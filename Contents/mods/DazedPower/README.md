# Dazed Power  (v0.15.0, Build 42)

Solar, wind, pedal, steam and gas power for Project Zomboid, in one mod, re-graded and extended.
Needs **Dazed Core 1.9.0 or newer** (`DazedCore`), loaded first. Works with
*Dazed Plumbing*: generators and boilers burn and drink from its tanks, the pump and purifier wire to a
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
| Electric fence | A solid fence section; cable it to any part of a system (no controller slot). While the system is on and above its discharge floor, a zombie beside it is knocked down and stunned, 5 Wh a zap, 3 s apart per zombie. People are not hurt. |
| Room cooler | Hangs on a wall inside a room; cabled like the fence. While powered, food in every container of that room (not fridges) keeps like it does in a fridge. 100 W plus 10 W per container, Normal priority. Dazed Climate's cold-storage rule is the unpowered cousin: in a room below 15 C (no cooler needed) ordinary containers (not fridges or freezers) age food slower, about 30% speed at 0-4 C like a fridge and almost not at all when frozen, back to normal at 15 C. A powered Power cooler owns its room and Climate checks for it and leaves that room alone, because both work by rewinding each item's age and must never both run on one container. Any other room-wide food system (a cellar, an ice house) must register with the same check Climate uses. |
| Zombie treadwheel | The **Large Zombie Treadwheel** (0.18.0): 2x2 squares, its drum tall enough for a grown zombie; one grade (Dazed Power Handbook, Electricity 2, Carpentry 3; 14 planks, 24 nails, 2 metal pipes). Wheels of the old one-square kind already standing keep working and can be scrapped, but are no longer built. Knock a zombie down, right-click it with a Rope or Sheet Rope, **Tie up the zombie** (about 3 s; it fails if it gets up first). Walk it home: it follows on the rope, is pulled along when the rope goes taut, never through a wall or fence, and does not attack while tied. Running or sprinting with the rope taut can snap it (a sheet rope sooner), a zombie held back 8 tiles always breaks free, and a snapped rope or **Let go of the rope** frees it to come for you (sandbox *Treadwheel rope can snap*). Within 3 tiles of a wheel, **Put the zombie on the treadwheel**: the zombie stays in the drum, walking in place for ever (0.17.0; kill it and the wheel is empty; sandbox *Real zombie on the treadwheel* off: it leaves the world and the wheel shows a painted one), 80 W (a crawler 40%), 140 W while anyone stands within 8 tiles, scaled by the wheel's condition; the slats wear 0.03 points an hour and are repaired like the water wheel. **Release the zombie** lets it out beside the wheel, hostile; **Put the zombie down** leaves a corpse and gives the rope back. A wheel with a zombie in it cannot be picked up. Blender art (0.11.1): the empty wheel, and a grey-green zombie walking it. |
| Treadmill generator | The vanilla gym treadmill (W 28+29, N 30+31, E 36+37, S 38+39 of `recreational_sports_01`), wired like any source; the item (Dazed Power Handbook, Electricity 3, Metal Welding 2) puts down that tile. Right-click it: **Walk**, **Run** or **Sprint on the treadmill**. A pedal rider's watts (50 W at Fitness 0, 150 W at 10) times 1, 2 or 3.5, scaled by condition and the sandbox *Treadmill output*. Costs Fatigue every game minute (0.20, 0.35, 0.50 points); a sprint also spends 0.02 Endurance a minute and drops to a run below 0.15. One user at a time. Our data is made only when it is first wired or used. |
| Electric space heater | Stands on the floor; cabled like the fence and switched on from its menu. Draws 1500 W while it runs, Low priority by default. With Dazed Climate it warms its room. Dazed Power Handbook, Electricity 3. |
| Box fan | Stands on the floor; cabled and switched like the heater (0.19.0). Draws 60 W while it runs, Low priority by default. With Dazed Climate it pushes a hot room's air out (-4, in a room at 24 C or more that is warmer than outside). Dazed Power Handbook, Electricity 2. |

**Wiring.** A cable costs Electric Wire by length: one per 4 tiles by default (sandbox *Tiles per Electric Wire*,
0 = free), and cutting it gives half of what it cost back (cables from found rigs, or run while cables were free, give nothing). Running or cutting a cable while the controller is switched on can burn
your hand: the chance grows with the system's load and falls with Electricity skill (sandbox *Shock when wiring a
live system*). Switch the controller off first and it is safe.

