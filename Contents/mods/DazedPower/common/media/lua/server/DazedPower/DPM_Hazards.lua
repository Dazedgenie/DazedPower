--[[ DazedPower -- lightning storms and hydrogen, live only (a catch-up replay never rolls them). ]]

if isClient() then return end

require "DazedPower/DP_System"
require "DazedPower/DP_Hazards"

local S = DazedPower.System
local H = DazedPower.Hazards
local P = DazedPower.Parts
local M = DazedPower.Model
local E = DazedPower.Env
local H2 = {}

local function tell(sq, key, warn)
    if not sq then return end
    local players = getOnlinePlayers and getOnlinePlayers()
    local list = {}
    if players and players.size and players:size() > 0 then
        for i = 0, players:size() - 1 do list[#list + 1] = players:get(i) end
    elseif getSpecificPlayer and getSpecificPlayer(0) then
        list[1] = getSpecificPlayer(0)
    end
    for _, pl in ipairs(list) do
        if math.abs(pl:getX() - sq:getX()) < 40 and math.abs(pl:getY() - sq:getY()) < 40 then
            if isServer() then
                sendServerCommand(pl, "DazedPower", "note", { key = key, id = pl:getOnlineID(), warn = warn })
            else
                P.haloNote(pl, getText(key), warn)
            end
        end
    end
end

--- Is a grounding rod standing within reach of this controller?
function H.rodNear(rec)
    local R = H.ROD_RADIUS
    for dx = -R, R do
        for dy = -R, R do
            local sq = getSquare(rec.x + dx, rec.y + dy, rec.z)
            local objs = sq and sq:getObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                if P.partOf(objs:get(i)) == "rod" then return true end
            end
        end
    end
    return false
end

function H.strike(rec, gen)
    local d = P.data(gen)
    local outcome = H.strikeOutcome(H.rodNear(rec), ZombRandFloat and ZombRandFloat(0, 1) or math.random())
    local sq = gen:getSquare()
    if outcome == "rod" then
        tell(sq, "IGUI_DazedPower_StormRod", false)
    elseif outcome == "trip" then
        d.trip, d.online = true, false
        d.powered, d.poweredWant, d.poweredHold = false, false, 0
        gen:transmitModData()
        tell(sq, "IGUI_DazedPower_StormTrip", true)
    else
        d.trip, d.online = true, false
        d.powered, d.poweredWant, d.poweredHold = false, false, 0
        d.condition = math.max(0, (d.condition or 100) - H.HEAVY_DAMAGE)
        pcall(function() gen:setCondition(math.max(0, gen:getCondition() - H.HEAVY_DAMAGE)) end)
        gen:transmitModData()
        tell(sq, "IGUI_DazedPower_StormHit", true)
    end
    return outcome
end

--- A window in reach that is open or broken lets the gas out; so does standing outdoors.
function H.ventilated(sq)
    if not sq then return true end
    if sq.isOutside and sq:isOutside() then return true end
    return H.windowOpenNear(sq)
end

--- The 9x9 window walk behind H.ventilated, uncached.
function H.windowOpenNear(sq)
    for dx = -4, 4 do
        for dy = -4, 4 do
            local s = getSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
            local objs = s and s:getObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local o = objs:get(i)
                if instanceof(o, "IsoWindow") and ((o.IsOpen and o:IsOpen()) or (o.isSmashed and o:isSmashed())) then return true end
            end
        end
    end
    return false
end

-- How long a rack's ventilation answer is trusted, in in-game hours; the gas counter moves a minute at a time.
H.VENT_TTL_H = 5 / 60
H.ventMemo = H.ventMemo or {}      -- "x,y,z" -> { at = world hours, open = bool, sq }
local ventWrites = 0

local function worldHours()
    return E.worldHours and E.worldHours() or 0
end

--- H.ventilated for a rack, with the window walk remembered for H.VENT_TTL_H so a busy rack does not walk 81 squares every minute.
function H.ventilatedCached(sq)
    if not sq then return true end
    if sq.isOutside and sq:isOutside() then return true end
    local k = sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
    local now = worldHours()
    local c = H.ventMemo[k]
    -- age < 0 means the clock was set back; look again.
    if c and c.sq == sq and now - c.at >= 0 and now - c.at < H.VENT_TTL_H then return c.open end
    local open = H.windowOpenNear(sq)
    H.ventMemo[k] = { at = now, open = open, sq = sq }
    -- Now and then drop expired answers, so racks that were lifted do not stay in the table.
    ventWrites = ventWrites + 1
    if ventWrites >= 256 then
        ventWrites = 0
        for mk, mc in pairs(H.ventMemo) do
            if now - mc.at >= H.VENT_TTL_H or now < mc.at then H.ventMemo[mk] = nil end
        end
    end
    return open
end

--- Forget remembered ventilation, everywhere or on one square ("x,y,z").
function H.forgetVent(k)
    if k then H.ventMemo[k] = nil else H.ventMemo = {} end
end

function H.gas(rec, gen, chargeW)
    if P.sandbox("HydrogenRisk") == false or #(rec.banks or {}) == 0 then return end
    -- One state table per controller, so forgetting its gone racks never walks every other controller's.
    local mine = H2[rec.key]
    if not mine then
        mine = {}
        H2[rec.key] = mine
    end
    local seen = {}
    local perRack = chargeW / math.max(1, #rec.banks)
    for _, o in ipairs(rec.banks or {}) do
        local info = P.describe(o)
        local sq = o:getSquare()
        if info and sq then
            local k = sq:getX() .. "," .. sq:getY()
            local st = mine[k] or { m = 0, warned = false }
            -- Only a Makeshift rack charging hard can be at risk, so only that one needs its air looked at.
            local vent = perRack >= H.H2_RATE_W and info.tier == "makeshift" and H.ventilatedCached(sq)
            local risk = H.atRisk(info.tier, perRack, vent)
            local ev
            st.m, st.warned, ev = H.h2Step(st.m, st.warned, risk, ZombRandFloat and ZombRandFloat(0, 1) or math.random())
            mine[k] = st
            seen[k] = true
            if ev == "warn" then tell(sq, "IGUI_DazedPower_Hydrogen", true)
            elseif ev == "fire" and IsoFireManager and getCell then
                pcall(function() IsoFireManager.StartFire(getCell(), sq, true, 60) end)
                local d = P.data(o)
                d.condition = math.max(0, (d.condition or 100) - 30)
                o:transmitModData()
            end
        end
    end
    -- forget racks of this controller that are gone
    for k in pairs(mine) do
        if not seen[k] then mine[k] = nil end
    end
end

--- The hydrogen counters, for the headless checks: controller key -> "x,y" -> { m, warned }.
function H.h2State() return H2 end

if not H.wrapped then
    H.wrapped = true
    local upd0 = S.updateController
    function S.updateController(rec, dt, hoursAgo, wet)
        local before = 0
        for _, o in ipairs(rec.banks or {}) do before = before + (P.data(o).charge or 0) end
        local r = upd0(rec, dt, hoursAgo, wet)
        if hoursAgo or not dt or dt <= 0 then return r end
        local gen = P.objectAt(rec.x, rec.y, rec.z, "controller")
        if not gen then return r end
        -- A bench's lamp shows whether its system is up.
        local gd = P.data(gen)
        local up = gd.online ~= false and not gd.trip
        local want = up and "on" or "off"
        for _, b in ipairs((rec.dpm and rec.dpm.bench) or {}) do
            local bi = P.describe(b)
            if bi and bi.state ~= want then P.setState(b, want) end
        end
        local after = 0
        for _, o in ipairs(rec.banks or {}) do after = after + (P.data(o).charge or 0) end
        pcall(H.gas, rec, gen, math.max(0, (after - before) / dt))
        local env = E.read()
        gd = P.data(gen)
        if env.thunder and gd.online ~= false and not gd.trip then
            local roll = ZombRandFloat and ZombRandFloat(0, 1) or math.random()
            if roll < H.strikeChance(P.sandbox("StormRate") or 100) * (dt * 60) then pcall(H.strike, rec, gen) end
        end
        return r
    end
end
