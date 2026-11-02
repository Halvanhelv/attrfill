"""The whole Acme Retail catalog (catalog_dump) → a catalog of its categories and the cards to learn and test on.

    python script/convert/catalog_full.py data/catalog_dump data/catalog_dump/catalog

Run script/convert/catalog_dump.py first (it unpacks skus.pkl). Every shop category with MIN_OFFERS offers or more that
config/catalog.yml does not describe becomes a category of its own; its fields are the `*_search` parameters most
of its offers have. A field's kind is told by its values: a number with a unit (quantity), one of a short list
(dictionary), anything else, yes/no included, free (taken from known products, the seller, the category's usual
value or the model).
Writes config/catalog.full.yml, config/dictionaries/catalog/*.yml and all/train/test/test_new.jsonl.
"""
import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import yaml

from catalog_dump import CATEGORIES, GOLD, NO_VALUE, clean, gold, offers, params, product, read_descriptions

MIN_OFFERS = 300
MIN_SHARE = 0.3
MAX_LISTED = 300
SKIPPED = {"Модель_search", "Бренд_search", "Гарантия_search", "Гарантия предоставляется_search"}
HAND = {key: attribute for attribute, keys in GOLD.items() for key in keys}
NUMBER = re.compile(r"\d+(?:[.,]\d+)?")
# The same unit as products write it in Latin letters.
LATIN = {"мм": "mm", "см": "cm", "м": "m", "г": "g", "кг": "kg", "л": "l", "мл": "ml", "вт": "w", "квт": "kw",
         "гц": "hz", "мгц": "mhz", "ггц": "ghz", "мач": "mah", "дб": "db", "в": "v", "а": "a", "гб": "gb", "тб": "tb",
         "об/мин": "rpm", "ч": "h", "мин": "min", "шт": "pcs", "дюйм": "inch"}
LETTERS = dict(zip("абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
                   "a b v g d e e zh z i y k l m n o p r s t u f h ts ch sh sch _ y _ e yu ya".split()))
digest = lambda value: hashlib.md5(str(value).encode()).hexdigest()


def slug(title):
    words = re.findall(r"[a-zа-яё0-9]+", title.lower().replace("_search", ""))
    return "_".join("".join(LETTERS.get(letter, letter) for letter in word).replace("_", "") for word in words)[:40]


def kind(values, units):
    counted = sum(values.values())
    unit = units.most_common(1)[0][0].strip()
    numbers = [float(value.replace(",", ".")) for value in values if NUMBER.fullmatch(value)]
    if sum(seen for value, seen in values.items() if NUMBER.fullmatch(value)) >= 0.9 * counted:
        if not unit:
            return {"kind": "free"}
        names = [unit.lower(), *([LATIN[unit.lower()]] if unit.lower() in LATIN else [])]
        return {"kind": "quantity", "units": names, "range": [round(min(numbers) / 2, 3), round(max(numbers) * 2, 3)],
                "format": {"suffix": unit if unit == '"' else f" {unit}"}}
    listed = [value for value, seen in values.items() if seen >= 2]
    yes_no = {value.lower() for value in values} <= {"да", "нет"}
    if not yes_no and len(listed) <= MAX_LISTED and sum(values[value] for value in listed) >= 0.9 * counted:
        return {"kind": "dictionary", "values": sorted(listed)}
    return {"kind": "free"}


# A one-word adjective is listed by its stem, to be found in any of its endings (the stem followed by "~").
def forms(value):
    stem = re.fullmatch(r"([а-я]{3,})(?:ый|ий|ой|ая|ое|ые)", value.lower())
    return [f"{stem[1]}~"] if stem else []


def raw(offer):
    found = offer.get("param") or []
    found = [found] if isinstance(found, dict) else found
    return {param["@name"]: ((param.get("#text") or "").strip(), param.get("@unit", "")) for param in reversed(found)}


