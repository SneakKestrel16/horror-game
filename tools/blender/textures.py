"""Tileable surface textures, made from Blender procedural nodes and baked to images.

Each texture is a node graph over one tile (UV 0 to 1) that wraps seamlessly: every noise
is sampled on a torus (u and v each turned into a circle in 4D noise space), and every
stripe or board count is a whole number per tile. Baking writes a colour map (`<name>.jpg`)
and a tangent-space normal map (`<name>_n.jpg`, OpenGL, as Godot expects) into
game/assets/textures/, and `textures.json` with each texture's tile size in metres and its
roughness, metal and mapping, which `Dress` (scripts/dress.gd) reads.

Colours are sRGB, as in the GDScript; the graphs work in linear and the bake stores sRGB.
Heights are in metres and turned into the bump for the tile's real size.
"""

import json
import math
from collections.abc import Callable, Sequence
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "assets" / "textures"
SIZE = 1024  # Pixels per tile side.
QUALITY = 88  # JPEG, lowered for a map that would pass MAX_BYTES.
MAX_BYTES = 480_000  # check-added-large-files allows 500 KB a file.

Socket = bpy.types.NodeSocket
Value = Socket | float
Color = tuple[float, float, float]


def _linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _rgba(color: Color) -> tuple[float, float, float, float]:
    return (*(_linear(c) for c in color), 1.0)


