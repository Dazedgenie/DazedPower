--[[ Dazed Power -- the zombie treadwheel, and the rope that walks a zombie home to it.

     1. Knock a zombie down (a shove, a hit, the electric fence) and, while it is on the floor, tie a rope
        round it (DP_TieZombie, a short timed action that fails if it gets up first). The rope is used up.
     2. Walk it home. The tied zombie is made "useless" (it does not attack) and follows the leader on the
        rope: it is stood up and walks after them on its own legs (woken when the leader is a couple of
        tiles off, made inert again close up, the way the Zombie Leash & Lead mod by gadinho does it), and
        when the rope goes taut it is pulled along, never through a wall or a fence. Running or sprinting with the rope taut can snap it, and so can the zombie being
        held back more than SNAP_DIST tiles (stuck behind a fence, a door shut on it). A snapped rope, or
        letting go, frees the zombie and it turns on whoever held it.
     3. Put it on a Zombie Treadwheel within LOAD_REACH tiles. The wheel keeps a record of it (its outfit, sex
        and whether it crawls), walks for ever and makes power (DPM_Model's treadOutput) like any other source on
        the cable. The zombie itself stays in the drum, walking in place (0.17.0, "the real zombie on the wheel"
        below); with the sandbox option Real zombie on the treadwheel off it leaves the world and the wheel's
        sprite shows a painted one instead (0.10.0).
     4. From the wheel it can be released (loose beside it, hostile) or put down (a corpse, and the rope back).

     Who does what. Everything that changes the world runs on the authority (the server, or single player):
     the leash registry, the rope taken and given back, the zombie removed or spawned, the wheel's ModData.
     The moving does not: a zombie is simulated by the client that owns it, so every client keeps a mirror of
     the leashes (broadcast on every change) and steps the tied zombies it owns, as the electric fence's zap
     is applied (DP_ApplianceMenu). The leader's own client watches the rope and asks the authority to snap
     it. Nothing about a leash is saved: a leash in progress ends with the session.

     Zombies are told apart by their online ID on a server and by their object ID in single player. ]]

require "DazedPower/DP_Parts"
require "DazedPower/DPM_Model"
require "DazedCore/DC_Boot"

DazedPower = DazedPower or {}
DazedPower.Tread = DazedPower.Tread or {}
local T = DazedPower.Tread
local P = DazedPower.Parts
local try = P.try

T.MOD = "DazedPower"
-- Ropes that tie a zombie, and how likely each is to part on one taut check while its holder runs.
T.ROPES = { ["Base.Rope"] = { snap = 0.10 }, ["Base.SheetRope"] = { snap = 0.25 } }
T.ROPE_ORDER = { "Base.Rope", "Base.SheetRope" }        -- the menu reaches for the stronger one first
T.ROPE_LEN = 2.5          -- tiles of slack: closer than this the zombie stands where it is
T.TAUT = 4.0              -- beyond this the rope is taut and the zombie is pulled along
T.SNAP_DIST = 8.0         -- held back this far, the rope always parts
T.LOST_DIST = 20.0        -- this far apart (a teleport, a car) the leash is simply over, rope snap option or not
T.TIE_REACH = 1.8         -- tiles from the player to a zombie they can tie
T.LOAD_REACH = 3.0        -- tiles from the wheel to the player and to the zombie being put on it
T.TIE_TICKS = 150         -- about three seconds at 1x
T.CHECK_MS = 250          -- the leader's rope check and the owner's nudge
T.PATH_MS = 750           -- how often a following zombie is asked to path after its leader
T.LOST_MS = 3000          -- a tied zombie nobody can find for this long has gone (killed, streamed out)
T.WALK_SPEED = 1.6        -- tiles a second a tied zombie shambles after its leader when the rope is slack-ish
T.CATCHUP = 3.0           -- and how hard it closes a longer gap (fraction of the excess per second)
T.STEP_MAX_MS = 100       -- a frame longer than this (a hitch, a pause) steps no further than this one
T.WALK_ON = 2.0           -- tiles: further than this from its leader, a tied zombie is woken to walk after them
T.WALK_OFF = 1.3          -- closer than this it is made inert again (before it is near enough to lunge)
T.STUCK_MS = 1500         -- woken this long without moving STUCK_MOVE tiles, the rope steps it instead
T.STUCK_MOVE = 0.3

-- pid -> { pid, zid, rope, x, y, z }: the authority's truth, and each client's mirror of it.
T.leashes = T.leashes or {}

---------------------------------------------------------------- identity

local function mp() return (isClient and isClient()) or (isServer and isServer()) or false end
local function nowMs() return getTimestampMs and getTimestampMs() or 0 end
local function paused()
    local ok, v = pcall(function() return isGamePaused and isGamePaused() end)
    return ok and v == true
end

--- A zombie's key: its online ID on a server (the same on every machine), its object ID in single player.
function T.zid(z)
    if not z then return nil end
    local id = mp() and try(z, "getOnlineID") or try(z, "getID")
    if type(id) == "number" and id >= 0 then return id end
    return nil
end

--- A player's key: online ID on a server, player number in single player (split screen).
function T.pid(pl)
    if not pl then return nil end
    local id = mp() and try(pl, "getOnlineID") or try(pl, "getPlayerNum")
    if type(id) == "number" then return id end
    return nil
end

--- The player with this key, if this machine knows them.
function T.playerFor(pid)
    if pid == nil then return nil end
    if not mp() then return getSpecificPlayer and getSpecificPlayer(pid) or nil end
    if getPlayerByOnlineID then
        local ok, p = pcall(getPlayerByOnlineID, pid)
        if ok and p then return p end
    end
    for _, p in ipairs(DazedCore.Util.players()) do
        if try(p, "getOnlineID") == pid then return p end
    end
    return nil
end

--- Is this zombie alive and still standing in the world?
function T.zombieAlive(z)
    return z ~= nil and not try(z, "isDead") and try(z, "getCurrentSquare") ~= nil
end

--- The zombie with this key, searched for in the loaded cell (nearest x, y first when given).
function T.findZombie(zid, x, y)
    if zid == nil then return nil end
    local cell = getCell and getCell()
    local list = cell and try(cell, "getZombieList")
    for i = 0, (list and list:size() or 0) - 1 do
        local z = list:get(i)
        if z and T.zid(z) == zid and T.zombieAlive(z) then return z end
    end
    return nil
end

--- Is this zombie down: on the floor, knocked over, or a crawler (which never gets up)?
function T.isDown(z)
    if not T.zombieAlive(z) then return false end
    return try(z, "isOnFloor") == true or try(z, "isKnockedDown") == true or try(z, "isCrawling") == true
end

--- Tiles between two characters on the plane.
function T.dist(a, b)
    local ax, ay, bx, by = try(a, "getX"), try(a, "getY"), try(b, "getX"), try(b, "getY")
    if not (ax and ay and bx and by) then return math.huge end
    return math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))
