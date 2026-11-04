"""Make a deterministic holdout without reusing an earlier development test.

    python3 script/split_holdout.py TRAIN.csv PREVIOUS_TEST.csv OUTPUT_PREFIX

Groups identical textual inputs before splitting (80/20). This is NOT a
product-disjoint split: different variants of one model may occur on both sides.
No labels are inspected when assigning the split. Input CSV uses canonical columns.
"""
import csv
import hashlib
import json
import sys
from pathlib import Path


def fingerprint(row):
    return tuple(row.get(key, "") for key in ("title", "description", "category"))


def split(source, previous, prefix):
    paths = [Path(f"{prefix}-{name}.csv") for name in ("train", "test")]
    manifest = Path(f"{prefix}-split.json")
    if any(path.exists() for path in [*paths, manifest]):
        raise ValueError("Output already exists; choose a new prefix")
    with open(previous, encoding="utf-8") as file:
        excluded = {fingerprint(row) for row in csv.DictReader(file)}
    with open(source, encoding="utf-8") as file:
        reader = csv.DictReader(file)
        fields = reader.fieldnames
        if not fields or not {"title", "description", "category"}.issubset(fields):
            raise ValueError("Expected title, description and category CSV columns")
        rows = list(reader)
    groups = [[], []]
    removed = 0
    for row in rows:
        key = fingerprint(row)
        if key in excluded:
            removed += 1
            continue
        digest = hashlib.sha256(json.dumps(key, ensure_ascii=False).encode()).hexdigest()
        groups[1 if int(digest, 16) % 5 == 0 else 0].append(row)
    if not all(groups):
        raise ValueError("Both partitions must contain cards")
    for path, items in zip(paths, groups):
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", newline="", encoding="utf-8") as file:
            writer = csv.DictWriter(file, fieldnames=fields)
            writer.writeheader()
            writer.writerows(items)
    result = {"source_sha256": hashlib.sha256(Path(source).read_bytes()).hexdigest(),
              "previous_test_sha256": hashlib.sha256(Path(previous).read_bytes()).hexdigest(),
              "excluded_rows": removed, "train_cards": len(groups[0]), "test_cards": len(groups[1]),
              "method": "SHA-256 of title/description/category, mod 5; no product-disjoint claim"}
    manifest.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: split_holdout.py TRAIN.csv PREVIOUS_TEST.csv OUTPUT_PREFIX")
    split(*sys.argv[1:])
