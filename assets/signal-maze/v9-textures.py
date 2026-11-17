import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "v9")
SIZE = 1024
SEED = 20261117


def periodic_field(rng, size, low, high):
    white = rng.standard_normal((size, size))
    spectrum = np.fft.fft2(white)
    fy = np.fft.fftfreq(size)[:, None] * size
    fx = np.fft.fftfreq(size)[None, :] * size
    radius = np.sqrt(fx * fx + fy * fy)
    band = np.exp(-((radius / high) ** 2)) * (1 - np.exp(-((radius / max(low, 1e-6)) ** 2)))
    field = np.real(np.fft.ifft2(spectrum * band))
    field -= field.mean()
    return field / (np.abs(field).max() + 1e-9)


def blur(image, sigma):
    size = image.shape[0]
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    kernel = np.exp(-2 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(image) * kernel))


def warp(image, dx, dy):
    size = image.shape[0]
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    sx = (xs + dx) % size
    sy = (ys + dy) % size
    x0 = np.floor(sx).astype(int)
    y0 = np.floor(sy).astype(int)
    tx = sx - x0
    ty = sy - y0
    x1 = (x0 + 1) % size
    y1 = (y0 + 1) % size
    a = image[y0, x0] * (1 - tx) + image[y0, x1] * tx
    b = image[y1, x0] * (1 - tx) + image[y1, x1] * tx
    return a * (1 - ty) + b * ty


def blobs(rng, size, count, radius_range, height_scale, field=None, bias=None):
    height = np.full((size, size), -1.0)
    for _ in range(count):
        cx = rng.uniform(0, size)
        cy = rng.uniform(0, size)
        if bias is not None:
            for _ in range(6):
                if rng.uniform() < bias[int(cy) % size, int(cx) % size]:
                    break
                cx = rng.uniform(0, size)
                cy = rng.uniform(0, size)
        r = rng.uniform(*radius_range)
        stretch = rng.uniform(0.75, 1.3)
        angle = rng.uniform(0, np.pi)
        extent = int(np.ceil(r * max(stretch, 1 / stretch))) + 2
        ys = np.arange(int(cy) - extent, int(cy) + extent + 1)
        xs = np.arange(int(cx) - extent, int(cx) + extent + 1)
        gx, gy = np.meshgrid(xs - cx, ys - cy)
        ca, sa = np.cos(angle), np.sin(angle)
        u = (gx * ca + gy * sa) / (r * stretch)
        v = (-gx * sa + gy * ca) / (r / stretch)
        d2 = u * u + v * v
        dome = np.sqrt(np.clip(1 - d2, 0, None)) * r * height_scale
        dome[d2 >= 1] = -1.0
        iy = (ys % size)[:, None]
        ix = (xs % size)[None, :]
        height[iy, ix] = np.maximum(height[iy, ix], dome)
    return height


def normalize(a):
    a = a - a.min()
    return a / (a.max() + 1e-9)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    t = t[..., None] if a.ndim == 3 and t.ndim == 2 else t
    return a * (1 - t) + b * t


