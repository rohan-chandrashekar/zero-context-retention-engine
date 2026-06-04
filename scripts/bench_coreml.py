import argparse
import os
import time
import numpy as np
import coremltools as ct
from PIL import Image


def model_size_mb(path):
    total = 0
    for root, _, files in os.walk(path):
        for name in files:
            total += os.path.getsize(os.path.join(root, name))
    return total / (1024 * 1024)


def benchmark(path, runs, size, compute_units):
    units = {
        "all": ct.ComputeUnit.ALL,
        "cpu_and_ne": ct.ComputeUnit.CPU_AND_NE,
        "cpu_and_gpu": ct.ComputeUnit.CPU_AND_GPU,
        "cpu_only": ct.ComputeUnit.CPU_ONLY,
    }[compute_units]
    model = ct.models.MLModel(path, compute_units=units)
    image = Image.fromarray(np.random.randint(0, 255, (size, size, 3), dtype=np.uint8))
    for _ in range(15):
        model.predict({"image": image})
    timings = []
    for _ in range(runs):
        start = time.perf_counter()
        model.predict({"image": image})
        timings.append((time.perf_counter() - start) * 1000.0)
    timings = np.array(timings)
    print(f"compute_units {compute_units}")
    print(f"model_size_mb {model_size_mb(path):.2f}")
    print(f"mean_ms {timings.mean():.2f}")
    print(f"median_ms {np.median(timings):.2f}")
    print(f"p95_ms {np.percentile(timings, 95):.2f}")
    print(f"throughput_per_sec {1000.0 / timings.mean():.0f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="MobileCLIPImage.mlpackage")
    parser.add_argument("--runs", type=int, default=200)
    parser.add_argument("--size", type=int, default=256)
    parser.add_argument("--compute-units", default="all")
    args = parser.parse_args()
    benchmark(args.model, args.runs, args.size, args.compute_units)