class Graph:
    """One texture's node graph, built a node at a time.

    u and v run 0 to 1 across the tile. Methods return output sockets; any input can be
    a socket or a number.
    """

    def __init__(self, name: str, size: float) -> None:
        self.size = size
        self.material = bpy.data.materials.new(name)
        self.material.use_nodes = True
        tree = self.material.node_tree
        assert tree is not None
        self.tree = tree
        tree.nodes.clear()
        coords = self.node("ShaderNodeTexCoord")
        split = self.node("ShaderNodeSeparateXYZ")
        self.link(coords.outputs["UV"], split.inputs[0])
        self.u: Socket = split.outputs[0]
        self.v: Socket = split.outputs[1]

    def node(self, kind: str, **props: object) -> bpy.types.Node:
        node = self.tree.nodes.new(kind)
        for key, value in props.items():
            setattr(node, key, value)
        return node

    def link(self, out: Socket, into: Socket) -> None:
        self.tree.links.new(out, into)

    def feed(self, into: Socket, value: Value | Color) -> None:
        if isinstance(value, bpy.types.NodeSocket):
            self.link(value, into)
        elif isinstance(value, tuple):
            into.default_value = _rgba(value)  # type: ignore[attr-defined]
        else:
            into.default_value = value  # type: ignore[attr-defined]

    # --- Arithmetic ------------------------------------------------------------------

    def math(self, op: str, a: Value, b: Value = 0.0, c: Value = 0.0, clamp: bool = False):
        node = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, value in enumerate((a, b, c)):
            self.feed(node.inputs[i], value)
        return node.outputs[0]

    def add(self, *values: Value) -> Value:
        total = values[0]
        for value in values[1:]:
            total = self.math("ADD", total, value)
        return total

    def mul(self, a: Value, b: Value) -> Socket:
        return self.math("MULTIPLY", a, b)

    def sub(self, a: Value, b: Value) -> Socket:
        return self.math("SUBTRACT", a, b)

    def lin(self, cu: float, cv: float) -> Socket:
        """cu * u + cv * v: a direction across the tile (whole numbers keep it seamless)."""
        return self.math("MULTIPLY_ADD", self.u, cu, self.mul(self.v, cv))

    def wave(self, at: Value, count: float) -> Socket:
        """sin(2 pi count at), -1 to 1: count stripes a tile when count is whole."""
        return self.math("SINE", self.mul(at, 2 * math.pi * count))

    def fract(self, at: Value, count: float) -> Socket:
        return self.math("FRACT", self.mul(at, count))

    def band(self, x: Value, lo: float, hi: float) -> Socket:
        """0 below lo, 1 above hi, smooth between."""
        node = self.node("ShaderNodeMapRange", interpolation_type="SMOOTHERSTEP", clamp=True)
        self.feed(node.inputs["Value"], x)
        node.inputs["From Min"].default_value = lo  # type: ignore[attr-defined]
        node.inputs["From Max"].default_value = hi  # type: ignore[attr-defined]
        return node.outputs["Result"]

    def random(self, cell: Value, seed: float = 0.0) -> Socket:
        """A random 0-1 number for each whole value of cell (a board, a row)."""
        node = self.node("ShaderNodeTexWhiteNoise", noise_dimensions="2D")
        vector = self.node("ShaderNodeCombineXYZ")
        self.feed(vector.inputs[0], self.math("FLOOR", cell))
        self.feed(vector.inputs[1], seed)
        self.link(vector.outputs[0], node.inputs["Vector"])
        return node.outputs["Value"]

    # --- Seamless noise ----------------------------------------------------------------

    def _torus(self, a: Value, b: Value, ka: float, kb: float, offset: Value):
        """4D coordinates for directions a and b, each a whole cycle per tile, so noise
        sampled there wraps: ka and kb noise units fit along each."""
        ra, rb = ka / (2 * math.pi), kb / (2 * math.pi)
        turn_a = self.mul(a, 2 * math.pi)
        turn_b = self.mul(b, 2 * math.pi)
        vector = self.node("ShaderNodeCombineXYZ")
        self.feed(vector.inputs[0], self.add(self.mul(self.math("COSINE", turn_a), ra), offset))
        self.feed(vector.inputs[1], self.mul(self.math("SINE", turn_a), ra))
        self.feed(vector.inputs[2], self.mul(self.math("COSINE", turn_b), rb))
        w = self.add(self.mul(self.math("SINE", turn_b), rb), self.mul(offset, 0.7))
        return vector.outputs[0], w

    def noise(
        self,
        ku: float,
        kv: float,
        seed: Value = 0.0,
        detail: float = 4.0,
        roughness: float = 0.5,
        distortion: float = 0.0,
        a: Value | None = None,
        b: Value | None = None,
    ) -> Socket:
        """Fractal noise, 0 to 1 (about 0.5 on average), ku features across the tile and
        kv down it; a and b replace u and v for slanted grain."""
        vector, w = self._torus(
            self.u if a is None else a, self.v if b is None else b, ku, kv, self.add(seed, 3.1)
        )
        node = self.node("ShaderNodeTexNoise", noise_dimensions="4D")
        self.link(vector, node.inputs["Vector"])
        self.feed(node.inputs["W"], w)
        for key, value in (
            ("Scale", 1.0),
            ("Detail", detail),
            ("Roughness", roughness),
            ("Distortion", distortion),
        ):
            node.inputs[key].default_value = value  # type: ignore[attr-defined]
        return node.outputs["Fac"]

    def cells(
        self,
        ku: float,
        kv: float,
        seed: Value = 0.0,
        feature: str = "F1",
        output: str = "Distance",
        randomness: float = 1.0,
    ) -> Socket:
        """Voronoi cells, ku across and kv down: Distance from the nearest point, its
        random Color, or (feature DISTANCE_TO_EDGE) the distance to a cell's edge."""
        vector, w = self._torus(self.u, self.v, ku, kv, self.add(seed, 5.3))
        node = self.node("ShaderNodeTexVoronoi", voronoi_dimensions="4D", feature=feature)
        self.link(vector, node.inputs["Vector"])
        self.feed(node.inputs["W"], w)
        node.inputs["Scale"].default_value = 1.0  # type: ignore[attr-defined]
        node.inputs["Randomness"].default_value = randomness  # type: ignore[attr-defined]
        if output == "Color":
            return self.math("ADD", self.bw(node.outputs["Color"]), 0.0)
        return node.outputs[output]

    def bw(self, color: Socket) -> Socket:
        node = self.node("ShaderNodeRGBToBW")
        self.link(color, node.inputs[0])
        return node.outputs[0]

    # --- Colour ----------------------------------------------------------------------

    def ramp(self, fac: Value, stops: Sequence[tuple[float, Color]], step: bool = False):
        node = self.node("ShaderNodeValToRGB")
        ramp = node.color_ramp
        ramp.interpolation = "CONSTANT" if step else "LINEAR"
        while len(ramp.elements) < len(stops):
            ramp.elements.new(0.5)
        for element, (at, color) in zip(ramp.elements, stops, strict=True):
            element.position = at
            element.color = _rgba(color)
        self.feed(node.inputs[0], fac)
        return node.outputs[0]

    def mix(self, a: Socket | Color, b: Socket | Color, fac: Value, blend: str = "MIX"):
        node = self.node("ShaderNodeMix", data_type="RGBA", blend_type=blend, clamp_result=True)
        self.feed(node.inputs[0], fac)
        self.feed(node.inputs[6], a)
        self.feed(node.inputs[7], b)
        return node.outputs[2]

