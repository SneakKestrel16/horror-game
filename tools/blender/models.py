"""The game's models, exported to game/assets/models/.

Blender axes (Z up), every model facing +Y, which is Godot's -Z (see lib.py). A Godot
point (x, y, z) is Blender's (x, -z, y). The barn and shed are built where they stand on the
farm (Farm.BARN, Farm.SHED), so they import at the origin and line up with the colliders
farm.gd makes; everything else stands on its own origin.

The farmer and the creature hang their parts on empties that Godot animates by name:
`leg_0` and `leg_1` swing about X from the hip, `arm_0` and `arm_1` from the shoulder, `head`
turns. The creature's are where creature.gd's old primitive model had them, so its walk and
reach work unchanged.

Materials are named for the texture Godot dresses them in (textures.py), with "+..." to keep
differently tinted copies apart; "plain+..." is a flat colour and "glow+..." emits.
"""

import math
import random
from collections.abc import Sequence

import bmesh
import bpy
import lib
from lib import blob, box, cyl, lathe, mat, parent, pivot, sphere, torus, tube
from mathutils import Matrix, Vector

OUT = lib.MODELS
Vec = Sequence[float]


def _under(holder: bpy.types.Object, *parts: bpy.types.Object) -> None:
    for part in parts:
        parent(part, holder)


def _quad_strip(
    name: str,
    lefts: Sequence[Vec],
    rights: Sequence[Vec],
    material: bpy.types.Material,
    length_scale: float = 1.0,
) -> bpy.types.Object:
    """A ribbon between two rows of points, with UVs: u 0 to 1 across, v the distance
    along (in metres times length_scale). For leaves."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    rows = []
    v = 0.0
    for i, (left, right) in enumerate(zip(lefts, rights, strict=True)):
        if i:
            mid = (Vector(left) + Vector(right)) / 2
            last = (Vector(lefts[i - 1]) + Vector(rights[i - 1])) / 2
            v += (mid - last).length * length_scale
        rows.append((bm.verts.new(left), bm.verts.new(right), v))
    for (a0, b0, v0), (a1, b1, v1) in zip(rows, rows[1:]):
        face = bm.faces.new([a0, b0, b1, a1])
        for loop, coord in zip(face.loops, [(0, v0), (1, v0), (1, v1), (0, v1)], strict=True):
            loop[uv].uv = coord
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    scene = bpy.context.scene
    assert scene is not None
    scene.collection.objects.link(obj)
    mesh.materials.append(material)
    return obj


def _uv_tube(
    name: str, points: Sequence[Vec], radii: Sequence[float], material, sides: int = 6
) -> bpy.types.Object:
    """A tube with UVs (u round, v along in metres), open at the ends: stalks, husks."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    rings = []
    v = 0.0
    for i, p in enumerate(points):
        if i:
            v += (Vector(p) - Vector(points[i - 1])).length
        ahead = Vector(points[min(i + 1, len(points) - 1)]) - Vector(points[max(i - 1, 0)])
        ahead.normalize()
        side = lib._cross(ahead, Vector((0, 0, 1)) if abs(ahead.z) < 0.9 else Vector((1, 0, 0)))
        side.normalize()
        normal = lib._cross(side, ahead)
        ring = [
            bm.verts.new(
                (Vector(p) + (side * math.cos(a) + normal * math.sin(a)) * radii[i]).to_tuple()
            )
            for a in (2 * math.pi * j / sides for j in range(sides))
        ]
        rings.append((ring, v))
    for (r0, v0), (r1, v1) in zip(rings, rings[1:]):
        for j in range(sides):
            k = (j + 1) % sides
            face = bm.faces.new([r0[j], r0[k], r1[k], r1[j]])
            u0, u1 = j / sides, (j + 1) / sides
            for loop, coord in zip(face.loops, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], strict=True):
                loop[uv].uv = coord
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    scene = bpy.context.scene
    assert scene is not None
    scene.collection.objects.link(obj)
    mesh.materials.append(material)
    return obj


def _prism(
    name: str, outline: Sequence[tuple[float, float]], y0: float, y1: float, material
) -> bpy.types.Object:
    """A flat shape in the XZ plane (outline of (x, z), counter-clockwise seen from -Y),
    given thickness from y0 to y1: gable ends, sloped wall tops."""
    bm = bmesh.new()
    front = [bm.verts.new((x, y0, z)) for x, z in outline]
    back = [bm.verts.new((x, y1, z)) for x, z in outline]
    bm.faces.new(list(reversed(front)))
    bm.faces.new(back)
    count = len(outline)
    for i in range(count):
        j = (i + 1) % count
        bm.faces.new([front[i], front[j], back[j], back[i]])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return lib._from_bmesh(name, bm, material, False)


def _taper(points: Sequence[Vec], radii: Sequence[float], step: float = 0.03) -> list:
    """Metaball balls along a path whose radius changes smoothly from point to point:
    limbs that swell at the muscle and thin at the joint, unlike a capsule's even tube.
    Neighbouring balls melt together, so the surface is a little fatter than the radii."""
    elements = []
    for (a, ra), (b, rb) in zip(zip(points, radii), zip(points[1:], radii[1:])):
        va, vb = Vector(a), Vector(b)
        count = max(1, round((vb - va).length / step))
        for k in range(count):
            t = k / count
            elements.append((va.lerp(vb, t).to_tuple(), ra + (rb - ra) * t))
    elements.append((tuple(points[-1]), radii[-1]))
    return elements


def _claw(base: Vec, direction: Vec, length: float, radius: float, material):
    """A curved bone claw from base toward direction, bending down at the tip."""
    d = Vector(direction).normalized()
    tip = Vector(base) + d * length + Vector((0, 0, -length * 0.35))
    mid = Vector(base) + d * length * 0.55
    return tube([base, mid.to_tuple(), tip.to_tuple()], [radius, radius * 0.6, radius * 0.08], material, 8)


# --- The farmer ----------------------------------------------------------------------


def farmer() -> list[bpy.types.Object]:
    """A farmer in overalls over a flannel shirt, sleeves rolled, boots, a straw hat.

    1.8 m tall with the hat, standing on the origin. The overalls ("denim+overalls") are
    pale, for Godot to tint each player's own colour."""
    denim = mat("denim+overalls", (1.0, 1.0, 1.0), 0.9)
    flannel = mat("flannel", (1.0, 1.0, 1.0), 0.9)
    skin = mat("skin", (1.0, 1.0, 1.0), 0.6)
    leather = mat("leather", (1.0, 1.0, 1.0), 0.7)
    sole = mat("plain+sole", (0.07, 0.06, 0.05), 0.9)
    lace = mat("plain+lace", (0.55, 0.45, 0.3), 0.9)
    brass = mat("metal_paint+brass", (0.8, 0.62, 0.3), 0.35, 0.6)
    straw = mat("straw_weave", (1.0, 1.0, 1.0), 0.85)
    band = mat("leather+band", (0.45, 0.4, 0.38), 0.7)
    hair = mat("plain+hair", (0.2, 0.13, 0.08), 0.8)
    eye = mat("plain+eye", (0.04, 0.035, 0.03), 0.2)
    white = mat("plain+eyewhite", (0.85, 0.82, 0.76), 0.4)
    root = pivot("farmer")

    for i, side in enumerate((-1, 1)):
        x = side * 0.1
        hip = pivot(f"leg_{i}", (x, 0, 0.92))
        leg = blob(
            [
                ((x, 0, 0.95), (x * 1.08, 0.012, 0.52), 0.085),
                ((x * 1.08, 0.012, 0.52), (x * 1.1, -0.004, 0.17), 0.072),
            ],
            denim,
            name=f"trouser_{i}",
        )
        cuff = torus(0.07, 0.016, (x * 1.1, -0.002, 0.18), denim, segments=20)
        boot = blob(
            [
                ((x * 1.1, -0.01, 0.13), (x * 1.1, -0.005, 0.07), 0.062),
                ((x * 1.1, 0.0, 0.065), (x * 1.1, 0.12, 0.05), 0.052),
                ((x * 1.1, 0.13, 0.05), 0.05),
            ],
            leather,
            resolution=0.02,
            name=f"boot_{i}",
        )
        tread = box((0.115, 0.3, 0.03), (x * 1.1, 0.045, 0.015), sole, bevel=0.012)
        heel = box((0.1, 0.08, 0.035), (x * 1.1, -0.06, 0.0175), sole, bevel=0.008)
        laces = [
            box((0.07, 0.008, 0.006), (x * 1.1, 0.06 + k * 0.025, 0.105 - k * 0.012), lace)
            for k in range(3)
        ]
        _under(hip, leg, cuff, boot, tread, heel, *laces)
        parent(hip, root)

    body = pivot("body")
    hips = blob(
        [((-0.065, 0, 0.9), (-0.065, 0, 1.08), 0.135), ((0.065, 0, 0.9), (0.065, 0, 1.08), 0.135)],
        denim,
        name="hips",
    )
    chest = blob(
        [
            ((-0.07, 0, 1.06), (-0.075, 0, 1.36), 0.125),
            ((0.07, 0, 1.06), (0.075, 0, 1.36), 0.125),
            ((-0.17, 0, 1.4), (0.17, 0, 1.4), 0.075),
        ],
        flannel,
        name="chest",
    )
    collar = torus(0.06, 0.018, (0, 0.005, 1.455), flannel, segments=20)
    bib = box((0.25, 0.022, 0.25), (0, 0.112, 1.2), denim, bevel=0.008)
    pocket = box((0.12, 0.012, 0.09), (0, 0.126, 1.25), denim, bevel=0.004)
    side_pockets = [
        box((0.012, 0.11, 0.1), (s * 0.145, 0.04, 0.98), denim, bevel=0.004) for s in (-1, 1)
    ]
    straps = []
    buttons = []
    for s in (-1, 1):
        straps.append(
            tube(
                [
                    (s * 0.1, 0.114, 1.31),
                    (s * 0.12, 0.09, 1.42),
                    (s * 0.13, 0.0, 1.475),
                    (s * 0.11, -0.1, 1.42),
                    (s * 0.05, -0.13, 1.2),
                    (s * 0.02, -0.135, 1.08),
                ],
                0.014,
                denim,
                6,
            )
        )
        buttons.append(cyl(0.017, 0.017, 0.012, (s * 0.1, 0.126, 1.31), brass, (math.pi / 2, 0, 0)))
        buttons.append(cyl(0.012, 0.012, 0.01, (s * 0.14, 0.11, 1.03), brass, (math.pi / 2, 0, 0)))
    shirt_buttons = [
        cyl(0.007, 0.007, 0.006, (0, 0.13, 1.37 + k * 0.04), white, (math.pi / 2, 0, 0))
        for k in range(2)
    ]
    neck = cyl(0.052, 0.058, 0.12, (0, 0.0, 1.48), skin, segments=16)
    _under(body, hips, chest, collar, bib, pocket, *side_pockets, *straps, *buttons)
    _under(body, *shirt_buttons, neck)
    parent(body, root)

    head = pivot("head", (0, 0, 1.52))
    face = blob(
        [
            ((0, 0.0, 1.67), 0.11),
            ((0, 0.0, 1.61), (0, 0.025, 1.585), 0.072),
            ((0, 0.055, 1.565), 0.036),
            ((0, 0.098, 1.655), (0, 0.106, 1.632), 0.016),
            ((-0.05, 0.065, 1.625), 0.03),
            ((0.05, 0.065, 1.625), 0.03),
        ],
        skin,
        resolution=0.013,
        name="face",
    )
    ears = [
        sphere(0.04, (s * 0.105, -0.005, 1.65), skin, (0.35, 0.7, 1.0), segments=12)
        for s in (-1, 1)
    ]
    whites = [sphere(0.012, (s * 0.037, 0.095, 1.665), white, segments=12) for s in (-1, 1)]
    pupils = [sphere(0.0065, (s * 0.037, 0.105, 1.665), eye, segments=10) for s in (-1, 1)]
    brows = [
        box((0.04, 0.012, 0.01), (s * 0.038, 0.104, 1.69), hair, bevel=0.003, rot=(0, s * 0.15, 0))
        for s in (-1, 1)
    ]
    scalp = blob(
        [((0, -0.025, 1.69), 0.105), ((0, -0.05, 1.63), 0.08)], hair, resolution=0.015, name="hair"
    )
    stubble = tube([(-0.035, 0.088, 1.6), (0, 0.1, 1.605), (0.035, 0.088, 1.6)], 0.011, hair, 8, name="moustache")
    crown = lathe(
        [(0.0, 0.135), (0.06, 0.135), (0.085, 0.125), (0.1, 0.09), (0.103, 0.0), (0.0, 0.0)],
        (0, -0.01, 1.745),
        straw,
        closed=True,
        name="crown",
    )
    brim = lathe(
        [
            (0.095, 0.006),
            (0.17, 0.0),
            (0.215, -0.018),
            (0.232, -0.035),
            (0.228, -0.042),
            (0.205, -0.026),
            (0.16, -0.01),
            (0.095, -0.004),
        ],
        (0, -0.01, 1.755),
        straw,
        closed=True,
        name="brim",
    )
    hatband = cyl(0.104, 0.103, 0.028, (0, -0.01, 1.77), band, segments=32)
    _under(head, face, *ears, *whites, *pupils, *brows, scalp, stubble, crown, brim, hatband)
    parent(head, root)

    for i, side in enumerate((-1, 1)):
        x = side * 0.2
        shoulder = pivot(f"arm_{i}", (x, 0, 1.41))
        sleeve = blob(
            [((x, 0, 1.41), 0.068), ((x, 0, 1.41), (x * 1.13, 0.0, 1.17), 0.056)],
            flannel,
            name=f"sleeve_{i}",
        )
        roll = torus(0.052, 0.02, (x * 1.13, 0.0, 1.15), flannel, segments=20)
        forearm = blob(
            [
                ((x * 1.13, 0.0, 1.16), (x * 1.18, 0.025, 0.95), 0.042),
                ((x * 1.18, 0.025, 0.95), (x * 1.19, 0.03, 0.91), 0.034),
            ],
            skin,
            name=f"forearm_{i}",
        )
        hand = blob(
            [
                ((x * 1.19, 0.035, 0.9), (x * 1.19, 0.045, 0.84), 0.036),
                ((x * 1.19 - side * 0.035, 0.06, 0.88), (x * 1.19 - side * 0.04, 0.085, 0.84), 0.013),
            ]
            + [
                (
                    (x * 1.19 + side * 0.011 * (k - 1.5), 0.05, 0.83),
                    (x * 1.19 + side * 0.013 * (k - 1.5), 0.075, 0.775),
                    0.0115,
                )
                for k in range(4)
            ],
            skin,
            resolution=0.008,
            name=f"hand_{i}",
        )
        _under(shoulder, sleeve, roll, forearm, hand)
        parent(shoulder, root)
    return [root]


