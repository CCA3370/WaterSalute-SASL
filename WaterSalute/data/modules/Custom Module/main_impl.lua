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
project_version = "1.1.0"

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
-- Sound System
--------------------------------------------------------------------------------

-- Sound sample IDs
soundWaterSpray = nil
soundTruckEngine = nil
soundTruckHorn = nil

-- Sound settings
SOUND_WATER_SPRAY_GAIN = 800      -- Volume for water spray (0-1000)
SOUND_TRUCK_ENGINE_GAIN = 600     -- Volume for truck engine
SOUND_TRUCK_HORN_GAIN = 900       -- Volume for truck horn
SOUND_MAX_DISTANCE = 500          -- Maximum audible distance in meters

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

-- Command IDs
cmdStartWaterSalute = nil
cmdStopWaterSalute = nil
cmdToggleWaterSalute = nil
cmdTruckHorn = nil

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

-- Configuration file path
CONFIG_FILE_PATH = nil

-- User settings (with defaults)
userSettings = {
    soundEnabled = true,
    soundVolume = 100,            -- 0-100 percentage
    autoStartOnGround = false,    -- Auto start when conditions are met
    truckSpeed = 15,              -- Truck approach speed m/s
    waterJetHeight = 25           -- Water jet height in meters
}

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function onModuleInit()
    debugLog("========================================")
    debugLog("WaterSalute plugin v" .. project_version .. " starting...")
    debugLog("========================================")
    
    -- Initialize random number generator
    math.randomseed(os.time())
    
    -- Set up configuration file path
    CONFIG_FILE_PATH = moduleDirectory .. "/output/watersalute_config.json"
    
    -- Load user configuration
    loadConfiguration()
    
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
    
    -- Register X-Plane commands
    registerCommands()
    
    -- Load sound samples
    loadSounds()
    
    -- Load fire truck model
    loadFireTruckModel()
    
    -- Load water effect models (tries waterjet.obj first, falls back to waterdrop.obj)
    loadWaterEffectModels()
    
    -- Initialize raindrop effect system
    initializeRaindropEffect()
    
    -- Initialize trucks
    leftTruck = createFireTruck()
    rightTruck = createFireTruck()
    
    debugLog("WaterSalute plugin started successfully")
end

function onModuleShutdown()
    debugLog("WaterSalute plugin stopping...")
    
    -- Stop all sounds
    stopAllSounds()
    
    -- Cleanup raindrop effect
    cleanupRaindropEffect()
    
    -- Cleanup trucks (including water streams)
    if leftTruck then cleanupTruck(leftTruck) end
    if rightTruck then cleanupTruck(rightTruck) end
    
    -- Unload models (note: SASL will auto-cleanup but we do it explicitly)
    if truckObjectId then
        sasl.unloadObject(truckObjectId)
        truckObjectId = nil
    end
    if waterStreamObjectId then
        sasl.unloadObject(waterStreamObjectId)
        waterStreamObjectId = nil
    end
    if waterDropObjectId then
        sasl.unloadObject(waterDropObjectId)
        waterDropObjectId = nil
    end
    
    -- Unload sounds
    unloadSounds()
    
    -- Note: SASL automatically cleans up menus, datarefs, and commands on shutdown
    
    debugLog("WaterSalute plugin stopped")
end

-- Called when project is about to be unloaded - save configuration
function onModuleDone()
    saveConfiguration()
    debugLog("Configuration saved")
end

--------------------------------------------------------------------------------
-- Menu System
--------------------------------------------------------------------------------

-- Local menu storage
local subMenuId = nil

function createPluginMenu()
    -- Create menu item under Plugins menu
    menuId = sasl.appendMenuItem(PLUGINS_MENU_ID, "Water Salute")
    
    -- Create submenu
    subMenuId = sasl.createMenu("Water Salute", PLUGINS_MENU_ID, menuId)
    
    -- Add menu items
    menuStartItem = sasl.appendMenuItem(subMenuId, "Start Water Salute", onMenuStart)
    menuStopItem = sasl.appendMenuItem(subMenuId, "Stop Water Salute", onMenuStop)
    
    updateMenuState()
end

