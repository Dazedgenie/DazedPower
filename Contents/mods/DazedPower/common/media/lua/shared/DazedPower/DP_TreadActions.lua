--[[ Dazed Power -- tying a downed zombie with a rope (DP_Tread).

     Shared, like the other actions: the client runs it, and in multiplayer complete() runs on the server,
     which re-checks reach and the rope against the world as it is then. Whether the zombie is still down is
     the client's to judge (it owns the animation); the action stops the moment it gets up. ]]

require "TimedActions/ISBaseTimedAction"
require "DazedPower/DP_Tread"

local T = DazedPower.Tread
local try = DazedPower.Parts.try

DP_TieZombie = ISBaseTimedAction:derive("DP_TieZombie")

--- The zombie this action is tying, found on this side by its key.
function DP_TieZombie:target()
    if self.zombie and T.zombieAlive(self.zombie) then return self.zombie end
    self.zombie = T.findZombie(self.zid)
    return self.zombie
end

function DP_TieZombie:isValid()
    local zb = self:target()
    if not (zb and T.isDown(zb)) then return false end
    if T.leashOf(self.character) then return false end
    if not (self.rope and self.rope.getContainer and self.rope:getContainer()) then return false end
    return T.dist(self.character, zb) <= T.TIE_REACH + 0.5
end

function DP_TieZombie:waitToStart()
    local zb = self:target()
    if zb then self.character:faceThisObject(zb) end
    return self.character:shouldBeTurning()
end

function DP_TieZombie:update()
    local zb = self:target()
    if zb then self.character:faceThisObject(zb) end
    -- It got up before the knot was tied.
    if not (zb and T.isDown(zb)) then
        if DazedCore.Note then DazedCore.Note.limited(self.character, "IGUI_DazedPower_TreadGotUp", nil, true) end
        self:forceStop()
    end
end

function DP_TieZombie:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end

function DP_TieZombie:stop() ISBaseTimedAction.stop(self) end
function DP_TieZombie:perform() ISBaseTimedAction.perform(self) end

function DP_TieZombie:complete()
    -- True on every "nothing to do" path: false would reject the action on the client (see DP_BankCell).
    local item = self.rope
    local cont = item and item.getContainer and item:getContainer()
    if not cont or (item.getWorldItem and item:getWorldItem()) then return true end
    if not T.ROPES[item:getFullType()] then return true end
    if T.leashOf(self.character) then return true end
    local zb = self:target()
    if not zb or T.dist(self.character, zb) > T.TIE_REACH + 1.0 then return true end
    cont:Remove(item)
    if sendRemoveItemFromContainer then sendRemoveItemFromContainer(cont, item) end
    T.startLeash(self.character, self.zid, item:getFullType())
    return true
end

function DP_TieZombie:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return T.TIE_TICKS
end

--- `zid` is the zombie's key (DP_Tread.zid), so the server can find its own copy. Only plain values and the
--  rope item are parameters: a server rebuilds the action from new's arguments, and an IsoZombie is not one
--  it can carry. The menu sets `zombie` on the result to save this side the search.
function DP_TieZombie:new(character, zid, rope)
    local o = ISBaseTimedAction.new(self, character)
    o.zid = zid
    o.rope = rope
    o.maxTime = o:getDuration()
    return o
end

return DP_TieZombie
