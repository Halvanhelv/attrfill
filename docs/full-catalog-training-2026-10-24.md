# Training on the full catalogue

Completed 2026-10-25T01:55:30Z. The training set contains **546,069 cards**: 440,732 cards from the main categories and 105,337 cards from rare categories. Rare-category cards were kept with their known manual attributes (including brand and model); unsupported fields were not added. The IDs of all prepared cards were reconciled with the source export: no duplicates and no losses. The input contains 9,795,403 attribute values; they come from the dataset's source fields, not from a separate manual check of gold labels.

Dictionaries, formats, calibration, the product reference and typical values were built on the whole set. The NER was trained with the standard algorithm: the first 40,000 cards in the reproducible order of the input file, up to 12,000 text examples per pass, five epochs. This is a sampling limit of the NER, not training the tagger on every text in the export. The fallback Transformer was not retrained. No LLM or paid services were used; parallel processing used three processes.

## Verification

The models were loaded in an isolated copy of the application. 2,000 cards were checked for schema compliance and confidence range, along with the basic smartphone scenario and protection against extracting the brand of a compatible device from an accessory. Rails tests and all 15 production HTTP scenarios passed. The new files are installed in `config/`; the previous ones are kept locally in `tmp/full-catalog-training-20261024/previous-config`.

**Independent F1 after full training has not been measured.** The previous TEST and TEST_NEW are included in the training set; generalisation quality cannot be computed on them. The F1 of **0.6657** from the [previous experiment](f1-improvement-2026-10-24.md) refers to the earlier split TRAIN/TEST run and different models. The interface may display saved results from that experiment.

The [training manifest](full-catalog-training-manifest.json) contains the input checksum, SHA-256 of all new model files, settings, the NER training scope, the source code files and the verification results. The source export and temporary training files are not included in the archive.

## Reproduction

From the project root, run the [preparation script](full-catalog-prepare.py). It creates a separate new folder, keeps all rare categories and reconciles IDs with the source. Re-preparing the current set was verified: the SHA-256 of `all.jsonl` matches the one used in training byte for byte. Then run training:

```sh
uv run --with pyarrow==26.0.0 --with pyyaml python docs/full-catalog-prepare.py RAW_DIR PREPARED_DIR

GOLD=partial LLM_MODE=off LEARN_WORKERS=3 RUBY_YJIT_ENABLE=1 \
  ruby bin/rails runner script/train_isolated.rb PREPARED_DIR/data/all.jsonl NEW_MODELS_DIR - PREPARED_DIR/config
```

The `NEW_MODELS_DIR` folder must be new. The `RAW_DIR` folder contains the source `skus.pkl` and `sku_desc.parquet`, or already unpacked `offers.jsonl`, `categories.json` and `sku_desc.parquet`. `PREPARED_DIR` must be new. Check new models separately before installing them. Detailed temporary logs of the current run are kept locally in `tmp/full-catalog-training-20261024`.

## Change in automation

The calibrated score of the `brand/title/dictionary` rule dropped from 0.999 to 0.673 when moving from pilot data to the full catalogue. This may enlarge the manual review queue at the existing 0.98 threshold. In the Samsung control card, the brand was extracted as `Samsung` with confidence 0.96 and status `review`. The previous models are kept for rollback and comparison. Full training by itself does not prove a quality improvement on new products.
