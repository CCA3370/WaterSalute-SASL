--------------------------------------------------------------------------------
-- WaterSalute SASL3 Plugin for X-Plane 12
-- Main Module - Water Salute Ceremony Simulation
--
-- This plugin simulates a water salute ceremony where two fire trucks
-- approach the aircraft and spray water arches over it.
--
-- Features:
-- - Menu system with Start/Stop controls
-- - Aircraft ground and speed validation
-- - Fire truck positioning based on aircraft wingspan
-- - Particle-based water effects
-- - Road network path planning from apt.dat
-- - Raindrop effect on windshield when passing through water gate
--
-- Copyright (c) 2024
--------------------------------------------------------------------------------

-- Define the project name
project_name = "WaterSalute"
project_version = "1.0.0"

--------------------------------------------------------------------------------
-- Global Plugin State
--------------------------------------------------------------------------------

pluginState = STATE_IDLE
menuId = nil
menuStartItem = nil
menuStopItem = nil

-- Fire truck and water drop objects
truckObjectId = nil
waterDropObjectId = nil

-- Datarefs from X-Plane
drOnGround = nil
drGroundSpeed = nil
drLocalX = nil
drLocalY = nil
drLocalZ = nil
drHeading = nil
drWingspan = nil
drLatitude = nil
drLongitude = nil

-- Custom datarefs published by this plugin
customDatarefs = {}

-- Debug timer
debugLogTimer = 0.0

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function onModuleInit()
    debugLog("========================================")
    debugLog("WaterSalute plugin starting...")
    debugLog("========================================")
    
    -- Initialize random number generator
    math.randomseed(os.time())
    
    -- Initialize datarefs
    drOnGround = globalPropertyi("sim/flightmodel/failures/onground_any")
    drGroundSpeed = globalPropertyf("sim/flightmodel/position/groundspeed")
    drLocalX = globalPropertyd("sim/flightmodel/position/local_x")
    drLocalY = globalPropertyd("sim/flightmodel/position/local_y")
    drLocalZ = globalPropertyd("sim/flightmodel/position/local_z")
    drHeading = globalPropertyf("sim/flightmodel/position/psi")
    drLatitude = globalPropertyd("sim/flightmodel/position/latitude")
    drLongitude = globalPropertyd("sim/flightmodel/position/longitude")
    
    drWingspan = globalPropertyf("sim/aircraft/view/acf_semi_len_m")
    if not drWingspan then
        drWingspan = globalPropertyf("sim/aircraft/overflow/acf_span")
    end
    
    -- Create menu
    createPluginMenu()
    
    -- Register custom datarefs
    registerCustomDatarefs()
    
    -- Load fire truck model
    loadFireTruckModel()
    
    -- Load water drop model
    loadWaterDropModel()
    
    -- Initialize raindrop effect system
    initializeRaindropEffect()
    
    -- Initialize trucks
    leftTruck = createFireTruck()
    rightTruck = createFireTruck()
    
    debugLog("WaterSalute plugin started successfully")
end

function onModuleShutdown()
    debugLog("WaterSalute plugin stopping...")
    
    -- Cleanup raindrop effect
    cleanupRaindropEffect()
    
    -- Cleanup trucks
    if leftTruck then cleanupTruck(leftTruck) end
    if rightTruck then cleanupTruck(rightTruck) end
    
    -- Unload models
    if truckObjectId then
        unloadObject(truckObjectId)
        truckObjectId = nil
    end
    if waterDropObjectId then
        unloadObject(waterDropObjectId)
        waterDropObjectId = nil
    end
    
    -- Unregister custom datarefs
    unregisterCustomDatarefs()
    
    debugLog("WaterSalute plugin stopped")
end

--------------------------------------------------------------------------------
-- Menu System
--------------------------------------------------------------------------------

