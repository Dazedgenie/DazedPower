--[[ Dazed Power -- the physics of the three added sources.

     Pure and engine-free, like Dazed Power's own DP_Model: numbers in, numbers
     out, so it can be run and tested headlessly. It lives in its OWN table
     (DazedPower.More.Model), never on Dazed Power's, so a Dazed Power update that
     adds a function of the same name cannot collide with anything here.

     The sections below are the pedal generator, the windmills and the
     steam engines, exactly as designed and tested in the fork; see
     PEDAL_GENERATOR.md, WINDMILLS.md and STEAM.md for the reasoning.
]]

DazedPower = DazedPower or {}
DazedPower.More = DazedPower.More or {}
DazedPower.More.Model = DazedPower.More.Model or {}
local M = DazedPower.More.Model

local max, min, abs = math.max, math.min, math.abs
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
M.clamp = clamp

------------------------------------------------------------ pedal generator

--  The physical-labour source: a stationary bike or hand-crank driving a
--  generator. Unlike an array it has no environment to read -- no sun, no
--  wind, no flow -- its input is a character actively working the pedals,
--  which DP_Actions.DP_Pedal supplies live while its timed action runs.
--  Everything here stays pure and engine-free, like the rest of this file;
--  DP_Actions is where a live character's Fitness perk is actually read.
--
--  REAL-WORLD SUSTAINED WATTAGES (not sprint peaks), which is what this is
--  built from and deliberately does not inflate: an untrained adult holds
--  roughly 50-150 W over an hour on a bike, a well-conditioned rider more.
--  Faking the number bigger would be the one dishonest figure in a mod that
--  otherwise runs on real physics everywhere else (the solar model is real
--  geodesy; this is the same discipline applied to a human engine instead of
--  a photovoltaic one). The payoff for a low number is instead in WHEN it
--  works: a bike needs no sun, no wind, no water, and works at 3 AM in a
--  blizzard, indoors, for as long as somebody's legs hold out.
M.PEDAL_FITNESS_MIN = 50    -- an untrained rider, vanilla Fitness perk 0
M.PEDAL_FITNESS_MAX = 150   -- a well-conditioned rider, Fitness 10

--- What the machine itself is built from, mirroring the array's makeshift /
--  standard / premium ladder. `mult` is how much of the rider's own effort
--  actually reaches the generator (a lashed-together frame slips and binds);
--  `wear` scales how fast a session costs it condition, for a later repair
--  mechanic to spend against, the same shape as an array's `wear`.
M.PEDAL_SPEC = {
    makeshift    = { mult = 0.60, wear = 1.6 },
    salvaged     = { mult = 0.85, wear = 1.1 },
    workshop = { mult = 1.00, wear = 0.7 },
}

--- An installed gear set, found or built (P.GEAR_ITEM). Real bicycle gearing
--  does not create power -- the rider's legs are the only engine there is --
--  it changes how much of a given effort at the pedals reaches the wheel, or
--  here, the generator. `mult` is that conversion; `fatigue` is how much
--  harder the higher gearing is to sustain, so racing gears are a genuine
--  trade rather than a strict upgrade: more watts, tireder rider.
M.GEAR_SPEC = {
    low    = { mult = 0.75, fatigue = 0.75 },
    stock  = { mult = 1.00, fatigue = 1.00 },
    racing = { mult = 1.35, fatigue = 1.45 },
}

function M.pedalSpec(tier)
    return M.PEDAL_SPEC[tier or "workshop"] or M.PEDAL_SPEC.workshop
end

function M.gearSpec(gear)
    return M.GEAR_SPEC[gear or "stock"] or M.GEAR_SPEC.stock
end

--- Watts a rider produces at the pedals themselves, before the machine's own
--  losses and gearing: a straight line between the real-world "everyday
--  adult" and "well-conditioned" sustained bands, by the vanilla Fitness
--  perk (0..10). A level-0 survivor sits at the bottom of that range and a
--  maxed one at the top -- there is no path here to the 300-400 W a genuine
--  athlete can hold, because that number belongs to competitive cyclists,
--  not to a person who has been doing bicep curls with a sledgehammer.
function M.pedalRiderWatts(fitness)
    local f = clamp(fitness or 0, 0, 10) / 10
    return M.PEDAL_FITNESS_MIN + (M.PEDAL_FITNESS_MAX - M.PEDAL_FITNESS_MIN) * f
end

------------------------------------------------------------------ amplifier
--
--  A rare piece of kit that bolts onto any one generating machine (pedal,
--  windmill, boiler, propane): a hot-rodded alternator winding and a voltage
--  regulator that lets the machine be pushed past its rating. The machine
--  makes AMP_POWER times what it otherwise would, and wears AMP_WEAR times
--  as fast. The fuel it burns is unchanged: the gain is in how hard the
--  hardware is driven, and the bill is paid in condition, not in fuel.
--
--  A machine with no running wear of its own (a pedal generator's cranks do
--  not wear out) gets PEDAL_AMP_WEAR condition points per hour of being
--  ridden while amplified, so the amplifier always costs durability.
--
--  The machine's condition derating (rough bearings, a cracked plate...) is
--  applied first, and the amplifier multiplies what is left.

--  Three more costs, all live-world only:
--    noise   an amplified machine that is making power whines, and zombies
--            hear it AMP_NOISE tiles away (a machine already loud is 1.5x
--            as loud).
--    sparks  below AMP_FIRE_BELOW condition the over-driven windings and
--            wiring can arc and start a fire: AMP_FIRE_RISK chance per hour
--            of making power, scaled by how far below, at most one an hour.
--    solar   a Dazed Power solar array has only weather wear, so the amplifier
--            wears it SOLAR_AMP_WEAR condition points per hour it is making
--            extra power. (Its extra output is 0.5 x what the array makes.)

M.AMP_POWER = 1.5
M.AMP_WEAR = 2.0
M.PEDAL_AMP_WEAR = 0.5

--- Micro-hydro wheel: steady, weather-proof power while it sits in moving water.
M.HYDRO_W = 350
M.HYDRO_WEAR = 0.02      -- condition points per hour turning

--- Watts a wheel delivers: scaled by condition, throttled by ice under -5 C,
--  a little extra in rain, nothing when it has no water or is broken.
function M.hydroOutput(h, env)
    if not h or not h.wet then return 0, "still" end
    local cond = (h.condition or 100) / 100
    if cond <= 0.35 then return 0, "still" end
    local w = M.HYDRO_W * cond
    local t = env and env.temperature or 20
    if t < -5 then w = w * 0.3 elseif t < 0 then w = w * 0.7 end
    if env and (env.precipitation or 0) > 0 and not env.snowing then w = w * 1.15 end
    return w, "turning"
