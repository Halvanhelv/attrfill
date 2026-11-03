"""Fine-tunes a small BERT to mark attribute values in product text, then exports it to ONNX for the Ruby app.

    bin/rails 'extraction:tagger_examples[data/train.csv,tmp/tagger_examples.jsonl]'
    python script/ner/train.py tmp/tagger_examples.jsonl config/tagger/transformer

Input lines come from Extraction::Tagger::Examples: {"tokens": [...], "labels": [...], "category": ..., "source": ...}.
Each text is prefixed with its category and source, the same way Extraction::Tagger::Transformer reads it.
"""
import argparse
import json
import random
import time
from pathlib import Path

import torch
from onnxruntime.quantization import QuantType, quantize_dynamic
from transformers import AutoModelForTokenClassification, AutoTokenizer

MAX_LENGTH = 320


def prefixed(example):
    return [example["category"], "|", example["source"], "|"] + example["tokens"]


def encode(tokenizer, example, label_ids):
    words = prefixed(example)
    labels = [None] * 4 + example["labels"]
    encoding = tokenizer(words, is_split_into_words=True, truncation=True, max_length=MAX_LENGTH)
    targets, previous = [], None
    for word in encoding.word_ids():
        # Only the first piece of a word is scored; the prefix and special tokens never are.
        targets.append(-100 if word is None or word == previous or labels[word] is None else label_ids[labels[word]])
        previous = word
    return encoding["input_ids"], targets


def batches(items, size):
    for start in range(0, len(items), size):
        chunk = items[start:start + size]
        width = max(len(ids) for ids, _ in chunk)
        ids = torch.tensor([ids + [0] * (width - len(ids)) for ids, _ in chunk])
        mask = torch.tensor([[1] * len(ids) + [0] * (width - len(ids)) for ids, _ in chunk])
        targets = torch.tensor([t + [-100] * (width - len(t)) for _, t in chunk])
        yield ids, mask, targets


def accuracy(model, items, device):
    model.eval()
    right = total = 0
    with torch.no_grad():
        for ids, mask, targets in batches(items, 32):
            predicted = model(input_ids=ids.to(device), attention_mask=mask.to(device)).logits.argmax(-1).cpu()
            scored = (targets != -100) & (targets != 0)  # label 0 is "O": count only value words
            right += ((predicted == targets) & scored).sum().item()
            total += scored.sum().item()
    model.train()
    return right / max(total, 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("examples")
    parser.add_argument("output")
    parser.add_argument("--base", default="cointegrated/rubert-tiny2")
    parser.add_argument("--epochs", type=int, default=4)
    parser.add_argument("--batch", type=int, default=16)
    parser.add_argument("--lr", type=float, default=5e-5)
    parser.add_argument("--limit", type=int, default=0, help="train on at most this many texts (0 = all)")
    args = parser.parse_args()

    random.seed(1)
    torch.manual_seed(1)
    examples = [json.loads(line) for line in Path(args.examples).read_text().splitlines() if line.strip()]
    random.shuffle(examples)
    if args.limit:
        examples = examples[:args.limit]
    labels = ["O"] + sorted({label for example in examples for label in example["labels"]} - {"O"})
    label_ids = {label: index for index, label in enumerate(labels)}

    tokenizer = AutoTokenizer.from_pretrained(args.base)
    model = AutoModelForTokenClassification.from_pretrained(
        args.base, num_labels=len(labels), id2label=dict(enumerate(labels)), label2id=label_ids)
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    model.to(device)

    items = [encode(tokenizer, example, label_ids) for example in examples]
    held = items[: max(len(items) // 10, 1)]
    train = items[len(held):]
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr)
    steps = args.epochs * ((len(train) + args.batch - 1) // args.batch)
    schedule = torch.optim.lr_scheduler.LinearLR(optimizer, 1.0, 0.0, total_iters=steps)

    started = time.time()
    for epoch in range(args.epochs):
        random.shuffle(train)
        train.sort(key=lambda item: len(item[0]) // 16)  # similar lengths together: less padding
        chunks = list(batches(train, args.batch))
        random.shuffle(chunks)
        for ids, mask, targets in chunks:
            loss = model(input_ids=ids.to(device), attention_mask=mask.to(device), labels=targets.to(device)).loss
            loss.backward()
            optimizer.step()
            schedule.step()
            optimizer.zero_grad()
        print(f"epoch {epoch + 1}: loss {loss.item():.4f}, value words right on held-out {accuracy(model, held, device):.3f}, "
              f"{time.time() - started:.0f}s", flush=True)

    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    model.to("cpu").eval()
    sample = torch.tensor([items[0][0]])
    full = output / "model.full.onnx"
    torch.onnx.export(model, (sample, torch.ones_like(sample)), full, input_names=["input_ids", "attention_mask"],
                      output_names=["logits"], opset_version=17, dynamo=False,
                      dynamic_axes={"input_ids": {0: "batch", 1: "length"}, "attention_mask": {0: "batch", 1: "length"},
                                    "logits": {0: "batch", 1: "length"}})
    quantize_dynamic(str(full), str(output / "model.onnx"), weight_type=QuantType.QInt8)
    full.unlink()
    tokenizer.backend_tokenizer.save(str(output / "tokenizer.json"))
    (output / "labels.json").write_text(json.dumps(labels, ensure_ascii=False))
    print(f"→ {output}/model.onnx ({(output / 'model.onnx').stat().st_size // 1024} KB), {len(labels)} labels")


if __name__ == "__main__":
    main()
