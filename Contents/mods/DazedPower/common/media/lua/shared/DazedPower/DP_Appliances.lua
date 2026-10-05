--[[ DazedPower -- the electric fence and the room cooler: the rules both sides share.
     Both are wired like the charger bench, and the server (DP_ApplianceTick) and the menus apply the same answers. ]]

require "DazedPower/DP_Parts"
require "DazedPower/DP_Model"
require "DazedPower/DP_Priority"

DazedPower = DazedPower or {}
DazedPower.Appliances = DazedPower.Appliances or {}
local A = DazedPower.Appliances
local P = DazedPower.Parts
local M = DazedPower.Model

A.FENCE_IDLE_W = 5            -- the energiser's standing draw while live
A.ZAP_WH = 5                  -- what one zap takes from the racks
A.ZAP_DAMAGE = 0.05           -- health a zap takes off a zombie
A.ZAP_COOLDOWN_MS = 3000      -- real time before the same zombie can be zapped again
A.ZAP_MAX_PER_CHECK = 4       -- zaps one fence section gives per check, to bound a horde's cost
A.FENCE_EVERY_TICKS = 15      -- ticks between fence checks
A.ZAP_SOUND = "LightbulbBurnedOut"
A.COOLER_BASE_W = 100         -- the compressor's draw while it runs
A.COOLER_PER_W = 10           -- extra draw per container it keeps cold
A.COOLER_MAX_SQUARES = 600    -- the most squares of one room a pass reads
A.COOLER_MAX_HOURS = 0.5      -- the longest gap one pass credits, so a long unload is not paid back

--------------------------------------------------------------- power gate

--- Whether a wired appliance's system can run it, and the reason key when it cannot.
--  `cd` is the controller's ModData; `kind` names the load for Priority.shed.
function A.gate(cd, kind)
    if type(cd) ~= "table" then return false, "IGUI_DazedPower_ApplFar" end
    if cd.trip then return false, "IGUI_DazedPower_ApplTrip" end
    if cd.online ~= true then return false, "IGUI_DazedPower_ApplOffline" end
    if cd.lvd then return false, "IGUI_DazedPower_ApplLvd" end
    if (tonumber(cd.soc) or 0) <= (tonumber(cd.floorSoc) or 0.2) then return false, "IGUI_DazedPower_ApplFloor" end
    if kind and DazedPower.Priority and DazedPower.Priority.shed(cd, kind) then return false, "IGUI_DazedPower_ApplShed" end
    return true, nil
end

--- The controller ModData of the system a part is wired to, or nil and the reason key.
function A.systemData(obj)
    local d = obj and P.data(obj)
    local sys = d and d.sys
    if type(sys) ~= "string" or sys == "" then return nil, "IGUI_DazedPower_ApplLoose" end
    local x, y, z = M.parseNodeKey(sys)
    local ctrl = x and P.objectAt(x, y, z, "controller")
    if not ctrl then return nil, "IGUI_DazedPower_ApplFar" end
    return P.data(ctrl), nil, ctrl
end

--- Is this fence or cooler powered right now? Returns live and, when not, the reason key.
function A.status(obj, kind)
    local cd, why = A.systemData(obj)
    if not cd then return false, why end
    return A.gate(cd, kind)
end

--------------------------------------------------------------- fence

--- May this zombie be zapped now? `z` is { dead = bool }; `last` is its last zap (ms) or nil.
--  A clock that went backwards (a reload) clears the cooldown rather than freezing it.
function A.canZap(last, now, z)
    if type(z) ~= "table" or z.dead then return false end
    if last == nil or now < last then return true end
    return now - last >= A.ZAP_COOLDOWN_MS
end

--- Whether the racks hold enough above the floor for one zap.
function A.canPay(availWh)
    return (tonumber(availWh) or 0) >= A.ZAP_WH
end

--- Drop cooldown entries old enough not to matter, so the table does not grow with every zombie ever zapped.
function A.pruneCooldowns(map, now)
    for k, t in pairs(map) do
        if now < t or now - t >= A.ZAP_COOLDOWN_MS then map[k] = nil end
    end
end

--- Count one zap on the fence's data, starting over on a new day. Returns today's count.
function A.countZap(d, day)
    if d.zapDay ~= day then d.zapDay, d.zaps = day, 0 end
    d.zaps = (d.zaps or 0) + 1
    return d.zaps
end

--- Today's zaps as the menu shows them: a count left from another day reads 0.
function A.zapsToday(d, day)
    if type(d) ~= "table" or d.zapDay ~= day then return 0 end
    return d.zaps or 0
end

--- Knock a zombie down, hurt it a little and play the zap, on whichever side simulates it.
function A.applyZap(z, damage)
    if not (P.try(z, "isOnFloor") or P.try(z, "isKnockedDown")) then P.try(z, "knockDown", false) end
    if damage then
        local h = P.try(z, "getHealth")
        if type(h) == "number" then P.try(z, "setHealth", h - A.ZAP_DAMAGE) end
    end
    P.try(z, "playSound", A.ZAP_SOUND)
end

--------------------------------------------------------------- cooler

--- The share of a day's ageing a fridge would have saved over `hours`, at the world's rot speed and fridge factor.
function A.coolerCredit(hours, rotSpeed, fridgeFactor)
    hours = math.max(0, tonumber(hours) or 0)
    local ff = M.clamp(tonumber(fridgeFactor) or 0.2, 0, 1)
    return hours / 24 * (tonumber(rotSpeed) or 1) * (1 - ff)
end

--- A food item's age after the credit, never below zero.
function A.compensatedAge(age, credit)
    return math.max(0, (tonumber(age) or 0) - (tonumber(credit) or 0))
end

--- The hours one pass credits since the last: nothing on the first pass, clamped after a long gap.
function A.coolerHours(lastAt, now)
    if type(lastAt) ~= "number" or now < lastAt then return 0 end
    return math.min(A.COOLER_MAX_HOURS, now - lastAt)
end

--- Does a food item take the credit? `f` is { frozen, burnt, perishable }.
function A.foodTakesCredit(f)
    return type(f) == "table" and f.perishable == true and not f.frozen and not f.burnt
end

--- The cooler's draw for `n` containers kept cold.
function A.coolerWatts(n)
    return A.COOLER_BASE_W + A.COOLER_PER_W * math.max(0, tonumber(n) or 0)
end

--- The room a cooler serves: its own square's, else the one it faces into across its wall. Nil when outside.
A.FACE_STEP = { N = { 0, -1 }, W = { -1, 0 } }
function A.roomOf(obj)
    local sq = P.try(obj, "getSquare")
    if not sq then return nil end
    local room = P.try(sq, "getRoom")
    if room then return room end
    local info = P.describe(obj)
    local step = info and A.FACE_STEP[info.facing]
    if not step or not getSquare then return nil end
    local n = getSquare(sq:getX() + step[1], sq:getY() + step[2], sq:getZ())
    return n and P.try(n, "getRoom") or nil
end

return A
