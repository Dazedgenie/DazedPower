# Dazed Utilities: Power  (v0.3.2, Build 42)

Solar, wind, pedal, steam and gas power for Project Zomboid, in one mod, re-graded and extended.
Needs **Dazed Utilities: Core** (`DazedCore`), loaded first. Works with
*Dazed Utilities: Plumbing*: generators and boilers burn and drink from its tanks, the pump and purifier wire to a
controller. Derived from the original *Off-Grid: Solar Power* by cakcan (CC BY-NC-SA 4.0; see `NOTICE.md`).

- **Mod ID:** `DazedPower` · **Load order:** `DazedCore`, then `DazedPower` (and `DazedPlumbing` either side)
- **Every name is new**, so worlds saved with other power mods will not carry over. Start a new world.

## What is in it

Every part is **Makeshift / Salvaged / Workshop** (controllers and lamps: Makeshift / Workshop). Makeshift and
Salvaged builds are taught by the *Dazed Power Handbook*, Workshop builds by *Workshop Power Systems*; the
Makeshift lamps, the windsock and the weather vane need no book. Anything over 30 kg comes apart into parts to carry.

| Part | Notes |
|---|---|
| Solar array | One square, faces E/S/W/N; snow, dust and wear as before. |
| Tracking array | Turns to follow the sun through the day (the sprite follows): 8 / 12 / 15% more energy than standing still; the Workshop one tips itself to shed snow. |
| Large solar array | Four arrays on one 2x2 frame; one cable for the lot; must stand in the open. |
| Battery bank, wall battery | The cell system: floor racks hold 3 / 6 / 8 car batteries, wall boxes 2 / 3 / 4. |
| Charge controller | Makeshift manages **8** parts, Workshop **24** (and harvests 10% more). The controller is a real generator to the engine, silent. |
| Transformer | Carries power across town and wires buildings (the Building Picker, from the core). |
| Solar lamps | Garden and street, each Makeshift or Workshop: the Workshop ones last 20 hours a night and light a wider pool; the Makeshift ones go out before dawn in winter. |
| Pedal generator, windmill, steam engine, propane and petrol generators | Parts of the one registry; their watts enter the controller directly and the monitor's SOURCE page splits them. Gear kits and the amplifier as before. |
| Windsock, weather vane | Read the wind; never wired. |
| Wall power gauge | Hangs on a wall; cable it to any part of a system. Its lamp shows the charge band, and Read Gauge (or a click) opens that system's monitor, read only. Takes no controller slot. |

**Wiring.** A cable costs Electric Wire by length: one per 4 tiles by default (sandbox *Tiles per Electric Wire*,
0 = free), and cutting it gives half of what it cost back (cables from found rigs, or run while cables were free, give nothing). Running or cutting a cable while the controller is switched on can burn
your hand: the chance grows with the system's load and falls with Electricity skill (sandbox *Shock when wiring a
live system*). Switch the controller off first and it is safe.

**Generators on the monitor.** The GEN page runs the propane and petrol generators cabled to a controller: a master
AUTO, the battery levels they start and stop at, and each engine's own AUTO and ON/OFF, with fuel, burn, hours left
and condition. Makeshift engines are pull-cord: no AUTO, and they are started by hand.

**Electricians** start knowing every Makeshift build.

**Found rigs** come in all three grades (about 65% Makeshift, 28% Salvaged, 7% Workshop); better ones sometimes
have a tracking array, and Workshop rigs a Workshop controller.

Not included: the roof (flat) panel mount, the converted vanilla "backup" generator (the gas generators
replace it), the Turkish translation.

## Test in game (0.3.0)

Charge a battery on the bench and from a parked car (also on a dedicated server: the car action passes the vehicle
itself); set priorities and watch Low go first; wear a cell and read the ceiling; place a wheel beside a river and
on dry land; a thunderstorm with and without a rod (StormRate 400 to hurry it); a Makeshift bank charged hard in a
shut room for the hydrogen warning; the presets.

## Console lines to check

```
DazedCore: ready -- 1.1.1, heavy parts v3, 1 power provider, N loads, mods: DazedPower 0.3.2, ...
DazedPower: ready -- 644/644 tiles, 64/64 items
```

## Tools

- `tools/dp_taxonomy.py` is the one description of every kind, mount, tier and state; `DP_Parts.lua` mirrors it.
- `tools/build_sheet.py` builds the tiledef, the texture pack, the part items, the icons and the Moveables/ItemName
  keys from it. Art: `tools/art/<sprite index>.png` (128x256) when present, else the old sheets in `tools/art/src`
  as stand-ins (only the power sources still use them).
- `tools/blender/dp_render.py` renders every new part in Blender (Cycles, 2x, the Dazed Power / Plumbing rig): paste
  `ART = r"<folder>"; FAMILIES = ["all"]; exec(open(ART + r"\dp_render.py").read())` into Blender's Python console.
  Families: arrays, trackers, xl, banks, walls, controllers, transformer, lamps, icons (or `preview`). The 2x2
  array renders whole and writes a `_m.png` mask per piece.
