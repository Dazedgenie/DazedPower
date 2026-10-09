-- Checks for 0.5.0: the climate lookup, cold starts, the space heater and the heaters and coolers as room heat
-- sources. Run from load_test.lua.
return function(check, E)
    local P, M = DazedPower.Parts, DazedPower.Model
    local MM, Env = DazedPower.More.Model, DazedPower.Env
    local A, GP = DazedPower.Appliances, DazedPower.GenPanel
    local Cl = DazedCore.Climate
    local print = E.realPrint

    -- A climate manager that answers like the engine, with a two-day forecast ring.
    local function fcDay(mean, lo, hi)
        return {
            getCloudiness = function() return { getDayMean = function() return 0.2 end } end,
            getTemperature = function() return { getDayMean = function() return mean end, getTotalMin = function() return lo end,
                                                 getTotalMax = function() return hi end } end,
            isHasStorm = function() return false end, isHasBlizzard = function() return false end,
            isHasTropicalStorm = function() return false end, isHasHeavyRain = function() return false end,
            isChanceOnSnow = function() return false end, isHasFog = function() return false end,
            getFogStrength = function() return 0 end,
        }
    end
    local ring = { [0] = fcDay(10, 5, 15), [1] = fcDay(11, 6, 16) }
    local fakeCm = setmetatable({
        getTemperature = function() return 7 end,
        getAirTemperatureForSquare = function() return 9 end,
        getClimateForecaster = function() return { getForecast = function(_, i) return ring[i] end } end,
    }, { __index = function() return function() return nil end end })
    local cm0, provider0, sv0, gt0 = getClimateManager, Cl and Cl.provider, SandboxVars, getGameTime
    getClimateManager = function() return fakeCm end
    getGameTime = function()
        local t = gt0()
        t.getDayPlusOne = t.getDayPlusOne or function() return 21 end
        return t
    end
    local sq = E.square(40, 40, 0)
    local spot = { getSquare = function() return sq end }

    ------------------------------------------------------------ the climate lookup
    -- Run against an older DazedCore too: then only the game's figures can be checked.
    if Cl then Cl.provider = nil end
    check(Env.readFresh().temperature == 7 and Env.tempAt(spot, 0) == 9, "with no climate mod the game's figures stand")
    if Cl then
        Cl.register({ outdoor = function() return -12 end, at = function(s) return s == sq and 21 or nil end,
                      forecast = function(i) return i == 1 and { min = -20, max = -8, mean = -14 } or nil end })
        check(Env.readFresh().temperature == -12, "the county's air comes from the climate mod")
        check(Env.tempAt(spot, 0) == 21 and Env.tempAt(nil, 3) == 3, "a part's air is its room's; no square falls back")
        local fc = Env.readForecast(1)
        check(fc and fc[1].t == 10 and fc[1].n == 5, "a day the climate mod does not forecast keeps the engine's temperatures")
        check(fc and fc[2].t == -14 and fc[2].n == -20 and fc[2].x == -8 and fc[2].c == 0.2, "a forecast day takes the curve's low, high and mean")

        -- A rack in a heated room keeps its capacity on a freezing day; the same rack outdoors does not.
        local shape = { tier = "makeshift", cellSum = 3, scale = 1 }
        local warm = M.bankCapacity(shape, Env.tempAt(spot, Env.readFresh().temperature))
        local cold = M.bankCapacity(shape, Env.readFresh().temperature)
        check(math.abs(warm - M.bankNominalWh(shape)) < 1e-6 and cold < warm * 0.7, "a heated room holds a rack's capacity")
        local savedCl = DazedCore.Climate
        DazedCore.Climate = nil
        check(Env.readFresh().temperature == 7 and Env.tempAt(spot, 0) == 9 and Env.readForecast(1)[2].t == 11,
              "an older DazedCore without the lookup still works")
        DazedCore.Climate = savedCl
    else
        print("climate_power_test: DazedCore has no climate lookup (older than 1.3.0); its checks skipped")
    end

    ------------------------------------------------------------ the seasons, as the solar model already has them
    local function dayWh(m, d, tempC)
        local noon, len = M.engineDay(1993, m, d)
        local wh = 0
        for q = 0, 95 do
            local env = { dayOfYear = M.dayOfYear(m, d), hour = q / 4, noon = noon, dayHours = len, cloud = 0, fog = 0,
                          precipitation = 0, temperature = tempC }
            wh = wh + M.arrayOutput({ tier = "salvaged", mount = "ground", facing = "S", panels = 2 }, env) / 4
        end
        return wh
    end
    local winter, summer = dayWh(12, 21, -5), dayWh(6, 21, 25)
    check(winter > 0 and summer > winter, "a clear summer day beats a clear winter one")
    print(string.format("solar, clear sky, Salvaged 2-panel south array: 21 Dec %.2f kWh (-5 C), 21 Jun %.2f kWh (25 C), winter/summer %.2f",
                        winter / 1000, summer / 1000, winter / summer))

    ------------------------------------------------------------ cold starts
    check(MM.coldStartChance(-5, "salvaged") == 0 and MM.coldStartChance(0, "salvaged") == 0, "no failures from -5 C up")
    check(math.abs(MM.coldStartChance(-25, "salvaged") - 0.6) < 1e-9 and math.abs(MM.coldStartChance(-15, "salvaged") - 0.3) < 1e-9,
          "linear to 60% at -25 C")
    check(math.abs(MM.coldStartChance(-40, "salvaged") - 0.6) < 1e-9, "no worse than -25 C below it")
    check(math.abs(MM.coldStartChance(-25, "makeshift") - 0.75) < 1e-9 and math.abs(MM.coldStartChance(-25, "workshop") - 0.45) < 1e-9,
          "Makeshift x1.25, Workshop x0.75")
    check(MM.coldStartChance(nil, "makeshift") == 0, "no air reading, no cold check")

    local roll0 = MM.coldRoll
    local function gen(extra)
        local g = { tier = "salvaged", kind = "propane", mode = "on", condition = 100, lpg = 5 }
        for k, v in pairs(extra or {}) do g[k] = v end
        return g
    end
    MM.coldRoll = function() return 0 end         -- every roll fails when there is a chance
    local g = gen({ ambient = -20 })
    check(MM.propaneSwitch(g, nil) == false and g.coldFail and g.mode == "off", "a failed manual start stays off, flagged, switch back to OFF")
    check(MM.propaneSwitch(g, nil) == false and g.coldFail, "the failure stays on show")
    g = gen({ ambient = -20, running = true })
    check(MM.propaneSwitch(g, nil) == true and not g.coldFail, "a running engine never rolls")
    g = gen({ ambient = -4 })
    check(MM.propaneSwitch(g, nil) == true, "nothing fails at -4 C")
    g = gen({ ambient = nil })
    check(MM.propaneSwitch(g, nil) == true, "with cold starts off nothing fails")
    MM.coldRoll = function() return 0.99 end
    g = gen({ ambient = -25, coldFail = true })
    check(MM.propaneSwitch(g, nil) == true and g.coldFail == nil, "a start that works clears the failure")
    -- AUTO waits an hour after a failed start, then tries again, rolling each time.
    MM.coldRoll = function() return 0 end
    g = gen({ mode = "auto", ambient = -6, now = 100 })
    check(MM.propaneSwitch(g, 10) == false and g.coldFail and g.coldFailAt == 100 and g.mode == "auto", "AUTO fails a cold start, stamped, stays on AUTO")
    MM.coldRoll = function() return 0.99 end
    g.now = 100.5
    check(MM.propaneSwitch(g, 10) == false, "AUTO does not retry within the hour")
    MM.coldRoll = function() return 0 end
    g.now = 101
    check(MM.propaneSwitch(g, 10) == false and g.coldFailAt == 101, "after an hour it tries again, and a second failure restamps")
    MM.coldRoll = function() return 0.99 end
    g.now = 102
    check(MM.propaneSwitch(g, 10) == true and g.coldFail == nil and g.coldFailAt == nil, "a retry that works runs and clears the failure")
    g = gen({ mode = "auto", ambient = -20, coldFail = true, coldFailAt = 100, now = 100.2 })
    g.ambient = 2
    check(MM.propaneSwitch(g, 10) == true and g.coldFail == nil, "AUTO starts once the air warms, and clears the failure")
    g = gen({ mode = "off", ambient = 3, coldFail = true })
    MM.propaneSwitch(g, nil)
    check(g.coldFail == nil, "warmer air clears a failure left on a stopped engine")

    -- The engine's air comes from its square, and the sandbox option turns the check off.
    if Cl then Cl.register({ at = function() return -30 end, outdoor = function() return -30 end }) end
    fakeCm.getAirTemperatureForSquare = function() return -30 end
    local engSq = E.square(41, 40, 0)
    local engine = E.object(P.sprite("propane", "ground", "salvaged", "off", "S"), engSq)
    check(Env.engineAir(engine) == -30, "the engine's air is read at its square")
    SandboxVars = { DazedPower = { ColdStarts = false } }
    check(Env.engineAir(engine) == nil, "ColdStarts off: no air reading, so no failures")
    SandboxVars = sv0
    -- The GEN page's run goes through the same roll.
    MM.coldRoll = function() return 0 end
    local gd = { condition = 100, lpg = 5, mode = "off" }
    check(GP.start(engine, { tier = "salvaged", kind = "propane" }, gd) == false and gd.coldFail and not gd.running,
          "the GEN page's run can fail in the cold")
    check(GP.state({ tier = "salvaged", kind = "propane", lpg = 5, condition = 100, coldFail = true }) == "cold", "the page shows COLD")
    MM.coldRoll = function() return 0.99 end
    gd = { condition = 100, lpg = 5, mode = "off", coldFail = true }
    check(GP.start(engine, { tier = "salvaged", kind = "propane" }, gd) == true and gd.running and gd.coldFail == nil, "and can succeed")
    -- An away system's engine has no square to read, so the county's air decides its start.
    local D = DazedPower.Distrib
    local bank = { cells = 0, charge = 0, capacity = 0, health = 1 }
    local snapGen = { tier = "salvaged", kind = "propane", mode = "on", lpg = 5, condition = 100 }
    local store = ModData.getOrCreate(D.REMOTE_TAG)
    store.coldTest = { bank = bank, dpm = { turbines = {}, boilers = {}, pedals = {}, gens = { snapGen }, solar = {}, hydros = {} } }
    MM.coldRoll = function() return 0 end
    M.step({ arrays = {}, bank = bank, load = 0, online = true }, 1 / 60, { temperature = -25, hour = 12, dayOfYear = 1, cloud = 0 })
    check(snapGen.coldFail == true and snapGen.mode == "off" and type(snapGen.coldFailAt) == "number", "an unloaded engine rolls against the county's air")
    store.coldTest = nil
    MM.coldRoll = roll0
    local GF = DazedPower.More.Bridge.GEN_FIELDS
    check(GF[#GF - 1] == "coldFail" and GF[#GF] == "coldFailAt", "the failure and its hour are saved with the engine")

    -- A failure in the tick is told to the players within ten squares, on the authority.
    local said, say0, op0 = {}, DazedCore.Note.say, getOnlinePlayers
    DazedCore.Note.say = function(pl, key) said[#said + 1] = { pl, key } end
    local function player(x, y) return { getX = function() return x end, getY = function() return y end, getZ = function() return 0 end } end
    local near, far = player(45, 44), player(70, 40)
    getOnlinePlayers = function() return { size = function() return 2 end, get = function(_, i) return i == 0 and near or far end } end
    DazedPower.More.Bridge.coldNote(engine)
    check(#said == 1 and said[1][1] == near and said[1][2] == "IGUI_DazedPower_GenColdNote", "only the player near the engine hears it")
    DazedCore.Note.say, getOnlinePlayers = say0, op0

    ------------------------------------------------------------ the space heater
    check(P.KINDS[#P.KINDS - 1] == "heater" and P.ROWS[167].kind == "heater", "the heater is appended after the earlier rows")
    check(P.sprite("heater", "ground", "standard", "off", "S") == "dazedpower_02_149"
          and P.sprite("heater", "ground", "standard", "on", "N") == "dazedpower_02_155", "heater sprites follow the cooler's")
    check(P.sprite("cooler", "wall", "standard", "on", "N") == "dazedpower_02_147", "the cooler's sprites did not move")
    local hi = P.spriteInfo("dazedpower_02_153")
    check(hi and hi.kind == "heater" and hi.state == "on" and hi.facing == "S", "a heater sprite decodes")
    check(P.itemFor("heater", "ground", "standard") == "Base.DazedSpaceHeater", "the heater's item")
    check(M.wireLegal("heater", "controller") and not M.countsAsNode("heater") and M.APPLIANCE_KINDS.heater, "wired like the cooler, no controller slot")
    check(DazedPower.Priority.of({}, "heater") == 3, "a heater is a Low priority load by default")

    local hsq = E.square(44, 40, 0)
    local heater = E.object(P.sprite("heater", "ground", "standard", "off", "S"), hsq)
    local live, why = A.status(heater, "heater")
    check(not live and why == "IGUI_DazedPower_HeaterSwitchedOff", "a new heater is switched off")
    check(A.setSwitch(heater, true) and A.switchedOn(P.data(heater)), "the switch turns it on")
    live, why = A.status(heater, "heater")
    check(not live and why == "IGUI_DazedPower_ApplLoose", "switched on but not wired: still off, and says why")
    P.data(heater).live = true
    P.setState(heater, "on")
    check(A.setSwitch(heater, false) and not P.data(heater).live and P.describe(heater).state == "off", "switching off darkens it at once")
    check(not A.setSwitch(heater, false), "switching off twice changes nothing")

    local rec = { dpm = { heater = { heater }, fence = {}, cooler = {} } }
    P.data(heater).live = true
    local active, idle, total = A.draw(rec)
    check(active.heater == A.HEATER_W and total == A.HEATER_W, "a running heater bills 1500 W")
    P.data(heater).live = nil
    active, idle, total = A.draw(rec)
    check(active.heater == nil and idle.heater == A.HEATER_W and total == 0, "an idle heater bills nothing")

    ------------------------------------------------------------ heat sources for Dazed Climate
    check(A.roomHeat("heater", { live = true }) == 18 and A.roomHeat("heater", {}) == 0, "a running heater gives 18, an idle one 0")
    check(A.roomHeat("cooler", { live = true }) == -12 and A.roomHeat("cooler", { live = true, noRoom = true }) == 0,
          "a running cooler takes 12 from its room")
    SandboxVars = { DazedPower = { RoomHeat = false } }
    check(A.roomHeat("heater", { live = true }) == 0, "RoomHeat off: no heat")
    SandboxVars = sv0

    local objSrc, roomSrc = {}, {}
    DazedClimate = { Rooms = { addObjectSource = function(s) objSrc[#objSrc + 1] = s end,
                               addRoomSource = function(f) roomSrc[#roomSrc + 1] = f end } }
    A.climateDone = nil
    check(A.registerClimate() and #objSrc == 2 and #roomSrc == 1, "the heater, the cooler and the outside coolers register")
    check(A.registerClimate() and #objSrc == 2, "and only once")
    local cooler = E.object(P.sprite("cooler", "wall", "standard", "on", "S"), E.square(45, 40, 0))
    P.data(heater).live = true
    P.data(cooler).live = true
    local heatOf = {}
    for _, s in ipairs(objSrc) do
        if s.match(heater) then heatOf.heater = s.heat(heater) end
        if s.match(cooler) then heatOf.cooler = s.heat(cooler) end
        check(not s.match(engine), "a generator is no heat source")
    end
    check(heatOf.heater == 18 and heatOf.cooler == -12, "Dazed Climate reads the heater's warmth and the cooler's chill")
    A.outsideCoolers[cooler] = "1,2,0"
    check(roomSrc[1]({ key = "1,2,0" }) == -12 and roomSrc[1]({ key = "9,9,0" }) == 0, "a cooler hung from outside chills the room it serves")
    -- Cold storage: only the cooler's source says it cools, and only while it is powered and serves a room.
    check(objSrc[1].cools == nil and type(objSrc[2].cools) == "function", "the cooler's source answers cools, the heater's does not")
    local status0, roomOf0 = A.status, A.roomOf
    A.roomOf = function() return {} end
    A.status = function() return true end
    check(objSrc[2].cools(cooler) and A.outsideCoolerCools({ key = "1,2,0" }) and not A.outsideCoolerCools({ key = "9,9,0" }),
          "a running cooler in a room keeps the food cold")
    SandboxVars = { DazedPower = { RoomHeat = false } }
    check(objSrc[2].cools(cooler), "whatever the RoomHeat option says")
    SandboxVars = sv0
    A.status = function() return false, "IGUI_DazedPower_ApplOffline" end
    check(not objSrc[2].cools(cooler) and not A.outsideCoolerCools({ key = "1,2,0" }), "an unpowered cooler keeps nothing cold")
    A.status, A.roomOf = status0, roomOf0
    A.outsideCoolers[cooler] = nil

    -- Placing or lifting one marks its Dazed Climate room stale.
    local def = { getX = function() return 3 end, getY = function() return 4 end, getZ = function() return 0 end }
    local roomSq = E.square(46, 40, 0)
    roomSq.getRoom = function() return { getRoomDef = function() return def end } end
    local placed = E.object(P.sprite("heater", "ground", "standard", "off", "S"), roomSq)
    DazedClimate.Rooms.info = { ["3,4,0"] = { stale = false } }
    DazedClimate.Rooms.keyOf = function(d) return d:getX() .. "," .. d:getY() .. "," .. d:getZ() end
    A.markRoomStale(placed)
    check(DazedClimate.Rooms.info["3,4,0"].stale == true, "the heater's room is read again")
    DazedClimate = nil

    getClimateManager, SandboxVars, getGameTime = cm0, sv0, gt0
    if Cl then Cl.provider = provider0 end
end
