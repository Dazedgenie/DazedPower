--[[ DazedPower -- some of the generators already on the map are Dazed ones.

     The map ships generators as plain tiles (appliances_misc_01_0..15) and
     vanilla's MOGenerator.lua turns each into a working IsoGenerator the first
     time its ground is generated. This file takes over those sixteen sprites
     and, for one tile in GenSwapChance, stands a Dazed petrol or propane
     generator there instead, with a makeshift controller on the square beside
     it, already wired. Kyle, 2026-10-21: the Dazed generators should turn up
     across the map in place of the default ones.

     COMPLETE OR VANILLA. A Dazed generator does not light the houses around it
     the way a vanilla one does; only a controller hands its power out. So a
     generator with no controller beside it would be a find nobody can use,
     and DP_Seed's rule holds here too: the pair is placed whole, or the tile
     becomes the vanilla generator it always was. No free square beside it,
     or a part that will not place, and the vanilla path runs.

     WHY THE SAME PRIORITY. MapObjects keeps one callback per sprite and
     priority, and registering at an equal priority replaces it (the same
     fact DUP_World.lua relies on). Registering at vanilla's 5 therefore
     takes the tile over instead of racing MOGenerator for it, and the vanilla
     branch below is MOGenerator's own code, so a tile that is not swapped
     comes out exactly as it would without this mod.

     The colour picks the engine: red and old become petrol, yellow and blue
     the propane standby set a house would have had. The old ones are the
     worn Makeshift grade; the rest are Salvaged, one in WORKSHOP_IN Workshop.
     Every roll is on the tile's own coordinates, so the same tile gives the
     same answer however often the question is asked. ]]

if isClient() then return end

require "DazedPower/DP_Parts"
require "DazedPower/DP_Model"
require "DazedPower/DP_Place"

DazedPower = DazedPower or {}
DazedPower.GenSwap = DazedPower.GenSwap or {}
local W = DazedPower.GenSwap
local P = DazedPower.Parts
local M = DazedPower.Model
local try = P.try

W.PRIORITY = 5                 -- MOGenerator.lua's, so this replaces its callback
W.CHANCE = 3                   -- the sandbox default: one map generator in this many
W.WORKSHOP_IN = 5              -- one non-old swap in this many is Workshop grade
W.SALT = 4242

--- The vanilla item and the Dazed engine for each sprite block of four.
W.BLOCKS = {
    { first = 0,  item = "Base.Generator",        kind = "petrol",  old = false },
    { first = 4,  item = "Base.Generator_Old",    kind = "petrol",  old = true },
    { first = 8,  item = "Base.Generator_Yellow", kind = "propane", old = false },
    { first = 12, item = "Base.Generator_Blue",   kind = "propane", old = false },
}

--- The neighbours tried for the controller, sides first.
W.AROUND = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }

function W.chance()
    local n = math.floor(tonumber(P.sandbox("GenSwapChance")) or W.CHANCE)
    return n < 0 and 0 or n
end

--- Is the tile at x, y one of the swapped ones?
function W.picked(x, y)
    local n = W.chance()
    if n <= 0 then return false end
    return M.placeRoll(x, y, W.SALT, n) == 0
end

function W.gradeOf(x, y, old)
    if old then return "makeshift" end
    if M.placeRoll(x, y, W.SALT + 1, W.WORKSHOP_IN) == 0 then return "workshop" end
    return "salvaged"
end

--- The facing the vanilla tile was drawn with, or S.
function W.facingOf(object)
    local sprite = try(object, "getSprite")
    local props = sprite and try(sprite, "getProperties")
    local f = props and try(props, "Val", "Facing")
    if f == "N" or f == "S" or f == "E" or f == "W" then return f end
    return "S"
end

--- Open floor with nothing standing on it and no container on it.
local function floorFree(sq)
    if try(sq, "isFree", false) ~= true then return false end
    local objs = try(sq, "getObjects")
    for i = 0, (objs and objs:size() or 0) - 1 do
        if try(objs:get(i), "getContainer") ~= nil then return false end
    end
    return true
end

--- A square beside the generator the controller can stand on, with no wall between them.
function W.spotFor(sq)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    for _, d in ipairs(W.AROUND) do
        local n = getSquare(x + d[1], y + d[2], z)
        if n and floorFree(n) and try(sq, "isBlockedTo", n) ~= true then return n end
    end
    return nil
