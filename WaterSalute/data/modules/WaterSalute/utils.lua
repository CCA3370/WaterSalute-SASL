--------------------------------------------------------------------------------
-- WaterSalute SASL3 Plugin - Utility Functions
-- Common utility functions used across the plugin
--------------------------------------------------------------------------------

-- Normalize angle to 0-360 range
function normalizeAngle360(angle)
    while angle >= 360.0 do angle = angle - 360.0 end
    while angle < 0.0 do angle = angle + 360.0 end
    return angle
end

-- Normalize angle to -180 to 180 range
function normalizeAngle180(angle)
    while angle > 180.0 do angle = angle - 360.0 end
    while angle < -180.0 do angle = angle + 360.0 end
    return angle
end

-- Smooth speed transition using acceleration/deceleration
function updateSpeedSmooth(currentSpeed, targetSpeed, dt)
    if currentSpeed < targetSpeed then
        -- Accelerating
        currentSpeed = currentSpeed + TRUCK_ACCELERATION * dt
        if currentSpeed > targetSpeed then
            currentSpeed = targetSpeed
        end
    elseif currentSpeed > targetSpeed then
        -- Decelerating
        currentSpeed = currentSpeed - TRUCK_DECELERATION * dt
        if currentSpeed < targetSpeed then
            currentSpeed = targetSpeed
        end
    end
    return currentSpeed
end

-- Clamp steering angle to valid range
function clampSteeringAngle(angle)
    if angle > MAX_STEERING_ANGLE then return MAX_STEERING_ANGLE end
    if angle < -MAX_STEERING_ANGLE then return -MAX_STEERING_ANGLE end
    return angle
end

-- Calculate rear steering angle based on front angle (counter-steering)
function calculateRearSteeringAngle(frontSteerAngle)
    -- Rear axle uses counter-steering (opposite direction) with reduced magnitude
    return -frontSteerAngle * REAR_STEER_RATIO
end

-- Calculate turning rate using Ackermann steering model
function calculateTurningRate(speed, frontSteerAngleDeg, rearSteerAngleDeg)
    -- For very low speeds or zero steering, no turning
    if math.abs(speed) < 0.01 or math.abs(frontSteerAngleDeg) < 0.1 then
        return 0.0
    end
    
    -- Convert steering angles to radians
    local frontAngleRad = frontSteerAngleDeg * DEG_TO_RAD
    local rearAngleRad = rearSteerAngleDeg * DEG_TO_RAD
    
    -- Combined steering effect
    local effectiveSteerAngle = (math.tan(frontAngleRad) - math.tan(rearAngleRad)) / 2.0
    
    -- Angular velocity = v * tan(steer) / wheelbase
    local angularVelocity = speed * effectiveSteerAngle / WHEELBASE
    
    -- Convert to degrees per second
    return angularVelocity * RAD_TO_DEG
end

-- Get terrain height at a position
function getTerrainHeight(x, z)
    local result, lat, lon, alt, nx, ny, nz, vx, vy, vz, isWet = probeTerrain(x, 10000.0, z)
    if result == PROBE_HIT_TERRAIN then
        return lat  -- 'lat' is actually the Y coordinate (height) in SASL
    end
    return 0.0
end

-- Linear interpolation
function lerp(a, b, t)
    return a + (b - a) * t
end

-- Clamp value between min and max
function clamp(value, minVal, maxVal)
    if value < minVal then return minVal end
    if value > maxVal then return maxVal end
    return value
end

-- Calculate distance between two points
function distance2D(x1, z1, x2, z2)
    local dx = x2 - x1
    local dz = z2 - z1
    return math.sqrt(dx * dx + dz * dz)
end

-- Calculate distance in 3D
function distance3D(x1, y1, z1, x2, y2, z2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Random number between min and max
function randomRange(minVal, maxVal)
    return minVal + math.random() * (maxVal - minVal)
end

-- Debug log function
function debugLog(message)
    logInfo("[WaterSalute] " .. message)
end

-- Verbose debug log (can be disabled in production)
DEBUG_VERBOSE = false
function debugLogVerbose(message)
    if DEBUG_VERBOSE then
        logInfo("[WaterSalute VERBOSE] " .. message)
    end
end
