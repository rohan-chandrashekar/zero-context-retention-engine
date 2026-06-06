import json
import numpy as np

RECORD_DTYPE = np.dtype([("t", "<f8"), ("v", "<f4", 512)])


def load_store(path):
    raw = np.fromfile(path, dtype=RECORD_DTYPE)
    if raw.size == 0:
        return np.zeros(0, dtype=np.float64), np.zeros((0, 512), dtype=np.float32)
    timestamps = np.ascontiguousarray(raw["t"])
    vectors = np.ascontiguousarray(raw["v"]).astype(np.float32)
    return timestamps, vectors


def load_text(path, count):
    texts = [""] * count
    try:
        with open(path, "r") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                obj = json.loads(line)
                index = obj.get("i")
                if isinstance(index, int) and 0 <= index < count:
                    texts[index] = obj.get("text", "")
    except FileNotFoundError:
        pass
    return texts


def embed_query(text_model, tokenizer, query):
    tokens = np.asarray(tokenizer([query])).astype(np.int32)
    out = text_model.predict({"text": tokens})
    vec = np.array(out["embedding"]).reshape(-1).astype(np.float32)
    norm = float(np.linalg.norm(vec))
    return vec / norm if norm > 0 else vec


def rank_all(vectors, query_vector):
    scores = vectors @ query_vector
    order = np.argsort(-scores)
    return scores, order
