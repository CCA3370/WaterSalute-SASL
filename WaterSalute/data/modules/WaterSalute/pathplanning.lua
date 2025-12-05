--------------------------------------------------------------------------------
-- WaterSalute SASL3 Plugin - Path Planning Module
-- A* pathfinding and Bezier curve smoothing
--------------------------------------------------------------------------------

-- Path waypoint structure
function createPathWaypoint()
    return {
        x = 0,
        z = 0,
        targetHeading = 0,
        speed = TRUCK_APPROACH_SPEED,
        isSmoothed = false
    }
end

-- Planned route structure
function createPlannedRoute()
    return {
        waypoints = {},
        currentWaypointIndex = 1,
        isValid = false,
        isCompleted = false
    }
end

-- A* pathfinding node
function createAStarNode(nodeIndex, gScore, fScore, parentIndex)
    return {
        nodeIndex = nodeIndex,
        gScore = gScore or 0,
        fScore = fScore or 0,
        parentIndex = parentIndex
    }
end

-- Priority queue implementation for A*
local PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

function PriorityQueue.new()
    return setmetatable({ heap = {} }, PriorityQueue)
end

function PriorityQueue:push(item, priority)
    table.insert(self.heap, { item = item, priority = priority })
    self:bubbleUp(#self.heap)
end

function PriorityQueue:pop()
    if #self.heap == 0 then return nil end
    local top = self.heap[1].item
    self.heap[1] = self.heap[#self.heap]
    table.remove(self.heap)
    if #self.heap > 0 then
        self:bubbleDown(1)
    end
    return top
end

function PriorityQueue:isEmpty()
    return #self.heap == 0
end

function PriorityQueue:bubbleUp(index)
    while index > 1 do
        local parent = math.floor(index / 2)
        if self.heap[parent].priority <= self.heap[index].priority then
            break
        end
        self.heap[parent], self.heap[index] = self.heap[index], self.heap[parent]
        index = parent
    end
end

function PriorityQueue:bubbleDown(index)
    local size = #self.heap
    while true do
        local smallest = index
        local left = 2 * index
        local right = 2 * index + 1
        
        if left <= size and self.heap[left].priority < self.heap[smallest].priority then
            smallest = left
        end
        if right <= size and self.heap[right].priority < self.heap[smallest].priority then
            smallest = right
        end
        
        if smallest == index then break end
        
        self.heap[index], self.heap[smallest] = self.heap[smallest], self.heap[index]
        index = smallest
    end
end

-- Find path using A* algorithm
function findPath(startNode, goalNode)
    local path = {}
    
    if not roadNetwork.isLoaded or startNode > #roadNetwork.nodes or goalNode > #roadNetwork.nodes then
        return nil
    end
    
    local goalNodeRef = roadNetwork.nodes[goalNode]
    
    -- A* data structures
    local openSet = PriorityQueue.new()
    local gScores = {}
    local cameFrom = {}
    local closedSet = {}
    
    -- Initialize start node
    local startNodeRef = roadNetwork.nodes[startNode]
    local heuristic = math.sqrt((goalNodeRef.x - startNodeRef.x)^2 + (goalNodeRef.z - startNodeRef.z)^2)
    
    openSet:push(startNode, heuristic)
    gScores[startNode] = 0
    
    while not openSet:isEmpty() do
        local current = openSet:pop()
        
        if current == goalNode then
            -- Reconstruct path
            local node = goalNode
            while node ~= startNode and cameFrom[node] do
                table.insert(path, 1, node)
                node = cameFrom[node]
            end
            table.insert(path, 1, startNode)
            
            debugLog("FindPath: Found path with " .. #path .. " nodes")
            return path
        end
        
        if closedSet[current] then
            goto continue
        end
        closedSet[current] = true
        
        local currentNode = roadNetwork.nodes[current]
        
        -- Explore neighbors
        for _, edgeIdx in ipairs(currentNode.connectedEdges) do
            local edge = roadNetwork.edges[edgeIdx]
            
            -- Skip non-fire truck routes
            if not edge.isFireTruckRoute then
                goto nextEdge
            end
            
            -- Determine neighbor node
            local neighborIdx
            if edge.node1Idx == current then
                neighborIdx = edge.node2Idx
            elseif not edge.isOneWay and edge.node2Idx == current then
                neighborIdx = edge.node1Idx
            else
                goto nextEdge
            end
            
            if closedSet[neighborIdx] then
                goto nextEdge
            end
            
            local tentativeG = gScores[current] + edge.length
            
            if not gScores[neighborIdx] or tentativeG < gScores[neighborIdx] then
                gScores[neighborIdx] = tentativeG
                cameFrom[neighborIdx] = current
                
                local neighborNode = roadNetwork.nodes[neighborIdx]
                local h = math.sqrt((goalNodeRef.x - neighborNode.x)^2 + (goalNodeRef.z - neighborNode.z)^2)
                
                openSet:push(neighborIdx, tentativeG + h)
            end
            
            ::nextEdge::
        end
        
        ::continue::
    end
    
    debugLog("FindPath: No path found from node " .. startNode .. " to node " .. goalNode)
    return nil
end

-- Apply Bezier curve smoothing to a planned route
function smoothPath(route)
    if #route.waypoints < 3 then
        return
    end
    
    local smoothedWaypoints = {}
    
    for i, current in ipairs(route.waypoints) do
        if i == 1 or i == #route.waypoints then
            -- Keep start and end points as-is
            table.insert(smoothedWaypoints, current)
        else
            -- Smooth middle points using Bezier interpolation
            local prev = route.waypoints[i - 1]
            local next = route.waypoints[i + 1]
            
            -- Calculate segment lengths
            local lenPrev = math.sqrt((current.x - prev.x)^2 + (current.z - prev.z)^2)
            local lenNext = math.sqrt((next.x - current.x)^2 + (next.z - current.z)^2)
            
            -- Only add smoothing points if segments are long enough
            if lenPrev > MIN_TURN_RADIUS * 2 and lenNext > MIN_TURN_RADIUS * 2 then
                -- Add approach point before the turn
                local approach = createPathWaypoint()
                approach.x = current.x - (current.x - prev.x) * BEZIER_SMOOTHING_FACTOR
                approach.z = current.z - (current.z - prev.z) * BEZIER_SMOOTHING_FACTOR
                approach.targetHeading = math.atan2(current.x - prev.x, -(current.z - prev.z)) * RAD_TO_DEG
                approach.speed = TRUCK_APPROACH_SPEED * 0.7
                approach.isSmoothed = true
                table.insert(smoothedWaypoints, approach)
                
                -- Add the actual waypoint
                local wp = createPathWaypoint()
                wp.x = current.x
                wp.z = current.z
                wp.speed = TRUCK_APPROACH_SPEED * 0.5
                wp.isSmoothed = false
                table.insert(smoothedWaypoints, wp)
                
                -- Add exit point after the turn
                local exit = createPathWaypoint()
                exit.x = current.x + (next.x - current.x) * BEZIER_SMOOTHING_FACTOR
                exit.z = current.z + (next.z - current.z) * BEZIER_SMOOTHING_FACTOR
                exit.targetHeading = math.atan2(next.x - current.x, -(next.z - current.z)) * RAD_TO_DEG
                exit.speed = TRUCK_APPROACH_SPEED * 0.7
                exit.isSmoothed = true
                table.insert(smoothedWaypoints, exit)
            else
                -- Segment too short, just keep the waypoint
                table.insert(smoothedWaypoints, current)
            end
        end
    end
    
    -- Calculate target headings for all waypoints
    for i = 1, #smoothedWaypoints - 1 do
        local wp = smoothedWaypoints[i]
        local nextWp = smoothedWaypoints[i + 1]
        wp.targetHeading = math.atan2(nextWp.x - wp.x, -(nextWp.z - wp.z)) * RAD_TO_DEG
    end
    -- Last waypoint keeps its heading
    if #smoothedWaypoints > 1 then
        smoothedWaypoints[#smoothedWaypoints].targetHeading = smoothedWaypoints[#smoothedWaypoints - 1].targetHeading
    end
    
    route.waypoints = smoothedWaypoints
    debugLog("SmoothPath: Created " .. #route.waypoints .. " smoothed waypoints")
end

-- Plan a route from start position to target using road network
function planRouteToTarget(startX, startZ, targetX, targetZ, targetHeading)
    local route = createPlannedRoute()
    route.currentWaypointIndex = 1
    route.isValid = false
    route.isCompleted = false
    
    debugLog("PlanRouteToTarget: Planning from (" .. string.format("%.2f, %.2f", startX, startZ) .. 
             ") to (" .. string.format("%.2f, %.2f", targetX, targetZ) .. ")")
    
    if not roadNetwork.isLoaded then
        debugLog("PlanRouteToTarget: No road network loaded, using direct approach")
        
        -- Create simple direct path with intermediate waypoints
        local dx = targetX - startX
        local dz = targetZ - startZ
        local dist = math.sqrt(dx * dx + dz * dz)
        local numWaypoints = math.floor(dist / PATH_NODE_DISTANCE) + 2
        numWaypoints = math.min(numWaypoints, MAX_PATH_NODES)
        
        for i = 0, numWaypoints - 1 do
            local t = i / (numWaypoints - 1)
            local wp = createPathWaypoint()
            wp.x = startX + dx * t
            wp.z = startZ + dz * t
            wp.targetHeading = math.atan2(dx, -dz) * RAD_TO_DEG
            wp.speed = TRUCK_APPROACH_SPEED
            wp.isSmoothed = false
            table.insert(route.waypoints, wp)
        end
        
        -- Set final waypoint heading
        if #route.waypoints > 0 then
            route.waypoints[#route.waypoints].targetHeading = targetHeading
            route.waypoints[#route.waypoints].speed = 0.0
        end
        
        route.isValid = true
        return route
    end
    
    -- Find nearest nodes to start and target
    local startNode = findNearestNode(startX, startZ, true)
    local goalNode = findNearestNode(targetX, targetZ, false)
    
    if not startNode or not goalNode then
        debugLog("PlanRouteToTarget: Could not find start or goal node, using direct approach")
        
        -- Fallback to direct path
        local startWp = createPathWaypoint()
        startWp.x = startX
        startWp.z = startZ
        startWp.targetHeading = math.atan2(targetX - startX, -(targetZ - startZ)) * RAD_TO_DEG
        startWp.speed = TRUCK_APPROACH_SPEED
        startWp.isSmoothed = false
        
        local endWp = createPathWaypoint()
        endWp.x = targetX
        endWp.z = targetZ
        endWp.targetHeading = targetHeading
        endWp.speed = 0.0
        endWp.isSmoothed = false
        
        table.insert(route.waypoints, startWp)
        table.insert(route.waypoints, endWp)
        route.isValid = true
        return route
    end
    
    debugLog("PlanRouteToTarget: Start node " .. startNode .. ", Goal node " .. goalNode)
    
    -- Run A* pathfinding
    local nodePath = findPath(startNode, goalNode)
    
    if not nodePath then
        debugLog("PlanRouteToTarget: A* failed, using direct approach")
        
        -- Fallback to direct path
        local startWp = createPathWaypoint()
        startWp.x = startX
        startWp.z = startZ
        startWp.targetHeading = math.atan2(targetX - startX, -(targetZ - startZ)) * RAD_TO_DEG
        startWp.speed = TRUCK_APPROACH_SPEED
        startWp.isSmoothed = false
        
        local endWp = createPathWaypoint()
        endWp.x = targetX
        endWp.z = targetZ
        endWp.targetHeading = targetHeading
        endWp.speed = 0.0
        endWp.isSmoothed = false
        
        table.insert(route.waypoints, startWp)
        table.insert(route.waypoints, endWp)
        route.isValid = true
        return route
    end
    
    -- Convert node path to waypoints
    -- Add start position as first waypoint
    local startWp = createPathWaypoint()
    startWp.x = startX
    startWp.z = startZ
    startWp.speed = TRUCK_APPROACH_SPEED
    startWp.isSmoothed = false
    table.insert(route.waypoints, startWp)
    
    -- Add road network nodes as waypoints
    for _, nodeIdx in ipairs(nodePath) do
        local node = roadNetwork.nodes[nodeIdx]
        local wp = createPathWaypoint()
        wp.x = node.x
        wp.z = node.z
        wp.speed = TRUCK_APPROACH_SPEED
        wp.isSmoothed = false
        table.insert(route.waypoints, wp)
    end
    
    -- Add target as final waypoint
    local endWp = createPathWaypoint()
    endWp.x = targetX
    endWp.z = targetZ
    endWp.targetHeading = targetHeading
    endWp.speed = 0.0
    endWp.isSmoothed = false
    table.insert(route.waypoints, endWp)
    
    -- Calculate headings for all waypoints
    for i = 1, #route.waypoints - 1 do
        local wp = route.waypoints[i]
        local nextWp = route.waypoints[i + 1]
        wp.targetHeading = math.atan2(nextWp.x - wp.x, -(nextWp.z - wp.z)) * RAD_TO_DEG
    end
    
    -- Apply Bezier smoothing for natural turns
    smoothPath(route)
    
    route.isValid = true
    debugLog("PlanRouteToTarget: Created route with " .. #route.waypoints .. " waypoints")
    
    return route
end

-- Update truck following planned path
function updateTruckFollowingPath(truck, dt)
    if not truck.route or not truck.route.isValid or truck.route.isCompleted then
        return
    end
    
    -- Get current target waypoint
    if truck.route.currentWaypointIndex > #truck.route.waypoints then
        truck.route.isCompleted = true
        truck.positioned = true
        debugLog("UpdateTruckFollowingPath: Truck completed route")
        return
    end
    
    local target = truck.route.waypoints[truck.route.currentWaypointIndex]
    
    -- Calculate distance to current waypoint
    local dx = target.x - truck.x
    local dz = target.z - truck.z
    local distance = math.sqrt(dx * dx + dz * dz)
    
    -- Check if waypoint reached
    if distance < PATH_REACH_THRESHOLD then
        truck.route.currentWaypointIndex = truck.route.currentWaypointIndex + 1
        
        if truck.route.currentWaypointIndex > #truck.route.waypoints then
            truck.route.isCompleted = true
            truck.positioned = true
            truck.targetSpeed = 0.0
            debugLogVerbose("UpdateTruckFollowingPath: Route completed")
            return
        end
        
        debugLogVerbose("UpdateTruckFollowingPath: Reached waypoint " .. truck.route.currentWaypointIndex .. "/" .. #truck.route.waypoints)
    end
    
    -- Calculate desired heading to target
    local desiredHeading = math.atan2(dx, -dz) * RAD_TO_DEG
    
    -- Look ahead for upcoming turns
    local lookAheadDist = TURN_ANTICIPATION
    local accumulatedDist = distance
    local futureHeading = desiredHeading
    
    for i = truck.route.currentWaypointIndex + 1, #truck.route.waypoints do
        if accumulatedDist >= lookAheadDist then break end
        
        local wp = truck.route.waypoints[i]
        local prevWp = truck.route.waypoints[i - 1]
        
        local segDx = wp.x - prevWp.x
        local segDz = wp.z - prevWp.z
        local segLen = math.sqrt(segDx * segDx + segDz * segDz)
        accumulatedDist = accumulatedDist + segLen
        
        if accumulatedDist >= lookAheadDist then
            futureHeading = math.atan2(segDx, -segDz) * RAD_TO_DEG
            break
        end
    end
    
    -- Calculate heading difference for steering
    local headingDiff = normalizeAngle180(desiredHeading - truck.heading)
    
    -- Anticipate turns
    local futureHeadingDiff = normalizeAngle180(futureHeading - truck.heading)
    
    if math.abs(futureHeadingDiff) > math.abs(headingDiff) and distance < TURN_ANTICIPATION then
        headingDiff = headingDiff * 0.7 + futureHeadingDiff * 0.3
    end
    
    -- Set steering angle based on heading difference
    truck.frontSteeringAngle = clampSteeringAngle(headingDiff)
    truck.rearSteeringAngle = calculateRearSteeringAngle(truck.frontSteeringAngle)
    
    -- Calculate minimum turn radius and adjust speed
    local steerTan = math.tan(truck.frontSteeringAngle * DEG_TO_RAD)
    if math.abs(steerTan) < MIN_STEERING_TANGENT then
        steerTan = MIN_STEERING_TANGENT
    end
    local turnRadius = WHEELBASE / math.abs(steerTan)
    
    -- Speed control
    local maxSpeedForTurn = math.sqrt(turnRadius * 2.0)
    maxSpeedForTurn = math.min(maxSpeedForTurn, TRUCK_APPROACH_SPEED)
    maxSpeedForTurn = math.max(maxSpeedForTurn, TRUCK_TURN_IN_PLACE_SPEED)
    
    -- Target speed from waypoint
    local waypointSpeed = target.speed
    if waypointSpeed <= 0 then waypointSpeed = TRUCK_APPROACH_SPEED end
    
    -- Slow down approaching waypoints
    if distance < TRUCK_SLOWDOWN_DISTANCE then
        local slowdownFactor = distance / TRUCK_SLOWDOWN_DISTANCE
        waypointSpeed = math.max(TRUCK_TURN_IN_PLACE_SPEED, waypointSpeed * slowdownFactor)
    end
    
    -- Use the minimum of turn speed and waypoint speed
    truck.targetSpeed = math.min(maxSpeedForTurn, waypointSpeed)
    
    -- Smooth speed transition
    truck.speed = updateSpeedSmooth(truck.speed, truck.targetSpeed, dt)
    
    -- Update physics
    updateTruckPhysics(truck, dt)
    
    -- Update instance
    updateTruckInstance(truck)
end