# A texture: its graph builder, tile size in metres, roughness, metal, and mapping
# ("triplanar" in each model's own space, or "uv" for meshes made with UVs).
Recipe = tuple[Callable[[Graph], tuple[Socket, Value]], float, float, float, str]


def planks(
    count: int,
    paint: Color | None,
    gaps: bool = True,
    wood: Sequence[Color] = ((0.25, 0.22, 0.19), (0.5, 0.46, 0.4), (0.62, 0.58, 0.52)),
) -> Callable[[Graph], tuple[Socket, Value]]:
    """Vertical boards, count a tile, weathered grey wood, painted (and peeling) if paint."""

    def build(g: Graph) -> tuple[Socket, Value]:
        board = g.mul(g.u, count)
        rand = g.random(board, 1.0)
        across = g.math("FRACT", board)
        grain = g.noise(count * 7.0, 3.0, g.mul(rand, 40.0), 6.0, 0.62, 0.0)
        knots = g.cells(count * 1.0, 2.0, g.mul(rand, 9.0))
        tone = g.add(g.mul(grain, 0.8), g.mul(rand, 0.25), -0.05)
        color = g.ramp(tone, [(0.25, wood[0]), (0.55, wood[1]), (0.8, wood[2])])
        color = g.mix(color, (0.15, 0.12, 0.1), g.sub(1.0, g.band(knots, 0.0, 0.07)))
        height: Value = g.mul(grain, 0.0015)
        if gaps:
            edge = g.mul(g.band(across, 0.0, 0.035), g.sub(1.0, g.band(across, 0.965, 1.0)))
            color = g.mix((0.05, 0.04, 0.035), color, edge)
            height = g.add(height, g.mul(edge, 0.006))
        if paint is not None:
            peel = g.noise(6.0, 8.0, g.mul(rand, 13.0), 7.0, 0.62)
            bare = g.band(g.add(peel, g.mul(g.noise(count * 3.0, 1.5, 4.0), 0.25)), 0.71, 0.73)
            # Paint gone thin shows the wood's grain through it.
            fade = g.add(
                g.mul(g.noise(3.0, 2.0, 7.0, 3.0), 0.55),
                g.mul(g.noise(40.0, 60.0, 8.0, 5.0), 0.3),
                g.mul(rand, 0.15),
                g.mul(grain, 0.2),
            )
            coat = g.ramp(fade, [(0.3, _darker(paint)), (0.55, paint), (0.85, _lighter(paint))])
            streak = g.noise(count * 4.0, 1.0, 11.0, 4.0)
            coat = g.mix(coat, (0.1, 0.07, 0.05), g.mul(g.band(streak, 0.5, 0.85), 0.5))
            color = g.mix(coat, color, bare)
            height = g.add(height, g.mul(g.sub(1.0, bare), 0.0006))
        return color, height

    return build


def _lighter(color: Color) -> Color:
    return (min(1.0, color[0] * 1.3), min(1.0, color[1] * 1.3), min(1.0, color[2] * 1.3))


def _darker(color: Color) -> Color:
    return (color[0] * 0.65, color[1] * 0.65, color[2] * 0.65)


def wood(g: Graph) -> tuple[Socket, Value]:
    """Plain sawn wood, grain along v: beams, posts, handles."""
    grain = g.noise(40.0, 2.0, 0.0, 6.0, 0.6, 0.3)
    rings = g.wave(g.add(g.u, g.mul(g.noise(3.0, 2.0, 2.0), 0.15)), 18.0)
    tone = g.add(g.mul(grain, 0.7), g.mul(rings, 0.08))
    color = g.ramp(tone, [(0.2, (0.27, 0.18, 0.11)), (0.5, (0.45, 0.32, 0.2)), (0.75, (0.56, 0.42, 0.27))])
    return color, g.mul(grain, 0.001)