# --- The creature --------------------------------------------------------------------


def creature() -> list[bpy.types.Object]:
    """A gaunt thing 2.4 m tall, hunched: digitigrade legs, ribs and spine pushing
    through dark creased hide, arms to its shins ending in long clawed fingers, and a long
    skull with a toothed jaw and small pale eyes deep in their sockets."""
    hide = mat("hide", (1.0, 1.0, 1.0), 0.4)
    bone = mat("bone", (1.0, 1.0, 1.0), 0.55)
    mouth = mat("plain+mouth", (0.14, 0.03, 0.035), 0.3)
    socket = mat("plain+socket", (0.01, 0.008, 0.008), 0.9)
    glint = mat("glow+eye", (0.75, 0.78, 0.6), 0.2, emission=0.6)
    rng = random.Random(7)
    root = pivot("creature")

    for i, side in enumerate((-1, 1)):
        x = side * 0.18
        hip = pivot(f"leg_{i}", (x, 0, 1.3))
        knee = (x * 1.05, 0.16, 0.86)
        hock = (x * 1.08, -0.1, 0.36)
        ball = (x * 1.08, 0.1, 0.05)
        path = [
            (x, 0, 1.3),
            (x * 1.03, 0.08, 1.08),
            (x * 1.05, 0.15, 0.91),
            knee,
            (x * 1.06, 0.06, 0.64),
            (x * 1.07, -0.04, 0.47),
            hock,
            (x * 1.08, 0.0, 0.2),
            ball,
        ]
        leg = blob(
            _taper(path, [0.08, 0.072, 0.045, 0.048, 0.045, 0.034, 0.03, 0.025, 0.03]),
            hide,
            resolution=0.026,
            name=f"leg_mesh_{i}",
        )
        toes = []
        for t, spread in enumerate((-0.05, 0.0, 0.05)):
            tip = (ball[0] + spread * 1.2, ball[1] + 0.17 - abs(spread), 0.02)
            mid = (ball[0] + spread * 0.7, ball[1] + 0.09, 0.045)
            toes.append(tube([ball, mid, tip], [0.022, 0.017, 0.013], hide, 8, name=f"toe_{i}_{t}"))
            toes.append(_claw(tip, (spread, 1.0, -0.2), 0.07, 0.012, bone))
        _under(hip, leg, *toes)
        parent(hip, root)

    torso = pivot("torso", (0, 0, 1.3))
    spine = [(0, -0.04, 1.32), (0, -0.07, 1.55), (0, 0.0, 1.82), (0, 0.12, 2.05), (0, 0.27, 2.2), (0, 0.4, 2.26)]
    elements = [
        ((0, -0.02, 1.32), 0.11),
        ((-0.12, 0.03, 1.37), 0.05),
        ((0.12, 0.03, 1.37), 0.05),
        ((-0.055, 0.07, 1.66), (-0.065, 0.17, 2.0), 0.112),
        ((0.055, 0.07, 1.66), (0.065, 0.17, 2.0), 0.112),
        ((0, 0.1, 2.06), 0.125),
    ]
    elements += _taper([(0, -0.04, 1.36), (0, -0.04, 1.55), (0, 0.02, 1.68)], [0.07, 0.06, 0.08])
    elements += _taper([(0, 0.28, 2.2), (0, 0.42, 2.26), (0, 0.5, 2.28)], [0.055, 0.042, 0.038])
    for s in (-1, 1):
        elements.append(((0, 0.29, 2.24), (s * 0.19, 0.27, 2.12), 0.045))  # Trapezius.
        elements.append(((s * 0.04, 0.36, 2.15), (s * 0.23, 0.3, 2.1), 0.022))  # Collarbone.
        elements.append(((s * 0.26, 0.28, 2.09), 0.055))
        elements.append(((s * 0.025, 0.33, 2.2), (s * 0.015, 0.47, 2.26), 0.024))  # Neck cord.
    body = blob(
        elements,
        hide,
        resolution=0.028,
        name="body",
    )
    ribs = []
    for k in range(5):  # Ribs, sloping down to the front, half sunk in the chest.
        z = 1.72 + k * 0.07
        lean = (z - 1.7) * 0.3
        for s in (-1, 1):
            arc = [
                (s * 0.05, -0.02 + lean, z + 0.05),
                (s * 0.155, 0.04 + lean, z + 0.03),
                (s * 0.17, 0.13 + lean, z - 0.01),
                (s * 0.12, 0.22 + lean, z - 0.07),
                (s * 0.04, 0.25 + lean, z - 0.1),
            ]
            ribs.append(tube(arc, [0.008, 0.012, 0.012, 0.01, 0.006], hide, 8, name="rib"))
    knobs = []  # The spine, a ridge of small knuckles down the hunched back.
    for a, b in zip(spine[:-2], spine[1:-1]):
        for t in (0.0, 0.33, 0.66):
            p = Vector(a).lerp(Vector(b), t)
            knobs.append(sphere(0.018, (p.x, p.y - 0.085, p.z), hide, (1.0, 0.8, 1.3), segments=10))
    blades = [
        sphere(0.06, (s * 0.11, 0.03, 2.03), hide, (1.0, 0.35, 1.2), (0.55, 0, s * 0.3), 14)
        for s in (-1, 1)
    ]
    _under(torso, body, *ribs, *knobs, *blades)
    parent(torso, root)

    head = pivot("head", (0, 0.5, 2.28))
    skull = blob(
        [
            ((0, 0.52, 2.38), (0, 0.66, 2.37), 0.115),
            ((0, 0.64, 2.32), (0, 0.82, 2.27), 0.055),
            ((-0.065, 0.73, 2.37), (0.065, 0.73, 2.37), 0.03),
            ((-0.075, 0.72, 2.29), 0.035),
            ((0.075, 0.72, 2.29), 0.035),
            ((0, 0.58, 2.47), (0, 0.66, 2.44), 0.06),
        ],
        hide,
        resolution=0.015,
        name="skull",
    )
    jaw = blob(
        [((-0.06, 0.6, 2.25), (0, 0.8, 2.18), 0.03), ((0.06, 0.6, 2.25), (0, 0.8, 2.18), 0.03)],
        hide,
        resolution=0.013,
        name="jaw",
    )
    gullet = box((0.08, 0.2, 0.05), (0, 0.72, 2.23), mouth, bevel=0.02, rot=(-0.25, 0, 0))
    sockets = [sphere(0.03, (s * 0.045, 0.75, 2.335), socket, (1.0, 0.8, 0.8), segments=12) for s in (-1, 1)]
    eyes = [sphere(0.011, (s * 0.045, 0.772, 2.335), glint, segments=8) for s in (-1, 1)]
    teeth = []
    for k in range(7):
        t = k / 6
        for s in (-1, 1):
            y = 0.66 + t * 0.15
            x = s * (0.05 - t * 0.035)
            long = 0.035 + rng.random() * 0.025
            teeth.append(cyl(0.008, 0.0, long, (x, y, 2.255 - long / 2), bone, (math.pi, 0, 0), 6))
            teeth.append(cyl(0.007, 0.0, long * 0.8, (x * 0.9, y - 0.01, 2.2 + long * 0.4), bone, segments=6))
    _under(head, skull, jaw, gullet, *sockets, *eyes, *teeth)
    parent(head, torso)

    for i, side in enumerate((-1, 1)):
        shoulder_at = (side * 0.27, 0.28, 2.12)
        palm = (side * 0.31, 0.33, 0.77)
        arm = pivot(f"arm_{i}", shoulder_at)
        path = [
            (side * 0.26, 0.28, 2.09),
            (side * 0.285, 0.27, 1.95),
            (side * 0.3, 0.25, 1.78),
            (side * 0.31, 0.24, 1.56),
            (side * 0.31, 0.24, 1.5),
            (side * 0.31, 0.25, 1.36),
            (side * 0.31, 0.28, 1.05),
            (side * 0.31, 0.3, 0.88),
            palm,
        ]
        limb = blob(
            _taper(path, [0.052, 0.046, 0.038, 0.028, 0.034, 0.033, 0.022, 0.02, 0.028]),
            hide,
            resolution=0.021,
            name=f"arm_mesh_{i}",
        )
        fingers = []
        for f in range(4):
            spread = (f - 1.5) * 0.028
            base = Vector((palm[0] + spread * side, palm[1] + 0.01, palm[2] - 0.02))
            curl = 0.04 + f * 0.01
            pts = [
                base,
                base + Vector((spread * 0.4 * side, 0.02, -0.1)),
                base + Vector((spread * 0.6 * side, 0.02 + curl, -0.2)),
                base + Vector((spread * 0.7 * side, 0.03 + curl * 2.2, -0.28)),
            ]
            fingers.append(tube([p.to_tuple() for p in pts], [0.015, 0.013, 0.011, 0.009], hide, 8))
            fingers.append(_claw(pts[-1].to_tuple(), (0, 0.6, -1.0), 0.07, 0.01, bone))
        thumb_base = Vector((palm[0] - side * 0.04, palm[1] + 0.03, palm[2] + 0.02))
        thumb = [thumb_base, thumb_base + Vector((-side * 0.03, 0.05, -0.08)), thumb_base + Vector((-side * 0.02, 0.09, -0.15))]
        fingers.append(tube([p.to_tuple() for p in thumb], [0.016, 0.012, 0.01], hide, 8))
        fingers.append(_claw(thumb[-1].to_tuple(), (0, 1.0, -0.6), 0.06, 0.01, bone))
        _under(arm, limb, *fingers)
        parent(arm, torso)
    return [root]




