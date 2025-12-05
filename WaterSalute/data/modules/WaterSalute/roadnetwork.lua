--------------------------------------------------------------------------------
-- WaterSalute SASL3 Plugin - Road Network Module
-- Handles apt.dat parsing and road network management
--------------------------------------------------------------------------------

-- Road network data structure
roadNetwork = {
    airportId = "",
    refLat = 0,
    refLon = 0,
    nodes = {},       -- { name, lat, lon, x, z, nodeType, connectedEdges }
    edges = {},       -- { node1Idx, node2Idx, isOneWay, isFireTruckRoute, length, surfaceType }
    nodeNameToIndex = {},
    isLoaded = false
}

-- Coordinate conversion: lat/lon to local coordinates
function latLonToLocal(lat, lon, refLat, refLon)
    local latRad = refLat * DEG_TO_RAD
    local x = (lon - refLon) * DEG_TO_RAD * EARTH_RADIUS_METERS * math.cos(latRad)
    local z = -(lat - refLat) * DEG_TO_RAD * EARTH_RADIUS_METERS
    return x, z
end

-- Coordinate conversion: local to lat/lon
function localToLatLon(x, z, refLat, refLon)
    local latRad = refLat * DEG_TO_RAD
    local lon = refLon + x / (EARTH_RADIUS_METERS * math.cos(latRad)) * RAD_TO_DEG
    local lat = refLat - z / EARTH_RADIUS_METERS * RAD_TO_DEG
    return lat, lon
end

-- Parse a single line from apt.dat into tokens
function parseAptDatLine(line)
    local tokens = {}
    for token in string.gmatch(line, "%S+") do
        table.insert(tokens, token)
    end
    return tokens
end

