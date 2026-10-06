--[[ DazedPower -- the electric fence, the room cooler and the space heater: the rules both sides share.
     All three are wired like the charger bench, and the server (DP_ApplianceTick) and the menus apply the same answers. ]]

require "TimedActions/ISBaseTimedAction"
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
A.HEATER_W = 1500             -- the space heater's draw while it runs
A.HEATER_HEAT = 18            -- what a running heater gives its room, in C-squares per hour (a lit fireplace is 22)
A.COOLER_HEAT = -12           -- what a running cooler takes out of its room's air

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

--- Is this appliance powered right now (a heater also needs its own switch on)? Returns live and, when not, the reason key.
function A.status(obj, kind)
    if kind == "heater" and not A.switchedOn(obj and P.data(obj)) then return false, "IGUI_DazedPower_HeaterSwitchedOff" end
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

--------------------------------------------------------------- space heater

--- Whether a heater's own switch is on; a new one starts switched off.
function A.switchedOn(d)
    return type(d) == "table" and d.heatOn == true
end

--- The heat a part gives its room in C-squares per hour from its ModData `d`, as the server last wrote it.
--  Zero when it is not running or the RoomHeat sandbox option is off.
function A.roomHeat(kind, d)
    if type(d) ~= "table" or d.live ~= true then return 0 end
    if P.sandbox("RoomHeat") == false then return 0 end
    if kind == "heater" then return A.HEATER_HEAT end
    if kind == "cooler" and not d.noRoom then return A.COOLER_HEAT end
    return 0
end

-- The part's ModData without making one: Dazed Climate asks this of every object in a room.
local function rawData(obj)
    if obj and obj.hasModData and not obj:hasModData() then return nil end
    local md = obj and obj.getModData and obj:getModData()
    return md and md.dazedpower or nil
end

--- Dazed Climate's key for a room: its definition's corner square, as DCl_Rooms.keyOf makes it.
function A.roomKey(room)
    local def = P.try(room, "getRoomDef")
    local x, y, z = P.try(def, "getX"), P.try(def, "getY"), P.try(def, "getZ")
    if not (x and y and z) then return nil end
    return x .. "," .. y .. "," .. z
end

-- Coolers hung from outside the room they serve (an east or south wall), by object: Dazed Climate only reads room squares.
A.outsideCoolers = A.outsideCoolers or {}

--- Note where a cooler stands; the authority calls this each controller tick.
function A.noteCooler(obj)
    local sq = P.try(obj, "getSquare")
    local served = sq and not P.try(sq, "getRoom") and A.roomOf(obj)
    A.outsideCoolers[obj] = served and A.roomKey(served) or nil
end

--- Dazed Climate's room source: the chill of the coolers that serve this room from outside its squares.
function A.outsideCoolerHeat(info)
    local key = type(info) == "table" and info.key
    if not key then return 0 end
    local total = 0
    for o, k in pairs(A.outsideCoolers) do
        local ix = P.try(o, "getObjectIndex")
        if type(ix) ~= "number" or ix < 0 then
            A.outsideCoolers[o] = nil
        elseif k == key then
            total = total + A.roomHeat("cooler", rawData(o))
        end
    end
    return total
end

--- Is this cooler keeping its room's food cold now? The same test its food pass uses, whatever RoomHeat says.
function A.coolerKeepsCold(o)
    return (A.status(o, "cooler")) == true and A.roomOf(o) ~= nil
end

--- Dazed Climate's cold-storage question for a room: does a running cooler hung from outside serve it?
function A.outsideCoolerCools(info)
    local key = type(info) == "table" and info.key
    if not key then return false end
    for o, k in pairs(A.outsideCoolers) do
        local ix = P.try(o, "getObjectIndex")
        if k == key and type(ix) == "number" and ix >= 0 and A.coolerKeepsCold(o) then return true end
    end
    return false
end

