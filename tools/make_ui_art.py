#!/usr/bin/env python3
"""Draws the game's UI frame art (our own procedural images, no sources).

    python3 tools/make_ui_art.py        # writes art/ui/*.png

Style: dark-fantasy iron and stone frames with violet gems, stone-housed
glossy bars, an ornate round portrait ring, inset item slots. Every image is
built from height maps lit from the top-left, so bevels read the same on all
pieces. Frames are 9-slice images whose edges are uniform along their length,
so stretching them never smears detail; corner ornaments stay in the corners.

Slice rectangles (used by src/client/UI/Skin.luau) are printed at the end.
"""

import math
import os

import numpy as np
from PIL import Image
from scipy import ndimage

OUT = os.path.join(os.path.dirname(__file__), "..", "art", "ui")
RNG = np.random.default_rng(1027)

LIGHT = np.array([-0.55, -0.65, 0.9])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


# Helpers ---------------------------------------------------------------------


def periodic_noise(h, w, beta=1.8, seed=0):
    """1/f noise that tiles in both directions, normalised to 0..1."""
    r = np.random.default_rng(seed)
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1
    spec = (r.normal(size=(h, w)) + 1j * r.normal(size=(h, w))) / f ** beta
    spec[0, 0] = 0
    n = np.real(np.fft.ifft2(spec))
    n -= n.min()
    return n / max(n.max(), 1e-9)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def shade(height, strength=6.0):
    """Lambert + a little specular from the height map's normals."""
    gy, gx = np.gradient(height)
    nx, ny, nz = -gx * strength, -gy * strength, np.ones_like(height)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / ln, ny / ln, nz / ln
    diff = np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
    # Blinn half vector with the viewer straight on.
    hv = LIGHT + np.array([0, 0, 1.0])
    hv = hv / np.linalg.norm(hv)
    spec = np.clip(nx * hv[0] + ny * hv[1] + nz * hv[2], 0, 1) ** 40
    return diff, spec


def colorize(base, diff, spec, ambient=0.35, spec_col=(255, 245, 230), spec_amt=0.55):
    base = np.asarray(base, dtype=float)
    if base.ndim == 1:
        base = np.broadcast_to(base, diff.shape + (3,))
    light = ambient + (1 - ambient) * diff
    rgb = base * light[..., None] + np.array(spec_col, float) * (spec * spec_amt)[..., None]
    return np.clip(rgb, 0, 255)