function createPluginMenu()
    -- Create menu under Plugins menu
    menuId = sasl.appendMenuItem(PLUGINS_MENU_ID, "Water Salute")
    local subMenu = sasl.createMenu("Water Salute", PLUGINS_MENU_ID, menuId)
    
    menuStartItem = sasl.appendMenuItem(subMenu, "Start Water Salute", onMenuStart)
    menuStopItem = sasl.appendMenuItem(subMenu, "Stop Water Salute", onMenuStop)
    
    updateMenuState()
end

function updateMenuState()
    if menuId then
        sasl.enableMenuItem(menuId, menuStartItem, pluginState == STATE_IDLE and 1 or 0)
        sasl.enableMenuItem(menuId, menuStopItem, pluginState ~= STATE_IDLE and 1 or 0)
    end
end

function onMenuStart()
    startWaterSalute()
end

function onMenuStop()
    stopWaterSalute()
end

--------------------------------------------------------------------------------
-- Resource Loading
--------------------------------------------------------------------------------

function loadFireTruckModel()
    local objPath = getProjectPath() .. "/resources/firetruck.obj"
    truckObjectId = loadObject(objPath)
    
    if truckObjectId then
        debugLog("Fire truck model loaded successfully")
    else
        debugLog("WARNING: Failed to load fire truck model from " .. objPath)
        debugLog("Fire trucks will not be visible")
    end
end

function loadWaterDropModel()
    local objPath = getProjectPath() .. "/resources/waterdrop.obj"
    waterDropObjectId = loadObject(objPath)
    
    if waterDropObjectId then
        debugLog("Water drop model loaded successfully")
    else
        debugLog("WARNING: Failed to load water drop model from " .. objPath)
        debugLog("Water particles will not be visible")
    end
end

--------------------------------------------------------------------------------
-- Custom Datarefs
--------------------------------------------------------------------------------

function registerCustomDatarefs()
    debugLog("Registering custom datarefs...")
    
    -- Front steering angle (float array)
    customDatarefs.frontSteeringAngle = createGlobalPropertyfa("watersalute/truck/front_steering_angle", {0, 0})
    
    -- Rear steering angle (float array)
    customDatarefs.rearSteeringAngle = createGlobalPropertyfa("watersalute/truck/rear_steering_angle", {0, 0})
    
    -- Wheel rotation angle (float array, read-only)
    customDatarefs.wheelRotationAngle = createGlobalPropertyfa("watersalute/truck/wheel_rotation_angle", {0, 0}, false, false, true)
    
    -- Cannon pitch (float array)
    customDatarefs.cannonPitch = createGlobalPropertyfa("watersalute/truck/cannon_pitch", {DEFAULT_CANNON_PITCH, DEFAULT_CANNON_PITCH})
    
    -- Cannon yaw (float array)
    customDatarefs.cannonYaw = createGlobalPropertyfa("watersalute/truck/cannon_yaw", {0, 0})
    
    -- Speed (float array, read-only)
    customDatarefs.speed = createGlobalPropertyfa("watersalute/truck/speed", {0, 0}, false, false, true)
    
    debugLog("Custom datarefs registered")
end

function unregisterCustomDatarefs()
    debugLog("Unregistering custom datarefs...")
    -- SASL handles dataref cleanup automatically
    debugLog("Custom datarefs unregistered")
end

function updateCustomDatarefs()
    if not leftTruck or not rightTruck then return end
    
    -- Update readable datarefs
    set(customDatarefs.wheelRotationAngle, {leftTruck.wheelRotationAngle, rightTruck.wheelRotationAngle})
    set(customDatarefs.speed, {leftTruck.speed, rightTruck.speed})
    
    -- Sync writable datarefs to trucks (with mirroring)
    local frontSteering = get(customDatarefs.frontSteeringAngle)
    leftTruck.frontSteeringAngle = clampSteeringAngle(frontSteering[1])
    rightTruck.frontSteeringAngle = clampSteeringAngle(frontSteering[2])
    leftTruck.rearSteeringAngle = calculateRearSteeringAngle(leftTruck.frontSteeringAngle)
    rightTruck.rearSteeringAngle = calculateRearSteeringAngle(rightTruck.frontSteeringAngle)
    
    local cannonPitch = get(customDatarefs.cannonPitch)
    leftTruck.cannonPitch = clamp(cannonPitch[1], MIN_CANNON_PITCH, MAX_CANNON_PITCH)
    rightTruck.cannonPitch = clamp(cannonPitch[2], MIN_CANNON_PITCH, MAX_CANNON_PITCH)
    
    local cannonYaw = get(customDatarefs.cannonYaw)
    leftTruck.cannonYaw = normalizeAngle180(cannonYaw[1])
    rightTruck.cannonYaw = normalizeAngle180(cannonYaw[2])
