--[[ DazedPower -- the electric fence's and the room cooler's menu rows, and the fence's zap on a client.

     The rows only read: the state the server last wrote (on or off, and why), the fence's zaps today
     and the containers the cooler keeps cold. A zap in multiplayer arrives as `fenceZap` and is applied
     by the client that owns each zombie. ]]

require "DazedPower/DP_Parts"
require "DazedPower/DP_Appliances"

DazedPower.ApplianceMenu = DazedPower.ApplianceMenu or {}
local AM = DazedPower.ApplianceMenu
local A = DazedPower.Appliances
local P = DazedPower.Parts

local function today()
    local E = DazedPower.Env
    return math.floor(((E and E.worldHours and E.worldHours()) or 0) / 24)
end

--- The state line: On, or Off and why. Read fresh from the system, as the server judges it.
function AM.stateText(obj, kind)
    local live, why = A.status(obj, kind)
    if kind == "cooler" and live and A.roomOf(obj) == nil then live, why = false, "IGUI_DazedPower_CoolerNoRoom" end
    if live then return getText("ContextMenu_DazedPower_ApplOn") end
    return P.txt("ContextMenu_DazedPower_ApplOff", getText(why or "IGUI_DazedPower_ApplLoose"))
end

local function infoRow(menu, text)
    local o = menu:addOption(text, nil, nil)
    o.notAvailable = true
    return o
end

--- The fence's rows: its state and today's zaps.
function AM.fenceMenu(menu, obj)
    infoRow(menu, AM.stateText(obj, "fence"))
    infoRow(menu, P.txt("ContextMenu_DazedPower_FenceZaps", A.zapsToday(P.data(obj), today())))
end

--- The cooler's rows: its state and how many containers it keeps cold, or that it has no room to cool.
function AM.coolerMenu(menu, obj)
    infoRow(menu, AM.stateText(obj, "cooler"))
    if A.roomOf(obj) == nil then
        infoRow(menu, getText("ContextMenu_DazedPower_CoolerNoRoom"))
    else
        infoRow(menu, P.txt("ContextMenu_DazedPower_CoolerCount", P.data(obj).cooled or 0))
    end
end

--------------------------------------------------------------- the zap, multiplayer

--- Apply a server's zap to the zombies this client owns near the fence; everyone hears it.
function AM.onZap(args)
    if type(args) ~= "table" or type(args.ids) ~= "table" then return end
    local want = {}
    for _, id in pairs(args.ids) do want[tonumber(id) or -1] = true end
    for dx = -1, 1 do
        for dy = -1, 1 do
            local s = getSquare((tonumber(args.x) or 0) + dx, (tonumber(args.y) or 0) + dy, tonumber(args.z) or 0)
            local mov = s and s:getMovingObjects()
            for i = 0, (mov and mov:size() or 0) - 1 do
                local z = mov:get(i)
                if z and instanceof(z, "IsoZombie") and want[P.try(z, "getOnlineID") or -2] then
                    if P.try(z, "isRemoteZombie") then
                        P.try(z, "playSound", A.ZAP_SOUND)
                    else
                        A.applyZap(z, args.dmg == true)
                    end
                end
            end
        end
    end
end

local function onServerCommand(module, command, args)
    if module == "DazedPower" and command == "fenceZap" then AM.onZap(args) end
end
if Events.OnServerCommand then Events.OnServerCommand.Add(onServerCommand) end

return AM
