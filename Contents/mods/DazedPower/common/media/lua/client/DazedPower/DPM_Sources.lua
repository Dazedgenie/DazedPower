--[[ Dazed Power -- the controller's power sources.
     The analog charge board lists them itself now (DP_BoardLayout's SOURCES IN), so this file only keeps the old
     module name for anything that still asks for it.
]]

require "DazedPower/DP_BoardLayout"

DazedPower.More = DazedPower.More or {}
DazedPower.More.Sources = DazedPower.More.Sources or {}
local X = DazedPower.More.Sources

--- The rows the board lists, biggest first, and every source's total.
function X.rows(s)
    return DazedPower.BoardLayout.sources(s), (s and s.gen) or 0
end

return X