end
M.SOLAR_AMP_WEAR = 0.15
M.AMP_NOISE = 12
M.AMP_NOISE_LOUD = 1.5
M.AMP_FIRE_BELOW = 50
M.AMP_FIRE_RISK = 0.2

--- The chance, over `hours` of making power, that an amplified machine of
--  this condition starts a fire.
function M.ampFireChance(condition, hours)
    local c = condition or 100
    if c >= M.AMP_FIRE_BELOW then return 0 end
    return M.AMP_FIRE_RISK * (M.AMP_FIRE_BELOW - c) / M.AMP_FIRE_BELOW * (hours or 0)
end

--- Noise radius of an amplified machine making power; `baseTiles` is what it
--  already makes (0 for the silent kinds).
function M.ampNoise(baseTiles)
    return math.max(M.AMP_NOISE, (baseTiles or 0) * M.AMP_NOISE_LOUD)
end

--- Output multiplier for a machine with (true) or without an amplifier.
function M.ampPower(amp) return amp and M.AMP_POWER or 1 end
--- Wear multiplier likewise.
function M.ampWear(amp) return amp and M.AMP_WEAR or 1 end

--- Electrical watts a pedal generator delivers right now, for a rider of the
--  given Fitness level, on a machine of this tier fitted with this gear, at
--  this condition (0..100, same scale an array frame uses). A worn machine
--  loses drive-train efficiency the same way a cracked panel loses cells:
--  never down to nothing, because a rider is still turning a shaft, but a
--  neglected bike is worth a repair.
function M.pedalOutput(fitness, tier, gear, condition, amp)
    local rider = M.pedalRiderWatts(fitness)
    local cond = clamp((condition or 100) / 100, 0, 1)
    return rider * M.pedalSpec(tier).mult * M.gearSpec(gear).mult
                 * (0.4 + 0.6 * cond) * M.ampPower(amp)
end

-- Fatigue cost in PERCENTAGE POINTS of the character's Fatigue stat, per
-- in-game minute of pedaling at "stock" gearing. DPM_Actions charges it once
-- a minute of the timed action has elapsed, through DPM_Stats, which
-- converts to the engine's own scale (0..1). Scaled by M.gearSpec(gear).fatigue
-- for the gear actually fitted. At 0.25/minute stock that is about 15
-- points an hour -- a noticeable dent inside a session, exhausting after
-- several hours straight, never a free lunch, and never a feasible way to
-- run the whole house around the clock on one rider's legs.
M.PEDAL_FATIGUE_PER_MINUTE = 0.25

-- Too tired to start pedaling, in percent of the Fatigue stat.
M.PEDAL_TOO_TIRED_PCT = 95

function M.pedalFatiguePerMinute(gear)
    return M.PEDAL_FATIGUE_PER_MINUTE * M.gearSpec(gear).fatigue
end

------------------------------------------------------------------- windmills
--
--  A wind turbine's power is the textbook formula, the same one real
--  small-turbine makers print on their spec sheets:
--
--      P = 1/2 * air density * swept area * wind speed^3 * Cp
--
--  where Cp ("power coefficient") is the share of the wind's energy the
--  rotor actually catches. No rotor can beat 59.3% (the Betz limit); good
--  small turbines manage 35-40%, crude home-built ones 15-25%. The cube is
--  the whole character of wind power: double the wind and you get EIGHT
--  times the power, so a breezy day and a calm one are worlds apart.
--
--  Then four real-world limits on top:
--    * cut-in: below this wind speed the rotor cannot overcome its own
--      friction and the alternator's drag, and makes nothing.
--    * rated power: the alternator's ceiling. Past the wind speed that
--      reaches it, more wind gives no more power.
--    * furling (Workshop only): past a set speed the turbine deliberately
--      turns its rotor out of the wind to protect itself, and output drops
--      to a trickle until the storm passes.
--    * the safe speed (Makeshift and Salvaged): past it the machine is
--      simply overspeeding and gets damaged -- see M.turbineDamage.
--
--  How the numbers compare, standing on the ground in a 36 km/h (10 m/s)
--  weather wind at 15 C -- a fresh breeze -- measured by running this code:
--    makeshift     ~100 W   (1.2 m rotor on a 4 m pole, blades cut from a barrel)
--    salvaged      ~460 W   (2 m rotor on a 6 m mast)
--    workshop  ~1570 W  (3 m rotor on a 9 m tower, proper aerofoil blades)
--  (less than the rotor sizes alone suggest, because the rotor sits lower
--  than the 10 m the weather is measured at -- see M.hubWind), and at
--  18 km/h, a gentle breeze, about an eighth of that. A standard solar array
--  makes about 575 W in full sun; the difference is that wind blows at
--  night, in winter, and hardest in exactly the weather that shuts the
--  panels down.

M.WIND_SPEC = {
    --  rotor: diameter in metres.  cp: share of the wind's energy caught.
    --  rated: alternator ceiling in watts.  cutIn: m/s to start turning.
    --  tracks: has a tail fin, so it always faces the wind. Without one the
    --          rotor stays pointed wherever it was placed.
    --  hub: height of the rotor above the ground it stands on, in metres.
    --  safe: m/s past which it is damaged (nil = never, because it furls).
    --  furl: m/s at which it turns out of the wind (nil = cannot).
    --  wear: how fast its bearings wear while turning, relative to salvaged.
    makeshift    = { rotor = 1.2, cp = 0.22, rated = 150,  cutIn = 3.5,
                     tracks = false, hub = 4, safe = 14, furl = nil, wear = 2.0 },
    salvaged     = { rotor = 2.0, cp = 0.30, rated = 600,  cutIn = 3.0,
                     tracks = true,  hub = 6, safe = 20, furl = nil, wear = 1.0 },
    workshop = { rotor = 3.0, cp = 0.38, rated = 1800, cutIn = 2.5,
                     tracks = true,  hub = 9, safe = nil, furl = 18, wear = 0.5 },
}

--- A furled turbine is not stopped: it still turns, edge-on, and makes a
--  fraction of its rated power. Real furling machines hold roughly this.
M.FURL_SHARE = 0.20

function M.windSpec(tier)
    return M.WIND_SPEC[tier or "salvaged"] or M.WIND_SPEC.salvaged
end

--- Air density from temperature, at sea level (kg/m^3). Cold air is denser,
--  so the same wind carries about 15% more energy at -10 C than at 30 C.
--  Knox County sits under 300 m, low enough that altitude does not matter.
function M.airDensity(tempC)
    return 101325 / (287.05 * ((tempC or 15) + 273.15))
end

