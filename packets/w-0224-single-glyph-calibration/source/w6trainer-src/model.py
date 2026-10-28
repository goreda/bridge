"""Recipe v12 sec. 3 R2 net: 4 conv blocks (3x3, 32/64/128/128, ReLU,
2x2 maxpool after blocks 1-3) -> global average pool -> FC 128 ReLU ->
linear num_classes RAW LOGITS. No softmax layer anywhere (sec. 3 loss
discipline: CrossEntropyLoss consumes raw logits directly)."""
import torch
from torch import nn


class R2Net(nn.Module):
    def __init__(self, num_classes: int = 62):
        super().__init__()
        blocks = []
        cin = 1
        for i, cout in enumerate((32, 64, 128, 128)):
            blocks.append(nn.Conv2d(cin, cout, kernel_size=3, padding=1))
            blocks.append(nn.ReLU())
            if i < 3:
                blocks.append(nn.MaxPool2d(2))
            cin = cout
        self.features = nn.Sequential(*blocks)
        self.head_fc = nn.Linear(128, 128)
        self.head_out = nn.Linear(128, num_classes)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.features(x)
        x = x.mean(dim=(2, 3))  # global average pool
        x = torch.relu(self.head_fc(x))
        return self.head_out(x)  # raw logits


def kaiming_init_seeded(model: nn.Module, seed: int) -> None:
    """Recipe v12 sec. 4: random init ONLY, Kaiming-uniform per layer,
    seeded from the master seed chain. No pretrained weights."""
    gen = torch.Generator().manual_seed(seed)
    for m in model.modules():
        if isinstance(m, (nn.Conv2d, nn.Linear)):
            nn.init.kaiming_uniform_(m.weight, a=5**0.5, generator=gen)
            if m.bias is not None:
                nn.init.zeros_(m.bias)
