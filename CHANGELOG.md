# Changelog

## 0.17.0 (2026-10-18)
- **The real zombie walks the treadwheel.** The zombie you put on a wheel no longer turns into a painted one: it stays in the world, held in the middle of the drum, facing the wheel's front and walking in place on the game's own zombie walk (a crawler crawls). It cannot bite or wander off, and the wheel makes power exactly as before. The drum shows without the painted zombie and stands still while the real one walks it.
  - Kill it (or put it down from the menu) and the wheel is empty. Release it and that same zombie is let loose beside the wheel and comes for you.
  - Across saves it is found again where it stands. If it is lost (the game dropped it while the area was unloaded), an identical one is put back in the drum after a few seconds, once someone is within 30 tiles.
  - New sandbox option **Real zombie on the treadwheel** (on). Off brings back the painted zombie of 0.10.0. Each wheel keeps the way it was loaded, so wheels already turning in a save stay painted until their zombie is released and put back.
  - Leaving the zombie inert in the world with an animation of its own is the approach *Zombie Leash & Lead* (CativeiroBR, by gadinho) uses for its prisoners.
- Lua tests cover loading, the pin, finding it after a reload, putting a lost one back, killing, release and put down; not yet run in game.

## 0.16.0 (2026-10-18)
- Fix: **a tied zombie really follows you now.** 0.15.1 never moved it in single player: the game reports every zombie as "remote" there, so the rope code thought another machine was in charge of it and left it alone (your console showed `drives`/`owned=false`). The leader's own machine now always walks it.
- **It walks on its own legs**, the way the *Zombie Leash & Lead* mod (CativeiroBR, by gadinho) does it: close to you it stands still and harmless; once you are 2 tiles off it is woken and set on you, so the game's own walking brings it along, and it is made still again before it is close enough to lunge. It never bites (no teeth) while tied. If the game does not walk it (1.5 s without moving), the rope steps it after you instead, and a taut rope still pulls it, never through walls.
- **You can see the rope.** The game only draws a rope from a player to an animal they lead, so you lead an invisible rat held at the zombie's neck, and the game's own rope runs from your hand to the zombie (the same trick Zombie Leash & Lead uses). Visual only, on your own screen; a stray rat left by a crash is cleared when you come near it.
- A snapped rope or letting go now turns the zombie on you in single player too (that was skipped for the same "remote" reason).
- Lua tests cover the walk/still switching, the stuck fallback, pause and the rope rat; not yet run in game.

## 0.15.2 (2026-10-17)
- Works with the new **Dazed Occupations** mod when it is installed (nothing changes without it):
  - **Grid Reader** (the Power Plant Operator's free trait): the charge board shows exact watts and watt-hours ("12345.6 W") instead of rounded ones ("12.3 kW").
  - **Skittish Around Wires** (negative trait): running or cutting cable on a live system is twice as likely to burn your hand, and Electricity skill no longer lowers the risk (still capped, still never lethal, still off with the *Live shock* sandbox option). Power now tells Dazed Occupations this trait has an effect, so it shows up in character creation.
- Lua tests cover both; not yet run in game.

## 0.15.1 (2026-10-17)
- Fix: **a zombie tied with a rope now follows you.** It stood where it was tied: it was left lying down, and the "useless" flag that stops it biting also stops it walking on its own, so asking it to path after you did nothing.
  - Once tied it gets up (a crawler stays a crawler and is dragged).
  - The rope now walks it: each frame it shambles toward you once you are more than 2.5 tiles away, faster the further behind it is, and stops at the rope's length. A taut rope still pulls it as before, and it is still never moved through a wall, a fence or a closed door. Nothing moves while single player is paused.
  - The console gets one line per tied zombie (`DazedPower: tread leash ...`) saying whether it was found and whether it was still down, to help if anything is still off.
- Lua tests cover the follow step, standing up, the rope length and pause; not yet run in game.

## 0.15.0 (2026-10-17)
- Animations: **machine work has its own animations** instead of the generic looting one.
  - **Tinkering** (crouched at the machine, one hand braced on it, the other turning a screwdriver at one spot and then the next): repairing a damaged part (solar arrays and every added machine), fitting a pedal gear set, and the generator controller's panel. Repairs show the screwdriver you carry in your hand.
  - **Pressing a switch** (reach, press, hold, let go): the heater switch, charging a battery, and resetting a breaker.
  - **Laying cable** (squatting, feeding the cable along the ground hand over hand): running and cutting cable.
  - **Reading the sky** (head up, a hand shading the eyes, a slow look from one side to the other) for the weather almanac.
- New client option **Work animations** (on the Dazed Core options page, on by default): untick it to go back to the game's own animations for all of these, exactly as in 0.14.0.
- Four new clips in `anims_X/Bob` (`Bob_DazedTinker`, `Bob_DazedPress`, `Bob_DazedRunCable`, `Bob_DazedReadSky`) with their AnimSet nodes, built on the vanilla Bob skeleton like the pedal and pull-start clips.
- Built and checked headless (contact sheets of every clip on the Bob mesh, a file checker, Lua tests); not yet run in game.

## 0.14.0 (2026-10-17)
- Effects: **the turning machines move.** Near you (25 tiles) and on screen:
  - **Water wheel:** while it turns, the wheel is drawn sharp instead of as a blur and its paddles go round, with water tipping off the chute and spray below. A badly worn wheel turns slower.
  - **Zombie treadwheel:** the tied zombie strides (four poses) and the drum's slats roll back under its feet. Faster while it is lured (someone within 8 tiles), slower for a crawler.
  - **Windsock:** a drooping or streaming sock swings from side to side, faster in a strong wind. A limp sock hangs still.
  - **Windmills** spin as before (speed with the wind, a blur in a gale, a broken rotor rocking), but now on the same shared effects code as the generators: they stop while single player is paused (they used to keep turning), cost nothing off screen, and follow the sandbox option *Machine effects* as well as their own *Animate windmills* tick box.
- Visual only, on your own computer: nothing is sent or saved. *Machine effects* off puts every plain sprite back.
- Art: 44 new sprites (water wheel 3 frames, treadwheel 4, windsock 4; each in four facings), Blender-rendered in the house style and appended on a new page of the existing tileset (`dazedpower_02`, now 508 of 512 tiles); the existing pages and sprite ids are unchanged.
- Coded and tested headless; not yet run in game.

## 0.13.1 (2026-10-17)
- Art: the **petrol** and **propane** running frames are stronger, so they read at game size (the 0.13.0 ones were hard to tell from the still sprite).
  - **Petrol:** the engine now visibly shakes on its mounts, 2 to 3 pixels a frame in alternating directions, while the pallet, frame or base plate stays still; two larger grey-white exhaust puffs climb from the pipe.
  - **Propane:** the burner flame is a proper flame, a blue tongue with a bright white-blue core, two to three times bigger, flickering in height and lean from frame to frame, with a slightly stronger blue glow on the ground under it.
- Only those 72 sprites were re-rendered and re-packed (`build_sheet.py --replace`); sprite ids and every other sprite are unchanged, and the depth map changes only for those sprites. Nothing in the code changes.

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
