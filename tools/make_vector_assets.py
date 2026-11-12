"""Rebuild original SVG/Lottie demo art and deterministic rendering fixtures."""
import json
import math
from pathlib import Path

assets = Path(__file__).resolve().parents[1] / "examples" / "assets"
assets.mkdir(parents=True, exist_ok=True)


def svg(name, content, width=320, height=240):
    text = f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{content}</svg>\n'
    (assets / name).write_text(text, encoding="utf-8")


petals = ''.join(f'<ellipse cx="160" cy="70" rx="26" ry="52" transform="rotate({i * 45} 160 120)" fill="url(#petal)" stroke="#593f70" stroke-width="2"/>' for i in range(8))
svg("vector_flower.svg", '<defs><linearGradient id="petal" x2="1" y2="1"><stop stop-color="#f6a8a2"/><stop offset="1" stop-color="#9377c7"/></linearGradient></defs>'
    + petals + '<circle cx="160" cy="120" r="32" fill="#ffe6a3" stroke="#593f70" stroke-width="3"/><circle cx="150" cy="112" r="5" fill="#593f70"/><circle cx="170" cy="112" r="5" fill="#593f70"/><path d="M149 130 Q160 141 173 128" fill="none" stroke="#593f70" stroke-width="4" stroke-linecap="round"/>')
svg("vector_orbit.svg", '<ellipse cx="160" cy="120" rx="120" ry="62" fill="none" stroke="#9b86c2" stroke-width="4" transform="rotate(-25 160 120)"/><circle cx="160" cy="120" r="65" fill="#ffe1a0"/><path d="M165 55 A65 65 0 1 1 112 163 Q189 161 165 55" fill="#ed9398"/><circle cx="258" cy="72" r="16" fill="#614d82"/><path d="M67 53 L72 67 L87 72 L72 77 L67 92 L62 77 L47 72 L62 67Z" fill="#b3a0d4"/>')
svg("vector_probe.svg", '<rect x="25" y="25" width="50" height="50" fill="#e8505b"/>', 100, 100)
svg("vector_probe_alt.svg", '<rect width="100" height="50" fill="#18aa88"/>', 100, 50)


def prop(value):
    return {"a": 0, "k": value}


def animated(points):
    keys = []
    for index, (frame, value) in enumerate(points):
        entry = {"t": frame, "s": value if isinstance(value, list) else [value]}
        if index + 1 < len(points):
            end = points[index + 1][1]
            entry.update(e=end if isinstance(end, list) else [end], i={"x": [1], "y": [1]}, o={"x": [0], "y": [0]})
        keys.append(entry)
    return {"a": 1, "k": keys}


def fill(color):
    return {"ty": "fl", "c": prop([*color, 1]), "o": prop(100), "r": 1}


def ellipse(size):
    return {"ty": "el", "p": prop([0, 0]), "s": prop([size, size]), "d": 1}


def layer(name, shapes, position, scale=None, rotation=None):
    return {"ddd": 0, "ind": 1, "ty": 4, "nm": name, "sr": 1,
            "ks": {"o": prop(100), "r": rotation or prop(0), "p": position,
                   "a": prop([0, 0, 0]), "s": scale or prop([100, 100, 100])},
            "shapes": shapes, "ip": 0, "op": 60, "st": 0, "bm": 0}


def lottie(name, layers, width=240, height=240):
    for index, item in enumerate(layers):
        item["ind"] = index + 1
    doc = {"v": "5.7.4", "fr": 30, "ip": 0, "op": 60, "w": width, "h": height,
           "nm": name, "ddd": 0, "assets": [], "layers": layers, "markers": []}
    (assets / name).write_text(json.dumps(doc, separators=(",", ":")) + "\n", encoding="utf-8")


lottie("vector_probe.json", [layer("Moving coral disc", [ellipse(32), fill([245 / 255, 92 / 255, 110 / 255])],
    animated([(0, [30, 50, 0]), (30, [170, 50, 0]), (60, [30, 50, 0])]))], 200, 100)
lottie("vector_probe_alt.json", [layer("Static teal disc", [ellipse(40), fill([24 / 255, 170 / 255, 136 / 255])], prop([50, 50, 0]))], 100, 100)
orbit = layer("Orbit ring", [ellipse(150), {"ty": "st", "c": prop([.69, .62, .83, 1]), "o": prop(100), "w": prop(3), "lc": 2, "lj": 2}], prop([120, 120, 0]))
sun = layer("Warm core", [ellipse(64), fill([1, .85, .57])], prop([120, 120, 0]), animated([(0, [90, 90, 100]), (30, [110, 110, 100]), (60, [90, 90, 100])]))
satellites = []
for index in range(3):
    points = []
    for frame in range(0, 61, 5):
        angle = 2 * math.pi * (frame / 60 + index / 3)
        points.append((frame, [round(120 + 75 * math.cos(angle), 4), round(120 + 75 * math.sin(angle), 4), 0]))
    satellites.append(layer(f"Satellite {index}", [ellipse(24 if index else 34), fill(([.91, .39, .45], [.42, .31, .59], [.61, .48, .77])[index])], animated(points)))
lottie("vector_motion.json", satellites + [sun, orbit])
lottie("vector_pulse.json", [layer("Breathing bloom", [ellipse(110), fill([.64, .49, .81])], prop([120, 120, 0]),
    animated([(0, [55, 55, 100]), (30, [120, 120, 100]), (60, [55, 55, 100])])), sun])
print("Generated 4 original SVGs and 4 original Lottie animations")
