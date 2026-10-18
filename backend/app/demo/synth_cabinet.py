"""Procedural renderer for SYNTHETIC electrical-cabinet imagery and matching GA drawings.

Everything produced by this module is computer-generated. It exists for two purposes:

1. Demonstration fixtures (a cabinet "photograph", its GA drawing and an expected
   wire/label list) so EAGLE EYE can be demonstrated without a real cabinet.
2. Training data for the synthetic YOLOv8 detector (``models/eagleeye-synth-v1.pt``).

Nothing rendered here is a real cabinet photograph and none of it should ever be
presented as one. Layout coordinates are in millimetres on the backplate with a
top-left origin.
"""
from __future__ import annotations

import io
import math
import random
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT_DIR = Path(__file__).resolve().parent / "fonts"

# Detector classes of the synthetic model. Order defines YOLO class ids.
CLASSES = [
    "circuit_breaker",
    "contactor",
    "power_supply",
    "terminal_block",
    "wire_marker",
    "device_label",
    "earth_bar",
]

WIRE_COLORS: dict[str, tuple[int, int, int]] = {
    "brown": (122, 74, 42),
    "blue": (38, 84, 196),
    "black": (28, 28, 30),
    "grey": (128, 130, 134),
    "red": (196, 40, 38),
    "white": (232, 232, 228),
    "orange": (226, 122, 32),
    "dark_blue": (24, 42, 118),
    "green_yellow": (70, 160, 60),
}


@dataclass
class Item:
    kind: str  # circuit_breaker | contactor | power_supply | terminal_block | earth_bar
    tag: str  # reference designation, e.g. "CB41"
    x: float
    y: float
    w: float
    h: float
    zone: str
    label_text: str | None = None  # text physically printed on the label plate
    present: bool = True
    occluded_label: bool = False
    description: str = ""
    rating: str = ""
    poles: int = 1

    @property
    def label_box(self) -> tuple[float, float, float, float]:
        lw = max(26.0, min(self.w, 40.0))
        cx = self.x + self.w / 2
        return (cx - lw / 2, self.y - 14.0, lw, 10.0)

    @property
    def bottom_center(self) -> tuple[float, float]:
        return (self.x + self.w / 2, self.y + self.h)


@dataclass
class Terminal:
    strip: str
    number: int
    x: float
    y: float
    w: float
    h: float
    zone: str
    ferrule_expected: str
    ferrule_printed: str | None
    wire_color_expected: str
    wire_color_actual: str
    source_tag: str

    @property
    def ref(self) -> str:
        return f"{self.strip}:{self.number}"

    @property
    def marker_box(self) -> tuple[float, float, float, float]:
        return (self.x + self.w / 2 - 13.0, self.y - 24.0, 26.0, 9.0)


@dataclass
class Zone:
    code: str
    name: str
    x: float
    y: float
    w: float
    h: float


@dataclass
class Layout:
    cabinet_id: str
    width: float
    height: float
    items: list[Item] = field(default_factory=list)
    terminals: list[Terminal] = field(default_factory=list)
    zones: list[Zone] = field(default_factory=list)
    rails: list[tuple[float, float, float]] = field(default_factory=list)  # (x0, x1, y_center)
    ducts: list[tuple[float, float, float, float]] = field(default_factory=list)  # x, y, w, h
    strip_labels: list[tuple[str, float, float]] = field(default_factory=list)  # text, x, y


# ---------------------------------------------------------------------------
# Layouts
# ---------------------------------------------------------------------------

def demo_layout(variant: str = "v1") -> Layout:
    """The fixed demonstration cabinet CAB-07.

    ``v1`` contains deliberate discrepancies against the expected lists; ``v2`` is
    the "after correction" state where most of them are fixed.
    """
    v1 = variant == "v1"
    lay = Layout(cabinet_id="CAB-07", width=800.0, height=600.0)
    # Zone frames (drawing only).
    lay.zones = [
        Zone("Z1", "PROTECTION", 30, 30, 520, 150),
        Zone("Z2", "POWER SUPPLY", 30, 215, 210, 165),
        Zone("Z3", "CONTROL", 260, 215, 290, 165),
        Zone("Z4", "TERMINAL STRIP X12", 30, 415, 340, 150),
        Zone("Z5", "PE EARTH BAR", 400, 455, 160, 90),
    ]
    lay.rails = [(40, 540, 115), (40, 540, 297), (40, 380, 515)]
    lay.ducts = [(30, 185, 740, 26), (30, 385, 740, 26), (590, 30, 36, 380)]

    # Z1 — protection row
    y1 = 72.0
    lay.items.append(Item("circuit_breaker", "QF01", 60, y1, 66, 88, "Z1", "QF01", description="MAIN MCB 3P", rating="C32", poles=3))
    for i, tag in enumerate(["CB41", "CB42", "CB43", "CB44"]):
        present = not (v1 and tag == "CB44")
        lay.items.append(Item("circuit_breaker", tag, 160 + i * 62, y1, 30, 88, "Z1", tag, present=present, description="MCB 1P", rating="C10"))
    lay.items.append(Item("circuit_breaker", "CB45", 420, y1, 44, 88, "Z1", "CB45", description="MCB 2P", rating="C6", poles=2))

    # Z2 — power supplies
    lay.items.append(Item("power_supply", "PS11", 55, 250, 66, 100, "Z2", "PS11", description="PSU 24V DC 5A"))
    lay.items.append(Item("power_supply", "PS12", 145, 250, 66, 100, "Z2", "PS21" if v1 else "PS12", description="PSU 24V DC 5A"))

    # Z3 — contactors
    for i, tag in enumerate(["K1", "K2", "K3"]):
        lay.items.append(Item("contactor", tag, 300 + i * 80, 258, 48, 80, "Z3", tag, occluded_label=(tag == "K2"), description="CONTACTOR 24VDC"))

    # Z5 — earth bar
    lay.items.append(Item("earth_bar", "PE", 420, 492, 120, 20, "Z5", "PE", description="PE BAR"))

    # Z4 — terminal strip X12
    ferrules = ["X12-1A", "X12-2A", "X12-3A", "X12-4B", "X12-5B", "X12-6B", "X12-7C", "X12-8C", "X12-9A", "X12-10A"]
    expected_colors = ["brown", "blue", "black", "brown", "blue", "grey", "blue", "black", "brown", "blue"]
    sources = ["QF01", "QF01", "QF01", "CB41", "CB42", "CB43", "K1", "K2", "K3", "PS11"]
    for n in range(10):
        printed = ferrules[n]
        actual_color = expected_colors[n]
        if v1 and n == 3:
            printed = "X12-8B"  # wrong ferrule fitted
        if n == 5:
            printed = "X12-68"  # confusable print (8 vs B) — present in both runs
        if v1 and n == 6:
            actual_color = "brown"  # wrong wire colour
        lay.terminals.append(
            Terminal("X12", n + 1, 50 + n * 30, 490, 26, 54, "Z4", ferrules[n], printed, expected_colors[n], actual_color, sources[n])
        )
    lay.strip_labels.append(("X12", 50, 447))
    return lay