**The monitor.** **System monitor** opens one analog charge board: SOURCES IN and LOAD OUT dials, NET, the battery
column, BANK, RECEIVED TODAY, CIRCUITS and the MAIN ISOLATOR. Its generator card runs the propane and petrol
generators cabled to the controller: MASTER, each engine's AUTO and ON, and the START BELOW / STOP ABOVE levels, with
fuel, burn, hours left and condition. Makeshift engines are pull-cord: no AUTO, and they are started by hand.

**Electricians** start knowing every Makeshift build.

**Found rigs** come in all three grades (about 65% Makeshift, 28% Salvaged, 7% Workshop); better ones sometimes
have a tracking array, and Workshop rigs a Workshop controller.

Not included: the roof (flat) panel mount, the converted vanilla "backup" generator (the gas generators
replace it), the Turkish translation.

## Test in game (0.15.0, work animations)

Built and checked headless only: `tools/blender/dp_work.py` writes the clips, `dp_xcheck.py` checks them against the
pedal clip, `dp_clipsheet.py` draws them on the Bob mesh, `anim_test.lua` checks the hookup. Nobody has seen these
clips in the game yet, so the first job is that nothing breaks. With a screwdriver, scrap and screws, a damaged part,
a pedal gear set, a heater, a charging bench, a controller and cable: **repair** a damaged array and an added machine
(crouched tinkering, screwdriver in the right hand), **fit a gear set** (tinkering, empty hands or whatever you hold),
open the **generator controller's panel** (tinkering), flip a **heater switch**, **charge** a battery and **reset a
breaker** (the press: reach, press, let go), **run and cut a cable** (squatting, hand over hand), and **read the sky**
(head back, hand shading the eyes). For each: no T-pose, no hands-up "default" pose, no sliding or sinking feet,
faces the machine, loops without a jump, and the action finishes and does its job. Watch the screwdriver: does it sit
in the palm and point sensibly? Then untick **Work animations** (options, Dazed Core page) and every one of these goes
back to the 0.14.0 looting animation (ExamineVehicle for the sky). With a skirt or dress on, laying cable: the hem
stays off the floor. Multiplayer: a second player sees the same animations.

## Test in game (0.19.0, the box fan)

Console at start: `DazedPower: ready -- 1060/1060 tiles`. Build **Box Fan** from the handbook, place it in all four
facings: blades show while off, a blur while on. Cable it to a controller, **Switch on**: it lights only while the system
has power and shows FAN on the LOADS page (60 W) and in Load Priority. With Dazed Climate, on a hot day in a closed room
the room's temperature should creep down toward 24 C at night (when outside is cooler) and not move while it is hotter outside.

## Test in game (0.18.0, the large 2x2 treadwheel)

Coded and tested headless only (`tools/tests/tread_test.lua`, `load_test.lua`); the art is rendered and packed. Console at
start: `DazedPower: ready -- 1052/1052 tiles`. Build **Large Zombie Treadwheel** from the handbook recipe (it replaces the
one-square build; the recipe keeps its name, so a handbook already read still teaches it). Place it in all four facings,
indoors and out: four squares, one wheel, no gaps or seams between its squares, the item comes back as one when lifted.
Tie a zombie and **Put the zombie on the treadwheel** from any of its squares: the zombie stands in the middle of the big
drum, head and shoulders inside the rim, facing the wheel's front, walking in place; the drum stays still (no stride
frames on the large wheel). Walk round it: no square of it can be lifted while the zombie is in it. **Release** it: it
steps out on a free square beside the wheel, never inside it. Sandbox *Real zombie on the treadwheel* off: the painted
zombie shows on the large wheel too. An old one-square wheel in a save still works as before.

## Test in game (0.14.0, turning machines: windmill, water wheel, treadwheel, windsock)