def roof_tin(g: Graph) -> tuple[Socket, Value]:
    """Corrugated iron, ridges along v, galvanised grey gone to rust in patches and streaks."""
    ridge = g.wave(g.v, 40.0)  # Ridges along u: down the slope in a roof's top-down projection.
    patch = g.noise(5.0, 5.0, 1.0, 8.0, 0.65)
    streak = g.noise(2.5, 60.0, 2.0, 4.0, 0.5)
    rust = g.band(g.add(patch, g.mul(streak, 0.3)), 0.68, 0.76)
    zinc = g.ramp(g.noise(8.0, 8.0, 3.0, 5.0), [(0.3, (0.42, 0.43, 0.42)), (0.7, (0.6, 0.61, 0.6))])
    brown = g.ramp(g.noise(30.0, 30.0, 4.0, 6.0), [(0.3, (0.3, 0.13, 0.06)), (0.7, (0.55, 0.27, 0.1))])
    color = g.mix(zinc, brown, rust)
    color = g.mix(color, (0.15, 0.13, 0.12), g.mul(g.math("ABSOLUTE", g.sub(ridge, -1.0)), 0.06))
    height = g.add(g.mul(ridge, 0.012), g.mul(g.noise(40.0, 40.0, 5.0, 6.0), g.mul(rust, 0.002)))
    return color, height


def metal_paint(g: Graph) -> tuple[Socket, Value]:
    """Painted steel, near white so Godot can tint it, chipped down to dark metal and rust."""
    chips = g.noise(9.0, 9.0, 1.0, 8.0, 0.7)
    chip = g.band(chips, 0.66, 0.68)
    scratches = g.band(g.noise(2.0, 90.0, 2.0, 2.0, 0.5, a=g.lin(1, 1), b=g.lin(1, -1)), 0.72, 0.74)
    paint = g.ramp(g.noise(4.0, 4.0, 3.0, 4.0), [(0.3, (0.78, 0.78, 0.76)), (0.7, (0.92, 0.92, 0.9))])
    rust = g.ramp(g.noise(30.0, 30.0, 4.0, 6.0), [(0.3, (0.22, 0.12, 0.07)), (0.7, (0.45, 0.22, 0.09))])
    color = g.mix(paint, (0.35, 0.34, 0.33), g.mul(scratches, 0.6))
    color = g.mix(color, rust, chip)
    return color, g.add(g.mul(g.sub(1.0, chip), 0.0005), g.mul(scratches, -0.0002))


def iron(g: Graph) -> tuple[Socket, Value]:
    """Cast iron, black-grey and pitted, rusty in the hollows: the pump, tools, traps."""
    pits = g.cells(40.0, 40.0, 1.0)
    rust = g.band(g.noise(6.0, 6.0, 2.0, 7.0, 0.65), 0.55, 0.7)
    base = g.ramp(g.noise(20.0, 20.0, 3.0, 6.0), [(0.3, (0.12, 0.12, 0.12)), (0.7, (0.24, 0.23, 0.22))])
    color = g.mix(base, (0.4, 0.2, 0.09), g.mul(rust, 0.8))
    color = g.mix((0.3, 0.15, 0.07), color, g.band(pits, 0.04, 0.12))
    return color, g.mul(g.band(pits, 0.0, 0.12), 0.0006)


def hay(g: Graph) -> tuple[Socket, Value]:
    """Packed straw: strands mostly along u, some across, golden with pale and dark."""
    along = g.noise(3.0, 140.0, 0.0, 8.0, 0.55)
    slant = g.noise(2.0, 90.0, 1.0, 6.0, 0.55, a=g.lin(1, 1), b=g.lin(1, -1))
    other = g.noise(2.0, 90.0, 2.0, 6.0, 0.55, a=g.lin(1, -1), b=g.lin(1, 1))
    strands = g.math("MAXIMUM", g.math("MAXIMUM", along, slant), other)
    color = g.ramp(
        g.add(strands, g.mul(g.noise(6.0, 6.0, 3.0), 0.25), -0.1),
        [(0.3, (0.3, 0.22, 0.09)), (0.5, (0.68, 0.55, 0.27)), (0.75, (0.88, 0.78, 0.5))],
    )
    return color, g.mul(strands, 0.006)


def grass(g: Graph) -> tuple[Socket, Value]:
    """Rough pasture: blades in clumps, greens and straw, bare earth between."""
    blades = g.noise(160.0, 160.0, 0.0, 6.0, 0.7, 0.4)
    clumps = g.cells(14.0, 14.0, 1.0)
    patch = g.noise(4.0, 4.0, 2.0, 5.0, 0.6)
    tone = g.add(g.mul(blades, 0.8), g.mul(g.sub(0.5, clumps), 0.15))
    green = g.ramp(tone, [(0.2, (0.1, 0.13, 0.05)), (0.5, (0.24, 0.3, 0.11)), (0.75, (0.36, 0.42, 0.17))])
    straw = g.ramp(tone, [(0.25, (0.25, 0.22, 0.1)), (0.7, (0.5, 0.45, 0.24))])
    color = g.mix(green, straw, g.mul(g.band(patch, 0.5, 0.7), 0.7))
    earth = g.band(g.noise(10.0, 10.0, 3.0, 6.0, 0.6), 0.66, 0.72)
    color = g.mix(color, (0.24, 0.19, 0.13), g.mul(earth, 0.8))
    return color, g.mul(blades, 0.012)


