import argparse
import json
import numpy as np
import coremltools as ct
import mobileclip
from retrieval_common import load_store, embed_query, rank_all


def main(args):
    text_model = ct.models.MLModel(args.text_model)
    tokenizer = mobileclip.get_tokenizer(args.variant)

    timestamps, vectors = load_store(args.store)
    if vectors.shape[0] == 0:
        print(f"store is empty: {args.store}")
        return

    with open(args.labels, "r") as handle:
        labels = json.load(handle)

    k = args.k
    precision_at_k = []
    top1 = []
    reciprocal_rank = []

    print(f"evaluating {len(labels)} queries over {vectors.shape[0]} moments, k={k}")
    for entry in labels:
        query = entry["query"]
        relevant = set(entry.get("relevant", []))
        if not relevant:
            print(f"  [skip] no relevant indices  | {query}")
            continue
        query_vector = embed_query(text_model, tokenizer, query)
        scores, order = rank_all(vectors, query_vector)
        order_list = order.tolist()
        topk = order_list[:k]
        hits = sum(1 for index in topk if index in relevant)
        precision_at_k.append(hits / k)
        top1.append(1.0 if topk[0] in relevant else 0.0)
        rank = next((position for position, index in enumerate(order_list, 1) if index in relevant), None)
        reciprocal_rank.append(1.0 / rank if rank else 0.0)
        marker = "OK  " if topk[0] in relevant else "MISS"
        print(f"  [{marker}] p@{k} {hits / k:.2f}  rr {(1.0 / rank if rank else 0.0):.3f}  | {query}")

    n = len(precision_at_k)
    if n == 0:
        print("no labeled queries with relevant items")
        return
    print()
    print(f"queries evaluated : {n}")
    print(f"top-1 accuracy    : {np.mean(top1):.3f}")
    print(f"precision@{k}      : {np.mean(precision_at_k):.3f}")
    print(f"MRR               : {np.mean(reciprocal_rank):.3f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--labels", default="vectorstore/labels.json")
    parser.add_argument("--text-model", default="MobileCLIPText.mlpackage")
    parser.add_argument("--store", default="vectorstore/vectors.f32bin")
    parser.add_argument("--variant", default="mobileclip_s2")
    parser.add_argument("--k", type=int, default=5)
    args = parser.parse_args()
    main(args)
