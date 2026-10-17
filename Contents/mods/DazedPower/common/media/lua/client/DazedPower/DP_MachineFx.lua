--[[ DazedPower -- the engines' effects on screen: the shared part (0.13.0).

     The steam engine's fire (DP_SteamFx, 0.12.0) and the other generators' running frames (DP_GenFx: wood gas,
     petrol, propane) all run through here: one list of engines, one cull, one set of lights and the same two
     Dazed Core Tick jobs. Each kind registers what it shows (M.register): its frame cycle, its one-frame looks
     and its light. Purely cosmetic and only on this machine, like the spinning windmills (DP_WindSpin): nothing is
     sent, nothing is written to ModData, and the server keeps showing the plain sprites clients sync from.

     Cost. Nothing at all while no such engine is loaded: the engines come from DPM_Machines (map loads, placing,
     its sweep), and the two jobs exist only while there is something for them to do.
       DazedPower.steamfx        once a second while any registered engine is loaded: drops the ones that left (and
                                 their lights), culls to RANGE squares of a local player and to the screen, picks
                                 each one's look, keeps the lights right.
       DazedPower.steamfxFrames  every FRAME_MS while at least one engine is cycling frames near and on screen: one
                                 sprite swap per engine when its frame changes (the registered sprite object, no strings).
     (The job names kept the steam pilot's, so nothing new appears in Core's job list.) Both stop while single player
     is paused. A culled engine keeps the frame it shows (it reads back as the same state, DP_Parts.ALIAS), so walking
     away costs no swap. A light is IsoLightSource + IsoCell.addLamppost, at most MAX_LIGHTS of them across every kind,
     and it goes with setActive(false) + removeLamppost (the two calls known safe with Build 42's lights): when the
     engine changes look or band, leaves range, is picked up, destroyed or unloaded (OnObjectAboutToBeRemoved, else
     the scan's alive check within a second), when the sandbox option goes off, and at the next game start.

     Sandbox: Machine effects (MachineEffects, on) governs every kind. Off puts every plain sprite back and removes
     every light. A kind may add its own switch on top (spec.enabled: the windmill keeps its 0.4 "spinning blades"
     tick box); off, that kind's machines go back to their plain sprites.

     Turning machines (0.14.0): a kind may pick its look from more than its state (spec.modeOf: the windmill's gale
     blur and broken rocking follow the wind), cycle more than one look (spec.cycles: spin and rock), and walk its
     frames at a speed of its own (spec.rate, frames a second: the windmill with the wind, the treadwheel with its
     zombie, the water wheel with its condition). Rated cycles keep a phase per machine that only advances while the
     game runs, and while any is on screen the frame job runs every FAST_MS instead of FRAME_MS (still one job). The
     windmill's spinning blades (DP_WindSpin, its own per-frame tick until 0.13) and the water wheel, treadwheel and
     windsock (DP_TurnFx) register here.
]]

require "DazedCore/DC_Tick"
require "DazedPower/DP_Parts"
require "DazedPower/DPM_Model"
require "DazedPower/DPM_Machines"

DazedPower = DazedPower or {}
DazedPower.MachineFx = DazedPower.MachineFx or {}
local M = DazedPower.MachineFx
local P = DazedPower.Parts

M.OPTION = "MachineEffects"
M.RANGE = 25                 -- squares from a local player (either axis) within which an engine shows its effects
M.FLOORS = 2                 -- and floors above or below
M.SCAN_MS = 1000
M.FRAME_MS = 150             -- one frame of any fixed-speed cycle
M.FAST_MS = 40               -- the frame job's period while a rated cycle (a speed of its own) is on screen
M.MAX_DT = 0.25              -- seconds a rated cycle may advance in one step (a hitch does not spin it on)
M.MAX_LIGHTS = 8             -- at most this many effect lights at once, of every kind together, the first found
M.DARK_BELOW = 0.6           -- ClimateManager day light strength under which an engine casts light
M.SCAN_ID, M.FRAME_ID = "DazedPower.steamfx", "DazedPower.steamfxFrames"

M.kinds = M.kinds or {}      -- kind -> spec (M.register)
M.tracked = M.tracked or {}  -- object -> entry { obj, spec, x, y, z, offset, mode, f, spr, light, lightKey }
M.count = M.count or 0       -- entries in tracked (Kahlua has no next)
M.active = M.active or {}    -- entries cycling frames now (near, on screen, in their cycling look)
M.lights = M.lights or 0     -- light sources this file has in the cell
M.scanJob, M.frameJob = M.scanJob or false, M.frameJob or false
M.frameMs = M.frameMs or nil -- the period the frame job was registered with
M.lastFrameT = nil           -- when the frame job last stepped the rated cycles (nil: paused or just started)

local spriteNames = {}       -- kind -> tier -> frame or state -> facing -> sprite name (false: none)
local spriteObjs = {}        -- sprite name -> registered IsoSprite (false: none)

------------------------------------------------------------------ registration and pure parts, for the tests

--- Register what one kind shows. spec = {
--    kind   = "steam",                         the logical kind (the plain sprites' kind)
--    modes  = { running = "fire", warming = "embers" },   logical state -> look; a state not listed shows plain
--    cycle  = "fire",                          the look that walks `frames` (nil: none)
--    frames = { "fire1", ... },                the frame names of that cycle (the alias rows' states)
--    still  = { embers = "embers" },           one-frame looks -> their frame name (or a plain state's name)
--    light  = function(mode, tier, d) -> { radius, r, g, b, band } or nil   (d: the synced ModData, may be nil)
--   optional, for the turning machines (0.14.0):
--    modeOf  = function(state, tier, d) -> look or nil   replaces `modes` when the look needs more than the state
--    cycles  = { spin = { "spin1", ... }, rock = { "broken", "broken", "wobble" } }   more looks that walk frames
--              (a frame may name a plain state); `cycle`/`frames` is folded in
--    rate    = function(mode, tier, d) -> frames a second   the cycle's own speed (nil: one frame per FRAME_MS)
--    enabled = function() -> bool              a switch of the kind's own on top of Machine effects
--  }
function M.register(spec)
    spec.still = spec.still or {}
    spec.frames = spec.frames or {}
    spec.cycles = spec.cycles or {}
    if spec.cycle then spec.cycles[spec.cycle] = spec.frames end
    local longest = 1
    for _, fr in pairs(spec.cycles) do longest = math.max(longest, #fr) end
    spec.longest = longest
    M.kinds[spec.kind] = spec
    return spec
end

--- The look for a machine of a registered spec, from its logical state, tier and synced ModData; nil: plain.
function M.lookOf(spec, state, tier, d)
    if spec.modeOf then return spec.modeOf(state, tier, d) end
    return spec.modes and spec.modes[state] or nil
end

--- The sprite a kind shows in `look` at frame step `step` (any number; it wraps), or nil when the look is unknown.
function M.pickLook(kind, tier, look, facing, step)
    local spec = M.kinds[kind]
    if not spec or not look then return nil end
    local fr = spec.cycles[look]
    if fr then return M.spriteName(kind, tier, fr[(math.floor(step or 0) % #fr) + 1], facing) end
    if spec.still[look] then return M.spriteName(kind, tier, spec.still[look], facing) end
    return nil
end

--- The sandbox option; on unless switched off.
function M.enabled()
    return P.sandbox(M.OPTION) ~= false
end

--- The look for a kind's logical state, or nil (plain sprite).
function M.mode(kind, state)
    local spec = M.kinds[kind]
    return spec and spec.modes[state] or nil
end

--- The engine's logical state. A plain sprite says it (the server just set it); a frame we showed is only as new as
--  the last look we picked, so then the synced ModData answers, then the frame's own state.
function M.stateOf(info, d)
    if not info.frame then return info.state end
    return (d and d.state) or info.state
end

--- Sprite name for an engine of `kind` and `tier` showing `frame` (a frame name, or a plain state), memoised.
function M.spriteName(kind, tier, frame, facing)
    local byTier = spriteNames[kind]
    if not byTier then byTier = {} spriteNames[kind] = byTier end
    local byFrame = byTier[tier]
    if not byFrame then byFrame = {} byTier[tier] = byFrame end
    local byFacing = byFrame[frame]
    if not byFacing then byFacing = {} byFrame[frame] = byFacing end
    local n = byFacing[facing]
    if n == nil then
        n = P.sprite(kind, "ground", tier, frame, facing) or false
        byFacing[facing] = n
    end
    return n or nil
end

--- Which sprite an engine of `kind` shows for `state` at frame step `step` (any integer; it wraps). `d`, the synced
--  ModData, only matters to a kind whose look needs more than its state (spec.modeOf).
function M.pick(kind, tier, state, facing, step, d)
    local spec = M.kinds[kind]
    local m = spec and M.lookOf(spec, state, tier, d)
    return M.pickLook(kind, tier, m, facing, step) or M.spriteName(kind, tier, state, facing)
end

--- A light that follows the load: `watts` against `rated`, in three bands so a wavering load does not rebuild it.
--  radius runs from radii[1] (no load) to radii[2] (full), the colour `rgb` from 60% to full brightness.
function M.loadLight(watts, rated, radii, rgb)
    local load = math.max(0, math.min(1, (tonumber(watts) or 0) / rated))
    local band = (load >= 0.66 and 2) or (load >= 0.25 and 1) or 0
    local k = band / 2
    local lo, hi = radii[1], radii[2]
    local glow = 0.6 + 0.4 * k
    return { radius = math.floor(lo + (hi - lo) * k + 0.5), r = rgb[1] * glow, g = rgb[2] * glow, b = rgb[3] * glow,
             band = band }
end

------------------------------------------------------------------ engine calls, all guarded

local function paused()
    local ok, v = pcall(function() return isGamePaused and isGamePaused() end)
    if ok and v then return true end
    ok, v = pcall(function() return getGameSpeed and getGameSpeed() end)
    return ok and v == 0
end
M.paused = paused

local function now() return getTimestampMs and getTimestampMs() or 0 end

local function dark()
    local cm = getClimateManager and getClimateManager()
    local v = cm and P.try(cm, "getDayLightStrength")
    if type(v) ~= "number" then return true end
    return v < M.DARK_BELOW
end
M.dark = dark

local function spriteObj(name)
    local s = spriteObjs[name]
    if s == nil then
        s = (getSprite and getSprite(name)) or false
        spriteObjs[name] = s
    end
    return s or nil
end

--- Show sprite `name` on the object (the registered sprite, so no new sprite per swap); true when it changed.
local function show(obj, name)
    if not name then return false end
    local cur = P.try(obj, "getSprite")
    if cur and cur:getName() == name then return false end
    local s = spriteObj(name)
    if not s then return false end
    return (pcall(obj.setSprite, obj, s))
end
M.show = show

local function dropLight(e)
    if not e.light then return end
    local light, cell = e.light, getCell and getCell()
    pcall(function() light:setActive(false) end)
    if cell then pcall(function() cell:removeLamppost(light) end) end
    e.light, e.lightKey = nil, nil
    M.lights = math.max(0, M.lights - 1)
end
M.dropLight = dropLight

local function setLight(e, want)
    local key = want and (want.radius .. "|" .. (want.band or "e")) or nil
    if key == e.lightKey then return end
    dropLight(e)
    if not want or M.lights >= M.MAX_LIGHTS then return end
    if not (IsoLightSource and IsoLightSource.new) then return end
    local cell = getCell and getCell()
    if not cell then return end
    local ok, light = pcall(IsoLightSource.new, e.x, e.y, e.z, want.r, want.g, want.b, want.radius)
    if not ok or not light then return end
    if not pcall(function() cell:addLamppost(light) end) then return end
    e.light, e.lightKey = light, key
    M.lights = M.lights + 1
end

------------------------------------------------------------------ jobs

local frameTick -- forward

-- The frame job on or off; `fast` (a rated cycle on screen) runs it every FAST_MS instead of FRAME_MS.
local function setFrameJob(on, fast)
    local ms = on and (fast and M.FAST_MS or M.FRAME_MS) or nil
    if on == M.frameJob and ms == M.frameMs then return end
    M.frameJob, M.frameMs = on, ms
    if on then DazedCore.Tick.every(M.FRAME_ID, ms, frameTick) else DazedCore.Tick.remove(M.FRAME_ID); M.lastFrameT = nil end
end

local function forget(obj)
    local e = M.tracked[obj]
    if not e then return end
    dropLight(e)
    M.tracked[obj] = nil
    M.count = M.count - 1
end

-- Put the plain sprite back on one machine if it shows one of our frames (a machine gone from the cell is left alone).
local function restoreOne(obj, e)
    if P.alive(obj) then
        local spr = P.try(obj, "getSprite")
        local info = spr and P.spriteInfo(spr:getName())
        if info and info.kind == e.spec.kind and info.frame ~= nil then
            local md = obj:hasModData() and obj:getModData()
            show(obj, M.spriteName(info.kind, info.tier, M.stateOf(info, md and md.dazedpower), info.facing))
        end
    end
    e.mode, e.f, e.spr, e.cyc = nil, nil, nil, nil
end
M.restoreOne = restoreOne

--- Put a plain sprite back on everything showing our frame, and take every light out (option off, or a reset).
--  Since 0.14.0 that includes a machine culled while it showed a frame (it kept the frame, see the scan).
function M.restoreAll()
    for obj, e in pairs(M.tracked) do
        dropLight(e)
        restoreOne(obj, e)
    end
    M.active = {}
    setFrameJob(false)
end

-- The living local players, in one table reused every scan; returns it and the count.
local playerList = {}
local function localPlayers()
    local n = 0
    for i = 0, (getNumActivePlayers and getNumActivePlayers() or 0) - 1 do
        local p = getSpecificPlayer(i)
        if p and not p:isDead() then n = n + 1 playerList[n] = p end
    end
    for i = n + 1, #playerList do playerList[i] = nil end
    return playerList, n
end

local function nearAny(e, players, np)
    for i = 1, np do
        local p = players[i]
        if math.abs(p:getX() - e.x) <= M.RANGE and math.abs(p:getY() - e.y) <= M.RANGE
                and math.abs(p:getZ() - e.z) <= M.FLOORS then
            return true
        end
    end
    return false
end

local function onScreen(sq)
    local v = P.try(sq, "IsOnScreen")
    if v == nil then return true end            -- no such call: take it as seen
    return v == true
end
M.onScreen = onScreen

--- The once-a-second pass. Public for the tests.
function M.scan()
    if M.count == 0 then
        DazedCore.Tick.remove(M.SCAN_ID); M.scanJob = false
        setFrameJob(false)
        return
    end
    if not M.enabled() then
        if M.lights > 0 or #M.active > 0 or M.shown then M.restoreAll() end
        M.shown = false
        return
    end
    if paused() then return end
    local players, np = localPlayers()
    local isDark = dark()
    local active, na, fast = M.active, 0, false
    local kindOn = {}            -- a kind's own switch, asked once a scan
    for obj, e in pairs(M.tracked) do
        if not P.alive(obj) then
            forget(obj)
        else
            local spec = e.spec
            local spr = obj:getSprite()
            local info = spr and P.spriteInfo(spr:getName())
            if not info or info.kind ~= spec.kind then
                forget(obj)
            else
                local on = kindOn[spec.kind]
                if on == nil then
                    on = spec.enabled == nil or spec.enabled() ~= false
                    kindOn[spec.kind] = on
                end
                local near = on and np > 0 and nearAny(e, players, np)
                local md = obj:hasModData() and obj:getModData()
                local d = md and md.dazedpower
                local mode = near and M.lookOf(spec, M.stateOf(info, d), info.tier, d) or nil
                setLight(e, (mode and isDark and spec.light) and spec.light(mode, info.tier, d) or nil)
                if not on then
                    -- The kind's own switch is off: its plain sprite, whatever it showed.
                    if info.frame ~= nil or e.mode then restoreOne(obj, e) end
                elseif mode and onScreen(obj:getSquare()) then
                    M.shown = true
                    if e.mode ~= mode or e.facing ~= info.facing then e.f, e.spr = nil, nil end
                    e.mode, e.tier, e.facing = mode, info.tier, info.facing
                    local cyc = spec.cycles[mode]
                    e.cyc = cyc
                    if not cyc then
                        show(obj, M.spriteName(spec.kind, info.tier, spec.still[mode], info.facing))
                        e.spr = obj:getSprite()
                    else
                        e.rate = spec.rate and spec.rate(mode, info.tier, d) or nil
                        if e.rate then fast = true end
                        na = na + 1
                        active[na] = e
                    end
                else
                    -- Culled: it keeps the frame it shows (same logical state), and costs nothing more.
                    e.mode = nil
                end
            end
        end
    end
    for i = na + 1, #active do active[i] = nil end
    setFrameJob(na > 0, fast)
end

-- Is a machine whose sprite someone else just changed (the server's state flip) still in a cycling look?
local function stillCycling(e, obj, cur)
    local spec = e.spec
    local info = P.spriteInfo(cur:getName())
    if not info or info.kind ~= spec.kind then return false end
    local md = obj:hasModData() and obj:getModData()
    local d = md and md.dazedpower
    local look = info.frame ~= nil and e.mode or M.lookOf(spec, info.state, info.tier, d)
    if look == nil or spec.cycles[look] == nil then return false end
    -- Follow the new sprite's facing and tier (a windmill yawing into the wind), and its look.
    if look ~= e.mode then e.mode, e.cyc = look, spec.cycles[look] end
    e.facing, e.tier = info.facing, info.tier
    return true
end

--- One frame step for every active engine. Public for the tests. A fixed-speed cycle's frame comes from the clock
--  (one per FRAME_MS); a rated one's from its own phase, advanced by the time since the last step (at most MAX_DT)
--  times its rate, and never while paused.
function M.frames(t)
    if paused() then M.lastFrameT = nil return end
    t = t or now()
    local dt = M.lastFrameT and math.max(0, math.min(M.MAX_DT, (t - M.lastFrameT) / 1000)) or 0
    M.lastFrameT = t
    local active, keep = M.active, 0
    for i = 1, #active do
        local e = active[i]
        local obj, spec = e.obj, e.spec
        local cur = P.try(obj, "getSprite")
        local live = e.cyc ~= nil and cur ~= nil
        if live and cur ~= e.spr and e.spr ~= nil then
            -- Someone else changed the sprite (the server's state flip): still cycling only if it says so.
            live = stillCycling(e, obj, cur)
            if not live then e.mode, e.cyc = nil, nil end
        end
        if live then
            local cyc = e.cyc
            local n = #cyc
            local f
            if e.rate then
                e.phase = (e.phase or e.offset) + dt * e.rate
                f = math.floor(e.phase) % n
            else
                f = math.floor(t / M.FRAME_MS + e.offset) % n
            end
            if f ~= e.f or cur ~= e.spr then
                e.f = f
                show(obj, M.spriteName(spec.kind, e.tier, cyc[f + 1], e.facing))
                e.spr = P.try(obj, "getSprite")
            end
            keep = keep + 1
            active[keep] = e
        end
    end
    for i = keep + 1, #active do active[i] = nil end
    if keep == 0 then setFrameJob(false) end
end
frameTick = function(t) M.frames(t) end

--- Start following an object if it is an engine of a registered kind.
function M.consider(obj)
    if not obj or M.tracked[obj] then return end
    local spr = obj.getSprite and obj:getSprite()
    local info = spr and P.spriteInfo(spr:getName())
    local spec = info and M.kinds[info.kind]
    if not spec then return end
    local sq = obj:getSquare()
    if not sq then return end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    -- Engines side by side do not flicker in step.
    M.tracked[obj] = { obj = obj, spec = spec, x = x, y = y, z = z, offset = (x * 7 + y * 13) % spec.longest }
    M.count = M.count + 1
    if not M.scanJob then
        M.scanJob = true
        DazedCore.Tick.every(M.SCAN_ID, M.SCAN_MS, function() M.scan() end)
    end
end

--- A tracked engine about to leave the square (picked up, destroyed, a chunk going): its light goes now.
function M.onRemoved(obj)
    if obj and M.tracked[obj] then forget(obj) end
end

--- Forget everything without touching the engines (a new game: the old cell and its lights are gone), then take
--  the engines the machine list already holds again (the login area streams in before OnGameStart).
function M.reset()
    M.tracked, M.count, M.active, M.lights, M.shown = {}, 0, {}, 0, false
    DazedCore.Tick.remove(M.SCAN_ID); DazedCore.Tick.remove(M.FRAME_ID)
    M.scanJob, M.frameJob, M.frameMs, M.lastFrameT = false, false, nil, nil
    DazedPower.More.Machines.each(M.consider)
end

if Events and not M.hooked then
    M.hooked = true
    DazedPower.More.Machines.onAdd(M.consider)
    if Events.OnObjectAboutToBeRemoved then Events.OnObjectAboutToBeRemoved.Add(M.onRemoved) end
    if Events.OnGameStart then Events.OnGameStart.Add(M.reset) end
end

return M
