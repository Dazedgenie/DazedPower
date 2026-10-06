--[[ Dazed Power -- connecting the added sources to Dazed Power's
     simulation, without editing a line of it.

     Dazed Power's simulation lives in DP_System (and DP_Distrib for systems
     nobody is near). Almost all of it is private, but five functions are
     public and called through their tables, and those are enough:

       S.relink          after Dazed Power walks a controller's wiring, we pick
                         OUR parts out of what it walked (S.claimed).
       S.staleLinks      so a moved or lifted part of ours triggers a relink,
                         exactly like one of Dazed Power's.
       S.updateController  marks which controller is being stepped, and runs
                         the live-only effects (sprites, noise, storms, fire)
                         after Dazed Power has finished its own tick.
       M.step + M.arrayOutput   THE POWER. Dazed Power adds up generation by
                         calling M.arrayOutput for each array in sys.arrays,
                         then multiplies the total by the controller's
                         efficiency. We add one extra entry to that list for
                         the duration of the step, and answer M.arrayOutput
                         for it with our machines' watts (pre-divided so the
                         multiplier leaves them as they are). From there
                         Dazed Power's own code does everything: the battery,
                         the load, the low-voltage cut-out, the monitor's
                         figures, whether the house has power, the clipped
                         surplus. The entry is removed again before anything
                         else can see it.
       D.capture         so the snapshot Dazed Power keeps of a far-away system
                         carries our windmills and boilers too, and its
                         away-simulation (which also runs M.step) counts them.

     Nothing here runs on a multiplayer client: the simulation is the
     server's, as it is in Dazed Power.
]]

if isClient() then return end

require "DazedPower/DP_System"
require "DazedPower/DP_Distrib"
require "DazedPower/DPM_Parts"
require "DazedPower/DPM_Model"
require "DazedPower/DPM_Env"
require "DazedPower/DPM_Water"

local S = DazedPower.System
if not S then return end

DazedPower.More = DazedPower.More or {}
DazedPower.More.Bridge = DazedPower.More.Bridge or {}
local B = DazedPower.More.Bridge
local P, R = DazedPower.Parts, DazedPower.More.Parts
local MM, ME = DazedPower.More.Model, DazedPower.More.Env
local UM = DazedPower.Model                -- Dazed Power's model

-- How long a pedal generator's heartbeat is trusted (real ms); see
-- DPM_Actions.DPM_Pedal and PEDAL_GENERATOR.md.
local PEDAL_FRESH_MS = 2500

-- The controller Dazed Power is stepping right now, if any.
local CTX = nil

-- The world clock in hours (also what a cold failure is stamped with).
local function hoursNow()
    local gt = getGameTime and getGameTime()
    return gt and gt:getWorldAgeHours() or 0
end

B.COLD_NOTE_RANGE = 10        -- squares: who hears an engine fail to start in the cold

