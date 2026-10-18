--[[ DazedPower -- "Spawn Dazed Power generators" inside Dazed Core's "Dazed debug" right-click row: every
     generator type with a row per tier and one for all three tiers, the one-tier sources, and a row for the
     lot. The rows send Dazed Core's own spawn command with the hidden sets DP_DebugSpawn registers, so the
     authority checks who may spawn and places the parts the way the full Power set does. ]]

require "DazedCore/DC_DebugSpawnMenu"   -- Core's row is added to the menu first, so this one finds it
require "DazedPower/DP_DebugSpawn"

local S = DazedCore and DazedCore.DebugSpawn
local G = DazedPower and DazedPower.DebugGens
if not (S and S.sets and G and G.ALL) then return end   -- a Dazed Core without debug spawn

local P = DazedPower.Parts

local function onSpawn(_, playerObj, id)
    DazedCore.Net.send(playerObj, S.MODULE, S.COMMAND, { set = id })
end

local function nameOf(fullType)
    local sm = getScriptManager and getScriptManager()
    local item = sm and sm:getItem(fullType)
    return item and item:getDisplayName() or fullType
end

local function onFill(player, context, worldobjects, test)
    if test then return end
    local playerObj = getSpecificPlayer(player)
    if not (playerObj and S.allowed(playerObj)) then return end
    local head = context:getOptionFromName(getText("IGUI_DazedCore_Debug"))
    local sub = head and head.subOption and context:getSubMenu(head.subOption)
    if not sub then return end

    local genHead = sub:addOption(getText("IGUI_DazedPower_DebugGens"), worldobjects, nil)
    local genSub = ISContextMenu:getNew(sub)
    sub:addSubMenu(genHead, genSub)
    genSub:addOption(getText("IGUI_DazedPower_DebugGensAll"), worldobjects, onSpawn, playerObj, G.ALL)
    for _, kind in ipairs(G.TIERED) do
        local kindHead = genSub:addOption(getText("IGUI_DazedPower_DebugGen_" .. kind), worldobjects, nil)
        local kindSub = ISContextMenu:getNew(genSub)
        genSub:addSubMenu(kindHead, kindSub)
        kindSub:addOption(getText("IGUI_DazedPower_DebugGenTiers"), worldobjects, onSpawn, playerObj, G.kindId(kind))
        for _, tier in ipairs(P.TIERS[kind] or {}) do
            local item = G.item(kind, tier)
            if item then kindSub:addOption(nameOf(item), worldobjects, onSpawn, playerObj, G.tierId(kind, tier)) end
        end
    end
    for _, fullType in ipairs(G.SINGLE) do
        genSub:addOption(nameOf(fullType), worldobjects, onSpawn, playerObj, G.itemId(fullType))
    end
end

if Events and Events.OnFillWorldObjectContextMenu and not G.menuHooked then
    G.menuHooked = true
    Events.OnFillWorldObjectContextMenu.Add(onFill)
end
