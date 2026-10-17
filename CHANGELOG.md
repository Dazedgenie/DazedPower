# Changelog

## 0.13.0 (2026-10-17)
- Effects: **every generator shows it is running**, like the steam engine since 0.12.0. Near you (25 tiles) and on screen:
  - **Wood gas:** the gasifier's ash door opens on flickering flames and the exhaust smoke climbs while it makes power; while it warms up, the door shows glowing embers. At night a warm orange light that widens with its load, and a dim red glow while it warms.
  - **Petrol:** the engine shakes on its mounts and a thin puff of exhaust rises. No light.
  - **Propane:** a small blue flame flickers at the exhaust with a faint heat shimmer above it, no smoke, and a faint blue glow at night.
- Off, broken or out of range, they keep their still sprites. Visual only, on your own computer: nothing is sent or saved, and the steam engine works exactly as before. At most 8 effect lights at once across every generator.
- The sandbox option **Machine effects** now covers every generator (off: plain sprites, no lights).
- Art: 132 new sprites (wood gas: four flame frames and an embers frame; petrol: three running frames; propane: three flame frames; each for every grade and facing), Blender-rendered in the house style and appended on a new page; the existing pages and sprite ids are unchanged.
- Coded and tested headless; not yet run in game.

## 0.12.0 (2026-10-17)
- Effects: **steam engines show their fire.** Near you (25 tiles) and on screen, a running steam engine opens its firebox door on flickering flames and its chimney smoke climbs; an idle one (batteries full, raising steam, or its fuel just ran out) shows banked embers. At night the engine lights its square with a warm glow that widens with its load, and a dim red one while it idles. Visual only, on your own computer: nothing is sent or saved, and engines far away or off screen cost nothing.
- New sandbox option **Machine effects** (on). Turn it off on a slow computer; the plain sprites come back and every light goes.
- Art: 60 new sprites (four flame frames and an embers frame for each grade and facing), Blender-rendered in the house style and appended on a new page; the existing pages and sprite ids are unchanged.
- This is a pilot: the other generators keep their still sprites for now. Coded and tested headless; not yet run in game.

