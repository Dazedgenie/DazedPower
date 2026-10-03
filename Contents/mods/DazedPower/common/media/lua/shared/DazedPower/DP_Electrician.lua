--[[ DazedPower -- the Electrician profession starts knowing the Makeshift builds.

     Checked when a character spawns (new or loaded), so a save that adds the mod mid-game gets them
     too. The client learns them and asks the server to do the same, so a dedicated server's copy of
     the character agrees. ]]

require "DazedPower/DP_Parts"
require "DazedPower/DP_RecipeLists"

DazedPower = DazedPower or {}
DazedPower.Electrician = DazedPower.Electrician or {}
local E = DazedPower.Electrician
local try = DazedPower.Parts.try

--- Is this character an Electrician? Works with the string professions of early 42 and the
--  registry objects of later builds.
function E.isElectrician(playerObj)
    local desc = try(playerObj, "getDescriptor")
    if not desc then return false end
    local prof = try(desc, "getCharacterProfession") or try(desc, "getProfession")
    if prof == nil then return false end
    return string.find(string.lower(tostring(prof)), "electrician", 1, true) ~= nil
end

local function known(playerObj, name)
    if try(playerObj, "isRecipeKnown", name) then return true end
    local list = try(playerObj, "getKnownRecipes")
    return list ~= nil and try(list, "contains", name) == true
end

--- Teach the Makeshift builds to an Electrician; returns how many were new.
function E.grant(playerObj)
    if not E.isElectrician(playerObj) then return 0 end
    local n = 0
    for _, name in ipairs(DazedPower.RecipeLists.ELECTRICIAN or {}) do
        if not known(playerObj, name) then
            try(playerObj, "learnRecipe", name)
            n = n + 1
        end
    end
    return n
end

local function onCreatePlayer(_, playerObj)
    if not playerObj then return end
    E.grant(playerObj)
    if isClient() and E.isElectrician(playerObj) then
        sendClientCommand(playerObj, "DazedPower", "electrician", {})
    end
end

if not isServer() then Events.OnCreatePlayer.Add(onCreatePlayer) end

return E
