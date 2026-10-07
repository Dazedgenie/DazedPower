-- Loads every Lua file of the mod (shared, then server, then client) on a stand-in engine, the way the game
-- would, and reports any file that fails to load. Then a few smoke checks on the registry and the model.
-- Run: lua load_test.lua [<lua root>] [<core lua root>]
local root = arg[1] or "../../common/media/lua"
local core = arg[2] or "../../../DazedCore/common/media/lua"
package.path = core .. "/shared/?.lua;" .. core .. "/client/?.lua;" .. root .. "/shared/?.lua;" .. root .. "/server/?.lua;" .. root .. "/client/?.lua;" .. package.path
local E = dofile("../../../DazedCore/tools/tests/engine_stub.lua")
local print = E.realPrint
local fails, checks = 0, 0
local function check(c, m) checks = checks + 1 if not c then fails = fails + 1 print("FAIL " .. m) end end

-- ------------------------------------------------------------ more of the engine than the core stub has
local function anyObject()
    return setmetatable({}, { __index = function(t, k) return function() return anyObject() end end, __call = function() return anyObject() end })
end
getTextManager = function() return { getFontHeight = function() return 16 end, MeasureStringX = function() return 10 end } end
UIFont = { Small = "Small", Medium = "Medium", Large = "Large", Code = "Code", NewSmall = "NewSmall", NewMedium = "NewMedium" }
local function uiClass(name)
    local c = { Type = name }
    c.__index = c
    function c:derive(n) local d = { Type = n } d.__index = d setmetatable(d, { __index = self }) return d end
    function c:new(...) return setmetatable({}, self) end
    for _, m in ipairs({ "initialise", "instantiate", "addChild", "setVisible", "addToUIManager", "removeFromUIManager", "setWidth", "setHeight",
                         "getWidth", "getHeight", "setX", "setY", "getX", "getY", "titleBarHeight", "createChildren", "prerender", "render",
                         "setResizable", "drawText", "drawRect", "drawRectBorder", "setEnable", "close", "setTitle", "bringToTop", "onMouseDown",
                         "onMouseUp", "onMouseMove", "onMouseMoveOutside", "onMouseWheel", "clearChildren", "setAnchorRight", "setAnchorBottom" }) do
        c[m] = function() return 0 end
    end
    return c
end
ISPanel = uiClass("ISPanel"); ISCollapsableWindow = uiClass("ISCollapsableWindow"); ISButton = uiClass("ISButton")
ISLabel = uiClass("ISLabel"); ISScrollingListBox = uiClass("ISScrollingListBox"); ISTickBox = uiClass("ISTickBox")
ISUIElement = uiClass("ISUIElement"); ISLayoutManager = uiClass("ISLayoutManager"); ISEquippedItem = uiClass("ISEquippedItem")
ISEmoteRadialMenu = uiClass("ISEmoteRadialMenu"); ISContextMenu = uiClass("ISContextMenu"); ISToolTip = uiClass("ISToolTip")
ISWorldObjectContextMenu = { addToolTip = function() return {} end }
ISInventoryPaneContextMenu = {}
ISLiteratureUI = { miscRecipes = {} }
ISMoveableSpriteProps = setmetatable({}, { __index = function() return function() end end })
ISTransferAction = { transferItem = function() end }; ISDropWorldItemAction = { complete = function() end }
ISDropVehicleItemAction = { complete = function() end }; ISDestroyStuffAction = { complete = function() end }
ISTakeGenerator = { isValid = function() return true end, complete = function() return true end }
ISLightActions = { isValidRemoveBattery = function() return true end, isValidAddBattery = function() return true end }
ISTimedActionQueue = { add = function() end }
MapObjects = { OnLoadWithSprite = function() end, OnNewWithSprite = function() end }
IsoPlayer = { getPlayerIndex = function() return 0 end }
IsoUtils = { XToScreenExact = function() return 0 end, YToScreenExact = function() return 0 end }
SpriteRenderer = { instance = { renderPoly = function() end, renderlinef = function() end } }
Keyboard = { KEY_ESCAPE = 1 }
getSpecificPlayer = function() return nil end
getPlayer = function() return nil end
getNumActivePlayers = function() return 0 end
isClient = function() return false end
isServer = function() return false end
getCore = function() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
getSprite = function() return nil end
getSpriteManager = function() return { getNamedMap = function() return { containsKey = function() return true end } end } end
getScriptManager = function() return { getItem = function() return { getActualWeight = function() return 10 end } end } end
getTexture = function() return {} end
getTimestampMs = function() return 0 end
getWorld = function() return { getMetaGrid = function() return nil end } end
getClimateManager = function() return anyObject() end
getGameTime = function() return { getWorldAgeHours = function() return 100 end, getHour = function() return 12 end, getDay = function() return 1 end,
                                   getMonth = function() return 6 end, getYear = function() return 1993 end, getTimeOfDay = function() return 12 end,
                                   getNightsSurvived = function() return 0 end, getMinutes = function() return 0 end, getDayLightStrength = function() return 1 end,
                                   getNight = function() return 0 end, getDawn = function() return 6 end, getDusk = function() return 20 end } end
