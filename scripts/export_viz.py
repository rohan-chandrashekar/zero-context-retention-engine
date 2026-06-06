import argparse
import json
import os
import numpy as np
from retrieval_common import load_store, load_text


def pca_2d(vectors):
    if vectors.shape[0] < 2:
        return np.zeros((vectors.shape[0], 2), dtype=np.float32)
    mean = vectors.mean(axis=0, keepdims=True)
    centered = vectors - mean
    _, _, vt = np.linalg.svd(centered, full_matrices=False)
    return (centered @ vt[:2].T).astype(np.float32)


def main(args):
    timestamps, vectors = load_store(args.store)
    texts = load_text(args.text, timestamps.shape[0])

    coords = pca_2d(vectors)
    scale = float(np.max(np.abs(coords))) if coords.size else 1.0
    scale = scale if scale > 0 else 1.0

    moments = []
    for index in range(timestamps.shape[0]):
        moments.append({
            "i": index,
            "t": float(timestamps[index]),
            "x": float(coords[index, 0] / scale),
            "y": float(coords[index, 1] / scale),
            "text": " ".join(texts[index].split())[:160],
        })

    data = {"count": len(moments), "moments": moments}
    output_dir = os.path.dirname(args.output)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    with open(args.output, "w") as handle:
        json.dump(data, handle)
    print(f"wrote {len(moments)} moments -> {args.output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", default="vectorstore/vectors.f32bin")
    parser.add_argument("--text", default="vectorstore/text.jsonl")
    parser.add_argument("--output", default="viz/data.json")
    args = parser.parse_args()
    main(args)
