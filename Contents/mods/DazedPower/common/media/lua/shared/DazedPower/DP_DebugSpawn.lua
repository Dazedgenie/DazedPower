--[[ DazedPower -- every Dazed Power item for Dazed Core's debug spawn ("Dazed debug" in the right-click menu,
     debug mode or staff only). One of each part in every tier, in the order the sheet lists them, then the
     books, kits and amplifier. The controller's extra facing and running records are left out: they are the
     same controller. ]]

require "DazedCore/DC_Boot"
require "DazedCore/DC_DebugSpawn"     -- by name, so it is there whichever mod's shared files load first
require "DazedPower/DP_Parts"

local S = DazedCore.DebugSpawn
if not (S and S.register) then return end      -- a Dazed Core older than 1.5.0

local P = DazedPower.Parts

S.register("power", "Dazed Power", function()
    local out = {}
    for _, kind in ipairs(P.KINDS) do
        local byMount = P.ITEM[kind]
        if byMount then
            for _, mount in ipairs(P.MOUNTS[kind]) do
                for _, tier in ipairs(P.TIERS[kind]) do
                    local item = byMount[mount] and byMount[mount][tier]
                    if item then out[#out + 1] = item end
                end
            end
        end
    end
    for _, k in ipairs({ "MANUAL", "MANUAL_ADV", "ALMANAC", "AMP_ITEM" }) do
        if P[k] then out[#out + 1] = P[k] end
    end
    for _, gear in ipairs(P.GEAR_ORDER or {}) do out[#out + 1] = P.GEAR_ITEM[gear] end
    return out
end)