def random_layout(rng: random.Random) -> Layout:
    """Randomised cabinet for detector training data."""
    W = rng.choice([700.0, 800.0, 900.0])
    H = rng.choice([500.0, 600.0, 650.0])
    lay = Layout(cabinet_id=f"SYN-{rng.randint(1, 999):03d}", width=W, height=H)
    y = 60.0 + rng.uniform(-10, 15)
    row = 0
    prefix_pool = ["CB", "QF", "F", "Q", "FC"]
    while y < H - 120 and row < 4:
        kind_roll = rng.random()
        x = 40.0 + rng.uniform(0, 30)
        x_max = W - 60
        row_h = 0.0
        if kind_roll < 0.40:
            pre = rng.choice(prefix_pool)
            base = rng.randint(1, 80)
            k = 0
            while True:
                poles = rng.choice([1, 1, 1, 2, 3])
                w = {1: rng.uniform(26, 32), 2: rng.uniform(40, 48), 3: rng.uniform(60, 70)}[poles]
                if x + w > x_max:
                    break
                tag = f"{pre}{base + k}"
                lay.items.append(Item("circuit_breaker", tag, x, y, w, rng.uniform(80, 95), "Z", tag, present=rng.random() > 0.06, rating=rng.choice(["C6", "C10", "C16", "B10", "C32"]), poles=poles))
                x += w + rng.uniform(4, 30)
                k += 1
                row_h = max(row_h, 95)
            lay.rails.append((40, x_max, y + 44))
        elif kind_roll < 0.65:
            k = 0
            while True:
                w = rng.uniform(42, 56)
                if x + w > x_max:
                    break
                tag = f"K{rng.randint(1, 60)}"
                lay.items.append(Item("contactor", tag, x, y, w, rng.uniform(72, 88), "Z", tag, occluded_label=rng.random() < 0.1))
                x += w + rng.uniform(12, 40)
                k += 1
            lay.rails.append((40, x_max, y + 42))
            row_h = 90
        elif kind_roll < 0.80:
            while True:
                w = rng.uniform(55, 80)
                if x + w > x_max:
                    break
                tag = f"PS{rng.randint(1, 40)}"
                lay.items.append(Item("power_supply", tag, x, y, w, rng.uniform(90, 110), "Z", tag))
                x += w + rng.uniform(15, 60)
            lay.rails.append((40, x_max, y + 50))
            row_h = 110
        else:
            strip = f"X{rng.randint(1, 30)}"
            pitch = rng.uniform(26, 32)
            tw = pitch - rng.uniform(2, 5)
            n = 0
            y_t = y + 30
            while x + tw < x_max and n < 16:
                num = n + 1
                fer = f"{strip}-{num}{rng.choice('ABCD')}"
                printed = fer if rng.random() > 0.15 else f"{strip}-{rng.randint(1, 19)}{rng.choice('ABCDE')}"
                col = rng.choice(list(WIRE_COLORS))
                lay.terminals.append(Terminal(strip, num, x, y_t, tw, rng.uniform(48, 58), "Z", fer, printed if rng.random() > 0.05 else None, col, col, ""))
                x += pitch
                n += 1
            lay.strip_labels.append((strip, lay.terminals[-1].x if n else x, y_t - 36))
            lay.rails.append((40, x_max, y_t + 27))
            if rng.random() < 0.5 and x + 140 < W - 20:
                lay.items.append(Item("earth_bar", "PE", x + 20, y_t + 10, rng.uniform(90, 130), 20, "Z", "PE"))
            row_h = 95
        duct_y = y + row_h + rng.uniform(12, 22)
        if duct_y + 26 < H - 20:
            lay.ducts.append((30, duct_y, W - 60, 26))
        y = duct_y + 26 + rng.uniform(40, 60)
        row += 1
    if rng.random() < 0.5:
        lay.ducts.append((W - 70, 30, 34, H - 60))
    return lay


