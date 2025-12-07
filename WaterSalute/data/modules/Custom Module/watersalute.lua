--------------------------------------------------------------------------------
-- WaterSalute SASL3 Plugin Component
-- Entry point for the WaterSalute module
--------------------------------------------------------------------------------

-- Size of the component (not used for 3D-only plugins)
size = { 0, 0 }

-- Include sub-modules in dependency order
-- Constants and utilities must be loaded first as other modules depend on them
include("constants.lua")
include("utils.lua")
include("firetruck.lua")
include("roadnetwork.lua")
include("pathplanning.lua")
include("raindrop.lua")
-- main_impl.lua is loaded last as it depends on all the above modules
include("main_impl.lua")
