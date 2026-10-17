-- Checks for the player treadmill (0.11.0): the output model, recognising the vanilla gym tiles by sprite, the loader leaving
-- an unused treadmill alone, the authority's beat checks, and a single-player round trip -- wire it, sprint on it, step the
-- bridge, read the board row, get off, and a sprint that runs out of breath. Run from load_test.lua.
return function(check, E)
    local P, M = DazedPower.Parts, DazedPower.Model
    local MM = DazedPower.More.Model
    local T = DazedPower.Treadmill
    local B = DazedPower.More.Bridge
    local S = DazedPower.System
    local PFX = "recreational_sports_01_"
    ISBaseTimedAction.perform = ISBaseTimedAction.perform or function() end      -- the stand-in base has neither
    ISBaseTimedAction.stop = ISBaseTimedAction.stop or function() end

    ------------------------------------------------------------ the output model
    local function near(a, b) return math.abs(a - b) < 1e-9 end
    check(near(MM.treadmillOutput(0, "walk", 100, 100), 50) and near(MM.treadmillOutput(0, "run", 100, 100), 100)
        and near(MM.treadmillOutput(0, "sprint", 100, 100), 175), "fitness 0 makes 1x, 2x and 3.5x a pedal rider's 50 W")
    check(near(MM.treadmillOutput(10, "walk", 100, 100), 150) and near(MM.treadmillOutput(10, "run", 100, 100), 300)
        and near(MM.treadmillOutput(10, "sprint", 100, 100), 525), "fitness 10 makes 150, 300 and 525 W")
    check(near(MM.treadmillOutput(10, "run", 100, 250), 750) and near(MM.treadmillOutput(0, "walk", 100, 40), 20), "the sandbox scale multiplies it")
    check(near(MM.treadmillOutput(0, "walk", 50, 100), 50 * 0.7) and near(MM.treadmillOutput(0, "walk", 0, 100), 50 * 0.4)
        and near(MM.treadmillOutput(0, "walk", nil, 100), 50), "condition scales it by 0.4 + 0.6 x condition")
    check(MM.treadmillOutput(10, "jog", 100, 100) == 0 and MM.treadmillOutput(10, nil, 100, 100) == 0, "an unknown gait makes nothing")
    check(MM.validTreadmillMode("run") and not MM.validTreadmillMode("jog") and not MM.validTreadmillMode(3), "only the three gaits are valid")
    check(#MM.TREADMILL_MODE_ORDER == 3 and MM.TREADMILL_MODE_ORDER[3] == "sprint", "the gaits are listed in order")
    check(MM.treadmillFatiguePerMinute("walk") < MM.treadmillFatiguePerMinute("run") and MM.treadmillFatiguePerMinute("run") < MM.treadmillFatiguePerMinute("sprint")
        and MM.treadmillFatiguePerMinute("jog") == 0, "a harder gait tires faster")
    check(MM.treadmillEnduranceAfter(0.8, "walk", 30) == 0.8 and MM.treadmillEnduranceAfter(0.8, "run", 30) == 0.8, "walking and running spend no Endurance")
    check(near(MM.treadmillEnduranceAfter(0.8, "sprint", 10), 0.6) and MM.treadmillEnduranceAfter(0.1, "sprint", 10) == 0, "a sprint drains it, and never below zero")

    ------------------------------------------------------------ the eight tiles
    local function obj(sprite, x, y)
        return E.object(sprite, E.square(x, y, 0), { hasModData = function(self) return self.md.dazedpower ~= nil end })
    end
    -- facing -> master sprite, second sprite, where the second stands from the master
    local layout = { W = { 28, 29, 1, 0 }, N = { 31, 30, 0, 1 }, E = { 36, 37, 1, 0 }, S = { 39, 38, 0, 1 } }
    local made, x0 = {}, 700
    for facing, l in pairs(layout) do
        local m = obj(PFX .. l[1], x0, 700)
        local s2 = obj(PFX .. l[2], x0 + l[3], 700 + l[4])
        made[facing] = { m = m, s = s2 }
        local im, is = T.identify(m), T.identify(s2)
        check(im and im.kind == "treadmill" and im.mount == "ground" and im.tier == "standard" and im.facing == facing and im.piece == 1
            and im.pieces == 2 and im.master and im.state == "idle", facing .. ": the master tile is a treadmill")
        check(is and is.facing == facing and is.piece == 2 and not is.master, facing .. ": the second tile is piece 2")
        check(T.masterOf(m) == m and T.masterOf(s2) == m and P.master(s2) == m and P.master(m) == m, facing .. ": every piece resolves to the master")
        local pcs = P.piecesAround(s2)
        check(pcs[1] == m and pcs[2] == s2 and T.pieces(m)[2] == s2, facing .. ": both pieces are found from either")
        check(P.describe(m).kind == "treadmill" and P.partOf(s2) == "treadmill", facing .. ": describe and partOf call it a treadmill")
        x0 = x0 + 10
    end
    local scenery = obj(PFX .. "32", 800, 700)
    check(T.identify(scenery) == nil and P.describe(scenery) == nil and T.masterOf(scenery) == nil, "a neighbouring gym tile is not a treadmill")
    local plain = obj("floors_exterior_natural_01_0", 801, 700)
    check(P.describe(plain) == nil and P.master(plain) == nil, "other objects are untouched by the wraps")
    -- the master is not found when the neighbour is not loaded
    local lone = obj(PFX .. "29", 810, 700)
    check(T.masterOf(lone) == nil and P.master(lone) == nil and T.pieces(lone)[1] == nil, "a second tile with no master loaded resolves to nothing")

    check(M.wireLegal("treadmill", "controller") and M.wireLegal("treadmill", "treadmill") and not M.wireLegal("array", "treadmill"), "a treadmill wires like any source")
    check(P.SOURCE_KINDS.treadmill and M.SOURCE_KINDS.treadmill and not P.KIND_SET.treadmill, "a source kind with no sheet rows")
    check(P.itemFor("treadmill", "ground", "standard") == "Base.DazedTreadmill" and P.itemFor("pedal", "ground", "salvaged") == "Base.DazedPedalSalvaged",
        "the item is the treadmill's, and other kinds are unchanged")
    check(P.spriteInfo(PFX .. "39") == nil, "Power's sprite lookup does not claim the vanilla tile")
    local m = made.S.m
    check(P.setState(m, "on") == false and m:getSprite():getName() == PFX .. "39" and made.S.s:getSprite():getName() == PFX .. "38", "setState swaps no sprite")
    check(m.md.dazedpower == nil, "describing and setState made no ModData")
    check(MM.TREADMILL_MODES.walk.mult == 1 and MM.TREADMILL_MODES.run.mult == 2 and MM.TREADMILL_MODES.sprint.mult == 3.5, "gait multipliers")
    check(P.sandbox("TreadmillWatts") == 100 and P.PRESETS.TreadmillWatts[2] == 100, "the sandbox option defaults to 100")
    local sx, sy, dir = T.seat({ facing = "W" }, 10, 20)
    local nx, ny = T.seat({ facing = "N" }, 10, 20)
    check(sx == 11.0 and sy == 20.5 and nx == 10.5 and ny == 21.0 and dir == T.RUN_DIR.W, "the seat is the middle of the two tiles")

    ------------------------------------------------------------ the loader
    -- A treadmill that streams in with no Power data is left alone; one that was wired or used is registered.
    local reg0 = S.register
    local registered = {}
    S.register = function(o) registered[#registered + 1] = o end
    local fresh = obj(PFX .. "31", 820, 700)
    B.onLoadTreadmill(fresh)
    check(#registered == 0 and fresh.md.dazedpower == nil, "an unwired, unused treadmill gets no ModData and no registration")
    fresh.md.dazedpower = { sys = "1,1,0,controller" }
    B.onLoadTreadmill(fresh)
    check(#registered == 1 and registered[1] == fresh, "a wired one is registered")
    S.register = reg0
    local names, prio = {}, {}
    local onload0 = MapObjects.OnLoadWithSprite
    MapObjects.OnLoadWithSprite = function(name, fn, p) names[#names + 1] = name; prio[#prio + 1] = p end
    B.registerTreadmill()
    MapObjects.OnLoadWithSprite = onload0
    table.sort(names)
    check(#names == 4 and names[1] == PFX .. "28" and names[2] == PFX .. "31" and names[3] == PFX .. "36" and names[4] == PFX .. "39"
        and prio[1] == 7, "the four master tiles are hooked at priority 7")

    ------------------------------------------------------------ the authority's beat
    local clock = 10000
    local getTs0, getGt0 = getTimestampMs, getGameTime
    getTimestampMs = function() return clock end
    local function rider(x, y, fitness, num)
        local c = E.character(x, y, 0, fitness)
        function c:getPlayerNum() return num or 0 end
        function c:isDead() return false end
        return c
    end
    local sq = made.S.m:getSquare()
    local mx, my = sq:getX(), sq:getY()
    local a1, a2 = rider(mx + 0.5, my + 1.0, 4, 0), rider(mx + 1.5, my + 1.0, 9, 1)
    local args = { x = mx, y = my, z = 0, mode = "run" }
    check(T.beat(a1, { x = mx, y = my, z = 0, mode = "jog" }) == false and m.md.dazedpower == nil, "an unknown gait is refused")
    check(T.beat(a1, { x = mx, y = my + 1, z = 0, mode = "run" }) == false, "the second tile is not the master: refused")
    check(T.beat(a1, { x = mx, y = my, z = 0 }) == false and T.beat(a1, nil) == false and T.beat(nil, args) == false, "malformed beats are refused")
    local far = rider(mx + 20, my, 4, 0)
    check(T.beat(far, args) == false and m.md.dazedpower == nil, "out of reach is refused")
    args.fitness = 10                                                      -- a client's claim is never read
    check(T.beat(a1, args) == true, "a rider in reach is accepted")
    local d = m.md.dazedpower
    check(d and d.tmFitness == 4 and d.tmMode == "run" and d.tmBeat == clock and d.tmRider == 0, "the Fitness is the server's own, with the gait and the time")
    check(P.describe(m).state == "run", "describe reports the gait as the state")
    check(T.beat(a2, args) == false and d.tmRider == 0 and d.tmFitness == 4, "a second rider is refused while the first is beating")
    clock = clock + 1000
    check(T.beat(a1, { x = mx, y = my, z = 0, mode = "sprint" }) == true and d.tmMode == "sprint", "the same rider may change gait")
    clock = clock + T.FRESH_MS + 1
    check(T.beat(a2, args) == true and d.tmRider == 1 and d.tmFitness == 9, "once the first beat is stale, the second rider takes over")
    T.release(m, a1)
    check(d.tmRider == 1, "the old rider getting off does not clear the new one")
    T.release(m, a2)
    check(d.tmBeat == 0 and d.tmRider == nil and d.tmMode == nil and d.tmWatts == 0 and P.describe(m).state == "idle", "release clears the beat and the gait")
    T.beat(a1, args)
    clock = clock + T.FRESH_MS + 1
    check(T.sweep() == 1 and d.tmRider == nil and d.tmBeat == 0, "the sweep clears a rider whose beat stopped")

    ------------------------------------------------------------ a single-player round trip
    -- A controller, wired to the treadmill, a rider with Endurance, and the bridge stepping it.
    local instanceof0, getSq0 = instanceof, getSquare
    getSquare = function(x, y, z) return E.squares[x .. "," .. y .. "," .. (z or 0)] end
    instanceof = function(o, cls) return cls == "IsoGenerator" and type(o) == "table" and o.isGen == true end
    local ctrl = E.object(P.sprite("controller", "ground", "makeshift", "off", "S"), E.square(900, 700, 0), { isGen = true,
        isActivated = function() return false end, getFuel = function() return 0 end })
    P.data(ctrl)
    local tm = obj(PFX .. "39", 902, 700)
    local tm2 = obj(PFX .. "38", 902, 701)
    local tech = rider(901, 700, 3, 0)
    tech.getInventory = function() return tech.inv end
    SandboxVars.DazedPower.CableTilesPerWire = 0
    local ok, why = S.connect(tech, { ax = 902, ay = 700, az = 0, ak = "treadmill", bx = 900, by = 700, bz = 0, bk = "controller" })
    SandboxVars.DazedPower.CableTilesPerWire = nil
    check(ok and tm.md.dazedpower and tm.md.dazedpower.sys ~= nil, "a cable lands on the treadmill and makes its ModData: " .. tostring(why))
    check(tm2.md.dazedpower == nil, "the second tile carries nothing")

    -- the bridge's view: linked as a treadmill of this system
    local rec = { x = 900, y = 700, z = 0, arrays = {}, banks = {}, xfmrs = {}, gauges = {} }
    S.claimed = S.claimed or {}
    S.claimed[M.nodeKey(900, 700, 0, "controller")] = { [M.nodeKey(902, 700, 0, "treadmill")] = true }
    S.relink(rec)
    check(rec.dpm and #rec.dpm.treadmill == 1 and rec.dpm.treadmill[1] == tm, "the relink files the treadmill in the controller's system")

    local alt0 = DazedPower.Alternator
    DazedPower.Alternator = nil
    local function sources()
        local src = B.internals.liveSources(rec)
        local env = { temperature = 15 }
        local total = select(2, pcall(B.internals.stepSources, src, { arrays = {}, bank = {}, load = 0 }, 1, env, 0.9, 1))
        return src, total
    end
    local src0, total0 = sources()
    check(src0 and #src0.treadmills == 1 and src0.pedalW == 0 and total0 == 0 and src0.treadmills[1].watts == 0, "nobody on it: no watts")
    local rows0 = B.internals.sourceRows(rec, src0)
    check(#rows0 == 1 and rows0[1].k == "treadmill" and rows0[1].s == "idle" and rows0[1].w == 0, "an idle treadmill is a board row")

    -- the rider and the action
    local stats = { FATIGUE = 0.1, ENDURANCE = 0.9 }
    local FAT, END = {}, {}
    local cs0 = CharacterStat
    CharacterStat = { FATIGUE = FAT, ENDURANCE = END }
    local vals = { [FAT] = 0.1, [END] = 0.9 }
    local pl = rider(902.0, 701.0, 3, 0)
    pl.vars, pl.px, pl.py = {}, 901.0, 700.5
    function pl:getStats() return { get = function(_, st) return vals[st] end, set = function(_, st, v) vals[st] = v return true end } end
    function pl:SetVariable(k, v) assert(type(v) ~= "number", "SetVariable only takes text") self.vars[k] = v end
    function pl:setVariable(k, v) self.vars[k] = v end
    function pl:setX(v) self.x = v end
    function pl:setY(v) self.y = v end
    function pl:setLx(v) self.lx = v end
    function pl:setLy(v) self.ly = v end
    function pl:setDir(v) self.dir = v end
    function pl:shouldBeTurning() return false end
    function pl:isTimedActionInstant() return false end
    pl.x, pl.y = 901.0, 700.5
    IsoDirections = IsoDirections or { N = "N", E = "E", S = "S", W = "W" }
    local hours = 100
    getGameTime = function() return { getWorldAgeHours = function() return hours end } end

    local act = DPM_Treadmill:new(pl, tm2, "sprint")            -- made from the second tile: it acts on the master
    act.setActionAnim = function(self, n) self.anim = n end
    check(act.object == tm and act.mode == "sprint" and act:isValid(), "the action works on the master whichever tile was clicked")
    act:start()
    check(act.anim == "DazedTreadmill" and pl.vars.DazedTreadmillMode == "sprint" and pl.vars.DazedTreadmillSpeed == 1, "starting sets the mode and speed variables and the animation")
    check(pl.x == 902.5 and pl.y == 701.0 and pl.dir == IsoDirections[T.RUN_DIR.S], "the rider is put on the belt: " .. pl.x .. "," .. pl.y)
    tm.alpha, tm2.alpha = 0.2, 0.2
    function tm:setAlphaAndTarget(pn, a) self.alpha = a end
    function tm2:setAlphaAndTarget(pn, a) self.alpha = a end
    DPM_Pedal.keepSolid()
    check(tm.alpha == 1.0 and tm2.alpha == 1.0, "both tiles are kept fully drawn while it is ridden")

    act:update()
    local td = tm.md.dazedpower
    check(td.tmMode == "sprint" and td.tmFitness == 3 and td.tmBeat == clock, "the first frame beats at once")
    local src1, total1 = sources()
    local want = MM.treadmillOutput(3, "sprint", 100, 100)
    check(near(want, 280) and near(src1.pedalW, want) and near(total1, want), "a sprint at Fitness 3 makes 280 W and reaches the bus: " .. tostring(total1))
    check(src1.riding == 1 and td.tmWatts == want, "counted as riding, and the watts are written for the client")
    local rows1 = B.internals.sourceRows(rec, src1)
    check(rows1[1].k == "treadmill" and rows1[1].s == "sprint" and rows1[1].w == 280, "the board row reads the treadmill sprinting at 280 W")
    SandboxVars.DazedPower.TreadmillWatts = 50
    check(near(select(1, sources()).pedalW, 140), "the sandbox scale applies")
    SandboxVars.DazedPower.TreadmillWatts = nil
    td.condition = 50
    check(near(select(1, sources()).pedalW, 280 * 0.7), "condition applies")
    td.condition = nil

    -- a minute in a sprint: Fatigue up, Endurance down
    hours = hours + 1 / 60
    clock = clock + 100
    act:update()
    check(vals[FAT] > 0.1 and near(vals[END], 0.9 - 0.02), "a game minute of sprinting tires the rider and spends 0.02 Endurance")
    -- a beat is not repeated inside a second
    td.tmBeat = -1
    act:update()
    check(td.tmBeat == -1, "no second beat inside the interval")
    clock = clock + DazedPower.More.Actions.PEDAL_BEAT_MS
    act:update()
    check(td.tmBeat == clock, "and one after it")

    -- the rider is held on the belt
    pl.x, pl.y = 905, 705
    act:update()
    check(pl.x == 902.5 and pl.y == 701.0, "something nudging the rider does not move them off the belt")

    -- getting off
    act:complete()
    local src2 = sources()
    check(td.tmBeat == 0 and src2.pedalW == 0 and src2.treadmills[1].mode == nil, "complete() ends the watts at once")
    check(B.internals.sourceRows(rec, src2)[1].s == "idle", "and the board row goes idle")
    act:dismount()
    check(pl.x == 901.0 and pl.y == 700.5, "getting off puts the rider back where they stood")
    check(DPM_Pedal.solid[tm] == nil and DPM_Pedal.solid[tm2] == nil, "and the tiles are released to fade as usual")

    -- a stale beat stops the watts without complete()
    clock = clock + 10
    check(T.beat(pl, { x = 902, y = 700, z = 0, mode = "walk" }), "a walk beat")
    check(near(select(1, sources()).pedalW, 80), "a walk at Fitness 3 is 80 W")
    clock = clock + T.FRESH_MS + 1
    local src3 = sources()
    check(src3.pedalW == 0 and td.tmMode == nil and td.tmRider == nil, "a beat that stops ages out, and clears the rider")

    -- low Endurance drops a sprint to a run
    vals[END] = 0.16
    local act2 = DPM_Treadmill:new(pl, tm, "sprint")
    act2.setActionAnim = function(self, n) self.anim = n end
    act2:start()
    check(act2.mode == "sprint" and pl.vars.DazedTreadmillMode == "sprint", "enough Endurance to start a sprint")
    hours = hours + 1 / 60
    clock = clock + 10
    act2:update()
    check(act2.mode == "run" and pl.vars.DazedTreadmillMode == "run" and near(vals[END], 0.14), "below the minimum the sprint drops to a run")
    check(td.tmMode == "run" or td.tmMode == "sprint", "the beat names the gait")
    clock = clock + DazedPower.More.Actions.PEDAL_BEAT_MS
    hours = hours + 1 / 60
    act2:update()
    check(td.tmMode == "run" and near(vals[END], 0.14), "the next beat says run, and a run spends no Endurance")
    act2:dismount()
    vals[END] = 0.05
    local act3 = DPM_Treadmill:new(pl, tm, "sprint")
    act3.setActionAnim = function(self, n) self.anim = n end
    act3:start()
    check(act3.mode == "run", "a sprint asked of empty legs starts as a run")
    act3:dismount()

    -- a second rider is turned off the machine in single player
    T.release(tm)
    local other = rider(902.5, 701.0, 9, 1)
    check(T.beat(other, { x = 902, y = 700, z = 0, mode = "run" }), "somebody else is on it")
    local act4 = DPM_Treadmill:new(pl, tm, "run")
    act4.setActionAnim = function(self, n) self.anim = n end
    act4.forceStop = function(self) self.stopped = true end
    act4:start()
    clock = clock + 10
    act4:update()
    check(act4.stopped == true, "a refused beat gets the second rider off")
    act4:dismount()

    -- changing gait on the belt: the next action takes over without the rider stepping off
    do
        local TM = DazedPower.TreadmillMenu
        local q = { queue = {} }
        local gtq0, add0 = ISTimedActionQueue.getTimedActionQueue, ISTimedActionQueue.add
        ISTimedActionQueue.getTimedActionQueue = function() return q end
        ISTimedActionQueue.add = function(a) q.queue[#q.queue + 1] = a end
        pl.x, pl.y = 901.0, 700.5
        local g1 = DPM_Treadmill:new(pl, tm, "walk")
        g1.setActionAnim = function() end
        g1:start()
        q.queue = { g1 }
        local forced = 0
        g1.forceComplete = function() forced = forced + 1 end
        TM.onRun(nil, tm2, pl, "run")
        check(#q.queue == 2 and q.queue[2].mode == "run" and q.queue[2].object == tm and forced == 1,
            "picking a gait on the belt queues a new action and ends the running one")
        local g2 = q.queue[2]
        g2.setActionAnim = function() end
        g1:perform()
        check(pl.x == 902.5 and pl.y == 701.0 and DPM_Pedal.solid[tm] ~= nil, "the first gait hands over: the rider stays on the belt")
        q.queue = { g2 }
        g2:start()
        check(pl.vars.DazedTreadmillMode == "run" and g2.mountedFrom.x == 901.0 and g2.mountedFrom.y == 700.5, "the second gait remembers where the rider first stood")
        g2:perform()
        check(pl.x == 901.0 and pl.y == 700.5 and DPM_Pedal.solid[tm] == nil, "and getting off puts them back there")
        ISTimedActionQueue.getTimedActionQueue, ISTimedActionQueue.add = gtq0, add0
    end

    -- the status line and the rows, from the menu
    local TM = DazedPower.TreadmillMenu
    check(TM ~= nil and TM.busy({ tmRider = 1 }, pl) and not TM.busy({ tmRider = 0 }, pl) and not TM.busy({}, pl), "the menu knows when somebody else is on it")
    vals[END] = 0.05
    check(TM.refusal({}, pl, "sprint") == "ContextMenu_DazedPower_TreadmillTooWinded" and TM.refusal({}, pl, "run") == nil, "a sprint is greyed with no breath")
    vals[END] = 1
    check(TM.refusal({ tmRider = 1 }, pl, "walk") == "ContextMenu_DazedPower_TreadmillBusy", "all three are greyed while somebody else is on it")
    vals[FAT] = 0.96
    check(TM.refusal({}, pl, "walk") == "Tooltip_DazedPower_TooTired", "and when too tired")
    vals[FAT] = 0.1
    local rows, ctx = {}, nil
    ctx = { addOption = function(_, text, ...) local o = { text = text, args = { ... } } rows[#rows + 1] = o return o end }
    local addTip0 = ISWorldObjectContextMenu.addToolTip
    ISWorldObjectContextMenu.addToolTip = function() return { setName = function() end } end
    T.release(tm)
    td.tmWatts = 200
    TM.rows(ctx, nil, tm, pl, nil)
    ISWorldObjectContextMenu.addToolTip = addTip0
    check(#rows == 4 and rows[1].notAvailable and rows[2].text == "ContextMenu_DazedPower_TreadmillWalk" and rows[4].text == "ContextMenu_DazedPower_TreadmillSprint"
        and not rows[2].notAvailable, "a status line and three gait rows")
    check(TM.status(tm):find("ContextMenu_DazedPower_TreadmillMaking", 1, true) ~= nil, "the status line says what it makes")

    -- the boot line
    local sm0 = getSpriteManager
    getSpriteManager = function() return { getNamedMap = function() return { containsKey = function(_, n) return n ~= PFX .. "39" end } end } end
    local n0 = #E.printed
    T.booted = false
    T.boot()
    getSpriteManager = sm0
    check(E.printed[#E.printed]:find("MISSING", 1, true) and E.printed[#E.printed]:find("recreational_sports_01_39 not found", 1, true), "the boot line says when _39 is missing")
    T.booted = true

    DazedPower.Alternator = alt0
    CharacterStat = cs0
    instanceof, getSquare = instanceof0, getSq0
    getTimestampMs, getGameTime = getTs0, getGt0
end