def main(source, output):
    source, output = Path(source), Path(output)
    names = {category["@id"]: category["#text"] for category in json.loads((source / "categories.json").read_text())}

    counts = Counter((offer.get("categories") or {}).get("categoryId") for offer in offers(source))
    # Shop categories of one name are one category: a card names its category by name.
    groups = defaultdict(list)
    for category, seen in counts.items():
        if category and category not in CATEGORIES and seen >= MIN_OFFERS:
            groups[names.get(category, category)].append(category)
    group_of = {category: title for title, categories in groups.items() for category in categories}

    present = defaultdict(Counter)
    values = defaultdict(Counter)
    units = defaultdict(Counter)
    for offer in offers(source):
        title = group_of.get(offer["categories"].get("categoryId") if offer.get("categories") else None)
        if not title:
            continue
        for key, (text, unit) in raw(offer).items():
            if key.endswith("_search") and key not in SKIPPED:
                present[title][key] += 1
                if text.lower() not in NO_VALUE:
                    values[key][text] += 1
                    units[key][unit] += 1

    attributes, named, dictionaries = {}, {}, {}
    # A yes/no field keeps its "no": without it every card would seem to have the feature.
    yes_no = {key for key, seen in values.items() if {value.lower() for value in seen} == {"да"}}
    taken = {"brand", "model", "resolution", *GOLD}
    for key in sorted({key for found in present.values() for key in found}):
        if key in HAND or not values[key]:
            continue
        name = slug(key)
        while name in taken:
            name += "_"
        taken.add(name)
        named[key] = name
        described = kind(values[key], units[key])
        listed = described.pop("values", None)
        if listed:
            described["dictionary"] = f"catalog/{name}"
            dictionaries[name] = listed
        attributes[name] = {"title": key.removesuffix("_search"), **described, "generated": True,
                            "seller_keys": [key.removesuffix("_search").lower()]}

    categories = {}
    for title, categories_of in groups.items():
        total = sum(counts[category] for category in categories_of)
        fields = [key for key, seen in present[title].most_common() if seen >= MIN_SHARE * total]
        chosen = [HAND.get(key) or named.get(key) for key in fields]
        chosen = list(dict.fromkeys(["brand", "model", *[name for name in chosen if name]]))
        categories[f"catalog_{min(categories_of, key=int)}"] = {"title": title, "keywords": [], "attributes": chosen}

    used = {name for category in categories.values() for name in category["attributes"]}
    for name in used & dictionaries.keys():
        path = Path("config/dictionaries/catalog") / f"{name}.yml"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump({value: forms(value) for value in dictionaries[name]}, allow_unicode=True, sort_keys=False))
    catalog = {"categories": categories, "attributes": {name: spec for name, spec in attributes.items() if name in used}}
    Path("config/catalog.full.yml").write_text(
        "# Generated by script/convert/catalog_full.py from the Acme Retail catalog; config/catalog.yml wins over it.\n" +
        yaml.safe_dump(catalog, allow_unicode=True, sort_keys=False, width=200))
    print(f"{len(categories)} categories, {len(catalog['attributes'])} attributes → config/catalog.full.yml")

    rows = []
    for offer in offers(source):
        category = (offer.get("categories") or {}).get("categoryId")
        if category not in CATEGORIES and category not in group_of:
            continue
        found = params(offer)
        row = {"id": offer["@id"], "title": offer.get("name", ""), "category": names.get(category, "")}
        labels = gold(offer, found)
        if category in group_of:
            wanted = set(categories[f"catalog_{min(groups[group_of[category]], key=int)}"]["attributes"])
            labels = {"brand": labels["brand"], "model": labels["model"]}
            for key, value in found.items():
                name = HAND.get(key) or named.get(key)
                value = "Нет" if key in yes_no and value.lower() == "нет" else clean(name, value) if name else ""
                if name in wanted and value and name not in labels:
                    labels[name] = value
        row.update({name: value for name, value in labels.items() if value})
        rows.append(row)
    rows.sort(key=lambda row: digest(row["id"]))

    ids = {int(row["id"]) for row in rows}
    descriptions = read_descriptions(source / "sku_desc.parquet", ids)
    for row in rows:
        row["description"] = descriptions.get(int(row["id"]), "")

    output.mkdir(parents=True, exist_ok=True)
    held = lambda row: int(digest(row["id"]), 16) % 5 == 0
    train = [row for row in rows if not held(row)]
    test = [row for row in rows if held(row)]
    naming = lambda row: product({"brand": row.get("brand", ""), "model": row.get("model", "")})
    known = {naming(row) for row in train}
    for name, part in [("all", rows), ("train", train), ("test", test),
                       ("test_new", [row for row in test if naming(row) not in known])]:
        with open(output / f"{name}.jsonl", "w") as file:
            file.writelines(json.dumps(row, ensure_ascii=False) + "\n" for row in part)
        print(f"{len(part):7d} → {output / name}.jsonl")


if __name__ == "__main__":
    main(*sys.argv[1:3])
