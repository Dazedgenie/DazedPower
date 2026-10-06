--[[ DazedPower -- the monitor's GEN page, for the propane and petrol generators.

     The controller keeps the page's settings: the master AUTO (d.bkAuto) and the start and stop
     battery levels (d.bkStart, d.bkStop, held to M.backupLevels). Every live step the bridge hands
     this file the generators it ran, and the controller gets a small mirror of them under bk*
     names for the window to draw; the settings are copied onto each generator, so the same rules
     hold while the base is unloaded. A press on the page is a short action at the controller whose
     completion runs GP.command on the authority. ]]

require "DazedPower/DP_Parts"
require "DazedPower/DP_Model"
require "DazedPower/DPM_Parts"
require "DazedPower/DPM_Model"

DazedPower = DazedPower or {}
DazedPower.GenPanel = DazedPower.GenPanel or {}
local GP = DazedPower.GenPanel
local P = DazedPower.Parts
local UM = DazedPower.Model
local MM = DazedPower.More.Model
local try = P.try

GP.MAX_ROWS = 4                 -- the rows the page has room for (DP_Window's GEN.rows)
GP.STEP = 0.05                  -- one press of a level's - or +
GP.FAULT_AT = 35                -- condition at or under which an engine shows FAULT (as the bridge's "broken")
GP.UNIT = { propane = "kg", petrol = "L" }

local function round(v, places)
    local m = 10 ^ (places or 0)
    return math.floor((v or 0) * m + 0.5) / m
end

--- The controller's levels as fractions: start, stop, the start Auto really uses, and the ends of the start's range.
function GP.levels(d)
    return UM.backupLevels(d.dod or UM.DAMAGE_SOC, d.floorSoc, d.bkStart, d.bkStop)
end

--- The word the page shows for one generator.
function GP.state(g)
    local spec = MM.propaneSpec(g.tier, g.kind)
    if (g.condition or 100) <= GP.FAULT_AT then return "fault" end
    if g.running then return "running" end
    if MM.propaneFuel(g) <= 0 then return "nofuel" end
    if g.coldFail then return "cold" end
    if g.mode == "auto" and spec.auto and not g.hold then return "standby" end
    return "off"
end

--- One generator's row for the page, from its step entry (the bridge's genEntry after the step).
function GP.row(g)
    local spec = MM.propaneSpec(g.tier, g.kind)
    local sq = g.obj and try(g.obj, "getSquare")
    local x, y, z = sq and sq:getX() or 0, sq and sq:getY() or 0, sq and sq:getZ() or 0
    local fuel = MM.propaneFuel(g)
    local w = g.watts or 0
    local burn = g.running and MM.propaneBurnAt(g.tier, w, g.kind) or 0
    return {
        k = UM.nodeKey(x, y, z, g.kind), kind = g.kind, t = g.kind .. "_" .. (g.tier or "salvaged"),
        s = GP.state(g), auto = (g.mode == "auto" and spec.auto) or false, noAuto = not spec.auto,
        w = math.floor(w + 0.5), u = GP.UNIT[g.kind] or "kg",
        tank = round(math.max(0, g.lpg or 0), 1), feed = round(math.max(0, fuel - math.max(0, g.lpg or 0)), 1),
        burn = round(burn, 2), left = (burn > 0) and round(fuel / burn, 1) or -1,
        cond = math.floor((g.condition or 100) + 0.5), x = x, y = y, z = z,
    }
end

--- Running first, then the most watts, then position, so the four rows shown are the ones that matter.
function GP.sortRows(rows)
    table.sort(rows, function(a, b)
        if (a.s == "running") ~= (b.s == "running") then return a.s == "running" end
        if a.w ~= b.w then return a.w > b.w end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    return rows
end

--- Copy the controller's settings onto one generator (its ModData and its step entry). True if anything changed.
function GP.applySettings(g, d, eff, stop)
    local hold = (d.bkAuto == false) or nil
    local startPct, stopPct = math.floor(eff * 100 + 0.5), math.floor(stop * 100 + 0.5)
    if g.startPct == startPct and g.stopPct == stopPct and g.hold == hold then return false end
    g.startPct, g.stopPct, g.hold = startPct, stopPct, hold
    if g.obj and try(g.obj, "getObjectIndex") ~= -1 then
        local gd = P.data(g.obj)
        gd.startPct, gd.stopPct, gd.hold = startPct, stopPct, hold
        g.obj:transmitModData()
    end
    return true
end

--- Write the page's mirror onto the controller after a live step; sends it only when what the page shows changed.
function GP.mirror(ctrl, d, src, dt)
    local gens = (src and src.gens) or {}
    local start, stop, eff = GP.levels(d)
    d.bkStartNow, d.bkStopNow = start, stop

    -- "Today" rolls at midnight with the controller's own ledger (DP_System), which zeroes these too.
    d.bkWhToday = (d.bkWhToday or 0) + (src and src.genW or 0) * math.max(0, dt or 0)

    local rows, cap = {}, 0
    for i = 1, #gens do
        local g = gens[i]
        GP.applySettings(g, d, eff, stop)
        local used = math.max(0, (g.fuel0 or 0) - MM.propaneFuel(g))
        if g.kind == "petrol" then d.bkFuelL = (d.bkFuelL or 0) + used
        else d.bkFuelKg = (d.bkFuelKg or 0) + used end
        if (g.condition or 100) > GP.FAULT_AT then cap = cap + MM.propaneAvailable(g) end
        rows[#rows + 1] = GP.row(g)
    end
    GP.sortRows(rows)
    local shown = {}
    for i = 1, math.min(GP.MAX_ROWS, #rows) do shown[i] = rows[i] end
    d.bkRows = (#shown > 0) and shown or nil
    d.bkN, d.bkMore = #rows, math.max(0, #rows - GP.MAX_ROWS)
    d.bkW = math.floor((src and src.genW or 0) + 0.5)
    d.bkCap = math.floor(cap + 0.5)
    if d.bkAuto == nil then d.bkAuto = true end

    -- Sent at once only for what a player is waiting to see change: a switch, a level, a start or stop, an
    -- engine added or gone, a big swing in output. Fuel, hours left and today's totals ride the controller's
    -- ordinary sync, so a running engine does not resend the controller every minute.
    local sig = table.concat({ d.bkN, tostring(d.bkAuto), start, stop, math.floor(d.bkW / 250) }, "|")
    for i = 1, #shown do
        local r = shown[i]
        sig = sig .. ";" .. table.concat({ r.k, r.s, tostring(r.auto), r.cond >= GP.FAULT_AT and 1 or 0 }, ",")
    end
    if sig ~= d.bkSig then
        d.bkSig = sig
        ctrl:transmitModData()
        return true
    end
    return false
end

----------------------------------------------------------------- presses

local function mayUse(playerObj, obj)
    local G = DazedPower.Place
    if not (playerObj and G and G.mayUse) then return true end
    return G.mayUse(playerObj, obj)
end

--- One of this controller's generators by its row's square (gx, gy, gz) and kind, or nil.
local function genOf(ctrl, args)
    local x, y, z = tonumber(args.gx), tonumber(args.gy), tonumber(args.gz)
    if not (x and y and z) then return nil end
    local kind = (args.kind == "petrol") and "petrol" or "propane"
    local obj = P.objectAt(x, y, z, kind)
    if not obj then return nil end
    -- It must hang off this controller's own system, or the page could reach anyone's engine.
    local csq = ctrl:getSquare()
    local root = csq and UM.nodeKey(csq:getX(), csq:getY(), csq:getZ(), "controller")
    local claimed = DazedPower.System and DazedPower.System.claimed and DazedPower.System.claimed[root]
    if claimed and not claimed[UM.nodeKey(x, y, z, kind)] then return nil end
    return obj
end

--- Start one engine from the page through the model's switch, so a cold start can fail. True when it runs.
function GP.start(obj, info, gd)
    local E = DazedPower.Env
    local g = { tier = info and info.tier, kind = info and info.kind, mode = "on", running = gd.running == true }
    for _, f in ipairs({ "condition", "lpg", "feedTank", "lineTx", "lineTy", "lineTz", "t1Type", "t1Fill", "t2Type", "t2Fill" }) do
        g[f] = gd[f]
    end
    if not g.running and E and E.engineAir then g.ambient = E.engineAir(obj) end
    local run = MM.propaneSwitch(g, nil)
    gd.running, gd.noFuel, gd.coldFail = run, g.noFuel, g.coldFail
    return run
end

local function setMode(obj, mode)
    local d = P.data(obj)
    d.mode = mode
    if mode == "off" then d.running = false end
    if DazedPower.More.Parts and DazedPower.More.Parts.setVariant then
        local broken = (d.condition or 100) <= GP.FAULT_AT
        DazedPower.More.Parts.setVariant(obj, (broken and "broken") or (d.running and "running") or "off")
    end
    obj:transmitModData()
end

--- Run one GEN page press on the authority. Returns true when it changed something.
function GP.command(playerObj, ctrl, cmd, args)
    if isClient() or not ctrl then return false end
    args = type(args) == "table" and args or {}
    if not mayUse(playerObj, ctrl) then return false end
    local d = P.data(ctrl)
    if cmd == "bkMaster" then
        d.bkAuto = args.value == true
    elseif cmd == "bkLevelStart" or cmd == "bkLevelStop" then
        local dir = (tonumber(args.value) or 0) > 0 and 1 or -1
        local start, stop = GP.levels(d)
        if cmd == "bkLevelStart" then d.bkStart = start + dir * GP.STEP
        else d.bkStop = stop + dir * GP.STEP end
        -- Held to the model's ranges at once, so the next press steps from what the page shows.
        d.bkStart, d.bkStop = GP.levels(d)
    elseif cmd == "bkAuto" or cmd == "bkRun" then
        local obj = genOf(ctrl, args)
        if not obj or not mayUse(playerObj, obj) then return false end
        local info = DazedPower.More.Parts.describe(obj)
        local spec = MM.propaneSpec(info and info.tier, info and info.kind)
        local gd = P.data(obj)
        if cmd == "bkAuto" then
            if not spec.auto then
                if DazedCore.Note then DazedCore.Note.say(playerObj, "IGUI_DazedPower_GenNoAuto", nil, true) end
                return false
            end
            setMode(obj, (args.value == true) and "auto" or "off")
        else
            if gd.mode == "auto" then return false end          -- greyed on the page while AUTO is on
            if args.value == true then
                -- A pull-cord engine has to be started by hand, standing at it.
                if not spec.auto then
                    if DazedCore.Note then DazedCore.Note.say(playerObj, "IGUI_DazedPower_GenPullCord", nil, true) end
                    return false
                end
                if (gd.condition or 100) <= GP.FAULT_AT or MM.propaneFuel(gd) <= 0 then return false end
                if not GP.start(obj, info, gd) then
                    if DazedCore.Note then DazedCore.Note.say(playerObj, "IGUI_DazedPower_GenColdNote", nil, true) end
                    setMode(obj, "off")
                    d.bkSig = nil
                    ctrl:transmitModData()
                    return true
                end
                setMode(obj, "on")
            else
                gd.coldFail = nil
                setMode(obj, "off")
            end
        end
    else
        return false
    end
    d.bkSig = nil              -- the mirror sends at the next step whatever it holds
    ctrl:transmitModData()
    return true
end

------------------------------------------------------------ the press action

--  A few seconds at the controller's panel, as the breaker is; its completion runs on the authority.
DP_GenPanelAction = ISBaseTimedAction and ISBaseTimedAction:derive("DP_GenPanelAction") or {}

function DP_GenPanelAction:isValid()
    return self.object ~= nil and self.object:getObjectIndex() ~= -1
end

function DP_GenPanelAction:waitToStart()
    self.character:faceThisObject(self.object)
    return self.character:shouldBeTurning()
end

function DP_GenPanelAction:update()
    self.character:faceThisObject(self.object)
end

function DP_GenPanelAction:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
end

function DP_GenPanelAction:stop()
    ISBaseTimedAction.stop(self)
end

function DP_GenPanelAction:perform()
    ISBaseTimedAction.perform(self)
end

function DP_GenPanelAction:complete()
    GP.command(self.character, self.object, self.cmd,
               { gx = self.gx, gy = self.gy, gz = self.gz, kind = self.gkind, value = self.value })
    return true
end

function DP_GenPanelAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 25
end

--- Plain fields only, so the action reaches a dedicated server whole: the engine's square and kind, and the value.
function DP_GenPanelAction:new(character, object, cmd, args)
    local o = ISBaseTimedAction.new(self, character)
    args = type(args) == "table" and args or {}
    o.object, o.cmd = object, cmd
    o.gx, o.gy, o.gz, o.gkind, o.value = args.gx, args.gy, args.gz, args.kind, args.value
    o.maxTime = o:getDuration()
    return o
end

return GP