end

---------------------------------------------------------------- the rope, pure (tested)

--- The rope a player would tie with: the first of ROPE_ORDER they carry, as an item, or nil.
function T.ropeIn(player)
    local inv = player and try(player, "getInventory")
    if not inv then return nil end
    for _, t in ipairs(T.ROPE_ORDER) do
        local it = try(inv, "getFirstTypeRecurse", t)
        if it then return it end
    end
    return nil
end

--- Does the rope snap option apply? (Sandbox TreadRopeSnap, on unless switched off.)
function T.snapOn()
    return P.sandbox("TreadRopeSnap") ~= false
end

--- What the leader's check makes of the rope: "ok", "taut", "snap" or "lost".
--  `d` is the distance to the zombie, `floors` whether they stand on different floors, `running` whether the
--  leader runs or sprints, `roll` a number in [0, 1), `rope` the rope's full type.
function T.ropeVerdict(d, floors, running, roll, rope, snapOn)
    if d == nil or d >= T.LOST_DIST then return "lost" end
    if floors then return snapOn and "snap" or "lost" end
    if d < T.TAUT - 0.25 then return "ok" end
    if not snapOn then return "taut" end
    if d >= T.SNAP_DIST then return "snap" end
    local spec = T.ROPES[rope] or T.ROPES["Base.Rope"]
    if running and roll < spec.snap then return "snap" end
    return "taut"
end

--- Where a tied zombie steps this frame: toward the leader, closing what lies beyond ROPE_LEN at walking pace,
--  faster the longer the gap. nil while it is within the rope's slack. `dt` is in seconds.
function T.followTo(zx, zy, lx, ly, dt)
    local dx, dy = lx - zx, ly - zy
    local d = math.sqrt(dx * dx + dy * dy)
    local excess = d - T.ROPE_LEN
    if excess <= 0.01 or not dt or dt <= 0 then return nil end
    local move = math.max(T.WALK_SPEED * dt, excess * (1 - math.exp(-T.CATCHUP * dt)))
    if move > excess then move = excess end
    return zx + dx / d * move, zy + dy / d * move
end

--- Where a taut rope pulls the zombie: on the line to the leader, TAUT tiles short of them. nil when slack.
function T.pullTo(zx, zy, lx, ly)
    local dx, dy = lx - zx, ly - zy
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= T.TAUT or d <= 0 then return nil end
    local k = (d - T.TAUT) / d
    return zx + dx * k, zy + dy * k
end

---------------------------------------------------------------- the wheel's zombie

--- The zombie a wheel holds, or nil. Any square of a large (2x2) wheel answers for it: its master keeps the record.
function T.occupant(obj)
    local info = obj and P.describe(obj)
    if not info or info.kind ~= "treadwheel" then return nil end
    if info.pieces > 1 and not info.master then
        obj = P.master(obj)
        if not obj then return nil end
    end
    local md = obj:getModData()
    local d = md and md.dazedpower
    local z = d and d.zombie
    return type(z) == "table" and z or nil
end

--- A wheel with a zombie in it, which may not be lifted or turned (DPM_Place).
function T.occupied(obj) return T.occupant(obj) ~= nil end

--- What a wheel keeps of a zombie: enough to dress the one released from it.
function T.describeZombie(z)
    local outfit = try(z, "getOutfitName")
    return { outfit = type(outfit) == "string" and outfit or nil, female = try(z, "isFemale") == true,
             crawler = try(z, "isCrawling") == true or try(z, "isBecomeCrawler") == true,
             since = DazedCore.Util.worldHours() }
