--[[ Dazed Power -- the rope you can see between you and the zombie you lead (DP_Tread).

     The game only draws a rope from a player to an animal they lead, so an invisible rat is led instead
     and held at the tied zombie's neck every frame: the game's own rope runs from your hand to the
     zombie. The trick is the one the Zombie Leash & Lead mod (CativeiroBR, by gadinho) uses: a rat (it
     has no rope bone, so the rope ends exactly where it is), hung "on a hook" so it has no mind of its
     own and makes no sound, out of reach of shoves, wearing a fully transparent skin.

     Visual only and only on the leader's own machine: nothing is sent, and nothing about it is meant to
     be saved. A rat left behind by a crash is removed the next time its leader's machine finds it. ]]

require "DazedPower/DP_Tread"

local T = DazedPower.Tread
local try = DazedPower.Parts.try

DazedPower.TreadRope = DazedPower.TreadRope or {}
local R = DazedPower.TreadRope

R.SKIN = "DazedPower_Invisible"   -- media/textures/Body/DazedPower_Invisible.png, fully transparent
R.NECK = 0.45                     -- floors above the zombie's feet where the rope is tied
R.FORWARD = 0.02                  -- tiles in front of its chest, toward the leader
R.TAG = "DazedPowerRope"          -- ModData mark on the rat, so a stray one can be told from a real rat
R.SWEEP_MS = 5000
R.SWEEP_RANGE = 8

R.ghosts = R.ghosts or {}         -- pid -> rat

local function make(zb)
    local a
    pcall(function()
        a = IsoAnimal.new(getCell(), zb:getX(), zb:getY(), zb:getZ(), "rat", "grey")
    end)
    if not a then return nil end
    pcall(function() a:setWild(false) end)
    pcall(function() a:setOnHook(true) end)            -- no mind of its own, no falling, no sound
    pcall(function() a:setGodMod(true) end)            -- not a target for shoves or swings
    pcall(function() a:getModData()[R.TAG] = true end)
    pcall(function() a:getAnimalVisual():setSkinTextureName(R.SKIN) end)
    pcall(function() a:resetModel() end)
    pcall(function() a:setInvisible(true) end)
    pcall(function() a:getBehavior():setBlockMovement(true) end)
    pcall(function() a:getEmitter():stopAll() end)
    return a
end

local function attach(leader, a)
    pcall(function()
        a:getData():setAttachedTree(nil)
        leader:getAttachedAnimals():add(a)
        a:getData():setAttachedPlayer(leader)
    end)
end

local function remove(a, leader)
    if not a then return end
    pcall(function() a:setOnHook(false) end)
    if leader then pcall(function() leader:removeAttachedAnimal(a) end) end
    pcall(function() a:getData():setAttachedPlayer(nil) end)
    pcall(function() a:getData():setAttachedTree(nil) end)
    pcall(function() a:removeFromWorld() end)
    pcall(function() a:removeFromSquare() end)
end
R.remove = remove

--- Hold the rat at the zombie's neck, just in front of it toward the leader.
local function hold(a, zb, leader)
    pcall(function()
        local zx, zy = zb:getX(), zb:getY()
        local dx, dy = leader:getX() - zx, leader:getY() - zy
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.01 then zx, zy = zx + dx / len * R.FORWARD, zy + dy / len * R.FORWARD end
        a:setX(zx); a:setY(zy)
        a:setZ(zb:getZ() + R.NECK)
        a:getEmitter():stopAll()
    end)
end

--- One frame: a rat for every leash this machine leads, held at its zombie; none for any other.
function R.frame()
    for pid, a in pairs(R.ghosts) do
        local l = T.leashes[pid]
        local leader = T.playerFor(pid)
        local f = l and T.found[l.zid]
        if not (l and leader and f and f.z and T.zombieAlive(f.z)) then
            remove(a, leader)
            R.ghosts[pid] = nil
        end
    end
    for pid, l in pairs(T.leashes) do
        local leader = T.playerFor(pid)
        local f = T.found[l.zid]
        local zb = f and f.z
        if leader and try(leader, "isLocalPlayer") and zb and T.zombieAlive(zb) then
            local a = R.ghosts[pid]
            if not a then
                a = make(zb)
                if a then attach(leader, a) R.ghosts[pid] = a end
            end
            if a then hold(a, zb, leader) end
        end
    end
end

--- Remove marked rats near the local players that no leash holds (left by a crash or a reload).
function R.sweep()
    local held = {}
    for _, a in pairs(R.ghosts) do held[a] = true end
    for _, p in ipairs(DazedCore.Util.players()) do
        if try(p, "isLocalPlayer") then
            local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
            for dx = -R.SWEEP_RANGE, R.SWEEP_RANGE do
                for dy = -R.SWEEP_RANGE, R.SWEEP_RANGE do
                    local sq = DazedCore.Util.squareAt(px + dx, py + dy, pz)
                    local movs = sq and try(sq, "getMovingObjects")
                    for i = (movs and movs:size() or 0) - 1, 0, -1 do
                        local o = movs:get(i)
                        if o and not held[o] and instanceof and instanceof(o, "IsoAnimal") then
                            local md = try(o, "getModData")
                            if md and md[R.TAG] then remove(o, p) end
                        end
                    end
                end
            end
        end
    end
end

if not R.filed and DazedCore.Tick then
    R.filed = true
    DazedCore.Tick.everyTicks("DazedPower.treadRope", 1, function()
        for _ in pairs(T.leashes) do R.frame() return end
        for _ in pairs(R.ghosts) do R.frame() return end
    end)
    DazedCore.Tick.every("DazedPower.treadRopeSweep", R.SWEEP_MS, function() R.sweep() end)
end

return R
