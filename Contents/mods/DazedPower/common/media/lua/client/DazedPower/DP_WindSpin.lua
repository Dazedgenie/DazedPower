--[[ DazedPower -- turning windmills spin on screen.

     Purely cosmetic and only on this machine: the server keeps showing the plain "turning" sprite, and this file
     walks each windmill near a local player through its four blade frames (the windspin rows of the sheet). Speed
     follows the wind at the rotor (windMs, sent with the windmill's ModData). Past MAX_MS the blades blur into the
     render's motion-blur sprite; a broken rotor in a breeze rocks on its bearing instead of turning.

     Frames are set with the REGISTERED sprite object (no new sprite per swap), and a frame saved by a single-player
     save mid-spin still reads back as a turning windmill (DP_Parts.ALIAS), so nothing outside this file sees them.
]]

require "DazedPower/DP_Parts"
require "DazedCore/DC_Options"

DazedPower = DazedPower or {}
DazedPower.WindSpin = DazedPower.WindSpin or {}
local W = DazedPower.WindSpin
local P = DazedPower.Parts

W.OPTION = "WindSpin"
W.RANGE = 30                   -- squares from a local player within which windmills animate
W.MIN_FPS, W.MAX_FPS = 3, 15    -- blade frames a second at cut-in and at full speed
W.FPS_PER_MS = 1.6              -- frames a second added per m/s above cut-in
W.MAX_MS = 15                   -- wind at the rotor past which the blades blur instead
W.WOBBLE_MS = 2                 -- a broken rotor rocks once the wind passes this
W.SWEEP_MS = 5000               -- how often the squares round each player are searched for windmills
W.SWEEP_RADIUS = 16
W.FRAMES = { "spin1", "spin2", "spin3", "spin4" }
W.CUT_IN = { makeshift = 3.5, salvaged = 3.0, workshop = 2.5 }

W.tracked = W.tracked or {}     -- object -> { phase = frames advanced }
W.count = W.count or 0          -- how many are tracked (Kahlua has no next())
local spriteMemo = {}
local lastTick, lastSweep = nil, 0

--- The player's tick box on the shared Dazed Utilities page; on unless unticked.
function W.enabled()
    return DazedCore.Options.on("DazedPower", W.OPTION)
end

-- The registered sprite for a name, looked up once.
local function spriteFor(name)
    local s = spriteMemo[name]
    if s == nil then
        s = (getSprite and getSprite(name)) or false
        spriteMemo[name] = s
    end
    return s or nil
end

--- Show `name` on the object if it isn't already; true when the sprite changed.
local function show(obj, name)
    local cur = obj:getSprite()
    if cur and cur:getName() == name then return false end
    local s = spriteFor(name)
    if not s then return false end
    obj:setSprite(s)
    return true
end

--- Which windmill sprite the object should show right now, from its stored state and wind. Pure, for tests.
function W.pick(info, d, phase)
    local state = (d and d.state) or info.state
    local facing = (d and d.facing) or info.facing
    local ms = (d and d.windMs) or 0
    if state == "turning" then
        if ms >= W.MAX_MS then return P.sprite("windmill", "ground", info.tier, "turning", facing) end
        local frame = W.FRAMES[(math.floor(phase) % #W.FRAMES) + 1]
        return P.sprite("windmill", "ground", info.tier, frame, facing)
    end
    if state == "broken" and ms >= W.WOBBLE_MS then
        -- Uneven rocking: two beats on the rest, one rocked off it.
        local beat = math.floor(phase) % 3
        return P.sprite("windmill", "ground", info.tier, beat == 2 and "wobble" or "broken", facing)
    end
    return P.sprite("windmill", "ground", info.tier, state, facing)
end

--- Blade frames a second for wind of `ms` at the rotor on this tier.
function W.fps(tier, ms, state)
    if state == "broken" then return 1.6 end
    local over = math.max(0, (ms or 0) - (W.CUT_IN[tier] or 3))
    return math.min(W.MAX_FPS, W.MIN_FPS + over * W.FPS_PER_MS)
end

--- Start following an object if it is one of our windmills.
function W.consider(obj)
    if not obj or W.tracked[obj] then return end
    local spr = obj.getSprite and obj:getSprite()
    local info = spr and P.spriteInfo(spr:getName())
    if info and info.kind == "windmill" then
        W.tracked[obj] = { phase = 0 }
        W.count = W.count + 1
    end
end

local function onSquare(sq)
    local objects = sq and sq:getObjects()
    if not objects then return end
    for i = 0, objects:size() - 1 do W.consider(objects:get(i)) end
end

-- Catches windmills placed or streamed in without an event we saw, around each local player.
local function sweep(px, py, pz)
    local cell = getCell()
    if not cell then return end
    local R = W.SWEEP_RADIUS
    for x = px - R, px + R do
        for y = py - R, py + R do
            onSquare(cell:getGridSquare(x, y, pz))
        end
    end
end

local function localPlayers()
    local out = {}
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and not p:isDead() then out[#out + 1] = p end
    end
    return out
end

--- Put every tracked windmill back on the sprite its state names (option turned off).
function W.restoreAll()
    for obj, t in pairs(W.tracked) do
        if obj:getObjectIndex() ~= -1 then
            local info = P.spriteInfo(obj:getSprite() and obj:getSprite():getName())
            local md = obj:hasModData() and obj:getModData()
            local d = md and md.dazedpower
            if info then
                local want = P.sprite("windmill", "ground", info.tier, (d and d.state) or info.state, (d and d.facing) or info.facing)
                if want then show(obj, want) end
            end
        end
    end
    W.tracked, W.count = {}, 0
end

local function tick()
    local now = getTimestampMs()
    local dt = lastTick and math.min(0.25, (now - lastTick) / 1000) or 0
    lastTick = now
    if not W.enabled() then
        if W.count > 0 then W.restoreAll() end
        return
    end
    local players = localPlayers()
    if #players == 0 then return end
    if now - lastSweep >= W.SWEEP_MS then
        lastSweep = now
        for _, p in ipairs(players) do sweep(math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())) end
    end
    for obj, t in pairs(W.tracked) do
        local sq = obj:getSquare()
        if obj:getObjectIndex() == -1 or not sq then
            W.tracked[obj] = nil
            W.count = W.count - 1
        else
            local near = false
            for _, p in ipairs(players) do
                if math.abs(p:getX() - sq:getX()) <= W.RANGE and math.abs(p:getY() - sq:getY()) <= W.RANGE then near = true break end
            end
            if near then
                local info = P.spriteInfo(obj:getSprite() and obj:getSprite():getName())
                if not info or info.kind ~= "windmill" then
                    W.tracked[obj] = nil
                    W.count = W.count - 1
                else
                    local md = obj:hasModData() and obj:getModData()
                    local d = md and md.dazedpower
                    local state = (d and d.state) or info.state
                    t.phase = t.phase + dt * W.fps(info.tier, d and d.windMs or 0, state)
                    local want = W.pick(info, d, t.phase)
                    if want then show(obj, want) end
                end
            end
        end
    end
end

W.tick = tick

local function register()
    DazedCore.Options.tick("DazedPower", W.OPTION, "IGUI_DazedPower_OptWindSpin", true, "IGUI_DazedPower_OptWindSpinTip")
end
register()

if Events and not W.hooked then
    W.hooked = true
    if Events.LoadGridsquare then Events.LoadGridsquare.Add(onSquare) end
    if Events.OnObjectAdded then Events.OnObjectAdded.Add(W.consider) end
    if Events.OnTick then Events.OnTick.Add(tick) end
end

return W