# --- The other monster looks ---------------------------------------------------------
#
# Each run the creature wears one of four looks (creature.gd LOOKS). All share its joints:
# legs swing from the hip, arms hang down and reach forward from the shoulder, the head turns.


def _spike(base: Vec, direction: Vec, length: float, radius: float, material, sides: int = 5):
    """A cone from base toward direction: straw tufts, bristles."""
    d = Vector(direction).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(d).to_euler()
    centre = Vector(base) + d * (length / 2)
    return cyl(radius, 0.0, length, centre.to_tuple(), material, tuple(rot), sides, name="spike")


def _turn(parts: Sequence[bpy.types.Object], centre: Vec, angle: float, axis: str) -> None:
    """Turns parts angle radians round axis through centre, before they are parented: a
    lean that creature.gd's absolute head rotation would otherwise undo."""
    lib._refresh()
    c = Vector(centre)
    m = Matrix.Translation(c) @ Matrix.Rotation(angle, 4, axis) @ Matrix.Translation(-c)
    for part in parts:
        part.matrix_world = m @ part.matrix_world
    lib._refresh()


def _rag(name: str, lefts: Sequence[Vec], rights: Sequence[Vec], material) -> list:
    """Cloth seen from both sides: a strip and its reverse, since only leaves draw two-sided."""
    return [_quad_strip(name, lefts, rights, material), _quad_strip(name, rights, lefts, material)]


def _surface(obj: bpy.types.Object, origin: Vec, direction: Vec) -> tuple[Vector, Vector]:
    """Where a ray from origin first meets obj's mesh, and the normal there: to set eyes and
    stitches on a metaball surface whose exact shape the radii don't give."""
    lib._refresh()
    hit, location, normal, _ = obj.ray_cast(Vector(origin), Vector(direction).normalized())
    assert hit, f"no surface on {obj.name} from {origin}"
    return location, normal


def _bundle(
    path: Sequence[Vec],
    count: int,
    spread: float | Sequence[float],
    radius: float,
    material,
    twist: float = 1.5,
) -> list:
    """Stalks twisted round a path, like a rope of corn stems: the husk's limbs."""
    pts = [Vector(p) for p in path]
    spreads = [spread] * len(pts) if isinstance(spread, (int, float)) else list(spread)
    strands = []
    for k in range(count):
        a0 = 2 * math.pi * k / count
        strand = []
        for i, p in enumerate(pts):
            ahead = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
            ahead.normalize()
            side = lib._cross(ahead, Vector((0, 0, 1)) if abs(ahead.z) < 0.9 else Vector((1, 0, 0)))
            side.normalize()
            normal = lib._cross(side, ahead)
            a = a0 + twist * i / (len(pts) - 1)
            strand.append((p + (side * math.cos(a) + normal * math.sin(a)) * spreads[i]).to_tuple())
        radii = [radius * (1.0 - 0.35 * i / (len(pts) - 1)) for i in range(len(pts))]
        strands.append(_uv_tube("stalk", strand, radii, material, 5))
    return strands


def scarecrow() -> list[bpy.types.Object]:
    """A scarecrow come down off its pole, 2.7 m to the hat: a burlap sack head lolling to
    one side with mismatched ember eyes and a stitched grin, a long ragged coat open over
    flannel, twig fingers poking from straw-stuffed cuffs, and wooden stakes for shins."""
    denim = mat("denim+scarecrow", (0.55, 0.6, 0.68), 0.95)
    flannel = mat("flannel+scarecrow", (0.6, 0.25, 0.22), 0.95)
    coat = mat("leather+coat", (0.42, 0.36, 0.3), 0.85)
    sack = mat("straw_weave+sack", (0.7, 0.58, 0.42), 0.95)
    hay = mat("hay", (1.0, 1.0, 1.0), 0.9)
    stake = mat("wood+stake", (0.75, 0.68, 0.58), 0.9)
    twig = mat("bark+twig", (0.6, 0.55, 0.5), 0.9)
    stitch = mat("plain+stitch", (0.08, 0.06, 0.05), 0.9)
    socket = mat("plain+socket", (0.01, 0.008, 0.008), 0.9)
    ember = mat("glow+ember", (1.0, 0.55, 0.15), 0.3, emission=0.6)
    hat = mat("leather+hat", (0.3, 0.25, 0.2), 0.8)
    rng = random.Random(11)
    root = pivot("scarecrow")

    for i, side in enumerate((-1, 1)):
        x = side * 0.12
        hip = pivot(f"leg_{i}", (x, 0, 1.35))
        trouser = blob(
            _taper([(x, 0, 1.4), (x * 1.2, 0.03, 0.85), (x * 1.3, 0.0, 0.32)], [0.1, 0.08, 0.095]),
            denim,
            resolution=0.03,
            name=f"trouser_{i}",
        )
        ankle = Vector((x * 1.3, 0.0, 0.3))
        shin = cyl(0.04, 0.025, 0.34, (ankle.x, 0.0, 0.17), stake, (0.04 * side, 0, 0), 7)
        tufts = []
        for k in range(9):
            a = 2 * math.pi * k / 9 + rng.random() * 0.4
            out = (math.cos(a) * 0.6, math.sin(a) * 0.6, -1.0)
            base = ankle + Vector((math.cos(a) * 0.06, math.sin(a) * 0.06, 0.03))
            tufts.append(_spike(base.to_tuple(), out, 0.1 + rng.random() * 0.08, 0.018, hay))
        _under(hip, trouser, shin, *tufts)
        parent(hip, root)

    torso = pivot("torso", (0, 0, 1.35))
    body = blob(
        [((0, 0, 1.42), (0, 0.01, 2.0), 0.16), ((-0.2, 0, 2.04), (0.2, 0, 2.04), 0.08)],
        flannel,
        name="body",
    )
    belt = torus(0.165, 0.025, (0, 0, 1.47), hay, segments=20)
    crossbar = cyl(0.03, 0.03, 1.0, (0, -0.06, 2.1), stake, (0, math.pi / 2, 0), 8)
    neck = cyl(0.032, 0.032, 0.3, (0, 0.02, 2.2), stake, segments=8)
    rags = []
    strips = 14
    gap = 0.54
    width = (2 * math.pi - 2 * gap) / strips * 1.15
    for j in range(strips):
        centre = gap + (j + 0.5) * (2 * math.pi - 2 * gap) / strips
        hem = 1.05 + rng.random() * 0.17
        out = 0.008 * (j % 2)  # Alternate strips sit proud, so overlaps don't flicker.
        lefts, rights = [], []
        for k in range(6):
            t = k / 5
            z = 2.1 + (hem - 2.1) * t
            rx = 0.27 + 0.09 * t + out
            ry = 0.19 + 0.09 * t + out
            for row, a in ((lefts, centre - width / 2), (rights, centre + width / 2)):
                sag = -rng.random() * 0.06 if k == 5 else 0.0
                row.append((rx * math.sin(a), ry * math.cos(a), z + sag))
        rags += _rag("coat", lefts, rights, coat)
    _under(torso, body, belt, crossbar, neck, *rags)
    parent(torso, root)

    head = pivot("head", (0, 0.03, 2.3))
    lump = blob(
        [((0, 0.03, 2.48), 0.16), ((0.01, 0.05, 2.56), 0.15), ((0.09, 0.0, 2.6), 0.08)],
        sack,
        resolution=0.02,
        name="sack",
    )
    frill = cyl(0.1, 0.055, 0.07, (0, 0.03, 2.33), sack, segments=12)
    string = torus(0.068, 0.016, (0, 0.03, 2.35), hay, segments=16)
    rope = tube([(0.06, 0.08, 2.35), (0.075, 0.1, 2.28), (0.08, 0.11, 2.2)], 0.01, hay, 6)
    face = []
    for x, z, r in ((-0.065, 2.54, 0.036), (0.06, 2.51, 0.026)):  # Mismatched eyes.
        at, normal = _surface(lump, (x, 1.0, z), (0, -1, 0))
        face.append(sphere(r, (at - normal * 0.006).to_tuple(), socket, (1.0, 0.55, 1.0), segments=12))
        face.append(sphere(r * 0.38, (at + normal * 0.012).to_tuple(), ember, segments=8))
    grin = []
    for k in range(13):
        x = -0.11 + 0.22 * k / 12
        at, normal = _surface(lump, (x, 1.0, 2.4 + 5.0 * x * x), (0, -1, 0))
        grin.append((at + normal * 0.004).to_tuple())
    face.append(tube(grin, 0.006, stitch, 6, name="grin"))
    for k in range(1, 12, 2):  # X stitches across the grin.
        for lean in (-0.7, 0.7):
            face.append(box((0.045, 0.006, 0.006), grin[k], stitch, rot=(0, lean, 0)))
    crown = lathe(
        [(0.0, 0.17), (0.09, 0.16), (0.125, 0.12), (0.13, 0.0), (0.0, 0.0)],
        (0.01, 0.02, 2.62),
        hat,
        rot=(0.12, -0.1, 0.3),
        closed=True,
        segments=20,
        name="crown",
    )
    brim = lathe(
        [(0.12, 0.01), (0.22, -0.01), (0.3, -0.06), (0.31, -0.075), (0.21, -0.025), (0.12, 0.0)],
        (0.01, 0.02, 2.63),
        hat,
        rot=(0.2, -0.08, 0.0),
        closed=True,
        segments=24,
        name="brim",
    )
    straw = []
    for k in range(16):
        a = 2 * math.pi * k / 16 + rng.random() * 0.3
        if abs(math.sin(a / 2)) < 0.25:  # Leave the face clear.
            continue
        base = (math.sin(a) * 0.13, 0.03 + math.cos(a) * 0.12, 2.6)
        down = (math.sin(a), math.cos(a), -0.9 - rng.random() * 0.6)
        straw.append(_spike(base, down, 0.12 + rng.random() * 0.1, 0.015, hay))
    parts = [lump, frill, string, rope, *face, crown, brim, *straw]
    _turn(parts, (0, 0.03, 2.33), 0.28, "Y")  # The head lolls to its left shoulder.
    _under(head, *parts)
    parent(head, torso)

    for i, side in enumerate((-1, 1)):
        x = side * 0.28
        arm = pivot(f"arm_{i}", (x, 0.02, 2.08))
        cuff = Vector((x * 1.15, 0.06, 1.38))
        sleeve = blob(
            _taper([(x, 0.02, 2.08), (x * 1.12, 0.04, 1.7), cuff.to_tuple()], [0.075, 0.068, 0.085]),
            coat,
            name=f"sleeve_{i}",
        )
        tufts = []
        for k in range(7):
            a = 2 * math.pi * k / 7
            out = (math.cos(a) * 0.5, math.sin(a) * 0.5, -1.0)
            base = cuff + Vector((math.cos(a) * 0.05, math.sin(a) * 0.05, -0.02))
            tufts.append(_spike(base.to_tuple(), out, 0.1 + rng.random() * 0.06, 0.016, hay))
        fingers = []
        for f in range(5):
            spread = (f - 2) * 0.025
            start = cuff + Vector((spread * side, 0.01, -0.03))
            pts = [start]
            for _ in range(4):  # Gnarled: each joint kinks a little.
                kink = Vector((rng.uniform(-0.03, 0.03) + spread * 0.4 * side, rng.uniform(0.0, 0.04), -0.1))
                pts.append(pts[-1] + kink)
            radii = [0.013, 0.011, 0.008, 0.006, 0.003]
            fingers.append(tube([p.to_tuple() for p in pts], radii, twig, 6, name="twig"))
        _under(arm, sleeve, *tufts, *fingers)
        parent(arm, torso)
    return [root]


