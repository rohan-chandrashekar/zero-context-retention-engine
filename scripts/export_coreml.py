import argparse
import numpy as np
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


class TextEncoderWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, text):
        features = self.model.encode_text(text.to(torch.long))
        return features / features.norm(dim=-1, keepdim=True)


def export_image(model, variant, output):
    size = VARIANT_RESOLUTION[variant]
    wrapper = ImageEncoderWrapper(model).eval()
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
    print(f"saved {output} encoder=image variant={variant} resolution={size}")


def export_text(model, variant, output):
    tokenizer = mobileclip.get_tokenizer(variant)
    wrapper = TextEncoderWrapper(model).eval()
    example = tokenizer(["a screenshot of a code editor"]).to(torch.int32)
    context_length = int(example.shape[1])
    exported = torch.export.export(wrapper, (example,))
    exported = exported.run_decompositions({})
    text_input = ct.TensorType(name="text", shape=(1, context_length), dtype=np.int32)
    mlmodel = ct.convert(
        exported,
        inputs=[text_input],
        outputs=[ct.TensorType(name="embedding")],
        minimum_deployment_target=ct.target.macOS14,
        compute_units=ct.ComputeUnit.ALL,
        compute_precision=ct.precision.FLOAT16,
    )
    mlmodel.save(output)
    print(f"saved {output} encoder=text variant={variant} context_length={context_length}")


def export(encoder, variant, checkpoint, output):
    model, _, _ = mobileclip.create_model_and_transforms(variant, pretrained=checkpoint)
    model.eval()
    if encoder == "image":
        export_image(model, variant, output)
    else:
        export_text(model, variant, output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--encoder", default="image", choices=["image", "text"])
    parser.add_argument("--variant", default="mobileclip_s2")
    parser.add_argument("--checkpoint", default="checkpoints/mobileclip_s2.pt")
    parser.add_argument("--output", default=None)
    args = parser.parse_args()
    default_output = "MobileCLIPImage.mlpackage" if args.encoder == "image" else "MobileCLIPText.mlpackage"
    export(args.encoder, args.variant, args.checkpoint, args.output or default_output)
