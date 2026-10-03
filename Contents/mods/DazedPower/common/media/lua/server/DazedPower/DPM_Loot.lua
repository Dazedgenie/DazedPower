--[[ Dazed Power -- where the generator amplifier turns up.

     The amplifier (Base.DazedAmplifier) is LOOT-ONLY and very rare: it is
     added to the procedural loot lists for electronics stock and for
     military / army-surplus storage, with a small weight each (vanilla's
     common items sit at 1-30; this is a fraction of one).

     Each list is looked up by name and skipped when this version of the game
     does not have it, so a renamed list costs a spawn point, never an error.
     What it did is printed once to the console, so a player can see which
     lists took it.
]]

require "Items/ProceduralDistributions"

DazedPower = DazedPower or {}
DazedPower.More = DazedPower.More or {}
local H = DazedPower.More

H.AMP_LOOT = {
    -- electronics stock and crates
    { "ElectronicStoreMisc",       0.30 },
    { "ElectronicStoreComponents", 0.30 },
    { "ElectronicStoreLights",     0.15 },
    { "CrateElectronics",          0.30 },
    -- military and army surplus
    { "ArmySurplusMisc",           0.40 },
    { "ArmySurplusTools",          0.40 },
    { "ArmyStorageElectronics",    0.50 },
    { "ArmyHangarTools",           0.30 },
}

function H.addAmpLoot()
    if H.ampLootDone then return end
    H.ampLootDone = true
    local lists = ProceduralDistributions and ProceduralDistributions.list
    if not lists then return end
    local added, skipped = {}, {}
    for _, row in ipairs(H.AMP_LOOT) do
        local name, weight = row[1], row[2]
        local list = lists[name]
        if weight > 0 and list and type(list.items) == "table" then
            table.insert(list.items, "Base.DazedAmplifier")
            table.insert(list.items, weight)
            added[#added + 1] = name
        elseif weight > 0 then
            skipped[#skipped + 1] = name
        end
    end
    print(string.format("DazedPower: amplifier loot in %d lists (%s)%s", #added,
        table.concat(added, ", "),
        #skipped > 0 and ("; no such list: " .. table.concat(skipped, ", ")) or ""))
end

-- B42 builds the merged distributions after the Lua loads; adding before
-- that merge is what OnPreDistributionMerge is for. Where the event is
-- missing, add at once.
if Events and Events.OnPreDistributionMerge then
    Events.OnPreDistributionMerge.Add(H.addAmpLoot)
else
    H.addAmpLoot()
end
