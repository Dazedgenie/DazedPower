# Changelog

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
