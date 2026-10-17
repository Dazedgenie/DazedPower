--[[ Dazed Power -- the right-click rows for the zombie treadwheel and the rope (DP_Tread).

     World menu (through Dazed Core's Menu): "Tie up the zombie" on a downed zombie at or beside the clicked
     square, and "Let go of the rope" while leading one. The wheel's own rows (status, put the zombie on,
     release, put down) go into Dazed Power's submenu for the part, from DPM_Menu's addRows. ]]

require "DazedPower/DP_Tread"
require "DazedPower/DP_TreadActions"
require "DazedPower/DP_Context"

local T = DazedPower.Tread
local P = DazedPower.Parts
local MM = DazedPower.More.Model
local try = P.try

DazedPower.TreadMenu = DazedPower.TreadMenu or {}
local TM = DazedPower.TreadMenu

local function tip(key)
    local C = DazedPower.Context
    return C and C.tip and C.tip(getText(key)) or nil
end

local function grey(opt, key)
    opt.notAvailable = true
    opt.toolTip = tip(key)
end

---------------------------------------------------------------- tying

--- A downed zombie, not already tied, on the square or the eight around it: the nearest to the player.
function TM.downedZombieNear(square, player)
    if not square then return nil end
    local tied = {}
    for _, l in pairs(T.leashes) do tied[l.zid] = true end
    local best, bestD = nil, math.huge
    for dx = -1, 1 do
        for dy = -1, 1 do
            local s = DazedCore.Util.squareAt(square:getX() + dx, square:getY() + dy, square:getZ())
            local mov = s and s:getMovingObjects()
            for i = 0, (mov and mov:size() or 0) - 1 do
                local z = mov:get(i)
                if z and instanceof(z, "IsoZombie") and T.isDown(z) and not tied[T.zid(z) or -1] then
                    local d = T.dist(z, player)
                    if d < bestD then best, bestD = z, d end
                end
            end
        end
    end
    return best
end

function TM.onTie(_, player, zombie, rope)
    if not (zombie and rope and T.zombieAlive(zombie)) then return end
    local sq = zombie:getCurrentSquare()
    if sq and T.dist(player, zombie) > T.TIE_REACH and luautils and luautils.walkAdj then
        if not luautils.walkAdj(player, sq, true) then return end
    end
    local a = DP_TieZombie:new(player, T.zid(zombie), rope)
    a.zombie = zombie
    ISTimedActionQueue.add(a)
end

function TM.onLetGo(_, player)
    DazedCore.Net.send(player, T.MOD, "treadLetGo", {})
end

local function worldRows(player, context, square)
    if not (player and context and square) then return end
    if T.leashOf(player) then
        context:addOption(getText("ContextMenu_DazedPower_TreadLetGo"), nil, TM.onLetGo, player)
        return
    end
    local zombie = TM.downedZombieNear(square, player)
    if not zombie then return end
    local rope = T.ropeIn(player)
    local opt = context:addOption(getText("ContextMenu_DazedPower_TreadTie"), nil, TM.onTie, player, zombie, rope)
    if not rope then grey(opt, "Tooltip_DazedPower_TreadNeedRope")
    else opt.toolTip = tip("Tooltip_DazedPower_TreadTie") end
end
TM.worldRows = worldRows

if not TM.menuFiled and DazedCore.Menu then
    TM.menuFiled = true
    DazedCore.Menu.world("DazedPower.tread", worldRows, 60)
end

---------------------------------------------------------------- the wheel's rows

--- The wheel's status line: who is in it and what it makes.
function TM.status(obj)
    local d = P.data(obj)
    local bits = {}
    if not d.sys or d.sys == "" then bits[#bits + 1] = getText("IGUI_DazedPower_NotWired") end
    local z = T.occupant(obj)
    if not z then
        bits[#bits + 1] = getText("IGUI_DazedPower_TreadEmpty")
    else
        bits[#bits + 1] = getText(z.crawler and "IGUI_DazedPower_TreadCrawling" or "IGUI_DazedPower_TreadWalking")
        if (d.treadWatts or 0) > 0 then
            bits[#bits + 1] = P.txt("IGUI_DazedPower_SteamMaking", math.floor(d.treadWatts + 0.5))
        elseif (d.condition or 100) <= MM.TREAD_STOP_BELOW then
            bits[#bits + 1] = getText("IGUI_DazedPower_TreadSlipping")
        end
        if d.treadLured then bits[#bits + 1] = getText("IGUI_DazedPower_TreadLured") end
    end
    bits[#bits + 1] = P.txt("IGUI_DazedPower_ConditionPct", math.floor(d.condition or 100))
    return table.concat(bits, "   ")
end

local function send(command, player, obj)
    local sq = obj and obj:getSquare()
    if not sq then return end
    DazedCore.Net.send(player, T.MOD, command, { x = sq:getX(), y = sq:getY(), z = sq:getZ() })
end

--- The authority refuses wheel commands beyond LOAD_REACH and says nothing, so the rows are greyed instead
--  (DP_Context does the same for its own commands).
function TM.inReach(player, obj)
    local sq = obj and obj:getSquare()
    if not (sq and player) or math.floor(player:getZ()) ~= sq:getZ() then return false end
    local dx, dy = player:getX() - (sq:getX() + 0.5), player:getY() - (sq:getY() + 0.5)
    return dx * dx + dy * dy <= T.LOAD_REACH * T.LOAD_REACH
end

local function act(command)
    return function(_, obj, player) send(command, player, obj) end
end
TM.onLoad, TM.onRelease, TM.onPutDown = act("treadLoad"), act("treadRelease"), act("treadPutDown")

--- Rows for one treadwheel, into Dazed Power's submenu. `icon` is Dazed Power's C.icon, for the row icons.
function TM.wheelRows(menu, wo, target, player, icon)
    icon = icon or function(o) return o end
    local line = menu:addOption(TM.status(target), nil, nil)
    line.notAvailable = true
    local far = not TM.inReach(player, target)
    if T.occupied(target) then
        local rel = icon(menu:addOption(getText("ContextMenu_DazedPower_TreadRelease"), wo, TM.onRelease, target, player), menu, "clean")
        local put = icon(menu:addOption(getText("ContextMenu_DazedPower_TreadPutDown"), wo, TM.onPutDown, target, player), menu, "clean")
        if far then grey(rel, "Tooltip_DazedPower_TreadWalkCloser") grey(put, "Tooltip_DazedPower_TreadWalkCloser")
        else rel.toolTip = tip("Tooltip_DazedPower_TreadRelease") put.toolTip = tip("Tooltip_DazedPower_TreadPutDown") end
        return
    end
    local opt = icon(menu:addOption(getText("ContextMenu_DazedPower_TreadLoad"), wo, TM.onLoad, target, player), menu, "clean")
    local l = T.leashOf(player)
    if not l then
        grey(opt, "Tooltip_DazedPower_TreadNeedZombie")
    elseif far then
        grey(opt, "Tooltip_DazedPower_TreadWalkCloser")
    else
        local zb = T.findZombie(l.zid)
        local sq = target:getSquare()
        if zb and sq then
            local dx, dy = zb:getX() - (sq:getX() + 0.5), zb:getY() - (sq:getY() + 0.5)
            if dx * dx + dy * dy > (T.LOAD_REACH + 0.5) * (T.LOAD_REACH + 0.5) then grey(opt, "Tooltip_DazedPower_TreadBringCloser")
            else opt.toolTip = tip("Tooltip_DazedPower_TreadLoad") end
        end
    end
end

return TM