function updateMenuState()
    if subMenuId then
        sasl.enableMenuItem(subMenuId, menuStartItem, pluginState == STATE_IDLE and 1 or 0)
        sasl.enableMenuItem(subMenuId, menuStopItem, pluginState ~= STATE_IDLE and 1 or 0)
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
    -- Use sasl.loadObject which uses the searchResourcesPath
    truckObjectId = sasl.loadObject("firetruck.obj")
    
    if truckObjectId then
        debugLog("Fire truck model loaded successfully")
    else
        debugLog("WARNING: Failed to load fire truck model")
        debugLog("Fire trucks will not be visible - please add firetruck.obj to resources folder")
    end
end

function loadWaterEffectModels()
    -- Try to load animated water stream model first (recommended approach)
    -- This is more performant than particle system as it uses a single OBJ with animations
    waterStreamObjectId = sasl.loadObject("waterjet.obj")
    
    if waterStreamObjectId then
        debugLog("Water stream model loaded successfully (using animated stream mode)")
        waterEffectMode = WATER_EFFECT_STREAM
        return
    end
    
    -- Fall back to particle system with water drop model
    waterDropObjectId = sasl.loadObject("waterdrop.obj")
    
    if waterDropObjectId then
        debugLog("Water drop model loaded (using particle system mode)")
        waterEffectMode = WATER_EFFECT_PARTICLES
    else
        debugLog("WARNING: No water effect models found")
        debugLog("Please add waterjet.obj (recommended) or waterdrop.obj to resources folder")
        waterEffectMode = WATER_EFFECT_NONE
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
-- X-Plane Commands
--------------------------------------------------------------------------------

function registerCommands()
    debugLog("Registering X-Plane commands...")
    
    -- Create command: Start Water Salute
    cmdStartWaterSalute = sasl.createCommand(
        "watersalute/start",
        "Start Water Salute Ceremony"
    )
    sasl.registerCommandHandler(cmdStartWaterSalute, 0, function(phase)
        if phase == SASL_COMMAND_BEGIN then
            startWaterSalute()
        end
        return 0  -- Consume the command
    end)
    
    -- Create command: Stop Water Salute
    cmdStopWaterSalute = sasl.createCommand(
        "watersalute/stop",
        "Stop Water Salute Ceremony"
    )
    sasl.registerCommandHandler(cmdStopWaterSalute, 0, function(phase)
        if phase == SASL_COMMAND_BEGIN then
            stopWaterSalute()
        end
        return 0
    end)
    
    -- Create command: Toggle Water Salute
    cmdToggleWaterSalute = sasl.createCommand(
        "watersalute/toggle",
        "Toggle Water Salute Ceremony"
    )
    sasl.registerCommandHandler(cmdToggleWaterSalute, 0, function(phase)
        if phase == SASL_COMMAND_BEGIN then
            if pluginState == STATE_IDLE then
                startWaterSalute()
            else
                stopWaterSalute()
            end
        end
        return 0
    end)
    
    -- Create command: Truck Horn
    cmdTruckHorn = sasl.createCommand(
        "watersalute/horn",
        "Sound Fire Truck Horn"
    )
    sasl.registerCommandHandler(cmdTruckHorn, 0, function(phase)
        if phase == SASL_COMMAND_BEGIN then
            playTruckHorn()
        end
        return 0
    end)
    
    debugLog("Commands registered: watersalute/start, watersalute/stop, watersalute/toggle, watersalute/horn")
end

--------------------------------------------------------------------------------
-- Sound System
--------------------------------------------------------------------------------

