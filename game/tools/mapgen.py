"""Tiny helper library for building Roblox maps as Rojo .model.json files.

Every function returns a plain dict in Rojo's JSON model format, so maps can be
written as normal Python code (loops, math, reuse) and then saved with save().

Conventions
- Positions and sizes are in studs: (x, y, z).
- Rotations are in degrees, applied like Studio's Orientation property
  (Y first, then X, then Z).
- Colors are hex strings ("#ff8800") or (r, g, b) tuples with 0-255 values.
"""

import json
import math
import os


# ---------------------------------------------------------------- math helpers

def _rx(a):
    c, s = math.cos(a), math.sin(a)
    return [[1, 0, 0], [0, c, -s], [0, s, c]]


def _ry(a):
    c, s = math.cos(a), math.sin(a)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def _rz(a):
    c, s = math.cos(a), math.sin(a)
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


def _mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def rotation(rx=0, ry=0, rz=0):
    """3x3 rotation matrix (rows) for an Orientation-style (YXZ) rotation in degrees."""
    m = _mul(_mul(_ry(math.radians(ry)), _rx(math.radians(rx))), _rz(math.radians(rz)))
    return [[round(v, 6) + 0.0 for v in row] for row in m]


def cframe(pos, rot=(0, 0, 0)):
    return {"CFrame": {"position": [float(p) for p in pos], "orientation": rotation(*rot)}}


