local function dbg(msg)
  if Config.Debug then
    print(('[TwoPoint_WeatherSync] %s'):format(msg))
  end
end

-- ===========================
--  HELPERS
-- ===========================
local function clampDaySeconds(s)
  s = s % 86400
  if s < 0 then s = s + 86400 end
  return s
end

local function hmsFromDaySeconds(s)
  s = clampDaySeconds(s)
  local h = math.floor(s / 3600)
  local m = math.floor((s % 3600) / 60)
  local sec = math.floor(s % 60)
  return h, m, sec
end

-- ===========================
--  WEATHER (Mode: REAL or GTA cycles)
-- ===========================
local function getWeatherMode()
  local w = Config.Weather or {}
  local mode = w.Mode or w.mode or 'REAL'
  mode = tostring(mode):upper()
  if mode ~= 'REAL' and mode ~= 'GTA' then mode = 'REAL' end
  return mode
end

local function getRealLatLon()
  local w = Config.Weather or {}
  local r = w.Real or {}
  local lat = r.Latitude or Config.Latitude or 32.2226
  local lon = r.Longitude or Config.Longitude or -110.9747
  return lat, lon
end

local function getRealUpdateIntervalMinutes()
  local w = Config.Weather or {}
  local r = w.Real or {}
  return tonumber(r.UpdateIntervalMinutes or Config.UpdateIntervalMinutes or 10) or 10
end

local function getGtaCycleConfig()
  local w = Config.Weather or {}
  return w.Gta or {}
end

local function resolveGtaWeights()
  local g = getGtaCycleConfig()
  local preset = tostring(g.Preset or 'VANILLA_LIKE'):upper()
  if preset ~= 'CUSTOM' then
    local presets = Config.WeatherPresets or {}
    return presets[preset] or g.Weights or {}
  end
  return g.Weights or {}
end


local function getBlacklistSet()
  local g = getGtaCycleConfig()
  local bl = g.Blacklist
  local set = {}
  if type(bl) == 'table' then
    for k, v in pairs(bl) do
      if type(k) == 'number' then
        if type(v) == 'string' then set[tostring(v):upper()] = true end
      elseif type(k) == 'string' then
        if v == true or v == 1 then set[tostring(k):upper()] = true end
      end
    end
  end
  return set
end

local function filterWeightsByBlacklist(weights, blacklist)
  if not blacklist or next(blacklist) == nil then return weights or {} end
  local out = {}
  for k, v in pairs(weights or {}) do
    local key = tostring(k):upper()
    if not blacklist[key] then out[key] = v end
  end
  return out
end

local function pickFallbackWeather(blacklist)
  local candidates = { 'CLEAR', 'EXTRASUNNY', 'CLOUDS', 'OVERCAST', 'SMOG', 'FOGGY', 'RAIN', 'THUNDER' }
  for _, w in ipairs(candidates) do
    if not (blacklist and blacklist[w]) then return w end
  end
  return Config.DefaultGTAWeather or 'CLEAR'
end

local function weightedPick(weights)
  local total = 0
  for _, v in pairs(weights or {}) do
    local n = tonumber(v) or 0
    if n > 0 then total = total + n end
  end
  if total <= 0 then return Config.DefaultGTAWeather end

  local roll = math.random() * total
  local acc = 0
  for k, v in pairs(weights) do
    local n = tonumber(v) or 0
    if n > 0 then
      acc = acc + n
      if roll <= acc then return tostring(k) end
    end
  end
  return Config.DefaultGTAWeather
end

local function clampInt(v, lo, hi)
  v = tonumber(v) or lo
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function randomDurationSeconds()
  local g = getGtaCycleConfig()
  local minM = clampInt(g.MinDurationMinutes or 15, 1, 1440)
  local maxM = clampInt(g.MaxDurationMinutes or 60, minM, 1440)
  local durM = math.random(minM, maxM)
  return durM * 60
end

-- Current weather state (used for both REAL and GTA modes)

local currentWeather = Config.DefaultGTAWeather
local currentWeatherMeta = {
  source = 'boot',
  weatherCode = nil,
  temperatureF = nil,
  windSpeedMph = nil,
  fetchedAt = os.time(),
}

local function buildOpenMeteoUrl(lat, lon)
  return ('https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current_weather=true&temperature_unit=fahrenheit&windspeed_unit=mph&timezone=auto')
    :format(tostring(lat), tostring(lon))