function loadSounds()
    debugLog("Loading sound samples...")
    
    -- Load water spray sound (looping)
    soundWaterSpray = sasl.al.loadSample("water_spray.wav")
    if soundWaterSpray then
        sasl.al.setSampleGain(soundWaterSpray, SOUND_WATER_SPRAY_GAIN)
        sasl.al.setSampleMaxDistance(soundWaterSpray, SOUND_MAX_DISTANCE)
        sasl.al.setSampleEnv(soundWaterSpray, SOUND_EVERYWHERE)
        debugLog("Water spray sound loaded")
    else
        debugLog("WARNING: water_spray.wav not found in resources folder")
    end
    
    -- Load truck engine sound (looping)
    soundTruckEngine = sasl.al.loadSample("truck_engine.wav")
    if soundTruckEngine then
        sasl.al.setSampleGain(soundTruckEngine, SOUND_TRUCK_ENGINE_GAIN)
        sasl.al.setSampleMaxDistance(soundTruckEngine, SOUND_MAX_DISTANCE)
        sasl.al.setSampleEnv(soundTruckEngine, SOUND_EVERYWHERE)
        debugLog("Truck engine sound loaded")
    else
        debugLog("WARNING: truck_engine.wav not found in resources folder")
    end
    
    -- Load truck horn sound
    soundTruckHorn = sasl.al.loadSample("truck_horn.wav")
    if soundTruckHorn then
        sasl.al.setSampleGain(soundTruckHorn, SOUND_TRUCK_HORN_GAIN)
        sasl.al.setSampleMaxDistance(soundTruckHorn, SOUND_MAX_DISTANCE)
        sasl.al.setSampleEnv(soundTruckHorn, SOUND_EVERYWHERE)
        debugLog("Truck horn sound loaded")
    else
        debugLog("WARNING: truck_horn.wav not found in resources folder")
    end
end

function unloadSounds()
    if soundWaterSpray then
        sasl.al.unloadSample(soundWaterSpray)
        soundWaterSpray = nil
    end
    if soundTruckEngine then
        sasl.al.unloadSample(soundTruckEngine)
        soundTruckEngine = nil
    end
    if soundTruckHorn then
        sasl.al.unloadSample(soundTruckHorn)
        soundTruckHorn = nil
    end
end

function startWaterSpraySound()
    if not userSettings.soundEnabled then return end
    if soundWaterSpray and not sasl.al.isSamplePlaying(soundWaterSpray) then
        sasl.al.playSample(soundWaterSpray, true)  -- Loop
        debugLog("Water spray sound started")
    end
end

function stopWaterSpraySound()
    if soundWaterSpray and sasl.al.isSamplePlaying(soundWaterSpray) then
        sasl.al.stopSample(soundWaterSpray)
    end
end

function startTruckEngineSound()
    if not userSettings.soundEnabled then return end
    if soundTruckEngine and not sasl.al.isSamplePlaying(soundTruckEngine) then
        sasl.al.playSample(soundTruckEngine, true)  -- Loop
        debugLog("Truck engine sound started")
    end
end

function stopTruckEngineSound()
    if soundTruckEngine and sasl.al.isSamplePlaying(soundTruckEngine) then
        sasl.al.stopSample(soundTruckEngine)
    end
end

function playTruckHorn()
    if not userSettings.soundEnabled then return end
    if soundTruckHorn then
        -- Set position to truck location
        if leftTruck then
            sasl.al.setSamplePosition(soundTruckHorn, leftTruck.x, leftTruck.y, leftTruck.z)
        end
        sasl.al.playSample(soundTruckHorn, false)  -- Play once
        debugLog("Truck horn played")
    end
end

function updateSoundPositions()
    -- Update 3D sound positions to follow trucks
    if leftTruck and rightTruck then
        -- Average position between trucks for water spray
        if soundWaterSpray then
            local avgX = (leftTruck.x + rightTruck.x) / 2
            local avgY = (leftTruck.y + rightTruck.y) / 2 + 5  -- Above trucks
            local avgZ = (leftTruck.z + rightTruck.z) / 2
            sasl.al.setSamplePosition(soundWaterSpray, avgX, avgY, avgZ)
        end
        
        -- Engine sound at left truck position
        if soundTruckEngine then
            sasl.al.setSamplePosition(soundTruckEngine, leftTruck.x, leftTruck.y, leftTruck.z)
        end
    end
end

function stopAllSounds()
    stopWaterSpraySound()
    stopTruckEngineSound()
    if soundTruckHorn and sasl.al.isSamplePlaying(soundTruckHorn) then
        sasl.al.stopSample(soundTruckHorn)
    end
end

--------------------------------------------------------------------------------
-- Configuration System
--------------------------------------------------------------------------------