def dirt(g: Graph) -> tuple[Socket, Value]:
    """Packed yard dirt: grit, scattered pebbles, darker damp patches and fine cracks."""
    grit = g.noise(200.0, 200.0, 0.0, 4.0, 0.6)
    cells = g.cells(30.0, 30.0, 1.0)
    picked = g.math("GREATER_THAN", g.cells(30.0, 30.0, 1.0, output="Color"), 0.6)
    pebble = g.mul(g.sub(1.0, g.band(cells, 0.18, 0.26)), picked)
    damp = g.band(g.noise(4.0, 4.0, 2.0, 6.0, 0.6), 0.5, 0.75)
    edges = g.cells(10.0, 10.0, 3.0, feature="DISTANCE_TO_EDGE")
    cracks = g.sub(1.0, g.band(edges, 0.0, 0.03))
    tone = g.add(g.mul(g.noise(12.0, 12.0, 4.0, 6.0, 0.65), 0.5), g.mul(grit, 0.5))
    color = g.ramp(
        tone, [(0.3, (0.27, 0.21, 0.15)), (0.5, (0.4, 0.33, 0.24)), (0.7, (0.5, 0.43, 0.32))]
    )
    color = g.mix(color, (0.16, 0.12, 0.09), g.add(g.mul(damp, 0.5), g.mul(cracks, 0.06)))
    stone = g.ramp(
        g.add(grit, g.mul(cells, 0.5)), [(0.2, (0.62, 0.6, 0.55)), (0.8, (0.4, 0.38, 0.35))]
    )
    color = g.mix(color, stone, pebble)
    return color, g.add(g.mul(grit, 0.002), g.mul(pebble, 0.01), g.mul(cracks, -0.002))


def soil(g: Graph) -> tuple[Socket, Value]:
    """Tilled earth: furrows along u, dark and crumbly, clods on the ridges."""
    furrow = g.wave(g.add(g.v, g.mul(g.noise(3.0, 3.0, 1.0), 0.03)), 6.0)
    clods = g.cells(50.0, 50.0, 2.0)
    clod = g.sub(1.0, g.band(clods, 0.15, 0.3))
    tone = g.add(g.mul(furrow, 0.15), g.mul(g.noise(80.0, 80.0, 3.0, 5.0), 0.5), g.mul(clod, 0.2))
    color = g.ramp(tone, [(0.2, (0.08, 0.06, 0.04)), (0.5, (0.18, 0.13, 0.09)), (0.8, (0.3, 0.23, 0.16))])
    return color, g.add(g.mul(furrow, 0.03), g.mul(clod, 0.01))


def leaf(g: Graph) -> tuple[Socket, Value]:
    """Corn leaf, veins along v and a midrib at u 0.5; light so the instance colour tints it.

    Mapped by UV: u across the leaf (0 to 1), v along it."""
    veins = g.wave(g.u, 24.0)
    midrib = g.sub(1.0, g.band(g.math("ABSOLUTE", g.sub(g.u, 0.5)), 0.0, 0.05))
    blotch = g.noise(3.0, 12.0, 1.0, 6.0, 0.6)
    dry = g.band(g.noise(4.0, 20.0, 2.0, 7.0, 0.6), 0.68, 0.75)
    base = g.ramp(g.add(blotch, g.mul(veins, 0.05)), [(0.3, (0.7, 0.75, 0.6)), (0.7, (0.92, 0.95, 0.82))])
    color = g.mix(base, (0.98, 0.95, 0.75), midrib)
    color = g.mix(color, (0.7, 0.55, 0.3), g.mul(dry, 0.7))
    return color, g.add(g.mul(veins, 0.0004), g.mul(midrib, 0.001))