# ---------------------------------------------------------------------------
# Raster rendering ("photo" style)
# ---------------------------------------------------------------------------

def _font(name: str, size_px: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_DIR / name), max(6, int(round(size_px))))


def _shade(c: tuple[int, int, int], f: float) -> tuple[int, int, int]:
    return tuple(int(max(0, min(255, v * f))) for v in c)  # type: ignore[return-value]


class _Painter:
    def __init__(self, lay: Layout, ppm: float, rng: random.Random):
        self.lay = lay
        self.ppm = ppm
        self.rng = rng
        self.W = int(lay.width * ppm)
        self.H = int(lay.height * ppm)
        self.style = {
            "breaker": rng.choice([(236, 236, 232), (236, 236, 232), (222, 224, 226), (88, 90, 96)]),
            "contactor": rng.choice([(118, 120, 126), (118, 120, 126), (70, 72, 78), (200, 200, 196)]),
            "psu": rng.choice([(206, 209, 213), (206, 209, 213), (96, 100, 108)]),
            "terminal": rng.choice([(214, 210, 198), (214, 210, 198), (150, 152, 156), (226, 226, 222)]),
        }
        plate_base = rng.choice([(186, 188, 184), (186, 188, 184), (214, 216, 212), (232, 140, 60)])
        base = np.array(plate_base, np.float32) + rng.uniform(-14, 10)
        noise = np.random.default_rng(rng.randint(0, 1 << 30)).normal(0, 9, (self.H, self.W)).astype(np.float32)
        noise = cv2.GaussianBlur(noise, (0, 0), sigmaX=6, sigmaY=0.6)  # brushed steel streaks
        plate = np.clip(base[None, None, :] + noise[..., None], 0, 255).astype(np.uint8)
        self.img = Image.fromarray(plate, "RGB")
        self.draw = ImageDraw.Draw(self.img)
        self.shadow = Image.new("L", (self.W, self.H), 0)
        self.sdraw = ImageDraw.Draw(self.shadow)
        self.boxes: list[tuple[int, float, float, float, float, str]] = []  # class, x0,y0,x1,y1 (px), text

    def p(self, v: float) -> float:
        return v * self.ppm

    def rect_px(self, x: float, y: float, w: float, h: float) -> tuple[float, float, float, float]:
        return (self.p(x), self.p(y), self.p(x + w), self.p(y + h))

    def gradient_rect(self, x: float, y: float, w: float, h: float, top: tuple[int, int, int], bottom: tuple[int, int, int], outline=None):
        x0, y0, x1, y1 = self.rect_px(x, y, w, h)
        rows = max(1, int(y1 - y0))
        for i in range(rows):
            t = i / max(1, rows - 1)
            c = tuple(int(top[k] * (1 - t) + bottom[k] * t) for k in range(3))
            self.draw.line([(x0, y0 + i), (x1, y0 + i)], fill=c)
        if outline:
            self.draw.rectangle([x0, y0, x1, y1], outline=outline, width=max(1, int(self.ppm * 0.5)))

    def drop_shadow(self, x: float, y: float, w: float, h: float, strength: int = 150, off: float = 3.0):
        x0, y0, x1, y1 = self.rect_px(x + off, y + off, w, h)
        self.sdraw.rectangle([x0, y0, x1, y1], fill=strength)

    def apply_shadows(self):
        sh = self.shadow.filter(ImageFilter.GaussianBlur(self.ppm * 3.0))
        arr = np.asarray(self.img).astype(np.float32)
        s = np.asarray(sh).astype(np.float32)[..., None] / 255.0
        arr = arr * (1 - 0.55 * s)
        self.img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
        self.draw = ImageDraw.Draw(self.img)
        self.shadow = Image.new("L", (self.W, self.H), 0)
        self.sdraw = ImageDraw.Draw(self.shadow)

    def text(self, cx: float, cy: float, s: str, size_mm: float, fill, font="DejaVuSans-Bold.ttf"):
        f = _font(font, self.p(size_mm))
        bb = self.draw.textbbox((0, 0), s, font=f)
        tw, th = bb[2] - bb[0], bb[3] - bb[1]
        self.draw.text((self.p(cx) - tw / 2 - bb[0], self.p(cy) - th / 2 - bb[1]), s, font=f, fill=fill)

    def add_box(self, cls: str, x: float, y: float, w: float, h: float, text: str = ""):
        x0, y0, x1, y1 = self.rect_px(x, y, w, h)
        self.boxes.append((CLASSES.index(cls), x0, y0, x1, y1, text))

    # -- elements ------------------------------------------------------------
    def rail(self, x0: float, x1: float, yc: float):
        self.gradient_rect(x0, yc - 17.5, x1 - x0, 35, (214, 216, 218), (160, 162, 166), outline=(120, 122, 126))
        self.gradient_rect(x0, yc - 9, x1 - x0, 18, (150, 152, 156), (196, 198, 200))
        sx = x0 + 6
        while sx < x1 - 12:
            X0, Y0, X1, Y1 = self.rect_px(sx, yc - 3, 10, 6)
            self.draw.rounded_rectangle([X0, Y0, X1, Y1], radius=self.p(2.5), fill=(70, 72, 76))
            sx += 25

    def duct(self, x: float, y: float, w: float, h: float):
        horiz = w >= h
        self.gradient_rect(x, y, w, h, (176, 178, 180), (140, 142, 146), outline=(105, 107, 110))
        if horiz:
            fx = x + 3
            while fx < x + w - 3:
                X0, Y0, X1, Y1 = self.rect_px(fx, y + 2, 2.6, h - 4)
                self.draw.rectangle([X0, Y0, X1, Y1], fill=(92, 94, 98))
                fx += 9
        else:
            fy = y + 3
            while fy < y + h - 3:
                X0, Y0, X1, Y1 = self.rect_px(x + 2, fy, w - 4, 2.6)
                self.draw.rectangle([X0, Y0, X1, Y1], fill=(92, 94, 98))
                fy += 9
        # cover
        self.gradient_rect(x + w * 0.08 if horiz else x + 3, y + 3 if horiz else y + h * 0.04, w * 0.84 if horiz else w - 6, h - 6 if horiz else h * 0.92, (190, 192, 194), (162, 164, 168))

    def label_plate(self, box, text: str | None, rng: random.Random, occluded: bool, yellow: bool):
        x, y, w, h = box
        bg = (238, 214, 70) if yellow else (243, 243, 238)
        self.gradient_rect(x, y, w, h, bg, _shade(bg, 0.93), outline=(150, 150, 140))
        if text:
            self.text(x + w / 2, y + h / 2 + 0.2, text, 6.4, (18, 18, 20))
        if occluded:
            # cable tie strapped across the label (makes it partly unreadable)
            X0, Y0, X1, Y1 = self.rect_px(x + w * 0.18, y - 3, w * 0.42, h + 6)
            self.draw.rectangle([X0, Y0, X1, Y1], fill=(24, 24, 26))
            self.draw.line([(X0 + 2, Y0 + 3), (X1 - 2, Y0 + 3)], fill=(70, 70, 74), width=2)
        self.add_box("device_label", x, y, w, h, text or "")

    def breaker(self, it: Item):
        body = self.style["breaker"]
        self.gradient_rect(it.x, it.y, it.w, it.h, body, _shade(body, 0.87), outline=_shade(body, 0.62))
        pole_w = it.w / max(1, it.poles)
        for k in range(it.poles):
            px = it.x + k * pole_w
            for ty in (it.y + 4, it.y + it.h - 13):
                self.gradient_rect(px + 2.5, ty, pole_w - 5, 9, (150, 150, 152), (118, 118, 122))
                cx, cy = self.p(px + pole_w / 2), self.p(ty + 4.5)
                r = self.p(2.6)
                self.draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(196, 198, 200), outline=(80, 80, 84))
                self.draw.line([(cx - r * 0.8, cy), (cx + r * 0.8, cy)], fill=(70, 70, 74), width=max(1, int(self.p(0.6))))
            # toggle
            self.gradient_rect(px + pole_w * 0.28, it.y + 30, pole_w * 0.44, 22, (70, 72, 76), (40, 42, 46))
            self.gradient_rect(px + pole_w * 0.30, it.y + 31, pole_w * 0.40, 9, (36, 120, 70) if k % 2 == 0 else (36, 120, 70), (30, 90, 56))
            if k > 0:
                X = self.p(px)
                self.draw.line([(X, self.p(it.y + 2)), (X, self.p(it.y + it.h - 2))], fill=(176, 176, 172), width=max(1, int(self.p(0.5))))
        stripe = (40, 90, 170)
        X0, Y0, X1, Y1 = self.rect_px(it.x + 2, it.y + 58, it.w - 4, 3)
        self.draw.rectangle([X0, Y0, X1, Y1], fill=stripe)
        if it.rating:
            self.text(it.x + it.w / 2, it.y + 68, it.rating, 4.2, (60, 60, 64), "DejaVuSans.ttf")
        self.add_box("circuit_breaker", it.x, it.y, it.w, it.h, it.tag)

    def contactor(self, it: Item):
        body = self.style["contactor"]
        self.gradient_rect(it.x, it.y, it.w, it.h, body, _shade(body, 0.72), outline=_shade(body, 0.48))
        for ty in (it.y + 3, it.y + it.h - 12):
            for k in range(3):
                cx = self.p(it.x + it.w * (0.2 + 0.3 * k))
                cy = self.p(ty + 4.5)
                r = self.p(2.8)
                self.draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(176, 178, 182), outline=(40, 40, 44))
        self.gradient_rect(it.x + it.w * 0.2, it.y + 24, it.w * 0.6, 22, (206, 196, 160), (176, 166, 132), outline=(70, 70, 70))
        self.text(it.x + it.w * 0.25, it.y + 52, "A1", 3.6, (230, 230, 230), "DejaVuSans.ttf")
        self.text(it.x + it.w * 0.75, it.y + 52, "A2", 3.6, (230, 230, 230), "DejaVuSans.ttf")
        self.add_box("contactor", it.x, it.y, it.w, it.h, it.tag)

    def psu(self, it: Item):
        body = self.style["psu"]
        self.gradient_rect(it.x, it.y, it.w, it.h, body, _shade(body, 0.81), outline=_shade(body, 0.55))
        for r in range(5):
            for c in range(4):
                X0, Y0, X1, Y1 = self.rect_px(it.x + 6 + c * (it.w - 12) / 4, it.y + 8 + r * 6, (it.w - 12) / 4 - 3, 2.4)
                self.draw.rectangle([X0, Y0, X1, Y1], fill=(64, 66, 70))
        cx, cy, r = self.p(it.x + it.w - 9), self.p(it.y + 46), self.p(2.2)
        self.draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(60, 230, 90))
        self.text(it.x + it.w / 2 - 4, it.y + 47, "24V DC", 4.4, (40, 42, 46), "DejaVuSans-Bold.ttf")
        self.gradient_rect(it.x + 4, it.y + it.h - 16, it.w - 8, 11, (60, 62, 66), (40, 42, 46))
        for k in range(5):
            cx = self.p(it.x + 9 + k * (it.w - 18) / 4)
            cy = self.p(it.y + it.h - 10.5)
            rr = self.p(2.2)
            self.draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(180, 182, 186))
        self.add_box("power_supply", it.x, it.y, it.w, it.h, it.tag)

    def earth_bar(self, it: Item):
        self.gradient_rect(it.x, it.y, it.w, it.h, (206, 140, 70), (150, 94, 44), outline=(110, 70, 30))
        n = int(it.w // 14)
        for k in range(n):
            cx = self.p(it.x + 8 + k * (it.w - 16) / max(1, n - 1))
            cy = self.p(it.y + it.h / 2)
            r = self.p(2.6)
            self.draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(205, 206, 210), outline=(80, 60, 30))
        self.add_box("earth_bar", it.x, it.y, it.w, it.h, it.tag)

    def terminal(self, t: Terminal, blue: bool):
        body = (78, 120, 196) if blue else self.style["terminal"]
        self.gradient_rect(t.x, t.y, t.w, t.h, body, _shade(body, 0.86), outline=_shade(body, 0.6))
        for ty in (t.y + 8, t.y + t.h - 8):
            cx, cy, r = self.p(t.x + t.w / 2), self.p(ty), self.p(3.3)
            self.draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(150, 152, 156), outline=(70, 70, 74))
            self.draw.line([(cx - r * 0.7, cy - r * 0.7), (cx + r * 0.7, cy + r * 0.7)], fill=(60, 60, 64), width=max(1, int(self.p(0.7))))
        X0, Y0, X1, Y1 = self.rect_px(t.x + 3, t.y + t.h / 2 - 4, t.w - 6, 8)
        self.draw.rectangle([X0, Y0, X1, Y1], fill=(246, 246, 242))
        self.text(t.x + t.w / 2, t.y + t.h / 2, str(t.number), 4.0, (30, 30, 30), "DejaVuSans.ttf")
        self.add_box("terminal_block", t.x, t.y, t.w, t.h, t.ref)

    def wire(self, x: float, y0: float, y1: float, color: str, width_mm: float = 3.4):
        c = WIRE_COLORS[color]
        X = self.p(x)
        wpx = max(2, int(self.p(width_mm)))
        self.draw.line([(X, self.p(y0)), (X, self.p(y1))], fill=_shade(c, 0.7), width=wpx)
        self.draw.line([(X - wpx * 0.12, self.p(y0)), (X - wpx * 0.12, self.p(y1))], fill=c, width=max(1, int(wpx * 0.65)))
        hl = tuple(min(255, int(v * 0.6 + 110)) for v in c)
        self.draw.line([(X - wpx * 0.22, self.p(y0)), (X - wpx * 0.22, self.p(y1))], fill=hl, width=max(1, int(wpx * 0.18)))
        if color == "green_yellow":
            yy = y0
            while yy < y1:
                self.draw.line([(X, self.p(yy)), (X, self.p(min(y1, yy + 5)))], fill=(230, 210, 40), width=max(1, int(wpx * 0.7)))
                yy += 10

    def marker(self, t: Terminal):
        x, y, w, h = t.marker_box
        self.gradient_rect(x, y, w, h, (248, 248, 244), (226, 226, 220), outline=(160, 160, 152))
        if t.ferrule_printed:
            self.text(x + w / 2, y + h / 2 + 0.2, t.ferrule_printed, 5.2, (16, 16, 18), "DejaVuSans-Bold.ttf")
        self.add_box("wire_marker", x, y, w, h, t.ferrule_printed or "")


