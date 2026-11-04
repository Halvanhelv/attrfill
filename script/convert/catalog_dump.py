"""Acme Retail catalog dump (catalog_dump: skus.pkl + sku_desc.parquet) → the app's CSV.

    python script/convert/catalog_dump.py data/catalog_dump data/catalog_dump [PER_CATEGORY|all]

skus.pkl is converted once into offers.jsonl and categories.json next to it (loading the pickle takes a minute).
Input is the offer's name, its description and its category; gold is vendor, model and the exact `*_search`
parameters (the parameters without the suffix are filter buckets such as "from 27\" to 29\"").
Writes train.csv / test.csv (80/20 by offer id) for the categories in config/catalog.yml, and test_new.csv:
the test cards of products none of whose variants are in train. all.csv holds every card: what bin/learn
learns from before the autorun.
"""
import csv
import hashlib
import json
import pickle
import re
import sys
from collections import defaultdict
from pathlib import Path

import pyarrow.parquet as pq

# Category id → catalog category; several shop categories may feed one.
CATEGORIES = {
    "761": "smartphone", "914": "smartphone", "987": "laptop", "930": "tablet", "1682": "tv", "1263": "monitor",
    "1233": "smartwatch", "31607": "headphones", "666": "refrigerator", "2447": "washing_machine",
    "2455": "vacuum", "3088": "vacuum", "2457": "vacuum",
}
# Attribute → parameters, first present wins.
GOLD = {
    "storage": ["Встроенная память (ROM)_search", "Объём SSD"],
    "ram": ["Оперативная память (RAM)_search"],
    "screen_diagonal": ["Диагональ_search", "Диагональ экрана_search", "Диагональ/разрешение_search"],
    "battery": ["Емкость аккумулятора_search"],
    "color": ["Цвет_search"],
    "cpu": ["Процессор_search"],
    "refresh_rate": ["Частота обновления_search"],
    "screen_type": ["Тип матрицы_search"],
    "connection": ["Тип подключения наушников_search"],
    "volume": ["Общий объем_search"],
    "load": ["Максимальная загрузка_search"],
    "spin_speed": ["Максимальная скорость отжима_search"],
    "power": ["Потребляемая мощность_search", "Максимальная потребляемая мощность_search"],
}
NO_VALUE = {"", "-", "нет", "отсутствует", "другие цвета", "прочие", "0"}
COLUMNS = ["id", "title", "description", "category", "brand", "model", "resolution", *GOLD]


def unpack(directory):
    path = directory / "offers.jsonl"
    if not path.exists():
        shop = pickle.load(open(directory / "skus.pkl", "rb"))["yml_catalog"]["shop"]
        (directory / "categories.json").write_text(json.dumps(shop["categories"]["category"], ensure_ascii=False))
        with open(path, "w") as file:
            for offer in shop["offers"]["offer"]:
                file.write(json.dumps(offer, ensure_ascii=False) + "\n")


def offers(directory):
    with open(directory / "offers.jsonl") as file:
        for line in file:
            yield json.loads(line)


def params(offer):
    found = offer.get("param") or []
    found = [found] if isinstance(found, dict) else found
    result = {}
    for param in found:
        text = (param.get("#text") or "").strip()
        unit = param.get("@unit", "")
        result.setdefault(param["@name"], text + ('"' if unit == '"' else f" {unit}" if unit else ""))
    return result


def clean(attribute, value):
    if attribute == "screen_diagonal":
        value = re.split(r"[/(]", value)[0].replace("''", '"').strip()
    elif attribute == "cpu":
        value = re.sub(r"\s+\d+(?:[.,]\d+)?\s*ГГц.*$", "", value).strip()
        # "Intel Core i5 Core i5-13420H": the catalog repeats the family before the processor.
        value = re.sub(r"\b(\w+(?: \w+){0,3}) (?=\1\b)", "", value)
    elif attribute == "storage":
        value = re.sub(r"^(?:SSD|HDD|eMMC)\s+", "", value.split("+")[0]).strip()
    return "" if value.lower() in NO_VALUE else value


def gold(offer, found):
    row = {"brand": offer.get("vendor") or "", "model": offer.get("model") or ""}
    width = found.get("Разрешение пo горизонтали_search", "").split(" ")[0]
    height = found.get("Разрешение по вертикали_search", "").split(" ")[0]
    if width.isdigit() and height.isdigit() and int(width) and int(height):
        row["resolution"] = f"{width}x{height}"
    for attribute, keys in GOLD.items():
        for key in keys:
            value = clean(attribute, found.get(key, ""))
            if value:
                row[attribute] = value
                break
    return row


# Vendor and the first two words of the model, colour and memory aside: one product, whatever the variant.
def product(row):
    words = re.findall(r"[a-zа-я0-9+]+", re.sub(r"\(.*?\)|\d+\s*/\s*\d+|\d+\s*(?:gb|гб|tb|тб)\b", " ", row["model"].lower()))
    return row["brand"].lower(), " ".join(words[:2])


def write(path, rows):
    with open(path, "w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"{len(rows):6d} → {path}")


def read_descriptions(path, ids):
    """Read only selected descriptions in bounded batches instead of materializing the full Parquet table."""
    found = {}
    parquet = pq.ParquetFile(path)
    for batch in parquet.iter_batches(columns=["sku_id", "description"], batch_size=65_536):
        for sku, text in zip(batch.column(0).to_pylist(), batch.column(1).to_pylist()):
            if sku in ids:
                found[sku] = text
    return found


def main(source, output, per_category="2000"):
    limit = None if per_category == "all" else int(per_category)
    source, output = Path(source), Path(output)
    output.mkdir(parents=True, exist_ok=True)
    unpack(source)
    names = {category["@id"]: category["#text"] for category in json.loads((source / "categories.json").read_text())}
    digest = lambda value: hashlib.md5(str(value).encode()).hexdigest()

    picked = defaultdict(list)
    for offer in offers(source):
        category = (offer.get("categories") or {}).get("categoryId")
        if category in CATEGORIES:
            picked[CATEGORIES[category]].append(offer)
    chosen = [offer for group in picked.values() for offer in sorted(group, key=lambda o: digest(o["@id"]))[:limit]]

    ids = {int(offer["@id"]) for offer in chosen}
    descriptions = read_descriptions(source / "sku_desc.parquet", ids)

    rows = []
    for offer in chosen:
        found = params(offer)
        row = {"id": offer["@id"], "title": offer.get("name", ""), "description": descriptions.get(int(offer["@id"]), ""),
               "category": names.get(offer["categories"]["categoryId"], "")}
        row.update(gold(offer, found))
        rows.append(row)

    held = lambda row: int(digest(row["id"]), 16) % 5 == 0
    train = [row for row in rows if not held(row)]
    test = [row for row in rows if held(row)]
    write(output / "all.csv", rows)
    write(output / "train.csv", train)
    write(output / "test.csv", test)
    # Products none of whose variants are in train: what known products cannot help with.
    known = {product(row) for row in train}
    write(output / "test_new.csv", [row for row in test if product(row) not in known])
    print(f"descriptions for {sum(bool(row['description']) for row in rows)} of {len(rows)}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
