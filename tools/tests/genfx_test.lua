-- Checks for the gas engines' effects (DP_GenFx on the shared DP_MachineFx, 0.13.0): wood gas, petrol and propane
-- state to frame, lights by kind and load, the cull, pause, cleanup, the sandbox switch, the shared light cap and the
-- shared jobs. Run from load_test.lua, after steamfx_test.lua.
return function(check, E)
    local P, M, G, F, T = DazedPower.Parts, DazedPower.MachineFx, DazedPower.GenFx, DazedPower.SteamFx, DazedCore.Tick
    check(M ~= nil and G ~= nil and M.kinds.woodgas and M.kinds.petrol and M.kinds.propane and M.kinds.steam,
          "the shared effects module carries steam, wood gas, petrol and propane")
    check(F.SCAN_ID == M.SCAN_ID and F.FRAME_ID == M.FRAME_ID and F.MAX_LIGHTS == M.MAX_LIGHTS and F.RANGE == M.RANGE,
          "steam reads its jobs, cap and range from the shared module")

    -- State -> sprite.
    local function frameOf(name) local i = P.spriteInfo(name) return i and (i.frame or i.state) end
    local seen = {}
    for k = 0, 4 do seen[#seen + 1] = frameOf(G.pick("woodgas", "salvaged", "running", "S", k)) end
    check(seen[1] == "fire1" and seen[2] == "fire2" and seen[4] == "fire4" and seen[5] == "fire1", "wood gas running walks four flame frames")
    check(frameOf(G.pick("woodgas", "makeshift", "warming", "E", 3)) == "embers", "wood gas warming shows embers")
    check(G.pick("woodgas", "workshop", "off", "N", 1) == P.sprite("woodgas", "ground", "workshop", "off", "N")
          and G.pick("woodgas", "workshop", "broken", "N", 1) == P.sprite("woodgas", "ground", "workshop", "broken", "N"),
          "wood gas off and broken keep the plain sprite")
    seen = {}
    for k = 0, 3 do seen[#seen + 1] = frameOf(G.pick("petrol", "workshop", "running", "W", k)) end
    check(seen[1] == "run1" and seen[3] == "run3" and seen[4] == "run1", "petrol running walks three shake frames")
    seen = {}
    for k = 0, 3 do seen[#seen + 1] = frameOf(G.pick("propane", "makeshift", "running", "E", k)) end
    check(seen[1] == "flame1" and seen[2] == "flame2" and seen[4] == "flame1", "propane running walks three flame frames")
    for _, kind in ipairs({ "petrol", "propane" }) do
        for _, st in ipairs({ "off", "broken" }) do
            check(G.pick(kind, "salvaged", st, "S", 2) == P.sprite(kind, "ground", "salvaged", st, "S"), kind .. " " .. st .. " keeps the plain sprite")
        end
    end
    local pi = P.spriteInfo(G.pick("propane", "workshop", "running", "N", 1))
    check(pi.kind == "propane" and pi.tier == "workshop" and pi.facing == "N" and pi.state == "running", "a frame keeps kind, tier and facing")

    -- Lights by kind and load.
    local l0, l1 = G.woodgasLight("fire", "salvaged", 0), G.woodgasLight("fire", "salvaged", 1600)
    check(l0.radius == G.WOODGAS_RADIUS[1] and l1.radius == G.WOODGAS_RADIUS[2] and l1.r > l0.r and l1.r > l1.b,
          "the wood gas light is warm and grows with the load")
    check(G.woodgasLight("fire", "salvaged", 1550).radius == l1.radius, "a wavering wood gas load stays in its band")
    check(G.woodgasLight("embers", "makeshift", 0) == G.EMBER_LIGHT and G.woodgasLight(nil, "workshop", 900) == nil, "embers glow dimly")
    local pl = M.kinds.propane.light("flame", "salvaged", { genWatts = 2000 })
    check(pl and pl.b > pl.r and pl.radius == 2 and M.kinds.propane.light("flame", "salvaged", { genWatts = 0 }) == pl,
          "propane casts a faint blue glow whatever the load")
    check(M.kinds.petrol.light == nil, "petrol casts no light")

    -- A small world: one square per engine, a cell with a lamppost list, a player we can move.
    local saved = { getCell = getCell, getSprite = getSprite, getNumActivePlayers = getNumActivePlayers, getSpecificPlayer = getSpecificPlayer,
                    getTimestampMs = getTimestampMs, IsoLightSource = IsoLightSource, getClimateManager = getClimateManager,
                    isGamePaused = isGamePaused }
    local lamps, nLamps = {}, 0
    local function spr(name) return { getName = function() return name end } end
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
    local cell = {}
    function cell:getGridSquare(x, y, z) return z == 0 and squares[x .. "," .. y] or nil end
    function cell:addLamppost(l) lamps[l] = true; nLamps = nLamps + 1 end
    function cell:removeLamppost(l) if lamps[l] then lamps[l] = nil; nLamps = nLamps - 1 end end
    local function engine(kind, tier, state, x, y, d)
        local sq = square(x, y)
        local md = { dazedpower = d or {} }
        md.dazedpower.state = state
        local o = { sprite = spr(P.sprite(kind, "ground", tier, state, "S")), swaps = 0, md = md, sq = sq }
        function o:getSprite() return self.sprite end
        function o:setSprite(s) self.sprite = s; self.swaps = self.swaps + 1 end
        function o:getSquare() return self.gone and nil or self.sq end
        function o:getObjectIndex() return self.gone and -1 or 0 end
        function o:hasModData() return true end
        function o:getModData() return self.md end
        function o:set(st) self.sprite = spr(P.sprite(kind, "ground", tier, st, "S")); self.md.dazedpower.state = st end
        sq.objs[1] = o
        return o
    end
    local wg = engine("woodgas", "salvaged", "running", 50, 60, { genWatts = 1600 })
    local pe = engine("petrol", "makeshift", "running", 52, 60, { genWatts = 400 })
    local pr = engine("propane", "workshop", "running", 54, 60, { genWatts = 900 })
    local player = { x = 52, y = 61 }
    function player:getX() return self.x end
    function player:getY() return self.y end
    function player:getZ() return 0 end
    function player:isDead() return false end
    local daylight, t, paused = 0.1, 0, false
    getCell = function() return cell end
    getSprite = function(name) return spr(name) end
    getNumActivePlayers = function() return 1 end
    getSpecificPlayer = function() return player end
    getTimestampMs = function() return t end
    getClimateManager = function() return { getDayLightStrength = function() return daylight end } end
    isGamePaused = function() return paused end
    IsoLightSource = { new = function(x, y, z, r, g, b, radius)
        local l = { x = x, y = y, z = z, r = r, g = g, b = b, radius = radius, active = true }
        function l:setActive(v) self.active = v end
        return l
    end }
    local function run(ms) local stop = t + ms while t < stop do t = t + 33; T.onTick() end end
    local function lightAt(x)
        for l in pairs(lamps) do if l.x == x then return l end end
    end
    local function frameName(o) return P.spriteInfo(o.sprite:getName()).frame end

    M.reset()
    check(M.count == 0 and not T.has(M.SCAN_ID) and not T.has(M.FRAME_ID), "no jobs while no engine is loaded")
    -- Something that is not a registered engine (a pedal generator) is not followed.
    local ped = engine("pedal", "salvaged", "on", 40, 40)
    M.consider(ped)
    check(M.count == 0 and not T.has(M.SCAN_ID), "a pedal generator starts nothing")
    M.consider(wg); M.consider(pe); M.consider(pr)
    check(M.count == 3 and T.has(M.SCAN_ID), "three engines, one scan job")
    run(1200)
    check(T.has(M.FRAME_ID) and #M.active == 3, "all three running near and on screen share the one frame job")
    local s1 = { wg.swaps, pe.swaps, pr.swaps }
    run(900)
    check(wg.swaps > s1[1] and pe.swaps > s1[2] and pr.swaps > s1[3], "each walks its frames")
    check(frameName(wg):sub(1, 4) == "fire" and frameName(pe):sub(1, 3) == "run" and frameName(pr):sub(1, 5) == "flame",
          "each shows its own kind's frames")
    check(nLamps == 2 and lightAt(50) and lightAt(54) and not lightAt(52), "at night: wood gas and propane lit, petrol not")
    local lw = lightAt(50)
    check(lw.radius == G.WOODGAS_RADIUS[2] and lw.r > lw.b and lightAt(54).b > lightAt(54).r, "a wide warm pool at full load, a blue glow")

    -- Less load: the wood gas light is rebuilt smaller, never two at once.
    wg.md.dazedpower.genWatts = 100
    run(1100)
    local lw2 = lightAt(50)
    check(nLamps == 2 and lw2 ~= lw and lw2.radius == G.WOODGAS_RADIUS[1] and lw.active == false, "a lighter load swaps the light, the old one off")

    -- Pause: nothing moves.
    paused = true
    s1 = { wg.swaps, pe.swaps, pr.swaps }
    run(1500)
    check(wg.swaps == s1[1] and pe.swaps == s1[2] and pr.swaps == s1[3], "paused, every engine's frames hold")
    paused = false

    -- Daytime: no light.
    daylight = 0.9
    run(1100)
    check(nLamps == 0, "no light in daylight")
    daylight = 0.1
    run(1100)

    -- The server flips the wood gas engine to warming: embers and a dim glow; petrol switched off: plain sprite.
    wg:set("warming"); pe:set("off")
    run(1300)
    check(frameName(wg) == "embers" and P.spriteInfo(wg.sprite:getName()).state == "warming", "warming wood gas shows embers")
    check(lightAt(50) and lightAt(50).radius == G.EMBER_LIGHT.radius, "embers cast the dim glow")
    check(frameName(pe) == nil and P.spriteInfo(pe.sprite:getName()).state == "off" and #M.active == 1, "petrol off keeps its plain sprite, out of the frame job")
    local sp = pe.swaps
    run(900)
    check(pe.swaps == sp, "an engine that is off costs no swaps")
    -- The server's flip back to running between scans: the frame job notices the plain sprite and keeps going.
    pe:set("running")
    run(1300)
    check(frameName(pe) and frameName(pe):sub(1, 3) == "run" and #M.active == 2, "petrol running again walks its frames")
    -- Broken propane: plain sprite, no light.
    pr:set("broken")
    run(1300)
    check(frameName(pr) == nil and not lightAt(54), "broken propane: plain sprite, no light")
    pr:set("running"); wg:set("running")
    run(1300)

    -- The player walks off: no lights, frames stop, the frames shown stay.
    player.x = 52 + M.RANGE + 5
    run(1300)
    s1 = { wg.swaps, pe.swaps, pr.swaps }
    run(600)
    check(nLamps == 0 and not T.has(M.FRAME_ID) and wg.swaps == s1[1] and pe.swaps == s1[2] and pr.swaps == s1[3],
          "out of range: no light, no frame job, no swaps")
    player.x = 52

    -- Off screen but near: no frames, the lights stay.
    wg.sq.onScreen, pe.sq.onScreen, pr.sq.onScreen = false, false, false
    run(1300)
    s1 = { wg.swaps, pe.swaps, pr.swaps }
    run(600)
    check(not T.has(M.FRAME_ID) and wg.swaps == s1[1] and pr.swaps == s1[3] and nLamps == 2, "off screen: frames stop, the lights stay")
    wg.sq.onScreen, pe.sq.onScreen, pr.sq.onScreen = true, true, true
    run(1300)

    -- The option off: plain sprites back, every light out.
    SandboxVars.DazedPower.MachineEffects = false
    run(1300)
    local plain = true
    for _, o in ipairs({ wg, pe, pr }) do
        local i = P.spriteInfo(o.sprite:getName())
        if i.frame ~= nil or i.state ~= "running" then plain = false end
    end
    check(plain and nLamps == 0 and not T.has(M.FRAME_ID), "option off: plain sprites, no light, no frames")
    s1 = { wg.swaps, pe.swaps, pr.swaps }
    run(2000)
    check(wg.swaps == s1[1] and pe.swaps == s1[2] and pr.swaps == s1[3], "option off: no swaps after")
    SandboxVars.DazedPower.MachineEffects = nil
    run(1300)
    check(nLamps == 2 and T.has(M.FRAME_ID) and #M.active == 3, "option on again: the effects come back")

    -- The shared light cap: ten lit engines (wood gas and steam together) hold at most MAX_LIGHTS.
    local extra = {}
    for i = 1, 5 do
        extra[#extra + 1] = engine("woodgas", "workshop", "running", 50 + i, 70, { genWatts = 3000 })
        extra[#extra + 1] = engine("steam", "salvaged", "running", 50 + i, 72, { steamWatts = 900 })
    end
    for _, o in ipairs(extra) do M.consider(o) end
    run(1300)
    check(M.count == 13 and nLamps == M.MAX_LIGHTS and M.lights == M.MAX_LIGHTS, "every kind shares the cap of " .. M.MAX_LIGHTS .. " lights: " .. nLamps)
    check(T.has(M.FRAME_ID) and #M.active == 13, "steam and the gas engines share the one frame job")
    for _, o in ipairs(extra) do M.onRemoved(o) end
    run(1300)
    check(M.count == 3 and nLamps == 2, "removed ones give their lights back")

    -- Picked up: the removal event takes the light at once.
    M.onRemoved(pr)
    check(not lightAt(54) and M.count == 2, "removal drops the propane light at once")
    -- Unloaded with no event: the scan's alive check finds it within a second.
    wg.gone = true
    run(1300)
    check(not lightAt(50) and M.count == 1, "a wood gas engine that left without an event loses its light at the next scan")
    M.onRemoved(pe)
    run(1300)
    check(M.count == 0 and not T.has(M.SCAN_ID) and not T.has(M.FRAME_ID) and nLamps == 0, "no engines left: both jobs gone, no lights")

    M.reset()
    for k, v in pairs(saved) do _G[k] = v end
end
