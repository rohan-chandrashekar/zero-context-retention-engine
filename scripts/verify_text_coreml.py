import argparse
import numpy as np
import torch
import coremltools as ct
import mobileclip

PROMPTS = [
    "a screenshot of a code editor",
    "a bank login page",
    "a video call with several people",
    "a terminal running a build",
]


def main(variant, checkpoint, model_path):
    model, _, _ = mobileclip.create_model_and_transforms(variant, pretrained=checkpoint)
    model.eval()
    tokenizer = mobileclip.get_tokenizer(variant)
    mlmodel = ct.models.MLModel(model_path)

    tokens = tokenizer(PROMPTS)
    with torch.no_grad():
        ref = model.encode_text(tokens)
        ref = ref / ref.norm(dim=-1, keepdim=True)
    ref = ref.numpy()

    got = np.zeros_like(ref)
    for i in range(len(PROMPTS)):
        row = tokens[i:i + 1].to(torch.int32).numpy()
        out = mlmodel.predict({"text": row})
        vec = np.array(out["embedding"]).reshape(-1)
        got[i] = vec / np.linalg.norm(vec)

    print(f"embedding_dim {got.shape[1]}")
    for i, prompt in enumerate(PROMPTS):
        cosine = float(np.dot(ref[i], got[i]))
        max_abs = float(np.max(np.abs(ref[i] - got[i])))
        print(f"cosine_torch_vs_coreml {cosine:.6f}  max_abs_diff {max_abs:.6f}  | {prompt}")

    print(f"sanity self_cosine {float(np.dot(got[0], got[0])):.6f}  cross_cosine[0,1] {float(np.dot(got[0], got[1])):.6f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", default="mobileclip_s2")
    parser.add_argument("--checkpoint", default="checkpoints/mobileclip_s2.pt")
    parser.add_argument("--model", default="MobileCLIPText.mlpackage")
    args = parser.parse_args()
    main(args.variant, args.checkpoint, args.model)
