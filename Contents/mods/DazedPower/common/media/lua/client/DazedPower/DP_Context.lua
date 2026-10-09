--[[ DazedPower -- the right-click menus.

     Note the safehouse trap: OnFillWorldObjectContextMenu is fired inside
     `if fetch.safehouseAllowInteract then` in ISWorldObjectContextMenu.lua,
     so a mod whose only entry point hangs off this event disappears entirely
     inside a safehouse the player may not interact with. That is correct
     behaviour here -- you should not be able to service someone else's
     array -- but it is worth knowing it is the engine's doing, not a bug.
]]

require "DazedPower/DP_Parts"
require "DazedPower/DP_GenPanel"
require "DazedPower/DP_Gauge"
require "DazedPower/DP_Actions"
require "DazedPower/DP_Almanac"
require "DazedPower/DP_Coverage"
require "DazedPower/DP_Buildings"
require "DazedPower/DP_Lamps"
require "DazedPower/DP_Admin"
require "DazedPower/DP_ApplianceMenu"
-- DP_Info requires this file back, so it cannot be required here.
-- It registers itself on DazedPower.Info and is reached through that. The
-- forecast window is reached the same way: DP_Forecast loads after this file
-- and a hard require here would be the first cycle in the tree.

DazedPower = DazedPower or {}
DazedPower.Context = DazedPower.Context or {}
local C = DazedPower.Context
local P = DazedPower.Parts
local M = DazedPower.Model

--- How many buildings a part wires. DP_Buildings is looked up when asked, not
--  held from file load, so a harness or a load order that brings this file in
--  without it reads "none" instead of failing the whole menu.
local function wiredCount(d)
    local Bd = DazedPower.Buildings
    return (Bd and Bd.decodeTargets) and #Bd.decodeTargets(d.bw) or 0
end

------------------------------------------------------------------ row icons

--- The Dazed Power menu's row icons (2026-09-26: line pictures coloured by
--  group). Tabler Icons (MIT, v3.48.0; the licence ships beside them), drawn
--  white at these sizes. Each row tints its icon
--  with its group's colour: ISContextMenu.renderOptionTextureOrColor draws
--  the texture multiplied by option.color and uses the colour for nothing
--  else. A row the player cannot use yet shows its icon grey.
C.ICON_DIR = "media/ui/DazedPower/Menu/"
C.ICON_SIZES = { 16, 20, 24, 32, 48 }
C.ICON_GROUP = {
    info  = { r = 133 / 255, g = 183 / 255, b = 235 / 255 },   -- Info, System monitor
    sky   = { r = 239 / 255, g = 159 / 255, b = 39 / 255 },    -- Dazed Power, Almanac, the sky
    reach = { r = 93 / 255, g = 202 / 255, b = 165 / 255 },    -- coverage and buildings
    power = { r = 151 / 255, g = 196 / 255, b = 89 / 255 },    -- switch on, batteries
    off   = { r = 226 / 255, g = 75 / 255, b = 74 / 255 },     -- switch off
    cable = { r = 240 / 255, g = 153 / 255, b = 123 / 255 },   -- cables
    care  = { r = 175 / 255, g = 169 / 255, b = 236 / 255 },   -- snow, cleaning, repair
    take  = { r = 180 / 255, g = 178 / 255, b = 169 / 255 },   -- Pick up
}
C.ICON_DIM = { r = 111 / 255, g = 110 / 255, b = 105 / 255 }

-- Every row's icon and group, in one place: { Tabler icon, group }.
C.ROW_ICONS = {
    dazedpower         = { "solar-panel", "sky" },
    info            = { "info-circle", "info" },
    monitor         = { "device-desktop-analytics", "info" },
    almanac         = { "book-2", "sky" },
    readSky         = { "cloud", "sky" },
    coverageShow    = { "radar-2", "reach" },
    coverageHide    = { "radar-off", "reach" },
    wireBuilding    = { "home-bolt", "reach" },
    chooseBuildings = { "building-community", "reach" },
    unwireBuildings = { "home-off", "reach" },
    switchOn        = { "power", "power" },
    reset           = { "refresh", "power" },
    cells           = { "battery-automotive", "power" },
    equalise        = { "battery-charging-2", "power" },
    equaliseStop    = { "battery-off", "power" },
    switchOff       = { "power", "off" },
    wireFrom        = { "plug", "cable" },
    wireTo          = { "plug-connected", "cable" },
    wireCancel      = { "plug-x", "cable" },
    wireCut         = { "scissors", "cable" },
    clearSnow       = { "snowflake", "care" },
    repair          = { "tool", "care" },
    clean           = { "droplet", "care" },
    takeDown        = { "hand-grab", "take" },
    admin           = { "tool", "info" },
    adminInspect    = { "info-circle", "info" },
    adminRepair     = { "tool", "care" },
    adminReset      = { "refresh", "power" },
    adminFill       = { "battery-charging-2", "power" },
}

