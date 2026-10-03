--[[ Dazed Power -- the timed actions.

     Pedalling, fitting a gear kit, tending a boiler (fuel, water, fire),
     and repairing any of the added machines. Ported from the fork with
     every name prefixed DPM_ so they can never collide with Dazed Power's own
     actions or with the fork's. Shared, like Dazed Power's: in multiplayer a
     timed action's complete() runs on the server, which re-checks
     everything against the world as it is then.
]]

require "TimedActions/ISBaseTimedAction"
require "DazedPower/DP_Parts"
require "DazedPower/DP_Env"
require "DazedPower/DPM_Stats"
require "DazedPower/DPM_Parts"
require "DazedPower/DPM_Model"

local P = DazedPower.Parts
local R = DazedPower.More.Parts
local M = DazedPower.More.Model     -- the add-on's physics (pedal, wind, steam)
local UM = DazedPower.Model         -- Dazed Power's own (for repairStep)
local E = DazedPower.Env            -- Dazed Power's own (worldHours, isSunlit)

------------------------------------------------------- pedalling a generator

--  The physical-labour source. Unlike every other kind here, this action IS
--  the generation: DPM_Bridge asks a pedal generator's own ModData
--  "has this been ridden in the last couple of real seconds", and the only
--  thing that ever answers yes is this action's update(), running every
--  frame it is active. Nothing is computed here and handed to the
--  simulation in one lump at complete() -- a queued action can be
--  interrupted at any moment (walking away, a zombie attack, the player
--  pressing the movement keys, which vanilla treats as cancelling a timed
--  action), and the system must stop billing the instant that happens, not
--  wait for an action that may never call complete() at all.
--
--  One queued session is a fixed real-world stretch (DPM_PEDAL_SECONDS), the
--  same technique DP_ReadSky uses for "stand here for half a minute", not a
--  fixed IN-GAME duration: like every timed action it still runs faster
--  under the game's own fast-forward speed keys, so a session queued at x3
--  speed banks roughly three in-game minutes' worth of watts and fatigue
--  for every one real minute spent waiting on it. The player can queue
--  another session immediately after one completes for a longer ride, or
--  stop whenever they choose.
DPM_PEDAL_SECONDS = 600     -- ten real minutes per queued session, at 1x speed

DPM_Pedal = ISBaseTimedAction:derive("DPM_Pedal")

function DPM_Pedal:isValid()
    if not self.object or self.object:getObjectIndex() == -1 then return false end
    local info = P.describe(self.object)
    return info ~= nil and info.kind == "pedal"
end

function DPM_Pedal:waitToStart()
    self.character:faceThisObject(self.object)
    return self.character:shouldBeTurning()
end

function DPM_Pedal:update()
    self.character:faceThisObject(self.object)
    if not self:isValid() then return end
    local d = P.data(self.object)

    -- The live rider's own Fitness, refreshed every frame: this is the ONLY
    -- place in the mod that ever has a character in hand while a pedal
    -- generator is active, so it is the only place that can write it.
    -- DPM_Bridge reads these two fields and nothing else to decide
    -- what the generator is making right now.
    d.pedalFitness = self.character:getPerkLevel(Perks.Fitness) or 0
    d.pedalHeartbeat = getTimestampMs and getTimestampMs() or 0

    -- Fatigue, charged once per whole in-game minute actually spent
    -- pedaling, so a session queued at a faster game speed costs fatigue at
    -- the same faster rate it earns watts at -- both are on the same clock.
    local now = E.worldHours()
    if not self.lastFatigueHour then self.lastFatigueHour = now end
    local minutes = math.floor((now - self.lastFatigueHour) * 60)
    if minutes >= 1 then
        self.lastFatigueHour = self.lastFatigueHour + minutes / 60
        local cost = M.pedalFatiguePerMinute(d.gear) * minutes
        -- In percentage points; DPM_Stats finds this build's way to the stat
        -- (Build 42.13+ moved it behind CharacterStat) and converts to the
        -- engine's own 0..1 scale.
        DazedPower.More.Stats.addFatiguePct(self.character, cost)
    end
end