def _duct_bottom_above(lay: Layout, y: float) -> float:
    best = None
    for (dx, dy, dw, dh) in lay.ducts:
        if dw >= dh and dy + dh <= y:
            if best is None or dy + dh > best:
                best = dy + dh
    return best if best is not None else max(0.0, y - 60)


def _duct_top_below(lay: Layout, y: float) -> float | None:
    best = None
    for (dx, dy, dw, dh) in lay.ducts:
        if dw >= dh and dy >= y:
            if best is None or dy < best:
                best = dy
    return best


def render_plate(lay: Layout, ppm: float, rng: random.Random) -> tuple[Image.Image, list]:
    pt = _Painter(lay, ppm, rng)

    def wire_shadow(x, y0, y1):
        X = pt.p(x) + max(1, int(pt.p(2.0)))
        pt.sdraw.line([(X, pt.p(y0)), (X, pt.p(y1))], fill=110, width=max(2, int(pt.p(3.4))))

    # rails
    for (x0, x1, yc) in lay.rails:
        pt.drop_shadow(x0, yc - 17.5, x1 - x0, 35, 90, 1.5)
    pt.apply_shadows()
    for (x0, x1, yc) in lay.rails:
        pt.rail(x0, x1, yc)
    # ducts
    for d in lay.ducts:
        pt.drop_shadow(*d, 120, 2.5)
    pt.apply_shadows()
    for d in lay.ducts:
        pt.duct(*d)
    # device wires down into the duct below each device
    dev_wires = []
    for it in lay.items:
        if not it.present or it.kind == "earth_bar":
            continue
        top = _duct_top_below(lay, it.y + it.h)
        if top is None:
            continue
        for k in range(max(1, it.poles)):
            x = it.x + (k + 0.5) * it.w / max(1, it.poles)
            col = rng.choice(["brown", "black", "grey", "blue", "red"]) if it.kind != "power_supply" else rng.choice(["red", "blue"])
            dev_wires.append((x, it.y + it.h - 6, top + 2, col))
    for (x, a, b, _) in dev_wires:
        wire_shadow(x, a, b)
    pt.apply_shadows()
    for (x, a, b, col) in dev_wires:
        pt.wire(x, a, b, col)
    # devices
    for it in lay.items:
        if it.present:
            strength, off = (170, 3.5) if it.kind == "power_supply" else ((120, 2.0) if it.kind == "earth_bar" else (150, 3.0))
            pt.drop_shadow(it.x, it.y, it.w, it.h, strength, off)
    for t in lay.terminals:
        pt.drop_shadow(t.x, t.y, t.w, t.h, 120, 1.8)
    pt.apply_shadows()
    for it in lay.items:
        if it.present:
            {"circuit_breaker": pt.breaker, "contactor": pt.contactor, "power_supply": pt.psu, "earth_bar": pt.earth_bar}[it.kind](it)
    for t in lay.terminals:
        pt.terminal(t, blue=False)
    # field wires from the duct above into terminals / earth bar
    field_wires = []
    for t in lay.terminals:
        top = _duct_bottom_above(lay, t.y)
        field_wires.append((t.x + t.w / 2, top - 2, t.y + 10, t.wire_color_actual))
    for it in lay.items:
        if it.kind == "earth_bar" and it.present:
            top = _duct_bottom_above(lay, it.y)
            for k in range(3):
                field_wires.append((it.x + 14 + k * 20, top - 2, it.y + it.h / 2, "green_yellow"))
    for (x, a, b, _) in field_wires:
        wire_shadow(x, a, b)
    pt.apply_shadows()
    for (x, a, b, col) in field_wires:
        pt.wire(x, a, b, col)
    # wire markers and label plates sit on top
    for t in lay.terminals:
        pt.drop_shadow(*t.marker_box, 90, 1.0)
    for it in lay.items:
        if it.label_text is not None:
            pt.drop_shadow(*it.label_box, 80, 0.8)
    for (text, x, y) in lay.strip_labels:
        pt.drop_shadow(x, y, 26, 10, 80, 0.8)
    pt.apply_shadows()
    for t in lay.terminals:
        pt.marker(t)
    for it in lay.items:
        if it.label_text is not None:
            pt.label_plate(it.label_box, it.label_text, rng, it.occluded_label, yellow=(it.kind == "earth_bar"))
    for (text, x, y) in lay.strip_labels:
        pt.label_plate((x, y, 26, 10), text, rng, False, yellow=True)
    return pt.img, pt.boxes


