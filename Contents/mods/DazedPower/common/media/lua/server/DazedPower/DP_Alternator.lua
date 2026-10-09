--[[ DazedPower -- the server side of hooked-up cars: the hook command and the live list each step. ]]

if isClient() then return end

require "DazedPower/DP_System"
require "DazedPower/DP_Alternator"

local S = DazedPower.System
local A = DazedPower.Alternator
local P = DazedPower.Parts
local M = DazedPower.Model

--- Every loaded vehicle by its lasting id, built from one walk of the cell's list.
local function buildIndex()
    local cell = getCell and getCell()
    local list = cell and cell:getVehicles()
    local byId = {}
    for i = 0, (list and list:size() or 0) - 1 do
        local v = list:get(i)
        local id = A.idOf(v)
        -- The first vehicle with an id wins, as the old front-to-back search did.
        if id and byId[id] == nil then byId[id] = v end
    end
    return byId
end

-- Shared by every controller during one simulation tick (S.tick below); nil outside one.
local tickIndex = nil

local function vehicleById(id, fresh)
    if tickIndex and not fresh then
        if not tickIndex.byId then tickIndex.byId = buildIndex() end
        return tickIndex.byId[id]
    end
    return buildIndex()[id]
end
A.vehicleById = vehicleById

--- Share one vehicle index across a tick: on (true) at its start, off (false) at its end.
function A.holdVehicles(on)
    tickIndex = on and {} or nil
end

if not A.tickWrapped then
    A.tickWrapped = true
    local tick0 = S.tick
    function S.tick(...)
        -- A tick that throws leaves the index held only until the next tick starts a fresh one.
        A.holdVehicles(true)
        local r = tick0(...)
        A.holdVehicles(false)
        return r
    end
end

local function engineCondition(v)
    local part = v.getPartById and v:getPartById("Engine")
    return part and part:getCondition() or 0
end

function A.hasLinks(rec)
    local gen = rec and S.controllerOf(rec)
    return gen ~= nil and (P.data(gen).cars or "") ~= ""
end

--- The hooked cars that are here and running, as source entries; drops links whose car left.
function A.liveCars(rec)
    local gen = S.controllerOf(rec)
    if not gen then return {} end
    local d = P.data(gen)
    if (d.cars or "") == "" then return {} end
    local keep, out = {}, {}
    for _, l in ipairs(A.parse(d.cars)) do
        local v = vehicleById(l.id)
        local sq = v and v:getSquare()
        if v and sq and math.abs(sq:getX() - l.x) <= A.REACH and math.abs(sq:getY() - l.y) <= A.REACH then
            keep[#keep + 1] = l
            local running = v.isEngineRunning and v:isEngineRunning() or false
            local cond = engineCondition(v)
            out[#out + 1] = { obj = v, watts = A.output(running, cond), condition = cond, x = sq:getX(), y = sq:getY() }
        elseif getSquare(l.x, l.y, l.z) then
            -- the hook-up square is loaded and the car is not there: it drove off
        else
            keep[#keep + 1] = l
        end
    end
    local s = A.join(keep)
    if s ~= d.cars then d.cars = s gen:transmitModData() end
    return out
end

--- Client asks to hook or unhook a car: { x,y,z of the wired part, vid, on }.
S.COMMANDS.carLink = function(playerObj, args)
    if type(args) ~= "table" or type(args.vid) ~= "string" then return end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    local sq = x and getSquare(x, y, z)
    if not sq then return end
    local node
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if P.partOf(o) and type(P.data(o).sys) == "string" then node = o break end
    end
    local v = vehicleById(args.vid, true)
    local vsq = v and v:getSquare()
    if not (node and vsq) then return end
    if math.abs(vsq:getX() - x) > A.REACH or math.abs(vsq:getY() - y) > A.REACH then return end
    if playerObj and (math.abs(playerObj:getX() - vsq:getX()) > 4 or math.abs(playerObj:getY() - vsq:getY()) > 4) then return end
    local cx, cy, cz = M.parseNodeKey(P.data(node).sys)
    local gen = cx and P.objectAt(cx, cy, cz, "controller")
    if not gen then return end
    local d = P.data(gen)
    d.cars = A.toggle(d.cars, args.vid, x, y, z, args.on == true)
    gen:transmitModData()
end
