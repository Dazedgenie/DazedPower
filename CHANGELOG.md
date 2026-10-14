# Changelog

## 0.8.2 (2026-10-14)
- Fixed: the wood gas generator's "Clean out the ash" option lost its percentage. A lone % in a translation string breaks the game's text formatting; the ash, warm-up and status texts now use %% like the rest. The status line also reads "ash 45% full" instead of "45 full".

## 0.8.1 (2026-10-12)
- Fixed: hooked-up cars threw "tried to call nil" whenever a vehicle loaded. B42's cell vehicle list is a HashSet with no get(i); the alternator now walks it with its iterator.

## 0.8.0
- Wood gas generator: warm-up, ash, hopper feeding, menus, GEN page and recipes.
