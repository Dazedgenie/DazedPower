--[[ Dazed Power -- the Info window's rows for the added machines.

     Dazed Power's "Info" row opens its own window (DP_Info, client side): a
     description, a "What it does" card of label/value rows, and the wiring.
     The rows come from a function private to that file, which knows only
     Dazed Power's own parts, so for ours the card was empty.

     DP_Info is a global window class, and the rows are rebuilt by its
     refresh method -- on opening, and twice a second while it is open. So
     refresh is wrapped: Dazed Power's own runs first, then our rows are added
     to its list (self.rows, the same { k, v, col } entries it draws) and the
     window is grown by that many rows. If a future Dazed Power lays its window
     out some other way, the guard below simply adds nothing.

     STEAM ENGINE, the one that most needs it: what state it is in, fuel and
     water against what it holds, how fast it uses both, and how long it can
     run on what is in it now (DPM_Model.steamRuntime) -- flat out, and, for
     the governed engines, idling on full batteries -- naming which runs out
     first. WINDMILL and PEDAL GENERATOR get their key figures too.
]]

require "DazedPower/DP_Info"
require "DazedPower/DPM_Parts"
require "DazedPower/DPM_Model"

if not (DP_Info and DP_Info.refresh) then return end

local P = DazedPower.Parts
local R = DazedPower.More.Parts
local M = DazedPower.More.Model
local H = DazedPower.More

-- The window's own row pitch (DP_Info: the Small font's height plus 3).
local function rowHeight()
    local ok, fh = pcall(function() return getTextManager():getFontHeight(UIFont.Small) end)
    return ((ok and fh) or 16) + 3
end

local function f1(v) return string.format("%.1f", v or 0) end
local function pct(v) return string.format("%d%%", math.floor((v or 0) * 100 + 0.5)) end
local function yesNo(b) return getText(b and "IGUI_DazedPower_InfoYes" or "IGUI_DazedPower_InfoNo") end

--- A runtime as words: "6.4 h (water runs out first)".
local function runText(h, limit)
    if h == nil then return nil end
    if h == math.huge then return "-" end
    return P.txt(limit == "water" and "IGUI_DazedPower_RunWater" or "IGUI_DazedPower_RunFuel", f1(h))
end

local function steamRows(add, obj, info, d)
    local spec = M.steamSpec(info.tier)
    local heat = d.heat or 0
    local state, col
    if (d.condition or 100) <= 0 then state, col = getText("IGUI_DazedPower_SteamWrecked"), "bad"
    elseif d.indoors then state, col = getText("IGUI_DazedPower_UnderRoof"), "bad"
    elseif d.dry then state, col = getText("IGUI_DazedPower_SteamDry"), "bad"
    elseif d.lit and heat < M.STEAM_READY then
        state, col = P.txt("IGUI_DazedPower_SteamRaising", math.floor(heat / M.STEAM_READY * 100)), "warn"
    elseif d.lit and (d.steamWatts or 0) > 0 then
        state, col = P.txt("IGUI_DazedPower_SteamMaking", math.floor(d.steamWatts + 0.5)), "good"
    elseif d.lit then state, col = getText("IGUI_DazedPower_SteamIdle"), "good"
    elseif heat > 0.3 then state, col = getText("IGUI_DazedPower_SteamCooling"), "dim"
    else state, col = getText("IGUI_DazedPower_SteamCold"), "dim" end
    add(getText("IGUI_DazedPower_InfoState"), state, col)

    local fuel, water = d.fuel or 0, d.water or 0
    add(getText("IGUI_DazedPower_InfoFuel"),
        P.txt("IGUI_DazedPower_InfoOfMax", f1(fuel), tostring(spec.hopper), "fire-h", pct(fuel / spec.hopper)),
        fuel <= 0 and "bad" or (fuel < spec.hopper * 0.2 and "warn" or nil))
    add(getText("IGUI_DazedPower_InfoWater"),
        P.txt("IGUI_DazedPower_InfoOfMax", f1(water), tostring(spec.tank), "L", pct(water / spec.tank)),
        water <= 0 and "bad" or (water < spec.tank * 0.2 and "warn" or nil))
    add(getText("IGUI_DazedPower_InfoUses"),
        P.txt("IGUI_DazedPower_InfoUsesValue", f1(M.steamFullBurn(info.tier)), f1(M.steamFullWater(info.tier))))

    local rt = M.steamRuntime({ tier = info.tier, fuel = fuel, water = water, heat = heat })
    if rt.cantRaise then
        add(getText("IGUI_DazedPower_InfoRunFull"), getText("IGUI_DazedPower_RunCantRaise"), "bad")
    else
        add(getText("IGUI_DazedPower_InfoRunFull"), runText(rt.full, rt.fullLimit),
            rt.full < 1 and "warn" or nil)
        if rt.idle then add(getText("IGUI_DazedPower_InfoRunIdle"), runText(rt.idle, rt.idleLimit)) end
    end
    if rt.raiseFuel > 0.01 then
        add(getText("IGUI_DazedPower_InfoRaise"), P.txt("IGUI_DazedPower_InfoRaiseValue", f1(rt.raiseFuel)), "dim")
    end

    add(getText("IGUI_DazedPower_InfoRated"), string.format("%d W", spec.rated))
    add(getText("IGUI_DazedPower_InfoEff"), pct(spec.eff))
    add(getText("IGUI_DazedPower_InfoGovernor"), yesNo(spec.governor))
    add(getText("IGUI_DazedPower_InfoNoise"), P.count("IGUI_DazedPower_TileCount", spec.noise))
