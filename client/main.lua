local currentWeather = nil
local currentWeatherMeta = nil

local uiOpen = false

local timeEnabled = Config.Time and Config.Time.Enabled
local gmprm = (Config.Time and Config.Time.GameMinutesPerRealMinute) or 4
local gsecsPerRealSec = gmprm

-- time anchor from server
local anchorDaySeconds = nil
local anchorServerUnix = nil
local anchorClientMs = nil

local function setWeatherNow(weather, transition)
  if not weather or weather == '' then return end
  transition = tonumber(transition) or 0

  ClearOverrideWeather()
  ClearWeatherTypePersist()

  if transition > 0 then
    -- native expects seconds
    SetWeatherTypeOvertimePersist(weather, transition * 60.0)
  else
    SetWeatherTypeNowPersist(weather)
    SetWeatherTypeNow(weather)
  end
end

local function applyClockFromDaySeconds(daySeconds)
  daySeconds = tonumber(daySeconds) or 0
  daySeconds = daySeconds % 86400
  if daySeconds < 0 then daySeconds = daySeconds + 86400 end

  local h = math.floor(daySeconds / 3600)
  local m = math.floor((daySeconds % 3600) / 60)
  local s = math.floor(daySeconds % 60)

  NetworkOverrideClockTime(h, m, s)
end

RegisterNetEvent('TwoPoint_WeatherSync:client:setWeather', function(weather, transitionMinutes, meta)
  currentWeather = weather
  currentWeatherMeta = meta
  setWeatherNow(weather, transitionMinutes)
end)

RegisterNetEvent('TwoPoint_WeatherSync:client:setTimeAnchor', function(daySeconds, serverUnix)
  if not timeEnabled then return end
  anchorDaySeconds = tonumber(daySeconds) or 0
  anchorServerUnix = tonumber(serverUnix) or 0
  anchorClientMs = GetGameTimer()

  applyClockFromDaySeconds(anchorDaySeconds)
end)

RegisterNetEvent('TwoPoint_WeatherSync:client:showWeather', function(weather, meta)
  local msg = ('Weather: %s'):format(tostring(weather))
  if meta and meta.temperatureF then
    msg = msg .. (' | Temp: %s°F | Wind: %s mph'):format(tostring(meta.temperatureF), tostring(meta.windSpeedMph))
  end
  TriggerEvent('chat:addMessage', { args = { '^2Forecast', msg } })
end)

RegisterNetEvent('TwoPoint_WeatherSync:client:showTime', function(h, m, s, speed)
  TriggerEvent('chat:addMessage', { args = { '^2TwoPoint', ('Time: %02d:%02d:%02d (speed: %s gm/min)'):format(
    tonumber(h) or 0, tonumber(m) or 0, tonumber(s) or 0, tostring(speed or gmprm)
  ) } })
end)

local function openForecastUI()
  uiOpen = true
  SetNuiFocus(true, true)
  SetNuiFocusKeepInput(true)

  local h = GetClockHours()
  local m = GetClockMinutes()
  local s = GetClockSeconds()

  SendNUIMessage({
    action = 'open',
    weather = currentWeather or 'UNKNOWN',
    meta = currentWeatherMeta or {},
    gameTime = { hour = h, minute = m, second = s },
  })
end

local function closeForecastUI()
  uiOpen = false
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)
  SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('tpwx_close', function(_, cb)
  closeForecastUI()
  cb({ ok = true })
end)

RegisterCommand('weather', function()
  if uiOpen then
    closeForecastUI()
  else
    openForecastUI()
  end
end, false)

CreateThread(function()
  -- Ask server for current state on join
  Wait(1500)
  TriggerServerEvent('TwoPoint_WeatherSync:server:requestSync')

  -- Smooth time simulation + lock
  while true do
    Wait(0)

    if timeEnabled and anchorDaySeconds ~= nil and anchorClientMs ~= nil then
      local elapsedRealSec = (GetGameTimer() - anchorClientMs) / 1000.0
      local predicted = anchorDaySeconds + (elapsedRealSec * gsecsPerRealSec)
      applyClockFromDaySeconds(predicted)
    end

    if uiOpen then
      DisableControlAction(0, 1, true)
      DisableControlAction(0, 2, true)
      DisableControlAction(0, 24, true)
      DisableControlAction(0, 25, true)
      DisableControlAction(0, 200, true)

      if IsControlJustPressed(0, 322) or IsControlJustPressed(0, 200) then
        closeForecastUI()
      end
    end
  end
end)