function DPM_Pedal:start()
    -- No dedicated pedaling animation exists yet; Loot is the same
    -- repetitive hands-busy anim DP_ClearArray and DP_BankCell already use
    -- for "working at this object", and it reads better than standing still.
    -- A proper cycling animation is a cosmetic follow-up, not a simulation
    -- change, and can replace this line alone whenever one ships.
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end

function DPM_Pedal:stop()
    ISBaseTimedAction.stop(self)
end

function DPM_Pedal:perform()
    ISBaseTimedAction.perform(self)
end

function DPM_Pedal:complete()
    -- Clear the heartbeat at once rather than letting it age out on its own:
    -- a deliberate stop should stop billing the same instant the player
    -- sees the action end, not up to PEDAL_FRESH_MS later.
    if self.object and self.object:getObjectIndex() ~= -1 then
        local d = P.data(self.object)
        d.pedalHeartbeat = 0
        self.object:transmitModData()
    end
    return true
end

function DPM_Pedal:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return DPM_PEDAL_SECONDS * 48
end

function DPM_Pedal:new(character, object)
    local o = ISBaseTimedAction.new(self, character)
    o.object = object
    o.maxTime = o:getDuration()
    return o
end

------------------------------------------------------------- fitting a gear set

DPM_InstallGear = ISBaseTimedAction:derive("DPM_InstallGear")

function DPM_InstallGear:isValid()
    if not self.object or self.object:getObjectIndex() == -1 then return false end
    local info = P.describe(self.object)
    return info ~= nil and info.kind == "pedal" and self.item ~= nil
end

function DPM_InstallGear:waitToStart()
    self.character:faceThisObject(self.object)
    return self.character:shouldBeTurning()
end

function DPM_InstallGear:update()
    self.character:faceThisObject(self.object)
end

function DPM_InstallGear:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end

function DPM_InstallGear:stop()
    ISBaseTimedAction.stop(self)
end

function DPM_InstallGear:perform()
    ISBaseTimedAction.perform(self)
end

function DPM_InstallGear:complete()
    if not self.object or self.object:getObjectIndex() == -1 then return true end
    local info = P.describe(self.object)
    if not info or info.kind ~= "pedal" then return true end
    -- Still actually possessed, the same still-there check every other
    -- item-consuming completion in this file makes: two installs can be
    -- queued against the same kit before either finishes.
    local cont = self.item and self.item.getContainer and self.item:getContainer()
    if not cont then return true end
    local gear = R.gearOfItem(self.item:getFullType())
    if not gear then return true end

    local d = P.data(self.object)
    d.gear = gear
    self.object:transmitModData()

    cont:Remove(self.item)
    sendRemoveItemFromContainer(cont, self.item)
    return true
end

function DPM_InstallGear:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 100
end

function DPM_InstallGear:new(character, object, item)
    local o = ISBaseTimedAction.new(self, character)
    o.object = object
    o.item = item
    o.maxTime = o:getDuration()
    return o
end

----------------------------------------------------------- tending a boiler
--
--  Three jobs keep a steam engine going: feeding the firebox, keeping water
--  in the boiler, and lighting (or damping down) the fire. Each is its own
--  timed action, shaped like the others in this file, and each re-checks
--  itself on the authority at completion: isValid never runs on a server,
--  and in multiplayer complete() runs there against the world as it is now,
--  so nothing the queueing client believed is trusted.

--- Is the boiler still there, still a boiler, and still in arm's reach?
local function boilerStillApplies(action)
    local o = action.object
    if not o or o:getObjectIndex() == -1 then return false end
    local info = P.describe(o)
    if not info or info.kind ~= "steam" then return false end
    local sq = o:getSquare()
    local c = action.character
    return sq ~= nil and math.abs(sq:getX() - c:getX()) <= 2
       and math.abs(sq:getY() - c:getY()) <= 2 and sq:getZ() == c:getZ()
end

--- Still carried, right now, by somebody (not lying on the floor)? The same
--  test every item-consuming completion in this file makes: two queued
--  actions can name the same item, and the first to finish takes it.
local function stillCarried(item)
    local cont = item and item.getContainer and item:getContainer()
    if not cont then return nil end
    if item.getWorldItem and item:getWorldItem() then return nil end
    return cont
