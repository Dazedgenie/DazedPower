--[[ DazedPower -- turning windmills spin on screen.

     Purely cosmetic and only on this machine: the server keeps showing the plain "turning" sprite, and each
     windmill near a local player walks through its four blade frames (the windspin rows of the sheet). Speed
     follows the wind at the rotor (windMs, sent with the windmill's ModData). Past MAX_MS the blades blur into the
     render's motion-blur sprite; a broken rotor in a breeze rocks on its bearing instead of turning.

     Since 0.14.0 this is a registration on the shared DP_MachineFx (like the engines' effects) instead of a tick of
     its own: the same cull (25 squares and on screen), the pause (the blades hold while single player is paused;
     they used to keep turning), the sandbox switch Machine effects, the cleanup, and no job at all while no machine
     is loaded. The player's own tick box (Dazed Core options page, "spinning blades") still works on top. The look,
     the frames and the speed are the same as before: W.pick and W.fps below are unchanged, and the registered look
     (modeOf, cycles, rate) is checked against them in tools/tests/anim_test.lua.

     A frame saved by a single-player save mid-spin still reads back as a turning windmill (DP_Parts.ALIAS).
]]

require "DazedPower/DP_Parts"
require "DazedPower/DP_MachineFx"
require "DazedCore/DC_Options"

DazedPower = DazedPower or {}
DazedPower.WindSpin = DazedPower.WindSpin or {}
local W = DazedPower.WindSpin
local M = DazedPower.MachineFx
local P = DazedPower.Parts

W.OPTION = "WindSpin"
W.MIN_FPS, W.MAX_FPS = 3, 15    -- blade frames a second at cut-in and at full speed
W.FPS_PER_MS = 1.6              -- frames a second added per m/s above cut-in
W.MAX_MS = 15                   -- wind at the rotor past which the blades blur instead
W.WOBBLE_MS = 2                 -- a broken rotor rocks once the wind passes this
W.ROCK_FPS = 1.6                -- beats a second of a broken rotor's rocking
W.FRAMES = { "spin1", "spin2", "spin3", "spin4" }
W.ROCK = { "broken", "broken", "wobble" }   -- uneven rocking: two beats on the rest, one rocked off it
W.CUT_IN = { makeshift = 3.5, salvaged = 3.0, workshop = 2.5 }

--- The player's tick box on the shared Dazed Core page; on unless unticked.
function W.enabled()
    return DazedCore.Options.on("DazedPower", W.OPTION)
end

--- Blade frames a second for wind of `ms` at the rotor on this tier.
function W.fps(tier, ms, state)
    if state == "broken" then return W.ROCK_FPS end
    local over = math.max(0, (ms or 0) - (W.CUT_IN[tier] or 3))
    return math.min(W.MAX_FPS, W.MIN_FPS + over * W.FPS_PER_MS)
end

--- The look of a windmill in `state` with the synced ModData `d`: "spin" (the blade frames), "blur" (a gale: the
--  plain turning sprite, drawn motion-blurred), "rock" (a broken rotor in a breeze), or nil (its plain sprite).
function W.modeOf(state, tier, d)
    local ms = (d and d.windMs) or 0
    if state == "turning" then return ms >= W.MAX_MS and "blur" or "spin" end
    if state == "broken" and ms >= W.WOBBLE_MS then return "rock" end
    return nil
end

--- How fast a look walks its frames.
function W.rate(mode, tier, d)
    return W.fps(tier, d and d.windMs, mode == "rock" and "broken" or "turning")
end

--- Which windmill sprite the object should show right now, from its stored state and wind. Pure, for tests.
function W.pick(info, d, phase)
    local state = (d and d.state) or info.state
    local facing = (d and d.facing) or info.facing
    return M.pickLook("windmill", info.tier, W.modeOf(state, info.tier, d), facing, phase)
        or M.spriteName("windmill", info.tier, state, facing)
end

M.register({
    kind = "windmill",
    modeOf = W.modeOf,
    cycles = { spin = W.FRAMES, rock = W.ROCK },
    still = { blur = "turning" },
    rate = W.rate,
    enabled = W.enabled,
})

--- Kept for anything that called it: windmills are followed by DP_MachineFx now.
W.consider = M.consider

--- Put every windmill showing a blade frame back on its plain sprite (DP_MachineFx does this when the tick box or
--  Machine effects goes off).
function W.restoreAll()
    for obj, e in pairs(M.tracked) do
        if e.spec.kind == "windmill" then M.restoreOne(obj, e) end
    end
end

local function register()
    DazedCore.Options.tick("DazedPower", W.OPTION, "IGUI_DazedPower_OptWindSpin", true, "IGUI_DazedPower_OptWindSpinTip")
end
register()

return W
