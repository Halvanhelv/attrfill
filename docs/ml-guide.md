# Neural networks in the project: a short guide

For anyone joining the ML part. What we have, where it lives, what to read.

## The task in ML terms

From the card text (title, description), extract field values: brand, model, memory, colour, etc.
This is **NER** (Named Entity Recognition) — labelling the words of a text:
each word gets a label `B-brand` (start of a brand), `I-brand` (continuation), `O` (nothing).
The labelling scheme is called **BIO**.

```
Smartphone  Samsung  Galaxy   S24      12/256GB
O           B-brand  B-model  I-model  O
```

## Where models sit in the pipeline

A card passes through steps; each one takes only what the previous ones did not resolve:

| Step | What it is | Code |
|---|---|---|
| 1. Rules and dictionaries | regexes and reference lists, no ML | `app/models/extraction/kinds/` |
| 2. NER tagger | trainable model, see below | `app/models/extraction/tagger/` |
| 3. Product reference | values from variants of the same product, no ML | `app/models/extraction/reference.rb` |
| 3a. Typical category value | the most frequent value of the field in the category, if most cards have it; no ML | `app/models/extraction/prior.rb` |
| 4. LLM | large language model via API, only for what is left | `app/models/extraction/llm_fallback.rb`, `app/prompts/` |
| 5. Human | everything we are not confident about | "Review" screen |

## Two NER models (interchangeable)

**Perceptron** — the default (`tagger/perceptron.rb`). A simple linear classifier: for each word
it computes features (the word itself, its neighbours, the "Xx9" shape, the category, the previous label) and picks the label
with the highest weight. Trains in minutes in pure Ruby, runs in ~1 ms per text.

**rubert-tiny2** — the fallback (`tagger/transformer.rb`, `script/ner/train.py`). A small BERT for the Russian
language, fine-tuned on our examples in PyTorch and exported to **ONNX** so it can run
from Ruby without Python. Quality is the same as the perceptron, but it is 1.6 times slower, so it is not the main one.
Enabled with `TAGGER=transformer`.

## Where the training data comes from

We have no word-level labels — only the correct field values for each card. Examples are built
automatically (`tagger/examples.rb`): we find the correct value in the text and label those words.
This is **distant supervision** (weak labelling).

## Confidence and calibration

Every value has a confidence. It is not the model's "feeling" but the measured share of correct answers
of that rule or model on a **held-out sample** (every fifth card is excluded from training).
Below the 0.8 threshold a value goes to a human. Code: `learner.rb`, output: `config/calibration.yml`.

## LLM

We only ask about fields that were not found and for which the text contains a hint. The model must
quote the place in the card; no quote — the value is not accepted (protection against hallucinations).
The answer must strictly follow a JSON schema (`app/schemas/`). The provider and model are set in `.env`.

## How to run

```bash
bin/learn data/train.csv                         # train the perceptron, dictionaries, calibration, reference
bin/compare TRAIN TEST rules,perceptron+ref      # compare variants on held-out data
bin/errors TEST brand                            # inspect errors for a field
# rubert-tiny2:
bin/rails 'extraction:tagger_examples[TRAIN,tmp/examples.jsonl]'
python script/ner/train.py tmp/examples.jsonl config/tagger/transformer
```

The metric is **macro-F1**: F1 (the harmonic mean of precision and recall) for each field, then averaged across fields.

## What to study (in order)

1. Precision, recall, F1, macro-averaging; why a held-out sample is needed (train/test split).
2. NER and BIO labelling.
3. Perceptron and averaged perceptron — the simplest trainable model; it makes "features" and "weights" easy to understand.
4. Transformers and BERT at the level of the idea: subword tokenisation, fine-tuning for your own task
   (Hugging Face course, the chapter on token classification).
5. ONNX — how to run a trained model outside Python.
6. LLMs: prompts, structured output (an answer following a JSON schema), hallucinations and how to fight them.
7. Confidence calibration: what "confidence 0.9" means and how to check it.

## Where to start in the code

1. `README.md`, sections 1 and 7.
2. `app/models/extraction/pipeline.rb` — the whole pipeline on one page.
3. `app/models/extraction/tagger/perceptron.rb` and `examples.rb`.
4. Run `bin/compare` on a small sample and `bin/errors`, see where it makes mistakes.