--- Tell the players near an engine that it would not start in the cold. Authority only.
function B.coldNote(obj)
    local sq = obj and P.try(obj, "getSquare")
    if not (sq and DazedCore and DazedCore.Note) then return end
    local players = {}
    local list = getOnlinePlayers and getOnlinePlayers()
    if list and list:size() > 0 then
        for i = 0, list:size() - 1 do players[#players + 1] = list:get(i) end
    elseif getSpecificPlayer then
        for i = 0, ((getNumActivePlayers and getNumActivePlayers()) or 1) - 1 do players[#players + 1] = getSpecificPlayer(i) end
    end
    for _, pl in ipairs(players) do
        if pl and math.abs(pl:getX() - sq:getX()) <= B.COLD_NOTE_RANGE and math.abs(pl:getY() - sq:getY()) <= B.COLD_NOTE_RANGE
                and math.floor(pl:getZ()) == sq:getZ() then
            DazedCore.Note.say(pl, "IGUI_DazedPower_GenColdNote", nil, true)
        end
    end
end

local function try(obj, method, ...)
    if not obj or not obj[method] then return nil end
    local ok, v = pcall(obj[method], obj, ...)
    if ok then return v end
    return nil
end

local function alive(o)
    local ix = try(o, "getObjectIndex")
    return type(ix) == "number" and ix >= 0
end

----------------------------------------------------------- finding our parts

--- Our parts in a controller's system: whatever Dazed Power's own last relink
--  walked (S.claimed[root]) that is one of our kinds and is standing there.
--  Dazed Power's walk already accepted them as nodes (it recognises them
--  through the wrapped P.spriteInfo) and stamped their system claim; it just
--  had no list to file them in.
local function collect(rec)
    local out = { pedal = {}, windmill = {}, steam = {}, propane = {}, water = {}, hydro = {}, bench = {}, fence = {}, cooler = {}, heater = {} }
    local root = UM.nodeKey(rec.x, rec.y, rec.z, "controller")
    for nk in pairs((S.claimed or {})[root] or {}) do
        local x, y, z, kind = UM.parseNodeKey(nk)
        -- out[kind] only for the power sources: an instrument is never wired
        -- (DPM_Model.wireLegal), so it should never be here; if an old save
        -- somehow claims one, it is left out rather than counted.
        -- the petrol generator is filed with the propane ones: the same
        -- engine code runs both (each entry says which it is: g.kind)
        local slot = (kind == "petrol") and "propane" or kind
        -- Plumbing's wired pump and purifier are loads, filed together (DPM_Water).
        if UM.LOAD_KINDS and UM.LOAD_KINDS[kind] then slot = "water" end
        if x and out[slot] then
            local o = P.objectAt(x, y, z, kind)
            if o then out[slot][#out[slot] + 1] = o end
        end
    end
    return out
end

if not B.wrapped then
    B.wrapped = true

    local relink0 = S.relink
    function S.relink(rec)
        relink0(rec)
        rec.dpm = collect(rec)
    end

    local stale0 = S.staleLinks
    function S.staleLinks(rec)
        if stale0(rec) then return true end
        local o = rec.dpm
        if not o then return false end
        for _, parts in pairs(o) do
            for i = 1, #parts do
                if not alive(parts[i]) then return true end
            end
        end
        return false
    end
end

---------------------------------------------------------- what they make

--- The model's view of this controller's added parts, built fresh every
--  step from the objects (the way Dazed Power's gather builds its arrays').
--- The plain-table view of a propane generator the model works on: its
--  flat ModData fields (DPM_Model's propane section), copied, so the model
--  can mutate them and a replay can write them back.
local genEntry, genEffects
B.GEN_FIELDS = { "mode", "running", "lpg", "feedTank", "lineTx", "lineTy", "lineTz", "t1Type", "t1Fill", "t1Cond", "t2Type", "t2Fill",
                 "t2Cond", "condition", "startPct", "stopPct", "hold", "noFuel", "coldFail", "coldFailAt" }
genEntry = function(obj, info, d)
    local g = { obj = obj, tier = info.tier, kind = info.kind, amp = d.amp == true }
    for _, f in ipairs(B.GEN_FIELDS) do g[f] = d[f] end
    if g.condition == nil then g.condition = 100 end
    -- The air at the engine, for a cold start or to clear an old failure: only a stopped one that may start needs it.
    local env = DazedPower.Env
    if not g.running and (g.mode ~= "off" or g.coldFail) and env and env.engineAir then g.liveAir = env.engineAir(obj) end
    g.fuel0 = MM.propaneFuel(g)      -- what it held before this step, for the GEN page's fuel today
    return g
end

--- True when a wheel's square or a neighbouring one is water.
local function nearWater(sq)
    if not (sq and IsoFlagType and IsoFlagType.water) then return false end
    local cell = getCell and getCell()
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local flag = IsoFlagType.water
    for dx = -1, 1 do
        for dy = -1, 1 do
            local n = (dx == 0 and dy == 0) and sq or (cell and cell:getGridSquare(x + dx, y + dy, z))
            -- A method pcall instead of a fresh closure per neighbour, every wheel, every minute.
            if n and n.Is then
                local ok, w = pcall(n.Is, n, flag)
                if ok and w then return true end
            end
        end
    end
    return false
end

local function liveSources(rec)
    local o = rec.dpm or { pedal = {}, windmill = {}, steam = {}, propane = {}, hydro = {} }
    o.hydro = o.hydro or {}

    -- Dazed Power's own solar arrays that carry an amplifier: copies of the
    -- entries its gather builds, so the model can price the extra half.
    local solar = {}
    local env = DazedPower.Env
    for i = 1, #(rec.arrays or {}) do
        local obj = rec.arrays[i]
        local info = alive(obj) and P.describe(obj)
        local sq = info and try(obj, "getSquare")
        if info and sq then
            local d = P.data(obj)
            if d.amp and (not (env and env.isSunlit) or env.isSunlit(sq)) then
                solar[#solar + 1] = { obj = obj, entry = {
                    facing = info.facing, mount = info.mount, tier = info.tier,
                    panels = d.panels or UM.baseArraySpec(info.tier).panels,
                    condition = d.condition or 100, soiling = d.soiling or 0, snow = d.snow or 0 } }
            end
        end
    end

    local hooked = DazedPower.Alternator and DazedPower.Alternator.hasLinks(rec)
    if (#o.pedal + #o.windmill + #o.steam + #(o.propane or {}) + #o.hydro + #solar) == 0 and not hooked then return nil end
    local src = { pedalW = 0, riding = 0, pedals = {}, turbines = {}, boilers = {},
                  gens = {}, solar = solar, indoors = 0, hydros = {}, hydroW = 0 }
    local now = getTimestampMs and getTimestampMs() or 0

    for i = 1, #o.pedal do
        local obj = o.pedal[i]
        local info = R.describe(obj)
        if info then
            local d = P.data(obj)
            local w = 0
            if now - (d.pedalHeartbeat or 0) <= PEDAL_FRESH_MS then
                w = MM.pedalOutput(d.pedalFitness or 0, info.tier, d.gear, d.condition, d.amp == true)
            end
            d.pedalWatts = w
            src.pedals[#src.pedals + 1] = { obj = obj, watts = w, amp = d.amp == true }
            src.pedalW = src.pedalW + w
            if w > 0 then src.riding = src.riding + 1 end
        end
    end

    -- Cars hooked up by their alternator (DP_Alternator): idling engines feed the bus.
    if DazedPower.Alternator then
        src.cars = DazedPower.Alternator.liveCars(rec)
    end

    for i = 1, #o.hydro do
        local obj = o.hydro[i]
        local sq = alive(obj) and obj:getSquare()
        if sq then
            local d = P.data(obj)
            src.hydros[#src.hydros + 1] = { obj = obj, condition = d.condition or 100, wet = nearWater(sq) }
        end
    end

    for i = 1, #o.windmill do
        local obj = o.windmill[i]
        local info = R.describe(obj)
        local sq = obj:getSquare()
        if info and sq then
            local d = P.data(obj)
            if ME.isOutside(sq) then
                d.indoors = nil
                src.turbines[#src.turbines + 1] = { obj = obj, tier = info.tier,
                    facing = info.facing, condition = d.condition or 100, z = sq:getZ(),
                    amp = d.amp == true }
            else
                d.indoors = true
                src.indoors = src.indoors + 1
            end
        end
    end

    for i = 1, #o.steam do
        local obj = o.steam[i]
        local info = R.describe(obj)
        local sq = obj:getSquare()
        if info and sq then
            local d = P.data(obj)
            -- No draught and nowhere for the smoke under a roof: a boiler
            -- found lit indoors is smothered (and will not light, DPM_Actions).
            if not ME.isOutside(sq) then
                d.indoors, d.lit = true, false
            else
                d.indoors = nil
            end
            src.boilers[#src.boilers + 1] = { obj = obj, tier = info.tier, lit = d.lit == true,
                fuel = d.fuel or 0, water = d.water or 0, heat = d.heat or 0,
                condition = d.condition or 100, amp = d.amp == true }
        end
    end

    -- Propane generators run indoors too (that is their danger: fumes).
    for i = 1, #(o.propane or {}) do
        local obj = o.propane[i]
        local info = R.describe(obj)
        local sq = obj:getSquare()
        if info and sq then
            local d = P.data(obj)
            d.indoors = (not ME.isOutside(sq)) or nil
            src.gens[#src.gens + 1] = genEntry(obj, info, d)
        end
    end
    return src
end

--- Step the added sources over `dt` hours and return the watts they deliver
--  at the controller, in total. Mutates the boilers (fuel, water, heat...).
--  The governor logic is the fork's M.step block, unchanged in meaning: the
--  want is the house's load the other sources do not cover plus whatever the
--  bank can still take; a boiler with no governor runs flat out and goes
--  first, the governed ones share what is left.
local arrayOutput0 = UM.arrayOutput      -- Dazed Power's own, captured before wrapping

local function stepSources(src, sys, dt, env, invEff, harvest)
    local windKph, windFrom = ME.wind()
    local wind = { windKph = windKph, windFrom = windFrom, temperature = env.temperature }
    src.windKph, src.windFrom = windKph, windFrom

    -- An amplified pedal generator has no running wear of its own, so the
    -- amplifier is what wears it: per hour it is actually being ridden.
    for i = 1, #(src.pedals or {}) do
        local p = src.pedals[i]
        if p.amp and (p.watts or 0) > 0 and dt > 0 and p.obj and alive(p.obj) then
            local d = P.data(p.obj)
            d.condition = math.max(0, (d.condition or 100) - MM.PEDAL_AMP_WEAR * dt)
        end
    end

    -- The amplified solar arrays' extra half, delivered the way Dazed Power
    -- delivers an array's output (through the inverter and its harvest).
    local solarAmpW = 0
    for i = 1, #(src.solar or {}) do
        local sa = src.solar[i]
        local a = arrayOutput0(sa.entry, env)
        sa.extra = (MM.AMP_POWER - 1) * (a or 0)
        solarAmpW = solarAmpW + sa.extra
    end
    solarAmpW = solarAmpW * invEff * harvest
    src.solarAmpW = solarAmpW

    local windW = 0
    for i = 1, #src.turbines do
        local tb = src.turbines[i]
        local w, ms, motion = MM.turbineOutput(tb, wind)
        tb.watts, tb.ms, tb.motion = w, ms, motion
        windW = windW + w
    end
    windW = windW * invEff

    local hydroW = 0
    for i = 1, #(src.hydros or {}) do
        local h = src.hydros[i]
        local w, motion = MM.hydroOutput(h, env)
        h.watts, h.motion = w, motion
        hydroW = hydroW + w
    end
    hydroW = hydroW * invEff
    src.hydroW = hydroW
    local carW = 0
    for i = 1, #(src.cars or {}) do carW = carW + (src.cars[i].watts or 0) end
    carW = carW * invEff
    src.carW = carW
    hydroW = hydroW + carW
    windW = windW + hydroW      -- sized into the boiler/generator "need" like wind

    local steamW = 0
    local boilers = src.boilers or {}
    if #boilers > 0 then
        local solarW = 0
        for i = 1, #(sys.arrays or {}) do
            local a = sys.arrays[i]
            solarW = solarW + (arrayOutput0(a, env))
        end
        solarW = solarW * invEff * harvest + solarAmpW
        local bank = sys.bank or {}
        local chargeEff = bank.eff or UM.CHARGE_EFF or 0.86
        local capNow = bank.capacity or (UM.bankCapacity and UM.bankCapacity(bank, env.temperature or 20)) or 0
        local room = math.max(0, capNow - math.max(0, bank.charge or 0))
        local drawW = (sys.online and not sys.lvd) and math.max(0, sys.load or 0) or 0
        local need = math.max(0, drawW - solarW - windW - (src.pedalW or 0))
        if dt > 0 and chargeEff > 0 then need = need + room / dt / chargeEff end
        local govAvail = 0
        for i = 1, #boilers do
            local b = boilers[i]
            local a = MM.steamAvailable(b) * invEff
            if MM.steamSpec(b.tier).governor then govAvail = govAvail + a
            else need = math.max(0, need - a) end
        end
        local share = (govAvail > 0) and MM.clamp(need / govAvail, 0, 1) or 1
        src.throttle = share
        for i = 1, #boilers do
            local b = boilers[i]
            local w, motion, dry = MM.steamStep(b, dt, MM.steamSpec(b.tier).governor and share or 1)
            b.watts, b.motion, b.dry = w, motion, dry
            steamW = steamW + w
        end
        steamW = steamW * invEff
    end

    -- Propane, last: an engine that starts and stops at will is the one
    -- source worth holding back, so it covers only what the others leave --
    -- the house's load plus the battery's room, the same want the steam
    -- governor uses. With the switch on AUTO it is also the battery's
    -- charge that starts and stops it (DPM_Model.propaneSwitch).
    local genW = 0
    local gens = src.gens or {}
    if #gens > 0 then
        local solarW = 0
        for i = 1, #(sys.arrays or {}) do
            local a = sys.arrays[i]
            solarW = solarW + (arrayOutput0(a, env))
        end
        solarW = solarW * invEff * harvest + solarAmpW
        local bank = sys.bank or {}
        local chargeEff = bank.eff or UM.CHARGE_EFF or 0.86
        local capNow = bank.capacity or (UM.bankCapacity and UM.bankCapacity(bank, env.temperature or 20)) or 0
        local charge = math.max(0, bank.charge or 0)
        local soc = (capNow > 0) and math.min(100, charge / capNow * 100) or nil
        local room = math.max(0, capNow - charge)
        local drawW = (sys.online and not sys.lvd) and math.max(0, sys.load or 0) or 0
        local need = math.max(0, drawW - solarW - windW - steamW - (src.pedalW or 0))
        if dt > 0 and chargeEff > 0 then need = need + room / dt / chargeEff end
        src.soc = soc
        local coldOn = P.sandbox("ColdStarts") ~= false
        for i = 1, #gens do
            local g = gens[i]
            -- Its own air when loaded, else the county's (an away snapshot or an engine read while running); stamped with this step's hour.
            g.ambient = g.liveAir
            if g.ambient == nil and coldOn and not g.running then g.ambient = env.temperature end
            g.now = src.at
            local failedAt = g.coldFailAt
            MM.propaneSwitch(g, soc)
            g.coldNote = (g.coldFail and g.coldFailAt ~= failedAt) or nil
            local w, ran, leak = MM.propaneStep(g, dt, (invEff > 0) and need / invEff or 0)
            g.watts, g.ran, g.leak = w, ran, leak
            need = math.max(0, need - w * invEff)
            genW = genW + w
        end
        genW = genW * invEff
    end

    src.windW, src.steamW, src.genW = windW - hydroW, steamW, genW
    -- A pedal generator's dynamo feeds the controller as it is: no
    -- conversion, as in the fork.
    return (src.pedalW or 0) + windW + steamW + genW + solarAmpW
end

--- Write the generators' fuel, switch and condition back, EVERY step, live
--  or catch-up, for the same reason as the boilers: a replay that did not
--  would hand out free propane for every hour the base sat unloaded.
local function writeGens(src)
    for i = 1, #(src.gens or {}) do
        local g = src.gens[i]
        if g.obj and alive(g.obj) then
            local d = P.data(g.obj)
            for _, f in ipairs(B.GEN_FIELDS) do d[f] = g[f] end
            d.genWatts = g.watts or 0
        end
    end
end

--- Write the boilers' new fuel, water, heat and condition onto the objects.
--  EVERY step, live or catch-up: a replay that did not would hand out free
--  fuel for every hour the base sat unloaded.
local function writeBoilers(src)
    for i = 1, #(src.boilers or {}) do
        local b = src.boilers[i]
        if b.obj and alive(b.obj) then
            local d = P.data(b.obj)
            d.fuel, d.water, d.heat = b.fuel, b.water, b.heat
            d.lit, d.condition = b.lit == true, b.condition
            d.steamWatts = b.watts or 0
            d.dry = ((b.dry or 0) > 0) or nil
        end
    end
end

--- The snapshot Dazed Power's away-simulation is stepping, found by its bank
--  table: DP_Distrib builds the step's sys with the snapshot's own bank.
local function remoteSources(sys)
    local D = DazedPower.Distrib
    if not (D and D.REMOTE_TAG and ModData and ModData.getOrCreate and sys.bank) then return nil end
    local store = ModData.getOrCreate(D.REMOTE_TAG)
    for _, snap in pairs(store) do
        if type(snap) == "table" and snap.bank == sys.bank and snap.dpm then
            snap.dpm.pedalW = 0
            return snap.dpm
        end
    end
    return nil
end

--- What the wired water machines draw: watts per load kind while working, and the idle ones' rated watts.
local function waterDraw(rec)
    local W = DazedPower.More.Water
    local list = rec and rec.dpm and rec.dpm.water
    local active, idle, total = {}, {}, 0
    if not (W and list) then return active, idle, 0 end
    for i = 1, #list do
        local o = list[i]
        if alive(o) then
            local kind, rated, working = W.draw(o)
            if kind and working then
                active[kind] = (active[kind] or 0) + rated
                total = total + rated
            elseif kind then
                idle[kind] = (idle[kind] or 0) + rated
            end
        end
    end
    return active, idle, total
end

--- A copy of a kind->watts table with `extra` added on top.
local function addKinds(base, extra)
    local out = {}
    for k, w in pairs(base or {}) do out[k] = w end
    for k, w in pairs(extra) do out[k] = (out[k] or 0) + w end
    return out
end

--- Bill the wired water machines once per controller step, and list them on the LOADS page.
--  The LOADS tables are swapped for patched copies and put back after the tick (S.updateController below).
local function billWater(sys)
    if not CTX or CTX.waterDone then return end
    CTX.waterDone = true
    local rec = CTX.rec
    local active, idle, total = waterDraw(rec)
    -- The fences, coolers and heaters (DP_ApplianceTick) are billed the same way, on the same LOADS rows.
    local Ap = DazedPower.Appliances
    if Ap and Ap.draw then
        local a2, i2, t2 = Ap.draw(rec)
        active, idle, total = addKinds(active, a2), addKinds(idle, i2), total + t2
    end
    if total > 0 and P.sandbox("SimulateLoad") ~= false then
        sys.load = (sys.load or 0) + total
    end
    if rec and rec.kinds then
        local any = false
        for _ in pairs(active) do any = true end
        for _ in pairs(idle) do any = true end
        if any then
            CTX.kinds0, CTX.idle0 = rec.kinds, rec.idleKinds
            rec.kinds = addKinds(rec.kinds, active)
            rec.idleKinds = addKinds(rec.idleKinds, idle)
            CTX.kindsP, CTX.idleP = rec.kinds, rec.idleKinds
        end
    end
end
B.waterDraw = waterDraw

if not B.wrappedStep then
    B.wrappedStep = true

    local step0 = UM.step
    function UM.step(sys, dt, env)
        local okw, errw = pcall(billWater, sys)
        if not okw then print("DazedPower: water billing failed: " .. tostring(errw)) end
        local src
        if CTX and not CTX.stepped then
            CTX.stepped = true
            src = liveSources(CTX.rec)
            CTX.src = src
        elseif not CTX then
            src = remoteSources(sys)
        end
        if not src then return step0(sys, dt, env) end

        dt = math.max(0, dt or 0)
        local invEff = sys.inverterEff or UM.INVERTER_EFF or 0.93
        local harvest = sys.harvest or 1.0
        src.invEff = invEff
        src.at = (CTX and CTX.at) or hoursNow()
        -- what the sources make this step, already at the bus: the model adds it to the sun's
        sys.sourceW = stepSources(src, sys, dt, env or {}, invEff, harvest)
        -- A failed cold start in a live step is told to whoever stands near; replays and away systems stay quiet.
        for i = 1, #(src.gens or {}) do
            local g = src.gens[i]
            if g.coldNote and CTX and CTX.live and g.obj then pcall(B.coldNote, g.obj) end
            g.coldNote = nil
        end
        local ok, a, b = pcall(step0, sys, dt, env)
        sys.sourceW = nil
        if not ok then error(a, 0) end
        writeBoilers(src)
        writeGens(src)
        return a, b
    end
end

------------------------------------------------------ the live-only effects

-- A dry boiler's fire risk; see STEAM.md.
local BOILER_FIRE_RISK, BOILER_FIRE_BELOW, BOILER_BLAST_SOUND = 0.5, 40, 60

local function worldCell()
    if getWorld and getWorld() then return getWorld():getCell() end
    return getCell and getCell() or nil
end

local function roll(p)
    if p <= 0 then return false end
    local r = ZombRand and ZombRand(1000000) / 1000000 or math.random()
    return r < p
end

local function boilerState(cond, motion, lit, heat)
    if (cond or 100) <= 35 then return "broken" end
    if motion == "running" then return "running" end
    if lit or (heat or 0) > 0.3 then return "warming" end
    return "cold"
end

--- One boiler's live-only effects after a step: engine noise while it
--  runs, a dry one's fire and explosion, its sprite. Shared by the wired
--  boilers (liveEffects) and the loose ones (settleLoose).
local function boilerEffects(b, now)
    local obj = b.obj
    local sq = obj and try(obj, "getSquare")
    if not (sq and alive(obj)) then return end
    local d = P.data(obj)
    local spec = MM.steamSpec(b.tier)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    -- A world sound: it draws zombies but plays no audio (no steam
    -- engine sound file ships with the add-on).
    if (b.watts or 0) > 0 and addSound then
        pcall(addSound, obj, x, y, z, spec.noise, spec.noise)
    end
    local dry = b.dry or 0
    if dry > 0 then
        local cell = worldCell()
        if b.condition <= 0 and not d.blown then
            d.blown = true
            d.lit, d.fuel, d.water, d.heat = false, 0, 0, 0
            if cell and IsoFireManager then
                if IsoFireManager.explode then pcall(IsoFireManager.explode, cell, sq, 100) end
                if IsoFireManager.StartFire then pcall(IsoFireManager.StartFire, cell, sq, true, 100) end
            end
            if addSound then
                pcall(addSound, obj, x, y, z, BOILER_BLAST_SOUND, BOILER_BLAST_SOUND)
            end
        elseif b.condition < BOILER_FIRE_BELOW and (not d.fireAt or now - d.fireAt >= 1) then
            local risk = BOILER_FIRE_RISK * dry * (BOILER_FIRE_BELOW - b.condition) / BOILER_FIRE_BELOW
            if roll(risk) and cell and IsoFireManager and IsoFireManager.StartFire then
                pcall(IsoFireManager.StartFire, cell, sq, true, 100)
                d.fireAt = now
            end
        end
    elseif b.condition > 0 then
        d.blown = nil
    end
    R.setVariant(obj, boilerState(d.condition, b.motion, d.lit, d.heat))
    -- Every tick: the fuel and water gauges move every minute and the
    -- player is watching them while feeding it.
    obj:transmitModData()
end

--------------------------------------------------- propane: the live world

--  FUMES. A running generator under a roof fills its building with carbon
--  monoxide, the way vanilla's petrol generator does: the engine's own
--  "toxic" flag on the building, which is what poisons whoever is inside.
--  Dazed Power clears that flag in any building holding one of its controllers
--  (a solar controller is a generator to the engine, but burns nothing),
--  unless it finds a FOREIGN generator running there -- and DPM_Parts teaches
--  its finder, P.generatorsOn, to count a running indoor propane generator as
--  one. So the flag is set here and kept by both mods while ours runs; when
--  it stops, it comes down again unless something else in the building is
--  still running.

local function buildingOf(obj)
    local sq = obj and try(obj, "getSquare")
    return sq and try(sq, "getBuilding")
end

--- Any other generator, vanilla or ours, running in this building?
local function otherEmitterIn(building, self)
    local def = try(building, "getDef")
    local rooms = def and try(def, "getRooms")
    if not rooms then return false end
    for i = 0, rooms:size() - 1 do
        local rd = rooms:get(i)
        local room = rd and try(rd, "getIsoRoom")
        local squares = room and try(room, "getSquares")
        if squares then
            for j = 0, squares:size() - 1 do
                local g = P.generatorsOn(squares:get(j))
                if g and g.obj ~= self then return true end
            end
        end
    end
    return false
end

local function setFumes(obj, d, on)
    local b = buildingOf(obj)
    if on then
        if b and b.setToxic and not try(b, "isToxic") then b:setToxic(true) end
        d.fumes = (b ~= nil) or nil
    elseif d.fumes then
        d.fumes = nil
        if b and b.setToxic and try(b, "isToxic") and not otherEmitterIn(b, obj) then
            b:setToxic(false)
        end
    end
end

--- One propane generator's live-only effects after a step.
genEffects = function(g, now)
    local obj = g.obj
    local sq = obj and try(obj, "getSquare")
    if not (sq and alive(obj)) then return end
    local d = P.data(obj)
    local spec = MM.propaneSpec(g.tier, g.kind)
    local running = d.running == true
    if running and addSound then
        pcall(addSound, obj, sq:getX(), sq:getY(), sq:getZ(), spec.noise, spec.noise)
    end
    setFumes(obj, d, running and d.indoors == true)
    -- Worn fittings: gas lost (already taken in the step) and a chance of
    -- fire for the hours it ran, at most one an hour.
    d.leaking = (running and (d.condition or 100) < MM.PROPANE_LEAK_BELOW) or nil
    if d.leaking and (g.ran or 0) > 0 and (not d.fireAt or now - d.fireAt >= 1) then
        if roll(MM.propaneFireChance(d.condition, g.ran)) then
            local cell = worldCell()
            if cell and IsoFireManager and IsoFireManager.StartFire then
                pcall(IsoFireManager.StartFire, cell, sq, true, 100)
                d.fireAt = now
            end
        end
    end
    local state = ((d.condition or 100) <= 35 and "broken") or (running and "running") or "off"
    R.setVariant(obj, state)
    obj:transmitModData()
end

--- The amplifier's live-world costs for one machine that is making power:
--  noise that draws zombies, and sparks that can start a fire once it is
--  worn. `baseNoise` is the machine's own noise in tiles (0 for the silent
--  kinds); `hours` is the step just taken.
local function ampEffects(obj, baseNoise, hours, now)
    local sq = obj and try(obj, "getSquare")
    if not (sq and alive(obj)) then return end
    local d = P.data(obj)
    if addSound then
        local r = MM.ampNoise(baseNoise)
        pcall(addSound, obj, sq:getX(), sq:getY(), sq:getZ(), r, r)
    end
    if (d.condition or 100) < MM.AMP_FIRE_BELOW and (not d.ampFireAt or now - d.ampFireAt >= 1) then
        if roll(MM.ampFireChance(d.condition, hours)) then
            local cell = worldCell()
            if cell and IsoFireManager and IsoFireManager.StartFire then
                pcall(IsoFireManager.StartFire, cell, sq, true, 100)
                d.ampFireAt = now
                obj:transmitModData()
            end
        end
    end
end

--- One row per wired power fixture for the controller's SOURCES page: what it
--  is, its state, and the watts it delivers at the controller. Plain values only,
--  since it travels as controller ModData.
local function sourceRows(rec, src)
    local o = rec.dpm or {}
    local eff = src.invEff or 1
    local rows = {}
    local function add(obj, kind, tier, state, w, cond)
        local sq = try(obj, "getSquare")
        rows[#rows + 1] = { k = kind, t = tier, s = state, w = math.floor((w or 0) + 0.5), c = cond,
                            x = sq and sq:getX() or 0, y = sq and sq:getY() or 0 }
        return rows[#rows]
    end
    for _, p in ipairs(src.pedals or {}) do
        local info = R.describe(p.obj)
        add(p.obj, "pedal", info and info.tier, (p.watts or 0) > 0 and "riding" or "idle", p.watts, P.data(p.obj).condition)
    end
    for _, c in ipairs(src.cars or {}) do
        local r = add(c.obj, "car", "standard", "running", (c.watts or 0) * eff, c.condition)
        r.x, r.y = c.x or r.x, c.y or r.y
    end
    for _, h in ipairs(src.hydros or {}) do
        add(h.obj, "hydro", "standard", h.motion or "still", (h.watts or 0) * eff, h.condition)
    end
    for _, tb in ipairs(src.turbines or {}) do
        local r = add(tb.obj, "windmill", tb.tier, MM.turbineState(tb.motion, P.data(tb.obj).condition),
                      (tb.watts or 0) * eff, P.data(tb.obj).condition)
        r.v = math.floor((tb.ms or 0) * 10 + 0.5) / 10
    end
    for _, obj in ipairs(o.windmill or {}) do
        local d = alive(obj) and P.data(obj)
        local info = d and d.indoors and R.describe(obj)
        if info then add(obj, "windmill", info.tier, "indoors", 0, d.condition) end
    end
    for _, b in ipairs(src.boilers or {}) do
        local d = P.data(b.obj)
        add(b.obj, "steam", b.tier, boilerState(d.condition, b.motion, d.lit, d.heat), (b.watts or 0) * eff, d.condition)
    end
    for _, g in ipairs(src.gens or {}) do
        local d = P.data(g.obj)
        local st = ((g.condition or 100) <= 35 and "broken") or (g.running and "running") or "off"
        local r = add(g.obj, g.kind == "petrol" and "petrol" or "propane", g.tier, st, (g.watts or 0) * eff, g.condition)
        r.v = math.floor(MM.propaneFuel(g) * 10 + 0.5) / 10
    end
    table.sort(rows, function(a, b) if a.w ~= b.w then return a.w > b.w end
        if a.k ~= b.k then return a.k < b.k end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y end)
    return rows
end

local function rowsSignature(rows)
    local t = {}
    for i = 1, #rows do local r = rows[i]; t[i] = table.concat({ r.k, r.t or "", r.s, r.w, r.c or "", r.v or "", r.x, r.y }, ",") end
    return table.concat(t, ";")
end

--- Everything that must only happen in the live world, never in a catch-up
--  replay: sprites, a tail fin turning, storm damage (a replay reuses
--  today's weather for every missed hour), engine noise, fire, explosion.
local function liveEffects(rec, src, dt)
    local o = rec.dpm or { pedal = {}, windmill = {}, steam = {}, propane = {} }
    local now = UM.worldHours and UM.worldHours() or (DazedPower.Env and DazedPower.Env.worldHours
                and DazedPower.Env.worldHours()) or 0

    for i = 1, #(src.pedals or {}) do
        local p = src.pedals[i]
        if alive(p.obj) then
            R.setVariant(p.obj, p.watts > 0 and "on" or "off")
            p.obj:transmitModData()
        end
    end

    -- Hydro wheels: turn while wet, wear slowly, show it.
    for i = 1, #(src.hydros or {}) do
        local h = src.hydros[i]
        if alive(h.obj) then
            local d = P.data(h.obj)
            if h.motion == "turning" then d.condition = math.max(0, (d.condition or 100) - MM.HYDRO_WEAR * dt) end
            R.setVariant(h.obj, h.motion == "turning" and "turning" or "still")
            h.obj:transmitModData()
        end
    end

    -- Windmills: indoor ones sit still; the rest yaw, wear and show it.
    for i = 1, #o.windmill do
        local obj = o.windmill[i]
        local d = alive(obj) and P.data(obj)
        if d and d.indoors then
            d.windWatts, d.windMs = 0, 0
            R.setVariant(obj, MM.turbineState("still", d.condition))
            obj:transmitModData()
        end
    end
    for i = 1, #(src.turbines or {}) do
        local tb = src.turbines[i]
        local obj = tb.obj
        if alive(obj) then
            local info = R.describe(obj)
            local d = P.data(obj)
            local spec = MM.windSpec(tb.tier)
            local facing = info.facing
            if spec.tracks then facing = MM.trackFacing(src.windFrom, info.facing) end
            local lost = MM.turbineDamage(tb.tier, tb.ms or 0, tb.motion == "turning", dt, tb.amp)
            if lost > 0 then d.condition = math.max(0, (d.condition or 100) - lost) end
            d.windWatts, d.windMs = tb.watts or 0, tb.ms or 0
            d.windKph, d.windFrom = src.windKph, src.windFrom
            d.overspeed = (spec.safe ~= nil and (tb.ms or 0) > spec.safe) or nil
            R.setVariant(obj, MM.turbineState(tb.motion, d.condition), facing)
            obj:transmitModData()
        end
    end

    -- Boilers: noise while the engine runs; a dry one's fire and explosion.
    for i = 1, #(src.boilers or {}) do boilerEffects(src.boilers[i], now) end
    -- Propane generators: sprite, noise, fumes, a worn one's fire.
    for i = 1, #(src.gens or {}) do genEffects(src.gens[i], now) end

    -- The amplifier: noise and sparks on every amplified machine making power;
    -- an amplified solar array also wears (its only wear is weather).
    for i = 1, #(src.pedals or {}) do
        local p = src.pedals[i]
        if p.amp and (p.watts or 0) > 0 then ampEffects(p.obj, 0, dt, now) end
    end
    for i = 1, #(src.turbines or {}) do
        local tb = src.turbines[i]
        if tb.amp and (tb.watts or 0) > 0 then ampEffects(tb.obj, 0, dt, now) end
    end
    for i = 1, #(src.boilers or {}) do
        local b = src.boilers[i]
        if b.amp and (b.watts or 0) > 0 then ampEffects(b.obj, MM.steamSpec(b.tier).noise, dt, now) end
    end
    for i = 1, #(src.gens or {}) do
        local g = src.gens[i]
        if g.amp and (g.watts or 0) > 0 then ampEffects(g.obj, MM.propaneSpec(g.tier, g.kind).noise, dt, now) end
    end
    for i = 1, #(src.solar or {}) do
        local sa = src.solar[i]
        if (sa.extra or 0) > 0 and alive(sa.obj) then
            local d = P.data(sa.obj)
            d.condition = math.max(0, (d.condition or 100) - MM.SOLAR_AMP_WEAR * dt)
            sa.obj:transmitModData()
            ampEffects(sa.obj, 0, dt, now)
        end
    end

    -- The controller's breakdown, for anything that wants to show it. Its
    -- own total (d.gen) already includes all of this: Dazed Power computed it.
    local gen = P.objectAt(rec.x, rec.y, rec.z, "controller")
    if gen then
        local d = P.data(gen)
        d.dpmPedalW, d.dpmWindW, d.dpmSteamW = src.pedalW or 0, src.windW or 0, src.steamW or 0
        d.dpmGenW = src.genW or 0
        d.dpmSoc = src.soc          -- the battery charge the auto-start last read, percent
        d.dpmRiding, d.dpmThrottle = src.riding or 0, src.throttle
        d.dpmSolarAmpW = src.solarAmpW or 0
        -- The GEN page's figures, from the same step (DP_GenPanel).
        if DazedPower.GenPanel then DazedPower.GenPanel.mirror(gen, d, src, dt) end
        local rows = sourceRows(rec, src)
        local sig = rowsSignature(rows)
        if sig ~= d.dpmRowsSig then
            d.dpmRows, d.dpmRowsSig = rows, sig
            gen:transmitModData()
        end
    end
end

if not B.wrappedUpdate then
    B.wrappedUpdate = true

    local update0 = S.updateController
    function S.updateController(rec, dt, hoursAgo, wet)
        local outer = CTX
        CTX = { rec = rec, at = hoursNow() - math.max(0, hoursAgo or 0), live = (hoursAgo or 0) <= 0 }
        local ok, err = pcall(update0, rec, dt, hoursAgo, wet)
        local ctx = CTX
        CTX = outer
        -- Put back the LOADS tables billWater patched, unless the tick already replaced them.
        if ctx.kindsP and rec.kinds == ctx.kindsP then rec.kinds = ctx.kinds0 end
        if ctx.idleP and rec.idleKinds == ctx.idleP then rec.idleKinds = ctx.idle0 end
        if not ok then error(err, 0) end
        if ctx.src and (hoursAgo or 0) <= 0 then
            local ok2, err2 = pcall(liveEffects, rec, ctx.src, dt or 0)
            if not ok2 then print("DazedPower: live effects failed: " .. tostring(err2)) end
        end
        -- Nothing of ours is wired any more: take the SOURCES page's rows down.
        if not ctx.src and (hoursAgo or 0) <= 0 then
            local c = P.objectAt(rec.x, rec.y, rec.z, "controller")
            local cd = c and P.data(c)
            if cd and (cd.dpmRows ~= nil or cd.bkRows ~= nil or (cd.bkW or 0) ~= 0) then
                cd.dpmRows, cd.dpmRowsSig = nil, nil
                cd.dpmPedalW, cd.dpmWindW, cd.dpmSteamW, cd.dpmGenW, cd.dpmSolarAmpW = 0, 0, 0, 0, 0
                -- and the GEN page's, or the last engine cut away would still show RUNNING
                cd.bkRows, cd.bkW, cd.bkCap, cd.bkN, cd.bkMore, cd.bkSig = nil, 0, 0, 0, 0, nil
                c:transmitModData()
            end
        end
    end

    -- The away-snapshot carries plain copies of our windmills and boilers,
    -- so the away-simulation (which steps M.step on it) counts them. Their
    -- fuel runs down in the SNAPSHOT only; the real hopper is settled by the
    -- controller's own catch-up replay when it is loaded again.
    local D = DazedPower.Distrib
    if D and D.capture then
        local capture0 = D.capture
        function D.capture(rec, snap)
            capture0(rec, snap)
            local src = CTX and CTX.src
            if not (src and ModData and ModData.getOrCreate and D.REMOTE_TAG) then return end
            local store = ModData.getOrCreate(D.REMOTE_TAG)
            local entry = store[rec.key]
            if type(entry) ~= "table" then return end
            local turbines, boilers = {}, {}
            for i = 1, #(src.turbines or {}) do
                local t = src.turbines[i]
                turbines[i] = { tier = t.tier, facing = t.facing, condition = t.condition, z = t.z, amp = t.amp }
            end
            for i = 1, #(src.boilers or {}) do
                local b = src.boilers[i]
                boilers[i] = { tier = b.tier, lit = b.lit, fuel = b.fuel, water = b.water,
                               heat = b.heat, condition = b.condition, amp = b.amp }
            end
            local gens = {}
            for i = 1, #(src.gens or {}) do
                local g = { tier = src.gens[i].tier, amp = src.gens[i].amp }
                for _, f in ipairs(B.GEN_FIELDS) do g[f] = src.gens[i][f] end
                gens[i] = g
            end
            local solar = {}
            for i = 1, #(src.solar or {}) do
                local e = src.solar[i].entry
                solar[i] = { entry = { facing = e.facing, mount = e.mount, tier = e.tier,
                    panels = e.panels, condition = e.condition, soiling = e.soiling, snow = e.snow } }
            end
            local hydros = {}
            for i = 1, #(src.hydros or {}) do
                local h = src.hydros[i]
                hydros[i] = { condition = h.condition, wet = h.wet }
            end
            entry.dpm = { turbines = turbines, boilers = boilers, pedals = {}, gens = gens, solar = solar, hydros = hydros }
        end
    end
end

----------------------------------------------------------- loading parts in

--- Our power sources register with Dazed Power's simulation as they stream
--  in, the same call Dazed Power makes for its own (S.register is generic for
--  any part that is not a controller or a lamp). The wind instruments are
--  left out, the way Dazed Power leaves out its lamps: they are never part of a
--  system, and DPM_Instruments registers them with a callback of its own
--  (one sprite name keeps only one callback per priority).
-------------------------------------------------------- parts cut loose

--  A part only moves while its controller steps it (liveEffects), so one
--  that falls out of its system -- its cable cut, its controller lifted, a
--  rewire that left it behind -- used to stay frozen in its last sprite:
--  a windmill cut loose kept spinning forever. Dazed Power itself marks the
--  moment for us: whatever drops a part from a system clears the part's
--  `sys` (DP_System's releaseClaim), whichever way it happened.
--
--  So every loaded power part of ours is kept in a list as it streams in,
--  and once a game minute each one with no system is settled:
--
--    windmill  stops: nothing is drawing on it, its brake holds it. Still
--              shows a broken blade if it is badly worn.
--    pedal     shows nobody riding: there is no load to pedal against.
--    steam     a fire does not go out because a cable was cut. A loose
--              boiler keeps burning what is in it, with no load (a governor
--              idles it), its steam vented; it cools once the fire is out,
--              and a dry one is exactly as dangerous as on a cable. So a
--              lit boiler still has to be damped by hand, and the pick-up
--              lock lifts once it has really cooled.
--
--  Only `sys` empty counts as loose, never "not in the list of the last
--  relink": a wired boiler stepped here as well would burn twice.

B.LOOSE_MAX_STEP = 1          -- hours; a longer gap was time unloaded, not watched
B.loaded = B.loaded or setmetatable({}, { __mode = "k" })

local function isLoose(d)
    return d.sys == nil or d.sys == ""
end

local function worldHoursNow()
    local gt = getGameTime and getGameTime()
    return gt and gt:getWorldAgeHours() or 0
end

--- Settle one loose part. Returns false once it is no longer ours to track.
local function settleLoose(obj, now)
    if not alive(obj) then return false end
    local info = R.describe(obj)
    if not info or R.INSTRUMENT[info.kind] then return false end
    local d = P.data(obj)
    if not isLoose(d) then
        d.looseAt = nil
        return true
    end
    local changed = false
    if info.kind == "windmill" then
        if (d.windWatts or 0) ~= 0 or d.windKph ~= nil or d.overspeed then changed = true end
        d.windWatts, d.windMs, d.overspeed = 0, 0, nil
        d.windKph, d.windFrom = nil, nil
        changed = R.setVariant(obj, MM.turbineState("still", d.condition)) or changed
    elseif info.kind == "hydro" then
        changed = R.setVariant(obj, "still") or changed
    elseif info.kind == "pedal" then
        if (d.pedalWatts or 0) ~= 0 then changed = true end
        d.pedalWatts = 0
        changed = R.setVariant(obj, "off") or changed
    elseif info.kind == "steam" then
        local gap = now - (d.looseAt or now)
        local dt = (gap > 0 and gap <= B.LOOSE_MAX_STEP) and gap or 0
        d.looseAt = now
        local sq = obj:getSquare()
        if sq and not ME.isOutside(sq) then d.indoors, d.lit = true, false else d.indoors = nil end
        local b = { obj = obj, tier = info.tier, lit = d.lit == true, fuel = d.fuel or 0,
                    water = d.water or 0, heat = d.heat or 0, condition = d.condition or 100,
                    amp = d.amp == true }
        local w, motion, dry = MM.steamStep(b, dt, 0)
        b.watts, b.motion, b.dry = w, motion, dry
        d.fuel, d.water, d.heat = b.fuel, b.water, b.heat
        d.lit, d.condition = b.lit == true, b.condition
        d.steamWatts = 0                      -- made, but going nowhere
        d.dry = ((dry or 0) > 0) or nil
        boilerEffects(b, now)                 -- sprite, noise, a dry one's danger; transmits
        return true
    elseif info.kind == "propane" or info.kind == "petrol" then
        -- Loose, there is no battery to read: AUTO stops it; a switch left
        -- ON keeps it turning over at idle, burning gas for nothing.
        local gap = now - (d.looseAt or now)
        local dt = (gap > 0 and gap <= B.LOOSE_MAX_STEP) and gap or 0
        d.looseAt = now
        local sq = obj:getSquare()
        d.indoors = (sq and not ME.isOutside(sq)) or nil
        local g = genEntry(obj, info, d)
        g.ambient, g.now = g.liveAir, now
        local failedAt = g.coldFailAt
        MM.propaneSwitch(g, nil)
        if g.coldFail and g.coldFailAt ~= failedAt then pcall(B.coldNote, obj) end
        g.watts, g.ran, g.leak = MM.propaneStep(g, dt, 0)
        g.ran = dt > 0 and g.ran or 0
        for _, f in ipairs(B.GEN_FIELDS) do d[f] = g[f] end
        d.genWatts = 0
        genEffects(g, now)                    -- sprite, noise, fumes, fire; transmits
        return true
    end
    if changed then obj:transmitModData() end
    return true
end

function B.sweepLoose()
    local now = worldHoursNow()
    for obj in pairs(B.loaded) do
        local ok, keep = pcall(settleLoose, obj, now)
        if not ok then
            print("DazedPower: settling a loose part failed: " .. tostring(keep))
        elseif not keep then
            B.loaded[obj] = nil
        end
    end
end

if not B.sweepHooked then
    B.sweepHooked = true
    Events.EveryOneMinute.Add(B.sweepLoose)
end

local function registerSprites()
    local function onLoad(obj)
        S.register(obj)
        -- Tracked for the loose sweep, and settled straight away: a save made
        -- before this fix can hold a windmill cut loose mid-spin.
        B.loaded[obj] = true
        pcall(settleLoose, obj, worldHoursNow())
    end
    for row = 1, #P.ROWS do
        if P.SOURCE_KINDS[P.ROWS[row].kind] then
            for col = 0, P.COLS - 1 do
                local name = P.spriteName((row - 1) * P.COLS + col)
                MapObjects.OnLoadWithSprite(name, onLoad, 6)
                MapObjects.OnNewWithSprite(name, onLoad, 6)
            end
        end
    end
end
registerSprites()
Events.OnGameStart.Add(registerSprites)

B.internals = { collect = collect, liveSources = liveSources, stepSources = stepSources,
                liveEffects = liveEffects, writeBoilers = writeBoilers, settleLoose = settleLoose }
return B
