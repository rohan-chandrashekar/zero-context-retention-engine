import argparse
import datetime as dt
import coremltools as ct
import mobileclip
from retrieval_common import load_store, load_text, embed_query, rank_all


def main(args):
    text_model = ct.models.MLModel(args.text_model)
    tokenizer = mobileclip.get_tokenizer(args.variant)

    timestamps, vectors = load_store(args.store)
    if timestamps.shape[0] == 0:
        print(f"store is empty: {args.store}")
        return
    texts = load_text(args.text, timestamps.shape[0])

    query_vector = embed_query(text_model, tokenizer, args.query)
    scores, order = rank_all(vectors, query_vector)
    k = min(args.k, scores.shape[0])

    print(f"query: {args.query!r}   over {timestamps.shape[0]} stored moments")
    for rank, index in enumerate(order[:k].tolist(), 1):
        when = dt.datetime.fromtimestamp(float(timestamps[index])).strftime("%Y-%m-%d %H:%M:%S")
        snippet = " ".join(texts[index].split())[:140]
        print(f"#{rank}  score {scores[index]:.4f}  {when}  idx {index}")
        if snippet:
            print(f"      ocr: {snippet}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--query", required=True)
    parser.add_argument("--text-model", default="MobileCLIPText.mlpackage")
    parser.add_argument("--store", default="vectorstore/vectors.f32bin")
    parser.add_argument("--text", default="vectorstore/text.jsonl")
    parser.add_argument("--variant", default="mobileclip_s2")
    parser.add_argument("--k", type=int, default=5)
    args = parser.parse_args()
    main(args)
