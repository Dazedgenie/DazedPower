--[[ Dazed Power -- keeping the windsock and the weather vane
     up to date.

     The two instruments are Dazed Power parts as far as its menus, pick-up
     gate and ModData carry go (DPM_Parts teaches P.spriteInfo their names),
     but they are never wired and Dazed Power's simulation never ticks them, the
     same way it leaves its solar lamps alone. This file is their whole
     simulation:

       * As one streams in (a chunk loads) or is put down, it is added to a
         list of loaded instruments and set straight away to the wind now.
       * Every ten game minutes, each instrument still standing is set to the
         wind again: the sock's sprite shows the wind's strength and the way
         it blows, the vane's arrow turns to face it, and the vane adds the
         last ten minutes to its record (DPM_Model.vaneRecord).

     The wind is read ONCE per tick for all of them -- it is the same wind
     everywhere in Knox County -- through DPM_Env, the same reading (and the
     same direction calibration) the windmills use.

     Only the time a vane actually spent loaded counts toward its record: a
     vane whose area was unloaded for a week has seen nothing in that week,
     so on its first tick back it is credited one tick's worth, not seven
     days of whatever the wind happens to be doing now.

     Runs where the world is simulated: single player, or the server. On a
     multiplayer client the server's sprite changes and ModData arrive by
     the engine's own sync.
]]

if isClient() then return end

require "DazedPower/DPM_Parts"
require "DazedPower/DPM_Model"
require "DazedPower/DPM_Env"

DazedPower.More = DazedPower.More or {}
DazedPower.More.Instruments = DazedPower.More.Instruments or {}
local I = DazedPower.More.Instruments
local R = DazedPower.More.Parts
local MM = DazedPower.More.Model
local ME = DazedPower.More.Env
local P = DazedPower.Parts

I.TICK_HOURS = 1 / 6                 -- EveryTenMinutes
I.MAX_CREDIT_HOURS = 1               -- a gap longer than this was time unwatched

-- The loaded instruments. Weak keys: an object the engine has let go of (its
-- chunk unloaded) drops out of the list by itself.
I.loaded = I.loaded or setmetatable({}, { __mode = "k" })

local function worldHours()
    local gt = getGameTime and getGameTime()
    return gt and gt:getWorldAgeHours() or 0
end

--- Still standing in the world? (An object lifted or destroyed reports
--  index -1, the same test Dazed Power's own actions use.)
local function standing(obj)
    if not obj or not obj.getSquare or not obj:getSquare() then return false end
    local ok, idx = pcall(function() return obj:getObjectIndex() end)
    return ok and idx ~= nil and idx >= 0
end

--- Set one instrument to the given wind. `record` is false on the first
--  sight of it (load or placement): the sprite is set, and the vane's clock
--  started, but nothing is added to its record yet.
function I.update(obj, kph, windFrom, now, record)
    local info = R.describe(obj)
    if not info or not R.INSTRUMENT[info.kind] then return end
    local sq = obj:getSquare()
    local d = P.data(obj)
    local outside = sq and ME.isOutside(sq)
    local z = sq and sq:getZ() or 0

    if info.kind == "windsock" then
        -- Under a roof there is no wind to fill it: it hangs, wherever it
        -- was last pointing.
        local state, facing = "limp", info.facing
        if outside and kph then
            state = MM.sockState(MM.sockWind(kph, z))
            if state ~= "limp" then facing = MM.sockFacing(windFrom, info.facing) end
        end
        R.setVariant(obj, state, facing)

    elseif info.kind == "vane" then
        -- The arrow needs a breath of wind to swing; in a calm it stays put.
        if outside and kph and kph >= MM.VANE_CALM_KPH and windFrom then
            R.setVariant(obj, "set", MM.vaneFacing(windFrom, info.facing))
        end
        if record and outside and kph then
            local gap = now - (d.vAt or now)
            local credit = (gap > 0 and gap <= I.MAX_CREDIT_HOURS) and gap or I.TICK_HOURS
            MM.vaneRecord(d, windFrom, kph, credit)
        end
        -- Sheltered, it reads nothing, and a vane taken indoors says so in
        -- its menu rather than recording a calm that is not really there.
        d.vAt = now
        if isServer() and obj.transmitModData then obj:transmitModData() end
    end
end

--- Every loaded instrument, set to the wind now.
function I.tick()
    local kph, from = ME.wind()
    local now = worldHours()
    for obj in pairs(I.loaded) do
        if standing(obj) then
            I.update(obj, kph, from, now, true)
        else
            I.loaded[obj] = nil
        end
    end
end

--- A windsock or vane streaming in, or just put down.
function I.onLoad(obj)
    if not obj then return end
    local info = R.describe(obj)
    if not info or not R.INSTRUMENT[info.kind] then return end
    I.loaded[obj] = true
    local kph, from = ME.wind()
    I.update(obj, kph, from, worldHours(), false)
end

local function registerSprites()
    local P = DazedPower.Parts
    for row = 1, #P.ROWS do
        if P.INSTRUMENT[P.ROWS[row].kind] then
            for col = 0, P.COLS - 1 do
                local name = P.TILESET .. "_" .. ((row - 1) * P.COLS + col)
                MapObjects.OnLoadWithSprite(name, I.onLoad, 6)
                MapObjects.OnNewWithSprite(name, I.onLoad, 6)
            end
        end
    end
end

if not I.hooked then
    I.hooked = true
    registerSprites()
    Events.OnGameStart.Add(registerSprites)
    Events.EveryTenMinutes.Add(I.tick)
end

return I
