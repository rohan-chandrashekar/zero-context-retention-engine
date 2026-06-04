import argparse
import torch
import coremltools as ct
import mobileclip

VARIANT_RESOLUTION = {
    "mobileclip_s0": 256,
    "mobileclip_s1": 256,
    "mobileclip_s2": 256,
    "mobileclip_b": 224,
}

CLIP_MEAN = [0.48145466, 0.4578275, 0.40821073]
CLIP_STD = [0.26862954, 0.26130258, 0.27577711]


class ImageEncoderWrapper(torch.nn.Module):
    def __init__(self, model, mean, std):
        super().__init__()
        self.model = model
        self.register_buffer("mean", torch.tensor(mean).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(std).view(1, 3, 1, 1))

    def forward(self, image):
        normalized = (image - self.mean) / self.std
        features = self.model.encode_image(normalized)
        return features / features.norm(dim=-1, keepdim=True)


def export(variant, checkpoint, output):
    model, _, _ = mobileclip.create_model_and_transforms(variant, pretrained=checkpoint)
    model.eval()
    wrapper = ImageEncoderWrapper(model, CLIP_MEAN, CLIP_STD).eval()
    size = VARIANT_RESOLUTION[variant]
    example = torch.rand(1, 3, size, size)
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example)
    image_input = ct.ImageType(
        name="image",
        shape=(1, 3, size, size),
        scale=1.0 / 255.0,
        bias=[0.0, 0.0, 0.0],
        color_layout=ct.colorlayout.RGB,
    )
    mlmodel = ct.convert(
        traced,
        inputs=[image_input],
        outputs=[ct.TensorType(name="embedding")],
        minimum_deployment_target=ct.target.macOS14,
        compute_units=ct.ComputeUnit.ALL,
        compute_precision=ct.precision.FLOAT16,
    )
    mlmodel.save(output)
    print(f"saved {output} variant={variant} resolution={size}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", default="mobileclip_s2")
    parser.add_argument("--checkpoint", default="checkpoints/mobileclip_s2.pt")
    parser.add_argument("--output", default="MobileCLIPImage.mlpackage")
    args = parser.parse_args()
    export(args.variant, args.checkpoint, args.output)