def color(c):
    if isinstance(c, str):
        c = c.lstrip("#")
        return [int(c[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [v / 255 for v in c]


def offset(origin, local, ry=0):
    """Rotate a local (x, y, z) offset around Y by ry degrees and add it to origin."""
    a = math.radians(ry)
    x, y, z = local
    return (origin[0] + x * math.cos(a) + z * math.sin(a),
            origin[1] + y,
            origin[2] - x * math.sin(a) + z * math.cos(a))


# ---------------------------------------------------------------- instances

def inst(class_name, name=None, props=None, children=None, attrs=None, tags=None):
    d = {"ClassName": class_name}
    if name:
        d["Name"] = name
    if props:
        d["Properties"] = props
    if attrs:
        d["Attributes"] = attrs
    if tags:
        d["Tags"] = tags
    kids = [c for c in (children or []) if c]
    if kids:
        d["Children"] = kids
    return d


def part(name, size, pos, rot=(0, 0, 0), col="#a3a2a5", material="SmoothPlastic",
         shape=None, cls="Part", transparency=0, collide=True, anchored=True,
         cast_shadow=True, reflectance=0, props=None, children=None, attrs=None, tags=None):
    p = {
        "Anchored": anchored,
        "Size": [float(s) for s in size],
        "CFrame": cframe(pos, rot),
        "Color": color(col),
        "Material": material,
        "TopSurface": "Smooth",
        "BottomSurface": "Smooth",
    }
    if shape:
        p["Shape"] = shape
    if transparency:
        p["Transparency"] = float(transparency)
    if not collide:
        p["CanCollide"] = False
    if not cast_shadow:
        p["CastShadow"] = False
    if reflectance:
        p["Reflectance"] = float(reflectance)
    if props:
        p.update(props)
    return inst(cls, name, p, children, attrs, tags)


def wedge(name, size, pos, rot=(0, 0, 0), **kw):
    return part(name, size, pos, rot, cls="WedgePart", **kw)


def ball(name, diameter, pos, **kw):
    return part(name, (diameter, diameter, diameter), pos, shape="Ball", **kw)


def cylinder(name, length, diameter, pos, rot=(0, 0, 0), **kw):
    """Roblox cylinders run along the part's X axis; use rot=(0,0,90) to stand one up."""
    return part(name, (length, diameter, diameter), pos, rot, shape="Cylinder", **kw)


def model(name, children, attrs=None, tags=None):
    return inst("Model", name, None, children, attrs, tags)


def folder(name, children, attrs=None):
    return inst("Folder", name, None, children, attrs)


# ---------------------------------------------------------------- effects & gui

def point_light(col="#ffffff", brightness=1.5, range_=16, shadows=False):
    return inst("PointLight", "Light", {"Color": color(col), "Brightness": float(brightness),
                                         "Range": float(range_), "Shadows": shadows})


def spot_light(col="#ffffff", brightness=2, range_=30, angle=60, face="Bottom"):
    return inst("SpotLight", "Spot", {"Color": color(col), "Brightness": float(brightness),
                                      "Range": float(range_), "Angle": float(angle), "Face": face})


def particles(name="Particles", col="#ffffff", col2=None, rate=10, lifetime=(1, 2), speed=(2, 4),
              size=(1, 0), texture="rbxasset://textures/particles/sparkles_main.dds",
              light_emission=0.6, spread=(30, 30), transparency=(0, 1), accel=(0, 0, 0)):
    c1, c2 = color(col), color(col2 or col)
    return inst("ParticleEmitter", name, {
        "Texture": texture,
        "Rate": float(rate),
        "Lifetime": {"NumberRange": [float(lifetime[0]), float(lifetime[1])]},
        "Speed": {"NumberRange": [float(speed[0]), float(speed[1])]},
        "SpreadAngle": [float(spread[0]), float(spread[1])],
        "Acceleration": [float(a) for a in accel],
        "LightEmission": float(light_emission),
        "Color": {"ColorSequence": {"keypoints": [{"time": 0, "color": c1}, {"time": 1, "color": c2}]}},
        "Size": {"NumberSequence": {"keypoints": [
            {"time": 0, "value": float(size[0]), "envelope": 0},
            {"time": 1, "value": float(size[1]), "envelope": 0}]}},
        "Transparency": {"NumberSequence": {"keypoints": [
            {"time": 0, "value": float(transparency[0]), "envelope": 0},
            {"time": 1, "value": float(transparency[1]), "envelope": 0}]}},
    })


def udim2(xs, xo, ys, yo):
    return {"UDim2": [[float(xs), int(xo)], [float(ys), int(yo)]]}


FONT = {"Font": {"family": "rbxasset://fonts/families/FredokaOne.json", "weight": "Regular", "style": "Normal"}}
FONT_BOLD = {"Font": {"family": "rbxasset://fonts/families/GothamSSm.json", "weight": "Heavy", "style": "Normal"}}


def text_label(text, col="#ffffff", stroke="#000000", font=None, bg=None, size=None, pos=None, name="Text"):
    p = {
        "Text": text,
        "TextScaled": True,
        "TextColor3": color(col),
        "TextStrokeColor3": color(stroke),
        "TextStrokeTransparency": 0.2,
        "FontFace": font or FONT,
        "Size": size or udim2(1, 0, 1, 0),
        "BackgroundTransparency": 1.0 if bg is None else 0.0,
    }
    if bg is not None:
        p["BackgroundColor3"] = color(bg)
    if pos:
        p["Position"] = pos
    return inst("TextLabel", name, p)


def surface_text(text, face="Front", col="#ffffff", stroke="#000000", bg=None, pixels=50, light=1.0):
    return inst("SurfaceGui", "Sign", {"Face": face, "PixelsPerStud": float(pixels),
                                        "SizingMode": "PixelsPerStud", "LightInfluence": float(light)},
                [text_label(text, col, stroke, bg=bg)])


def billboard(text, col="#ffffff", stroke="#000000", size=(8, 2), offset_y=3, max_distance=150):
    return inst("BillboardGui", "Billboard", {
        "Size": udim2(size[0], 0, size[1], 0),
        "StudsOffset": [0.0, float(offset_y), 0.0],
        "AlwaysOnTop": False,
        "MaxDistance": float(max_distance),
        "LightInfluence": 0.0,
    }, [text_label(text, col, stroke)])


# ---------------------------------------------------------------- prefabs

def tree(name, base, trunk_h=8, leaf_col="#4caf50", trunk_col="#7a4b2a", leaf_size=9, style="round"):
    x, y, z = base
    kids = [cylinder("Trunk", trunk_h, 1.6, (x, y + trunk_h / 2, z), (0, 0, 90), col=trunk_col, material="Wood")]
    if style == "round":
        kids.append(ball("Leaves", leaf_size, (x, y + trunk_h + leaf_size * 0.3, z), col=leaf_col, material="Grass"))
        kids.append(ball("Leaves2", leaf_size * 0.7, (x + 2, y + trunk_h - 0.5, z + 1.5), col=leaf_col, material="Grass"))
    elif style == "pine":
        for i in range(3):
            w = leaf_size * (1 - i * 0.28)
            kids.append(part(f"Leaves{i}", (w, 2.6, w), (x, y + trunk_h - 1 + i * 2.2, z), (0, 45 * i, 0),
                             col=leaf_col, material="Grass"))
    elif style == "sakura":
        kids.append(ball("Blossom", leaf_size, (x, y + trunk_h + 1.5, z), col=leaf_col, material="SmoothPlastic"))
        kids.append(ball("Blossom2", leaf_size * 0.75, (x - 2.5, y + trunk_h, z + 1), col=leaf_col, material="SmoothPlastic"))
        kids.append(ball("Blossom3", leaf_size * 0.7, (x + 2.2, y + trunk_h + 0.5, z - 1.5), col=leaf_col, material="SmoothPlastic"))
        kids[1]["Children"] = [particles("Petals", "#ffc0d9", "#ffffff", rate=3, lifetime=(4, 6), speed=(1, 2),
                                         size=(0.35, 0.2), accel=(0.5, -1.5, 0), light_emission=0.2,
                                         spread=(180, 180))]
    return model(name, kids)


def lamp_post(name, base, height=10, glow="#ffd27a", pole="#2b2b2b"):
    x, y, z = base
    return model(name, [
        cylinder("Pole", height, 0.6, (x, y + height / 2, z), (0, 0, 90), col=pole, material="Metal"),
        ball("Bulb", 1.6, (x, y + height + 0.6, z), col=glow, material="Neon",
             children=[point_light(glow, 1.4, 22)]),
    ])


def stairs(name, start, steps, step_size=(8, 1, 2), rise=1, run=2, ry=0, col="#9e9e9e", material="Concrete"):
    kids = []
    for i in range(steps):
        pos = offset(start, (0, i * rise + step_size[1] / 2, i * run), ry)
        kids.append(part(f"Step{i}", step_size, pos, (0, ry, 0), col=col, material=material))
    return model(name, kids)


def ring(name, center, radius, count, size, col, material="Neon", y=0, face_out=True, **kw):
    """Place `count` parts evenly around a circle (good for pillars, lights, fences)."""
    kids = []
    for i in range(count):
        a = 2 * math.pi * i / count
        pos = (center[0] + radius * math.cos(a), center[1] + y, center[2] + radius * math.sin(a))
        ry = -math.degrees(a) + (90 if face_out else 0)
        kids.append(part(f"{name}{i}", size, pos, (0, ry, 0), col=col, material=material, **kw))
    return model(name, kids)


def save(obj, path):
    """Write a model to disk. Rojo names the instance after the file, so the top-level Name is dropped."""
    obj = {k: v for k, v in obj.items() if k != "Name"}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, indent=1)
    return path


def count_parts(obj):
    n = 1 if obj.get("ClassName") in ("Part", "WedgePart", "SpawnLocation", "TrussPart", "CornerWedgePart") else 0
    return n + sum(count_parts(c) for c in obj.get("Children", []))