Coded and tested headless only (`tools/tests/turnfx_test.lua`; `anim_test.lua` checks the windmill shows exactly what it
did before, frame for frame); the art is rendered and packed. Console at start: `DazedPower: ready -- 1020/1020 tiles`.
In game, all four facings: a turning **water wheel** within 25 tiles and on screen is drawn sharp (not the blur) with its
paddles going round, water tipping off the chute and spray below, top of the wheel moving away from the chute side; a
still one is plain. A **treadwheel** with a zombie in it: the zombie's legs stride and the slats roll back under its
feet, faster while you stand within 8 tiles (lured); an empty wheel is plain. A **windsock** at half or full swings
side to side (faster when full), a limp one hangs still, and it still turns to follow the wind. **Windmills** spin
with the wind as before (blur in a gale, a broken rotor rocks) but now freeze while single player is paused and stop
off screen; both the sandbox *Machine effects* and the client tick box *Animate windmills* turn them off. Machine
effects off: every plain sprite back within a second. Tick stats: still only `DazedPower.steamfx` (1 s) and
`DazedPower.steamfxFrames` (40 ms while something with its own speed turns on screen, else 150 ms), and neither when
no machine is near; the old per-frame windmill tick is gone. FPS with several turning machines on screen against the
option off. Is the water wheel's turn readable at game zoom (it is the smallest motion of the four)?

## Test in game (0.13.0, generator effects: wood gas, petrol, propane)

Coded and tested headless only (`tools/tests/genfx_test.lua`, and `steamfx_test.lua` still passes unchanged); the art is
rendered and packed. Console at start: `DazedPower: ready -- 976/976 tiles`. In game, check each grade in all four facings:
a running wood gas generator opens its ash door on flickering flames (the door faces the front; from behind only the
smoke and the light show) and its exhaust smoke climbs without a jump at the loop, a warming one shows embers; a running
petrol generator shakes slightly and puffs thin exhaust, with no light; a running propane generator shows a small blue
flame at its exhaust and a faint shimmer, no smoke, and a faint blue glow at night. Off, broken, out of range or the
sandbox *Machine effects* off: plain sprites and no light. With steam and gas engines together at night, never more
than 8 effect lights; picking one up takes its light away at once. FPS with five of each running on screen against the
option off.

## Test in game (0.12.0, steam engine effects, a pilot)

Coded and tested headless only (`tools/tests/steamfx_test.lua`); the art is rendered and packed. In game, check: a running
steam engine within 25 tiles opens its firebox and the flames flicker (E and S facings show the mouth; W and N only the
smoke and the light, the firebox is on the far side), the chimney smoke climbs without a jump at the loop; an idle
governed engine (batteries full), one raising steam or one whose fuel ran out shows banked embers; at night the square
gets a warm light that widens with load, and a dim red one for embers; picking the engine up, breaking it or walking
out of range takes the light away at once (no light left floating); the sandbox *Machine effects* off puts the plain
sprites back and removes every light; the FPS with five running engines on screen against the option off; single
player pause freezes the flames; on a dedicated server, that the client's frames do not fight the server's sprite.

## Test in game (0.11.0, the treadmill generator)