def photo_from_plate(
    plate: Image.Image,
    boxes: list,
    rng: random.Random,
    out_size: tuple[int, int] = (2400, 1800),
    jitter: float = 0.05,
    margin: float = 0.06,
    blur: tuple[float, float] = (0.5, 1.1),
    noise: tuple[float, float] = (2.5, 6.0),
    jpeg_quality: int | None = 88,
) -> tuple[np.ndarray, list, np.ndarray]:
    """Place the backplate in an enclosure, apply camera perspective, lighting and noise.

    Returns (BGR image, boxes in output pixel coordinates, H plate_px->photo_px).
    """
    OW, OH = out_size
    pw, ph = plate.size
    # target quad for the plate inside the frame
    mx, my = OW * margin, OH * margin
    avail_w, avail_h = OW - 2 * mx, OH - 2 * my
    s = min(avail_w / pw, avail_h / ph)
    w, h = pw * s, ph * s
    ox, oy = (OW - w) / 2, (OH - h) / 2
    dst = np.array([[ox, oy], [ox + w, oy], [ox + w, oy + h], [ox, oy + h]], np.float32)
    j = np.array([[rng.uniform(-1, 1) * jitter * OW, rng.uniform(-1, 1) * jitter * OH] for _ in range(4)], np.float32)
    dst = dst + j
    src = np.array([[0, 0], [pw, 0], [pw, ph], [0, ph]], np.float32)
    H = cv2.getPerspectiveTransform(src, dst)

    # enclosure background
    bg = np.zeros((OH, OW, 3), np.float32)
    base = np.array([62, 64, 68], np.float32) * rng.uniform(0.8, 1.15)
    yy, xx = np.mgrid[0:OH, 0:OW].astype(np.float32)
    bg[:] = base
    bg *= (0.75 + 0.35 * (yy / OH))[..., None]
    plate_bgr = cv2.cvtColor(np.asarray(plate), cv2.COLOR_RGB2BGR)
    warped = cv2.warpPerspective(plate_bgr, H, (OW, OH), flags=cv2.INTER_LINEAR)
    mask = cv2.warpPerspective(np.full((ph, pw), 255, np.uint8), H, (OW, OH))
    m = (mask.astype(np.float32) / 255.0)[..., None]
    img = warped.astype(np.float32) * m + bg * (1 - m)

    # lighting: directional gradient + vignette + soft hotspot
    ang = rng.uniform(0, 2 * math.pi)
    g = (np.cos(ang) * (xx / OW - 0.5) + np.sin(ang) * (yy / OH - 0.5))
    light = 1.0 + rng.uniform(0.08, 0.22) * g
    r2 = ((xx / OW - 0.5) ** 2 + (yy / OH - 0.5) ** 2)
    light *= 1.0 - rng.uniform(0.15, 0.32) * r2
    hx, hy = rng.uniform(0.2, 0.8) * OW, rng.uniform(0.2, 0.8) * OH
    light += rng.uniform(0.02, 0.08) * np.exp(-(((xx - hx) ** 2 + (yy - hy) ** 2) / (2 * (0.25 * OW) ** 2)))
    light *= rng.uniform(0.85, 1.08)
    img = img * light[..., None]
    # colour cast
    img *= np.array([rng.uniform(0.94, 1.06), 1.0, rng.uniform(0.94, 1.06)], np.float32)[None, None, :]
    img = np.clip(img, 0, 255).astype(np.uint8)
    sig = rng.uniform(*blur)
    if sig > 0.05:
        img = cv2.GaussianBlur(img, (0, 0), sig)
    nrng = np.random.default_rng(rng.randint(0, 1 << 30))
    img = np.clip(img.astype(np.float32) + nrng.normal(0, rng.uniform(*noise), img.shape), 0, 255).astype(np.uint8)
    if jpeg_quality:
        ok, enc = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, jpeg_quality])
        img = cv2.imdecode(enc, cv2.IMREAD_COLOR)

    out_boxes = []
    for (cls, x0, y0, x1, y1, text) in boxes:
        pts = np.array([[[x0, y0]], [[x1, y0]], [[x1, y1]], [[x0, y1]]], np.float32)
        tp = cv2.perspectiveTransform(pts, H).reshape(-1, 2)
        bx0, by0 = tp.min(axis=0)
        bx1, by1 = tp.max(axis=0)
        bx0, by0 = max(0.0, float(bx0)), max(0.0, float(by0))
        bx1, by1 = min(float(OW), float(bx1)), min(float(OH), float(by1))
        if bx1 - bx0 > 2 and by1 - by0 > 2:
            out_boxes.append((cls, bx0, by0, bx1, by1, text))
    return img, out_boxes, H


