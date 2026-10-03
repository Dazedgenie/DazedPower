--[[ DazedPower -- the charger bench's menu and "charge this car" on a vehicle's menu. ]]

require "DazedPower/DP_Parts"
require "DazedPower/DP_Charge"
require "DazedPower/DP_Context"

DazedPower.ChargeMenu = DazedPower.ChargeMenu or {}
local CM = DazedPower.ChargeMenu
local P = DazedPower.Parts
local Ch = DazedPower.Charge

local function pct(item) return math.floor((item:getCurrentUsesFloat() or 0) * 100 + 0.5) end

--- Chargeable batteries the player carries that are not already full.
function CM.batteries(playerObj)
    local out = {}
    local inv = playerObj:getInventory()
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if Ch.itemWh(it) and Ch.needWh(it) > 1 then out[#out + 1] = it end
    end
    return out
end

local function wired(node)
    local s = node and P.data(node).sys
    return type(s) == "string"
end

--- The wired part nearest the car within the lead's reach, or nil.
function CM.nodeNear(vehicle)
    local sq = vehicle:getSquare()
    local cell = getCell()
    if not (sq and cell) then return nil end
    local best, bestD
    for dx = -Ch.REACH, Ch.REACH do
        for dy = -Ch.REACH, Ch.REACH do
            local s = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            if s then
                local objs = s:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if P.partOf(o) and wired(o) then
                        local dd = dx * dx + dy * dy
                        if not bestD or dd < bestD then best, bestD = o, dd end
                    end
                end
            end
        end
    end
    return best
end

function CM.onBench(worldobjects, bench, playerObj, item)
    local C = DazedPower.Context
    if C.approach(playerObj, bench) then
        ISTimedActionQueue.add(DP_ChargeAction:new(playerObj, bench, item, nil))
    end
end

function CM.benchMenu(menu, worldobjects, bench, playerObj)
    local items = CM.batteries(playerObj)
    local isWired = wired(bench)
    if #items == 0 then
        local o = menu:addOption(getText("ContextMenu_DazedPower_ChargeNone"))
        o.notAvailable = true
        return
    end
    for _, it in ipairs(items) do
        local o = menu:addOption(getText("ContextMenu_DazedPower_Charge", it:getDisplayName(), pct(it)),
                                 worldobjects, CM.onBench, bench, playerObj, it)
        if not isWired then
            o.notAvailable = true
            local t = ISToolTip:new(); t:initialise(); t:setVisible(false)
            t.description = getText("Tooltip_DazedPower_ChargeUnwired")
            o.toolTip = t
        end
    end
end

function CM.onCar(vehicle, playerObj, node)
    local part = vehicle:getPartById("Battery")
    if not (part and part:getInventoryItem()) then return end
    if ISPathFindAction and ISPathFindAction.pathToVehicleArea then
        ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, "Engine"))
    end
    ISTimedActionQueue.add(DP_ChargeAction:new(playerObj, node, nil, vehicle))
end

local function hookVehicle()
    if not ISVehicleMenu or ISVehicleMenu.dazedChargeHooked then return end
    ISVehicleMenu.dazedChargeHooked = true
    local fill0 = ISVehicleMenu.FillMenuOutsideVehicle
    function ISVehicleMenu.FillMenuOutsideVehicle(player, context, vehicle, test)
        local r = fill0(player, context, vehicle, test)
        if test then return r end
        local playerObj = getSpecificPlayer(player)
        local part = vehicle and vehicle:getPartById("Battery")
        local bat = part and part:getInventoryItem()
        if bat and playerObj and Ch.itemWh(bat) and Ch.needWh(bat) > 1 then
            local node = CM.nodeNear(vehicle)
            if node then
                context:addOption(getText("ContextMenu_DazedPower_ChargeCar", pct(bat)), vehicle, CM.onCar, playerObj, node)
            end
        end
        return r
    end
end
Events.OnGameStart.Add(hookVehicle)
