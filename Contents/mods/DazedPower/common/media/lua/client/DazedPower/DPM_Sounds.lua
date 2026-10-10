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
    -- Windmills use the mod's own sounds (media/scripts/sounds_DazedWindmill.txt), one set per look.
    windmill_old    = { turning = { "DazedWindmillOld_Loop" } },
    windmill_modern = { turning = { "DazedWindmillModern_Loop" } },
}
-- Kinds whose sound set depends on tier: kind -> tier -> key in S.LOOPS.
S.VOICE = { windmill = { makeshift = "windmill_old", salvaged = "windmill_old", workshop = "windmill_modern" } }
-- One-shots when a machine is seen starting or stopping.
S.START = { petrol = "GeneratorStarting", propane = "OldGeneratorStarting",
            windmill_old = "DazedWindmillOld_Start", windmill_modern = "DazedWindmillModern_Start" }
S.STOP = { petrol = "GeneratorStopping", propane = "OldGeneratorStopping",
           windmill_old = "DazedWindmillOld_Stop", windmill_modern = "DazedWindmillModern_Stop" }
-- A spin-up clip ends at full speed, so its loop waits this long (ms) to take over instead of overlapping.
S.LOOP_DELAY_MS = { windmill_old = 5900, windmill_modern = 4900 }

S.live = S.live or {}       -- key -> { emitter, ids, kind, state, x, y, z, startAt, startId, startEmitter }
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
    for _, id in ipairs(rec.ids) do
        if id then pcall(rec.emitter.stopSound, rec.emitter, id) end
    end
    if rec.startId then                                         -- cut a spin-up short, wherever it plays
        local e = rec.startEmitter or rec.emitter
        pcall(e.stopSound, e, rec.startId)
    end
    local stop = stopSound and S.STOP[rec.kind]
    if stop then pcall(rec.emitter.playSound, rec.emitter, stop) end
    S.live[key] = nil
end

-- Sounds that already failed to play, so the console names each one once instead of every scan.
local warned = {}

--- Play one sound on an emitter; the handle, or nil (and one console line) when the engine refused it.
local function play(emitter, name)
    local ok, id = pcall(emitter.playSound, emitter, name)
    if ok and id and id ~= 0 then return id end
    if not warned[name] and print then
        warned[name] = true
        print("DazedPower sounds: could not play " .. tostring(name) .. (ok and "" or (": " .. tostring(id))))
    end
    return nil
end

--- A free world emitter at the middle of a square, or nil.
local function emitterAt(x, y, z)
    local world = getWorld and getWorld()
    if not world then return nil end
    local ok, emitter = pcall(world.getFreeEmitter, world, x + 0.5, y + 0.5, z)
    if ok and emitter then return emitter end
    return nil
end

--- Play a machine's loops and clear any pending delayed start. A machine that played a spin-up clip gets a
--  fresh emitter for its loops: the world hands an emitter back to its pool once nothing on it is playing,
--  so the spin-up's emitter can be gone (or reused) by the time the loop is due.
local function startLoops(rec)
    local waited = rec.startAt ~= nil
    rec.startAt = nil
    if waited then
        local fresh = emitterAt(rec.x, rec.y, rec.z)
        if fresh then rec.emitter, rec.startEmitter = fresh, rec.emitter end
    end
    rec.ids = {}
    for i, name in ipairs(S.LOOPS[rec.kind][rec.state] or {}) do
        rec.ids[i] = play(rec.emitter, name) or false
    end
end

--- Start, keep or stop the loops for a machine now in `state` (was `prev` last scan).
local function voice(key, sq, kind, state, prev)
    local loops = S.LOOPS[kind][state]
    local rec = S.live[key]
    if rec and rec.kind == kind and rec.state == state then
        if rec.startAt then return end                          -- still spinning up; startDue takes it from here
        -- a loop the engine dropped (sound reset, emitter handed back to the pool) or never started:
        -- start the set again on a fresh emitter, since the old one may no longer play anything
        for i = 1, #loops do
            local id = rec.ids[i]
            local ok, playing = false, false
            if id then ok, playing = pcall(rec.emitter.isPlaying, rec.emitter, id) end
            if not (ok and playing ~= false) then
                for _, old in ipairs(rec.ids) do
                    if old then pcall(rec.emitter.stopSound, rec.emitter, old) end
                end
                rec.emitter = emitterAt(rec.x, rec.y, rec.z) or rec.emitter
                rec.ids = {}
                for j, name in ipairs(loops) do rec.ids[j] = play(rec.emitter, name) or false end
                break
            end
        end
        return
    end
    silence(key, rec ~= nil and not loops)                     -- just switched off: play its stop
    if not loops then return end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local emitter = emitterAt(x, y, z)
    if not emitter then return end
    local rec2 = { emitter = emitter, ids = {}, kind = kind, state = state, x = x, y = y, z = z }
    S.live[key] = rec2
    if prev and not S.LOOPS[kind][prev] and S.START[kind] then  -- just switched on in earshot
        rec2.startId = play(emitter, S.START[kind])
        local delay = S.LOOP_DELAY_MS[kind]
        if delay and rec2.startId then
            rec2.startAt = (getTimestampMs and getTimestampMs() or 0) + delay
            return
        end
    end
    startLoops(rec2)
end

--- Start loops whose spin-up clip has finished; runs every tick but only walks the live machines.
local function startDue(now)
    for _, rec in pairs(S.live) do
        if rec.startAt and now >= rec.startAt then startLoops(rec) end
    end
end

--- One machine's sound set (its kind, or kind and tier via S.VOICE) and state from its sprite, or nil.
local function machineState(obj)
    local spr = obj:getSprite()
    local name = spr and spr:getName()
    if not (name and string.find(name, PREFIX_PATTERN)) then return nil end
    local hit = soundOf[name]
    if hit == nil then
        local info = R.spriteInfo(name)
        local v = info and S.VOICE[info.kind]
        local key = info and ((v and (v[info.tier] or v.makeshift)) or info.kind)
        hit = (key and S.LOOPS[key]) and { key, info.state } or false
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
    startDue(now)
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
