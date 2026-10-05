--[[ DazedPower -- a console stats line on the authority: systems, parts and how long the tick takes.
     Wraps S.tick once; DP_System's minute event looks S.tick up on every call, so the wrapper is what runs. ]]

if isClient() then return end

require "DazedPower/DP_System"

DazedPower = DazedPower or {}
DazedPower.Stats = DazedPower.Stats or {}
local T = DazedPower.Stats
local S = DazedPower.System

T.EVERY = 10    -- in-game minutes (ticks) between stats lines

--- Fresh counters for one reporting period.
function T.reset()
    T.ticks, T.sumMs, T.maxMs = 0, 0, 0
end
if T.ticks == nil then T.reset() end
T.lastMs = T.lastMs or 0

--- Systems and parts in memory now: each controller plus everything its record holds.
function T.counts()
    local systems, parts = 0, 0
    local A = DazedPower.Admin
    for _, rec in pairs(S.controllers or {}) do
        systems = systems + 1
        parts = parts + 1 + (A and #A.partsOf(rec) or 0)
    end
    return systems, parts
end

--- The one console line for the period just ended.
function T.line()
    local n, m = T.counts()
    local avg = T.ticks > 0 and T.sumMs / T.ticks or 0
    return string.format("DazedPower: stats -- %d systems, %d parts, last tick %d ms (avg %.1f ms, max %d ms over %d ticks)",
                         n, m, T.lastMs, avg, T.maxMs, T.ticks)
end

--- Time one tick and fold it into the period; every T.EVERY ticks print the line and start again.
function T.record(ms)
    ms = math.max(0, ms or 0)
    T.lastMs = ms
    T.ticks = T.ticks + 1
    T.sumMs = T.sumMs + ms
    if ms > T.maxMs then T.maxMs = ms end
    if T.ticks >= T.EVERY then
        print(T.line())
        T.reset()
    end
end

-- Guarded so a second load of this file does not time the tick twice.
if not T.wrapped then
    T.wrapped = true
    local tick0 = S.tick
    function S.tick()
        local t0 = getTimestampMs()
        tick0()
        T.record(getTimestampMs() - t0)
    end
end

return T
