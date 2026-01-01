Config = {}

-- ===========================
--  BRANDING / LOGGING
-- ===========================
Config.Debug = false

-- ===========================
--  REAL WEATHER SOURCE
-- ===========================
-- Tucson, Arizona (downtown-ish)
Config.Latitude  = 32.2226
Config.Longitude = -110.9747

-- Refresh real-world weather every X minutes
Config.UpdateIntervalMinutes = 10

-- Smooth transition time when changing weather (minutes)
Config.WeatherTransitionMinutes = 2

-- If a code isn't mapped, fall back to this GTA weather type
Config.DefaultGTAWeather = 'CLEAR'

-- ===========================
--  TIME SYNC (SERVER-AUTHORITY)
-- ===========================
Config.Time = {
  Enabled = true,

  -- Starting time at server/resource start (24h clock)
  StartHour = 12,
  StartMinute = 0,
  StartSecond = 0,

  -- How fast in-game time advances:
  -- Example: 2 = 2 in-game minutes per real minute (24h cycle in 12 real hours)
  GameMinutesPerRealMinute = 4,

  -- How often the server broadcasts a sync anchor (seconds).
  -- Clients simulate smoothly between broadcasts using the same speed.
  BroadcastIntervalSeconds = 5,

  -- Optional admin ACE permission for /twopoint_settime
  -- Grant like: add_ace group.admin "twopoint.weather.admin" allow
  AdminAce = 'twopoint.weather.admin'
}

-- ===========================
--  OPEN-METEO WEATHER CODE -> GTA WEATHER MAP
--  Open-Meteo codes reference: https://open-meteo.com/en/docs
-- ===========================
Config.OpenMeteoCodeToGTA = {
  [0]  = 'CLEAR',      -- Clear sky
  [1]  = 'EXTRASUNNY', -- Mainly clear
  [2]  = 'CLOUDS',     -- Partly cloudy
  [3]  = 'OVERCAST',   -- Overcast

  [45] = 'FOGGY',      -- Fog
  [48] = 'FOGGY',      -- Depositing rime fog

  [51] = 'RAIN',       -- Drizzle (light)
  [53] = 'RAIN',       -- Drizzle (moderate)
  [55] = 'RAIN',       -- Drizzle (dense)

  [56] = 'RAIN',       -- Freezing drizzle
  [57] = 'RAIN',

  [61] = 'RAIN',       -- Rain (slight)
  [63] = 'RAIN',       -- Rain (moderate)
  [65] = 'RAIN',       -- Rain (heavy)

  [66] = 'RAIN',       -- Freezing rain
  [67] = 'RAIN',

  [71] = 'SNOWLIGHT',  -- Snow fall (slight)
  [73] = 'SNOW',       -- Snow fall (moderate)
  [75] = 'SNOW',       -- Snow fall (heavy)

  [77] = 'SNOWLIGHT',  -- Snow grains

  [80] = 'RAIN',       -- Rain showers (slight)
  [81] = 'RAIN',       -- Rain showers (moderate)
  [82] = 'RAIN',       -- Rain showers (violent)

  [85] = 'SNOWLIGHT',  -- Snow showers (slight)
  [86] = 'SNOW',       -- Snow showers (heavy)

  [95] = 'THUNDER',    -- Thunderstorm
  [96] = 'THUNDER',
  [99] = 'THUNDER',
}