end

--- Weight of an item as it is now (a half-used bag of charcoal weighs less).
function DPM_ItemWeight(item)
    if not item then return 0 end
    if item.getActualWeight then
        local ok, w = pcall(item.getActualWeight, item)
        if ok and type(w) == "number" then return w end
    end
    return item.getWeight and item:getWeight() or 0
end

--- Setting up a boiler action: face it, work low, finish cleanly.
local function boilerAction(name, getDuration)
    local A = ISBaseTimedAction:derive(name)
    function A:isValid() return boilerStillApplies(self) end
    function A:waitToStart()
        self.character:faceThisObject(self.object)
        return self.character:shouldBeTurning()
    end
    function A:update() self.character:faceThisObject(self.object) end
    function A:start()
        self:setActionAnim("Loot")
        self.character:SetVariable("LootPosition", "Low")
        self.character:reportEvent("EventLootItem")
    end
    function A:stop() ISBaseTimedAction.stop(self) end
    function A:perform() ISBaseTimedAction.perform(self) end
    function A:getDuration()
        if self.character:isTimedActionInstant() then return 1 end
        return getDuration(self)
    end
    return A
end

-- Feeding the firebox, one item at a time (the menu queues one per item).
DPM_SteamFuel = boilerAction("DPM_SteamFuel", function() return 50 end)

function DPM_SteamFuel:complete()
    -- true on every no-op path: false is a Reject, which force-stops the client.
    if not boilerStillApplies(self) then return true end
    local item = self.item
    local cont = stillCarried(item)
    if not cont then return true end
    local d = P.data(self.object)
    local info = P.describe(self.object)
    local spec = M.steamSpec(info.tier)
    local hours = M.steamFuelHours(DPM_ItemWeight(item), item:getFullType())
    if hours <= 0 or (d.fuel or 0) + hours > spec.hopper + 0.001 then return true end
    d.fuel = (d.fuel or 0) + hours
    cont:Remove(item)
    sendRemoveItemFromContainer(cont, item)
    self.object:transmitModData()
    return true
end

function DPM_SteamFuel:new(character, object, item)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.item = object, item
    o.maxTime = o:getDuration()
    return o
end

-- Pouring water in from a bottle, pot, bucket: whatever it holds, up to
-- what the boiler has room for. B42 water lives in the item's FluidContainer
-- (see DP_ClearArray for why the legacy "uses" field is not it).
DPM_SteamWater = boilerAction("DPM_SteamWater", function(self)
    return 40 + math.floor(8 * math.min(40, self.litres or 1))
end)

function DPM_SteamWater:complete()
    if not boilerStillApplies(self) then return true end
    local item = self.item
    if not stillCarried(item) then return true end
    local fc = item.getFluidContainer and item:getFluidContainer()
    if not (fc and fc.getAmount and fc.adjustAmount) then return true end
    local d = P.data(self.object)
    local info = P.describe(self.object)
    local room = M.steamSpec(info.tier).tank - (d.water or 0)
    local have = fc:getAmount() or 0
    local pour = math.min(have, room)
    if pour <= 0 then return true end
    fc:adjustAmount(have - pour)
    sendItemStats(item)
    d.water = (d.water or 0) + pour
    self.object:transmitModData()
    return true
end

function DPM_SteamWater:new(character, object, item, litres)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.item, o.litres = object, item, litres
    o.maxTime = o:getDuration()
    return o
end

-- Lighting the fire, or damping it down. Lighting is refused, on the
-- authority, for every reason the menu greys the row out: nothing in the
-- firebox, a wrecked boiler, no open sky, no fire-starter -- and an EMPTY
-- boiler, because firing one dry is the thing that wrecks it.
DPM_SteamFire = boilerAction("DPM_SteamFire", function(self)
    return self.light and 80 or 40
end)

function DPM_SteamFire:complete()
    if not boilerStillApplies(self) then return true end
    local d = P.data(self.object)
    if not self.light then
        d.lit = false
        self.object:transmitModData()
        return true
    end
    if (d.fuel or 0) <= 0 or (d.water or 0) <= 0 or (d.condition or 100) <= 0 then
        return true
    end
    local E = DazedPower.Env
    if E and E.isSunlit and not E.isSunlit(self.object:getSquare()) then return true end
    if not stillCarried(self.starter) then return true end
    d.lit = true
    d.blown = nil
    self.object:transmitModData()
    return true