end

--------------------------------------------------------------------------------
-- Start/Stop Water Salute
--------------------------------------------------------------------------------

function startWaterSalute()
    debugLog("========================================")
    debugLog("StartWaterSalute called")
    debugLog("========================================")
    
    if pluginState ~= STATE_IDLE then
        debugLog("Cannot start - not in idle state (current: " .. getStateName(pluginState) .. ")")
        return
    end
    
    -- Check if aircraft is on ground
    local onGround = 0
    if drOnGround then
        onGround = get(drOnGround)
    end
    
    if onGround == 0 then
        debugLog("Cannot start - aircraft not on ground")
        return
    end
    
    -- Check ground speed
    local groundSpeed = 0.0
    if drGroundSpeed then
        groundSpeed = get(drGroundSpeed)
    end
    
    local groundSpeedKnots = groundSpeed / KNOTS_TO_MS
    
    if groundSpeedKnots > MAX_GROUND_SPEED_KNOTS then
        debugLog("Cannot start - ground speed too high: " .. string.format("%.1f", groundSpeedKnots) .. " knots")
        return
    end
    
    -- Get aircraft position and heading
    local acX = drLocalX and get(drLocalX) or 0.0
    local acY = drLocalY and get(drLocalY) or 0.0
    local acZ = drLocalZ and get(drLocalZ) or 0.0
    local acHeading = drHeading and get(drHeading) or 0.0
    
    -- Get wingspan
    local wingspan = DEFAULT_WINGSPAN_METERS
    if drWingspan then
        local rawValue = get(drWingspan)
        if rawValue >= MIN_SEMISPAN_METERS and rawValue <= MAX_SEMISPAN_METERS then
            wingspan = rawValue * 2.0
        else
            local wingspanMeters = rawValue * FEET_TO_METERS
            if wingspanMeters >= MIN_WINGSPAN_METERS and wingspanMeters <= MAX_WINGSPAN_METERS then
                wingspan = wingspanMeters
            elseif rawValue >= MIN_WINGSPAN_METERS and rawValue <= MAX_WINGSPAN_METERS then
                wingspan = rawValue
            end
        end
    end
    
    debugLog("Aircraft position: (" .. string.format("%.2f, %.2f, %.2f", acX, acY, acZ) .. ")")
    debugLog("Aircraft heading: " .. string.format("%.1f", acHeading) .. " degrees, wingspan: " .. string.format("%.1f", wingspan) .. " meters")
    
    -- Try to load road network
    local acLat = 0.0
    local acLon = 0.0
    if drLatitude and drLongitude then
        acLat = get(drLatitude)
        acLon = get(drLongitude)
        debugLog("Aircraft lat/lon: (" .. string.format("%.6f, %.6f", acLat, acLon) .. ")")
    end
    
    local roadNetworkLoaded = loadAptDat(acLat, acLon)
    if roadNetworkLoaded then
        debugLog("Road network loaded successfully for airport " .. roadNetwork.airportId)
    else
        debugLog("Road network not available, using direct approach")
    end
    
    -- Calculate truck spacing
    local truckSpacing = (wingspan / 2.0) + (TRUCK_EXTRA_SPACING / 2.0)
    
    local headingRad = acHeading * DEG_TO_RAD
    local forwardX = math.sin(headingRad)
    local forwardZ = -math.cos(headingRad)
    local rightX = math.cos(headingRad)
    local rightZ = math.sin(headingRad)
    
    -- Calculate positions
    local startDistance = TRUCK_SPAWN_DISTANCE
    local startX = acX + forwardX * startDistance
    local startZ = acZ + forwardZ * startDistance
    
    local targetX = acX + forwardX * TRUCK_STOP_DISTANCE
    local targetZ = acZ + forwardZ * TRUCK_STOP_DISTANCE
    
    -- Initialize left truck
    initializeTruck(leftTruck)
    leftTruck.x = startX - rightX * truckSpacing
    leftTruck.z = startZ - rightZ * truckSpacing
    leftTruck.y = getTerrainHeight(leftTruck.x, leftTruck.z)
    leftTruck.heading = acHeading + 180.0
    leftTruck.targetX = targetX - rightX * truckSpacing
    leftTruck.targetZ = targetZ - rightZ * truckSpacing
    leftTruck.targetHeading = acHeading + 90.0
    leftTruck.nozzleOffsetY = 3.5
    leftTruck.nozzleOffsetZ = 2.0
    
    -- Initialize right truck
    initializeTruck(rightTruck)
    rightTruck.x = startX + rightX * truckSpacing
    rightTruck.z = startZ + rightZ * truckSpacing
    rightTruck.y = getTerrainHeight(rightTruck.x, rightTruck.z)
    rightTruck.heading = acHeading + 180.0
    rightTruck.targetX = targetX + rightX * truckSpacing
    rightTruck.targetZ = targetZ + rightZ * truckSpacing
    rightTruck.targetHeading = acHeading - 90.0
    rightTruck.nozzleOffsetY = 3.5
    rightTruck.nozzleOffsetZ = 2.0
    
    -- Plan routes if road network available
    if roadNetworkLoaded then
        local leftSpawnNode = findNearestNode(leftTruck.x, leftTruck.z, true)
        local rightSpawnNode = findNearestNode(rightTruck.x, rightTruck.z, true)
        
        if leftSpawnNode then
            local node = roadNetwork.nodes[leftSpawnNode]
            leftTruck.x = node.x
            leftTruck.z = node.z
            leftTruck.y = getTerrainHeight(node.x, node.z)
        end
        
        if rightSpawnNode then
            local node = roadNetwork.nodes[rightSpawnNode]
            rightTruck.x = node.x
            rightTruck.z = node.z
            rightTruck.y = getTerrainHeight(node.x, node.z)
        end
        
        leftTruck.route = planRouteToTarget(leftTruck.x, leftTruck.z, 
                                             leftTruck.targetX, leftTruck.targetZ,
                                             leftTruck.targetHeading)
        leftTruck.useRoadNetwork = leftTruck.route and leftTruck.route.isValid
        
        rightTruck.route = planRouteToTarget(rightTruck.x, rightTruck.z,
                                              rightTruck.targetX, rightTruck.targetZ,
                                              rightTruck.targetHeading)
        rightTruck.useRoadNetwork = rightTruck.route and rightTruck.route.isValid
        
        if leftTruck.route and leftTruck.route.isValid and #leftTruck.route.waypoints > 1 then
            leftTruck.heading = leftTruck.route.waypoints[1].targetHeading
        end
        if rightTruck.route and rightTruck.route.isValid and #rightTruck.route.waypoints > 1 then
            rightTruck.heading = rightTruck.route.waypoints[1].targetHeading
        end
    end
    
    -- Create truck instances
    if truckObjectId then
        leftTruck.objectId = truckObjectId
        leftTruck.instance = createInstance(truckObjectId, {})
        if leftTruck.instance then
            setInstancePosition(leftTruck.instance, leftTruck.x, leftTruck.y, leftTruck.z, 0, leftTruck.heading, 0, {})
        end
        
        rightTruck.objectId = truckObjectId
        rightTruck.instance = createInstance(truckObjectId, {})
        if rightTruck.instance then
            setInstancePosition(rightTruck.instance, rightTruck.x, rightTruck.y, rightTruck.z, 0, rightTruck.heading, 0, {})
        end
    end
    
    pluginState = STATE_TRUCKS_APPROACHING
    updateMenuState()
    
    debugLog("State changed to: " .. getStateName(pluginState))
    debugLog("Water salute started - trucks approaching")
