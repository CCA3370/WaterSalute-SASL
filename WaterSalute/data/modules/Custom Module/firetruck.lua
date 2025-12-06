--------------------------------------------------------------------------------
-- WaterSalute SASL3 Plugin - Fire Truck Module
-- Handles fire truck data structures, movement, and water effects
--
-- Water Effects Implementation Options:
-- 
-- 1. ANIMATED WATER STREAM (Recommended - Better Performance):
--    Use a water stream OBJ file with dataref-driven animations.
--    The OBJ file should have animations controlled by datarefs:
--    - watersalute/waterjet/active (0/1) - controls visibility
--    - watersalute/waterjet/intensity (0-1) - controls spray width/volume
--    This is more performant and looks better than particle systems.
--    
--    To use: Place 'waterjet.obj' in resources folder with animations.
--
-- 2. PARTICLE SYSTEM (Fallback):
--    Creates individual water drop instances that follow physics.
--    Less performant but works with simple sphere OBJ models.
--    
--    To use: Place 'waterdrop.obj' in resources folder.
--
-- The plugin will attempt to load waterjet.obj first, falling back to
-- the particle system if not found.
--------------------------------------------------------------------------------

-- Water effect mode
WATER_EFFECT_NONE = 0
WATER_EFFECT_STREAM = 1      -- Single animated OBJ per truck
WATER_EFFECT_PARTICLES = 2   -- Multiple particle instances

-- Current water effect mode
waterEffectMode = WATER_EFFECT_NONE

-- Water stream object ID (for animated stream approach)
waterStreamObjectId = nil

-- Fire truck structure template
function createFireTruck()
    return {
        -- Position and orientation
        x = 0, y = 0, z = 0,
        heading = 0,
        targetX = 0, targetZ = 0,
        targetHeading = 0,
        positioned = false,
        
        -- Instance for rendering
        instance = nil,
        objectId = nil,
        
        -- Wheel and steering
        frontSteeringAngle = 0,
        rearSteeringAngle = 0,
        wheelRotationAngle = 0,
        
        -- Water cannon
        cannonPitch = DEFAULT_CANNON_PITCH,
        cannonYaw = 0,
        nozzleOffsetX = 0,
        nozzleOffsetY = 3.5,
        nozzleOffsetZ = 2.0,
        
        -- Speed control
        speed = 0,
        targetSpeed = 0,
        
        -- Leaving state
        isTurningBeforeLeave = false,
        leaveHeading = 0,
        
        -- Route planning
        route = nil,
        useRoadNetwork = false,
        
        -- Water stream instance (for animated stream mode)
        waterStreamInstance = nil,
        waterStreamActive = false,
        
        -- Water particles (for particle mode fallback)
        particles = {},
        lastEmitTime = 0
    }
end

-- Global truck instances
leftTruck = nil
rightTruck = nil

-- Initialize a fire truck
function initializeTruck(truck)
    truck.x = 0
    truck.y = 0
    truck.z = 0
    truck.heading = 0
    truck.targetX = 0
    truck.targetZ = 0
    truck.targetHeading = 0
    truck.positioned = false
    truck.instance = nil
    truck.frontSteeringAngle = 0
    truck.rearSteeringAngle = 0
    truck.wheelRotationAngle = 0
    truck.cannonPitch = DEFAULT_CANNON_PITCH
    truck.cannonYaw = 0
    truck.speed = 0
    truck.targetSpeed = 0
    truck.isTurningBeforeLeave = false
    truck.leaveHeading = 0
    truck.route = nil
    truck.useRoadNetwork = false
    truck.waterStreamInstance = nil
    truck.waterStreamActive = false
    truck.particles = {}
    truck.lastEmitTime = 0
end

-- Cleanup a fire truck
function cleanupTruck(truck)
    if truck.instance then
        sasl.destroyInstance(truck.instance)
        truck.instance = nil
    end
    
    -- Clean up water stream instance
    if truck.waterStreamInstance then
        sasl.destroyInstance(truck.waterStreamInstance)
        truck.waterStreamInstance = nil
    end
    truck.waterStreamActive = false
    
    -- Clean up all particle instances
    for i, particle in ipairs(truck.particles) do
        if particle.instance then
            sasl.destroyInstance(particle.instance)
            particle.instance = nil
        end
    end
    truck.particles = {}
end

-- Update wheel rotation angle based on distance moved
function updateWheelRotationAngle(truck, distanceMoved)
    local wheelCircumference = 2.0 * PI * WHEEL_RADIUS
    local rotationDegrees = (distanceMoved / wheelCircumference) * 360.0
    truck.wheelRotationAngle = normalizeAngle360(truck.wheelRotationAngle + rotationDegrees)
end