def save(array, name, mode="RGB"):
    os.makedirs(OUT, exist_ok=True)
    data = np.clip(array * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(data, mode).save(os.path.join(OUT, name), optimize=True)


def flesh():
    rng = np.random.default_rng(SEED)
    s = SIZE
    lobes = blobs(rng, s, 46, (70, 150), 0.55)
    mids = blobs(rng, s, 260, (22, 52), 0.75)
    crease = 1 - normalize(np.maximum(lobes, 0))
    nodules = blobs(rng, s, 900, (6, 15), 0.9, bias=crease)
    base = np.maximum(np.maximum(lobes, 0), 0)
    height = np.maximum(base, mids * 0.9)
    height = np.maximum(height, nodules * 0.8)
    height = np.where(height < 0, 0, height)
    height = blur(height, 2.2)
    height = normalize(height)

    wx = periodic_field(rng, s, 2, 9) * 38
    wy = periodic_field(rng, s, 2, 9) * 38
    vein_field = warp(periodic_field(rng, s, 6, 26), wx, wy)
    veins = np.clip(1 - np.abs(vein_field) * 9, 0, 1) ** 3
    fine_veins = np.clip(1 - np.abs(warp(periodic_field(rng, s, 20, 70), wx * 0.5, wy * 0.5)) * 7, 0, 1) ** 4
    pores = periodic_field(rng, s, 120, 260)
    mottle = periodic_field(rng, s, 1, 6)
    patches = smoothstep(0.35, 0.75, periodic_field(rng, s, 2, 8))

    relief = height + veins * 0.018 + fine_veins * 0.008 + pores * 0.012
    cavity = relief - blur(relief, 18)
    cavity = np.clip(cavity / (np.abs(cavity).max() + 1e-9), -1, 1)

    dx = (np.roll(relief, -1, 1) - np.roll(relief, 1, 1)) * 0.5
    dy = (np.roll(relief, -1, 0) - np.roll(relief, 1, 0)) * 0.5
    strength = 26.0
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(nx)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / length, ny / length, nz / length], -1) * 0.5 + 0.5
    save(normal, "flesh-normal.png")

    deep = np.array([0.24, 0.06, 0.07])
    meat = np.array([0.58, 0.22, 0.23])
    swell = np.array([0.76, 0.40, 0.39])
    pale = np.array([0.86, 0.62, 0.58])
    vein = np.array([0.32, 0.05, 0.12])
    t = np.clip(relief * 0.9 + cavity * 0.35, 0, 1)
    color = mix(deep[None, None, :] * np.ones((s, s, 3)), np.broadcast_to(meat, (s, s, 3)), smoothstep(0.02, 0.45, t))
    color = mix(color, np.broadcast_to(swell, (s, s, 3)), smoothstep(0.55, 1.0, t) * 0.75)
    color = mix(color, np.broadcast_to(pale, (s, s, 3)), patches * smoothstep(0.5, 0.9, t) * 0.45)
    color = mix(color, np.broadcast_to(vein, (s, s, 3)), np.clip(veins * 0.32 + fine_veins * 0.16, 0, 1))
    color *= (1 + mottle[..., None] * 0.14)
    color *= (0.84 + 0.16 * smoothstep(-0.6, 0.25, cavity))[..., None]
    save(np.clip(color, 0, 1), "flesh-color.png")

    rough = 0.2 - relief * 0.06 - np.clip(-cavity, 0, 1) * 0.1 + patches * 0.12 + veins * 0.08
    rough += periodic_field(rng, s, 40, 140) * 0.04
    rough = np.clip(rough, 0.05, 0.6)
    save(np.repeat(rough[..., None], 3, -1), "flesh-roughness.png")


