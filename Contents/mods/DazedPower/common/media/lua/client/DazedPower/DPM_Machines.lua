--[[ Dazed Power -- every loaded power-source machine on this side, for the machine sounds and the spinning blades.

     Fed by MapObjects as chunks stream in and machines are placed, by OnObjectAdded, and by a slow sweep round each
     local player that catches anything no event announced. Readers walk this list instead of searching squares. ]]

require "DazedPower/DP_Parts"

DazedPower.More = DazedPower.More or {}
DazedPower.More.Machines = DazedPower.More.Machines or {}
local Mc = DazedPower.More.Machines
local P = DazedPower.Parts

-- Not 6: the server's loaders (DPM_Bridge) use 6 for the same sprites, and an equal priority would replace them in single player.
Mc.PRIORITY = 7
Mc.SWEEP_MS = 10000             -- real time between the fallback sweeps
Mc.SWEEP_RADIUS = 18            -- squares round each local player the sweep reads
Mc.SWEEP_FLOORS = 1             -- floors above and below the player

Mc.objs = Mc.objs or {}         -- object -> true
Mc.listeners = Mc.listeners or {}

--- Is this one of our power-source machines (by its sprite)?
function Mc.isMachine(obj)
    local spr = obj and obj.getSprite and obj:getSprite()
    local info = spr and P.spriteInfo(spr:getName())
    return info ~= nil and P.SOURCE_KINDS[info.kind] == true
end

--- Track an object if it is one of our machines, and tell the listeners about a new one.
function Mc.consider(obj)
    if not obj or Mc.objs[obj] or not Mc.isMachine(obj) then return end
    Mc.objs[obj] = true
    for i = 1, #Mc.listeners do pcall(Mc.listeners[i], obj) end
end

--- Call fn(obj) for every new machine from now on, and once for each one already tracked.
function Mc.onAdd(fn)
    Mc.listeners[#Mc.listeners + 1] = fn
    for obj in pairs(Mc.objs) do pcall(fn, obj) end
end

--- Call fn(obj, sq) for every tracked machine still standing; the ones that left are dropped.
function Mc.each(fn)
    for obj in pairs(Mc.objs) do
        local sq = obj:getSquare()
        if obj:getObjectIndex() == -1 or not sq then
            Mc.objs[obj] = nil
        else
            fn(obj, sq)
        end
    end
end

--- Read the squares round every local player for machines no event announced.
function Mc.sweep()
    local cell = getCell and getCell()
    if not cell then return end
    local r, floors, floor = Mc.SWEEP_RADIUS, Mc.SWEEP_FLOORS, math.floor
    for p = 0, (getNumActivePlayers and getNumActivePlayers() or 1) - 1 do
        local pl = getSpecificPlayer(p)
        if pl and not pl:isDead() then
            local px, py, pz = floor(pl:getX()), floor(pl:getY()), floor(pl:getZ())
            for z = math.max(0, pz - floors), pz + floors do
                for x = px - r, px + r do
                    for y = py - r, py + r do
                        local sq = cell:getGridSquare(x, y, z)
                        local objs = sq and sq:getObjects()
                        for i = 0, (objs and objs:size() or 0) - 1 do Mc.consider(objs:get(i)) end
                    end
                end
            end
        end
    end
end

local lastSweep = nil
local function onTick()
    local now = getTimestampMs and getTimestampMs() or 0
    if lastSweep and now >= lastSweep and now - lastSweep < Mc.SWEEP_MS then return end
    lastSweep = now
    local ok, err = pcall(Mc.sweep)
    if not ok and print then print("DazedPower machines: " .. tostring(err)) end
end

local function registerSprites()
    if not (MapObjects and MapObjects.OnLoadWithSprite) then return end
    for row = 1, #P.ROWS do
        if P.SOURCE_KINDS[P.ROWS[row].kind] then
            for col = 0, P.COLS - 1 do
                local name = P.spriteName((row - 1) * P.COLS + col)
                MapObjects.OnLoadWithSprite(name, Mc.consider, Mc.PRIORITY)
                if MapObjects.OnNewWithSprite then MapObjects.OnNewWithSprite(name, Mc.consider, Mc.PRIORITY) end
            end
        end
    end
end

-- At file load and again at start, as DP_System does: the login area streams in during the loading screen.
if not Mc.hooked then
    Mc.hooked = true
    registerSprites()
    if Events then
        if Events.OnGameStart then Events.OnGameStart.Add(registerSprites) end
        if Events.OnObjectAdded then Events.OnObjectAdded.Add(Mc.consider) end
        if Events.OnTick then Events.OnTick.Add(onTick) end
    end
end

return Mc
