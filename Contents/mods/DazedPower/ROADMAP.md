# Dazed Utilities: Power -- roadmap

## v1 scope (agreed; (done) marks what is already in)

- Build the power mod on Dazed Utilities: Core (done)
- Makeshift / Salvaged / Workshop grades; static, tracking and 2x2 arrays; floor and wall banks; Makeshift /
  Workshop controllers differing by how many parts they manage (8 / 24); garden and street lamps in two grades (done)
- Blender renders for every part in the Dazed Power / Plumbing style (`tools/blender/dp_render.py`) (done, 0.1.1)
- Cable cost by distance: one Electric Wire per 4 tiles (sandbox), half back on a cut; Electricity XP per wire (done, 0.2.0)
- Live-work shock: connecting or disconnecting with the controller's output on risks a shock unless it is switched off (done, 0.2.0)
- The Electrician profession knows the Makeshift recipes without a handbook (done, 0.2.0)
- Wall power gauge: a placeable panel showing SOC, in/out watts and the running sources anywhere in the base (done, 0.2.0)
- ModData schema versions through DazedCore.Migrate on every part (done, 0.2.0)
- Shared options page and Error Magnifier report through the core (done)
- The GEN page for the propane and petrol generators; found rigs in all three grades (done, 0.2.0)
- Still to do before 1.0: the Blender pass for the gauge, then review, optimise and test

## Post-1.0 (all coded in 0.3.0, stand-in art, untested in game)

World seeding (loot tables), charger bench, vehicle charging, battery ageing, load priority, micro-hydro, biogas
digester (Plumbing 0.12), hydrogen risk, grounding rod and lightning, sandbox presets, and Plumbing's fuel pump.

Still open: cross-mod loads for Dazed Dank (the registry is ready; Dank has to register), Blender art for the
rod, bench and wheel, and the in-game and dedicated-server passes.

## Considered and left out

Transformer grades, inverters as a separate part, electric fences, a water heater, motion-sensing lamps, cable overlay sprites.

Already in: the 30-day weather forecast is the Almanac (DP_Forecast), and deep discharge already costs bank capacity (DegradeBank).
