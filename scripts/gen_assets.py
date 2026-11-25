#!/usr/bin/env python3
"""Generates the vector assets of the app (chess pieces and move-classification
badges) as SVG files inside an Xcode asset catalog.

Usage: python3 scripts/gen_assets.py

All artwork is original and drawn with plain paths (no text, filters or masks),
which keeps it compatible with the asset catalog compiler. The output goes to
App/Resources/Assets.xcassets and is committed to the repository, so running
this script is only needed after changing the drawings.
"""
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "App", "Resources", "Assets.xcassets")

SVG_HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
            'viewBox="0 0 100 100">\n')
SVG_TAIL = "</svg>\n"


# ---------------------------------------------------------------- primitives

def path(d, fill="none", stroke="none", sw=0.0):
    attrs = f'd="{d}" fill="{fill}"'
    if stroke != "none":
        attrs += (f' stroke="{stroke}" stroke-width="{sw}" '
                  'stroke-linejoin="round" stroke-linecap="round"')
    return f"  <path {attrs}/>\n"


def circle(cx, cy, r, fill="none", stroke="none", sw=0.0):
    attrs = f'cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"'
    if stroke != "none":
        attrs += f' stroke="{stroke}" stroke-width="{sw}"'
    return f"  <circle {attrs}/>\n"


# -------------------------------------------------------------------- pieces

SCHEMES = {
    "w": {"fill": "#f7f4ee", "line": "#2b2825", "detail": "#bdb6a6"},
    "b": {"fill": "#48443f", "line": "#0e0d0c", "detail": "#948d82"},
}
LINE_W = 2.6


def plinth(c):
    """Wide base shared by every piece."""
    return path("M21 92 L21 87 Q21 82 26 82 L74 82 Q79 82 79 87 L79 92 Z",
                c["fill"], c["line"], LINE_W)


def pawn(c):
    out = plinth(c)
    out += path("M50 38 C41 38 37 44 40 52 C42 57 44 60 42 66 C40 72 35 75 31 82 "
                "L69 82 C65 75 60 72 58 66 C56 60 58 57 60 52 C63 44 59 38 50 38 Z",
                c["fill"], c["line"], LINE_W)
    out += path("M37 50 Q50 56 63 50", "none", c["detail"], 2.0)
    out += circle(50, 28, 12.5, c["fill"], c["line"], LINE_W)
    out += path("M44 25 Q46 21 50 21", "none", c["detail"], 2.0)
    return out


def rook(c):
    out = plinth(c)
    out += path("M33 82 L37 44 L63 44 L67 82 Z", c["fill"], c["line"], LINE_W)
    out += path("M28 44 L28 20 L38 20 L38 27 L45 27 L45 20 L55 20 L55 27 "
                "L62 27 L62 20 L72 20 L72 44 Z", c["fill"], c["line"], LINE_W)
    out += path("M30 38 L70 38", "none", c["detail"], 2.0)
    out += path("M41 52 L40 74", "none", c["detail"], 2.0)
    return out


def bishop(c):
    out = plinth(c)
    out += path("M39 70 L34 82 L66 82 L61 70 Z", c["fill"], c["line"], LINE_W)
    out += path("M50 20 C64 29 69 42 62 55 C60 59 58 61 58 64 L42 64 "
                "C42 61 40 59 38 55 C31 42 36 29 50 20 Z",
                c["fill"], c["line"], LINE_W)
    out += path("M33 63 Q33 70 40 70 L60 70 Q67 70 67 63 Q67 57 60 57 L40 57 "
                "Q33 57 33 63 Z", c["fill"], c["line"], LINE_W)
    out += path("M45 34 L55 46", "none", c["line"], 3.0)
    out += circle(50, 13, 5.5, c["fill"], c["line"], LINE_W)
    return out


def knight(c):
    out = plinth(c)
    out += path("M28 82 C28 71 30 64 37 58 C31 58 24 61 18 59 C13 57 12 51 16 46 "
                "C20 41 26 36 31 28 L32 15 L41 23 C57 22 73 38 76 62 "
                "C77 70 77 76 77 82 Z", c["fill"], c["line"], LINE_W)
    out += path("M43 30 C57 34 66 47 67 66", "none", c["detail"], 2.4)
    out += path("M36 58 C42 54 44 50 43 45", "none", c["detail"], 2.0)
    out += circle(32, 41, 2.6, c["line"])
    out += circle(17, 51, 1.6, c["line"])
    return out


def queen(c):
    out = plinth(c)
    out += path("M26 82 L16 34 L32 56 L34 24 L43 54 L50 20 L57 54 L66 24 L68 56 "
                "L84 34 L74 82 Z", c["fill"], c["line"], LINE_W)
    for cx, cy in ((16, 30), (34, 20), (50, 16), (66, 20), (84, 30)):
        out += circle(cx, cy, 4.8, c["fill"], c["line"], LINE_W)
    out += path("M28 72 Q50 78 72 72", "none", c["detail"], 2.0)
    return out