def boar() -> list[bpy.types.Object]:
    """A boar brute 2.3 m at the hump: a hulking hog on two hoofed legs, bristled along its
    spine, an iron collar with a broken chain, a ringed snout, curved tusks, little red eyes,
    and arms like hams ending in cloven hoof-claws."""
    hide = mat("hide+boar", (0.78, 0.6, 0.58), 0.5)
    bone = mat("bone", (1.0, 1.0, 1.0), 0.55)
    bristle = mat("plain+bristle", (0.18, 0.12, 0.09), 0.9)
    iron = mat("iron", (1.0, 1.0, 1.0), 0.6, 0.7)
    hoof = mat("plain+hoof", (0.1, 0.08, 0.07), 0.5)
    snout = mat("plain+snout", (0.7, 0.45, 0.45), 0.5)
    mouth = mat("plain+mouth", (0.14, 0.03, 0.035), 0.3)
    socket = mat("plain+socket", (0.01, 0.008, 0.008), 0.9)
    eye = mat("glow+boar", (0.95, 0.15, 0.08), 0.3, emission=0.6)
    rng = random.Random(23)
    root = pivot("boar")

    for i, side in enumerate((-1, 1)):
        x = side * 0.22
        hip = pivot(f"leg_{i}", (x, 0, 1.15))
        path = [(x, 0, 1.15), (x * 1.05, 0.12, 0.8), (x * 1.05, -0.1, 0.4), (x * 1.05, 0.0, 0.12)]
        leg = blob(_taper(path, [0.16, 0.12, 0.065, 0.06]), hide, resolution=0.045, name=f"leg_mesh_{i}")
        hooves = [
            box((0.065, 0.15, 0.1), (x * 1.05 + s * 0.037, 0.05, 0.05), hoof, 0.025, (0, 0, -s * 0.12))
            for s in (-1, 1)
        ]
        _under(hip, leg, *hooves)
        parent(hip, root)

    torso = pivot("torso", (0, 0, 1.15))
    body = blob(
        [
            ((0, -0.02, 1.22), 0.25),
            ((0, 0.12, 1.38), 0.29),
            ((-0.17, 0.1, 1.75), (0.17, 0.1, 1.75), 0.27),
            ((-0.4, 0.08, 1.9), (0.4, 0.08, 1.9), 0.16),
            ((0, -0.08, 1.96), 0.24),
            ((0, 0.25, 1.92), 0.19),
        ],
        hide,
        resolution=0.045,
        name="body",
    )
    bristles = []
    for k in range(26):  # A ridge of bristles down the spine, laid back.
        y = -0.24 + 0.52 * k / 25
        x = rng.uniform(-0.04, 0.04)
        at, normal = _surface(body, (x, y, 3.0), (0, 0, -1))
        direction = normal + Vector((rng.uniform(-0.2, 0.2), -0.6, 0.2))
        bristles.append(_spike((at - normal * 0.01).to_tuple(), direction, 0.08 + rng.random() * 0.08, 0.014, bristle))
    collar = torus(0.215, 0.03, (0, 0.3, 1.9), iron, (math.pi / 2, 0, 0), 24)
    links = [
        torus(0.033, 0.009, (0, 0.47, 1.66 - k * 0.055), iron, (math.pi / 2, 0, (k % 2) * math.pi / 2), 12)
        for k in range(5)
    ]
    _under(torso, body, *bristles, collar, *links)
    parent(torso, root)

    head = pivot("head", (0, 0.35, 1.95))
    skull = blob(
        [
            ((0, 0.42, 2.0), 0.17),
            ((0, 0.45, 1.95), (0, 0.78, 1.88), 0.11),
            ((-0.1, 0.52, 1.9), 0.09),
            ((0.1, 0.52, 1.9), 0.09),
            ((-0.09, 0.57, 2.03), (0.09, 0.57, 2.03), 0.05),
        ],
        hide,
        resolution=0.028,
        name="skull",
    )
    jaw = blob([((0, 0.45, 1.8), (0, 0.72, 1.78), 0.07)], hide, resolution=0.02, name="jaw")
    gullet = box((0.11, 0.2, 0.04), (0, 0.66, 1.825), mouth, bevel=0.015)
    disc = cyl(0.085, 0.08, 0.05, (0, 0.88, 1.88), snout, (-math.pi / 2, 0, 0), 20)
    nostrils = [sphere(0.02, (s * 0.032, 0.905, 1.885), socket, (1.0, 0.5, 1.3), segments=10) for s in (-1, 1)]
    ring = torus(0.032, 0.006, (0, 0.91, 1.845), iron, (0, math.pi / 2, 0), 16)
    tusks = [
        tube(
            [(s * 0.07, 0.74, 1.84), (s * 0.13, 0.8, 1.86), (s * 0.165, 0.82, 1.94), (s * 0.15, 0.79, 2.01)],
            [0.026, 0.02, 0.012, 0.004],
            bone,
            8,
            name="tusk",
        )
        for s in (-1, 1)
    ]
    teeth = [
        cyl(0.012, 0.0, 0.035, (s * (0.03 + k * 0.02), 0.6 + k * 0.04, 1.84), bone, segments=6)
        for s in (-1, 1)
        for k in range(3)
    ]
    ears = [
        sphere(0.08, (-0.13, 0.36, 2.13), hide, (0.55, 0.22, 1.0), (0.3, 0, 0.5), 12),
        sphere(0.06, (0.13, 0.37, 2.1), hide, (0.55, 0.22, 1.0), (0.9, 0, -0.6), 12),  # Torn.
    ]
    eyes = []
    for s in (-1, 1):
        at, normal = _surface(skull, (s * 0.075, 1.5, 1.98), (0, -1, 0))
        eyes.append(sphere(0.026, (at - normal * 0.008).to_tuple(), socket, (1.0, 0.6, 0.8), segments=10))
        eyes.append(sphere(0.011, (at + normal * 0.006).to_tuple(), eye, segments=8))
    _under(head, skull, jaw, gullet, disc, *nostrils, ring, *tusks, *teeth, *ears, *eyes)
    parent(head, torso)

    for i, side in enumerate((-1, 1)):
        x = side * 0.42
        arm = pivot(f"arm_{i}", (x, 0.12, 1.88))
        path = [(x, 0.12, 1.88), (x * 1.1, 0.15, 1.55), (x * 1.12, 0.12, 1.3), (x * 1.1, 0.2, 1.05), (x * 1.08, 0.22, 0.95)]
        limb = blob(_taper(path, [0.15, 0.125, 0.095, 0.105, 0.08]), hide, resolution=0.045, name=f"arm_mesh_{i}")
        fist = blob([((x * 1.08, 0.24, 0.9), 0.085)], hide, resolution=0.025, name=f"fist_{i}")
        claws = [
            _claw((x * 1.08 + s * 0.04, 0.28, 0.88), (s * 0.15, 0.6, -1.0), 0.22, 0.035, hoof)
            for s in (-1, 1)
        ]
        parts = [limb, fist, *claws]
        if i == 0:  # A shackle on one wrist, its chain snapped.
            parts.append(torus(0.1, 0.022, (x * 1.09, 0.2, 1.02), iron, segments=20))
            parts += [
                torus(0.03, 0.008, (x * 1.09 - side * 0.1, 0.2, 0.98 - k * 0.05), iron, (math.pi / 2, 0, (k % 2) * math.pi / 2), 12)
                for k in range(3)
            ]
        _under(arm, *parts)
        parent(arm, torso)
    return [root]