Coded and tested headless only (`tools/tests/treadmill_test.lua`). In game, check: the console line `DazedPower: treadmill tiles present`
(the vanilla tiles are named as expected); all four facings, from either tile, offer Walk, Run and Sprint and wire to a
controller; the user stands on the middle of the two tiles and faces along the belt (`T.RUN_DIR` in `DP_Treadmill.lua` swaps
the facing if they run backwards); Bob_Walk, Bob_Run and Bob_Sprint play and are held in place (the bone weights are the
pedal's); watts show on the board as Treadmill with the gait; a sprint drops to a run when Endurance falls below 15%;
changing gait while on it does not step the user off; a second player is refused and the rows grey; picking the treadmill
up or turning it with the vanilla move tool while wired unwires it cleanly; on a dedicated server, that the beats reach the
server (the watts follow the user's Fitness there) and stop when the user walks off.

## Test in game (0.10.0, the zombie treadwheel)

Coded and tested headless only (`tools/tests/tread_test.lua`). In game, check: a shoved zombie and a fence-zapped one
can be tied before they stand; a tied zombie walks after you rather than sliding (if it only slides, B42 does not path
"useless" zombies and the pull is doing all the work); it never bites while tied; it does not come through a wall,
fence or closed door; running snaps the rope; loading removes it for every player; release and put down spawn the
right outfit; and on a dedicated server, that the zombie owner's client moves it and the server can remove and spawn.

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
- `tools/blender/dp_pedal.py` builds the seated pedalling animations (one per tier) (plain Python with numpy, or in Blender for a
  preview); `tools/blender/dp_pullstart.py` the pull-start one.
- `tools/blender/dp_work.py` builds the work clips (tinker, press, run cable, read sky) and their AnimSet nodes, plain
  Python with numpy: `python3 tools/blender/dp_work.py`. It takes the skeleton and mesh from `Bob_SquatLoop.X` when
  `PZ_ANIMS` points at the game's `anims_X/Bob`, otherwise from the mod's own pull-start clip (same header). Check with
  `python3 tools/blender/dp_xcheck.py <Bob_DazedPedalSalvaged.X> <clips...>` (header, bones, keys, loop) and look at
  `python3 tools/blender/dp_clipsheet.py <out.png> <clips...> [--box x0,x1,z0,z1,h] [--frames N] [--big]` (contact
  sheet on the skinned Bob mesh, no Blender needed).
- `tools/tests/load_test.lua` (at the repo root, outside the uploaded mod) loads every file on a stand-in engine and
  runs smoke checks: `sh tools/tests/run_all.sh [<DazedCore lua root>]` from the repo root. The default core is the
  sibling `dazedcore` repo (`../dazedcore/Contents/mods/DazedCore/common/media/lua`); `DAZEDCORE_LUA` also sets it.

## Changes

- **0.15.0 (work animations).** New `DP_Anim` (shared): `A.play(action, clip, how)` sets the clip's AnimSet node
  (`tinker` DazedTinker, `press` DazedPress, `cable` DazedRunCable, `sky` DazedReadSky) and otherwise the vanilla
  animation `how` describes (`anim`, default Loot; `position` for LootPosition; `event` for EventLootItem), the same
  as each action did before; the fallback also covers the client tick box `WorkAnims` being off and a throwing
  setter. `A.screwdriver` / `A.hold` put the carried screwdriver in the right hand for the two repairs. Users:
  DPM_InstallGear, DPM_Repair, DP_RepairArray, DP_GenPanelAction (tinker); DP_HeaterSwitch, DP_ChargeAction,
  DP_ResetBreaker (press); DP_RunCable (cable); DP_ReadSky (sky). Clips from `tools/blender/dp_work.py`: the
  pull-start crouch (its frame 0) re-posed with two-bone IK, feet kept planted; Prop1/Prop2 follow the hands at the
  standing rest pose's hand-to-prop offset; every clip loops (last key = first).
- **0.14.0 (turning machines).** `DP_MachineFx` learned looks picked from more than the state (`spec.modeOf`), several
  cycling looks per kind (`spec.cycles`), a speed per machine (`spec.rate`, frames a second; its phase only advances
  while the game runs, at most `MAX_DT` a step; the frame job runs every `FAST_MS` = 40 ms while such a cycle is on
  screen) and a kind's own switch (`spec.enabled`); a culled machine still on a frame is restored when the option
  goes off, and a frame job follows the server's facing flip at once. `DP_WindSpin` (its own per-frame `OnTick` and a
  5 s square sweep since 0.4) is now a registration on it: W.pick and W.fps unchanged, and the registered look is
  checked against W.pick in 672 cases. New `DP_TurnFx`: water wheel (`hydrospin` spin1..spin3, 10 degrees a frame of
  its 30 degree paddle pitch, 8 fps scaled down to half by condition), treadwheel (`treadspin` walk1..walk4: four
  stride poses, the slats a quarter pitch a frame, 4 fps, x1.5 lured, x0.5 crawler), windsock (`windsockflap`
  half1/half2/full1/full2, cycled plain, 1, plain, 2 at 3 or 6 fps). `DPM_Machines` now also lists windsocks. Sprite
  alias kinds `hydrospin` (rows 244-246, `dazedpower_02_464` to `_475`), `treadspin` (247-250, `_476` to `_491`),
  `windsockflap` (251-254, `_492` to `_507`): 44 tiles, tileset 02 now 508 of 512. Rendered by `tools/blender/dz2.py
  dp:hydrospin,treadspin,windsockflap` (`hydro_frame`, `treadwheel_part(frame=)` with `zombie_walker(stride=)`, and
  `SOCK_FLAP` in `dz_render.build_windsock`), appended with `import_art.py ... --append`. Tests: `turnfx_test.lua`.
- **0.13.0 (generator effects).** The steam pilot's tracking, cull, lights, pause, cleanup and option moved into a shared
  `DP_MachineFx` (client only) that every kind registers with (`M.register`: its looks per state, its frame cycle, its
  one-frame looks, its light); `DP_SteamFx` is now a thin registration that keeps its 0.12.0 calls, and `DP_GenFx`
  registers wood gas (four fire frames while running, embers while warming, a warm light by `genWatts` against the
  grade's rating, radius 3 to 5), petrol (three shake-and-exhaust frames while running, no light) and propane (three
  blue-flame frames while running, a faint blue radius-2 light). Still the same two Dazed Core Tick jobs
  (`DazedPower.steamfx`, `DazedPower.steamfxFrames`) and one cap of 8 lights across every kind. New sprite-only alias
  kinds `woodgasfire` (rows 211-225, `dazedpower_02_332` to `_391`), `petrolrun` (rows 226-234, `_392` to `_427`) and
  `propaneflame` (rows 235-243, `_428` to `_463`): 132 tiles, so tileset 02 now holds 464 of its 512. Rendered by
  `tools/blender/dz2.py dp:woodgasfire,petrolrun,propaneflame` (the `WG_FRAME` hook on the gasifier's ash door in
  `dz2.py`, the `GAS_FRAME` hook on `build_gas` in `dz_render.py`), appended with `build_sheet.py --append`.
  Tests: `tools/tests/genfx_test.lua`.
- **0.12.0 (steam engine effects, the pilot for machine effects).** `DP_SteamFx` (client only): a running steam engine
  near a local player and on screen cycles four fire frames (the firebox door open on flames, the chimney smoke
  climbing) and an idle one shows banked embers, with a warm `IsoLightSource` on its square at night (radius 3, 5 or 7
  by load band, a dim radius-2 glow for embers). The frames are a sprite-only alias kind, `steamfire` (rows 196-210,
  `dazedpower_02_272` to `_331`, appended with `build_sheet.py --append`), that reads back as the steam engine in the
  state it shows, exactly like the windmill's `windspin`. Rendered by `tools/blender/dz2.py dp:steamfire` (the
  `STEAM_FRAME` hook in `dz_render.py`'s firebox and a looping `puffs(phase=)`). Two Dazed Core Tick jobs, each
  present only while it has work: `DazedPower.steamfx` (1 s: cull, look, lights) and `DazedPower.steamfxFrames`
  (150 ms: one sprite swap per running engine on screen). New sandbox option *Machine effects* (MachineEffects, on).
  Tests: `tools/tests/steamfx_test.lua`.
- **0.11.0.** The player treadmill generator: the vanilla gym treadmill recognised by sprite name through guarded wraps
  of `P.describe`, `P.master`, `P.piecesAround` and `P.itemFor` (`DP_Treadmill`), with no new sheet rows and nothing wrapped
  on `P.spriteInfo`. Output model in `DPM_Model` (`treadmillOutput`, gait table), the timed action in `DP_TreadmillAction`
  (`DPM_Treadmill`, modelled on `DPM_Pedal`), rows in `DP_TreadmillMenu`, Endurance helpers in `DPM_Stats`. The bridge folds
  treadmill watts into `pedalW` and lists them on the board. Animation nodes `DazedTreadmill{Walk,Run,Sprint}`. New sandbox
  option TreadmillWatts. Tests: `tools/tests/treadmill_test.lua`.
- **0.19.0.** The box fan: kind `fan` (ground, standard, off/on), a LATE row after the large treadwheel so nothing
  moves: `dazedpower_03_28` to `dazedpower_03_35`. A switched appliance like the heater (`A.SWITCHED`), 60 W, priority 3;
  its Dazed Climate object source is `A.fanHeat` (`A.fanEffect`: -4 when the room is >= 24 C and 1 C warmer than outside,
  read from `Rooms.roomTemp` and `outdoorNow`). Rendered by `tools/blender/dz2.py dp:fan` (`fan_part`).
- **0.18.0.** The large treadwheel: mount `xl` of `treadwheel`, four pieces like the XL array, its rows APPENDED after
  every older row (`dp_taxonomy.LATE`, mirrored as `P.LATE`) so nothing already in a save moves: `dazedpower_02_508` to
  `dazedpower_03_27`. Rendered by `tools/blender/dz2.py dp:treadxl` (`treadwheel_xl_part`, drum radius 1.0 with the zombie
  at k=1.2). `MakeDazedTreadwheel` now outputs `DazedTreadwheelLarge`; the one-square wheel is scrap-only
  (`build_recipes.make(name=False)`). `T.spot`, `T.wheelAt`, `T.occupant` and `T.freeBeside` resolve a wheel's master and
  its footprint; DPM_Machines tracks only masters and DP_MachineFx gives 2x2 parts no frames.
- **0.10.0.** The zombie treadwheel (see the parts table): a new part, `treadwheel`, appended to the sheet on a new
  page (`dazedpower_02_264` to `_271`), Blender-rendered since 0.11.1 (`tools/blender/dz2.py dp:treadwheel`). The rope and wheel live in `DP_Tread` (rules, leash
  registry, authority commands, the follow loop), `DP_TreadActions` (tying) and `DP_TreadMenu` (rows); the bridge
  counts the wheel like the water wheel. New sandbox option *Treadwheel rope can snap* (TreadRopeSnap, off on Easy).
  Tests: `tools/tests/tread_test.lua`.

- **0.8.0 (wood gas generator).** A new generator in three grades (Makeshift, Salvaged, Workshop) that runs an engine on gas from smouldering wood, the wartime farm kind. Feed its hopper logs, planks, branches or charcoal from the right-click menu, counted in fire-hours like the steam engine. From cold it needs a while to warm up (30, 21 or 15 minutes by grade) before it makes power, and every fire-hour burned leaves ash: when the grate is full it stalls until you **Clean out the ash** with it stopped. The Salvaged and Workshop grades take AUTO from the GEN page like the other engines. 700, 1600 and 3000 W; it fumes indoors like any engine. Built and scrapped from the handbooks (Makeshift and Salvaged basic, Workshop advanced). Stand-in sprites until its Blender renders land.
- **0.7.5 (battery rack debug spawn).** With Dazed Core 1.6.1, **Dazed debug > Spawn every battery rack fill level around me** puts down every floor rack from empty to full in each grade, all facing south, then a full Workshop rack in each facing. They are real racks holding healthy car batteries, for checking the art and Dazed Viewpoint's 3D models.
- **0.7.4 (debug spawn).** With Dazed Core 1.5.0, in debug mode or as an admin or moderator, right-click the ground and choose **Dazed debug > Spawn all Dazed Power items around me**: one of every part in every tier is placed in a ring of open squares around you, and the handbooks, almanac, gear kits and amplifier go into your inventory, as does any part that found no room (a wall bank, gauge or cooler with no wall nearby).
- **0.7.3 (windmill sounds).** Windmills have their own sounds instead of a washing machine's churn. Makeshift and Salvaged windmills creak, clank and pump like an old farm windmill; the Workshop Wind Turbine whooshes and hums. Each spins up when it starts turning, loops while it turns, and winds down when it stops, furls or breaks. Sounds are in `media/sound`, defined in `media/scripts/sounds_DazedWindmill.txt`; `tools/audio/windmill_synth.py` regenerates them.
  - **Fix:** the loop now plays after the spin-up. It was started on the spin-up's emitter, which the game could hand back to its pool once the spin-up ended, so only the start was heard. The loop gets its own emitter, a dropped loop restarts on a fresh one, and a sound the game refuses is named once in the console.
- **0.7.2 (fewer sandbox options, 21 down to 14).** Merged or removed the options that were rarely touched. *Panel weathering* now covers snow and dust together, *Battery wear* also covers deep-discharge damage (0 = no wear at all), *Found solar gear* sets both yard rigs and barn stock, and a transformer's line is always 2.5 times the link radius. The electric fence always hurts zombies, heaters and coolers always warm rooms with Dazed Climate, and Realistic Mode (1993 panels) is now set only by the Realistic and Hardcore presets. Existing saves keep working; any value you had set for a merged or removed option falls back to its default.
- **0.7.1 (rename).** Now called **Dazed Power** in the mod list and Workshop; needs **Dazed Core** (was "Dazed Utilities: Core"). Mod ID, saves and settings unchanged. README: the monitor is described as the charge board it now is, and the electric space heater is listed.
  - **Fix:** the Micro-Hydro Wheel can be repaired (*Dazed Power -> Repair it*: electronics scrap, screws, a screwdriver; +30 condition), like the other machines. It wore down and stopped at 35 with no way back.
  - **Fix:** the Dazed Core preset for found solar rigs was backwards. Easy now puts a rig on one house in 5, Standard 15, Realistic 20, Hardcore 25.

- **0.7.0 (performance).** The same simulation, cheaper to run and to sync. Each controller is looked up once per
  minute instead of six times; the load scan keeps running totals; wiring graphs, sprite decodes, the generator range
  and text widths are remembered; fences find zombies through one list per check; source machines, panels and gauges
  only send their data when something a player can see moved; machine sounds and windmill blades track the machines
  instead of searching the squares round the player; the charge board only rebuilds when its numbers change. Catch-up
  after a long absence bills the saved household demand for all but the last hour. The test and art tools moved out of
  the uploaded mod to the repo root, and 22 unused screen images were removed.
  - **Fixes.**
    - Pedal generators make power on dedicated and hosted servers. The rider's client sends the server a heartbeat
      about once a second, and the bike stops making power a couple of seconds after the beats stop.
    - Parts in an area that unloaded are no longer kept as "ghosts". A battery bank or panel whose area unloaded
      while its controller stayed loaded makes the system relink at once, instead of charging a dead copy for up to
      half an hour. Lamps, windsocks, vanes, coolers, machine sounds and windmill blades drop ghosts the same way.
    - Single-player windmills no longer reset their blade sprite every minute, which marked each windmill's area
      for a resave.
    - Generator settings are not sent to a generator that has gone, and a petrol generator that has unloaded is no
      longer trusted for ten minutes when the mod clears a building's fumes.
- **0.6.5 (fix).** The rider's legs really no longer go behind a pedal generator. The game treated the bike as
  something hiding its rider and drew it over them in a later pass, so 0.6.4's depth map never applied. The rider now
  counts as seated on the bike (the way vanilla chairs work), so the bike draws normally and the rider shows in front.
- **0.6.4 (fix).** The rider's legs no longer go behind a pedal generator. The bike now draws as a card near
  its square's far corner, so the rider on the saddle is in front while people on the squares behind it stay behind.
- **0.6.3 (fix).** A pedal generator stays fully drawn while you ride it; the game had been fading it out like
  anything that hides the player.
- **0.6.2 (pedalling fit).** Each bike tier has its own pedalling animation, so the rider sits on that bike's
  saddle with feet on its pedals and hands on its grips. The rider used to sit low and in front of the saddle. Rebuild
  with `python tools/blender/dp_pedal.py`; GAME_SCALE and RENDER_DROP at its top were fitted from in-game screenshots.
- **0.6.1 (fix).** Getting on a pedal generator threw a Lua error and skipped the seated animation. The cadence was
  sent to the game as a number where it only accepts text; it now goes through the number setter.
- **0.6.0 (animation).**
  - **Windmills spin.** A turning windmill walks through four blade positions on your screen, faster in stronger
    wind; past 15 m/s at the rotor the blades blur. A broken rotor rocks on its bearing in a breeze. Cosmetic and
    local only: the server still sends the plain sprite. Untick **Animate windmills** on the Dazed Core options
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
  - **Dazed Dank:** grow lights, fans, climate gear (heater, AC, humidifiers) and hydro pumps register as loads through Dazed Core (Power 0.8.5, Core 1.8.4, Dank 0.57.0). They take no controller slots and follow load priority: pumps Essential, grow lights and climate Normal, fans Low. Dank gear that is not cabled keeps running off the square's power and is not billed.
  - **Electric fence** (Workshop Power Systems, Electricity 3, Welding 2). A zombie on or beside a live
    section is knocked down and stunned, with a little damage, 5 Wh from the racks a zap.
    5 W standing draw on the LOADS page; its menu shows On/Off with the reason and today's zaps.
  - **Room cooler** (Workshop Power Systems, Electricity 4). Every container in its room keeps food like a fridge
    while the system is powered; 100 W + 10 W per container, billed like Plumbing's wired machines and cut by Load
    Priority. Outside a room it does nothing and its menu says so.
  - Stand-in art for both.
  - Performance: the per-frame fumes check keeps each controller's object instead of walking its square every frame.
  - Performance: one climate read and one vehicle index serve every controller in a minute's tick; a charger reads the
    weather once, not once per rack.
  - Performance: hydrogen only looks for open windows around a Makeshift rack charging hard, and keeps the answer for
    5 in-game minutes; its counters are kept per controller, so pruning no longer walks every rack in the world.
  - Performance: sprite names decode once (`P.indexOf` remembers), describing an object no longer creates empty
    ModData on it, the fence check makes no tables while no zombie is near, and the client sound scan makes no
    substrings.

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
