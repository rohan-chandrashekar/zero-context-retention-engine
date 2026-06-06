import json
import os
import tempfile
import numpy as np
from retrieval_common import load_store, load_text, rank_all, RECORD_DTYPE


def write_store(path, timestamps, vectors):
    arr = np.zeros(len(timestamps), dtype=RECORD_DTYPE)
    arr["t"] = timestamps
    arr["v"] = vectors
    arr.tofile(path)


def write_text(path, texts, timestamps):
    with open(path, "w") as handle:
        for index, (timestamp, text) in enumerate(zip(timestamps, texts)):
            handle.write(json.dumps({"i": index, "t": timestamp, "text": text}, sort_keys=True) + "\n")


def main():
    rng = np.random.default_rng(0)
    dim = 512
    concepts = rng.standard_normal((3, dim)).astype(np.float32)
    concepts /= np.linalg.norm(concepts, axis=1, keepdims=True)

    rows = []
    labels = []
    for concept in range(3):
        for _ in range(3):
            vector = concepts[concept] + 0.05 * rng.standard_normal(dim).astype(np.float32)
            vector /= np.linalg.norm(vector)
            rows.append(vector)
            labels.append(concept)
    vectors = np.stack(rows).astype(np.float32)
    timestamps = 1_700_000_000 + np.arange(len(rows), dtype=np.float64)
    texts = [f"moment for concept {labels[i]}" for i in range(len(rows))]

    with tempfile.TemporaryDirectory() as tmp:
        store_path = os.path.join(tmp, "vectors.f32bin")
        text_path = os.path.join(tmp, "text.jsonl")
        write_store(store_path, timestamps, vectors)
        write_text(text_path, texts, timestamps)

        loaded_ts, loaded_vectors = load_store(store_path)
        assert loaded_ts.shape[0] == len(rows), (loaded_ts.shape, len(rows))
        assert loaded_vectors.shape == (len(rows), dim), loaded_vectors.shape
        assert np.allclose(loaded_ts, timestamps), "timestamp round-trip mismatch"
        assert np.allclose(loaded_vectors, vectors, atol=1e-6), "vector round-trip mismatch"

        loaded_texts = load_text(text_path, len(rows))
        assert loaded_texts == texts, "text sidecar misaligned with index"

        query = concepts[1] / np.linalg.norm(concepts[1])
        _, order = rank_all(loaded_vectors, query)
        top3 = set(order[:3].tolist())
        expected = {i for i in range(len(rows)) if labels[i] == 1}
        assert top3 == expected, (top3, expected)

    print("selftest_retrieval OK: binary round-trip + index alignment + cosine ranking")


if __name__ == "__main__":
    main()
