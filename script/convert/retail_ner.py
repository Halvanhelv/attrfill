"""Acme Retail NER titles (example/retail-ner-data) → the app's CSV: title in, brand and model spans as gold.

    python script/convert/retail_ner.py data/external/retail_ner/raw data/external/retail_ner

Only product names are kept (not search queries). ner_gold (hand-labelled) → test.csv, ner_llm_silver → train.csv.
"""
import csv
import json
import sys
from pathlib import Path


def convert(source, target):
    rows = []
    for number, line in enumerate(Path(source).read_text(encoding="utf-8").splitlines()):
        record = json.loads(line)
        if record["source"] != "name":
            continue
        spans = {}
        for start, stop, label in record["spans"]:
            spans.setdefault(label, record["text"][start:stop])
        rows.append({"id": f"mv{number}", "title": record["text"], "category": spans.get("TYPE", ""),
                     "brand": spans.get("BRAND", ""), "model": spans.get("MODEL", "")})
    with open(target, "w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, ["id", "title", "category", "brand", "model"])
        writer.writeheader()
        writer.writerows(rows)
    print(f"{len(rows):6d} → {target}")


if __name__ == "__main__":
    source, output = Path(sys.argv[1]), Path(sys.argv[2])
    convert(source / "ner_gold.jsonl", output / "test.csv")
    convert(source / "ner_llm_silver.jsonl", output / "train.csv")