def bark(g: Graph) -> tuple[Socket, Value]:
    """Pine bark: tall plates split by deep, dark cracks, grey-brown and flaking."""
    plates = g.cells(9.0, 2.5, 1.0, feature="DISTANCE_TO_EDGE")
    crack = g.band(plates, 0.0, 0.08)
    flake = g.noise(30.0, 10.0, 2.0, 6.0, 0.6)
    tone = g.add(g.mul(flake, 0.7), g.mul(g.cells(9.0, 2.5, 1.0, output="Color"), 0.3))
    outer = g.ramp(tone, [(0.3, (0.2, 0.16, 0.13)), (0.7, (0.38, 0.32, 0.27))])
    inner = g.ramp(flake, [(0.3, (0.05, 0.035, 0.03)), (0.7, (0.16, 0.08, 0.05))])
    color = g.mix(inner, outer, crack)
    return color, g.add(g.mul(crack, 0.025), g.mul(flake, 0.004))


def needles(g: Graph) -> tuple[Socket, Value]:
    """Pine boughs from a distance: dark needle clumps in crossing streaks."""
    a = g.noise(3.0, 70.0, 0.0, 5.0, 0.6, a=g.lin(1, 1), b=g.lin(1, -1))
    b = g.noise(3.0, 70.0, 1.0, 5.0, 0.6, a=g.lin(1, -1), b=g.lin(1, 1))
    clumps = g.noise(8.0, 8.0, 2.0, 4.0, 0.5)
    tone = g.add(g.math("MAXIMUM", a, b), g.mul(clumps, 0.4), -0.2)
    color = g.ramp(tone, [(0.25, (0.02, 0.04, 0.03)), (0.5, (0.07, 0.13, 0.08)), (0.8, (0.15, 0.24, 0.13))])
    return color, g.mul(tone, 0.01)


def denim(g: Graph) -> tuple[Socket, Value]:
    """Twill weave and faded wear; pale so Godot tints each farmer's overalls."""
    twill = g.wave(g.lin(1, 1), 60.0)
    fibre = g.noise(4.0, 120.0, 0.0, 5.0, 0.6)
    worn = g.noise(3.0, 3.0, 1.0, 5.0, 0.6)
    tone = g.add(g.mul(twill, 0.06), g.mul(fibre, 0.3), g.mul(worn, 0.35))
    color = g.ramp(tone, [(0.25, (0.55, 0.58, 0.64)), (0.55, (0.8, 0.82, 0.86)), (0.85, (0.95, 0.95, 0.96))])
    return color, g.add(g.mul(twill, 0.0003), g.mul(fibre, 0.0002))


def flannel(g: Graph) -> tuple[Socket, Value]:
    """Red plaid flannel: dark bands both ways and a thin yellow line, soft weave."""

    def bands(at: Socket) -> tuple[Socket, Socket]:
        wide = g.band(g.wave(at, 2.0), 0.3, 0.35)
        thin = g.band(g.math("ABSOLUTE", g.sub(g.fract(at, 2.0), 0.75)), 0.0, 0.015)
        return wide, g.sub(1.0, thin)

    wide_u, thin_u = bands(g.u)
    wide_v, thin_v = bands(g.v)
    weave = g.wave(g.lin(1, 1), 80.0)
    dark = g.add(wide_u, wide_v)
    color = g.ramp(g.mul(dark, 0.5), [(0.0, (0.62, 0.12, 0.1)), (0.5, (0.32, 0.06, 0.06)), (1.0, (0.1, 0.05, 0.05))])
    color = g.mix(color, (0.75, 0.62, 0.25), g.mul(g.math("MAXIMUM", thin_u, thin_v), 0.8))
    color = g.mix(color, (0.0, 0.0, 0.0), g.mul(g.add(weave, 1.0), 0.05))
    return color, g.mul(weave, 0.0002)


def skin(g: Graph) -> tuple[Socket, Value]:
    """Weathered skin: pores and blotches; tan, tinted per farmer if wanted."""
    pores = g.cells(90.0, 90.0, 0.0)
    blotch = g.noise(6.0, 6.0, 1.0, 5.0, 0.6)
    color = g.ramp(blotch, [(0.3, (0.62, 0.45, 0.36)), (0.7, (0.78, 0.6, 0.48))])
    color = g.mix(color, (0.6, 0.35, 0.3), g.mul(g.band(g.noise(3.0, 3.0, 2.0), 0.5, 0.8), 0.25))
    return color, g.mul(g.band(pores, 0.0, 0.08), 0.0002)


