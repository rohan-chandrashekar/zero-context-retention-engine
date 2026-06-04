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

class ImageEncoderWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, image):
        features = self.model.encode_image(image)
        return features / features.norm(dim=-1, keepdim=True)


def export(variant, checkpoint, output):
    model, _, _ = mobileclip.create_model_and_transforms(variant, pretrained=checkpoint)
    model.eval()
    wrapper = ImageEncoderWrapper(model).eval()
    size = VARIANT_RESOLUTION[variant]
    example = torch.rand(1, 3, size, size)
    exported = torch.export.export(wrapper, (example,))
    exported = exported.run_decompositions({})
    image_input = ct.ImageType(
        name="image",
        shape=(1, 3, size, size),
        scale=1.0 / 255.0,
        bias=[0.0, 0.0, 0.0],
        color_layout=ct.colorlayout.RGB,
    )
    mlmodel = ct.convert(
        exported,
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