getSandboxOptions = function() return { getOptionByName = function() return nil end } end
SandboxVars = { DazedPower = {}, DazedPlumb = {}, WaterShutModifier = 0, GeneratorFuelConsumption = 0.1 }
ModData = ModData or {}
PZAPI = { ModOptions = { create = function() local page = { options = {} } function page:addTickBox(id) local o = { id = id, getValue = function() return true end } self.options[id] = o return o end function page:getOption(id) return self.options[id] end return page end, getOptions = function() return nil end } }
ProceduralDistributions = { list = {} }
package.preload["Items/ProceduralDistributions"] = function() return true end
package.preload["Moveables/ISMoveableSpriteProps"] = function() return true end
for _, m in ipairs({ "ISUI/ISCollapsableWindow", "ISUI/ISButton", "ISUI/ISPanel", "ISUI/ISLabel", "ISUI/ISScrollingListBox", "ISUI/ISTickBox",
                     "ISUI/ISUIElement", "ISUI/ISLayoutManager", "ISUI/ISEquippedItem", "ISUI/ISToolTip", "ISUI/ISContextMenu",
                     "TimedActions/ISBaseTimedAction", "TimedActions/ISLightActions", "TimedActions/ISTakeGenerator",
                     "ISUI/ISEmoteRadialMenu", "Moveables/ISMoveableDefinitions", "Items/ItemPicker", "errorMagnifier_Main" }) do
    package.preload[m] = package.preload[m] or function() return true end
