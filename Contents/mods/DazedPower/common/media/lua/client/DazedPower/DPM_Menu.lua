--[[ Dazed Power -- the right-click rows for the added parts.

     Dazed Power already builds the whole "Dazed Power" submenu for any part it
     recognises -- and it recognises ours (DPM_Parts) -- so a windmill
     already gets Info, the cable rows and Take down with no help. What it
     cannot know is OUR rows: a status line, Pedal, the gear kits, the
     boiler's fuel, water and fire, repair.

     They go in through C.icon, the helper Dazed Power calls for every row it
     adds. When the row being added is "Info", its option carries the part
     it was built for (option.param1, as ISContextMenu:addOption stores its
     arguments) and the player (param2), and `menu` IS the Dazed Power submenu.
     That is the moment to add ours, right under Info and above the cable
     rows. Every step is guarded: if a future Dazed Power builds its menu some
     other way, the rows simply do not appear and nothing else changes.
]]

require "DazedPower/DP_Context"
require "DazedPower/DP_Parts"
require "DazedPower/DPM_Parts"
require "DazedPower/DPM_Model"
require "DazedPower/DPM_Env"
require "DazedPower/DPM_Stats"
require "DazedPower/DPM_Actions"

local C = DazedPower.Context
local P = DazedPower.Parts
local R = DazedPower.More.Parts
local M = DazedPower.More.Model
if not (C and C.icon) then return end

---------------------------------------------------------------- helpers

--- Every item in a container and the bags inside it that `pred` takes.
local function collectRecurse(inv, pred, out)
    out = out or {}
    local items = inv and inv.getItems and inv:getItems()
    if not items then return out end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it then
            if pred(it) then out[#out + 1] = it end
            if it.IsInventoryContainer and it:IsInventoryContainer() and it.getInventory then
                collectRecurse(it:getInventory(), pred, out)
            end
        end
    end
    return out
end

-- Fuel: vanilla's own test first (so modded fuel works), a list if it fails.
local FUEL_FALLBACK = {
    ["Base.Log"] = true, ["Base.Plank"] = true, ["Base.TreeBranch2"] = true,
    ["Base.Twigs"] = true, ["Base.UnusableWood"] = true, ["Base.ScrapWood"] = true,
    ["Base.Firewood"] = true, ["Base.Charcoal"] = true,
}
local function isFuel(item)
    if not item then return false end
    if item.isEquipped and item:isEquipped() then return false end
    if ISCampingMenu and ISCampingMenu.isValidFuel then
        local ok, v = pcall(ISCampingMenu.isValidFuel, item)
        if ok then return v == true end
    end
    return FUEL_FALLBACK[item:getFullType()] == true
end

local STARTER_FALLBACK = {
    ["Base.Lighter"] = true, ["Base.Matches"] = true,
    ["Base.LighterDisposable"] = true, ["Base.LighterBBQ"] = true,
}
local function isStarter(item)
    if not item then return false end
    if ItemTag and ItemTag.START_FIRE then
        local ok, v = pcall(item.hasTag, item, ItemTag.START_FIRE)
        if ok and v then return true end
    end
    return STARTER_FALLBACK[item:getFullType()] == true
end

local function waterIn(item)
    local fc = item and item.getFluidContainer and item:getFluidContainer()
    return fc and fc.getAmount and (fc:getAmount() or 0) or 0
end

-- Dazed Power's own water test (DP_Context's predicateWater), repeated here
-- because the original is private to that file.
local function isWater(item)
    local ok, v = pcall(function() return item:isWaterSource() and item:getCurrentUses() > 0 end)
    return ok and v and waterIn(item) > 0
end

local function findRepairParts(playerObj)
    local inv = playerObj:getInventory()
    return inv:getFirstEvalRecurse(function(i) return i ~= nil and i:getFullType() == "Base.ElectronicsScrap" end),
           inv:getFirstEvalRecurse(function(i) return i ~= nil and i:getFullType() == "Base.Screws" end)
end

local function hasScrewdriver(playerObj)
    if P.hasScrewdriver then return P.hasScrewdriver(playerObj) end
    return true
end

local function tip(key) return C.tip(getText(key)) end

------------------------------------------------------------ status lines

