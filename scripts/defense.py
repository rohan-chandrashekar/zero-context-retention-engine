import argparse
import numpy as np
from retrieval_common import load_store, RECORD_DTYPE
from redteam_common import apply_defense, gaussian_epsilon


def write_store(path, timestamps, vectors):
    arr = np.zeros(len(timestamps), dtype=RECORD_DTYPE)
    arr["t"] = timestamps
    arr["v"] = vectors.astype(np.float32)
    arr.tofile(path)


def main(args):
    timestamps, vectors = load_store(args.store)
    if vectors.shape[0] == 0:
        print(f"store is empty: {args.store}")
        return
    rng = np.random.default_rng(args.seed)
    defended = apply_defense(vectors, args.defense, args.param, rng=rng)
    write_store(args.output, timestamps, defended)
    print(f"wrote {defended.shape[0]} defended vectors -> {args.output}")
    print(f"defense={args.defense} param={args.param}")
    if args.defense == "dpnoise":
        epsilon = gaussian_epsilon(float(args.param), sensitivity=2.0, delta=1e-5)
        print(f"indicative gaussian-mechanism epsilon (sensitivity=2, delta=1e-5): {epsilon:.2f}")
        print("note: indicative only; formal (epsilon,delta)-DP requires a bounded-sensitivity release model")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", default="vectorstore/vectors.f32bin")
    parser.add_argument("--output", default="vectorstore/vectors.defended.f32bin")
    parser.add_argument("--defense", default="dpnoise", choices=["none", "pca", "quantize", "dpnoise"])
    parser.add_argument("--param", default="0.1")
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()
    main(args)
