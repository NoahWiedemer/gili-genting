#!/usr/bin/env python3
"""Procedural pixel-art generator for "Gili Genting".

Generates (no downloads, numpy/scipy/Pillow only):
  game/assets/textures/*.png   32x32 seamless terrain/material tiles
  game/assets/fx/*.png         battle VFX strips + particle sprites, fx_meta.json, README
  game/assets/ui/*.png         JRPG window pieces, cursors, icons
  art_src/preview_*.png        8x contact sheets / 3x3 tiling checks

Usage:  python3 tools/gen_textures.py            (everything)
        python3 tools/gen_textures.py tex fx ui  (subset)
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
TEX_DIR = ROOT / "game/assets/textures"
FX_DIR = ROOT / "game/assets/fx"
UI_DIR = ROOT / "game/assets/ui"
PREV_DIR = ROOT / "art_src"
S = 32


# =============================================================== colour utils
def hx(h):
    h = h.lstrip("#")
    if len(h) == 6:
        h += "ff"
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4, 6))


def P(*hs):
    """Palette (n,3) uint8 from hex strings, dark -> light."""
    return np.array([hx(h)[:3] for h in hs], dtype=np.uint8)


def norm01(a):
    a = a - a.min()
    m = a.max()
    return a / m if m > 0 else a


# =============================================================== noise utils
def pnoise(rng, shape=(S, S), kmax=4, beta=1.0, kmin=1):
    """Band-limited periodic noise in [0,1] (FFT synthesis => tiles perfectly)."""
    h, w = shape
    F = rng.standard_normal((h, w)) + 1j * rng.standard_normal((h, w))
    ky = np.fft.fftfreq(h) * h
    kx = np.fft.fftfreq(w) * w
    K = np.sqrt(ky[:, None] ** 2 + kx[None, :] ** 2)
    amp = np.where((K >= kmin) & (K <= kmax), 1.0 / np.maximum(K, 1) ** beta, 0)
    return norm01(np.real(np.fft.ifft2(F * amp)))


def wblur(a, sigma):
    return ndimage.gaussian_filter(a, sigma, mode="wrap")


B4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], float)


def bayer(h, w):
    return (np.tile(B4, (h // 4 + 1, w // 4 + 1))[:h, :w] + 0.5) / 16.0 - 0.5


def quant(v, n, dither=0.5):
    """Map v in [0,1] to n levels with tasteful ordered dithering near the edges."""
    b = bayer(*v.shape)
    return np.clip(np.floor(np.clip(v, 0, 0.9999) * n + b * dither), 0, n - 1).astype(int)


def relief(h, light=(-1.0, -1.0)):
    """Lambert-ish term from a periodic heightfield, light from top-left."""
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    lx, ly = light
    n = math.hypot(lx, ly)
    return -(gx * lx + gy * ly) / n


YY, XX = np.mgrid[0:S, 0:S]


def toff(x0, y0, size=S):
    """Toroidal offsets from (x0,y0) to every pixel centre."""
    dx = (XX + 0.5 - x0 + size / 2) % size - size / 2
    dy = (YY + 0.5 - y0 + size / 2) % size - size / 2
    return dx, dy


def voronoi(points, size=S):
    D = []
    for (px, py) in points:
        dx, dy = toff(px, py, size)
        D.append(np.hypot(dx, dy))
    D = np.stack(D)
    order = np.argsort(D, axis=0)
    d1 = np.take_along_axis(D, order[0:1], 0)[0]
    d2 = np.take_along_axis(D, order[1:2], 0)[0]
    return d1, d2, order[0]


def lloyd(points, iters=3, size=S):
    pts = np.array(points, float)
    for _ in range(iters):
        _, _, ids = voronoi(pts, size)
        for i in range(len(pts)):
            m = ids == i
            if not m.any():
                continue
            ax = 2 * np.pi * (XX[m] + 0.5) / size
            ay = 2 * np.pi * (YY[m] + 0.5) / size
            cx = math.atan2(np.sin(ax).mean(), np.cos(ax).mean()) / (2 * np.pi) * size
            cy = math.atan2(np.sin(ay).mean(), np.cos(ay).mean()) / (2 * np.pi) * size
            pts[i] = (cx % size, cy % size)
    return pts


def wput(a, x, y, v):
    a[int(y) % a.shape[0], int(x) % a.shape[1]] = v


def wget(a, x, y):
    return a[int(y) % a.shape[0], int(x) % a.shape[1]]


def wline(a, x0, y0, x1, y1, v):
    x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    pts = []
    while True:
        pts.append((x0, y0))
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy
    for (x, y) in pts:
        if callable(v):
            wput(a, x, y, v(x, y, wget(a, x, y)))
        else:
            wput(a, x, y, v)
    return pts


def random_walk(rng, x, y, n, dirs):
    pts = [(x, y)]
    for _ in range(n):
        dx, dy = dirs[rng.integers(len(dirs))]
        x, y = x + dx, y + dy
        pts.append((x, y))
    return pts


def ellipse_mask(cx, cy, rx, ry, ang=0.0, size=S):
    dx, dy = toff(cx, cy, size)
    ca, sa = math.cos(ang), math.sin(ang)
    u = dx * ca + dy * sa
    v = -dx * sa + dy * ca
    return (u / rx) ** 2 + (v / ry) ** 2, u, v


def render(pal, idx):
    return pal[np.clip(idx, 0, len(pal) - 1)]


# =================================================================== TEXTURES
def tex_sand(rng):
    pal = P("#a5866f", "#c3a17e", "#d6b98f", "#e5cea1", "#f1e1b9", "#fcf3d8")
    low = pnoise(rng, kmax=2)
    warp = pnoise(rng, kmax=3)
    ph = 2 * np.pi * (1 * XX + 3 * YY) / S + 2.2 * warp
    rip = np.sin(ph + 0.6 * np.sin(ph))
    grain = wblur(rng.random((S, S)), 0.6)
    v = 0.52 + 0.24 * (low - 0.5) + 0.12 * rip + 0.18 * (norm01(grain) - 0.5)
    idx = 1 + quant(v, 4, 0.5)
    for _ in range(5):
        x, y = rng.integers(0, S, 2)
        wput(idx, x, y, 0 if wget(idx, x, y) <= 2 else 1)
    for _ in range(6):
        x, y = rng.integers(0, S, 2)
        wput(idx, x, y, 5)
    for _ in range(2):  # tiny shell bits
        x, y = rng.integers(0, S, 2)
        wput(idx, x, y, 5)
        wput(idx, x + 1, y, 5)
        wput(idx, x + 1, y + 1, 2)
    return render(pal, idx)


def tex_sand_wet(rng):
    pal = P("#5f4c48", "#7a6455", "#927a62", "#a99071", "#bea684", "#d9cbb0", "#f2eee2")
    low = pnoise(rng, kmax=2)
    warp = pnoise(rng, kmax=3)
    ph = 2 * np.pi * (2 * XX + 1 * YY) / S + 1.8 * warp
    rip = np.sin(ph)
    v = 0.5 + 0.3 * (low - 0.5) + 0.1 * rip + 0.08 * (pnoise(rng, kmax=10) - 0.5)
    idx = 1 + quant(v, 4, 0.45)
    for _ in range(6):  # glossy glints
        x, y = rng.integers(0, S, 2)
        L = int(rng.integers(2, 4))
        for k in range(L):
            wput(idx, x + k, y, 5)
        if L == 3:
            wput(idx, x + 1, y, 6)
    for _ in range(2):  # crab holes
        x, y = rng.integers(0, S, 2)
        wput(idx, x, y, 0)
        wput(idx, x + 1, y, 0)
        wput(idx, x, y + 1, 1)
        wput(idx, x + 1, y + 1, 4)
    return render(pal, idx)


def _tufts(rng, idx, n, colors, base_dark, hmin=2, hmax=4, light_bias=None):
    """Grass tufts: 1-3 thin blades, dark root shadow, bright tips; drawn back-to-front."""
    tufts = sorted([(int(rng.integers(0, S)), int(rng.integers(0, S))) for _ in range(n)], key=lambda t: t[1])
    for (x, y) in tufts:
        b = wget(idx, x, y)
        lvl = 0 if (light_bias is not None and b <= light_bias) else 1
        c_lo, c_mid, c_hi = colors[lvl]
        h = int(rng.integers(hmin, hmax + 1))
        shape = rng.integers(0, 3)
        if shape == 0:
            blades = [(0, h, 0)]
        elif shape == 1:
            blades = [(0, h, 0), (1, h - 1, 1)]
        else:
            blades = [(-1, h - 1, -1), (0, h, 0), (1, max(1, h - 2), 0)]
        xs = [x + ox for ox, _, _ in blades]
        for xx in range(min(xs), max(xs) + 1):
            wput(idx, xx, y + 1, base_dark)
        for (ox, bh, lean) in blades:
            for k in range(bh):
                xx = x + ox + (lean if (k == bh - 1 and bh > 2) else 0)
                c = c_hi if k == bh - 1 else (c_mid if k > 0 else c_lo)
                wput(idx, xx, y - k, c)


def tex_grass(rng):
    pal = P("#143430", "#1e4c39", "#2d663e", "#438243", "#64a14a", "#93c35a", "#cbe28a")
    low = pnoise(rng, kmax=2)
    idx = 2 + quant(0.1 + 0.8 * low, 2, 0.25)
    _tufts(rng, idx, 48, [(3, 4, 5), (3, 4, 5)], base_dark=1, light_bias=2)
    for _ in range(4):
        x, y = rng.integers(0, S, 2)
        if wget(idx, x, y) == 5:
            wput(idx, x, y, 6)
    for _ in range(3):  # tiny pale clover flowers
        x, y = rng.integers(0, S, 2)
        wput(idx, x, y, 6)
        wput(idx, x, y + 1, 1)
    return render(pal, idx)


def tex_grass_dry(rng):
    pal = P("#3f3226", "#5d4a30", "#7f6a3c", "#a28c4c", "#c1aa62", "#dbc784", "#efe2b0")
    low = pnoise(rng, kmax=2)
    dirt = pnoise(rng, kmax=3)
    idx = 2 + quant(0.1 + 0.8 * low, 2, 0.25)
    bare = dirt < 0.25
    idx[bare] = 1
    edge = ndimage.binary_dilation(bare) & ~bare & (bayer(S, S) > 0)
    idx[edge] = 1
    _tufts(rng, idx, 40, [(3, 4, 5), (4, 5, 6)], base_dark=0, hmin=2, hmax=4, light_bias=2)
    for _ in range(6):  # pebbles on bare dirt
        x, y = rng.integers(0, S, 2)
        if bare[int(y), int(x)]:
            wput(idx, x, y, 4)
            wput(idx, x + 1, y, 3)
            wput(idx, x + 1, y + 1, 0)
    return render(pal, idx)


def tex_jungle_floor(rng):
    pal = P("#141218", "#211c1f", "#30282a", "#43352b",  # earth 0-3
            "#5c3a24", "#81552e", "#a77a40", "#c8a05c",  # brown leaves 4-7
            "#1d3424", "#2c4e2f", "#466f3a", "#6c9648")  # green leaves 8-11
    low = pnoise(rng, kmax=3)
    idx = 1 + quant(low, 3, 0.3)
    leaf_types = [(4, 5, 6, 7), (8, 9, 10, 11), (4, 5, 6, 7), (8, 9, 10, 11), (5, 5, 6, 7)]
    for i in range(20):
        cx, cy = rng.random(2) * S
        L = rng.uniform(3.8, 5.6)
        Wd = rng.uniform(1.7, 2.4)
        ang = rng.uniform(0, np.pi)
        d, u, v = ellipse_mask(cx, cy, L, Wd, ang)
        sh, _, _ = ellipse_mask(cx + 1, cy + 1, L, Wd, ang)
        shadow = (sh <= 1) & (d > 1)
        idx[shadow] = np.minimum(idx[shadow], 1)
        dark, mid, light, hi = leaf_types[rng.integers(len(leaf_types))]
        # pointy leaf: narrow towards the tip
        taper = 1 - 0.55 * np.clip(u / L, 0, 1)
        d2 = (u / L) ** 2 + (v / (Wd * taper)) ** 2
        m = d2 <= 1
        side = v * math.cos(ang) < 0
        col = np.where(side, light, mid)
        rib = (np.abs(v) < 0.5) & (np.abs(u) < L - 0.8)
        col = np.where(rib, dark if not side.any() else mid, col)
        col = np.where(rib & side, mid, col)
        col = np.where(rib & ~side, dark, col)
        edge = (d2 > 0.5) & ~side
        col = np.where(edge, dark, col)
        tip = (d2 > 0.35) & side & (u < 0)
        col = np.where(tip, hi, col)
        idx[m] = col[m]
    for _ in range(3):  # twigs
        x, y = rng.integers(0, S, 2)
        L = int(rng.integers(5, 9))
        dx = 1 if rng.random() < 0.5 else -1
        pts = wline(idx, x, y, x + L * dx, y + rng.integers(-2, 3), 5)
        for (px, py) in pts:
            wput(idx, px, py + 1, 1)
        for (px, py) in pts[::3]:
            wput(idx, px, py, 6)
    return render(pal, idx)


def tex_dirt_path(rng):
    pal = P("#3d2a28", "#5c3e30", "#7b573c", "#9a7149", "#b78c5e", "#d0a978", "#e6c79a")
    low = pnoise(rng, kmax=3)
    mid = pnoise(rng, kmax=7)
    h = 0.6 * low + 0.4 * mid
    v = 0.5 + 0.35 * (low - 0.5) + 0.9 * relief(mid * 2.5)
    idx = 1 + quant(v, 5, 0.4)
    idx = np.clip(idx, 1, 5)
    for _ in range(11):
        x, y = rng.integers(0, S, 2)
        big = rng.random() < 0.4
        wput(idx, x + 1, y + 1, 0)
        wput(idx, x, y, 5)
        wput(idx, x + 1, y, 4)
        wput(idx, x, y + 1, 3)
        if big:
            wput(idx, x + 2, y + 1, 0)
            wput(idx, x + 1, y + 2, 0)
            wput(idx, x + 1, y + 1, 3)
            wput(idx, x - 1, y, 5)
            wput(idx, x, y - 1, 6)
        else:
            wput(idx, x + 1, y + 1, 1)
    for _ in range(10):
        x, y = rng.integers(0, S, 2)
        wput(idx, x, y, 1)
    return render(pal, idx)


def tex_cracked_earth(rng):
    pal = P("#3b2324", "#6a3f33", "#93603f", "#b38052", "#c99d68", "#dcb887", "#ecd3a8")
    pts = lloyd(rng.random((12, 2)) * S, 3)
    d1, d2, ids = voronoi(pts)
    e = (d2 - d1) * 0.5
    tone = rng.uniform(-0.07, 0.07, len(pts))[ids]
    h = np.clip(e / 1.4, 0, 1)
    v = 0.6 + tone + 0.45 * relief(h) + 0.1 * (pnoise(rng, kmax=6) - 0.5)
    idx = 2 + quant(v, 5, 0.3)
    crack = e < 0.5
    idx[crack] = 0
    # lower-right lip of each crack in shade, upper-left lip catches light
    sh = np.roll(np.roll(crack, 1, 0), 1, 1) & ~crack
    hi = np.roll(np.roll(crack, -1, 0), -1, 1) & ~crack
    idx[sh] = 1
    idx[hi & ~sh] = np.maximum(idx[hi & ~sh], 5)
    for _ in range(7):  # hairline sub-cracks
        x, y = rng.random(2) * S
        if e[int(y), int(x)] < 2:
            continue
        for (px, py) in random_walk(rng, int(x), int(y), int(rng.integers(2, 4)), [(1, 0), (0, 1), (1, 1), (-1, 1)]):
            if wget(idx, px, py) > 1:
                wput(idx, px, py, 2)
    return render(pal, idx)


def tex_soil_rows(rng):
    pal = P("#1d1418", "#33221f", "#4c3226", "#68462f", "#845b39", "#a07446", "#bb915c")
    wav = (pnoise(rng, kmax=2)[0] - 0.5) * 2.0
    prof = np.array([0.04, 0.12, 0.35, 0.62, 0.78, 0.72, 0.55, 0.3])
    v = np.zeros((S, S))
    for x in range(S):
        for y in range(S):
            p = (y + wav[x]) % 8
            i0 = int(p)
            f = p - i0
            v[y, x] = prof[i0] * (1 - f) + prof[(i0 + 1) % 8] * f
    v += 0.16 * (pnoise(rng, kmax=8) - 0.5) + 0.08 * (pnoise(rng, kmax=3) - 0.5)
    idx = quant(v, 7, 0.6)
    for _ in range(16):  # clods sitting on ridges
        x = int(rng.integers(0, S))
        r = int(rng.integers(0, 4))
        y = int(r * 8 + 3 - wav[x])
        wput(idx, x, y, 6)
        wput(idx, x + 1, y, 5)
        wput(idx, x, y + 1, 4)
        wput(idx, x + 1, y + 1, 2)
    for _ in range(6):  # small stones in furrow
        x = int(rng.integers(0, S))
        r = int(rng.integers(0, 4))
        y = int(r * 8 + 1 - wav[x])
        wput(idx, x, y, 5)
    return render(pal, idx)


def tex_rock(rng):
    pal = P("#251f2c", "#3e333c", "#5b4c4b", "#796658", "#978067", "#b39c7f", "#d0bd9b")
    thick = [6, 3, 7, 4, 5, 7]
    tones = [0.55, 0.36, 0.62, 0.42, 0.5, 0.58]
    kinds = ["speck", "smooth", "speck", "band", "smooth", "speck"]
    gdisp = (pnoise(rng, kmax=2)[0] - 0.5) * 3.0
    bounds = np.cumsum([0] + thick)  # 0..32
    bdisp = [(pnoise(rng, kmax=3)[0] - 0.5) * 1.6 for _ in thick]
    fine = pnoise(rng, kmax=12)
    lowv = pnoise(rng, kmax=3)
    v = np.zeros((S, S))
    layer_of = np.zeros((S, S), int)
    pos = np.zeros((S, S), int)
    for x in range(S):
        b = [bounds[k] + gdisp[x] + bdisp[k][x] for k in range(len(thick))] + [S + gdisp[x] + bdisp[0][x]]
        for y in range(S):
            yy = y
            # find layer: boundary k <= y < boundary k+1 (with wrap)
            k = None
            for kk in range(len(thick)):
                lo, hi = b[kk], b[kk + 1]
                for off in (0, S, -S):
                    if lo <= yy + off < hi:
                        k = kk
                        t = yy + off - lo
                        T = hi - lo
                        break
                if k is not None:
                    break
            if k is None:
                k, t, T = 0, 0, thick[0]
            layer_of[y, x] = k
            ti = int(t)
            Ti = int(round(T))
            val = tones[k] + 0.12 * (lowv[y, x] - 0.5)
            if kinds[k] == "speck":
                val += 0.2 * (fine[y, x] - 0.5)
            elif kinds[k] == "band":
                val += -0.12 if ti == Ti // 2 else 0.04
            else:
                val += 0.06 * (fine[y, x] - 0.5)
            if ti == 0:
                val += 0.26
            elif ti == 1:
                val += 0.08
            if ti >= Ti - 1:
                val -= 0.3
            elif ti == Ti - 2:
                val -= 0.08
            v[y, x] = val
            pos[y, x] = ti
    idx = quant(v, 7, 0.3)
    # vertical joints
    for _ in range(9):
        x = int(rng.integers(0, S))
        y = int(rng.integers(0, S))
        k = layer_of[y, x]
        yy = y
        n = 0
        while layer_of[yy % S, x] == k and n < 7:
            if pos[yy % S, x] > 0:
                wput(idx, x, yy, 1)
                if wget(idx, x + 1, yy) > 1:
                    wput(idx, x + 1, yy, min(6, wget(idx, x + 1, yy) + 1))
            yy += 1
            n += 1
    return render(pal, idx)


def tex_rock_top(rng):
    pal = P("#2a2530", "#433a40", "#5e534f", "#7b6e63", "#988a78", "#b3a68f", "#cdc2a8")
    lich = P("#7f8a5a", "#a9ad74")
    pts = lloyd(rng.random((5, 2)) * S, 3)
    d1, d2, ids = voronoi(pts)
    e = (d2 - d1) * 0.5
    tone = rng.uniform(-0.08, 0.08, len(pts))
    low = pnoise(rng, kmax=3)
    mid = pnoise(rng, kmax=8)
    hgt = 0.6 * low + 0.4 * mid
    v = 0.52 + tone[ids] + 1.0 * relief(hgt * 2.5) + 0.1 * (mid - 0.5)
    idx = 1 + quant(v, 6, 0.35)
    keep = pnoise(rng, kmax=3) > 0.35  # cracks only along some cell edges
    crack = (e < 0.5) & keep
    idx[crack] = 0
    lip = np.roll(np.roll(crack, 1, 0), 1, 1) & ~crack
    idx[lip] = np.minimum(idx[lip], 2)
    hi = np.roll(np.roll(crack, -1, 0), -1, 1) & ~crack & ~lip
    idx[hi] = np.minimum(idx[hi] + 1, 6)
    for _ in range(12):  # pits
        x, y = rng.integers(0, S, 2)
        if wget(idx, x, y) > 2:
            wput(idx, x, y, 1)
            wput(idx, x + 1, y + 1, min(6, wget(idx, x + 1, y + 1) + 1))
    img = render(pal, idx)
    for _ in range(3):  # lichen clusters
        x, y = rng.integers(0, S, 2)
        for (dx, dy, c) in [(0, 0, 1), (1, 0, 0), (0, 1, 0), (-1, 1, 0), (1, 1, 1)]:
            if rng.random() < 0.85:
                img[(y + dy) % S, (x + dx) % S] = lich[c]
    return img


def tex_cliff_dark(rng):
    pal = P("#07080f", "#10141f", "#1a212d", "#262f3a", "#36434b", "#4c5d62", "#a7cccd")
    widths = [6, 5, 7, 4, 6, 4]
    edges = np.cumsum([0] + widths)
    v = np.zeros((S, S))
    col_of = np.zeros(S, int)
    lx = np.zeros(S)
    for c in range(len(widths)):
        for x in range(edges[c], edges[c + 1]):
            col_of[x] = c
            lx[x] = (x - edges[c] + 0.5) / widths[c]
    tone = rng.uniform(-0.08, 0.08, len(widths))
    fine = pnoise(rng, kmax=9)
    for x in range(S):
        c = col_of[x]
        prof = 0.62 - 0.55 * lx[x] ** 1.3
        if lx[x] < 0.2:
            prof += 0.12
        v[:, x] = prof + tone[c] + 0.14 * (fine[:, x] - 0.5)
    idx = quant(v, 6, 0.5)
    for c in range(len(widths)):
        x0 = edges[c]
        idx[:, (x0 - 1) % S] = 0  # joint
        for _ in range(2):  # cross joints
            y = int(rng.integers(0, S))
            for x in range(x0, edges[c + 1]):
                wput(idx, x, y, 0)
                wput(idx, x, y + 1, min(5, wget(idx, x, y + 1) + 1))
    # wet streaks: specular glints running down column faces
    for _ in range(8):
        x = int(rng.integers(0, S))
        if lx[x] > 0.5:
            continue
        y = int(rng.integers(0, S))
        L = int(rng.integers(2, 6))
        for k in range(L):
            wput(idx, x, y + k, 5 if k in (0, L - 1) else 6)
    for _ in range(10):
        x, y = rng.integers(0, S, 2)
        if wget(idx, x, y) >= 3:
            wput(idx, x, y, 6)
    return render(pal, idx)


def _cobbles(rng, n, iters, mortar, tones=0.1):
    pts = lloyd(rng.random((n, 2)) * S, iters)
    d1, d2, ids = voronoi(pts)
    e = (d2 - d1) * 0.5
    h = 1 - (1 - np.clip(e / 3.0, 0, 1)) ** 2
    tone = rng.uniform(-tones, tones, len(pts))[ids]
    return pts, e, h, tone, ids


def tex_stone_floor(rng):
    pal = P("#211f29", "#38343d", "#544d51", "#716864", "#8f8478", "#ada18e", "#cbc1aa")
    pts, e, h, tone, ids = _cobbles(rng, 13, 4, 0.8)
    v = 0.5 + tone + 1.1 * relief(h * 2.2) + 0.12 * (pnoise(rng, kmax=8) - 0.5)
    idx = 1 + quant(v, 6, 0.5)
    idx[e < 1.3] = np.minimum(idx[e < 1.3], 3)
    idx[e < 0.75] = 0
    for _ in range(8):  # chips & specks
        x, y = rng.integers(0, S, 2)
        if e[int(y), int(x)] > 2:
            wput(idx, x, y, 2)
    return render(pal, idx)


def tex_moss_stone(rng):
    pal = P("#1b1e26", "#2e333b", "#474c51", "#636764", "#808278", "#9fa092",  # stone 0-5
            "#162b20", "#21432a", "#346131", "#55833a", "#82a84b", "#b1cc6a")  # moss 6-11
    pts, e, h, tone, ids = _cobbles(rng, 8, 3, 0.8)
    v = 0.48 + tone + 1.0 * relief(h * 2.2) + 0.14 * (pnoise(rng, kmax=8) - 0.5)
    idx = 1 + quant(v, 5, 0.5)
    idx[e < 1.2] = np.minimum(idx[e < 1.2], 2)
    idx[e < 0.7] = 0
    # moss: on top portions of stones and in some joints
    cy = np.array([p[1] for p in pts])[ids]
    _, dy = toff(0, 0)
    rel = ((YY + 0.5 - cy + S / 2) % S - S / 2)  # negative = upper part of stone
    mn = pnoise(rng, kmax=4)
    mf = pnoise(rng, kmax=10)
    m = 0.55 * mn + 0.25 * mf - 0.05 * rel / 4.0 + np.where(e < 1, 0.15, 0)
    moss = m > 0.62
    mv = 0.45 + 0.8 * relief(wblur(moss.astype(float), 0.7) * 2.0) + 0.3 * (mf - 0.5) + 0.15 * (h - 0.5)
    midx = 6 + quant(mv, 6, 0.6)
    idx[moss] = midx[moss]
    # fringe: dither the moss edge
    edge = moss ^ ndimage.binary_erosion(moss, border_value=0)
    fr = ndimage.binary_dilation(moss) & ~moss & (bayer(S, S) > 0.1)
    idx[fr] = 8
    return render(pal, idx)


def tex_wood_planks(rng):
    pal = P("#22141b", "#412620", "#62392b", "#83523a", "#a26c49", "#bd885b", "#d6a775")
    grain = norm01(ndimage.gaussian_filter(rng.standard_normal((S, S)), (0.5, 5), mode="wrap"))
    idx = np.zeros((S, S), int)
    for r in range(4):
        y0 = r * 8
        nseam = 1 if rng.random() < 0.5 else 2
        s0 = int(rng.integers(0, S))
        seams = [s0] if nseam == 1 else [s0, (s0 + int(rng.integers(11, 21))) % S]
        board = np.zeros(S, int)
        for x in range(S):
            board[x] = sum(1 for s in seams if (x - s) % S < (x - seams[0]) % S + 1) % len(seams)
        btone = rng.uniform(-0.1, 0.1, len(seams))
        for y in range(y0, y0 + 8):
            ly = y - y0
            for x in range(S):
                v = 0.5 + btone[board[x]] + (grain[y, x] - 0.5) * 0.7
                if ly == 0:
                    v += 0.2
                elif ly == 1:
                    v += 0.05
                elif ly == 6:
                    v -= 0.14
                idx[y, x] = 1 + quant(np.array([[v]]), 6, 0.0)[0, 0] if ly != 7 else 0
        for s in seams:
            for y in range(y0, y0 + 7):
                wput(idx, s, y, 1)
                wput(idx, s + 1, y, min(6, wget(idx, s + 1, y) + 1))
            for nx in (s - 2, s + 3):
                wput(idx, nx, y0 + 2, 1)
                wput(idx, nx, y0 + 5, 1)
                wput(idx, nx - 1, y0 + 1, 5)
        if rng.random() < 0.6:  # knot
            kx = int(rng.integers(0, S))
            ky = y0 + 3
            for (dx, dy, c) in [(-1, 0, 2), (0, 0, 1), (1, 0, 2), (0, -1, 3), (0, 1, 3), (-2, 0, 3), (2, 0, 3)]:
                wput(idx, kx + dx, ky + dy, c)
    # long dark grain lines
    for _ in range(6):
        r = int(rng.integers(0, 4))
        y = r * 8 + int(rng.integers(2, 6))
        x = int(rng.integers(0, S))
        L = int(rng.integers(5, 12))
        for k in range(L):
            if wget(idx, x + k, y) > 1:
                wput(idx, x + k, y, max(2, wget(idx, x + k, y) - 1))
    return render(pal, idx)


def tex_wood_wall(rng):
    pal = P("#1d191b", "#332b29", "#4c4138", "#665849", "#81725d", "#9d8f76", "#bcb095")
    widths = [7, 5, 8, 6, 6]
    edges = np.cumsum([0] + widths)
    grain = norm01(ndimage.gaussian_filter(rng.standard_normal((S, S)), (6, 0.45), mode="wrap"))
    v = np.zeros((S, S))
    for c in range(len(widths)):
        tone = rng.uniform(-0.1, 0.1)
        for x in range(edges[c], edges[c + 1]):
            lx = x - edges[c]
            val = 0.52 + tone + (grain[:, x] - 0.5) * 0.8
            if lx == 0:
                val = val + 0.18
            elif lx == widths[c] - 2:
                val = val - 0.12
            v[:, x] = val
    idx = 1 + quant(v, 6, 0.25)
    for c in range(len(widths)):
        idx[:, edges[c + 1] - 1] = 0
        if rng.random() < 0.7:  # horizontal split
            y = int(rng.integers(0, S))
            for x in range(edges[c] + 1, edges[c + 1] - 2):
                wput(idx, x, y, 1)
                wput(idx, x, y + 1, min(6, wget(idx, x, y + 1) + 1))
        x = edges[c] + int(rng.integers(1, max(2, widths[c] - 2)))
        y = int(rng.integers(0, S))
        for k in range(int(rng.integers(4, 9))):  # split along grain
            wput(idx, x, y + k, 1)
    for ny in (5, 21):  # nail rows with a little rust drip
        for c in range(len(widths)):
            x = edges[c] + widths[c] // 2
            wput(idx, x, ny, 0)
            wput(idx, x - 1, ny - 1, 6)
            wput(idx, x, ny + 1, 2)
            wput(idx, x, ny + 2, 2)
    return render(pal, idx)


def tex_bamboo_wall(rng):
    pal = P("#3a2416", "#5c3d22", "#835c2f", "#a77b3d", "#c49851", "#ddb86f", "#efd69a")
    fib_h = norm01(ndimage.gaussian_filter(rng.standard_normal((S, S)), (0.4, 3), mode="wrap"))
    fib_v = norm01(ndimage.gaussian_filter(rng.standard_normal((S, S)), (3, 0.4), mode="wrap"))
    v = np.zeros((S, S))
    w = 4
    for y in range(S):
        for x in range(S):
            u, vv = x // w, y // w
            k = (u + vv) % 4
            if k < 2:  # horizontal strip on top
                ly = y % w
                sp = k * w + x % w
                val = 0.62 + [0.2, 0.06, 0.0, -0.22][ly] + (fib_h[y, x] - 0.5) * 0.25
            else:
                lx = x % w
                sp = (k - 2) * w + y % w
                val = 0.44 + [0.16, 0.05, -0.02, -0.24][lx] + (fib_v[y, x] - 0.5) * 0.25
            if sp in (0, 7):
                val -= 0.2
            elif sp in (1, 6):
                val -= 0.05
            v[y, x] = val
    idx = quant(v, 7, 0.35)
    return render(pal, idx)


def tex_thatch(rng):
    pal = P("#271c19", "#45332a", "#675035", "#8a6d44", "#ab8d58", "#c8ab72", "#e1cb95")
    R = 4
    ext, strand = [], []
    for r in range(R):
        e = np.clip(np.round(rng.normal(1.6, 1.0, S)), 0, 3).astype(int)
        ext.append(e)
        s = rng.random(S)
        s = 0.6 * s + 0.4 * ndimage.gaussian_filter1d(rng.random(S), 1.5, mode="wrap")
        strand.append(norm01(s))
    v = np.zeros((S, S))
    for y in range(S):
        for x in range(S):
            r = y // 8
            p = y % 8
            prev = (r - 1) % R
            if p < ext[prev][x]:
                row, pe = prev, 8 + p
            else:
                row, pe = r, p
            d = pe - ext[(row - 1) % R][x]
            val = [0.02, 0.3, 0.42][d] if d < 3 else 0.48 + 0.03 * (d - 3)
            if pe >= 8:
                val += 0.06
            val += (strand[row][x] - 0.5) * 0.5
            v[y, x] = val
    idx = quant(v, 7, 0.0)
    for _ in range(5):  # stray strands
        x, y = rng.integers(0, S, 2)
        for k in range(3):
            if wget(idx, x, y + k) > 1:
                wput(idx, x, y + k, 6)
    return render(pal, idx)


def tex_tin_roof(rng):
    tin = P("#1f2530", "#36404d", "#55616d", "#78858d", "#9eaaae", "#cad1cd")
    rust = P("#2c1714", "#4c2219", "#71331d", "#965024", "#b8702f", "#d39250")
    prof = np.array([0.2, 0.42, 0.66, 0.92, 0.78, 0.55, 0.35, 0.12])
    v = prof[XX % 8] + 0.06 * (pnoise(rng, kmax=6) - 0.5)
    v[0] -= 0.25
    v[1] += 0.05
    streak = norm01(ndimage.gaussian_filter(rng.random((S, S)), (4.5, 0.6), mode="wrap"))
    blot = pnoise(rng, kmax=3)
    # rust lives in the channels and runs downward
    chan = np.isin(XX % 8, [0, 6, 7]).astype(float)
    rm = 0.5 * blot + 0.45 * streak + 0.12 * chan
    rusty = rm > 0.6
    ti = quant(v, 6, 0.4)
    img = render(tin, ti)
    ri = quant(v * 0.9 + 0.05 * (pnoise(rng, kmax=10) - 0.5), 6, 0.6)
    rimg = render(rust, ri)
    fringe = (rm > 0.56) & ~rusty & (bayer(S, S) > 0.2)
    m = rusty | fringe
    img[m] = rimg[m]
    for x in range(3, S, 8):  # nails on ridge tops at the overlap
        img[2, x] = tin[5] if not rusty[2, x] else rust[5]
        img[3, x] = tin[0]
        img[2, (x - 1) % S] = tin[1]
    return img


def tex_plaster(rng):
    pal = P("#7a6f66", "#a0978a", "#c2baa9", "#d8d1c0", "#e7e2d4", "#f4f1e7")
    brick = P("#5a2b22", "#8c4a34", "#ad6646", "#c98a62")
    low = pnoise(rng, kmax=2)
    mid = pnoise(rng, kmax=6)
    v = 0.55 + 0.35 * (low - 0.5) + 0.12 * (mid - 0.5)
    idx = 3 + quant(v, 3, 0.0)
    stain = pnoise(rng, kmax=3) > 0.78  # faint damp stains
    idx[stain] = np.minimum(idx[stain], 3)
    img = render(pal, idx)
    # small chip revealing brick
    cx, cy = 9.5, 20.5
    d, u, vv = ellipse_mask(cx, cy, 2.8, 1.8, 0.25)
    d = d + 0.3 * (pnoise(rng, kmax=6) - 0.5)
    hole = d < 1
    rim = (d < 1.7) & ~hole
    bi = np.where((YY % 3) == 0, 0, np.where(((XX + (YY // 3) * 2) % 5) == 0, 0, 2))
    img[hole] = brick[bi[hole]]
    up = (YY + 0.5 - cy) < 0
    img[hole & up & (bi > 0)] = brick[1]
    img[rim & up] = pal[1]
    img[rim & ~up] = pal[5]
    # branching hairline cracks
    for (x, y, n) in [(22, 2, 14), (3, 6, 8)]:
        pts = random_walk(rng, x, y, n, [(0, 1), (1, 1), (-1, 1), (0, 1)])
        for i, (px, py) in enumerate(pts):
            img[py % S, px % S] = pal[1]
            q = ((py) % S, (px + 1) % S)
            if not hole[q]:
                img[q] = pal[5]
    return img


def tex_tile_floor(rng):
    pal = P("#45484f", "#73787b", "#a2a49f", "#c3c2ba", "#d8d7ce", "#e8e7e0", "#f6f5f0")
    blood = P("#26050b", "#420912", "#5f1018", "#7f1b1f", "#9e3a33")
    grime = pnoise(rng, kmax=3)
    v = np.zeros((S, S))
    tt = rng.uniform(-0.07, 0.07, (4, 4))
    for y in range(S):
        for x in range(S):
            lx, ly = x % 8, y % 8
            val = 0.78 + tt[y // 8, x // 8] - 0.35 * max(0, grime[y, x] - 0.55)
            if ly == 1 or lx == 1:
                val += 0.07
            if ly == 7 or lx == 7:
                val -= 0.08
            v[y, x] = val
    idx = 1 + quant(v, 6, 0.6)
    gr = (XX % 8 == 0) | (YY % 8 == 0)
    idx[gr] = np.where(grime[gr] > 0.55, 0, 1)
    for _ in range(10):  # grime specks
        x, y = rng.integers(0, S, 2)
        if not gr[y, x]:
            idx[y, x] = 2
    img = render(pal, idx)
    # blood: one splat + drops + small smear
    field = np.full((S, S), 9.0)
    cx, cy = 20.5, 12.5
    blobs = [(cx, cy, 3.4, 2.6)] + [(cx + rng.uniform(-4, 4), cy + rng.uniform(-3, 3), rng.uniform(0.9, 1.8), rng.uniform(0.9, 1.6)) for _ in range(4)]
    for (bx, by, rx, ry) in blobs:
        d, _, _ = ellipse_mask(bx, by, rx, ry)
        field = np.minimum(field, d)
    for (bx, by, r) in [(cx + 6, cy - 3, 0.8), (cx - 6, cy + 4, 0.9), (cx + 2, cy + 6, 0.7), (6.5, 25.5, 1.2), (8.5, 27.5, 0.7)]:
        d, _, _ = ellipse_mask(bx, by, r, r)
        field = np.minimum(field, d)
    d, u, _ = ellipse_mask(5.5, 26.0, 4.5, 0.9, -0.5)  # smear
    field = np.minimum(field, d + 0.4 * (np.abs(u) / 4.5))
    m = field < 1
    core = field < 0.45
    bidx = np.where(core, 1, 2)
    bidx = np.where((field > 0.75) & m, 3, bidx)
    bidx = np.where(gr & m, 0, bidx)
    img[m] = blood[bidx[m]]
    img[11, 19] = blood[4]
    img[11, 20] = blood[3]
    return img


def tex_concrete(rng):
    pal = P("#383c43", "#51565b", "#6a6e6f", "#838581", "#9c9c96", "#b6b5ad")
    low = pnoise(rng, kmax=2)
    mid = pnoise(rng, kmax=7)
    v = 0.5 + 0.35 * (low - 0.5) + 0.15 * (mid - 0.5)
    idx = 2 + quant(v, 3, 0.0)
    for _ in range(16):  # aggregate
        x, y = rng.integers(0, S, 2)
        c = 5 if rng.random() < 0.4 else 1
        wput(idx, x, y, c)
    for _ in range(8):  # pores
        x, y = rng.integers(0, S, 2)
        wput(idx, x, y, 0)
        wput(idx, x + 1, y + 1, 4)
    pts = random_walk(rng, 4, 10, 20, [(1, 0), (1, 1), (1, -1), (0, 1), (1, 0)])
    for (px, py) in pts:
        wput(idx, px, py, 1)
    return render(pal, idx)


def tex_carpet(rng):
    pal = P("#1a0910", "#3e0d18", "#661722", "#8c2229", "#ad3530",  # reds 0-4
            "#1b2244", "#2c3c6c",  # navy 5-6
            "#a8742e", "#d8aa4a", "#f2d78e")  # golds 7-9
    u = XX % 16
    v = YY % 16
    du = np.abs(u - 7.5)
    dv = np.abs(v - 7.5)
    d = du + dv
    idx = np.full((S, S), 3)
    fab = bayer(S, S) + 0.6 * (pnoise(rng, kmax=10) - 0.5)
    idx = np.where(fab > 0.25, 4, np.where(fab < -0.35, 2, 3))
    idx = np.where(d <= 1, 9, idx)
    idx = np.where((d == 2), 8, idx)
    idx = np.where((d == 3), 5, idx)
    idx = np.where((d >= 4) & (d <= 5), 6, idx)
    idx = np.where((d >= 4) & (d <= 5) & ((du < 0.6) | (dv < 0.6)), 8, idx)
    idx = np.where(d == 6, 8, idx)
    idx = np.where(d == 7, 1, idx)
    idx = np.where((d == 9) & ((du < 0.6) | (dv < 0.6)), 8, idx)
    idx = np.where((d == 10) & ((du < 1.6) & (dv > 6) | (dv < 1.6) & (du > 6)), 7, idx)
    idx = np.where(d == 12, np.where((u + v) % 2 == 0, 7, 1), idx)
    idx = np.where(d == 13, 0, idx)
    idx = np.where(d >= 14, 5, idx)
    idx = np.where(d >= 15, 8, idx)
    # border-ish lattice: thin dark weft lines every 16
    return render(pal, idx)


def tex_straw_floor(rng):
    pal = P("#2f2216", "#4b3721", "#6f532b", "#94743a", "#b6954e", "#d2b468", "#ead596")
    low = pnoise(rng, kmax=2)
    idx = 1 + quant(low, 2, 0.3)
    strands = []
    for i in range(80):
        ang = rng.choice([0.0, 0.0, 0.35, -0.35, 0.6, -0.6, 0.0, 0.2, -0.2]) + rng.normal(0, 0.08)
        L = rng.uniform(4, 9)
        x, y = rng.random(2) * S
        tone = int(rng.choice([2, 3, 3, 4, 4, 5, 5, 6]))
        strands.append((tone, x, y, ang, L))
    strands.sort(key=lambda s: s[0])
    for (tone, x, y, ang, L) in strands:
        x1, y1 = x + math.cos(ang) * L, y + math.sin(ang) * L
        wline(idx, x, y + 1, x1, y1 + 1, lambda a, b, c: min(c, 1 if tone >= 4 else 2))
        pts = wline(idx, x, y, x1, y1, tone)
        if tone >= 4 and len(pts) > 2:
            wput(idx, *pts[1], min(6, tone + 1))
    return render(pal, idx)


def tex_wood_dark(rng):
    pal = P("#0f080d", "#1d1015", "#2f181b", "#45231f", "#5c3025", "#77412c", "#94573a")
    nx = pnoise(rng, kmax=2)
    fine = norm01(ndimage.gaussian_filter(rng.standard_normal((S, S)), (0.4, 4), mode="wrap"))
    g = np.sin(2 * np.pi * (YY / 4.0 + 1.6 * nx))
    v = 0.48 + 0.16 * g + 0.25 * (fine - 0.5)
    for y0 in (0, 16):
        v[y0] -= 0.4
        v[(y0 + 1) % S] += 0.12
    sheen = np.isin(YY % 16, [5, 6]) & (pnoise(rng, kmax=3) > 0.55)
    v[sheen] += 0.15
    idx = quant(v, 7, 0.4)
    for (x0, y0) in ((int(rng.integers(0, S)), 0), (int(rng.integers(0, S)), 16)):
        for y in range(y0 + 1, y0 + 16):
            pass
    return render(pal, idx)


def tex_white_void(rng):
    pal = P("#e6e5e0", "#edece7", "#f3f2ee", "#f9f8f5")
    low = pnoise(rng, kmax=2)
    idx = 1 + quant(0.25 + 0.5 * low, 2, 0.9)
    lat = ((XX + YY) % 16 == 0) | ((XX - YY) % 16 == 0)
    idx[lat] = np.maximum(idx[lat] - 1, 0)
    idx[(XX % 16 == 0) & (YY % 16 == 8)] = 3
    idx[(XX % 16 == 8) & (YY % 16 == 0)] = 3
    return render(pal, idx)


def tex_mud(rng):
    pal = P("#150f10", "#241917", "#36271e", "#4a3624", "#60472d", "#785b38", "#9a8b77", "#cbc2b0")
    low = pnoise(rng, kmax=3)
    mid = pnoise(rng, kmax=7)
    h = 0.55 * low + 0.45 * mid
    r = relief(h * 3.2)
    v = 0.5 + 0.25 * (low - 0.5) + 1.2 * r
    idx = 2 + quant(v, 4, 0.3)
    pud = h < 0.22
    idx[pud] = 1
    deep = h < 0.14
    idx[deep] = 0
    # reflections in puddles: short horizontal sky glints
    py, px = np.nonzero(deep)
    for k in rng.permutation(len(py))[:3]:
        y, x = py[k], px[k]
        wput(idx, x, y, 6)
        if pud[y, (x + 1) % S]:
            wput(idx, x + 1, y, 6)
    # wet glints on lump tops
    gy, gx = np.nonzero((r > 0.06) & ~pud)
    for k in rng.permutation(len(gy))[:12]:
        wput(idx, gx[k], gy[k], 7 if rng.random() < 0.4 else 6)
    return render(pal, idx)


TEXTURES = [
    ("sand", tex_sand), ("sand_wet", tex_sand_wet), ("grass", tex_grass), ("grass_dry", tex_grass_dry),
    ("jungle_floor", tex_jungle_floor), ("dirt_path", tex_dirt_path), ("cracked_earth", tex_cracked_earth),
    ("soil_rows", tex_soil_rows), ("rock", tex_rock), ("rock_top", tex_rock_top), ("cliff_dark", tex_cliff_dark),
    ("moss_stone", tex_moss_stone), ("stone_floor", tex_stone_floor), ("wood_planks", tex_wood_planks),
    ("wood_wall", tex_wood_wall), ("bamboo_wall", tex_bamboo_wall), ("thatch", tex_thatch),
    ("tin_roof", tex_tin_roof), ("plaster", tex_plaster), ("tile_floor", tex_tile_floor),
    ("concrete", tex_concrete), ("carpet", tex_carpet), ("straw_floor", tex_straw_floor),
    ("wood_dark", tex_wood_dark), ("white_void", tex_white_void), ("mud", tex_mud),
]


# =================================================================== previews
def _font():
    try:
        return ImageFont.load_default(size=14)
    except TypeError:
        return ImageFont.load_default()


def checker(w, h, a=(40, 44, 56), b=(50, 55, 68), cell=8):
    yy, xx = np.mgrid[0:h, 0:w]
    m = ((yy // cell + xx // cell) % 2).astype(bool)
    out = np.zeros((h, w, 3), np.uint8)
    out[~m] = a
    out[m] = b
    return Image.fromarray(out)


def contact_sheet(items, scale, cols, path, bg=(24, 26, 32), checker_bg=False, label_h=18, pad=10):
    """items: list of (label, PIL image)."""
    font = _font()
    cells = [(lab, im.resize((im.width * scale, im.height * scale), Image.NEAREST)) for lab, im in items]
    cw = max(c.width for _, c in cells)
    ch = max(c.height for _, c in cells)
    rows = (len(cells) + cols - 1) // cols
    W = cols * (cw + pad) + pad
    H = rows * (ch + label_h + pad) + pad
    sheet = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(sheet)
    for i, (lab, c) in enumerate(cells):
        x = pad + (i % cols) * (cw + pad)
        y = pad + (i // cols) * (ch + label_h + pad)
        d.text((x, y), lab, fill=(230, 220, 190), font=font)
        if c.mode == "RGBA":
            base = checker(c.width, c.height, cell=scale * 2) if checker_bg else Image.new("RGB", c.size, (34, 38, 50))
            base.paste(c, (0, 0), c)
            c = base
        sheet.paste(c, (x, y + label_h))
    sheet.save(path)
    return path


def gen_textures():
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    out = []
    for i, (name, fn) in enumerate(TEXTURES):
        rng = np.random.default_rng(1000 + i * 17)
        arr = fn(rng)
        assert arr.shape == (S, S, 3), name
        im = Image.fromarray(arr.astype(np.uint8), "RGB")
        im.save(TEX_DIR / f"{name}.png")
        out.append((name, im))
    # previews: single tiles 8x, 9 per sheet; 3x3 tilings 4x, 9 per sheet
    for k in range(0, len(out), 9):
        n = k // 9 + 1
        contact_sheet(out[k:k + 9], 8, 3, PREV_DIR / f"preview_textures_{n}.png")
        tiled = [(lab, Image.fromarray(np.tile(np.array(im), (3, 3, 1)))) for lab, im in out[k:k + 9]]
        contact_sheet(tiled, 4, 3, PREV_DIR / f"preview_tiling_{n}.png")
    return [n for n, _ in out]


def C(h):
    return np.array(hx(h), np.uint8)


def blank(w, h):
    return np.zeros((h, w, 4), np.uint8)


def grid(w, h):
    ys, xs = np.mgrid[0:h, 0:w] + 0.5
    return xs, ys


def paint(img, mask, col):
    img[mask] = C(col) if isinstance(col, str) else col


def levels(img, mask, val, cols, ths):
    """Paint mask with cols[i] where val > ths[i] (first match wins), else cols[-1]."""
    out = np.full(val.shape, len(cols) - 1)
    for i in reversed(range(len(ths))):
        out = np.where(val > ths[i], i, out)
    for i, c in enumerate(cols):
        paint(img, mask & (out == i), c)


def outline(img, col, diag=False, only_transparent=True):
    a = img[..., 3] > 0
    st = np.ones((3, 3), bool) if diag else ndimage.generate_binary_structure(2, 1)
    o = ndimage.binary_dilation(a, st) & ~a
    paint(img, o, col)
    return img


def dfade(img, amount, offset=0.0):
    """Ordered-dither fade: remove `amount` (0..1) of the opaque pixels."""
    h, w = img.shape[:2]
    b = bayer(h, w) + 0.5
    b = (b + offset) % 1.0
    img[b < amount] = 0
    return img


def stroke_field(pts, widths, w, h):
    xs, ys = grid(w, h)
    F = np.full((h, w), 1e9)
    for (x, y), r in zip(pts, widths):
        F = np.minimum(F, np.hypot(xs - x, ys - y) - r)
    return F


def resample(poly, step=0.4):
    poly = np.asarray(poly, float)
    seg = np.hypot(*np.diff(poly, axis=0).T)
    L = seg.sum()
    n = max(2, int(L / step))
    cum = np.concatenate([[0], np.cumsum(seg)])
    t = np.linspace(0, L, n)
    x = np.interp(t, cum, poly[:, 0])
    y = np.interp(t, cum, poly[:, 1])
    return np.stack([x, y], 1), t / max(L, 1e-6)


def bezier(p0, p1, p2, n=40):
    t = np.linspace(0, 1, n)[:, None]
    p0, p1, p2 = map(lambda p: np.asarray(p, float), (p0, p1, p2))
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t ** 2 * p2


def poly_mask(xs, ys, pts):
    """Convex polygon fill (any winding)."""
    pts = np.asarray(pts, float)
    sgn = None
    m_pos = np.ones(xs.shape, bool)
    m_neg = np.ones(xs.shape, bool)
    for i in range(len(pts)):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % len(pts)]
        cr = (bx - ax) * (ys - ay) - (by - ay) * (xs - ax)
        m_pos &= cr >= 0
        m_neg &= cr <= 0
    return m_pos | m_neg


def px(img, x, y, col):
    x, y = int(math.floor(x)), int(math.floor(y))
    if 0 <= y < img.shape[0] and 0 <= x < img.shape[1]:
        img[y, x] = C(col) if isinstance(col, str) else col


def sparkle(img, x, y, size, c_core, c_arm, c_tip=None):
    px(img, x, y, c_core)
    for k in range(1, size + 1):
        c = c_arm if k < size or c_tip is None else c_tip
        for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            px(img, x + dx * k, y + dy * k, c)


def plus_sign(img, x, y, arm, fill, line, hi=None):
    pts = [(x, y)] + [(x + dx * k, y + dy * k) for k in range(1, arm + 1) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
    for (a, b) in pts:
        for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1), (0, 0)):
            q = (a + dx, b + dy)
            if q not in pts:
                px(img, *q, line)
    for (a, b) in pts:
        px(img, a, b, fill)
    if hi:
        px(img, x - 1 if arm > 1 else x, y - 1 if arm > 1 else y, hi)
        px(img, x, y - arm, hi)
        px(img, x - arm, y, hi)


def disc(img, cx, cy, r, col):
    h, w = img.shape[:2]
    xs, ys = grid(w, h)
    paint(img, np.hypot(xs - cx, ys - cy) <= r, col)


# ----------------------------------------------------------------- slash


def fx_slash():
    W = H = 48
    xs, ys = grid(W, H)
    cols = ["#ffffff", "#fff6c4", "#ffe15c", "#ffab2e", "#ee6c1f", "#a8361a"]
    ths = [0.82, 0.64, 0.46, 0.3, 0.16]

    def arc(img, cx, cy, R, Tmax, tail, head, tm, heat):
        dx, dy = xs - cx, ys - cy
        r = np.hypot(dx, dy)
        th = np.arctan2(dy, dx)
        th0, th1 = math.radians(-100), math.radians(6)
        s = (th - th0) / (th1 - th0)
        depth = R - r
        T = Tmax * tm * np.clip(np.sin(np.pi * np.clip(s, 0, 1)), 0, 1) ** 0.55
        span = max(head - tail, 1e-3)
        a = np.clip((s - tail) / span, 0, 1)
        T = T * a ** 0.8 * np.clip((head - s) / 0.05, 0, 1) ** 0.5
        m = (s >= tail) & (s <= head) & (depth >= 0) & (depth <= T) & (T > 0.35)
        hv = heat * (1.05 - 0.8 * depth / np.maximum(T, 1e-3) - 0.45 * (1 - a))
        levels(img, m, hv, cols, ths)

    params = [(0.0, 0.3, 0.8, 1.0), (0.0, 0.7, 1.0, 1.05), (0.03, 1.0, 1.0, 1.0),
              (0.4, 1.0, 0.75, 0.8), (0.74, 1.0, 0.45, 0.6), (0.92, 1.0, 0.25, 0.42)]
    rng = np.random.default_rng(5)
    sparks = [(rng.uniform(0.35, 1.0), rng.uniform(0, 3), rng.uniform(2, 5)) for _ in range(9)]
    frames = []
    for f, (tail, head, tm, heat) in enumerate(params):
        img = blank(W, H)
        if 1 <= f <= 3:  # trailing echo arc
            arc(img, 8, 42, 21, 4.0, max(0, tail - 0.05), max(0.05, head - 0.18), tm, heat * 0.62)
        arc(img, 8, 42, 31, 9.5, tail, head, tm, heat)
        if f >= 3:
            for (s0, o, sp) in sparks:
                if s0 < tail - 0.1 and f < 5:
                    continue
                th = math.radians(-100) + s0 * math.radians(106)
                rr = 31 + o + sp * (f - 2)
                x, y = 8 + math.cos(th) * rr, 42 + math.sin(th) * rr
                c = "#fff6c4" if f == 3 else ("#ffe15c" if f == 4 else "#ffab2e")
                px(img, x, y, c)
                if f == 3:
                    px(img, x - math.cos(th), y - math.sin(th), "#ffab2e")
        frames.append(img)
    return frames


# ------------------------------------------------------------------ claw


def fx_claw():
    W = H = 48
    d = np.array([0.6, 0.8])
    n = np.array([-d[1], d[0]])
    c = np.array([24.0, 24.0])
    offs = [-9.0, 0.0, 9.0]
    lens = [30.0, 38.0, 30.0]
    prog = [0.55, 1.0, 1.0, 1.0, 1.0]
    wid = [2.3, 2.7, 2.4, 1.7, 1.1]
    pal_f = [("#ffffff", "#ff5c5c", "#7a0c1a"), ("#ffffff", "#ff4848", "#6a0a18"),
             ("#ffd4d4", "#e3222e", "#5a0814"), ("#ff7a7a", "#b2141f", "#3e0610"),
             ("#c8282e", "#7a0c18", None)]
    frames = []
    for f in range(5):
        img = blank(W, H)
        core_c, mid_c, out_c = pal_f[f]
        Fo = np.full((H, W), 1e9)
        Fc = np.full((H, W), 1e9)
        for i in range(3):
            p = prog[f] if f > 0 else np.clip(prog[f] * 1.3 - 0.2 * i, 0.05, 1)
            u = np.linspace(0, p, 60)
            pts = [c + d * (uu - 0.5) * lens[i] + n * (offs[i] + 2.2 * math.sin(math.pi * uu)) for uu in u]
            ws = wid[f] * np.sin(np.pi * np.clip(u, 0.02, 0.98)) ** 0.5 + 0.25
            if f == 0:
                ws = ws * np.clip((p - u) / 0.12 + 0.4, 0, 1)
            Fo = np.minimum(Fo, stroke_field(pts, ws, W, H))
            Fc = np.minimum(Fc, stroke_field(pts, ws * 0.42, W, H))
        if out_c:
            paint(img, Fo < 1.0, out_c)
        paint(img, Fo < 0, mid_c)
        paint(img, Fc < 0, core_c)
        if f >= 3:  # drips
            for i in range(3):
                base = c + d * 0.1 * lens[i] + n * (offs[i] + 2.0)
                dy = 3 + (f - 3) * 4
                px(img, base[0], base[1] + dy, "#7a0c18")
                px(img, base[0], base[1] + dy + 1, "#b2141f" if f == 3 else "#7a0c18")
        if f == 4:
            dfade(img, 0.3)
        frames.append(img)
    return frames


# ------------------------------------------------------------------- hit


def fx_hit():
    W = H = 32
    xs, ys = grid(W, H)
    dx, dy = xs - 16, ys - 16
    r = np.hypot(dx, dy)
    th = np.arctan2(dy, dx)
    sp4 = np.maximum(0, np.cos(4 * th)) ** 6
    sp4b = np.maximum(0, np.cos(4 * (th - math.pi / 4))) ** 6
    frames = []
    cols = ["#ffffff", "#fff7b8", "#ffd84a", "#ff9a2a", "#c84a1a"]
    # f0: small flash
    img = blank(W, H)
    R0 = 3.5 + 3.5 * sp4 + 1.5 * sp4b
    levels(img, r < R0, 1 - r / R0, cols, [0.45, 0.25, 0.1, 0.0])
    frames.append(img)
    # f1: big star
    img = blank(W, H)
    R1 = 5.5 + 9.5 * sp4 + 5 * sp4b
    m = r < R1
    levels(img, m, 1 - r / R1, cols, [0.55, 0.35, 0.18, 0.07])
    outline(img, "#7a2410")
    frames.append(img)
    # f2: hollow star ring
    img = blank(W, H)
    R2 = 8 + 7 * sp4 + 3.5 * sp4b
    m = (r < R2) & (r > 4.5 + 2 * sp4)
    levels(img, m, 1 - (r - 4) / np.maximum(R2 - 4, 1), cols[1:], [0.6, 0.35, 0.12])
    frames.append(img)
    # f3: sparks + ring fragments
    img = blank(W, H)
    ring = (np.abs(r - 11.5) < 0.8) & (np.cos(8 * th) > 0.2)
    paint(img, ring, "#ffab2e")
    for k in range(8):
        a = k * math.pi / 4
        L = 14 if k % 2 == 0 else 11
        for t in (L - 1, L):
            px(img, 16 + math.cos(a) * t, 16 + math.sin(a) * t, "#fff7b8" if t == L else "#ffd84a")
    dfade(img, 0.15)
    frames.append(img)
    return frames


# ----------------------------------------------------------------- blood


def fx_blood():
    W = H = 48
    xs, ys = grid(W, H)
    rng = np.random.default_rng(23)
    c = np.array([24.0, 21.0])
    cols = {"out": "#22030a", "dark": "#4c0911", "base": "#7c121b", "lite": "#a8232a", "spec": "#f2a08e"}
    parts = []
    for i in range(24):
        a = rng.uniform(-math.pi, math.pi)
        a = a * 0.85 - 0.25 * math.pi * (abs(a) > 2.2)  # mild upward bias
        sp = rng.uniform(9, 20)
        sz = rng.uniform(0.7, 2.1)
        parts.append((a, sp, sz))
    spikes = rng.uniform(0, 2 * math.pi, 9)
    times = [0.06, 0.18, 0.36, 0.56, 0.78, 1.0]
    core_r = [3.6, 5.2, 4.6, 3.2, 1.8, 0.0]
    frames = []
    for f, t in enumerate(times):
        dens = np.full((H, W), -9.0)
        dx, dy = xs - c[0], ys - (c[1] + 6 * t * t)
        r = np.hypot(dx, dy)
        th = np.arctan2(dy, dx)
        if core_r[f] > 0:
            sp = sum(np.maximum(0, np.cos(th - s)) ** 40 for s in spikes)
            Rb = core_r[f] * (1 + (0.55 if f < 2 else 0.25) * sp) * (1 + 0.08 * np.sin(5 * th + f))
            dens = np.maximum(dens, 1 - r / Rb)
        specs = []
        for (a, spd, sz) in parts:
            if f == 0:
                continue
            tt = t ** 0.6
            pxp = c[0] + math.cos(a) * spd * tt
            pyp = c[1] + math.sin(a) * spd * tt + 13 * tt * tt
            if not (3 < pxp < W - 3 and 3 < pyp < H - 3):
                continue
            szz = sz * (1.15 - 0.55 * tt)
            if szz < 0.55:
                continue
            vx, vy = math.cos(a) * spd, math.sin(a) * spd + 26 * tt
            vn = math.hypot(vx, vy) + 1e-6
            stretch = 1 + min(1.6, vn / 18) * (1 if f <= 3 else 0.5)
            ux, uy = (xs - pxp), (ys - pyp)
            along = (ux * vx + uy * vy) / vn
            perp = (-ux * vy + uy * vx) / vn
            dd = np.hypot(along / (szz * stretch), perp / szz)
            dens = np.maximum(dens, 1 - dd)
            if szz > 1.3:
                specs.append((pxp - 0.6, pyp - 0.6))
        m = dens > 0
        img = blank(W, H)
        h = ndimage.gaussian_filter(np.clip(dens, 0, 1), 0.8)
        gx = np.gradient(h, axis=1)
        gy = np.gradient(h, axis=0)
        lit = (gx + gy) / 1.41
        paint(img, m, cols["base"])
        paint(img, m & (lit > 0.06), cols["lite"])
        paint(img, m & (lit < -0.05), cols["dark"])
        for (sx, sy) in specs:
            px(img, sx, sy, cols["spec"])
        if core_r[f] > 3:
            px(img, c[0] - 2, c[1] - 2 + 10 * t * t, cols["spec"])
            px(img, c[0] - 1, c[1] - 2 + 10 * t * t, cols["lite"])
        outline(img, cols["out"])
        if f == 5:
            dfade(img, 0.25)
        frames.append(img)
    return frames


def fx_fire():
    W = H = 48
    xs, ys = grid(W, H)
    rng = np.random.default_rng(31)
    N = pnoise(rng, (64, 64), kmax=7)
    c = np.array([24.0, 27.0])
    puffs = [(0.0, 0.0, 0.95)]
    for k in range(8):
        a = 2 * math.pi * k / 8 + rng.uniform(-0.3, 0.3)
        d = rng.uniform(0.45, 0.7)
        puffs.append((math.cos(a) * d, math.sin(a) * d * 0.85 - 0.12, rng.uniform(0.42, 0.62)))
    Rf = [5, 10, 14, 16.5, 17.5, 18, 18, 17.5]
    heat = [1.35, 1.2, 1.02, 0.85, 0.66, 0.48, 0.33, 0.2]
    erode = [0, 0, 0, 0.03, 0.1, 0.2, 0.33, 0.47]
    rise = [0, 0, 0.6, 1.6, 3.0, 4.6, 6.2, 7.8]
    fire_c = ["#fffbe6", "#ffe866", "#ffb22e", "#f56b1f", "#c9331c", "#7e1e1c"]
    fire_t = [1.05, 0.86, 0.66, 0.5, 0.35, 0.23]
    frames = []
    embers = [(rng.uniform(0, 2 * math.pi), rng.uniform(14, 22)) for _ in range(10)]
    for f in range(8):
        R = Rf[f]
        D = np.full((H, W), -9.0)
        for (ox, oy, rr) in puffs:
            pc = c + np.array([ox, oy]) * R + np.array([0, -rise[f] * (0.4 + 0.6 * (oy < 0))])
            D = np.maximum(D, 1 - np.hypot(xs - pc[0], ys - pc[1]) / (rr * R))
        k = 1.0 / (1 + 0.09 * f)
        n = ndimage.map_coordinates(N, [((ys - c[1]) * k + 32).ravel(), ((xs - c[0]) * k + 32).ravel()],
                                    order=1, mode="wrap").reshape(H, W)
        val = D + 0.28 * (n - 0.5)
        inside = val > erode[f]
        T = heat[f] * (val * 1.25 + 0.15)
        hgt = ndimage.gaussian_filter(np.clip(val, 0, 1), 1.0)
        lit = (np.gradient(hgt, axis=1) + np.gradient(hgt, axis=0)) / 1.41
        img = blank(W, H)
        fire = inside & (T > fire_t[-1])
        levels(img, fire, T, fire_c, fire_t[:-1])
        smoke = inside & ~fire
        paint(img, smoke, "#4a3a3e")
        paint(img, smoke & (lit > 0.02), "#6f6160")
        paint(img, smoke & (lit > 0.06), "#93847c")
        paint(img, smoke & (lit < -0.03), "#2c2229")
        if f == 0:
            ring = (np.abs(np.hypot(xs - c[0], ys - c[1]) - 8.5) < 0.7)
            paint(img, ring & (bayer(H, W) > -0.2), "#ffe866")
        if 2 <= f <= 6:
            for (a, sp) in embers:
                rr = sp * (0.3 + 0.13 * f)
                ex, ey = c[0] + math.cos(a) * rr, c[1] + math.sin(a) * rr * 0.8 - 1.2 * f + 0.35 * f * f * 0.3
                col = "#ffe866" if f < 4 else ("#ffb22e" if f < 6 else "#c9331c")
                px(img, ex, ey, col)
        if f == 7:
            dfade(img, 0.35)
        frames.append(img)
    return frames


# ------------------------------------------------------------------- ice


def fx_ice():
    W = H = 48
    xs, ys = grid(W, H)
    base = np.array([24.0, 37.0])
    shards = [(-90, 28, 7.0), (-62, 20, 5.6), (-118, 20, 5.6), (-34, 13, 4.4), (-146, 13, 4.4),
              (-77, 24, 5.0), (-103, 23, 5.0)]
    grow = [0.32, 0.74, 1.0, 1.0]
    cols = dict(out="#14245a", dark="#2b58ad", mid="#5aa3e6", light="#a9e3fa", white="#f4feff")
    frames = []

    def shard(b, ang, L, w):
        a = math.radians(ang)
        dv = np.array([math.cos(a), math.sin(a)])
        nv = np.array([-dv[1], dv[0]])
        tip = b + dv * L
        mid = b + dv * L * 0.3
        m = poly_mask(xs, ys, [b - dv * 0.8, mid + nv * w / 2, tip, mid - nv * w / 2])
        side = (xs - b[0]) * nv[0] + (ys - b[1]) * nv[1]
        lit = (side > 0) if (nv @ np.array([-1, -1])) > 0 else (side < 0)
        return m, lit, np.abs(side) < 0.5, tip, dv

    for f in range(6):
        img = blank(W, H)
        if 1 <= f <= 4:  # frost patch on the ground
            rx = [0, 9, 13, 15, 14][f]
            d = np.hypot((xs - base[0]) / rx, (ys - base[1] - 1.5) / (rx * 0.3))
            paint(img, d < 1, cols["mid"] if f < 4 else cols["dark"])
            paint(img, (d < 0.8) & (ys < base[1] + 1.5), cols["light"] if f < 4 else cols["mid"])
        layers = []
        if f < 4:
            for (ang, L, w) in shards:
                layers.append(shard(base, ang, L * grow[f], w * (0.6 + 0.4 * grow[f])))
        else:
            rng = np.random.default_rng(77)
            t = f - 3
            for (ang, L, w) in shards:
                a = math.radians(ang)
                dv = np.array([math.cos(a), math.sin(a)])
                for u in (0.35, 0.7, 1.0):
                    if f == 5 and u < 0.5:
                        continue
                    p = base + dv * L * u + dv * (2 + 3 * t) + np.array([rng.uniform(-1.5, 1.5), 2.0 * t * t])
                    layers.append(shard(p, ang + rng.uniform(-60, 60), 5.5 - t, 3.2 - 0.4 * t))
        sh = blank(W, H)
        for (m, lit, axis, tip, dv) in layers:
            paint(sh, m & ~lit, cols["mid"])
            paint(sh, m & lit, cols["light"])
            paint(sh, m & axis, cols["white"])
        for (m, lit, axis, tip, dv) in layers:
            if f < 4:
                px(sh, tip[0] - dv[0] * 1.2, tip[1] - dv[1] * 1.2, cols["white"])
        outline(sh, cols["out"])
        compose(img, sh)
        if f in (2, 3, 4):
            spots = [(24, 6), (37, 15), (11, 16), (33, 25)] if f in (2, 3) else [(16, 10), (34, 8), (41, 24), (7, 22)]
            for i, (sx, sy) in enumerate(spots):
                if (i + f) % 2 == 0 or f == 3:
                    sparkle(img, sx, sy, 2 if f == 3 else 1, cols["white"], cols["light"])
        if f == 5:
            dfade(img, 0.3)
        frames.append(img)
    return frames


# ------------------------------------------------------------------ heal


def fx_heal():
    W = H = 48
    xs, ys = grid(W, H)
    rng = np.random.default_rng(41)
    parts = []
    for i in range(11):
        parts.append(dict(x=rng.uniform(8, 40), ph=i / 11 + rng.uniform(-0.03, 0.03), kind=["plus", "spark", "spark", "plus2"][i % 4],
                          gold=(i % 3 == 0), wob=rng.uniform(0, 6.28)))
    frames = []
    for f in range(8):
        img = blank(W, H)
        t = f / 8
        # ground ring (two rings staggered so the loop is seamless)
        for k in (0, 1):
            ph = (t * 2 + k * 0.5) % 1.0
            rx = 6 + 14 * ph
            ry = rx * 0.32
            d = np.hypot((xs - 24) / rx, (ys - 41) / ry)
            em = d < 1
            ring = em & ~ndimage.binary_erosion(em)
            col = "#c8f07a" if ph < 0.4 else ("#6fcf57" if ph < 0.75 else "#2f8a43")
            paint(img, ring & ((bayer(H, W) > -0.3) if ph < 0.75 else (bayer(H, W) > 0.15)), col)
        # rising light streaks
        for i in range(4):
            sx = 12 + i * 8 + (3 if i % 2 else 0)
            ly = (40 - ((t + i * 0.27) % 1.0) * 36)
            for k in range(4):
                if 0 <= ly + k < H:
                    px(img, sx, ly + k, "#f4ffd0" if k == 0 else ("#9be36a" if k < 3 else "#3aa04a"))
        for p in parts:
            life = (p["ph"] + t) % 1.0
            y = 42 - life * 38
            x = p["x"] + 1.5 * math.sin(p["wob"] + life * 6.28)
            size = 2 if 0.2 < life < 0.75 else 1
            if life > 0.92:
                continue
            gold = p["gold"]
            if p["kind"].startswith("plus"):
                arm = 2 if (p["kind"] == "plus2" and size == 2) else 1
                plus_sign(img, round(x), round(y), arm, "#fff1a8" if gold else "#8ff06a", "#1e6a34" if not gold else "#8a5a12",
                          hi="#ffffff")
            else:
                sparkle(img, round(x), round(y), size, "#ffffff", "#f6d65a" if gold else "#b8f27a",
                        "#c48a1e" if gold else "#3aa04a")
        frames.append(img)
    return frames


# ---------------------------------------------------------------- poison


def fx_poison():
    W = H = 48
    xs, ys = grid(W, H)
    rng = np.random.default_rng(53)
    cols = dict(out="#1c0829", dark="#4a1868", mid="#7c2fa3", lite="#b25fd6", hi="#f0d0ff", glow="#d690f5")
    bubbles = [dict(x=rng.uniform(10, 38), y0=rng.uniform(34, 42), r=rng.uniform(2.2, 4.6), ph=i / 7 + rng.uniform(0, 0.08),
                    wob=rng.uniform(0, 6.28)) for i in range(7)]
    frames = []
    for f in range(6):
        img = blank(W, H)
        t = f / 6
        # toxic mist pool
        d = np.hypot((xs - 24) / 17, (ys - 41) / 4.5)
        nm = 0.25 * np.sin(xs * 0.7 + f * 1.05) + 0.15 * np.sin(xs * 1.3 - f * 2.1)
        mist = d + nm * 0.4 < 1
        paint(img, mist & (bayer(H, W) > -0.1), cols["dark"])
        paint(img, (d + nm * 0.4 < 0.65) & (bayer(H, W) > 0.15), cols["mid"])
        for b in bubbles:
            life = (b["ph"] + t) % 1.0
            y = b["y0"] - 30 * life
            x = b["x"] + 1.8 * math.sin(b["wob"] + life * 9)
            if life < 0.82:
                r = b["r"] * min(1.0, 0.35 + life * 2.5)
                dd = np.hypot(xs - x, ys - y)
                body = dd <= r
                paint(img, body, cols["out"])
                inner = dd <= r - 1
                paint(img, inner, cols["mid"])
                sh = inner & (np.hypot(xs - x - 0.9, ys - y - 0.9) > r - 1.6)
                paint(img, sh, cols["dark"])
                hl = inner & (np.hypot(xs - (x - r * 0.4), ys - (y - r * 0.4)) < r * 0.38)
                paint(img, hl, cols["lite"])
                px(img, x - r * 0.45, y - r * 0.45, cols["hi"])
            elif life < 0.93:  # pop!
                r = b["r"] + 1.5
                for k in range(6):
                    a = k * math.pi / 3 + 0.3
                    px(img, x + math.cos(a) * r, y + math.sin(a) * r, cols["glow"])
                    px(img, x + math.cos(a) * (r - 1.2), y + math.sin(a) * (r - 1.2), cols["mid"])
        frames.append(img)
    return frames


# ---------------------------------------------------------------- shield


def fx_shield():
    W = H = 48
    xs, ys = grid(W, H)
    dx, dy = xs - 24, ys - 24
    # flat-top hexagon "radius" (apothem-based)
    hexd = np.maximum(np.abs(dy), np.abs(dx) * math.sqrt(3) / 2 + np.abs(dy) / 2)
    # small hex lattice
    s = 5.0
    a1 = np.array([1.5 * s, math.sqrt(3) / 2 * s])
    a2 = np.array([0.0, math.sqrt(3) * s])
    pts = np.array([i * a1 + j * a2 for i in range(-8, 9) for j in range(-8, 9)]) + np.array([24, 24])
    D = np.stack([np.hypot(xs - p[0], ys - p[1]) for p in pts])
    D.sort(axis=0)
    lat = (D[1] - D[0]) < 0.9
    cols = dict(out="#0b2160", dark="#1d4fb8", mid="#3f8fe8", lite="#8fd2ff", white="#effbff")
    scale = [0.55, 1.0, 1.0, 1.0, 1.04, 1.08]
    frames = []
    for f in range(6):
        img = blank(W, H)
        R = 19.5 * scale[f]
        hd = hexd / R
        inside = hd < 1
        edge = (hd >= 1 - 1.6 / R) & inside
        if f in (1, 2, 3):
            fill = inside & ~edge & (bayer(H, W) > (0.2 if f != 2 else 0.05))
            paint(img, fill, cols["dark"])
        if f in (1, 2, 3, 4):
            if f == 1:
                lm = lat & inside & ~edge & (hd > 0.55)
            elif f == 2:
                lm = lat & inside & ~edge
            elif f == 3:
                ripple = np.abs(hd - 0.62) < 0.2
                lm = lat & inside & ~edge & ripple
            else:
                lm = lat & inside & ~edge & (bayer(H, W) > 0.0) & (hd > 0.75)
            paint(img, lm, cols["mid"] if f != 3 else cols["lite"])
            if f == 3:
                paint(img, lat & inside & ~edge & (np.abs(hd - 0.62) < 0.07), cols["white"])
        ecol = [cols["mid"], cols["white"], cols["lite"], cols["lite"], cols["mid"], cols["dark"]][f]
        em = edge
        if f == 5:
            em = edge & (np.cos(np.arctan2(dy, dx) * 6) > -0.2)
        paint(img, em, ecol)
        if f in (1, 2):
            inner_edge = (hd >= 1 - 2.6 / R) & (hd < 1 - 1.6 / R)
            paint(img, inner_edge, cols["mid"])
            # vertex glints
            for k in range(6):
                a = k * math.pi / 3
                sparkle(img, 24 + math.cos(a) * R * 1.0, 24 + math.sin(a) * R * 1.0, 2 if f == 1 else 1, cols["white"], cols["lite"])
        outline(img, cols["out"]) if f in (1, 2, 3) else None
        if f == 0:
            dfade(img, 0.35)
        if f == 5:
            dfade(img, 0.3)
        frames.append(img)
    return frames


# ------------------------------------------------------------------ dark


def fx_dark():
    W = H = 48
    xs, ys = grid(W, H)
    c = np.array([24.0, 24.0])
    cols = dict(core="#06030b", body="#1f0c33", rim="#5a2391", glow="#9c55d8", hi="#e2b6ff")
    angs = [200, 255, 310, 350, 140, 35]
    curls = [1, -1, 1, -1, 1, -1]
    tend = []
    for a, cl in zip(angs, curls):
        ar = math.radians(a)
        p0 = c + np.array([math.cos(ar), math.sin(ar)]) * 20
        ctrl = c + np.array([math.cos(ar + cl * 0.8), math.sin(ar + cl * 0.8)]) * 15
        tend.append(bezier(p0, ctrl, c, 50))
    frames = []
    for f in range(6):
        img = blank(W, H)
        if f < 3:
            prog = [0.4, 0.75, 1.0][f]
            Fb = np.full((H, W), 1e9)
            Fc = np.full((H, W), 1e9)
            for pts in tend:
                n = max(int(len(pts) * prog), 3)
                seg = pts[:n]
                u = np.linspace(0, 1, n)
                # thin tail at the origin, thickest just behind the head, pointed head
                ws = 2.6 * np.sin(np.pi * (0.12 + 0.8 * u)) ** 0.8 * (0.6 + 0.4 * prog) + 0.3
                ws[-3:] *= np.array([0.7, 0.45, 0.25])
                Fb = np.minimum(Fb, stroke_field(seg, ws, W, H))
                Fc = np.minimum(Fc, stroke_field(seg, ws * 0.45, W, H))
            paint(img, (Fb < 1.6) & (bayer(H, W) > 0.15), cols["glow"])
            paint(img, Fb < 0.8, cols["rim"])
            paint(img, Fb < 0, cols["body"])
            paint(img, Fc < 0, cols["core"])
            if f == 2:
                disc(img, 24, 24, 4.5, cols["rim"])
                disc(img, 24, 24, 3.4, cols["core"])
                px(img, 22, 22, cols["hi"])
        elif f == 3:
            dx, dy = xs - 24, ys - 24
            r = np.hypot(dx, dy)
            th = np.arctan2(dy, dx)
            sp = sum(np.maximum(0, np.cos(th - math.radians(a) + math.pi)) ** 30 for a in angs)
            R = 8.5 + 9 * sp
            paint(img, (r < R + 1.6) & (bayer(H, W) > 0.0), cols["glow"])
            paint(img, r < R + 0.8, cols["rim"])
            paint(img, r < R, cols["body"])
            paint(img, r < 6, cols["core"])
            paint(img, (np.abs(r - 7.5) < 0.6) & (np.cos(th * 5) > 0.3), cols["hi"])
        else:
            rng = np.random.default_rng(19 + f)
            t = f - 3
            for k in range(9):
                a = k * 2 * math.pi / 9 + 0.3
                rr = 9 + 5 * t
                p0 = c + np.array([math.cos(a), math.sin(a)]) * rr
                p1 = c + np.array([math.cos(a + 0.5), math.sin(a + 0.5)]) * (rr + 4)
                F = stroke_field(np.linspace(p0, p1, 10), np.linspace(1.4 / t, 0.3, 10), W, H)
                paint(img, F < 0.7, cols["rim"])
                paint(img, F < 0, cols["body"] if f == 4 else cols["rim"])
            if f == 4:
                disc(img, 24, 24, 3.0, cols["rim"])
                disc(img, 24, 24, 2.0, cols["core"])
            for k in range(6):
                a = rng.uniform(0, 6.28)
                rr = rng.uniform(6, 20)
                px(img, 24 + math.cos(a) * rr, 24 + math.sin(a) * rr - 2 * t, cols["hi"])
            if f == 5:
                dfade(img, 0.4)
        frames.append(img)
    return frames


def compose(dst, src):
    m = src[..., 3] > 0
    dst[m] = src[m]
    return dst


def _arrow_sprite(hw, head_h, stem_hw, stem_h, cols):
    """Up-pointing arrow with outline. cols = (outline, dark, mid, light, hi)."""
    w = 2 * hw + 1
    h = head_h + stem_h
    m = np.zeros((h, w), bool)
    for k in range(head_h):
        half = round(k * hw / max(head_h - 1, 1))
        m[k, hw - half:hw + half + 1] = True
    m[head_h:, hw - stem_hw:hw + stem_hw + 1] = True
    img = blank(w + 2, h + 2)
    mm = np.zeros((h + 2, w + 2), bool)
    mm[1:-1, 1:-1] = m
    yy = np.mgrid[0:h + 2, 0:w + 2][0]
    xx = np.mgrid[0:h + 2, 0:w + 2][1]
    paint(img, mm, cols[2])
    paint(img, mm & (yy <= 1 + head_h * 0.6), cols[3])
    paint(img, mm & (yy >= h - 1), cols[1])
    left_edge = mm & ~np.roll(mm, 1, 1)
    paint(img, left_edge & (yy < h - 1), cols[4])
    right_edge = mm & ~np.roll(mm, -1, 1)
    paint(img, right_edge & (yy > 2), cols[1])
    outline(img, cols[0])
    return img


def fx_buff(cols=("#4f1600", "#c94a14", "#ff8a2a", "#ffc65a", "#fff3b8"), trail=("#ffb04a", "#ff8a2a")):
    W, H = 32, 48
    small = _arrow_sprite(2, 3, 0, 2, cols)
    arrows = [(_arrow_sprite(4, 5, 1, 5, cols), 15, 0.0), (_arrow_sprite(3, 4, 1, 3, cols), 6, 0.36),
              (_arrow_sprite(3, 4, 1, 4, cols), 25, 0.69)]
    frames = []
    for f in range(6):
        img = blank(W, H)
        for (spr, cx, ph) in arrows:
            life = (ph + f / 6) % 1.0
            if life > 0.9:
                continue
            fading = life < 0.1 or life > 0.76
            s = small if fading else spr
            ah, aw = s.shape[:2]
            y = int(round(H - 4 - life * (H + 2))) + (spr.shape[0] - ah) // 2
            x = cx - aw // 2
            layer = blank(W, H)
            tl = 4 if fading else 8
            for k in range(1, tl + 1):
                ty = y + ah - 1 + k
                if 0 <= ty < H and (k < 4 or (k + f) % 2 == 0):
                    px(layer, cx, ty, trail[0] if k < 4 else trail[1])
            sy0, sx0 = max(0, y), max(0, x)
            sy1, sx1 = min(H, y + ah), min(W, x + aw)
            if sy1 > sy0 and sx1 > sx0:
                sub = s[sy0 - y:sy1 - y, sx0 - x:sx1 - x]
                region = layer[sy0:sy1, sx0:sx1]
                msk = sub[..., 3] > 0
                region[msk] = sub[msk]
            compose(img, layer)
        frames.append(img)
    return frames


def fx_debuff():
    fr = fx_buff(cols=("#08143e", "#1f4aa6", "#3f84e0", "#86c4f6", "#e4f6ff"), trail=("#5aa0ee", "#2f6ad0"))
    return [np.ascontiguousarray(np.flipud(f)) for f in fr]


# ------------------------------------------------------------------ peck


def fx_peck():
    W = H = 32
    xs, ys = grid(W, H)
    cols = dict(out="#3e1c06", dark="#c2650e", mid="#f5a11d", lite="#ffd659", hi="#fff6c8")

    def beak(img, tipx, cy, L=9, hh=4.0, squash=1.0):
        bx = tipx - L
        L2 = L * squash
        upper = poly_mask(xs, ys, [(tipx - L + (L - L2), cy - hh), (tipx, cy), (tipx - L + (L - L2), cy)])
        lower = poly_mask(xs, ys, [(tipx - L + (L - L2), cy + 0.01), (tipx - 1, cy + 0.01), (tipx - L + (L - L2), cy + hh * 0.7)])
        m = upper | lower
        layer = blank(W, H)
        paint(layer, upper, cols["mid"])
        paint(layer, upper & (ys < cy - hh * 0.45), cols["lite"])
        paint(layer, lower, cols["dark"])
        paint(layer, m & (np.abs(ys - cy) < 0.5) & (xs < tipx - 1), cols["out"])
        outline(layer, cols["out"])
        compose(img, layer)

    def speed(img, x0, x1, ys_):
        for i, y in enumerate(ys_):
            for x in range(int(x0), int(x1)):
                t = (x - x0) / max(1, x1 - x0)
                if t < 0.35 and (x + i) % 2 == 0:
                    continue
                px(img, x, y, "#ffffff" if t > 0.6 else "#fff1b0")

    def burst(img, r0, r1, fade=False):
        for k in range(7):
            a = -math.pi / 2 + (k - 3) * 0.42
            for rr in np.arange(r0, r1, 0.5):
                px(img, 24 + math.cos(a) * rr, 16 + math.sin(a) * rr, "#ffffff" if rr < (r0 + r1) / 2 else "#ffd659")
            a2 = math.pi / 2 + (k - 3) * 0.42
            if k % 2 == 0:
                for rr in np.arange(r0, r1 - 1, 0.5):
                    px(img, 24 + math.cos(a2) * rr, 16 + math.sin(a2) * rr, "#ffd659")
        if fade:
            dfade(img, 0.35)

    frames = []
    img = blank(W, H)
    speed(img, 0, 5, [12, 16, 20])
    beak(img, 14, 16)
    frames.append(img)
    img = blank(W, H)
    speed(img, 0, 14, [11, 15, 19, 22])
    beak(img, 23, 16, squash=0.85)
    frames.append(img)
    img = blank(W, H)
    disc(img, 24.5, 16.5, 3.2, "#fff6c8")
    disc(img, 24.5, 16.5, 2.0, "#ffffff")
    burst(img, 4, 8)
    beak(img, 23, 16, squash=0.7)
    frames.append(img)
    img = blank(W, H)
    burst(img, 7, 11, fade=True)
    for (x, y) in [(20, 23), (28, 22), (27, 9), (19, 10)]:
        px(img, x, y, "#d6c09a")
    frames.append(img)
    return frames


# ------------------------------------------------------------- lightning


def _bolt_path(rng, x0, y0, y1, step=(4, 7), jit=5, lo=5, hi=27):
    pts = [(x0, y0)]
    x, y = x0, y0
    while y < y1:
        y = min(y1, y + rng.integers(*step))
        x = float(np.clip(x + rng.uniform(-jit, jit), lo, hi))
        pts.append((x, y))
    return pts


def fx_lightning():
    W, H = 32, 64
    xs, ys = grid(W, H)
    rng = np.random.default_rng(3)
    main = _bolt_path(rng, 16, 0, 58)
    br1 = [main[3]] + _bolt_path(rng, main[3][0], main[3][1], main[3][1] + 14, step=(3, 6), jit=4)[1:]
    br1 = [(p[0] + i * 1.6, p[1]) for i, p in enumerate(br1)]
    br2 = [main[6]] + _bolt_path(rng, main[6][0], main[6][1], main[6][1] + 10, step=(3, 5), jit=3)[1:]
    br2 = [(p[0] - i * 1.8, p[1]) for i, p in enumerate(br2)]
    rng2 = np.random.default_rng(8)
    main2 = _bolt_path(rng2, 15, 0, 58)
    cols = dict(core="#ffffff", pale="#d4f2ff", glow="#62b6ff", outer="#2b4fd0", hot="#fff4a8")

    def field(path, w):
        pts, _ = resample(path, 0.35)
        return stroke_field(pts, np.full(len(pts), w), W, H)

    def bolt(img, path, wc, wp, wg, wo, dith=0.0):
        F = field(path, 0.0)
        paint(img, (F < wo) & (bayer(H, W) > dith), cols["outer"])
        paint(img, F < wg, cols["glow"])
        paint(img, F < wp, cols["pale"])
        paint(img, F < wc, cols["core"])

    def impact(img, rx, ry, sparks):
        d = np.hypot((xs - 15.5) / rx, (ys - 59.5) / ry)
        paint(img, (d < 1) & (bayer(H, W) > -0.2), cols["glow"])
        paint(img, d < 0.6, cols["pale"])
        paint(img, d < 0.3, cols["core"])
        for k in range(sparks):
            a = math.pi + k * math.pi / (sparks - 1)
            for rr in (rx + 1, rx + 2):
                px(img, 15.5 + math.cos(a) * rr, 59 + math.sin(a) * rr * 0.6, cols["hot"])

    frames = []
    img = blank(W, H)
    cut = [p for p in main if p[1] <= 30] + [main[len([p for p in main if p[1] <= 30])]]
    bolt(img, cut, 0.0, 0.6, 1.3, 2.2, dith=0.2)
    frames.append(img)
    img = blank(W, H)
    for b in (br1, br2):
        bolt(img, b, 0.0, 0.5, 1.2, 2.0, dith=0.25)
    bolt(img, main, 0.6, 1.2, 2.2, 3.4, dith=0.15)
    impact(img, 5, 2.2, 0)
    frames.append(img)
    img = blank(W, H)
    for b in (br1, br2):
        bolt(img, b, 0.4, 0.8, 1.6, 2.6, dith=0.2)
    bolt(img, main, 0.9, 1.6, 2.8, 4.2, dith=0.05)
    impact(img, 8, 3.2, 5)
    frames.append(img)
    img = blank(W, H)
    bolt(img, main2, 0.4, 0.9, 1.8, 2.8, dith=0.25)
    impact(img, 6, 2.4, 4)
    frames.append(img)
    img = blank(W, H)
    bolt(img, main2, 0.0, 0.4, 1.2, 1.9, dith=0.3)
    dfade(img, 0.45)
    for (x, y) in [(9, 56), (22, 55), (6, 60), (26, 60), (13, 52)]:
        px(img, x, y, cols["hot"])
    frames.append(img)
    return frames


# ------------------------------------------------------------------- egg


def fx_egg():
    W = H = 32
    xs, ys = grid(W, H)
    shell = dict(out="#4a3426", base="#f4e8d2", lite="#fffaf0", shade="#d6c19c", dark="#b09068")
    yolk = dict(out="#8a4508", base="#ffcf33", lite="#fff2a0", dark="#ef8813")
    white = dict(out="#8fa6b0", base="#ffffff", shade="#dce7ec")

    def egg(img, cx, cy, rx, ry, rot=0.0, crack=False):
        dx, dy = xs - cx, ys - cy
        ca, sa = math.cos(rot), math.sin(rot)
        u = dx * ca + dy * sa
        v = -dx * sa + dy * ca
        rxx = rx * (1 + 0.14 * v / ry)
        d = (u / rxx) ** 2 + (v / ry) ** 2
        m = d <= 1
        layer = blank(W, H)
        paint(layer, m, shell["base"])
        paint(layer, m & (np.hypot(u + rx * 0.35, v + ry * 0.4) < rx * 0.45), shell["lite"])
        paint(layer, m & (np.hypot(u + rx * 0.4, v + ry * 0.5) < rx * 0.9) & (d > 0.55) & (u > -rx * 0.2), shell["shade"])
        paint(layer, m & (d > 0.6) & (u + v > rx * 0.6), shell["dark"])
        px(layer, cx - rx * 0.4, cy - ry * 0.45, "#ffffff")
        if crack:
            zz = [(cx - rx, cy), (cx - rx * 0.5, cy - 1.5), (cx, cy + 0.5), (cx + rx * 0.5, cy - 1.5), (cx + rx, cy)]
            pts, _ = resample(zz, 0.4)
            for (x, y) in pts:
                if m[int(min(H - 1, max(0, y))), int(min(W - 1, max(0, x)))]:
                    px(layer, x, y, shell["out"])
        outline(layer, shell["out"])
        compose(img, layer)

    def blob(cx, cy, R, spikes, seed, flat=1.0, amp=0.55):
        rng = np.random.default_rng(seed)
        dx, dy = (xs - cx), (ys - cy) / flat
        r = np.hypot(dx, dy)
        th = np.arctan2(dy, dx)
        sp = sum(np.maximum(0, np.cos(th - a)) ** 24 for a in rng.uniform(0, 6.28, spikes))
        return r < R * (1 + amp * sp + 0.06 * np.sin(5 * th + seed))

    def splat(img, cx, cy, Rw, flat, yolk_r, yolk_ry, eyes=False, seed=4, drips=0):
        layer = blank(W, H)
        wm = blob(cx, cy, Rw, 7, seed, flat, amp=0.55 if flat > 0.6 else 0.22)
        paint(layer, wm, white["base"])
        sh = wm & ~np.roll(np.roll(wm, -1, 0), -1, 1)
        paint(layer, sh, white["shade"])
        for k in range(drips):
            x = cx - Rw + 3 + k * (2 * Rw - 6) / max(1, drips - 1)
            for j in range(2 + k % 2):
                px(layer, x, cy + Rw * flat * 0.8 + j, white["base"])
        outline(layer, white["out"])
        d = np.hypot((xs - cx) / yolk_r, (ys - cy + 0.5) / yolk_ry)
        ym = d <= 1
        paint(layer, ym, yolk["base"])
        paint(layer, ym & (d > 0.55) & (ys > cy), yolk["dark"])
        paint(layer, ym & (np.hypot((xs - cx + yolk_r * 0.35) / yolk_r, (ys - cy + yolk_ry * 0.35) / yolk_ry) < 0.35), yolk["lite"])
        ring = ndimage.binary_dilation(ym) & ~ym
        paint(layer, ring, yolk["out"])
        if eyes:
            for ex in (cx - 3, cx + 2):
                ey = cy - 0.6
                for (a, b) in ((0, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)):
                    px(layer, ex + a, ey + b, yolk["out"])
        compose(img, layer)

    frames = []
    img = blank(W, H)
    egg(img, 16, 6.5, 3.6, 4.6, rot=0.35)
    for x in (12, 20):
        px(img, x, 1, "#fff6dc")
        px(img, x, 2, "#d6c19c")
    frames.append(img)
    img = blank(W, H)
    for (x, y0) in ((11, 5), (16, 3), (21, 5)):
        for k in range(5):
            if k % 2 == 0 or k > 2:
                px(img, x, y0 + k, "#fff6dc" if k > 2 else "#d6c19c")
    egg(img, 16, 17, 3.8, 5.0, rot=0.15)
    frames.append(img)
    img = blank(W, H)
    egg(img, 16, 23.5, 5.4, 3.9, crack=True)
    for (x, y, dx, dy) in ((8, 26, -1, 0), (24, 26, 1, 0), (9, 20, -1, -1), (23, 20, 1, -1)):
        px(img, x, y, "#fff6dc")
        px(img, x + dx, y + dy, "#fff6dc")
    frames.append(img)
    img = blank(W, H)
    splat(img, 16, 19, 6.5, 0.8, 3.6, 3.0, seed=2)
    rng = np.random.default_rng(12)
    for (x, y, s) in [(6, 13, 0), (25, 12, 1), (9, 8, 1), (23, 6, 0), (4, 20, 0), (28, 19, 1)]:
        tri = poly_mask(xs, ys, [(x, y), (x + 3, y - 1 - s), (x + 2, y + 2)])
        layer = blank(W, H)
        paint(layer, tri, shell["base"])
        outline(layer, shell["out"])
        compose(img, layer)
    for (x, y) in [(3, 15), (29, 14), (16, 10), (11, 11)]:
        px(img, x, y, "#ffffff")
    frames.append(img)
    img = blank(W, H)
    splat(img, 16, 25, 11.5, 0.4, 5.6, 3.0, eyes=True, seed=5)
    for (x, y) in [(5, 21), (25, 21)]:
        layer = blank(W, H)
        paint(layer, poly_mask(xs, ys, [(x, y), (x + 3, y - 1), (x + 3, y + 1)]), shell["base"])
        outline(layer, shell["out"])
        compose(img, layer)
    for (x, y, c) in [(10, 14, "#ffe15c"), (22, 13, "#ffe15c"), (16, 11, "#fff6c4")]:
        sparkle(img, x, y, 1, "#ffffff", c)
    frames.append(img)
    img = blank(W, H)
    splat(img, 16, 24.5, 12, 0.34, 5.8, 2.8, eyes=True, seed=5, drips=4)
    for (x, y) in [(5, 22), (25, 22)]:
        layer = blank(W, H)
        paint(layer, poly_mask(xs, ys, [(x, y), (x + 3, y - 1), (x + 3, y + 1)]), shell["base"])
        outline(layer, shell["out"])
        compose(img, layer)
    frames.append(img)
    return frames


# ------------------------------------------------------- single sprites


def ss_render(w, h, ss, fn):
    """Supersampled RGBA render; fn(xs, ys) -> (rgb float (H,W,3) 0..1, alpha (H,W) 0..1) at ss*res."""
    ys, xs = np.mgrid[0:h * ss, 0:w * ss] + 0.5
    xs, ys = xs / ss, ys / ss
    rgb, a = fn(xs, ys)
    pm = rgb * a[..., None]
    pm = pm.reshape(h, ss, w, ss, 3).mean(axis=(1, 3))
    a = a.reshape(h, ss, w, ss).mean(axis=(1, 3))
    rgb = np.where(a[..., None] > 1e-4, pm / np.maximum(a[..., None], 1e-4), 0)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = np.clip(rgb * 255 + 0.5, 0, 255)
    out[..., 3] = np.clip(a * 255 + 0.5, 0, 255)
    return out


def col01(h):
    return np.array(hx(h)[:3], float) / 255


def sp_blood_puddle():
    W, H = 40, 20
    xs, ys = grid(W, H)
    rng = np.random.default_rng(9)
    N = pnoise(rng, (20, 40), kmax=4)
    f = np.hypot((xs - 19) / 15, (ys - 10.5) / 6.5) + 0.35 * (N - 0.5)
    for (bx, by, r) in [(31, 7, 3.2), (9, 13, 3.6), (22, 14, 3.0)]:
        f = np.minimum(f, np.hypot((xs - bx) / r, (ys - by) / (r * 0.7)) + 0.2)
    m = f < 1
    img = blank(W, H)
    paint(img, m, "#6c0f18")
    paint(img, m & (f < 0.62), "#520a13")
    paint(img, m & (f < 0.3), "#40070f")
    upper = m & ~np.roll(m, 1, 0)
    paint(img, upper, "#8e1d22")
    lower = m & ~np.roll(m, -1, 0)
    paint(img, lower, "#3a060d")
    for (x, y) in [(14, 7), (15, 7), (27, 9), (24, 6)]:
        px(img, x, y, "#c4524a")
    px(img, 15, 6, "#f2a090")
    for (x, y) in [(2, 9), (37, 14), (35, 3), (5, 17)]:
        px(img, x, y, "#6c0f18")
    outline(img, "#24040a")
    return img


def sp_feather():
    def fn(xs, ys):
        t = np.clip((ys - 0.5) / 15.0, 0, 1)
        sx = 4.0 + 0.9 * np.sin(t * 2.4 - 0.4)
        prof = np.sin(np.pi * np.clip(t * 0.95 + 0.02, 0, 1)) ** 0.55
        wl = 3.1 * prof
        wr = 2.4 * prof
        off = xs - sx
        inside = ((off < 0) & (-off < wl) | (off >= 0) & (off < wr)) & (ys > 0.3) & (ys < 13.8)
        notch = (np.abs(((ys + off * 0.6) % 5.0) - 2.5) < 0.18) & (np.abs(off) > 1.0)
        vane = inside & ~notch
        shaft = (np.abs(off) < 0.32) & (ys > 0.6) & (ys < 15.7)
        edge = np.clip(np.abs(off) / np.maximum(np.where(off < 0, wl, wr), 0.1), 0, 1)
        rgb = col01("#ffffff") * (1 - edge[..., None] * 0.5) + col01("#c9d2e2") * (edge[..., None] * 0.5)
        rgb = np.where(shaft[..., None], col01("#b8bfcc"), rgb)
        a = (vane | shaft).astype(float) * np.where(shaft & ~vane, 1.0, 0.96)
        return rgb, a
    return ss_render(8, 16, 8, fn)


def sp_petal():
    def fn(xs, ys):
        bx, by = 2.0, 14.5
        ang = math.radians(-50)
        dx, dy = xs - bx, ys - by
        u = dx * math.cos(ang) + dy * math.sin(ang)
        v = -dx * math.sin(ang) + dy * math.cos(ang)
        L = 15.0
        t = np.clip(u / L, 0, 1)
        width = 4.6 * np.sqrt(np.clip(t, 0, 1)) * (1 - t ** 3) ** 0.7 + 0.3
        width = width * (1 + 0.25 * t)
        vv = v + 0.9 * np.sin(t * 3.0) * t  # asymmetric twist
        inside = (u > 0) & (u < L) & (np.abs(vv) < width)
        e = np.abs(vv) / np.maximum(width, 1e-3)
        white = col01("#fffef8")
        cream = col01("#f2eadb")
        yel = col01("#ffc93a")
        yel2 = col01("#ffe27a")
        k = np.clip((0.5 - t) / 0.35, 0, 1)[..., None] ** 1.3
        base = white * (1 - 0.6 * e[..., None] * (vv < 0)[..., None]) + cream * (0.6 * e[..., None] * (vv < 0)[..., None])
        rgb = base * (1 - k) + (yel * k + yel2 * (1 - k)) * k
        rgb = np.where(((np.abs(vv) < 0.25) & (t < 0.6))[..., None], rgb * 0.97, rgb)
        a = inside.astype(float)
        return rgb, a
    return ss_render(16, 16, 12, fn)


def sp_raindrop():
    img = blank(2, 16)
    for y in range(16):
        t = y / 15
        a = int(255 * (0.08 + 0.85 * t ** 1.6))
        img[y, 0] = (214, 236, 255, a)
        img[y, 1] = (196, 222, 250, int(a * 0.55))
    return img


def sp_spark():
    ys, xs = np.mgrid[0:8, 0:8] + 0.5
    r = np.hypot(xs - 4, ys - 4)
    a = np.exp(-(r / 1.55) ** 2)
    a = np.clip(a * 1.15, 0, 1)
    img = np.zeros((8, 8, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = (a * 255).astype(np.uint8)
    return img


def sp_smoke():
    rng = np.random.default_rng(14)
    ys, xs = np.mgrid[0:32, 0:32] + 0.5
    field = np.zeros((32, 32))
    for (cx, cy, r, w) in [(16, 18, 6.5, 0.8), (9.5, 16, 5.0, 0.75), (22.5, 14, 5.5, 0.8), (12, 23, 4.5, 0.65),
                           (21, 23, 5.0, 0.7), (15, 9.5, 4.8, 0.7), (25, 20, 3.6, 0.55), (7, 21, 3.4, 0.5)]:
        field += w * np.exp(-((xs - cx) ** 2 + (ys - cy) ** 2) / (2 * (r * 0.6) ** 2))
    n = pnoise(rng, (32, 32), kmax=8)
    field = field * (0.6 + 0.8 * n)
    a = np.clip((field - 0.18) / 0.8, 0, 1) ** 1.1
    edge = np.hypot(xs - 16, ys - 16) / 16
    a *= np.clip(1.25 - edge, 0, 1)
    shade = np.clip((ys - 8) / 24, 0, 1)
    img = np.zeros((32, 32, 4), np.uint8)
    lum = 245 - 40 * shade
    img[..., 0] = lum
    img[..., 1] = lum
    img[..., 2] = np.clip(lum + 6, 0, 255)
    img[..., 3] = (a * 225).astype(np.uint8)
    return img


def sp_leaf():
    W = H = 12
    xs, ys = grid(W, H)
    bx, by = 1.5, 10.5
    ang = math.radians(-42)
    dx, dy = xs - bx, ys - by
    u = dx * math.cos(ang) + dy * math.sin(ang)
    v = -dx * math.sin(ang) + dy * math.cos(ang)
    L = 12.0
    t = np.clip(u / L, 0, 1)
    wdt = 3.4 * np.sin(np.pi * t) ** 0.8
    m = (u > 1.2) & (u < L) & (np.abs(v) < wdt)
    img = blank(W, H)
    paint(img, m, "#4a8a34")
    paint(img, m & (v < -0.4), "#76b247")
    paint(img, m & (v < -0.4) & (np.abs(v) > wdt * 0.6), "#b2dc6c")
    paint(img, m & (v > 0.4) & (np.abs(v) > wdt * 0.6), "#2f6528")
    paint(img, m & (np.abs(v) < 0.5) & (u < L - 2), "#2e5a26")
    outline(img, "#173018")
    px(img, 1, 10, "#6a4a24")
    px(img, 0, 11, "#6a4a24")
    return img


def sp_shadow_blob():
    ys, xs = np.mgrid[0:16, 0:32] + 0.5
    d = np.hypot((xs - 16) / 15.5, (ys - 8) / 7.5)
    a = np.clip(1 - d ** 2, 0, 1) ** 1.4
    img = np.zeros((16, 32, 4), np.uint8)
    img[..., :3] = (12, 10, 18)
    img[..., 3] = (a * 175).astype(np.uint8)
    return img


FX = [
    ("fx_slash", fx_slash, 48, 48, 6), ("fx_claw", fx_claw, 48, 48, 5), ("fx_hit", fx_hit, 32, 32, 4),
    ("fx_blood", fx_blood, 48, 48, 6), ("fx_fire", fx_fire, 48, 48, 8), ("fx_ice", fx_ice, 48, 48, 6),
    ("fx_heal", fx_heal, 48, 48, 8), ("fx_poison", fx_poison, 48, 48, 6), ("fx_shield", fx_shield, 48, 48, 6),
    ("fx_dark", fx_dark, 48, 48, 6), ("fx_buff", fx_buff, 32, 48, 6), ("fx_debuff", fx_debuff, 32, 48, 6),
    ("fx_peck", fx_peck, 32, 32, 4), ("fx_lightning", fx_lightning, 32, 64, 5), ("fx_egg", fx_egg, 32, 32, 6),
]
SPRITES = [
    ("blood_puddle", sp_blood_puddle, "40x20 top-down blood puddle decal (pixel art)"),
    ("feather", sp_feather, "8x16 soft white feather particle (anti-aliased)"),
    ("petal", sp_petal, "16x16 frangipani petal, smooth anti-aliased"),
    ("raindrop", sp_raindrop, "2x16 soft rain streak"),
    ("spark", sp_spark, "8x8 soft white glow dot (tint in engine)"),
    ("smoke", sp_smoke, "32x32 soft smoke puff (near-white, tint in engine)"),
    ("leaf", sp_leaf, "12x12 green leaf (pixel art)"),
    ("shadow_blob", sp_shadow_blob, "32x16 soft dark ellipse, alpha gradient"),
]


def gen_fx():
    FX_DIR.mkdir(parents=True, exist_ok=True)
    meta = {}
    prev = []
    for name, fn, fw, fh, nf in FX:
        frames = fn()
        assert len(frames) == nf, (name, len(frames))
        for fr in frames:
            assert fr.shape == (fh, fw, 4), (name, fr.shape)
        strip = np.concatenate(frames, axis=1)
        im = Image.fromarray(strip, "RGBA")
        im.save(FX_DIR / f"{name}.png")
        meta[name] = {"frame_w": fw, "frame_h": fh, "frames": nf}
        prev.append((f"{name}  ({nf} x {fw}x{fh})", im))
    (FX_DIR / "fx_meta.json").write_text(json.dumps(meta, indent=2) + "\n")
    sprites = []
    for name, fn, desc in SPRITES:
        arr = fn()
        im = Image.fromarray(arr, "RGBA")
        im.save(FX_DIR / f"{name}.png")
        sprites.append((name, im))
    # previews (8x nearest) -- grouped so each sheet stays readable
    groups = [prev[0:4], prev[4:7], prev[7:11], prev[11:15]]
    for i, g in enumerate(groups):
        contact_sheet(g, 8, 1, PREV_DIR / f"preview_fx_{i + 1}.png", checker_bg=True)
    contact_sheet(sprites, 8, 4, PREV_DIR / "preview_fx_sprites.png", checker_bg=True)
    write_fx_readme(meta)
    return list(meta) + [n for n, _ in sprites]


def write_fx_readme(meta):
    lines = ["# Gili Genting - FX assets", "",
             "Generated by `tools/gen_textures.py` (procedural, no external sources). Re-run the script to rebuild.", "",
             "## Sprite-sheet strips (frames laid out horizontally, transparent PNG)", "",
             "Frame sizes are also in `fx_meta.json` (`frame_w`, `frame_h`, `frames`).", "",
             "| file | frames | frame size | description |", "|---|---|---|---|"]
    desc = {
        "fx_slash": "white-hot to yellow crescent sword arc sweep",
        "fx_claw": "three red diagonal claw scratches",
        "fx_hit": "white/yellow impact star burst",
        "fx_blood": "stylised dark-red blood burst with droplets",
        "fx_fire": "fireball explosion collapsing into smoke",
        "fx_ice": "ice shards erupt, then shatter",
        "fx_heal": "green-gold rising sparkles and plus signs (loops)",
        "fx_poison": "purple bubbles rising and popping over a toxic pool (loops)",
        "fx_shield": "blue hexagon barrier pulse",
        "fx_dark": "purple-black shadow tendrils converge and strike",
        "fx_buff": "rising orange arrows (loops)",
        "fx_debuff": "falling blue arrows (loops)",
        "fx_peck": "quick beak jab with speed lines and impact",
        "fx_lightning": "lightning bolt strike with ground impact",
        "fx_egg": "egg bomb falls, cracks, and splats into a dazed yolk",
    }
    for name, m in meta.items():
        lines.append(f"| `{name}.png` | {m['frames']} | {m['frame_w']}x{m['frame_h']} | {desc.get(name, '')} |")
    lines += ["", "## Single sprites (transparent PNG)", "", "| file | description |", "|---|---|"]
    for name, _, d in SPRITES:
        lines.append(f"| `{name}.png` | {d} |")
    lines += ["", "## Other", "", "- `fx_meta.json`: frame layout for every strip.", "",
              "Import tip (Godot 4): disable filtering (Nearest) for the pixel-art strips; `feather`, `petal`,",
              "`raindrop`, `spark`, `smoke`, `shadow_blob` are soft and look best with Linear filtering.", ""]
    (FX_DIR / "README.md").write_text("\n".join(lines))


def ascii_sprite(rows, cmap, w=None, h=None, ox=0, oy=0):
    rows = [r for r in rows]
    W = w or max(len(r) for r in rows)
    H = h or len(rows)
    img = blank(W, H)
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in cmap and cmap[ch] is not None:
                img[y + oy, x + ox] = C(cmap[ch])
    return img


GOLD = dict(o="#0a0d14", g1="#f2d38c", g1b="#8f5d27", g2="#c9913d", g3="#6c421e")


def frame_rings(W, H, ring_cols, fill_fn, round_corners=True):
    """Generic bevelled frame. ring_cols[k] = (top_left_colour, bottom_right_colour) for distance k from edge."""
    img = blank(W, H)
    for y in range(H):
        for x in range(W):
            k = min(x, y, W - 1 - x, H - 1 - y)
            tl = min(x, y) <= min(W - 1 - x, H - 1 - y)
            if k < len(ring_cols):
                c = ring_cols[k][0 if tl else 1]
            else:
                c = fill_fn(x, y)
            if c is not None:
                img[y, x] = C(c) if isinstance(c, str) else c
    if round_corners:
        for (x, y) in ((0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)):
            img[y, x] = 0
        for (x, y, dx, dy) in ((1, 1, 1, 1), (W - 2, 1, -1, 1), (1, H - 2, 1, -1), (W - 2, H - 2, -1, -1)):
            img[y, x] = C(ring_cols[0][0])
    return img


def corner_ornaments(img, m, cols):
    """Diamond rivets + inner flourish in each m x m corner."""
    H, W = img.shape[:2]
    cream, light, mid, dark, line = cols
    for (cx, cy, sx, sy) in ((3, 3, 1, 1), (W - 4, 3, -1, 1), (3, H - 4, 1, -1), (W - 4, H - 4, -1, -1)):
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                d = abs(dx) + abs(dy)
                if d == 0:
                    c = cream
                elif d == 1:
                    c = light if (dx * sx + dy * sy) <= 0 else mid
                elif d == 2:
                    c = line
                else:
                    continue
                img[cy + dy, cx + dx] = C(c)
        # little inward spur
        px(img, cx + 3 * sx, cy + 3 * sy, mid)


def _bands(y, H, top, mid, bot, m):
    """Fill colour by row: top band in upper margin + first 3/8 of centre, etc. (9-slice safe)."""
    c0, c1 = m, H - m
    if y < c0:
        return top
    if y >= c1:
        return bot
    t = (y - c0) / max(1, c1 - c0)
    return top if t < 0.375 else (mid if t < 0.625 else bot)


def ui_panel(fill=("#1a283a", "#15202e", "#111a26"), alpha=255, ring=None, orn=None, inner=("#2c4559", "#162231")):
    W = H = 24
    ring = ring or [(GOLD["o"], GOLD["o"]), (GOLD["g1"], GOLD["g1b"]), (GOLD["g2"], GOLD["g2"]),
                    (GOLD["g3"], GOLD["g3"]), (GOLD["o"], GOLD["o"])]
    ring = ring + [inner]
    fc = [np.array(hx(c)[:3] + (alpha,), np.uint8) for c in fill]

    def fill_fn(x, y):
        return fc[["t", "m", "b"].index(_bands(y, H, "t", "m", "b", 8))]

    img = frame_rings(W, H, ring, fill_fn)
    corner_ornaments(img, 8, orn or ("#fff3c8", GOLD["g1"], GOLD["g2"], GOLD["g3"], GOLD["o"]))
    return img


def ui_panel_dark():
    ring = [(GOLD["o"], GOLD["o"]), ("#c9a060", "#6f4920"), ("#9a6c2e", "#9a6c2e"), ("#4e3016", "#4e3016"), (GOLD["o"], GOLD["o"])]
    return ui_panel(fill=("#0f1722", "#0c131c", "#090f17"), alpha=217, ring=ring,
                    orn=("#f0dcae", "#c9a060", "#9a6c2e", "#4e3016", GOLD["o"]), inner=("#1d2c3b", "#0c131c"))


def ui_panel_light():
    ring = [("#24160d", "#24160d"), ("#e9c47e", "#7a4a20"), ("#b07a3a", "#b07a3a"), ("#5a3418", "#5a3418"), ("#3a2414", "#3a2414")]
    return ui_panel(fill=("#f0e4c6", "#e9dab6", "#dfcea6"), ring=ring,
                    orn=("#fff6d8", "#e9c47e", "#b07a3a", "#5a3418", "#24160d"), inner=("#c8b38a", "#e3d3ad"))


def ui_button_focus():
    W, H = 24, 16
    ring = [(GOLD["o"], GOLD["o"]), (GOLD["g1"], "#a8742e"), ("#7fb6c4", "#1b3a4c")]
    cols = {"t": "#3d6f84", "m": "#305c71", "b": "#264b5f"}

    def fill_fn(x, y):
        return cols[_bands(y, H, "t", "m", "b", 6)]

    img = frame_rings(W, H, ring, fill_fn)
    # gold glints on the corners
    for (x, y) in ((2, 2), (W - 3, 2)):
        px(img, x, y, "#fff3c8")
    return img


def ui_cursor():
    rows = ["............",
            "............",
            "..ooo.......",
            ".owwwoooooo.",
            "owwwwwwwwwwo",
            "ocwwwwlllllo",
            "ocwwwwoooooo",
            "ocwwwwwwlo..",
            "ocwwwwwloo..",
            "ocwwwwwwlo..",
            ".oollllso...",
            "...ooooo...."]
    cmap = {"o": "#1a1220", "w": "#ffffff", "l": "#c9cfe2", "s": "#8e95b6", "c": "#d29a44"}
    return ascii_sprite(rows, cmap)


def ui_cursor_down():
    return np.ascontiguousarray(np.rot90(ui_cursor(), k=-1))


def ui_bar_bg():
    rows = [".oooooo.",
            "oggggggo",
            "ogjjjjGo",
            "ogiiiiGo",
            "oGGGGGGo",
            ".oooooo."]
    return ascii_sprite(rows, {"o": "#0a0d14", "g": "#c9913d", "G": "#6c421e", "j": "#05070b", "i": "#0e131c"})


ICON_ROWS = {
    "icon_hp": ([".........."
                 , ".oo...oo.."
                 , "ohho.orRo."
                 , "ohrrorrRo."
                 , "orrrrrrRo."
                 , ".orrrrRo.."
                 , "..orrRo..."
                 , "...oRo...."
                 , "....o....."
                 , ".........."],
                {"o": "#2a0710", "r": "#e2333d", "R": "#9a1428", "h": "#ffb0a8"}),
    "icon_mp": (["....o....."
                 , "...obo...."
                 , "..obbbo..."
                 , "..ohbbo..."
                 , ".ohbbbbo.."
                 , ".ohbbbBo.."
                 , ".obbbbBo.."
                 , ".oBbbBBo.."
                 , "..oBBBo..."
                 , "...ooo...."],
                {"o": "#0a1440", "b": "#3d8eea", "B": "#1c4aa8", "h": "#c6ecff"}),
    "icon_xp": (["....o....."
                 , "...oyo...."
                 , "...ohy...."
                 , "ooooyoooo."
                 , "oyyhyyyYo."
                 , ".oyyyyYo.."
                 , "..oyyyo..."
                 , ".oyyoyYo.."
                 , ".oyo.oYo.."
                 , ".oo...oo.."],
                {"o": "#173a10", "y": "#b9e04c", "Y": "#5c9a2c", "h": "#f2ffc0"}),
    "icon_clock": (["oooooooooo"
                    , "ogggggggGo"
                    , ".bwsssssb."
                    , "..bwsssb.."
                    , "...bsSb..."
                    , "...bwsb..."
                    , "..bwwsSb.."
                    , ".bwssssSb."
                    , "ogggggggGo"
                    , "oooooooooo"],
                   {"o": "#2a1608", "g": "#e0a83a", "G": "#8a5a1e", "b": "#3a4a62", "w": "#cfe6f4", "s": "#f2c95e", "S": "#b0782a"}),
    "icon_grain": (["....oo...."
                    , "...ohyo..."
                    , "...oyyo..."
                    , "...oyYo..."
                    , ".oo.oo.oo."
                    , "ohyo..ohyo"
                    , "oyyo..oyyo"
                    , "oyYo..oyYo"
                    , ".oo....oo."
                    , ".........."],
                   {"o": "#4a3010", "y": "#f2d27a", "Y": "#c8963a", "h": "#fff6d6"}),
    "quest_excl": (["..oooooo..", "..ohyyYo..", "..ohyyYo..", "..ohyyYo..", "..ohyyYo..", "..ohyyYo..",
                    "..oyyyYo..", "...oyYo...", "...oyYo...", "...oYYo...", "....oo....", "..........",
                    "...oooo...", "...ohYo...", "...oYYo...", "...oooo..."],
                   {"o": "#2a1606", "y": "#ffd83a", "Y": "#d08a14", "h": "#fff8c0"}),
    "quest_q": (["..oooooo..", ".ohyyyyYo.", "ohyyooyyYo", "oyYo..oyYo", "oooo..oyYo", "....ooyyYo",
                 "...ohyyYo.", "...oyYYo..", "...oyYo...", "...oyYo...", "...oooo...", "..........",
                 "...oooo...", "...ohYo...", "...oYYo...", "...oooo..."],
                {"o": "#2a1606", "y": "#ffd83a", "Y": "#d08a14", "h": "#fff8c0"}),
    "arrow_right": (["oo....", "oyo...", "ohyo..", "ohyyo.", "oyyYo.", "oyYo..", "oYo...", "oo...."],
                    {"o": "#1a0f06", "y": "#f2c552", "Y": "#a8742e", "h": "#fff3c8"}),
}


def ui_skill_node(kind="normal"):
    W = H = 20
    xs, ys = grid(W, H)
    dx, dy = np.abs(xs - 10), np.abs(ys - 10)
    m = (np.maximum(dx, dy) <= 8.6) & (dx + dy <= 12.6)
    layers = []
    cur = m.copy()
    for _ in range(6):
        nxt = ndimage.binary_erosion(cur)
        layers.append(cur & ~nxt)
        cur = nxt
    core = cur
    tl = (xs - 10) + (ys - 10) < 0
    if kind == "normal":
        ring = [("#0a0d14", "#0a0d14"), (GOLD["g1"], GOLD["g1b"]), (GOLD["g2"], GOLD["g2"]), (GOLD["g3"], GOLD["g3"]),
                ("#0a0d14", "#0a0d14"), ("#22344a", "#14202e")]
        fill = "#16222f"
    elif kind == "locked":
        ring = [("#08090c", "#08090c"), ("#8c9098", "#4a4d55"), ("#62666e", "#62666e"), ("#35373d", "#35373d"),
                ("#08090c", "#08090c"), ("#1a1d24", "#101217")]
        fill = "#0f1217"
    else:
        ring = [("#3a2206", "#3a2206"), ("#fff4be", "#d29a3c"), ("#ffd24c", "#ffd24c"), ("#c47a1e", "#c47a1e"),
                ("#3a2206", "#3a2206"), ("#5a4418", "#3a2c12")]
        fill = "#2e2512"
    img = blank(W, H)
    for k, L in enumerate(layers):
        paint(img, L & tl, ring[k][0])
        paint(img, L & ~tl, ring[k][1])
    paint(img, core, fill)
    if kind == "locked":  # faint cross-hatch in the dead socket
        paint(img, core & ((XX[:H, :W] + YY[:H, :W]) % 4 == 0), "#151920")
    if kind == "owned":
        glow = ndimage.binary_dilation(m) & ~m
        img[glow] = (255, 214, 92, 120)
        glow2 = ndimage.binary_dilation(m, iterations=2) & ~ndimage.binary_dilation(m) & (bayer(H, W) > 0.1)
        img[glow2] = (255, 214, 92, 60)
        for (x, y) in ((10, 0), (0, 10), (19, 10), (10, 19)):
            img[y, x] = (255, 246, 200, 230)
        paint(img, core & (ys < 8), "#3a2f16")
    else:
        for (x, y) in ((10, 1), (1, 10), (18, 10), (10, 18)):  # cardinal rivets
            paint(img, (np.abs(xs - x - 0.5) < 1) & (np.abs(ys - y - 0.5) < 1) & m, ring[2][0])
            px(img, x, y, "#fff3c8" if kind == "normal" else "#b8bcc4")
    return img


def ui_divider():
    W, H = 64, 4
    img = blank(W, H)
    for x in range(3, 61):
        t = abs(x - 31.5) / 28.5
        img[1, x] = C(GOLD["g1"] if t < 0.45 else GOLD["g2"])
        if 4 <= x <= 59:
            img[2, x] = C("#3c2410")
    for x in (1, 62):
        img[1, x] = C(GOLD["g2"])
        img[2, x] = C("#3c2410")
    for y in range(4):
        for x in range(27, 37):
            d = abs(x - 31.5) + abs(y - 1.5)
            if d <= 1.0:
                img[y, x] = C("#fff3c8")
            elif d <= 2.0:
                img[y, x] = C(GOLD["g1"])
            elif d <= 3.0:
                img[y, x] = C(GOLD["g2"])
            elif d <= 4.0:
                img[y, x] = C(GOLD["g3"])
    for xc in (22, 41):
        img[0, xc] = C(GOLD["g2"])
        img[3, xc] = C(GOLD["g3"])
        img[1, xc] = C("#fff3c8")
        img[1, xc - 1] = C(GOLD["g1"])
        img[1, xc + 1] = C(GOLD["g1"])
    return img


def nine_slice(img, w, h, m_l, m_t, m_r=None, m_b=None):
    m_r = m_l if m_r is None else m_r
    m_b = m_t if m_b is None else m_b
    H, W = img.shape[:2]
    xs_src = [*range(m_l)] + list(np.linspace(m_l, W - m_r - 1, w - m_l - m_r).round().astype(int)) + [*range(W - m_r, W)]
    ys_src = [*range(m_t)] + list(np.linspace(m_t, H - m_b - 1, h - m_t - m_b).round().astype(int)) + [*range(H - m_b, H)]
    return img[np.ix_(ys_src, xs_src)]


UI = [
    ("panel", ui_panel), ("panel_dark", ui_panel_dark), ("panel_light", ui_panel_light),
    ("button_focus", ui_button_focus), ("cursor", ui_cursor), ("cursor_down", ui_cursor_down),
    ("bar_bg", ui_bar_bg), ("skill_node", lambda: ui_skill_node("normal")),
    ("skill_node_locked", lambda: ui_skill_node("locked")), ("skill_node_owned", lambda: ui_skill_node("owned")),
    ("divider", ui_divider),
]


def gen_ui():
    UI_DIR.mkdir(parents=True, exist_ok=True)
    out = {}
    for name, fn in UI:
        out[name] = fn()
    for name, (rows, cmap) in ICON_ROWS.items():
        out[name] = ascii_sprite(rows, cmap)
    expect = {"panel": (24, 24), "panel_dark": (24, 24), "panel_light": (24, 24), "button_focus": (24, 16),
              "cursor": (12, 12), "cursor_down": (12, 12), "bar_bg": (8, 6), "icon_hp": (10, 10), "icon_mp": (10, 10),
              "icon_xp": (10, 10), "icon_clock": (10, 10), "icon_grain": (10, 10), "quest_excl": (10, 16),
              "quest_q": (10, 16), "skill_node": (20, 20), "skill_node_locked": (20, 20), "skill_node_owned": (20, 20),
              "divider": (64, 4), "arrow_right": (6, 8)}
    for name, (w, h) in expect.items():
        assert out[name].shape[:2] == (h, w), (name, out[name].shape)
        Image.fromarray(out[name], "RGBA").save(UI_DIR / f"{name}.png")
    # previews
    pieces = [(n, Image.fromarray(out[n], "RGBA")) for n in expect]
    contact_sheet(pieces[:7], 8, 4, PREV_DIR / "preview_ui_1.png", checker_bg=True)
    contact_sheet(pieces[7:], 8, 6, PREV_DIR / "preview_ui_2.png", checker_bg=True)
    # mock-up: 9-slice stretched windows with content, as the game would draw them
    mock = blank(200, 120)
    mock[:] = (58, 120, 128, 255)
    def put(dst, src, x, y):
        h, w = src.shape[:2]
        reg = dst[y:y + h, x:x + w]
        a = src[..., 3:4].astype(float) / 255
        reg[..., :3] = (src[..., :3] * a + reg[..., :3] * (1 - a)).astype(np.uint8)
    put(mock, nine_slice(out["panel"], 120, 70, 8, 8), 4, 4)
    put(mock, nine_slice(out["button_focus"], 104, 14, 6, 6), 12, 14)
    put(mock, out["cursor"], 2, 15)
    put(mock, out["divider"], 32, 34)
    for i, ic in enumerate(["icon_hp", "icon_mp", "icon_xp", "icon_clock", "icon_grain"]):
        put(mock, out[ic], 14 + i * 14, 42)
    bar = nine_slice(out["bar_bg"], 60, 6, 2, 2)
    put(mock, bar, 14, 58)
    mock[60:62, 16:52] = (220, 60, 60, 255)
    put(mock, nine_slice(out["panel_dark"], 70, 50, 8, 8), 126, 4)
    put(mock, nine_slice(out["panel_light"], 90, 46, 8, 8), 4, 72)
    for i, s in enumerate(["skill_node", "skill_node_locked", "skill_node_owned"]):
        put(mock, out[s], 104 + i * 24, 80)
    put(mock, out["quest_excl"], 180, 60)
    put(mock, out["quest_q"], 160, 60)
    put(mock, out["cursor_down"], 138, 60)
    put(mock, out["arrow_right"], 84, 104)
    Image.fromarray(mock[..., :3]).resize((1600, 960), Image.NEAREST).save(PREV_DIR / "preview_ui_mock.png")
    return list(expect)


# ======================================================================= main
if __name__ == "__main__":
    what = set(sys.argv[1:]) or {"tex", "fx", "ui"}
    PREV_DIR.mkdir(parents=True, exist_ok=True)
    if "tex" in what:
        print("textures:", gen_textures())
    if "fx" in what and "gen_fx" in globals():
        print("fx:", gen_fx())
    if "ui" in what and "gen_ui" in globals():
        print("ui:", gen_ui())
