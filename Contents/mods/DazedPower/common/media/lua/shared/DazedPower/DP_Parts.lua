--[[ DazedPower -- identifying and describing the world parts.

     Shared, because the client draws these and the server simulates them and
     both have to agree on what a given world object is.

     Identity comes from the sprite name. The tilesheet is laid out one row per
     (kind, mount, tier, state) and one column per facing, so `dazedpower_01_101`
     is exactly "a premium ground battery bank, LEDs green, facing S" and
     nothing else needs storing to know that. This table MUST stay in step with
     tools/og_taxonomy.py -- tests/test_pack.py fails if they drift.
]]

require "DazedCore/DC_Boot"
require "DazedPower/DP_Model"

DazedPower = DazedPower or {}
DazedPower.Parts = DazedPower.Parts or {}
local P = DazedPower.Parts

---------------------------------------------------- engine and sandbox access

--- Call an optional method: nil, not an error, when the object is nil, lacks
--  the method, or the call throws. For engine surfaces that differ between
--  builds and for objects that may already have left the world.
function P.try(obj, method, ...)
    if not obj or not obj[method] then return nil end
    local ok, v = pcall(obj[method], obj, ...)
    if ok then return v end
    return nil
end

--- Every sandbox option the mod declares, at the default
--  media/sandbox-options.txt gives it. tests/test_content.py fails if the two
--  drift, or if anything reads an option not listed here.
P.SANDBOX_DEFAULTS = {
    LinkRadius = 12,
    OutputScale = 100,
    BankScale = 100,
    SnowRate = 100,
    SoilRate = 100,
    SimulateLoad = true,
    DegradeBank = true,
    AgeRate = 100,
    StormRate = 100,
    HydrogenRisk = true,
    PickupLock = 3,
    GridLinkRadius = 30,
    TransformerLoss = 25,
    RealisticMode = false,
    RigChance = 15,
    BarnStockChance = 2,
    CableTilesPerWire = 4,
    LiveShock = true,
    FenceDamage = true,
    ColdStarts = true,
    RoomHeat = true,
}

-- The Dazed Utilities preset values for this page: { easy, standard, realistic, hardcore } per option.
P.PRESETS = {
    OutputScale = { 150, 100, 80, 60 }, BankScale = { 150, 100, 100, 75 },
    SnowRate = { 50, 100, 100, 150 }, SoilRate = { 50, 100, 100, 150 },
    SimulateLoad = { false, true, true, true }, DegradeBank = { false, true, true, true },
    AgeRate = { 0, 100, 150, 250 }, RealisticMode = { false, false, true, true },
    LinkRadius = { 16, 12, 10, 8 }, GridLinkRadius = { 40, 30, 25, 20 },
    TransformerLoss = { 10, 25, 25, 35 }, CableTilesPerWire = { 0, 4, 3, 2 },
    LiveShock = { false, true, true, true }, RigChance = { 25, 15, 10, 5 },
    StormRate = { 50, 100, 100, 160 }, HydrogenRisk = { false, true, true, true },
    FenceDamage = { true, true, true, true },
    ColdStarts = { false, true, true, true }, RoomHeat = { true, true, true, true },
}
if DazedCore and DazedCore.Preset then DazedCore.Preset.register("DazedPower", P.PRESETS) end

--- A sandbox option's value, or its declared default while SandboxVars does
--  not carry it yet (the main menu, a world from before the option existed).
function P.sandbox(name)
    local pre = DazedCore and DazedCore.Preset and DazedCore.Preset.override("DazedPower", name)
    if pre ~= nil then return pre end
    local sv = SandboxVars and SandboxVars.DazedPower
    local v = sv and sv[name]
    if v == nil then return P.SANDBOX_DEFAULTS[name] end
    return v
end

--- Realistic Mode, for the model: DP_Model asks this whenever it picks a
--  panel spec, so the simulation, the forecast and every card agree, and a
--  change of the option takes effect at once. DP_Model keeps this if it loads
--  second, which is why it only sets its own default when there is none.
DazedPower.Model = DazedPower.Model or {}
DazedPower.Model.isRealistic = function()
    return P.sandbox("RealisticMode") == true
end

--- ANOTHER mod's sandbox page, as the table SandboxVars holds, or nil. Read
--  here so this file stays the one place that touches SandboxVars; it has no
--  defaults to fall back on, because those options are not ours to declare.
function P.foreignSandbox(page)
    local sv = SandboxVars and SandboxVars[page]
    if type(sv) ~= "table" then return nil end
    return sv
end

--- Vanilla's Generator Fuel Consumption: the top-level sandbox multiplier a
--  normal generator's hourly burn is scaled by (SandboxVars.
--  GeneratorFuelConsumption, not a page of ours). A backup generator bills
--  the same appliances the same way, so it reads the same number. 0.1,
--  vanilla's default, when it is absent or not a number (the main menu, a
--  hand-edited file); 0 stays 0, which is free fuel in vanilla too. Read here
--  so this file stays the one place that touches SandboxVars.
function P.generatorFuelConsumption()
    local v = SandboxVars and SandboxVars.GeneratorFuelConsumption
    if type(v) ~= "number" then return 0.1 end
    return v
end

--- Vanilla's fridge factor: how much of normal ageing food in a powered fridge keeps, mirroring the
--  engine's private Food.getFridgeFactor (SandboxVars.FridgeFactor 1..6, default 3 = 0.2).
P.FRIDGE_FACTOR = { 0.4, 0.3, 0.2, 0.1, 0.03, 0.0 }
function P.fridgeFactor()
    local v = SandboxVars and tonumber(SandboxVars.FridgeFactor)
    return P.FRIDGE_FACTOR[v or 3] or 0.2
end

--- Vanilla's food rot speed multiplier, mirroring the engine's private Food.getFoodRotSpeed
--  (SandboxVars.FoodRotSpeed 1..5, default 3 = 1.0).
P.FOOD_ROT_SPEED = { 1.7, 1.4, 1.0, 0.7, 0.4 }
function P.foodRotSpeed()
    local v = SandboxVars and tonumber(SandboxVars.FoodRotSpeed)
    return P.FOOD_ROT_SPEED[v or 3] or 1.0
end

--- The bank capacity multiplier, and the only reader of it. Installing and
--  removing batteries, the simulation, the seeder and every panel must agree
--  on how big a rack is, or a charge is kept against one capacity and handed
--  back against another. Anything but a positive number (a hand-edited
--  SandboxVars) reads as 100%.
function P.bankScale()
    local v = P.sandbox("BankScale")
    if type(v) ~= "number" or v <= 0 then return 1 end
    return v / 100
end

P.TILESET = "dazedpower_01"
-- The engine takes at most 512 tiles per tileset, so overall index n lives on dazedpower_0<1 + n // 512>.
P.SHEET_TILES = 512

--- Engine sprite name for overall sheet index n.
function P.spriteName(n)
    local s = math.floor(n / P.SHEET_TILES)
    return string.format("dazedpower_%02d_%d", s + 1, n - s * P.SHEET_TILES)
end

