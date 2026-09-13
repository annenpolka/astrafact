"""Pixel-scope guard; compares decoded pixels, never PNG encoding bytes."""
from __future__ import annotations
from dataclasses import dataclass
from PIL import Image


@dataclass(frozen=True)
class PixelDiff:
    changed_pixels: int
    unauthorized_pixels: int

    @property
    def allowed(self) -> bool:
        return self.unauthorized_pixels == 0


def _canonical(pixel: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    # Invisible RGB values are irrelevant to the normalized visual representation.
    return (0, 0, 0, 0) if pixel[3] == 0 else pixel


def inspect_patch(before: Image.Image, after: Image.Image, mask: Image.Image) -> PixelDiff:
    """255 = editable; 0 = frozen. Caller verifies all unlisted frames separately."""
    if before.size != after.size or before.size != mask.size:
        raise ValueError("Canvas sizes differ; implicit resizing is forbidden")
    if mask.mode != "L":
        raise ValueError("Mask must be a grayscale L image")
    if not set(mask.tobytes()).issubset({0, 255}):
        raise ValueError("Mask must contain only 0 and 255")
    a, b = before.convert("RGBA"), after.convert("RGBA")
    changed = unauthorized = 0
    pa, pb, pm = a.load(), b.load(), mask.load()
    for y in range(a.height):
        for x in range(a.width):
            if _canonical(pa[x, y]) != _canonical(pb[x, y]):
                changed += 1
                if pm[x, y] == 0:
                    unauthorized += 1
    return PixelDiff(changed, unauthorized)