end

function stopWaterSalute()
    debugLog("StopWaterSalute called")
    
    if pluginState == STATE_IDLE then
        debugLog("Already stopped")
        return
    end
    
    if pluginState == STATE_TRUCKS_LEAVING then
        debugLog("Trucks already leaving")
        return
    end
    
    -- Set trucks to leave
    leftTruck.isTurningBeforeLeave = true
    leftTruck.leaveHeading = normalizeAngle360(leftTruck.heading - 45.0)
    
    rightTruck.isTurningBeforeLeave = true
    rightTruck.leaveHeading = normalizeAngle360(rightTruck.heading + 45.0)
    
    pluginState = STATE_TRUCKS_LEAVING
    updateMenuState()
    
    debugLog("State changed to: " .. getStateName(pluginState))
    debugLog("Water salute ending")
end

--------------------------------------------------------------------------------
-- Main Update Loop
--------------------------------------------------------------------------------

function update()
    local dt = getTimeDelta()
    if dt > 0.1 then dt = 0.1 end  -- Cap delta time
    
    debugLogTimer = debugLogTimer + dt
    
    if pluginState == STATE_IDLE then
        return
    end
    
    -- Get aircraft position for raindrop effect detection
    local acX = drLocalX and get(drLocalX) or 0.0
    local acY = drLocalY and get(drLocalY) or 0.0
    local acZ = drLocalZ and get(drLocalZ) or 0.0
    
    -- Update custom datarefs
    updateCustomDatarefs()
    
    if pluginState == STATE_TRUCKS_APPROACHING or pluginState == STATE_TRUCKS_POSITIONING then
        updateTrucks(dt)
    elseif pluginState == STATE_WATER_SPRAYING then
        local currentTime = os.clock()
        updateTruckParticles(leftTruck, dt, waterDropObjectId, currentTime)
        updateTruckParticles(rightTruck, dt, waterDropObjectId, currentTime)
        updateRaindropEffect(dt, acX, acY, acZ, pluginState)
    elseif pluginState == STATE_TRUCKS_LEAVING then
        updateTrucks(dt)
        updateRaindropEffect(dt, acX, acY, acZ, pluginState)
    end
