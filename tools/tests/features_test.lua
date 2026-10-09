-- Checks for the 0.2.0 features: cable cost, the live-work shock, the Electrician's recipes, the wall gauge,
-- schema stamps, the GEN page for the gas engines and the seeded rig grades. Run from load_test.lua.
return function(check, E)
    local P, M = DazedPower.Parts, DazedPower.Model
    local MM = DazedPower.More.Model
    local S = DazedPower.System

    local function list(t)
        return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
    end

    ------------------------------------------------------------ cable cost
    check(M.cableWire(6, 4) == 2 and M.cableWire(20, 4) == 5 and M.cableWire(4, 4) == 1, "wire by length, 1 per 4 tiles")
    check(M.cableWire(0.5, 4) == 1 and M.cableWire(6, 0) == 0, "never under one wire; 0 tiles per wire is free")
    check(M.cableRefund(5) == 2 and M.cableRefund(1) == 0, "a cut gives half back, rounded down")
    check(math.abs(M.cableLength(0, 0, 3, 4) - 5) < 1e-9, "cable length is straight-line tiles")

    -- a carried inventory with wire in the main bag and in a backpack
    local main, bag = { name = "main" }, { name = "bag" }
    local items = {}
    local function add(cont, ft) local it = { fullType = ft, cont = cont } it.getContainer = function(s) return s.cont end items[#items + 1] = it return it end
    for _ = 1, 2 do add(main, "Base.ElectricWire") end
    for _ = 1, 3 do add(bag, "Base.ElectricWire") end
    local function removeFrom(cont) return function(_, it) if it.cont == cont then for i, v in ipairs(items) do if v == it then table.remove(items, i) return end end end end end
    main.Remove, bag.Remove = removeFrom(main), removeFrom(bag)
    main.getAllTypeRecurse = function(_, ft) local out = {} for _, it in ipairs(items) do if it.fullType == ft then out[#out + 1] = it end end return list(out) end
    main.AddItem = function(_, ft) return add(main, ft) end
    local player = { getInventory = function() return main end }
    check(S.wireCount(player) == 5, "wire counted in bags too")
    S.takeWire(player, 4)
    check(S.wireCount(player) == 1, "wire taken from each item's own container")
    S.giveWire(player, 2)
    check(S.wireCount(player) == 3, "a refund lands in the main inventory")
    check(S.cableCost({ ax = 0, ay = 0, bx = 6, by = 0 }) == 2, "the server prices a cable with the sandbox default")

    ------------------------------------------------------------ cables end to end (S.connect / S.disconnect)
    local instanceof0, getSquare0 = instanceof, getSquare
    instanceof = function(o, cls) return cls == "IsoGenerator" and type(o) == "table" and o.isGen == true end
    getSquare = function(x, y, z) return E.squares[x .. "," .. y .. "," .. (z or 0)] end
    local function part(kind, mount, tier, state, x, y, extra)
        local o = E.object(P.sprite(kind, mount, tier, state, "S"), E.square(x, y, 0), extra)
        return o
    end
    local c3 = part("controller", "ground", "makeshift", "off", 100, 100, { isGen = true,
        isActivated = function() return false end, getFuel = function() return 0 end })
    P.data(c3)                -- already a managed controller, so adopting it changes nothing
    local a3 = part("array", "ground", "makeshift", "clear", 106, 100)
    local tech = { getX = function() return 103 end, getY = function() return 100 end, getInventory = function() return main end,
                   getPerkLevel = function() return 0 end }
    for i = #items, 1, -1 do table.remove(items, i) end
    add(main, "Base.ElectricWire")
    local args = { ax = 106, ay = 100, az = 0, ak = "array", bx = 100, by = 100, bz = 0, bk = "controller" }
    local ok, why = S.connect(tech, args)
    check(not ok and why == "not enough wire" and S.wireCount(tech) == 1, "a 6-tile cable is refused on 1 wire, and nothing is taken")
    add(main, "Base.ElectricWire"); add(main, "Base.ElectricWire")
    ok, why = S.connect(tech, args)
    check(ok and S.wireCount(tech) == 1 and P.data(a3).sys ~= nil, "connected for 2 wire: " .. tostring(why))
    check(P.data(a3).cablePaid == 2, "the cable remembers what it cost")
    ok = S.disconnect(tech, args)
    check(ok and S.wireCount(tech) == 2 and P.data(a3).cablePaid == nil, "the cut gives 1 back")
    -- a cable nobody paid for (a seeded rig, or one run while cables were free) refunds nothing
    SandboxVars.DazedPower.CableTilesPerWire = 0
    S.connect(tech, args)
    SandboxVars.DazedPower.CableTilesPerWire = nil
    S.disconnect(tech, args)
    check(S.wireCount(tech) == 2, "an unpaid cable refunds nothing")

    -- a Makeshift controller manages 8 parts; a gauge still fits on a full one
    SandboxVars.DazedPower.CableTilesPerWire = 0
    for i = 1, 8 do
        local a = part("array", "ground", "makeshift", "clear", 100 + i, 104)
        S.connect(tech, { ax = 100 + i, ay = 104, az = 0, ak = "array", bx = 100, by = 100, bz = 0, bk = "controller" })
        check(P.data(a).sys ~= nil, "array " .. i .. " wired")
    end
    part("array", "ground", "makeshift", "clear", 100, 106)
    ok, why = S.connect(tech, { ax = 100, ay = 106, az = 0, ak = "array", bx = 100, by = 100, bz = 0, bk = "controller" })
    check(not ok and why == "controller is full", "a ninth part is refused: " .. tostring(why))
    local gg = part("gauge", "wall", "standard", "off", 102, 102)
    ok, why = S.connect(tech, { ax = 102, ay = 102, az = 0, ak = "gauge", bx = 101, by = 104, bz = 0, bk = "array" })
    check(ok and P.data(gg).sys ~= nil, "a gauge still lands on a full system: " .. tostring(why))
    SandboxVars.DazedPower.CableTilesPerWire = nil
    instanceof, getSquare = instanceof0, getSquare0

    ------------------------------------------------------------ the wall gauge
    check(M.wireLegal("gauge", "controller") and M.wireLegal("gauge", "array") and M.wireLegal("gauge", "propane"), "a gauge lands on any wired part")
    check(not M.wireLegal("array", "gauge") and not M.wireLegal("gauge", "waterpump") and not M.wireLegal("gauge", "vane"), "nothing lands on a gauge")
    check(not M.countsAsNode("gauge") and M.countsAsNode("array") and M.countsAsNode("controller"), "a gauge takes no controller slot")
    check(M.gaugeState(false, 0.9) == "off" and M.gaugeState(true, 0.1) == "low" and M.gaugeState(true, 0.5) == "mid"
          and M.gaugeState(true, 0.8) == "full", "gauge bands")
    check(P.itemFor("gauge", "wall", "standard") == "Base.DazedPowerGauge", "gauge item")

    ------------------------------------------------------------ the shock
    local K = DazedPower.Shock
    check(math.abs(K.chance(0, 0) - K.BASE) < 1e-9 and K.chance(100000, 0) == K.MAX, "shock chance grows with watts, capped")
    check(math.abs(K.chance(0, 10) - K.BASE * K.SKILL_FLOOR) < 1e-9 and K.chance(2000, 5) < K.chance(2000, 0), "skill lowers the chance")
    check(K.live({ online = true, powered = true }) and not K.live({ online = true, powered = true, trip = true })
          and not K.live({ online = false, powered = true }), "live means switched on, untripped and powered")
    BodyPartType = { Hand_L = "Hand_L", Hand_R = "Hand_R" }
    Perks = Perks or {}
    Perks.Electricity = "Electricity"
    local hands = {}
    local function hand(name)
        hands[name] = hands[name] or { burnt = false, pain = 0, isBurnt = function(s) return s.burnt end, setBurned = function(s) s.burnt = true end,
                                       getAdditionalPain = function(s) return s.pain end, setAdditionalPain = function(s, v) s.pain = v end }
        return hands[name]
    end
    local worker = { getBodyDamage = function() return { getOverallBodyHealth = function() return 100 end,
                                                          getBodyPart = function(_, n) return hand(n) end } end,
                     getPerkLevel = function() return 0 end }
    local ctrlObj = E.object(P.sprite("controller", "ground", "makeshift", "on", "S"), E.square(50, 50, 0))
    local cd = P.data(ctrlObj)
    cd.online, cd.powered, cd.load = false, true, 800
    check(K.risk(worker, ctrlObj, "connect") == false, "no shock with the controller switched off")
    cd.online = true
    local hit = K.risk(worker, ctrlObj, "connect")      -- the stub's ZombRandFloat rolls 0: always under the chance
    check(hit == true and (hand("Hand_L").burnt or hand("Hand_R").burnt), "a live system burns a hand")
    local burnt = hand("Hand_L").burnt and hand("Hand_L") or hand("Hand_R")
    check(burnt.pain == K.PAIN, "with the shock's pain")
    SandboxVars.DazedPower.LiveShock = false
    check(K.risk(worker, ctrlObj, "connect") == false, "LiveShock off: never")
    SandboxVars.DazedPower.LiveShock = nil

    ------------------------------------------------------------ the Electrician
    local EL = DazedPower.Electrician
    local function who(prof)
        local known = {}
        return { getDescriptor = function() return { getProfession = function() return prof end } end,
                 isRecipeKnown = function(_, n) return known[n] == true end, learnRecipe = function(_, n) known[n] = true end }
    end
    check(EL.isElectrician(who("electrician")) and EL.isElectrician(who("base:electrician")) and not EL.isElectrician(who("carpenter")),
          "the Electrician is recognised either way")
    local sparky = who("electrician")
    local n1 = EL.grant(sparky)
    check(n1 == #DazedPower.RecipeLists.ELECTRICIAN and n1 == 11 and EL.grant(sparky) == 0, "eleven Makeshift builds, learned once")
    local allMakeshift = true
    for _, r in ipairs(DazedPower.RecipeLists.ELECTRICIAN) do if not r:find("Makeshift") then allMakeshift = false end end
    check(allMakeshift and EL.grant(who("chef")) == 0, "only Makeshift builds, only for an Electrician")

    ------------------------------------------------------------ schema stamps
    local arr = E.object(P.sprite("array", "ground", "salvaged", "clear", "S"), E.square(51, 50, 0))
    check(P.data(arr)._v == P.SCHEMA, "a part's ModData carries the schema version")
    local G = DazedPower.Migrate
    check(G and G.run() == 4 and G.run() == 0, "world tables are stamped once")

    ------------------------------------------------------------ gas engines on the GEN page
    local g = { tier = "salvaged", kind = "propane", mode = "auto", lpg = 5, running = true, stopPct = 80, condition = 100 }
    check(MM.propaneSwitch(g, 85) == false, "auto stops at the controller's stop level")
    g.running = false
    check(MM.propaneSwitch(g, 20) == true, "and starts under its start level")
    g.running, g.hold = false, true
    check(MM.propaneSwitch(g, 10) == false, "the master AUTO off holds it")

    local GP = DazedPower.GenPanel
    local function gen(kind, tier, extra)
        local e = { tier = tier, kind = kind, mode = "off", lpg = 4, condition = 100, watts = 0 }
        for k, v in pairs(extra or {}) do e[k] = v end
        return e
    end
    check(GP.state(gen("propane", "salvaged", { running = true })) == "running", "state: running")
    check(GP.state(gen("propane", "salvaged", { mode = "auto" })) == "standby", "state: standby")
    check(GP.state(gen("propane", "makeshift", { mode = "auto" })) == "off", "a pull-cord engine has no standby")
    check(GP.state(gen("petrol", "workshop", { lpg = 0 })) == "nofuel" and GP.state(gen("propane", "salvaged", { condition = 20 })) == "fault",
          "state: no fuel, fault")
    local row = GP.row(gen("petrol", "workshop", { running = true, watts = 1500 }))
    check(row.t == "petrol_workshop" and row.u == "L" and row.burn > 0 and row.left > 0 and row.s == "running", "a row in litres with burn and hours left")

    local ctrl2 = E.object(P.sprite("controller", "ground", "workshop", "on", "S"), E.square(60, 60, 0))
    local sent = 0
    ctrl2.transmitModData = function() sent = sent + 1 end
    local d2 = P.data(ctrl2)
    local gens = {}
    for i = 1, 5 do
        local x = gen("propane", "salvaged", { mode = "auto", running = (i == 5), watts = (i == 5) and 900 or 0, fuel0 = 4.5 })
        x.obj = E.object(P.sprite("propane", "ground", "salvaged", "off", "S"), E.square(60 + i, 61, 0))
        gens[i] = x
    end
    GP.mirror(ctrl2, d2, { gens = gens, genW = 900 }, 1)
    check(#d2.bkRows == 4 and d2.bkN == 5 and d2.bkMore == 1, "four rows shown, the fifth counted")
    check(d2.bkRows[1].s == "running", "the running engine is listed first")
    check(math.abs((d2.bkFuelKg or 0) - 2.5) < 1e-6 and (d2.bkWhToday or 0) == 900, "fuel and energy today")
    local start, stop, eff = GP.levels(d2)
    check(gens[1].startPct == math.floor(eff * 100 + 0.5) and gens[1].stopPct == math.floor(stop * 100 + 0.5)
          and P.data(gens[1].obj).stopPct == gens[1].stopPct, "the controller's levels reach every engine")
    local before = sent
    for i = 1, #gens do gens[i].fuel0 = (gens[i].fuel0 or 4) + 0.3 end   -- a minute of running: fuel and Wh move
    GP.mirror(ctrl2, d2, { gens = gens, genW = 910 }, 1 / 60)
    check(sent == before, "a running engine's minute does not resend the controller")
    gens[5].running, gens[5].watts = false, 0
    GP.mirror(ctrl2, d2, { gens = gens, genW = 0 }, 1 / 60)
    check(sent == before + 1, "an engine stopping does")
    gens[5].running, gens[5].watts = true, 900
    GP.command(nil, ctrl2, "bkLevelStart", { value = 1 })
    local start2 = GP.levels(d2)
    check(math.abs(start2 - (start + GP.STEP)) < 1e-6, "START + steps the level by five points")
    GP.command(nil, ctrl2, "bkMaster", { value = false })
    GP.mirror(ctrl2, d2, { gens = gens, genW = 0 }, 0)
    check(d2.bkAuto == false and gens[2].hold == true and P.data(gens[2].obj).hold == true, "master AUTO off holds every engine")

    ------------------------------------------------------------ seeded rig grades
    local Seed = DazedPower.Seed
    local tally = { makeshift = 0, salvaged = 0, workshop = 0 }
    for i = 1, 3000 do
        local def = { getX = function() return 1000 + (i * 37) % 900 end, getY = function() return 2000 + math.floor(i * 53 / 7) end }
        local gr = Seed.gradeOf(def)
        tally[gr] = tally[gr] + 1
    end
    local function near(v, pct) return math.abs(v / 3000 * 100 - pct) < 5 end
    check(near(tally.makeshift, 65) and near(tally.salvaged, 28) and near(tally.workshop, 7),
          string.format("rig grades %d/%d/%d of 3000", tally.makeshift, tally.salvaged, tally.workshop))
end
