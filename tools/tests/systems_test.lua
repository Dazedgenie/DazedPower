-- Checks for the 0.3.0 systems: battery ageing, load priority, presets, vehicle charging, storms and the new parts.
return function(check, E)
    local P, M = DazedPower.Parts, DazedPower.Model

    ------------------------------------------------------------ battery ageing
    local d1 = M.ageDelta(720, 720, "salvaged", 1)
    check(d1 > 0 and math.abs(d1 - 0.5 * M.AGE_CYCLE) < 1e-9, "one pack-worth of throughput is half a cycle of wear")
    check(M.ageDelta(720, 720, "makeshift", 1) > d1 and M.ageDelta(720, 720, "workshop", 1) < d1, "grades age at different speeds")
    check(M.ageDelta(720, 720, "salvaged", 0) == 0 and M.ageDelta(0, 720, "salvaged", 1) == 0, "rate 0 and no throughput age nothing")

    local rack = { cellList = {}, charge = 0, tier = "salvaged", scale = 1 }
    local c1 = M.installCell(rack, "Base.CarBattery1", 1, 0.5)
    local c2 = M.installCell(rack, "Base.CarBattery1", 0.8, 0.5, 0.3)
    check(c1.wear == 0 and c2.wear == 0.3, "a cell remembers the wear its battery carried")
    check(math.abs(c2.health - 0.7) < 1e-9, "health is held under the wear ceiling on install")
    local data = { cellList = rack.cellList }
    P.ageBank(data, 0.1)
    check(math.abs(c1.wear - 0.1) < 1e-9 and math.abs(c2.wear - 0.4) < 1e-9, "ageing adds wear to every cell")
    check(math.abs(c2.health - 0.6) < 1e-9 and math.abs(c1.health - 0.9) < 1e-9, "wear pulls health down to each cell's new ceiling")
    P.applyBankHealth(data, 1)
    check(math.abs(c2.health - 0.6) < 1e-9, "an equalisation cannot recover past the ceiling")
    check(math.abs(P.bankCeiling(data) - 0.75) < 1e-9, "the rack ceiling is the mean of its cells")
    P.ageBank(data, 5)
    check(c2.wear == M.MAX_WEAR and c2.health >= 0.25, "wear stops at the maximum and a cell never reads below a quarter")
    local out = M.removeCell(rack, c2.id)
    check(out.wear == M.MAX_WEAR, "a removed cell hands its wear back")

    ------------------------------------------------------------ cell weights
    -- A battery worth less (or more) than the tier's cell: Wh in a rack are Wh of the item, no more.
    M.registerCellWeight("Test.Third", 1 / 3)
    M.registerCellWeight("Test.Heavy", 1400 / 720)
    local wr = { cellList = {}, charge = 0, tier = "salvaged", scale = 1 }
    M.installCell(wr, "Base.CarBattery1", 1, 1)
    check(math.abs(M.cellSum(wr.cellList) - 1) < 1e-9 and math.abs(wr.charge - 720) < 1e-6, "a car battery is weight 1 and unchanged")
    local third = M.installCell(wr, "Test.Third", 1, 1)
    check(math.abs(M.cellSum(wr.cellList) - (1 + 1 / 3)) < 1e-9, "a makeshift cell is worth a third of a car battery in cellSum")
    check(math.abs(wr.charge - 960) < 1e-6, "it brings its own 240 Wh with it")
    check(math.abs(M.bankNominal(wr) - 960) < 1e-6 and math.abs(P.bankHealth({ cellList = wr.cellList }) - 1) < 1e-9, "nominal follows the weight; mean health does not")
    local back = M.removeCell(wr, third.id)
    check(back.type == "Test.Third" and math.abs(back.fill - 1) < 1e-9 and math.abs(wr.charge - 720) < 1e-6, "install then remove round-trips the energy")
    local hv = M.installCell(wr, "Test.Heavy", 0.5, 0.5)
    check(math.abs(M.cellSum(wr.cellList) - (1 + 0.5 * 1400 / 720)) < 1e-9, "a deep-cycle cell is worth ~1.94 car batteries at full health")
    check(math.abs(wr.charge - (720 + 0.25 * 1400)) < 1e-6, "it arrives with condition x fill of its 1400 Wh")
    local hb = M.removeCell(wr, hv.id)
    -- Cells share one state of charge, so the cell leaves with the rack's fill; what matters is that no Wh appear or vanish.
    check(math.abs(hb.fill * hb.cond * 1400 + wr.charge - (720 + 0.25 * 1400)) < 1e-6, "removing a deep-cycle cell conserves the energy in item plus rack")
    local old = { { type = "Base.CarBattery2", health = 0.5 }, { health = 1 } }
    check(math.abs(M.cellSum(old) - 1.5) < 1e-9 and M.cellWeight(nil) == 1, "cells with no registered type, or none at all, count as before")
    check(M.isCellItem({ getFullType = function() return "Test.Third" end }) and not M.isCellItem({ getFullType = function() return "Base.Nail" end })
        and not M.isCellItem(nil), "a rack accepts a registered type and nothing else without the tag")

    -- The weight is saved on the cell: a later registry change cannot re-price a rack.
    local sr = { cellList = {}, charge = 0, tier = "salvaged", scale = 1 }
    local sc = M.installCell(sr, "Test.Third", 1, 1)
    local cc = M.installCell(sr, "Base.CarBattery1", 1, 1)
    check(math.abs(sc.w - 1 / 3) < 1e-9 and cc.w == nil, "a non-unit cell saves its weight; a car battery stays as before")
    M.CELL_WEIGHT["Test.Third"] = nil
    check(math.abs(M.cellSum(sr.cellList) - (1 + 1 / 3)) < 1e-9 and math.abs(M.weightSum(sr.cellList) - (1 + 1 / 3)) < 1e-9,
        "cellSum and weightSum keep the saved weight after the type is unregistered")
    local sb = M.removeCell(sr, sc.id)
    check(math.abs(sr.charge - 720) < 1e-6 and math.abs(sb.w - 1 / 3) < 1e-9, "removal uses the saved weight too, and hands it on")
    check(M.cellW({ type = "Test.Third" }) == 1 and M.cellW({}) == 1 and M.cellW(nil) == 1, "an old cell with no saved weight and no registration reads 1")
    M.registerCellWeight("Test.Third", 1 / 3)
    check(math.abs(M.cellW({ type = "Test.Third" }) - 1 / 3) < 1e-9, "an old cell of a registered type reads the registry weight")

    -- Removal never upgrades a makeshift cell into a car battery.
    local realInstance = instanceItem
    local made = {}
    instanceItem = function(t) if t == "Base.CarBattery1" or t == "Test.Third" then made[#made + 1] = t; return {} end return nil end
    local gone = P.cellItem("Test.Gone", 1, 1, 0, 1 / 3)
    check(gone == nil and #made == 0, "a vanished makeshift type yields no item and no car battery")
    check(P.cellItem("Test.Gone", 1, 1, 0) ~= nil, "a vanished unit-weight type still falls back to a car battery")
    check(not P.cellReturnable({ type = "Test.Gone", w = 1 / 3 }) and P.cellReturnable({ type = "Test.Third", w = 1 / 3 })
        and P.cellReturnable({ type = "Test.Gone" }), "removal is refused only for a non-unit cell that cannot be made")
    instanceItem = realInstance

    -- Wear and equalisation bill against the weight sum, not the cell count.
    local nl = { { type = "Base.CarBattery1" }, { type = "Test.Third", w = 1 / 3 } }
    check(math.abs(M.weightSum(nl) * M.cellWh("salvaged", 1) - (4 / 3) * 720) < 1e-6 and M.weightSum({}) == 0 and M.weightSum(nil) == 0,
        "nameplate for wear and equalisation is the weight sum times cell Wh")
    M.CELL_WEIGHT["Test.Third"], M.CELL_WEIGHT["Test.Heavy"] = nil, nil

    ------------------------------------------------------------ load priority
    local Pr = DazedPower.Priority
    local cd = {}
    check(Pr.of(cd, "purifier") == 1 and Pr.of(cd, "waterpump") == 2 and Pr.of(cd, "fuelpump") == 3 and Pr.of(cd, "mystery") == 2, "default priorities by kind")
    check(Pr.set(cd, "waterpump", 3) and Pr.of(cd, "waterpump") == 3, "a priority can be set")
    check(not Pr.set(cd, "waterpump", 4) and not Pr.set(cd, "waterpump", 0) and not Pr.set(cd, nil, 2), "out-of-range priorities are refused")
    cd = {}
    check(Pr.update(cd, 0.9, 0.2) == false and not Pr.shed(cd, "fuelpump"), "nothing is cut with a full bank")
    Pr.update(cd, 0.40, 0.2)
    check(Pr.shed(cd, "fuelpump") and not Pr.shed(cd, "waterpump") and not Pr.shed(cd, "purifier"), "Low goes first")
    Pr.update(cd, 0.30, 0.2)
    check(Pr.shed(cd, "waterpump") and not Pr.shed(cd, "purifier"), "Normal goes next, Essential stays")
    Pr.update(cd, 0.34, 0.2)
    check(Pr.shed(cd, "waterpump"), "a cut tier holds inside its hysteresis band")
    Pr.update(cd, 0.50, 0.2)
    check(not Pr.shed(cd, "waterpump") and not Pr.shed(cd, "fuelpump"), "both come back once the charge recovers")
    local W = DazedPower.More.Water
    check(W and W.poweredByWire ~= nil, "the wired-machine power check exists")

    ------------------------------------------------------------ sandbox presets
    local sv0 = SandboxVars
    SandboxVars = { DazedPower = { OutputScale = 100, CableTilesPerWire = 4 }, DazedCore = { Preset = 1 } }
    check(P.sandbox("OutputScale") == 100 and P.sandbox("CableTilesPerWire") == 4, "Custom keeps the mod's own options")
    SandboxVars.DazedCore.Preset = 2
    check(P.sandbox("OutputScale") == 150 and P.sandbox("CableTilesPerWire") == 0 and P.sandbox("LiveShock") == false, "Easy: more output, free cable, no shock")
    SandboxVars.DazedCore.Preset = 5
    check(P.sandbox("OutputScale") == 60 and P.sandbox("AgeRate") == 250 and P.sandbox("LinkRadius") == 8, "Hardcore: less output, fast ageing, short links")
    SandboxVars.DazedCore.Preset = 3
    for name, row in pairs(P.PRESETS) do
        check(row[2] == P.SANDBOX_DEFAULTS[name] or name == "AgeRate", "Standard matches the default for " .. name)
    end
    SandboxVars = sv0

    ------------------------------------------------------------ micro-hydro
    local MM = DazedPower.More.Model
    local w1, st1 = MM.hydroOutput({ wet = true, condition = 100 }, { temperature = 15 })
    check(w1 == MM.HYDRO_W and st1 == "turning", "a wet wheel in good order makes its rated watts")
    check(MM.hydroOutput({ wet = false, condition = 100 }, {}) == 0, "a dry wheel makes nothing")
    check(MM.hydroOutput({ wet = true, condition = 30 }, {}) == 0, "a broken wheel makes nothing")
    check(MM.hydroOutput({ wet = true, condition = 100 }, { temperature = -10 }) < w1 * 0.4, "ice slows the wheel hard")
    check(MM.hydroOutput({ wet = true, condition = 100 }, { temperature = 10, precipitation = 0.5 }) > w1, "rain adds a little")
    check(MM.hydroOutput({ wet = true, condition = 50 }, { temperature = 15 }) == MM.HYDRO_W * 0.5, "output follows condition")

    ------------------------------------------------------------ charging
    local Ch = DazedPower.Charge
    local car = { getFullType = function() return "Base.CarBattery1" end, f = 0.25,
                  getCurrentUsesFloat = function(self) return self.f end,
                  setCurrentUsesFloat = function(self, v) self.f = v end }
    check(Ch.itemWh(car) == Ch.CAR_WH, "a car battery is chargeable")
    check(Ch.itemWh({ getFullType = function() return "Base.Axe" end }) == nil, "an axe is not")
    check(math.abs(Ch.needWh(car) - 0.75 * Ch.CAR_WH) < 1e-6, "need is the missing fill")
    check(Ch.give(car, 10000) == 1 and car.f == 1, "charging stops at full")
    local racks = { { charge = 600, nominal = 1000 }, { charge = 200, nominal = 500 } }
    check(math.abs(Ch.available(racks, 0.2) - 500) < 1e-9, "only what is above the floor is available")
    local took = Ch.takeFrom(racks, 400)
    check(took == 400 and math.abs(racks[1].charge - 300) < 1e-9 and math.abs(racks[2].charge - 100) < 1e-9, "the draw is shared by what each rack holds")
    check(Ch.duration(1) == 30 and Ch.duration(100000) == 900, "action length is clamped")

    ------------------------------------------------------------ lightning and hydrogen
    local Hz = DazedPower.Hazards
    check(Hz.strikeChance(0) == 0 and Hz.strikeChance(200) == 2 * Hz.strikeChance(100), "the strike rate follows the sandbox")
    check(Hz.strikeOutcome(true, 0.0) == "rod", "a rod always takes the strike")
    check(Hz.strikeOutcome(false, 0.01) == "hit" and Hz.strikeOutcome(false, 0.5) == "trip", "no rod: mostly a trip, rarely a hit")
    check(Hz.atRisk("makeshift", 200, false) and not Hz.atRisk("salvaged", 200, false), "only Makeshift banks make gas")
    check(not Hz.atRisk("makeshift", 200, true) and not Hz.atRisk("makeshift", 50, false), "air or a gentle charge is safe")
    local m, wd, ev = 0, false, nil
    for i = 1, Hz.H2_WARN do m, wd, ev = Hz.h2Step(m, wd, true, 1) end
    check(ev == "warn" and wd, "the warning comes first")
    for i = 1, Hz.H2_FIRE do m, wd, ev = Hz.h2Step(m, wd, true, 1) end
    check(ev == nil, "no fire without a bad roll")
    m, wd, ev = Hz.h2Step(m, wd, true, 0)
    check(ev == "fire" and m == 0, "a bad roll after the warning period lights it")
    m = Hz.h2Step(30, true, false, 1)
    check(m == 28, "fresh air clears the gas")

    ------------------------------------------------------------ the new parts
    check(P.SOURCE_KINDS.hydro and P.PASSIVE.rod and not P.PASSIVE.bench, "hydro is a source, the rod passive, the bench a wired node")
    check(DazedPower.Model.METER_KINDS.bench and DazedPower.Model.wireLegal("bench", "controller"), "a bench wires to a controller")
end
