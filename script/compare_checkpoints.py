"""Compare complete NER on/off checkpoints with identical inputs and weights.

python3 script/compare_checkpoints.py WITHOUT_NER WITH_NER OUTPUT.json
"""
import hashlib
import json
import sys
from pathlib import Path


def read_run(directory):
    folder = Path(directory)
    manifest = json.loads((folder / "manifest.json").read_text())
    if not manifest.get("complete"):
        raise ValueError(f"Incomplete checkpoint: {folder}")
    for name in ("predictions.csv", "report.json"):
        actual = hashlib.sha256((folder / name).read_bytes()).hexdigest()
        if actual != manifest["output_sha256"][name]:
            raise ValueError(f"Output checksum mismatch: {folder / name}")
    return manifest, json.loads((folder / "report.json").read_text())


def compare(without_dir, with_dir):
    before, before_report = read_run(without_dir)
    after, after_report = read_run(with_dir)
    for key in ("cards", "acceptance_mode", "acceptance_policy", "partial_gold",
                "input_and_source_sha256", "ruby", "llm_mode"):
        if before[key] != after[key]:
            raise ValueError(f"Runs are not comparable: {key} differs")
    before_options = before["runtime_options"].copy()
    after_options = after["runtime_options"].copy()
    if before_options.pop("TAGGER", None) != "off":
        raise ValueError("First run must explicitly set TAGGER=off")
    if after_options.pop("TAGGER", "perceptron") != "perceptron":
        raise ValueError("Second run must use the perceptron")
    if before_options != after_options:
        raise ValueError("Options other than TAGGER differ")
    attributes = {}
    if before_report["attributes"].keys() != after_report["attributes"].keys():
        raise ValueError("Scored attributes differ")
    for name, new in after_report["attributes"].items():
        old = before_report["attributes"][name]
        if (old["gold"], old["cards"]) != (new["gold"], new["cards"]):
            raise ValueError(f"Scored population differs: {name}")
        attributes[name] = {"without_ner_f1": old["f1"], "with_ner_f1": new["f1"],
                            "net_correct_change": new["correct"] - old["correct"]}
    return {"cards": after["cards"], "without_ner": before_report["totals"],
            "with_ner": after_report["totals"], "attributes": attributes,
            "net_correct_change": sum(a["net_correct_change"] for a in attributes.values()),
            "scope": "Paired local diagnostic; same weights and inputs, only TAGGER changes. "
                     "Development data, partial labels; not a blind or official score."}


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    destination = Path(sys.argv[3])
    if destination.exists():
        raise SystemExit(f"Refusing to overwrite: {destination}")
    result = compare(sys.argv[1], sys.argv[2])
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
