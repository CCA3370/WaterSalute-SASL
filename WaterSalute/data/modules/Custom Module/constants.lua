--------------------------------------------------------------------------------
-- WaterSalute SASL3 Plugin - Constants and Configuration
-- All constants used across the plugin modules
--------------------------------------------------------------------------------

-- Unit conversions
KNOTS_TO_MS = 0.514444           -- Knots to m/s conversion
FEET_TO_METERS = 0.3048          -- Feet to meters conversion
DEG_TO_RAD = math.pi / 180.0     -- Degrees to radians
RAD_TO_DEG = 180.0 / math.pi     -- Radians to degrees
PI = math.pi

-- Aircraft validation
MAX_GROUND_SPEED_KNOTS = 40.0    -- Maximum ground speed for water salute

-- Truck physics
TRUCK_APPROACH_SPEED = 15.0      -- Fire truck approach speed in m/s
TRUCK_TURN_IN_PLACE_SPEED = 2.0  -- Speed for turning in place (m/s)
TRUCK_LEAVING_SPEED_MULT = 2.0 / 3.0  -- Speed multiplier when leaving (2/3 of approach speed)
TRUCK_ACCELERATION = 3.0         -- Truck acceleration in m/s^2
TRUCK_DECELERATION = 4.0         -- Truck deceleration in m/s^2
TRUCK_SLOWDOWN_DISTANCE = 30.0   -- Distance at which truck starts slowing down (meters)
HEADING_TOLERANCE_DEG = 2.0      -- Tolerance for heading alignment (degrees)
TRUCK_LEAVING_DISTANCE = 600.0   -- Distance from aircraft to complete leaving (meters)
TRUCK_STOP_DISTANCE = 200.0      -- Distance in front of aircraft to stop (meters)
TRUCK_EXTRA_SPACING = 40.0       -- Extra spacing beyond wingspan (meters)
TRUCK_SPAWN_DISTANCE = 500.0     -- Distance from aircraft to spawn trucks (meters)

-- Wheel physics
WHEEL_RADIUS = 0.5               -- Wheel radius in meters
MAX_STEERING_ANGLE = 45.0        -- Maximum steering angle in degrees
WHEELBASE = 6.0                  -- Distance between front and rear axles in meters
REAR_STEER_RATIO = 0.4           -- Rear axle steering ratio (counter-steering)
MIN_STEERING_TANGENT = 0.01      -- Minimum tangent value to prevent division by zero

-- Water cannon
MIN_CANNON_PITCH = 0.0           -- Minimum cannon pitch angle
MAX_CANNON_PITCH = 90.0          -- Maximum cannon pitch angle
DEFAULT_CANNON_PITCH = 45.0      -- Default cannon pitch angle for water arc
WATER_JET_HEIGHT = 25.0          -- Maximum height of water arch (meters)

-- Particle system
NUM_PARTICLES_PER_JET = 200      -- Number of particles per water jet
PARTICLE_EMIT_RATE = 0.015       -- Time between particle emissions (seconds)
PARTICLE_LIFETIME = 4.0          -- Particle lifetime in seconds
PARTICLE_DRAG = 0.15             -- Air drag coefficient for particles
PARTICLE_TURBULENCE = 0.02       -- Turbulence amount for particle movement

-- Raindrop effect on windshield
RAINDROP_DETECTION_RADIUS = 50.0 -- Radius to detect water particles near aircraft (meters)
RAINDROP_DETECTION_HEIGHT = 20.0 -- Height range to detect water particles (meters)
RAINDROP_EFFECT_MAX = 0.8        -- Maximum rain effect intensity (0.0 - 1.0)
RAINDROP_FADE_IN_TIME = 0.5      -- Time to fade in rain effect (seconds)
RAINDROP_FADE_OUT_TIME = 2.0     -- Time to fade out rain effect (seconds)
RAINDROP_UPDATE_INTERVAL = 0.1   -- Interval to update raindrop detection (seconds)
RAINDROP_INTENSITY_MULTIPLIER = 2.0 -- Multiplier to boost intensity for visual effect

-- Wingspan validation
MIN_SEMISPAN_METERS = 2.5        -- Minimum semispan (half wingspan) in meters
MAX_SEMISPAN_METERS = 45.0       -- Maximum semispan in meters
MIN_WINGSPAN_METERS = 5.0        -- Minimum valid wingspan in meters
MAX_WINGSPAN_METERS = 90.0       -- Maximum valid wingspan in meters
DEFAULT_WINGSPAN_METERS = 30.0   -- Default wingspan if not available

-- Road network constants
ROAD_SEARCH_RADIUS = 5000.0      -- Maximum distance to search for roads (meters)
PATH_NODE_DISTANCE = 30.0        -- Minimum distance between path nodes (meters)
TURN_ANTICIPATION = 15.0         -- Distance ahead to start turning
MIN_TURN_RADIUS = 8.0            -- Minimum turning radius for 8x8 truck (meters)
PATH_REACH_THRESHOLD = 5.0       -- Distance to consider a waypoint reached (meters)
BEZIER_SMOOTHING_FACTOR = 0.25   -- Control point distance as fraction of segment length
MAX_PATH_NODES = 500             -- Maximum number of nodes in a planned path
EARTH_RADIUS_METERS = 6371000.0  -- Earth radius for lat/lon to meters conversion

-- Plugin state enumeration
STATE_IDLE = 0
STATE_TRUCKS_APPROACHING = 1
STATE_TRUCKS_POSITIONING = 2
STATE_WATER_SPRAYING = 3
STATE_TRUCKS_LEAVING = 4

-- State names for debugging
STATE_NAMES = {
    [STATE_IDLE] = "STATE_IDLE",
    [STATE_TRUCKS_APPROACHING] = "STATE_TRUCKS_APPROACHING",
    [STATE_TRUCKS_POSITIONING] = "STATE_TRUCKS_POSITIONING",
    [STATE_WATER_SPRAYING] = "STATE_WATER_SPRAYING",
    [STATE_TRUCKS_LEAVING] = "STATE_TRUCKS_LEAVING"
}

-- Get state name
function getStateName(state)
    return STATE_NAMES[state] or "UNKNOWN"
end
