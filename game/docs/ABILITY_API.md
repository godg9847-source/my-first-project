# Ability API (for writing fighter abilities)

Every fighter has one ability module at
`game/src/ServerScriptService/Sim/Abilities/<FighterId>.luau`.
Abilities run inside the battle simulation (`Sim/Battle.luau`). The simulation is
**pure Luau**: no `game`, `workspace`, `Instance`, `Vector3`, `task`, `wait` or
any other Roblox API is allowed in ability code. Use `battle:after()` and
`battle:every()` for delays, and `battle:fx()` for visuals. This keeps abilities
testable outside Roblox (`game/tools/simtest`).

## Module shape

```lua
--!nonstrict
-- <Parody name> — inspired by <Character> (<Anime>)
local A = {}

-- optional: runs once when the fighter enters the arena (passives, riders, hooks)
function A.setup(battle, unit)
end

-- Ability 1 (Signature). The ENGINE decides when it fires, from the fighter's data
-- (Shared/Fighters.luau → ability1.trigger). You only write what happens.
-- ctx depends on the trigger:
--   timer     ctx = {}
--   wall      ctx = {nx, ny}            -- wall normal (points back into the arena)
--   contact   ctx = {target}            -- the enemy you just collided with
--   proximity ctx = {target}            -- the enemy that came within ability1.radius
--   charge    ctx = {}                  -- fires when the charge-up completes
--   hurt      ctx = {source, amount}    -- who hit you and for how much
function A.ability1(battle, unit, ctx)
end

-- Ability 2 (Ultimate). Fires when the player taps ULT during the 6 s window,
-- or automatically at the end of it. battle:isFocused(unit) is true if tapped
-- (the engine already adds the +10 % FOCUS bonus to damage/heal/shield).
function A.ability2(battle, unit)
end

return A
```

### Ability 1 trigger data (in data/fighters.json → ability1)
| trigger | fields | meaning |
|---|---|---|
| `"timer"` | `cooldown` (3–8) | fires every `cooldown` s |
| `"wall"` | `cooldown` = internal cooldown (2–5) | fires when this fighter bounces off a wall/pillar and the ICD is ready |
| `"contact"` | `cooldown` = ICD (1.5–5) | fires when this fighter collides with an enemy |
| `"proximity"` | `cooldown` (3–7), `radius` (6–16) | fires when an enemy is within `radius` studs (edge to edge) and ready |
| `"charge"` | `cooldown` = charge time C (2–5) | a ring fills for C s, then fires; stuns cost 50 % of the progress |
| `"hurt"` | `cooldown` = ICD (3–6) | fires when this fighter takes damage |

The first cast is possible 1.5 s after FIGHT. Stun/freeze/silence block triggering (timers keep counting).
Ability 2 gets `ability2.duration` (seconds the ultimate lasts; the meter does not charge during it).

## Coordinates

* 2D studs on the arena floor. `(0, 0)` is the centre. Walls are at `x = ±battle.halfX` and `y = ±battle.halfY` (the standard arena is 48 × 48, so both are 24; some arenas are rectangles). `battle.half` = the smaller of the two.
* Some arenas have round pillars: `battle.obstacles = {{x, y, r}, ...}`. Fighters bounce off them (that counts as a wall hit) and projectiles stop on them.
* A unit is a circle: `unit.x, unit.y, unit.radius`, moving with `unit.vx, unit.vy` (studs/second). Cruise speed is `unit.baseSpeed` (27–44).
* Team 1 starts at (0, −14), team 2 at (0, +14).

## The unit table (read freely; change only through the API unless noted)

| Field | Meaning |
|---|---|
| `unit.id`, `unit.team` (1 or 2), `unit.fighterId`, `unit.def` | identity and fighter data |
| `unit.x`, `unit.y`, `unit.vx`, `unit.vy`, `unit.radius`, `unit.baseRadius` | position / velocity / size |
| `unit.hp`, `unit.maxHp`, `unit.alive` | health |
| `unit.baseSpeed`, `unit.contactDamage`, `unit.mass` | stats (you may change `contactDamage`/`contactBonus`/`damageMult`/`damageTakenMult` temporarily, but always restore them with `battle:after`) |
| `unit.charge` (0–100), `unit.ultReady`, `unit.cd1` | meters |
| `unit.status[name]` | active status effects |
| `unit.mem` | **your own scratch table** for ability state (stacks, counters, flags) |
| `unit.isMinion`, `unit.owner` | for summoned helpers |

