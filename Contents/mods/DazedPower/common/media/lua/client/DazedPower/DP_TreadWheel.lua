--[[ Dazed Power -- the real zombie on the treadwheel, on screen (DP_Tread, 0.17.0).

     A wheel loaded with the sandbox option Real zombie on the treadwheel keeps its zombie in the world. Every
     frame this machine holds each such wheel's zombie in its drum, near any local player: put back on the drum's
     middle, inert and toothless, facing the wheel's front, its DazedTread variable set so it walks in place
     (AnimSets zombie/idle/DazedTreadWalk, the crawler's crawl in zombie-crawler/idle). A wheel emptied (released,
     put down, its zombie killed) lets its zombie go. Finding and keeping the zombie across reloads is the
     authority's (T.keep); this only holds it still. Nothing is sent or saved.

     The wheels come from DPM_Machines (map loads, placing, its sweep). Cost: nothing while no treadwheel is
     loaded; otherwise a ModData read per wheel a frame, and the pin for the real ones within RANGE squares. ]]

require "DazedPower/DP_Tread"
require "DazedPower/DPM_Machines"

local T = DazedPower.Tread
local P = DazedPower.Parts
local Mc = DazedPower.More.Machines
local try = P.try

DazedPower.TreadWheel = DazedPower.TreadWheel or {}
local W = DazedPower.TreadWheel

W.RANGE = 40              -- squares from a local player within which a wheel's zombie is held
W.FIND_MS = 500           -- a wheel whose zombie is not found looks again at most this often
W.STRAY = 2.0             -- a cached zombie further than this from its wheel is not its zombie any more

W.wheels = W.wheels or {} -- wheel -> { z, tried, flagAt }

--- Follow a machine if it is a treadwheel (DPM_Machines listener).
function W.track(obj)
    if not obj or W.wheels[obj] then return end
    local info = P.describe(obj)
    if info and info.kind == "treadwheel" then W.wheels[obj] = {} end
end

local function nearLocal(x, y)
    for _, p in ipairs(DazedCore.Util.players()) do
        if try(p, "isLocalPlayer") ~= false then
            local dx, dy = (try(p, "getX") or 1e9) - x, (try(p, "getY") or 1e9) - y
            if dx * dx + dy * dy <= W.RANGE * W.RANGE then return true end
        end
    end
    return false
end

--- Hold one zombie in its drum for this frame: in place and facing the front every frame, inert again (T.harness)
--  when `flags`. Only try: a per-frame call that throws inside pcall leaks Kahlua slots (b42 gotchas).
function W.pin(zb, x, y, fx, fy, flags)
    T.place(zb, x, y)
    try(zb, "faceLocationF", x + fx, y + fy)
    if flags then T.harness(zb, true) end
end

--- One frame of every treadwheel this machine knows.
function W.frame(now)
    now = now or (getTimestampMs and getTimestampMs() or 0)
    local gone = nil
    for obj, w in pairs(W.wheels) do
        if not P.alive(obj) then
            gone = gone or {}
            gone[#gone + 1] = obj
            if w.z and T.zombieAlive(w.z) then T.harness(w.z, false) end
        else
            local desc = T.occupant(obj)
            if not T.isReal(desc) then
                if w.z then
                    if T.zombieAlive(w.z) then T.harness(w.z, false) end
                    w.z = nil
                end
            else
                local x, y, z, fx, fy = T.spot(obj)
                if x and nearLocal(x, y) then
                    local zb = w.z
                    if zb and (not T.zombieAlive(zb) or math.abs((try(zb, "getX") or 1e9) - x) > W.STRAY
                               or math.abs((try(zb, "getY") or 1e9) - y) > W.STRAY) then
                        zb, w.z = nil, nil
                    end
                    if not zb and (not w.tried or now - w.tried >= W.FIND_MS) then
                        w.tried = now
                        zb = T.wheelZombie(obj, desc)
                        w.z = zb
                    end
                    if zb then
                        local flags = not w.flagAt or now - w.flagAt >= W.FIND_MS or now < w.flagAt
                        if flags then w.flagAt = now end
                        W.pin(zb, x, y, fx, fy, flags)
                    end
                end
            end
        end
    end
    for i = 1, #(gone or {}) do W.wheels[gone[i]] = nil end
end

if not W.filed and Mc and DazedCore.Tick then
    W.filed = true
    Mc.onAdd(W.track)
    DazedCore.Tick.everyTicks("DazedPower.treadWheel", 1, function()
        if isServer and isServer() then return end
        for _ in pairs(W.wheels) do W.frame() return end
    end)
end

return W