--- The drawn size for a menu: the smallest at least as tall as its icon
--  slot, which is the menu's font height (ISContextMenu:render: iconSize =
--  itemHgt - 12, and itemHgt = fontHgt + 12), so the game scales an icon down,
--  and only a little. Past the largest, the largest.
function C.iconSize(menu)
    local want = (menu and type(menu.fontHgt) == "number") and menu.fontHgt or 18
    for i = 1, #C.ICON_SIZES do
        if C.ICON_SIZES[i] >= want then return C.ICON_SIZES[i] end
    end
    return C.ICON_SIZES[#C.ICON_SIZES]
end

local iconTextures = {}

local function iconTexture(name, size)
    local path = C.ICON_DIR .. size .. "/" .. name .. ".png"
    local t = iconTextures[path]
    if t == nil then
        t = getTexture(path) or false
        iconTextures[path] = t
    end
    return t or nil
end

--- Give a menu row its icon: `row` a key of C.ROW_ICONS. Returns the row,
--  so it can wrap addOption. A picture the game cannot find leaves the row as
--  it was. The row keeps its key (ogRow), which is how a painted controller
--  tells its rows apart (paintScenery).
function C.icon(option, menu, row)
    local spec = C.ROW_ICONS[row]
    if type(option) ~= "table" or not spec then return option end
    option.ogRow = row
    local tex = iconTexture(spec[1], C.iconSize(menu))
    if not tex then return option end
    option.iconTexture = tex
    local c = C.ICON_GROUP[spec[2]]
    option.color = c and { r = c.r, g = c.g, b = c.b } or nil
    return option
end

--- Grey the icon of every row in `menu` the player cannot use yet. Run once
--  the menu is built: several rows are marked notAvailable after they are
--  added.
function C.dimUnavailable(menu)
    local opts = menu and menu.options
    if type(opts) ~= "table" then return end
    local d = C.ICON_DIM
    for _, o in ipairs(opts) do
        if o.notAvailable and o.iconTexture then
            o.color = { r = d.r, g = d.g, b = d.b }
        end
    end
end

--- Ask the authority to do something. On a multiplayer client that is a
--  packet; in single player the simulation is loaded in this process, so it is
--  a direct call. Same validation runs at the far end either way.
function C.send(playerObj, command, args)
    if isClient() then
        sendClientCommand(playerObj, "DazedPower", command, args)
    elseif DazedPower.System and DazedPower.System.onCommand then
        DazedPower.System.onCommand(command, playerObj, args)
    end
end

--- Walk to a square NEXT TO an object, and say whether that is possible.
--
--  ISWalkToTimedAction aimed at the object's OWN square looks right and is
--  wrong for half of what this mod places. A ground array carries solidtrans,
--  so the pathfinder can never arrive on its tile: the walk fails, the whole
--  queued action goes with it, and what the player sees is a progress bar that
--  flickers once and then nothing. It only happens when they are not already
--  standing next to the thing, which is why it survived until somebody tried
--  to wire a panel from across the yard. A battery bank is IsLow and walkable,
--  so banks worked and arrays did not.
--
--  luautils.walkAdj finds an adjacent free tile instead, returns true when the
--  player is already close enough, and returns false when there is genuinely
--  nowhere to stand. It also clears the action queue, so it has to run BEFORE
--  anything is queued rather than after.
function C.approach(playerObj, object)
    local sq = object and object:getSquare()
    if not sq then return false end
    if not luautils or not luautils.walkAdj then return true end
    return luautils.walkAdj(playerObj, sq, false) and true or false
end

local function reachable(playerObj, object)
    local sq = object and object:getSquare()
    if not sq then return false end
    return playerObj:getCurrentSquare()
        and math.abs(sq:getX() - playerObj:getX()) <= 2
        and math.abs(sq:getY() - playerObj:getY()) <= 2
        and sq:getZ() == playerObj:getZ()
end

-- ItemContainer.getAllTag takes an ItemTag, never a String, so the tag has to
-- come from the exposed ItemTag container rather than a literal. Matching the
-- tag rather than Base.CarBattery1/2/3 means a modded battery works too.
local function predicateCarBattery(item)
    return item ~= nil and item:hasTag(ItemTag.CAR_BATTERY)
end

--- Exported so the bank panel's slot predicate and this menu agree on what
--  counts as a car battery, rather than each carrying its own copy.
function C.isCarBattery(item)
    return predicateCarBattery(item)
end

local function predicateWater(item)
    return item:isWaterSource() and item:getCurrentUses() > 0
end

local function predicateScrap(item)
    return item ~= nil and item:getFullType() == "Base.ElectronicsScrap"
end

local function predicateScrews(item)
    return item ~= nil and item:getFullType() == "Base.Screws"
end

-- A petrol container by vanilla's own test (ISWorldObjectContextMenu.lua,
-- predicatePetrol): any fluid container holding petrol, a sip of it at least.
local function predicatePetrol(item)
    local fc = item and item:getFluidContainer()
    return fc ~= nil and fc:contains(Fluid.Petrol) and fc:getAmount() >= 0.099
end

--- A screwdriver, by tag, so a modded one works.
--  Shared with the pickup gate: see P.hasScrewdriver for why this is one
--  function and not two.
local function hasScrewdriver(playerObj)
    return P.hasScrewdriver(playerObj)
end

local function findRepairParts(playerObj)
    local inv = playerObj:getInventory()
    return inv:getFirstEvalRecurse(predicateScrap),
           inv:getFirstEvalRecurse(predicateScrews)
end

local function findRagAndWater(playerObj)
    local inv = playerObj:getInventory()
    local rag = inv:getItemFromType("RippedSheets", true, true)
    if not rag then rag = inv:getItemFromType("DishCloth", true, true) end
    local water = inv:getFirstEvalRecurse(predicateWater)
    return rag, water
end

--- The system key this part can honestly claim, or nil.
--
--  `d.sys` is a server-maintained cache, and a cache can outlive its truth:
--  before 2026-08-28 picking a controller up never cleared it from the parts
--  it owned, and a member whose chunk was unloaded at that moment still
--  misses the sweep today. A part carrying a stale sys was locked out of the
--  whole wiring menu -- no "Run cable from here" because it looked wired, no
--  cut rows because its controller resolved to nothing. So the menu checks
--  the claim before honouring it: if the controller's square is LOADED and
--  no controller stands there, the claim is dead and the part is loose. Only
--  ever read here; the authoritative clear stays on the server.
local function liveSys(d)
    local sys = d.sys
    if not sys then return nil end
    local cx, cy, cz = M.parseNodeKey(sys)
    if not cx then return nil end
    local sq = getSquare(cx, cy, cz)
    if sq and not P.objectAt(cx, cy, cz, "controller") then return nil end
    return sys
end

--- Grey a row with a refusal key; nil leaves it usable. A row that opens a
--  submenu of our own (ogSub) greys that submenu's rows too: vanilla's menu
--  still opens the submenu of a greyed row.
local function greyed(opt, key)
    if key and opt then
        opt.notAvailable = true
        opt.toolTip = C.tip(getText(key))
        local sub = opt.ogSub
        if type(sub) == "table" and type(sub.options) == "table" then
            for _, o in ipairs(sub.options) do greyed(o, key) end
        end
    end
    return opt
end

--- Why this player may not use `obj`'s controls, or nil: since "Lock
--  them in 3.0.0" the rig's own: a controller's Switch on / Switch off,
--  Reset the breaker and Equalise, Run cable from here, Connect and Cut a
--  cable on any part (each part whose wiring changes), and Wire up the
--  building, Choose buildings and Unwire. DP_Place's G.useRefusal, the
--  question the authority asks again first (G.mayUse). Nil where DP_Place is not loaded.
local function lockOf(playerObj, obj)
    local G = DazedPower.Place
    if not (G and G.useRefusal and obj and playerObj) then return nil end
    return G.useRefusal(playerObj, P.try(obj, "getSquare"), obj)
end
C.lockOf = lockOf

