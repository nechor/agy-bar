local version = "1.2.2"

function widget:GetInfo()
  return {
    name      = "HTTP API Server v2",
    desc = "Exposes a local HTTP server on port 8540 with JSON endpoints for game state",
    author    = "Antigravity",
    date      = "2026",
    license   = "MIT",
    layer     = 0,
    enabled   = true
  }
end

local socket -- Local variable for the socket module
local server -- Local variable for the listening server socket

-- Chat/Console history buffer
local consoleHistory = {}
local maxConsoleHistory = 50

-- Optimization cache and throttle counters
local unitDefCache = {}
local frameCounter = 0
local frameThrottle = 8 -- Poll socket every 8 frames (approx 8-15 times per second)


-- Simple Lua-to-JSON encoder helper
local function to_json(val)
  local t = type(val)
  if t == "number" then
    return tostring(val)
  elseif t == "boolean" then
    return val and "true" or "false"
  elseif t == "string" then
    return string.format("%q", val)
  elseif t == "table" then
    local is_array = true
    local max_idx = 0
    local count = 0
    for k, v in pairs(val) do
      count = count + 1
      if type(k) == "number" and k > 0 and math.floor(k) == k then
        if k > max_idx then max_idx = k end
      else
        is_array = false
        break
      end
    end
    if is_array and max_idx ~= count then
      is_array = false
    end

    local parts = {}
    if is_array then
      for i = 1, max_idx do
        table.insert(parts, to_json(val[i]))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      for k, v in pairs(val) do
        local key_str = tostring(k)
        table.insert(parts, string.format("%q:%s", key_str, to_json(v)))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  else
    return "null"
  end
end

-- Hook console messages to log chat and game events
function widget:AddConsoleLine(line, level)
  table.insert(consoleHistory, {
    text = line,
    level = level,
    time = Spring.GetGameSeconds()
  })
  if #consoleHistory > maxConsoleHistory then
    table.remove(consoleHistory, 1)
  end
end

local lastInitAttemptTime = 0

local function InitializeServer()
  if server then return true end

  -- Resolve global socket via environment table getfenv(1) to avoid local shadowing
  local env = getfenv(1)
  if env then
    if env.socket then
      socket = env.socket
    elseif env.Socket then
      socket = env.Socket
    else
      local success, res = pcall(function() return VFS.Include("socket.lua") end)
      if success and res then
        socket = res
      end
    end
  end

  if not socket then
    Spring.Echo("HTTP API Server v2: ERROR - Sockets are not available.")
    return false
  end

  -- Bind to localhost:8540
  local err
  server, err = socket.bind("127.0.0.1", 8540)
  if not server then
    Spring.Echo("HTTP API Server v2: ERROR - Failed to bind to 127.0.0.1:8540. Error: " .. tostring(err))
    return false
  end
  server:settimeout(0) -- Set to non-blocking
  Spring.Echo("HTTP API Server v2: Successfully started on http://127.0.0.1:8540")
  return true
end

function widget:Initialize()
  Spring.Echo("HTTP API Server v2: Initializing fully-featured server...")
  InitializeServer()
end

function widget:Shutdown()
  if server then
    server:close()
    Spring.Echo("HTTP API Server v2: Stopped")
    server = nil
  end
end

