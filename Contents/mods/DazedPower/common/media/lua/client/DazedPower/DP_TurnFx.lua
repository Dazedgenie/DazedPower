--[[ DazedPower -- the turning machines on screen (0.14.0): the water wheel, the zombie treadwheel, the windsock.

     Registrations on the shared DP_MachineFx, like the engines' effects (DP_SteamFx, DP_GenFx) and the windmill's
     blades (DP_WindSpin): the same cull (25 squares of a local player and on screen), pause, cleanup, sandbox switch
     (Machine effects) and the same two Dazed Core Tick jobs, none while no such machine is loaded. Visual only, on
     this computer: nothing is sent or saved, and the server keeps showing the plain sprites.

       water wheel  turning   the wheel drawn sharp, its twelve paddles a third of their pitch on per frame
                              (hydrospin spin1..spin3: three frames loop the wheel's 30 degree symmetry), water
                              tipping off the chute and spraying below; speed with its condition (a worn wheel drags)
       treadwheel   walking   the tied zombie's stride in four poses, the drum's slats a quarter of their pitch back
                              under its feet per frame (treadspin walk1..walk4); faster when it is lured (someone in
                              reach), slower for a crawler
       windsock     half, full  the sock swinging to either side of its plain line, a wave running down it
                              (plain, windsockflap 1, plain, 2), faster in a stronger wind
       still, empty, limp     nothing; the plain sprite
]]

require "DazedPower/DP_Parts"
require "DazedPower/DP_MachineFx"

DazedPower = DazedPower or {}
local M = DazedPower.MachineFx
DazedPower.TurnFx = DazedPower.TurnFx or {}
local F = DazedPower.TurnFx

F.HYDRO_FRAMES = { "spin1", "spin2", "spin3" }
F.TREAD_FRAMES = { "walk1", "walk2", "walk3", "walk4" }
F.SOCK_HALF = { "half", "half1", "half", "half2" }
F.SOCK_FULL = { "full", "full1", "full", "full2" }

F.HYDRO_FPS = 8              -- a sound wheel: 80 degrees a second (about 13 turns a minute)
F.HYDRO_WORN = 0.5           -- of that at condition 0
F.TREAD_FPS = 4              -- one stride (two steps) a second
F.TREAD_LURED = 1.5          -- times that when the zombie is lured (DPM_Model.TREAD_LURED_W)
F.TREAD_CRAWLER = 0.5        -- times that for a crawler (its watts are under CRAWLER_BELOW)
F.CRAWLER_BELOW = 60
F.SOCK_FPS = { half = 3, full = 6 }

--- Paddle frames a second for a water wheel at `condition` (0..100, nil as new).
function F.hydroRate(condition)
    local c = math.max(0, math.min(100, tonumber(condition) or 100)) / 100
    return F.HYDRO_FPS * (F.HYDRO_WORN + (1 - F.HYDRO_WORN) * c)
end

--- Stride frames a second for a treadwheel from its synced ModData: lured faster, a crawler slower. A wheel worn
--  past use (0 W, the slats slipping) still turns at the walking pace: the zombie keeps walking.
function F.treadRate(d)
    local fps = F.TREAD_FPS
    if d and d.treadLured then return fps * F.TREAD_LURED end
    local w = d and tonumber(d.treadWatts)
    if w and w > 0 and w < F.CRAWLER_BELOW then return fps * F.TREAD_CRAWLER end
    return fps
end

M.register({
    kind = "hydro",
    modes = { turning = "spin" },
    cycles = { spin = F.HYDRO_FRAMES },
    rate = function(mode, tier, d) return F.hydroRate(d and d.condition) end,
})

M.register({
    kind = "treadwheel",
    modes = { walking = "walk" },
    cycles = { walk = F.TREAD_FRAMES },
    rate = function(mode, tier, d) return F.treadRate(d) end,
})

M.register({
    kind = "windsock",
    modes = { half = "half", full = "full" },
    cycles = { half = F.SOCK_HALF, full = F.SOCK_FULL },
    rate = function(mode) return F.SOCK_FPS[mode] or 3 end,
})

return F