end

local function mapWeatherCodeToGTA(code)
  local mapped = Config.OpenMeteoCodeToGTA[tonumber(code or -1)]
  return mapped or Config.DefaultGTAWeather
end

local function broadcastWeather(target)
  TriggerClientEvent('TwoPoint_WeatherSync:client:setWeather', target or -1, currentWeather, Config.WeatherTransitionMinutes, currentWeatherMeta)
end

local function fetchAndUpdateWeather()
  local lat, lon = getRealLatLon()
  local url = buildOpenMeteoUrl(lat, lon)
  dbg(('Fetching weather: %s'):format(url))

  PerformHttpRequest(url, function(status, body)
    if status ~= 200 or not body or body == '' then
      dbg(('Weather fetch failed (status=%s)'):format(tostring(status)))
      return
    end

    local ok, data = pcall(function() return json.decode(body) end)
    if not ok or not data then
      dbg('Weather decode failed')
      return
    end

    local cw = data.current_weather
    if not cw then
      dbg('Weather payload missing current_weather')
      return
    end

    local weatherCode = cw.weathercode
    local gtaWeather = mapWeatherCodeToGTA(weatherCode)

    currentWeather = gtaWeather
    currentWeatherMeta = {
      source = 'open-meteo',
      latitude = lat,
      longitude = lon,
      fetchedAt = os.time(),
      localTime = cw.time, -- e.g. "2026-01-01T09:10"
      temperatureF = cw.temperature,
      windSpeedMph = cw.windspeed,
      windDirection = cw.winddirection,
      weatherCode = weatherCode,
    }

    dbg(('Weather updated: code=%s -> %s'):format(tostring(weatherCode), tostring(gtaWeather)))
    broadcastWeather(-1)
  end, 'GET')
end

-- ===========================
--  WEATHER (GTA cycles)
-- ===========================
local gtaNextChangeAt = 0
local nextRealFetchAt = 0

local function setWeatherState(newWeather, meta)
  if not newWeather or newWeather == '' then return end
  currentWeather = tostring(newWeather)
  currentWeatherMeta = meta or {
    source = 'unknown',
    fetchedAt = os.time(),
  }
  broadcastWeather(-1)
end

local function tickGtaCycle()
  local now = os.time()
  if now < gtaNextChangeAt then return end

  local g = getGtaCycleConfig()
  local blacklist = getBlacklistSet()
  local weights = filterWeightsByBlacklist(resolveGtaWeights(), blacklist)
  local picked = weightedPick(weights)

  if blacklist[tostring(picked):upper()] then
    picked = pickFallbackWeather(blacklist)
  end

  if (g.AvoidRepeats == nil or g.AvoidRepeats == true) and picked == currentWeather then
    -- Try a few times to avoid repeats
    for _ = 1, 5 do
      local again = weightedPick(weights)
      if not blacklist[tostring(again):upper()] and again ~= currentWeather then
        picked = again
        break
      end
    end
  end

  local dur = randomDurationSeconds()
  gtaNextChangeAt = now + dur

  setWeatherState(picked, {
    source = 'gta-cycle',
    preset = tostring((g.Preset or 'VANILLA_LIKE')):upper(),
    pickedAt = now,
    nextChangeAt = gtaNextChangeAt,
    durationSeconds = dur,
  })

  dbg(('GTA cycle weather -> %s (next change in %ss)'):format(tostring(picked), tostring(dur)))
end

local function tickRealWeather()
  local now = os.time()
  if now < nextRealFetchAt then return end

  local intervalMin = getRealUpdateIntervalMinutes()
  nextRealFetchAt = now + (intervalMin * 60)
  fetchAndUpdateWeather()
end

-- Kick the scheduler immediately on resource start
CreateThread(function()
  Wait(1500)

  -- Seed RNG for cycle mode
  math.randomseed(os.time() + math.floor(math.random()*100000))

  local mode = getWeatherMode()
  dbg(('Weather mode: %s'):format(mode))

  if mode == 'REAL' then
    nextRealFetchAt = 0
    tickRealWeather()
  else
    gtaNextChangeAt = 0
    tickGtaCycle()
  end

  while true do
    Wait(1000)

    mode = getWeatherMode()
    if mode == 'REAL' then
      tickRealWeather()
    else
      tickGtaCycle()
    end
  end
end)

