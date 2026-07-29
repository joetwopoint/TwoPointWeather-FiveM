-- TwoPointWeather LB Phone compatibility layer
-- Built and maintained by TwoPoint Development.

local RESOURCE = GetCurrentResourceName()
local latestPhoneData = nil

local weatherLabels = {
    EXTRASUNNY = 'Sunny',
    CLEAR = 'Clear',
    CLOUDS = 'Cloudy',
    OVERCAST = 'Overcast',
    SMOG = 'Smog',
    FOGGY = 'Foggy',
    RAIN = 'Rain',
    THUNDER = 'Thunderstorms',
    CLEARING = 'Clearing',
    NEUTRAL = 'Mild',
    SNOW = 'Snow',
    BLIZZARD = 'Blizzard',
    SNOWLIGHT = 'Light snow',
    XMAS = 'Snow',
    HALLOWEEN = 'Eerie fog'
}

local weatherTemperatureOffsets = {
    EXTRASUNNY = 7,
    CLEAR = 4,
    CLOUDS = 1,
    OVERCAST = -1,
    SMOG = 3,
    FOGGY = -2,
    RAIN = -4,
    THUNDER = -6,
    CLEARING = -1,
    NEUTRAL = 0,
    SNOW = -18,
    BLIZZARD = -23,
    SNOWLIGHT = -15,
    XMAS = -17,
    HALLOWEEN = -5
}

local function getDisplayWeather(weatherData)
    if not weatherData.transition then
        return weatherData.current
    end

    if (weatherData.transition.progress or 0) >= 0.5 then
        return weatherData.transition.toWeather
    end

    return weatherData.transition.fromWeather
end

local function calculateTemperature(weatherType, gameMinutes)
    local base = tonumber(Config.LBPhone.BaseTemperatureC) or 23
    local hour = (gameMinutes or 720) / 60.0

    -- Coolest before sunrise, warmest in the afternoon.
    local dayCurve = math.sin(((hour - 8.0) / 24.0) * math.pi * 2.0) * 5.0
    local offset = weatherTemperatureOffsets[weatherType] or 0
    return math.floor(base + dayCurve + offset + 0.5)
end

local function buildPhoneData(payload)
    local timeMinutes = payload.time.currentMinutes or 720
    local displayWeather = getDisplayWeather(payload.weather)
    local forecast = {}

    for i = 1, #(payload.weather.forecast or {}) do
        local entry = payload.weather.forecast[i]
        forecast[#forecast + 1] = {
            weather = entry.weather,
            label = weatherLabels[entry.weather] or entry.weather,
            temperatureC = calculateTemperature(entry.weather, timeMinutes),
            startsAt = entry.startsAt,
            durationSeconds = entry.durationSeconds
        }
    end

    return {
        weather = displayWeather,
        label = weatherLabels[displayWeather] or displayWeather,
        temperatureC = calculateTemperature(displayWeather, timeMinutes),
        timeMinutes = timeMinutes,
        dynamic = payload.weather.dynamicEnabled,
        transitioning = payload.weather.transition ~= nil,
        transition = payload.weather.transition,
        forecast = forecast
    }
end

local function handleWeatherUpdated(payload)
    if not Config.LBPhone.Enabled or not Config.LBPhone.ProvideCompatibilityData then
        return
    end

    latestPhoneData = buildPhoneData(payload)

    -- Public integration event for an editable LB Phone bridge or any custom
    -- weather UI. The stock Weather app generally follows the applied GTA
    -- weather directly and therefore does not require a setter export.
    TriggerEvent(RESOURCE .. ':lb-phone:updated', latestPhoneData)
    if RESOURCE ~= 'TwoPointWeather' then
        TriggerEvent('TwoPointWeather:lb-phone:updated', latestPhoneData)
    end
end

AddEventHandler(RESOURCE .. ':client:updated', handleWeatherUpdated)

exports('GetLBPhoneWeatherData', function()
    return latestPhoneData
end)

exports('GetWeatherLabel', function(weatherType)
    return weatherLabels[string.upper(tostring(weatherType or ''))]
end)