def leather(g: Graph) -> tuple[Socket, Value]:
    """Worn brown leather: pebbled grain and paler scuffs."""
    grain = g.cells(70.0, 70.0, 0.0, feature="DISTANCE_TO_EDGE")
    scuff = g.band(g.noise(5.0, 5.0, 1.0, 6.0, 0.6), 0.6, 0.75)
    base = g.ramp(g.noise(8.0, 8.0, 2.0, 4.0), [(0.3, (0.2, 0.12, 0.07)), (0.7, (0.32, 0.2, 0.12))])
    color = g.mix(base, (0.45, 0.33, 0.24), g.mul(scuff, 0.6))
    color = g.mix((0.12, 0.07, 0.04), color, g.band(grain, 0.0, 0.05))
    return color, g.mul(g.band(grain, 0.0, 0.05), 0.0004)


def straw_weave(g: Graph) -> tuple[Socket, Value]:
    """A woven straw hat: strands over and under in a checker."""
    over = g.math("GREATER_THAN", g.mul(g.wave(g.u, 8.0), g.wave(g.v, 8.0)), 0.0)
    strand_u = g.add(g.mul(g.wave(g.v, 32.0), 0.5), 0.5)
    strand_v = g.add(g.mul(g.wave(g.u, 32.0), 0.5), 0.5)
    lift = g.add(g.mul(over, strand_u), g.mul(g.sub(1.0, over), strand_v))
    fibre = g.noise(40.0, 40.0, 0.0, 5.0)
    color = g.ramp(
        g.add(g.mul(lift, 0.5), g.mul(fibre, 0.4)),
        [(0.2, (0.45, 0.35, 0.18)), (0.6, (0.78, 0.66, 0.4)), (0.9, (0.9, 0.82, 0.58))],
    )
    return color, g.mul(lift, 0.0006)


def hide(g: Graph) -> tuple[Socket, Value]:
    """The creature's skin: dark, leathery, creased, with veins under it and a wet sheen."""
    creases = g.cells(14.0, 22.0, 0.0, feature="DISTANCE_TO_EDGE")
    crease = g.sub(1.0, g.band(creases, 0.0, 0.05))
    wrinkle = g.noise(60.0, 25.0, 1.0, 7.0, 0.65, 0.6)
    vein = g.sub(1.0, g.band(g.math("ABSOLUTE", g.sub(g.noise(4.0, 6.0, 2.0, 3.0, 0.5, 1.5), 0.5)), 0.0, 0.015))
    base = g.ramp(
        g.add(g.mul(g.noise(5.0, 5.0, 3.0, 5.0), 0.7), g.mul(wrinkle, 0.3)),
        [(0.3, (0.05, 0.045, 0.045)), (0.6, (0.11, 0.095, 0.09)), (0.85, (0.17, 0.14, 0.13))],
    )
    color = g.mix(base, (0.16, 0.06, 0.08), g.mul(vein, 0.55))
    color = g.mix(color, (0.02, 0.015, 0.015), g.mul(crease, 0.7))
    height = g.add(g.mul(wrinkle, 0.001), g.mul(crease, -0.0015), g.mul(vein, 0.0006))
    return color, height


def bone(g: Graph) -> tuple[Socket, Value]:
    """Yellowed bone and teeth, stained in the cracks."""
    cracks = g.sub(1.0, g.band(g.math("ABSOLUTE", g.sub(g.noise(3.0, 6.0, 1.0, 4.0, 0.5, 2.0), 0.5)), 0.0, 0.01))
    color = g.ramp(g.noise(8.0, 8.0, 2.0, 5.0), [(0.3, (0.55, 0.5, 0.38)), (0.7, (0.78, 0.73, 0.6))])
    color = g.mix(color, (0.25, 0.18, 0.1), g.mul(cracks, 0.8))
    return color, g.mul(cracks, -0.0003)


