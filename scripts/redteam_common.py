import math
import numpy as np


def l2_normalize(matrix, axis=-1, eps=1e-8):
    norm = np.linalg.norm(matrix, axis=axis, keepdims=True)
    return matrix / np.maximum(norm, eps)


def pca_defense(vectors, k):
    k = max(1, min(int(k), vectors.shape[1]))
    mean = vectors.mean(axis=0, keepdims=True)
    centered = vectors - mean
    _, _, vt = np.linalg.svd(centered, full_matrices=False)
    components = vt[:k]
    reconstructed = (centered @ components.T) @ components + mean
    return l2_normalize(reconstructed.astype(np.float32))


def quantize_defense(vectors, bits):
    levels = float((1 << int(bits)) - 1)
    low = vectors.min(axis=1, keepdims=True)
    high = vectors.max(axis=1, keepdims=True)
    scale = np.maximum(high - low, 1e-8) / levels
    quantized = np.round((vectors - low) / scale)
    dequantized = quantized * scale + low
    return l2_normalize(dequantized.astype(np.float32))


def dp_noise_defense(vectors, sigma, rng=None):
    rng = rng if rng is not None else np.random.default_rng()
    noisy = vectors + rng.normal(0.0, float(sigma), size=vectors.shape)
    return l2_normalize(noisy.astype(np.float32))


def gaussian_epsilon(sigma, sensitivity, delta):
    if sigma <= 0:
        return float("inf")
    return float(sensitivity * math.sqrt(2.0 * math.log(1.25 / delta)) / sigma)


def apply_defense(vectors, kind, param, rng=None):
    if kind == "none":
        return vectors.astype(np.float32)
    if kind == "pca":
        return pca_defense(vectors, param)
    if kind == "quantize":
        return quantize_defense(vectors, param)
    if kind == "dpnoise":
        return dp_noise_defense(vectors, param, rng=rng)
    raise ValueError(f"unknown defense {kind}")


def score_vocab(image_vectors, vocab_vectors):
    scores = image_vectors @ vocab_vectors.T
    top1 = np.argmax(scores, axis=1)
    return scores, top1


def top1_confidence(scores):
    return float(np.mean(np.max(scores, axis=1))) if scores.shape[0] else float("nan")


def recovery_rate(top1, truth):
    top1 = np.asarray(top1)
    truth = np.asarray(truth)
    mask = truth >= 0
    if mask.sum() == 0:
        return float("nan")
    return float((top1[mask] == truth[mask]).mean())


def agreement_rate(top1_defended, top1_reference):
    top1_defended = np.asarray(top1_defended)
    top1_reference = np.asarray(top1_reference)
    if top1_reference.shape[0] == 0:
        return float("nan")
    return float((top1_defended == top1_reference).mean())
