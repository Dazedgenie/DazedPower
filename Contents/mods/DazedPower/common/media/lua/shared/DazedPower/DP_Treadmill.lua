--[[ Dazed Power -- the player treadmill: the vanilla gym treadmill ("Human Hamster Wheel") as a source.

     The machine is vanilla's: two tiles of the tileset recreational_sports_01 per facing (W 28+29, N 30+31, E 36+37,
     S 38+39), so Power has no sheet rows for it and the sprites are recognised by NAME here, through guarded wraps of
     P.describe, P.master, P.piecesAround and P.itemFor (the way DPM_Water recognises Plumbing's machines). Nothing is
     wrapped on P.spriteInfo, so Power's placement hooks never take over the vanilla tile.

     Only a treadmill somebody wired or used carries Power's data: the loader (DPM_Bridge) registers one only when its
     ModData already holds `dazedpower`, and the ModData is made by the first cable (S.connect) or the first beat.

     Who does what. The user's own client runs DPM_Treadmill (the timed action: animation, position, Fatigue and
     Endurance) and sends a beat about once a second. The authority (the server, or single player) checks it
     (T.beat) and writes what DPM_Bridge reads: the user's Fitness from the server's own copy of the character, the
     gait, the beat's time and who is on. A beat that stops, for any reason, stops the watts within FRESH_MS. ]]

require "DazedCore/DC_Boot"
require "DazedPower/DP_Parts"
require "DazedPower/DPM_Model"

DazedPower = DazedPower or {}
DazedPower.Treadmill = DazedPower.Treadmill or {}
local T = DazedPower.Treadmill
local P = DazedPower.Parts
local MM = DazedPower.More.Model
local try = P.try

T.MOD = "DazedPower"
T.TILESET = "recreational_sports_01"
T.ITEM = "Base.DazedTreadmill"
T.REACH = 3.0            -- tiles from the master square to the user, checked by the authority
T.FRESH_MS = 2500        -- how long a beat is trusted (real ms); the action beats every MA.PEDAL_BEAT_MS

-- Each sprite: its facing, which piece of the two it is (1 is the master, the one that carries our data), and where
-- the master stands from it. The master is always the NW-most square: the second piece is one east (W, E) or south (N, S).
local SHORT = {
    [28] = { f = "W", piece = 1 },                      [29] = { f = "W", piece = 2, dx = -1, dy = 0 },
    [31] = { f = "N", piece = 1 },                      [30] = { f = "N", piece = 2, dx = 0, dy = -1 },
    [36] = { f = "E", piece = 1 },                      [37] = { f = "E", piece = 2, dx = -1, dy = 0 },
    [39] = { f = "S", piece = 1 },                      [38] = { f = "S", piece = 2, dx = 0, dy = -1 },
}
T.SPRITES = {}           -- full sprite name -> { f, piece, dx, dy }
T.PIECE_SPRITE = { W = {}, N = {}, E = {}, S = {} }      -- facing -> piece -> sprite name
T.MASTERS = {}           -- the four master sprite names
for n, def in pairs(SHORT) do
    local name = T.TILESET .. "_" .. n
    def.dx, def.dy = def.dx or 0, def.dy or 0
    T.SPRITES[name] = def
    T.PIECE_SPRITE[def.f][def.piece] = name
    if def.piece == 1 then T.MASTERS[#T.MASTERS + 1] = name end
end
table.sort(T.MASTERS)

-- The way the user faces on the belt, by the machine's facing. The sprites' fronts have not been seen in game: if the
-- user runs backwards, swap the pairs here (nothing else needs to change).
T.RUN_DIR = { W = "W", N = "N", E = "E", S = "S" }

---------------------------------------------------------------- identity

--- The sprite name of an object, or nil.
local function nameOf(obj)
    local spr = obj and obj.getSprite and obj:getSprite()
    local name = spr and spr.getName and spr:getName()
    if type(name) == "string" then return name end
    return nil
end

--- The object's Power data if it has any. getModData builds an empty table on every object it is asked of, so
--  an object that has none is not asked.
local function dataOf(obj)
    if not (obj and obj.getModData) or (obj.hasModData and not obj:hasModData()) then return nil end
    local md = obj:getModData()
    return md and md.dazedpower
end

--- The treadmill description of an object, or nil when it is not one of the eight tiles. Never makes ModData.
function T.identify(obj)
    local name = nameOf(obj)
    local def = name and T.SPRITES[name]
    if not def then return nil end
    local d = dataOf(obj)
    return { kind = "treadmill", mount = "ground", tier = "standard", state = (d and d.tmMode) or "idle",
             facing = def.f, piece = def.piece, pieces = 2, master = def.piece == 1 }
end

--- Where piece 2 stands from the master, by facing.
local function secondOffset(facing)
    if facing == "W" or facing == "E" then return 1, 0 end
    return 0, 1
end

local function squareAt(x, y, z) return DazedCore.Util.squareAt(x, y, z) end

--- The object on a square wearing this exact sprite, or nil.
local function findSprite(sq, name)
    local objs = sq and sq.getObjects and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        local o = objs:get(i)
        if nameOf(o) == name then return o end
    end
    return nil
end

--- The master piece of a treadmill (itself for the master tile), or nil when it is not one or its square is not loaded.
function T.masterOf(obj)
    local name = nameOf(obj)
    local def = name and T.SPRITES[name]
    if not def then return nil end
    if def.piece == 1 then return obj end
    local sq = obj:getSquare()
    if not sq then return nil end
    return findSprite(squareAt(sq:getX() + def.dx, sq:getY() + def.dy, sq:getZ()), T.PIECE_SPRITE[def.f][1])
end

--- Both pieces, master first: { [piece] = object }, for the squares that are loaded.
function T.pieces(obj)
    local out = {}
    local master = T.masterOf(obj)
    local sq = master and master:getSquare()
    local info = master and T.identify(master)
    if not (sq and info) then return out end
    out[1] = master
    local ox, oy = secondOffset(info.facing)
    local second = findSprite(squareAt(sq:getX() + ox, sq:getY() + oy, sq:getZ()), T.PIECE_SPRITE[info.facing][2])
    if second then out[2] = second end
    return out
end

--- Where the user stands on the belt, and which way they face: the middle of the two tiles. Pure, for tests.
function T.seat(info, mx, my)
    local x, y
    if info.facing == "W" or info.facing == "E" then x, y = mx + 1.0, my + 0.5 else x, y = mx + 0.5, my + 1.0 end
    return x, y, T.RUN_DIR[info.facing] or info.facing
end

--- Per-player key written beside the beat: the online ID in multiplayer (the same on every machine), else the player number.
function T.riderKey(player)
    if not player then return nil end
    local mp = (isClient and isClient()) or (isServer and isServer()) or false
    local id = mp and try(player, "getOnlineID") or try(player, "getPlayerNum")
    if type(id) == "number" then return id end
    return nil
end

---------------------------------------------------------------- the beat (authority)

T.active = T.active or {}      -- object -> true for a treadmill with a rider on it, for the sweep

local function nowMs() return getTimestampMs and getTimestampMs() or 0 end

--- A user's heartbeat, checked and written. `args` is { x, y, z, mode }: the MASTER square and the gait. Runs on
--  the authority only. True when written. Everything is re-checked here: reach, the master tile, a known gait, a
--  second user while the first is still beating, and the Fitness is the server's own.
function T.beat(player, args)
    if not player or type(args) ~= "table" or try(player, "isDead") then return false end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) then return false end
    if not MM.validTreadmillMode(args.mode) then return false end
    if not DazedCore.Net.near(player, x + 0.5, y + 0.5, z, T.REACH) then return false end
    local sq = squareAt(x, y, z)
    local objs = sq and sq.getObjects and sq:getObjects()
    for i = 0, (objs and objs:size() or 0) - 1 do
        local o = objs:get(i)
        local info = T.identify(o)
        if info and info.master then
            local who = T.riderKey(player)
            local now = nowMs()
            local d = P.data(o)
            if d.tmRider ~= nil and d.tmRider ~= who and now - (d.tmBeat or 0) <= T.FRESH_MS then return false end
            local changed = d.tmRider ~= who or d.tmMode ~= args.mode
            d.tmFitness = try(player, "getPerkLevel", Perks and Perks.Fitness) or 0
            d.tmBeat, d.tmMode, d.tmRider = now, args.mode, who
            T.active[o] = true
            if changed and o.transmitModData then o:transmitModData() end
            return true
        end
    end
    return false
end

--- The user got off (or the action ended): stop billing at once. Authority only. With `player`, only their own beat is cleared.
function T.release(obj, player)
    local d = dataOf(obj)
    if not d then return end
    if player and d.tmRider ~= nil and d.tmRider ~= T.riderKey(player) then return end
    d.tmBeat, d.tmRider, d.tmMode, d.tmWatts = 0, nil, nil, 0
    T.active[obj] = nil
    if obj.transmitModData then obj:transmitModData() end
end

--- Clear a treadmill whose user stopped beating without getting off (a crash, a dropped connection).
function T.sweep()
    local now = nowMs()
    local n = 0
    for obj in pairs(T.active) do
        if not P.alive(obj) then
            T.active[obj] = nil
        else
            local d = dataOf(obj)
            if not d or d.tmRider == nil then
                T.active[obj] = nil
            elseif now < (d.tmBeat or 0) or now - (d.tmBeat or 0) > T.FRESH_MS then
                T.release(obj)
                n = n + 1
            end
        end
    end
    return n
end

if not T.commandsFiled and DazedCore.Net and not (isClient and isClient()) then
    T.commandsFiled = true
    DazedCore.Net.on(T.MOD, "treadmillBeat", function(player, args) T.beat(player, args) end, 800)
    if DazedCore.Tick then DazedCore.Tick.every("DazedPower.treadmillSweep", 3000, function() pcall(T.sweep) end) end
end

---------------------------------------------------------------- recognising the vanilla tiles

if not T.wrapped then
    T.wrapped = true

    local describe0 = P.describe
    function P.describe(obj)
        return T.identify(obj) or describe0(obj)
    end

    local master0 = P.master
    function P.master(obj)
        if T.identify(obj) then return T.masterOf(obj) end
        return master0(obj)
    end

    local pieces0 = P.piecesAround
    function P.piecesAround(obj, info)
        if (info and info.kind == "treadmill") or (not info and T.identify(obj)) then return T.pieces(obj) end
        return pieces0(obj, info)
    end

    local itemFor0 = P.itemFor
    function P.itemFor(kind, mount, tier)
        if kind == "treadmill" then return T.ITEM end
        return itemFor0(kind, mount, tier)
    end
end

---------------------------------------------------------------- boot

--- Say in the log whether the vanilla tiles are in this build (a renamed tileset would leave the treadmill unrecognised).
function T.boot()
    if T.booted then return end
    T.booted = true
    local ok, sm = pcall(getSpriteManager, "")
    local named = ok and sm and sm.getNamedMap and sm:getNamedMap()
    local have, missing = 0, nil
    for _, name in ipairs(T.MASTERS) do
        if named and named:containsKey(name) then have = have + 1 elseif not missing then missing = name end
    end
    local second = T.PIECE_SPRITE.S[2]
    if named and named:containsKey(second) then have = have + 1 end
    local want = #T.MASTERS + 1
    local sm = getScriptManager and getScriptManager()
    local item = sm and sm:getItem(T.ITEM)
    print(string.format("DazedPower: treadmill tiles %s -- recreational_sports_01_39 %s, %d/%d checked%s, item %s",
        have == want and "present" or "MISSING", (named and named:containsKey("recreational_sports_01_39")) and "found" or "not found",
        have, want, missing and ("  (first missing: " .. missing .. ")") or "", item and "found" or "MISSING"))
end

if Events then
    if Events.OnGameStart then Events.OnGameStart.Add(T.boot) end
    if Events.OnServerStarted then Events.OnServerStarted.Add(T.boot) end
end

return T
