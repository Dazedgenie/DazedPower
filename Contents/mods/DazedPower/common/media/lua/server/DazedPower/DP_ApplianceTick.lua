--[[ DazedPower -- the electric fence, the room cooler and the space heater on the authority: sprites and status each controller tick,
     zaps every few ticks, the cooler's food credit every ten game minutes (their watts are billed by DPM_Bridge via A.draw). ]]

if isClient() then return end

require "DazedPower/DP_System"
require "DazedPower/DP_Appliances"
require "DazedPower/DP_Charge"

local S = DazedPower.System
local A = DazedPower.Appliances
local P = DazedPower.Parts
local M = DazedPower.Model
local Ch = DazedPower.Charge
local E = DazedPower.Env

A.cooldown = A.cooldown or {}     -- zombie key -> last zap (real ms)

local function alive(o)
    local ix = P.try(o, "getObjectIndex")
    return type(ix) == "number" and ix >= 0
end

-- Shared and never written: listOf runs for every controller every few ticks, so it hands this out instead of a new table.
local EMPTY = {}
local KINDS = { "fence", "cooler", "heater" }

local function listOf(rec, kind)
    return (rec and rec.dpm and rec.dpm[kind]) or EMPTY
end

local function nowMs()
    return getTimestampMs and getTimestampMs() or 0
end

local function today()
    return math.floor(E.worldHours() / 24)
end

--------------------------------------------------------------- billing

--- What the wired fences, coolers and heaters draw on this controller: watts per kind while running, rated watts idle.
function A.draw(rec)
    local active, idle, total = {}, {}, 0
    for _, kind in ipairs(KINDS) do
        for _, o in ipairs(listOf(rec, kind)) do
            if alive(o) then
                local d = P.data(o)
                local w = (kind == "fence") and A.FENCE_IDLE_W or (kind == "heater") and A.HEATER_W
                          or A.coolerWatts(d.cooled or 0)
                if d.live == true and not (kind == "cooler" and d.noRoom) then
                    active[kind] = (active[kind] or 0) + w
                    total = total + w
                else
                    idle[kind] = (idle[kind] or 0) + w
                end
            end
        end
    end
    return active, idle, total
end

--------------------------------------------------------------- status and sprites

--- Bring one appliance's sprite and status fields in line with its system; true when anything changed.
function A.refresh(o, kind)
    local d = P.data(o)
    local live, why = A.status(o, kind)
    local noRoom = nil
    if kind == "cooler" then
        noRoom = (A.roomOf(o) == nil) or nil
        if noRoom then live = false end
        A.noteCooler(o)
    end
    local changed = (d.live == true) ~= (live == true) or d.why ~= why or d.noRoom ~= noRoom
    d.live, d.why, d.noRoom = live or nil, why, noRoom
    local want = live and "on" or "off"
    local info = P.describe(o)
    if info and info.state ~= want and P.setState(o, want) then changed = true end
    if changed then o:transmitModData() end
    return changed
end

if not A.wrapped then
    A.wrapped = true
    local upd0 = S.updateController
    function S.updateController(rec, dt, hoursAgo, wet)
        local r = upd0(rec, dt, hoursAgo, wet)
        if hoursAgo or not dt or dt <= 0 then return r end
        for _, kind in ipairs(KINDS) do
            for _, o in ipairs(listOf(rec, kind)) do
                if alive(o) then pcall(A.refresh, o, kind) end
            end
        end
        return r
    end
end

--------------------------------------------------------------- fence

local function zombieKey(z)
    local id = P.try(z, "getOnlineID")
    if type(id) == "number" and id >= 0 then return "o" .. id end
    return "i" .. tostring(P.try(z, "getID"))
end

--- Tell the clients near a fence which zombies it zapped; the one that owns each zombie applies the hit.
local function broadcast(sq, ids, damage)
    local players = getOnlinePlayers and getOnlinePlayers()
    if not (players and players.size) then return end
    for i = 0, players:size() - 1 do
        local pl = players:get(i)
        if math.abs(pl:getX() - sq:getX()) < 60 and math.abs(pl:getY() - sq:getY()) < 60 then
            sendServerCommand(pl, "DazedPower", "fenceZap", { x = sq:getX(), y = sq:getY(), z = sq:getZ(), ids = ids, dmg = damage })
        end
    end
end

--- The zombies standing on a fence's square or the eight around it, or nil when there are none.
--  The list is only made once a zombie is found: almost every check finds none.
local function zombiesNear(sq)
    local out = nil
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local s = getSquare(x + dx, y + dy, z)
            local mov = s and s:getMovingObjects()
            for i = 0, (mov and mov:size() or 0) - 1 do
                local o = mov:get(i)
                if o and instanceof(o, "IsoZombie") then
                    out = out or {}
                    out[#out + 1] = o
                end
            end
        end
    end
    return out
end

--- One fence section's check: zap what is in reach and off cooldown, paid from its system's racks.
local function checkFence(fence, systems, dirty, now)
    -- A cheap look at the live flag first: P.data re-describes the sprite, and most fences are idle most ticks.
    local md = fence.getModData and fence:getModData()
    local raw = md and md.dazedpower
    if not raw or raw.live ~= true then return end
    local d = P.data(fence)
    if d.live ~= true then return end
    local sq = fence:getSquare()
    if not sq then return end
    local zs = zombiesNear(sq)
    if not zs then return end
    local cd = A.systemData(fence)
    if not A.gate(cd, "fence") then return end
    local sys = systems[d.sys]
    if sys == nil then
        sys = Ch.systemOf(fence) or false
        systems[d.sys] = sys
    end
    if not sys then return end
    local damage = P.sandbox("FenceDamage") ~= false
    local ids, n, day = {}, 0, today()
    for _, z in ipairs(zs) do
        if n >= A.ZAP_MAX_PER_CHECK then break end
        local k = zombieKey(z)
        if A.canZap(A.cooldown[k], now, { dead = P.try(z, "isDead") == true }) then
            if not A.canPay(Ch.available(sys.racks, sys.floorSoc)) then break end
            Ch.takeFrom(sys.racks, A.ZAP_WH)
            dirty[d.sys] = sys
            A.cooldown[k] = now
            n = n + 1
            A.countZap(d, day)
            if isServer() then
                local id = P.try(z, "getOnlineID")
                if type(id) == "number" then ids[#ids + 1] = id end
            else
                A.applyZap(z, damage)
            end
        end
    end
    if n > 0 then
        fence:transmitModData()
        if isServer() and #ids > 0 then broadcast(sq, ids, damage) end
    end
end

A.tickCount = A.tickCount or 0
function A.onTick()
    A.tickCount = A.tickCount + 1
    if A.tickCount < A.FENCE_EVERY_TICKS then return end
    A.tickCount = 0
    local now = nowMs()
    A.pruneCooldowns(A.cooldown, now)
    local systems, dirty = {}, {}
    for i = 1, #(S.order or EMPTY) do
        local rec = S.controllers[S.order[i]]
        for _, f in ipairs(listOf(rec, "fence")) do
            if alive(f) then
                local ok, err = pcall(checkFence, f, systems, dirty, now)
                if not ok then print("DazedPower: fence check failed: " .. tostring(err)) end
            end
        end
    end
    -- The racks a zap drew from are sent once per check, not once per zap.
    for _, sys in pairs(dirty) do
        for _, r in ipairs(sys.racks) do if r.obj and r.obj.transmitModData then r.obj:transmitModData() end end
    end
end

--------------------------------------------------------------- cooler

--- Credit one food item; true when its age changed.
local function creditFood(item, credit)
    if not A.foodTakesCredit({ frozen = P.try(item, "isFrozen") == true, burnt = P.try(item, "isBurnt") == true,
                               perishable = (tonumber(P.try(item, "getOffAgeMax")) or 1e9) < 1e9 }) then
        return false
    end
    local age = P.try(item, "getAge")
    if type(age) ~= "number" then return false end
    local new = A.compensatedAge(age, credit)
    if new == age then return false end
    item:setAge(new)
    if isServer() and sendItemStats then pcall(sendItemStats, item) end
    return true
end

--- Credit every food item in a container, and in the bags inside it one level down.
local function creditContainer(cont, credit, depth)
    local items = P.try(cont, "getItems")
    for i = 0, (items and items:size() or 0) - 1 do
        local it = items:get(i)
        if instanceof(it, "Food") then
            creditFood(it, credit)
        elseif depth < 1 and instanceof(it, "InventoryContainer") then
            local inner = P.try(it, "getInventory")
            if inner then creditContainer(inner, credit, depth + 1) end
        end
    end
end

--- One cooler's pass over its room: credit the food in every container that is not a fridge or freezer.
--  Returns the number of containers it kept cold.
local function coolRoom(room, credit)
    local squares = P.try(room, "getSquares")
    local count = 0
    local n = math.min(squares and squares:size() or 0, A.COOLER_MAX_SQUARES)
    for i = 0, n - 1 do
        local sq = squares:get(i)
        local objs = sq and sq:getObjects()
        for j = 0, (objs and objs:size() or 0) - 1 do
            local o = objs:get(j)
            local nc = tonumber(P.try(o, "getContainerCount")) or 0
            for c = 0, nc - 1 do
                local cont = o:getContainerByIndex(c)
                if cont and not (P.try(cont, "isFridge") or P.try(cont, "isFreezer")) then
                    count = count + 1
                    if credit > 0 then creditContainer(cont, credit, 0) end
                end
            end
        end
    end
    return count
end

local function coolOne(o)
    local d = P.data(o)
    local now = E.worldHours()
    local room = A.roomOf(o)
    local live = A.status(o, "cooler") and room ~= nil
    if not live then
        d.coolAt = now
        return
    end
    local credit = A.coolerCredit(A.coolerHours(d.coolAt, now), P.foodRotSpeed(), P.fridgeFactor())
    local count = coolRoom(room, credit)
    d.coolAt = now
    if d.cooled ~= count then
        d.cooled = count
        o:transmitModData()
    end
end

function A.everyTenMinutes()
    for i = 1, #(S.order or {}) do
        local rec = S.controllers[S.order[i]]
        for _, o in ipairs(listOf(rec, "cooler")) do
            if alive(o) then
                local ok, err = pcall(coolOne, o)
                if not ok then print("DazedPower: cooler pass failed: " .. tostring(err)) end
            end
        end
    end
end

if not A.hooked then
    A.hooked = true
    if Events.OnTick then Events.OnTick.Add(A.onTick) end
    if Events.EveryTenMinutes then Events.EveryTenMinutes.Add(A.everyTenMinutes) end
end

return A
