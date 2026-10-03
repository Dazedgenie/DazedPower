--[[ Dazed Power -- picking up, turning and placing the added parts.

     Dazed Power's pick-up and rotate gates all ask G.mayTake, through the
     table (DP_Place and DP_Context both), so one wrapper covers every path.
     A lit or still-hot boiler may not be lifted or turned -- vanilla's rule
     for a lit barbecue -- and says why.

     Carried state (a pedal generator's gear set, a boiler's fuel and water,
     a weather vane's record of the wind)
     rides along in the item's copy of the object's ModData, which Dazed Power's
     own stow/seed already carries for every part; G.seed is wrapped only to
     make sure a placed part picks up our defaults.
]]

require "DazedPower/DP_Place"
require "DazedPower/DPM_Parts"
require "DazedCore/DC_Boot"
DazedCore.Heavy.register("Base.Dazed")     -- generators, engines and windmills over 30 kg come apart into parts

local G = DazedPower.Place
local P = DazedPower.Parts
local R = DazedPower.More.Parts
if not G then return end

DazedPower.More = DazedPower.More or {}
local H = DazedPower.More

if not H.placeWrapped then
    H.placeWrapped = true

    -- The refusal note, the way Dazed Power gives its own (DP_Place's refuse):
    -- rate-limited per player, because the gate runs every frame the cursor
    -- hovers; and on a dedicated server sent as the KEY through Dazed Power's
    -- own "note" command, which its client side translates -- a server never
    -- loads translations, so getText there would hand back the raw key.
    local function note(character, key) DazedCore.Note.limited(character, key) end

    if G.mayTake then
        local mayTake0 = G.mayTake
        function G.mayTake(character, square, object, quiet)
            if object and R.hotBoiler(object) then
                if not quiet and character then note(character, "IGUI_DazedPower_BoilerHot") end
                return false
            end
            if object and R.runningGen(object) then
                if not quiet and character then note(character, "IGUI_DazedPower_GasRunning") end
                return false
            end
            return mayTake0(character, square, object, quiet)
        end
    end

    -- Lifting a propane generator unhooks its tanks first and stands them on
    -- its square, the way Dazed Power empties a battery rack it lifts (G.stow,
    -- G.giveBackCell). A rotation is a lift-and-place: it keeps them.
    if G.stow then
        local stow0 = G.stow
        function G.stow(obj, square, rotating)
            stow0(obj, square, rotating)
            local mine = obj and R.describe(obj)
            if mine and mine.kind == "propane" and not rotating and square then
                local d = P.data(obj)
                for p = 1, 2 do
                    local t = d["t" .. p .. "Type"]
                    if t then
                        local item = R.tankItem(t, d["t" .. p .. "Fill"], d["t" .. p .. "Cond"])
                        if item then square:AddWorldInventoryItem(item, 0.5, 0.5, 0.0) end
                        d["t" .. p .. "Type"], d["t" .. p .. "Fill"], d["t" .. p .. "Cond"] = nil, nil, nil
                    end
                end
            end
        end
    end

    if G.seed then
        local seed0 = G.seed
        function G.seed(obj, item, info)
            seed0(obj, item, info)
            local mine = obj and R.describe(obj)
            if not mine then
                -- Dazed Power's own solar array: only the amplifier rides along.
                local info = obj and P.describe(obj)
                if info and info.kind == "array" then
                    local src = item and item.getModData and item:getModData() and item:getModData().dazedpower
                    if src and src.amp == true then P.data(obj).amp = true end
                end
            end
            if mine then
                local d = P.data(obj)
                local src = item and item.getModData and item:getModData() and item:getModData().dazedpower
                if src then
                    -- An installed amplifier stays bolted on through a lift
                    -- or a turn; a flat boolean, so Dazed Power carried it.
                    if src.amp == true and R.canAmplify(mine) then d.amp = true end
                    if mine.kind == "pedal" and type(src.gear) == "string" then d.gear = src.gear end
                    if mine.kind == "steam" then
                        -- It went into a bag cold (a hot one cannot be lifted),
                        -- so it comes out unlit, whatever was in it.
                        d.fuel, d.water = src.fuel or d.fuel, src.water or d.water
                        d.lit, d.heat = false, 0
                    end
                    if mine.kind == "propane" or mine.kind == "petrol" then
                        -- The reservoir's gas and the auto-start level come
                        -- with it, and it never comes down running. A real
                        -- pick-up arrives with its ports empty (G.stow stood
                        -- the tanks on the floor before the item was made); a
                        -- ROTATION keeps them, and keeps its switch setting.
                        d.lpg = tonumber(src.lpg) or d.lpg
                        d.feedTank, d.lineTx, d.lineTy, d.lineTz = nil, nil, nil, nil   -- a line is cut by a lift
                        d.startPct = tonumber(src.startPct) or d.startPct
                        local turned = type(src.sys) == "string" and src.sys ~= ""
                        d.mode = (turned and src.mode) or "off"
                        d.running = false
                        for _, f in ipairs({ "t1Type", "t1Fill", "t1Cond", "t2Type", "t2Fill", "t2Cond" }) do
                            d[f] = src[f]
                        end
                    end
                    if mine.kind == "vane" then
                        -- The vane's record moves with it (plain numbers, see
                        -- DPM_Model.vaneRecord). Not its clock: the time it
                        -- spent in a bag was time unwatched.
                        for k, v in pairs(src) do
                            if type(v) == "number" and (k == "vCalm" or k == "vHours" or k == "vKph"
                                    or string.match(k, "^v[te]_%u+$")) then
                                d[k] = v
                            end
                        end
                        d.vAt = nil
                    end
                end
            end
        end
    end
end