--- Wind speed at the rotor, from the weather's speed.
--
--  Wind is slower near the ground, where it drags on grass, fences and
--  houses. Weather stations measure it at 10 m, the meteorological standard,
--  and the usual way to move it to another height is the "1/7 power law":
--      v(h) = v(10 m) * (h / 10) ^ (1/7)
--  So a tall tower is worth having, and a turbine on a roof (each floor up
--  adds about 3 m) catches more than the same turbine on the lawn.
M.FLOOR_HEIGHT = 3
function M.hubWind(ms, tier, z)
    local h = M.windSpec(tier).hub + M.FLOOR_HEIGHT * max(0, z or 0)
    return ms * (h / 10) ^ (1 / 7)
end

--- Bearing (0 = N, clockwise) that each placed facing points its rotor at.
--  A turbine's rotor faces INTO the wind, so its facing is the direction
--  the wind comes from.
M.FACING_BEARING = { N = 0, E = 90, S = 180, W = 270 }

--- Smallest angle between two bearings, 0..180.
function M.bearingGap(a, b)
    local d = math.abs((a - b) % 360)
    if d > 180 then d = 360 - d end
    return d
end

--- The share of power a rotor keeps when it is not facing the wind square.
--  Wind hitting the rotor at an angle is the cos of that angle as effective,
--  and field measurements of real turbines put the power loss close to
--  cos^2. Past 90 degrees the wind is coming from behind, and a rotor
--  built to face the wind does not usefully turn that way round.
function M.yawFactor(gapDeg)
    if gapDeg >= 90 then return 0 end
    local c = math.cos(math.rad(gapDeg))
    return c * c
end

--- The facing a tail-finned turbine turns to: the nearest of the four
--  sprite facings to where the wind comes from. `current` is kept unless the
--  wind has moved more than HYSTERESIS past the halfway point, so a wind
--  wavering around a diagonal does not flick the rotor back and forth.
M.YAW_HYSTERESIS = 10
function M.trackFacing(windFrom, current)
    if windFrom == nil then return current end
    if current and M.FACING_BEARING[current]
            and M.bearingGap(windFrom, M.FACING_BEARING[current]) <= 45 + M.YAW_HYSTERESIS then
        return current
    end
    local best, bestGap = current or "S", 999
    for f, b in pairs(M.FACING_BEARING) do
        local g = M.bearingGap(windFrom, b)
        if g < bestGap then best, bestGap = f, g end
    end
    return best
end

--- Watts one turbine makes, and why.
--
--  `tb` is { tier, facing, condition (0..100), z }. `env` needs windKph and
--  windFrom (DP_Env.readWind) and temperature. Returns the watts, the wind
--  speed at the rotor in m/s, and one of "still", "turning", "furled" --
--  what the sprite should show, before damage is considered (see
--  M.turbineState).
--
--  A tail-finned turbine always faces the wind, so its yaw loss is nil
--  whatever its sprite shows: the sprite can only show four directions, the
--  real fin follows the wind exactly. A fixed one keeps the facing it was
--  placed with, and loses power as the wind swings away from it.
function M.turbineOutput(tb, env)
    local spec = M.windSpec(tb.tier)
    local ms = (env.windKph or 0) / 3.6
    if ms <= 0 then return 0, 0, "still" end
    ms = M.hubWind(ms, tb.tier, tb.z)

    local yaw = 1
    if not spec.tracks and env.windFrom ~= nil then
        local b = M.FACING_BEARING[tb.facing or "S"] or 180
        yaw = M.yawFactor(M.bearingGap(env.windFrom, b))
    end
    -- Too little wind, or all of it from the side or behind: it sits there.
    if ms < spec.cutIn or yaw <= 0 then return 0, ms, "still" end

    local cond = clamp((tb.condition or 100) / 100, 0, 1)
    if cond <= 0 then return 0, ms, "still" end
    -- A worn machine loses efficiency the way a cracked array does: rough
    -- bearings, a bent blade, a slipping belt. Never below a quarter while
    -- it still turns at all.
    local derate = 0.25 + 0.75 * cond

    if spec.furl and ms >= spec.furl then
        return spec.rated * M.FURL_SHARE * derate * M.ampPower(tb.amp), ms, "furled"
    end

    local area = math.pi * (spec.rotor / 2) ^ 2
    local w = 0.5 * M.airDensity(env.temperature) * area * ms ^ 3 * spec.cp * yaw
    w = min(w, spec.rated) * derate * M.ampPower(tb.amp)
    return w, ms, "turning"
end

--- The sprite state for a turbine. Damage shows over everything else: a
--  machine at or under 35% condition shows a broken blade, like a cracked
--  array, while still making what its condition allows.
function M.turbineState(motion, condition)
    if (condition or 100) <= 35 then return "broken" end
    return motion or "still"
end

--- Condition points a turbine loses over `dtHours` in wind of `ms` at the
--  rotor. Two things wear a turbine out:
--
--  * Overspeed. Past its safe speed a machine without furling is spinning
--    faster than its blades and bearings were made for, and the damage
--    grows with how far past it the wind is: STORM_RATE points an hour for
--    every 100% over, times the grade's wear figure. Worked through: a
--    90 km/h gale costs a salvaged machine about 4 points an hour and a
--    makeshift one about 28 (it is broken in a few hours); a 70 km/h
--    blow costs the makeshift one about 11 an hour. A furling machine never
--    overspeeds: that is what furling is for.
--
--    Only while it TURNS. A rotor standing side-on to the wind is not
--    spinning, so it is not overspeeding -- and that is the real way to save
--    a home-built turbine from a storm: turn it out of the wind. A makeshift
--    one faces where it was put, so picking it up and setting it down
--    side-on before a storm protects it; tail-finned ones face the wind
--    whatever you do, which is what the Workshop turbine's furling is for.
--  * Ordinary running. Bearings wear while the rotor turns: RUN_RATE points
--    an hour at the salvaged grade, which is about a hundred days of steady
--    turning from new to scrap, twice as fast for makeshift and half for the
--    Workshop build.
--
--  TUNING NOTE: how often Project Zomboid's weather actually blows past
--  60-90 km/h has not been measured yet; STORM_RATE is the one number to
--  turn if storms prove too gentle or too brutal in play.
M.STORM_RATE = 25
M.RUN_RATE = 0.04
function M.turbineDamage(tier, ms, turning, dtHours, amp)
    if not turning then return 0 end
    local spec = M.windSpec(tier)
    local dmg = M.RUN_RATE * spec.wear * dtHours
    if spec.safe and ms > spec.safe then
        dmg = dmg + M.STORM_RATE * ((ms - spec.safe) / spec.safe) * spec.wear * dtHours
    end
    return dmg * M.ampWear(amp)
end

