--[[ Dazed Power -- running machines you can hear, one looping sound per machine near each local player.
     Client only and driven by the synced sprite state, so it behaves the same in multiplayer; zombie noise stays in DPM_Bridge. ]]

require "DazedPower/DPM_Parts"
require "DazedPower/DPM_Machines"

DazedPower.More = DazedPower.More or {}
DazedPower.More.Sounds = DazedPower.More.Sounds or {}
local S = DazedPower.More.Sounds
local R = DazedPower.More.Parts
local Mc = DazedPower.More.Machines

S.RANGE = 18                -- squares around the player that are listened for
S.FLOORS = 1                -- floors above and below the player
S.SCAN_MS = 1500            -- real time between passes over the tracked machines

-- What each machine plays in each state: a list of looping vanilla sounds.
S.LOOPS = {
    petrol   = { running = { "GeneratorLoop" } },
    propane  = { running = { "OldGeneratorLoop" } },
    steam    = { warming = { "FireplaceRunning" },
                 running = { "FireplaceRunning", "FactoryMachineAmbiance" } },
    pedal    = { on = { "ClothingDryerRunning" } },
    -- the pylon hum was an ambient-bus sound and too quiet to hear; a washer's churn reads as the rotor's whump
    windmill = { turning = { "ClothingWasherRunning" } },
}
-- One-shots when an engine is seen starting or stopping.
S.START = { petrol = "GeneratorStarting", propane = "OldGeneratorStarting" }
S.STOP = { petrol = "GeneratorStopping", propane = "OldGeneratorStopping" }

S.live = S.live or {}       -- key -> { emitter, ids, kind, state }
S.seen = S.seen or {}       -- key -> state at the last scan

-- Anchored, so a vanilla name fails on its first character without a substring being made.
local PREFIX_PATTERN = "^dazedpower_"
-- Our sprite name -> { kind, state } or false: the same name always decodes the same way.
local soundOf = {}

local function keyOf(sq) return sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ() end

--- Stop everything one machine is playing; `stopSound` says whether to play its stop one-shot.
local function silence(key, stopSound)
    local rec = S.live[key]
    if not rec then return end
    for _, id in ipairs(rec.ids) do pcall(rec.emitter.stopSound, rec.emitter, id) end
    local stop = stopSound and S.STOP[rec.kind]
    if stop then pcall(rec.emitter.playSound, rec.emitter, stop) end
    S.live[key] = nil
end

--- Start, keep or stop the loops for a machine now in `state` (was `prev` last scan).
local function voice(key, sq, kind, state, prev)
    local loops = S.LOOPS[kind][state]
    local rec = S.live[key]
    if rec and rec.kind == kind and rec.state == state then
        -- a loop the engine dropped (sound reset, emitter reused) is restarted
        for i, id in ipairs(rec.ids) do
            local ok, playing = pcall(rec.emitter.isPlaying, rec.emitter, id)
            if ok and playing == false then
                local ok2, nid = pcall(rec.emitter.playSound, rec.emitter, loops[i])
                if ok2 and nid then rec.ids[i] = nid end
            end
        end
        return
    end
    silence(key, rec ~= nil and not loops)                     -- just switched off: play its stop
    if not loops then return end
    local world = getWorld and getWorld()
    if not world then return end
    local ok, emitter = pcall(world.getFreeEmitter, world, sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ())
    if not ok or not emitter then return end
    if prev and not S.LOOPS[kind][prev] and S.START[kind] then  -- just switched on in earshot
        pcall(emitter.playSound, emitter, S.START[kind])
    end
    local ids = {}
    for _, name in ipairs(loops) do
        local ok2, id = pcall(emitter.playSound, emitter, name)
        if ok2 and id then ids[#ids + 1] = id end
    end
    S.live[key] = { emitter = emitter, ids = ids, kind = kind, state = state }
end

--- One machine's kind and state from its sprite, or nil.
local function machineState(obj)
    local spr = obj:getSprite()
    local name = spr and spr:getName()
    if not (name and string.find(name, PREFIX_PATTERN)) then return nil end
    local hit = soundOf[name]
    if hit == nil then
        local info = R.spriteInfo(name)
        hit = (info and S.LOOPS[info.kind]) and { info.kind, info.state } or false
        soundOf[name] = hit
    end
    if hit then return hit[1], hit[2] end
    return nil
end

-- The local players, gathered into one table reused every pass.
local players, nPlayers = {}, 0

--- Listen around every local player; machines out of range or gone fall silent.
--  Walks the machines DPM_Machines tracks rather than every square in earshot.
function S.scan()
    local range, floors, floor = S.RANGE, S.FLOORS, math.floor
    nPlayers = 0
    for p = 0, (getNumActivePlayers and getNumActivePlayers() or 1) - 1 do
        local pl = getSpecificPlayer(p)
        if pl and not pl:isDead() then
            nPlayers = nPlayers + 1
            local e = players[nPlayers]
            if not e then e = {} players[nPlayers] = e end
            e.x, e.y, e.z = floor(pl:getX()), floor(pl:getY()), floor(pl:getZ())
        end
    end
    local heard, seen = {}, {}
    Mc.each(function(obj, sq)
        local x, y, z = sq:getX(), sq:getY(), sq:getZ()
        for i = 1, nPlayers do
            local e = players[i]
            if math.abs(x - e.x) <= range and math.abs(y - e.y) <= range
                    and z >= math.max(0, e.z - floors) and z <= e.z + floors then
                local kind, state = machineState(obj)
                if kind then
                    local key = keyOf(sq)
                    if not heard[key] then
                        heard[key] = true
                        voice(key, sq, kind, state, S.seen[key])
                        seen[key] = state
                    end
                end
                break
            end
        end
    end)
    for key in pairs(S.live) do
        if not heard[key] then silence(key, false) end
    end
    S.seen = seen
end

local last = 0
local function onTick()
    local now = getTimestampMs and getTimestampMs() or 0
    if now - last < S.SCAN_MS then return end
    last = now
    local ok, err = pcall(S.scan)
    if not ok and print then print("DazedPower sounds: " .. tostring(err)) end
end

--- Quiet everything (leaving the game, or a test).
function S.stopAll()
    for key in pairs(S.live) do silence(key, false) end
end

if not S.hooked and Events then
    S.hooked = true
    if Events.OnTick then Events.OnTick.Add(onTick) end
    if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(S.stopAll) end
end

return S
