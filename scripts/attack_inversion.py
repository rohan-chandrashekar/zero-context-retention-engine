import argparse
import glob
import os
import numpy as np
import torch
import torch.nn as nn
import coremltools as ct
from PIL import Image
from skimage.metrics import structural_similarity
from redteam_common import apply_defense

TARGET = 64
ENCODER_INPUT = 256


def list_images(folder):
    paths = []
    for extension in ("*.jpg", "*.jpeg", "*.png", "*.bmp", "*.webp"):
        paths.extend(glob.glob(os.path.join(folder, "**", extension), recursive=True))
    return sorted(paths)


def embed_images(image_model, paths):
    embeddings = []
    targets = []
    for path in paths:
        try:
            image = Image.open(path).convert("RGB")
        except Exception:
            continue
        encoder_image = image.resize((ENCODER_INPUT, ENCODER_INPUT), Image.BILINEAR)
        out = image_model.predict({"image": encoder_image})
        vector = np.array(out["embedding"]).reshape(-1).astype(np.float32)
        vector = vector / max(float(np.linalg.norm(vector)), 1e-8)
        target = np.asarray(image.resize((TARGET, TARGET), Image.BILINEAR), dtype=np.float32) / 255.0
        embeddings.append(vector)
        targets.append(target)
    return np.stack(embeddings), np.stack(targets)


class Decoder(nn.Module):
    def __init__(self, dim):
        super().__init__()
        self.fc = nn.Linear(dim, 256 * 4 * 4)
        self.net = nn.Sequential(
            nn.ConvTranspose2d(256, 128, 4, stride=2, padding=1),
            nn.ReLU(inplace=True),
            nn.ConvTranspose2d(128, 64, 4, stride=2, padding=1),
            nn.ReLU(inplace=True),
            nn.ConvTranspose2d(64, 32, 4, stride=2, padding=1),
            nn.ReLU(inplace=True),
            nn.ConvTranspose2d(32, 3, 4, stride=2, padding=1),
            nn.Sigmoid(),
        )

    def forward(self, x):
        h = self.fc(x).view(-1, 256, 4, 4)
        return self.net(h)


def train(decoder, embeddings, targets, epochs, lr, device):
    decoder.train()
    optimizer = torch.optim.Adam(decoder.parameters(), lr=lr)
    loss_fn = nn.MSELoss()
    x = torch.from_numpy(embeddings).to(device)
    y = torch.from_numpy(targets.transpose(0, 3, 1, 2)).to(device)
    for epoch in range(epochs):
        optimizer.zero_grad()
        prediction = decoder(x)
        loss = loss_fn(prediction, y)
        loss.backward()
        optimizer.step()
        if (epoch + 1) % max(1, epochs // 10) == 0:
            print(f"  epoch {epoch + 1:4d}/{epochs}  mse {loss.item():.5f}")


def mean_ssim(decoder, embeddings, targets, device):
    decoder.eval()
    with torch.no_grad():
        prediction = decoder(torch.from_numpy(embeddings).to(device)).cpu().numpy()
    prediction = prediction.transpose(0, 2, 3, 1)
    scores = []
    for i in range(prediction.shape[0]):
        scores.append(structural_similarity(targets[i], prediction[i], channel_axis=2, data_range=1.0))
    return float(np.mean(scores)) if scores else float("nan")


def save_reconstruction(decoder, embeddings, path, device, upscale=256):
    decoder.eval()
    with torch.no_grad():
        prediction = decoder(torch.from_numpy(embeddings[:1]).to(device)).cpu().numpy()[0]
    image = (np.clip(prediction.transpose(1, 2, 0), 0.0, 1.0) * 255).astype(np.uint8)
    Image.fromarray(image).resize((upscale, upscale), Image.NEAREST).save(path)


def main(args):
    device = torch.device("cpu")
    image_model = ct.models.MLModel(args.image_model)
    paths = list_images(args.images)
    if len(paths) < 8:
        print(f"need at least 8 images in {args.images} (found {len(paths)})")
        return

    embeddings, targets = embed_images(image_model, paths)
    rng = np.random.default_rng(args.seed)
    order = rng.permutation(embeddings.shape[0])
    split = int(0.8 * len(order))
    train_idx, test_idx = order[:split], order[split:]

    decoder = Decoder(embeddings.shape[1]).to(device)
    print(f"training inversion decoder on {len(train_idx)} images, testing on {len(test_idx)}")
    train(decoder, embeddings[train_idx], targets[train_idx], args.epochs, args.lr, device)

    clean_ssim = mean_ssim(decoder, embeddings[test_idx], targets[test_idx], device)
    print()
    print(f"{'defense':<16}{'inversion SSIM↓':>16}")
    print("-" * 32)
    print(f"{'none':<16}{clean_ssim:>16.4f}")
    for spec in args.defenses:
        kind, param = (spec.split(":", 1) + ["0"])[:2]
        defended = apply_defense(embeddings[test_idx], kind, param, rng=rng)
        defended_ssim = mean_ssim(decoder, defended, targets[test_idx], device)
        print(f"{(kind + ':' + param):<16}{defended_ssim:>16.4f}")

    if args.dump:
        os.makedirs(args.dump, exist_ok=True)
        save_reconstruction(decoder, embeddings[test_idx], os.path.join(args.dump, "recon_clean.png"), device)
        kind, param = (args.defenses[0].split(":", 1) + ["0"])[:2]
        defended = apply_defense(embeddings[test_idx], kind, param, rng=rng)
        save_reconstruction(decoder, defended, os.path.join(args.dump, "recon_defended.png"), device)
        print(f"dumped reconstructions -> {args.dump}/recon_clean.png, {args.dump}/recon_defended.png")

    print()
    print("attacker trains on clean (image, embedding) pairs, then inverts the stored (possibly defended) embeddings.")
    print("lower SSIM under a defense = the reconstruction collapses = the defense works.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--images", default="attack_images")
    parser.add_argument("--image-model", default="MobileCLIPImage.mlpackage")
    parser.add_argument("--epochs", type=int, default=300)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--defenses", nargs="+", default=["pca:64", "quantize:4", "dpnoise:0.1", "dpnoise:0.2"])
    parser.add_argument("--dump", default=None)
    args = parser.parse_args()
    main(args)
