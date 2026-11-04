"""Group the local development pool by approximate product family and exact input.

python3 script/readiness_split.py [--strict] TRAIN.csv TEST.csv OUTPUT_DIR

This creates a diagnostic holdout, not a new blind dataset. Product families are
heuristic: category + brand + first two model tokens after removing memory.
"""
import csv
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path


def make_split(first, second, output):
    output = Path(output)
    names = ['family-train.csv', 'family-test.csv', 'family-split.json']
    if any((output / name).exists() for name in names):
        raise ValueError('Choose a new output directory; split files already exist')
    output.mkdir(parents=True, exist_ok=True)
    rows = []
    for path in [first, second]:
        with open(path) as file:
            reader = csv.DictReader(file)
            fields = reader.fieldnames
            rows.extend(reader)

    def input_key(row):
        return tuple(row.get(key, '') for key in ['title', 'description', 'category'])

    def family(row):
        model = re.sub(r'\(.*?\)|\d+\s*/\s*\d+|\d+\s*(?:gb|гб|tb|тб)\b', ' ', row['model'].lower())
        words = re.findall(r'[a-zа-я0-9+]+', model)
        return row['category'], row['brand'].lower(), ' '.join(words[:2])

    parent = {}

    def find(key):
        parent.setdefault(key, key)
        if parent[key] != key:
            parent[key] = find(parent[key])
        return parent[key]

    colors = r'\b(?:черн\w*|бел\w*|сер\w*|синий|синяя|голуб\w*|красн\w*|зел[её]н\w*|розов\w*|фиолет\w*|ж[её]лт\w*|золот\w*|серебр\w*|графит\w*|бежев\w*|black|white|gr[ae]y|blue|red|green|pink|purple|gold|silver|midnight|starlight)\b'

    def extra_keys(row):
        """--strict: also join cards that share a model code or a title without colour and memory."""
        model = re.sub(r'\(.*?\)|\d+\s*/\s*\d+|\d+\s*(?:gb|гб|tb|тб)\b', ' ', row['model'].lower())
        model = re.sub(colors, ' ', model)
        codes = [word for word in re.findall(r'[a-zа-я0-9+-]+', model) if re.search(r'\d', word) and len(word) >= 3]
        title = re.sub(r'\d+\s*/\s*\d+|\d+\s*(?:gb|гб|tb|тб)\b', ' ', row['title'].lower())
        title = ' '.join(re.findall(r'[a-zа-я0-9+]+', re.sub(colors, ' ', title))[:5])
        keys = [('title', row['category'], title)]
        if codes:
            keys.append(('code', row['category'], row['brand'].lower(), codes[0]))
        return keys

    for row in rows:
        parent[find(('family', *family(row)))] = find(('input', *input_key(row)))
        if STRICT:
            for key in extra_keys(row):
                parent[find(key)] = find(('family', *family(row)))
    groups = {}
    for row in rows:
        groups.setdefault(find(('family', *family(row))), []).append(row)
    train, test = [], []
    for group, items in sorted(groups.items()):
        digest = hashlib.sha256(json.dumps(group, ensure_ascii=False).encode()).hexdigest()
        (test if int(digest, 16) % 5 == 0 else train).extend(items)
    assert not ({family(row) for row in train} & {family(row) for row in test})
    if STRICT:
        assert not ({key for row in train for key in extra_keys(row)} & {key for row in test for key in extra_keys(row)})
    assert not ({input_key(row) for row in train} & {input_key(row) for row in test})
    for name, items in [('train', train), ('test', test)]:
        with (output / f'family-{name}.csv').open('w', newline='') as file:
            writer = csv.DictWriter(file, fieldnames=fields)
            writer.writeheader()
            writer.writerows(items)
    manifest = {'rows': len(rows), 'train': len(train), 'test': len(test), 'family_groups': len(groups),
                'family_overlap': 0, 'exact_input_overlap': 0,
                'test_categories': dict(Counter(row['category'] for row in test)),
                'input_sha256': {str(path): hashlib.sha256(Path(path).read_bytes()).hexdigest()
                                 for path in [first, second]},
                'definition': ('category + brand + first two model tokens, memory removed; input duplicates unioned; '
                               + ('also unioned by brand + first model code and by the first five title words without colour '
                                  'and memory (--strict); ' if STRICT else '') + 'development data')}
    (output / 'family-split.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
    print(json.dumps(manifest, ensure_ascii=False))


STRICT = '--strict' in sys.argv

if __name__ == '__main__':
    arguments = [argument for argument in sys.argv[1:] if argument != '--strict']
    if len(arguments) != 3:
        raise SystemExit('usage: readiness_split.py [--strict] TRAIN.csv TEST.csv OUTPUT_DIR')
    make_split(*arguments)
