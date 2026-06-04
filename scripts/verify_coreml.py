import argparse
import numpy as np
import torch
import coremltools as ct
import mobileclip
from PIL import Image
from torchvision.transforms import Resize, CenterCrop, ToTensor, InterpolationMode

VARIANT_RESOLUTION = {
    "mobileclip_s0": 256,
    "mobileclip_s1": 256,
    "mobileclip_s2": 256,
    "mobileclip_b": 224,
}


def reference_embedding(model, pil_square):
    tensor = ToTensor()(pil_square).unsqueeze(0)
    with torch.no_grad():
        features = model.encode_image(tensor)
        features = features / features.norm(dim=-1, keepdim=True)
    return features.squeeze(0).numpy()


def coreml_embedding(mlmodel, pil_square):
    out = mlmodel.predict({"image": pil_square})
    vector = np.array(out["embedding"]).reshape(-1)
    return vector / np.linalg.norm(vector)


def main(variant, checkpoint, model_path, image_path):
    size = VARIANT_RESOLUTION[variant]
    model, _, _ = mobileclip.create_model_and_transforms(variant, pretrained=checkpoint)
    model.eval()
    mlmodel = ct.models.MLModel(model_path)

    image = Image.open(image_path).convert("RGB")
    square = CenterCrop(size)(Resize(size, interpolation=InterpolationMode.BILINEAR, antialias=True)(image))

    ref = reference_embedding(model, square)
    got = coreml_embedding(mlmodel, square)

    cosine = float(np.dot(ref, got))
    print(f"image {image_path}")
    print(f"embedding_dim {got.shape[0]}")
    print(f"coreml_norm {np.linalg.norm(got):.6f}")
    print(f"reference_norm {np.linalg.norm(ref):.6f}")
    print(f"cosine_torch_vs_coreml {cosine:.6f}")
    print(f"max_abs_diff {np.max(np.abs(ref - got)):.6f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", default="mobileclip_s2")
    parser.add_argument("--checkpoint", default="checkpoints/mobileclip_s2.pt")
    parser.add_argument("--model", default="MobileCLIPImage.mlpackage")
    parser.add_argument("--image", default="/tmp/zrce_cats.jpg")
    args = parser.parse_args()
    main(args.variant, args.checkpoint, args.model, args.image)