-- Load airport ground routes from apt.dat
function loadAptDat(acLat, acLon)
    debugLog("LoadAptDat: Searching for airport near (" .. string.format("%.6f, %.6f", acLat, acLon) .. ")")
    
    -- Reset road network
    roadNetwork.nodes = {}
    roadNetwork.edges = {}
    roadNetwork.nodeNameToIndex = {}
    roadNetwork.isLoaded = false
    
    -- Get X-Plane system path
    local systemPath = getXPlanePath()
    
    -- Build path to apt.dat - try several common locations
    local aptDatPaths = {
        systemPath .. "Resources/default scenery/default apt dat/Earth nav data/apt.dat",
        systemPath .. "Custom Scenery/Global Airports/Earth nav data/apt.dat",
        systemPath .. "Resources/default data/apt.dat"
    }
    
    local file = nil
    local usedPath = ""
    
    for _, path in ipairs(aptDatPaths) do
        file = io.open(path, "r")
        if file then
            usedPath = path
            debugLog("LoadAptDat: Opened apt.dat at " .. path)
            break
        end
    end
    
    if not file then
        debugLog("LoadAptDat: Could not open any apt.dat file")
        return false
    end
    
    -- Parsing variables
    local foundNearbyAirport = false
    local inAirport = false
    local inGroundNetwork = false
    local airportLat = 0
    local airportLon = 0
    local currentAirportId = ""
    local bestDistance = ROAD_SEARCH_RADIUS
    local bestAirportId = ""
    local bestAirportLat = 0
    local bestAirportLon = 0
    
    -- Temporary storage for current airport's ground network
    local tempNodes = {}
    local tempEdges = {}
    local tempNodeNameToIndex = {}
    
    -- Parse apt.dat file
    for line in file:lines() do
        local tokens = parseAptDatLine(line)
        if #tokens == 0 then
            goto continue
        end
        
        local rowCode = tonumber(tokens[1])
        if not rowCode then
            goto continue
        end
        
        -- Airport header (1 = land airport, 16 = seaplane base, 17 = heliport)
        if rowCode == 1 or rowCode == 16 or rowCode == 17 then
            -- Check if we were in an airport with ground network
            if inAirport and inGroundNetwork and #tempNodes > 0 then
                -- Calculate distance to this airport
                local dx, dz = latLonToLocal(acLat, acLon, airportLat, airportLon)
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist < bestDistance then
                    bestDistance = dist
                    bestAirportId = currentAirportId
                    bestAirportLat = airportLat
                    bestAirportLon = airportLon
                    -- Save this airport's ground network
                    roadNetwork.nodes = tempNodes
                    roadNetwork.edges = tempEdges
                    roadNetwork.nodeNameToIndex = tempNodeNameToIndex
                    foundNearbyAirport = true
                end
            end
            
            -- Reset for new airport
            inAirport = true
            inGroundNetwork = false
            tempNodes = {}
            tempEdges = {}
            tempNodeNameToIndex = {}
            
            if #tokens >= 5 then
                currentAirportId = tokens[5]
                airportLat = acLat
                airportLon = acLon
            end
            
        -- Taxi routing network header
        elseif rowCode == 1200 then
            inGroundNetwork = true
            
        -- Taxi routing node (1201)
        elseif rowCode == 1201 and inGroundNetwork and #tokens >= 5 then
            local node = {
                lat = tonumber(tokens[2]) or 0,
                lon = tonumber(tokens[3]) or 0,
                x = 0,
                z = 0,
                nodeType = tokens[4],
                name = tokens[5],
                connectedEdges = {}
            }
            
            -- Use first node as airport reference point if not set
            if #tempNodes == 0 then
                airportLat = node.lat
                airportLon = node.lon
            end
            
            -- Concatenate remaining tokens for multi-word names
            for i = 6, #tokens do
                node.name = node.name .. "_" .. tokens[i]
            end
            
            tempNodeNameToIndex[node.name] = #tempNodes + 1
            table.insert(tempNodes, node)
            
        -- Taxi routing edge (1202) - basic taxiway connection
        elseif rowCode == 1202 and inGroundNetwork and #tokens >= 4 then
            local node1Name = tokens[2]
            local node2Name = tokens[3]
            
            local idx1 = tempNodeNameToIndex[node1Name]
            local idx2 = tempNodeNameToIndex[node2Name]
            
            if idx1 and idx2 then
                local edge = {
                    node1Idx = idx1,
                    node2Idx = idx2,
                    isOneWay = (tokens[4] == "oneway"),
                    isFireTruckRoute = true,  -- Assume taxiways can be used by fire trucks
                    length = 0,
                    surfaceType = (#tokens > 4) and tokens[5] or "taxiway"
                }
                
                table.insert(tempEdges, edge)
                table.insert(tempNodes[idx1].connectedEdges, #tempEdges)
                if not edge.isOneWay then
                    table.insert(tempNodes[idx2].connectedEdges, #tempEdges)
                end
            end
            
        -- Ground truck route edge (1206) - specific vehicle types
        elseif rowCode == 1206 and inGroundNetwork and #tokens >= 4 then
            local node1Name = tokens[2]
            local node2Name = tokens[3]
            local direction = (#tokens > 3) and tokens[4] or "twoway"
            local truckTypes = (#tokens > 4) and tokens[5] or ""
            
            local idx1 = tempNodeNameToIndex[node1Name]
            local idx2 = tempNodeNameToIndex[node2Name]
            
            if idx1 and idx2 then
                local edge = {
                    node1Idx = idx1,
                    node2Idx = idx2,
                    isOneWay = (direction == "oneway"),
                    isFireTruckRoute = (string.find(truckTypes, "fire_truck") ~= nil) or (truckTypes == ""),
                    length = 0,
                    surfaceType = "service_road"
                }
                
                table.insert(tempEdges, edge)
                table.insert(tempNodes[idx1].connectedEdges, #tempEdges)
                if not edge.isOneWay then
                    table.insert(tempNodes[idx2].connectedEdges, #tempEdges)
                end
            end
        end
        
        ::continue::
    end
    
    file:close()
    
    -- Check final airport if any
    if inAirport and inGroundNetwork and #tempNodes > 0 then
        local dx, dz = latLonToLocal(acLat, acLon, airportLat, airportLon)
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist < bestDistance then
            bestDistance = dist
            bestAirportId = currentAirportId
            bestAirportLat = airportLat
            bestAirportLon = airportLon
            roadNetwork.nodes = tempNodes
            roadNetwork.edges = tempEdges
            roadNetwork.nodeNameToIndex = tempNodeNameToIndex
            foundNearbyAirport = true
        end
    end
    
    if not foundNearbyAirport then
        debugLog("LoadAptDat: No nearby airport with ground routes found")
        return false
    end
    
    -- Set up the road network
    roadNetwork.airportId = bestAirportId
    roadNetwork.refLat = bestAirportLat
    roadNetwork.refLon = bestAirportLon
    
    -- Convert all node coordinates to local OpenGL coordinates
    for i, node in ipairs(roadNetwork.nodes) do
        local x, y, z = worldToLocal(node.lat, node.lon, 0)
        node.x = x
        node.z = z
    end
    
    -- Calculate edge lengths
    for i, edge in ipairs(roadNetwork.edges) do
        local n1 = roadNetwork.nodes[edge.node1Idx]
        local n2 = roadNetwork.nodes[edge.node2Idx]
        local dx = n2.x - n1.x
        local dz = n2.z - n1.z
        edge.length = math.sqrt(dx * dx + dz * dz)
    end
    
    roadNetwork.isLoaded = true
    
    debugLog("LoadAptDat: Loaded airport " .. bestAirportId .. " with " .. #roadNetwork.nodes .. " nodes and " .. #roadNetwork.edges .. " edges")
    
    return true
end

-- Find the nearest road network node to a given position
function findNearestNode(x, z, firetruckRoutesOnly)
    if not roadNetwork.isLoaded or #roadNetwork.nodes == 0 then
        return nil
    end
    
    local bestIndex = nil
    local bestDist = math.huge
    
    for i, node in ipairs(roadNetwork.nodes) do
        -- Check if node is connected to any fire truck routes
        if firetruckRoutesOnly then
            local hasFiretruckRoute = false
            for _, edgeIdx in ipairs(node.connectedEdges) do
                if roadNetwork.edges[edgeIdx].isFireTruckRoute then
                    hasFiretruckRoute = true
                    break
                end
            end
            if not hasFiretruckRoute then
                goto continue
            end
        end
        
        local dx = node.x - x
        local dz = node.z - z
        local dist = math.sqrt(dx * dx + dz * dz)
        
        if dist < bestDist then
            bestDist = dist
            bestIndex = i
        end
        
        ::continue::
    end
    
    return bestIndex
end
