#!/usr/bin/env python3
"""Generate a generative-art app icon: a Chladni (cymatic) nodal pattern.

Procedural, on-theme for a media-art / sound-to-image research atlas. Outputs a
1024x1024 RGBA PNG with an Apple-style squircle mask. Re-run to regenerate;
tweak SEED / MODES for a different figure.
"""
from __future__ import annotations

import numpy as np
from PIL import Image

N = 1024
SEED = 7
rng = np.random.default_rng(SEED)

# Two Chladni mode pairs blended for a richer figure (square plate, free edges).
MODES = [((4, 7), 1.0), ((3, 5), 0.6)]

# Palette (matches the app theme): near-black bg, cyan/teal glow.
BG_TOP = np.array([0.05, 0.06, 0.09])
BG_BOT = np.array([0.09, 0.11, 0.16])
GLOW = np.array([0.42, 0.86, 0.80])      # teal-cyan
CORE = np.array([0.85, 0.97, 1.00])      # near-white hot core


def chladni(x, y):
    f = np.zeros_like(x)
    for (a, b), w in MODES:
        f += w * (np.sin(a * np.pi * x) * np.sin(b * np.pi * y)
                  - np.sin(b * np.pi * x) * np.sin(a * np.pi * y))
    return f / sum(w for _, w in MODES)


def main() -> None:
    lin = np.linspace(0.0, 1.0, N)
    X, Y = np.meshgrid(lin, lin)

    f = chladni(X, Y)
    f /= np.max(np.abs(f)) + 1e-9

    # Bright nodal lines where the field crosses zero (sand collects there).
    sigma = 0.035
    glow = np.exp(-(f ** 2) / (2 * sigma ** 2))
    # A second, thinner highlight for crisp filaments.
    glow = np.clip(glow + 0.6 * np.exp(-(f ** 2) / (2 * (sigma / 2.4) ** 2)), 0, 1)

    # Vertical background gradient.
    bg = BG_TOP[None, None, :] * (1 - Y[..., None]) + BG_BOT[None, None, :] * Y[..., None]

    # Compose glow over background; hotter cores go toward white.
    g = glow[..., None]
    glow_col = GLOW[None, None, :] * (1 - glow[..., None] ** 2) + CORE[None, None, :] * glow[..., None] ** 2
    rgb = bg * (1 - g) + glow_col * g

    # Radial vignette to focus the center.
    cx = cy = 0.5
    r = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2) / 0.7071
    rgb *= (1 - 0.45 * np.clip(r, 0, 1)[..., None] ** 2)

    # Apple-style squircle alpha mask (superellipse), with soft antialiased edge.
    margin = 0.06
    R = 0.5 - margin
    xn = (X - 0.5) / R
    yn = (Y - 0.5) / R
    p = 5.0
    d = np.abs(xn) ** p + np.abs(yn) ** p           # <=1 inside
    edge = 0.06
    alpha = np.clip((1.0 - d) / edge + 0.5, 0, 1)

    # Subtle inner rim light along the squircle border.
    rim = np.exp(-((d - 1.0) ** 2) / (2 * 0.015 ** 2)) * (d < 1.0)
    rgb += rim[..., None] * np.array([0.20, 0.35, 0.40])[None, None, :]

    rgb = np.clip(rgb, 0, 1)
    out = np.dstack([rgb, alpha])
    img = Image.fromarray((out * 255).astype(np.uint8), mode="RGBA")
    img.save("icon_1024.png")
    print("wrote icon_1024.png")


if __name__ == "__main__":
    main()
