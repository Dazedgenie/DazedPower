--[[ DazedPower -- the generators already on the map are Dazed ones.

     The map ships generators as plain tiles (appliances_misc_01_0..15) and
     vanilla's MOGenerator.lua turns each into a working IsoGenerator the first
     time its ground is generated. This file takes over those sixteen sprites
     and stands a Dazed petrol or propane generator there instead, with a
     makeshift controller beside it, already wired. Kyle, 2026-10-21: "I dont
     want any vanilla generators". DP_Loot swaps them out of the loot lists
     the same way. The sandbox switch ReplaceGenerators turns both off.

     A Dazed generator does not light the houses around it the way a vanilla
     one does; only a controller hands its power out, so the controller comes
     with it whenever there is anywhere to put one: a free square beside it
     with no wall between, then any free square two out. Only when there is
     none does the generator stand alone, unwired, because Kyle would rather
     a player find a controller than find a vanilla generator.

     WHY THE SAME PRIORITY. MapObjects keeps one callback per sprite and
     priority, and registering at an equal priority replaces it (the same
     fact DUP_World.lua relies on). Registering at vanilla's 5 therefore
     takes the tile over instead of racing MOGenerator for it. W.vanilla is
     MOGenerator's own code, for the switch turned off and for a swap the
     engine refuses outright.

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
W.WORKSHOP_IN = 5              -- one non-old swap in this many is Workshop grade
W.SALT = 4242

--- The vanilla item and the Dazed engine for each sprite block of four.
W.BLOCKS = {
    { first = 0,  item = "Base.Generator",        kind = "petrol",  old = false },
    { first = 4,  item = "Base.Generator_Old",    kind = "petrol",  old = true },
    { first = 8,  item = "Base.Generator_Yellow", kind = "propane", old = false },
    { first = 12, item = "Base.Generator_Blue",   kind = "propane", old = false },
}

--- The neighbours tried for the controller, sides first, then the ring two out.
W.AROUND = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
W.FARTHER = { { 2, 0 }, { 0, 2 }, { -2, 0 }, { 0, -2 }, { 2, 1 }, { 2, -1 }, { -2, 1 }, { -2, -1 },
              { 1, 2 }, { -1, 2 }, { 1, -2 }, { -1, -2 }, { 2, 2 }, { -2, 2 }, { 2, -2 }, { -2, -2 } }

--- Are vanilla generators being replaced? The sandbox switch, on by default.
function W.on()
    return P.sandbox("ReplaceGenerators") ~= false
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

--- A square for the controller: beside the generator with no wall between them, else two out.
function W.spotFor(sq)
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    for _, d in ipairs(W.AROUND) do
        local n = getSquare(x + d[1], y + d[2], z)
        if n and floorFree(n) and try(sq, "isBlockedTo", n) ~= true then return n end
    end
    for _, d in ipairs(W.FARTHER) do
        local n = getSquare(x + d[1], y + d[2], z)
        if n and floorFree(n) then return n end
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

--- Stand the Dazed generator where the vanilla tile was, with its controller when there is room.
--  Returns true once the generator is down (the tile is then gone).
function W.swap(object, block)
    local sq = object:getSquare()
    if not sq then return false end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local tier = W.gradeOf(x, y, block.old)
    local facing = W.facingOf(object)

    -- The vanilla tile is taken away only once the Dazed generator stands.
    local g = place(sq, block.kind, tier, "off", facing)
    if not g then return false end
    sq:transmitRemoveItemFromSquare(object)

    local d = P.data(g)
    -- Found empty, like vanilla's (fuel 0), and switched off. The old ones are worn the way vanilla's are.
    d.condition = block.old and (15 + M.placeRoll(x, y, W.SALT + 2, 60)) or (60 + M.placeRoll(x, y, W.SALT + 3, 41))
    d.lpg = 0
    d.mode = "off"
    d.running = false
    d.state = "off"
    g:transmitModData()

    local spot = W.spotFor(sq)
    local c = spot and DazedPower.Place and DazedPower.Place.makeController(spot, nil,
        { kind = "controller", mount = "ground", tier = (tier == "workshop") and "workshop" or "makeshift",
          facing = facing }, nil)
    if c then
        local cd = P.data(c)
        cd.trip = false
        cd.wire = M.wireAdd("", M.nodeKey(x, y, z, block.kind),
                            M.nodeKey(spot:getX(), spot:getY(), spot:getZ(), "controller"))
        c:transmitModData()
    end
    return true
end

local function handler(block)
    return function(object)
        if not object or not object:getSquare() then return end
        local sq = object:getSquare()
        local ok, done = true, false
        if W.on() then
            ok, done = pcall(W.swap, object, block)
            if not ok then print("DP_GenSwap: swap failed: " .. tostring(done)) done = false end
            if not done then print("DP_GenSwap: kept a vanilla generator at " .. sq:getX() .. "," .. sq:getY()) end
        end
        -- Switched off, or the engine refused the Dazed generator: the tile still gets a working one.
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
