local version = "1.0.0"

function widget:GetInfo()
  return {
    name      = "HTTP API Server",
    desc      = "Exposes a local HTTP server on port 8540 with JSON endpoints for game state",
    author    = "Antigravity",
    date      = "2026",
    license   = "MIT",
    layer     = 0,
    enabled   = true
  }
end

local socket = require("socket")
local server

local function json_escape(str)
  if not str then return '""' end
  local escaped = str:gsub('\\', '\\\\')
                     :gsub('"', '\\"')
                     :gsub('\n', '\\n')
                     :gsub('\r', '\\r')
                     :gsub('\t', '\\t')
                     :gsub('\b', '\\b')
                     :gsub('\f', '\\f')
  escaped = escaped:gsub('[%c]', '')
  return '"' .. escaped .. '"'
end

-- Simple Lua-to-JSON encoder helper to keep the widget self-contained and dependency-free.
local function to_json(val)
  local t = type(val)
  if t == "number" then
    return tostring(val)
  elseif t == "boolean" then
    return val and "true" or "false"
  elseif t == "string" then
    return json_escape(val)
  elseif t == "table" then
    -- Check if it's an array
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
      is_array = false -- holes in array -> treat as dictionary
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

local lastInitAttemptTime = 0

local function InitializeServer()
  if server then return true end

  -- Delay initialization until player is fully loaded in-game to prevent socket conflicts on Windows during loading screen reloads
  local myPlayerID = Spring.GetMyPlayerID()
  if not myPlayerID or myPlayerID < 0 then
    return false
  end

  if not socket then
    Spring.Echo("HTTP API Server: ERROR - socket library not available")
    return false
  end

  -- Bind to localhost:8540
  local err
  server, err = socket.bind("127.0.0.1", 8540)
  if not server then
    Spring.Echo("HTTP API Server: ERROR - Failed to bind to 127.0.0.1:8540")
    return false
  end
  server:settimeout(0) -- Set to non-blocking
  Spring.Echo("HTTP API Server: Successfully started on http://127.0.0.1:8540")
  return true
end

function widget:Initialize()
  Spring.Echo("HTTP API Server: Initializing server...")
  InitializeServer()
end

function widget:Shutdown()
  if server then
    server:close()
    Spring.Echo("HTTP API Server: Stopped")
    server = nil
  end
end

function widget:Update()
  if not server then
    local now = os.clock()
    if now - lastInitAttemptTime > 5 then
      lastInitAttemptTime = now
      Spring.Echo("HTTP API Server: Server not running, retrying initialization...")
      InitializeServer()
    end
    if not server then return end
  end

  -- Accept incoming connections (non-blocking)
  local client, err = server:accept()
  if client then
    client:settimeout(0.01) -- Minimal timeout for receiving headers to prevent blocking the game thread
    local request, err = client:receive()
    
    if request then
      local method, path = request:match("^(%a+)%s+(%S+)%s+HTTP")
      
      if method == "GET" then
        local data = {}

        -- 1. Game general state
        data.game = {
          frame = Spring.GetGameFrame(),
          seconds = Spring.GetGameSeconds(),
          speed = Spring.GetGameSpeed(),
          paused = Spring.GetGameSpeed() == 0,
        }

        -- 2. Local player/team contexts
        local myPlayerID = Spring.GetMyPlayerID()
        local myTeamID = Spring.GetMyTeamID()
        local myAllyTeamID = Spring.GetMyAllyTeamID()
        
        data.localPlayer = {
          playerId = myPlayerID,
          teamId = myTeamID,
          allyTeamId = myAllyTeamID,
        }

        -- 3. Resources of the local team
        if myTeamID then
          local ms, md, me, mi, mo, mp = Spring.GetTeamResources(myTeamID, "metal")
          local es, ed, ee, ei, eo, ep = Spring.GetTeamResources(myTeamID, "energy")
          data.resources = {
            metal = { storage = ms, capacity = md, excess = me, income = mi, expense = mo, pull = mp },
            energy = { storage = es, capacity = ed, excess = ee, income = ei, expense = eo, pull = ep },
          }
        end

        -- 4. Environment data (Wind)
        local windMin, windMax, windCurrent = Spring.GetWind()
        data.environment = {
          wind = { min = windMin, max = windMax, current = windCurrent },
        }

        -- 5. Players list
        data.players = {}
        local playerList = Spring.GetPlayerList()
        if playerList then
          for _, pID in ipairs(playerList) do
            local name, active, spectator, teamID, allyTeamID, ping, cpu = Spring.GetPlayerInfo(pID)
            data.players[tostring(pID)] = {
              name = name,
              active = active,
              spectator = spectator,
              teamId = teamID,
              allyTeamId = allyTeamID,
              ping = ping,
              cpu = cpu
            }
          end
        end

        -- 6. Selected Units info
        data.selectedUnits = {}
        local selected = Spring.GetSelectedUnits()
        if selected then
          for _, uID in ipairs(selected) do
            local unitDefID = Spring.GetUnitDefID(uID)
            local unitDef = unitDefID and UnitDefs[unitDefID]
            local x, y, z = Spring.GetUnitPosition(uID)
            local health, maxHealth = Spring.GetUnitHealth(uID)
            
            table.insert(data.selectedUnits, {
              unitId = uID,
              defName = unitDef and unitDef.name or "unknown",
              humanName = unitDef and unitDef.humanName or "unknown",
              position = { x = x, y = y, z = z },
              health = health,
              maxHealth = maxHealth,
              team = Spring.GetUnitTeam(uID)
            })
          end
        end

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
