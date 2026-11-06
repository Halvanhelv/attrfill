"""Train conditional attribute priors and export a Python-free Ruby artifact.

Input JSONL is produced by script/context/export.rb using training cards only.
  uv run --with scikit-learn==1.9.1 python script/context/train.py \
    TRAIN.jsonl context.json.gz --policy context-policy.json
"""
import argparse
import collections
import gzip
import hashlib
import json
import re
import time
import unicodedata
from pathlib import Path

import numpy as np
import sklearn
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import SGDClassifier
from sklearn.svm import LinearSVC
from scipy.sparse import csr_matrix
from scipy.special import expit

ALPHAS = {'sgd-a000001': 0.000001, 'sgd-a00001': 0.00001, 'sgd-a0001': 0.0001, 'sgd-a0003': 0.0003, 'sgd-a001': 0.001}


def features(row, description_chars):
    result = []
    for source, text, repeats in [('t', row['title'], 3), ('d', row['description'][:description_chars], 1)]:
        text = ' '.join(unicodedata.normalize('NFKC', text).lower().replace('ё', 'е').split())
        words = re.findall('[a-zа-я0-9]+', text)[:300]
        found = [source + ':w:' + word for word in words]
        found += [source + ':b:' + a + '/' + b for a, b in zip(words, words[1:])]
        for word in words:
            token = '<' + word[:40] + '>'
            for size in (3, 4, 5):
                found.extend(source + ':' + token[i:i + size] for i in range(len(token) - size + 1))
        result.extend(found * repeats)
    return result


def compress_coefficients(coefficients, activation, terms):
    if terms < 1:
        raise ValueError('Coefficient limit must be positive')
    center = coefficients.mean(axis=0)
    columns, values, offsets = [], [], [0]
    for row in coefficients:
        delta = row - center
        if terms >= len(delta):
            keep = np.flatnonzero(delta)
        else:
            keep = np.argpartition(np.abs(delta), -terms)[-terms:]
            keep = np.sort(keep[delta[keep] != 0])
        columns.append(keep.astype(np.int32))
        values.append(delta[keep])
        offsets.append(offsets[-1] + len(keep))
    sparse = csr_matrix((np.concatenate(values), np.concatenate(columns), np.array(offsets)), shape=coefficients.shape)
    common = center if activation == 'sigmoid_normalize' else np.zeros_like(center)
    return sparse, common


def score_predictions(scores, classes, activation):
    if activation == 'margin' and scores.shape[1] > 1:
        order = np.argsort(scores, axis=1)
        winners = order[:, -1]
        gaps = scores[np.arange(len(winners)), winners] - scores[np.arange(len(winners)), order[:, -2]]
        confidence = expit(gaps)
    else:
        probability = expit(scores) if activation == 'sigmoid_normalize' else np.exp(scores - scores.max(axis=1)[:, None])
        probability /= probability.sum(axis=1)[:, None]
        winners = probability.argmax(axis=1)
        confidence = probability[np.arange(len(winners)), winners]
    return [(str(classes[index]), float(score)) for index, score in zip(winners, confidence)]


def predictions(estimator, matrix, classes):
    if estimator is None:
        return [(str(classes[0]), 1.0)] * matrix.shape[0]
    if isinstance(estimator, LinearSVC):
        scores = estimator.decision_function(matrix)
        if scores.ndim == 1:
            scores = np.column_stack((-scores, scores))
        rank = np.argsort(scores, axis=1)
        winners = rank[:, -1]
        gaps = scores[np.arange(len(winners)), winners] - scores[np.arange(len(winners)), rank[:, -2]]
        confidence = 1 / (1 + np.exp(-gaps))
    else:
        probability = estimator.predict_proba(matrix)
        winners = probability.argmax(axis=1)
        confidence = probability[np.arange(len(winners)), winners]
    return [(str(classes[index]), float(score)) for index, score in zip(winners, confidence)]


