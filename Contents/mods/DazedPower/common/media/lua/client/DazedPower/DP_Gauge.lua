--[[ DazedPower -- reading a wall power gauge.

     A gauge cabled into a system opens that system's monitor face, read only: the charge, the watts
     in and out, the loads and the generators, without walking to the controller. Its own sprite
     shows the charge band at a glance (DP_System sets it). ]]

require "DazedPower/DP_Parts"

DazedPower = DazedPower or {}
DazedPower.Gauge = DazedPower.Gauge or {}
local G = DazedPower.Gauge
local P = DazedPower.Parts
local M = DazedPower.Model

--- The controller a gauge reads, or nil and the reason: not wired, or its controller is not loaded here.
function G.controllerOf(gauge)
    local d = gauge and P.data(gauge)
    local root = d and d.sys
    if type(root) ~= "string" or root == "" then return nil, "IGUI_DazedPower_GaugeLoose" end
    local x, y, z = M.parseNodeKey(root)
    local ctrl = x and P.objectAt(x, y, z, "controller")
    if not ctrl then return nil, "IGUI_DazedPower_GaugeFar" end
    return ctrl
end

--- Open the monitor of the system this gauge reads, or say why not.
function G.open(playerObj, gauge)
    local ctrl, why = G.controllerOf(gauge)
    if not ctrl then
        P.haloNote(playerObj, getText(why), true)
        return nil
    end
    if not (DazedPower.Window and DazedPower.Window.open) then return nil end
    return DazedPower.Window.open(playerObj, ctrl, { readOnly = true })
end

--- The context line for a gauge: what it reads, and the charge.
function G.status(gauge)
    local ctrl, why = G.controllerOf(gauge)
    if not ctrl then return getText(why) end
    local d = P.data(ctrl)
    return P.txt("IGUI_DazedPower_GaugeStatus", math.floor((d.soc or 0) * 100 + 0.5),
                 math.floor((d.gen or 0) + 0.5), math.floor((d.load or 0) + 0.5))
end

return G
