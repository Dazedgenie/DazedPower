--[[ Dazed Power -- reading the wind.

     Dazed Power's own DP_Env reads only the wind's intensity. The windmills
     need its real speed and direction, so this file reads them itself,
     straight from the ClimateManager, with the self-calibrating direction
     described below. It adds nothing to Dazed Power's tables.
]]

DazedPower = DazedPower or {}
DazedPower.More = DazedPower.More or {}
DazedPower.More.Env = DazedPower.More.Env or {}
local E = DazedPower.More.Env

local function try(obj, method, ...)
    if not obj or not obj[method] then return nil end
    local ok, v = pcall(obj[method], obj, ...)
    if ok then return v end
    return nil
end

------------------------------------------------------------------------ wind
--
--  The engine hands out wind three ways: an intensity 0..1 (getWindIntensity,
--  what env.wind always was), a real speed in km/h (getWindspeedKph), and an
--  angle in degrees (getWindAngleDegrees). The speed is what a turbine's
--  physics wants, so it is read directly.
--
--  The ANGLE is the awkward one. Its convention is not documented anywhere
--  this mod's author could check: where 0 points, and which way it counts,
--  are both unknown, and a vane that points the wrong way is worse than none.
--  But the engine also NAMES the direction (the static
--  ClimateManager.getWindAngleString, "N", "NE", ... "NW"), and a name is
--  unambiguous. So instead of guessing, the angle is calibrated against the
--  name, live:
--
--    * Every way the engine could plausibly be measuring -- 0 at any of the
--      eight compass points, counting either way round -- is a candidate
--      mapping from the engine's degrees to true compass degrees (0 = N,
--      90 = E, clockwise).
--    * Each reading throws out every candidate that would have put the
--      angle in a different eighth of the compass than the engine's own name
--      for it. Readings within a few degrees of a sector edge are not used,
--      so a rounding difference at the boundary cannot throw out the right one.
--    * Once one candidate is left, it is used for full-precision degrees.
--      Until then the name alone is used, which is accurate to one eighth of
--      the compass (plus or minus 22.5 degrees): already enough to aim a
--      turbine or point a vane.
--
--  The one assumption left is that the engine's name says where the wind
--  comes FROM, the way weather reports always name winds (a "north wind"
--  blows from the north). WIND_NAME_IS_FROM flips that in one place if a
--  first look in-game shows the vane backwards.

E.WIND_NAME_IS_FROM = true

E.COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local COMPASS_INDEX = {}
for i, n in ipairs(E.COMPASS) do COMPASS_INDEX[n] = i end

--- Which eighth of the compass a true-compass bearing falls in, and how far
--  it sits from that eighth's nearest edge, in degrees.
function E.sectorOf(deg)
    deg = deg % 360
    local i = math.floor((deg + 22.5) / 45) % 8
    local offset = (deg + 22.5) % 45          -- 0..45 across the sector
    return E.COMPASS[i + 1], math.min(offset, 45 - offset)
end

--- The centre bearing of a compass name, or nil for anything else.
function E.bearingOf(name)
    local i = COMPASS_INDEX[name]
    return i and (i - 1) * 45 or nil
end

-- The candidate mappings, engine degrees -> compass degrees: sign * a + offset.
local function freshCandidates()
    local out = {}
    for _, sign in ipairs({ 1, -1 }) do
        for k = 0, 7 do out[#out + 1] = { sign = sign, offset = k * 45 } end
    end
    return out
end

--- What calibration has established so far. `state` is "learning" (several
--  mappings still fit), "resolved" (exactly one fits; `sign`/`offset` are
--  it), "no-name" (the engine gave no usable direction name, so the angle is
--  taken as plain compass degrees -- an assumption, and the Error Magnifier
--  report says so), or "reset" (a reading contradicted every mapping; it
--  starts over rather than trusting a broken one).
E.windCalib = E.windCalib or { state = "learning", candidates = freshCandidates() }

local EDGE_MARGIN = 3     -- degrees; readings closer than this to an edge are skipped

--- The engine's own name for an angle, normalised, or nil.
local function engineName(cm, angle)
    local function ask(fn, ...)
        local ok, v = pcall(fn, ...)
        if ok and type(v) == "string" then return v end
        return nil
    end
    local s = nil
    local CM = ClimateManager
    if CM and CM.getWindAngleString then s = ask(CM.getWindAngleString, angle) end
    if not s and cm and cm.getWindAngleString then s = ask(cm.getWindAngleString, angle) end
    if not s then return nil end
    s = string.upper((s:gsub("%s+", "")))
    return COMPASS_INDEX[s] and s or nil
end

--- Narrow the candidates with one (angle, name) pair.
function E.calibrate(angle, name)
    local c = E.windCalib
    if not name then
        if c.state == "learning" and not c.sawName then c.state = "no-name" end
        return
    end
    c.sawName = true
    if c.state == "no-name" then c.state = "learning" end
    local keep = {}
    for _, cand in ipairs(c.candidates) do
        local sector, margin = E.sectorOf(cand.sign * angle + cand.offset)
        if margin < EDGE_MARGIN or sector == name then keep[#keep + 1] = cand end
    end
    if #keep == 0 then
        c.candidates, c.state = freshCandidates(), "reset"
        return
    end
    c.candidates = keep
    if #keep == 1 then
        c.state, c.sign, c.offset = "resolved", keep[1].sign, keep[1].offset
    elseif c.state ~= "resolved" then
        c.state = "learning"
    end
end

--- Wind speed (km/h), the bearing it blows FROM (true compass degrees,
--  0 = N, clockwise), and that bearing's compass name. Any of them nil when
--  the engine does not answer.
function E.readWind(cm)
    if not cm then return nil, nil, nil end
    local kph = try(cm, "getWindspeedKph")
    local angle = try(cm, "getWindAngleDegrees")
    if type(kph) ~= "number" or kph ~= kph then kph = nil end
    if type(angle) ~= "number" or angle ~= angle then return kph, nil, nil end

    local name = engineName(cm, angle)
    E.calibrate(angle, name)
    local c = E.windCalib

    local bearing
    if c.state == "resolved" then
        bearing = (c.sign * angle + c.offset) % 360
    elseif name then
        bearing = E.bearingOf(name)
    else
        bearing = angle % 360      -- "no-name": the plain-compass assumption
    end
    if not E.WIND_NAME_IS_FROM then bearing = (bearing + 180) % 360 end
    return kph, bearing, (E.sectorOf(bearing))
end

--- The wind as the model wants it: km/h, the bearing it blows FROM, and
--  that bearing's compass name. Reads the climate afresh each call.
function E.wind()
    return E.readWind(getClimateManager and getClimateManager() or nil)
end

--- A square with open sky over it.
function E.isOutside(square)
    if not square then return false end
    if square.isOutside then return square:isOutside() end
    return true
end

return E
