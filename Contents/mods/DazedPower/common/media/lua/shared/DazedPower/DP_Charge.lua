--[[ DazedPower -- charging batteries from a wired system.

     The charger bench charges loose batteries; a car can be charged from the nearest wired node.
     Both draw watt-hours out of the system's racks (above the discharge floor) on the authority.
     The pure helpers here are tested headless; the timed actions are the plain-field kind. ]]

require "DazedPower/DP_Parts"
require "DazedPower/DP_Model"

DazedPower = DazedPower or {}
DazedPower.Charge = DazedPower.Charge or {}
local Ch = DazedPower.Charge
local P = DazedPower.Parts
local M = DazedPower.Model

Ch.CAR_WH = 720          -- a car battery's full charge
Ch.SMALL_WH = 20         -- a Base.Battery
Ch.RATE_W = 600          -- the bench's and the lead's charging power; sets how long it takes
Ch.EFF = 0.85            -- what reaches the battery from the rack
Ch.REACH = 10            -- tiles from a car to the nearest wired node

--- Wh a battery item holds when full, or nil when it is not chargeable here.
function Ch.itemWh(item)
    if not item then return nil end
    local t = item.getFullType and item:getFullType() or ""
    if string.find(t, "CarBattery", 1, true) then return Ch.CAR_WH end
    if t == "Base.Battery" then return Ch.SMALL_WH end
    if item.hasTag and ItemTag and ItemTag.CAR_BATTERY and item:hasTag(ItemTag.CAR_BATTERY) then return Ch.CAR_WH end
    return nil
end

local function fill(item)
    if item.getCurrentUsesFloat then return M.clamp(item:getCurrentUsesFloat() or 0, 0, 1) end
    return 1
end

--- Wh needed to top this item up.
function Ch.needWh(item)
    local full = Ch.itemWh(item)
    if not full then return 0 end
    return (1 - fill(item)) * full
end

--- Raise an item's fill by `wh`, never past full; returns the new fill.
function Ch.give(item, wh)
    local full = Ch.itemWh(item)
    if not full then return nil end
    local f = M.clamp(fill(item) + wh / full, 0, 1)
    if item.setCurrentUsesFloat then item:setCurrentUsesFloat(f)
    elseif item.setUsedDelta then item:setUsedDelta(f) end
    return f
end

--- Seconds-of-action for moving `wh` at the charger's power, in ticks (about 30 to 900).
function Ch.duration(wh)
    local hours = wh / Ch.RATE_W
    return M.clamp(math.floor(hours * 600), 30, 900)
end

--- The Wh a system can hand out right now: its racks' charge above the discharge floor.
--  `racks` is a list of { charge, nominal }; `floorSoc` is 0..1.
function Ch.available(racks, floorSoc)
    local charge, nominal = 0, 0
    for _, r in ipairs(racks) do charge = charge + (r.charge or 0); nominal = nominal + (r.nominal or 0) end
    return math.max(0, charge - (floorSoc or 0.2) * nominal)
end

--- Take `wh` from the racks, shared out by what each holds. `racks` entries are { d = ModData, charge }.
--  Returns what was actually taken.
function Ch.takeFrom(racks, wh)
    local total = 0
    for _, r in ipairs(racks) do total = total + (r.charge or 0) end
    if total <= 0 or wh <= 0 then return 0 end
    local take = math.min(wh, total)
    for _, r in ipairs(racks) do
        local part = take * (r.charge or 0) / total
        r.charge = (r.charge or 0) - part
        if r.d then r.d.charge = r.charge end
    end
    return take
end

