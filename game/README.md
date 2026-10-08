# Anime vs Anime — Roblox game files

An auto-battler inspired by the Roblox hit **Ball VS Ball**: pick an anime fighter, aim it, and watch it bounce around the arena and fight — then hit **ULT** at the perfect moment. 30 fighters, 2 abilities each.

The full design (research on Ball VS Ball, every system, every fighter) is in
[`../docs/Anime-vs-Anime-Design.md`](../docs/Anime-vs-Anime-Design.md).

---

## 1. Open the game in Roblox Studio (easiest way)

1. Download **`AnimeVsAnime.rbxlx`** from this folder (on GitHub: click the file → **Download raw file**).
2. Double-click it (or open Roblox Studio → **File → Open from File…** and pick it).
3. Press **Play** (F5). Walk to the **Training Dojo** (west side of the island) and step on a **Practice** pad, or press **QUICK MATCH**.

> **Saving progress in Studio:** go to **Home → Game Settings → Security** and turn on **Enable Studio Access to API Services** (you must publish the place first: **File → Publish to Roblox**). Without it the game still works, it just doesn't save coins/fighters between test sessions.

## 2. Testing with 2 players

In Studio: **Test** tab → **Clients and Servers** → choose **2 Players** → **Start**. Two windows open; step both players on the same 1v1 pad.

## 3. Before you publish

| What | Where |
|---|---|
| Your group id (for the group reward and +5 % coins) | `src/ReplicatedStorage/Shared/Config.luau` → `Config.GroupId` |
| Game pass ids (VIP, 2x Coins, …) | `Config.GamePasses.*.id` — create them in the Creator Dashboard first |
| Gem pack / Starter Pack ids | `Config.Products.*.id` |
| Codes | `Config.Codes` (add a new `UPDx` code with every update) |
| Featured shrine fighters | `Config.Banners` → `featured` |

While an id is `0`, its button says "Coming soon!" — nothing breaks.

**Names:** every fighter, ability and map uses an original *parody* name (e.g. "Rubber Pirate"). Real anime names only appear in comments and in the design document as inspiration. Keep it that way in anything players can see (titles, thumbnails, descriptions) to avoid takedowns. Consider making this repository **private** if you publish the game.

---

## 4. How the project is organised

```
game/
  AnimeVsAnime.rbxlx          ← the built place file (open this in Studio)
  default.project.json        ← Rojo project (how files map into Roblox)
  data/fighters.json          ← all 30 fighters: stats, looks, ability names/triggers
  src/
    ReplicatedStorage/Shared/ ← Config, Fighters (generated), Remotes
    ServerScriptService/
      Main.server.luau        ← starts every service
      Server/                 ← Data, Queue, Match, Shop, Rewards, Leaderboards, Lobby,
                                Renderer (draws fights), FighterModel (chibi fighter builder)
      Sim/                    ← the fight simulation (pure Luau, no Roblox APIs)
        Battle.luau           ← physics, damage, statuses, triggers, ultimates, overtime
        Abilities/<id>.luau   ← each fighter's 2 abilities
        Arenas/<gimmick>.luau ← waves, portals, cannons, puddles
    StarterPlayerScripts/Client/ ← all UI and the match camera (built from code)
    Workspace/                ← Lobby.model.json + Arenas.model.json (generated maps)
  tools/
    build_maps.py, maps/      ← the lobby + arenas, written in Python
    build_fighters.py         ← data/fighters.json → Shared/Fighters.luau
    simtest/                  ← runs thousands of fights outside Roblox (bug + balance tests)
  docs/
    PROTOCOL.md               ← server ↔ client messages and map naming rules
    ABILITY_API.md            ← how to write a fighter's abilities
```

## 5. Editing the game

### Option A — edit in Studio (simple)
Open the `.rbxlx`, change scripts/parts, **File → Save**. (Your Studio changes won't flow back into these text files.)

### Option B — edit the text files and sync with Rojo (recommended)
1. Install Rojo: the **Rojo** VS Code extension, or `cargo install rojo` / Aftman / Rokit.
2. Install the Rojo **Studio plugin** (from the extension, or `rojo plugin install`).
3. In this `game/` folder run `rojo serve`, then in Studio open the **Rojo** plugin → **Connect**.
4. Edit files — Studio updates live. To rebuild the place file: `rojo build -o AnimeVsAnime.rbxlx`.

### Regenerating data and maps
```bash
python3 tools/build_fighters.py   # after editing data/fighters.json
python3 tools/build_maps.py       # after editing tools/maps/*.py
rojo build -o AnimeVsAnime.rbxlx
```

### Testing fights without Roblox
```bash
cd tools/simtest && cargo build --release && cd ../..
./tools/simtest/target/release/simtest src tools/simtest/tests/engine_features.luau
./tools/simtest/target/release/simtest src tools/simtest/tests/roster.luau all 20      # win rates
./tools/simtest/target/release/simtest src tools/simtest/tests/roster.luau goku 30     # one fighter
```

---

## 6. What's in v0.1 and what's next

See **Part 5** of the design document for the full checklist of what is built and what is planned
(Ranked, trading, Clash TV predictions, highlight replays, cosmetics, Hero Path, …).