-- Update truck position and heading based on speed and steering
function updateTruckPhysics(truck, dt)
    if truck.speed < 0.01 then
        return
    end
    
    -- Calculate turning rate
    local turningRate = calculateTurningRate(truck.speed, truck.frontSteeringAngle, truck.rearSteeringAngle)
    
    -- Update heading
    truck.heading = truck.heading + turningRate * dt
    truck.heading = normalizeAngle360(truck.heading)
    
    -- Move truck forward
    local headingRad = truck.heading * DEG_TO_RAD
    local moveDistance = truck.speed * dt
    
    truck.x = truck.x + math.sin(headingRad) * moveDistance
    truck.z = truck.z - math.cos(headingRad) * moveDistance
    truck.y = getTerrainHeight(truck.x, truck.z)
    
    -- Update wheel rotation
    updateWheelRotationAngle(truck, moveDistance)
end

-- Update truck instance position for rendering
function updateTruckInstance(truck)
    if truck.instance then
        sasl.setInstancePosition(truck.instance, truck.x, truck.y, truck.z, 0, truck.heading, 0, {})
    end
end

-- Create water particle
function createWaterParticle()
    return {
        x = 0, y = 0, z = 0,
        vx = 0, vy = 0, vz = 0,
        lifetime = PARTICLE_LIFETIME,
        maxLifetime = PARTICLE_LIFETIME,
        active = true,
        instance = nil
    }
end

-- Emit a water particle from truck's nozzle
function emitParticle(truck, waterDropObjectId)
    local particle = createWaterParticle()
    
    -- Calculate nozzle world position
    local headingRad = truck.heading * DEG_TO_RAD
    local cosH = math.cos(headingRad)
    local sinH = math.sin(headingRad)
    
    -- Get cannon angles
    local pitchRad = truck.cannonPitch * DEG_TO_RAD
    local yawRad = (truck.cannonYaw + truck.heading) * DEG_TO_RAD
    
    -- Nozzle position in world coordinates
    particle.x = truck.x + sinH * truck.nozzleOffsetZ + cosH * truck.nozzleOffsetX
    particle.y = truck.y + truck.nozzleOffsetY
    particle.z = truck.z - cosH * truck.nozzleOffsetZ + sinH * truck.nozzleOffsetX
    
    -- Calculate initial velocity for water arc
    local initialSpeed = WATER_JET_HEIGHT * 2.5
    
    -- Add some randomness for spray effect
    local spreadAngle = 0.05
    local randPitch = pitchRad + randomRange(-0.5, 0.5) * spreadAngle
    local randYaw = yawRad + randomRange(-0.5, 0.5) * spreadAngle
    
    -- Calculate velocity components
    local cosPitch = math.cos(randPitch)
    local sinPitch = math.sin(randPitch)
    local cosYaw = math.cos(randYaw)
    local sinYaw = math.sin(randYaw)
    
    particle.vx = initialSpeed * cosPitch * sinYaw
    particle.vy = initialSpeed * sinPitch
    particle.vz = -initialSpeed * cosPitch * cosYaw
    
    -- Add some turbulence
    particle.vx = particle.vx + randomRange(-0.5, 0.5) * 0.5
    particle.vy = particle.vy + randomRange(-0.5, 0.5) * 0.3
    particle.vz = particle.vz + randomRange(-0.5, 0.5) * 0.5
    
    particle.lifetime = PARTICLE_LIFETIME
    particle.maxLifetime = PARTICLE_LIFETIME
    particle.active = true
    
    -- Create instance for this particle if water drop model is loaded
    if waterDropObjectId then
        particle.instance = sasl.createInstance(waterDropObjectId, {})
        if particle.instance then
            sasl.setInstancePosition(particle.instance, particle.x, particle.y, particle.z, 0, 0, 0, {})
        end
    end
    
    table.insert(truck.particles, particle)
end

-- Update a single water particle
function updateParticle(particle, dt)
    if not particle.active then
        return false
    end
    
    -- Apply gravity
    particle.vy = particle.vy - 9.81 * dt
    
    -- Apply air resistance
    local speed = math.sqrt(particle.vx * particle.vx + 
                           particle.vy * particle.vy + 
                           particle.vz * particle.vz)
    if speed > 0.01 then
        local dragForce = PARTICLE_DRAG * speed * speed
        local dragAccel = dragForce / speed
        particle.vx = particle.vx - particle.vx / speed * dragAccel * dt
        particle.vy = particle.vy - particle.vy / speed * dragAccel * dt
        particle.vz = particle.vz - particle.vz / speed * dragAccel * dt
    end
    
    -- Add turbulence
    particle.vx = particle.vx + randomRange(-0.5, 0.5) * PARTICLE_TURBULENCE
    particle.vy = particle.vy + randomRange(-0.5, 0.5) * PARTICLE_TURBULENCE
    particle.vz = particle.vz + randomRange(-0.5, 0.5) * PARTICLE_TURBULENCE
    
    -- Update position
    particle.x = particle.x + particle.vx * dt
    particle.y = particle.y + particle.vy * dt
    particle.z = particle.z + particle.vz * dt
    
    -- Check ground collision
    local groundY = getTerrainHeight(particle.x, particle.z)
    if particle.y < groundY then
        particle.y = groundY
        particle.vy = 0
        particle.vx = particle.vx * 0.5
        particle.vz = particle.vz * 0.5
    end
    
    -- Update instance position
    if particle.instance then
        sasl.setInstancePosition(particle.instance, particle.x, particle.y, particle.z, 0, 0, 0, {})
    end
    
    -- Update lifetime
    particle.lifetime = particle.lifetime - dt
    if particle.lifetime <= 0 then
        particle.active = false
        if particle.instance then
            sasl.destroyInstance(particle.instance)
            particle.instance = nil
        end
        return false
    end
    
    return true
