"""Ozon E-CUP 2023 cards → the app's CSV: name and description as input, the card's characteristics as gold.

    python script/convert/ozon.py data/external/ozon_ecup2023/raw data/external/ozon_ecup2023

Writes train.csv / test.csv (70/30 by product id) for electronics and appliances, test_focus.csv with only
the categories in config/catalog.yml, and test_small.csv (1000 focus cards) for runs that ask a model.
Gold is partial: a key the seller left out is unknown, not empty — evaluate with GOLD=partial.
"""
import csv
import glob
import hashlib
import json
import sys
from pathlib import Path

import pandas as pd

GOLD = {
    "brand": ["Бренд"],
    "storage": ["Встроенная память", "Общий объем SSD, ГБ"],
    "ram": ["Оперативная память"],
    "screen_diagonal": ["Диагональ экрана, дюймы"],
    "battery": ["Емкость аккумулятора, мАч"],
    "color": ["Цвет товара"],
    "resolution": ["Разрешение экрана", "Разрешение"],
    "cpu": ["Модель процессора"],
    "refresh_rate": ["Макс. частота обновления, Гц"],
    "screen_type": ["Матрица монитора", "Технология матрицы"],
    "connection": ["Подключение"],
    "volume": ["Общий объем, л"],
    "load": ["Загрузка белья, кг"],
    "spin_speed": ["Максимальная скорость отжима, об./мин."],
    "power": ["Потребляемая мощность, Вт", "Мощность, Вт"],
}
UNITS = {"Общий объем SSD, ГБ": " ГБ", "Емкость аккумулятора, мАч": " мАч", "Общий объем, л": " л",
         "Загрузка белья, кг": " кг", "Максимальная скорость отжима, об./мин.": " об/мин",
         "Потребляемая мощность, Вт": " Вт", "Мощность, Вт": " Вт", "Макс. частота обновления, Гц": " Гц"}
NO_VALUE = {"нет бренда", "без бренда", "другая", "другой", "не указан", "не указана", ""}
FOCUS = {"Смартфон", "Ноутбук", "Планшет", "Телевизор", "Монитор", "Умные часы", "Наушники", "Холодильник",
         "Стиральная машина", "Бытовой пылесос"}


def gold(mapping):
    row = {}
    for attribute, keys in GOLD.items():
        for key in keys:
            values = mapping.get(key) or []
            value = str(values[0]).strip() if values else ""
            if value.lower() in NO_VALUE:
                continue
            row[attribute] = value + UNITS.get(key, "") if value.replace(".", "").isdigit() else value
            break
    return row


def write(path, rows):
    columns = ["id", "title", "description", "category"] + list(GOLD)
    with open(path, "w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, columns)
        writer.writeheader()
        writer.writerows(rows)
    print(f"{len(rows):6d} → {path}")


def main(source, output):
    columns = ["variantid", "name", "description", "categories", "characteristic_attributes_mapping"]
    files = sorted(glob.glob(f"{source}/**/*.parquet", recursive=True))
    frame = pd.concat([pd.read_parquet(file, columns=columns) for file in files])
    frame = frame.drop_duplicates("variantid")
    rows = []
    for record in frame.itertuples():
        categories = json.loads(record.categories)
        if categories.get("2") not in ("Электроника", "Бытовая техника"):
            continue
        row = {"id": record.variantid, "title": record.name, "description": record.description or "",
               "category": categories.get("4") or categories.get("3") or ""}
        row.update(gold(json.loads(record.characteristic_attributes_mapping)))
        rows.append(row)

    output = Path(output)
    held = lambda row: int(hashlib.md5(str(row["id"]).encode()).hexdigest(), 16) % 10 < 3
    test = [row for row in rows if held(row)]
    focus = [row for row in test if row["category"] in FOCUS]
    write(output / "train.csv", [row for row in rows if not held(row)])
    write(output / "test.csv", test)
    write(output / "test_focus.csv", focus)
    write(output / "test_small.csv", sorted(focus, key=lambda row: hashlib.md5(str(row["id"]).encode()).hexdigest())[:1000])


if __name__ == "__main__":
    main(*sys.argv[1:3])
