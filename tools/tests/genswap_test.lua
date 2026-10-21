-- Checks for 0.20.0: no vanilla generators. Map generators become a Dazed generator with a wired controller,
-- and the loot lists hand out Dazed generators instead of vanilla ones.
return function(check, E)
    local W = DazedPower.GenSwap
    local P, M = DazedPower.Parts, DazedPower.Model
    check(W ~= nil, "DP_GenSwap loaded")
    if not W then return end

    local SqMeta = getmetatable(E.square(0, 0, 0))
    local free0, gen0, mk0, gs0 = SqMeta.isFree, IsoGenerator, DazedPower.Place.makeController, getSquare
    local rp0, rn0, rm0 = SqMeta.RecalcProperties, SqMeta.RecalcAllWithNeighbours, SqMeta.transmitRemoveItemFromSquare
    SqMeta.isFree = function(self) return not self.taken end
    SqMeta.RecalcProperties = function() end
    SqMeta.RecalcAllWithNeighbours = function() end
    SqMeta.transmitRemoveItemFromSquare = function(self, o) self:RemoveTileObject(o) end
    local gens = {}
    IsoGenerator = { new = function(item, cell, sq)
        local g = E.object("generator", sq) g.item = item gens[#gens + 1] = g return g end }
    local made = {}
    DazedPower.Place.makeController = function(sq, item, info)
        local c = E.object(P.sprite("controller", "ground", info.tier, "off", info.facing), sq)
        made[#made + 1] = { sq = sq, info = info, obj = c }
        return c
    end
    getSquare = function(x, y, z) return E.squares[x .. "," .. y .. "," .. (z or 0)] end
    local getWorld0, inst0 = getWorld, instanceItem
    getWorld = function() return { getCell = function() return {} end } end
    instanceItem = function(ft)
        local it = E.item(ft) local md = {}
        it.setCondition = function(s, c) s.cond = c end
        it.getModData = function() return md end
        return it
    end
    local function dazedOn(sq)
        for _, o in ipairs(sq.objs) do
            local i = P.spriteInfo(o.sprite)
            if i and (i.kind == "petrol" or i.kind == "propane") then return o, i end
        end
    end
    local function vanillaTile(sq)
        for _, o in ipairs(sq.objs) do if tostring(o.sprite):match("^appliances_misc_01_") then return true end end
        return false
    end

    -- The sixteen vanilla sprites are taken over at vanilla's priority.
    local hooked = {}
    local on0 = MapObjects.OnNewWithSprite
    MapObjects.OnNewWithSprite = function(name, fn, pri) hooked[name] = pri end
    W.register()
    MapObjects.OnNewWithSprite = on0
    local all = true
    for n = 0, 15 do if hooked["appliances_misc_01_" .. n] ~= 5 then all = false end end
    check(all, "all sixteen vanilla generator sprites are hooked at priority 5")

    -- A red tile with room beside it: a petrol generator and a wired controller, no vanilla left.
    do
        local sq = E.square(5000, 6000, 0)
        E.square(5001, 6000, 0)
        W.fns[0](E.object("appliances_misc_01_0", sq))
        local g, info = dazedOn(sq)
        check(g ~= nil and info.kind == "petrol" and #gens == 0 and not vanillaTile(sq), "a red map generator becomes a Dazed petrol generator")
        local c = made[#made]
        check(c and c.sq == E.squares["5001,6000,0"], "its controller stands on the free square beside it")
        if g and c then
            local d = P.data(g)
            check(d.lpg == 0 and d.mode == "off" and d.condition >= 60 and d.condition <= 100, "found empty, off and in fair shape")
            local edges = M.wireParse(P.data(c.obj).wire)
            check(#edges == 1 and M.wireHas(edges, M.nodeKey(5000, 6000, 0, "petrol"), M.nodeKey(5001, 6000, 0, "controller")),
                "the generator is wired to that controller")
        end
    end

    -- A wall beside it: the controller goes two squares out.
    do
        made = {}
        local sq = E.square(5100, 6000, 0)
        E.square(5101, 6000, 0)
        E.square(5102, 6000, 0)
        sq.walls = { ["5101,6000"] = true }
        W.fns[8](E.object("appliances_misc_01_9", sq))
        local _, info = dazedOn(sq)
        check(info and info.kind == "propane" and made[1] and made[1].sq.x == 5102,
            "a yellow one is propane, and its controller goes two out past a wall")
    end

    -- Boxed in: the generator still stands, alone. Never vanilla.
    do
        gens, made = {}, {}
        local sq = E.square(5200, 6000, 0)
        W.fns[4](E.object("appliances_misc_01_5", sq))
        local g, info = dazedOn(sq)
        check(g and info.kind == "petrol" and info.tier == "makeshift" and #made == 0 and #gens == 0 and not vanillaTile(sq),
            "an old one with nowhere for a controller is a lone Makeshift petrol generator, not vanilla")
    end

    -- Switched off: vanilla's own, item for item.
    do
        gens, made = {}, {}
        SandboxVars.DazedPower.ReplaceGenerators = false
        local sq = E.square(5300, 6000, 0)
        E.square(5301, 6000, 0)
        W.fns[12](E.object("appliances_misc_01_14", sq))
        SandboxVars.DazedPower.ReplaceGenerators = nil
        check(#gens == 1 and #made == 0 and gens[1].item.fullType == "Base.Generator_Blue" and not dazedOn(sq),
            "with ReplaceGenerators off a blue tile is vanilla's blue generator")
    end

    -- The loot lists.
    do
        local L = DazedPower.Loot
        local crate = { rolls = 1, items = { "Generator", 10, "Generator_Blue", 10, "Generator_Yellow", 10, "Generator_Old", 40, "Base.Generator", 1, "Hammer", 5 },
                        junk = { items = { "Generator", 1 } } }
        local trunk = { items = { "JerryCan", 10, "Generator", 0.1 } }
        local pd0, vd0 = ProceduralDistributions, VehicleDistributions
        ProceduralDistributions = { list = { CrateGenerator = crate } }
        VehicleDistributions = { SurvivalistTruckBed = trunk, [1] = { TruckBed = trunk } }
        local n = L.swapGenerators()
        check(n == 7, "seven vanilla generator loot entries swapped: " .. n)
        check(crate.items[1] == "DazedPetrolSalvaged" and crate.items[3] == "DazedPropaneSalvaged" and crate.items[5] == "DazedPropaneSalvaged"
              and crate.items[7] == "DazedPetrolMakeshift" and crate.items[9] == "DazedPetrolSalvaged" and crate.items[11] == "Hammer"
              and crate.items[8] == 40 and crate.junk.items[1] == "DazedPetrolSalvaged",
            "each colour becomes its Dazed engine at the same weight, other items untouched")
        check(trunk.items[3] == "DazedPetrolSalvaged" and trunk.items[4] == 0.1, "a car trunk's generator is a Dazed one")
        local crate2 = { items = { "Generator", 10 } }
        ProceduralDistributions = { list = { CrateGenerator = crate2 } }
        SandboxVars.DazedPower.ReplaceGenerators = false
        L.swapGenerators()
        SandboxVars.DazedPower.ReplaceGenerators = nil
        check(crate2.items[1] == "Generator", "with ReplaceGenerators off the loot stays vanilla")
        ProceduralDistributions, VehicleDistributions = pd0, vd0
    end

    SqMeta.RecalcProperties, SqMeta.RecalcAllWithNeighbours, SqMeta.transmitRemoveItemFromSquare = rp0, rn0, rm0
    SqMeta.isFree, IsoGenerator, DazedPower.Place.makeController, getSquare, getWorld, instanceItem = free0, gen0, mk0, gs0, getWorld0, inst0
end