# ---------------------------------------------------------------------------
# Vector GA drawing (PDF)
# ---------------------------------------------------------------------------

def render_ga_pdf(lay: Layout, path: Path, title: str = "GENERAL ARRANGEMENT", drawing_no: str = "EE-DEMO-GA-007") -> dict:
    """Write a vector GA drawing of the *expected* layout. Returns the mm->pt mapping."""
    import pymupdf

    doc = pymupdf.open()
    page = doc.new_page(width=1190.55, height=841.89)  # A3 landscape
    margin = 36.0
    scale = min((page.rect.width - 2 * margin - 40) / lay.width, (page.rect.height - 2 * margin - 120) / lay.height)
    ox, oy = margin + 20, margin + 20

    def R(x, y, w, h):
        return pymupdf.Rect(ox + x * scale, oy + y * scale, ox + (x + w) * scale, oy + (y + h) * scale)

    ink = (0.1, 0.12, 0.16)
    soft = (0.45, 0.48, 0.55)
    zone_c = (0.05, 0.35, 0.6)

    # sheet frame
    page.draw_rect(pymupdf.Rect(margin - 18, margin - 18, page.rect.width - margin + 18, page.rect.height - margin + 18), color=ink, width=1.2)
    # backplate
    page.draw_rect(R(0, 0, lay.width, lay.height), color=ink, width=1.0)
    for (x0, x1, yc) in lay.rails:
        page.draw_rect(R(x0, yc - 17.5, x1 - x0, 35), color=soft, width=0.4, dashes="[2 2] 0")
    for (x, y, w, h) in lay.ducts:
        page.draw_rect(R(x, y, w, h), color=soft, width=0.5)
        r = R(x, y, w, h)
        if w >= h:
            page.draw_line(pymupdf.Point(r.x0, r.y0 + r.height / 2), pymupdf.Point(r.x1, r.y0 + r.height / 2), color=soft, width=0.3, dashes="[4 3] 0")
        else:
            page.draw_line(pymupdf.Point(r.x0 + r.width / 2, r.y0), pymupdf.Point(r.x0 + r.width / 2, r.y1), color=soft, width=0.3, dashes="[4 3] 0")
        page.insert_text(pymupdf.Point(r.x0 + 4, r.y0 + 9) if w >= h else pymupdf.Point(r.x0 + 3, r.y0 + 12), "DUCT 40x60" if w >= h else "DUCT", fontsize=5.5, color=soft)
    for z in lay.zones:
        rz = R(z.x, z.y, z.w, z.h)
        page.draw_rect(rz, color=zone_c, width=0.9, dashes="[6 3] 0")
        page.insert_text(pymupdf.Point(rz.x0 + 4, rz.y0 + 11), f"{z.code} {z.name}", fontsize=8, fontname="hebo", color=zone_c)
    for it in lay.items:
        rb = R(it.x, it.y, it.w, it.h)
        page.draw_rect(rb, color=ink, width=0.8)
        desc = it.description or it.kind.replace("_", " ").upper()
        fs = 4.6
        tw = pymupdf.get_text_length(desc, fontname="helv", fontsize=fs)
        if tw > rb.width - 2:
            fs = max(3.2, fs * (rb.width - 2) / tw)
        page.insert_text(pymupdf.Point(rb.x0 + (rb.width - pymupdf.get_text_length(desc, fontname="helv", fontsize=fs)) / 2, rb.y0 + rb.height * 0.55), desc, fontsize=fs, fontname="helv", color=soft)
        # designation label plate (expected tag)
        lx, ly, lw, lh = it.label_box
        rl = R(lx, ly, lw, lh)
        page.draw_rect(rl, color=ink, width=0.6)
        fs = 7.0
        tlen = pymupdf.get_text_length(it.tag, fontname="hebo", fontsize=fs)
        page.insert_text(pymupdf.Point(rl.x0 + (rl.width - tlen) / 2, rl.y0 + rl.height / 2 + fs * 0.36), it.tag, fontsize=fs, fontname="hebo", color=ink)
    for (text, x, y) in lay.strip_labels:
        rl = R(x, y, 26, 10)
        page.draw_rect(rl, color=ink, width=0.6)
        tlen = pymupdf.get_text_length(text, fontname="hebo", fontsize=7)
        page.insert_text(pymupdf.Point(rl.x0 + (rl.width - tlen) / 2, rl.y0 + rl.height / 2 + 2.5), text, fontsize=7, fontname="hebo", color=ink)
    for t in lay.terminals:
        rt = R(t.x, t.y, t.w, t.h)
        page.draw_rect(rt, color=ink, width=0.6)
        num = str(t.number)
        page.insert_text(pymupdf.Point(rt.x0 + (rt.width - pymupdf.get_text_length(num, fontname="helv", fontsize=5)) / 2, rt.y0 + rt.height / 2 + 2), num, fontsize=5, fontname="helv", color=ink)
        mx, my, mw, mh = t.marker_box
        rm = R(mx, my, mw, mh)
        page.draw_rect(rm, color=ink, width=0.5)
        fs = 5.6
        tlen = pymupdf.get_text_length(t.ferrule_expected, fontname="cobo", fontsize=fs)
        if tlen > rm.width - 1:
            fs = fs * (rm.width - 1) / tlen
            tlen = pymupdf.get_text_length(t.ferrule_expected, fontname="cobo", fontsize=fs)
        page.insert_text(pymupdf.Point(rm.x0 + (rm.width - tlen) / 2, rm.y0 + rm.height / 2 + fs * 0.36), t.ferrule_expected, fontsize=fs, fontname="cobo", color=ink)
        page.draw_line(pymupdf.Point(rm.x0 + rm.width / 2, rm.y1), pymupdf.Point(rt.x0 + rt.width / 2, rt.y0), color=soft, width=0.4)
    # title block
    tb = pymupdf.Rect(page.rect.width - margin - 330, page.rect.height - margin - 74, page.rect.width - margin + 10, page.rect.height - margin + 10)
    page.draw_rect(tb, color=ink, width=1.0)
    rows = [
        ("TITLE", f"{title} — CABINET {lay.cabinet_id}"),
        ("DWG NO.", drawing_no),
        ("SHEET", "1 / 1      SCALE  NTS      UNITS  mm"),
        ("STATUS", "SYNTHETIC DEMONSTRATION FIXTURE — NOT FOR CONSTRUCTION"),
    ]
    for i, (k, v) in enumerate(rows):
        y = tb.y0 + 14 + i * 18
        page.insert_text(pymupdf.Point(tb.x0 + 6, y), k, fontsize=6, fontname="helv", color=soft)
        page.insert_text(pymupdf.Point(tb.x0 + 56, y), v, fontsize=7.2, fontname="hebo", color=ink)
        if i < len(rows) - 1:
            page.draw_line(pymupdf.Point(tb.x0, y + 5), pymupdf.Point(tb.x1, y + 5), color=soft, width=0.4)
    page.insert_text(pymupdf.Point(margin, page.rect.height - margin + 4), "EAGLE EYE · OpHackers · generated drawing for software demonstration only", fontsize=6, color=soft)
    doc.set_metadata({"title": f"GA {lay.cabinet_id} (synthetic)", "author": "EAGLE EYE demo fixture generator", "subject": "Synthetic demonstration fixture"})
    path.parent.mkdir(parents=True, exist_ok=True)
    doc.save(str(path), garbage=3, deflate=True)
    doc.close()
    return {"scale_pt_per_mm": scale, "origin_pt": [ox, oy]}


def render_photo(lay: Layout, seed: int, ppm: float = 3.0, out_size=(2400, 1800), **kw):
    rng = random.Random(seed)
    plate, boxes = render_plate(lay, ppm, rng)
    return photo_from_plate(plate, boxes, rng, out_size=out_size, **kw)


def encode_jpeg(img: np.ndarray, quality: int = 92) -> bytes:
    ok, enc = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, quality])
    if not ok:
        raise RuntimeError("JPEG encoding failed")
    return enc.tobytes()


def to_png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()