-- Sprite name -> sheet index (false for not ours); names are a fixed set, so the answer never changes.
local indexMemo, indexMemoN = {}, 0
local INDEX_MEMO_MAX = 50000

--- Overall sheet index of one of our sprite names, or nil.
function P.indexOf(name)
    if type(name) ~= "string" then return nil end
    local hit = indexMemo[name]
    if hit ~= nil then return hit or nil end
    local idx = nil
    local s, i = string.match(name, "^dazedpower_(%d%d)_(%d+)$")
    if s then
        s, i = tonumber(s), tonumber(i)
        if s >= 1 and i < P.SHEET_TILES then idx = (s - 1) * P.SHEET_TILES + i end
    end
    -- Bounded so a map with an unusual number of distinct tiles cannot grow it forever.
    if indexMemoN >= INDEX_MEMO_MAX then indexMemo, indexMemoN = {}, 0 end
    indexMemo[name] = idx or false
    indexMemoN = indexMemoN + 1
    return idx
end
P.COLS = 4

-- Column order inside every row, and the reverse lookup.
P.FACINGS = { "E", "S", "W", "N" }
P.FACING_INDEX = { E = 0, S = 1, W = 2, N = 3 }

-- APPEND ONLY, and in the same order as tools/dp_taxonomy.py: a sprite index is row * COLS + facing, so a
-- kind inserted anywhere but the end repoints every object already standing in a save.
P.KINDS = { "array", "bank", "controller", "transformer", "lamp", "pedal", "windmill", "steam", "windsock", "vane",
            "propane", "petrol", "gauge", "rod", "bench", "hydro", "fence", "cooler", "heater", "windspin" }
P.KIND_SET = {}
for _, k in ipairs(P.KINDS) do P.KIND_SET[k] = true end
-- The mount is the form factor: a static, tracking or 2x2 array; a floor or wall bank; a garden or street lamp.
P.MOUNTS = {
    array = { "ground", "tracker", "xl" },
    bank = { "ground", "wall" },
    controller = { "ground" },
    transformer = { "ground" },
    lamp = { "garden", "street" },
    pedal = { "ground" }, windmill = { "ground" }, steam = { "ground" },
    windsock = { "ground" }, vane = { "ground" },
    propane = { "ground" }, petrol = { "ground" },
    gauge = { "wall" }, rod = { "ground" }, bench = { "ground" }, hydro = { "ground" },
    fence = { "ground" }, cooler = { "wall" }, heater = { "ground" }, windspin = { "ground" },
}
local THREE = { "makeshift", "salvaged", "workshop" }
P.TIERS = {
    array = THREE, bank = THREE,
    controller = { "makeshift", "workshop" },
    transformer = { "standard" },
    lamp = { "makeshift", "workshop" },
    pedal = THREE, windmill = THREE, steam = THREE,
    windsock = { "basic" }, vane = { "basic" },
    propane = THREE, petrol = THREE,
    gauge = { "standard" }, rod = { "standard" }, bench = { "standard" }, hydro = { "standard" },
    fence = { "standard" }, cooler = { "standard" }, heater = { "standard" }, windspin = THREE,
}
P.STATES = {
    array = { "clear", "snow", "cracked" },
    controller = { "off", "on" },
    transformer = { "off", "on" },
    lamp = { "off", "on" },
    pedal = { "off", "on" },                                   -- someone riding it
    windmill = { "still", "turning", "furled", "broken" },
    steam = { "cold", "warming", "running", "broken" },
    windsock = { "limp", "half", "full" },                     -- how far the sock stands out
    vane = { "set" },                                          -- facing is all it shows
    propane = { "off", "running", "broken" },
    petrol = { "off", "running", "broken" },
    gauge = { "off", "low", "mid", "full" },                   -- the system's charge at a glance
    rod = { "set" },
    bench = { "off", "on" },                                   -- charging something
    hydro = { "still", "turning" },                            -- water under the wheel
    fence = { "off", "on" },                                   -- live wire
    cooler = { "off", "on" },                                  -- cooling its room
    heater = { "off", "on" },                                  -- switched on and powered
    windspin = { "spin1", "spin2", "spin3", "spin4", "wobble" }, -- blade positions of a turning windmill, and a broken one rocking
    -- bank has no flat list: see P.statesFor.
}
-- The 2x2 array is four sprites per facing: pieces 1..4 = NW, NE, SW, SE of its footprint; piece 1 is the
-- MASTER that carries the state and the item. Every other part is one square.
P.PIECES = { array = { xl = 4 } }
function P.piecesOf(kind, mount)
    local byMount = P.PIECES[kind]
    return byMount and byMount[mount] or 1
end
-- Where piece p stands from the master: { dx, dy }.
P.PIECE_OFFSET = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }

-- The power sources Dazed Power brought, and the two wind instruments that are parts but never wire or tick.
P.SOURCE_KINDS = { pedal = true, windmill = true, steam = true, propane = true, petrol = true, hydro = true }
-- A grounding rod is never wired and never ticks; it only protects a controller from lightning by standing near it.
P.PASSIVE = { rod = true }
P.INSTRUMENT = { windsock = true, vane = true }
P.GAS_ENGINE = { propane = true, petrol = true }

--- How many cells each bank grade holds, by mount. Mirrors dp_taxonomy.BANK_CELLS and M.bankCells.
P.BANK_CELLS = {
    ground = { makeshift = 3, salvaged = 6, workshop = 8 },
    wall   = { makeshift = 2, salvaged = 3, workshop = 4 },
}

