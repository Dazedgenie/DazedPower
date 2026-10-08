# Dazed Utilities: Power  (v0.5.0, Build 42)

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
| Electric fence | A solid fence section; cable it to any part of a system (no controller slot). While the system is on and above its discharge floor, a zombie beside it is knocked down and stunned, 5 Wh a zap, 3 s apart per zombie. People are not hurt. Sandbox *Electric fence hurts zombies*. |
| Room cooler | Hangs on a wall inside a room; cabled like the fence. While powered, food in every container of that room (not fridges) keeps like it does in a fridge. 100 W plus 10 W per container, Normal priority. |

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
DazedCore: ready -- 1.2.0, heavy parts v3, 1 power provider, N loads, mods: DazedPower 0.4.0, ...
DazedPower: ready -- 660/660 tiles, 66/66 items
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
- `tools/make_depth.py` writes the depth maps (`common/media/depthmaps`) from the packed sheet; run it after
  `build_sheet.py` whenever the art changes.
- `tools/wind_frames.py` draws stand-in windmill spin frames from the still renders; the real ones come from Blender:
  `blender -b --factory-startup -P tools/blender/dz2.py -- <out> dp:windspin`, then
  `python tools/import_art.py <out>/dp` and `python tools/make_depth.py`.
- `tools/blender/dp_pedal.py` builds the seated pedalling animation (plain Python with numpy, or in Blender for a
  preview); `tools/blender/dp_pullstart.py` the pull-start one.
- `tools/tests/load_test.lua` loads every file on a stand-in engine and runs smoke checks:
  `cd tools/tests && lua load_test.lua` (expects `DazedCore` checked out beside this folder).

## Changes

- **0.6.0 (animation).**
  - **Windmills spin.** A turning windmill walks through four blade positions on your screen, faster in stronger
    wind; past 15 m/s at the rotor the blades blur. A broken rotor rocks on its bearing in a breeze. Cosmetic and
    local only: the server still sends the plain sprite. Untick **Animate windmills** on the Dazed Utilities options
    page to turn it off. The frames are stand-ins drawn from the still renders until the Blender pass.
  - **Riding the pedal generators.** The rider sits on the saddle facing forward, hands on the bars, and pedals; the
    gear sets the cadence (Low slower, Racing faster). Getting off puts you back where you stood. Untick **Ride pedal
    generators** to pedal from beside the machine as before.
  - **Depth maps** for every Dazed Power tile, so players show correctly in front of and behind the machines
    (Build 42 treated a modded tile without one as a solid block filling its square).
  - The sprite pack is rebuilt from the new-style art in `tools/art`; later commits had put the old sheet back.
  - Generator pull-cord starts have their own crouch-and-yank animation (added before this release).

- **0.5.1 (fixes).**
  - The charge board loads again: its drawing is split into sections, because the game's Lua stops compiling a function that declares more than 200 local variables (the board had 258).
  - Restored what the board merge dropped: the GEN page's run button rolls for a cold start again, COLD shows on the board, and the heater and cold-start text strings are back.
  - The cold-start sandbox tooltip no longer trips the game's text formatter (a bare % sign).
  - The system monitor opens again. Opening it threw "tried to call nil in open": the board rewrite had dropped a small scaling helper the window still used to place itself.
  - The dial needles turn inside their dials again. They were drawn at the top left of the screen instead of on the board, wherever the window was.
  - The main isolator's ON/OFF no longer overlaps the breaker line under it.
  - SOURCES IN scrolls with the mouse wheel when there are more sources than fit, instead of ending in "+3 more". A thin bar on the right shows where you are; click above or below its middle to step a row.
  - The generator arrows on the board wrap from the first generator back to the last, instead of landing on an empty slot. Wind bearings below zero wrap round the compass, so a resolved wind calibration can't give a wind with no direction. (The game's Lua keeps the sign on a negative remainder.)
  - CIRCUITS scrolls the same way, and TOTAL stays in one place above the main isolator however many circuits there are (a long list used to push it down into the switch). The controller now sends up to 40 circuits instead of 9 before folding the rest into "+N more".

- **0.5.0.**
  - **Analog charge board** replaces the OG-1200 face. One board shows everything at once, with no pages:
    - two dials, SOURCES IN (every source) and LOAD OUT, whose ranges grow to fit what they read
    - NET on number wheels
    - the battery column with its floor in red, and the bank's cells, amber for a worn cell
    - the status lamps
    - today's history on chart paper
    - the SOURCES IN list (what used to be the SOURCE page) and the circuits list with its total
    - the main isolator switch
  - **Generator card:** its MASTER (the old master AUTO), AUTO and ON switches and the START BELOW / STOP ABOVE wheels
    with - and +. Two or more generators page with < and >.
  - Locks, read-only wall gauges and the switch-in-flight hold work as before.
  - The main isolator is a big red flip switch: up is on, down is off.
  - The art is Blender renders (`tools/blender/board_render.py`): dials, needle, battery case, toggles, number wheels, the
    isolator switch and the lamps. Tests: `tools/tests/board_test.lua`.

- **0.4.0.** Needs DazedCore 1.2.0.
  - **Admin tools:** an Admin submenu on controllers (staff, or single-player debug): Inspect system, Repair whole
    system, Reset system, Fill batteries. A `DazedPower: stats -- ...` server console line every 10 in-game minutes.
  - **Car alternator:** right-click a parked car near a wired part, *Hook alternator to Dazed Power*; while its engine
    runs it feeds the system (up to 500 W, less with a worn engine). It unhooks itself if the car drives off.
  - **Fix:** items made before 0.3.1 (whose tile moved to `dazedpower_02`) showed in the inventory but the Place cursor
    found nothing to place. They are healed on their own within a minute of joining.
  - **Dazed Dank:** default load priorities for its hydro pumps (Essential), grow lights (Normal) and drying fans (Low).
  - **Electric fence** (Workshop Power Systems, Electricity 3, Welding 2). A zombie on or beside a live
    section is knocked down and stunned, with a little damage (sandbox `FenceDamage`), 5 Wh from the racks a zap.
    5 W standing draw on the LOADS page; its menu shows On/Off with the reason and today's zaps.
  - **Room cooler** (Workshop Power Systems, Electricity 4). Every container in its room keeps food like a fridge
    while the system is powered; 100 W + 10 W per container, billed like Plumbing's wired machines and cut by Load
    Priority. Outside a room it does nothing and its menu says so.
  - Stand-in art for both. Tests: `tools/tests/fence_cooler_test.lua`.
  - Performance: the per-frame fumes check keeps each controller's object instead of walking its square every frame.
  - Performance: one climate read and one vehicle index serve every controller in a minute's tick; a charger reads the
    weather once, not once per rack.
  - Performance: hydrogen only looks for open windows around a Makeshift rack charging hard, and keeps the answer for
    5 in-game minutes; its counters are kept per controller, so pruning no longer walks every rack in the world.
  - Performance: sprite names decode once (`P.indexOf` remembers), describing an object no longer creates empty
    ModData on it, the fence check makes no tables while no zombie is near, and the client sound scan makes no
    substrings. Tests: new `tools/tests/perf_test.lua`.

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
