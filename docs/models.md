# Models and textures

How the game's look is made. Python scripts drive Blender headless. They bake tileable textures and
build the models, both into `game/assets/`. Godot dresses each imported model in the textures its
material names pick (`Dress`, `game/scripts/dress.gd`). Nothing is modelled or painted by hand, so
every model and texture can be rebuilt and changed in code. The pipeline follows the Sneak
project's (`tools/blender/lib.py` is copied from it). Sneak's textures were noise generated in
Godot. Here they are made in Blender (2026-10-04).

## Building

Blender 5.2 LTS is installed to `C:\Program Files\Blender Foundation\Blender 5.2\` and is not on
PATH. From the repository root:

```bash
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/build.py
```

That bakes every texture and builds every model, in about 15 s. Add names after `--` to rebuild
only those, e.g. `-- barn hide`. Godot imports the results on its next start or
`godot --headless --import`. Commit the generated `.import` files with them.

Look at the result in Godot, which is the look that counts:

```bash
godot --path game res://tools/showcase.tscn -- --set=characters --out=shot.png
```

The sets are `characters`, `props` and `plants`; add `--close` to frame the heads. To check models
in place on the farm, use the snapshot tool (`res://tools/snapshot.tscn`, see the project
CLAUDE.md).

## Textures

`tools/blender/textures.py` holds 21 textures. Each one is a node graph over one tile, baked
to two maps:

- a colour map, `<name>.jpg`;
- a tangent-space normal map, `<name>_n.jpg`, OpenGL convention as Godot expects.

`textures.json` records each texture's tile size in metres, roughness, metal and mapping.

| Texture | Tile (m) | For |
| --- | --- | --- |
| `planks_red`, `planks_white`, `planks_grey` | 2.4, 2.4, 2 | Barn siding in peeling red, white trim, weathered shed boards |
| `wood` | 1 | Beams, posts, handles |
| `roof_tin` | 2 | Corrugated iron, galvanised and rusting |
| `metal_paint` | 1 | Chipped near-white paint, tinted per use (generator, drum, lamp shades) |
| `iron` | 0.5 | Pitted cast iron: the pump, rails, hinges |
| `hay` | 1 | Bales |
| `grass`, `dirt`, `soil` | 3, 3, 2 | The ground, the yard, the plots |
| `leaf` | 1 | Corn, by UV: veins along the leaf, a midrib |
| `bark`, `needles` | 1.5, 1 | The pines |
| `denim`, `flannel`, `skin`, `leather`, `straw_weave` | 0.12 to 0.3 | The farmer |
| `hide`, `bone` | 0.5, 0.2 | The creature |

How a texture tiles:

- **Noise wraps.** Every noise is sampled on a torus: u and v each become a circle in 4D noise
  space (`Graph._torus`), so the noise is periodic over one tile.
- **Patterns repeat a whole number of times.** Boards, ridges and weaves fit the tile exactly.
- **Board edges line up with the barn.** Siding boards are 0.2 m, and the barn and shed sit at
  multiples of 0.2 m, so the texture's board gaps meet the modelled battens.

Colours in the scripts are sRGB, as in the GDScript; the bake stores sRGB. Heights are in metres
and turned into the normal map for the tile's real size.

Maps are 1024 px JPEGs, so that each file stays under `check-added-large-files`' 500 KB limit. A
noisy normal map that would pass 480 KB is saved at lower JPEG quality (`MAX_BYTES`).

The `.import` files set mipmaps on and VRAM compression for every map, and normal-map compression
for the `_n` maps. Godot's defaults (no mipmaps, lossless) shimmered on tiled ground. Keep those
settings when adding a texture: copy an existing `.import`'s `[params]`.

## Models

`tools/blender/models.py`. Axes are Blender's: Z up, every model facing +Y, which glTF turns into
Godot's -Z (a Godot point (x, y, z) is Blender's (x, -z, y)).

| Model | What it is |
| --- | --- |
| `farmer` | Overalls over a flannel shirt with rolled sleeves, boots with laces, a straw hat; joints `leg_N`, `arm_N`, `head`. The overalls are pale and tinted each player's colour in `player.gd`. |
| `creature` | 2.5 m, hunched: digitigrade legs, ribs and spine under creased dark hide, arms to its shins, four long clawed fingers and a thumb, a long toothed skull with small pale eyes. Joints `leg_N`, `arm_N`, `head` (and `torso`), where the old primitive body had them, so `creature.gd`'s animation is unchanged. |
| `barn` | Where it stands: board-and-batten walls (red outside, grey inside), white trim, gable roof of tin over rafters, sliding doors run open on a rail, loft hatch and hay hook, four windows, posts and beams, hay stacked over Farm's hay colliders, three lamps where Farm hangs its lights. |
| `shed` | Where it stands: grey board-and-batten, a lean-to tin roof, a window, the door open flat against the front wall. |
| `generator`, `drum`, `pump`, `crate` | The props, each about its collider in `farm.gd`. |
| `corn`, `corn_far` | A stalk with ten arching leaves, a tassel and an ear, UV-mapped for `leaf`; the far one has four leaves. |
| `pine` | Trunk and twelve drooping tiers. |

The models are visual only. The colliders stay the boxes `farm.gd` always made: walls, hay,
generator, pump, crate. So the barn and shed are built exactly over `Farm.BARN` and `Farm.SHED`.
The barn's door header, roof and gables are above head height and have no colliders.

Material names pick the texture: the name up to any `+` (`metal_paint+generator`), tinted by the
material's colour. `plain+...` is a flat colour and `glow+...` emits.

## In the game

- **Ground** boxes use the textures projected in world space (`Dress.material(..., world = true)`),
  so grass tiles the same on every box.
- **Corn** is drawn in 8 m squares (`Farm.CORN_CHUNK`). A MultiMesh picks no level of detail per
  stalk, so each square has two MultiMeshes: the detailed stalk within 30 m (`Farm.CORN_NEAR`)
  and the plain one past it.
- **Corn colour** is each stalk's MultiMesh instance colour, multiplied into the pale leaf
  texture. Godot applied it only after the mesh was given white vertex colours (`Dress.mesh`); the
  glTF has none, and without them every stalk drew the texture's own pale colour. That the vertex
  colours are what made the difference was seen in two snapshots, not traced in Godot's source.
- **Performance** on an RTX 5070 at 1600 x 900, vsync off, 2026-10-04:

  | View | fps | Triangles drawn |
  | --- | --- | --- |
  | Open yard | 434 | 0.92 M |
  | Inside the corn | 358 | 1.2 M |
  | Facing the ring | 228 | 1.1 M |

  Weaker machines are untested.

## Not done yet

- Tools, traps, the pegboard and crops are still primitives from `looks.gd`.
- No animation beyond swinging joints: the farmer's walk is a leg and arm swing from its speed
  (`Player._walk_cycle`), and crouching does not show.
- Exported builds would need `textures.json` included (it is read with `FileAccess`).