def husk() -> list[bpy.types.Object]:
    """A husk thing 3 m tall, made of the corn: legs and arms of twisted stalks, brace roots
    for feet, a cage of husk leaves round a hollow chest with something glowing in it, and
    for a head a long ear of corn split down the front into a mouth lined with kernel teeth,
    no eyes, silk hanging from its tip."""
    husk_leaf = mat("leaf+husk", (0.85, 0.75, 0.5), 0.85)
    rot = mat("leaf+rot", (0.4, 0.33, 0.2), 0.9)
    dark = mat("plain+hollow", (0.04, 0.03, 0.02), 0.9)
    kernel = mat("bone+kernel", (0.95, 0.8, 0.35), 0.5)
    core = mat("glow+husk", (0.75, 0.85, 0.3), 0.3, emission=0.6)
    silk = mat("plain+silk", (0.75, 0.6, 0.35), 0.8)
    rng = random.Random(31)
    root = pivot("husk")

    for i, side in enumerate((-1, 1)):
        x = side * 0.14
        hip = pivot(f"leg_{i}", (x, 0, 1.6))
        ankle = Vector((x * 1.25, -0.02, 0.22))
        path = [(x, 0, 1.62), (x * 1.1, 0.1, 1.0), (x * 1.2, 0.04, 0.55), ankle.to_tuple()]
        stalks = _bundle(path, 4, [0.03, 0.035, 0.03, 0.03], 0.022, husk_leaf, 2.0)
        roots = []
        for k in range(5):
            a = math.pi / 2 + (k - 2) * 0.75 + rng.uniform(-0.15, 0.15)  # Mostly forward.
            out = Vector((math.cos(a), math.sin(a), 0))
            pts = [ankle + Vector((0, 0, 0.04)), ankle + out * 0.1 + Vector((0, 0, -0.06)), ankle + out * 0.2 + Vector((0, 0, -0.21))]
            roots.append(_uv_tube("root", [p.to_tuple() for p in pts], [0.018, 0.014, 0.008], rot, 5))
        _under(hip, *stalks, *roots)
        parent(hip, root)

    torso = pivot("torso", (0, 0, 1.6))
    spine = _bundle([(0, 0, 1.6), (0, -0.04, 1.95), (0, 0.0, 2.3), (0, 0.12, 2.65)], 5, 0.04, 0.024, husk_leaf, 2.5)
    yoke = []
    for s in (-1, 1):
        yoke += _bundle([(0, 0.08, 2.5), (s * 0.15, 0.08, 2.53), (s * 0.3, 0.1, 2.5)], 3, 0.025, 0.02, husk_leaf, 1.5)
        yoke += _bundle([(0, 0, 1.62), (s * 0.15, 0, 1.64)], 3, 0.025, 0.02, husk_leaf, 1.0)
    cage = []
    for k in range(6):  # Bands of husk round the chest, open at the front.
        z = 1.85 + k * 0.1
        bulge = math.sin(math.pi * (k + 0.5) / 6)
        rx, ry = 0.13 + 0.1 * bulge, 0.1 + 0.08 * bulge
        y0 = 0.04
        bottom, top = [], []
        for j in range(15):
            a = 0.5 + (2 * math.pi - 1.0) * j / 14
            droop = rng.uniform(-0.015, 0.015)
            bottom.append((rx * math.sin(a), y0 + ry * math.cos(a), z + droop))
            top.append((rx * 1.03 * math.sin(a), y0 + ry * 1.03 * math.cos(a), z + 0.075 + droop))
        cage.append(_quad_strip("band", bottom, top, husk_leaf if k % 2 else rot, 3.0))
    hollow = sphere(0.14, (0, 0.0, 2.1), dark, (1.0, 0.75, 1.5), segments=14)
    heart = sphere(0.045, (0, 0.06, 2.12), core, segments=12)
    trails = []
    for s in (-1, 1):  # Long leaves trailing off the shoulders.
        for k in range(2):
            start = Vector((s * (0.18 + k * 0.08), -0.05 - k * 0.04, 2.52))
            lefts, rights = [], []
            for n in range(6):
                t = n / 5
                at = start + Vector((s * 0.06 * t, -0.08 * t, -0.9 * t - 0.15 * k * t))
                w = 0.06 * math.sin(math.pi * (0.15 + 0.85 * t)) + 0.005
                lefts.append((at.x - w, at.y, at.z))
                rights.append((at.x + w, at.y, at.z))
            trails.append(_quad_strip("trail", lefts, rights, husk_leaf, 1.0))
    _under(torso, *spine, *yoke, *cage, hollow, heart, *trails)
    parent(torso, root)

    head = pivot("head", (0, 0.15, 2.7))
    base, tip = Vector((0, 0.12, 2.66)), Vector((0, 0.44, 3.06))
    axis = (tip - base).normalized()
    length = (tip - base).length
    across = Vector((1, 0, 0))
    front = lib._cross(axis, across)  # Forward and down, square to the ear.

    def on_ear(t: float, angle: float, scale: float = 1.0) -> Vector:
        r = 0.16 * math.sin(math.pi * (0.12 + 0.8 * t)) * scale
        return base + axis * length * t + (across * math.sin(angle) + front * math.cos(angle)) * r

    def gape(t: float) -> float:
        return 0.25 + 0.35 * math.sin(math.pi * t)

    rows = 9
    shell = []
    for s in (-1, 1):  # Husk leaves round each side of the ear, parted at the front.
        columns = 4
        for c in range(columns):
            puff = 1.0 + 0.05 * (c % 2)
            lefts, rights = [], []
            for n in range(rows + 1):
                t = n / rows
                g = gape(t)
                a0 = g + (math.pi - g) * c / columns
                a1 = g + (math.pi - g) * (c + 1.1) / columns
                lefts.append(on_ear(t, s * a0, puff).to_tuple())
                rights.append(on_ear(t, s * a1, puff).to_tuple())
            flap = Vector(lefts[-1]).lerp(Vector(rights[-1]), 0.5) + axis * rng.uniform(0.06, 0.14)
            lefts.append(flap.to_tuple())
            rights.append((flap + across * 0.004).to_tuple())
            shell.append(_quad_strip("shell", lefts, rights, husk_leaf, 2.0))
    cob = blob(
        [((base + axis * length * 0.1).to_tuple(), (base + axis * length * 0.85).to_tuple(), 0.1)],
        dark,
        resolution=0.025,
        name="cob",
    )
    teeth = []
    for n in range(1, rows):
        t = n / rows
        for s in (-1, 1):
            lip = on_ear(t, s * gape(t), 0.97)
            inward = (base + axis * length * t - lip).normalized()
            centre = lip + inward * 0.02
            rot_euler = Vector((0, 0, 1)).rotation_difference(inward).to_euler()
            teeth.append(box((0.022, 0.026, 0.045), centre.to_tuple(), kernel, 0.006, tuple(rot_euler)))
    glow = sphere(0.03, (base + axis * length * 0.45 + front * 0.03).to_tuple(), core, segments=10)
    strands = []
    for k in range(9):  # Silk hanging from the tip and down the back.
        start = tip + Vector((rng.uniform(-0.03, 0.03), rng.uniform(-0.04, 0.0), -0.02))
        drop = 0.25 + rng.random() * 0.25
        sway = Vector((rng.uniform(-0.06, 0.06), rng.uniform(-0.04, 0.06), 0))
        pts = [start, start + sway * 0.5 + Vector((0, 0.02, -drop * 0.4)), start + sway + Vector((0, 0, -drop))]
        strands.append(tube([p.to_tuple() for p in pts], 0.004, silk, 3, name="silk"))
    _under(head, *shell, cob, *teeth, glow, *strands)
    parent(head, torso)

    for i, side in enumerate((-1, 1)):
        x = side * 0.3
        arm = pivot(f"arm_{i}", (x, 0.1, 2.5))
        wrist = Vector((x * 1.25, 0.22, 1.2))
        path = [(x, 0.1, 2.5), (x * 1.18, 0.14, 1.85), wrist.to_tuple()]
        stalks = _bundle(path, 3, [0.025, 0.03, 0.02], 0.02, husk_leaf, 1.8)
        blades = []
        for f in range(4):  # Leaf-blade fingers, long and pointed.
            spread = (f - 1.5) * 0.035
            lefts, rights = [], []
            for n in range(7):
                t = n / 6
                at = wrist + Vector((spread * side * (1 + t), 0.02 + 0.12 * t * t, -0.5 * t - 0.03 * f * t))
                w = 0.022 * (1 - t) + 0.001
                lefts.append((at.x - w, at.y, at.z))
                rights.append((at.x + w, at.y, at.z))
            blades.append(_quad_strip("blade", lefts, rights, husk_leaf if f % 2 else rot, 2.0))
        elbow = Vector((x * 1.18, 0.14, 1.85))
        lefts, rights = [], []
        for n in range(5):
            t = n / 4
            at = elbow + Vector((side * 0.05 * t, -0.1 * t, -0.55 * t))
            w = 0.045 * math.sin(math.pi * (0.2 + 0.8 * t)) + 0.004
            lefts.append((at.x, at.y - w, at.z))
            rights.append((at.x, at.y + w, at.z))
        blades.append(_quad_strip("trail", lefts, rights, husk_leaf, 1.0))
        _under(arm, *stalks, *blades)
        parent(arm, torso)
    return [root]


# --- Buildings -----------------------------------------------------------------------

BARN_X = 6.0  # Half width: Farm.BARN is x -6 to 6, z -22 to -12 (Blender y 12 to 22).
BARN_Y0, BARN_Y1 = 12.0, 22.0
EAVE = 5.0  # Farm.BARN_HEIGHT.
RIDGE = 7.4
WALL = 0.25  # Farm.WALL.
DOOR = 3.2  # Farm.BARN_DOOR.
DOOR_TOP = 3.6  # The doorway is open to the eaves in Farm's colliders; this header is visual.
OVERHANG = 0.4
SIDING = 0.04  # The red boards' share of the wall's thickness.


def _gable_top(x: float) -> float:
    return EAVE + (RIDGE - EAVE) * (1 - abs(x) / BARN_X)


def _slab(x0, x1, y0, y1, z0, z1, material) -> bpy.types.Object:
    return box((x1 - x0, y1 - y0, z1 - z0), ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), material)


def _battens(x0: float, x1: float, y: float, top, material, gap: float = 0.0, step: float = 0.4):
    """Battens over the board joints of a wall facing along Y, from the ground (or the
    door header, within gap of x = 0) up to top(x)."""
    parts = []
    x = math.ceil((x0 + 1e-6) / step) * step
    while x < x1 - 1e-6:
        bottom = DOOR_TOP if abs(x) < gap else 0.0
        height = top(x) - bottom
        parts.append(box((0.06, 0.025, height), (x, y, bottom + height / 2), material))
        x += step
    return parts