## Helper API (`battle:...`)

### Randomness and math
* `battle:rand()`, `battle:randRange(a, b)`, `battle:randInt(a, b)`, `battle:chance(p)`, `battle:randomDir() -> dx, dy`, `battle:randomPoint(margin) -> x, y`
* `battle.math.len(x, y)`, `battle.math.norm(x, y)`, `battle.math.rotate(x, y, degrees)`, `battle.math.clamp(v, a, b)`
* **Never** use `math.random` (it breaks replays/tests).

### Finding targets
* `battle:nearestEnemy(unit) -> target, distance` (may be nil)
* `battle:enemiesOf(unit)`, `battle:alliesOf(unit, includeSelf)`
* `battle:unitsInRadius(x, y, r, unit, "enemy"|"ally"|nil)`
* `battle:unitsOnLine(x1, y1, x2, y2, width, unit, "enemy")`
* `battle:dirTo(a, b) -> dx, dy` (unit vector), `battle:distance(a, b)`, `battle:hpPercent(unit)`
* `battle:rayToWall(x, y, dx, dy) -> wx, wy`

### Damage and healing
* `battle:damage(source, target, amount, {kind = "ability"|"contact"|"dot"|"true", silent = bool})`
* `battle:damagePercent(source, target, percentOfMaxHp)`
* `battle:heal(unit, amount)`
* `battle:kill(unit, killer)`

### Status effects — `battle:applyStatus(target, name, seconds, params)`
Use the standard values from the design framework §7.3 unless the card says otherwise.
| name | params | effect |
|---|---|---|
| `stun` | | hard CC: can't move or trigger Ability 1, no contact damage, ULT window pauses (std 0.8 s) |
| `freeze` | | hard CC: a stun that also makes the target take +15 % damage (std 0.7 s) |
| `root` | | hard CC: can't move, abilities still work (std 1.0 s) |
| `silence` | | no Ability 1 and no ULT tap (meter still charges) (std 2 s) |
| `slow` | `{amount = 0.3}` | −30 % speed (speed never drops below 50 %) |
| `haste` | `{amount = 0.3}` | +30 % speed |
| `burn` | `{dps = 20, source = unit}` | damage over time (std 20 dps × 3 s) |
| `poison` | `{dps = 10, source = unit}` | weak long DoT and −30 % healing received (std 10 dps × 6 s) |
| `bleed` | `{perHit = 12, source = unit}` | damage each time the target bounces off a wall or collides (std 12 × 5 s) |
| `shield` | `{amount = 150}` | absorbs damage (std 150 for 4 s) |
| `invuln` | | takes no damage |
| `intangible` | | passes through units and projectiles, takes no damage (ULT only, ≤ 1.5 s) |
| `empower` | `{amount = 0.25}` | +25 % damage dealt |
| `vulnerable` | `{amount = 0.2}` | +20 % damage taken (std 3 s) — use this for "Mark" |
| `lifesteal` | `{amount = 0.2}` | heals 20 % of damage dealt |
| `grow` / `giant` | `{amount = 1.4}` | 40 % bigger (giant also adds mass) |
| `reflect` | `{amount = 1.0, cap = 300}` | returns that fraction of damage taken to the attacker (Counter stances) |
| `ghost` | | passes through units (no collisions / contact damage) |
| `unstoppable` | | immune to hard CC and knockback |
| anything else | | a plain flag — check with `battle:hasStatus(u, "name")` |

Global rules the engine applies for you: **CC Guard** (after 1.5 s of hard CC in ~6 s the target is immune for 3 s), Guardians take 25 % shorter hard CC, the **healing cap** (30 % of max HP per round), **Role Edge** (+12 % damage to the roles you counter), **Heavy Hit** (contact ×1.5 when moving ≥ 1.4× cruise), **Wall Slam** (+30 damage when a knockback ≥ 80 slams the target into a wall within 0.4 s), the FOCUS bonus, Rival Pull and Overtime.