end

local function propaneRows(add, obj, info, d)
    d.kind = d.kind or info.kind
    local petrol = info.kind == "petrol"
    local spec = M.propaneSpec(info.tier, info.kind)
    local fuel = M.propaneFuel(d)
    local unit, perTank = petrol and "L" or "kg", petrol and 20 or M.TANK_KG
    local state, col
    if (d.condition or 100) <= 0 then state, col = getText("IGUI_DazedPower_GenWrecked"), "bad"
    elseif d.running then
        state, col = P.txt("IGUI_DazedPower_GenRunningW", math.floor((d.genWatts or 0) + 0.5)), "good"
    elseif fuel <= 0 then state, col = getText(petrol and "IGUI_DazedPower_GenNoFuelPetrol" or "IGUI_DazedPower_GasNoFuel"), "bad"
    elseif d.mode == "auto" and spec.auto then
        state, col = P.txt("IGUI_DazedPower_GenAutoWaiting", d.startPct or M.PROPANE_START_SOC), "dim"
    else state, col = getText("IGUI_DazedPower_GasOff"), "dim" end
    add(getText("IGUI_DazedPower_InfoState"), state, col)

    local mode = d.mode or "off"
    if mode == "auto" and spec.auto then
        add(getText("IGUI_DazedPower_InfoSwitch"), P.txt("IGUI_DazedPower_InfoSwitchAuto",
            d.startPct or M.PROPANE_START_SOC, M.PROPANE_STOP_SOC))
    else
        add(getText("IGUI_DazedPower_InfoSwitch"), getText(mode == "on" and "IGUI_DazedPower_InfoSwitchOn"
                                                         or "IGUI_DazedPower_InfoSwitchOff"))
    end

    if petrol then
        add(getText("IGUI_DazedPower_InfoPetrol"), P.txt("IGUI_DazedPower_InfoPetrolValue", f1(fuel)),
            fuel <= 0 and "bad" or (fuel < perTank * 0.25 and "warn" or nil))
    else
        add(getText("IGUI_DazedPower_InfoPropane"),
            P.txt("IGUI_DazedPower_InfoPropaneValue", f1(fuel), f1(fuel / M.TANK_KG)),
            fuel <= 0 and "bad" or (fuel < M.TANK_KG * 0.25 and "warn" or nil))
    end
    add(getText("IGUI_DazedPower_InfoReservoir"),
        P.txt("IGUI_DazedPower_InfoOfMax", f1(d.lpg or 0), tostring(spec.reservoir), unit,
              pct((d.lpg or 0) / spec.reservoir)))
    for port = 1, spec.ports do
        local key = (spec.ports > 1) and P.txt("IGUI_DazedPower_InfoPortN", port) or getText("IGUI_DazedPower_InfoPort")
        if d["t" .. port .. "Type"] then
            add(key, P.txt("IGUI_DazedPower_InfoPortTank", pct(d["t" .. port .. "Fill"] or 0)))
        else
            add(key, getText("IGUI_DazedPower_InfoPortEmpty"), "dim")
        end
    end
    add(getText("IGUI_DazedPower_InfoBurns"), P.txt(petrol and "IGUI_DazedPower_InfoBurnsValueL" or "IGUI_DazedPower_InfoBurnsValue",
        f1(M.propaneBurnAt(info.tier, spec.rated, info.kind)), f1(M.propaneBurnAt(info.tier, 0, info.kind))))
    local rt = M.propaneRuntime({ tier = info.tier, kind = info.kind, lpg = d.lpg, condition = d.condition,
        feedTank = d.feedTank, lineTx = d.lineTx, lineTy = d.lineTy, lineTz = d.lineTz,
        t1Type = d.t1Type, t1Fill = d.t1Fill, t2Type = d.t2Type, t2Fill = d.t2Fill })
    add(getText("IGUI_DazedPower_InfoRunFull"), P.txt("IGUI_DazedPower_InfoHours", f1(rt.full)),
        rt.full < 1 and "warn" or nil)
    add(getText("IGUI_DazedPower_InfoRunNoLoad"), P.txt("IGUI_DazedPower_InfoHours", f1(rt.idle)))
    if d.indoors then
        add(getText("IGUI_DazedPower_InfoAir"), getText("IGUI_DazedPower_InfoAirIndoors"), "bad")
    end
    if (d.condition or 100) < M.PROPANE_LEAK_BELOW then
        add(getText("IGUI_DazedPower_InfoLeak"), getText("IGUI_DazedPower_InfoLeakValue"), "bad")
    end
    add(getText("IGUI_DazedPower_InfoRated"), string.format("%d W", spec.rated))
    add(getText("IGUI_DazedPower_InfoEff"), pct(spec.eff))
    add(getText("IGUI_DazedPower_InfoAutoStart"), yesNo(spec.auto))
    add(getText("IGUI_DazedPower_InfoNoise"), P.count("IGUI_DazedPower_TileCount", spec.noise))
