--[[ DazedPower -- a steam engine's fire, on screen (0.12.0).

     Purely cosmetic and only on this machine, like the spinning windmills (DP_WindSpin): nothing is sent, nothing
     is written to ModData, and the server keeps showing the plain sprites clients sync from.

       running  the firebox door open on four flicker frames (the steamfire rows fire1..fire4 of the sheet), the
                chimney smoke climbing a quarter puff a frame, and at night a warm light on the square that grows
                with the engine's load (steamWatts against its rating)
       warming  the door open on banked embers (one frame) and a dim red glow at night: an idle governed engine,
                one raising steam, or one cooling after its fuel ran out
       cold, broken  nothing; the plain sprite

     Cost. Nothing at all while no steam engine is loaded: the engines come from DPM_Machines (map loads, placing,
     its sweep), and the two Dazed Core Tick jobs below exist only while there is something for them to do.
       DazedPower.steamfx        once a second while any steam engine is loaded: drops the ones that left (and their
                                 lights), culls to RANGE squares of a local player and to the screen, picks each
                                 one's look, keeps the lights right.
       DazedPower.steamfxFrames  every FRAME_MS while at least one running engine is near and on screen: one sprite
                                 swap per engine when its frame changes (the registered sprite object, no strings).
     Both stop while single player is paused. A culled engine keeps the frame it shows (it reads back as the same
     state, DP_Parts.ALIAS), so walking away costs no swap. The light is IsoLightSource + IsoCell.addLamppost, and it
     goes with setActive(false) + removeLamppost (the two calls known safe with Build 42's lights): when the engine
     changes look or band, leaves range, is picked up, destroyed or unloaded (OnObjectAboutToBeRemoved, else the
     scan's alive check within a second), when the sandbox option goes off, and at the next game start.

     Sandbox: Machine effects (MachineEffects, on). Off puts every plain sprite back and removes every light.
]]

require "DazedCore/DC_Tick"
require "DazedPower/DP_Parts"
require "DazedPower/DPM_Model"
require "DazedPower/DPM_Machines"

DazedPower = DazedPower or {}
DazedPower.SteamFx = DazedPower.SteamFx or {}
local F = DazedPower.SteamFx
local P = DazedPower.Parts

F.OPTION = "MachineEffects"
F.RANGE = 25                 -- squares from a local player (either axis) within which an engine shows its fire
F.FLOORS = 2                 -- and floors above or below
F.SCAN_MS = 1000
F.FRAME_MS = 150             -- one flame frame; four make the loop (0.6 s)
F.MAX_LIGHTS = 8             -- at most this many fire lights at once, the first found
F.DARK_BELOW = 0.6           -- ClimateManager day light strength under which the fire casts light
F.SCAN_ID, F.FRAME_ID = "DazedPower.steamfx", "DazedPower.steamfxFrames"
F.FRAMES = { "fire1", "fire2", "fire3", "fire4" }
-- The light: radius in squares and colour, from banked embers to a fire under full load.
F.EMBER_LIGHT = { radius = 2, r = 0.45, g = 0.16, b = 0.05 }
F.FIRE_RADIUS = { 3, 7 }     -- no load to full load
F.FIRE_RGB = { 1.0, 0.55, 0.22 }

F.tracked = F.tracked or {}  -- object -> entry { obj, x, y, z, offset, mode, f, spr, light, lightKey }
F.count = F.count or 0       -- entries in tracked (Kahlua has no next)
F.active = F.active or {}    -- entries cycling flame frames now (near, on screen, running)
F.lights = F.lights or 0     -- light sources this file has in the cell
F.scanJob, F.frameJob = F.scanJob or false, F.frameJob or false

local spriteNames = {}       -- tier -> frame or state -> facing -> sprite name (false: none)
local spriteObjs = {}        -- sprite name -> registered IsoSprite (false: none)

------------------------------------------------------------------ pure parts, for the tests

--- The sandbox option; on unless switched off.
function F.enabled()
    return P.sandbox(F.OPTION) ~= false
end

--- The look for a steam engine's logical state: "fire", "embers" or nil (plain sprite).
function F.mode(state)
    if state == "running" then return "fire" end
    if state == "warming" then return "embers" end
    return nil
end

--- The engine's logical state. A plain sprite says it (the server just set it); a frame we showed is only as new as
--  the last look we picked, so then the synced ModData answers, then the frame's own state.
function F.stateOf(info, d)
    if not info.frame then return info.state end
    return (d and d.state) or info.state
end

--- Sprite name for a steam engine of `tier` showing `frame` (a fire frame, "embers", or a plain state), memoised.
function F.spriteName(tier, frame, facing)
    local byFrame = spriteNames[tier]
    if not byFrame then byFrame = {} spriteNames[tier] = byFrame end
    local byFacing = byFrame[frame]
    if not byFacing then byFacing = {} byFrame[frame] = byFacing end
    local n = byFacing[facing]
    if n == nil then
        n = P.sprite("steam", "ground", tier, frame, facing) or false
        byFacing[facing] = n
    end
    return n or nil
end

--- Which sprite the engine shows for `state` at flame step `step` (any integer; it wraps).
function F.pick(tier, state, facing, step)
    local m = F.mode(state)
    if m == "fire" then return F.spriteName(tier, F.FRAMES[(math.floor(step or 0) % #F.FRAMES) + 1], facing) end
    if m == "embers" then return F.spriteName(tier, "embers", facing) end
    return F.spriteName(tier, state, facing)
end

--- The light for a look: { radius, r, g, b } or nil. A running fire's radius and brightness follow the load:
--  `watts` against the tier's rating (DPM_Model), in three bands so a wavering load does not rebuild the light.
function F.lightFor(mode, tier, watts)
    if mode == "embers" then return F.EMBER_LIGHT end
    if mode ~= "fire" then return nil end
    local MM = DazedPower.More and DazedPower.More.Model
    local rated = (MM and MM.steamSpec and MM.steamSpec(tier).rated) or 900
    local load = math.max(0, math.min(1, (tonumber(watts) or 0) / rated))
    local band = (load >= 0.66 and 2) or (load >= 0.25 and 1) or 0
    local k = band / 2
    local lo, hi = F.FIRE_RADIUS[1], F.FIRE_RADIUS[2]
    local glow = 0.6 + 0.4 * k
    return { radius = math.floor(lo + (hi - lo) * k + 0.5), r = F.FIRE_RGB[1] * glow, g = F.FIRE_RGB[2] * glow,
             b = F.FIRE_RGB[3] * glow, band = band }
end

------------------------------------------------------------------ engine calls, all guarded

local function paused()
    local ok, v = pcall(function() return isGamePaused and isGamePaused() end)
    if ok and v then return true end
    ok, v = pcall(function() return getGameSpeed and getGameSpeed() end)
    return ok and v == 0
end
F.paused = paused

local function now() return getTimestampMs and getTimestampMs() or 0 end

local function dark()
    local cm = getClimateManager and getClimateManager()
    local v = cm and P.try(cm, "getDayLightStrength")
    if type(v) ~= "number" then return true end
    return v < F.DARK_BELOW
end
F.dark = dark

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
F.show = show

local function dropLight(e)
    if not e.light then return end
    local light, cell = e.light, getCell and getCell()
    pcall(function() light:setActive(false) end)
    if cell then pcall(function() cell:removeLamppost(light) end) end
    e.light, e.lightKey = nil, nil
    F.lights = math.max(0, F.lights - 1)
end
F.dropLight = dropLight

local function setLight(e, want)
    local key = want and (want.radius .. "|" .. (want.band or "e")) or nil
    if key == e.lightKey then return end
    dropLight(e)
    if not want or F.lights >= F.MAX_LIGHTS then return end
    if not (IsoLightSource and IsoLightSource.new) then return end
    local cell = getCell and getCell()
    if not cell then return end
    local ok, light = pcall(IsoLightSource.new, e.x, e.y, e.z, want.r, want.g, want.b, want.radius)
    if not ok or not light then return end
    if not pcall(function() cell:addLamppost(light) end) then return end
    e.light, e.lightKey = light, key
    F.lights = F.lights + 1
end

------------------------------------------------------------------ jobs

local frameTick -- forward

local function setFrameJob(on)
    if on == F.frameJob then return end
    F.frameJob = on
    if on then DazedCore.Tick.every(F.FRAME_ID, F.FRAME_MS, frameTick) else DazedCore.Tick.remove(F.FRAME_ID) end
end

local function forget(obj)
    local e = F.tracked[obj]
    if not e then return end
    dropLight(e)
    F.tracked[obj] = nil
    F.count = F.count - 1
end

--- Put a plain sprite back on everything showing our frame, and take every light out (option off, or a reset).
function F.restoreAll()
    for obj, e in pairs(F.tracked) do
        dropLight(e)
        if e.mode and P.alive(obj) then
            local spr = P.try(obj, "getSprite")
            local info = spr and P.spriteInfo(spr:getName())
            if info and info.kind == "steam" and info.frame ~= nil then
                local md = obj:hasModData() and obj:getModData()
                show(obj, F.spriteName(info.tier, F.stateOf(info, md and md.dazedpower), info.facing))
            end
        end
        e.mode, e.f, e.spr = nil, nil, nil
    end
    F.active = {}
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
        if math.abs(p:getX() - e.x) <= F.RANGE and math.abs(p:getY() - e.y) <= F.RANGE
                and math.abs(p:getZ() - e.z) <= F.FLOORS then
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
F.onScreen = onScreen

--- The once-a-second pass. Public for the tests.
function F.scan()
    if F.count == 0 then
        DazedCore.Tick.remove(F.SCAN_ID); F.scanJob = false
        setFrameJob(false)
        return
    end
    if not F.enabled() then
        if F.lights > 0 or #F.active > 0 or F.shown then F.restoreAll() end
        F.shown = false
        return
    end
    if paused() then return end
    local players, np = localPlayers()
    local isDark = dark()
    local active, na = F.active, 0
    for obj, e in pairs(F.tracked) do
        if not P.alive(obj) then
            forget(obj)
        else
            local spr = obj:getSprite()
            local info = spr and P.spriteInfo(spr:getName())
            if not info or info.kind ~= "steam" then
                forget(obj)
            else
                local near = np > 0 and nearAny(e, players, np)
                local md = obj:hasModData() and obj:getModData()
                local d = md and md.dazedpower
                local mode = near and F.mode(F.stateOf(info, d)) or nil
                setLight(e, (mode and isDark) and F.lightFor(mode, info.tier, d and d.steamWatts) or nil)
                if mode and onScreen(obj:getSquare()) then
                    F.shown = true
                    if e.mode ~= mode or e.facing ~= info.facing then e.f, e.spr = nil, nil end
                    e.mode, e.tier, e.facing = mode, info.tier, info.facing
                    if mode == "embers" then
                        show(obj, F.spriteName(info.tier, "embers", info.facing))
                        e.spr = obj:getSprite()
                    else
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
    setFrameJob(na > 0)
end

--- One flame step for every active engine. Public for the tests.
function F.frames(t)
    if paused() then return end
    t = t or now()
    local active, keep = F.active, 0
    for i = 1, #active do
        local e = active[i]
        local obj = e.obj
        local cur = P.try(obj, "getSprite")
        local live = e.mode == "fire" and cur ~= nil
        if live and cur ~= e.spr and e.spr ~= nil then
            -- Someone else changed the sprite (the server's state flip): still running only if it says so.
            local info = P.spriteInfo(cur:getName())
            live = info ~= nil and info.kind == "steam" and (info.frame ~= nil or info.state == "running")
            if not live then e.mode = nil end
        end
        if live then
            local f = math.floor(t / F.FRAME_MS + e.offset) % #F.FRAMES
            if f ~= e.f or cur ~= e.spr then
                e.f = f
                show(obj, F.spriteName(e.tier, F.FRAMES[f + 1], e.facing))
                e.spr = P.try(obj, "getSprite")
            end
            keep = keep + 1
            active[keep] = e
        end
    end
    for i = keep + 1, #active do active[i] = nil end
    if keep == 0 then setFrameJob(false) end
end
frameTick = function(t) F.frames(t) end

--- Start following an object if it is one of our steam engines.
function F.consider(obj)
    if not obj or F.tracked[obj] then return end
    local spr = obj.getSprite and obj:getSprite()
    local info = spr and P.spriteInfo(spr:getName())
    if not (info and info.kind == "steam") then return end
    local sq = obj:getSquare()
    if not sq then return end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    -- Engines side by side do not flicker in step.
    F.tracked[obj] = { obj = obj, x = x, y = y, z = z, offset = (x * 7 + y * 13) % #F.FRAMES }
    F.count = F.count + 1
    if not F.scanJob then
        F.scanJob = true
        DazedCore.Tick.every(F.SCAN_ID, F.SCAN_MS, function() F.scan() end)
    end
end

--- A tracked engine about to leave the square (picked up, destroyed, a chunk going): its light goes now.
function F.onRemoved(obj)
    if obj and F.tracked[obj] then forget(obj) end
end

--- Forget everything without touching the engine (a new game: the old cell and its lights are gone), then take
--  the engines the machine list already holds again (the login area streams in before OnGameStart).
function F.reset()
    F.tracked, F.count, F.active, F.lights, F.shown = {}, 0, {}, 0, false
    DazedCore.Tick.remove(F.SCAN_ID); DazedCore.Tick.remove(F.FRAME_ID)
    F.scanJob, F.frameJob = false, false
    DazedPower.More.Machines.each(F.consider)
end

if Events and not F.hooked then
    F.hooked = true
    DazedPower.More.Machines.onAdd(F.consider)
    if Events.OnObjectAboutToBeRemoved then Events.OnObjectAboutToBeRemoved.Add(F.onRemoved) end
    if Events.OnGameStart then Events.OnGameStart.Add(F.reset) end
end

return F
