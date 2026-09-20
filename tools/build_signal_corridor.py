import json
import math
import random
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src" / "prototypes" / "SignalCorridor.model.json"
rng = random.Random(719)


def instance(name, kind, properties=None, children=None):
    return {"name": name, "className": kind, "properties": properties or {}, "children": children or []}


def color(rgb):
    return {"Color3": [round(v / 255, 5) for v in rgb]}


def transform(position, yaw=0, roll=0):
    c, s, cr, sr = math.cos(yaw), math.sin(yaw), math.cos(roll), math.sin(roll)
    return {"CFrame": {"position": position, "orientation": [[c * cr, -c * sr, s], [sr, cr, 0], [-s * cr, s * sr, c]]}}


def part(name, size, position, rgb, material="SmoothPlastic", collide=False, yaw=0, roll=0, shape="Block", reflectance=0):
    return instance(name, "Part", {
        "Size": {"Vector3": size}, "CFrame": transform(position, yaw, roll),
        "Color": color(rgb), "Material": material, "Shape": shape,
        "Anchored": True, "CanCollide": collide, "CanTouch": False,
        "CanQuery": collide, "CastShadow": True, "Reflectance": reflectance,
        "TopSurface": "Smooth", "BottomSurface": "Smooth",
    })


def frame(name, position, size, rgb, transparency=0):
    return instance(name, "Frame", {
        "Position": {"UDim2": [[position[0], 0], [position[1], 0]]},
        "Size": {"UDim2": [[size[0], 0], [size[1], 0]]},
        "BackgroundColor3": color(rgb), "BackgroundTransparency": transparency,
        "BorderSizePixel": 0, "ZIndex": 2,
    })


def tv(name, origin, yaw, scale, red, tilt):
    model = instance(name, "Model")

    def piece(label, size, offset, rgb, material="SmoothPlastic"):
        x, y, z = [n * scale for n in offset]
        x, y = x * math.cos(tilt) - y * math.sin(tilt), x * math.sin(tilt) + y * math.cos(tilt)
        position = [origin[0] + x * math.cos(yaw) + z * math.sin(yaw), origin[1] + y,
                    origin[2] - x * math.sin(yaw) + z * math.cos(yaw)]
        obj = part(label, [n * scale for n in size], position, rgb, material, yaw=yaw, roll=tilt)
        model["children"].append(obj)
        return obj

    piece("DeepHousing", [3.55, 2.8, 1.65], [0, 0, 0], (25, 20, 22))
    piece("RecessedBezel", [3.32, 2.56, .18], [0, 0, -.85], (9, 7, 9))
    screen = piece("ConvexGlass", [2.79, 2.18, .22], [-.17, .05, -.97], (90, 5, 8) if red else (31, 41, 42))
    gui = instance("Broadcast", "SurfaceGui", {
        "Face": "Front", "CanvasSize": {"Vector2": [512, 400]},
        "LightInfluence": 0, "Brightness": 1.45 if red else .65,
        "AlwaysOnTop": False, "MaxDistance": 70,
    })
    image = instance("Signal", "ImageLabel", {
        "Size": {"UDim2": [[1, 0], [1, 0]]}, "BackgroundColor3": color((108, 3, 8) if red else (39, 43, 42)),
        "BorderSizePixel": 0, "Image": "rbxassetid://125278888728934",
        "ImageRectOffset": {"Vector2": [512 if red else 0, 0]},
        "ImageRectSize": {"Vector2": [512, 512]}, "ImageColor3": color((255, 150, 145) if red else (151, 176, 171)),
    }, [instance("RoundedGlass", "UICorner", {"CornerRadius": {"UDim": [.095, 0]}})])
    gui["children"].append(image)
    for i in range(19):
        image["children"].append(frame("Scanline%02d" % i, [0, i / 19], [1, .006], (0, 0, 0), .63))
    screen["children"].append(gui)
    piece("ControlStrip", [.23, 2.15, .12], [1.43, 0, -.99], (42, 32, 32))
    for y in [.65, .14]:
        knob = piece("TuningDial", [.2, .22, .15], [1.43, y, -1.09], (75, 64, 59))
        knob["properties"]["Shape"] = "Ball"
    piece("StandbyLED", [.06, .055, .03], [1.43, -.61, -1.07], (255, 40, 18), "Neon")
    for i in range(5):
        piece("SpeakerSlot%02d" % i, [.2, .032, .02], [1.43, -.22 - i * .065, -1.07], (5, 5, 5))
    return model


