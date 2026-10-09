--[[ DazedPower -- heals Dazed Power items made before 0.3.1, whose world sprite still names a tile past 511
     on dazedpower_01. Those tiles moved to dazedpower_02, so the Place cursor found nothing and showed a white box. ]]

if isClient() then return end

require "DazedPower/DP_Parts"

local P = DazedPower.Parts
local done = {}

--- Point one item at the tile's new name; true when it changed.
local function heal(item)
    if not (instanceof(item, "Moveable") and item.getWorldSprite) then return false end
    local n = tonumber(string.match(item:getWorldSprite() or "", "^dazedpower_01_(%d+)$") or "")
    if not n or n < P.SHEET_TILES then return false end
    item:setWorldSprite(P.spriteName(n))
    if item.syncItemFields then pcall(item.syncItemFields, item) end
    return true
end

local function walk(cont)
    local fixed = 0
    local items = cont:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it.IsInventoryContainer and it:IsInventoryContainer() then fixed = fixed + walk(it:getInventory())
        elseif heal(it) then fixed = fixed + 1 end
    end
    return fixed
end

-- Walk one player's inventory once per session.
local function healPlayer(pl)
    local who = tostring(pl:getUsername() or pl:getPlayerNum())
    if not done[who] then
        done[who] = true
        local n = walk(pl:getInventory())
        if n > 0 then print("DazedPower: healed " .. n .. " item(s) carrying an old tile name for " .. who) end
    end
end

local function sweep()
    if isServer() and getOnlinePlayers then
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do healPlayer(list:get(i)) end
    elseif getSpecificPlayer and getSpecificPlayer(0) then
        healPlayer(getSpecificPlayer(0))
    end
end

Events.EveryOneMinute.Add(sweep)
