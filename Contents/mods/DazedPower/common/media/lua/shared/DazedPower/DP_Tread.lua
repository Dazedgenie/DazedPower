--[[ Dazed Power -- the zombie treadwheel, and the rope that walks a zombie home to it.

     1. Knock a zombie down (a shove, a hit, the electric fence) and, while it is on the floor, tie a rope
        round it (DP_TieZombie, a short timed action that fails if it gets up first). The rope is used up.
     2. Walk it home. The tied zombie is made "useless" (it does not attack) and follows the leader on the
        rope: it is asked to path after them, and when the rope goes taut it is pulled along, never through a
        wall or a fence. Running or sprinting with the rope taut can snap it, and so can the zombie being
        held back more than SNAP_DIST tiles (stuck behind a fence, a door shut on it). A snapped rope, or
        letting go, frees the zombie and it turns on whoever held it.
     3. Put it on a Zombie Treadwheel within LOAD_REACH tiles. The zombie leaves the world and becomes data on
        the wheel (its outfit, sex and whether it crawls), which walks for ever and makes power (DPM_Model's
        treadOutput) like any other source on the cable.
     4. From the wheel it can be released (a hostile zombie in the same clothes, loose beside it) or put down
        (a corpse, and the rope back).

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

-- pid -> { pid, zid, rope, x, y, z }: the authority's truth, and each client's mirror of it.
T.leashes = T.leashes or {}

---------------------------------------------------------------- identity

local function mp() return (isClient and isClient()) or (isServer and isServer()) or false end
local function nowMs() return getTimestampMs and getTimestampMs() or 0 end

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

--- Where a taut rope pulls the zombie: on the line to the leader, TAUT tiles short of them. nil when slack.
function T.pullTo(zx, zy, lx, ly)
    local dx, dy = lx - zx, ly - zy
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= T.TAUT or d <= 0 then return nil end
    local k = (d - T.TAUT) / d
    return zx + dx * k, zy + dy * k
end

---------------------------------------------------------------- the wheel's zombie

--- The zombie a wheel holds, or nil.
function T.occupant(obj)
    local info = obj and P.describe(obj)
    if not info or info.kind ~= "treadwheel" then return nil end
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

--- The wheel at x, y, z, or nil.
local function wheelAt(x, y, z)
    local sq = DazedCore.Util.squareAt(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
    local objs = sq and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        local o = objs:get(i)
        local info = P.describe(o)
        if info and info.kind == "treadwheel" then return o end
    end
    return nil
end
T.wheelAt = wheelAt

local function near(player, x, y, z, max) return DazedCore.Net.near(player, x, y, z, max) end

--- Start a leash: filed, and told to every client. Authority only.
function T.startLeash(player, zid, rope)
    local pid = T.pid(player)
    if pid == nil or zid == nil then return false end
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

--- Spawn a zombie like the one a wheel held, on a free square beside the wheel. Returns it or nil.
local function spawnBeside(wheel, desc, knockedDown)
    local sq = wheel and wheel:getSquare()
    if not (sq and addZombiesInOutfit) then return nil end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local spot = nil
    for _, off in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } }) do
        local s = DazedCore.Util.squareAt(x + off[1], y + off[2], z)
        if s and try(s, "isFree", false) and not try(sq, "isBlockedTo", s) then spot = s break end
    end
    spot = spot or sq
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
    if not near(player, sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ(), T.LOAD_REACH + 0.5) then return end
    local pid = T.pid(player)
    local l = pid ~= nil and T.leashes[pid]
    if not l then return end
    local zb = T.findZombie(l.zid)
    if not zb then note(player, "IGUI_DazedPower_TreadNoZombie", true) return end
    local zx, zy = try(zb, "getX") or 1e9, try(zb, "getY") or 1e9
    local dx, dy = zx - (sq:getX() + 0.5), zy - (sq:getY() + 0.5)
    if dx * dx + dy * dy > (T.LOAD_REACH + 0.5) * (T.LOAD_REACH + 0.5) then
        note(player, "IGUI_DazedPower_TreadTooFar", true)
        return
    end
    local d = P.data(wheel)
    d.zombie = T.describeZombie(zb)
    d.zombie.rope = l.rope
    pcall(function()
        zb:removeFromWorld()
        zb:removeFromSquare()
    end)
    P.setState(wheel, "walking")
    wheel:transmitModData()
    T.leashes[pid] = nil
    DazedCore.Net.broadcast(T.MOD, "treadLeashEnd", { pid = pid, zid = l.zid, why = "loaded" })