def save(name, rgb, alpha, scale=1):
    img = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha, 0, 1) * 255]).astype(np.uint8)
    im = Image.fromarray(img, "RGBA")
    if scale != 1:
        im = im.resize((im.width // scale, im.height // scale), Image.LANCZOS)
    im.save(os.path.join(OUT, name), optimize=True)
    print(f"  {name:22s} {im.width}x{im.height}")
    return im


def edge_distance(h, w, radius=0.0):
    """Distance (px) from the outer edge of a rounded rectangle."""
    y, x = np.mgrid[0:h, 0:w].astype(float)
    dx = np.minimum(x, w - 1 - x)
    dy = np.minimum(y, h - 1 - y)
    d = np.minimum(dx, dy)
    if radius > 0:
        cx = np.clip(radius - dx, 0, None)
        cy = np.clip(radius - dy, 0, None)
        corner = (cx > 0) & (cy > 0)
        d = np.where(corner, radius - np.sqrt(cx * cx + cy * cy), d)
    return d


def band_profile(t, stops):
    """Piecewise-linear height across a frame band. stops: [(t, height), ...]."""
    ts = np.array([s[0] for s in stops], float)
    hs = np.array([s[1] for s in stops], float)
    return np.interp(t, ts, hs)


IRON = (74, 68, 66)
IRON_DARK = (26, 24, 32)
STONE = (98, 94, 100)
GEM = (178, 70, 255)
GEM_HI = (255, 210, 255)
GOLD = (214, 160, 70)


def gem(rgb, alpha, height, cx, cy, r, color=GEM, ss=1):
    """A faceted diamond gem with a bright glint."""
    h, w = alpha.shape
    y, x = np.mgrid[0:h, 0:w].astype(float)
    d = (np.abs(x - cx) + np.abs(y - cy)) / r  # diamond norm
    m = d <= 1.0
    mount = d <= 1.32
    # Gold mount ring.
    ring = mount & ~m
    rh = (1 - np.abs((d - 1.16) / 0.16)).clip(0, 1)
    height[ring] = np.maximum(height[ring], 1.2 + rh[ring] * 0.5)
    # Facets: four triangles lit differently.
    fx = np.sign(x - cx)
    fy = np.sign(y - cy)
    facet = np.where(fy < 0, np.where(fx < 0, 1.0, 0.75), np.where(fx < 0, 0.5, 0.3))
    inner = d < 0.45
    facet = np.where(inner, 0.9, facet)
    col = np.array(color, float)
    g = col[None, None, :] * (0.35 + 0.9 * facet[..., None])
    glint = np.exp(-(((x - (cx - r * 0.28)) / (r * 0.18)) ** 2 + ((y - (cy - r * 0.3)) / (r * 0.18)) ** 2))
    g = g + np.array(GEM_HI, float)[None, None, :] * glint[..., None] * 0.9
    sel = m
    rgb[sel] = np.clip(g[sel], 0, 255)
    alpha[mount] = 1
    return ring


def rivet(height, cx, cy, r, amount=1.0):
    h, w = height.shape
    y, x = np.mgrid[0:h, 0:w].astype(float)
    dd = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / r
    dome = np.sqrt(np.clip(1 - dd * dd, 0, 1)) * amount
    np.maximum(height, height.max() * 0 + (height + dome * (dd < 1)), out=height)


# Frames ----------------------------------------------------------------------


def frame(name, size=256, band=34, corner=64, ornate=False, ss=2):
    S = size * ss
    B = band * ss
    C = corner * ss
    d = edge_distance(S, S, radius=4 * ss)
    t = d / ss
    if ornate:
        stops = [(0, 0), (2, 0.3), (6, 1.15), (10, 1.2), (12, 0.6), (15, 1.05), (27, 1.1), (29, 0.6), (32, 1.0), (band - 6, 0.95), (band - 3, 0.3), (band, 0.0)]
    else:
        stops = [(0, 0), (2, 0.3), (6, 1.15), (9, 1.2), (11, 0.6), (14, 1.0), (band - 6, 1.0), (band - 3, 0.3), (band, 0.0)]
    height = band_profile(t, stops)
    grain = periodic_noise(S, S, 1.2, seed=11)
    height = height + (grain - 0.5) * 0.08 * (t < band)
    alpha = smoothstep(-0.5, 0.8, t) * (1 - smoothstep(band - 0.6, band + 0.4, t))
    # Corner ornaments: a raised square plate with a gem (ornate) or rivet.
    rgb_base = np.empty((S, S, 3))
    metal = periodic_noise(S, S, 2.0, seed=12)
    rgb_base[:] = np.array(IRON, float)
    rgb_base *= (0.85 + 0.3 * metal)[..., None]
    gems = []
    for (cx, cy) in [(1, 1), (-1, 1), (1, -1), (-1, -1)]:
        ox = (B * 0.5 + ss * 4) if cx > 0 else S - 1 - (B * 0.5 + ss * 4)
        oy = (B * 0.5 + ss * 4) if cy > 0 else S - 1 - (B * 0.5 + ss * 4)
        y, x = np.mgrid[0:S, 0:S].astype(float)
        # A rotated-square boss plate centred on the corner of the band.
        pr = (B * 1.05 if ornate else B * 0.8)
        dd = np.maximum(np.abs(x - ox), np.abs(y - oy)) / pr  # square boss
        dd = np.maximum(dd, (np.abs(x - ox) + np.abs(y - oy)) / (pr * 1.45))  # clipped corners
        plate = dd <= 1
        ph = 1.45 + (1 - dd) * 0.35
        height = np.where(plate, np.maximum(height, ph * (1 - smoothstep(0.9, 1.0, dd)) + height * smoothstep(0.9, 1.0, dd)), height)
        alpha = np.where(plate, 1.0, alpha)
        gems.append((ox, oy, pr * 0.5))
    hammer = periodic_noise(S, S, 1.1, seed=13)
    height = height + (hammer - 0.5) * 0.12 * (alpha > 0.5)
    diff, spec = shade(height, strength=7.0 / ss)
    rgb = colorize(rgb_base, diff, spec, ambient=0.16, spec_amt=0.7)
    # Dark outer line and dark inner lip.
    edge_dark = (1 - smoothstep(0, 2.2, t)) + smoothstep(band - 2.5, band, t)
    rgb = rgb * (1 - 0.6 * np.clip(edge_dark, 0, 1))[..., None]
    for (ox, oy, r) in gems:
        if ornate:
            gem(rgb, alpha, height, ox, oy, r)
        else:
            y, x = np.mgrid[0:S, 0:S].astype(float)
            dd = np.sqrt((x - ox) ** 2 + (y - oy) ** 2) / (r * 0.7)
            dome = np.sqrt(np.clip(1 - dd * dd, 0, 1))
            m = dd < 1
            sh = 0.35 + 0.65 * np.clip(((ox - x) * 0.6 + (oy - y) * 0.7) / (r * 0.7) * 0.5 + dome * 0.7, 0, 1)
            col = np.array(GOLD, float)[None, None, :] * sh[..., None]
            rgb[m] = col[m]
    save(name, rgb, alpha, ss)
    return corner


def slot(name="slot.png", size=128, ss=2):
    S = size * ss
    t = edge_distance(S, S, radius=3 * ss) / ss
    # Inset: the frame rises at the outer edge then drops into the well.
    height = band_profile(t, [(0, 0.2), (2, 1.0), (6, 1.0), (10, 0.0), (64, 0.0)])
    grain = periodic_noise(S, S, 1.4, seed=21)
    height = height + (grain - 0.5) * 0.05
    diff, spec = shade(height, strength=5.0 / ss)
    base = np.empty((S, S, 3))
    base[:] = np.array(IRON, float)
    well = t >= 10
    leather = periodic_noise(S, S, 1.6, seed=22)
    wellcol = np.array([30, 26, 24], float)[None, None, :] * (0.75 + 0.5 * leather)[..., None]
    base = np.where(well[..., None], wellcol, base)
    rgb = colorize(base, diff, spec, ambient=0.3, spec_amt=0.5)
    # Inner shadow from the top-left rim into the well.
    y, x = np.mgrid[0:S, 0:S].astype(float) / ss
    sh = np.exp(-np.clip(t - 10, 0, None) / 7) * 0.65
    rgb = rgb * (1 - sh * well)[..., None]
    rgb = rgb * (1 - 0.55 * (1 - smoothstep(0, 1.8, t)))[..., None]
    alpha = smoothstep(-0.5, 0.8, t)
    save(name, rgb, alpha, ss)


def glow(name="glow.png", size=128):
    t = edge_distance(size, size, radius=6)
    a = np.exp(-((t - 5) / 4.0) ** 2) + 0.35 * np.exp(-((t - 5) / 10.0) ** 2)
    a = np.clip(a, 0, 1)
    rgb = np.full((size, size, 3), 255.0)
    save(name, rgb, a)


def vignette(name="vignette.png", size=128):
    t = edge_distance(size, size)
    a = (1 - smoothstep(0, 44, t)) ** 1.6 * 0.85
    rgb = np.zeros((size, size, 3))
    save(name, rgb, a)


def grain(name="grain.png", size=256):
    n = periodic_noise(size, size, 1.3, seed=31)
    fine = periodic_noise(size, size, 0.6, seed=32)
    v = 0.55 * n + 0.45 * fine
    v = (v - v.mean()) / (v.std() * 3) + 0.5
    rgb = np.repeat((np.clip(v, 0, 1) * 255)[..., None], 3, axis=2)
    save(name, rgb, np.ones((size, size)))


# Plaque (title banner with gem caps) -----------------------------------------


def plaque(name="plaque.png", w=1024, h=128, cap=150, ss=1):
    y, x = np.mgrid[0:h, 0:w].astype(float)
    cy = h / 2
    half = h * 0.4  # plate half height
    # Distance inside the plate (a long rectangle with arrow-tipped ends).
    tip = cap * 0.15
    dx_left = x - tip
    dx_right = (w - 1 - tip) - x
    # Arrow ends: half-height shrinks toward the tips.
    hh_left = np.clip(dx_left / (cap * 0.55), 0, 1) * half
    hh_right = np.clip(dx_right / (cap * 0.55), 0, 1) * half
    hh = np.minimum(np.minimum(hh_left, hh_right), half)
    inside_v = hh - np.abs(y - cy)
    mask = inside_v > 0
    dist = ndimage.distance_transform_edt(mask)
    height = band_profile(dist, [(0, 0), (2, 0.4), (7, 1.2), (10, 1.2), (12, 0.55), (15, 1.0), (60, 1.05)])
    metal = periodic_noise(h, w, 1.8, seed=41)
    height = height + (metal - 0.5) * 0.06 * mask
    alpha = np.clip(dist / 1.5, 0, 1)
    # Wing spikes above/below the gems at both ends.
    hammer = periodic_noise(h, w, 1.1, seed=42)
    height = height + (hammer - 0.5) * 0.12 * mask
    diff, spec = shade(height, strength=6.0)
    base = np.empty((h, w, 3))
    base[:] = np.array(IRON, float)
    base *= (0.85 + 0.3 * metal)[..., None]
    rgb = colorize(base, diff, spec, ambient=0.18, spec_amt=0.7)
    inner = dist > 15
    rgb[inner] = rgb[inner] * 0.5  # recessed dark face behind the title
    rgb = rgb * (1 - 0.55 * (1 - smoothstep(0, 2, dist)))[..., None]
    for gx in (cap * 0.5, w - 1 - cap * 0.5):
        gem(rgb, alpha, height, gx, cy, half * 0.55)
    save(name, rgb, alpha, ss)
    return cap


# Ring (round portrait frame with spikes) -------------------------------------


def ring(name="ring.png", size=256, ss=2):
    S = size * ss
    y, x = np.mgrid[0:S, 0:S].astype(float)
    c = (S - 1) / 2
    r = np.sqrt((x - c) ** 2 + (y - c) ** 2) / ss
    ang = np.arctan2(y - c, x - c)
    R_out, R_in = 108, 80
    tband = r - R_in  # 0 at inner edge
    width = R_out - R_in
    height = band_profile(tband, [(-2, 0), (0, 0.2), (3, 1.0), (9, 1.05), (11, 0.7), (13, 1.05), (width - 5, 1.0), (width - 1, 0.25), (width, 0)])
    band = (tband >= 0) & (tband <= width)
    # Eight spikes outward from the ring (cardinal ones longer).
    spikes = np.zeros_like(r)
    for k in range(8):
        a0 = k * math.pi / 4
        da = np.angle(np.exp(1j * (ang - a0)))
        length = 24 if k % 2 == 0 else 15
        wid = 0.16 if k % 2 == 0 else 0.12
        prof = 1 - np.abs(da) / wid
        reach = R_out + length * np.clip(prof, 0, 1)
        sp = (r >= R_out - 2) & (r <= reach) & (prof > 0)
        hgt = np.clip(prof, 0, 1) * 1.2 * (1 - (r - R_out) / (length + 1e-3)).clip(0, 1) + 0.4
        spikes = np.where(sp, np.maximum(spikes, hgt), spikes)
    height = np.where(band, height, 0) + spikes
    metal = periodic_noise(S, S, 1.8, seed=51)
    height = height + (metal - 0.5) * 0.06 * (band | (spikes > 0))
    alpha = np.clip(np.where(band, 1, 0) + (spikes > 0), 0, 1).astype(float)
    alpha = ndimage.gaussian_filter(alpha, 0.7 * ss)
    diff, spec = shade(height, strength=6.0 / ss)
    base = np.empty((S, S, 3))
    base[:] = np.array(IRON, float)
    base *= (0.85 + 0.3 * metal)[..., None]
    rgb = colorize(base, diff, spec, ambient=0.18, spec_amt=0.7)
    # Small gems on the four diagonal spikes' roots.
    for k in (1, 3, 5, 7):
        a0 = k * math.pi / 4
        gx = c + math.cos(a0) * (R_out - 1) * ss
        gy = c + math.sin(a0) * (R_out - 1) * ss
        gem(rgb, alpha, height, gx, gy, 7 * ss)
    rgb = rgb * (1 - 0.5 * np.exp(-np.abs(tband) / 1.2) * (tband < 2))[..., None]
    save(name, rgb, alpha, ss)


def disc(name="disc.png", size=256):
    """Dark backing for the portrait ring (circle, soft edge)."""
    y, x = np.mgrid[0:size, 0:size].astype(float)
    c = (size - 1) / 2
    r = np.sqrt((x - c) ** 2 + (y - c) ** 2)
    a = 1 - smoothstep(size * 0.42, size * 0.43, r)
    n = periodic_noise(size, size, 1.6, seed=61)
    v = (20 + 26 * n) * (1 - 0.5 * (r / (size * 0.43)) ** 2)
    rgb = np.dstack([v * 0.9, v * 0.8, v * 1.25])
    save(name, rgb, a)


# Stone bar housing and fills --------------------------------------------------


def trough(name="trough.png", w=1024, h=96, ss=1, seed=71):
    r = np.random.default_rng(seed)
    y, x = np.mgrid[0:h, 0:w].astype(float)
    top0, top1 = 1, 30
    bot0, bot1 = 66, 95
    cap = 40
    labels = np.zeros((h, w), int)
    lid = 1
    # End caps (full height).
    for x0, x1 in ((2, cap), (w - 1 - cap, w - 3)):
        labels[1:95, x0:x1] = lid
        lid += 1
    for (y0, y1) in ((top0, top1), (bot0, bot1)):
        xx = cap + 2
        while xx < w - cap - 2:
            bw = int(r.integers(46, 120))
            x1 = min(xx + bw, w - cap - 2)
            if w - cap - 2 - x1 < 40:
                x1 = w - cap - 2
            jy0 = y0 + int(r.integers(0, 4))
            jy1 = y1 + int(r.integers(0, 4)) if y0 < 40 else y1 - int(r.integers(0, 4))
            labels[jy0:jy1, xx:x1 - 3] = lid
            lid += 1
            xx = x1
    # Chip block corners with noise and compute per-block bevel.
    chip = periodic_noise(h, w, 1.5, seed=seed + 1)
    height = np.zeros((h, w))
    base = np.zeros((h, w, 3))
    alpha = np.zeros((h, w))
    stone_noise = periodic_noise(h, w, 1.4, seed=seed + 2)
    for k in range(1, lid):
        m = labels == k
        if not m.any():
            continue
        d = ndimage.distance_transform_edt(m)
        d = d - chip * 5.0
        mm = d > 0
        prof = np.clip(d / 9, 0, 1) ** 0.6
        height = np.where(mm, prof * 1.4 + stone_noise * 0.6, height)
        tone = r.uniform(0.7, 1.15)
        col = np.array(STONE, float) * tone
        base[mm] = col * (0.75 + 0.5 * stone_noise[mm, None])
        alpha = np.where(mm, np.clip(d / 1.2, 0, 1), alpha)
    diff, spec = shade(height, strength=4.0)
    rgb = colorize(base, diff, spec, ambient=0.2, spec_amt=0.2)
    # Dark mortar behind the stones so the gaps read as depth, not holes.
    band = np.zeros((h, w), bool)
    band[2:31, 3:w - 3] = True
    band[65:94, 3:w - 3] = True
    band[2:94, 3:cap + 2] = True
    band[2:94, w - cap - 3:w - 3] = True
    mortar = np.array([16, 14, 18], float)[None, None, :] * (0.8 + 0.4 * stone_noise[..., None])
    a_st = alpha[..., None]
    rgb = rgb * a_st + mortar * (1 - a_st) * band[..., None] + rgb * (1 - a_st) * (~band)[..., None]
    alpha = np.where(band, 1.0, alpha)
    save(name, rgb, alpha, ss)
    return (cap + 6, top1, w - cap - 6, bot0)


def fill(name, col_lo, col_hi, w=256, h=64, seed=81, stars=True):
    y, x = np.mgrid[0:h, 0:w].astype(float)
    n1 = periodic_noise(h, w, 1.6, seed=seed)
    n2 = periodic_noise(h, w, 1.0, seed=seed + 1)
    v = (y / (h - 1))
    # Glossy liquid: bright band near the top, deep at the bottom.
    gloss = np.exp(-((v - 0.22) / 0.12) ** 2)
    depth = 0.55 + 0.45 * (1 - v) + (n1 - 0.5) * 0.5 + (n2 - 0.5) * 0.25
    lo = np.array(col_lo, float)
    hi = np.array(col_hi, float)
    t = np.clip(depth, 0, 1)[..., None]
    rgb = lo * (1 - t) + hi * t
    rgb = rgb + 255 * gloss[..., None] * 0.35
    if stars:
        r = np.random.default_rng(seed + 2)
        for _ in range(26):
            sx, sy = r.uniform(0, w), r.uniform(h * 0.15, h * 0.9)
            s = r.uniform(0.6, 1.6)
            dx = np.minimum(np.abs(x - sx), w - np.abs(x - sx))
            dy = y - sy
            g = np.exp(-(dx * dx + dy * dy) / (2 * s * s)) + 0.35 * np.exp(-(dx * dx) / (0.5 * s) - (dy * dy) / (8 * s * s)) + 0.35 * np.exp(-(dy * dy) / (0.5 * s) - (dx * dx) / (8 * s * s))
            rgb = rgb + 255 * g[..., None] * 0.8
    edge = 1 - 0.45 * (np.exp(-y / 3) + np.exp(-(h - 1 - y) / 4))
    rgb = rgb * edge[..., None]
    save(name, rgb, np.ones((h, w)))


def main():
    os.makedirs(OUT, exist_ok=True)
    print("UI art ->", os.path.abspath(OUT))
    frame("frame_iron.png", size=256, band=30, corner=60, ornate=False)
    frame("frame_ornate.png", size=256, band=44, corner=80, ornate=True)
    slot()
    glow()
    vignette()
    grain()
    plaque()
    ring()
    disc()
    tr = trough()
    fill("fill_red.png", (90, 6, 14), (255, 70, 52), seed=81)
    fill("fill_blue.png", (8, 30, 110), (70, 190, 255), seed=91)
    fill("fill_white.png", (70, 70, 80), (245, 245, 255), seed=101, stars=True)
    print("slices: frame_iron 56px, frame_ornate 72px, slot 24px, glow 32px, vignette 48px, plaque caps 150px, trough", tr)


if __name__ == "__main__":
    main()
