import argparse
import os
import time
import numpy as np
import coremltools as ct
from PIL import Image

UNIT_MAP = {
    "all": ct.ComputeUnit.ALL,
    "cpu_and_ne": ct.ComputeUnit.CPU_AND_NE,
    "cpu_and_gpu": ct.ComputeUnit.CPU_AND_GPU,
    "cpu_only": ct.ComputeUnit.CPU_ONLY,
}


def model_size_mb(path):
    total = 0
    for root, _, files in os.walk(path):
        for name in files:
            total += os.path.getsize(os.path.join(root, name))
    return total / (1024 * 1024)


def benchmark(path, unit, runs, size):
    model = ct.models.MLModel(path, compute_units=UNIT_MAP[unit])
    image = Image.fromarray(np.random.randint(0, 255, (size, size, 3), dtype=np.uint8))
    for _ in range(15):
        model.predict({"image": image})
    timings = []
    for _ in range(runs):
        start = time.perf_counter()
        model.predict({"image": image})
        timings.append((time.perf_counter() - start) * 1000.0)
    timings = np.array(timings)
    return float(np.median(timings)), float(np.percentile(timings, 95)), float(1000.0 / timings.mean())


def label_for(path):
    base = os.path.basename(path.rstrip("/"))
    return os.path.splitext(base)[0]


def main(args):
    print(f"machine label: {args.machine}")
    print()
    header = f"| Model | Size (MB) | Compute unit | Median (ms) | p95 (ms) | Throughput (img/s) |"
    sep = "|---|---|---|---|---|---|"
    print(header)
    print(sep)
    for path in args.models:
        if not os.path.exists(path):
            print(f"| {label_for(path)} | (missing) | - | - | - | - |")
            continue
        size_mb = model_size_mb(path)
        for unit in args.compute_units:
            median, p95, throughput = benchmark(path, unit, args.runs, args.size)
            print(f"| {label_for(path)} | {size_mb:.2f} | {unit} | {median:.2f} | {p95:.2f} | {throughput:.0f} |")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--models", nargs="+", required=True)
    parser.add_argument("--compute-units", nargs="+", default=["all", "cpu_and_ne", "cpu_and_gpu", "cpu_only"])
    parser.add_argument("--runs", type=int, default=200)
    parser.add_argument("--size", type=int, default=256)
    parser.add_argument("--machine", default="UNLABELED-MACHINE")
    args = parser.parse_args()
    main(args)
