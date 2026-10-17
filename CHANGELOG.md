# Changelog

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