end

function DPM_SteamFire:new(character, object, light, starter)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.light, o.starter = object, light and true or false, starter
    o.maxTime = o:getDuration()
    return o
end

------------------------------------------------------------ propane generator

--  Five jobs: hook a propane tank up to a port, unhook one, top up the
--  generator's own reservoir from a carried tank, set the switch (off, on,
--  auto), and set the auto-start level. Same shape and the same rule as the
--  boiler's actions: everything is re-checked at completion, on the
--  authority, against the world as it is then.

local function genStillApplies(action)
    local o = action.object
    if not o or o:getObjectIndex() == -1 then return false end
    local info = P.describe(o)
    if not info or not R.GAS_ENGINE[info.kind] then return false end
    local sq = o:getSquare()
    local c = action.character
    return sq ~= nil and math.abs(sq:getX() - c:getX()) <= 2
       and math.abs(sq:getY() - c:getY()) <= 2 and sq:getZ() == c:getZ()
end

--- A drainable's fill, 0..1 -- Dazed Power's own battery reading (its itemFill
--  explains why it is getCurrentUsesFloat and not the obvious getUsedDelta).
function DPM_TankFill(item)
    if not item then return 0 end
    if item.getCurrentUsesFloat then
        return math.max(0, math.min(1, item:getCurrentUsesFloat() or 0))
    end
    local maxU = item.getMaxUses and item:getMaxUses() or 1
    if not maxU or maxU <= 0 then return 1 end
    return math.max(0, math.min(1, (item.getCurrentUses and item:getCurrentUses() or maxU) / maxU))
end

local function tankCond(item)
    if not item or not item.getCondition then return 1 end
    local maxC = item.getConditionMax and item:getConditionMax() or 100
    if not maxC or maxC <= 0 then return 1 end
    return math.max(0, math.min(1, (item:getCondition() or maxC) / maxC))
end

local function genAction(name, getDuration, applies)
    applies = applies or genStillApplies
    local A = ISBaseTimedAction:derive(name)
    function A:isValid() return applies(self) end
    function A:waitToStart()
        self.character:faceThisObject(self.object)
        return self.character:shouldBeTurning()
    end
    function A:update() self.character:faceThisObject(self.object) end
    function A:start()
        self:setActionAnim("Loot")
        self.character:SetVariable("LootPosition", "Low")
        self.character:reportEvent("EventLootItem")
    end
    function A:stop() ISBaseTimedAction.stop(self) end
    function A:perform() ISBaseTimedAction.perform(self) end
    function A:getDuration()
        if self.character:isTimedActionInstant() then return 1 end
        return getDuration(self)
    end
    return A
end

-- Hooking a carried tank up to a free port.
DPM_PropaneHook = genAction("DPM_PropaneHook", function() return 120 end)

function DPM_PropaneHook:complete()
    if not genStillApplies(self) then return true end
    local tank = self.tank
    local cont = stillCarried(tank)
    if not cont or not R.TANK_TYPES[tank:getFullType()] then return true end
    local d = P.data(self.object)
    local info = P.describe(self.object)
    local port = self.port
    if not port or port < 1 or port > M.propaneSpec(info.tier).ports then return true end
    if d["t" .. port .. "Type"] then return true end          -- taken meanwhile
    d["t" .. port .. "Type"] = tank:getFullType()
    d["t" .. port .. "Fill"] = DPM_TankFill(tank)
    d["t" .. port .. "Cond"] = tankCond(tank)
    cont:Remove(tank)
    sendRemoveItemFromContainer(cont, tank)
    self.object:transmitModData()
    return true
end

function DPM_PropaneHook:new(character, object, tank, port)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.tank, o.port = object, tank, port
    o.maxTime = o:getDuration()
    return o
end

-- Unhooking the tank on a port, back to the player at whatever it holds.
DPM_PropaneUnhook = genAction("DPM_PropaneUnhook", function() return 90 end)

