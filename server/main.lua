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
--  WEATHER (Open-Meteo)
-- ===========================
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
  local url = buildOpenMeteoUrl(Config.Latitude, Config.Longitude)
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
      latitude = Config.Latitude,
      longitude = Config.Longitude,
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
  Wait(1500)
  fetchAndUpdateWeather()

  while true do
    Wait((Config.UpdateIntervalMinutes or 10) * 60 * 1000)
    fetchAndUpdateWeather()
  end
end)

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