def _braced_leaf(width: float, height: float, at: Vec, face, trim) -> list:
    """A plank door or hatch facing -Y: boards behind a frame of trim boards and an X
    brace, centred on at."""
    cx, cy, cz = at
    parts = [box((width, 0.05, height), (cx, cy, cz), face)]
    board = 0.14
    front = cy - 0.035
    parts.append(box((width, 0.03, board), (cx, front, cz + height / 2 - board / 2), trim))
    parts.append(box((width, 0.03, board), (cx, front, cz - height / 2 + board / 2), trim))
    parts.append(box((board, 0.03, height), (cx + width / 2 - board / 2, front, cz), trim))
    parts.append(box((board, 0.03, height), (cx - width / 2 + board / 2, front, cz), trim))
    inner_w, inner_h = width - 2 * board, height - 2 * board
    angle = math.atan2(inner_h, inner_w)
    length = math.hypot(inner_w, inner_h) - board * 0.6
    for sign in (-1, 1):
        parts.append(box((length, 0.03, board * 0.9), (cx, front, cz), trim, rot=(0, sign * angle, 0)))
    return parts


def _window(x: float, y: float, z: float, trim, glass) -> list:
    """A four-pane window on a wall facing along X: frame, sash bars and dark glass;
    visual only, the wall behind it stays solid."""
    w, h, t = 0.8, 0.9, 0.05
    parts = [
        box((t, w + 0.16, 0.1), (x, y, z + h / 2 + 0.05), trim),
        box((t, w + 0.16, 0.1), (x, y, z - h / 2 - 0.05), trim),
        box((t, 0.1, h), (x, y + w / 2 + 0.05, z), trim),
        box((t, 0.1, h), (x, y - w / 2 - 0.05, z), trim),
        box((0.04, 0.03, h), (x, y, z), trim),
        box((0.04, w, 0.03), (x, y, z), trim),
        box((0.02, w, h), (x, y, z), glass),
    ]
    return parts


def _lamp(at: Vec, hang_to: float, shade, bulb, cord) -> list:
    """An enamel shade hanging on a cord from height hang_to down to at."""
    x, y, z = at
    parts = [cyl(0.008, 0.008, hang_to - z - 0.15, (x, y, (hang_to + z + 0.15) / 2), cord, segments=6)]
    profile = [
        (0.03, 0.16),
        (0.06, 0.14),
        (0.2, 0.03),
        (0.23, 0.0),
        (0.22, -0.005),
        (0.19, 0.025),
        (0.05, 0.13),
        (0.025, 0.15),
    ]
    parts.append(lathe(profile, (x, y, z), shade, closed=True, name="shade"))
    parts.append(sphere(0.045, (x, y, z + 0.03), bulb, segments=12))
    return parts


def _hay_stack(cx: float, cy: float, hay, twine, rng: random.Random) -> list:
    """Bales filling Farm's hay collider (2.4 m along x, 1.2 m deep, 1 m high, around cx,
    cy), tied with twine; the top layer has gaps."""
    parts = []
    size = (0.78, 0.38, 0.32)
    for layer in range(3):
        z = 0.16 + layer * 0.33
        for row in range(3):
            for col in range(3):
                if layer == 2 and rng.random() < 0.35:
                    continue
                turn = rng.uniform(-0.05, 0.05)
                x = cx + (col - 1) * 0.79 + rng.uniform(-0.03, 0.03)
                y = cy + (row - 1) * 0.39 + rng.uniform(-0.02, 0.02)
                parts.append(box(size, (x, y, z), hay, bevel=0.045, rot=(0, 0, turn), segments=1))
                for offset in (-0.2, 0.2):
                    tie = (x + offset * math.cos(turn), y + offset * math.sin(turn), z)
                    tie_size = (0.012, size[1] + 0.008, size[2] + 0.008)
                    parts.append(box(tie_size, tie, twine, rot=(0, 0, turn)))
    return parts


def barn() -> list[bpy.types.Object]:
    """The barn where it stands: board-and-batten walls in peeling red with white trim, a
    gable roof of rusting tin, sliding doors run open on their rail, a loft hatch and hay
    hook, windows, posts, beams and rafters inside, hay stacked where Farm's hay colliders
    are and lamps where Farm hangs its lights."""
    red = mat("planks_red", (1.0, 1.0, 1.0), 0.85)
    trim = mat("planks_white", (1.0, 1.0, 1.0), 0.8)
    inner = mat("planks_grey", (1.0, 1.0, 1.0), 0.9)
    timber = mat("wood", (1.0, 1.0, 1.0), 0.8)
    tin = mat("roof_tin", (1.0, 1.0, 1.0), 0.55, 0.4)
    iron = mat("iron", (1.0, 1.0, 1.0), 0.65, 0.5)
    glass = mat("plain+window", (0.05, 0.06, 0.07), 0.15)
    floor = mat("dirt+floor", (1.0, 0.86, 0.68), 0.95)
    hay = mat("hay", (1.0, 1.0, 1.0), 0.95)
    twine = mat("plain+twine", (0.45, 0.35, 0.2), 0.9)
    enamel = mat("metal_paint+lamp", (0.2, 0.32, 0.22), 0.4, 0.3)
    bulb = mat("plain+bulb", (0.95, 0.9, 0.75), 0.3)
    cord = mat("plain+cord", (0.05, 0.05, 0.05), 0.8)
    rng = random.Random(11)
    root = pivot("barn")
    parts: list[bpy.types.Object] = []
    y0, y1, x0, x1 = BARN_Y0, BARN_Y1, -BARN_X, BARN_X

    # Walls: red siding outside, grey boards inside.
    for a, b in ((x0, -DOOR / 2), (DOOR / 2, x1)):
        parts.append(_slab(a, b, y0, y0 + SIDING, 0, EAVE, red))
        parts.append(_slab(a, b, y0 + SIDING, y0 + WALL, 0, EAVE, inner))
    parts.append(_slab(-DOOR / 2, DOOR / 2, y0, y0 + SIDING, DOOR_TOP, EAVE, red))
    parts.append(_slab(-DOOR / 2, DOOR / 2, y0 + SIDING, y0 + WALL, DOOR_TOP, EAVE, inner))
    parts.append(_slab(x0, x1, y1 - SIDING, y1, 0, EAVE, red))
    parts.append(_slab(x0, x1, y1 - WALL, y1 - SIDING, 0, EAVE, inner))
    for s in (-1, 1):
        out, mid, wall_in = s * BARN_X, s * (BARN_X - SIDING), s * (BARN_X - WALL)
        parts.append(_slab(min(out, mid), max(out, mid), y0, y1, 0, EAVE, red))
        parts.append(_slab(min(mid, wall_in), max(mid, wall_in), y0, y1, 0, EAVE, inner))
    gable = [(x0, EAVE), (x1, EAVE), (0.0, RIDGE)]
    parts.append(_prism("gable", gable, y0, y0 + SIDING, red))
    parts.append(_prism("gable", gable, y0 + SIDING, y0 + WALL, inner))
    parts.append(_prism("gable", gable, y1 - SIDING, y1, red))
    parts.append(_prism("gable", gable, y1 - WALL, y1 - SIDING, inner))
    parts += _battens(x0, x1, y0 - 0.0125, _gable_top, red, gap=DOOR / 2 + 0.05)
    parts += _battens(x0, x1, y1 + 0.0125, _gable_top, red)
    for s in (-1, 1):
        y = y0 + 0.4
        while y < y1 - 0.1:
            parts.append(box((0.025, 0.06, EAVE), (s * (BARN_X + 0.0125), y, EAVE / 2), red))
            y += 0.4

    # Trim: corner boards and the door frame.
    for sx in (-1, 1):
        for y, sy in ((y0, -1), (y1, 1)):
            parts.append(box((0.18, 0.04, EAVE), (sx * (BARN_X - 0.09), y + sy * 0.035, EAVE / 2), trim))
            parts.append(box((0.04, 0.18, EAVE), (sx * (BARN_X + 0.035), y - sy * 0.09, EAVE / 2), trim))
    for s in (-1, 1):
        parts.append(box((0.16, 0.05, DOOR_TOP), (s * (DOOR / 2 + 0.08), y0 - 0.03, DOOR_TOP / 2), trim))
    parts.append(box((DOOR + 0.32, 0.05, 0.16), (0, y0 - 0.03, DOOR_TOP + 0.08), trim))

    # Sliding doors, run open along their rail.
    parts.append(box((8.8, 0.06, 0.08), (0, y0 - 0.14, DOOR_TOP + 0.3), iron))
    for s in (-1, 1):
        cx = s * (DOOR / 2 + 0.9)
        door_h = DOOR_TOP - 0.06
        parts += _braced_leaf(1.75, door_h, (cx, y0 - 0.11, 0.06 + door_h / 2), red, trim)
        for h in (-0.55, 0.55):
            parts.append(box((0.05, 0.03, 0.32), (cx + h, y0 - 0.14, DOOR_TOP + 0.12), iron))
            wheel = (cx + h, y0 - 0.17, DOOR_TOP + 0.33)
            parts.append(cyl(0.05, 0.05, 0.03, wheel, iron, (math.pi / 2, 0, 0), 12))
    # Loft hatch and hay hook on the front gable.
    parts += _braced_leaf(1.4, 1.2, (0, y0 - 0.03, 5.95), red, trim)
    parts.append(box((0.18, 1.1, 0.2), (0, y0 - 0.45, RIDGE - 0.32), timber))
    hook = [
        (0, y0 - 0.9, RIDGE - 0.42),
        (0, y0 - 0.9, RIDGE - 0.75),
        (0, y0 - 0.8, RIDGE - 0.85),
        (0, y0 - 0.72, RIDGE - 0.78),
    ]
    parts.append(tube(hook, 0.018, iron, 8))

    # Windows on the side walls, inside and out.
    for s in (-1, 1):
        for y in (14.5, 19.5):
            parts += _window(s * (BARN_X + 0.03), y, 3.0, trim, glass)
            parts += _window(s * (BARN_X - WALL - 0.01), y, 3.0, trim, glass)

    # Roof: tin on boards on rafters, a ridge cap, white fascia and rake boards.
    slope = math.atan((RIDGE - EAVE) / BARN_X)
    run = BARN_X + OVERHANG
    length = run / math.cos(slope)
    depth = y1 - y0 + 2 * OVERHANG
    for s in (-1, 1):
        cx = s * run / 2
        cz = RIDGE - (run / 2) * math.tan(slope)
        normal = Vector((s * math.sin(slope), 0, math.cos(slope)))
        rot = (0, s * slope, 0)
        middle = Vector((cx, 17.0, cz))
        parts.append(box((length, depth, 0.04), (middle + normal * 0.06).to_tuple(), tin, rot=rot))
        sheathing = (middle + normal * 0.025).to_tuple()
        parts.append(box((length, depth - 0.1, 0.03), sheathing, inner, rot=rot))
        y = y0 + 0.2
        while y < y1:
            rafter = Vector((s * BARN_X / 2, y, RIDGE - BARN_X / 2 * math.tan(slope))) - normal * 0.08
            rafter_size = (BARN_X / math.cos(slope), 0.07, 0.15)
            parts.append(box(rafter_size, rafter.to_tuple(), timber, rot=rot))
            y += 0.8
        eave_z = RIDGE - run * math.tan(slope)
        parts.append(box((0.04, depth + 0.04, 0.2), (s * (run + 0.01), 17.0, eave_z), trim))
        for edge in (y0 - OVERHANG - 0.02, y1 + OVERHANG + 0.02):
            parts.append(box((length, 0.04, 0.2), (cx, edge, cz), trim, rot=rot))
    parts.append(box((0.36, depth + 0.04, 0.05), (0, 17.0, RIDGE + 0.1), tin, bevel=0.01))

    # Inside: posts, tie beams and king posts, a dirt floor, hay and lamps.
    for y in (13.6, 16.0, 18.4, 20.8):
        for s in (-1, 1):
            parts.append(box((0.18, 0.18, EAVE), (s * (BARN_X - WALL - 0.09), y, EAVE / 2), timber))
        parts.append(box((2 * BARN_X - 2 * WALL, 0.16, 0.22), (0, y, EAVE - 0.11), timber))
        king = (0, y, (EAVE + RIDGE) / 2 - 0.05)
        parts.append(box((0.14, 0.14, RIDGE - EAVE - 0.1), king, timber))
    parts.append(_slab(x0 + WALL, x1 - WALL, y0 + WALL, y1 - WALL, 0.0, 0.012, floor))
    for s in (-1, 1):
        parts += _hay_stack(s * 4.2, 20.6, hay, twine, rng)
    for x in (-2.5, 2.5):
        parts += _lamp((x, 17.5, 4.32), RIDGE - abs(x) * math.tan(slope) - 0.2, enamel, bulb, cord)
    parts += _lamp((0, y0 - 0.6, 3.75), 4.1, enamel, bulb, cord)
    arm = [(0, y0, 4.5), (0, y0 - 0.35, 4.48), (0, y0 - 0.6, 4.3), (0, y0 - 0.6, 4.1)]
    parts.append(tube(arm, 0.02, iron, 8))
    _under(root, *parts)
    return [root]


