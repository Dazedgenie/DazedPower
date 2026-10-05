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

## Next (agreed 2026-10-04) -- coded in Power 0.4.0, Plumbing 0.14.0, Core 1.2.0, Dank branch `dazedpower-loads`; not yet run in game

Power
- Car as a generator: a parked car with its engine running and a wired node within 10 tiles charges the bank from its
  alternator, burning petrol, with engine noise.
- Electric fence: a wired fence section; a zombie touching it is knocked down and stunned, with small damage and watts per hit (coded, unreleased).
- Dazed Dank loads: grow lights, fans and the reservoir pump register as loads and follow priority.
- Cold room (with Dazed Butchery): a wall cooler unit; every container in its room keeps food like a fridge while
  powered; watts scale with room size (the Power side coded, unreleased: the room cooler).

Plumbing
- Sprinkler schedule: watering hours and a skip-when-raining switch.
- Drilled well: built once, an electric Dazed Power load, about 15 L/min of clean water into a piped tank.
- Smokehouse on biogas (with Dazed Butchery): the Butchery smoker can burn propane from a Plumbing line.

Polish (all three mods)
- Help window from the sidebar: tabbed pages for Power, Plumbing and Core.
- Admin tools: inspect, repair or reset a system from the context menu; a server stats line.
- Performance pass over the minute ticks and square scans.
- Translation-ready: key lists and a template for community languages.

## Considered and left out

Transformer grades, inverters as a separate part, a water heater, motion-sensing lamps, cable overlay sprites.

Already in: the 30-day weather forecast is the Almanac (DP_Forecast), and deep discharge already costs bank capacity (DegradeBank).