--- Dazed Climate's object sources for the heater and the cooler, as it takes them.
function A.climateSources()
    local out = {}
    for _, kind in ipairs({ "heater", "cooler" }) do
        out[#out + 1] = {
            match = function(o) return P.partOf(o) == kind end,
            heat = function(o) return A.roomHeat(kind, rawData(o)) end,
        }
    end
    -- Its cold storage asks the cooler whether it is already keeping the food cold.
    out[2].cools = function(o) return A.coolerKeepsCold(o) end
    return out
end

--- Have Dazed Climate read the rooms around a heater or cooler again now, after one is placed or lifted.
function A.markRoomStale(obj)
    local Rm = DazedClimate and DazedClimate.Rooms
    if not (Rm and type(Rm.info) == "table" and type(Rm.keyOf) == "function") then return end
    local sq = P.try(obj, "getSquare")
    local rooms = { sq and P.try(sq, "getRoom") or false, A.roomOf(obj) or false }
    for i = 1, 2 do
        local def = rooms[i] and P.try(rooms[i], "getRoomDef")
        local ok, key = pcall(Rm.keyOf, def)
        local info = def and ok and key and Rm.info[key]
        if info then info.stale = true end
    end
end

--- Hand the sources to Dazed Climate once, if it is loaded. True once they are registered.
function A.registerClimate()
    if A.climateDone then return true end
    local R = DazedClimate and DazedClimate.Rooms
    if not (R and type(R.addObjectSource) == "function") then return false end
    for _, src in ipairs(A.climateSources()) do
        local ok, err = pcall(R.addObjectSource, src)
        if not ok then print("DazedPower: Dazed Climate refused a heat source: " .. tostring(err)) end
    end
    if type(R.addRoomSource) == "function" then pcall(R.addRoomSource, A.outsideCoolerHeat, A.outsideCoolerCools) end
    A.climateDone = true
    return true
end

-- Dazed Climate may load after this file, so the game start tries again.
A.registerClimate()
if Events and not A.climateHooked then
    A.climateHooked = true
    if Events.OnGameStart then Events.OnGameStart.Add(A.registerClimate) end
    if Events.OnServerStarted then Events.OnServerStarted.Add(A.registerClimate) end
end

--- Throw a heater's switch on the authority; the next controller tick lights or darkens it. True when it changed.
function A.setSwitch(obj, on)
    local info = obj and P.describe(obj)
    if not info or info.kind ~= "heater" then return false end
    local d = P.data(obj)
    if A.switchedOn(d) == (on == true) then return false end
    d.heatOn = (on == true) or nil
    if not on then
        d.live, d.why = nil, "IGUI_DazedPower_HeaterSwitchedOff"
        P.setState(obj, "off")
    end
    if obj.transmitModData then obj:transmitModData() end
    return true
end

--  The heater's switch: a moment at the heater; its completion runs on the authority.
DP_HeaterSwitch = ISBaseTimedAction and ISBaseTimedAction:derive("DP_HeaterSwitch") or {}

function DP_HeaterSwitch:isValid()
    return self.object ~= nil and self.object:getObjectIndex() ~= -1
end

function DP_HeaterSwitch:waitToStart()
    self.character:faceThisObject(self.object)
    return self.character:shouldBeTurning()
end

function DP_HeaterSwitch:update()
    self.character:faceThisObject(self.object)
end

function DP_HeaterSwitch:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end

function DP_HeaterSwitch:stop()
    ISBaseTimedAction.stop(self)
end

function DP_HeaterSwitch:perform()
    ISBaseTimedAction.perform(self)
end

function DP_HeaterSwitch:complete()
    if not self:isValid() then return true end
    -- The pick-up lock decides who may use it, asked again here on the authority.
    local G = DazedPower.Place
    if G and G.mayUse and not G.mayUse(self.character, self.object) then return true end
    A.setSwitch(self.object, self.on == true)
    return true
end

function DP_HeaterSwitch:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 20
end

function DP_HeaterSwitch:new(character, object, on)
    local o = ISBaseTimedAction.new(self, character)
    o.object, o.on = object, on
    o.maxTime = o:getDuration()
    return o
end

return A
