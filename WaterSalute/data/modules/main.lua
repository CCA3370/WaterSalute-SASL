--------------------------------------------------------------------------------
-- WaterSalute SASL3 Plugin for X-Plane 12
-- Root main.lua - Project entry point
--
-- This is the root component definition file for the SASL project.
-- According to SASL documentation, main.lua must be located directly in the
-- modules folder with a fixed name and location.
--------------------------------------------------------------------------------

-- Size of the root component (not used for global/3D-only plugins)
size = { 0, 0 }

-- Define the component hierarchy
-- The watersalute component script will be searched in the Custom Module folder
-- The empty braces {} indicate no additional properties are passed to the component
components = {
    watersalute {}
}
