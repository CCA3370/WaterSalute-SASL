--------------------------------------------------------------------------------
-- WaterSalute SASL3 Plugin for X-Plane 12
-- Simulates a water salute ceremony with fire trucks
--
-- Features:
-- - Menu control (Plugins -> Water Salute -> Start/Stop)
-- - Aircraft ground and speed validation
-- - Fire truck positioning based on aircraft wingspan
-- - 8x8 fire truck physics with Ackermann steering model
-- - Water particle effects
-- - Road network path planning from apt.dat
-- - Raindrop effect on windshield when passing through water gate
--------------------------------------------------------------------------------

-- Enable 3D rendering for this project
set3DRendering(true)

-- Add search paths for our module
addSearchPath(moduleDirectory .. "/modules/WaterSalute/")
addSearchResourcesPath(moduleDirectory .. "/modules/WaterSalute/")
addSearchResourcesPath(moduleDirectory .. "/modules/WaterSalute/resources/")

-- Load the WaterSalute component
components = {
    watersalute {}
}
