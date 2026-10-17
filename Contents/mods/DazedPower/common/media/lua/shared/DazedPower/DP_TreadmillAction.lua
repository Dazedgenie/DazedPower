--[[ Dazed Power -- running on the treadmill (DP_Treadmill).

     Like the pedal generator (DPM_Pedal), this action IS the generation: the watts exist only while it runs. Each
     frame it pins the user to the belt, and about once a second it sends a beat (the gait and the master square) that
     the authority checks (DazedPower.Treadmill.beat) and DPM_Bridge turns into watts. A queued session is
     MA.PEDAL_SECONDS of real time; the user can queue another gait, or stop, at any moment.

     The user pays for it: Fatigue every game minute (DPM_Stats), and in a sprint Endurance too. When Endurance falls
     below the sprint minimum the sprint drops to a run on its own. ]]

require "TimedActions/ISBaseTimedAction"
require "DazedPower/DP_Parts"
require "DazedPower/DP_Env"
require "DazedPower/DPM_Stats"
require "DazedPower/DPM_Model"
require "DazedPower/DPM_Actions"
require "DazedPower/DP_Treadmill"

local P = DazedPower.Parts
local T = DazedPower.Treadmill
local MM = DazedPower.More.Model
local ST = DazedPower.More.Stats
local MA = DazedPower.More.Actions

DPM_Treadmill = ISBaseTimedAction:derive("DPM_Treadmill")

local function clientSide() return isClient and isClient() end

function DPM_Treadmill:isValid()
    if not self.object or self.object:getObjectIndex() == -1 then return false end
    local info = P.describe(self.object)
    return info ~= nil and info.kind == "treadmill"
end

--- Set an animation variable. SetVariable only takes text, so numbers go through setVariable (float), text as the fallback.
function DPM_Treadmill.setVar(character, name, value)
    if type(value) == "number" then
        if character.setVariable and pcall(character.setVariable, character, name, value) then return end
        character:SetVariable(name, tostring(value))
    else
        character:SetVariable(name, value)
    end
end

--- Change the gait the animation plays (and the next beat reports).
function DPM_Treadmill:setMode(mode)
    self.mode = mode
    self.character:SetVariable("DazedTreadmillMode", mode)
    DPM_Treadmill.setVar(self.character, "DazedTreadmillSpeed", (MM.TREADMILL_MODES[mode] or MM.TREADMILL_MODES.walk).pace)
end

--- Stand the user on the belt, facing along it, and keep both tiles of the machine fully drawn for them.
function DPM_Treadmill:mount()
    local sq = self.object and self.object:getSquare()
    local info = self.object and P.describe(self.object)
    if not (sq and info) then return end
    if isServer and isServer() then return end                                   -- the client moves its own player
    local x, y, dir = T.seat(info, sq:getX(), sq:getY())
    local c = self.character
    self.mountedFrom = { x = c:getX(), y = c:getY() }
    local carry = DPM_Treadmill.carry               -- a gait handed over from the one before: where they first stood
    DPM_Treadmill.carry = nil
    if carry and carry.object == self.object and carry.from then self.mountedFrom = carry.from end
    self.mountDir = IsoDirections and IsoDirections[dir] or nil
    self.mountAt = { x = x, y = y }
    DPM_Pedal.place(self, x, y)
    local pn = c.getPlayerNum and c:getPlayerNum() or 0
    for _, o in pairs(T.pieces(self.object)) do DPM_Pedal.solid[o] = pn end
end

--- Is the next queued action another gait on this same machine? Then the user stays on the belt between the two.
function DPM_Treadmill:handsOff()
    local q = ISTimedActionQueue and ISTimedActionQueue.getTimedActionQueue and ISTimedActionQueue.getTimedActionQueue(self.character)
    local nxt = q and q.queue and q.queue[2]
    return nxt ~= nil and nxt.isTreadmillAction == true and nxt.object == self.object
end

function DPM_Treadmill:dismount()
    if self.mountedFrom and self:handsOff() then
        DPM_Treadmill.carry = { object = self.object, from = self.mountedFrom }
        self.mountedFrom, self.mountAt = nil, nil
        return
    end
    for _, o in pairs(T.pieces(self.object)) do DPM_Pedal.solid[o] = nil end
    DPM_Pedal.solid[self.object or false] = nil
    if not self.mountedFrom then return end
    DPM_Pedal.place(self, self.mountedFrom.x, self.mountedFrom.y)
    self.mountedFrom, self.mountAt = nil, nil
