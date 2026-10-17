--[[ Dazed Power -- the right-click rows for the player treadmill (DP_Treadmill).

     Walk, Run and Sprint on the vanilla gym treadmill, in Dazed Power's submenu for the part (from DPM_Menu's addRows).
     A row is greyed when the player is too tired (the pedal's limit), somebody else is on the machine, or a sprint is
     asked of legs with no Endurance left. Picking a gait while already on the belt queues a new action and ends the
     running one; DPM_Treadmill hands the user over without stepping off. ]]

require "DazedPower/DP_Treadmill"
require "DazedPower/DP_TreadmillAction"
require "DazedPower/DPM_Stats"
require "DazedPower/DP_Context"

local T = DazedPower.Treadmill
local P = DazedPower.Parts
local MM = DazedPower.More.Model
local ST = DazedPower.More.Stats

DazedPower.TreadmillMenu = DazedPower.TreadmillMenu or {}
local TM = DazedPower.TreadmillMenu

local function tip(key)
    local C = DazedPower.Context
    return C and C.tip and C.tip(getText(key)) or nil
end

local function grey(opt, key)
    opt.notAvailable = true
    opt.toolTip = tip(key)
end

local ROW_KEY = { walk = "ContextMenu_DazedPower_TreadmillWalk", run = "ContextMenu_DazedPower_TreadmillRun",
                  sprint = "ContextMenu_DazedPower_TreadmillSprint" }

--- Is somebody other than this player on the machine? The authority keeps `tmRider` while a beat is fresh and clears it when it is not.
function TM.busy(d, player)
    return d ~= nil and d.tmRider ~= nil and d.tmRider ~= T.riderKey(player)
end

--- Why this gait is unavailable for this player, as a translation key, or nil.
function TM.refusal(d, player, mode)
    if (ST.fatiguePct(player) or 0) >= MM.PEDAL_TOO_TIRED_PCT then return "Tooltip_DazedPower_TooTired" end
    if TM.busy(d, player) then return "ContextMenu_DazedPower_TreadmillBusy" end
    if mode == "sprint" then
        local cur = ST.endurance(player)
        if cur ~= nil and cur < MM.TREADMILL_SPRINT_MIN_END then return "ContextMenu_DazedPower_TreadmillTooWinded" end
    end
    return nil
end

--- The status line: wired or not, and what it makes now.
function TM.status(obj)
    local d = T.dataOf(obj) or {}         -- read only: an unused treadmill gets no ModData from a menu
    local bits = { getText("IGUI_DazedPower_SrcTreadmill") }
    if not d.sys or d.sys == "" then bits[#bits + 1] = getText("IGUI_DazedPower_NotWired") end
    if (d.tmWatts or 0) > 0 then
        bits[#bits + 1] = P.txt("ContextMenu_DazedPower_TreadmillMaking", math.floor(d.tmWatts + 0.5))
    end
    return table.concat(bits, "   ")
end

--- The running treadmill action of this player on this machine, if any.
local function runningOn(player, master)
    local q = ISTimedActionQueue and ISTimedActionQueue.getTimedActionQueue and ISTimedActionQueue.getTimedActionQueue(player)
    local cur = q and q.queue and q.queue[1]
    if cur and cur.isTreadmillAction and cur.object == master then return cur end
    return nil
end

function TM.onRun(_, target, player, mode)
    local C = DazedPower.Context
    local master = T.masterOf(target) or target
    local cur = runningOn(player, master)
    if not cur and C and C.approach and not C.approach(player, master) then return end
    ISTimedActionQueue.add(DPM_Treadmill:new(player, master, mode))
    -- Already on the belt: the new gait takes over as the old one ends.
    if cur and cur.forceComplete then cur:forceComplete() end
end

--- Rows for one treadmill, into Dazed Power's submenu. `icon` is Dazed Power's C.icon, for the row icons.
function TM.rows(menu, wo, target, player, icon)
    icon = icon or function(o) return o end
    local line = menu:addOption(TM.status(target), nil, nil)
    line.notAvailable = true
    local d = T.dataOf(target)
    for _, mode in ipairs(MM.TREADMILL_MODE_ORDER) do
        local opt = icon(menu:addOption(getText(ROW_KEY[mode]), wo, TM.onRun, target, player, mode), menu, "switchOn")
        local why = TM.refusal(d, player, mode)
        if why then grey(opt, why) end
    end
end

return TM
