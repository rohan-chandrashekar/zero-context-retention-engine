import argparse
import datetime as dt
import numpy as np
import coremltools as ct
import mobileclip
from retrieval_common import load_store, load_text, embed_query
from redteam_common import score_vocab, top1_confidence


def load_vocab(path):
    with open(path, "r") as handle:
        return [line.strip() for line in handle if line.strip()]


def embed_vocab(text_model, tokenizer, vocab):
    rows = [embed_query(text_model, tokenizer, phrase) for phrase in vocab]
    return np.stack(rows).astype(np.float32)


def main(args):
    text_model = ct.models.MLModel(args.text_model)
    tokenizer = mobileclip.get_tokenizer(args.variant)

    timestamps, vectors = load_store(args.store)
    if vectors.shape[0] == 0:
        print(f"store is empty: {args.store}")
        return
    texts = load_text(args.text, timestamps.shape[0])
    vocab = load_vocab(args.vocab)
    vocab_vectors = embed_vocab(text_model, tokenizer, vocab)

    scores, top1 = score_vocab(vectors, vocab_vectors)
    print(f"semantic-leakage attack: {vectors.shape[0]} stored vectors vs {len(vocab)} candidate labels")
    print(f"mean top-1 cosine (attacker confidence): {top1_confidence(scores):.4f}")
    print()
    for index in range(min(args.show, vectors.shape[0])):
        ranked = np.argsort(-scores[index])[:3]
        when = dt.datetime.fromtimestamp(float(timestamps[index])).strftime("%Y-%m-%d %H:%M:%S")
        guesses = "; ".join(f"{vocab[j]} ({scores[index, j]:.3f})" for j in ranked)
        ocr_hint = " ".join(texts[index].split())[:60]
        print(f"idx {index:4d}  {when}  recovered: {guesses}")
        if ocr_hint:
            print(f"           (ocr ground-truth hint: {ocr_hint})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", default="vectorstore/vectors.f32bin")
    parser.add_argument("--text", default="vectorstore/text.jsonl")
    parser.add_argument("--vocab", default="scripts/leakage_vocab.txt")
    parser.add_argument("--text-model", default="MobileCLIPText.mlpackage")
    parser.add_argument("--variant", default="mobileclip_s2")
    parser.add_argument("--show", type=int, default=20)
    args = parser.parse_args()
    main(args)
