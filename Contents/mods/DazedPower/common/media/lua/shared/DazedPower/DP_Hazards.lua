--[[ DazedPower -- lightning and hydrogen: the pure rules.

     A thunderstorm may trip a system's isolator; a grounding rod beside the controller sends it to earth.
     A Makeshift bank charged hard in a closed room builds gas: a warning first, a fire only if ignored.
     The server hooks (DPM_Hazards) roll the dice and apply the outcomes. ]]

require "DazedPower/DP_Parts"

DazedPower = DazedPower or {}
DazedPower.Hazards = DazedPower.Hazards or {}
local H = DazedPower.Hazards

H.STRIKE_PER_MIN = 0.002      -- per game minute of thunder, at StormRate 100
H.HEAVY = 0.05                -- share of strikes that fry an unprotected controller
H.HEAVY_DAMAGE = 40           -- condition points a heavy strike takes
H.ROD_RADIUS = 6              -- tiles from the controller a rod covers

H.H2_WARN = 10                -- minutes at risk before the warning
H.H2_FIRE = 40                -- minutes at risk before a fire becomes possible
H.H2_FIRE_CHANCE = 0.04       -- per minute past that
H.H2_RATE_W = 120             -- charge rate per Makeshift rack that makes gas

--- Chance of a strike this minute, from the sandbox rate (percent).
function H.strikeChance(ratePct)
    return H.STRIKE_PER_MIN * math.max(0, ratePct or 100) / 100
end

--- What a strike does: "rod" when a rod covers the system, else "trip", rarely "hit".
--  `roll` is 0..1 and decides light against heavy.
function H.strikeOutcome(hasRod, roll)
    if hasRod then return "rod" end
    if roll < H.HEAVY then return "hit" end
    return "trip"
end

--- Is a rack making gas? Only Makeshift ones, charging hard, with no air.
function H.atRisk(tier, chargeW, ventilated)
    return tier == "makeshift" and (chargeW or 0) >= H.H2_RATE_W and not ventilated
end

--- One minute of the gas counter. Returns the new minutes and an event: "warn" once, "fire" on a roll.
function H.h2Step(minutes, warned, risk, roll)
    minutes = minutes or 0
    if not risk then return math.max(0, minutes - 2), warned, nil end
    minutes = minutes + 1
    if not warned and minutes >= H.H2_WARN then return minutes, true, "warn" end
    if minutes >= H.H2_FIRE and (roll or 1) < H.H2_FIRE_CHANCE then return 0, false, "fire" end
    return minutes, warned, nil
end

return H