end

local function windRows(add, obj, info, d)
    local spec = M.windSpec(info.tier)
    if (d.windWatts or 0) > 0 then
        add(getText("IGUI_DazedPower_InfoNow"), string.format("%d W", math.floor(d.windWatts + 0.5)), "good")
    end
    add(getText("IGUI_DazedPower_InfoRated"), string.format("%d W", spec.rated))
    add(getText("IGUI_DazedPower_InfoCutIn"),
        string.format("%d km/h", math.floor(spec.cutIn * 3.6 / ((spec.hub / 10) ^ (1 / 7)) + 0.5)))
    add(getText("IGUI_DazedPower_InfoTracks"), yesNo(spec.tracks))
    if not spec.tracks then add(getText("IGUI_DazedPower_InfoFacing"), tostring(info.facing)) end
    add(getText("IGUI_DazedPower_InfoStorm"), spec.furl and getText("IGUI_DazedPower_InfoFurls")
        or string.format("%d km/h", math.floor(spec.safe * 3.6 / ((spec.hub / 10) ^ (1 / 7)) + 0.5)))
end

local function pedalRows(add, obj, info, d)
    if (d.pedalWatts or 0) > 0 then
        add(getText("IGUI_DazedPower_InfoNow"), string.format("%d W", math.floor(d.pedalWatts + 0.5)), "good")
    end
    add(getText("IGUI_DazedPower_InfoGearFitted"), getText("IGUI_DazedPower_Gear_" .. (d.gear or "stock")))
    add(getText("IGUI_DazedPower_InfoRider"), P.txt("IGUI_DazedPower_InfoRiderValue",
        math.floor(M.pedalOutput(0, info.tier, d.gear, d.condition) + 0.5),
        math.floor(M.pedalOutput(10, info.tier, d.gear, d.condition) + 0.5)))
end

--- Our rows for one machine, as { k, v, col } entries.
function H.infoRows(obj)
    local info = R.describe(obj)
    local rows = {}
    local function add(k, v, col) if v then rows[#rows + 1] = { k = k, v = v, col = col } end end
    if not info then
        -- Dazed Power's own solar array: just the amplifier, if one is fitted.
        local theirs = P.describe(obj)
        if theirs and theirs.kind == "array" and P.data(obj).amp then
            local d = P.data(obj)
            add(getText("IGUI_DazedPower_InfoAmp"), P.txt("IGUI_DazedPower_InfoAmpValue",
                math.floor((M.AMP_POWER - 1) * 100 + 0.5), f1(M.AMP_WEAR)), "warn")
            if (d.condition or 100) < M.AMP_FIRE_BELOW then
                add(getText("IGUI_DazedPower_InfoAmpSparks"), getText("IGUI_DazedPower_InfoAmpSparksValue"), "bad")
            end
        end
        return rows
    end
    if R.INSTRUMENT[info.kind] then return {} end
    local d = P.data(obj)
    if info.kind == "steam" then steamRows(add, obj, info, d)
    elseif info.kind == "windmill" then windRows(add, obj, info, d)
    elseif info.kind == "pedal" then pedalRows(add, obj, info, d)
    elseif info.kind == "propane" or info.kind == "petrol" then propaneRows(add, obj, info, d) end
    if d.amp then
        add(getText("IGUI_DazedPower_InfoAmp"), P.txt("IGUI_DazedPower_InfoAmpValue",
            math.floor((M.AMP_POWER - 1) * 100 + 0.5), f1(M.AMP_WEAR)), "warn")
        if (d.condition or 100) < M.AMP_FIRE_BELOW then
            add(getText("IGUI_DazedPower_InfoAmpSparks"), getText("IGUI_DazedPower_InfoAmpSparksValue"), "bad")
        end
    end
    add(getText("IGUI_DazedPower_InfoCondition"), pct((d.condition or 100) / 100),
        (d.condition or 100) < 60 and "warn" or nil)
    return rows
end

if not H.infoWrapped then
    H.infoWrapped = true
    local refresh0 = DP_Info.refresh
    function DP_Info:refresh()
        refresh0(self)
        -- Dazed Power's refresh closes the window if the part is gone; only add
        -- to a window it actually filled.
        if not (self.object and type(self.rows) == "table" and self.setHeight) then return end
        local ok, extra = pcall(H.infoRows, self.object)
        if not ok then
            print("DazedPower: info rows failed: " .. tostring(extra))
            return
        end
        if #extra == 0 then return end
        for i = 1, #extra do self.rows[#self.rows + 1] = extra[i] end
        self:setHeight(self:getHeight() + #extra * rowHeight())
    end
end