end

-- Update all water particles for a truck
function updateTruckParticles(truck, dt, waterDropObjectId, currentTime)
    -- Emit new particles
    if currentTime - truck.lastEmitTime >= PARTICLE_EMIT_RATE then
        -- Count active particles
        local activeCount = 0
        for i, p in ipairs(truck.particles) do
            if p.active then activeCount = activeCount + 1 end
        end
        
        if activeCount < NUM_PARTICLES_PER_JET then
            emitParticle(truck, waterDropObjectId)
            truck.lastEmitTime = currentTime
        end
    end
    
    -- Update existing particles
    for i = #truck.particles, 1, -1 do
        local particle = truck.particles[i]
        if not updateParticle(particle, dt) then
            -- Remove dead particles if list is getting too long
            if #truck.particles > NUM_PARTICLES_PER_JET * 2 then
                table.remove(truck.particles, i)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Water Stream Functions (Recommended Approach)
-- Uses a single animated OBJ file per truck instead of many particles
--------------------------------------------------------------------------------

-- Datarefs for water stream animation control
local waterStreamDatarefs = {
    "watersalute/waterjet/active",      -- 0 or 1, controls visibility
    "watersalute/waterjet/intensity"    -- 0-1, controls spray width/volume
}

-- Create water stream instance for a truck
function createWaterStreamInstance(truck)
    if not waterStreamObjectId then
        return false
    end
    
    if truck.waterStreamInstance then
        return true  -- Already created
    end
    
    -- Create instance with animation datarefs
    truck.waterStreamInstance = sasl.createInstance(waterStreamObjectId, waterStreamDatarefs)
    
    if truck.waterStreamInstance then
        debugLog("Water stream instance created for truck")
        return true
    else
        debugLog("WARNING: Failed to create water stream instance")
        return false
    end
end

-- Update water stream position and animation
function updateWaterStream(truck, active)
    if not truck.waterStreamInstance then
        return
    end
    
    -- Calculate nozzle world position
    local headingRad = truck.heading * DEG_TO_RAD
    local cosH = math.cos(headingRad)
    local sinH = math.sin(headingRad)
    
    -- Nozzle position in world coordinates
    local streamX = truck.x + sinH * truck.nozzleOffsetZ + cosH * truck.nozzleOffsetX
    local streamY = truck.y + truck.nozzleOffsetY
    local streamZ = truck.z - cosH * truck.nozzleOffsetZ + sinH * truck.nozzleOffsetX
    
    -- Stream orientation: pitch from cannon, yaw from truck heading + cannon yaw
    local streamPitch = truck.cannonPitch
    local streamHeading = truck.heading + truck.cannonYaw
    
    -- Animation dataref values
    local activeValue = active and 1.0 or 0.0
    local intensityValue = active and 1.0 or 0.0
    
    -- Update instance position and animation datarefs
    sasl.setInstancePosition(
        truck.waterStreamInstance,
        streamX, streamY, streamZ,
        streamPitch, streamHeading, 0,
        { activeValue, intensityValue }
    )
    
    truck.waterStreamActive = active
end

-- Cleanup water stream for a truck
function cleanupWaterStream(truck)
    if truck.waterStreamInstance then
        sasl.destroyInstance(truck.waterStreamInstance)
        truck.waterStreamInstance = nil
    end
    truck.waterStreamActive = false
end

--------------------------------------------------------------------------------
-- Unified Water Effect Update
-- Automatically uses the best available method
--------------------------------------------------------------------------------

function updateTruckWaterEffect(truck, dt, waterDropObjectId, currentTime, active)
    if waterEffectMode == WATER_EFFECT_STREAM then
        -- Use animated water stream OBJ (better performance)
        if active and not truck.waterStreamInstance then
            createWaterStreamInstance(truck)
        end
        updateWaterStream(truck, active)
    elseif waterEffectMode == WATER_EFFECT_PARTICLES then
        -- Use particle system (fallback)
        if active then
            updateTruckParticles(truck, dt, waterDropObjectId, currentTime)
        end
    end
    -- WATER_EFFECT_NONE: do nothing
end

-- Get truck by index (0 = left, 1 = right)
function getTruckByIndex(index)
    if index == 0 then return leftTruck end
    if index == 1 then return rightTruck end
    return nil
end
