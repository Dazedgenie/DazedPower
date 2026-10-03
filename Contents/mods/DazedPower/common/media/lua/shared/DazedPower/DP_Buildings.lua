--[[ Dazed Power -- which squares a building is: the core's resolver (DazedCore.Buildings); this keeps the old name. ]]
require "DazedCore/DC_Boot"
require "DazedPower/DP_Reach"
DazedPower = DazedPower or {}
DazedPower.Buildings = DazedCore.Buildings
return DazedPower.Buildings