end

function updateTrucks(dt)
    if pluginState == STATE_TRUCKS_APPROACHING or pluginState == STATE_TRUCKS_POSITIONING then
        local allPositioned = true
        
        updateTruckPosition(leftTruck, dt)
        updateTruckPosition(rightTruck, dt)
        
        if not leftTruck.positioned then allPositioned = false end
        if not rightTruck.positioned then allPositioned = false end
        
        if allPositioned and leftTruck.positioned and rightTruck.positioned then
            pluginState = STATE_WATER_SPRAYING
            debugLog("State changed to: " .. getStateName(pluginState))
        end
    elseif pluginState == STATE_TRUCKS_LEAVING then
        local leftDone = updateTruckLeaving(leftTruck, dt)
        local rightDone = updateTruckLeaving(rightTruck, dt)
        
        if leftDone and rightDone then
            cleanupTruck(leftTruck)
            cleanupTruck(rightTruck)
            pluginState = STATE_IDLE
            updateMenuState()
            debugLog("State changed to: " .. getStateName(pluginState))
        end
    end
end

function updateTruckPosition(truck, dt)
    if truck.positioned then
        truck.targetSpeed = 0.0
        truck.speed = updateSpeedSmooth(truck.speed, truck.targetSpeed, dt)
        truck.frontSteeringAngle = 0.0
        truck.rearSteeringAngle = 0.0
        return
    end
    
    -- Use road network path following if available
    if truck.useRoadNetwork and truck.route and truck.route.isValid and not truck.route.isCompleted then
        updateTruckFollowingPath(truck, dt)
        if truck.route.isCompleted then
            truck.positioned = true
        end
        return
    end
    
    -- Fallback: Direct approach
    local dx = truck.targetX - truck.x
    local dz = truck.targetZ - truck.z
    local distance = math.sqrt(dx * dx + dz * dz)
    
    if distance > 2.0 then
        local dirX = dx / distance
        local dirZ = dz / distance
        local desiredHeading = math.atan2(dirX, -dirZ) * RAD_TO_DEG
        
        local headingDiff = normalizeAngle180(desiredHeading - truck.heading)
        
        truck.frontSteeringAngle = clampSteeringAngle(headingDiff)
        truck.rearSteeringAngle = calculateRearSteeringAngle(truck.frontSteeringAngle)
        
        if distance < TRUCK_SLOWDOWN_DISTANCE then
            truck.targetSpeed = TRUCK_APPROACH_SPEED * (distance / TRUCK_SLOWDOWN_DISTANCE)
            if truck.targetSpeed < TRUCK_TURN_IN_PLACE_SPEED then
                truck.targetSpeed = TRUCK_TURN_IN_PLACE_SPEED
            end
        else
            truck.targetSpeed = TRUCK_APPROACH_SPEED
        end
        
        truck.speed = updateSpeedSmooth(truck.speed, truck.targetSpeed, dt)
        
        updateTruckPhysics(truck, dt)
        updateTruckInstance(truck)
    else
        -- Start positioning phase
        local headingDiff = normalizeAngle180(truck.targetHeading - truck.heading)
        
        if math.abs(headingDiff) > HEADING_TOLERANCE_DEG then
            truck.frontSteeringAngle = clampSteeringAngle(headingDiff)
            truck.rearSteeringAngle = calculateRearSteeringAngle(truck.frontSteeringAngle)
            truck.targetSpeed = TRUCK_TURN_IN_PLACE_SPEED
            truck.speed = updateSpeedSmooth(truck.speed, truck.targetSpeed, dt)
            
            updateTruckPhysics(truck, dt)
            updateTruckInstance(truck)
        else
            truck.positioned = true
            truck.targetSpeed = 0.0
            truck.speed = 0.0
            truck.frontSteeringAngle = 0.0
            truck.rearSteeringAngle = 0.0
        end
    end