end

---------------------------------------------------------------- the authority

local function note(player, key, warn) if player and DazedCore.Note then DazedCore.Note.say(player, key, nil, warn) end end

--- The wheel at x, y, z, or nil: for any square of a large (2x2) wheel, its master.
local function wheelAt(x, y, z)
    local sq = DazedCore.Util.squareAt(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
    local objs = sq and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        local o = objs:get(i)
        local info = P.describe(o)
        if info and info.kind == "treadwheel" then
            if info.pieces > 1 and not info.master then return P.master(o) end
            return o
        end
    end
    return nil
end
T.wheelAt = wheelAt

local function near(player, x, y, z, max) return DazedCore.Net.near(player, x, y, z, max) end

--- Does any leash already hold this zombie? Authority only.
function T.zombieHeld(zid)
    for _, l in pairs(T.leashes) do
        if l.zid == zid then return true end
    end
    return false
end

--- Start a leash: filed, and told to every client. Authority only.
function T.startLeash(player, zid, rope)
    local pid = T.pid(player)
    if pid == nil or zid == nil or T.zombieHeld(zid) then return false end
    T.leashes[pid] = { pid = pid, zid = zid, rope = rope }
    DazedCore.Net.broadcast(T.MOD, "treadLeash", { pid = pid, zid = zid, rope = rope })
    return true
end

--- End a leash, why = "snap", "letgo", "loaded" or "lost". Authority only.
function T.endLeash(pid, why)
    local l = T.leashes[pid]
    if not l then return false end
    T.leashes[pid] = nil
    DazedCore.Net.broadcast(T.MOD, "treadLeashEnd", { pid = pid, zid = l.zid, why = why })
    return true
end

--- The leash this player holds, or nil.
function T.leashOf(player)
    local pid = T.pid(player)
    return pid ~= nil and T.leashes[pid] or nil
end

-- The squares beside a wheel, nearest first, from its (master) square: round one square, or round a 2x2 footprint.
T.BESIDE = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } }
T.BESIDE_XL = { { 2, 0 }, { 2, 1 }, { 0, 2 }, { 1, 2 }, { -1, 0 }, { -1, 1 }, { 0, -1 }, { 1, -1 },
                { 2, 2 }, { -1, -1 }, { 2, -1 }, { -1, 2 } }

--- The first free square beside a wheel that is not walled off from it, or nil. A square beside a 2x2 wheel is
--  checked against the footprint square it touches.
function T.freeBeside(wheel)
    local sq = wheel and wheel:getSquare()
    if not sq then return nil end
    local info = P.describe(wheel)
    local xl = info and info.pieces > 1
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    for _, off in ipairs(xl and T.BESIDE_XL or T.BESIDE) do
        local s = DazedCore.Util.squareAt(x + off[1], y + off[2], z)
        local from = sq
        if xl then
            from = DazedCore.Util.squareAt(x + math.max(0, math.min(1, off[1])), y + math.max(0, math.min(1, off[2])), z) or sq
        end
        if s and try(s, "isFree", false) and not try(from, "isBlockedTo", s) then return s end
    end
    return nil
end

--- Spawn a zombie like the one a wheel held, on a free square beside the wheel. Returns it or nil.
local function spawnBeside(wheel, desc, knockedDown)
    local sq = wheel and wheel:getSquare()
    if not (sq and addZombiesInOutfit) then return nil end
    local z = sq:getZ()
    local spot = T.freeBeside(wheel) or sq
    local ok, list = pcall(addZombiesInOutfit, spot:getX(), spot:getY(), z, 1, desc and desc.outfit or nil,
                           (desc and desc.female) and 100 or 0, desc and desc.crawler == true, false, false,
                           knockedDown == true, false, false, 1.0)
    local zb = ok and list and list.size and list:size() > 0 and list:get(0) or nil
    return zb
end

local function clearWheel(wheel)
    local d = P.data(wheel)
    d.zombie, d.treadWatts, d.treadLured = nil, 0, nil
    P.setState(wheel, "empty")
    wheel:transmitModData()
    local sq = wheel:getSquare()
    if sq then T.unfile(sq:getX(), sq:getY(), sq:getZ()) end
end

