--[[ DazedPower -- a parked car's alternator as a power source.

     A car hooked up to a system (right-click it near a wired part) feeds the bus while its engine runs.
     The links live on the controller as "id@x,y,z" strings; the server checks them every step. ]]

require "DazedPower/DP_Parts"
require "DazedPower/DP_Model"

DazedPower = DazedPower or {}
DazedPower.Alternator = DazedPower.Alternator or {}
local A = DazedPower.Alternator
local P = DazedPower.Parts
local M = DazedPower.Model

A.WATTS = 500           -- an idling alternator at full engine condition
A.REACH = 10            -- tiles from the car to the part it was hooked to

--- A vehicle's lasting id: the saved one when the engine has it, else the session one.
function A.idOf(vehicle)
    if not vehicle then return nil end
    -- Method pcalls rather than closures: this runs for every vehicle in the cell when an index is built.
    local ok, sid = pcall(vehicle.getSqlId, vehicle)
    if ok and sid and sid >= 0 then return "s" .. tostring(sid) end
    local ok2, id = pcall(vehicle.getId, vehicle)
    return ok2 and id and ("i" .. tostring(id)) or nil
end

--- Watts for an engine of this condition (0..100) that is or is not running.
function A.output(running, condition)
    if not running then return 0 end
    local c = M.clamp((condition or 100) / 100, 0, 1)
    if c <= 0.1 then return 0 end
    return A.WATTS * (0.4 + 0.6 * c)
end

--- Parse a controller's link list into { {id, x, y, z}, ... }.
function A.parse(str)
    local out = {}
    for id, x, y, z in string.gmatch(str or "", "([%w]+)@(-?%d+),(-?%d+),(-?%d+)") do
        out[#out + 1] = { id = id, x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    end
    return out
end

function A.join(list)
    local t = {}
    for _, l in ipairs(list) do t[#t + 1] = l.id .. "@" .. l.x .. "," .. l.y .. "," .. l.z end
    return table.concat(t, ";")
end

--- Add or drop one link in a list; returns the new string.
function A.toggle(str, id, x, y, z, on)
    local list, out = A.parse(str), {}
    for _, l in ipairs(list) do if l.id ~= id then out[#out + 1] = l end end
    if on then out[#out + 1] = { id = id, x = x, y = y, z = z } end
    return A.join(out)
end

function A.linked(str, id)
    for _, l in ipairs(A.parse(str)) do if l.id == id then return true end end
    return false
end

return A