-- ===========================
--  TIME (Synced, NOT IRL)
-- ===========================
local timeEnabled = Config.Time and Config.Time.Enabled
local gmprm = (Config.Time and Config.Time.GameMinutesPerRealMinute) or 4
local gsecsPerRealSec = gmprm -- 1 real second -> gmprm game seconds
local currentDaySeconds = clampDaySeconds(
  ((Config.Time.StartHour or 12) * 3600) +
  ((Config.Time.StartMinute or 0) * 60) +
  (Config.Time.StartSecond or 0)
)

local lastTimeBroadcast = 0

local function broadcastTimeAnchor(target)
  if not timeEnabled then return end
  -- Send an anchor (server day seconds + server unix time) so clients can simulate smoothly.
  TriggerClientEvent('TwoPoint_WeatherSync:client:setTimeAnchor', target or -1, currentDaySeconds, os.time())
end

local function setTime(h, m, s)
  h = tonumber(h) or 0
  m = tonumber(m) or 0
  s = tonumber(s) or 0
  if h < 0 then h = 0 elseif h > 23 then h = 23 end
  if m < 0 then m = 0 elseif m > 59 then m = 59 end
  if s < 0 then s = 0 elseif s > 59 then s = 59 end

  currentDaySeconds = clampDaySeconds(h * 3600 + m * 60 + s)
  broadcastTimeAnchor(-1)
end

-- Client sync request on spawn
RegisterNetEvent('TwoPoint_WeatherSync:server:requestSync', function()
  local src = source
  broadcastWeather(src)
  broadcastTimeAnchor(src)
end)

-- Commands
RegisterCommand('wx', function(source)
  TriggerClientEvent('TwoPoint_WeatherSync:client:showWeather', source, currentWeather, currentWeatherMeta)
end, false)

-- Backwards-compatible alias
RegisterCommand('twopoint_wx', function(source)
  TriggerClientEvent('TwoPoint_WeatherSync:client:showWeather', source, currentWeather, currentWeatherMeta)
end, false)

RegisterCommand('twopoint_time', function(source)
  local h, m, s = hmsFromDaySeconds(currentDaySeconds)
  TriggerClientEvent('TwoPoint_WeatherSync:client:showTime', source, h, m, s, gmprm)
end, false)

RegisterCommand('twopoint_settime', function(source, args)
  local src = source
  if src ~= 0 then
    local ace = (Config.Time and Config.Time.AdminAce) or 'twopoint.weather.admin'
    if not IsPlayerAceAllowed(src, ace) then
      TriggerClientEvent('chat:addMessage', src, { args = { '^1TwoPoint', 'No permission.' } })
      return
    end
  end

  local h = tonumber(args[1])
  local m = tonumber(args[2])
  local s = tonumber(args[3] or 0)

  if h == nil or m == nil then
    local usage = 'Usage: /twopoint_settime <hour 0-23> <minute 0-59> [second 0-59]'
    if src ~= 0 then
      TriggerClientEvent('chat:addMessage', src, { args = { '^3TwoPoint', usage } })
    else
      print(usage)
    end
    return
  end

  setTime(h, m, s)
end, false)

-- Threads

CreateThread(function()
  if not timeEnabled then return end

  local broadcastEvery = (Config.Time.BroadcastIntervalSeconds or 5)
  -- IMPORTANT: In Lua, a function call only expands multiple return values when it is
  -- the *last* expression in an argument list. So we must capture h/m/s first.
  if Config.Debug then
    local sh, sm, ss = hmsFromDaySeconds(currentDaySeconds)
    dbg(('Time sync enabled: start=%02d:%02d:%02d speed=%s gm/min broadcast=%ss'):format(
      sh, sm, ss, tostring(gmprm), tostring(broadcastEvery)
    ))
  end

  while true do
    Wait(1000)

    -- Advance server-authority clock
    currentDaySeconds = clampDaySeconds(currentDaySeconds + gsecsPerRealSec)

    -- Broadcast anchor periodically
    local now = os.time()
    if now - lastTimeBroadcast >= broadcastEvery then
      lastTimeBroadcast = now
      broadcastTimeAnchor(-1)
    end
  end
end)