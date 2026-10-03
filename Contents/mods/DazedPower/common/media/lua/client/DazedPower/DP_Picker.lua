--[[ Dazed Power -- the Building Picker, on the core's (DazedCore.Picker).

     Dazed Power > Choose buildings... on a controller or a transformer opens it. What the part wires is read
     off the two strings the server stores on it (`bw`, the targets; `bwr`, their footprints as rects), so
     every client draws exactly what the server wired. A click sends bwPick to the authority, which decides;
     Remove all sends bwClear. ]]

require "DazedCore/DC_Picker"
require "DazedPower/DP_Parts"
require "DazedPower/DP_Reach"
require "DazedPower/DP_Buildings"
require "DazedPower/DP_Interop"

DazedPower = DazedPower or {}
DazedPower.Picker = DazedPower.Picker or {}
local K = DazedPower.Picker
local P = DazedPower.Parts
local R = DazedPower.Reach
local B = DazedPower.Buildings
local Core = DazedCore.Picker

local function send(playerObj, command, args)
    if DazedPower.Context and DazedPower.Context.send then DazedPower.Context.send(playerObj, command, args) end
end

local function range()
    local I = DazedPower.Interop
    local r = I and I.generatorRange and I.generatorRange() or 20
    local v = I and I.generatorVerticalRange and I.generatorVerticalRange() or 3
    return r, v
end

--- The registry key of the system the part belongs to: the controller's own square, or the one a
--  transformer's claim names. Nil for a transformer in no system.
local function systemKey(st)
    if P.partOf(st.part) == "controller" then return st.x .. "," .. st.y .. "," .. st.z end
    local M = DazedPower.Model
    if not (M and M.parseNodeKey) then return nil end
    local x, y, z = M.parseNodeKey(P.data(st.part).sys)
    if not x then return nil end
    return x .. "," .. y .. "," .. z
end

K.SPEC = {
    title = "IGUI_DazedPower_PickTitle", help = "IGUI_DazedPower_PickHelp", legend = "IGUI_DazedPower_PickLegend",
    clear = "IGUI_DazedPower_PickClear", clearTip = "Tooltip_DazedPower_UnwireBuildings", done = "IGUI_DazedPower_PickDone",
    building = "IGUI_DazedPower_PickBuilding", structure = "IGUI_DazedPower_PickStructure",
    range = function() return range() end,
    textVersion = function(st)
        local d = P.data(st.part)
        return (d.bw or "") .. "|" .. (d.bwr or "")
    end,
    served = function(st)
        local d = P.data(st.part)
        local list = B.decodeTargets(d.bw)
        local rects, i = {}, 1
        for seg in string.gmatch((d.bwr or "") .. "|", "([^|]*)|") do
            rects[i] = seg
            i = i + 1
        end
        for n = 1, #list do list[n].rects = R.decodeRects(rects[n] or "") end
        return list
    end,
    status = function(st, t, fp)
        local G, own = DazedPower.Grid, systemKey(st)
        if G and G.wires and own and G.wires(G.entry(own), t, fp) then return "wired" end
        if G and G.wiredBy and G.wiredBy(t, fp, own) then return "taken" end
        return nil
    end,
    lock = function(st)
        local G = DazedPower.Place
        if not (st.player and st.part and G and G.useRefusal) then return nil end
        return G.useRefusal(st.player, P.try(st.part, "getSquare"), st.part)
    end,
    pick = function(st, sx, sy, sz)
        send(st.player, "bwPick", { x = st.x, y = st.y, z = st.z, kind = st.kind, sx = sx, sy = sy, sz = sz })
    end,
    clear = function(st) send(st.player, "bwClear", { x = st.x, y = st.y, z = st.z, kind = st.kind }) end,
}

function K.stateFor(playerObj) return Core.stateFor(playerObj) end
function K.isOpen(playerObj) return Core.isOpen(playerObj) end
function K.close(pn) Core.close(pn) end
function K.closeAll() Core.closeAll() end

--- Open the picker for a controller or a transformer.
function K.open(playerObj, part)
    if not playerObj or not part then return nil end
    local kind = P.partOf(part)
    if kind ~= "controller" and kind ~= "transformer" then return nil end
    local st = Core.open(playerObj, part, K.SPEC)
    if st then st.kind = kind end
    return st
end

return K