---------------------------------------------------------------- the real zombie on the wheel (0.17.0)
--[[ With the sandbox option Real zombie on the treadwheel (TreadRealZombie, on), the zombie put on a wheel stays
     in the world: pinned in the drum, inert and toothless, walking in place (AnimSets zombie/idle/DazedTreadWalk:
     the game's own Zombie_Walk, or Zombie_Crawl for a crawler, while its DazedTread variable is set). The wheel
     shows its plain drum ("empty" sprite); its power still comes from its ModData record, so a wheel that cannot
     find its zombie for a moment keeps turning. Kill the zombie and the wheel is empty. The authority files each
     such wheel (ModData "DazedPowerTread") and keeps its zombie: re-found by where it stands after a reload, made
     inert again, and if it has gone (streamed out and lost) an identical one is put back. Every client pins the
     ones near its players each frame (DP_TreadWheel). Off, the sprite wheel of 0.10.0 is used, and wheels loaded
     either way keep the way they were loaded. The idea of leaving the zombie inert in the world with its own
     animation is the one Zombie Leash & Lead (CativeiroBR, by gadinho) uses for its prisoners. ]]

T.REAL_REACH = 1.0        -- tiles from the wheel's middle within which its zombie is looked for
T.KEEP_MS = 2000          -- the authority's look at its real wheels
T.RESPAWN_MS = 6000       -- a real wheel's zombie missing this long, with a player in RESPAWN_NEAR, is put back
T.RESPAWN_NEAR = 30
T.VAR = "DazedTread"      -- the animation variable (AnimSets zombie/idle and zombie-crawler/idle)
T.TAG = "DazedPowerWheel" -- ModData mark on a wheel's zombie: the key of its wheel
-- The way a wheel's zombie faces: the wheel's facing (the model's front, tools/blender/dz2.py treadwheel_part).
T.FACE = { E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 }, N = { 0, -1 } }

T.held = T.held or {}     -- wheel key -> { z, missing }: the authority's cache of each real wheel's zombie

--- Does the real zombie option apply to a wheel loaded now? (On unless switched off.)
function T.realOn() return P.sandbox("TreadRealZombie") ~= false end

--- Is this wheel record a real zombie in the world (not the painted one)?
function T.isReal(desc) return type(desc) == "table" and desc.real == true end

function T.key(x, y, z) return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) end

--- Where a wheel's zombie stands and the way it faces: x, y, z, fx, fy. A large (2x2) wheel's drum stands on the
--  middle of its footprint, the corner its four squares share.
function T.spot(wheel)
    local info = wheel and P.describe(wheel)
    if info and info.pieces > 1 and not info.master then wheel = P.master(wheel) end
    local sq = wheel and wheel:getSquare()
    if not sq then return nil end
    local f = T.FACE[P.facingOf(wheel)] or T.FACE.S
    if info and info.pieces > 1 then return sq:getX() + 1.0, sq:getY() + 1.0, sq:getZ(), f[1], f[2] end
    return sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ(), f[1], f[2]
end

--- The authority's list of real wheels, kept in the save (global ModData) when there is one.
function T.registry()
    if not T.reg then
        local ok, md = pcall(function() return ModData and ModData.getOrCreate and ModData.getOrCreate("DazedPowerTread") end)
        T.reg = (ok and type(md) ~= "boolean" and md) or {}
    end
    return T.reg
end

function T.file(x, y, z) T.registry()[T.key(x, y, z)] = { x = x, y = y, z = z } end
function T.unfile(x, y, z)
    local k = T.key(x, y, z)
    T.registry()[k] = nil
    T.held[k] = nil
end

--- The zombie standing in a real wheel: the one marked for it, else one in its clothes, within REAL_REACH of
--  its middle and on no rope. Nil when there is none.
function T.wheelZombie(wheel, desc)
    local x, y, z = T.spot(wheel)
    if not x then return nil end
    local key = T.key(math.floor(x), math.floor(y), z)
    local tied = {}
    for _, l in pairs(T.leashes) do tied[l.zid] = true end
    local cell = getCell and getCell()
    local list = cell and try(cell, "getZombieList")
    local best, bestD, marked = nil, math.huge, nil
    local r2 = T.REAL_REACH * T.REAL_REACH
    for i = 0, (list and list:size() or 0) - 1 do
        local zb = list:get(i)
        if zb and T.zombieAlive(zb) and math.floor(try(zb, "getZ") or -99) == z and not tied[T.zid(zb) or -1] then
            local dx, dy = (try(zb, "getX") or 1e9) - x, (try(zb, "getY") or 1e9) - y
            local d2 = dx * dx + dy * dy
            if d2 <= r2 then
                local md = try(zb, "getModData")
                if md and md[T.TAG] == key then marked = zb break end
                local outfit = try(zb, "getOutfitName")
                if (not desc or not desc.outfit or outfit == desc.outfit) and d2 < bestD then best, bestD = zb, d2 end
            end
        end
    end
    local zb = marked or best
    local md = zb and try(zb, "getModData")
    if md then md[T.TAG] = key end
    return zb
end

--- Make a zombie a wheel's walker (or, `on` false, a zombie again). Pinning it in place is the clients' job.
--  Called every frame or two for a wheel near a player, so only try (a missing method answers nil, nothing throws).
function T.harness(zb, on)
    if not zb then return end
    try(zb, "setUseless", on)
    try(zb, "setNoTeeth", on)
    try(zb, "setVariable", T.VAR, on)
    if on then
        try(zb, "setTarget", nil)
    else
        local md = try(zb, "getModData")
        if md then md[T.TAG] = nil end
    end
end

--- Put a zombie at x, y without walking it there.
function T.place(zb, x, y)
    try(zb, "setX", x); try(zb, "setY", y)
    try(zb, "setLastX", x); try(zb, "setLastY", y)
    try(zb, "setNextX", x); try(zb, "setNextY", y)
end