end
if not ISBaseTimedAction then require "TimedActions/ISBaseTimedAction" end
-- any other vanilla module (TimedActions/*, ISUI/*, Vehicles/*...) loads as an empty stub
table.insert(package.searchers, 2, function(name)
    if name:match("^DazedPower/") or name:match("^DazedCore/") or name:match("^DazedPlumbing/") then return nil end
    return function() return true end
end)
IsoFlagType = { waterPiped = "waterPiped" }
IsoRegions = nil
ArrayList = { new = function() local t = {} return { add = function(_, v) t[#t + 1] = v end, size = function() return #t end, get = function(_, i) return t[i + 1] end } end }
ZombRand = function(n) return 0 end
ZombRandFloat = function(a, b) return a end
luautils = { walkAdj = function() return true end }
getText = function(k) return k end
instanceof = function() return false end

-- ------------------------------------------------------------ load everything, in the game's order
local function filesIn(dir)
    local out = {}
    local p = io.popen('ls "' .. dir .. '"')
    for f in p:lines() do if f:match("%.lua$") then out[#out + 1] = f:gsub("%.lua$", "") end end
    p:close()
    table.sort(out)
    return out
end
local loaded, failed = 0, {}
for _, side in ipairs({ "shared", "server", "client" }) do
    for _, f in ipairs(filesIn(root .. "/" .. side .. "/DazedPower")) do
        local ok, err = pcall(require, "DazedPower/" .. f)
        if ok then loaded = loaded + 1 else failed[#failed + 1] = f .. ": " .. tostring(err) end
    end
end
for _, f in ipairs(failed) do print("LOAD FAIL " .. f) end
check(#failed == 0, #failed .. " file(s) failed to load")
print(string.format("loaded %d files", loaded))

-- ------------------------------------------------------------ smoke checks
local P, M = DazedPower.Parts, DazedPower.Model
check(#P.ROWS == 167, "167 sheet rows: " .. #P.ROWS)
check(P.sprite("array", "ground", "makeshift", "clear", "S") == "dazedpower_01_1", "first array sprite")
check(P.sprite("controller", "ground", "makeshift", "off", "S") == "dazedpower_01_345", "controller sprite matches the taxonomy")
local xl = P.spriteInfo("dazedpower_01_73")
check(xl and xl.kind == "array" and xl.mount == "xl" and xl.piece == 1 and xl.master and xl.pieces == 4, "XL master piece decoded")
local xl2 = P.spriteInfo(P.sprite("array", "xl", "workshop", "snow", "N", 3))
check(xl2 and xl2.piece == 3 and not xl2.master and xl2.tier == "workshop" and xl2.state == "snow", "XL piece 3 decoded")
check(P.spriteInfo("dazedpower_02_95").kind == "petrol", "last sprite is a petrol generator")
check(P.spriteInfo("dazedpower_02_96").kind == "gauge" and P.spriteInfo("dazedpower_02_111").state == "full", "the wall gauge rows follow")
check(P.spriteInfo("dazedpower_02_156") == nil and P.spriteInfo("dazedpower_02_155") ~= nil, "nothing past the sheet")
check(P.spriteName(511) == "dazedpower_01_511" and P.spriteName(512) == "dazedpower_02_0", "the sheet spills onto a second tileset at 512")
check(P.indexOf("dazedpower_02_0") == 512 and P.indexOf("dazedpower_01_512") == nil, "names map back to sheet indices")
local over = 0
for n = 0, #P.ROWS * P.COLS - 1 do
    local nm = P.spriteName(n)
    if P.indexOf(nm) ~= n or tonumber(string.match(nm, "_(%d+)$")) >= 512 then over = over + 1 end
end
check(over == 0, "every sprite round-trips and no tileset holds more than 512")
check(#P.allItems() == 67, "67 items: " .. #P.allItems())
check(M.wireLegal("windmill", "controller") and M.wireLegal("windmill", "windmill") and not M.wireLegal("windmill", "array"), "source wiring rules")
check(M.wireLegal("waterpump", "transformer") and not M.wireLegal("array", "waterpump") and not M.wireLegal("vane", "controller"), "load and instrument rules")
check(M.ctrlSpec("makeshift").nodes == 8 and M.ctrlSpec("workshop").nodes == 24, "controller node caps")
check(M.lampSpec("street_workshop").wh == 720 and M.lampSpec("nope").wh == 24, "lamp specs by key")
check(M.trackerFacing(8) == "E" and M.trackerFacing(12) == "S" and M.trackerFacing(16) == "W", "tracker facing by sun hour")
-- a tracker beats the same static array through a clear day
local env = { dayOfYear = 172, hour = 15, noon = 13, dayHours = 14.5, cloud = 0, fog = 0, precipitation = 0, temperature = 25, daylight = 1, latitude = 38 }
local staticW = M.arrayOutput({ tier = "salvaged", mount = "ground", facing = "S", panels = 2 }, env)
local trackW = M.arrayOutput({ tier = "salvaged", mount = "tracker", facing = "S", panels = 2 }, env)
check(trackW > staticW and trackW < staticW * 1.6, string.format("tracker %.0f W beats static %.0f W in the afternoon", trackW, staticW))
-- the model takes source watts at the bus
local sys = { arrays = {}, bank = { cells = 2, charge = 0, capacity = 1000, eff = 0.9 }, load = 0, online = true, powered = true, sourceW = 500 }
local _, t = M.step(sys, 1, env)
check(t.sourceWatts == 500 and t.generated >= 500, "source watts counted in generation: " .. tostring(t.generated))

dofile("features_test.lua")(check, E)
dofile("systems_test.lua")(check, E)
dofile("climate_power_test.lua")(check, E)
dofile("board_test.lua")(check, E)

-- The monitor places itself before building; stop it there to check that much runs (it once called a missing helper).
do
    getPlayerScreenLeft = getPlayerScreenLeft or function() return 0 end
    getPlayerScreenTop = getPlayerScreenTop or function() return 0 end
    local realNew = DP_Window.new
    DP_Window.new = function() error("placed") end
    local ok, err = pcall(DazedPower.Window.open, nil, nil)
    DP_Window.new = realNew
    check(not ok and tostring(err):find("placed") ~= nil, "the monitor window places itself: " .. tostring(err))
end

print(string.format("load_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