end

function updateTruckLeaving(truck, dt)
    local acX = drLocalX and get(drLocalX) or 0.0
    local acZ = drLocalZ and get(drLocalZ) or 0.0
    
    -- First turn, then leave
    if truck.isTurningBeforeLeave then
        local headingDiff = normalizeAngle180(truck.leaveHeading - truck.heading)
        
        if math.abs(headingDiff) > HEADING_TOLERANCE_DEG then
            truck.frontSteeringAngle = clampSteeringAngle(headingDiff)
            truck.rearSteeringAngle = calculateRearSteeringAngle(truck.frontSteeringAngle)
            truck.targetSpeed = TRUCK_TURN_IN_PLACE_SPEED
            truck.speed = updateSpeedSmooth(truck.speed, truck.targetSpeed, dt)
            
            updateTruckPhysics(truck, dt)
            updateTruckInstance(truck)
        else
            truck.isTurningBeforeLeave = false
            truck.frontSteeringAngle = 0.0
            truck.rearSteeringAngle = 0.0
        end
    else
        -- Drive away
        truck.targetSpeed = TRUCK_APPROACH_SPEED * TRUCK_LEAVING_SPEED_MULT
        truck.speed = updateSpeedSmooth(truck.speed, truck.targetSpeed, dt)
        
        updateTruckPhysics(truck, dt)
        updateTruckInstance(truck)
    end
    
    -- Check if truck has left the area
    local dx = truck.x - acX
    local dz = truck.z - acZ
    local dist = math.sqrt(dx * dx + dz * dz)
    
    return dist > TRUCK_LEAVING_DISTANCE
end

--------------------------------------------------------------------------------
-- Get delta time helper
--------------------------------------------------------------------------------

local lastTime = nil

function getTimeDelta()
    local currentTime = os.clock()
    if not lastTime then
        lastTime = currentTime
        return 0.016  -- Default ~60fps
    end
    local dt = currentTime - lastTime
    lastTime = currentTime
    return dt
end