function loadConfiguration()
    debugLog("Loading configuration...")
    
    if CONFIG_FILE_PATH and isFileExists(CONFIG_FILE_PATH) then
        local config = sasl.readConfig(CONFIG_FILE_PATH, "json")
        if config then
            -- Merge loaded config with defaults
            if config.soundEnabled ~= nil then userSettings.soundEnabled = config.soundEnabled end
            if config.soundVolume ~= nil then userSettings.soundVolume = config.soundVolume end
            if config.autoStartOnGround ~= nil then userSettings.autoStartOnGround = config.autoStartOnGround end
            if config.truckSpeed ~= nil then userSettings.truckSpeed = config.truckSpeed end
            if config.waterJetHeight ~= nil then userSettings.waterJetHeight = config.waterJetHeight end
            debugLog("Configuration loaded from " .. CONFIG_FILE_PATH)
        else
            debugLog("Failed to parse configuration file, using defaults")
        end
    else
        debugLog("No configuration file found, using defaults")
    end
    
    -- Apply sound volume
    applySoundVolume()
end

function saveConfiguration()
    if not CONFIG_FILE_PATH then return end
    
    local result = sasl.writeConfig(CONFIG_FILE_PATH, "json", userSettings)
    if result then
        debugLog("Configuration saved to " .. CONFIG_FILE_PATH)
    else
        debugLog("WARNING: Failed to save configuration")
    end
end

function applySoundVolume()
    local volumeMultiplier = userSettings.soundVolume / 100.0
    
    if soundWaterSpray then
        sasl.al.setSampleGain(soundWaterSpray, math.floor(SOUND_WATER_SPRAY_GAIN * volumeMultiplier))
    end
    if soundTruckEngine then
        sasl.al.setSampleGain(soundTruckEngine, math.floor(SOUND_TRUCK_ENGINE_GAIN * volumeMultiplier))
    end
    if soundTruckHorn then
        sasl.al.setSampleGain(soundTruckHorn, math.floor(SOUND_TRUCK_HORN_GAIN * volumeMultiplier))
    end
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
        leftTruck.instance = sasl.createInstance(truckObjectId, {})
        if leftTruck.instance then
            sasl.setInstancePosition(leftTruck.instance, leftTruck.x, leftTruck.y, leftTruck.z, 0, leftTruck.heading, 0, {})
        end
        
        rightTruck.objectId = truckObjectId
        rightTruck.instance = sasl.createInstance(truckObjectId, {})
        if rightTruck.instance then
            sasl.setInstancePosition(rightTruck.instance, rightTruck.x, rightTruck.y, rightTruck.z, 0, rightTruck.heading, 0, {})
        end
    end
    
    -- Start truck engine sound
    startTruckEngineSound()
    
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
    
    -- Stop water spray sound
    stopWaterSpraySound()
    
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
    
    -- Update 3D sound positions
    updateSoundPositions()
    
    if pluginState == STATE_TRUCKS_APPROACHING or pluginState == STATE_TRUCKS_POSITIONING then
        updateTrucks(dt)
    elseif pluginState == STATE_WATER_SPRAYING then
        local currentTime = os.clock()
        -- Use unified water effect function (automatically picks best method)
        updateTruckWaterEffect(leftTruck, dt, waterDropObjectId, currentTime, true)
        updateTruckWaterEffect(rightTruck, dt, waterDropObjectId, currentTime, true)
        updateRaindropEffect(dt, acX, acY, acZ, pluginState)
        -- Water spray sound is started when transitioning to this state
    elseif pluginState == STATE_TRUCKS_LEAVING then
        -- Turn off water effects when leaving
        local currentTime = os.clock()
        updateTruckWaterEffect(leftTruck, dt, waterDropObjectId, currentTime, false)
        updateTruckWaterEffect(rightTruck, dt, waterDropObjectId, currentTime, false)
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
            -- Start water spray sound when spraying begins
            startWaterSpraySound()
            debugLog("State changed to: " .. getStateName(pluginState))
        end
    elseif pluginState == STATE_TRUCKS_LEAVING then
        local leftDone = updateTruckLeaving(leftTruck, dt)
        local rightDone = updateTruckLeaving(rightTruck, dt)
        
        if leftDone and rightDone then
            cleanupTruck(leftTruck)
            cleanupTruck(rightTruck)
            -- Stop all sounds when ceremony ends
            stopAllSounds()
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
