--[[ Dazed Power -- wiring other mods' machines into a system through the core's power registry.

     Any mod registers a LOAD with DazedCore.Power (Plumbing does its electric pump and purifier):
     how to recognise the machine, its rated watts and whether it is working. Dazed Power learns
     each such machine as a part through P.describe (by object, never by sprite name, so its
     placement hooks never take over the other mod's). They are leaves: each runs one cable to a
     controller or a transformer and nothing lands on them.

     A wired machine counts as powered while its controller's output is live; Dazed Power answers
     that through the registry's PROVIDER it registers here. The controller then bills its watts
     (DPM_Bridge), and the other mod's own square-power path lists it idle, never paid twice. ]]

require "DazedCore/DC_Boot"
require "DazedPower/DP_Parts"
require "DazedPower/DP_Model"
require "DazedPower/DP_Priority"

DazedPower.More = DazedPower.More or {}
DazedPower.More.Water = DazedPower.More.Water or {}
local W = DazedPower.More.Water
local P = DazedPower.Parts
local M = DazedPower.Model
local DW = DazedCore.Power

--- The registered load this object is, or nil.
function W.loadOf(obj)
    if not (obj and obj.getSprite) then return nil end
    return DW.loadOf(obj)
end

--- What Dazed Power should call this object, or nil when it is not a wireable machine. The load's `kind`
--  names it on the LOADS page (IGUI_DazedPower_Load_<kind>).
function W.identify(obj)
    local l = W.loadOf(obj)
    if not l then return nil end
    M.LOAD_KINDS[l.kind] = true
    return { kind = l.kind, mount = "ground", tier = "salvaged", state = "set", facing = "S", piece = 1, pieces = 1, master = true, load = l }
end

--- The controller this machine is wired to and its ModData, or nil. The claim only counts while the
--  controller's own wire still names the machine.
function W.controllerOf(obj)
    local info = W.identify(obj)
    local md = info and obj:getModData()
    local sys = md and md.dazedpower and md.dazedpower.sys
    if type(sys) ~= "string" then return nil end
    local cx, cy, cz = M.parseNodeKey(sys)
    local sq = cx and obj:getSquare()
    if not sq then return nil end
    local ctrl = P.objectAt(cx, cy, cz, "controller")
    local cmd = ctrl and ctrl:getModData()
    local cd = cmd and cmd.dazedpower
    if not cd then return nil end
    local nk = M.nodeKey(sq:getX(), sq:getY(), sq:getZ(), info.kind)
    for _, e in ipairs(M.wireParse(cd.wire or "")) do
        if e.a == nk or e.b == nk then return ctrl, cd end
    end
    return nil
end

--- Is this machine wired to a controller whose output is live right now?
function W.poweredByWire(obj)
    local _, cd = W.controllerOf(obj)
    if not (cd ~= nil and cd.powered == true and cd.online == true and not cd.trip and not cd.lvd) then return false end
    local l = W.loadOf(obj)
    local Pr = DazedPower.Priority
    return not (l and Pr and Pr.shed(cd, l.kind))
end

--- The load kind, its rated watts and whether it is drawing them now.
function W.draw(obj)
    local l = W.loadOf(obj)
    if not l then return nil, 0, false end
    return l.kind, DW.rated(obj, l), DW.draw(obj, l) > 0
end

--- Tell the core that a wired machine is powered. Answers nil for anything that is not a registered load.
function W.install()
    DW.registerProvider({ id = "dazedpower_wire", isPowered = function(obj)
        if not W.loadOf(obj) then return nil end
        return W.poweredByWire(obj)
    end })
end

if not W.wrapped then
    W.wrapped = true

    -- Identity: a registered load first, so a stale ModData stamp can never answer for it.
    -- Our own sheet's sprites are never another mod's load, so they skip the registry walk.
    local describe0 = P.describe
    function P.describe(obj)
        local spr = obj and obj.getSprite and obj:getSprite()
        if spr and P.indexOf(spr:getName()) then return describe0(obj) end
        return W.identify(obj) or describe0(obj)
    end

    -- Dazed Power stamps identity into ModData; a load's is cleared so removing Dazed Power leaves no ghost part.
    local data0 = P.data
    function P.data(obj)
        local d = data0(obj)
        if d and M.LOAD_KINDS[d.kind] then
            d.kind, d.mount, d.tier, d.facing, d.state = nil, nil, nil, nil, nil
        end
        return d
    end

    -- The wiring menu and the Info window name a part by its item.
    local itemFor0 = P.itemFor
    function P.itemFor(kind, mount, tier)
        if M.LOAD_KINDS[kind] then
            local l = DW.loads[kind]
            for _, cand in pairs(DW.loads) do if cand.kind == kind then l = cand end end
            return l and l.items and l.items[1] or nil
        end
        return itemFor0(kind, mount, tier)
    end
end

W.install()

return W
