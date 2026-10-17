--[[ DazedPower -- the gas engines' effects on screen (0.13.0): wood gas, petrol and propane generators.

     The steam engine's fire (DP_SteamFx) carried over to the other generators, on the same shared DP_MachineFx:
     same range (25 squares) and screen cull, same pause, cleanup and sandbox option (Machine effects), the same
     two Dazed Core Tick jobs, and the same cap of MAX_LIGHTS lights across every kind. Visual only, on this
     computer: nothing is sent or saved.

       wood gas  running  the gasifier's ash door open on four flicker frames (woodgasfire fire1..fire4), its
                          exhaust smoke climbing a quarter puff a frame; at night a warm orange light that widens
                          with the load (genWatts against the grade's rating)
                 warming  the door open on glowing embers (one frame), a dim red glow at night: the gasifier
                          coming up to heat before the engine takes the load
       petrol    running  the engine shaking on its mounts with a thin exhaust puff climbing (petrolrun run1..run3);
                          no light (a petrol engine shows no flame)
       propane   running  a small blue burner flame at the exhaust and a faint heat shimmer, no smoke
                          (propaneflame flame1..flame3); at night a faint blue glow
       off, broken (and anything else)  nothing; the plain sprite
]]

require "DazedPower/DP_Parts"
require "DazedPower/DPM_Model"
require "DazedPower/DP_MachineFx"

DazedPower = DazedPower or {}
local M = DazedPower.MachineFx
DazedPower.GenFx = DazedPower.GenFx or {}
local G = DazedPower.GenFx

G.WOODGAS_FRAMES = { "fire1", "fire2", "fire3", "fire4" }
G.PETROL_FRAMES = { "run1", "run2", "run3" }
G.PROPANE_FRAMES = { "flame1", "flame2", "flame3" }
-- Lights. Wood gas: warm orange like the steam engine's, a smaller pool (the ash door is small).
G.EMBER_LIGHT = { radius = 2, r = 0.45, g = 0.16, b = 0.05 }
G.WOODGAS_RADIUS = { 3, 5 }  -- no load to full load
G.WOODGAS_RGB = { 1.0, 0.55, 0.22 }
-- Propane: a faint blue glow round the burner, whatever the load.
G.PROPANE_LIGHT = { radius = 2, r = 0.12, g = 0.2, b = 0.5, band = "blue" }

local function rated(tier, kind)
    local MM = DazedPower.More and DazedPower.More.Model
    local s = MM and MM.propaneSpec and MM.propaneSpec(tier, kind)
    return (s and s.rated) or 1600
end

--- A wood gas generator's light for a look: embers glow dimly, a running gasifier's pool follows `watts`.
function G.woodgasLight(mode, tier, watts)
    if mode == "embers" then return G.EMBER_LIGHT end
    if mode ~= "fire" then return nil end
    return M.loadLight(watts, rated(tier, "woodgas"), G.WOODGAS_RADIUS, G.WOODGAS_RGB)
end

--- A propane generator's light: the faint blue glow while it runs.
function G.propaneLight(mode)
    if mode == "flame" then return G.PROPANE_LIGHT end
    return nil
end

--- Which sprite a generator of `kind` shows for `state` at frame step `step` (any integer; it wraps).
function G.pick(kind, tier, state, facing, step)
    return M.pick(kind, tier, state, facing, step)
end

M.register({
    kind = "woodgas",
    modes = { running = "fire", warming = "embers" },
    cycle = "fire",
    frames = G.WOODGAS_FRAMES,
    still = { embers = "embers" },
    light = function(mode, tier, d) return G.woodgasLight(mode, tier, d and d.genWatts) end,
})

M.register({
    kind = "petrol",
    modes = { running = "run" },
    cycle = "run",
    frames = G.PETROL_FRAMES,
    light = nil,                 -- no flame, no light
})

M.register({
    kind = "propane",
    modes = { running = "flame" },
    cycle = "flame",
    frames = G.PROPANE_FRAMES,
    light = function(mode) return G.propaneLight(mode) end,
})

return G
