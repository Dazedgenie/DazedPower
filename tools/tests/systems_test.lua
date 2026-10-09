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