model = instance("SignalCorridor_Prototype", "Model")
architecture = instance("Architecture", "Model")
model["children"].append(architecture)
architecture["children"].extend([
    part("WalkableFloor", [18, 1, 36], [0, -.5, -14], (21, 13, 17), "Slate", True),
    part("RemovableCeiling", [18, 1, 32], [0, 17.5, -15], (10, 8, 11), "Slate", True),
    part("TerminalWall", [18, 17, 1], [0, 8.5, -30.5], (18, 8, 12), "Slate", True),
])

for side in [-1, 1]:
    for bay in range(3):
        center_z = -5 - bay * 10
        module = instance(("Left" if side < 0 else "Right") + "Wall_%02d" % (bay + 1), "Model")
        model["children"].append(module)
        module["children"].append(part("SolidBacking", [1, 17, 10], [side * 8.1, 8.5, center_z], (46, 14, 22), "Slate", True))
        tissue = instance("OrganicGrowth", "Model")
        module["children"].append(tissue)
        for strand in range(4):
            base_z = center_z - 4.05 + strand * 2.6
            phase = rng.uniform(0, 6.28)
            for j in range(9):
                y = .7 + j * 1.86
                z = base_z + .53 * math.sin(j * .88 + phase)
                x = side * (7.55 - .30 * math.sin(j * .7 + phase))
                radius = rng.uniform(.86, 1.36)
                rgb = rng.choice([(88, 29, 38), (106, 40, 48), (71, 19, 30), (118, 48, 53)])
                tissue["children"].append(part("Fold_%02d_%02d" % (strand, j), [radius * 1.38, 2.9, radius * 1.7], [x, y, z], rgb, yaw=rng.uniform(-.3, .3), roll=side * rng.uniform(-.3, .3), shape="Ball", reflectance=.09))
                if j % 3 == 0:
                    tissue["children"].append(part("DarkNodule_%02d_%02d" % (strand, j), [.72, 1.0, .7], [side * 6.78, y + .5, z + .28], (39, 8, 18), shape="Ball", reflectance=.15))
        for i in range(5):
            tissue["children"].append(part("Root_%02d" % i, [2.25, 1.15, 2.7], [side * rng.uniform(6.9, 7.6), .42, center_z - 4 + i * 2], (66, 18, 30), shape="Ball", reflectance=.12))
        for row in range(3):
            red = (bay + row + (side == 1)) % 2 == 0
            module["children"].append(tv("CRT_%02d" % (row + 1), [side * 6.96, 2.8 + row * 5.15 + rng.uniform(-.4, .4), center_z + (1.8 if row % 2 else -1.75)], side * math.pi / 2, rng.uniform(1.02, 1.27), red, rng.uniform(-.14, .14)))
        lamp = part("ScreenBounce", [.1, .1, .1], [side * 5.5, 7, center_z], (0, 0, 0))
        lamp["properties"]["Transparency"] = 1
        lamp["children"].append(instance("RedSpill", "PointLight", {"Color": color((255, 48, 48)), "Brightness": 1.35, "Range": 15, "Shadows": True}))
        module["children"].append(lamp)

model["children"].append(tv("EndBroadcast", [0, 7.4, -29.6], math.pi, .97, True, -.055))
floor_details = instance("FloorGrowthAndPuddles", "Model")
model["children"].append(floor_details)
for i in range(18):
    floor_details["children"].append(part("WetPatch_%02d" % i, [rng.uniform(1.2, 3.4), .055, rng.uniform(1.4, 4.9)], [rng.uniform(-5, 5), .015, rng.uniform(-29, 1)], (24, 12, 17), shape="Ball", reflectance=.22))

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
model.pop("name")
OUTPUT.write_text(json.dumps(model, indent=2) + "\n", encoding="ascii")


def walk(node):
    yield node
    for child in node.get("children", []):
        yield from walk(child)


nodes = list(walk(model))
parts = [n for n in nodes if n["className"] == "Part"]
assert all(p["properties"]["Anchored"] for p in parts)
assert not any(n["className"] in ("Script", "LocalScript", "ModuleScript") for n in nodes)
print("Generated %s: %d anchored parts, %d CRTs, no scripts" % (OUTPUT.name, len(parts), sum(n["className"] == "SurfaceGui" for n in nodes)))