end

function DPM_Treadmill:waitToStart()
    self.character:faceThisObject(self.object)
    return self.character:shouldBeTurning()
end

--- The beat: through the network on a multiplayer client, straight to the check everywhere else.
function DPM_Treadmill:beat(nowMs)
    local sq = self.object:getSquare()
    if not sq then return end
    local args = { x = sq:getX(), y = sq:getY(), z = sq:getZ(), mode = self.mode }
    if clientSide() then
        if DazedCore and DazedCore.Net then DazedCore.Net.send(self.character, T.MOD, "treadmillBeat", args) end
    elseif not T.beat(self.character, args) and self.forceStop then
        self:forceStop()          -- refused (somebody else is on it): get off
    end
end

function DPM_Treadmill:update()
    if self.mountAt then
        DPM_Pedal.place(self, self.mountAt.x, self.mountAt.y)       -- held on the belt whatever nudges the character
    else
        self.character:faceThisObject(self.object)
    end
    if not self:isValid() then return end

    local nowMs = getTimestampMs and getTimestampMs() or 0
    if not self.beatAt or nowMs < self.beatAt or nowMs - self.beatAt >= MA.PEDAL_BEAT_MS then
        self.beatAt = nowMs
        self:beat(nowMs)
    end

    -- Fatigue (and a sprint's Endurance), charged once per whole game minute actually spent, so a session at a faster
    -- game speed costs at the same faster rate it earns watts at.
    local now = DazedPower.Env.worldHours()
    if not self.lastMinuteHour then self.lastMinuteHour = now end
    local minutes = math.floor((now - self.lastMinuteHour) * 60 + 1e-6)     -- the epsilon: a minute of float hours reads 0.99999
    if minutes >= 1 then
        self.lastMinuteHour = self.lastMinuteHour + minutes / 60
        ST.addFatiguePct(self.character, MM.treadmillFatiguePerMinute(self.mode) * minutes)
        if self.mode == "sprint" then
            local cur = ST.endurance(self.character)
            if cur ~= nil then
                local after = MM.treadmillEnduranceAfter(cur, "sprint", minutes)
                ST.setEndurance(self.character, after)
                if after < MM.TREADMILL_SPRINT_MIN_END then
                    self:setMode("run")
                    P.haloNote(self.character, getText("IGUI_DazedPower_TreadmillWinded"), true)
                end
            end
        end
    end
end

function DPM_Treadmill:start()
    -- A sprint needs the legs for it.
    if self.mode == "sprint" then
        local cur = ST.endurance(self.character)
        if cur ~= nil and cur < MM.TREADMILL_SPRINT_MIN_END then self.mode = "run" end
    end
    self.lastMinuteHour = DazedPower.Env.worldHours()
    self.character:SetVariable("DazedTreadmillMode", self.mode)
    DPM_Treadmill.setVar(self.character, "DazedTreadmillSpeed", MM.TREADMILL_MODES[self.mode].pace)
    self:setActionAnim("DazedTreadmill")
    self:mount()
end

--- Stop billing at once rather than letting the beat age out. Authority and single player; a multiplayer client's
--  release is the action's complete() on the server (or the beat going stale).
function DPM_Treadmill:release()
    if not clientSide() and self.object then T.release(self.object, self.character) end
end

function DPM_Treadmill:stop()
    self:dismount()
    self:release()
    ISBaseTimedAction.stop(self)
end

function DPM_Treadmill:perform()
    self:dismount()
    ISBaseTimedAction.perform(self)
end

function DPM_Treadmill:complete()
    if self.object and self.object:getObjectIndex() ~= -1 then T.release(self.object, self.character) end
    return true
end

function DPM_Treadmill:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return MA.PEDAL_SECONDS * 48
end

function DPM_Treadmill:new(character, object, mode)
    local o = ISBaseTimedAction.new(self, character)
    o.object = T.masterOf(object) or object
    o.isTreadmillAction = true
    o.mode = MM.validTreadmillMode(mode) and mode or "walk"
    o.maxTime = o:getDuration()
    return o
end

return DPM_Treadmill