function DPM_PropaneUnhook:complete()
    if not genStillApplies(self) then return true end
    local d = P.data(self.object)
    local port = self.port
    local t = port and d["t" .. port .. "Type"]
    if not t then return true end                            -- unhooked meanwhile
    local item = R.tankItem(t, d["t" .. port .. "Fill"], d["t" .. port .. "Cond"])
    d["t" .. port .. "Type"], d["t" .. port .. "Fill"], d["t" .. port .. "Cond"] = nil, nil, nil
    if item then
        local inv = self.character:getInventory()
        inv:AddItem(item)
        sendAddItemToContainer(inv, item)
    end
    self.object:transmitModData()
    return true
end

function DPM_PropaneUnhook:new(character, object, port)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.port = object, port
    o.maxTime = o:getDuration()
    return o
end

-- Topping up the reservoir from a carried tank, as much as fits; the tank
-- stays with the player, lighter.
DPM_PropaneFill = genAction("DPM_PropaneFill", function() return 150 end)

function DPM_PropaneFill:complete()
    if not genStillApplies(self) then return true end
    local tank = self.tank
    if not stillCarried(tank) or not R.TANK_TYPES[tank:getFullType()] then return true end
    local d = P.data(self.object)
    local info = P.describe(self.object)
    local room = M.propaneSpec(info.tier, info.kind).reservoir - (d.lpg or 0)
    local size = M.tankKg(tank:getFullType())
    local have = DPM_TankFill(tank) * size
    local move = math.min(room, have)
    if move <= 0.001 then return true end
    if tank.setCurrentUsesFloat then tank:setCurrentUsesFloat((have - move) / size) end
    sendItemStats(tank)
    d.lpg = (d.lpg or 0) + move
    self.object:transmitModData()
    return true
end

function DPM_PropaneFill:new(character, object, tank)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.tank = object, tank
    o.maxTime = o:getDuration()
    return o
end

-- Petrol: pouring a carried petrol can (a fluid container) into the
-- generator's reservoir, litres, as much as fits. The fluid calls are the
-- ones Plumbing proved in game: getAmount / adjustAmount (an absolute set).
local function petrolOf(item)
    local fc = item and item.getFluidContainer and item:getFluidContainer()
    if not fc then return nil end
    -- the petrol in it, however mixed: asking for the fluid itself works where the primary fluid's name may not
    local okS, amount = pcall(function() return fc:getSpecificFluidAmount(Fluid.Petrol) end)
    if okS and type(amount) == "number" and amount > 0 then return fc, amount end
    local okA, total = pcall(fc.getAmount, fc)
    if not okA or type(total) ~= "number" then return nil end
    local okF, fluid = pcall(fc.getPrimaryFluid, fc)
    local name = okF and fluid and select(2, pcall(fluid.getFluidTypeString, fluid))
    name = name and string.lower(tostring(name)) or ""
    if not (string.find(name, "petrol", 1, true) or string.find(name, "gasoline", 1, true)) then return nil end
    return fc, total
end
DPM_PetrolOf = petrolOf

DPM_PetrolFill = genAction("DPM_PetrolFill", function() return 150 end)

function DPM_PetrolFill:complete()
    if not genStillApplies(self) then return true end
    local can = self.can
    if not stillCarried(can) then return true end
    local fc, have = petrolOf(can)
    if not fc then return true end
    local d = P.data(self.object)
    local info = P.describe(self.object)
    local room = M.propaneSpec(info.tier, info.kind).reservoir - (d.lpg or 0)
    local move = math.min(room, have)
    if move <= 0.001 then return true end
    if not pcall(fc.removeFluid, fc, move) then pcall(fc.adjustAmount, fc, have - move) end
    local _, after = petrolOf(can)
    local took = have - (after or 0)                    -- what the can really gave up
    if took <= 0 then return true end
    sendItemStats(can)
    d.lpg = (d.lpg or 0) + took
    self.object:transmitModData()
    return true
end

function DPM_PetrolFill:new(character, object, can)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.can = object, can
    o.maxTime = o:getDuration()
    return o
end