`battle:removeStatus(u, name)`, `battle:hasStatus(u, name)`, `battle:cleanse(u)`.

### Meters and special helpers
* `battle:isFocused(unit)` — true while this ultimate was tapped manually
* `battle:addCharge(unit, amount)` / `battle:drainUlt(target, amount)` — change ULT meters (drain 10–30)
* `battle:execute(source, target, percent)` — KO the target if its HP is below `percent` % (ULT only, ≤ 12)
* `battle:telegraph(x, y, radius, seconds, {color})` — ground warning circle (visual only). Required ≥ 0.5 s before any area that deals ≥ 120 damage.

### Movement
* `battle:knockback(target, dx, dy, power, source)` — power ≈ studs/second (std 70, range 40–110). Pass `source` so Wall Slams credit you.
* `battle:pull(target, x, y, power)`
* `battle:dash(unit, dx, dy, speed, seconds, {damage, knockback, status = {name, secs, params}, onHit = fn(battle, unit, target), pierce, stopOnWall})`
* `battle:teleport(unit, x, y)`
* `battle:setDirection(unit, dx, dy)`

### Spawning things
* `battle:shoot(unit, dx, dy, {speed, damage, radius, ttl, pierce, homing = target, turnRate, status, knockback, wall = "die"|"bounce", onHit = fn(battle, e, target), visual})`
* `battle:blast(unit, x, y, radius, damage, {status, knockback, color, onHit = fn(target)}) -> hitList` (instant)
* `battle:beam(unit, dx, dy, {damage, width, length, duration, tick, status, knockback, color, follow})` (instant if no duration)
* `battle:zone(unit, x, y, radius, {damage, tick, duration, status, follow = unit, hits, visual})`
* `battle:spawn(spec)` — the general version (see the comment above `Battle:spawn` for every field)
* `battle:summon(owner, {hp, size, speed, contactDamage, ttl, visual, x, y, dirX, dirY, name})` — temporary helper unit (clones, shadows, pets)
* `battle:destroy(entity)`

### Timing
* `battle:after(seconds, fn, unit)` — run later (skipped if `unit` died)
* `battle:every(interval, count, fn(i), unit, startNow)` — repeat
* `battle:hook(unit, event, fn, seconds?)` — events: `onWallHit(b, u, nx, ny)`, `onCollide(b, u, other)`, `onDamaged(b, u, amount, source)`, `onDealDamage(b, u, target, amount, kind)`, `onTick(b, u, dt)`, `onDeath(b, u, killer)` (set `u.hp > 0` inside to cancel death), `onAbility(b, u, slot)`
* `battle:setCooldown(unit, seconds)` — change time until the next Ability 1

### Visuals (no gameplay effect)
* `battle:fx(kind, data)` kinds: `burst {x, y, radius, color, duration}`, `ring {x, y, radius, color, duration}`, `line {x, y, x2, y2, width, color, duration}`, `text {x, y, text, color, size}`, `shake {power, duration}`, `flash {color, duration}`, `sound {name}`
* `battle:setVisual(unit, {aura = "#hex", scale = 1.3, color = "#hex", transparency = 0.5}, seconds)`
* Entity `visual = {shape = "ball"|"block"|"disc"|"ring"|"beam"|"cylinder"|"spike"|"none", color = "#hex", size, height, transparency, light = true, trail = true}`

Ability names appear above the fighter automatically when cast — don't add your own callout.

## Rules of thumb
1. Every number must come from the fighter's design card (`fighters/NN-id.md`); keep within the Fighter Designer Guide budgets.
0. Caps: ≤ 6 projectiles per cast, ≤ 14 live objects per fighter (the engine removes your oldest beyond that), persistent hazards live 4–10 s.
2. Use `unit.mem` for state; never globals or module-level variables (several battles run at once).
3. Anything you change temporarily (`contactDamage`, `damageMult`, statuses) must be undone with `battle:after(...)`.
4. Always check `target and target.alive` before using a target.
5. Abilities must work in 1v1 **and** 2v2 (use `nearestEnemy`, `enemiesOf`, `alliesOf`).
