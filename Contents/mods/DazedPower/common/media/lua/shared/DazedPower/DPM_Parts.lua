--[[ Dazed Power -- helpers for the power sources (pedal, windmill, steam, propane, petrol) and the two wind
     instruments. Their identity lives in DP_Parts like every other part's; this file keeps what is
     particular to them: carried-state rules, the amplifier, propane tanks on a generator's ports. ]]

require "DazedPower/DP_Parts"
require "DazedPower/DPM_Model"

DazedPower.More = DazedPower.More or {}
DazedPower.More.Parts = DazedPower.More.Parts or {}
local R = DazedPower.More.Parts
local P = DazedPower.Parts
local MM = DazedPower.More.Model

R.TILESET, R.COLS, R.FACINGS, R.FACING_INDEX = P.TILESET, P.COLS, P.FACINGS, P.FACING_INDEX
R.KINDS = { "pedal", "windmill", "steam", "windsock", "vane", "propane", "petrol" }
R.KIND_SET = {}
for _, k in ipairs(R.KINDS) do R.KIND_SET[k] = true end
R.INSTRUMENT = P.INSTRUMENT
R.GAS_ENGINE = P.GAS_ENGINE
R.GEAR_ITEM, R.GEAR_ORDER, R.AMP_ITEM = P.GEAR_ITEM, P.GEAR_ORDER, P.AMP_ITEM
R.gearOfItem = P.gearOfItem

--- Which parts take an amplifier: everything that makes power, never the wind instruments.
function R.canAmplify(info)
    if info == nil then return false end
    if info.kind == "array" then return true end
    return R.KIND_SET[info.kind] == true and not R.INSTRUMENT[info.kind]
end

--- Every item these kinds declare.
function R.allItems()
    local out = {}
    for _, kind in ipairs(R.KINDS) do
        for _, byTier in pairs(P.ITEM[kind]) do
            for _, item in pairs(byTier) do out[#out + 1] = item end
        end
    end
    for _, gear in ipairs(R.GEAR_ORDER) do out[#out + 1] = R.GEAR_ITEM[gear] end
    out[#out + 1] = R.AMP_ITEM
    return out
end

function R.sprite(kind, mount, tier, state, facing) return P.sprite(kind, mount, tier, state, facing) end

function R.spriteInfo(name)
    local info = P.spriteInfo(name)
    if info and R.KIND_SET[info.kind] then return info end
    return nil
end

--- Is this object a power source or an instrument? Returns its description.
function R.describe(obj)
    local info = P.describe(obj)
    if info and R.KIND_SET[info.kind] then return info end
    return nil
end

--- Change state and/or facing in one sprite swap.
function R.setVariant(obj, state, facing)
    if not R.describe(obj) then return false end
    return P.setState(obj, state, facing)
end

--- A propane or petrol generator whose engine is running, which may not be lifted or turned.
function R.runningGen(obj)
    local info = R.describe(obj)
    if not info or not R.GAS_ENGINE[info.kind] then return false end
    local md = obj:getModData()
    local d = md and md.dazedpower
    return d ~= nil and d.running == true
end

--- A boiler that is lit or still hot, which may not be lifted or turned.
function R.hotBoiler(obj)
    local info = R.describe(obj)
    if not info or info.kind ~= "steam" then return false end
    local md = obj:getModData()
    local d = md and md.dazedpower
    return d ~= nil and (d.lit == true or (d.heat or 0) > 0.3)
end

--- A propane tank item at a given fill (0..1) and condition (0..1), for a tank leaving a generator's port.
R.TANK_TYPE = "Base.PropaneTank"
R.TANK_TYPES = { ["Base.PropaneTank"] = true, ["Base.Propane_Refill"] = true }  -- big tank, lantern bottle
function R.tankItem(fullType, fill, cond)
    local t = fullType or R.TANK_TYPE
    if getScriptManager and getScriptManager() and not getScriptManager():getItem(t) then
        t = R.TANK_TYPE
    end
    if P.cellItem then return P.cellItem(t, fill or 0, cond) end
    local item = instanceItem and instanceItem(t)
    if item and item.setCurrentUsesFloat then item:setCurrentUsesFloat(math.max(0, math.min(1, fill or 0))) end
    return item
end

return R
