"""Rebuild MATE365 icons from the transparent, reference-generated master.

Requires Python and Pillow: python -m pip install Pillow
"""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent


def main():
    with Image.open(ROOT / "mate365-master.png") as source:
        master = source.convert("RGBA")

    for size in (16, 32, 48, 180, 192, 512):
        master.resize((size, size), Image.Resampling.LANCZOS).save(
            ROOT / f"mate365-{size}.png", optimize=True
        )

    master.save(
        ROOT / "favicon.ico",
        sizes=[(16, 16), (32, 32), (48, 48)],
    )


if __name__ == "__main__":
    main()
