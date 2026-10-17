-- Checks for the zombie treadwheel (0.10.0): its output, the rope's rules, and the whole single-player round trip --
-- tie a downed zombie, walk it (pulled, held by a wall, snapped by running), put it on the wheel, the wheel's power
-- through the bridge, the pick-up lock, then release and put down. Zombies here are stand-ins, not the engine's.
return function(check, E)
    local P = DazedPower.Parts
    local MM = DazedPower.More.Model
    local T = DazedPower.Tread

    ------------------------------------------------------------ the output model
    check(MM.treadOutput(nil) == 0 and select(2, MM.treadOutput({ walking = false })) == "empty", "an empty wheel makes nothing")
    local w, st = MM.treadOutput({ walking = true, condition = 100 })
    check(w == MM.TREAD_W and st == "walking", "a walked wheel in good order makes its rated watts: " .. tostring(w))
    check(MM.treadOutput({ walking = true, lured = true, condition = 100 }) == MM.TREAD_LURED_W, "someone close lures it faster")
    check(MM.treadOutput({ walking = true, crawler = true, condition = 100 }) == MM.TREAD_W * MM.TREAD_CRAWLER, "a crawler is slow")
    check(MM.treadOutput({ walking = true, condition = 50 }) == MM.TREAD_W * 0.7, "output follows condition like a pedal generator's")
    check(MM.treadOutput({ walking = true, condition = MM.TREAD_STOP_BELOW }) == 0, "worn-through slats slip and make nothing")

    ------------------------------------------------------------ the rope's rules
    local V = T.ropeVerdict
    check(V(1, false, true, 0, "Base.Rope", true) == "ok", "slack rope: running is fine")
    check(V(T.TAUT + 0.5, false, false, 0, "Base.Rope", true) == "taut", "taut, walking: holds")
    check(V(T.TAUT + 0.5, false, true, 0.05, "Base.Rope", true) == "snap", "taut, running, an unlucky roll: snaps")
    check(V(T.TAUT + 0.5, false, true, 0.2, "Base.Rope", true) == "taut", "a rope holds a roll a sheet rope would not")
    check(V(T.TAUT + 0.5, false, true, 0.2, "Base.SheetRope", true) == "snap", "a sheet rope snaps sooner")
    check(V(T.SNAP_DIST + 0.1, false, false, 0.99, "Base.Rope", true) == "snap", "held back too far, it always breaks free")
    check(V(T.SNAP_DIST + 0.1, false, true, 0, "Base.Rope", false) == "taut", "with the snap option off it never snaps")
    check(V(2, true, false, 0.99, "Base.Rope", true) == "snap" and V(2, true, false, 0.99, "Base.Rope", false) == "lost",
        "another floor ends it either way")
    check(V(T.LOST_DIST, false, false, 0.99, "Base.Rope", false) == "lost" and V(nil, false, false, 0, "Base.Rope", true) == "lost",
        "far out of reach or nowhere: lost")
    check(T.pullTo(0, 0, 3, 0) == nil, "no pull while slack")
    local px, py = T.pullTo(0, 0, 10, 0)
    check(math.abs(px - (10 - T.TAUT)) < 1e-9 and py == 0, "a taut rope pulls it to TAUT short of its leader")

    ------------------------------------------------------------ the stand-in world
    local saved = { getCell = getCell, getSpecificPlayer = getSpecificPlayer, getTimestampMs = getTimestampMs,
                    instanceof = instanceof, addZombiesInOutfit = addZombiesInOutfit, ZombRandFloat = ZombRandFloat,
                    players = DazedCore.Util.players }
    local zombies = {}
    local function zlist() return { size = function() return #zombies end, get = function(_, i) return zombies[i + 1] end } end
    local cell0 = getCell
    getCell = function()
        local c = cell0()
        c.getZombieList = function() return zlist() end
        return c
    end
    for x = 480, 530 do for y = 490, 510 do E.square(x, y, 0) end end
    local clock = 0
    getTimestampMs = function() clock = clock + 1000 return clock end

    local Z = {}
    Z.__index = Z
    function Z:getX() return self.x end
    function Z:getY() return self.y end
    function Z:getZ() return self.z end
    function Z:setX(v) self.x = v end
    function Z:setY(v) self.y = v end
    function Z:getID() return self.id end
    function Z:getOnlineID() return -1 end
    function Z:isDead() return self.dead == true end
    function Z:getCurrentSquare() if self.gone then return nil end return E.square(math.floor(self.x), math.floor(self.y), self.z) end
    function Z:isOnFloor() return self.down == true end
    function Z:isKnockedDown() return false end
    function Z:isCrawling() return self.crawler == true end
    function Z:isBecomeCrawler() return false end
    function Z:getOutfitName() return "Police" end
    function Z:isFemale() return true end
    function Z:isRemoteZombie() return false end
    function Z:setUseless(b) self.useless = b end
    function Z:setNoTeeth(b) self.noTeeth = b end
    function Z:setTarget(t) self.target = t end
    function Z:pathToLocationF() self.pathed = (self.pathed or 0) + 1 end
    function Z:faceLocationF() end
    function Z:removeFromWorld() self.gone = true end
    function Z:removeFromSquare() self.gone = true end
    function Z:Kill() self.dead = true end
    local function zombie(id, x, y, extra)
        local z = setmetatable({ id = id, x = x, y = y, z = 0 }, Z)
        for k, v in pairs(extra or {}) do z[k] = v end
        zombies[#zombies + 1] = z
        local sq = E.square(math.floor(x), math.floor(y), 0)
        sq.movers = sq.movers or {}
        sq.movers[#sq.movers + 1] = z
        return z
    end
    instanceof = function(o, cls) return cls == "IsoZombie" and getmetatable(o) == Z end

    local player = E.character(500.5, 500.5, 0)
    function player:getPlayerNum() return 0 end
    function player:isLocalPlayer() return true end
    function player:isDead() return false end
    function player:getVehicle() return nil end
    function player:isRunning() return self.running == true end
    function player:isSprinting() return false end
    function player:shouldBeTurning() return false end
    function player:setX(v) self.x = v end
    function player:setY(v) self.y = v end
    player.inv.getFirstTypeRecurse = function(self, t)
        for _, v in ipairs(self.items) do if v.fullType == t then return v end end
        return nil
    end
    getSpecificPlayer = function(n) return n == 0 and player or nil end
    DazedCore.Util.players = function() return { player } end

    ------------------------------------------------------------ tying
    E.give(player, "Base.Rope", 1)
    local zb = zombie(7, 501.5, 500.5, { down = true })
    check(T.zid(zb) == 7 and T.pid(player) == 0, "single player keys: object ID and player number")
    check(T.findZombie(7) == zb and T.isDown(zb), "the downed zombie is found by its key")
    local rope = T.ropeIn(player)
    check(rope and rope.fullType == "Base.Rope", "the player's rope is found")

    local TM = DazedPower.TreadMenu
    local addTip0 = ISWorldObjectContextMenu.addToolTip
    ISWorldObjectContextMenu.addToolTip = function() return { setName = function() end } end
    local rows = {}
    local ctx = { addOption = function(_, text, ...) local o = { text = text, args = { ... } } rows[#rows + 1] = o return o end }
    TM.worldRows(player, ctx, E.square(501, 500, 0))
    check(#rows == 1 and rows[1].text == "ContextMenu_DazedPower_TreadTie" and not rows[1].notAvailable, "a downed zombie offers Tie up")

    local a = DP_TieZombie:new(player, 7, rope)
    a.zombie = zb
    check(a:isValid(), "the tie is valid on a downed zombie in reach with a rope")
    zb.down = false
    check(not a:isValid(), "and not once it is on its feet")
    zb.down = true
    check(a:complete() == true, "complete() returns true")
    check(E.count(player, "Base.Rope") == 0, "the rope is used up")
    local l = T.leashOf(player)
    check(l and l.zid == 7 and l.rope == "Base.Rope", "the leash is filed with the rope it used")
    rows = {}
    TM.worldRows(player, ctx, E.square(501, 500, 0))
    check(#rows == 1 and rows[1].text == "ContextMenu_DazedPower_TreadLetGo", "while leading, the world menu offers Let go")

    -- A zombie already on a rope cannot be tied again, by anyone.
    check(T.startLeash(player, 7, "Base.Rope") == false, "a leashed zombie cannot be leashed again")
    check(T.zombieHeld(7) and not T.zombieHeld(99), "zombieHeld reports the held zombie")
    T.leashes[3] = { pid = 3, zid = 77, rope = "Base.Rope" }
    check(T.sweep() == 1 and T.leashes[3] == nil and T.leashOf(player) ~= nil, "the sweep drops a leash whose owner is offline, and only that")

    ------------------------------------------------------------ walking it
    zb.down = false
    player.x, player.y = 510.5, 500.5
    T.follow()
    check(zb.useless == true and zb.noTeeth == true and zb.target == nil, "a tied zombie does not attack or choose a target")
    check((zb.pathed or 0) >= 1, "it is asked to walk after its leader")
    check(math.abs(T.dist(zb, player) - T.TAUT) < 0.01, "a taut rope pulls it along: " .. T.dist(zb, player))
    check(T.leashOf(player) ~= nil, "walking, the rope holds")

    -- A wall between it and where the rope pulls holds it back.
    local from = zb:getCurrentSquare()
    player.x = player.x + 3
    local tx = math.floor(T.pullTo(zb.x, zb.y, player.x, player.y))
    from.walls = { [tx .. "," .. math.floor(zb.y)] = true }
    local x0 = zb.x
    T.follow()
    check(zb.x == x0, "never pulled through a wall or a fence")
    from.walls = nil

    -- Running with it taut snaps the rope, and the zombie turns on its leader.
    player.running = true
    ZombRandFloat = function() return 0 end
    T.follow()
    check(T.leashOf(player) == nil, "running with the rope taut snapped it")
    check(zb.useless == false and zb.target == player, "a snapped rope frees the zombie, and it comes for its leader")
    player.running = false

    ------------------------------------------------------------ onto the wheel
    local wsq = E.square(520, 500, 0)
    local wheel = E.object(P.sprite("treadwheel", "ground", "standard", "empty", "S"), wsq)
    local info = P.describe(wheel)
    check(info and info.kind == "treadwheel" and info.state == "empty", "a treadwheel is a Dazed Power part")
    check(P.SOURCE_KINDS.treadwheel and DazedPower.Model.wireLegal("treadwheel", "controller"), "a source, wired to a controller")
    check(not T.occupied(wheel), "a new wheel is empty")

    E.give(player, "Base.SheetRope", 1)
    local zb2 = zombie(8, 517.5, 500.5, { down = true })
    player.x, player.y = 518.5, 500.5
    local b = DP_TieZombie:new(player, 8, T.ropeIn(player))
    b:complete()
    check(T.leashOf(player) and T.leashOf(player).rope == "Base.SheetRope", "tied with a sheet rope")

    DazedCore.Net.send(player, "DazedPower", "treadLoad", { x = 520, y = 500, z = 0 })
    local occ = T.occupant(wheel)
    check(occ and occ.outfit == "Police" and occ.female == true and occ.rope == "Base.SheetRope", "the wheel keeps its zombie's outfit, sex and rope")
    check(zb2.gone == true, "the zombie leaves the world")
    check(T.leashOf(player) == nil, "and the leash is over")
    check(P.describe(wheel).state == "walking", "the wheel shows it walking")

    local G = DazedPower.Place
    check(G and G.mayTake and G.mayTake(player, wsq, wheel, true) == false, "a wheel with a zombie in it cannot be picked up")

    ------------------------------------------------------------ its power, through the bridge
    local B = DazedPower.More.Bridge
    local alt0 = DazedPower.Alternator
    DazedPower.Alternator = nil                -- no hooked-up cars in this stand-in world
    local rec = { dpm = { pedal = {}, windmill = {}, steam = {}, propane = {}, hydro = {}, treadwheel = { wheel } }, arrays = {} }
    local src = B.internals.liveSources(rec)
    check(src and #src.treads == 1 and src.treads[1].walking and src.treads[1].lured, "the bridge sees a walking, lured wheel")
    local ok, total = pcall(B.internals.stepSources, src, { arrays = {}, bank = {}, load = 0 }, 1, { temperature = 15 }, 0.9, 1)
    check(ok, "stepSources runs: " .. tostring(total))
    if ok then
        check(math.abs(total - MM.TREAD_LURED_W * 0.9) < 1e-6, "its watts reach the bus through the inverter: " .. tostring(total))
        check(math.abs(src.treadW - MM.TREAD_LURED_W * 0.9) < 1e-6 and src.windW == 0, "filed as the wheel's, not the wind's")
    end
    DazedCore.Util.players = function() return {} end
    src = B.internals.liveSources(rec)
    check(src.treads[1].lured == false, "nobody close: not lured")
    DazedCore.Util.players = function() return { player } end
    DazedPower.Alternator = alt0

    ------------------------------------------------------------ release and put down
    local spawned = {}
    addZombiesInOutfit = function(x, y, z, n, outfit, female, crawler, front, fake, knocked)
        local s = zombie(100 + #spawned, x + 0.5, y + 0.5, { outfit = outfit, female = female, knocked = knocked })
        spawned[#spawned + 1] = s
        return { size = function() return 1 end, get = function() return s end }
    end
    player.x, player.y = 518.5, 500.5
    DazedCore.Net.send(player, "DazedPower", "treadPutDown", { x = 520, y = 500, z = 0 })
    check(#spawned == 1 and spawned[1].dead and spawned[1].outfit == "Police" and spawned[1].female == 100,
        "put down: a corpse in the same clothes")
    check(E.count(player, "Base.SheetRope") == 1, "and the rope back")
    check(not T.occupied(wheel) and P.describe(wheel).state == "empty", "the wheel is empty again")

    P.data(wheel).zombie = { outfit = "Farmer", female = false }
    DazedCore.Net.send(player, "DazedPower", "treadRelease", { x = 520, y = 500, z = 0 })
    check(#spawned == 2 and not spawned[2].dead and spawned[2].target == player, "released: loose, and after the player")
    check(not T.occupied(wheel), "released: the wheel is empty")

    P.data(wheel).zombie = { outfit = "Farmer" }
    player.x, player.y = 510.5, 500.5
    DazedCore.Net.send(player, "DazedPower", "treadRelease", { x = 520, y = 500, z = 0 })
    check(T.occupied(wheel) and #spawned == 2, "the authority refuses a release from out of reach")
    P.data(wheel).zombie = nil

    getCell, getSpecificPlayer, getTimestampMs = saved.getCell, saved.getSpecificPlayer, saved.getTimestampMs
    instanceof, addZombiesInOutfit, ZombRandFloat = saved.instanceof, saved.addZombiesInOutfit, saved.ZombRandFloat
    DazedCore.Util.players = saved.players
    ISWorldObjectContextMenu.addToolTip = addTip0
    T.leashes, T.found = {}, {}
end
