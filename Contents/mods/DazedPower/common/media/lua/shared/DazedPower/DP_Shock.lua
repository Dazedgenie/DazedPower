--[[ DazedPower -- the live-work shock.

     Running or cutting a cable while the controller's output is on can burn the hand that did it.
     The chance grows with what the system is carrying and falls with Electricity skill; switching
     the controller off first makes it safe. A burn and pain only: never lethal (LiveShock sandbox). ]]

require "DazedPower/DP_Parts"

DazedPower = DazedPower or {}
DazedPower.Shock = DazedPower.Shock or {}
local K = DazedPower.Shock
local P = DazedPower.Parts

K.BASE = 0.08            -- chance on a live system carrying nothing
K.PER_KW = 0.12          -- added per kW of load or generation, whichever is larger
K.MAX = 0.45             -- never worse than this
K.SKILL_CUT = 0.08       -- each Electricity level takes this share off
K.SKILL_FLOOR = 0.2      -- a master electrician keeps a fifth of the risk
K.PAIN = 35              -- extra pain on the burned hand
K.MIN_HEALTH = 25        -- below this overall health nothing happens

--- Is this controller's output live? Its isolator on, not tripped, and the system powered.
function K.live(d)
    return type(d) == "table" and d.online == true and not d.trip and d.powered == true
end

--- The chance of a shock for one cable job on a live system, from its watts and the worker's level.
function K.chance(watts, level)
    local kw = math.max(0, tonumber(watts) or 0) / 1000
    local c = math.min(K.MAX, K.BASE + K.PER_KW * kw)
    local skill = math.max(K.SKILL_FLOOR, 1 - K.SKILL_CUT * math.max(0, tonumber(level) or 0))
    return c * skill
end

--- Burn one hand and add pain; the same hand and values on both sides, so applying twice is harmless.
function K.apply(playerObj, hand)
    local bd = P.try(playerObj, "getBodyDamage")
    if not bd or not BodyPartType then return false end
    if (P.try(bd, "getOverallBodyHealth") or 100) < K.MIN_HEALTH then return false end
    local part = P.try(bd, "getBodyPart", hand == "L" and BodyPartType.Hand_L or BodyPartType.Hand_R)
    if not part then return false end
    if not P.try(part, "isBurnt") then P.try(part, "setBurned") end
    if (P.try(part, "getAdditionalPain") or 0) < K.PAIN then P.try(part, "setAdditionalPain", K.PAIN) end
    return true
end

--- Roll for a shock after a cable job on `ctrl`'s system. Runs on the authority only.
function K.risk(playerObj, ctrl, why)
    if isClient() or not playerObj or not ctrl then return false end
    if P.sandbox("LiveShock") == false then return false end
    local d = P.data(ctrl)
    if not K.live(d) then return false end
    local level = P.try(playerObj, "getPerkLevel", Perks and Perks.Electricity) or 0
    local watts = math.max(d.load or 0, d.gen or 0)
    if ZombRandFloat(0, 1) >= K.chance(watts, level) then return false end
    local hand = (ZombRand(2) == 0) and "L" or "R"
    K.apply(playerObj, hand)
    if isServer() and sendServerCommand then
        sendServerCommand(playerObj, "DazedPower", "shock",
                          { hand = hand, id = P.try(playerObj, "getOnlineID") })
    else
        K.feel(playerObj)
    end
    return true
end

--- What the player hears and says; on a client this also applies the burn the server sent.
function K.feel(playerObj, hand)
    if hand then K.apply(playerObj, hand) end
    P.haloNote(playerObj, getText("IGUI_DazedPower_Shocked"), true)
end

return K