def king(c):
    out = plinth(c)
    out += path("M50 30 C70 30 78 47 71 60 C67 66 67 71 71 82 L29 82 "
                "C33 71 33 66 29 60 C22 47 30 30 50 30 Z",
                c["fill"], c["line"], LINE_W)
    out += path("M47 8 L53 8 L53 14 L59 14 L59 20 L53 20 L53 30 L47 30 L47 20 "
                "L41 20 L41 14 L47 14 Z", c["fill"], c["line"], LINE_W)
    out += path("M30 70 Q50 76 70 70", "none", c["detail"], 2.0)
    out += path("M37 46 Q40 38 47 36", "none", c["detail"], 2.0)
    return out


PIECES = {"P": pawn, "N": knight, "B": bishop, "R": rook, "Q": queen, "K": king}


# -------------------------------------------------------- classification art

class Glyph:
    """Helper drawing exclamation / question marks around a centre x."""

    def __init__(self, cx, scale=1.0):
        self.cx = cx
        self.s = scale

    def pt(self, dx, y):
        return f"{self.cx + dx * self.s:.1f} {50 + (y - 50) * self.s:.1f}"

    def bang(self):
        p = self.pt
        d = (f"M{p(-6, 29)} Q{p(-6, 21)} {p(0, 21)} Q{p(6, 21)} {p(6, 29)} "
             f"L{p(4, 58)} L{p(-4, 58)} Z")
        out = path(d, "#ffffff")
        out += circle(round(self.cx, 1), round(50 + (71 - 50) * self.s, 1),
                      round(6.5 * self.s, 1), "#ffffff")
        return out

    def question(self):
        p = self.pt
        d = (f"M{p(-13, 36)} C{p(-13, 20)} {p(14, 20)} {p(14, 36)} "
             f"C{p(14, 48)} {p(0, 47)} {p(0, 58)}")
        out = path(d, "none", "#ffffff", round(9.5 * self.s, 1))
        out += circle(round(self.cx, 1), round(50 + (72 - 50) * self.s, 1),
                      round(6.2 * self.s, 1), "#ffffff")
        return out


def star():
    pts = []
    for i in range(10):
        r = 28 if i % 2 == 0 else 12
        a = -math.pi / 2 + i * math.pi / 5
        pts.append(f"{50 + r * math.cos(a):.1f} {53 + r * math.sin(a):.1f}")
    return path("M" + " L".join(pts) + " Z", "#ffffff")


CLASSES = {
    "brilliant": ("#1baca6", "#127f7a",
                  lambda: Glyph(33, 0.92).bang() + Glyph(67, 0.92).bang()),
    "great": ("#5c8bb0", "#3f6a8c", lambda: Glyph(50, 1.05).bang()),
    "best": ("#7fb53f", "#5b8a25", star),
    "excellent": ("#9bc95b", "#6f9a33", lambda: (
        path("M24 48 L37 48 L37 75 L24 75 Z", "#ffffff") +
        path("M42 48 L52 26 C54 21 62 22 62 28 L60 40 L74 40 C78 40 80 44 79 48 "
             "L75 66 C74 70 71 75 67 75 L42 75 Z", "#ffffff"))),
    "good": ("#8fa77b", "#6b8059",
             lambda: path("M27 52 L43 68 L74 34", "none", "#ffffff", 10.5)),
    "book": ("#a88865", "#836646", lambda: (
        path("M23 33 Q37 29 48 38 L48 71 Q37 62 23 66 Z", "#ffffff") +
        path("M77 33 Q63 29 52 38 L52 71 Q63 62 77 66 Z", "#ffffff"))),
    "inaccuracy": ("#f2b925", "#c18f0b",
                   lambda: Glyph(34, 0.92).question() + Glyph(70, 0.92).bang()),
    "mistake": ("#e58f2a", "#b86a10", lambda: Glyph(50, 1.05).question()),
    "miss": ("#e06a5b", "#b04a3d",
             lambda: path("M31 31 L69 69 M69 31 L31 69", "none", "#ffffff", 11)),
    "blunder": ("#ca3431", "#9b2220",
                lambda: Glyph(32, 0.92).question() + Glyph(68, 0.92).question()),
    "forced": ("#8b8987", "#666462", lambda: path(
        "M23 43 L53 43 L53 29 L79 50 L53 71 L53 57 L23 57 Z", "#ffffff")),
}


def badge(color, dark, glyph):
    out = circle(50, 50, 46.5, color, dark, 3.5)
    out += glyph()
    return out


# ------------------------------------------------------------------- writing

def write_imageset(name, svg_body):
    folder = os.path.join(CATALOG, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, name + ".svg"), "w", encoding="utf-8") as f:
        f.write(SVG_HEAD + svg_body + SVG_TAIL)
    contents = {
        "images": [{"filename": name + ".svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True},
    }
    with open(os.path.join(folder, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")


def main():
    os.makedirs(CATALOG, exist_ok=True)
    with open(os.path.join(CATALOG, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    for side, scheme in SCHEMES.items():
        for letter, fn in PIECES.items():
            write_imageset(f"piece_{side}{letter}", fn(scheme))
    for name, (color, dark, glyph) in CLASSES.items():
        write_imageset(f"class_{name}", badge(color, dark, glyph))
    print("Assets written to", CATALOG)


if __name__ == "__main__":
    main()