-- The switch. Starting a makeshift one is a pull-cord, so it takes longer;
-- the standby units have a starter button. ON with fuel and a working
-- engine starts it now; AUTO hands it to the battery (DPM_Bridge, within a
-- minute); OFF stops it.
DPM_PropaneSwitch = genAction("DPM_PropaneSwitch", function(self)
    if self.mode == "on" and self.pullStart then return 110 end
    return 35
end)

function DPM_PropaneSwitch:complete()
    if not genStillApplies(self) then return true end
    local d = P.data(self.object)
    local info = P.describe(self.object)
    local spec = M.propaneSpec(info.tier, info.kind)
    local mode = self.mode
    if mode ~= "off" and mode ~= "on" and mode ~= "auto" then return true end
    if mode == "auto" and not spec.auto then return true end
    d.mode = mode
    if mode == "off" then
        d.running = false
    elseif mode == "on" then
        local g = { tier = info.tier, kind = info.kind, mode = "on", condition = d.condition, lpg = d.lpg, feedTank = d.feedTank,
                    lineTx = d.lineTx, lineTy = d.lineTy, lineTz = d.lineTz,
                    t1Type = d.t1Type, t1Fill = d.t1Fill, t2Type = d.t2Type, t2Fill = d.t2Fill }
        d.running = M.propaneSwitch(g, nil)
        d.noFuel = g.noFuel
    end
    R.setVariant(self.object, ((d.condition or 100) <= 35 and "broken") or (d.running and "running") or "off")
    self.object:transmitModData()
    return true
end

function DPM_PropaneSwitch:new(character, object, mode)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.mode = object, mode
    local info = P.describe(object)
    o.pullStart = info and not M.propaneSpec(info.tier, info.kind).auto
    o.maxTime = o:getDuration()
    return o
end

-- The auto-start level: one of the choices the menu offers.
DPM_PropaneLevel = genAction("DPM_PropaneLevel", function() return 20 end)

function DPM_PropaneLevel:complete()
    if not genStillApplies(self) then return true end
    local pct = tonumber(self.pct)
    local ok = false
    for _, c in ipairs(M.PROPANE_START_CHOICES) do if c == pct then ok = true end end
    if not ok then return true end
    P.data(self.object).startPct = pct
    self.object:transmitModData()
    return true
end

function DPM_PropaneLevel:new(character, object, pct)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.pct = object, pct
    o.maxTime = o:getDuration()
    return o
end

------------------------------------------------------------------ amplifier

--  Bolting the amplifier (Base.DazedAmplifier, DPM_Model's amplifier
--  section) onto a machine, and taking it off again. Any generating part
--  takes one, one at a time; the flag is a flat boolean in the part's
--  ModData (d.amp), which Dazed Power's pick-up carries and DPM_Place's seed
--  restores. A screwdriver is the tool (checked by the menu; the item itself
--  is what is consumed here).

local function ampStillApplies(action)
    local o = action.object
    if not o or o:getObjectIndex() == -1 then return false end
    if not R.canAmplify(P.describe(o)) then return false end
    local sq = o:getSquare()
    local c = action.character
    return sq ~= nil and math.abs(sq:getX() - c:getX()) <= 2
       and math.abs(sq:getY() - c:getY()) <= 2 and sq:getZ() == c:getZ()
end

DPM_AmpInstall = genAction("DPM_AmpInstall", function() return 200 end, ampStillApplies)

function DPM_AmpInstall:complete()
    if not ampStillApplies(self) then return true end
    local d = P.data(self.object)
    if d.amp then return true end                           -- fitted meanwhile
    local amp = self.amp
    local cont = stillCarried(amp)
    if not cont or amp:getFullType() ~= R.AMP_ITEM then return true end
    cont:Remove(amp)
    sendRemoveItemFromContainer(cont, amp)
    d.amp = true
    self.object:transmitModData()
    addXp(self.character, Perks.Electricity, 10)
    return true
end

function DPM_AmpInstall:new(character, object, amp)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.amp = object, amp
    o.maxTime = o:getDuration()
    return o
end

DPM_AmpRemove = genAction("DPM_AmpRemove", function() return 140 end, ampStillApplies)

