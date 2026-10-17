--[[ DazedPower -- a steam engine's fire, on screen (0.12.0; on the shared DP_MachineFx since 0.13.0).

     Purely cosmetic and only on this machine, like the spinning windmills (DP_WindSpin): nothing is sent, nothing
     is written to ModData, and the server keeps showing the plain sprites clients sync from.

       running  the firebox door open on four flicker frames (the steamfire rows fire1..fire4 of the sheet), the
                chimney smoke climbing a quarter puff a frame, and at night a warm light on the square that grows
                with the engine's load (steamWatts against its rating)
       warming  the door open on banked embers (one frame) and a dim red glow at night: an idle governed engine,
                one raising steam, or one cooling after its fuel ran out
       cold, broken  nothing; the plain sprite

     The tracking, the cull to range and screen, the lights (at most DP_MachineFx.MAX_LIGHTS across every engine
     kind), the pause, the cleanup, the sandbox option (Machine effects) and the two Dazed Core Tick jobs are the
     shared DP_MachineFx's; this file registers the steam engine's looks and light. Everything the 0.12.0 module
     offered still answers here: the steam-only calls below, and the shared state and calls (count, active,
     tracked, lights, scan, frames, consider, reset, onRemoved, restoreAll, ...) read through to DP_MachineFx.
]]

require "DazedPower/DP_Parts"
require "DazedPower/DPM_Model"
require "DazedPower/DP_MachineFx"

DazedPower = DazedPower or {}
local M = DazedPower.MachineFx
DazedPower.SteamFx = DazedPower.SteamFx or {}
local F = DazedPower.SteamFx
setmetatable(F, { __index = M })

F.FRAMES = { "fire1", "fire2", "fire3", "fire4" }
-- The light: radius in squares and colour, from banked embers to a fire under full load.
F.EMBER_LIGHT = { radius = 2, r = 0.45, g = 0.16, b = 0.05 }
F.FIRE_RADIUS = { 3, 7 }     -- no load to full load
F.FIRE_RGB = { 1.0, 0.55, 0.22 }

--- The look for a steam engine's logical state: "fire", "embers" or nil (plain sprite).
function F.mode(state)
    if state == "running" then return "fire" end
    if state == "warming" then return "embers" end
    return nil
end

--- Sprite name for a steam engine of `tier` showing `frame` (a fire frame, "embers", or a plain state), memoised.
function F.spriteName(tier, frame, facing)
    return M.spriteName("steam", tier, frame, facing)
end

--- Which sprite the engine shows for `state` at flame step `step` (any integer; it wraps).
function F.pick(tier, state, facing, step)
    return M.pick("steam", tier, state, facing, step)
end

--- The light for a look: { radius, r, g, b } or nil. A running fire's radius and brightness follow the load:
--  `watts` against the tier's rating (DPM_Model), in three bands so a wavering load does not rebuild the light.
function F.lightFor(mode, tier, watts)
    if mode == "embers" then return F.EMBER_LIGHT end
    if mode ~= "fire" then return nil end
    local MM = DazedPower.More and DazedPower.More.Model
    local rated = (MM and MM.steamSpec and MM.steamSpec(tier).rated) or 900
    return M.loadLight(watts, rated, F.FIRE_RADIUS, F.FIRE_RGB)
end

M.register({
    kind = "steam",
    modes = { running = "fire", warming = "embers" },
    cycle = "fire",
    frames = F.FRAMES,
    still = { embers = "embers" },
    light = function(mode, tier, d) return F.lightFor(mode, tier, d and d.steamWatts) end,
})

return F