TEXTURES: dict[str, Recipe] = {
    "planks_red": (planks(12, (0.42, 0.11, 0.08)), 2.4, 0.85, 0.0, "triplanar"),
    "planks_white": (planks(12, (0.85, 0.83, 0.78), gaps=False), 2.4, 0.8, 0.0, "triplanar"),
    "planks_grey": (planks(10, None), 2.0, 0.9, 0.0, "triplanar"),
    "wood": (wood, 1.0, 0.8, 0.0, "triplanar"),
    "roof_tin": (roof_tin, 2.0, 0.55, 0.4, "triplanar"),
    "metal_paint": (metal_paint, 1.0, 0.5, 0.2, "triplanar"),
    "iron": (iron, 0.5, 0.65, 0.5, "triplanar"),
    "hay": (hay, 1.0, 0.95, 0.0, "triplanar"),
    "grass": (grass, 3.0, 0.95, 0.0, "triplanar"),
    "dirt": (dirt, 3.0, 0.95, 0.0, "triplanar"),
    "soil": (soil, 2.0, 1.0, 0.0, "triplanar"),
    "leaf": (leaf, 1.0, 0.75, 0.0, "uv"),
    "bark": (bark, 1.5, 0.95, 0.0, "triplanar"),
    "needles": (needles, 1.0, 0.9, 0.0, "triplanar"),
    "denim": (denim, 0.25, 0.9, 0.0, "triplanar"),
    "flannel": (flannel, 0.3, 0.9, 0.0, "triplanar"),
    "skin": (skin, 0.15, 0.6, 0.0, "triplanar"),
    "leather": (leather, 0.3, 0.7, 0.0, "triplanar"),
    "straw_weave": (straw_weave, 0.12, 0.85, 0.0, "triplanar"),
    "hide": (hide, 0.5, 0.4, 0.0, "triplanar"),
    "bone": (bone, 0.2, 0.55, 0.0, "triplanar"),
}


def _scene() -> bpy.types.Scene:
    scene = bpy.context.scene
    assert scene is not None
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 4  # Some antialiasing; the graphs have no lighting to sample.
    scene.render.bake.margin = 0
    scene.render.image_settings.quality = QUALITY
    scene.view_settings.view_transform = "Standard"
    return scene


def _plane() -> bpy.types.Object:
    bpy.ops.mesh.primitive_plane_add(size=1.0)
    obj = bpy.context.active_object
    assert obj is not None
    return obj


def _bake(obj: bpy.types.Object, graph: Graph, kind: str, path: Path) -> None:
    image = bpy.data.images.new(path.stem, SIZE, SIZE, alpha=False, float_buffer=False)
    if kind == "NORMAL":
        image.colorspace_settings.name = "Non-Color"
    target = graph.node("ShaderNodeTexImage")
    target.image = image
    graph.tree.nodes.active = target
    bpy.ops.object.bake(type=kind, normal_space="TANGENT", margin=0)
    image.filepath_raw = str(path)
    image.file_format = "JPEG"
    quality = QUALITY
    image.save(quality=quality)
    while path.stat().st_size > MAX_BYTES and quality > 50:  # Noisy maps compress worst.
        quality -= 6
        image.save(quality=quality)
    graph.tree.nodes.remove(target)
    bpy.data.images.remove(image)


def main(names: set[str]) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _scene()
    OUT.mkdir(parents=True, exist_ok=True)
    catalogue_path = OUT / "textures.json"
    catalogue = json.loads(catalogue_path.read_text()) if catalogue_path.exists() else {}
    obj = _plane()
    for name, (build, size, roughness, metal, mapping) in TEXTURES.items():
        if names and name not in names:
            continue
        graph = Graph(name, size)
        color, height = build(graph)
        mesh = obj.data
        assert isinstance(mesh, bpy.types.Mesh)
        mesh.materials.clear()
        mesh.materials.append(graph.material)
        output = graph.node("ShaderNodeOutputMaterial")
        emit = graph.node("ShaderNodeEmission")
        graph.link(color, emit.inputs["Color"])
        graph.link(emit.outputs[0], output.inputs["Surface"])
        _bake(obj, graph, "EMIT", OUT / f"{name}.jpg")
        bump = graph.node("ShaderNodeBump")
        graph.feed(bump.inputs["Height"], graph.mul(height, 1.0 / size) if not isinstance(height, float) else 0.0)
        bump.inputs["Distance"].default_value = 1.0  # type: ignore[attr-defined]
        shader = graph.node("ShaderNodeBsdfPrincipled")
        graph.link(bump.outputs[0], shader.inputs["Normal"])
        graph.link(shader.outputs[0], output.inputs["Surface"])
        _bake(obj, graph, "NORMAL", OUT / f"{name}_n.jpg")
        catalogue[name] = {"size": size, "roughness": roughness, "metal": metal, "mapping": mapping}
        print(f"texture {name}")
    catalogue_path.write_bytes((json.dumps(catalogue, indent="\t", sort_keys=True) + "\n").encode())
