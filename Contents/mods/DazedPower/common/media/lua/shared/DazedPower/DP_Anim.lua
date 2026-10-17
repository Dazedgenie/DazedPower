--[[ DazedPower -- the work clips: which animation a machine job plays.

     Four clips ship in anims_X/Bob, each with an AnimSet node in
     AnimSets/player/actions that plays when PerformingAction names it
     (tools/blender/dp_work.py builds both):

       tinker  DazedTinker    crouched at the machine, screwdriver at work
       press   DazedPress     crouched at a switch or button: reach, press, let go
       cable   DazedRunCable  squatting, feeding cable along the ground
       sky     DazedReadSky   standing, head up, hand shading the eyes

     Every caller names the vanilla animation it used before (Loot at a
     height, or ExamineVehicle), and gets that instead when the player has
     unticked "Work animations" or when setting the custom one throws. The
     tick box is the real escape hatch: an AnimSet node the engine failed to
     load does not throw, it just matches nothing, and the actions state then
     falls through to default-fallback.xml (the survivor stands, hands
     raised) -- unticking puts every job back on the vanilla clips at once.
]]

DazedPower = DazedPower or {}
DazedPower.Anim = DazedPower.Anim or {}
local A = DazedPower.Anim

A.MOD = "DazedPower"
A.OPTION = "WorkAnims"
A.NODES = { tinker = "DazedTinker", press = "DazedPress", cable = "DazedRunCable", sky = "DazedReadSky" }

--- Does this player want the work clips? Yes unless the option exists and is unticked (a server has no option page).
function A.enabled()
    if not (DazedCore and DazedCore.Options and DazedCore.Options.on) then return true end
    local ok, on = pcall(DazedCore.Options.on, A.MOD, A.OPTION)
    return not ok or on ~= false
end

--- The vanilla way: `anim` (default Loot), LootPosition if given, the loot event unless event == false.
function A.vanilla(action, how)
    how = how or {}
    action:setActionAnim(how.anim or "Loot")
    if how.position then action.character:SetVariable("LootPosition", how.position) end
    if how.event then action.character:reportEvent("EventLootItem") end
    return how.anim or "Loot"
end

--- Plays clip `name` for a timed action, or the vanilla animation `how` describes. Returns the node set.
function A.play(action, name, how)
    local node = A.NODES[name]
    if node and A.enabled() and pcall(action.setActionAnim, action, node) then return node end
    return A.vanilla(action, how)
end

--- The first screwdriver the character carries (bags included), or nil. Same lookup order as P.hasScrewdriver.
function A.screwdriver(character)
    local ok, inv = pcall(function() return character:getInventory() end)
    if not ok or not inv then return nil end
    if ItemTag and ItemTag.SCREWDRIVER and inv.getFirstTagRecurse then
        local okTag, item = pcall(inv.getFirstTagRecurse, inv, ItemTag.SCREWDRIVER)
        if okTag and item then return item end
    end
    if inv.getFirstTypeRecurse then
        local okType, item = pcall(inv.getFirstTypeRecurse, inv, "Screwdriver")
        if okType and item then return item end
    end
    return nil
end

--- Shows `item` in the right hand for the action (left hand empty); nothing changes when there is none.
function A.hold(action, item)
    if not item or not action.setOverrideHandModels then return false end
    return (pcall(action.setOverrideHandModels, action, item, nil))
end

return A
