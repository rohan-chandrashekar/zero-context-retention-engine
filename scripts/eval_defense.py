import argparse
import json
import numpy as np
import coremltools as ct
import mobileclip
from retrieval_common import load_store, embed_query, rank_all
from redteam_common import apply_defense, score_vocab, top1_confidence, agreement_rate


def load_vocab(path):
    with open(path, "r") as handle:
        return [line.strip() for line in handle if line.strip()]


def parse_defense(spec):
    if ":" in spec:
        kind, param = spec.split(":", 1)
        return kind, param
    return spec, "0"


def retrieval_metrics(query_vectors, relevant_sets, vectors, k):
    if not query_vectors:
        return float("nan"), float("nan")
    top1 = []
    precision = []
    for query_vector, relevant in zip(query_vectors, relevant_sets):
        if not relevant:
            continue
        _, order = rank_all(vectors, query_vector)
        order_list = order.tolist()
        top1.append(1.0 if order_list[0] in relevant else 0.0)
        hits = sum(1 for index in order_list[:k] if index in relevant)
        precision.append(hits / k)
    if not precision:
        return float("nan"), float("nan")
    return float(np.mean(top1)), float(np.mean(precision))


def main(args):
    text_model = ct.models.MLModel(args.text_model)
    tokenizer = mobileclip.get_tokenizer(args.variant)

    timestamps, vectors = load_store(args.store)
    if vectors.shape[0] == 0:
        print(f"store is empty: {args.store}")
        return

    vocab = load_vocab(args.vocab)
    vocab_vectors = np.stack([embed_query(text_model, tokenizer, phrase) for phrase in vocab]).astype(np.float32)

    with open(args.labels, "r") as handle:
        labels = json.load(handle)
    query_vectors = [embed_query(text_model, tokenizer, entry["query"]) for entry in labels]
    relevant_sets = [set(entry.get("relevant", [])) for entry in labels]

    _, reference_top1 = score_vocab(vectors, vocab_vectors)
    defenses = [parse_defense(spec) for spec in args.defenses]
    rng = np.random.default_rng(args.seed)

    print(f"before/after over {vectors.shape[0]} moments, {len(vocab)} leakage labels, {len(labels)} retrieval queries, k={args.k}")
    print()
    header = f"{'defense':<16}{'leak-agree↓':>12}{'leak-conf↓':>12}{'ret-top1↑':>11}{'ret-p@k↑':>10}"
    print(header)
    print("-" * len(header))
    for kind, param in defenses:
        defended = apply_defense(vectors, kind, param, rng=rng)
        scores, top1 = score_vocab(defended, vocab_vectors)
        leak_agree = agreement_rate(top1, reference_top1)
        leak_conf = top1_confidence(scores)
        ret_top1, ret_pk = retrieval_metrics(query_vectors, relevant_sets, defended, args.k)
        name = kind if param in ("0", "") else f"{kind}:{param}"
        print(f"{name:<16}{leak_agree:>12.3f}{leak_conf:>12.4f}{ret_top1:>11.3f}{ret_pk:>10.3f}")

    print()
    print("leak-agree = fraction of moments whose recovered top-1 label still matches the undefended attack (lower = defense destroys more of what the attacker learns)")
    print("ret-top1 / ret-p@k = legitimate retrieval kept usable (higher = better); a good defense pushes leak down while holding retrieval up")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", default="vectorstore/vectors.f32bin")
    parser.add_argument("--labels", default="vectorstore/labels.json")
    parser.add_argument("--vocab", default="scripts/leakage_vocab.txt")
    parser.add_argument("--text-model", default="MobileCLIPText.mlpackage")
    parser.add_argument("--variant", default="mobileclip_s2")
    parser.add_argument("--k", type=int, default=5)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--defenses", nargs="+", default=["none", "pca:64", "quantize:4", "dpnoise:0.05", "dpnoise:0.1", "dpnoise:0.2"])
    args = parser.parse_args()
    main(args)