--------------------------------------------------------------- steam engines
--
--  A boiler burns fuel to boil water; the steam drives a small engine that
--  turns a generator. Three things make it unlike every other source here:
--  it has to be FED (fuel and water), it takes time to raise steam from
--  cold, and it can be hurt by running out of water while the fire burns.
--
--  FUEL is measured in the game's own unit: FIRE-HOURS, how long a campfire
--  or stove burns an item (vanilla: a log 6 hours, a plank 2). That keeps a
--  boiler consistent with every fire in the game. It is really an energy
--  unit: a 9 kg log is about 38 kWh of heat (dry wood holds about 4.2 kWh a
--  kilogram), spread over its 6 fire-hours, so ONE FIRE-HOUR IS ABOUT
--  6.3 kWh OF HEAT. Wood's energy goes with its weight, so an item's value is
--  worked out from its weight: 2/3 of a fire-hour a kilogram, which gives
--  vanilla's figures for a log and a plank exactly. Charcoal holds about
--  twice the energy of wood by weight, so it counts double.
--
--  EFFICIENCY is the brutal part of small steam, and it is real: of the
--  fuel's heat, a home-built boiler-and-engine turns 3-5% into electricity,
--  a good small plant 8-10%. The rest goes up the chimney, out with the
--  exhaust steam, and into friction. So a log gives:
--     makeshift  ~1.5 kWh   salvaged  ~2.3 kWh   workshop  ~3.4 kWh
--  -- a fridge for a day or so, per log, from the best of them.
--
--  WATER: every kilogram of steam is a litre of water boiled away, and
--  boiling a litre from cold takes about 0.72 kWh (2.6 MJ). Only the
--  Workshop plant has a condenser, which turns most of its exhaust back
--  into water for the boiler. Worked out below, at full output:
--     makeshift ~6.9 L/h   salvaged ~12.5 L/h   workshop ~3.2 L/h

M.FIRE_HOUR_KWH = 6.3        -- heat in one fire-hour of fuel
M.FUEL_HOURS_PER_KG = 2 / 3  -- fire-hours per kilogram of wood
M.STEAM_KWH_PER_LITRE = 0.72 -- heat to turn a litre of cold water into steam
M.STEAM_READY = 0.6          -- boiler heat (0..1) at which it makes steam
M.STEAM_IDLE = 0.2           -- the lowest a governor lets the fire burn
M.STEAM_COOL_HOURS = 3       -- how long a hot boiler takes to go cold
M.DRY_RATE = 30              -- condition lost per hour firing a dry boiler
M.STEAM_RUN_WEAR = 0.03      -- condition lost per hour of running, x wear