end

--- MOGenerator.lua's ReplaceExistingObject, unchanged in what it does. `square` is
--  where the tile stood, for the one case where a failed swap already took it away.
function W.vanilla(object, block, square)
    square = square or object:getSquare()
    if not square then return end
    local item = instanceItem(block.item)
    if item == nil then
        print("DP_GenSwap: failed to create " .. tostring(block.item))
        return
    end
    item:setCondition(block.old and (ZombRand(100) + 1) or 100)
    item:getModData().fuel = 0
    if object:getSquare() then square:transmitRemoveItemFromSquare(object) end
    local gen = IsoGenerator.new(item, getWorld():getCell(), square)
    gen:transmitCompleteItemToClients()
end

local function place(sq, kind, tier, state, facing)
    local name = P.sprite(kind, "ground", tier, state, facing)
    if not name then return nil end
    -- The three-argument form keeps the sprite's name (see DP_Seed's S.place).
    local o = IsoObject.new(sq, name, name)
    if isServer() and sq.transmitAddObjectToSquare then
        sq:transmitAddObjectToSquare(o, -1)
    else
        sq:AddTileObject(o)
    end
    sq:RecalcProperties()
    sq:RecalcAllWithNeighbours(true)
    if DazedPower.System then DazedPower.System.register(o) end
    return o
end

--- Stand the Dazed pair where the vanilla tile was. Returns true when both are down.
function W.swap(object, block)
    local sq = object:getSquare()
    if not sq then return false end
    local spot = W.spotFor(sq)
    if not spot then return false end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local tier = W.gradeOf(x, y, block.old)
    local facing = W.facingOf(object)

    -- The vanilla tile is taken away last, so a part that will not place leaves it for vanilla:
    -- no generator, or a generator with no controller, and the pair is not placed at all.
    local g = place(sq, block.kind, tier, "off", facing)
    if not g then return false end
    local c = DazedPower.Place and DazedPower.Place.makeController(spot, nil,
        { kind = "controller", mount = "ground", tier = (tier == "workshop") and "workshop" or "makeshift",
          facing = facing }, nil)
    if not c then
        sq:transmitRemoveItemFromSquare(g)
        return false
    end
    sq:transmitRemoveItemFromSquare(object)

    local d = P.data(g)
    -- Found empty, like vanilla's (fuel 0), and switched off. The old ones are worn the way vanilla's are.
    d.condition = block.old and (15 + M.placeRoll(x, y, W.SALT + 2, 60)) or (60 + M.placeRoll(x, y, W.SALT + 3, 41))
    d.lpg = 0
    d.mode = "off"
    d.running = false
    d.state = "off"
    g:transmitModData()

    local cd = P.data(c)
    cd.trip = false
    cd.wire = M.wireAdd("", M.nodeKey(x, y, z, block.kind),
                        M.nodeKey(spot:getX(), spot:getY(), spot:getZ(), "controller"))
    c:transmitModData()
    return true
end

local function handler(block)
    return function(object)
        if not object or not object:getSquare() then return end
        local sq = object:getSquare()
        local ok, done = true, false
        if W.picked(sq:getX(), sq:getY()) then
            ok, done = pcall(W.swap, object, block)
            if not ok then print("DP_GenSwap: swap failed: " .. tostring(done)) done = false end
        end
        -- Not swapped, or the swap failed part way: the tile still gets a working vanilla generator.
        if not done then W.vanilla(object, block, sq) end
    end
end

function W.register()
    if not (MapObjects and MapObjects.OnNewWithSprite) then return end
    for _, block in ipairs(W.BLOCKS) do
        local fn = W.fns and W.fns[block.first] or handler(block)
        W.fns = W.fns or {}
        W.fns[block.first] = fn
        for n = block.first, block.first + 3 do
            MapObjects.OnNewWithSprite("appliances_misc_01_" .. n, fn, W.PRIORITY)
        end
    end
end

-- At file load and again at start, the way DUP_World.lua does: equal priority
-- replaces, so registering twice is harmless, and whichever of this file and
-- MOGenerator.lua loaded later, the second pass leaves this one in place.
W.register()
Events.OnGameStart.Add(W.register)
Events.OnServerStarted.Add(W.register)