end

function T.COMMANDS.treadRelease(player, args)
    local wheel = wheelAt(args.x, args.y, args.z)
    local desc = wheel and T.occupant(wheel)
    if not desc then return end
    local sq = wheel:getSquare()
    if not near(player, sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ(), T.LOAD_REACH + 0.5) then return end
    clearWheel(wheel)
    local zb = spawnBeside(wheel, desc, false)
    if zb then pcall(function() zb:setTarget(player) end) end
    note(player, "IGUI_DazedPower_TreadReleased", true)
end

function T.COMMANDS.treadPutDown(player, args)
    local wheel = wheelAt(args.x, args.y, args.z)
    local desc = wheel and T.occupant(wheel)
    if not desc then return end
    local sq = wheel:getSquare()
    if not near(player, sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ(), T.LOAD_REACH + 0.5) then return end
    clearWheel(wheel)
    local zb = spawnBeside(wheel, desc, true)
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
    if not zb or try(zb, "isRemoteZombie") then return end
    pcall(function() zb:setUseless(false) end)
    pcall(function() zb:setNoTeeth(false) end)
    if toward then pcall(function() zb:setTarget(toward) end) end
end

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
    local leader = T.playerFor(args.pid)
    if args.why == "loaded" then
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
local function zombieOf(l, now)
    local f = T.found[l.zid]
    if f and T.zombieAlive(f.z) then f.at = now return f.z end
    local zb = T.findZombie(l.zid)
    if zb then
        T.found[l.zid] = { z = zb, at = now }
        return zb
    end
    if not f then T.found[l.zid] = { z = nil, at = now } end
    return nil
end

--- Pull a zombie this machine owns toward its leader, onto a square it can reach from its own.
local function pull(zb, leader)
    local zx, zy, lx, ly = zb:getX(), zb:getY(), leader:getX(), leader:getY()
    local nx, ny = T.pullTo(zx, zy, lx, ly)
    if not nx then return end
    local from = try(zb, "getCurrentSquare")
    local to = DazedCore.Util.squareAt(math.floor(nx), math.floor(ny), math.floor(zb:getZ()))
    if not (from and to) then return end
    -- Never through a wall, a fence or a closed door: a rope caught on one holds the zombie back.
    if from ~= to and (try(from, "isBlockedTo", to) or try(to, "isSolid") or try(to, "isSolidTrans")) then return end
    zb:setX(nx); zb:setY(ny)
    pcall(function() zb:setLastX(nx) zb:setLastY(ny) end)
    pcall(function() zb:setNextX(nx) zb:setNextY(ny) end)
end

T.lastCheck, T.lastPath = T.lastCheck or {}, T.lastPath or {}

--- One frame of every leash this machine can see.
function T.follow()
    if isServer and isServer() then return end            -- a dedicated server moves nobody
    local any = false
    for _ in pairs(T.leashes) do any = true break end
    if not any then return end
    local now = nowMs()
    for pid, l in pairs(T.leashes) do
        local leader = T.playerFor(pid)
        local zb = zombieOf(l, now)
        local owned = zb ~= nil and not try(zb, "isRemoteZombie")
        if leader and zb and owned then
            -- Tied: it does not bite, it does not choose its own target, and it walks after its leader.
            pcall(function() zb:setUseless(true) zb:setNoTeeth(true) zb:setTarget(nil) end)
            local d = T.dist(zb, leader)
            if d > T.ROPE_LEN and (not T.lastPath[pid] or now - T.lastPath[pid] >= T.PATH_MS) then
                T.lastPath[pid] = now
                pcall(function() zb:pathToLocationF(leader:getX(), leader:getY(), leader:getZ()) end)
            end
            if d > T.TAUT then pcall(pull, zb, leader) end
            pcall(function() zb:faceLocationF(leader:getX(), leader:getY()) end)
        end
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