--- A zombie like the one a wheel held, put back in the drum. Returns it or nil.
local function spawnIn(wheel, desc)
    local x, y, z = T.spot(wheel)
    if not (x and addZombiesInOutfit) then return nil end
    local ok, list = pcall(addZombiesInOutfit, math.floor(x), math.floor(y), z, 1, desc and desc.outfit or nil,
                           (desc and desc.female) and 100 or 0, desc and desc.crawler == true, false, false,
                           false, false, false, 1.0)
    local zb = ok and list and list.size and list:size() > 0 and list:get(0) or nil
    if zb then
        T.place(zb, x, y)
        local md = try(zb, "getModData")
        if md then md[T.TAG] = T.key(math.floor(x), math.floor(y), z) end
        T.harness(zb, true)
    end
    return zb
end

--- The authority's look at every real wheel: its zombie found and kept inert, or put back if it has gone.
--  A wheel that is gone or no longer holds a real zombie leaves the list (and its zombie, if found, is let go).
function T.keep(now)
    now = now or nowMs()
    local reg = T.registry()
    local drop = {}
    for k, e in pairs(reg) do
        local sq = DazedCore.Util.squareAt(e.x, e.y, e.z)
        if sq then                                          -- not loaded: left as it is until it is
            local wheel = wheelAt(e.x, e.y, e.z)
            local desc = wheel and T.occupant(wheel)
            local h = T.held[k] or {}
            T.held[k] = h
            if not T.isReal(desc) then
                drop[#drop + 1] = k
                if h.z and T.zombieAlive(h.z) then T.harness(h.z, false) end
            else
                if not (h.z and T.zombieAlive(h.z)) then h.z = T.wheelZombie(wheel, desc) end
                if h.z then
                    h.missing = nil
                    if T.isDown(h.z) then T.standUp(h.z) end     -- knocked over in the drum: back on its feet
                    T.harness(h.z, true)
                else
                    h.missing = h.missing or now
                    local px, py = sq:getX() + 0.5, sq:getY() + 0.5
                    local near = false
                    for _, p in ipairs(DazedCore.Util.players()) do
                        local dx, dy = (try(p, "getX") or 1e9) - px, (try(p, "getY") or 1e9) - py
                        if dx * dx + dy * dy <= T.RESPAWN_NEAR * T.RESPAWN_NEAR then near = true break end
                    end
                    if near and now - h.missing >= T.RESPAWN_MS then
                        h.z, h.missing = spawnIn(wheel, desc), nil
                        print("DazedPower: tread wheel " .. k .. " lost its zombie, put back: " .. tostring(h.z ~= nil))
                    end
                end
            end
        end
    end
    for _, k in ipairs(drop) do reg[k] = nil T.held[k] = nil end
end

--- A real wheel's zombie killed: the wheel is empty (its record goes, nothing is put back).
function T.onZombieDead(zb)
    if not zb then return end
    local md = try(zb, "getModData")
    local key = md and md[T.TAG]
    for k, h in pairs(T.held) do
        if h.z == zb then key = k break end
    end
    local e = key and T.registry()[key]
    if not e then return end
    local wheel = wheelAt(e.x, e.y, e.z)
    if wheel and T.isReal(T.occupant(wheel)) then clearWheel(wheel) else T.unfile(e.x, e.y, e.z) end
end

if not T.keepFiled and DazedCore.Tick and not (isClient and isClient()) then
    T.keepFiled = true
    DazedCore.Tick.every("DazedPower.treadKeep", T.KEEP_MS, function() pcall(T.keep) end)
    if Events and Events.OnZombieDead then Events.OnZombieDead.Add(function(zb) pcall(T.onZombieDead, zb) end) end
end

--- The commands a client sends. Each re-checks everything against the world as it is.
T.COMMANDS = {}

function T.COMMANDS.treadLetGo(player)
    local pid = T.pid(player)
    if pid ~= nil then T.endLeash(pid, "letgo") end
end

--- The leader's client saw the rope part (or the zombie gone). Trusted only for its own leash.
function T.COMMANDS.treadSnap(player, args)
    local pid = T.pid(player)
    local l = pid ~= nil and T.leashes[pid]
    if not l or (args.zid ~= nil and tonumber(args.zid) ~= l.zid) then return end
    T.endLeash(pid, args.lost and "lost" or "snap")
end

function T.COMMANDS.treadLoad(player, args)
    local wheel = wheelAt(args.x, args.y, args.z)
    if not wheel or T.occupied(wheel) then return end
    local sq = wheel:getSquare()
    local mx, my = T.spot(wheel)
    if not near(player, mx, my, sq:getZ(), T.LOAD_REACH + 0.5) then return end
    local pid = T.pid(player)
    local l = pid ~= nil and T.leashes[pid]
    if not l then return end
    local zb = T.findZombie(l.zid)
    if not zb then note(player, "IGUI_DazedPower_TreadNoZombie", true) return end
    if T.zid(zb) ~= l.zid then return end                 -- only the zombie this player's own leash holds
    local zx, zy = try(zb, "getX") or 1e9, try(zb, "getY") or 1e9
    local dx, dy = zx - mx, zy - my
    if dx * dx + dy * dy > (T.LOAD_REACH + 0.5) * (T.LOAD_REACH + 0.5) then
        note(player, "IGUI_DazedPower_TreadTooFar", true)
        return
    end
    local d = P.data(wheel)
    d.zombie = T.describeZombie(zb)
    d.zombie.rope = l.rope
    local real = T.realOn()
    if real then
        -- It stays in the world, pinned in the drum and walking in place; the wheel shows its plain drum.
        d.zombie.real = true
        local x, y, z = T.spot(wheel)
        T.standUp(zb)
        T.place(zb, x, y)
        local md = try(zb, "getModData")
        if md then md[T.TAG] = T.key(sq:getX(), sq:getY(), sq:getZ()) end
        T.harness(zb, true)
        T.file(sq:getX(), sq:getY(), sq:getZ())
        T.held[T.key(sq:getX(), sq:getY(), sq:getZ())] = { z = zb }
        P.setState(wheel, "empty")
    else
        pcall(function()
            zb:removeFromWorld()
            zb:removeFromSquare()
        end)
        P.setState(wheel, "walking")
    end
    wheel:transmitModData()
    T.leashes[pid] = nil
    DazedCore.Net.broadcast(T.MOD, "treadLeashEnd", { pid = pid, zid = l.zid, why = "loaded", real = real or nil })
end

--- A real wheel's zombie, for release or putting down: the authority's own, else found where it stands.
local function realZombie(wheel, desc)
    local sq = wheel:getSquare()
    local h = T.held[T.key(sq:getX(), sq:getY(), sq:getZ())]
    if h and h.z and T.zombieAlive(h.z) then return h.z end
    return T.wheelZombie(wheel, desc)
end

--- Move a real wheel's zombie out onto a free square beside the wheel (the one spawnBeside would use).
local function stepOut(wheel, zb)
    local s = T.freeBeside(wheel)
    if s then T.place(zb, s:getX() + 0.5, s:getY() + 0.5) end
end

function T.COMMANDS.treadRelease(player, args)
    local wheel = wheelAt(args.x, args.y, args.z)
    local desc = wheel and T.occupant(wheel)
    if not desc then return end
    local sq = wheel:getSquare()
    local mx, my = T.spot(wheel)
    if not near(player, mx, my, sq:getZ(), T.LOAD_REACH + 0.5) then return end
    local zb = T.isReal(desc) and realZombie(wheel, desc) or nil
    clearWheel(wheel)
    if zb then
        T.harness(zb, false)
        stepOut(wheel, zb)
    else
        zb = spawnBeside(wheel, desc, false)
    end
    if zb then pcall(function() zb:setTarget(player) end) end
    note(player, "IGUI_DazedPower_TreadReleased", true)
end

function T.COMMANDS.treadPutDown(player, args)
    local wheel = wheelAt(args.x, args.y, args.z)
    local desc = wheel and T.occupant(wheel)
    if not desc then return end
    local sq = wheel:getSquare()
    local mx, my = T.spot(wheel)
    if not near(player, mx, my, sq:getZ(), T.LOAD_REACH + 0.5) then return end
    local zb = T.isReal(desc) and realZombie(wheel, desc) or nil
    clearWheel(wheel)
    if zb then
        T.harness(zb, false)
        stepOut(wheel, zb)
    else
        zb = spawnBeside(wheel, desc, true)
    end
    if zb then
        if not pcall(function() zb:Kill(player) end) then pcall(function() zb:setHealth(0) end) end
    end
    -- The rope comes off it whole.
    local rope = (desc.rope and T.ROPES[desc.rope]) and desc.rope or "Base.Rope"
    local inv = try(player, "getInventory")
    local item = inv and instanceItem and instanceItem(rope)
    if item then
        inv:AddItem(item)
        if sendAddItemToContainer then sendAddItemToContainer(inv, item) end
    end
end

--- Drop the leashes whose owner is no longer online (they left, or dropped), telling every client. Authority only.
function T.sweep()
    local gone = {}
    for pid in pairs(T.leashes) do
        if not T.playerFor(pid) then gone[#gone + 1] = pid end
    end
    for _, pid in ipairs(gone) do T.endLeash(pid, "lost") end
    return #gone
end

if not T.sweepFiled and DazedCore.Tick and isServer and isServer() then
    T.sweepFiled = true
    DazedCore.Tick.every("DazedPower.treadSweep", 5000, function() pcall(T.sweep) end)
end

--- A client that joins (or a client that lost track) asks for every leash in play.
function T.COMMANDS.treadSync(player)
    local list = {}
    for _, l in pairs(T.leashes) do list[#list + 1] = { pid = l.pid, zid = l.zid, rope = l.rope } end
    DazedCore.Net.reply(player, T.MOD, "treadLeashes", { list = list })
end

if not T.commandsFiled and DazedCore.Net then
    T.commandsFiled = true
    for name, fn in pairs(T.COMMANDS) do
        DazedCore.Net.on(T.MOD, name, function(player, args) T.COMMANDS[name](player, args) end, 200)
    end
end

---------------------------------------------------------------- every client: the mirror

--- Free a zombie this machine owns: it may attack again, and turns on `toward` when given.
function T.free(zb, toward)
    if not zb then return end
    -- Clear the flags even on a remote zombie: this client may have set them while it owned it.
    pcall(function() zb:setUseless(false) end)
    pcall(function() zb:setNoTeeth(false) end)
    if toward and (not mp() or not try(zb, "isRemoteZombie")) then pcall(function() zb:setTarget(toward) end) end
end

T.logged = T.logged or {}     -- zid -> true once the follow loop has reported a leash to the console
T.found = T.found or {}       -- zid -> { z, at }: the zombie object last found for a leash, and when it was last seen

local function onLeash(args)
    if type(args) ~= "table" or args.pid == nil then return end
    T.leashes[args.pid] = { pid = args.pid, zid = args.zid, rope = args.rope }
end

local function onLeashEnd(args)
    if type(args) ~= "table" or args.pid == nil then return end
    local l = T.leashes[args.pid]
    if l and l.zid == args.zid then T.leashes[args.pid] = nil end
    local zb = T.found[args.zid] and T.found[args.zid].z or T.findZombie(args.zid)
    T.found[args.zid] = nil
    T.logged[args.zid] = nil
    local leader = T.playerFor(args.pid)
    if args.why == "loaded" and args.real then
        -- It walks the wheel now: DP_TreadWheel pins it there and keeps it inert.
        if zb then T.harness(zb, true) end
    elseif args.why == "loaded" then
        -- Gone on the authority already; this side's copy goes too, in case removal had not reached it.
        if zb and not try(zb, "isRemoteZombie") then pcall(function() zb:removeFromWorld() zb:removeFromSquare() end) end
    elseif zb then
        T.free(zb, (args.why == "snap" or args.why == "letgo") and leader or nil)
    end
    if leader and try(leader, "isLocalPlayer") then
        local key = ({ snap = "IGUI_DazedPower_TreadSnapped", letgo = "IGUI_DazedPower_TreadLetGo",
                       loaded = "IGUI_DazedPower_TreadLoaded", lost = "IGUI_DazedPower_TreadLost" })[args.why]
        if key then P.haloNote(leader, getText(key), args.why == "snap" or args.why == "letgo") end
    end
end

local function onLeashes(args)
    if type(args) ~= "table" or type(args.list) ~= "table" then return end
    for _, l in pairs(args.list) do
        if type(l) == "table" and l.pid ~= nil then T.leashes[l.pid] = { pid = l.pid, zid = l.zid, rope = l.rope } end
    end
end

if not T.clientFiled and DazedCore.Net then
    T.clientFiled = true
    DazedCore.Net.onClient(T.MOD, "treadLeash", onLeash)
    DazedCore.Net.onClient(T.MOD, "treadLeashEnd", onLeashEnd)
    DazedCore.Net.onClient(T.MOD, "treadLeashes", onLeashes)
end
T.onLeash, T.onLeashEnd, T.onLeashes = onLeash, onLeashEnd, onLeashes

---------------------------------------------------------------- every client: walking a zombie on a rope

--- The tied zombie for a leash, cached, re-found when it went missing. Records when it was last seen.
local SCAN_MS = 1000       -- a missing zombie is searched for at most this often per leash
local SCAN_NEAR = 60.0        -- and only while a local player is this close to its leader

local function localNear(leader)
    if not leader then return false end
    for _, p in ipairs(DazedCore.Util.players()) do
        if try(p, "isLocalPlayer") and T.dist(p, leader) <= SCAN_NEAR then return true end
    end
    return false
end

local function zombieOf(l, now, leader)
    local f = T.found[l.zid]
    if f and T.zombieAlive(f.z) then f.at = now return f.z end
    local zb = nil
    if (not l.tried or now - l.tried >= SCAN_MS) and localNear(leader) then
        l.tried = now
        zb = T.findZombie(l.zid)
    end
    if zb then
        T.found[l.zid] = { z = zb, at = now }
        return zb
    end
    if not f then T.found[l.zid] = { z = nil, at = now } end
    return nil
end

--- Move a zombie this machine owns to nx, ny, if the square there can be reached from its own.
local function stepTo(zb, nx, ny)
    if not nx then return false end
    local from = try(zb, "getCurrentSquare")
    local to = DazedCore.Util.squareAt(math.floor(nx), math.floor(ny), math.floor(zb:getZ()))
    if not (from and to) then return false end
    -- Never through a wall, a fence or a closed door: a rope caught on one holds the zombie back.
    if from ~= to and (try(from, "isBlockedTo", to) or try(to, "isSolid") or try(to, "isSolidTrans")) then return false end
    zb:setX(nx); zb:setY(ny)
    pcall(function() zb:setLastX(nx) zb:setLastY(ny) end)
    pcall(function() zb:setNextX(nx) zb:setNextY(ny) end)
    return true
end

--- Pull a zombie this machine owns toward its leader when the rope is taut.
local function pull(zb, leader)
    local nx, ny = T.pullTo(zb:getX(), zb:getY(), leader:getX(), leader:getY())
    return stepTo(zb, nx, ny)
end

--- Get a tied zombie off the floor (it was down to be tied). A crawler stays a crawler, dragged along.
function T.standUp(zb)
    if try(zb, "isCrawling") == true then return end
    pcall(function() zb:setOnFloor(false) end)
    pcall(function() zb:setKnockedDown(false) end)
    pcall(function() zb:setFallOnFront(false) end)
    pcall(function() zb:setFakeDead(false) end)
    pcall(function() zb:setSitAgainstWall(false) end)
end

T.lastCheck, T.lastPath, T.lastStep = T.lastCheck or {}, T.lastPath or {}, T.lastStep or {}

--- One frame of walking a tied zombie after its leader. A "useless" zombie stands inert and cannot bite,
--  so close to the leader it is made useless; once the leader is WALK_ON away it is woken and set on the
--  leader, and the game's own walking brings it along until it is back within WALK_OFF. It never bites
--  (no teeth). Should the game not walk it (STUCK_MS without moving), the rope steps it instead. A taut
--  rope always pulls, never through a wall. Nothing moves while single player is paused.
function T.drive(l, pid, zb, leader, now)
    pcall(function() zb:setNoTeeth(true) end)
    if not l.stood then l.stood = true T.standUp(zb) end
    local d = T.dist(zb, leader)
    if d > T.WALK_ON then l.walking = true elseif d < T.WALK_OFF then l.walking = false end
    local dt = math.min(now - (T.lastStep[pid] or now), T.STEP_MAX_MS) / 1000
    T.lastStep[pid] = now
    local zx, zy = zb:getX(), zb:getY()
    if l.walking then
        pcall(function() zb:setUseless(false) end)
        pcall(function() zb:setTarget(leader) end)
        pcall(function() zb:spotted(leader, true) end)
        if not T.lastPath[pid] or now - T.lastPath[pid] >= T.PATH_MS then
            T.lastPath[pid] = now
            pcall(function() zb:pathToLocationF(leader:getX(), leader:getY(), leader:getZ()) end)
        end
        if not l.moveAt then
            l.moveAt, l.mx, l.my = now, zx, zy
        elseif (zx - l.mx) * (zx - l.mx) + (zy - l.my) * (zy - l.my) >= T.STUCK_MOVE * T.STUCK_MOVE then
            l.moveAt, l.mx, l.my = now, zx, zy
        elseif now - l.moveAt >= T.STUCK_MS then
            l.stuck = true                                  -- the game is not walking it: the rope does
        end
        if l.stuck and not paused() then
            local nx, ny = T.followTo(zx, zy, leader:getX(), leader:getY(), dt)
            if nx then pcall(stepTo, zb, nx, ny) end
        end
    else
        pcall(function() zb:setUseless(true) zb:setTarget(nil) end)
        l.moveAt = nil
        pcall(function() zb:faceLocationF(leader:getX(), leader:getY()) end)
    end
    if not paused() and T.dist(zb, leader) > T.TAUT then pcall(pull, zb, leader) end
end

--- One frame of every leash this machine can see.
function T.follow()
    if isServer and isServer() then return end            -- a dedicated server moves nobody
    local any = false
    for _ in pairs(T.leashes) do any = true break end
    if not any then return end
    local now = nowMs()
    for pid, l in pairs(T.leashes) do
        local leader = T.playerFor(pid)
        local zb = zombieOf(l, now, leader)
        -- The leader's own machine walks the zombie (as Zombie Leash & Lead does): in single player that is
        -- this machine. isRemoteZombie is no guide here, it reads true in single player.
        local drives = zb ~= nil and leader ~= nil and (not mp() or try(leader, "isLocalPlayer") == true)
        if leader and zb and not T.logged[l.zid] then
            T.logged[l.zid] = true
            print(string.format("DazedPower: tread leash %s found, drives=%s down=%s floor=%s crawl=%s d=%.1f",
                tostring(l.zid), tostring(drives), tostring(T.isDown(zb)), tostring(try(zb, "isOnFloor")),
                tostring(try(zb, "isCrawling")), T.dist(zb, leader)))
        end
        if drives then T.drive(l, pid, zb, leader, now) end
        -- The leader's own client reads the rope and asks the authority to end the leash.
        if leader and try(leader, "isLocalPlayer") and (not T.lastCheck[pid] or now - T.lastCheck[pid] >= T.CHECK_MS) then
            T.lastCheck[pid] = now
            local verdict
            if try(leader, "isDead") or try(leader, "getVehicle") then
                verdict = "lost"
            elseif not zb then
                local f = T.found[l.zid]
                if f and now - (f.at or now) >= T.LOST_MS then verdict = "lost" end
            else
                local running = try(leader, "isRunning") == true or try(leader, "isSprinting") == true
                local floors = math.floor(try(zb, "getZ") or 0) ~= math.floor(try(leader, "getZ") or 0)
                verdict = T.ropeVerdict(T.dist(zb, leader), floors, running, ZombRandFloat(0, 1), l.rope, T.snapOn())
            end
            if verdict == "snap" or verdict == "lost" then
                T.lastCheck[pid] = now + 1000              -- one ask, not one a frame, while the answer travels
                DazedCore.Net.send(leader, T.MOD, "treadSnap", { zid = l.zid, lost = verdict == "lost" })
            end
        end
    end
end

if not T.tickFiled and DazedCore.Tick then
    T.tickFiled = true
    DazedCore.Tick.everyTicks("DazedPower.tread", 1, T.follow)
end

-- A client joining a game in progress asks for the leashes already in play.
if not T.syncFiled and Events and Events.OnGameStart then
    T.syncFiled = true
    Events.OnGameStart.Add(function()
        if isClient and isClient() and getPlayer and getPlayer() then
            DazedCore.Net.send(getPlayer(), T.MOD, "treadSync", {})
        end
    end)
end

return T
