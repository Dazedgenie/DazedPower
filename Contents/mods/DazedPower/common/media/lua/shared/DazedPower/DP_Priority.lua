--[[ DazedPower -- load priority for the wired machines.

     Each wired kind of machine on a controller has a priority: 1 Essential, 2 Normal, 3 Low. As the bank
     drains, Low machines are cut first, then Normal, and Essential ones run until the controller's own
     low-voltage disconnect. Lights and appliances on the building's circuit are not wired machines; they
     ride the building power and are cut only by that disconnect. ]]

require "DazedPower/DP_Parts"

DazedPower = DazedPower or {}
DazedPower.Priority = DazedPower.Priority or {}
local K = DazedPower.Priority

K.ESSENTIAL, K.NORMAL, K.LOW = 1, 2, 3
K.STEP = 0.12            -- each priority step cuts this much charge earlier
K.BACK = 0.05            -- a cut tier returns this far above where it was cut
K.DEFAULT = { purifier = 1, dankpump = 1, growlight = 2, dryfan = 3, waterpump = 2, well = 2, fuelpump = 3, charger = 3, carcharger = 3, cooler = 2, fence = 2 }

--- The priority of a wired load kind on this controller's data, 1..3.
function K.of(d, kind)
    local set = type(d) == "table" and d.prio
    local p = type(set) == "table" and tonumber(set[kind]) or nil
    if p and p >= 1 and p <= 3 then return math.floor(p) end
    return K.DEFAULT[kind] or K.NORMAL
end

--- Set one kind's priority (authority only); anything out of range is refused.
function K.set(d, kind, p)
    p = math.floor(tonumber(p) or 0)
    if type(kind) ~= "string" or p < 1 or p > 3 then return false end
    if type(d.prio) ~= "table" then d.prio = {} end
    d.prio[kind] = p
    return true
end

--- Is this kind cut right now? Priority 3 goes first, then 2; 1 is never cut here.
function K.shed(d, kind)
    if type(d) ~= "table" then return false end
    local p = K.of(d, kind)
    return (p == 3 and d.shedLow == true) or (p == 2 and d.shedNorm == true)
end

--- Move the two cut flags for the charge `soc` over the floor `floorSoc`, with a little hysteresis.
--  Returns true when either flag changed.
function K.update(d, soc, floorSoc)
    soc, floorSoc = tonumber(soc) or 0, tonumber(floorSoc) or 0.2
    local function flag(on, edge)
        if on then return soc < edge + K.BACK end
        return soc < edge
    end
    local low = flag(d.shedLow == true, floorSoc + 2 * K.STEP)
    local norm = flag(d.shedNorm == true, floorSoc + K.STEP)
    local changed = (low ~= (d.shedLow == true)) or (norm ~= (d.shedNorm == true))
    d.shedLow, d.shedNorm = low or nil, norm or nil
    return changed
end

return K