--- Server only: the live racks and floor of the system that a node belongs to.
function Ch.systemOf(obj)
    local S = DazedPower.System
    if not (S and S.controllers and obj) then return nil end
    local sys = P.data(obj).sys
    local x, y, z = M.parseNodeKey(sys)
    local rec = x and S.controllers[x .. "," .. y .. "," .. z]
    if not rec then return nil end
    local gen = P.objectAt(rec.x, rec.y, rec.z, "controller")
    if not gen then return nil end
    local floorSoc = P.data(gen).floorSoc or 0.2
    local racks, nominal = {}, 0
    -- The county temperature is the same for every rack, so the world is read once, not once per rack.
    local E = DazedPower.Env
    local county = E and E.read and E.read().temperature
    for _, o in ipairs(rec.banks or {}) do
        local info = P.describe(o)
        if info then
            local d = P.data(o)
            -- the floor is on the cold-capacity scale (what the controller prints), so use that
            local temp = E and E.read and E.tempAt(o, county) or 20
            local cap = M.bankCapacity({ tier = info.tier, cellSum = P.cellSum(d), scale = P.bankScale() }, temp)
            racks[#racks + 1] = { d = d, obj = o, charge = d.charge or 0, nominal = cap }
            nominal = nominal + cap
        end
    end
    return { rec = rec, gen = gen, racks = racks, floorSoc = floorSoc }
end

--- Move up to `wantWh` from a system into `item`. Returns Wh delivered to the item.
function Ch.transfer(node, item, wantWh)
    local sys = Ch.systemOf(node)
    if not sys then return 0 end
    if P.data(sys.gen).trip or P.data(sys.gen).online == false then return 0 end
    local avail = Ch.available(sys.racks, sys.floorSoc)
    local draw = math.min(avail, wantWh / Ch.EFF)
    if draw <= 0 then return 0 end
    local took = Ch.takeFrom(sys.racks, draw)
    for _, r in ipairs(sys.racks) do if r.obj and r.obj.transmitModData then r.obj:transmitModData() end end
    Ch.give(item, took * Ch.EFF)
    return took * Ch.EFF
end

--------------------------------------------------------------- timed action

if ISBaseTimedAction then
    DP_ChargeAction = ISBaseTimedAction:derive("DP_ChargeAction")

    function DP_ChargeAction:isValid()
        if not (self.node and self.node:getObjectIndex() ~= -1) then return false end
        if self.vehicle then return self.vehicle:getSquare() ~= nil end
        return self.item ~= nil
    end
    function DP_ChargeAction:waitToStart()
        self.character:faceThisObject(self.node)
        return self.character:shouldBeTurning()
    end
    function DP_ChargeAction:update() self.character:faceThisObject(self.node) end
    function DP_ChargeAction:start()
        self:setActionAnim("Loot")
        self.character:reportEvent("EventLootItem")
    end
    function DP_ChargeAction:stop() ISBaseTimedAction.stop(self) end
    function DP_ChargeAction:perform() ISBaseTimedAction.perform(self) end

    --- The battery being charged: the carried item, or the car's installed one.
    function DP_ChargeAction:target()
        if self.vehicle then
            local part = self.vehicle.getPartById and self.vehicle:getPartById("Battery")
            return part and part:getInventoryItem(), part
        end
        return self.item
    end

    function DP_ChargeAction:complete()
        local item, part = self:target()
        if not item or not P.describe(self.node) then return true end
        -- A carried battery must still be in the character's own inventory.
        if self.item and (self.item:getContainer() ~= self.character:getInventory()) then return true end
        local got = Ch.transfer(self.node, item, Ch.needWh(item))
        if got > 0 and item.syncItemFields then pcall(function() item:syncItemFields() end) end
        if got > 0 and part and self.vehicle then
            if self.vehicle.transmitPartUsedDelta then pcall(function() self.vehicle:transmitPartUsedDelta(part) end) end
        end
        return true
    end

    function DP_ChargeAction:getDuration()
        if self.character:isTimedActionInstant() then return 1 end
        local item = self:target()
        return Ch.duration(item and Ch.needWh(item) or 0)
    end

    --- node: the bench or wired part; item: a loose battery, or vehicle: the car (one of the two).
    function DP_ChargeAction:new(character, node, item, vehicle)
        local o = ISBaseTimedAction.new(self, character)
        o.node, o.item, o.vehicle = node, item, vehicle
        o.maxTime = o:getDuration()
        return o
    end
end

return Ch
