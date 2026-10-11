--[[ DazedPower -- every Dazed Power item for Dazed Core's debug spawn ("Dazed debug" in the right-click menu,
     debug mode or staff only). One of each part in every tier, in the order the sheet lists them, then the
     books, kits and amplifier. The controller's extra facing and running records are left out: they are the
     same controller. ]]

require "DazedCore/DC_Boot"
require "DazedCore/DC_DebugSpawn"     -- by name, so it is there whichever mod's shared files load first
require "DazedPower/DP_Parts"

local S = DazedCore.DebugSpawn
if not (S and S.register) then return end      -- a Dazed Core older than 1.5.0

local P = DazedPower.Parts

S.register("power", "Dazed Power", function()
    local out = {}
    for _, kind in ipairs(P.KINDS) do
        local byMount = P.ITEM[kind]
        if byMount then
            for _, mount in ipairs(P.MOUNTS[kind]) do
                for _, tier in ipairs(P.TIERS[kind]) do
                    local item = byMount[mount] and byMount[mount][tier]
                    if item then out[#out + 1] = item end
                end
            end
        end
    end
    for _, k in ipairs({ "MANUAL", "MANUAL_ADV", "ALMANAC", "AMP_ITEM" }) do
        if P[k] then out[#out + 1] = P[k] end
    end
    for _, gear in ipairs(P.GEAR_ORDER or {}) do out[#out + 1] = P.GEAR_ITEM[gear] end
    return out
end)

--- Every floor battery rack at every fill level, for checking the art (and Dazed Viewpoint's models) in one
--  place: one row per grade from empty to full, all facing S, then the full Workshop rack in each facing.
--  Real racks, filled with healthy car batteries the way DP_Seed fills a found rig, so the sprite and the
--  cells inside agree and the system leaves them alone. Placed on the authority, a square apart.
local BANK_GAP = 2

local function openFloor(sq)
    if not sq or sq:isSolid() or sq:isSolidTrans() then return false end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if o and not o:isFloor() then return false end
    end
    return true
end

local function spawnBanks(character)
    local Seed = DazedPower.Seed
    if not (Seed and Seed.place) then return 0, 0 end
    local cell = getCell()
    local x0, y0, z = math.floor(character:getX()) + 2, math.floor(character:getY()) + 2, math.floor(character:getZ())
    local rows = {}
    for _, tier in ipairs(P.TIERS.bank) do
        local row = {}
        for n = 0, (P.BANK_CELLS.ground[tier] or 0) do row[#row + 1] = { tier = tier, cells = n, facing = "S" } end
        rows[#rows + 1] = row
    end
    local turns = {}
    for _, f in ipairs({ "E", "S", "W", "N" }) do turns[#turns + 1] = { tier = "workshop", cells = P.BANK_CELLS.ground.workshop, facing = f } end
    rows[#rows + 1] = turns

    local placed = 0
    for r, row in ipairs(rows) do
        for c, b in ipairs(row) do
            local sq = cell:getGridSquare(x0 + (c - 1) * BANK_GAP, y0 + (r - 1) * BANK_GAP, z)
            if openFloor(sq) then
                local state = P.bankState({ mount = "ground", tier = b.tier, cells = b.cells })
                local o = Seed.place(sq, "bank", "ground", b.tier, state, b.facing)
                if o then
                    local d = P.data(o)
                    d.condition, d.cells, d.cellList = 100, b.cells, {}
                    for j = 1, b.cells do d.cellList[j] = { id = j, type = "Base.CarBattery1", health = 1 } end
                    d.nextCellId, d.charge, d.state = b.cells + 1, 0, state
                    o:transmitModData()
                    placed = placed + 1
                end
            end
        end
    end
    return placed, 0
end

S.register("powerBanks", "battery rack", nil, { label = "IGUI_DazedPower_DebugBanks", place = spawnBanks })