function widget:Update()
  -- Safety checks: Only process API requests when server is set up
  if not server then
    local now = os.clock()
    if now - lastInitAttemptTime > 5 then
      lastInitAttemptTime = now
      Spring.Echo("HTTP API Server v2: Server not running, retrying initialization...")
      InitializeServer()
    end
    if not server then return end
  end
  
  -- Throttle execution to run once every 8 frames (reduces constant polling CPU waste)
  frameCounter = frameCounter + 1
  if frameCounter % frameThrottle ~= 0 then return end

  -- Accept incoming connections (non-blocking)
  local client, err = server:accept()
  if client then
    client:settimeout(0.02) -- Minimal timeout to receive headers without blocking
    local request, err = client:receive()
    
    if request then
      local method, path = request:match("^(%a+)%s+(%S+)%s+HTTP")
      
      if method == "GET" then
        local data = {}
        local frame = Spring.GetGameFrame()
        
        if not frame or frame < 0 then
          -- Minimal loading state to empty backlog and keep socket alive
          data.game = {
            frame = frame or -1,
            seconds = 0,
            speed = 1,
            paused = true,
            mapName = "Loading...",
            modName = "Loading...",
          }
          data.localPlayer = { playerId = -1, teamId = -1, allyTeamId = -1 }
          data.resources = {
            metal = { storage = 0, capacity = 0, excess = 0, income = 0, expense = 0, pull = 0 },
            energy = { storage = 0, capacity = 0, excess = 0, income = 0, expense = 0, pull = 0 }
          }
          data.environment = {
            wind = { min = 0, max = 25, current = 0 },
            mapSize = { x = 0, z = 0 }
          }
          data.players = {}
          data.teams = {}
          data.units = {}
          data.selectedUnits = {}
          data.console = consoleHistory
          
          local json_body = to_json(data)
          local response = "HTTP/1.1 200 OK\r\n" ..
                           "Content-Type: application/json\r\n" ..
                           "Access-Control-Allow-Origin: *\r\n" ..
                           "Content-Length: " .. string.len(json_body) .. "\r\n" ..
                           "Connection: close\r\n\r\n" ..
                           json_body
          client:send(response)
          client:close()
          return
        end

        -- 1. Game general state (highly defensive)
        data.game = {
          frame = frame,
          seconds = Spring.GetGameSeconds() or 0,
          speed = Spring.GetGameSpeed() or 1,
          paused = (Spring.GetGameSpeed() or 1) == 0,
          mapName = Game and Game.mapName or "unknown",
          modName = Game and Game.modName or "unknown",
        }

        -- 2. Local player/team contexts
        local myPlayerID = Spring.GetMyPlayerID()
        local myTeamID = Spring.GetMyTeamID()
        local myAllyTeamID = Spring.GetMyAllyTeamID()
        
        data.localPlayer = {
          playerId = myPlayerID or -1,
          teamId = myTeamID or -1,
          allyTeamId = myAllyTeamID or -1,
        }

        -- 3. Resources of the local team
        if myTeamID and myTeamID >= 0 then
          local success_m, ms, md, me, mi, mo, mp = pcall(Spring.GetTeamResources, myTeamID, "metal")
          local success_e, es, ed, ee, ei, eo, ep = pcall(Spring.GetTeamResources, myTeamID, "energy")
          data.resources = {
            metal = success_m and { storage = ms or 0, capacity = md or 0, excess = me or 0, income = mi or 0, expense = mo or 0, pull = mp or 0 } or { storage = 0, capacity = 0, excess = 0, income = 0, expense = 0, pull = 0 },
            energy = success_e and { storage = es or 0, capacity = ed or 0, excess = ee or 0, income = ei or 0, expense = eo or 0, pull = ep or 0 } or { storage = 0, capacity = 0, excess = 0, income = 0, expense = 0, pull = 0 },
          }
        else
          data.resources = {
            metal = { storage = 0, capacity = 0, excess = 0, income = 0, expense = 0, pull = 0 },
            energy = { storage = 0, capacity = 0, excess = 0, income = 0, expense = 0, pull = 0 }
          }
        end

        -- 4. Environment data (Wind & Map Size)
        local _, _, _, windCurrent = Spring.GetWind()
        local windMin = Game and Game.windMin or 0
        local windMax = Game and Game.windMax or 25
        data.environment = {
          wind = { min = windMin, max = windMax, current = windCurrent or 0 },
          mapSize = { x = Game and Game.mapSizeX or 0, z = Game and Game.mapSizeZ or 0 },
        }

        -- 5. Players list
        data.players = {}
        local playerList = Spring.GetPlayerList()
        if playerList then
          for i = 1, #playerList do
            local pID = playerList[i]
            if pID then
              local name, active, spectator, teamID, allyTeamID, ping, cpu = Spring.GetPlayerInfo(pID)
              if name then
                data.players[tostring(pID)] = {
                  name = name,
                  active = active or false,
                  spectator = spectator or false,
                  teamId = teamID or -1,
                  allyTeamId = allyTeamID or -1,
                  ping = ping or 0,
                  cpu = cpu or 0
                }
              end
            end
          end
        end

        -- 6. Teams list
        data.teams = {}
        local teamList = Spring.GetTeamList()
        if teamList then
          for i = 1, #teamList do
            local tID = teamList[i]
            if tID then
              local color = {Spring.GetTeamColor(tID)}
              local leader, active, spectator, share, handicap, allyTeamID = Spring.GetTeamInfo(tID)
              local success_m, ms, md, _, mi, mo = pcall(Spring.GetTeamResources, tID, "metal")
              local success_e, es, ed, _, ei, eo = pcall(Spring.GetTeamResources, tID, "energy")
              
              -- Resolve team name (player or bot)
              local name = "BOT_" .. tID
              if leader and leader >= 0 then
                local pName = Spring.GetPlayerInfo(leader)
                if pName then name = pName end
              else
                -- Try to get Skirmish AI name
                local hasAI, aiName = Spring.GetAIInfo(tID)
                if hasAI and aiName then
                  name = aiName
                end
              end

              data.teams[tostring(tID)] = {
                name = name,
                allyTeamId = allyTeamID,
                color = color,
                leader = leader or -1,
                active = active or false,
                spectator = spectator or false,
                share = share or 0,
                handicap = handicap or 0,
                resources = {
                  metal = { storage = success_m and ms or 0, capacity = success_m and md or 0, income = success_m and mi or 0, expense = success_m and mo or 0 },
                  energy = { storage = success_e and es or 0, capacity = success_e and ed or 0, income = success_e and ei or 0, expense = success_e and eo or 0 }
                }
              }
            end
          end
        end

        -- 7. All Units visible to the local player (Optimized with Cache)
        data.units = {}
        local teamThreats = {}
        local allUnits = Spring.GetAllUnits()
        local myTeamId = Spring.GetMyTeamID() -- Get local player's team ID
        
        if allUnits then
          for i = 1, #allUnits do
            local uID = allUnits[i]
            if uID then
              local team = Spring.GetUnitTeam(uID)
              local unitDefID = Spring.GetUnitDefID(uID)
              
              if unitDefID then
                local cachedDef = unitDefCache[unitDefID]
                if not cachedDef then
                  local unitDef = UnitDefs and UnitDefs[unitDefID]
                  if unitDef then
                    local name = unitDef.name or ""
                    local isBuilder = unitDef.isBuilder or unitDef.canBuild
                    local hasWeapons = unitDef.weapons and #unitDef.weapons > 0
                    local isEco = (name:match("mex") or name:match("solar") or name:match("wind") or name:match("win$") or name:match("fusion") or name:match("converter") or name:match("makr") or name:match("mkr") or name:match("stor$") or name:match("geo") or (unitDef.energyMake or 0) > 0 or (unitDef.metalMake or 0) > 0 or (unitDef.extractsMetal or 0) > 0) and not isBuilder
                    
                    local category = "utility"
                    if isEco then
                      category = "economy"
                    elseif isBuilder then
                      category = "build"
                    elseif hasWeapons or unitDef.canAttack then
                      category = "combat"
                    end

                    local techLevel = unitDef.techLevel or (unitDef.customParams and tonumber(unitDef.customParams.techlevel)) or 1
                    if techLevel < 1 then techLevel = 1 end

                    local isBuilding = unitDef.isBuilding or (unitDef.speed or 0) == 0

                    cachedDef = {
                      defName = name,
                      humanName = unitDef.translatedHumanName or (unitDef.humanName ~= "" and unitDef.humanName) or name,
                      category = category,
                      techLevel = techLevel,
                      isBuilding = isBuilding,
                      metalCost = unitDef.metalCost or 0,
                      buildSpeed = unitDef.buildSpeed or 0
                    }
                    unitDefCache[unitDefID] = cachedDef
                  end
                end

                if cachedDef then
                  local health, maxHealth, _, _, buildProgress = Spring.GetUnitHealth(uID)
                  local isBuilt = not buildProgress or buildProgress >= 1.0

                  if isBuilt then
                    -- 1. Threat calculation (combat units only, for any team)
                    if cachedDef.category == "combat" and team then
                      teamThreats[team] = (teamThreats[team] or 0) + cachedDef.metalCost
                    end

                    -- 2. Detail serialization (ONLY for local player's own units to save CPU/GC)
                    if team == myTeamId then
                      local x, y, z = Spring.GetUnitPosition(uID)
                      
                      -- Command queue safely
                      local cmdQueue = Spring.GetUnitCommands(uID, 1)
                      local currentCmd = "Idle"
                      if cmdQueue and #cmdQueue > 0 and cmdQueue[1] then
                        currentCmd = cmdQueue[1].name or tostring(cmdQueue[1].id or "Action")
                      end

                      table.insert(data.units, {
                        unitId = uID,
                        defName = cachedDef.defName,
                        humanName = cachedDef.humanName,
                        position = { x = x or 0, y = y or 0, z = z or 0 },
                        health = health or 0,
                        maxHealth = maxHealth or 1,
                        team = team,
                        command = currentCmd,
                        isBuilding = cachedDef.isBuilding,
                        category = cachedDef.category,
                        techLevel = cachedDef.techLevel,
                        metalCost = cachedDef.metalCost,
                        buildSpeed = cachedDef.buildSpeed
                      })
                    end
                  end
                end
              end
            end
          end
        end

        -- Merge threat ratings into teams list
        if data.teams then
          for tIDStr, teamData in pairs(data.teams) do
            local tID = tonumber(tIDStr)
            teamData.threat = tID and teamThreats[tID] or 0
          end
        end

        -- 8. Selected Units list
        data.selectedUnits = {}
        local selected = Spring.GetSelectedUnits()
        if selected then
          for i = 1, #selected do
            if selected[i] then
              table.insert(data.selectedUnits, selected[i])
            end
          end
        end

        -- 9. Chat/Console log history
        data.console = consoleHistory

        -- Serialize to JSON
        local json_body = to_json(data)
        local response = "HTTP/1.1 200 OK\r\n" ..
                         "Content-Type: application/json\r\n" ..
                         "Access-Control-Allow-Origin: *\r\n" ..
                         "Content-Length: " .. string.len(json_body) .. "\r\n" ..
                         "Connection: close\r\n\r\n" ..
                         json_body
        client:send(response)
      else
        local response = "HTTP/1.1 405 Method Not Allowed\r\n" ..
                         "Connection: close\r\n\r\n"
        client:send(response)
      end
    end
    client:close()
  end
end
