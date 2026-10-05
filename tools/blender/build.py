"""Builds the game's textures and models in Blender, into game/assets/.

Run from the repository root (Blender is not on PATH; see docs/models.md):
    "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup \
        --python tools/blender/build.py -- [name ...]
Names pick textures or models to rebuild; with none, everything is rebuilt.
"""

import importlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
args = set(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
for module in ("textures", "models"):
    try:
        importlib.import_module(module).main(args)
    except ModuleNotFoundError as error:
        if error.name != module:
            raise