SHED_X0, SHED_X1 = -25.0, -21.0  # Farm.SHED: x -25 to -21, z -4 to -1 (Blender y 1 to 4).
SHED_Y0, SHED_Y1 = 1.0, 4.0
SHED_DOOR = 1.4  # Farm.SHED_DOOR, centred on x -23.
SHED_FRONT, SHED_BACK = 3.0, 2.6  # Wall tops; the roof falls to the back.


def _side_wall(x_lo: float, x_hi: float, material) -> bpy.types.Object:
    """One of the shed's side walls, its top following the roof's slope."""
    bm = bmesh.new()
    outline = [(SHED_Y0, 0.0), (SHED_Y1, 0.0), (SHED_Y1, SHED_BACK), (SHED_Y0, SHED_FRONT)]
    near = [bm.verts.new((x_lo, y, z)) for y, z in outline]
    far = [bm.verts.new((x_hi, y, z)) for y, z in outline]
    bm.faces.new(near)
    bm.faces.new(list(reversed(far)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new([near[i], near[j], far[j], far[i]])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return lib._from_bmesh("shed_side", bm, material, False)


def shed() -> list[bpy.types.Object]:
    """The tool shed where it stands: weathered grey board-and-batten walls, a lean-to tin
    roof falling to the back, a window, and its plank door swung open flat to the wall."""
    grey = mat("planks_grey", (1.0, 1.0, 1.0), 0.9)
    timber = mat("wood", (1.0, 1.0, 1.0), 0.8)
    tin = mat("roof_tin", (1.0, 1.0, 1.0), 0.55, 0.4)
    iron = mat("iron", (1.0, 1.0, 1.0), 0.65, 0.5)
    glass = mat("plain+window", (0.05, 0.06, 0.07), 0.15)
    root = pivot("shed")
    parts: list[bpy.types.Object] = []
    door_l, door_r = -23.0 - SHED_DOOR / 2, -23.0 + SHED_DOOR / 2
    door_top = 2.2

    def top(y: float) -> float:
        return SHED_FRONT + (SHED_BACK - SHED_FRONT) * (y - SHED_Y0) / (SHED_Y1 - SHED_Y0)

    for a, b in ((SHED_X0, door_l), (door_r, SHED_X1)):
        parts.append(_slab(a, b, SHED_Y0, SHED_Y0 + WALL, 0, SHED_FRONT, grey))
    parts.append(_slab(door_l, door_r, SHED_Y0, SHED_Y0 + WALL, door_top, SHED_FRONT, grey))
    parts.append(_slab(SHED_X0, SHED_X1, SHED_Y1 - WALL, SHED_Y1, 0, SHED_BACK, grey))
    parts.append(_side_wall(SHED_X0, SHED_X0 + WALL, grey))
    parts.append(_side_wall(SHED_X1 - WALL, SHED_X1, grey))
    x = SHED_X0 + 0.4
    while x < SHED_X1 - 0.1:
        if door_l - 0.03 < x < door_r + 0.03:
            above = SHED_FRONT - door_top
            parts.append(box((0.06, 0.025, above), (x, SHED_Y0 - 0.0125, door_top + above / 2), grey))
        else:
            parts.append(box((0.06, 0.025, SHED_FRONT), (x, SHED_Y0 - 0.0125, SHED_FRONT / 2), grey))
        parts.append(box((0.06, 0.025, SHED_BACK), (x, SHED_Y1 + 0.0125, SHED_BACK / 2), grey))
        x += 0.4
    for s, wall_x in ((-1, SHED_X0), (1, SHED_X1)):
        y = SHED_Y0 + 0.4
        while y < SHED_Y1 - 0.1:
            parts.append(box((0.025, 0.06, top(y)), (wall_x + s * 0.0125, y, top(y) / 2), grey))
            y += 0.4
        for y, sy in ((SHED_Y0, -1), (SHED_Y1, 1)):
            post = (wall_x + s * 0.04, y + sy * 0.04, top(y) / 2)
            parts.append(box((0.12, 0.12, top(y)), post, timber))
    for s, a in ((-1, door_l), (1, door_r)):
        parts.append(box((0.1, 0.06, door_top), (a + s * 0.05, SHED_Y0 - 0.03, door_top / 2), timber))
    parts.append(box((SHED_DOOR + 0.2, 0.06, 0.1), (-23.0, SHED_Y0 - 0.03, door_top + 0.05), timber))
    parts += _window(SHED_X1 + 0.03, 2.5, 1.6, timber, glass)

    # The roof: tin over rafters, overhanging every side.
    fall = math.atan((SHED_FRONT - SHED_BACK) / (SHED_Y1 - SHED_Y0))
    width = SHED_X1 - SHED_X0 + 0.6
    span = (SHED_Y1 - SHED_Y0 + 0.8) / math.cos(fall)
    mid = ((SHED_Y0 + SHED_Y1) / 2, (SHED_FRONT + SHED_BACK) / 2)
    parts.append(box((width, span, 0.04), (-23.0, mid[0], mid[1] + 0.09), tin, rot=(-fall, 0, 0)))
    x = SHED_X0 + 0.1
    while x < SHED_X1:
        parts.append(box((0.06, span, 0.12), (x, mid[0], mid[1]), timber, rot=(-fall, 0, 0)))
        x += 0.6

    # The door, open flat against the front wall: hinged on its left post, swung out.
    hinge = pivot("door", (door_l, SHED_Y0 - 0.06, 0))
    leaf_h = door_top - 0.08
    centre = (door_l + SHED_DOOR / 2, SHED_Y0 - 0.06, 0.04 + leaf_h / 2)
    leaf = _braced_leaf(SHED_DOOR - 0.05, leaf_h, centre, grey, grey)
    for z in (0.4, door_top - 0.4):
        leaf.append(box((0.35, 0.015, 0.05), (door_l + 0.17, SHED_Y0 - 0.1, z), iron))
    _under(hinge, *leaf)
    hinge.rotation_euler = (0, 0, math.radians(170))
    _under(root, *parts, hinge)
    return [root]


# --- Farm props ------------------------------------------------------------------------


def generator() -> list[bpy.types.Object]:
    """A portable generator in a tube frame, about Farm's 1.2 x 0.9 x 0.8 m collider: an
    engine with cooling fins and a pull start, the alternator, a fuel tank on top, a muffler
    and a panel of sockets."""
    yellow = mat("metal_paint+generator", (0.82, 0.68, 0.18), 0.45, 0.25)
    black = mat("metal_paint+black", (0.12, 0.12, 0.12), 0.5, 0.3)
    iron = mat("iron", (1.0, 1.0, 1.0), 0.65, 0.5)
    rubber = mat("plain+rubber", (0.05, 0.05, 0.05), 0.9)
    red = mat("plain+switch", (0.6, 0.08, 0.05), 0.4)
    root = pivot("generator")
    side = (0, math.pi / 2, 0)
    parts = []
    for y in (-0.3, 0.3):
        parts.append(box((1.15, 0.06, 0.05), (0, y, 0.025), black, bevel=0.01))
    for x in (-0.56, 0.56):
        for y in (-0.36, 0.36):
            parts.append(tube([(x, y, 0.04), (x, y, 0.7), (x * 0.95, y * 0.92, 0.84)], 0.022, black, 10))
        arch = [(x * 0.95, -0.33, 0.84), (x * 0.98, 0.0, 0.87), (x * 0.95, 0.33, 0.84)]
        parts.append(tube(arch, 0.022, black, 10))
    for y in (-0.33, 0.33):
        parts.append(tube([(-0.53, y, 0.84), (0.53, y, 0.84)], 0.02, black, 10))
    for y in (-0.36, 0.36):
        parts.append(tube([(-0.56, y, 0.06), (0.56, y, 0.06)], 0.02, black, 10))
    parts.append(box((0.48, 0.42, 0.34), (-0.18, 0.0, 0.26), black, bevel=0.03))
    for k in range(7):
        parts.append(box((0.4, 0.36, 0.012), (-0.2, 0.0, 0.45 + k * 0.022), iron))
    parts.append(cyl(0.1, 0.1, 0.06, (-0.45, 0.0, 0.3), yellow, side, 20))
    parts.append(cyl(0.025, 0.025, 0.05, (-0.5, 0.0, 0.3), black, side, 10))
    parts.append(box((0.03, 0.08, 0.03), (-0.52, 0.0, 0.3), rubber))
    parts.append(cyl(0.16, 0.16, 0.4, (0.27, 0.0, 0.27), yellow, side, 24))
    parts.append(cyl(0.165, 0.165, 0.03, (0.47, 0.0, 0.27), black, side, 24))
    parts.append(box((0.9, 0.55, 0.2), (0.0, 0.0, 0.69), yellow, bevel=0.06))
    parts.append(cyl(0.05, 0.05, 0.05, (-0.25, 0.1, 0.8), black, segments=16))
    parts.append(cyl(0.07, 0.07, 0.3, (-0.3, -0.27, 0.35), iron, side, 16))
    parts.append(tube([(-0.15, -0.27, 0.35), (-0.05, -0.32, 0.3)], 0.015, iron, 8))
    parts.append(box((0.3, 0.03, 0.2), (0.25, 0.23, 0.27), black, bevel=0.01))
    for x in (0.18, 0.3):
        parts.append(box((0.05, 0.02, 0.05), (x, 0.25, 0.3), rubber))
    parts.append(box((0.03, 0.02, 0.05), (0.38, 0.25, 0.22), red))
    _under(root, *parts)
    return [root]


def drum() -> list[bpy.types.Object]:
    """A 55-gallon fuel drum, 0.7 m across and 1 m tall: rolling hoops, rims and bungs."""
    paint = mat("metal_paint+drum", (0.6, 0.12, 0.08), 0.45, 0.25)
    iron = mat("iron", (1.0, 1.0, 1.0), 0.65, 0.5)
    root = pivot("drum")
    profile = [
        (0.0, 0.015),
        (0.33, 0.015),
        (0.35, 0.03),
        (0.35, 0.32),
        (0.36, 0.33),
        (0.35, 0.34),
        (0.35, 0.66),
        (0.36, 0.67),
        (0.35, 0.68),
        (0.35, 0.97),
        (0.345, 0.985),
        (0.0, 0.985),
    ]
    body = lathe(profile, (0, 0, 0), paint, segments=32, name="drum")
    rims = [torus(0.345, 0.014, (0, 0, z), paint, segments=32) for z in (0.015, 0.99)]
    bungs = [cyl(0.03, 0.03, 0.02, (x, 0.1, 0.995), iron, segments=12) for x in (-0.2, 0.18)]
    _under(root, body, *rims, *bungs)
    return [root]


def pump() -> list[bpy.types.Object]:
    """An old cast-iron hand pump on a concrete pad, its spout toward Godot's +Z (Blender
    -Y) and its handle back, about Farm's 1.2 m pump collider."""
    iron = mat("iron", (1.0, 1.0, 1.0), 0.65, 0.5)
    concrete = mat("plain+concrete", (0.45, 0.44, 0.42), 0.95)
    timber = mat("wood", (1.0, 1.0, 1.0), 0.8)
    root = pivot("pump")
    parts = [box((0.6, 0.6, 0.08), (0, 0, 0.04), concrete, bevel=0.02)]
    parts.append(cyl(0.13, 0.11, 0.05, (0, 0, 0.105), iron, segments=20))
    column = [
        (0.0, 0.13),
        (0.065, 0.13),
        (0.06, 0.4),
        (0.075, 0.42),
        (0.065, 0.45),
        (0.07, 0.85),
        (0.085, 0.87),
        (0.085, 0.9),
        (0.07, 0.92),
        (0.0, 0.92),
    ]
    parts.append(lathe(column, (0, 0, 0), iron, segments=20, name="column"))
    spout = [(0, -0.05, 0.78), (0, -0.25, 0.76), (0, -0.32, 0.7), (0, -0.33, 0.64)]
    parts.append(tube(spout, [0.035, 0.03, 0.028, 0.026], iron, 12))
    cap = [(0.0, 0.0), (0.04, 0.0), (0.045, 0.05), (0.03, 0.12), (0.0, 0.14)]
    parts.append(lathe(cap, (0, 0, 0.92), iron, segments=16, name="cap"))
    parts.append(box((0.04, 0.08, 0.12), (0, 0.02, 0.98), iron))
    handle = [(0, 0.0, 1.0), (0, 0.25, 1.1), (0, 0.5, 1.18), (0, 0.6, 1.18)]
    parts.append(tube(handle, 0.018, iron, 8))
    parts.append(cyl(0.025, 0.025, 0.14, (0, 0.66, 1.18), timber, (math.pi / 2, 0, 0), 10))
    _under(root, *parts)
    return [root]


def crate() -> list[bpy.types.Object]:
    """The shipping crate, Farm's 1.4 x 0.8 x 1.0 m: corner posts, slatted sides, a lid."""
    boards = mat("planks_grey+crate", (0.9, 0.82, 0.7), 0.9)
    timber = mat("wood", (1.0, 1.0, 1.0), 0.8)
    dark = mat("plain+dark", (0.03, 0.025, 0.02), 1.0)
    root = pivot("crate")
    w, d, h = 1.4, 1.0, 0.8
    parts = [box((w - 0.1, d - 0.1, h - 0.06), (0, 0, h / 2), dark)]
    for x in (-w / 2 + 0.04, w / 2 - 0.04):
        for y in (-d / 2 + 0.04, d / 2 - 0.04):
            parts.append(box((0.08, 0.08, h), (x, y, h / 2), timber, bevel=0.01))
    for k in range(4):
        z = 0.1 + k * 0.19
        for y in (-d / 2 - 0.01, d / 2 + 0.01):
            parts.append(box((w - 0.1, 0.025, 0.14), (0, y, z), boards, bevel=0.005))
        for x in (-w / 2 - 0.01, w / 2 + 0.01):
            parts.append(box((0.025, d - 0.1, 0.14), (x, 0, z), boards, bevel=0.005))
    for k in range(6):
        lid = (-w / 2 + 0.12 + k * 0.232, 0, h + 0.012)
        parts.append(box((0.21, d, 0.025), lid, boards, bevel=0.005))
    _under(root, *parts)
    return [root]


# --- Plants ---------------------------------------------------------------------------

CORN_HEIGHT = 2.5  # Farm.CORN_HEIGHT.


def corn(detail: bool) -> list[bpy.types.Object]:
    """A corn stalk with UVs for the leaf texture: a jointed stalk, arching leaves that
    droop at the tips, and (in detail) a tassel and an ear in its husk. The far version
    keeps four leaves and nothing else, for corn past the near range."""
    leaf = mat("leaf", (1.0, 1.0, 1.0), 0.75)
    rng = random.Random(3)
    root = pivot("corn" if detail else "corn_far")
    top = CORN_HEIGHT - 0.15
    stalk = [(0, 0, 0), (0.01, 0, 0.6), (0, 0.01, 1.3), (0, 0, 2.0), (0, 0, top)]
    radii = [0.024, 0.02, 0.016, 0.012, 0.006]
    parts = [_uv_tube("stalk", stalk, radii, leaf, 6 if detail else 3)]
    count = 10 if detail else 4
    segments = 8 if detail else 3
    for k in range(count):
        base_z = 0.35 + k * (1.8 / count) + rng.uniform(-0.05, 0.05)
        angle = k * 2.6 + rng.uniform(-0.3, 0.3)
        length = 0.7 + 0.35 * math.sin(math.pi * (k + 0.5) / count) + rng.uniform(-0.08, 0.08)
        width = 0.08 if detail else 0.11
        out = Vector((math.cos(angle), math.sin(angle), 0))
        across = Vector((-math.sin(angle), math.cos(angle), 0))
        droop = rng.uniform(0.6, 0.9)
        lefts, rights = [], []
        for i in range(segments + 1):
            t = i / segments
            centre = Vector((0, 0, base_z)) + out * (0.015 + length * 0.85 * t)
            centre.z += length * (0.6 * t - droop * t * t)
            swell = 0.5 + 0.5 * math.sin(math.pi * min(1.0, t * 0.9 + 0.1))
            half = width / 2 * swell * (1 - t**3)
            cup = Vector((0, 0, half * 0.25))
            lefts.append((centre + across * half + cup).to_tuple())
            rights.append((centre - across * half + cup).to_tuple())
        parts.append(_quad_strip("leaf", lefts, rights, leaf))
    if detail:
        for k in range(9):  # The tassel: thin spikes from the top, spreading and bending.
            angle = k * 0.7
            out = Vector((math.cos(angle), math.sin(angle), 0))
            across = Vector((-math.sin(angle), math.cos(angle), 0))
            lefts, rights = [], []
            for i in range(4):
                t = i / 3
                centre = Vector((0, 0, top)) + out * 0.25 * t + Vector((0, 0, 0.3 * t - 0.15 * t * t))
                lefts.append((centre + across * 0.006).to_tuple())
                rights.append((centre - across * 0.006).to_tuple())
            parts.append(_quad_strip("tassel", lefts, rights, leaf))
        out = Vector((math.cos(1.1), math.sin(1.1), 0))
        start = Vector((0, 0, 1.15))
        husk = [start + out * (0.02 + 0.06 * t) + Vector((0, 0, 0.22 * t)) for t in (0.0, 0.2, 0.5, 0.8, 1.0)]
        husk_radii = [0.018, 0.034, 0.036, 0.025, 0.004]
        parts.append(_uv_tube("ear", [p.to_tuple() for p in husk], husk_radii, leaf, 8))
    _under(root, *parts)
    return [root]


def pine() -> list[bpy.types.Object]:
    """A pine about 9 m tall standing on its origin: a flared trunk and twelve drooping,
    ragged tiers of boughs, widest (2.2 m) at the bottom."""
    bark = mat("bark", (1.0, 1.0, 1.0), 0.95)
    boughs = mat("needles", (1.0, 1.0, 1.0), 0.9)
    rng = random.Random(5)
    root = pivot("pine")
    parts = [
        cyl(0.2, 0.04, 8.8, (0, 0, 4.4), bark, segments=10),
        cyl(0.34, 0.2, 0.45, (0, 0, 0.225), bark, segments=10),
    ]
    tiers = 12
    for k in range(tiers):
        t = k / (tiers - 1)
        top_z = 1.7 + t * 7.3
        radius = 2.1 * (1 - t) + 0.3
        bm = bmesh.new()
        spokes = 16
        apex = bm.verts.new((0, 0, top_z))
        mids, rims = [], []
        for j in range(spokes):
            a = 2 * math.pi * j / spokes + rng.uniform(-0.1, 0.1)
            r = radius * rng.uniform(0.82, 1.12)
            sag = r * rng.uniform(0.75, 1.0)
            mids.append(bm.verts.new((math.cos(a) * r * 0.5, math.sin(a) * r * 0.5, top_z - sag * 0.38)))
            rims.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, top_z - sag - rng.uniform(0, 0.25))))
        for j in range(spokes):
            n = (j + 1) % spokes
            bm.faces.new([apex, mids[j], mids[n]])
            bm.faces.new([mids[j], rims[j], rims[n], mids[n]])
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        parts.append(lib._from_bmesh("tier", bm, boughs, True))
    _under(root, *parts)
    return [root]


MODELS = {
    "farmer": farmer,
    "creature": creature,
    "scarecrow": scarecrow,
    "boar": boar,
    "husk": husk,
    "barn": barn,
    "shed": shed,
    "generator": generator,
    "drum": drum,
    "pump": pump,
    "crate": crate,
    "corn": lambda: corn(True),
    "corn_far": lambda: corn(False),
    "pine": pine,
}


def main(names: set[str]) -> None:
    for name, build in MODELS.items():
        if names and name not in names:
            continue
        lib.reset()
        roots = build()
        lo, hi = lib.bounds(roots)
        size = hi - lo
        lib.export(OUT / f"{name}.glb", roots)
        print(f"model {name}: {size.x:.2f} x {size.y:.2f} x {size.z:.2f} m")
