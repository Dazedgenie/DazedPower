--[[ Dazed Power -- its POWER tab in Dazed Control (Dazed Core 1.8.1 and later).

     Shows every charge controller the simulation knows (DP_System's S.controllers, server memory only), the gas
     engines wired to them, and lets an admin reset, repair and fill a controller's system, clean a wood gas grate,
     fill an engine's tank, and have every network re-walked, all from anywhere on the map. The same field changes
     the near-by admin menu makes (DP_System adminReset/adminRepair/adminFill, DP_Admin helpers), but found by
     position from the server's own records, not by a staff member standing within reach.

     Only what is streamed in can be changed: a controller's ModData lives on its object, so an unloaded one shows
     "unloaded" (with its away snapshot when DP_Distrib keeps one) and has no buttons. After a restart the list
     fills only as chunks stream in.

     Server side only. With an older Core there is no Dazed Control and this file does nothing. ]]

if isClient() then return end

require "DazedCore/DC_Net"
pcall(require, "DazedCore/DC_Control")

local C = DazedCore and DazedCore.Control
local Net = DazedCore and DazedCore.Net
if not (C and C.register and Net and Net.on) then return end

DazedPower = DazedPower or {}
DazedPower.Control = DazedPower.Control or {}
local PC = DazedPower.Control

local MOD = "DazedPowerControl"
PC.MODULE = MOD
PC.MAX_ROWS = 14
PC.LOW_SOC = 0.15
PC.MAX_MARKS = 200
local GAS = { propane = true, petrol = true, woodgas = true }

-- Plain English: the server has no translations.
local CTRL_NAME = {
    makeshift = "Makeshift charge controller",
    workshop = "Workshop MPPT charge controller",
    salvaged = "Salvaged charge controller",
    basic = "Basic charge controller",
}
local GAS_NAME = { propane = "propane generator", petrol = "petrol generator", woodgas = "wood gas generator" }
local TIER_WORD = { makeshift = "Makeshift", salvaged = "Salvaged", workshop = "Workshop", basic = "Basic" }

local function Sys() return DazedPower.System end
local function Parts() return DazedPower.Parts end

-- A guarded method call: the mod's own helper when it is there, else a local one.
local function try(obj, method, ...)
    local P = Parts()
    if P and P.try then return P.try(obj, method, ...) end
    if not obj or not obj[method] then return nil end
    local ok, v = pcall(obj[method], obj, ...)
    if ok then return v end
    return nil
end

local function push(obj) try(obj, "transmitModData") end

-- An object's Dazed Power ModData, never creating ModData on an object that has none.
local function dataOf(obj)
    local P = Parts()
    if not (obj and P and P.data) then return nil end
    if obj.hasModData and try(obj, "hasModData") ~= true then return nil end
    local ok, d = pcall(P.data, obj)
    return ok and type(d) == "table" and d or nil
end

local function isAdmin(player) return C.atLeast(C.level(player), "admin") end

-- A whole number in range, or nil.
local function whole(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < lo or v > hi then return nil end
    return math.floor(v)
end

local function spot(args)
    if type(args) ~= "table" then return nil end
    local x, y, z = whole(args.x, 0, 1000000), whole(args.y, 0, 1000000), whole(args.z, -32, 32)
    if not (x and y and z) then return nil end
    return x, y, z
end

-- The record at x,y,z, from the server's own list.
local function recordAt(x, y, z)
    local S = Sys()
    if not (S and type(S.controllers) == "table" and type(S.order) == "table") then return nil end
    for i = 1, #S.order do
        local rec = S.controllers[S.order[i]]
        if rec and rec.x == x and rec.y == y and rec.z == z then return rec end
    end
    return nil
end

local function loaded(x, y, z) return getSquare ~= nil and getSquare(x, y, z) ~= nil end

-- The live controller for a request: a known record, its square streamed in, a real controller standing there.
local function controllerFor(player, args)
    if not isAdmin(player) then return nil end
    local x, y, z = spot(args)
    if not x then return nil end
    local rec = recordAt(x, y, z)
    if not (rec and loaded(x, y, z)) then return nil end
    local S, P = Sys(), Parts()
    local ctrl = S.controllerOf and S.controllerOf(rec)
    if not (ctrl and P and P.partOf and P.partOf(ctrl) == "controller") then return nil end
    return ctrl, rec, S
end

-- A gas engine standing at x,y,z, on a streamed-in square.
local function engineFor(player, args)
    if not isAdmin(player) then return nil end
    local x, y, z = spot(args)
    if not x then return nil end
    local sq = getSquare and getSquare(x, y, z)
    local P = Parts()
    if not (sq and P and P.describe) then return nil end
    local objs = try(sq, "getObjects")
    local n = objs and try(objs, "size") or 0
    for i = 0, n - 1 do
        local o = objs:get(i)
        local info = P.describe(o)
        if info and GAS[info.kind] then return o, info end
    end
    return nil
end

local function more() return DazedPower.More and DazedPower.More.Model end

---------------------------------------------------------------- reading

local function pct(f) return math.floor(math.max(0, math.min(1, tonumber(f) or 0)) * 100 + 0.5) end

local function kw(w)
    w = tonumber(w) or 0
    return string.format("%s%.1f kW", w >= 0 and "+" or "-", math.abs(w) / 1000)
end

local function where(rec)
    local s = rec.x .. ", " .. rec.y
    if (rec.z or 0) ~= 0 then s = s .. " (floor " .. rec.z .. ")" end
    return s
end

local function roomName(x, y, z)
    local sq = getSquare and getSquare(x, y, z)
    local room = sq and try(sq, "getRoom")
    local n = room and try(room, "getName")
    return type(n) == "string" and n ~= "" and n or nil
end

local function awaySnapshot(k)
    local store = ModData and ModData.get and ModData.get("DazedPowerRemote")
    return type(store) == "table" and store[k] or nil
end

-- One controller as plain facts: what the view, the lamps and the marks all read.
local RANK = { red = 1, amber = 2, muted = 3, blue = 4, green = 5 }
local function facts(rec)
    local f = { rec = rec, x = rec.x, y = rec.y, z = rec.z, place = where(rec) }
    local S, P = Sys(), Parts()
    local ctrl = loaded(rec.x, rec.y, rec.z) and S.controllerOf and S.controllerOf(rec) or nil
    local d = ctrl and dataOf(ctrl)
    if not d then
        f.loaded = false
        f.name = "Charge controller"
        local snap = awaySnapshot(rec.key)
        local b = snap and snap.bank
        if b and (tonumber(b.capacity) or 0) > 0 then
            f.soc = (tonumber(b.charge) or 0) / b.capacity
            f.state = "unloaded, away " .. pct(f.soc) .. "%"
        else
            f.state = "unloaded"
        end
        f.tone = "muted"
        return f
    end
    f.loaded = true
    local info = P.describe and P.describe(ctrl)
    local tier = info and info.tier or d.tier or "makeshift"
    f.name = CTRL_NAME[tier] or ((TIER_WORD[tier] or tostring(tier)) .. " charge controller")
    f.room = roomName(rec.x, rec.y, rec.z)
    f.owner = type(d.owner) == "string" and d.owner ~= "" and d.owner or nil
    f.soc = tonumber(d.soc) or 0
    f.net = (tonumber(d.gen) or 0) - (tonumber(d.load) or 0)
    f.cells = tonumber(d.cells) or 0
    f.trip, f.lvd, f.online = d.trip == true, d.lvd == true, d.online ~= false
    local sources = (tonumber(d.arrayCount) or 0) + (type(d.dpmRows) == "table" and #d.dpmRows or 0)
    f.hasBank = (tonumber(d.capacity) or 0) > 0
    if f.trip then
        f.tone, f.state = "red", "TRIPPED"
    elseif f.lvd then
        f.tone, f.state = "amber", "low-voltage cut-off"
    elseif not f.online then
        f.tone, f.state = "muted", "switched off"
    elseif sources == 0 then
        f.tone, f.state = "muted", "no sources"
    elseif f.hasBank and f.soc < PC.LOW_SOC then
        f.tone, f.state = "amber", "low battery"
    else
        f.tone, f.state = "green", (tonumber(d.load) or 0) > 0 and "running" or "idle"
    end
    f.low = f.lvd or (f.hasBank and f.soc < PC.LOW_SOC)
    -- the gas engines wired to it, from its last relink (DPM_Bridge files them under propane)
    f.engines = {}
    local list = type(rec.dpm) == "table" and rec.dpm.propane or nil
    for i = 1, #(list or {}) do
        local o = list[i]
        local ix = try(o, "getObjectIndex")
        if type(ix) ~= "number" or ix >= 0 then f.engines[#f.engines + 1] = o end
    end
    return f
end

local function allFacts()
    local S = Sys()
    local out = {}
    if not (S and type(S.controllers) == "table" and type(S.order) == "table") then return out, false end
    for i = 1, #S.order do
        local rec = S.controllers[S.order[i]]
        if rec and rec.x and rec.y and rec.z then out[#out + 1] = facts(rec) end
    end
    table.sort(out, function(a, b)
        if RANK[a.tone] ~= RANK[b.tone] then return RANK[a.tone] < RANK[b.tone] end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    return out, true
end

-- Away snapshots of systems no record holds yet: known, but not streamed in since the restart.
local function awayOnly()
    local store = ModData and ModData.get and ModData.get("DazedPowerRemote")
    local S = Sys()
    local out = {}
    if type(store) ~= "table" then return out end
    for k, snap in pairs(store) do
        if type(snap) == "table" and not (S and S.controllers and S.controllers[k]) and tonumber(snap.x) and tonumber(snap.y) then
            out[#out + 1] = { key = k, snap = snap }
        end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

---------------------------------------------------------------- the view

local function btn(label, command, args, extra)
    local b = { label = label, module = MOD, command = command, args = args }
    for k, v in pairs(extra or {}) do b[k] = v end
    return b
end

local function at(f) return { x = f.x, y = f.y, z = f.z } end

local function controllerItem(f)
    local bits = {}
    if f.loaded then
        bits[#bits + 1] = f.owner or "unowned"
        bits[#bits + 1] = f.hasBank and (pct(f.soc) .. "%") or "no bank"
        if f.tone ~= "muted" and f.state ~= "low-voltage cut-off" then bits[#bits + 1] = kw(f.net) end
        if f.cells > 0 then bits[#bits + 1] = f.cells .. " cells" end
        bits[#bits + 1] = f.state
    else
        bits[#bits + 1] = f.state
    end
    local text = f.name .. ", " .. f.place .. (f.room and (" (" .. f.room .. ")") or "")
    local item = { text = text, sub = table.concat(bits, " - "), tone = f.tone }
    if f.loaded then
        item.buttons = { btn("Reset", "reset", at(f)), btn("Repair", "repair", at(f)), btn("Fill", "fill", at(f)) }
    end
    return item
end

local function engineItem(o, owner)
    local P, MM = Parts(), more()
    local info = P.describe(o)
    local d = dataOf(o) or {}
    local sq = try(o, "getSquare")
    if not (info and sq) then return nil end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local spec = MM and MM.propaneSpec and MM.propaneSpec(info.tier, info.kind) or nil
    local bits, tone = {}, "muted"
    local running = d.running == true
    local cond = tonumber(d.condition) or 100
    local choked = info.kind == "woodgas" and MM and MM.ashChoked and MM.ashChoked({ kind = "woodgas", tier = info.tier, ash = d.ash })
    local fuel = MM and MM.propaneFuel and MM.propaneFuel(d) or (tonumber(d.lpg) or 0)
    local res = spec and spec.reservoir or 0
    bits[#bits + 1] = running and "running" or (d.mode == "auto" and "on auto" or "off")
    if res > 0 then bits[#bits + 1] = (info.kind == "woodgas" and "hopper " or "fuel ") .. pct((tonumber(d.lpg) or 0) / res) .. "%" end
    if info.kind == "woodgas" and spec and spec.ash then bits[#bits + 1] = "ash " .. pct((tonumber(d.ash) or 0) / spec.ash) .. "%" end
    if cond < 100 then bits[#bits + 1] = "condition " .. math.floor(cond) .. "%" end
    if cond <= 35 then
        tone = "red"; bits[#bits + 1] = "broken"
    elseif choked then
        tone = "red"; bits[#bits + 1] = "grate choked"
    elseif fuel <= 0 then
        tone = "red"; bits[#bits + 1] = "no fuel"
    elseif res > 0 and (tonumber(d.lpg) or 0) / res < PC.LOW_SOC then
        tone = "amber"
    elseif running then
        tone = "green"
    end
    local buttons = {}
    local args = { x = x, y = y, z = z }
    if info.kind == "woodgas" and (tonumber(d.ash) or 0) > 0 then
        if running then bits[#bits + 1] = "stop it to clean" else buttons[#buttons + 1] = btn("Clean ash", "cleanAsh", args) end
    end
    if res > 0 and (tonumber(d.lpg) or 0) < res - 0.001 then buttons[#buttons + 1] = btn("Fill fuel", "fillFuel", args) end
    return { text = (TIER_WORD[info.tier] or tostring(info.tier)) .. " " .. (GAS_NAME[info.kind] or info.kind) .. ", " .. x .. ", " .. y
                    .. (owner and (" (" .. owner .. ")") or ""),
             sub = table.concat(bits, " - "), tone = tone, buttons = buttons }
end

local function capped(list, n)
    if #list <= n then return list end
    local out = {}
    for i = 1, n do out[i] = list[i] end
    out[#out + 1] = { text = "and " .. (#list - n) .. " more", tone = "muted" }
    return out
end

function PC.view()
    local list, ok = allFacts()
    if not ok then
        return { lamps = { { "Grid: not running", "off" } },
                 cards = { { title = "Controllers", lines = { "The power simulation is not loaded on this server." } } } }
    end
    local items, engines = {}, {}
    local tripped, low, streamed = 0, 0, 0
    for _, f in ipairs(list) do
        items[#items + 1] = controllerItem(f)
        if f.loaded then streamed = streamed + 1 end
        if f.trip then tripped = tripped + 1 end
        if f.low then low = low + 1 end
        for _, o in ipairs(f.engines or {}) do
            local it = engineItem(o, f.owner)
            if it then engines[#engines + 1] = it end
        end
    end
    local away = awayOnly()
    for _, a in ipairs(away) do
        local b = a.snap.bank
        local soc = b and (tonumber(b.capacity) or 0) > 0 and pct((tonumber(b.charge) or 0) / b.capacity) .. "%" or "?"
        items[#items + 1] = { text = "Charge controller, " .. math.floor(a.snap.x) .. ", " .. math.floor(a.snap.y),
                              sub = "not streamed in since the restart - away " .. soc, tone = "muted" }
    end
    if #items == 0 then items[1] = { text = "No controllers streamed in", sub = "they appear as their chunks load", tone = "muted" } end
    local cards = {
        { title = "Controllers", items = capped(items, PC.MAX_ROWS) },
        { title = "Whole grid", rows = {
            { "Controllers known", tostring(#list) },
            { "Streamed in", tostring(streamed), streamed < #list and "amber" or nil },
            { "Away, not seen since restart", tostring(#away), #away > 0 and "amber" or nil },
            { "Note", "after a restart the list fills as chunks load" },
            { "Buttons", "only on streamed-in controllers" } },
          buttons = { btn("Check every network", "checkAll") } },
    }
    if #engines > 0 then
        table.sort(engines, function(a, b)
            if RANK[a.tone] ~= RANK[b.tone] then return RANK[a.tone] < RANK[b.tone] end
            return a.text < b.text
        end)
        cards[#cards + 1] = { title = "Generators", items = capped(engines, PC.MAX_ROWS) }
    end
    return {
        lamps = {
            { "Grid: " .. #list .. " controller" .. (#list == 1 and "" or "s"), #list > 0 and "green" or "off" },
            { "Tripped: " .. tripped, tripped > 0 and "red" or "off" },
            { "Low battery: " .. low, low > 0 and "amber" or "off" },
        },
        cards = cards,
    }
end

function PC.marks()
    local list = allFacts()
    local out = {}
    for _, f in ipairs(list) do
        if #out >= PC.MAX_MARKS then break end
        out[#out + 1] = { x = f.x, y = f.y, tone = f.tone,
                          label = f.name .. ": " .. f.state .. (f.loaded and f.hasBank and (", " .. pct(f.soc) .. "%") or "") }
    end
    return out
end

---------------------------------------------------------------- the handlers (authority only)

--- Clear the breaker trip and the low-voltage disconnect, switch on, stop equalising, relink next tick (as adminReset).
function PC.reset(player, args)
    local ctrl, rec = controllerFor(player, args)
    if not ctrl then return end
    if DazedPower.Place and DazedPower.Place.adopt then pcall(DazedPower.Place.adopt, ctrl) end
    local d = dataOf(ctrl) or Parts().data(ctrl)
    d.trip = false
    d.lvd = false
    d.lvdAt = nil
    d.online = true
    d.equalise = false
    rec.relinkAt = -1
    rec.syncIn = 0
    push(ctrl)
end

--- Every part the system holds and the controller itself back to full condition (as adminRepair).
function PC.repair(player, args)
    local ctrl, rec, S = controllerFor(player, args)
    local A = DazedPower.Admin
    if not (ctrl and A and A.partsOf and A.repairPart) then return end
    if S.relink then S.relink(rec) end
    local parts = A.partsOf(rec)
    for i = 1, #parts do
        A.repairPart(parts[i])
        push(parts[i])
    end
    if ctrl.setCondition then pcall(ctrl.setCondition, ctrl, 100) end
    Parts().data(ctrl).condition = 100
    rec.syncIn = 0
    push(ctrl)
end

--- Every rack in the system filled to its nominal capacity (as adminFill).
function PC.fill(player, args)
    local ctrl, rec, S = controllerFor(player, args)
    local A = DazedPower.Admin
    if not (ctrl and A and A.fillBank) then return end
    if S.relink then S.relink(rec) end
    for i = 1, #(rec.banks or {}) do
        A.fillBank(rec.banks[i])
        push(rec.banks[i])
    end
    rec.syncIn = 0
    push(ctrl)
end

--- Every known network re-walked on the next tick and pushed at once. Unloaded ones are walked when they stream in.
function PC.checkAll(player)
    if not isAdmin(player) then return end
    local S = Sys()
    if not (S and type(S.controllers) == "table" and type(S.order) == "table") then return end
    local n = 0
    for i = 1, #S.order do
        local rec = S.controllers[S.order[i]]
        if rec then
            rec.relinkAt = -1
            rec.syncIn = 0
            n = n + 1
        end
    end
    print("DazedPower: Dazed Control marked " .. n .. " networks for a relink")
end

--- Clear a stopped wood gas generator's grate (as DPM_WoodGasAsh). Never into a live grate.
function PC.cleanAsh(player, args)
    local o, info = engineFor(player, args)
    if not (o and info.kind == "woodgas") then return end
    local d = dataOf(o)
    if not d or d.running == true then return end
    d.ash, d.choked = 0, nil
    push(o)
end

--- Fill a gas engine's own reservoir (the wood gas one's hopper) to its spec.
function PC.fillFuel(player, args)
    local o, info = engineFor(player, args)
    local MM = more()
    if not (o and MM and MM.propaneSpec) then return end
    local spec = MM.propaneSpec(info.tier, info.kind)
    local d = dataOf(o)
    if not (d and spec and (tonumber(spec.reservoir) or 0) > 0) then return end
    if (tonumber(d.lpg) or 0) < spec.reservoir then d.lpg = spec.reservoir end
    d.noFuel = nil
    push(o)
end

for _, cmd in ipairs({ "reset", "repair", "fill", "checkAll", "cleanAsh", "fillFuel" }) do
    local fn = PC[cmd]
    Net.on(MOD, cmd, function(player, args) fn(player, args) end, 500)
end

C.register("power", {
    title = "Power",
    order = 30,
    commands = { [MOD .. ".reset"] = "admin", [MOD .. ".repair"] = "admin", [MOD .. ".fill"] = "admin",
                 [MOD .. ".checkAll"] = "admin", [MOD .. ".cleanAsh"] = "admin", [MOD .. ".fillFuel"] = "admin" },
    view = function(viewer) return PC.view(viewer) end,
    marks = function(viewer) return PC.marks(viewer) end,
})

return PC
