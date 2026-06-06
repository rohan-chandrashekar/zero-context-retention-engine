import argparse
import datetime as dt
from retrieval_common import load_store, load_text


def main(args):
    timestamps, vectors = load_store(args.store)
    texts = load_text(args.text, timestamps.shape[0])
    print(f"{timestamps.shape[0]} moments in {args.store}")
    for index in range(timestamps.shape[0]):
        when = dt.datetime.fromtimestamp(float(timestamps[index])).strftime("%Y-%m-%d %H:%M:%S")
        snippet = " ".join(texts[index].split())[:args.width]
        print(f"idx {index:4d}  {when}  {snippet}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", default="vectorstore/vectors.f32bin")
    parser.add_argument("--text", default="vectorstore/text.jsonl")
    parser.add_argument("--width", type=int, default=140)
    args = parser.parse_args()
    main(args)