--- A press that reached its handler although the row was greyed (the
--  monitor's knob, a menu built before the lock changed): the first of
--  `...` whose lock refuses this player puts the reason above him in the
--  warning colour, and the caller sends nothing. True when refused.
local function refusedPress(playerObj, ...)
    for i = 1, select("#", ...) do
        local why = lockOf(playerObj, (select(i, ...)))
        if why then
            P.haloNote(playerObj, getText(why), true)
            return true
        end
    end
    return false
end
C.refusedPress = refusedPress

-- The rows a controller painted with the Brush Tool keeps usable: the
-- almanac's two, which are the player's own, and Pick up.
local SCENERY_KEEP = { almanac = true, readSky = true, takeDown = true }

--- A controller tile the Brush Tool painted (P.isPainted) is scenery (Can,
--  2026-09-29: "Say it's scenery"): every row of ours that cannot work on it
--  stays on the menu, greyed with why, never hidden.
local function paintScenery(menu)
    local opts = menu and menu.options
    if type(opts) ~= "table" then return end
    for _, o in ipairs(opts) do
        if o.ogRow and not SCENERY_KEEP[o.ogRow] then
            greyed(o, "Tooltip_DazedPower_Painted")
        end
    end
end

--- One line of status for the tooltip, so the common case needs no window.
local function statusText(obj, part)
    if part == "gauge" and DazedPower.Gauge then return DazedPower.Gauge.status(obj) end
    local d = P.data(obj)
    -- Membership comes first, because an unwired part makes nothing and every
    -- other number on the line is beside the point until it is connected.
    local loose = (part ~= "controller") and not liveSys(d)
    if part == "array" then
        local bits = {}
        if loose then bits[#bits + 1] = getText("IGUI_DazedPower_NotWired") end
        -- Second only to being unwired: an array under a roof makes nothing
        -- whatever its snow, dust or condition say. DP_System's own test.
        local E, sq = DazedPower.Env, obj:getSquare()
        if E and E.isSunlit and sq and not E.isSunlit(sq) then
            bits[#bits + 1] = getText("IGUI_DazedPower_UnderRoof")
        end
        if (d.snow or 0) > 0.02 then
            bits[#bits + 1] = P.txt("IGUI_DazedPower_SnowPct",
                                      math.floor((d.snow or 0) * 100))
        end
        if (d.soiling or 0) > 0.05 then
            bits[#bits + 1] = P.txt("IGUI_DazedPower_DirtPct",
                                      math.floor((d.soiling or 0) * 100))
        end
        bits[#bits + 1] = P.txt("IGUI_DazedPower_ConditionPct",
                                  math.floor(d.condition or 100))
        return table.concat(bits, "   ")
    elseif part == "bank" then
        local info = P.describe(obj)
        -- The same capacity the simulation uses: BankScale in, the day's real
        -- temperature in, and the ratio clamped. Against the old unscaled
        -- 20 C figure a cold morning read over 100% charged.
        local scale = P.bankScale()
        local tempC = (DazedPower.Env and DazedPower.Env.read().temperature) or 20
        tempC = (DazedPower.Env and DazedPower.Env.tempAt(obj, tempC)) or tempC
        local cap = M.bankCapacity({ tier = info and info.tier,
                                     cellSum = P.cellSum(d),
                                     scale = scale }, tempC)
        local soc = cap > 0 and M.clamp((d.charge or 0) / cap, 0, 1) or 0
        local line = P.txt("IGUI_DazedPower_BankStatus", d.cells or 0,
                           P.cellCap(obj), math.floor(soc * 100))
        if loose then
            return getText("IGUI_DazedPower_NotWired") .. "   " .. line
        end
        return line
    elseif part == "transformer" then
        -- Unwired first, as for every part: a transformer lights nothing
        -- until a power line joins it to a controller.
        if loose then return getText("IGUI_DazedPower_NotWired") end
        local info = P.describe(obj)
        local bits = { getText((info and info.state == "on") and "IGUI_DazedPower_GridOn"
                                                             or "IGUI_DazedPower_GridOff") }
        local n = wiredCount(d)
        if n > 0 then bits[#bits + 1] = P.txt("IGUI_DazedPower_BuildingsWired", n) end
        return table.concat(bits, "   ")
    end
    return nil
end

--- Strip vanilla's generator submenu when the generator it was built for is ours.
--
--  The Java menu keys purely on `instanceof IsoGenerator`, so the controller
--  inherits Add Fuel (which has no skill gate and writes the state-of-charge
--  gauge), Connect, Turn On/Off, Fix, Take and a
--  petrol readout. None of it belongs on a solar controller and Dazed Power's own
--  submenu already covers everything that does.
--
--  Keyed on the generator the Java menu was actually BUILT for. The fetch
--  keeps exactly one (ISWorldObjectContextMenuLogic.java:326-327), and it
--  walks every object on the clicked square, not only the clicked object: a
--  right-click on the floor or wall a controller stands on, and the joypad
--  prompt, which hands the floor over first, built the full submenu with
--  Take in it while this file only looked at `worldobjects` and found no
--  part of ours there. When the fetched generator is a real one, its menu
--  stays, controller beside it or not.
local function stripGeneratorMenu(context, test)
    if test or not context or not context.removeOptionByName then return end
    local fv = ISWorldObjectContextMenu and ISWorldObjectContextMenu.fetchVars
    local g = fv and fv.generator
    if g and P.partOf(g) == "controller" then
        context:removeOptionByName(getText("ContextMenu_Generator"))
    end
end

--- Strip vanilla's Remove Battery when the light it was built for is one of
--  the solar lamps, whose battery is built in. Keyed on the light switch the
--  menu was actually BUILT for, as stripGeneratorMenu is on the generator:
--  vanilla fetches every object on the clicked square, so a right-click on
--  the ground beside the stake or pole, and the joypad, built the row while
--  `worldobjects` held no lamp (review, 2026-09-26). DP_Lamps refuses the
--  action itself as well.
local function stripLampBattery(context, test)
    if test or not context or not context.removeOptionByName then return end
    local fv = ISWorldObjectContextMenu and ISWorldObjectContextMenu.fetchVars
    local l = fv and fv.lightSwitch
    if l and P.partOf(l) == "lamp" then
        context:removeOptionByName(getText("ContextMenu_Remove_Battery"))
    end
end

--- A solar lamp's menu. The switch, the bulb and the light are vanilla's
--  own rows (Turn On / Turn Off, Remove Light Bulb): the lamp IS a vanilla
--  light. This adds one line saying how charged it is and what it will do.
--  Vanilla's Remove Battery goes in stripLampBattery, keyed on the light the
--  rows were built for: removed here by its label, it took the row of another
--  battery lamp vanilla had fetched instead (review, 2026-09-26). Returns the
--  submenu.
function C.lampMenu(context, worldobjects, target)
    local sub = C.icon(context:addOption(getText("ContextMenu_DazedPower"), worldobjects, nil),
                       context, "dazedpower")
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(sub, menu)
    local line = menu:addOption(DazedPower.Lamps.status(target), nil, nil)
    line.notAvailable = true
    return menu
end

function C.onFill(playerNum, context, worldobjects, test)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    stripGeneratorMenu(context, test)
    stripLampBattery(context, test)

    local target, part = nil, nil
    for _, o in ipairs(worldobjects) do
        local p = P.partOf(o)
        if p then target, part = o, p break end
    end
    -- A click on a side square of a 2x2 array is a click on the array: the master square has its state.
    if target then
        local master = P.master(target)
        if master and master ~= target then target = master end
    end
    if not target then return end
    if test then return true end

    if part == "lamp" then
        C.lampMenu(context, worldobjects, target)
        return true
    end

    local sub = C.icon(context:addOption(getText("ContextMenu_DazedPower"), worldobjects, nil),
                       context, "dazedpower")
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(sub, menu)

    local status = statusText(target, part)
    if status then
        local line = menu:addOption(status, nil, nil)
        line.notAvailable = true
    end

    C.icon(menu:addOption(getText("ContextMenu_DazedPower_Info"), worldobjects,
                          C.onInfo, target, playerObj), menu, "info")

    -- The almanac, on every part, once the sky can be read. The sidebar
    -- button is one route to the same window and can be switched off in the
    -- player's options; this row is the one that reads like the vanilla
    -- generator's own Info entry, which is what was asked for.
    if DazedPower.Almanac and DazedPower.Almanac.knows(playerObj)
            and DazedPower.Forecast and DazedPower.Forecast.open then
        C.icon(menu:addOption(getText("ContextMenu_DazedPower_Almanac"), worldobjects,
                              C.onAlmanac, playerObj), menu, "almanac")
        -- Taking a reading without the window: the window's button is mouse
        -- only, so this row is how a controller player reads the sky at all.
        local why = DazedPower.Almanac.blocked(playerObj)
        local read = C.icon(menu:addOption(getText("IGUI_DazedPower_ReadSky"), worldobjects,
                                           C.onReadSky, playerObj), menu, "readSky")
        if why then
            read.notAvailable = true
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip.description = getText(why)
            read.toolTip = tip
        end
    end

    if part == "controller" then
        C.icon(menu:addOption(getText("ContextMenu_DazedPower_Monitor"), worldobjects,
                              C.onMonitor, target, playerObj),
               menu, "monitor")
        C.coverageMenu(menu, target, playerObj)
        C.buildingMenu(menu, worldobjects, target, playerObj, part)
        local d = P.data(target)
        -- The switch is the controller's owner's group's (2026-09-29:
        -- "Lock them in 3.0.0"): greyed with the lock's reason for anyone
        -- else, never hidden, as DP_ResetBreaker's completion refuses it.
        local lock = lockOf(playerObj, target)
        local sw
        if d.trip then
            sw = C.icon(menu:addOption(getText("ContextMenu_DazedPower_Reset"), worldobjects,
                                       C.onBreaker, target, playerObj, true), menu, "reset")
        elseif d.online then
            sw = C.icon(menu:addOption(getText("ContextMenu_DazedPower_SwitchOff"), worldobjects,
                                       C.onBreaker, target, playerObj, false), menu, "switchOff")
        else
            sw = C.icon(menu:addOption(getText("ContextMenu_DazedPower_SwitchOn"), worldobjects,
                                       C.onBreaker, target, playerObj, true), menu, "switchOn")
        end
        greyed(sw, lock)

        C.priorityMenu(menu, worldobjects, target, playerObj, d, lock)

        -- Equalisation. Only offered when there is something it can actually
        -- fix, so it is not a permanent switch nobody understands: a sealed
        -- cabinet must never be equalised and a healthy bank has nothing to
        -- gain, which between them means the row appears exactly when it is
        -- the right thing to do.
        if d.canEqualise then
            local key = d.equalise and "ContextMenu_DazedPower_EqualiseStop"
                                    or "ContextMenu_DazedPower_Equalise"
            local opt = C.icon(menu:addOption(getText(key), worldobjects, C.onEqualise,
                                              target, playerObj, not d.equalise),
                               menu, d.equalise and "equaliseStop" or "equalise")
            -- The server refuses this command beyond arm's reach and says
            -- nothing; a row that works at 2 tiles and silently does not at 4
            -- reads as a broken switch. Grey it out where it will not work,
            -- and say so in its own words: it borrowed the cable's "Too far
            -- for one run of cable", and there is no cable here. The owner's
            -- lock is said first (2026-09-29: "Lock them in 3.0.0"):
            -- walking closer would not help with that one.
            if lock then
                greyed(opt, lock)
            elseif not reachable(playerObj, target) then
                opt.notAvailable = true
                opt.toolTip = C.tip(getText("Tooltip_DazedPower_EqualiseReach"))
            end
        end

        C.adminMenu(menu, worldobjects, target, playerObj)

    elseif part == "transformer" then
        -- A transformer in a system shows the system's coverage and wires
        -- buildings of its own; a loose one only offers its cable rows.
        if liveSys(P.data(target)) then
            C.coverageMenu(menu, target, playerObj)
            C.buildingMenu(menu, worldobjects, target, playerObj, part)
        end

    elseif part == "bench" then
        if DazedPower.ChargeMenu then DazedPower.ChargeMenu.benchMenu(menu, worldobjects, target, playerObj) end

    elseif part == "fence" and DazedPower.ApplianceMenu then
        DazedPower.ApplianceMenu.fenceMenu(menu, target)

    elseif part == "cooler" and DazedPower.ApplianceMenu then
        DazedPower.ApplianceMenu.coolerMenu(menu, target)

    elseif part == "heater" and DazedPower.ApplianceMenu then
        DazedPower.ApplianceMenu.heaterMenu(menu, worldobjects, target, playerObj)

    elseif part == "gauge" then
        C.icon(menu:addOption(getText("ContextMenu_DazedPower_ReadGauge"), worldobjects,
                              C.onGauge, target, playerObj), menu, "monitor")

    elseif part == "bank" then
        -- One row. The install and remove rows it replaces were two more code
        -- paths into the same mutation, and the panel does both with the cells
        -- visible instead of guessing which battery the player meant.
        C.icon(menu:addOption(getText("ContextMenu_DazedPower_Cells"), worldobjects,
                              C.onCells, target, playerObj), menu, "cells")

    elseif part == "array" then
        local d = P.data(target)
        if (d.snow or 0) > 0.01 then
            C.icon(menu:addOption(getText("ContextMenu_DazedPower_ClearSnow"), worldobjects,
                                  C.onClear, target, playerObj, "snow"), menu, "clearSnow")
        end
        -- Repair. Condition only ever fell before this: a frame left out in a
        -- wet autumn walked down to a quarter of its output with no way back.
        if (d.condition or 100) < 100 then
            local scrap, screws = findRepairParts(playerObj)
            local opt = C.icon(menu:addOption(getText("ContextMenu_DazedPower_Repair"),
                                              worldobjects, C.onRepair, target,
                                              playerObj, scrap, screws), menu, "repair")
            if not (scrap and screws) then
                opt.notAvailable = true
                opt.toolTip = C.tip(getText("Tooltip_DazedPower_NeedParts"))
            elseif not hasScrewdriver(playerObj) then
                opt.notAvailable = true
                opt.toolTip = C.tip(getText("Tooltip_DazedPower_NeedScrewdriver"))
            end
        end

        local rag, water = findRagAndWater(playerObj)
        local opt = C.icon(menu:addOption(getText("ContextMenu_DazedPower_Clean"),
                                          worldobjects, C.onClear, target, playerObj,
                                          "dirt", rag, water), menu, "clean")
        if (d.soiling or 0) <= 0.01 then
            opt.notAvailable = true
            opt.toolTip = C.tip(getText("Tooltip_DazedPower_AlreadyClean"))
        elseif not rag or not water then
            opt.notAvailable = true
            opt.toolTip = C.tip(getText("Tooltip_DazedPower_NeedRagWater"))
        end

    end

    -- Wiring is offered on every kind, because every kind is either a loose
    -- end, something to land a cable on, or both.
    C.wireMenu(menu, worldobjects, target, playerObj, P.describe(target))

    -- A controller tile painted with the Brush Tool: every row so far that
    -- would act on it is greyed "Painted with the Brush Tool", before Pick up,
    -- which works on it as on any part.
    if part == "controller" and P.isPainted(target) then paintScenery(menu) end

    -- Last row, because it is the one that ends the conversation.
    C.takeDownMenu(menu, worldobjects, target, playerObj)

    C.dimUnavailable(menu)
end

--- Take the part down, without having to see it.
--
--  A Workshop report, 2026-09-21: an enclosed battery cabinet put in a bad
--  spot "cannot be picked up removed or destroyed with a sledge hammer". That
--  is accurate, it is only that one part, and the mod's own permission gate is
--  not what blocks it.
--
--  The sealed cabinet is the ONE thing this mod places that carries `solid`
--  rather than `solidtrans` -- deliberately, as the price of the best storage
--  in the game (its tile properties). A solid object blocks line of sight to
--  its own square, and both vanilla ways of removing a placed object are
--  gated on seeing the square, independently and for different reasons:
--
--    * ISMoveableCursor:shouldAddObject returns false for anything that is
--      not a wall or a door on a square failing isCouldSee, so the cabinet
--      never enters the pick-up list and the cursor finds nothing there.
--    * ISDestroyCursor:isValid refuses on the same test, with an exception
--      only for walls and windows reached from the opposite square.
--
--  So a lone cabinet is unreachable from every angle, and the harder the
--  player tries the more it looks like a bug in this mod. The context menu is
--  built from the objects the click hit and asks nothing about vision, which
--  is why this row works where those two cannot.
--
--  It does not reimplement removal. It asks G.mayTake -- the same owner, tool
--  and switch-off rule the cursor asks -- and then queues the engine's own
--  pick-up action, so emptying a rack's batteries onto the floor, unplugging
--  the node, retiring a controller's system and building the item all happen
--  exactly as they do from the cursor, through the hooks already in DP_Place.
function C.takeDownMenu(menu, worldobjects, target, playerObj)
    if not ISMoveableSpriteProps or not ISMoveableSpriteProps.fromObject then
        return
    end
    local sq = target and target:getSquare()
    if not sq or not playerObj then return end

    local props = ISMoveableSpriteProps.fromObject(target)
    if not props or not props.isMoveable then return end

    -- QUIET. The menu is rebuilt as the cursor moves over it, and a refusal
    -- halo per frame is how the pick-up lock earned its rate limit in the
    -- first place. A part this character may not lift keeps its row, greyed
    -- with G.takeRefusal's reason, which is silent (2026-09-27: a
    -- refused action is shown greyed with its reason, never hidden). Hiding
    -- it gave a player the owner or screwdriver lock refuses the same silence
    -- the sealed-cabinet report describes, since the cursor shows them
    -- nothing either.
    local refused = DazedPower.Place and DazedPower.Place.mayTake
            and not DazedPower.Place.mayTake(playerObj, sq, target, true)

    local opt = C.icon(menu:addOption(getText("ContextMenu_DazedPower_TakeDown"),
                                      worldobjects, C.onTakeDown, target, playerObj),
                       menu, "takeDown")
    if refused then
        local G = DazedPower.Place
        local why = G.takeRefusal and G.takeRefusal(playerObj, sq, target)
        opt.notAvailable = true
        if why then opt.toolTip = C.tip(getText(why)) end
        return
    end

    -- A full bag greys the row the same way. Hiding it would read as the
    -- same silence the cabinet already gives.
    local inv = playerObj.getInventory and playerObj:getInventory()
    if inv and inv.hasRoomFor
            and not inv:hasRoomFor(playerObj, props.weight or 0) then
        opt.notAvailable = true
        opt.toolTip = C.tip(getText("Tooltip_DazedPower_TooHeavy"))
    end
end

function C.onTakeDown(worldobjects, object, playerObj)
    if not object or not playerObj then return end
    local sq = object:getSquare()
    if not sq then return end
    -- The menu can outlive what it was built on: another player, a fire or a
    -- zombie can take the part off the square while it is open.
    local objs = sq:getObjects()
    if not objs or not objs:contains(object) then return end

    local props = ISMoveableSpriteProps.fromObject(object)
    if not props or not props.isMoveable then return end

    -- NOT quiet, unlike the menu: this is the moment the player asked, so a
    -- refusal has to explain itself. canPickUpMoveable runs through
    -- canPickUpMoveableInternal, which DP_Place hooks, so the owner lock, the
    -- screwdriver lock and the running-controller rule all answer here.
    if not props:canPickUpMoveable(playerObj, sq, object) then return end

    -- walkToAndEquip is the preamble both vanilla routes use
    -- (ISMoveableCursor:create and ISDisassembleMenu.disassemble). It walks to
    -- a square BESIDE the object, which matters more here than anywhere else:
    -- a sealed cabinet's own square is solid and a ground array's is
    -- solidtrans, so neither can ever be stood on, and a walk aimed at the
    -- object's own tile would fail and take the queued action with it.
    -- When no free square beside it can be reached (walled in, or only past
    -- a closed door), the walk never starts. Say so once, on this click: the
    -- menu is not rebuilt here, so this cannot repeat every frame.
    if not (ISMoveableDefinitions and ISMoveableDefinitions.cheat)
            and not props:walkToAndEquip(playerObj, sq, "pickup",
                                         props.spriteName) then
        P.haloNote(playerObj, getText("IGUI_DazedPower_CannotReach"), true)
        return
    end

    -- The facing the action puts back on the item, read from the sprite the
    -- part is actually wearing rather than from its ModData: a panel under
    -- snow and the same panel swept are different sprites of the same facing.
    local facing = props.sprite
                   and props:getFaceDirectionFromSpriteName(props.sprite:getName())
    local found = props:findOnSquare(sq, props.spriteName)
    ISTimedActionQueue.add(ISMoveablesAction:new(playerObj, sq, "pickup",
                                                 props.spriteName,
                                                 found or object, facing,
                                                 nil, nil))
end

function C.tip(text)
    local t = ISWorldObjectContextMenu.addToolTip()
    t:setName("")
    t.description = text
    return t
end

function C.onInfo(worldobjects, object, playerObj)
    if DazedPower.Info and DazedPower.Info.open then
        DazedPower.Info.open(playerObj, object)
    end
end

function C.onGauge(worldobjects, object, playerObj)
    if DazedPower.Gauge then DazedPower.Gauge.open(playerObj, object) end
end

function C.onMonitor(worldobjects, object, playerObj)
    -- No walk. This is a screen to read, and walkAdj would clear whatever the
    -- player already had queued just to open a window.
    DazedPower.Window.open(playerObj, object)
end

function C.onAlmanac(worldobjects, playerObj)
    -- Same rule as the monitor: a window, not a job. A menu row opens, it
    -- never closes: an almanac already up is reopened, so it also takes the
    -- system from where the player stands now. (The sidebar button and the
    -- radial slice toggle, which is what a button does.)
    local F = DazedPower.Forecast
    local cur = F.windowFor and F.windowFor(playerObj)
    if cur then cur:close() end
    F.open(playerObj)
end

function C.onReadSky(worldobjects, playerObj)
    if not DazedPower.Almanac or DazedPower.Almanac.blocked(playerObj) then return end
    ISTimedActionQueue.add(DP_ReadSky:new(playerObj))
end

function C.onBreaker(worldobjects, object, playerObj, on)
    -- The monitor's knob comes here too; for a player the controller's lock
    -- refuses it says why and walks him nowhere.
    if refusedPress(playerObj, object) then return end
    if not C.approach(playerObj, object) then return end
    ISTimedActionQueue.add(DP_ResetBreaker:new(playerObj, object, on))
end

function C.onCells(worldobjects, object, playerObj)
    if not C.approach(playerObj, object) then return end
    DazedPower.Bank.open(playerObj, object)
end

function C.onClear(worldobjects, object, playerObj, mode, rag, water)
    if not C.approach(playerObj, object) then return end
    ISTimedActionQueue.add(DP_ClearArray:new(playerObj, object, mode, rag, water))
end

--- Start or stop an equalisation charge.
--  A flag on the controller rather than a timed action: it runs for days off
--  surplus that would otherwise be clipped, so there is nothing to stand and
--  watch.
----------------------------------------------------------------- wiring

--  A connection is made in two steps because there is nothing to click on in
--  between them. A cable exists only as data: it has no IsoObject and no
--  square, so it can never be hovered, outlined or right-clicked. Every
--  selection path in the game ends at an object on a tile.
--
--  So the interaction is anchored at the ENDS. Pick a part, then pick what to
--  wire it to. The pending choice is a client-side upvalue and nothing more,
--  which is also why it is dropped the moment anything about it stops making
--  sense.

local pending = nil        -- { obj, kind, name }

local function pendingValid(playerObj)
    if not pending then return false end
    if not pending.obj or pending.obj:getObjectIndex() == -1 then
        pending = nil
        return false
    end
    -- Wired by somebody else, or by this player from another menu, since the
    -- source was chosen. Through liveSys, not the raw field: a part carrying a
    -- DEAD claim is exactly the part most in need of being wired, and the raw
    -- check silently cancelled it as the player walked toward the controller.
    if liveSys(P.data(pending.obj)) then
        pending = nil
        return false
    end
    return true
end

function C.onPickSource(worldobjects, object, playerObj)
    local info = P.describe(object)
    if not info then return end
    if refusedPress(playerObj, object) then return end
    pending = { obj = object, kind = info.kind,
                name = getItemNameFromFullType(P.itemFor(info.kind, info.mount,
                                                         info.tier) or "") }
end

function C.onClearSource()
    pending = nil
end

function C.onRunCable(worldobjects, target, playerObj)
    if not pendingValid(playerObj) then return end
    local src = pending.obj
    if refusedPress(playerObj, src, target) then return end
    -- Walk to the end the player JUST CLICKED, not the one they marked earlier.
    -- Marking a panel on a roof and then walking downstairs to the controller
    -- is exactly how somebody would really do this, and sending the character
    -- back up the stairs to start the job is the opposite of what they asked
    -- for. The server accepts either end, so standing here is legitimate.
    if not C.approach(playerObj, target) then return end
    pending = nil
    ISTimedActionQueue.add(DP_RunCable:new(playerObj, src, target, false, target))
end

function C.onCutCable(worldobjects, object, playerObj, other)
    if refusedPress(playerObj, object, other) then return end
    if not C.approach(playerObj, object) then return end
    ISTimedActionQueue.add(DP_RunCable:new(playerObj, object, other, true, object))
end

--- Everything this part is wired to, as world objects.
function C.connectionsOf(object, info)
    local out = {}
    local sq = object:getSquare()
    if not sq then return out end
    local d = P.data(object)
    local sysKey = (info.kind == "controller")
        and M.nodeKey(sq:getX(), sq:getY(), sq:getZ(), "controller") or liveSys(d)
    if not sysKey then return out end
    local cx, cy, cz = M.parseNodeKey(sysKey)
    if not cx then return out end
    local ctrl = (info.kind == "controller") and object
                 or P.objectAt(cx, cy, cz, "controller")
    if not ctrl then return out end
    local edges = M.wireParse(P.data(ctrl).wire)
    local me = M.nodeKey(sq:getX(), sq:getY(), sq:getZ(), info.kind)
    local near = M.wireNeighbours(edges, me)
    for i = 1, #near do
        local x, y, z, kind = M.parseNodeKey(near[i])
        local o = x and P.objectAt(x, y, z, kind)
        if o then out[#out + 1] = { obj = o, kind = kind } end
    end
    return out
end

--- One connection in words, as seen from this part: its name and how to get
--  there ("Solar Array, 3 tiles east, 1 tile south"). The Info panel's Wired
--  to list and the cut menu print the same line, so the row a player cuts is
--  the one they read.
function C.linkText(object, other)
    local li = other and P.describe(other)
    local name = li and getItemNameFromFullType(
        P.itemFor(li.kind, li.mount, li.tier) or "") or "?"
    local sq, osq = object and object:getSquare(), other and other:getSquare()
    if not (sq and osq) then return name end
    return P.txt("IGUI_DazedPower_InfoLink", name,
                 P.offsetText(sq:getX(), sq:getY(), sq:getZ(),
                              osq:getX(), osq:getY(), osq:getZ()))
end

--- Electric Wire the player carries, bags included (DP_System counts it the same way).
function C.wireCount(playerObj)
    local inv = playerObj and playerObj:getInventory()
    local list = inv and P.try(inv, "getAllTypeRecurse", "Base.ElectricWire")
    return list and list:size() or 0
end

--- The wiring rows for one part.
function C.wireMenu(menu, worldobjects, target, playerObj, info)
    local d = P.data(target)
    local sysKey = (info.kind == "controller") and "self" or liveSys(d)

    -- Every cable row asks the owner's lock of each part whose wiring it
    -- changes (2026-09-29: "Lock them in 3.0.0"), the lock S.connect and S.disconnect ask again first. A
    -- refused row stays, greyed with the reason.
    local lock = lockOf(playerObj, target)

    -- Step one: choose this part as the loose end.
    if info.kind ~= "controller" and not sysKey then
        if pending and pending.obj == target then
            C.icon(menu:addOption(getText("ContextMenu_DazedPower_WireCancel"),
                                  worldobjects, C.onClearSource), menu, "wireCancel")
        else
            greyed(C.icon(menu:addOption(getText("ContextMenu_DazedPower_WireFrom"),
                                         worldobjects, C.onPickSource, target, playerObj),
                          menu, "wireFrom"), lock)
        end
    end

    -- Step two: land it on something that is already part of a system.
    if pendingValid(playerObj) and pending.obj ~= target and sysKey
            and M.wireLegal(pending.kind, info.kind) then
        local sq, ps = target:getSquare(), pending.obj:getSquare()
        local far = false
        if sq and ps then
            local dx, dy = sq:getX() - ps:getX(), sq:getY() - ps:getY()
            -- The same rule the server applies (S.connect): a power line to
            -- or from a transformer runs further than a panel or battery lead.
            local reach = M.cableReach(pending.kind, info.kind, P.sandbox("LinkRadius"),
                                       P.sandbox("GridLinkRadius"))
            far = (dx * dx + dy * dy) > reach * reach
        end
        local opt = C.icon(menu:addOption(
            P.txt("ContextMenu_DazedPower_WireTo", pending.name or "?"),
            worldobjects, C.onRunCable, target, playerObj), menu, "wireTo")
        -- Both ends, before the server's other reasons, in the order
        -- S.connect asks them: the loose end in hand, then this part.
        local endLock = lockOf(playerObj, pending.obj) or lock
        if endLock then
            greyed(opt, endLock)
        elseif far then
            opt.notAvailable = true
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip.description = getText("IGUI_DazedPower_WireFar")
            opt.toolTip = tip
        elseif sq and ps then
            -- The wire the cable takes (S.connect charges the same), shown either way and refused when short.
            local cost = M.cableWire(M.cableLength(sq:getX(), sq:getY(), ps:getX(), ps:getY()),
                                     P.sandbox("CableTilesPerWire"))
            if cost > 0 then
                local have = C.wireCount(playerObj)
                if have < cost then
                    opt.notAvailable = true
                    opt.toolTip = C.tip(P.txt("Tooltip_DazedPower_WireShort", cost, have))
                else
                    opt.toolTip = C.tip(P.txt("Tooltip_DazedPower_WireCost", cost, have))
                end
            end
        end
    end

    -- And cutting, one row per connection, anchored at this end because the
    -- cable itself can never be the thing you click. Each row says where the
    -- other end is: two arrays wired to one controller were two rows reading
    -- "Solar Array" and nothing else.
    --  A cable is its ends' owners' groups' to cut, from either end:
    --  every part's since "Lock them in 3.0.0". Both ends' locks, as
    --  S.disconnect asks them.
    local links = C.connectionsOf(target, info)
    if #links > 0 then
        local sub = C.icon(menu:addOption(getText("ContextMenu_DazedPower_WireCut")),
                           menu, "wireCut")
        local ctx = ISContextMenu:getNew(menu)
        menu:addSubMenu(sub, ctx)
        sub.ogSub = ctx
        for i = 1, #links do
            local opt = ctx:addOption(C.linkText(target, links[i].obj), worldobjects,
                                      C.onCutCable, target, playerObj, links[i].obj)
            greyed(opt, lock or lockOf(playerObj, links[i].obj))
        end
    end
end

--- The wired kinds this controller's loads page lists, in page order.
function C.wiredKinds(d)
    local out, seen = {}, {}
    for _, row in ipairs(type(d.loadList) == "table" and d.loadList or {}) do
        local wired = (M.LOAD_KINDS and M.LOAD_KINDS[row.k]) or (M.APPLIANCE_KINDS and M.APPLIANCE_KINDS[row.k])
        if row.k and wired and not seen[row.k] then
            seen[row.k] = true
            out[#out + 1] = row.k
        end
    end
    return out
end

--- Load priority: one submenu per wired kind, three rows each.
function C.priorityMenu(menu, worldobjects, target, playerObj, d, lock)
    local Pr = DazedPower.Priority
    local kinds = Pr and C.wiredKinds(d) or {}
    if #kinds == 0 then return end
    local sub = ISContextMenu:getNew(menu)
    local head = menu:addOption(getText("ContextMenu_DazedPower_Priority"))
    menu:addSubMenu(head, sub)
    head.toolTip = C.tip(getText("Tooltip_DazedPower_Priority"))
    local names = { getText("ContextMenu_DazedPower_PrioEssential"), getText("ContextMenu_DazedPower_PrioNormal"),
                    getText("ContextMenu_DazedPower_PrioLow") }
    for _, kind in ipairs(kinds) do
        local cur = Pr.of(d, kind)
        local kmenu = ISContextMenu:getNew(sub)
        local row = sub:addOption(getText("IGUI_DazedPower_Load_" .. kind) .. " (" .. names[cur] .. ")")
        sub:addSubMenu(row, kmenu)
        for p = 1, 3 do
            local o = kmenu:addOption(names[p], worldobjects, C.onPriority, target, playerObj, kind, p)
            if p == cur then o.notAvailable = true end
            greyed(o, lock)
        end
    end
end

function C.onPriority(worldobjects, object, playerObj, kind, value)
    local sq = object and object:getSquare()
    if not sq or refusedPress(playerObj, object) then return end
    C.send(playerObj, "priority", { x = sq:getX(), y = sq:getY(), z = sq:getZ(), kind = kind, value = value })
end

function C.onEqualise(worldobjects, object, playerObj, on)
    if not object then return end
    local sq = object:getSquare()
    if not sq then return end
    if refusedPress(playerObj, object) then return end
    -- Never written here. A client's transmitModData() replaces the object's
    -- whole ModData table on the server, so setting one flag from the client
    -- would also clobber the live charge the server has been keeping.
    C.send(playerObj, "equalise",
           { x = sq:getX(), y = sq:getY(), z = sq:getZ(),
             on = on and true or false })
end

function C.onRepair(worldobjects, object, playerObj, scrap, screws)
    if not object or not scrap or not screws then return end
    if not C.approach(playerObj, object) then return end
    ISTimedActionQueue.add(DP_RepairArray:new(playerObj, object, scrap, screws))
end

------------------------------------------------------- coverage and buildings

--- Show / Hide power coverage: the whole system's reach, from the controller
--  or from any transformer in it.
function C.coverageMenu(menu, target, playerObj)
    local coverage = DazedPower.Coverage
    if not coverage then return end
    local shown = coverage.isSelected(target, playerObj)
    local key = shown and "ContextMenu_DazedPower_HideCoverage" or "ContextMenu_DazedPower_ShowCoverage"
    local option = C.icon(menu:addOption(getText(key), target, coverage.toggle, playerObj),
                          menu, shown and "coverageHide" or "coverageShow")
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip.description = getText("Tooltip_DazedPower_Coverage")
    option.toolTip = tip
end

--- Wire up the building, Choose buildings..., Unwire the buildings.
--
--  Sent to the authority, which resolves the building, checks the reach and
--  stores the footprint; never written here (see C.onEqualise for why a
--  client must not push a part's ModData). The server accepts these from
--  anywhere within the part's own reach, so there is no walk: the player is
--  on site, and the Building Picker is used from where they stand.
--  All three are the part's owner's group's (2026-09-29: "Lock them in
--  3.0.0"): for anyone else each stays on the menu, greyed with the lock's
--  reason in place of its own tooltip, as DP_Distrib refuses them.
function C.buildingMenu(menu, worldobjects, target, playerObj, part)
    local n = wiredCount(P.data(target))
    local lock = lockOf(playerObj, target)
    if n == 0 then
        local opt = C.icon(menu:addOption(getText("ContextMenu_DazedPower_WireBuilding"), worldobjects,
                                          C.onWireBuilding, target, playerObj),
                           menu, "wireBuilding")
        opt.toolTip = C.tip(getText("Tooltip_DazedPower_WireBuilding"))
        greyed(opt, lock)
    end
    local pick = C.icon(menu:addOption(getText("ContextMenu_DazedPower_ChooseBuildings"), worldobjects,
                                       C.onChooseBuildings, target, playerObj),
                        menu, "chooseBuildings")
    pick.toolTip = C.tip(getText("Tooltip_DazedPower_ChooseBuildings"))
    greyed(pick, lock)
    if n > 0 then
        local opt = C.icon(menu:addOption(P.txt("ContextMenu_DazedPower_UnwireBuildings", n), worldobjects,
                                          C.onUnwireBuildings, target, playerObj),
                           menu, "unwireBuildings")
        opt.toolTip = C.tip(getText("Tooltip_DazedPower_UnwireBuildings"))
        greyed(opt, lock)
    end
end

local function partArgs(object)
    local sq = object and object:getSquare()
    if not sq then return nil end
    return { x = sq:getX(), y = sq:getY(), z = sq:getZ(), kind = P.partOf(object) }
end

function C.onWireBuilding(worldobjects, object, playerObj)
    if refusedPress(playerObj, object) then return end
    local args = partArgs(object)
    if args then C.send(playerObj, "bwDefault", args) end
end

function C.onUnwireBuildings(worldobjects, object, playerObj)
    if refusedPress(playerObj, object) then return end
    local args = partArgs(object)
    if args then C.send(playerObj, "bwClear", args) end
end

function C.onChooseBuildings(worldobjects, object, playerObj)
    if refusedPress(playerObj, object) then return end
    -- DP_Picker loads after this file (see the note on DP_Info at the top),
    -- so it is reached through its table, not required.
    if DazedPower.Picker and DazedPower.Picker.open then DazedPower.Picker.open(playerObj, object) end
end

--- A GEN page press: walk to the controller and queue the short action whose completion runs it (DP_GenPanel).
function C.onGenPanel(playerObj, object, cmd, args)
    if not playerObj or not object or not DP_GenPanelAction then return nil end
    if not C.approach(playerObj, object) then return nil end
    local act = DP_GenPanelAction:new(playerObj, object, cmd, args)
    ISTimedActionQueue.add(act)
    return act
end

------------------------------------------------------------------ admin

--- The controller's Admin submenu, for staff and single-player debug only (DP_Admin.allowed); the server asks again.
function C.adminMenu(menu, worldobjects, target, playerObj)
    local A = DazedPower.Admin
    if not (A and A.allowed(playerObj)) then return end
    local head = C.icon(menu:addOption(getText("ContextMenu_DazedPower_Admin"), worldobjects, nil), menu, "admin")
    local sub = ISContextMenu:getNew(menu)
    menu:addSubMenu(head, sub)
    head.ogSub = sub
    C.icon(sub:addOption(getText("ContextMenu_DazedPower_AdminInspect"), worldobjects, C.onAdminInspect, target, playerObj),
           sub, "adminInspect")
    -- The three writes go through commandTarget on the server, which refuses beyond arm's reach.
    local far = not reachable(playerObj, target)
    for _, row in ipairs({ { "AdminRepair", "adminRepair" }, { "AdminReset", "adminReset" }, { "AdminFill", "adminFill" } }) do
        local opt = C.icon(sub:addOption(getText("ContextMenu_DazedPower_" .. row[1]), worldobjects, C.onAdminCommand,
                                         target, playerObj, row[2]), sub, row[2])
        if far then
            opt.notAvailable = true
            opt.toolTip = C.tip(getText("Tooltip_DazedPower_AdminReach"))
        else
            opt.toolTip = C.tip(getText("Tooltip_DazedPower_" .. row[1]))
        end
    end
    C.dimUnavailable(sub)
end

function C.onAdminInspect(worldobjects, object, playerObj)
    -- Reached through its table, so neither client file has to require the other.
    if DazedPower.AdminWindow and DazedPower.AdminWindow.open then DazedPower.AdminWindow.open(playerObj, object) end
end

function C.onAdminCommand(worldobjects, object, playerObj, command)
    local sq = object and object:getSquare()
    if not sq then return end
    C.send(playerObj, command, { x = sq:getX(), y = sq:getY(), z = sq:getZ() })
end

Events.OnFillWorldObjectContextMenu.Add(C.onFill)

return C
