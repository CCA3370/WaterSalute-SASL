--------------------------------------------------------------------------------
-- WaterSalute SASL3 Plugin Component
-- Entry point for the WaterSalute module
--------------------------------------------------------------------------------

-- Size of the component (not used for 3D-only plugins)
size = { 0, 0 }

-- Include sub-modules
include("constants.lua")
include("utils.lua")
include("firetruck.lua")
include("roadnetwork.lua")
include("pathplanning.lua")
include("raindrop.lua")
include("main.lua")