M.STEAM_SPEC = {
    --  rated: most the generator makes (W).  eff: fuel heat -> electricity.
    --  boilerEff: fuel heat -> steam.  tank: water, litres.  hopper: fuel,
    --  fire-hours.  warmup: hours to raise steam from cold at full fire.
    --  condense: share of exhaust recovered as water.  governor: throttles
    --  itself when the batteries are full.  noise: how far zombies hear it,
    --  in tiles (vanilla's petrol generator: 20).  wear: bearing wear.
    makeshift    = { rated = 400,  eff = 0.04, boilerEff = 0.50, tank = 40,
                     hopper = 12, warmup = 0.75, condense = 0,
                     governor = false, noise = 22, wear = 2.0 },
    salvaged     = { rated = 900,  eff = 0.06, boilerEff = 0.60, tank = 80,
                     hopper = 18, warmup = 1.0,  condense = 0,
                     governor = true,  noise = 16, wear = 1.0 },
    workshop = { rated = 2000, eff = 0.09, boilerEff = 0.70, tank = 120,
                     hopper = 24, warmup = 1.25, condense = 0.85,
                     governor = true,  noise = 10, wear = 0.5 },
}

function M.steamSpec(tier)
    return M.STEAM_SPEC[tier or "salvaged"] or M.STEAM_SPEC.salvaged
end

--- Fire-hours of fuel burned per hour at full output.
function M.steamFullBurn(tier)
    local s = M.steamSpec(tier)
    return (s.rated / 1000 / s.eff) / M.FIRE_HOUR_KWH
end

--- Litres of water used per hour at full output.
function M.steamFullWater(tier)
    local s = M.steamSpec(tier)
    local heatKw = s.rated / 1000 / s.eff
    return heatKw * s.boilerEff / M.STEAM_KWH_PER_LITRE * (1 - s.condense)
end

--- How long a boiler can run on what is in it now, for its Info screen.
--
--  Two figures, from the same burn and water rates M.steamStep uses:
--
--    full  hours making its rated output, flat out. A cold or warm boiler
--          first has to raise steam at full fire (no water used, no power),
--          so that fuel is spent before the clock starts: a hopper too low
--          to raise steam at all gives 0 and `cantRaise`.
--    idle  (governed engines only) hours kept hot and ready at the idle
--          floor, M.STEAM_IDLE, with nothing wanted from it: how long it
--          waits on full batteries. Water still boils at that fire.
--
--  Each comes with which runs out first, "fuel" or "water". A boiler with
--  no water reports 0 and "water" whatever is in the hopper: lit like that
--  it is not running, it is being damaged (M.DRY_RATE).
function M.steamRuntime(b)
    local spec = M.steamSpec(b.tier)
    local burn, drink = M.steamFullBurn(b.tier), M.steamFullWater(b.tier)
    local fuel, water = max(0, b.fuel or 0), max(0, b.water or 0)
    local out = { raiseFuel = 0 }
    local heat = clamp(b.heat or 0, 0, 1)
    if heat < M.STEAM_READY then
        out.raiseFuel = burn * (M.STEAM_READY - heat) * spec.warmup
        fuel = fuel - out.raiseFuel
        if fuel <= 0 then
            out.full, out.fullLimit, out.cantRaise = 0, "fuel", true
            if spec.governor then out.idle, out.idleLimit = 0, "fuel" end
            return out
        end
    end
    local function run(rate)
        local byFuel = (burn * rate > 0) and fuel / (burn * rate) or math.huge
        local byWater = (drink * rate > 0) and water / (drink * rate) or math.huge
        if byWater < byFuel then return byWater, "water" end
        return byFuel, "fuel"
    end
    out.full, out.fullLimit = run(1)
    if spec.governor then out.idle, out.idleLimit = run(M.STEAM_IDLE) end
    return out
end

--- Fire-hours an item of fuel is worth, from its weight (see above).
function M.steamFuelHours(weight, fullType)
    local h = max(0, weight or 0) * M.FUEL_HOURS_PER_KG
    if type(fullType) == "string" and string.find(fullType, "Charcoal", 1, true) then
        h = h * 2
    end
    return h
end

--- Watts a boiler could make right now, before any governor: nothing until
--  it is lit, fed, has water and has raised steam; then rising to full as
--  the pressure comes up, less for a worn machine.
function M.steamAvailable(b)
    if not b.lit or (b.fuel or 0) <= 0 or (b.water or 0) <= 0 then return 0 end
    local cond = clamp((b.condition or 100) / 100, 0, 1)
    if cond <= 0 then return 0 end
    local heat = b.heat or 0
    if heat < M.STEAM_READY then return 0 end
    local ramp = clamp((heat - M.STEAM_READY) / (1 - M.STEAM_READY), 0, 1)
    return M.steamSpec(b.tier).rated * ramp * (0.25 + 0.75 * cond) * M.ampPower(b.amp)
end

--- Advance one boiler by `dtHours`, at `throttle` (0..1, the share of what
--  it could make that is wanted; 1 for a machine with no governor).
--
--  Mutates b (fuel, water, heat, lit, condition) and returns the average
--  watts over the step, then how it was: "cold", "warming" or "running",
--  and how many of those hours it spent firing with no water (dryHours).
--
--  The fire burns at full while raising steam. Once up to pressure a
--  governed machine eases the fire down to what is wanted, never below
--  STEAM_IDLE, which keeps it hot and ready. Water only boils once it is
--  making steam, in step with the fire. Running dry with the fire lit is
--  the dangerous case: no steam, and the boiler plates overheat.
function M.steamStep(b, dtHours, throttle)
    local spec = M.steamSpec(b.tier)
    local dt = max(0, dtHours or 0)
    b.fuel, b.water = max(0, b.fuel or 0), max(0, b.water or 0)
    b.heat, b.condition = clamp(b.heat or 0, 0, 1), clamp(b.condition or 100, 0, 100)
    if b.lit and b.fuel <= 0 then b.lit = false end
    if not b.lit or dt <= 0 then
        b.heat = max(0, b.heat - dt / M.STEAM_COOL_HOURS)
        return 0, (b.heat > 0.3) and "warming" or "cold", 0
    end

    local raising = b.heat < M.STEAM_READY
    local firing = 1
    if not raising and spec.governor then
        firing = M.STEAM_IDLE + (1 - M.STEAM_IDLE) * clamp(throttle or 1, 0, 1)
    end

    -- Fuel: burn for as long as this step, or until it runs out.
    local burnRate = M.steamFullBurn(b.tier) * firing
    local tBurn = min(dt, b.fuel / burnRate)
    b.fuel = max(0, b.fuel - burnRate * tBurn)
    local heatBefore = b.heat
    b.heat = min(1, b.heat + tBurn / spec.warmup)
    if tBurn < dt then
        b.lit = false                     -- burnt out part-way
        b.heat = max(0, b.heat - (dt - tBurn) / M.STEAM_COOL_HOURS)
    end

    local watts, dry = 0, 0
    if b.water <= 0 then
        -- Fired with an empty boiler: nothing to boil, so the plates take
        -- the whole fire, whether or not it had raised steam yet.
        dry = tBurn
    else
        -- Steam: only the part of the step spent at pressure makes any.
        local tSteam = tBurn
        if heatBefore < M.STEAM_READY then
            tSteam = max(0, tBurn - (M.STEAM_READY - heatBefore) * spec.warmup)
        end
        if tSteam > 0 then
            local wantShare = spec.governor and clamp(throttle or 1, 0, 1) or 1
            local useRate = M.steamFullWater(b.tier) * firing
            local tWater = (useRate > 0) and min(tSteam, b.water / useRate) or tSteam
            b.water = max(0, b.water - useRate * tWater)
            -- What it makes at the pressure it has now, for the hours it had
            -- both steam and water, averaged over the whole step.
            local ramp = clamp((b.heat - M.STEAM_READY) / (1 - M.STEAM_READY), 0, 1)
            local wNow = spec.rated * ramp * (0.25 + 0.75 * b.condition / 100) * M.ampPower(b.amp)
            watts = wNow * wantShare * tWater / max(dt, 1e-9)
            dry = tSteam - tWater
            b.condition = max(0, b.condition - M.STEAM_RUN_WEAR * spec.wear * M.ampWear(b.amp) * tWater)
        end
    end
    if dry > 0 then b.condition = max(0, b.condition - M.DRY_RATE * dry) end
    if b.condition <= 0 then watts = 0 end
    local motion = raising and "warming" or ((watts > 0) and "running" or "warming")
    return watts, motion, dry
end


------------------------------------------------------------ propane generator
--
--  An engine-driven generator burning propane: the fuel of real home
--  standby units, because it keeps for decades in a sealed tank where petrol
--  goes stale in months. The fuel is vanilla's own propane tank
--  (Base.PropaneTank), taken as a 20 lb barbecue cylinder: 9 kg of propane
--  when full.
--
--  ENERGY: propane holds about 12.9 kWh of heat per kilogram. A small
--  engine generator turns 13-22% of that into electricity at full load (the
--  bigger and better-built, the higher), so a full cylinder is worth roughly
--  15-25 kWh at the plug. Ratings are kept modest (800-3500 W) so a gas engine
--  does not outclass the other sources.
--
--  FUEL FOLLOWS LOAD, but not to zero. An engine held at its governed speed
--  burns a good share of its full-load fuel just turning over: real
--  generators idle at 25-35% of full-load consumption. So
--      fuel/hour = full-load fuel x (idle share + (1 - idle share) x load share)
--  which is why running one for a light load wastes fuel, and why the
--  better ones start and stop THEMSELVES around the battery: run hard to
--  fill the bank, then shut down and let the bank carry the house.
--
--  STORAGE: each grade has its own small RESERVOIR (kg of propane, filled
--  from a tank and carried with the machine) and one or two PORTS, each
--  taking a whole propane tank hooked up in place, drawn first and handed
--  back, part-used, when unhooked. Both count as fuel.
--
--  AUTO-START (Salvaged and Workshop): with the switch on AUTO, the engine
--  starts when the batteries fall to the start level the player set and
--  stops when they reach PROPANE_STOP_SOC -- a standby generator's two
--  thresholds, a wide gap between them so it runs in long efficient
--  stretches rather than short wasteful ones.
--
--  DANGERS, all live-world only except the fuel a leak wastes:
--    noise   how far zombies hear it running, in tiles.
--    fumes   running with no open sky above it fills the building with
--            carbon monoxide, as a petrol generator does (DPM_Bridge).
--    leaks   worn fittings: below LEAK_BELOW condition a running engine
--            loses gas as it goes, worse the more worn, and that gas can
--            catch: at most one fire an hour, likelier the worse the wear.
--    wear    condition drops slowly with running hours (the reason fittings
--            ever wear at all); repaired like the other machines.

--  A hook the optional Plumbing hookup fills in (DPM_Plumbing.lua): a fuel
--  line's tank as a fuel source. .available(g) -> kg ready, .draw(g, kg) -> kg
--  taken. nil when Plumbing is absent, and then nothing here changes.
M.LineSource = nil

M.PROPANE_KWH_PER_KG = 12.9
M.TANK_KG = 9                  -- a full vanilla propane tank, as a 20 lb cylinder

--  Every vessel the generator accepts, and the kg of propane it holds when
--  full. Hook-up stores the type and a 0..1 fill (a drainable's own reading),
--  so every conversion between that fill and kilograms goes through tankKg.
--  Base.Propane_Refill is vanilla's small LANTERN BOTTLE, taken as a 1 lb
--  camping cylinder: 0.45 kg, a twentieth of the big tank.
M.TANK_KG_BY_TYPE = {
    ["Base.PropaneTank"]    = 9,
    ["Base.Propane_Refill"] = 0.45,
}
function M.tankKg(fullType)
    return M.TANK_KG_BY_TYPE[fullType or "Base.PropaneTank"] or M.TANK_KG
end
M.PROPANE_STOP_SOC = 95        -- auto: stop at this battery charge, percent
M.PROPANE_START_SOC = 30       -- auto: the default start level, percent
M.PROPANE_START_CHOICES = { 20, 30, 40, 50, 60 }
M.PROPANE_RUN_WEAR = 0.05      -- condition lost per running hour, x wear
M.PROPANE_LEAK_BELOW = 40      -- condition under which a running engine leaks
M.PROPANE_LEAK_KG = 0.4        -- kg/hour lost at condition 0 (scaled up from 40)
M.PROPANE_FIRE_RISK = 0.25     -- chance per running hour of a fire, at condition 0

M.PROPANE_SPEC = {
    --  rated: most it makes (W).  eff: fuel heat -> electricity at full load.
    --  idle: share of full-load fuel burned with no load at all.
    --  reservoir: built-in tank, kg.  ports: propane tanks it can hook up.
    --  auto: has the standby controller.  noise: tiles.  wear: x run wear.
    makeshift    = { rated = 800,  eff = 0.13, idle = 0.35, reservoir = 4,
                     ports = 1, auto = false, noise = 24, wear = 2.0 },
    salvaged     = { rated = 2000, eff = 0.17, idle = 0.30, reservoir = 9,
                     ports = 1, auto = true,  noise = 18, wear = 1.0 },
    workshop = { rated = 3500, eff = 0.21, idle = 0.25, reservoir = 18,
                     ports = 2, auto = true,  noise = 12, wear = 0.5 },
}

--  THE PETROL GENERATOR shares all of this machinery (kind "petrol" in place
--  of "propane"; the model finds out from g.kind or the `kind` argument). Its
--  fuel is petrol in LITRES where the propane one's is kg, burned from a
--  built-in reservoir (poured in from cans) or straight from a linked gas
--  tank. Louder and thirstier than the propane engine, no hook-up ports.
M.PETROL_KWH_PER_L = 8.9
M.PETROL_SPEC = {
    makeshift    = { rated = 800,  eff = 0.12, idle = 0.35, reservoir = 10,
                     ports = 0, auto = false, noise = 32, wear = 2.0 },
    salvaged     = { rated = 2000, eff = 0.16, idle = 0.30, reservoir = 20,
                     ports = 0, auto = true,  noise = 26, wear = 1.0 },
    workshop = { rated = 3500, eff = 0.20, idle = 0.25, reservoir = 40,
                     ports = 0, auto = true,  noise = 20, wear = 0.5 },
}

--- The spec table for a grade of either gas engine. `kind` is "petrol" for
--  the petrol generator and anything else for the propane one.
function M.propaneSpec(tier, kind)
    if kind == "petrol" then return M.PETROL_SPEC[tier or "salvaged"] or M.PETROL_SPEC.salvaged end
    return M.PROPANE_SPEC[tier or "salvaged"] or M.PROPANE_SPEC.salvaged
end

--- Kilowatt-hours in one unit of the engine's fuel (kg propane, L petrol).
function M.fuelKwh(kind)
    return (kind == "petrol") and M.PETROL_KWH_PER_L or M.PROPANE_KWH_PER_KG
end

--- Kilograms of propane burned per hour at full load.
function M.propaneFullBurn(tier, kind)
    local s = M.propaneSpec(tier, kind)
    return s.rated / 1000 / s.eff / M.fuelKwh(kind)
end

--- Kilograms burned per hour making `watts` (0..rated).
function M.propaneBurnAt(tier, watts, kind)
    local s = M.propaneSpec(tier, kind)
    -- Capped at the rating: an amplified engine's extra watts cost no extra fuel.
    local share = clamp((watts or 0) / s.rated, 0, 1)
    return M.propaneFullBurn(tier, kind) * (s.idle + (1 - s.idle) * share)
end

--- All the propane a generator can reach: its reservoir and the tanks on
--  its ports. `g` holds the flat ModData fields (lpg, t1Fill, t2Fill...).
function M.propaneFuel(g)
    local kg = max(0, g.lpg or 0)
    if g.feedTank and M.LineSource then kg = kg + (M.LineSource.available(g) or 0) end
    for p = 1, 2 do
        if g["t" .. p .. "Type"] then kg = kg + max(0, g["t" .. p .. "Fill"] or 0) * M.tankKg(g["t" .. p .. "Type"]) end
    end
    return kg
end

--- Take `kg` from the hooked-up tanks first (port 1, then 2), then the
--  reservoir. Returns what it could actually take.
function M.propaneDraw(g, kg)
    local want = max(0, kg or 0)
    local got = 0
    -- A fuel line from a Dazed Utilities tank (g.feedTank, see DPM_Plumbing):
    -- the tank is drawn FIRST, exactly as much as is burned, however long the
    -- step; then the built-in reservoir; then any hooked-up bottle.
    if g.feedTank and M.LineSource then
        got = M.LineSource.draw(g, want) or 0
    end
    if want - got > 0 and g.feedTank then
        local have = max(0, g.lpg or 0)
        local take = min(have, want - got)
        g.lpg = have - take
        got = got + take
    end
    for p = 1, 2 do
        if want - got <= 0 then break end
        if g["t" .. p .. "Type"] then
            local size = M.tankKg(g["t" .. p .. "Type"])
            local have = max(0, g["t" .. p .. "Fill"] or 0) * size
            local take = min(have, want - got)
            g["t" .. p .. "Fill"] = (have - take) / size
            got = got + take
        end
    end
    if want - got > 0 then
        local have = max(0, g.lpg or 0)
        local take = min(have, want - got)
        g.lpg = have - take
        got = got + take
    end
    return got
end

--- What it can make right now, worn or not.
function M.propaneAvailable(g)
    local cond = clamp((g.condition or 100) / 100, 0, 1)
    if cond <= 0 then return 0 end
    return M.propaneSpec(g.tier, g.kind).rated * (0.25 + 0.75 * cond) * M.ampPower(g.amp)
end

--- Should it be running? Applies the switch: "off", "on", or (standby
--  grades only) "auto" against the battery's charge `soc` (percent, nil if
--  there is no bank to read). Sets g.running and returns it.
function M.propaneSwitch(g, soc)
    local spec = M.propaneSpec(g.tier, g.kind)
    local mode = g.mode or "off"
    if mode == "auto" and not spec.auto then mode = "on" end
    local run
    if M.propaneFuel(g) > 0 then g.noFuel = nil end
    if (g.condition or 100) <= 0 or M.propaneFuel(g) <= 0 then
        run = false
    elseif mode == "on" then
        run = true
    elseif mode == "auto" then
        -- g.hold: the controller's master AUTO is off (GEN page), so nothing starts on its own.
        if soc == nil or g.hold then
            run = false
        elseif g.running then
            run = soc < (g.stopPct or M.PROPANE_STOP_SOC)
        else
            run = soc <= (g.startPct or M.PROPANE_START_SOC)
        end
    else
        run = false
    end
    g.running = run
    return run
end

--- Advance one generator by `dtHours`, asked for `wantW` watts.
--
--  Mutates g (fuel fields, condition, running). Returns the average watts
--  over the step, the hours it ran, and the kg a leak lost. Call
--  M.propaneSwitch first: this only runs one that is already running.
function M.propaneStep(g, dtHours, wantW)
    local dt = max(0, dtHours or 0)
    g.condition = clamp(g.condition or 100, 0, 100)
    if not g.running or dt <= 0 then return 0, 0, 0 end
    local spec = M.propaneSpec(g.tier, g.kind)
    local w = clamp(wantW or 0, 0, M.propaneAvailable(g))
    local cond = g.condition
    local leakRate = 0
    if cond < M.PROPANE_LEAK_BELOW then
        leakRate = M.PROPANE_LEAK_KG * (M.PROPANE_LEAK_BELOW - cond) / M.PROPANE_LEAK_BELOW
    end
    local rate = M.propaneBurnAt(g.tier, w, g.kind) + leakRate
    local fuel = M.propaneFuel(g)
    local tRun = (rate > 0) and min(dt, fuel / rate) or dt
    M.propaneDraw(g, rate * tRun)
    if tRun < dt then
        g.running = false                 -- ran dry part-way
        g.noFuel = true
    end
    g.condition = max(0, cond - M.PROPANE_RUN_WEAR * spec.wear * M.ampWear(g.amp) * tRun)
    if g.condition <= 0 then g.running = false end
    return w * tRun / max(dt, 1e-9), tRun, leakRate * tRun
end

--- The chance, over `hours` of running, that worn fittings start a fire.
function M.propaneFireChance(condition, hours)
    local c = condition or 100
    if c >= M.PROPANE_LEAK_BELOW then return 0 end
    return M.PROPANE_FIRE_RISK * (M.PROPANE_LEAK_BELOW - c) / M.PROPANE_LEAK_BELOW * (hours or 0)
end

--- Hours it can run on what it holds: flat out, and idling with no load.
function M.propaneRuntime(g)
    local fuel = M.propaneFuel(g)
    local leak = 0
    local cond = g.condition or 100
    if cond < M.PROPANE_LEAK_BELOW then
        leak = M.PROPANE_LEAK_KG * (M.PROPANE_LEAK_BELOW - cond) / M.PROPANE_LEAK_BELOW
    end
    local full = M.propaneBurnAt(g.tier, M.propaneAvailable(g), g.kind) + leak
    local idle = M.propaneBurnAt(g.tier, 0, g.kind) + leak
    return { full = (full > 0) and fuel / full or 0, idle = (idle > 0) and fuel / idle or 0,
             fuel = fuel }
end

--- May `kind` be wired to `targetKind`? Only asked for the added kinds
--  (DPM_Parts wraps Dazed Power's M.wireLegal and hands these to it). Each
--  lands on a controller, and chains to its own kind, the way arrays chain.
function M.wireLegal(kind, targetKind)
    if M.INSTRUMENT[kind] or M.INSTRUMENT[targetKind] then return false end
    if targetKind == "controller" then return true end
    return kind == targetKind
end

------------------------------------------------------ windsock and vane

--  Two instruments for reading the wind. Neither makes power, so neither is
--  ever wired (see wireLegal above); they only report what the weather is
--  doing, so a player can decide where a windmill is worth building and
--  which way a fixed one should face.
--
--  WINDSOCK: the airfield kind, a striped fabric cone on a swivel. It shows
--  two things at a glance: which way the wind blows (the sock streams
--  DOWNWIND, away from where the wind comes from) and roughly how hard (a
--  real sock is made to fill one stripe for about every 3 knots, and stands
--  straight out at about 15 knots, 28 km/h).
--
--  WEATHER VANE: an arrow on a pivot. The broad tail catches the wind and
--  swings downwind, so the arrow's POINT aims at where the wind comes from.
--  It also keeps a record (a tally the player keeps beside it): how many
--  hours the wind came from each of the eight compass points, and how much
--  wind ENERGY came from each. The energy tally is the one that matters for
--  a windmill, because power goes with the cube of wind speed: one stormy
--  afternoon from the west can be worth more than a week of light airs from
--  the south.

M.INSTRUMENT = { windsock = true, vane = true }

M.COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
M.COMPASS_BEARING = {}
for i, n in ipairs(M.COMPASS) do M.COMPASS_BEARING[n] = (i - 1) * 45 end

--- Windsock bands, km/h at the sock. Below LIMP it hangs down; at FULL and
--  above it stands straight out; between, it droops.
M.SOCK_LIMP = 5.5          -- about 3 knots: not enough to lift the first stripe
M.SOCK_FULL = 28           -- about 15 knots: fully extended
M.SOCK_HEIGHT = 3          -- metres: the sock's swivel above the ground it stands on

--- The weather's wind (measured at 10 m) at the sock's own height, by the
--  same 1/7 power law the windmills use; each floor up adds FLOOR_HEIGHT.
function M.sockWind(kph, z)
    local h = M.SOCK_HEIGHT + M.FLOOR_HEIGHT * max(0, z or 0)
    return (kph or 0) * (h / 10) ^ (1 / 7)
end

function M.sockState(kph)
    kph = kph or 0
    if kph < M.SOCK_LIMP then return "limp" end
    if kph < M.SOCK_FULL then return "half" end
    return "full"
end

--- The facing a windsock's sprite shows: the way the sock STREAMS, which is
--  downwind, so the opposite of where the wind comes from. Same four-way
--  rounding, and the same hysteresis, as a tail-finned turbine.
function M.sockFacing(windFrom, current)
    if windFrom == nil then return current end
    return M.trackFacing((windFrom + 180) % 360, current)
end

--- The facing a vane's arrow shows: it points INTO the wind, exactly the
--  way a turbine's rotor does.
function M.vaneFacing(windFrom, current)
    return M.trackFacing(windFrom, current)
end

--- The Beaufort scale, the sailors' 0-12 names for wind strength. Each
--  entry is the lowest km/h of that force, so the force is the last entry
--  not above the speed.
M.BEAUFORT_KPH = { 0, 1, 6, 12, 20, 29, 39, 50, 62, 75, 89, 103, 118 }
function M.beaufort(kph)
    kph = kph or 0
    local force = 0
    for f = 1, #M.BEAUFORT_KPH do
        if kph >= M.BEAUFORT_KPH[f] then force = f - 1 end
    end
    local lo = M.BEAUFORT_KPH[force + 1]
    local hi = M.BEAUFORT_KPH[force + 2]
    return force, lo, hi and (hi - 1) or nil
end

--- Which windmill grades this wind would turn, on ground level `z`:
--  a table tier -> true/false, from each grade's own cut-in speed at its
--  own hub height (the same test M.turbineOutput uses).
function M.wouldTurn(kph, z)
    local out = {}
    local ms = (kph or 0) / 3.6
    for tier, spec in pairs(M.WIND_SPEC) do
        out[tier] = ms > 0 and M.hubWind(ms, tier, z) >= spec.cutIn
    end
    return out
end

--  THE VANE'S RECORD. Kept as plain numbers in the vane's ModData, not a
--  table: Dazed Power carries a part's plain fields onto the item when it is
--  picked up, but not its tables, and the record should survive a move.
--
--    vt_<dir>   hours of wind from that compass point
--    ve_<dir>   wind energy from it: (m/s)^3 x hours. Only ever compared
--               with the other seven, so the units do not matter.
--    vCalm      hours too calm to read (the arrow just wobbles)
--    vHours     all hours counted, calm included
--    vKph       km/h x hours, for the average
--
--  Old readings FADE, with a half-life of VANE_HALF_LIFE hours of watching:
--  the weather shifts with the seasons, and a record from last spring should
--  count for less than last week. Fading is applied only as new readings are
--  added, never for time the vane spent unwatched (unloaded), so a vane left
--  alone for a month still says what it saw.
M.VANE_HALF_LIFE = 168        -- one week
M.VANE_CALM_KPH = 2           -- below this the arrow cannot hold a direction
M.VANE_MIN_HOURS = 12         -- less than half a day of record is not a pattern

function M.vaneRecord(d, windFrom, kph, hours)
    if not hours or hours <= 0 then return end
    local keep = 0.5 ^ (hours / M.VANE_HALF_LIFE)
    for _, n in ipairs(M.COMPASS) do
        d["vt_" .. n] = (d["vt_" .. n] or 0) * keep
        d["ve_" .. n] = (d["ve_" .. n] or 0) * keep
    end
    d.vCalm = (d.vCalm or 0) * keep
    d.vHours = (d.vHours or 0) * keep + hours
    d.vKph = (d.vKph or 0) * keep + (kph or 0) * hours
    if windFrom == nil or (kph or 0) < M.VANE_CALM_KPH then
        d.vCalm = d.vCalm + hours
        return
    end
    local i = math.floor(((windFrom % 360) + 22.5) / 45) % 8
    local n = M.COMPASS[i + 1]
    local ms = kph / 3.6
    d["vt_" .. n] = d["vt_" .. n] + hours
    d["ve_" .. n] = d["ve_" .. n] + ms * ms * ms * hours
end

--- What the record says, or nil when there is none at all.
--
--  Returns { hours, calm (share 0..1), avgKph, first, firstShare, second,
--  secondShare, strongest, facing, facingKeeps } where first/second are the
--  two commonest directions by time (shares of the non-calm hours),
--  strongest is the direction that brought the most wind energy, and
--  facing is the best of the four facings for a windmill that cannot turn
--  itself, with facingKeeps the share of a tail-finned machine's energy it
--  would catch (the cos^2 yaw loss of M.yawFactor, weighted by energy).
function M.vaneSummary(d)
    local hours = d and d.vHours or 0
    if hours <= 0 then return nil end
    local s = { hours = hours, calm = (d.vCalm or 0) / hours,
                avgKph = (d.vKph or 0) / hours }
    local windy, energy = 0, 0
    for _, n in ipairs(M.COMPASS) do
        windy = windy + (d["vt_" .. n] or 0)
        energy = energy + (d["ve_" .. n] or 0)
    end
    if windy <= 0 then return s end
    -- The two commonest points, first by time; ties go to compass order.
    local order = {}
    for i, n in ipairs(M.COMPASS) do order[i] = n end
    table.sort(order, function(a, b)
        local ta, tb = d["vt_" .. a] or 0, d["vt_" .. b] or 0
        if ta ~= tb then return ta > tb end
        return M.COMPASS_BEARING[a] < M.COMPASS_BEARING[b]
    end)
    s.first, s.firstShare = order[1], (d["vt_" .. order[1]] or 0) / windy
    if (d["vt_" .. order[2]] or 0) > 0 then
        s.second, s.secondShare = order[2], (d["vt_" .. order[2]] or 0) / windy
    end
    if energy > 0 then
        local best, bestE = nil, -1
        for _, n in ipairs(M.COMPASS) do
            if (d["ve_" .. n] or 0) > bestE then best, bestE = n, d["ve_" .. n] or 0 end
        end
        s.strongest = best
        -- The fixed-windmill advice, over the four facings a sprite can take.
        local bestF, bestKeep = nil, -1
        for _, f in ipairs({ "N", "E", "S", "W" }) do
            local caught = 0
            for _, n in ipairs(M.COMPASS) do
                local gap = M.bearingGap(M.COMPASS_BEARING[n], M.FACING_BEARING[f])
                caught = caught + (d["ve_" .. n] or 0) * M.yawFactor(gap)
            end
            if caught / energy > bestKeep then bestF, bestKeep = f, caught / energy end
        end
        s.facing, s.facingKeeps = bestF, bestKeep
    end
    return s
end

return M
