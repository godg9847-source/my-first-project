"""Build the lobby and arena maps into Rojo model files.

    python3 tools/build_maps.py          (run from the game/ folder)

Writes src/Workspace/Lobby.model.json and src/Workspace/Arenas.model.json.
The map code lives in tools/maps/lobby.py and tools/maps/arenas.py and uses the
helpers in tools/mapgen.py. See docs/PROTOCOL.md for the names the game code needs.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "maps"))

import mapgen  # noqa: E402

GAME = os.path.dirname(HERE)
OUT = os.path.join(GAME, "src", "Workspace")


def main():
    only = sys.argv[1:] or ["lobby", "arenas"]
    if "lobby" in only:
        import lobby
        m = lobby.build()
        path = mapgen.save(m, os.path.join(OUT, "Lobby.model.json"))
        print(f"lobby: {mapgen.count_parts(m)} parts -> {os.path.relpath(path, GAME)}")
    if "arenas" in only:
        import arenas
        m = arenas.build()
        path = mapgen.save(m, os.path.join(OUT, "Arenas.model.json"))
        print(f"arenas: {mapgen.count_parts(m)} parts -> {os.path.relpath(path, GAME)}")


if __name__ == "__main__":
    main()