local function status(obj, info)
    local d = P.data(obj)
    local bits = {}
    if not d.sys or d.sys == "" then bits[#bits + 1] = getText("IGUI_DazedPower_NotWired") end
    if d.amp then bits[#bits + 1] = getText("IGUI_DazedPower_Amplified") end
    if info.kind == "pedal" then
        if (d.pedalWatts or 0) > 0 then
            bits[#bits + 1] = P.txt("IGUI_DazedPower_SteamMaking", math.floor(d.pedalWatts + 0.5))
        end
        bits[#bits + 1] = P.txt("IGUI_DazedPower_Gear", getText("IGUI_DazedPower_Gear_" .. (d.gear or "stock")))
    elseif info.kind == "windmill" then
        if d.indoors then
            bits[#bits + 1] = getText("IGUI_DazedPower_UnderRoof")
        elseif type(d.windKph) == "number" then
            local kph = math.floor(d.windKph + 0.5)
            if kph < 1 then bits[#bits + 1] = getText("IGUI_DazedPower_WindCalm")
            elseif type(d.windFrom) == "number" and DazedPower.More.Env then
                bits[#bits + 1] = P.txt("IGUI_DazedPower_WindFrom", kph, (DazedPower.More.Env.sectorOf(d.windFrom)))
            else bits[#bits + 1] = P.txt("IGUI_DazedPower_WindKph", kph) end
        end
        if info.state == "furled" then bits[#bits + 1] = getText("IGUI_DazedPower_Furled")
        elseif d.overspeed then bits[#bits + 1] = getText("IGUI_DazedPower_Overspeed")
        elseif (d.windWatts or 0) > 0 then
            bits[#bits + 1] = P.txt("IGUI_DazedPower_WindMaking", math.floor(d.windWatts + 0.5))
        end
        if not M.windSpec(info.tier).tracks then
            bits[#bits + 1] = P.txt("IGUI_DazedPower_RotorFaces", info.facing)
        end
    elseif info.kind == "steam" then
        if d.indoors then bits[#bits + 1] = getText("IGUI_DazedPower_UnderRoof") end
        local heat = d.heat or 0
        if d.lit then
            if heat < M.STEAM_READY then
                bits[#bits + 1] = P.txt("IGUI_DazedPower_SteamRaising", math.floor(heat / M.STEAM_READY * 100))
            elseif (d.steamWatts or 0) > 0 then
                bits[#bits + 1] = P.txt("IGUI_DazedPower_SteamMaking", math.floor(d.steamWatts + 0.5))
            else bits[#bits + 1] = getText("IGUI_DazedPower_SteamIdle") end
        else
            bits[#bits + 1] = getText(heat > 0.3 and "IGUI_DazedPower_SteamCooling" or "IGUI_DazedPower_SteamCold")
        end
        if d.dry then bits[#bits + 1] = getText("IGUI_DazedPower_SteamDry") end
        bits[#bits + 1] = P.txt("IGUI_DazedPower_SteamFuel",
                                string.format("%.1f", (d.fuel or 0) / M.steamFullBurn(info.tier)))
        bits[#bits + 1] = P.txt("IGUI_DazedPower_SteamWater", math.floor((d.water or 0) + 0.5),
                                M.steamSpec(info.tier).tank)
    elseif info.kind == "propane" or info.kind == "petrol" then
        d.kind = d.kind or info.kind
        local spec = M.propaneSpec(info.tier, info.kind)
        if d.running then
            bits[#bits + 1] = P.txt("IGUI_DazedPower_GenRunningW", math.floor((d.genWatts or 0) + 0.5))
            if d.indoors then bits[#bits + 1] = getText("IGUI_DazedPower_GenFumes") end
            if d.leaking then bits[#bits + 1] = getText("IGUI_DazedPower_GenLeaking") end
        elseif d.noFuel and M.propaneFuel(d) <= 0 then
            bits[#bits + 1] = getText(info.kind == "petrol" and "IGUI_DazedPower_GenNoFuelPetrol" or "IGUI_DazedPower_GasNoFuel")
        elseif d.coldFail then
            bits[#bits + 1] = getText("IGUI_DazedPower_GenColdFail")
        elseif d.mode == "auto" and spec.auto then
            bits[#bits + 1] = P.txt("IGUI_DazedPower_GenAutoWaiting", d.startPct or M.PROPANE_START_SOC)
        else
            bits[#bits + 1] = getText("IGUI_DazedPower_GasOff")
        end
        bits[#bits + 1] = P.txt(info.kind == "petrol" and "IGUI_DazedPower_GenFuelL" or "IGUI_DazedPower_GenFuelKg",
                                string.format("%.1f", M.propaneFuel(d)))
    end
    bits[#bits + 1] = P.txt("IGUI_DazedPower_ConditionPct", math.floor(d.condition or 100))
    return table.concat(bits, "   ")
end

---------------------------------------------------------------- the rows

local ICON = nil          -- Dazed Power's own C.icon, captured below

local function addRepair(menu, wo, target, playerObj, d)
    if (d.condition or 100) >= 100 then return end
    local scrap, screws = findRepairParts(playerObj)
    local opt = ICON(menu:addOption(getText("ContextMenu_DazedPower_RepairMachine"), wo, DazedPower.More.onRepair,
                                    target, playerObj, scrap, screws), menu, "repair")
    if not (scrap and screws) then opt.notAvailable = true; opt.toolTip = tip("Tooltip_DazedPower_NeedParts")
    elseif not hasScrewdriver(playerObj) then opt.notAvailable = true; opt.toolTip = tip("Tooltip_DazedPower_NeedScrewdriver") end
end

local function pedalRows(menu, wo, target, playerObj, d)
    -- Percent, through DPM_Stats (Build 42.13+ has no stats:getFatigue();
    -- calling it was the "tried to call nil in pedalRows" menu error).
    local fatigue = DazedPower.More.Stats.fatiguePct(playerObj) or 0
    local opt = ICON(menu:addOption(getText("ContextMenu_DazedPower_Pedal"), wo, DazedPower.More.onPedal,
                                    target, playerObj), menu, "switchOn")
    if fatigue >= M.PEDAL_TOO_TIRED_PCT then opt.notAvailable = true; opt.toolTip = tip("Tooltip_DazedPower_TooTired") end
    local inv = playerObj:getInventory()
    for _, gear in ipairs(R.GEAR_ORDER) do
        if gear ~= (d.gear or "stock") then
            local wanted = R.GEAR_ITEM[gear]
            local item = inv:getFirstEvalRecurse(function(i) return i ~= nil and i:getFullType() == wanted end)
            if item then
                ICON(menu:addOption(getText("ContextMenu_DazedPower_InstallGear_" .. gear), wo,
                                    DazedPower.More.onInstallGear, target, playerObj, item), menu, "repair")
            end
        end
    end
end

--  FEEDING THE FIREBOX. The player chooses what goes in: "Add fuel" opens
--  a submenu with one row per kind of fuel carried ("Log x3, 6.0 fire-h
--  each"), each offering one or all that fit, plus a quick "all the wood
--  that fits" at the top. That quick row takes ONLY wood and charcoal
--  (WOOD below): vanilla counts books, newspapers and clothes as fuel too,
--  and a one-click "fill it up" should never burn the jacket in the bag.
--  Those are still offered, by name, in their own rows.
--
--  An item goes in whole or not at all, so a row is greyed with the reason
--  when even one will not fit the room left.

local WOOD = FUEL_FALLBACK

local function fuelHours(it)
    return M.steamFuelHours(DazedPower.More.Actions.itemWeight(it), it:getFullType())
end

--- The items from `items` (best first) that fit in `room` fire-hours.
local function fitting(items, room)
    local out, used = {}, 0
    for _, it in ipairs(items) do
        local h = fuelHours(it)
        if h > 0 and used + h <= room + 0.001 then out[#out + 1] = it; used = used + h end
    end
    return out, used
end

local function fmtH(h) return string.format("%.1f", h) end

local function fuelRows(menu, wo, target, playerObj, room)
    local top = ICON(menu:addOption(getText("ContextMenu_DazedPower_FuelMenu"), wo, nil), menu, "cells")
    local all = collectRecurse(playerObj:getInventory(), isFuel)
    if room < 0.1 then
        top.notAvailable = true; top.toolTip = tip("Tooltip_DazedPower_SteamHopperFull"); return
    end
    if #all == 0 then
        top.notAvailable = true; top.toolTip = tip("Tooltip_DazedPower_SteamNoFuel"); return
    end
    local sub = ISContextMenu:getNew(menu)
    menu:addSubMenu(top, sub)

    -- Group by item type, best value first.
    local groups, order = {}, {}
    for _, it in ipairs(all) do
        local ft = it:getFullType()
        if fuelHours(it) > 0 then
            if not groups[ft] then
                groups[ft] = { items = {}, name = it:getDisplayName() or ft }
                order[#order + 1] = ft
            end
            table.insert(groups[ft].items, it)
        end
    end
    for _, g in pairs(groups) do
        table.sort(g.items, function(a, b) return fuelHours(a) > fuelHours(b) end)
        g.each = fuelHours(g.items[1])
    end
    table.sort(order, function(a, b)
        if groups[a].each ~= groups[b].each then return groups[a].each > groups[b].each end
        return a < b
    end)

    -- The quick row: wood and charcoal only, the biggest pieces first.
    local wood = {}
    for _, ft in ipairs(order) do
        if WOOD[ft] then for _, it in ipairs(groups[ft].items) do wood[#wood + 1] = it end end
    end
    table.sort(wood, function(a, b) return fuelHours(a) > fuelHours(b) end)
    local woodFits, woodH = fitting(wood, room)
    local quick = sub:addOption(P.txt("ContextMenu_DazedPower_FuelAllWood", #woodFits, fmtH(woodH)), wo,
                                DazedPower.More.onSteamFuel, target, playerObj, woodFits)
    if #woodFits == 0 then
        quick.notAvailable = true
        quick.toolTip = tip(#wood == 0 and "Tooltip_DazedPower_FuelNoWood" or "Tooltip_DazedPower_FuelWoodTooBig")
    end

    -- One row per kind carried.
    for _, ft in ipairs(order) do
        local g = groups[ft]
        local label = P.txt("ContextMenu_DazedPower_FuelType", g.name, #g.items, fmtH(g.each))
        local fits = fitting(g.items, room)
        if #fits == 0 then
            local opt = sub:addOption(label, wo, nil)
            opt.notAvailable = true
            opt.toolTip = C.tip(P.txt("Tooltip_DazedPower_FuelTooBig", fmtH(room), fmtH(g.each)))
        elseif #g.items == 1 then
            sub:addOption(label, wo, DazedPower.More.onSteamFuel, target, playerObj, { g.items[1] })
        else
            local opt = sub:addOption(label, wo, nil)
            local kind = ISContextMenu:getNew(sub)
            sub:addSubMenu(opt, kind)
            kind:addOption(getText("ContextMenu_DazedPower_FuelOne"), wo, DazedPower.More.onSteamFuel,
                           target, playerObj, { fits[1] })
            local many = kind:addOption(P.txt("ContextMenu_DazedPower_FuelAllType", #fits), wo,
                                        DazedPower.More.onSteamFuel, target, playerObj, fits)
            if #fits < 2 then
                many.notAvailable = true
                many.toolTip = C.tip(P.txt("Tooltip_DazedPower_FuelTooBig", fmtH(room - g.each), fmtH(g.each)))
            end
        end
    end
end

local function steamRows(menu, wo, target, playerObj, d, info)
    local spec = M.steamSpec(info.tier)
    local inv = playerObj:getInventory()
    local function grey(opt, key) opt.notAvailable = true; opt.toolTip = tip(key) end

    fuelRows(menu, wo, target, playerObj, spec.hopper - (d.fuel or 0))

    local jugs = collectRecurse(inv, isWater)
    opt = ICON(menu:addOption(getText("ContextMenu_DazedPower_SteamWater"), wo,
                              DazedPower.More.onSteamWater, target, playerObj, jugs), menu, "clean")
    if spec.tank - (d.water or 0) < 0.5 then grey(opt, "Tooltip_DazedPower_SteamTankFull")
    elseif #jugs == 0 then grey(opt, "Tooltip_DazedPower_SteamNoWater") end

    if d.lit then
        ICON(menu:addOption(getText("ContextMenu_DazedPower_SteamDamp"), wo, DazedPower.More.onSteamFire,
                            target, playerObj, false, nil), menu, "switchOff")
    else
        local starter = inv:getFirstEvalRecurse(isStarter)
        opt = ICON(menu:addOption(getText("ContextMenu_DazedPower_SteamLight"), wo, DazedPower.More.onSteamFire,
                                  target, playerObj, true, starter), menu, "switchOn")
        local sq = target:getSquare()
        if (d.condition or 100) <= 0 then grey(opt, "Tooltip_DazedPower_SteamWrecked")
        elseif (d.fuel or 0) <= 0 then grey(opt, "Tooltip_DazedPower_SteamNeedFuel")
        elseif (d.water or 0) <= 0 then grey(opt, "Tooltip_DazedPower_SteamEmpty")
        elseif sq and sq.isOutside and not sq:isOutside() then grey(opt, "Tooltip_DazedPower_SteamIndoors")
        elseif not starter then grey(opt, "Tooltip_DazedPower_SteamNeedStarter") end
    end
end

------------------------------------------------------- the wind instruments

--  Both read the wind LIVE, here on the player's own machine, through the
--  same DPM_Env reading the windmills use (the weather is the same on every
--  client and the server). Their sprites are set by the server
--  (DPM_Instruments); the vane's record arrives in its ModData.

local function note(menu, text)
    local line = menu:addOption(text, nil, nil)
    line.notAvailable = true
    return line
end

local function pct(x) return math.floor((x or 0) * 100 + 0.5) end

local function sockRows(menu, target)
    local sq = target:getSquare()
    if not (sq and DazedPower.More.Env.isOutside(sq)) then
        note(menu, getText("IGUI_DazedPower_Sheltered"))
        return
    end
    local kph, from = DazedPower.More.Env.wind()
    if not kph then return end
    local z = sq:getZ()
    local atSock = M.sockWind(kph, z)
    local force, lo, hi = M.beaufort(kph)
    local name = getText("IGUI_DazedPower_Beaufort" .. force)
    if M.sockState(atSock) == "limp" or not from then
        note(menu, P.txt("IGUI_DazedPower_SockLimp", name))
    elseif hi then
        note(menu, P.txt("IGUI_DazedPower_SockWind", name, lo, hi, (DazedPower.More.Env.sectorOf(from))))
    else
        note(menu, P.txt("IGUI_DazedPower_SockWindTop", name, lo, (DazedPower.More.Env.sectorOf(from))))
    end
    -- What that wind would do to a windmill standing here: the grades'
    -- cut-in speeds are ordered (the workshop turbine starts first), and so
    -- are their safe speeds (the makeshift one is hurt first).
    local turns = M.wouldTurn(kph, z)
    local key = "IGUI_DazedPower_SockTurnsNone"
    if turns.makeshift then key = "IGUI_DazedPower_SockTurnsAll"
    elseif turns.salvaged then key = "IGUI_DazedPower_SockTurnsSalvaged"
    elseif turns.workshop then key = "IGUI_DazedPower_SockTurnsWorkshop" end
    note(menu, getText(key))
    local ms = kph / 3.6
    if M.hubWind(ms, "salvaged", z) > M.windSpec("salvaged").safe then
        note(menu, getText("IGUI_DazedPower_SockStormSalvaged"))
    elseif M.hubWind(ms, "makeshift", z) > M.windSpec("makeshift").safe then
        note(menu, getText("IGUI_DazedPower_SockStormMakeshift"))
    end
end

local function vaneRows(menu, target, d)
    local sq = target:getSquare()
    if not (sq and DazedPower.More.Env.isOutside(sq)) then
        note(menu, getText("IGUI_DazedPower_Sheltered"))
    else
        local kph, from = DazedPower.More.Env.wind()
        if kph and from and kph >= M.VANE_CALM_KPH then
            note(menu, P.txt("IGUI_DazedPower_VaneNow", (DazedPower.More.Env.sectorOf(from))))
        else
            note(menu, getText("IGUI_DazedPower_VaneCalmNow"))
        end
    end

    local s = M.vaneSummary(d)
    local hours = s and s.hours or 0
    if hours < M.VANE_MIN_HOURS then
        note(menu, P.txt("IGUI_DazedPower_VaneLearning", math.floor(hours), M.VANE_MIN_HOURS))
        return
    end
    note(menu, P.txt("IGUI_DazedPower_VaneRecord", string.format("%.1f", hours / 24)))
    if s.first then
        note(menu, P.txt("IGUI_DazedPower_VaneMostly", s.first, pct(s.firstShare)))
        if s.second then note(menu, P.txt("IGUI_DazedPower_VaneThen", s.second, pct(s.secondShare))) end
    end
    note(menu, P.txt("IGUI_DazedPower_VaneCalm", pct(s.calm), math.floor(s.avgKph + 0.5)))
    if s.strongest then note(menu, P.txt("IGUI_DazedPower_VaneStrongest", s.strongest)) end
    if s.facing then note(menu, P.txt("IGUI_DazedPower_VaneFace", s.facing, pct(s.facingKeeps))) end
end

------------------------------------------------------- the propane generator

local function isTank(it) return it ~= nil and R.TANK_TYPES[it:getFullType()] == true end

local function tanksCarried(playerObj)
    local out = collectRecurse(playerObj:getInventory(), isTank)
    table.sort(out, function(a, b) return DazedPower.More.Actions.tankFill(a) > DazedPower.More.Actions.tankFill(b) end)
    return out
end

local function pctOf(f) return math.floor((f or 0) * 100 + 0.5) end

local function petrolCans(playerObj)
    local out = collectRecurse(playerObj:getInventory(), function(it)
        local fc, amount = DazedPower.More.Actions.petrolOf(it)
        return fc ~= nil and amount > 0.001
    end)
    return out
end

local function propaneRows(menu, wo, target, playerObj, d, info)
    d.kind = d.kind or info.kind
    local petrol = info.kind == "petrol"
    local spec = M.propaneSpec(info.tier, info.kind)
    local function grey(opt, key) opt.notAvailable = true; opt.toolTip = tip(key) end
    local fuel = M.propaneFuel(d)

    -- The switch: whichever of Start / Auto / Switch off is not what it is set to.
    if (d.mode or "off") ~= "on" then
        local opt = ICON(menu:addOption(getText(spec.auto and "ContextMenu_DazedPower_GenStart"
                                                 or "ContextMenu_DazedPower_GenPullStart"), wo,
                                        DazedPower.More.onPropaneSwitch, target, playerObj, "on"),
                         menu, "switchOn")
        if (d.condition or 100) <= 0 then grey(opt, "Tooltip_DazedPower_GenWrecked")
        elseif fuel <= 0 then grey(opt, petrol and "Tooltip_DazedPower_PetrolNoFuel" or "Tooltip_DazedPower_GenNoFuel") end
    end
    if spec.auto and d.mode ~= "auto" then
        local opt = ICON(menu:addOption(P.txt("ContextMenu_DazedPower_GenAuto", d.startPct or M.PROPANE_START_SOC), wo,
                                        DazedPower.More.onPropaneSwitch, target, playerObj, "auto"),
                         menu, "switchOn")
        if (d.condition or 100) <= 0 then grey(opt, "Tooltip_DazedPower_GenWrecked") end
    end
    if (d.mode or "off") ~= "off" then
        ICON(menu:addOption(getText("ContextMenu_DazedPower_GenOff"), wo, DazedPower.More.onPropaneSwitch,
                            target, playerObj, "off"), menu, "switchOff")
    end
    -- Its auto start and stop levels are the controller's, set on the monitor's GEN page (DP_GenPanel).

    -- The ports: unhook what is on one, or hook a carried tank up to a free one.
    local tanks = tanksCarried(playerObj)
    for port = 1, spec.ports do
        local t = d["t" .. port .. "Type"]
        local key = (spec.ports > 1) and "Two" or ""
        if t then
            ICON(menu:addOption(P.txt("ContextMenu_DazedPower_GenUnhook" .. key, pctOf(d["t" .. port .. "Fill"]), port), wo,
                                DazedPower.More.onPropaneUnhook, target, playerObj, port), menu, "cells")
        else
            local top = ICON(menu:addOption(P.txt("ContextMenu_DazedPower_GenHook" .. key, port), wo, nil), menu, "cells")
            if #tanks == 0 then
                grey(top, "Tooltip_DazedPower_GenNoTank")
            else
                local sub = ISContextMenu:getNew(menu)
                menu:addSubMenu(top, sub)
                for _, tk in ipairs(tanks) do
                    sub:addOption(P.txt("ContextMenu_DazedPower_GenTank", tk:getDisplayName() or "?", pctOf(DazedPower.More.Actions.tankFill(tk))),
                                  wo, DazedPower.More.onPropaneHook, target, playerObj, tk, port)
                end
            end
        end
    end

    -- The reservoir, topped up from a carried tank (propane) or can (petrol).
    local room = spec.reservoir - (d.lpg or 0)
    if petrol then
        local cans = petrolCans(playerObj)
        local top = ICON(menu:addOption(P.txt("ContextMenu_DazedPower_PetrolFill",
                                              string.format("%.1f", d.lpg or 0), spec.reservoir), wo, nil),
                         menu, "clean")
        if room < 0.05 then grey(top, "Tooltip_DazedPower_GenReservoirFull")
        elseif #cans == 0 then grey(top, "Tooltip_DazedPower_PetrolNoCan")
        else
            local sub = ISContextMenu:getNew(menu)
            menu:addSubMenu(top, sub)
            for _, can in ipairs(cans) do
                local _, amount = DazedPower.More.Actions.petrolOf(can)
                sub:addOption(P.txt("ContextMenu_DazedPower_PetrolCan", can:getName() or can:getDisplayName() or "?",
                                    string.format("%.1f", amount or 0)),
                              wo, DazedPower.More.onPetrolFill, target, playerObj, can)
            end
        end
        return
    end
    local top = ICON(menu:addOption(P.txt("ContextMenu_DazedPower_GenFill",
                                          string.format("%.1f", d.lpg or 0), spec.reservoir), wo, nil),
                     menu, "clean")
    if room < 0.05 then grey(top, "Tooltip_DazedPower_GenReservoirFull")
    elseif #tanks == 0 then grey(top, "Tooltip_DazedPower_GenNoTank")
    else
        local sub = ISContextMenu:getNew(menu)
        menu:addSubMenu(top, sub)
        for _, tk in ipairs(tanks) do
            local opt = sub:addOption(P.txt("ContextMenu_DazedPower_GenTank", tk:getDisplayName() or "?", pctOf(DazedPower.More.Actions.tankFill(tk))),
                                      wo, DazedPower.More.onPropaneFill, target, playerObj, tk)
            if DazedPower.More.Actions.tankFill(tk) <= 0 then grey(opt, "Tooltip_DazedPower_GenTankEmpty") end
        end
    end
end

---------------------------------------------------------------- the amplifier

--- Install (needs an amplifier carried and a screwdriver) or remove, on any
--  generating part. Shown for every kind but the instruments.
local function ampRows(menu, wo, target, playerObj, d)
    if d.amp then
        ICON(menu:addOption(getText("ContextMenu_DazedPower_AmpRemove"), wo, DazedPower.More.onAmpRemove,
                            target, playerObj), menu, "repair")
        return
    end
    local carried = collectRecurse(playerObj:getInventory(),
        function(it) return it:getFullType() == R.AMP_ITEM end)
    local opt = ICON(menu:addOption(getText("ContextMenu_DazedPower_AmpInstall"), wo, DazedPower.More.onAmpInstall,
                                    target, playerObj, carried[1]), menu, "repair")
    opt.toolTip = tip("Tooltip_DazedPower_AmpWhat")
    if #carried == 0 then opt.notAvailable = true; opt.toolTip = tip("Tooltip_DazedPower_AmpNone")
    elseif not hasScrewdriver(playerObj) then opt.notAvailable = true; opt.toolTip = tip("Tooltip_DazedPower_NeedScrewdriver") end
end

--- Our rows for one part, into Dazed Power's submenu.
local function addRows(menu, wo, target, playerObj)
    local info = R.describe(target)
    if not info then
        -- Dazed Power's own solar array takes an amplifier too; nothing else of its.
        local theirs = P.describe(target)
        if R.canAmplify(theirs) then ampRows(menu, wo, target, playerObj, P.data(target)) end
        return
    end
    local d = P.data(target)
    if info.kind == "windsock" then return sockRows(menu, target) end
    if info.kind == "vane" then return vaneRows(menu, target, d) end
    local line = menu:addOption(status(target, info), nil, nil)
    line.notAvailable = true
    if info.kind == "pedal" then pedalRows(menu, wo, target, playerObj, d)
    elseif info.kind == "steam" then steamRows(menu, wo, target, playerObj, d, info)
    elseif info.kind == "propane" or info.kind == "petrol" then propaneRows(menu, wo, target, playerObj, d, info)
    elseif info.kind == "windmill" and not M.windSpec(info.tier).tracks then
        -- no tail fin: the rotor stays where it is turned
        local top = menu:addOption(getText("ContextMenu_DazedPower_TurnRotor"), wo, nil)
        local sub = ISContextMenu:getNew(menu)
        menu:addSubMenu(top, sub)
        for _, f in ipairs(R.FACINGS) do
            local opt = sub:addOption(getText("IGUI_DazedPower_Facing_" .. f), wo, function(_, o, pl, face)
                if luautils.walkAdj(pl, o:getSquare()) then ISTimedActionQueue.add(DPM_TurnRotor:new(pl, o, face)) end
            end, target, playerObj, f)
            if f == info.facing then opt.notAvailable = true end
        end
    end
    addRepair(menu, wo, target, playerObj, d)
    if R.canAmplify(info) then ampRows(menu, wo, target, playerObj, d) end
end

------------------------------------------------------------ the handlers

DazedPower.More = DazedPower.More or {}
local H = DazedPower.More

function H.onPedal(wo, object, playerObj)
    if not C.approach(playerObj, object) then return end
    ISTimedActionQueue.add(DPM_Pedal:new(playerObj, object))
end
function H.onInstallGear(wo, object, playerObj, item)
    if not C.approach(playerObj, object) then return end
    ISTimedActionQueue.add(DPM_InstallGear:new(playerObj, object, item))
end
function H.onRepair(wo, object, playerObj, scrap, screws)
    if not (object and scrap and screws) then return end
    if not C.approach(playerObj, object) then return end
    ISTimedActionQueue.add(DPM_Repair:new(playerObj, object, scrap, screws))
end
function H.onAmpInstall(wo, object, playerObj, amp)
    if not (amp and C.approach(playerObj, object)) then return end
    ISTimedActionQueue.add(DPM_AmpInstall:new(playerObj, object, amp))
end
function H.onAmpRemove(wo, object, playerObj)
    if not C.approach(playerObj, object) then return end
    ISTimedActionQueue.add(DPM_AmpRemove:new(playerObj, object))
end
function H.onSteamFuel(wo, object, playerObj, items)
    if not items or #items == 0 then return end
    if not C.approach(playerObj, object) then return end
    for _, it in ipairs(items) do ISTimedActionQueue.add(DPM_SteamFuel:new(playerObj, object, it)) end
end
function H.onSteamWater(wo, object, playerObj, jugs)
    if not jugs or #jugs == 0 then return end
    if not C.approach(playerObj, object) then return end
    local info = R.describe(object)
    local room = M.steamSpec(info and info.tier).tank - (P.data(object).water or 0)
    for _, jug in ipairs(jugs) do
        if room <= 0.01 then break end
        local litres = math.min(waterIn(jug), room)
        room = room - litres
        ISTimedActionQueue.add(DPM_SteamWater:new(playerObj, object, jug, litres))
    end
end
function H.onPropaneSwitch(wo, object, playerObj, mode)
    if not C.approach(playerObj, object) then return end
    ISTimedActionQueue.add(DPM_PropaneSwitch:new(playerObj, object, mode))
end
function H.onPropaneLevel(wo, object, playerObj, pct)
    if not C.approach(playerObj, object) then return end
    ISTimedActionQueue.add(DPM_PropaneLevel:new(playerObj, object, pct))
end
function H.onPropaneHook(wo, object, playerObj, tank, port)
    if not (tank and C.approach(playerObj, object)) then return end
    ISTimedActionQueue.add(DPM_PropaneHook:new(playerObj, object, tank, port))
end
function H.onPropaneUnhook(wo, object, playerObj, port)
    if not C.approach(playerObj, object) then return end
    ISTimedActionQueue.add(DPM_PropaneUnhook:new(playerObj, object, port))
end
function H.onPropaneFill(wo, object, playerObj, tank)
    if not (tank and C.approach(playerObj, object)) then return end
    ISTimedActionQueue.add(DPM_PropaneFill:new(playerObj, object, tank))
end
function H.onPetrolFill(wo, object, playerObj, can)
    if not (can and C.approach(playerObj, object)) then return end
    ISTimedActionQueue.add(DPM_PetrolFill:new(playerObj, object, can))
end
function H.onSteamFire(wo, object, playerObj, light, starter)
    if not C.approach(playerObj, object) then return end
    ISTimedActionQueue.add(DPM_SteamFire:new(playerObj, object, light, starter))
end

----------------------------------------------------------------- the hook

if not H.menuWrapped then
    H.menuWrapped = true
    ICON = C.icon
    function C.icon(option, menu, row)
        local out = ICON(option, menu, row)
        if row == "info" and type(option) == "table" and menu and menu.addOption then
            local target, playerObj = option.param1, option.param2
            if target and target.getSprite and playerObj and playerObj.getInventory
                    and (R.describe(target) or R.canAmplify(P.describe(target))) then
                local ok, err = pcall(addRows, menu, option.target, target, playerObj)
                if not ok then print("DazedPower: menu rows failed: " .. tostring(err)) end
            end
        end
        return out
    end

    -- The cable rows. Dazed Power offers "wire from here" on every part it
    -- knows, because every one of ITS parts can be wired; our instruments
    -- cannot (DPM_Model.wireLegal), so they get no cable rows at all.
    if C.wireMenu then
        local wire0 = C.wireMenu
        function C.wireMenu(menu, worldobjects, target, playerObj, info)
            if info and R.INSTRUMENT[info.kind] then return end
            return wire0(menu, worldobjects, target, playerObj, info)
        end
    end
end
