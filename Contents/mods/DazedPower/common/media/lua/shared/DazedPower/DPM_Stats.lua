--[[ Dazed Power -- reading and charging a character's Fatigue.

     The pedal generator costs its rider Fatigue, and the menu greys out
     "Pedal" for someone too tired to. Both go through here, because the
     engine's way of reaching a character's stats has changed under Build 42:

       * Build 42.13 and later (seen live on 42.21): stats are read through
         the CharacterStat enum -- stats:get(CharacterStat.FATIGUE) and
         stats:set(CharacterStat.FATIGUE, value). The old per-stat methods
         are gone: calling stats:getFatigue() there is "tried to call nil",
         which is exactly the error the bike's menu threw in game.
       * Older builds: stats:getFatigue() / stats:setFatigue(value).

     The NEW way is tried first, the old one second, each guarded, so either
     build works and neither can throw into a menu or a timed action.

     THE SCALE. The engine keeps Fatigue as 0..1 (1 = about to pass out),
     not 0..100. This mod's numbers are in PERCENT (DPM_Model's per-minute
     cost, the "too tired" cut-off), so everything here converts: it asks
     the stat for its own maximum when the engine says (getMaximumValue),
     and otherwise takes 1.
]]

DazedPower = DazedPower or {}
DazedPower.More = DazedPower.More or {}
DazedPower.More.Stats = DazedPower.More.Stats or {}
local ST = DazedPower.More.Stats

local warned = false
local function warnOnce(why)
    if warned then return end
    warned = true
    print("DazedPower: cannot reach the character's Fatigue (" .. tostring(why)
          .. "); pedalling will cost no fatigue.")
end

--- The engine's maximum for Fatigue, or 1.
local function fatigueMax()
    local stat = CharacterStat and CharacterStat.FATIGUE
    if stat and stat.getMaximumValue then
        local ok, v = pcall(stat.getMaximumValue, stat)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    return 1
end

--- Read a stat ("FATIGUE", "ENDURANCE") in the engine's own units, and how: returns value, setter.
local function accessStat(character, name)
    local okS, stats = pcall(function() return character:getStats() end)
    if not okS or not stats then return nil, nil end
    -- Build 42.13+: the CharacterStat enum.
    local stat = CharacterStat and CharacterStat[name]
    if stat and stats.get then
        local ok, v = pcall(stats.get, stats, stat)
        if ok and type(v) == "number" then
            return v, function(nv) return pcall(stats.set, stats, stat, nv) end
        end
    end
    -- Older builds: a getter and setter per stat.
    local camel = name:sub(1, 1) .. name:sub(2):lower()
    local getter, setter = stats["get" .. camel], stats["set" .. camel]
    if getter and setter then
        local ok, v = pcall(getter, stats)
        if ok and type(v) == "number" then
            return v, function(nv) return pcall(setter, stats, nv) end
        end
    end
    return nil, nil
end

local function access(character) return accessStat(character, "FATIGUE") end

--- The character's Fatigue as a percentage (0..100), or nil if unreadable.
function ST.fatiguePct(character)
    local v = access(character)
    if v == nil then warnOnce("no readable fatigue"); return nil end
    return math.max(0, math.min(100, v / fatigueMax() * 100))
end

--- Add `pct` percentage points of Fatigue, capped at the stat's maximum.
--  Returns true if it was charged.
function ST.addFatiguePct(character, pct)
    local v, set = access(character)
    if v == nil or not set then warnOnce("no writable fatigue"); return false end
    local max = fatigueMax()
    local ok = set(math.min(max, v + (pct or 0) / 100 * max))
    if not ok then warnOnce("set refused") end
    return ok == true
end

--- The character's Endurance on the engine's 0..1 scale (1 = fresh), or nil if unreadable.
function ST.endurance(character)
    local v = accessStat(character, "ENDURANCE")
    if v == nil then return nil end
    return math.max(0, math.min(1, v))
end

--- Set Endurance (0..1). Returns true if it was written.
function ST.setEndurance(character, value)
    local v, set = accessStat(character, "ENDURANCE")
    if v == nil or not set then return false end
    return set(math.max(0, math.min(1, value or 0))) == true
end

return ST