--- The sprite states one exact object has. A battery rack shows what is IN it, so its states are its
--  possible cell counts, c0 through cN. Everything else keeps a flat list per kind.
function P.statesFor(kind, mount, tier)
    if kind ~= "bank" then return P.STATES[kind] end
    local out = {}
    local n = (P.BANK_CELLS[mount] or {})[tier] or 0
    for i = 0, n do out[#out + 1] = "c" .. i end
    return out
end

-- Sprite-only kinds that draw another kind in motion. Their rows read back as that kind, so a frame left on an object
-- (a single-player save mid-spin) is still a windmill everywhere; `frame` names the row's own state.
P.ALIAS = {
    windspin = { kind = "windmill", state = { spin1 = "turning", spin2 = "turning", spin3 = "turning",
                                              spin4 = "turning", wobble = "broken" } },
}

--- Build the row table in exactly the order dp_taxonomy.py emits it.
local function buildRows()
    local rows = {}
    for _, kind in ipairs(P.KINDS) do
        for _, mount in ipairs(P.MOUNTS[kind]) do
            for _, tier in ipairs(P.TIERS[kind]) do
                for _, state in ipairs(P.statesFor(kind, mount, tier)) do
                    local alias = P.ALIAS[kind]
                    if alias then
                        rows[#rows + 1] = { kind = alias.kind, mount = mount, tier = tier, state = alias.state[state],
                                            frame = state, piece = 1 }
                    else
                        for piece = 1, P.piecesOf(kind, mount) do
                            rows[#rows + 1] = { kind = kind, mount = mount, tier = tier, state = state, piece = piece }
                        end
                    end
                end
            end
        end
    end
    return rows
end

P.ROWS = buildRows()

-- Reverse index: "kind|mount|tier|state|piece" -> row number (1-based).
P.ROW_OF = {}
-- A frame row is keyed by its frame name ("windmill|ground|salvaged|spin2|1"), so it never shadows the real state.
for i, r in ipairs(P.ROWS) do
    P.ROW_OF[r.kind .. "|" .. r.mount .. "|" .. r.tier .. "|" .. (r.frame or r.state) .. "|" .. r.piece] = i
end

--- The item handed to IsoGenerator.new for each controller tier and facing. One record per combination,
--  because getGeneratorSpriteToType() keys its map on a single WorldObjectSprite per item, and a facing that
--  misses the map falls through to Base.Generator and its radius-20 world sound. The running state needs
--  records too: the controller swaps sprite when it starts working.
P.CONTROLLER_ITEM = {
    makeshift = { E = "Base.DazedControllerMakeshiftE", S = "Base.DazedControllerMakeshift",
                  W = "Base.DazedControllerMakeshiftW", N = "Base.DazedControllerMakeshiftN" },
    workshop  = { E = "Base.DazedControllerWorkshopE", S = "Base.DazedControllerWorkshop",
                  W = "Base.DazedControllerWorkshopW", N = "Base.DazedControllerWorkshopN" },
}
P.CONTROLLER_ITEM_ON = {
    makeshift = { E = "Base.DazedControllerMakeshiftOnE", S = "Base.DazedControllerMakeshiftOn",
                  W = "Base.DazedControllerMakeshiftOnW", N = "Base.DazedControllerMakeshiftOnN" },
    workshop  = { E = "Base.DazedControllerWorkshopOnE", S = "Base.DazedControllerWorkshopOn",
                  W = "Base.DazedControllerWorkshopOnW", N = "Base.DazedControllerWorkshopOnN" },
}

--- The inventory item behind each (kind, mount, tier). Mirrors dp_taxonomy.ITEM, which stamps CustomItem
--  into the tiledef.
P.ITEM = {
    array = {
        ground  = { makeshift = "Base.DazedArrayMakeshift", salvaged = "Base.DazedArraySalvaged", workshop = "Base.DazedArrayWorkshop" },
        tracker = { makeshift = "Base.DazedTrackerMakeshift", salvaged = "Base.DazedTrackerSalvaged", workshop = "Base.DazedTrackerWorkshop" },
        xl      = { makeshift = "Base.DazedArrayXLMakeshift", salvaged = "Base.DazedArrayXLSalvaged", workshop = "Base.DazedArrayXLWorkshop" },
    },
    bank = {
        ground = { makeshift = "Base.DazedBankMakeshift", salvaged = "Base.DazedBankSalvaged", workshop = "Base.DazedBankWorkshop" },
        wall   = { makeshift = "Base.DazedWallBankMakeshift", salvaged = "Base.DazedWallBankSalvaged", workshop = "Base.DazedWallBankWorkshop" },
    },
    controller = { ground = { makeshift = "Base.DazedControllerMakeshift", workshop = "Base.DazedControllerWorkshop" } },
    transformer = { ground = { standard = "Base.DazedTransformer" } },
    lamp = {
        garden = { makeshift = "Base.DazedGardenLampMakeshift", workshop = "Base.DazedGardenLampWorkshop" },
        street = { makeshift = "Base.DazedStreetLampMakeshift", workshop = "Base.DazedStreetLampWorkshop" },
    },
    pedal = { ground = { makeshift = "Base.DazedPedalMakeshift", salvaged = "Base.DazedPedalSalvaged", workshop = "Base.DazedPedalWorkshop" } },
    windmill = { ground = { makeshift = "Base.DazedWindMakeshift", salvaged = "Base.DazedWindSalvaged", workshop = "Base.DazedWindWorkshop" } },
    steam = { ground = { makeshift = "Base.DazedSteamMakeshift", salvaged = "Base.DazedSteamSalvaged", workshop = "Base.DazedSteamWorkshop" } },
    windsock = { ground = { basic = "Base.DazedWindsock" } },
    vane = { ground = { basic = "Base.DazedWeatherVane" } },
    propane = { ground = { makeshift = "Base.DazedPropaneMakeshift", salvaged = "Base.DazedPropaneSalvaged", workshop = "Base.DazedPropaneWorkshop" } },
    petrol = { ground = { makeshift = "Base.DazedPetrolMakeshift", salvaged = "Base.DazedPetrolSalvaged", workshop = "Base.DazedPetrolWorkshop" } },
    gauge = { wall = { standard = "Base.DazedPowerGauge" } },
    rod = { ground = { standard = "Base.DazedGroundingRod" } },
    bench = { ground = { standard = "Base.DazedChargerBench" } },
    hydro = { ground = { standard = "Base.DazedWaterWheel" } },
    fence = { ground = { standard = "Base.DazedElectricFence" } },
    cooler = { wall = { standard = "Base.DazedRoomCooler" } },
    heater = { ground = { standard = "Base.DazedSpaceHeater" } },
}

-- Items that are not world parts.
P.MANUAL, P.MANUAL_ADV, P.ALMANAC = "Base.DazedPowerManual", "Base.DazedPowerManualAdv", "Base.DazedAlmanac"
P.AMP_ITEM = "Base.DazedAmplifier"
P.GEAR_ITEM = { low = "Base.DazedGearKitLow", stock = "Base.DazedGearKitStock", racing = "Base.DazedGearKitRacing" }
P.GEAR_ORDER = { "low", "stock", "racing" }
function P.gearOfItem(fullType)
    for gear, item in pairs(P.GEAR_ITEM) do
        if item == fullType then return gear end
    end
    return nil
end

--- Every item record the mod declares, for the boot self-check.
function P.allItems()
    local out = {}
    for _, kind in ipairs(P.KINDS) do
        -- Animation-frame kinds have no item of their own.
        if not P.ALIAS[kind] then
            for _, mount in ipairs(P.MOUNTS[kind]) do
                for _, tier in ipairs(P.TIERS[kind]) do
                    out[#out + 1] = P.ITEM[kind][mount][tier]
                    if kind == "controller" then
                        for _, f in ipairs({ "E", "W", "N" }) do out[#out + 1] = P.CONTROLLER_ITEM[tier][f] end
                        for _, f in ipairs(P.FACINGS) do out[#out + 1] = P.CONTROLLER_ITEM_ON[tier][f] end
                    end
                end
            end
        end
    end
    for _, it in ipairs({ P.MANUAL, P.MANUAL_ADV, P.ALMANAC, P.AMP_ITEM }) do out[#out + 1] = it end
    for _, gear in ipairs(P.GEAR_ORDER) do out[#out + 1] = P.GEAR_ITEM[gear] end
    return out
end

--- The item a placed object corresponds to, or nil.
function P.itemFor(kind, mount, tier)
    local byMount = P.ITEM[kind]
    local byTier = byMount and byMount[mount or "ground"]
    return byTier and byTier[tier] or nil
end

-------------------------------------------------------------------- sprites

--- Sprite name for a variant (piece 1 unless asked), or nil if that combination does not exist.
function P.sprite(kind, mount, tier, state, facing, piece)
    local row = P.ROW_OF[kind .. "|" .. (mount or "ground") .. "|" .. tier .. "|" .. state .. "|" .. (piece or 1)]
    if not row then return nil end
    local fi = P.FACING_INDEX[facing or "S"] or 1
    return P.spriteName((row - 1) * P.COLS + fi)
end

-- Sheet index -> decoded info; the sheet is fixed, so each entry is built once.
local infoMemo = {}

--- Decompose one of the mod's sprite names, or nil if it is not ours. Anything but a string is not ours
--  (Kahlua's string.match raises on a userdata). `pieces` is how many squares the part covers and `master`
--  whether this is the one that carries its state.
--  The table is shared per sheet index: read it, never change it.
function P.spriteInfo(name)
    local idx = P.indexOf(name)
    if not idx then return nil end
    local hit = infoMemo[idx]
    if hit then return hit end
    local r = P.ROWS[math.floor(idx / P.COLS) + 1]
    if not r then return nil end
    local pieces = P.piecesOf(r.kind, r.mount)
    hit = { kind = r.kind, mount = r.mount, tier = r.tier, state = r.state,
            facing = P.FACINGS[(idx % P.COLS) + 1], index = idx,
            piece = r.piece, pieces = pieces, master = (r.piece == 1), frame = r.frame }
    infoMemo[idx] = hit
    return hit
end

--- Everything the mod knows about an object, or nil if it is not one of ours.
--
--  Sprite name first, ModData as the fallback. The fallback is not paranoia:
--  `IsoObject.new(square, tile)` -- the two-argument form -- does NOT use the
--  named sprite. It calls IsoSprite.CreateSprite + LoadFramesNoDirPageSimple
--  and builds an anonymous one (IsoObject.java:361-367), so the object renders
--  perfectly while getSprite():getName() comes back nil.
function P.describe(obj)
    if not obj or not obj.getSprite then return nil end
    local spr = obj:getSprite()
    if spr then
        local name = spr:getName()
        local info = P.spriteInfo(name)
        if info then return info end
        -- Rubble, not a part. A fire swaps a burning solidtrans object's
        -- sprite for a *_burnt_* one and KEEPS the object and its ModData
        -- (IsoGridSquare.BurnWalls), which is what happens to a seeded yard
        -- rig. The fallback below would still see the kind stamped in its
        -- ModData, so the ash went on generating, and the next state change
        -- put the panel's sprite back. The engine's own test for rubble.
        if name and string.find(name, "_burnt_", 1, true) then return nil end
    end
    -- getModData builds an empty table on every object it is asked of, so a square scan would leave one on each.
    if obj.hasModData and not obj:hasModData() then return nil end
    local md = obj.getModData and obj:getModData()
    local d = md and md.dazedpower
    if d and d.kind then
        -- "off" is not a bank state any more; banks are counted, c0 up.
        return { kind = d.kind, mount = d.mount or "ground",
                 tier = d.tier or "salvaged",
                 state = d.state or (d.kind == "bank" and "c0" or "off"),
                 facing = d.facing or "S", piece = 1, pieces = P.piecesOf(d.kind, d.mount or "ground"), master = true }
    end
    return nil
end

function P.partOf(obj)
    local info = P.describe(obj)
    return info and info.kind or nil
end

--- A controller tile on something that is not a controller: scenery.
--
--  A real controller is always an IsoGenerator (G.makeController builds one
--  for every placement). The admin Brush Tool paints a bare IsoObject with a
--  controller's sprite, and a map could carry one; S.register never counts
--  it, and the menus grey its rows with the reason (2026-09-29: "Say
--  it's scenery"). Where the engine's instanceof is absent (a headless
--  check) nothing is taken for paint.
function P.isPainted(obj)
    if P.partOf(obj) ~= "controller" then return false end
    if not instanceof then return false end
    return not instanceof(obj, "IsoGenerator")
end

--- The running generators on a square: the first one that is NOT a Dazed Power
--  controller (or nil), and whether a running controller is there too.
--
--  Every generator on the square, not getGenerator(), which returns only the
--  first: nothing stops two sharing a tile, and the engine marks a building
--  toxic for each of them. A generator is a special object
--  (IsoGridSquare.getSpecialObjects); instanceof filters out the light
--  switches and appliances in the same list that also answer isActivated().
function P.generatorsOn(sq)
    if not sq then return nil, false end
    local list = sq:getSpecialObjects()
    local ours = false
    for i = 0, list:size() - 1 do
        local o = list:get(i)
        if o and instanceof(o, "IsoGenerator") and o:isActivated() then
            if P.partOf(o) == "controller" then
                ours = true
            else
                return o, ours
            end
        end
    end
    -- A running propane or petrol generator under a roof is real fumes: answer for it with a small stand-in
    -- carrying the two methods callers use.
    local objs = sq.getObjects and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        local o = objs:get(i)
        local info = P.describe(o)
        if info and P.GAS_ENGINE[info.kind] then
            local d = o:getModData().dazedpower
            if d and d.running == true and d.indoors then
                return { obj = o,
                         isActivated = function() local dd = o:getModData().dazedpower return dd ~= nil and dd.running == true end,
                         getObjectIndex = function() return o:getObjectIndex() end }, ours
            end
        end
    end
    return nil, ours
end

--- The Dazed Power object of a given kind standing on a square, or nil.
--
--  A wiring edge is a pair of coordinates, so both sides of the mod need to
--  turn a coordinate back into the thing that is standing there. Returns nil
--  for a square that is not streamed in, which callers that care about the
--  difference between "gone" and "not loaded" have to resolve themselves.
function P.objectAt(x, y, z, kind)
    local sq = getSquare(x, y, z)
    if not sq then return nil end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if P.partOf(o) == kind then return o end
    end
    return nil
end

function P.facingOf(obj)
    local info = P.describe(obj)
    return info and info.facing or "S"
end

--- Is this table empty? PZ's Kahlua has no global `next` (nor xpcall,
--  loadstring, table.getn, math.random...), so the usual `next(t) == nil`
--  idiom throws "tried to call nil" in game while passing on stock Lua.
function P.isEmpty(t)
    for _ in pairs(t) do return false end
    return true
end

-- Sort keys of any type the same way every time.
local function keyLess(a, b) return tostring(a) < tostring(b) end

--- A string that changes whenever a ModData table does: every field exactly, except the top-level
--  numbers named in `steps` (field -> step), which only count once they move by a step.
function P.dataSig(t, steps)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, keyLess)
    local out = {}
    for i = 1, #keys do
        local k = keys[i]
        local v = t[k]
        local q = steps and type(v) == "number" and steps[k]
        if q then v = math.floor(v / q + 0.5) end
        if type(v) == "table" then
            out[i] = tostring(k) .. "={" .. P.dataSig(v) .. "}"
        else
            out[i] = tostring(k) .. "=" .. type(v) .. ":" .. tostring(v)
        end
    end
    return table.concat(out, ";")
end

--- Is this object still standing on a square (listed at an index there)?
function P.alive(o)
    local ix = P.try(o, "getObjectIndex")
    return type(ix) == "number" and ix >= 0
end

-------------------------------------------------------------------- cells

--- Bring a rack's contents up to the per-cell shape.
--
--  Before this release a rack stored a list of type strings plus ONE health
--  for the whole rack, so a battery's own condition was destroyed on the way
--  in and invented at full on the way out. A cell now carries its own health,
--  which IS the car battery's condition over its ConditionMax, and the rack's
--  health is the mean of its cells.
--
--  Every migrated cell inherits the rack's stored health, so capacity comes
--  out at exactly the old number and nobody's rack moves under them on update.
--  A very old save with a count but no cellTypes fills with CarBattery1, which
--  is what the removal path already used as its fallback.
function P.migrateCells(d)
    if d.cellList ~= nil then return false end
    local n = math.floor(d.cells or 0)
    if n < 0 then n = 0 end
    local health = d.health
    if health == nil then health = 1 end
    local types = d.cellTypes or {}
    local list = {}
    for i = 1, n do
        list[i] = { id = i, type = types[i] or "Base.CarBattery1",
                    health = health }
    end
    d.cellList = list
    d.nextCellId = n + 1
    -- Both are gone for good. d.health is now derived by P.bankHealth, and
    -- leaving a stale copy behind is exactly how a reader ends up silently
    -- using a number nothing maintains.
    d.cellTypes = nil
    d.health = nil
    return true
end

--- The rack's health: the mean of its cells.
--
--  An empty rack reads 1, because there is nothing in it to be damaged. The
--  damage lives in the batteries and leaves with them, which is the whole
--  point of the per-cell shape.
function P.bankHealth(d)
    local list = d.cellList
    if not list or #list == 0 then return 1 end
    return DazedPower.Model.cellSum(list) / #list
end

--- The rack's best possible health: the mean of what its cells can still recover to.
function P.bankCeiling(d)
    local list = d.cellList
    if not list or #list == 0 then return 1 end
    local s = 0
    for i = 1, #list do s = s + DazedPower.Model.healthCeiling(list[i]) end
    return s / #list
end

--- Wear every cell of a rack by `delta` for good, and pull its health down to the new ceiling.
function P.ageBank(d, delta)
    local M = DazedPower.Model
    local list = d.cellList or {}
    if delta <= 0 then return end
    for i = 1, #list do
        local c = list[i]
        c.wear = M.clamp((c.wear or 0) + delta, 0, M.MAX_WEAR)
        local ceil = M.healthCeiling(c)
        if (c.health or 1) > ceil then c.health = ceil end
    end
end

--- Summed cell health, which is what capacity is actually proportional to.
function P.cellSum(d)
    return DazedPower.Model.cellSum(d.cellList)
end

--- The cell carrying this id, or nil. Positions shift when a cell is pulled,
--  so nothing outside the panel's own draw loop should key on an index.
function P.findCell(d, cellId)
    if cellId == nil then return nil end
    local list = d.cellList or {}
    for i = 1, #list do
        if list[i].id == cellId then return list[i], i end
    end
    return nil
end

--- Which bay each cell sits in: bays[1..cap] = cell, or nil for an empty bay.
--
--  A cell keeps the bay it was dropped on (cell.bay). Listed in order with
--  the bays compacted, a battery dropped on bay 2 of an empty rack showed in
--  bay 1, and bay 2, still under the pointer, said "Empty bay" (live test,
--  2026-09-14). A cell with no bay, or with one out of range or already
--  taken, fills the first empty bay in list order, which is exactly the
--  layout every rack had before, so a rack from an older save opens as it
--  always did. Removal stays keyed on the cell id; the bay is only where it
--  is drawn.
function P.bayLayout(list, cap)
    local bays, loose = {}, {}
    list = list or {}
    for i = 1, #list do
        local c, b = list[i], list[i].bay
        if type(b) == "number" and b >= 1 and b <= cap and b == math.floor(b)
                and not bays[b] then
            bays[b] = c
        else
            loose[#loose + 1] = c
        end
    end
    local n = 1
    for i = 1, #loose do
        while bays[n] do n = n + 1 end
        if n > cap then break end
        bays[n] = loose[i]
    end
    return bays
end

--- Write down the bay every cell is drawn in, before the rack changes.
--
--  A cell from an older save has no bay and sits where list order puts it,
--  so taking the cell before it out would slide it one bay left. Pinned
--  first, every battery stays where the player saw it.
function P.pinBays(list, cap)
    local bays = P.bayLayout(list, cap)
    for b = 1, cap do
        if bays[b] then bays[b].bay = b end
    end
end

--- The bay a battery goes into: the one it was dropped on while that is
--  free, else the first free one (somebody filled it while the action ran, or
--  the drop named no bay). Nil when the rack is full.
function P.freeBay(list, cap, wanted)
    local bays = P.bayLayout(list, cap)
    if type(wanted) == "number" and wanted >= 1 and wanted <= cap
            and wanted == math.floor(wanted) and not bays[wanted] then
        return wanted
    end
    for b = 1, cap do
        if not bays[b] then return b end
    end
    return nil
end

--- Apply one tick's health delta to every cell in the rack.
--
--  Returns the MEAN delta actually achieved, which is not always the delta
--  asked for: a cell already at 1.0 absorbs none of a recovery, and the
--  equalise biller pays only for what landed. The 0.25 floor never LIFTS a
--  cell -- a battery installed at 8% condition is an 8% cell, and the old
--  unconditional clamp quietly healed it to 25% on the first tick that
--  touched the rack.
function P.applyBankHealth(d, delta)
    local list = d.cellList or {}
    if #list == 0 then return 0 end
    local before = P.bankHealth(d)
    for i = 1, #list do
        local h = list[i].health or 1
        local lo = math.min(0.25, h)
        list[i].health = DazedPower.Model.clamp(h + delta, lo, DazedPower.Model.healthCeiling(list[i]))
    end
    return P.bankHealth(d) - before
end

-------------------------------------------------------------------- state

--- Per-object persisted state, with defaults filled in on first touch.
--  IsoObject ModData is written into the chunk save, so this survives a
--  reload without the mod keeping a registry of its own.
-- The schema of a part's ModData (DazedCore.Migrate). Raise it and add a step to P.MIGRATIONS whenever a
-- release changes what a part stores; step n turns version n-1 data into version n.
P.SCHEMA = 1
P.MIGRATIONS = {}

function P.data(obj)
    local md = obj:getModData()
    if md.dazedpower == nil then md.dazedpower = {} end
    local d = md.dazedpower
    -- Upgraded on the authority only: a client's copy is replaced by the server's next sync anyway.
    if (d._v or 0) < P.SCHEMA and not isClient() then
        local Mig = DazedCore and DazedCore.Migrate
        if Mig then
            d = Mig.upgrade(d, P.SCHEMA, P.MIGRATIONS)
            md.dazedpower = d
        else
            d._v = P.SCHEMA
        end
    end
    local info = P.describe(obj)
    if not info then return d end

    -- remember the identity, so an object whose sprite went anonymous is
    -- still recognised on the next pass
    d.kind = info.kind
    d.mount = info.mount
    d.tier = info.tier
    d.facing = info.facing
    if d.state == nil then d.state = info.state end

    if info.kind == "array" then
        if d.panels == nil then
            -- the 2x2 array is four frames' worth of modules on one master
            d.panels = DazedPower.Model.baseArraySpec(info.tier).panels * (info.mount == "xl" and 4 or 1)
        end
        if d.soiling == nil then d.soiling = 0 end
        if d.snow == nil then d.snow = 0 end
        if d.condition == nil then d.condition = 100 end
    elseif info.kind == "bank" then
        if d.charge == nil then d.charge = 0 end
        P.migrateCells(d)
        -- ONE authority for the count. Everything downstream reads d.cells on
        -- the hot path and d.cellList for the detail, and they cannot drift
        -- because the count is derived here on every touch.
        d.cells = #d.cellList
    elseif info.kind == "controller" then
        if d.online == nil then d.online = false end
        if d.lastHour == nil then d.lastHour = -1 end
        if d.load == nil then d.load = 0 end
        if d.trip == nil then d.trip = false end
    elseif P.SOURCE_KINDS[info.kind] or P.INSTRUMENT[info.kind] then
        if d.condition == nil then d.condition = 100 end
        if info.kind == "pedal" then
            if d.gear == nil then d.gear = "stock" end
            if d.pedalHeartbeat == nil then d.pedalHeartbeat = 0 end
            if d.pedalWatts == nil then d.pedalWatts = 0 end
        elseif info.kind == "windmill" then
            if d.windWatts == nil then d.windWatts = 0 end
        elseif info.kind == "steam" then
            if d.fuel == nil then d.fuel = 0 end
            if d.water == nil then d.water = 0 end
            if d.heat == nil then d.heat = 0 end
            if d.lit == nil then d.lit = false end
        elseif P.GAS_ENGINE[info.kind] then
            -- the switch, the reservoir (propane kg, petrol litres) and the auto-start level
            if d.mode == nil then d.mode = "off" end
            if d.lpg == nil then d.lpg = 0 end
            if d.startPct == nil then
                local MM = DazedPower.More and DazedPower.More.Model
                d.startPct = MM and MM.PROPANE_START_SOC or 0.3
            end
        elseif info.kind == "vane" then
            if d.vHours == nil then d.vHours = 0 end
        end
    end
    return d
end

--- What vanilla's moveable round trip leaves on a placed part's ModData.
--
--  Picking up an IsoThumpable saves its name, health, sound, colour, light
--  and padlock onto the item, and a deep copy of its whole ModData
--  (ISMoveableSpriteProps.saveThumpableParameters, 42.20.4 lines 1204-1231);
--  placing the item copies that copy's keys back onto the new object, and
--  then every key of the item's ModData, the copy itself included, when the
--  item carries no movableData (restoreThumpableParameters 1233-1253,
--  placeMoveableInternal 2241-2243 and 2273-2282). Racks and panels are
--  IsoThumpables and a rotation is a pick-up and a place, so every turn or
--  move stored the part's data one level deeper inside itself: 53, 82 and
--  111 entries after three turns of one rack (live test, 2026-09-14).
--  Nothing reads these keys off an object; the restore reads the item's own
--  copy. itemCondition is not listed, because a non-thumpable pick-up reads
--  it back (1310-1312), and neither is anything another mod wrote.
P.VANILLA_CARRIED = { "modData", "name", "health", "maxHealth", "thumpSound", "color",
                      "lightSource", "canBeLockedByPadlock", "lockedByKeyId",
                      "lockedByCode" }

--- Drop those keys from a Dazed Power part's ModData; a part the mod owns
--  only (one carrying an `dazedpower` table). Returns whether it removed any.
function P.scrubCarried(obj)
    local md = obj and obj.getModData and obj:getModData()
    if not md or type(md.dazedpower) ~= "table" then return false end
    local changed = false
    for i = 1, #P.VANILLA_CARRIED do
        local k = P.VANILLA_CARRIED[i]
        if md[k] ~= nil then
            md[k] = nil
            changed = true
        end
    end
    return changed
end

--- How many car batteries this particular bank can hold.
function P.cellCap(obj)
    local info = P.describe(obj)
    if not info or info.kind ~= "bank" then return 0 end
    return DazedPower.Model.bankCells(info.tier, info.mount)
end

--- Swap an object to the sprite for `state`, keeping kind, mount, tier and
--  facing. No-op if it is already showing it, because setSprite dirties the
--  chunk for a resave.
function P.setState(obj, state, facing)
    if not obj then return false end
    local info = P.describe(obj)
    if not info then return false end
    facing = facing or info.facing
    if info.pieces > 1 then return P.setPiecesState(obj, info, state, facing) end
    local want = P.sprite(info.kind, info.mount, info.tier, state, facing)
    if not want then return false end
    local cur = obj:getSprite() and obj:getSprite():getName()
    if cur == want then return false end
    -- BOTH calls, in this order, and neither is redundant.
    --
    -- setSprite(String) builds an ANONYMOUS sprite: IsoSprite.CreateSprite +
    -- LoadSingleTexture, so getSprite():getName() comes back nil afterwards.
    -- It is still wanted, because it is also what sets the object's `tile` and
    -- `spriteName` fields, which the network path and re-identification use.
    --
    -- Corrected 2026-08-26: an earlier note here claimed `spriteName` is what
    -- IsoObject.save writes. It is not. save() writes the sprite's numeric id
    -- (`output.putInt(this.sprite == null ? -1 : this.sprite.id)`,
    -- IsoObject.java:1315), which is why setSpriteFromName below is the call
    -- that actually decides what persists: it swaps in the REGISTERED sprite
    -- out of IsoSpriteManager, and only a registered sprite has a usable id.
    -- Do not drop it on the grounds that setSprite already set the name.
    --
    -- setSpriteFromName(String) then swaps that anonymous sprite for the
    -- registered one out of IsoSpriteManager, which restores the name. That
    -- matters far beyond cosmetics: IsoGenerator.getGeneratorItemType() looks
    -- the CURRENT sprite name up in getGeneratorSpriteToType(), and a miss
    -- returns "Base.Generator" -- whose SoundRadius is 20. A controller with a
    -- nameless sprite is a controller that broadcasts a petrol generator's
    -- world sound, which is the one thing this mod exists not to do.
    obj:setSprite(want)
    if obj.setSpriteFromName then obj:setSpriteFromName(want) end
    local md = obj.getModData and obj:getModData()
    if md then
        md.dazedpower = md.dazedpower or {}
        md.dazedpower.kind = info.kind
        md.dazedpower.mount = info.mount
        md.dazedpower.tier = info.tier
        md.dazedpower.facing = facing
        md.dazedpower.state = state
    end
    if obj.transmitUpdatedSpriteToClients and isServer() then
        obj:transmitUpdatedSpriteToClients()
    end
    return true
end

--- The pieces of a multi-square part, master first: { [piece] = object }, for the ones whose squares are loaded.
function P.piecesAround(obj, info)
    info = info or P.describe(obj)
    local out = {}
    local sq = obj and obj:getSquare()
    if not (info and sq) then return out end
    local mo = P.PIECE_OFFSET[info.piece or 1]
    local mx, my, z = sq:getX() - mo[1], sq:getY() - mo[2], sq:getZ()
    for piece = 1, info.pieces do
        local o = P.PIECE_OFFSET[piece]
        local s2 = getSquare(mx + o[1], my + o[2], z)
        local objs = s2 and s2:getObjects()
        for i = 0, (objs and objs:size() or 0) - 1 do
            local cand = objs:get(i)
            local ci = P.describe(cand)
            if ci and ci.kind == info.kind and ci.mount == info.mount and ci.piece == piece then out[piece] = cand end
        end
    end
    return out
end

--- The master piece of a multi-square part (itself for a one-square part), or nil if its square is not loaded.
function P.master(obj)
    local info = P.describe(obj)
    if not info then return nil end
    if info.pieces == 1 or info.master then return obj end
    return P.piecesAround(obj, info)[1]
end

--- State and facing for every piece of a multi-square part at once.
function P.setPiecesState(obj, info, state, facing)
    local changed = false
    for piece, o in pairs(P.piecesAround(obj, info)) do
        local want = P.sprite(info.kind, info.mount, info.tier, state, facing, piece)
        local cur = want and o:getSprite() and o:getSprite():getName()
        if want and cur ~= want then
            o:setSprite(want)
            if o.setSpriteFromName then o:setSpriteFromName(want) end
            local md = o.getModData and o:getModData()
            if md then
                md.dazedpower = md.dazedpower or {}
                md.dazedpower.kind, md.dazedpower.mount, md.dazedpower.tier = info.kind, info.mount, info.tier
                md.dazedpower.facing, md.dazedpower.state = facing, state
            end
            if o.transmitUpdatedSpriteToClients and isServer() then o:transmitUpdatedSpriteToClients() end
            changed = true
        end
    end
    return changed
end

--- Which bank sprite a rack should be showing: the one with its cell count.
--
--  `soc` is no longer part of it. The sprite carries how many batteries are in
--  the rack, which is the thing worth seeing from across a room, and the charge
--  is on the controller's monitor and in the Info panel to the nearest per cent.
function P.bankState(d, soc)
    local n = math.floor(d.cells or 0)
    if n < 0 then n = 0 end
    -- Clamp to what this grade holds. Over capacity should be impossible, but
    -- a state with no sprite makes P.setState a silent no-op, so the rack
    -- would quietly stop tracking its own contents rather than say anything.
    local cap = (P.BANK_CELLS[d.mount or ""] or {})[d.tier or ""]
    if cap and n > cap then n = cap end
    return "c" .. n
end

--- Which array sprite an array should be showing.
function P.arrayState(d)
    if (d.snow or 0) >= 0.15 then return "snow" end
    if (d.condition or 100) <= 35 then return "cracked" end
    return "clear"
end

------------------------------------------------------------------ the world

--- Walk every square in a cube around a point, calling fn(square).
--  `zRange` is levels either side. Squares in unloaded chunks come back nil
--  and are skipped, which is the correct behaviour: the mod should not
--  simulate what the engine is not streaming.
function P.forEachSquare(x, y, z, radius, zRange, fn)
    local r2 = radius * radius
    for dz = -zRange, zRange do
        local zz = z + dz
        if zz >= -32 and zz <= 31 then
            for dy = -radius, radius do
                for dx = -radius, radius do
                    if dx * dx + dy * dy <= r2 then
                        local sq = getSquare(x + dx, y + dy, zz)
                        if sq then fn(sq) end
                    end
                end
            end
        end
    end
end

--- Every Dazed Power object of `kind` within `radius` of a square.
function P.findParts(square, radius, zRange, kind)
    local found = {}
    if not square then return found end
    P.forEachSquare(square:getX(), square:getY(), square:getZ(), radius, zRange,
        function(sq)
            local objs = sq:getObjects()
            for i = 0, objs:size() - 1 do
                local o = objs:get(i)
                if P.partOf(o) == kind then found[#found + 1] = o end
            end
        end)
    return found
end

---------------------------------------------------------------- inventory

--- A rack's cell as a car battery item, at `fill` charge and `cond`
--  condition (both 0..1). Nil only if not even a plain car battery can be
--  made. Every road a cell leaves a rack by comes through here: a battery
--  taken out by hand, a rack picked up, a rack destroyed.
--
--  A type that no longer resolves (a modded battery whose mod was removed)
--  comes back as Base.CarBattery1 at the same charge and condition. By the
--  time a cell becomes an item it is already out of the rack, so handing back
--  nothing would destroy both the battery and its share of the charge; this
--  keeps the value and loses only the branding.
--
--  setCurrentUsesFloat, not setUsedDelta: the pair is asymmetric on
--  InventoryItem (only the setter half of setUsedDelta exists, and only on
--  DrainableComboItem), so the mod uses the float accessors, which are
--  declared on the base class in both directions. See itemFill in DP_Actions.
function P.cellItem(batteryType, fill, cond, wear)
    local M = DazedPower.Model
    local wanted = batteryType or "Base.CarBattery1"
    local item = instanceItem(wanted)
    if not item and wanted ~= "Base.CarBattery1" then
        print("DazedPower: cell type " .. tostring(wanted)
              .. " no longer exists, substituting Base.CarBattery1")
        item = instanceItem("Base.CarBattery1")
    end
    if not item then return nil end
    if item.setCurrentUsesFloat then
        item:setCurrentUsesFloat(M.clamp(fill or 0, 0, 1))
    end
    if item.setCondition and cond ~= nil then
        local maxC = item.getConditionMax and item:getConditionMax() or 100
        item:setCondition(math.floor(M.clamp(cond, 0, 1) * maxC + 0.5))
    end
    if wear and wear > 0 and item.getModData then item:getModData().dazedWear = wear end
    return item
end

--- The wear a battery item carries from an earlier rack, 0..1.
function P.itemWear(item)
    local md = item and item.getModData and item:getModData()
    return DazedPower.Model.clamp(md and md.dazedWear or 0, 0, DazedPower.Model.MAX_WEAR)
end

--- Does this character have a screwdriver, counting bags and modded ones?
--
--  ONE copy of this, on purpose. It existed twice and the copies drifted: the
--  pickup gate passed `ItemTag.SCREWDRIVER` while the repair context menu
--  passed the string `"Screwdriver"`, which threw
--
--      expected argument of type ItemTag, got String
--
--  the moment a player right-clicked a damaged part while carrying both scrap
--  and screws. That is the `elseif` branch of the repair option, which is why
--  it took until a subscriber found it.
--
--  There has never been a String overload to lean on: 42.20.2 already declared
--  only `containsTagRecurse(zombie.scripting.objects.ItemTag)`, so this was
--  wrong long before 42.20.4 and is not a regression from that update. The
--  string is seductive precisely because it IS the tag's name --
--  `SCREWDRIVER = registerBase("Screwdriver")` -- but the name is not the
--  argument.
--
--  ItemTag's statics are assigned in the class initialiser, so they are
--  populated well before Lua expose and `ItemTag.SCREWDRIVER` is reliable. The
--  guard and the plain-type fallback stay regardless: this decides whether
--  someone may repair their own kit, and failing open beats locking them out.
--
--  Returns false when there is no inventory to read. The pickup gate wants the
--  opposite in that case, so it keeps its own `if not inv then return true end`
--  ahead of this call rather than pushing that policy in here.
function P.hasScrewdriver(character)
    if not character then return false end
    local ok, inv = pcall(function() return character:getInventory() end)
    if not ok or not inv then return false end

    if ItemTag and ItemTag.SCREWDRIVER and inv.containsTagRecurse then
        local okTag, has = pcall(inv.containsTagRecurse, inv, ItemTag.SCREWDRIVER)
        if okTag then return has == true end
    end

    local okType, hasType = pcall(inv.contains, inv, "Screwdriver")
    return okType and hasType == true
end

--------------------------------------------------------------------- text

--- getText with positional {1}/{2} substitution.
--
--  A correction to an earlier revision of this comment: `getText(key, a, b)`
--  DOES substitute. The Lua global is genuinely varargs
--  (LuaManager.java:7174) and %1..%9 are the engine's own placeholder syntax,
--  rewritten to %1$s by Translator.formatFixer at load time
--  (Translator.java:167, :895), for mod translation directories too. The old
--  claim came from testing a string that carried no placeholder in the
--  engine's syntax at all, so nothing substituted and the wrong lesson stuck.
--
--  Brace tokens are kept anyway because they also work -- Java's formatter
--  ignores them, so getText returns them untouched and the substitution
--  happens here -- and because 244 shipped strings is a lot of churn for a
--  change no player would see. What IS still true and still load-bearing:
--  a bare per-cent throws UnknownFormatConversionException, because
--  FORMAT_TOKEN matches only %% and %1..%9. build_translations escapes them.
--  Braces are not Lua pattern metacharacters either, so gsub takes them as-is.
function P.txt(key, ...)
    local s = getText(key)
    if s == nil then return tostring(key) end
    for i = 1, select("#", ...) do
        local v = tostring((select(i, ...)))
        -- gsub reads % in the REPLACEMENT as a capture reference and throws
        -- "invalid use of '%'", so anything heading into one gets escaped.
        v = string.gsub(v, "%%", "%%%%")
        s = string.gsub(s, "{" .. i .. "}", v)
    end
    return s
end

--- The colour a refusal note is drawn in above the character: orange-red,
--  one constant for every refusal Dazed Power shows (2026-09-29, "Red/
--  orange (Recommended)", over the game's default green). A note that is
--  news, not a refusal, keeps the game's own colour. NOTE_TIME is the
--  engine's own display time (IsoGameCharacter.haloDispTime, 128), which
--  the coloured overload sets for every later note too, so it is passed
--  unchanged.
P.NOTE_WARN = { r = 255, g = 96, b = 48 }
P.NOTE_TIME = 128

--- Put `text` above a character, as a refusal (`warn`, in P.NOTE_WARN) or
--  as news (the game's colour). The one place the mod calls setHaloNote:
--  setHaloNote(String, int, int, int, float) is on ILuaGameCharacter in
--  42.20.4 and 42.21 alike (tools/.jarindex-*.json), and vanilla's own
--  moveables call it that way (ISMoveableSpriteProps.lua).
function P.haloNote(character, text, warn)
    if not character or not character.setHaloNote or text == nil then return end
    if warn then
        local c = P.NOTE_WARN
        character:setHaloNote(tostring(text), c.r, c.g, c.b, P.NOTE_TIME)
    else
        character:setHaloNote(tostring(text))
    end
end

--- A counted phrase: "1 bank", "2 banks".
--
--  English needs the singular after 1, and a key holding "{1} banks" printed
--  "1 banks" on the Info card (live test, 2026-09-14). So every counted key
--  has a twin ending in One, picked when the count is exactly 1. Turkish
--  never puts a noun in the plural after a number ("1 akü", "3 akü"), so its
--  One key carries the same words as the other. The count picks the key; the
--  arguments fill it, the count alone when none are given.
function P.count(key, n, ...)
    local k = (n == 1) and (key .. "One") or key
    if select("#", ...) > 0 then return P.txt(k, ...) end
    return P.txt(k, n)
end

--- "3 arrays, 1 module": a system's arrays and the modules they carry.
function P.arrayLine(arrays, modules)
    return P.txt("IGUI_DazedPower_ArrayLine",
                 P.count("IGUI_DazedPower_ArrayCount", arrays or 0),
                 P.count("IGUI_DazedPower_ModuleCount", modules or 0))
end

-- North is -y and east is +x (IsoDirections.java:9-16, N is (0, -1)), the
-- compass the in-game map is drawn to and the one a panel's facing names.
local TOWARD = {
    north = "IGUI_DazedPower_DirNorth", south = "IGUI_DazedPower_DirSouth",
    east = "IGUI_DazedPower_DirEast", west = "IGUI_DazedPower_DirWest",
    up = "IGUI_DazedPower_DirUp", down = "IGUI_DazedPower_DirDown",
}

--- How to get from one square to another: "1 tile south, 3 tiles east,
--  1 floor up", or "same tile".
--
--  Whole tiles along each axis, not a straight-line distance. A row of
--  arrays three tiles east of a controller is three parts at the same
--  rounded distance and the same rough bearing, and the cut menu listed them
--  as the same "Solar Array" (live test, 2026-09-14). A connection is a node,
--  x,y,z,kind (M.nodeKey), and two parts of one name are one kind, so the
--  offset is what tells them apart. Levels count too: a controller on the
--  roof is not at the coordinates a player on the ground floor walks to.
function P.offsetText(fx, fy, fz, tx, ty, tz)
    local bits = {}
    local function add(n, plus, minus, floors)
        n = math.floor((n or 0) + 0.5)
        if n == 0 then return end
        local m = math.abs(n)
        bits[#bits + 1] = P.txt("IGUI_DazedPower_Toward",
                                floors and P.count("IGUI_DazedPower_FloorCount", m)
                                        or P.count("IGUI_DazedPower_TileCount", m),
                                getText(TOWARD[n > 0 and plus or minus]))
    end
    add((ty or 0) - (fy or 0), "south", "north")
    add((tx or 0) - (fx or 0), "east", "west")
    add((tz or 0) - (fz or 0), "up", "down", true)
    if #bits == 0 then return getText("IGUI_DazedPower_SameTile") end
    return table.concat(bits, ", ")
end

--- Translated one-word name for a tier, for the monitor's parts list.
function P.tierName(tier)
    return getText("IGUI_DazedPower_Tier_" .. tostring(tier))
end

return P
