--[[ DazedPower -- admin tools: who may use them, and the read-only inspect text.
     Shared so the client menu and the server's command check ask the same question. ]]

require "DazedPower/DP_Model"
require "DazedPower/DP_Parts"

DazedPower = DazedPower or {}
DazedPower.Admin = DazedPower.Admin or {}
local A = DazedPower.Admin
local P = DazedPower.Parts

--- True in single player with the game in debug mode. A multiplayer server or client never counts.
function A.debugSP()
    if isClient() or isServer() then return false end
    return getDebug ~= nil and getDebug() == true
end

--- May this character use the admin rows? Staff (DP_Place's role check) or single-player debug.
function A.allowed(character)
    if A.debugSP() then return true end
    local G = DazedPower.Place
    return character ~= nil and G ~= nil and G.isStaff ~= nil and G.isStaff(character) == true
end

local function txt(k) return getText("ContextMenu_DazedPower_Admin" .. k) end
local function yesNo(v) return v and txt("Yes") or txt("No") end
local function num(v) return string.format("%.0f", tonumber(v) or 0) end

--- The inspect window's lines for a controller's synced ModData `d`, at `key` "x,y,z". Plain strings, one per line.
function A.inspectLines(d, key)
    d = d or {}
    local out = {}
    local function add(label, value) out[#out + 1] = txt(label) .. ": " .. tostring(value) end
    add("Key", key or "?")
    add("Online", yesNo(d.online == true))
    add("Trip", yesNo(d.trip == true))
    add("Lvd", yesNo(d.lvd == true))
    add("Soc", string.format("%d%%", math.floor((tonumber(d.soc) or 0) * 100 + 0.5)))
    add("Charge", num(d.charge) .. " / " .. num(d.capacity) .. " Wh")

    -- Parts by kind: the counts the tick writes, plus each source kind read off the SOURCE page rows.
    local rows = type(d.dpmRows) == "table" and d.dpmRows or {}
    local srcCount, srcKinds = {}, {}
    for i = 1, #rows do
        local k = tostring(rows[i].k or "?")
        if not srcCount[k] then srcKinds[#srcKinds + 1] = k end
        srcCount[k] = (srcCount[k] or 0) + 1
    end
    table.sort(srcKinds)
    local parts = { "array " .. (d.arrayCount or 0), "bank " .. (d.bankCount or 0), "transformer " .. (d.xfmrCount or 0) }
    for i = 1, #srcKinds do parts[#parts + 1] = srcKinds[i] .. " " .. srcCount[srcKinds[i]] end
    add("Parts", table.concat(parts, ", "))

    add("Sources", #rows)
    for i = 1, #rows do
        local r = rows[i]
        out[#out + 1] = string.format("  %s (%s, %s) %s W @ %s,%s", tostring(r.k or "?"), tostring(r.t or "-"),
                                      tostring(r.s or "-"), num(r.w), tostring(r.x or "?"), tostring(r.y or "?"))
    end
    add("Loads", num(d.demand) .. " W")
    local Bd = DazedPower.Buildings
    local nb = (Bd and Bd.decodeTargets) and #Bd.decodeTargets(d.bw) or 0
    add("Buildings", nb)
    return out
end

--- Every part object a controller record holds, controller excluded: arrays, banks, transformers, gauges and rec.dpm sources.
function A.partsOf(rec)
    local out = {}
    if not rec then return out end
    for _, list in ipairs({ rec.arrays, rec.banks, rec.xfmrs, rec.gauges }) do
        for i = 1, #(list or {}) do out[#out + 1] = list[i] end
    end
    for _, list in pairs(rec.dpm or {}) do
        for i = 1, #list do out[#out + 1] = list[i] end
    end
    return out
end

--- Set a part's condition to full: arrays and sources by d.condition, each rack cell up to its wear ceiling.
function A.repairPart(obj)
    local d = P.data(obj)
    if type(d.cellList) == "table" then
        local M = DazedPower.Model
        for i = 1, #d.cellList do d.cellList[i].health = M.healthCeiling(d.cellList[i]) end
    end
    if d.condition ~= nil then d.condition = 100 end
    -- A burst boiler at full condition is a working one again.
    if d.blown then d.blown = nil end
end

--- Fill one rack to its nominal capacity (what its cells hold with the weather taken out).
function A.fillBank(obj)
    local info = P.describe(obj)
    if not info then return end
    local d = P.data(obj)
    d.charge = DazedPower.Model.bankNominal({ tier = info.tier, scale = P.bankScale(), cellList = d.cellList })
end

return A
