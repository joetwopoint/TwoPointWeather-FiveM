Config = {}

-- ===========================
--  BRANDING / LOGGING
-- ===========================
Config.Debug = false

-- ===========================
--  WEATHER MODE
-- ===========================
-- "REAL" = Sync weather from a real-world location (anywhere)
-- "GTA"  = Server-controlled GTA-style weather cycles (fully synced for everyone, no API calls)
Config.Weather = {
  Mode = "REAL",

  -- Used only when Mode = "REAL"
  Real = {
    -- Default: Tucson, Arizona (downtown-ish)
    Latitude  = 32.2226,
    Longitude = -110.9747,

    -- Refresh real-world weather every X minutes
    UpdateIntervalMinutes = 10,
  },

  -- Used only when Mode = "GTA"
  Gta = {
    -- Presets: "VANILLA_LIKE", "DESERT", "STORMY", "CUSTOM"
    Preset = "VANILLA_LIKE",

    -- How long each weather lasts (server chooses + syncs to all)
    MinDurationMinutes = 15,
    MaxDurationMinutes = 60,

    -- Weather blacklist (skip these in GTA cycle mode)
    -- You can list any GTA weather types here, e.g. { "RAIN", "THUNDER", "SNOW" }
    -- Types: EXTRASUNNY, CLEAR, CLOUDS, OVERCAST, RAIN, THUNDER, SMOG, FOGGY, XMAS, SNOWLIGHT, BLIZZARD, etc.
    Blacklist = {
      -- "RAIN",
      -- "THUNDER",
      -- "XMAS",
    },

    -- Used only when Preset = "CUSTOM"
    -- Higher number = more likely
    Weights = {
      EXTRASUNNY = 30,
      CLEAR      = 30,
      CLOUDS     = 20,
      OVERCAST   = 10,
      RAIN       = 7,
      THUNDER    = 3,

      -- Tucson/Arizona vibe: keep these at 0 unless you really want them
      FOGGY      = 0,
      SNOWLIGHT  = 0,
      SNOW       = 0,
      BLIZZARD   = 0,
      XMAS       = 0,
    },

    -- If true, the cycle will try not to repeat the same weather twice in a row
    AvoidRepeats = true,
  }
}

-- Smooth transition time when changing weather (minutes)
Config.WeatherTransitionMinutes = 2

-- If a weather type isn't mapped, fall back to this GTA weather type
Config.DefaultGTAWeather = 'CLEAR'

-- Built-in preset weights (feel free to edit)
Config.WeatherPresets = {
  VANILLA_LIKE = {
    EXTRASUNNY = 30, CLEAR = 30, CLOUDS = 20, OVERCAST = 10, RAIN = 7, THUNDER = 3,
    FOGGY = 0, SMOG = 0, SNOWLIGHT = 0, SNOW = 0, BLIZZARD = 0, XMAS = 0
  },
  DESERT = {
    EXTRASUNNY = 45, CLEAR = 35, CLOUDS = 12, OVERCAST = 5, RAIN = 2, THUNDER = 1,
    FOGGY = 0, SMOG = 0, SNOWLIGHT = 0, SNOW = 0, BLIZZARD = 0, XMAS = 0
  },
  STORMY = {
    OVERCAST = 30, RAIN = 35, THUNDER = 20, CLOUDS = 10, CLEAR = 3, EXTRASUNNY = 2,
    FOGGY = 0, SMOG = 0, SNOWLIGHT = 0, SNOW = 0, BLIZZARD = 0, XMAS = 0
  },
}

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