## 0.11.1 (2026-10-17)
- Art: the **Zombie Treadwheel** gets real Blender sprites in place of the stand-ins, in all four facings. An open slatted drum on two iron-shod wooden hoops rides on four rollers on a timber base, with guide posts, a car alternator belted to the back roller and a tether post at the front corner. Empty, the rope hangs slack off the post; with a zombie in it, a grey-green, blood-stained zombie strides inside with its arms out, roped by the waist to the post.
- Art: a new icon for the **Treadmill Generator** (a gym treadmill with an alternator and leads; it used the treadwheel's icon) and a refreshed Zombie Treadwheel icon.
- Tools: `tools/build_sheet.py --replace <first>-<last> [--icons ...]` re-packs only the named sprites and icons and leaves the rest of the pack byte for byte; `tools/import_art.py` passes its extra arguments through to it. The treadwheel now needs its rendered cells (`tools/blender/dz2.py dp:treadwheel`); the drawn stand-in is gone.

## 0.11.0 (2026-10-17)
- New source: the **Treadmill Generator**. The gym treadmill ("Human Hamster Wheel", the tileset recreational_sports_01) becomes a power source: wire it to a controller like any source, then right-click it and **Walk**, **Run** or **Sprint** on the treadmill. You stand on the belt and the watts last only as long as you do. The output is a pedal rider's own (50 W at Fitness 0 to 150 W at Fitness 10) times 1 for a walk, 2 for a run and 3.5 for a sprint, scaled by its condition and the new sandbox option **Treadmill output** (default 100%). Everything tires you; a sprint also spends Endurance and drops to a run when you are winded (below 15%), and cannot be started when you are. One person at a time. It shows on the board as Treadmill, with its gait.
- Build it from the Dazed Power Handbook (Electricity 3, Metal Welding 2): 4 Metal Pipe, 2 Sheet Metal, 4 Electronics Scrap, 2 Electric Wire, 8 Screws and a Rubber Hose, with a blowtorch and a screwdriver. The item places vanilla's own treadmill tile, so every treadmill already in the world can be wired too. A treadmill nobody wired or used carries nothing of ours.
- New sandbox option **Treadmill output** (TreadmillWatts, 10 to 400, default 100).
- Walking, running and sprinting use the game's own Bob_Walk, Bob_Run and Bob_Sprint, held on the belt. Coded and tested headless; not yet run in game or on a dedicated server (which way the user faces on each of the four treadmills is the first thing to check).

## 0.10.0 (2026-10-17)
- New source: the **Zombie Treadwheel** (Dazed Power Handbook, Electricity 2, Carpentry 3). Knock a zombie down, right-click it with a Rope or Sheet Rope and **Tie up the zombie** before it gets up. Walk it home on the rope: it follows, is pulled along when the rope goes taut (never through a wall, fence or closed door) and does not attack while tied. Running with the rope taut can snap it, a sheet rope sooner, and a zombie held back 8 tiles always breaks free; a snapped rope, or **Let go of the rope**, frees it and it comes for you. Within 3 tiles of a wheel, **Put the zombie on the treadwheel**: it walks for ever, 80 W (a crawler 40%), 140 W while anyone stands within 8 tiles, scaled by the wheel's condition. From the wheel, **Release the zombie** (loose and hostile) or **Put the zombie down** (a corpse, and your rope back). A wheel with a zombie in it cannot be picked up. Wire it like any source; it shows on the board as Treadwheel.
- New sandbox option **Treadwheel rope can snap** (on; off in the Easy preset).
- Review fixes: a missing tied zombie is searched for once a second per leash (not every frame), a leash whose owner went offline is swept on the server, a zombie already on a rope cannot be tied again or loaded by someone else, and a client clears its own tie flags on a zombie it no longer owns.
- Stand-in art until the Blender pass. Coded and tested headless; not yet run in game or on a dedicated server.

## 0.9.0 (2026-10-17)
- Needs Dazed Core 1.9.0. Internal only, nothing changes in play: the world right-click menu, the fence zap check and the machine sweep now run on Core's shared Menu and Tick hooks, Power's guarded-call, text, count and world-clock helpers are Core's, and Power reports its Core requirement at boot (an older Core is named in the console).

## 0.8.8 (2026-10-17)
- With Dazed Salvage installed, the pedal and wind generator recipes accept a stripped car Alternator in place of one electronics scrap, and Copper Wire in place of the wire. Without Salvage nothing changes.

## 0.8.7 (2026-10-17)
- A hooked-up car whose alternator was stripped (Dazed Salvage marks the Engine part) gives no power; a salvaged one gives power in proportion to its condition. Works without Salvage installed.

## 0.8.6 (2026-10-17)
- Internal: Power's client requests (connect, disconnect, pedal heartbeat, Electrician grant and the rest) now travel through Dazed Core's Net layer instead of raw client commands. The pedal heartbeat is rate limited per player. No change to how anything plays.

## 0.8.5 (2026-10-16)
- New: Dazed Dank gear (0.57+) can be a Power load through Dazed Core 1.8.4. Cabled grow lights, fans, pumps, heaters, ACs and humidifiers are billed on the LOADS page (GROW LIGHTS, FANS, HYDRO PUMPS, GROW CLIMATE), listed in Load Priority and cut by priority, LVD, trip or offline. Loads registered as slotless take no controller slot (Dank's do); they still cable to a controller or transformer.
- Fixed: the Load Priority menu on a client missed load kinds from other mods (Dank, Plumbing's fuel pump and well) until the player had right-clicked one of their machines. Load kinds are now filed at boot and game start.
- Changed: the wire verdict handed to Core is now three-way (fed, cut, not wired). Core's wired() treats cut and not wired alike, so Plumbing is unchanged.

## 0.8.4 (2026-10-16)
- Battery racks take add-on batteries that are not car batteries. A cell now counts for its type's weight (Model.registerCellWeight, default 1), so a smaller or bigger battery takes its relative share of the rack (a makeshift cell is a third of a car battery). The rack keeps the battery's fill fraction and relative size, not an exact Wh figure; the printed Wh only holds in a salvaged-tier rack. The weight is saved on each cell, and a cell whose item type vanished is never swapped for a car battery. Wear and equalisation use the cells' summed weights. Dazed Power: Electric Vehicles registers its makeshift and deep-cycle batteries. Existing racks are unchanged.

## 0.8.3 (2026-10-16)
- New: the monitor board (and the wall gauge) shows a time-left estimate beside NET: "~6.4 h left" until the bank hits its red line when draining, "full in ~2 h" when charging, from the current net watts.

## 0.8.2 (2026-10-14)
- Fixed: the wood gas generator's "Clean out the ash" option lost its percentage. A lone % in a translation string breaks the game's text formatting; the ash, warm-up and status texts now use %% like the rest. The status line also reads "ash 45% full" instead of "45 full".

## 0.8.1 (2026-10-12)
- Fixed: hooked-up cars threw "tried to call nil" whenever a vehicle loaded. B42's cell vehicle list is a HashSet with no get(i); the alternator now walks it with its iterator.

## 0.8.0
- Wood gas generator: warm-up, ash, hopper feeding, menus, GEN page and recipes.
