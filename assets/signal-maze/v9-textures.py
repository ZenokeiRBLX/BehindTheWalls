import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "v9")
SIZE = 1024
SEED = 20261117
SEAM_BAND = 84
SEAM_BORDER = 110
SEAM_SIGMAS = (1, 2, 4, 8, 16)
NORMAL_GAIN = 1.0
MICRO_BUMP = 0.6
COLOR_SATURATION = 1.05
COLOR_GAMMA = 1.12
COLOR_TINT = (0.96, 0.88, 0.9)
ROUGH_WET = 0.05
ROUGH_DRY = 0.17


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


def load_source(name):
    path = os.path.join(HERE, "..", "flesh-wall-rig", name)
    image = Image.open(path).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(image).astype(np.float64) / 255


def roll(image, dx, dy):
    return np.roll(np.roll(image, dy, 0), dx, 1)


def segment_distance(x, y, ax, ay, bx, by):
    px, py = x - ax, y - ay
    vx, vy = bx - ax, by - ay
    t = np.clip((px * vx + py * vy) / (vx * vx + vy * vy), 0, 1)
    return np.sqrt((px - t * vx) ** 2 + (py - t * vy) ** 2)


def seam_masks(rng):
    s = SIZE
    y, x = np.mgrid[0:s, 0:s].astype(np.float64)
    wobble = periodic_field(rng, s, 3, 14) * 0.45
    cross = np.minimum(np.abs(x - s / 2), np.abs(y - s / 2))
    border = np.minimum(np.minimum(x, y), np.minimum(s - 1 - x, s - 1 - y))
    first = ((1 - cross / SEAM_BAND + wobble) > 0.5) & (border > SEAM_BORDER * (0.65 + 0.3 * wobble))
    q = s / 4
    reach = SEAM_BORDER
    spots = np.minimum(
        segment_distance(x, y, 3 * q, q - reach, 3 * q, q + reach),
        segment_distance(x, y, q - reach, 3 * q, q + reach, 3 * q),
    )
    second = (1 - spots / SEAM_BAND + wobble) > 0.5
    return first.astype(np.float64), second.astype(np.float64)


def blur_channels(image, sigma):
    return np.stack([blur(image[..., c], sigma) for c in range(image.shape[-1])], -1)


def band_blend(a, b, mask):
    out = np.zeros_like(a)
    low_a, low_b = a, b
    for sigma in SEAM_SIGMAS:
        next_a = blur_channels(a, sigma)
        next_b = blur_channels(b, sigma)
        soft = np.clip(blur(mask, sigma), 0, 1)[..., None]
        out += (low_a - next_a) * (1 - soft) + (low_b - next_b) * soft
        low_a, low_b = next_a, next_b
    soft = np.clip(blur(mask, SEAM_SIGMAS[-1] * 1.5), 0, 1)[..., None]
    return out + low_a * (1 - soft) + low_b * soft


def make_seamless(image, masks):
    s = SIZE
    first, second = masks
    healed = band_blend(roll(image, s // 2, s // 2), image, first)
    return band_blend(roll(healed, s // 4, s // 4), roll(healed, 3 * s // 4, s // 4), second)


def wrap_error(image):
    inner = np.abs(image[:, 1:] - image[:, :-1]).mean() + np.abs(image[1:] - image[:-1]).mean()
    wrap = np.abs(image[:, 0] - image[:, -1]).mean() + np.abs(image[0] - image[-1]).mean()
    return wrap / inner


def flesh():
    rng = np.random.default_rng(SEED)
    s = SIZE
    masks = seam_masks(rng)
    color_source = load_source("flesh-color-v2.png")
    normal_source = load_source("flesh-normal-v2.png")
    color = make_seamless(color_source, masks)
    vectors = make_seamless(normal_source * 2 - 1, masks)
    print("color wrap/inner %.2f -> %.2f" % (wrap_error(color_source), wrap_error(color)))
    print("normal wrap/inner %.2f -> %.2f" % (wrap_error(normal_source), wrap_error(vectors * 0.5 + 0.5)))

    micro = periodic_field(rng, s, 170, 420)
    mx = (np.roll(micro, -1, 1) - np.roll(micro, 1, 1)) * 0.5
    my = (np.roll(micro, -1, 0) - np.roll(micro, 1, 0)) * 0.5
    vectors[..., 0] = vectors[..., 0] * NORMAL_GAIN - mx * MICRO_BUMP
    vectors[..., 1] = vectors[..., 1] * NORMAL_GAIN + my * MICRO_BUMP
    vectors[..., 2] = np.clip(vectors[..., 2], 0.05, None)
    vectors /= np.sqrt((vectors ** 2).sum(-1, keepdims=True))
    save(vectors * 0.5 + 0.5, "flesh-normal.png")

    luma = color @ np.array([0.3, 0.59, 0.11])
    mean = color.mean(-1, keepdims=True)
    graded = mean + (color - mean) * COLOR_SATURATION
    graded = np.clip(graded, 0, 1) ** COLOR_GAMMA * np.array(COLOR_TINT)
    save(np.clip(graded, 0, 1), "flesh-color.png")

    ridge = smoothstep(0.25, 0.75, normalize(blur(luma, 3)))
    rough = ROUGH_WET + (ROUGH_DRY - ROUGH_WET) * ridge + micro * 0.015
    save(np.repeat(np.clip(rough, 0.04, 0.6)[..., None], 3, -1), "flesh-roughness.png")


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
