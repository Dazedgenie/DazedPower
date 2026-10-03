# Notice of modification

Dazed Utilities: Power is built from **Off-Grid: Solar Power** 3.0.0 (mod id `OffGrid`) by cakcan,
https://github.com/turret001/OffGrid, Steam Workshop item 3789425624, licensed under Creative Commons
Attribution-NonCommercial-ShareAlike 4.0 International (https://creativecommons.org/licenses/by-nc-sa/4.0/), and from
**Off-Grid: More Power** 0.9.4, the Dazed Utilities add-on to it (same licence).

What changed, in outline (the full history is this repository's):

- The two mods are merged into one, under the `DazedPower` namespace: files `DP_*` (Off-Grid's `OG_*`) and `DPM_*`
  (More Power's `OGM_*`), items `Base.Dazed*`, one sprite sheet `dazedpower_01`, ModData key `dazedpower`, global
  tables `DazedPowerGrid`, `DazedPowerRemote`, `DazedPowerSeeded`, `DazedPowerSeedWaiting`.
- More Power's power sources are parts of the registry (`DP_Parts`) rather than wrappers over it; their watts enter
  the model directly (`sys.sourceW` in `DP_Model.step`); the wiring rules for every kind are in `DP_Model.wireLegal`.
- Grades are Makeshift / Salvaged / Workshop throughout; the roof (flat) mount and the backup generator (converted
  vanilla generator) are removed; tracking arrays, a 2x2 array, two grades of controller with a part limit each, two
  grades of each solar lamp are added.
- The building resolver, reach arithmetic and Building Picker moved to Dazed Utilities: Core (`DazedCore`), which
  this mod requires, along with heavy parts, notes, options and the Error Magnifier report.
- Turkish translation removed; the Realistic Mode figures (from Alwar) and Tabler Icons (MIT, licence shipped under
  `media/ui/DazedPower/Menu/`) are kept with their credits.

This mod as a whole is distributed under the same licence, CC BY-NC-SA 4.0 (see `LICENSE`). Please do not re-upload
Off-Grid itself to the Steam Workshop as your own item; this is a derivative work, published with attribution.
