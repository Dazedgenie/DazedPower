--[[ Dazed Power -- a status line in the Dazed Power submenu of Plumbing's
     wired water pump and purifier: not wired, powered, or wired with the
     controller's power off. Added under Info through C.icon, as DPM_Menu does.
]]

require "DazedPower/DP_Context"
require "DazedPower/DP_Parts"
require "DazedPower/DPM_Water"

local C = DazedPower.Context
local W = DazedPower.More.Water
if not (C and C.icon and W) then return end

--- The line for this machine, with how many watts it takes when it runs.
local function statusLine(target)
    local _, rated = W.draw(target)
    local ctrl, cd = W.controllerOf(target)
    if not ctrl then return getText("IGUI_DazedPower_NotWired") end
    local key = W.poweredByWire(target) and "IGUI_DazedPower_WaterWiredOn" or "IGUI_DazedPower_WaterWiredOff"
    return DazedPower.Parts.txt(key, tostring(rated or 0))
end

if not W.menuWrapped then
    W.menuWrapped = true
    local icon0 = C.icon
    function C.icon(option, menu, row)
        local out = icon0(option, menu, row)
        if row == "info" and type(option) == "table" and menu and menu.addOption then
            local target = option.param1
            if target and target.getSprite and W.identify(target) then
                local ok, text = pcall(statusLine, target)
                if ok and text then
                    menu:addOption(text, nil, nil).notAvailable = true
                end
            end
        end
        return out
    end
end
