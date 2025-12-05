--------------------------------------------------------------------------------
-- WaterSalute SASL3 Plugin - Raindrop Effect Module
-- Simulates water droplets on windshield when aircraft passes through water gate
--------------------------------------------------------------------------------

-- Raindrop effect state
local raindropState = {
    drRainOnAircraft = nil,       -- X-Plane rain on aircraft dataref
    currentIntensity = 0.0,       -- Current raindrop intensity (0.0 - 1.0)
    targetIntensity = 0.0,        -- Target raindrop intensity
    updateTimer = 0.0,            -- Timer for detection updates
    effectActive = false,         -- Whether the effect is currently active
    originalRainValue = 0.0,      -- Original rain value before we modified it
    savedOriginalRain = false     -- Whether we've saved the original rain value
}

-- Initialize the raindrop effect system
function initializeRaindropEffect()
    debugLog("Initializing raindrop effect system...")
    
    -- Try to find the rain/precipitation dataref
    raindropState.drRainOnAircraft = globalPropertyf("sim/private/controls/rain/precipitation_on_aircraft_ratio")
    if not raindropState.drRainOnAircraft then
        raindropState.drRainOnAircraft = globalPropertyf("sim/weather/rain_percent")
    end
    
    raindropState.currentIntensity = 0.0
    raindropState.targetIntensity = 0.0
    raindropState.updateTimer = 0.0
    raindropState.effectActive = false
    raindropState.savedOriginalRain = false
    
    if raindropState.drRainOnAircraft then
        debugLog("Raindrop effect system initialized")
    else
        debugLog("WARNING: No rain dataref found - raindrop effect may not be visible")
    end
end

-- Clean up the raindrop effect system
function cleanupRaindropEffect()
    -- Restore original rain value if we modified it
    if raindropState.savedOriginalRain and raindropState.drRainOnAircraft then
        set(raindropState.drRainOnAircraft, raindropState.originalRainValue)
        raindropState.savedOriginalRain = false
    end
    
    raindropState.currentIntensity = 0.0
    raindropState.targetIntensity = 0.0
    raindropState.effectActive = false
    
    debugLog("Raindrop effect system cleaned up")
end

-- Count water particles near the aircraft
function countNearbyParticles(acX, acY, acZ)
    local nearbyCount = 0
    
    local function countForTruck(truck)
        if not truck or not truck.particles then return end
        
        for _, particle in ipairs(truck.particles) do
            if not particle.active then
                goto continue
            end
            
            -- Calculate 3D distance from aircraft to particle
            local dx = particle.x - acX
            local dy = particle.y - acY
            local dz = particle.z - acZ
            
            -- Check if particle is within detection radius horizontally
            local horizontalDist = math.sqrt(dx * dx + dz * dz)
            if horizontalDist > RAINDROP_DETECTION_RADIUS then
                goto continue
            end
            
            -- Check if particle is at approximately the same height (with tolerance)
            if math.abs(dy) > RAINDROP_DETECTION_HEIGHT then
                goto continue
            end
            
            nearbyCount = nearbyCount + 1
            
            ::continue::
        end
    end
    
    countForTruck(leftTruck)
    countForTruck(rightTruck)
    
    return nearbyCount
end

-- Get current raindrop intensity
function getCurrentRaindropIntensity()
    return raindropState.currentIntensity
end

-- Update the raindrop effect based on aircraft proximity to water
function updateRaindropEffect(dt, acX, acY, acZ, pluginState)
    -- Only update when water is spraying
    if pluginState ~= STATE_WATER_SPRAYING then
        -- Fade out the effect when not spraying
        if raindropState.currentIntensity > 0.0 then
            raindropState.targetIntensity = 0.0
            raindropState.currentIntensity = raindropState.currentIntensity - dt / RAINDROP_FADE_OUT_TIME
            if raindropState.currentIntensity < 0.0 then
                raindropState.currentIntensity = 0.0
            end
            
            -- Apply the effect
            if raindropState.drRainOnAircraft then
                set(raindropState.drRainOnAircraft, raindropState.originalRainValue + raindropState.currentIntensity)
            end
            
            -- Restore original value when effect is done
            if raindropState.currentIntensity == 0.0 and raindropState.savedOriginalRain then
                if raindropState.drRainOnAircraft then
                    set(raindropState.drRainOnAircraft, raindropState.originalRainValue)
                end
                raindropState.savedOriginalRain = false
                raindropState.effectActive = false
                debugLog("Raindrop effect faded out completely")
            end
        end
        return
    end
    
    -- Save original rain value before first modification
    if not raindropState.savedOriginalRain then
        if raindropState.drRainOnAircraft then
            raindropState.originalRainValue = get(raindropState.drRainOnAircraft)
        else
            raindropState.originalRainValue = 0.0
        end
        raindropState.savedOriginalRain = true
        debugLog("Saved original rain value: " .. string.format("%.3f", raindropState.originalRainValue))
    end
    
    -- Update detection less frequently for performance
    raindropState.updateTimer = raindropState.updateTimer + dt
    if raindropState.updateTimer >= RAINDROP_UPDATE_INTERVAL then
        raindropState.updateTimer = 0.0
        
        -- Count nearby particles
        local nearbyParticles = countNearbyParticles(acX, acY, acZ)
        
        -- Calculate target intensity based on particle count
        local maxParticles = NUM_PARTICLES_PER_JET * 2  -- 2 trucks
        local particleRatio = nearbyParticles / maxParticles
        raindropState.targetIntensity = math.min(particleRatio * RAINDROP_INTENSITY_MULTIPLIER, RAINDROP_EFFECT_MAX)
        
        if nearbyParticles > 0 and not raindropState.effectActive then
            debugLog("Aircraft entering water spray - " .. nearbyParticles .. " particles nearby")
            raindropState.effectActive = true
        elseif nearbyParticles == 0 and raindropState.effectActive and raindropState.currentIntensity < 0.01 then
            debugLog("Aircraft left water spray area")
            raindropState.effectActive = false
        end
    end
    
    -- Smooth transition to target intensity
    if raindropState.currentIntensity < raindropState.targetIntensity then
        -- Fade in
        raindropState.currentIntensity = raindropState.currentIntensity + dt / RAINDROP_FADE_IN_TIME
        if raindropState.currentIntensity > raindropState.targetIntensity then
            raindropState.currentIntensity = raindropState.targetIntensity
        end
    elseif raindropState.currentIntensity > raindropState.targetIntensity then
        -- Fade out
        raindropState.currentIntensity = raindropState.currentIntensity - dt / RAINDROP_FADE_OUT_TIME
        if raindropState.currentIntensity < raindropState.targetIntensity then
            raindropState.currentIntensity = raindropState.targetIntensity
        end
    end
    
    -- Apply the rain effect to the windshield
    local effectValue = raindropState.originalRainValue + raindropState.currentIntensity
    effectValue = math.min(effectValue, 1.0)  -- Cap at maximum
    
    if raindropState.drRainOnAircraft then
        set(raindropState.drRainOnAircraft, effectValue)
    end
end
