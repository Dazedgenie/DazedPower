--[[ Dazed Power -- the fuel-line hookup with Dazed Utilities: Plumbing.

     Optional. If the Plumbing mod is also loaded, this teaches it three kinds
     of machine (the petrol generator burns PETROL from a gas tank the same way), so a right-click "Fuel line" menu appears on them:

       propane generators   burn PROPANE straight from a propane tank (drawn as
                            fuel is used, even across a long time-skip), then
                            their reservoir, then any hooked-up bottle
       steam boilers        take WATER from a water tank into their boiler tank

     Nothing here is needed without Plumbing: the registration below simply
     finds no DazedPlumb.Links and stops. It is tried at file load and again
     at game start, because either mod may load first; registering twice just
     replaces the entry.
]]

require "DazedPower/DP_Parts"
require "DazedPower/DPM_Model"
require "DazedPower/DPM_Parts"

local P = DazedPower.Parts
local R = DazedPower.More.Parts
local M = DazedPower.More.Model

DazedPower.More.Plumbing = DazedPower.More.Plumbing or {}
local H = DazedPower.More.Plumbing

local function kindOf(obj)
    local info = R.describe(obj)
    return info and info.kind or nil
end

local function transmit(obj)
    if obj and obj.transmitModData then obj:transmitModData() end
end

--- The tank a generator's line points at (master object) and its state, or nil.
local function lineTank(g)
    local L = DazedPlumb and DazedPlumb.Links
    if not (L and g.lineTx) then return nil end
    return (L.tankAt(g.lineTx, g.lineTy, g.lineTz, (g.kind == "petrol") and "gas" or "propane"))
end

--- The line as a fuel source for the model (see DazedPower.More.Model.LineSource):
--  the tank is drawn directly as fuel burns, so a long time-skip drains it
--  exactly as much as the generator used.
H.lineSource = {
    available = function(g)
        local tank = lineTank(g)
        return tank and (DazedPlumb.Parts.data(tank).amount or 0) or 0
    end,
    draw = function(g, kg)
        local tank = lineTank(g)
        if not tank then return 0 end
        local d = DazedPlumb.Parts.data(tank)
        local take = math.min(kg or 0, d.amount or 0)
        if take <= 0 then return 0 end
        DazedPlumb.Model.take(d, take)
        if tank.transmitModData then tank:transmitModData() end
        return take
    end,
}

H.propaneAdapter = {
    id = "dazedpower_propane_generator",
    supplies = "propane",
    label = "ContextMenu_DazedPlumb_FuelLine",
    match = function(obj) return kindOf(obj) == "propane" end,
    -- Nothing is pushed into the reservoir: the tank is drawn directly (above).
    room = function(obj) return 0 end,
    put = function(obj, kg) return 0 end,
    -- Called every minute while the line feeds: points the generator at its tank.
    engage = function(obj, link)
        local d = P.data(obj)
        if d.feedTank ~= true or d.lineTx ~= link.tx or d.lineTy ~= link.ty or d.lineTz ~= link.tz then
            d.feedTank, d.lineTx, d.lineTy, d.lineTz = true, link.tx, link.ty, link.tz
            transmit(obj)
        end
    end,
    release = function(obj)
        local d = P.data(obj)
        d.feedTank, d.lineTx, d.lineTy, d.lineTz = nil, nil, nil, nil
        transmit(obj)
    end,
}

H.petrolAdapter = {
    id = "dazedpower_petrol_generator",
    supplies = "gas",
    label = "ContextMenu_DazedPlumb_FuelLine",
    match = function(obj) return kindOf(obj) == "petrol" end,
    -- Nothing is pushed into the reservoir: the tank is drawn directly (above).
    room = function(obj) return 0 end,
    put = function(obj, kg) return 0 end,
    -- Called every minute while the line feeds: points the generator at its tank.
    engage = function(obj, link)
        local d = P.data(obj)
        if d.feedTank ~= true or d.lineTx ~= link.tx or d.lineTy ~= link.ty or d.lineTz ~= link.tz then
            d.feedTank, d.lineTx, d.lineTy, d.lineTz = true, link.tx, link.ty, link.tz
            transmit(obj)
        end
    end,
    release = function(obj)
        local d = P.data(obj)
        d.feedTank, d.lineTx, d.lineTy, d.lineTz = nil, nil, nil, nil
        transmit(obj)
    end,
}

H.boilerAdapter = {
    id = "dazedpower_steam_boiler",
    supplies = "water",
    label = "ContextMenu_DazedPlumb_FuelLine",
    match = function(obj) return kindOf(obj) == "steam" end,
    room = function(obj)
        local d = P.data(obj)
        local cap = M.steamSpec(d.tier).tank
        return math.max(0, cap - (d.water or 0))
    end,
    put = function(obj, litres)
        local d = P.data(obj)
        local cap = M.steamSpec(d.tier).tank
        local add = math.min(litres, math.max(0, cap - (d.water or 0)))
        if add <= 0 then return 0 end
        d.water = (d.water or 0) + add
        transmit(obj)
        return add
    end,
}

--- Hand both adapters to Plumbing, if it is here. Returns true when it was.
function H.register()
    local L = DazedPlumb and DazedPlumb.Links
    if not (L and L.register) then return false end
    M.LineSource = H.lineSource
    L.register(H.propaneAdapter)
    L.register(H.petrolAdapter)
    L.register(H.boilerAdapter)
    return true
end

H.register()
Events.OnGameStart.Add(H.register)
Events.OnServerStarted.Add(H.register)