function DPM_AmpRemove:complete()
    if not ampStillApplies(self) then return true end
    local d = P.data(self.object)
    if not d.amp then return true end                       -- removed meanwhile
    d.amp = nil
    local item = instanceItem and instanceItem(R.AMP_ITEM)
    if item then
        local inv = self.character:getInventory()
        inv:AddItem(item)
        sendAddItemToContainer(inv, item)
    end
    self.object:transmitModData()
    return true
end

function DPM_AmpRemove:new(character, object)
    local o = ISBaseTimedAction.new(self, character)
    o.object = object
    o.maxTime = o:getDuration()
    return o
end

------------------------------------------------------------------ repairing

--  The same job, parts and tool as Dazed Power's own array repair (scrap,
--  screws, a screwdriver), for any of the added machines. Dazed Power's
--  DP_RepairArray only accepts arrays, so this is its own action.
DPM_REPAIR_STEP = 30

DPM_Repair = ISBaseTimedAction:derive("DPM_Repair")

function DPM_Repair:isValid()
    if not self.object or self.object:getObjectIndex() == -1 then return false end
    if not R.describe(self.object) then return false end
    return (P.data(self.object).condition or 100) < 100
        and self.scrap ~= nil and self.screws ~= nil
end

function DPM_Repair:waitToStart()
    self.character:faceThisObject(self.object)
    return self.character:shouldBeTurning()
end

function DPM_Repair:update() self.character:faceThisObject(self.object) end

function DPM_Repair:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end

function DPM_Repair:stop() ISBaseTimedAction.stop(self) end
function DPM_Repair:perform() ISBaseTimedAction.perform(self) end

function DPM_Repair:complete()
    if not self.object or self.object:getObjectIndex() == -1 then return true end
    local info = R.describe(self.object)
    if not info then return true end
    local d = P.data(self.object)
    if (d.condition or 100) >= 100 then return true end
    for _, it in ipairs({ self.scrap, self.screws }) do
        local cont = it and it.getContainer and it:getContainer()
        if not cont then return true end                 -- used up elsewhere
    end
    for _, it in ipairs({ self.scrap, self.screws }) do
        local cont = it:getContainer()
        cont:Remove(it)
        sendRemoveItemFromContainer(cont, it)
    end
    local step = UM.repairStep and UM.repairStep(d.condition or 0, DPM_REPAIR_STEP)
                 or math.min(100, (d.condition or 0) + DPM_REPAIR_STEP)
    d.condition = step
    if (d.condition or 0) > 0 then d.blown = nil end
    -- The picture: out of "broken" once it is over 35%. The next tick sets
    -- the rest (turning, running...) from the wind or the fire.
    if (d.condition or 0) > 35 and info.state == "broken" then
        local calm = { pedal = "off", windmill = "still", steam = "cold" }
        R.setVariant(self.object, calm[info.kind])
    end
    self.object:transmitModData()
    addXp(self.character, Perks.Electricity, 4)
    return true
end

function DPM_Repair:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 340
end

function DPM_Repair:new(character, object, scrap, screws)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.scrap, o.screws = object, scrap, screws
    o.maxTime = o:getDuration()
    return o
end

-- Turning a fixed (no tail fin) windmill's rotor to face another way: a climb and some wrenching.
local function windStillApplies(action)
    local o = action.object
    if not o or o:getObjectIndex() == -1 then return false end
    local info = R.describe(o)
    if not info or info.kind ~= "windmill" or M.windSpec(info.tier).tracks then return false end
    local sq, c = o:getSquare(), action.character
    return sq ~= nil and math.abs(sq:getX() - c:getX()) <= 2 and math.abs(sq:getY() - c:getY()) <= 2 and sq:getZ() == c:getZ()
end
DPM_TurnRotor = genAction("DPM_TurnRotor", function() return 200 end, windStillApplies)
function DPM_TurnRotor:complete()
    if not windStillApplies(self) or not R.FACING_INDEX[self.facing or ""] then return true end
    local info = R.describe(self.object)
    R.setVariant(self.object, info.state, self.facing)
    self.object:transmitModData()
    return true
end
function DPM_TurnRotor:new(character, object, facing)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.facing = object, facing
    o.maxTime = o:getDuration()
    return o
end