- `tools/import_art.py <dp_out folder>` cuts the 2x2 pieces by their masks, shrinks the renders to 128x256 (icons
  to 32x32) into `tools/art`, then runs `build_sheet.py`.
- `tools/build_recipes.py` writes the recipes, the handbooks and the misc items.
- `tools/tests/load_test.lua` loads every file on a stand-in engine and runs smoke checks:
  `cd tools/tests && lua load_test.lua` (expects `DazedCore` checked out beside this folder).

## Changes

- **0.3.2.** Fix: the Large Solar Array (all grades) placed as a single tile. The engine builds a 2x2 grid only when
  each GroupName + CustomName has one tile per grid square per facing, and the clear, snow and cracked states shared
  one group, so the grid was thrown out. Snow and cracked now have their own groups (`Dazed Power Snow`,
  `Dazed Power Cracked`), with the same display name. Needs DazedCore 1.1.1, which lets a 2x2 part carried as heavy
  parts be placed. Placing a Dazed Power part now writes one `DazedPower: place ... -> placed / NOT placed` line to
  the console, so a part that won't go down can be traced.

- **0.3.1.** Fix: nothing from Dazed Power could be placed. The engine takes at most 512 tiles per tileset and the
  sheet had 644, so it refused the whole tiledef (`0/644 tiles` in the console). The sheet now spills onto a second
  tileset, `dazedpower_02` (indices 512 and up); sprite names go through `P.spriteName` / `P.indexOf`. Also fixed:
  the tracker tooltips' bare `%` (a formatter warning every hover) and a missing loot list (ToolStoreGardening).
  Clean break: parts placed under 0.3.0 never existed, so nothing to migrate.

- **0.3.0.** The roadmap's remaining code. All new art is stand-in until a Blender pass.
  - **Battery ageing.** Charge cycles wear each cell for good (a worn cell shows a ceiling line under its health bar;
    swap it out). The wear travels with the battery item. Sandbox `AgeRate`.
  - **Load priority.** Right-click a controller > Load Priority: Essential / Normal / Low per wired machine kind.
    Low is cut first as the bank drains, then Normal; Essential runs to the low-voltage disconnect.
  - **Sandbox presets** (DazedCore's `Preset`: Custom, Easy, Standard, Realistic, Hardcore) move this mod's options
    together; Custom leaves your own values alone. Plumbing's wrench, main reach and main flow follow it too.
  - **Charger bench** and **vehicle charging.** Wire a bench to a controller and charge loose car and small batteries;
    right-click a car with a wired node within 10 tiles to charge its battery from the system's racks (above the
    discharge floor, 85% efficient).
  - **Micro-hydro wheel.** A steady source beside water: 350 W at full condition, slowed by ice, a little extra in rain.
  - **Lightning.** A thunderstorm can trip a system's isolator (reset it as usual); rarely a strike with no rod
    damages the controller. A **grounding rod** within 6 tiles of the controller takes the strike instead.
    Sandbox `StormRate`.
  - **Hydrogen.** A Makeshift bank charging hard in a closed room builds gas: a warning first (open a window), a fire
    only if ignored. Sandbox `HydrogenRisk`.
  - **World seeding.** Salvaged wind turbines turn up in farm storage and garden stores, worn steam engines in
    carpentry stock, petrol generators at garages and gas stations, grounding rods in electrical stock.
  - Removed the dead backup-generator code and its strings. Tests: 137 checks.

- **0.2.2.** The wall power gauge has its Blender art (all four charge bands, four facings) and icon in place of the stand-in.
- **0.2.1.** Branding pass: every leftover Off-Grid and More Power name, string, comment and internal field is now Dazed (`rec.dpm`, `dpmRows`, ...); the handbook is the *Dazed Power Handbook*. Credit to the original author stays in `NOTICE.md` and here.
- **0.2.0.** The rest of the v1 list. Cables cost Electric Wire by length, half back on a cut. Wiring a live system
  can shock (never lethal). Electricians know the Makeshift builds. New Wall Power Gauge (stand-in art until the
  Blender pass). The GEN page now runs the propane and petrol generators. Found rigs come in all three grades.
  Saved data carries a schema version (DazedCore.Migrate) so later releases can change it without a clean break.
  Fixed: the monitor counted generator watts twice in its net figure. Removed the stale backup-generator sandbox
  options. Tests: 74 checks.
- **0.1.1.** Real art: fresh Blender renders for every new part (400 world sprites: static, tracking and 2x2 arrays
  in all three grades with snow and cracked states, floor and wall banks at every fill, controllers, transformer,
  garden and street lamps on and off) and 24 new inventory icons. No code or save changes.
- **0.1.0.** First build: the two predecessor mods merged, renamed and re-graded; one 608-sprite sheet
  (stand-in art); tracking arrays, 2x2 arrays, controller part limits, two-grade lamps; the core's picker, heavy
  parts, notes, options page, report and power registry; the fuel-line adapters renamed `dazedpower_*`. Untested in
  game.
