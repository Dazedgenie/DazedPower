-- Headless check of the POWER tab in Dazed Control (server/DazedPower/DP_Control.lua) on a FAKE world: the view, its
-- lamps and marks, and every handler as an admin, a moderator and a plain player (the last two must change nothing).
-- Also writes the view of a realistic world to /home/claude/work/views/power.lua (or $VIEWS_OUT) for the lead to draw.
-- Run from tools/tests: lua control_tab_test.lua [<DazedCore lua root>]; Lua 5.1 or later. DAZEDCORE_LUA works too.
local core = arg[1] or os.getenv("DAZEDCORE_LUA") or "../../../dazedcore/Contents/mods/DazedCore/common/media/lua"
local root = "../../Contents/mods/DazedPower/common/media/lua"
package.path = core .. "/shared/?.lua;" .. root .. "/shared/?.lua;" .. package.path
local E = dofile(core .. "/../../../tools/tests/engine_stub.lua")
local print = E.realPrint
local fails, checks = 0, 0
local function check(c, m) checks = checks + 1 if not c then fails = fails + 1; print("FAIL " .. m) end end

------------------------------------------------------------------ the engine bits the tab reads
isClient = function() return false end
isServer = function() return false end
getDebug = function() return false end
local t = 1000
getTimestampMs = function() t = t + 1000 return t end
getGameTime = function() return { getNightsSurvived = function() return 18 end, getHour = function() return 10 end,
                                  getMinutes = function() return 42 end, getWorldAgeHours = function() return 450 end } end
getSquare = function(x, y, z) return E.squares[x .. "," .. y .. "," .. z] end
local md = {}
ModData = { getOrCreate = function(k) md[k] = md[k] or {} return md[k] end, get = function(k) return md[k] end }
Capability = { UseMovablesCheat = "cheat", BanUnbanUser = "ban" }
local function person(name, caps)
    local p = E.character(10600, 9400, 0)
    p.getUsername = function() return name end
    p.getRole = function() return { hasCapability = function(_, c) return caps[c] == true end } end
    return p
