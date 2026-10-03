--[[ DazedPower -- the player's own settings.

     Client-side preferences, kept in the player's own ModOptions.ini through
     the engine's PZAPI.ModOptions page, which is the right store for a HUD
     choice: a sandbox option is world-wide and set by the host, and a player
     on somebody else's server cannot touch it.

     Registered at file load, not on an event: MainOptions builds its Mods
     page when the main screen is constructed (OnMainMenuEnter), and only if
     PZAPI.ModOptions.Data is non-empty at that moment. Vanilla loads
     PZAPI/ModOptions.lua before any mod file, so the table exists here.
     MainOptions reads ModOptions.ini itself before any world is entered, so
     a value is in place before the sidebar exists.

     A tick box only. The keybind widget throws on rebind for any mod that
     ships translations (its rebind handler matches the translated label
     against the raw name), which is why no hotkey is offered.
]]

DazedPower = DazedPower or {}
DazedPower.Options = DazedPower.Options or {}
local O = DazedPower.Options

O.MOD = "DazedPower"
O.SIDEBAR = "SidebarAlmanac"

require "DazedCore/DC_Options"

local function register()
    -- On the shared "Dazed Utilities" page. Applied the moment the player presses Apply.
    DazedCore.Options.tick(O.MOD, O.SIDEBAR, "IGUI_DazedPower_OptSidebar", true, "IGUI_DazedPower_OptSidebarTip",
        function() if DazedPower.Sidebar and DazedPower.Sidebar.refresh then DazedPower.Sidebar.refresh() end end)
end

--- Does this player want the almanac button on the sidebar? True unless the option exists and is unticked.
function O.sidebar()
    return DazedCore.Options.on(O.MOD, O.SIDEBAR)
end

register()

return O
