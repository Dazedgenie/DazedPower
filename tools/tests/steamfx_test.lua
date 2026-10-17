-- Checks for the steam engine's fire (DP_SteamFx, 0.12.0): state to frame, light by load, the cull, cleanup and the
-- sandbox switch. Run from load_test.lua.
return function(check, E)
    local P, F, T = DazedPower.Parts, DazedPower.SteamFx, DazedCore.Tick
    check(F ~= nil and F.pick ~= nil, "the steam effects module loads")

    -- State -> sprite.
    local function frameOf(name) local i = P.spriteInfo(name) return i and (i.frame or i.state) end
    local seen = {}
    for k = 0, 4 do seen[#seen + 1] = frameOf(F.pick("salvaged", "running", "S", k)) end
    check(seen[1] == "fire1" and seen[2] == "fire2" and seen[4] == "fire4" and seen[5] == "fire1", "running walks the four flame frames")
    check(frameOf(F.pick("makeshift", "warming", "E", 3)) == "embers", "warming shows the banked embers")
    check(F.pick("workshop", "cold", "N", 2) == P.sprite("steam", "ground", "workshop", "cold", "N"), "cold keeps the plain sprite")
    check(F.pick("workshop", "broken", "W", 1) == P.sprite("steam", "ground", "workshop", "broken", "W"), "broken keeps the plain sprite")
    local fw = P.spriteInfo(F.pick("workshop", "running", "W", 2))
    check(fw.tier == "workshop" and fw.facing == "W" and fw.kind == "steam" and fw.state == "running", "a frame keeps tier and facing")
    check(F.stateOf(fw, { state = "warming" }) == "warming" and F.stateOf(P.spriteInfo(P.sprite("steam", "ground", "salvaged", "cold", "S")),
        { state = "running" }) == "cold", "a plain sprite's state wins over ModData; a frame defers to it")

    -- Light by load.
    local l0, l1 = F.lightFor("fire", "salvaged", 0), F.lightFor("fire", "salvaged", 900)
    check(l0.radius == F.FIRE_RADIUS[1] and l1.radius == F.FIRE_RADIUS[2] and l1.r > l0.r, "the fire's light grows with the load")
    check(F.lightFor("fire", "salvaged", 880).radius == l1.radius, "a wavering load stays in its band")
    check(F.lightFor("embers", "makeshift", 0) == F.EMBER_LIGHT and F.lightFor(nil, "makeshift", 400) == nil, "embers glow dimly, cold casts nothing")

    -- A small world: one engine, a cell with a lamppost list, a player we can move.
    local saved = { getCell = getCell, getSprite = getSprite, getNumActivePlayers = getNumActivePlayers, getSpecificPlayer = getSpecificPlayer,
                    getTimestampMs = getTimestampMs, IsoLightSource = IsoLightSource, getClimateManager = getClimateManager,
                    isGamePaused = isGamePaused }
    local lamps, nLamps = {}, 0
    local function spr(name) return { getName = function() return name end } end
    local sq = { x = 50, y = 60, z = 0, objs = {}, onScreen = true }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:IsOnScreen() return self.onScreen end
    function sq:getObjects() local o = self.objs return { size = function() return #o end, get = function(_, i) return o[i + 1] end } end
    local cell = {}
    function cell:getGridSquare(x, y, z) return (x == 50 and y == 60 and z == 0) and sq or nil end
    function cell:addLamppost(l) lamps[l] = true; nLamps = nLamps + 1 end
    function cell:removeLamppost(l) if lamps[l] then lamps[l] = nil; nLamps = nLamps - 1 end end
    local md = { dazedpower = { state = "running", steamWatts = 900 } }
    local obj = { sprite = spr(P.sprite("steam", "ground", "salvaged", "running", "S")), swaps = 0 }
    function obj:getSprite() return self.sprite end
    function obj:setSprite(s) self.sprite = s; self.swaps = self.swaps + 1 end
    function obj:getSquare() return self.gone and nil or sq end
    function obj:getObjectIndex() return self.gone and -1 or 0 end
    function obj:hasModData() return true end
    function obj:getModData() return md end
    sq.objs[1] = obj
    local pl = { x = 52, y = 61 }
    function pl:getX() return self.x end
    function pl:getY() return self.y end
    function pl:getZ() return 0 end
    function pl:isDead() return false end
    local daylight, t, paused = 0.1, 0, false
    getCell = function() return cell end
    getSprite = function(name) return spr(name) end
    getNumActivePlayers = function() return 1 end
    getSpecificPlayer = function() return pl end
    getTimestampMs = function() return t end
    getClimateManager = function() return { getDayLightStrength = function() return daylight end } end
    isGamePaused = function() return paused end
    IsoLightSource = { new = function(x, y, z, r, g, b, radius)
        local l = { x = x, y = y, z = z, r = r, radius = radius, active = true }
        function l:setActive(v) self.active = v end
        return l
    end }
    local function run(ms) local stop = t + ms while t < stop do t = t + 33; T.onTick() end end

    F.reset()
    check(not T.has(F.SCAN_ID) and not T.has(F.FRAME_ID), "no jobs while no steam engine is loaded")
    F.consider(obj)
    check(F.count == 1 and T.has(F.SCAN_ID), "an engine starts the once-a-second scan")
    run(1200)
    check(T.has(F.FRAME_ID) and #F.active == 1, "a running engine near and on screen gets the frame job")
    local f = P.spriteInfo(obj.sprite:getName())
    check(f.frame ~= nil and f.frame:sub(1, 4) == "fire" and obj.swaps >= 4, "it walks the flame frames: " .. tostring(obj.swaps))
    check(nLamps == 1, "one light at night")
    local light
    for l in pairs(lamps) do light = l end
    check(light and light.radius == F.FIRE_RADIUS[2] and light.x == 50 and light.y == 60, "full load lights the widest pool on its square")

    -- Less load: the light is rebuilt smaller, never two at once.
    md.dazedpower.steamWatts = 100
    run(1100)
    local l2
    for l in pairs(lamps) do l2 = l end
    check(nLamps == 1 and l2 ~= light and l2.radius == F.FIRE_RADIUS[1] and light.active == false, "a lighter load swaps the light, the old one off")

    -- Pause: nothing moves.
    paused = true
    local s0 = obj.swaps
    run(1500)
    check(obj.swaps == s0, "paused, the frames hold")
    paused = false

    -- Daytime: no light.
    daylight = 0.9
    run(1100)
    check(nLamps == 0, "no light in daylight")
    daylight = 0.1

    -- The server idles it (plain warming sprite): embers, a dim glow, no frame job.
    obj.sprite = spr(P.sprite("steam", "ground", "salvaged", "warming", "S")); md.dazedpower.state = "warming"
    run(1300)
    check(P.spriteInfo(obj.sprite:getName()).frame == "embers" and not T.has(F.FRAME_ID), "warming shows embers and stops the frame job")
    local le
    for l in pairs(lamps) do le = l end
    check(nLamps == 1 and le.radius == F.EMBER_LIGHT.radius, "embers cast the dim glow")

    -- Running again, then the player walks off: light gone, frames stop, the frame it showed stays.
    obj.sprite = spr(P.sprite("steam", "ground", "salvaged", "running", "S")); md.dazedpower.state = "running"
    run(1300)
    check(T.has(F.FRAME_ID), "running again restarts the frames")
    pl.x = 50 + F.RANGE + 5
    run(1300)
    s0 = obj.swaps
    run(600)
    check(nLamps == 0 and not T.has(F.FRAME_ID) and obj.swaps == s0, "out of range: no light, no frame job, no swaps")
    pl.x = 52

    -- Off screen but near: no frames, the light stays (it lights what is on screen).
    sq.onScreen = false
    run(1300)
    s0 = obj.swaps
    run(600)
    check(not T.has(F.FRAME_ID) and obj.swaps == s0 and nLamps == 1, "off screen: frames stop, the light stays")
    sq.onScreen = true
    run(1300)

    -- The option off: the plain sprite back, every light out.
    SandboxVars.DazedPower.MachineEffects = false
    run(1300)
    local pi = P.spriteInfo(obj.sprite:getName())
    check(pi.frame == nil and pi.state == "running" and nLamps == 0 and not T.has(F.FRAME_ID), "option off: plain sprite, no light, no frames")
    s0 = obj.swaps
    run(2000)
    check(obj.swaps == s0, "option off: no swaps after")
    SandboxVars.DazedPower.MachineEffects = nil
    run(1300)
    check(nLamps == 1 and T.has(F.FRAME_ID), "option on again: the fire comes back")

    -- Picked up: the removal event takes its light at once, and the scan job ends with nothing left.
    F.onRemoved(obj)
    check(nLamps == 0 and F.count == 0, "removal drops the light at once")
    run(1300)
    check(not T.has(F.SCAN_ID) and not T.has(F.FRAME_ID), "no engines left: both jobs gone")

    -- Unloaded with no event: the scan's alive check finds it within a second.
    F.consider(obj)
    run(1300)
    check(nLamps == 1, "tracked again")
    obj.gone = true
    run(1300)
    check(nLamps == 0 and F.count == 0, "an engine that left without an event loses its light at the next scan")
    run(1300)
    check(not T.has(F.SCAN_ID), "and the scan job ends")

    F.reset()
    for k, v in pairs(saved) do _G[k] = v end
end