end
local admin, mod, user = person("Kyle", { cheat = true, ban = true }), person("Ash", { ban = true }), person("Pete", {})
getOnlinePlayers = function()
    local l = { admin, mod, user }
    return { size = function() return #l end, get = function(_, i) return l[i + 1] end }
end

local C = require "DazedCore/DC_Control"
local N = DazedCore.Net

------------------------------------------------------------------ fake mod state
DazedPower = { Parts = {}, System = {}, Admin = {}, More = { Model = {} } }
local P, S, A, MM = DazedPower.Parts, DazedPower.System, DazedPower.Admin, DazedPower.More.Model
function P.try(obj, m, ...)
    if not obj or not obj[m] then return nil end
    local ok, v = pcall(obj[m], obj, ...)
    if ok then return v end
    return nil
end
function P.describe(o) return o and o.info or nil end
function P.partOf(o) return o and o.info and o.info.kind or nil end
function P.data(o)
    local m = o:getModData()
    m.dazedpower = m.dazedpower or {}
    return m.dazedpower
end
local relinks = 0
S.controllers, S.order = {}, {}
function S.controllerOf(rec)
    local sq = getSquare(rec.x, rec.y, rec.z)
    if not sq then return nil end
    for _, o in ipairs(sq.objs) do if P.partOf(o) == "controller" then return o end end
    return nil
end
function S.relink(rec) relinks = relinks + 1 end
function A.partsOf(rec)
    local out = {}
    for _, l in ipairs({ rec.arrays or {}, rec.banks or {} }) do for _, o in ipairs(l) do out[#out + 1] = o end end
    return out
end
function A.repairPart(o) P.data(o).condition = 100 end
function A.fillBank(o) local d = P.data(o) d.charge = d.nominal end
local GAS_SPEC = { woodgas = { reservoir = 54, ash = 108 }, petrol = { reservoir = 20 }, propane = { reservoir = 9 } }
function MM.propaneSpec(tier, kind) return GAS_SPEC[kind] or GAS_SPEC.propane end
function MM.ashChoked(g) return g.kind == "woodgas" and (g.ash or 0) >= 108 end
function MM.propaneFuel(g) return math.max(0, g.lpg or 0) end

local function part(kind, tier, x, y, d)
    local o = E.object("dp_" .. kind, E.square(x, y, 0))
    o.info = { kind = kind, tier = tier }
    o.hasModData = function() return true end
    o.condition = 60
    o.setCondition = function(self, v) self.condition = v end
    o.md.dazedpower = d or {}
    return o
end
local function controller(x, y, tier, d, extra)
    local o = part("controller", tier, x, y, d)
    local k = x .. "," .. y .. ",0"
    local rec = { key = k, x = x, y = y, z = 0, arrays = {}, banks = {}, xfmrs = {}, relinkAt = 5, syncIn = 7 }
    for kk, v in pairs(extra or {}) do rec[kk] = v end
    S.controllers[k] = rec
    S.order[#S.order + 1] = k
    return o, rec
end

-- Riverside farm: a Workshop MPPT rig with a wood gas engine running
local bankA = part("bank", "workshop", 10656, 9380, { charge = 3000, nominal = 7360 })
local wood = part("woodgas", "workshop", 10657, 9381, { running = true, lpg = 30, ash = 67, condition = 90, mode = "auto" })
local ctlA, recA = controller(10655, 9380, "workshop",
    { owner = "Kyle", soc = 0.78, gen = 2400, load = 1000, cells = 8, capacity = 7360, online = true, arrayCount = 3 },
    { banks = { bankA }, dpm = { propane = { wood } } })
-- Muldraugh school: tripped (an old save's latch)
local arrB = part("array", "makeshift", 10621, 9750, { condition = 40 })
local ctlB, recB = controller(10620, 9750, "makeshift",
    { owner = "Ash", soc = 0.41, gen = 300, load = 0, cells = 4, capacity = 2240, online = true, trip = true, arrayCount = 1 },
    { arrays = { arrB } })
-- Gas station: low-voltage cut-off, its petrol engine dry
local petrol = part("petrol", "salvaged", 10751, 9851, { running = false, lpg = 0, noFuel = true })
local ctlC = controller(10750, 9850, "makeshift",
    { owner = "Jo", soc = 0.09, gen = 0, load = 0, cells = 3, capacity = 1680, online = true, lvd = true, lvdAt = 400, arrayCount = 2 },
    { dpm = { propane = { petrol } } })
-- Lake cabin: full and idle
controller(10500, 9600, "workshop", { owner = "Sam", soc = 1, gen = 0, load = 0, cells = 8, capacity = 7360, online = true, arrayCount = 2 })
-- an unclaimed controller with nothing wired
controller(10700, 9400, "makeshift", { soc = 0, online = true, arrayCount = 0 })
-- a known record whose chunk has streamed out, with an away snapshot
local k6 = "11200,9000,0"
S.controllers[k6] = { key = k6, x = 11200, y = 9000, z = 0, relinkAt = 3, syncIn = 4 }
S.order[#S.order + 1] = k6
md.DazedPowerRemote = { [k6] = { x = 11200, y = 9000, z = 0, bank = { capacity = 2000, charge = 1080 } },
                        ["12000,7000,0"] = { x = 12000, y = 7000, z = 0, bank = { capacity = 1000, charge = 500 } } }

dofile(root .. "/server/DazedPower/DP_Control.lua")
local PC = DazedPower.Control
check(C.tabs.power ~= nil and PC and PC.MODULE == "DazedPowerControl", "the POWER tab registers with its own Net module")
for _, cmd in ipairs({ "reset", "repair", "fill", "checkAll", "cleanAsh", "fillFuel" }) do
    check(N.server.DazedPowerControl[cmd] ~= nil and C.tabs.power.commands["DazedPowerControl." .. cmd] == "admin",
        cmd .. " is registered and needs an admin")
end

------------------------------------------------------------------ the view, as the panel sends it
local sent
N.onClient("DazedCore", "ctlView", function(a) sent = a end)
C.sendView(admin, "power")
check(sent and sent.tab == "power", "the panel sends the POWER view")
local view = sent.view
local lamps = view.lamps
check(lamps[1][1] == "Grid: 6 controllers" and lamps[1][2] == "green", "grid lamp counts every known controller")
check(lamps[2][1] == "Tripped: 1" and lamps[2][2] == "red", "one tripped")
check(lamps[3][1] == "Low battery: 1" and lamps[3][2] == "amber", "one low battery")
local ctl = view.cards[1]
check(ctl.title == "Controllers" and #ctl.items == 7, "six records and one away-only snapshot listed: " .. #ctl.items)
check(ctl.items[1].tone == "red" and ctl.items[1].text:find("Makeshift controller, 10620, 9750", 1, true), "trouble first: the tripped school")
check(ctl.items[2].tone == "amber" and ctl.items[2].sub:find("low-voltage cut-off", 1, true), "then the cut-off")
local byText = {}
for _, it in ipairs(ctl.items) do byText[it.text] = it end
local farm = byText["Workshop MPPT, 10655, 9380"]
check(farm and farm.tone == "green" and farm.sub == "running - Kyle - 78% - +1.4 kW - 8 cells", "the farm row: " .. tostring(farm and farm.sub))
check(farm and #farm.buttons == 3 and farm.buttons[1].need == "admin" and farm.buttons[1].args.x == 10655, "loaded rows carry Reset/Repair/Fill")
local empty = byText["Makeshift controller, 10700, 9400"]
check(empty and empty.tone == "muted" and empty.sub:find("no sources", 1, true) and empty.sub:find("unowned", 1, true), "no sources is muted")
local gone = byText["Charge controller, 11200, 9000"]
check(gone and gone.tone == "muted" and gone.sub == "unloaded, away 54%" and gone.buttons == nil, "an unloaded controller has no buttons")
check(byText["Charge controller, 12000, 7000"] ~= nil, "an away snapshot with no record yet is listed")
local grid = view.cards[2]
check(grid.title == "Whole grid" and grid.buttons[1].command == "checkAll" and grid.buttons[1].need == "admin", "whole grid card")
local gens = view.cards[3]
check(gens and gens.title == "Generators" and #gens.items == 2, "generators card lists the wired engines")
check(gens.items[1].tone == "red" and gens.items[1].sub:find("no fuel", 1, true) and gens.items[1].buttons[1].command == "fillFuel", "dry petrol engine")
check(gens.items[2].sub:find("ash 62%", 1, true) and gens.items[2].sub:find("stop it to clean", 1, true), "a running wood gas engine offers no clean")
check(#sent.marks == 6 and sent.marks[1].tone == "red", "one map mark per controller record")

------------------------------------------------------------------ handlers
local function snapshot()
    local out = {}
    local function put(prefix, tbl)
        for k, v in pairs(tbl) do if type(v) ~= "table" and type(v) ~= "function" then out[prefix .. k] = tostring(v) end end
    end
    for _, k in ipairs(S.order) do
        local r = S.controllers[k]
        put(k .. ".rec.", r)
        local o = S.controllerOf(r)
        if o then put(k .. ".d.", P.data(o)) out[k .. ".cond"] = tostring(o.condition) end
    end
    for i, o in ipairs({ bankA, arrB, wood, petrol }) do put(i .. ".part.", P.data(o)) end
    out.relinks = tostring(relinks)
    return out
end
local function same(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end
local function run(p, cmd, args) N.server.DazedPowerControl[cmd].fn(p, args) end
local function act(p, cmd, args) N.server.DazedCore.ctlAct.fn(p, { tab = "power", module = "DazedPowerControl", command = cmd, args = args }) end
wood.md.dazedpower.running = false

local before = snapshot()
for _, p in ipairs({ mod, user }) do
    for _, cmd in ipairs({ "reset", "repair", "fill", "checkAll" }) do
        run(p, cmd, { x = 10620, y = 9750, z = 0 })
        act(p, cmd, { x = 10620, y = 9750, z = 0 })
    end
    run(p, "cleanAsh", { x = 10657, y = 9381, z = 0 })
    run(p, "fillFuel", { x = 10751, y = 9851, z = 0 })
    act(p, "fillFuel", { x = 10751, y = 9851, z = 0 })
end
check(same(before, snapshot()), "a moderator and a plain player change nothing")
for _, bad in ipairs({ {}, { x = "10620", y = 9750.5, z = 0 }, { x = 10620, y = 9750, z = 99 }, { x = 1, y = 2, z = 0 }, "x", { x = 11200, y = 9000, z = 0 } }) do
    run(admin, "reset", bad); run(admin, "repair", bad); run(admin, "fill", bad); run(admin, "cleanAsh", bad); run(admin, "fillFuel", bad)
end
check(same(before, snapshot()), "odd, missing or unloaded targets change nothing, even for an admin")

act(admin, "reset", { x = 10620, y = 9750, z = 0 })
local dB = P.data(ctlB)
check(dB.trip == false and dB.lvd == false and dB.online == true and dB.equalise == false and recB.relinkAt == -1 and recB.syncIn == 0,
    "admin Reset clears the trip and relinks next tick")
run(admin, "repair", { x = 10620, y = 9750, z = 0 })
check(P.data(arrB).condition == 100 and dB.condition == 100 and ctlB.condition == 100, "admin Repair mends the parts and the controller")
run(admin, "fill", { x = 10655, y = 9380, z = 0 })
check(P.data(bankA).charge == 7360 and recA.syncIn == 0, "admin Fill fills the racks")
run(admin, "fillFuel", { x = 10751, y = 9851, z = 0 })
check(P.data(petrol).lpg == 20 and P.data(petrol).noFuel == nil, "admin Fill fuel fills the reservoir")
run(admin, "cleanAsh", { x = 10657, y = 9381, z = 0 })
check(P.data(wood).ash == 0, "admin Clean ash clears a stopped grate")
P.data(wood).ash, P.data(wood).running = 50, true
run(admin, "cleanAsh", { x = 10657, y = 9381, z = 0 })
check(P.data(wood).ash == 50, "never into a live grate")
local n0 = relinks
run(admin, "checkAll", {})
local all = true
for _, k in ipairs(S.order) do if S.controllers[k].relinkAt ~= -1 or S.controllers[k].syncIn ~= 0 then all = false end end
check(all and relinks == n0, "Check every network marks every record for its next tick")

-- a long list is capped with an "and N more" row
local saved = { S.controllers, S.order }
S.controllers, S.order = {}, {}
for i = 1, 20 do controller(20000 + i, 5000, "makeshift", { soc = 0.5, online = true, arrayCount = 1, capacity = 100 }) end
md.DazedPowerRemote = {}
local v2 = PC.view(admin)
check(#v2.cards[1].items == 15 and v2.cards[1].items[15].text == "and 6 more", "lists are capped at 14 and say how many more")
S.controllers, S.order = saved[1], saved[2]
-- with no simulation loaded the tab still answers
local sv = DazedPower.System
DazedPower.System = nil
local v3 = PC.view(admin)
check(v3 and v3.lamps[1][2] == "off" and #PC.marks() == 0, "no simulation: a quiet view and no marks")
DazedPower.System = sv

------------------------------------------------------------------ picture data
local function ser(v, ind)
    ind = ind or ""
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    local keys, n = {}, #v
    for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts, inner = {}, ind .. "  "
    for i = 1, n do parts[#parts + 1] = inner .. ser(v[i], inner) end
    for _, k in ipairs(keys) do
        local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. ser(k) .. "]")
        parts[#parts + 1] = inner .. key .. " = " .. ser(v[k], inner)
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "}"
end
local out = os.getenv("VIEWS_OUT") or "/home/claude/work/views/power.lua"
local f = io.open(out, "w")
if f then
    f:write("return " .. ser({ tab = "power", target = nil, view = view }) .. "\n")
    f:close()
    local ok, got = pcall(dofile, out)
    check(ok and got.view.clock == "D19 10:42" and #got.view.cards == 3, "picture data written and reads back")
else
    print("note: could not write " .. out)
end

print(string.format("control_tab_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
