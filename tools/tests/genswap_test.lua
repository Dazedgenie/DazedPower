-- Checks for 0.20.0: some map generators become a Dazed generator with a wired controller beside it.
return function(check, E)
    local W = DazedPower.GenSwap
    local P, M = DazedPower.Parts, DazedPower.Model
    check(W ~= nil, "DP_GenSwap loaded")
    if not W then return end

    local SqMeta = getmetatable(E.square(0, 0, 0))
    local free0, gen0, mk0, gs0 = SqMeta.isFree, IsoGenerator, DazedPower.Place.makeController, getSquare
    SqMeta.isFree = function(self) return not self.taken end
    local rp0, rn0 = SqMeta.RecalcProperties, SqMeta.RecalcAllWithNeighbours
    SqMeta.RecalcProperties = function() end
    SqMeta.RecalcAllWithNeighbours = function() end
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
    instanceItem = function(ft)
        local it = E.item(ft) local md = {}
        it.setCondition = function(s, c) s.cond = c end
        it.getModData = function() return md end
        return it
    end
    getWorld = function() return { getCell = function() return {} end } end

    -- The sixteen vanilla sprites are taken over at vanilla's priority.
    local hooked = {}
    local on0 = MapObjects.OnNewWithSprite
    MapObjects.OnNewWithSprite = function(name, fn, pri) hooked[name] = pri end
    W.register()
    MapObjects.OnNewWithSprite = on0
    local all = true
    for n = 0, 15 do if hooked["appliances_misc_01_" .. n] ~= 5 then all = false end end
    check(all, "all sixteen vanilla generator sprites are hooked at priority 5")

    -- Find a picked tile and an unpicked one.
    SandboxVars.DazedPower.GenSwapChance = 3
    local px, py, ux, uy
    for x = 5000, 5200 do
        if not px and W.picked(x, 6000) then px, py = x, 6000 end
        if not ux and not W.picked(x, 6000) then ux, uy = x, 6000 end
    end
    check(px and ux, "the chance picks some tiles and not others")
    local n, hits = 0, 0
    for x = 0, 2999 do n = n + 1 if W.picked(x, 777) then hits = hits + 1 end end
    check(hits > n / 4.5 and hits < n / 2, "about one tile in three is picked: " .. hits .. "/" .. n)

    local red = W.BLOCKS[1]
    local fire = W.fns[0]

    -- A picked tile with room beside it: a petrol generator and a wired controller.
    do
        local sq = E.square(px, py, 0)
        E.square(px + 1, py, 0)
        local tile = E.object("appliances_misc_01_0", sq)
        fire(tile)
        local g
        for _, o in ipairs(sq.objs) do local i = P.spriteInfo(o.sprite) if i and i.kind == "petrol" then g = o end end
        check(g ~= nil and #gens == 0, "a picked red tile becomes a Dazed petrol generator, not a vanilla one")
        local c = made[#made]
        check(c and c.sq == E.squares[(px + 1) .. "," .. py .. ",0"], "its controller stands on the free square beside it")
        if g and c then
            local d = P.data(g)
            check(d.lpg == 0 and d.mode == "off" and d.condition >= 60 and d.condition <= 100, "found empty, off and in fair shape")
            local w = P.data(c.obj).wire
            local edges = M.wireParse(w)
            check(#edges == 1 and M.wireHas(edges, M.nodeKey(px, py, 0, "petrol"), M.nodeKey(px + 1, py, 0, "controller")),
                "the generator is wired to that controller")
        end
    end

    -- A picked tile boxed in: vanilla's generator, untouched.
    do
        gens, made = {}, {}
        local sq = E.square(px, py + 50, 0)
        if W.picked(px, py + 50) then
            local tile = E.object("appliances_misc_01_0", sq)
            fire(tile)
            check(#gens == 1 and #made == 0 and gens[1].item.fullType == "Base.Generator",
                "with nowhere to stand a controller the tile stays vanilla")
        end
    end

    -- A tile that is not picked is vanilla's, item for item.
    do
        gens, made = {}, {}
        local sq = E.square(ux, uy, 0)
        E.square(ux + 1, uy, 0)
        E.object("appliances_misc_01_14", sq)
        W.fns[12](sq.objs[#sq.objs])
        check(#gens == 1 and #made == 0 and gens[1].item.fullType == "Base.Generator_Blue", "an unpicked blue tile is vanilla's blue generator")
    end

    -- A controller that will not place: no pair, the tile goes to vanilla.
    do
        gens, made = {}, {}
        local mk = DazedPower.Place.makeController
        DazedPower.Place.makeController = function() return nil end
        local qx
        for x = 7000, 7300 do if W.picked(x, 6100) then qx = x break end end
        local sq = E.square(qx, 6100, 0)
        E.square(qx + 1, 6100, 0)
        local tile = E.object("appliances_misc_01_8", sq)
        W.fns[8](tile)
        DazedPower.Place.makeController = mk
        check(#gens == 1 and gens[1].item.fullType == "Base.Generator_Yellow", "a failed controller leaves vanilla's yellow generator")
    end

    -- Blue and yellow are propane; the old ones are Makeshift.
    check(W.BLOCKS[3].kind == "propane" and W.BLOCKS[4].kind == "propane" and W.BLOCKS[2].kind == "petrol", "yellow and blue are propane, old is petrol")
    check(W.gradeOf(1, 1, true) == "makeshift", "an old generator is Makeshift")

    -- 0 turns it off.
    SandboxVars.DazedPower.GenSwapChance = 0
    check(not W.picked(px, py), "GenSwapChance 0 swaps nothing")
    SandboxVars.DazedPower.GenSwapChance = nil

    SqMeta.RecalcProperties, SqMeta.RecalcAllWithNeighbours = rp0, rn0
    SqMeta.isFree, IsoGenerator, DazedPower.Place.makeController, getSquare, getWorld, instanceItem = free0, gen0, mk0, gs0, getWorld0, inst0
end
