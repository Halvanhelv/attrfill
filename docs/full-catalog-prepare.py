"""Prepare every source offer without changing the project's active config.

  uv run --with pyarrow==26.0.0 --with pyyaml \
    python docs/full-catalog-prepare.py RAW_DIR NEW_OUTPUT_DIR

RAW_DIR contains sku_desc.parquet and either skus.pkl or cached offers.jsonl +
categories.json. NEW_OUTPUT_DIR must not exist. Generated catalog files go to
NEW_OUTPUT_DIR/config; the complete input goes to NEW_OUTPUT_DIR/data/all.jsonl.
"""
import argparse
import hashlib
import heapq
import json
import os
import sys
from collections import Counter
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('raw', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    source, output = args.raw.resolve(), args.output.resolve()
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'script/convert'))
    import catalog
    import catalog_full as catalog

    if output.exists():
        parser.error('Choose a new output directory')
    catalog.unpack(source)
    source_ids = set()
    counts = Counter()
    for offer in catalog.offers(source):
        key = str(offer['@id'])
        if key in source_ids:
            raise ValueError('Duplicate source id: ' + key)
        source_ids.add(key)
        counts[(offer.get('categories') or {}).get('categoryId')] += 1
    expected = len(source_ids)
    output.mkdir(parents=True)
    (output / 'config').mkdir()
    os.chdir(output)
    data = output / 'data'
    catalog.main(source, data)
    names = {row['@id']: row['#text'] for row in json.loads((source / 'categories.json').read_text())}
    extra = []
    for offer in catalog.offers(source):
        category = (offer.get('categories') or {}).get('categoryId')
        if category in catalog.CATEGORIES or (category and counts.get(category, 0) >= catalog.MIN_OFFERS):
            continue
        row = {'id': offer['@id'], 'title': offer.get('name', ''), 'category': names.get(category, '')}
        row.update({key: value for key, value in catalog.gold(offer, catalog.params(offer)).items() if value})
        extra.append(row)
    ids = {int(row['id']) for row in extra if str(row['id']).isdigit()}
    descriptions = catalog.read_descriptions(source / 'sku_desc.parquet', ids)
    for row in extra:
        row['description'] = descriptions.get(int(row['id']), '') if str(row['id']).isdigit() else ''
    extra.sort(key=lambda row: catalog.digest(row['id']))
    frequent = data / 'all.frequent.jsonl'
    complete = data / 'all.jsonl'
    complete.rename(frequent)
    count = 0
    with frequent.open(encoding='utf-8') as stream, complete.open('w', encoding='utf-8') as target:
        for row in heapq.merge((json.loads(line) for line in stream), extra, key=lambda row: catalog.digest(row['id'])):
            key = str(row['id'])
            if key not in source_ids:
                raise ValueError('Unexpected or duplicate prepared id: ' + key)
            source_ids.remove(key)
            target.write(json.dumps(row, ensure_ascii=False) + '\n')
            count += 1
    assert count == expected and not source_ids
    with complete.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    manifest = {'cards': count, 'frequent_cards': count - len(extra), 'rare_cards': len(extra),
                'input_sha256': digest, 'input_bytes': complete.stat().st_size,
                'source_ids_equal_prepared_ids': True,
                'scope': 'Every raw offer retained. Rare categories retain known manual labels, including brand/model. No unsupported attributes are invented.'}
    (output / 'dataset-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(manifest, ensure_ascii=False), flush=True)
    print('Existing train/test/test_new files describe the frequent subset; all.jsonl is the complete final-training input.', flush=True)


if __name__ == '__main__':
    main()