def build(rows, selection, queries=None, progress=False, terms=None):
    chosen = {name: value for name, value in selection.items() if name not in ('brand', 'model') and value['method'] != 'baseline'}
    result = {'version': 1, 'spaces': {}, 'models': {}, 'metadata': {
        'training_cards': len(rows), 'training_ids_sha256': hashlib.sha256(json.dumps(sorted(str(r['id']) for r in rows), separators=(',', ':')).encode()).hexdigest(),
        'selection_sha256': hashlib.sha256(json.dumps(selection, sort_keys=True, ensure_ascii=False).encode()).hexdigest(),
        'sklearn': sklearn.__version__, 'numpy': np.__version__, 'minimum_rows': 8,
        'scope': 'Input-only text features, labels from training cards only; guesses always require human review.'}}
    checks = [{key: row[key] for key in ('title', 'description', 'category')} | {'expected': {}} for row in (queries or [])]
    for limit in sorted({int(spec['desc_chars']) for spec in chosen.values()}):
        space_id = str(limit)
        vectorizer = TfidfVectorizer(analyzer=lambda row, n=limit: features(row, n), min_df=2, max_features=60000, dtype=np.float32, lowercase=False)
        matrix = vectorizer.fit_transform(rows)
        matrix.sort_indices()
        query_matrix = vectorizer.transform(queries) if queries else None
        space = {'description_chars': limit, 'features': vectorizer.get_feature_names_out().tolist(), 'idf': vectorizer.idf_.astype(float).tolist()}
        result['spaces'][space_id] = space
        if progress:
            print(json.dumps({'stage': 'features', 'description_chars': limit, 'shape': matrix.shape, 'nonzero': matrix.nnz}), flush=True)
        for category in sorted({r['category'] for r in rows if r['category'] != 'generic'}):
            category_rows = [i for i, row in enumerate(rows) if row['category'] == category]
            neighbor_fields = []
            for name, policy in chosen.items():
                if int(policy['desc_chars']) != limit:
                    continue
                indices = np.array([i for i in category_rows if name in rows[i]['attributes'] and rows[i]['labels'].get(name)], dtype=int)
                if len(indices) < 8:
                    continue
                labels = np.array([rows[i]['labels'][name] for i in indices])
                classes = np.unique(labels)
                method = policy['method']
                model = {key: policy[key] for key in ('threshold', 'replace_prior')}
                model.update(space=space_id, confidence=float(policy.get('confidence', 0.5)), training_rows=len(indices))
                relevant_queries = [i for i, row in enumerate(queries or []) if row['category'] == category]
                if method.startswith('knn'):
                    model.update(method='knn', k=int(method[3:]))
                    neighbor_fields.append(name)
                    if relevant_queries:
                        similarities = (query_matrix[relevant_queries] @ matrix[indices].T).toarray()
                        for q, sims in zip(relevant_queries, similarities):
                            ranking = sims.astype(np.float64) + np.arange(len(sims)) * 1e-12
                            top = np.argsort(ranking)[-min(model['k'], len(indices)):][::-1]
                            votes = collections.defaultdict(float)
                            for pos in top:
                                votes[str(labels[pos])] += max(0, float(sims[pos])) ** 3
                            if sum(votes.values()) > 0:
                                value, mass = max(votes.items(), key=lambda item: (item[1], item[0]))
                                score = float(sims[top[0]]) * mass / sum(votes.values())
                                if score >= policy['threshold']:
                                    checks[q]['expected'][name] = {'value': value, 'score': score}
                else:
                    estimator = None
                    if len(classes) > 1:
                        if method in ALPHAS:
                            estimator = SGDClassifier(loss='log_loss', alpha=ALPHAS[method], max_iter=200, tol=1e-4, random_state=7, n_jobs=1)
                        elif method in ('svc1', 'svc10', 'svc100'):
                            estimator = LinearSVC(C=int(method[3:]), random_state=7, max_iter=2000)
                        else:
                            raise ValueError('Unknown predictor: ' + method)
                        estimator.fit(matrix[indices], labels)
                        classes = estimator.classes_
                        coefficients = estimator.coef_.astype(float)
                        intercepts = estimator.intercept_.astype(float)
                        activation = 'margin' if isinstance(estimator, LinearSVC) else 'sigmoid_normalize'
                        if len(classes) == 2:
                            scale = 1 if activation == 'margin' else 0.5
                            coefficients = np.vstack((-coefficients[0] * scale, coefficients[0] * scale))
                            intercepts = np.array([-intercepts[0] * scale, intercepts[0] * scale])
                            if activation != 'margin':
                                activation = 'softmax'
                        active = np.flatnonzero(np.any(coefficients != 0, axis=0))
                        weights = {str(int(i)): coefficients[:, i].tolist() for i in active}
                    else:
                        activation, weights, intercepts = 'softmax', {}, np.zeros(1)
                        coefficients = np.zeros((1, matrix.shape[1]))
                    model.update(method='linear', activation=activation, classes=classes.tolist(), weights=weights, intercepts=intercepts.tolist())
                    compressed = common = None
                    if terms is not None and int(policy.get('terms', terms)) > 0:
                        limit_terms = int(policy.get('terms', terms))
                        compressed, common = compress_coefficients(coefficients, activation, limit_terms)
                        by_feature = compressed.tocsc()
                        sparse_weights = {}
                        for feature in np.flatnonzero(np.diff(by_feature.indptr)):
                            start, end = by_feature.indptr[feature:feature + 2]
                            sparse_weights[str(int(feature))] = [[int(index), float(weight)] for index, weight in zip(by_feature.indices[start:end], by_feature.data[start:end])]
                        model.update(weight_format='sparse', weights=sparse_weights, max_terms_per_class=limit_terms,
                                     common_weights={str(int(index)): float(common[index]) for index in np.flatnonzero(common)})
                    if relevant_queries:
                        if compressed is None:
                            values = predictions(estimator, query_matrix[relevant_queries], classes)
                        else:
                            scores = (query_matrix[relevant_queries] @ compressed.T).toarray() + intercepts
                            scores += np.asarray(query_matrix[relevant_queries] @ common).reshape(-1, 1)
                            values = score_predictions(scores, classes, activation)
                        for q, (value, score) in zip(relevant_queries, values):
                            if query_matrix[q].nnz and np.isfinite(score) and score >= policy['threshold']:
                                checks[q]['expected'][name] = {'value': value, 'score': score}
                result['models'].setdefault(category, {})[name] = model
            if neighbor_fields:
                corpus = []
                for i in category_rows:
                    values = {name: rows[i]['labels'][name] for name in neighbor_fields if name in rows[i]['attributes'] and rows[i]['labels'].get(name)}
                    if values:
                        vector = matrix[i]
                        corpus.append({'values': values, 'vector': [[int(index), float(value)] for index, value in zip(vector.indices, vector.data)]})
                space.setdefault('neighbors', {})[category] = corpus
            if progress:
                print(json.dumps({'stage': 'category', 'space': space_id, 'category': category}), flush=True)
    if queries:
        result['checks'] = checks
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--policy', type=Path, required=True)
    parser.add_argument('--terms', type=int, default=2048, help='Maximum residual terms per class; 0 exports the original dense model')
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Choose a new output file')
    rows = [json.loads(line) for line in args.input.open() if line.strip()]
    policy = json.loads(args.policy.read_text())
    policy = policy.get('best_by_attribute', policy)
    positions = sorted({int(i) for i in np.linspace(0, len(rows) - 1, min(48, len(rows)))})
    queries = [rows[i] for i in positions]
    started = time.monotonic()
    artifact = build(rows, policy, queries, progress=True, terms=args.terms or None)
    artifact['metadata'].update(input_sha256=hashlib.sha256(args.input.read_bytes()).hexdigest(), policy_file_sha256=hashlib.sha256(args.policy.read_bytes()).hexdigest(),
                                trainer_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), seconds=round(time.monotonic() - started, 2))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + '.tmp')
    with gzip.open(temporary, 'wt', encoding='utf-8', compresslevel=5) as stream:
        json.dump(artifact, stream, ensure_ascii=False, separators=(',', ':'), allow_nan=False)
    temporary.replace(args.output)
    print(json.dumps({'complete': True, 'training_cards': len(rows), 'models': sum(len(v) for v in artifact['models'].values()), 'bytes': args.output.stat().st_size, 'seconds': artifact['metadata']['seconds']}), flush=True)


if __name__ == '__main__':
    main()
