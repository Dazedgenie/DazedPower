-- Checks for the turning machines (DP_TurnFx on the shared DP_MachineFx, 0.14.0): the water wheel, the zombie
-- treadwheel and the windsock. State to frame, speed scaling, the cull, off screen, pause, cleanup, the sandbox
-- switch, no jobs when none is loaded, and the machine list now carrying windsocks. Run from load_test.lua.
return function(check, E)
    local P, M, F, T = DazedPower.Parts, DazedPower.MachineFx, DazedPower.TurnFx, DazedCore.Tick
    check(F ~= nil and M.kinds.hydro and M.kinds.treadwheel and M.kinds.windsock and M.kinds.windmill,
          "the shared module carries the water wheel, treadwheel, windsock and windmill")

    -- State -> sprite.
    local function frameOf(name) local i = P.spriteInfo(name) return i and (i.frame or ("plain:" .. i.state)) end
    local seen = {}
    for k = 0, 3 do seen[#seen + 1] = frameOf(M.pick("hydro", "standard", "turning", "S", k)) end
    check(seen[1] == "spin1" and seen[2] == "spin2" and seen[3] == "spin3" and seen[4] == "spin1", "a turning wheel walks three frames and loops")
    check(M.pick("hydro", "standard", "still", "S", 2) == P.sprite("hydro", "ground", "standard", "still", "S"), "a still wheel keeps its plain sprite")
    seen = {}
    for k = 0, 4 do seen[#seen + 1] = frameOf(M.pick("treadwheel", "standard", "walking", "E", k)) end
    check(seen[1] == "walk1" and seen[4] == "walk4" and seen[5] == "walk1", "a walked treadwheel walks four stride frames")
    check(M.pick("treadwheel", "standard", "empty", "E", 1) == P.sprite("treadwheel", "ground", "standard", "empty", "E"), "an empty wheel stays plain")
    seen = {}
    for k = 0, 3 do seen[#seen + 1] = frameOf(M.pick("windsock", "basic", "full", "N", k)) end
    check(seen[1] == "plain:full" and seen[2] == "full1" and seen[3] == "plain:full" and seen[4] == "full2",
          "a full sock swings plain, one side, plain, the other")
    check(frameOf(M.pick("windsock", "basic", "half", "W", 1)) == "half1" and M.pick("windsock", "basic", "limp", "W", 1)
          == P.sprite("windsock", "ground", "basic", "limp", "W"), "a half sock flutters too; a limp one hangs still")
    local hi = P.spriteInfo(M.pick("hydro", "standard", "turning", "N", 1))
    check(hi.kind == "hydro" and hi.state == "turning" and hi.facing == "N", "a frame reads back as the machine, state and facing")

    -- Speed.
    check(F.hydroRate(100) == F.HYDRO_FPS and F.hydroRate(0) == F.HYDRO_FPS * F.HYDRO_WORN and F.hydroRate(nil) == F.HYDRO_FPS
          and F.hydroRate(50) < F.hydroRate(90), "a worn wheel turns slower")
    check(F.treadRate({ treadWatts = 80 }) == F.TREAD_FPS and F.treadRate({ treadWatts = 140, treadLured = true }) > F.TREAD_FPS
          and F.treadRate({ treadWatts = 32 }) < F.TREAD_FPS and F.treadRate({ treadWatts = 0 }) == F.TREAD_FPS,
          "lured faster, a crawler slower, slipping slats still walked")
    check(M.kinds.windsock.rate("full") > M.kinds.windsock.rate("half"), "a streaming sock flutters faster than a drooping one")

    -- Windsocks are followed by the machine list now (they are no power source).
    local Mc = DazedPower.More.Machines
    local function spr(name) return { getName = function() return name end } end
    check(Mc.isMachine({ getSprite = function() return spr(P.sprite("windsock", "ground", "basic", "half", "S")) end })
          and not Mc.isMachine({ getSprite = function() return spr(P.sprite("vane", "ground", "basic", "set", "S")) end }),
          "the machine list takes windsocks, not vanes")

    -- A small world.
    local saved = { getCell = getCell, getSprite = getSprite, getNumActivePlayers = getNumActivePlayers, getSpecificPlayer = getSpecificPlayer,
                    getTimestampMs = getTimestampMs, isGamePaused = isGamePaused }
    local squares = {}
    local function square(x, y)
        local sq = { x = x, y = y, z = 0, objs = {}, onScreen = true }
        function sq:getX() return self.x end
        function sq:getY() return self.y end
        function sq:getZ() return self.z end
        function sq:IsOnScreen() return self.onScreen end
        function sq:getObjects() local o = self.objs return { size = function() return #o end, get = function(_, i) return o[i + 1] end } end
        squares[x .. "," .. y] = sq
        return sq
    end
    local cell = { addLamppost = function() end, removeLamppost = function() end }
    function cell:getGridSquare(x, y, z) return z == 0 and squares[x .. "," .. y] or nil end
    local function machine(kind, tier, state, x, y, d, facing)
        local sq = square(x, y)
        local md = { dazedpower = d or {} }
        md.dazedpower.state = state
        local o = { sprite = spr(P.sprite(kind, "ground", tier, state, facing or "S")), swaps = 0, md = md, sq = sq }
        function o:getSprite() return self.sprite end
        function o:setSprite(s) self.sprite = s; self.swaps = self.swaps + 1 end
        function o:getSquare() return self.gone and nil or self.sq end
        function o:getObjectIndex() return self.gone and -1 or 0 end
        function o:hasModData() return true end
        function o:getModData() return self.md end
        function o:set(st, f) self.sprite = spr(P.sprite(kind, "ground", tier, st, f or "S")); self.md.dazedpower.state = st end
        sq.objs[1] = o
        return o
    end
    local player = { x = 52, y = 61 }
    function player:getX() return self.x end
    function player:getY() return self.y end
    function player:getZ() return 0 end
    function player:isDead() return false end
    local t, paused = 0, false
    getCell = function() return cell end
    getSprite = function(name) return spr(name) end
    getNumActivePlayers = function() return 1 end
    getSpecificPlayer = function() return player end
    getTimestampMs = function() return t end
    isGamePaused = function() return paused end
    local function run(ms) local stop = t + ms while t < stop do t = t + 16; T.onTick() end end
    local function frameName(o) return P.spriteInfo(o.sprite:getName()).frame end

    M.reset()
    check(M.count == 0 and not T.has(M.SCAN_ID) and not T.has(M.FRAME_ID), "no jobs while no machine is loaded")
    local hy = machine("hydro", "standard", "turning", 50, 60, { condition = 100 })
    local tw = machine("treadwheel", "standard", "walking", 52, 60, { treadWatts = 80 })
    local ws = machine("windsock", "basic", "full", 54, 60)
    local vane = machine("vane", "basic", "set", 56, 60)
    M.consider(vane)
    check(M.count == 0, "a weather vane is not followed")
    M.consider(hy); M.consider(tw); M.consider(ws)
    check(M.count == 3 and T.has(M.SCAN_ID), "three turning machines, one scan job")
    run(1100)
    check(T.has(M.FRAME_ID) and #M.active == 3 and M.frameMs == M.FAST_MS, "all three near and on screen share the one (fast) frame job")
    local s1 = { hy.swaps, tw.swaps, ws.swaps }
    run(2000)
    local d = { hy.swaps - s1[1], tw.swaps - s1[2], ws.swaps - s1[3] }
    check(math.abs(d[1] - 2 * F.HYDRO_FPS) <= 2 and math.abs(d[2] - 2 * F.TREAD_FPS) <= 2 and math.abs(d[3] - 2 * F.SOCK_FPS.full) <= 2,
          string.format("each turns at its own speed: %d, %d, %d frames in 2 s", d[1], d[2], d[3]))
    check(frameName(hy) and frameName(hy):sub(1, 4) == "spin" and frameName(tw):sub(1, 4) == "walk", "each shows its own frames")

    -- Speed follows the synced ModData at the next scan.
    tw.md.dazedpower.treadLured = true; hy.md.dazedpower.condition = 0
    run(1100)
    s1 = { hy.swaps, tw.swaps }
    run(2000)
    check(tw.swaps - s1[2] > d[2] + 2 and hy.swaps - s1[1] < d[1] - 2, "a lured zombie walks faster, a worn wheel drags")
    tw.md.dazedpower.treadLured = nil; hy.md.dazedpower.condition = 100

    -- Pause: nothing moves, and nothing jumps after.
    paused = true
    s1 = { hy.swaps, tw.swaps, ws.swaps }
    run(2000)
    check(hy.swaps == s1[1] and tw.swaps == s1[2] and ws.swaps == s1[3], "paused, every machine holds its frame")
    paused = false
    run(300)
    check(hy.swaps - s1[1] <= 4, "unpaused, no catch-up spin")

    -- The server's flips: the zombie released (empty), the sock turning with the wind (a new facing).
    tw:set("empty")
    ws:set("full", "E")
    run(300)
    check(frameName(tw) == nil and P.spriteInfo(tw.sprite:getName()).state == "empty", "an emptied wheel keeps the plain sprite at once")
    check(P.spriteInfo(ws.sprite:getName()).facing == "E", "the sock follows the wind's new facing before the next scan")
    local sp = tw.swaps
    run(1500)
    check(tw.swaps == sp and #M.active == 2, "an empty wheel costs no swaps")
    tw:set("walking")
    run(1300)
    check(frameName(tw) and frameName(tw):sub(1, 4) == "walk", "walked again, it strides again")
    -- The sock falls limp: its plain sprite.
    ws:set("limp", "E")
    run(1300)
    check(frameName(ws) == nil and P.spriteInfo(ws.sprite:getName()).state == "limp", "a limp sock hangs still")
    ws:set("half", "E")
    run(1300)

    -- Out of range: frames stop and the frame shown stays.
    player.x = 52 + M.RANGE + 5
    run(1300)
    s1 = { hy.swaps, tw.swaps, ws.swaps }
    run(800)
    check(not T.has(M.FRAME_ID) and hy.swaps == s1[1] and tw.swaps == s1[2] and ws.swaps == s1[3], "out of range: no frame job, no swaps")
    player.x = 52
    -- Off screen but near: the same.
    hy.sq.onScreen, tw.sq.onScreen, ws.sq.onScreen = false, false, false
    run(1300)
    s1 = { hy.swaps, tw.swaps, ws.swaps }
    run(800)
    check(not T.has(M.FRAME_ID) and hy.swaps == s1[1] and tw.swaps == s1[2], "off screen: no frame job, no swaps")
    hy.sq.onScreen, tw.sq.onScreen, ws.sq.onScreen = true, true, true
    run(1300)
    check(#M.active == 3, "back on screen, all three turn")

    -- The option off: plain sprites back (a culled one that kept its frame too), no frames.
    player.x = 52 + M.RANGE + 5
    run(1300)
    local culledFrame = frameName(hy)
    player.x = 52
    SandboxVars.DazedPower.MachineEffects = false
    run(1300)
    local plain = true
    for _, o in ipairs({ hy, tw, ws }) do if frameName(o) ~= nil then plain = false end end
    check(plain and not T.has(M.FRAME_ID), "option off: every machine on its plain sprite (culled on " .. tostring(culledFrame) .. " first)")
    s1 = { hy.swaps, tw.swaps, ws.swaps }
    run(2000)
    check(hy.swaps == s1[1] and tw.swaps == s1[2] and ws.swaps == s1[3], "option off: no swaps after")
    SandboxVars.DazedPower.MachineEffects = nil
    run(1300)
    check(T.has(M.FRAME_ID) and #M.active == 3, "option on again: they turn again")

    -- Cleanup: picked up (the removal event), and unloaded with no event (the scan's alive check).
    M.onRemoved(hy)
    check(M.count == 2 and M.tracked[hy] == nil, "a removed wheel is forgotten at once")
    tw.gone = true
    run(1300)
    check(M.count == 1, "an unloaded treadwheel is dropped at the next scan")
    M.onRemoved(ws)
    run(1300)
    check(M.count == 0 and not T.has(M.SCAN_ID) and not T.has(M.FRAME_ID), "none left: both jobs gone")

    M.reset()
    for k, v in pairs(saved) do _G[k] = v end
end