def static_atlas():
    rng = np.random.default_rng(SEED + 1)
    frame = 256
    grid = 4
    atlas = np.zeros((frame * grid, frame * grid, 3))
    for index in range(grid * grid):
        grain = rng.uniform(0, 1, (frame, frame // 2))
        grain = np.repeat(grain, 2, 1)
        grain = grain * 0.6 + np.roll(grain, 1, 1) * 0.25 + np.roll(grain, -1, 1) * 0.15
        rows = rng.normal(0, 0.12, (frame, 1))
        band_phase = rng.uniform(0, 2 * np.pi)
        y = np.arange(frame)[:, None] / frame
        band = 0.16 * np.sin(y * 2 * np.pi * rng.uniform(1, 2.5) + band_phase)
        dark_bar = np.exp(-(((y - rng.uniform(0, 1)) * 9) ** 2)) * rng.uniform(0.15, 0.4)
        value = grain ** 1.6 * 1.25 + rows + band - dark_bar
        speck = rng.uniform(0, 1, (frame, frame)) > 0.997
        value = np.where(speck, 1.0, value)
        value = np.clip(value, 0, 1)
        tint = np.array([0.86, 0.88, 0.92])
        tile = value[..., None] * tint
        gy, gx = divmod(index, grid)
        atlas[gy * frame:(gy + 1) * frame, gx * frame:(gx + 1) * frame] = tile
    save(atlas, "static-atlas.png")


def red_atlas():
    rng = np.random.default_rng(SEED + 2)
    source = Image.open(os.path.join(HERE, "crt-atlas.png")).convert("RGB")
    w, h = source.size
    crop = source.crop((w // 2, 0, w, h)).resize((512, 512), Image.LANCZOS)
    red = np.asarray(crop).astype(np.float64)[..., 0] / 255
    shape = blur(np.pad(red, ((0, 512), (0, 512)), mode="edge"), 7)[:512, :512]
    shape = 1 - smoothstep(0.38, 0.62, normalize(shape))
    frame = 512
    atlas = np.zeros((frame * 2, frame * 2, 3))
    y, x = np.mgrid[0:frame, 0:frame] / frame
    radial = np.sqrt((x - 0.5) ** 2 * 1.2 + (y - 0.48) ** 2)
    glow = np.clip(1.15 - radial * 1.5, 0.25, 1)
    bright = np.array([1.0, 0.42, 0.28])
    mid = np.array([0.95, 0.12, 0.07])
    dark = np.array([0.16, 0.0, 0.0])
    for index in range(4):
        shift_x = int(rng.integers(-3, 4))
        shift_y = int(rng.integers(-2, 3))
        body = np.roll(np.roll(shape, shift_x, 1), shift_y, 0)
        grain = rng.uniform(0, 1, (frame, frame // 2))
        grain = np.repeat(grain, 2, 1)
        lines = 1 - 0.22 * (np.arange(frame)[:, None] % 4 < 1)
        tear_row = int(rng.integers(40, frame - 40))
        tear = np.zeros((frame, 1))
        tear[tear_row:tear_row + int(rng.integers(3, 9))] = rng.uniform(0.15, 0.35)
        light = (glow * 0.85 + grain * 0.3 + tear) * lines
        background = mix(np.broadcast_to(mid, (frame, frame, 3)), np.broadcast_to(bright, (frame, frame, 3)), np.clip(light - 0.45, 0, 1) * 1.6)
        figure = np.broadcast_to(dark, (frame, frame, 3)) + (grain[..., None] * 0.22 * mid)
        tile = mix(background, figure, body * 0.92)
        tile *= (0.82 + 0.18 * grain)[..., None]
        gy, gx = divmod(index, 2)
        atlas[gy * frame:(gy + 1) * frame, gx * frame:(gx + 1) * frame] = np.clip(tile, 0, 1)
    save(atlas, "red-atlas.png")


def overlay():
    size = 512
    y, x = np.mgrid[0:size, 0:size] / (size - 1)
    u = (x - 0.5) * 2
    v = (y - 0.5) * 2
    corner = (np.abs(u) ** 6 + np.abs(v) ** 6) ** (1 / 6)
    vignette = smoothstep(0.82, 1.03, corner) * 0.9 + smoothstep(0.3, 1.0, np.sqrt(u * u + v * v) / 1.4) * 0.22
    lines = (np.arange(size)[:, None] % 4 < 2) * 0.16 * np.ones((1, size))
    glare = np.exp(-(((u + 0.35) / 0.55) ** 2 + ((v + 0.55) / 0.28) ** 2)) * 0.13
    alpha = np.clip(np.maximum(vignette, lines) + glare, 0, 1)
    rgb = np.ones((size, size, 3)) * (glare / (alpha + 1e-6))[..., None]
    rgba = np.concatenate([np.clip(rgb, 0, 1), alpha[..., None]], -1)
    save(rgba, "crt-overlay.png", "RGBA")


if __name__ == "__main__":
    targets = sys.argv[1:] or ["flesh", "static", "red", "overlay"]
    if "flesh" in targets:
        flesh()
    if "static" in targets:
        static_atlas()
    if "red" in targets:
        red_atlas()
    if "overlay" in targets:
        overlay()
