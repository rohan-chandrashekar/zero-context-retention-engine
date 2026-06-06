import numpy as np
from redteam_common import (
    apply_defense,
    pca_defense,
    quantize_defense,
    dp_noise_defense,
    score_vocab,
    recovery_rate,
    agreement_rate,
    top1_confidence,
    gaussian_epsilon,
    l2_normalize,
)


def synth(rng, dim=512, n_concepts=5, per_concept=6, spread=0.1):
    concepts = l2_normalize(rng.standard_normal((n_concepts, dim)))
    rows = []
    labels = []
    for concept in range(n_concepts):
        for _ in range(per_concept):
            direction = rng.standard_normal(dim)
            direction /= np.linalg.norm(direction)
            rows.append(concepts[concept] + spread * direction)
            labels.append(concept)
    vectors = l2_normalize(np.stack(rows)).astype(np.float32)
    return concepts.astype(np.float32), vectors, np.array(labels)


def is_unit(matrix, tol=1e-4):
    return np.allclose(np.linalg.norm(matrix, axis=1), 1.0, atol=tol)


def avg_offdiag_sim(matrix):
    similarity = matrix @ matrix.T
    np.fill_diagonal(similarity, 0.0)
    return float(similarity.sum() / (similarity.size - matrix.shape[0]))


def main():
    rng = np.random.default_rng(0)
    concepts, vectors, labels = synth(rng)
    _, dim = vectors.shape

    scores, top1 = score_vocab(vectors, concepts)
    assert recovery_rate(top1, labels) > 0.95, recovery_rate(top1, labels)

    for kind, param in [("none", 0), ("pca", 64), ("quantize", 4), ("dpnoise", 0.1)]:
        out = apply_defense(vectors, kind, param, rng=np.random.default_rng(1))
        assert out.shape == vectors.shape, (kind, out.shape)
        assert is_unit(out), (kind, np.linalg.norm(out, axis=1)[:3])

    assert np.allclose(apply_defense(vectors, "none", 0), vectors)

    full = pca_defense(vectors, dim)
    assert float(np.mean(np.sum(full * vectors, axis=1))) > 0.999, "pca full-rank should be ~identity"
    low = pca_defense(vectors, 2)
    assert avg_offdiag_sim(low) > avg_offdiag_sim(vectors), "pca k=2 should collapse the spread"

    q1 = quantize_defense(vectors, 1)
    assert float(np.mean(np.sum(q1 * vectors, axis=1))) < 0.999, "1-bit quantize should distort"

    n0 = dp_noise_defense(vectors, 0.0, rng=np.random.default_rng(2))
    assert np.allclose(n0, l2_normalize(vectors), atol=1e-6)
    nbig = dp_noise_defense(vectors, 1.0, rng=np.random.default_rng(3))
    assert float(np.mean(np.sum(nbig * vectors, axis=1))) < 0.9, "large sigma should move vectors"

    assert gaussian_epsilon(0.1, 2.0, 1e-5) > gaussian_epsilon(1.0, 2.0, 1e-5)

    for concept in range(concepts.shape[0]):
        order = np.argsort(-(vectors @ concepts[concept]))
        assert labels[order[0]] == concept, concept

    _, scrambled_top1 = score_vocab(dp_noise_defense(vectors, 1.0, rng=np.random.default_rng(4)), concepts)
    assert 0.0 <= agreement_rate(scrambled_top1, top1) <= 1.0
    assert 0.0 <= top1_confidence(scores) <= 1.0

    print("selftest_defense OK: defenses normalize + transform, leakage scoring + metrics correct")


if __name__ == "__main__":
    main()
