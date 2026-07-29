-- TwoPointWeather
-- Built and maintained by TwoPoint Development.

Config = {}

Config.Debug = false

-- ACE permission used by /weather and /time.
Config.AdminAce = 'TwoPointWeather.admin'

-- How often the server corrects every client's clock/weather state.
Config.SyncIntervalSeconds = 5
Config.AckTimeoutSeconds = 15

-- Client/server timer calibration compensates for packet latency so all clients
-- calculate the same transition progress and clock position.
Config.CalibrationIntervalSeconds = 30
Config.CalibrationSampleCount = 8


-- Re-apply authoritative client state regularly. This prevents GTA's local
-- cycle from drifting and makes conflicts with other time/weather resources
-- easier to identify.
Config.ClientTimeApplyIntervalMs = 50
Config.ClientWeatherApplyIntervalMs = 0
Config.ClientWeatherTransitionApplyIntervalMs = 0
Config.ClientWeatherFullResetIntervalMs = 2000
Config.ClientWeatherDiagnosticIntervalMs = 1000
Config.ClientAckIntervalMs = 2000
Config.WeatherProgressTolerance = 0.20

-- Own rain/snow intensity as well as the weather type. This prevents another
-- resource (or a character/interior script) from leaving rain or snow forced
-- to a different local value on only some clients.
Config.ForcePrecipitationLevels = true

-- Strict mode continuously owns the GTA clock/weather. External generic pause
-- events are ignored by default because they can silently desync individual players.
Config.StrictSync = true
Config.AllowExternalPauseEvents = false
Config.UseExactWeatherBlendNative = true

-- Warn in the server console when another commonly-used sync resource is
-- running at the same time. Two weather/time controllers will fight each other.
Config.WarnAboutConflictingResources = true
Config.KnownConflictingResources = {
    'qb-weathersync',
    'cd_easytime',
    'vSync',
    'vsync',
    'easytime',
    'Renewed-Weathersync',
    'renewed-weathersync',
    'nd-weathersync',
    'ps-weathersync',
    'esx_weathersync',
    'esx_weather',
    'okokWeather',
    'av_weather',
    'wasabi_weather',
    'weathersync'
}

-- Default smooth transition duration for admin commands.
Config.CommandTransitionSeconds = 60

Config.Time = {
    StartHour = 8,
    StartMinute = 0,

    -- Number of in-game minutes that pass per real-world minute.
    MinutesPerRealMinute = 2.0,

    Frozen = false,
    TransitionSeconds = 60
}

Config.Dynamic = {
    Enabled = true,
    InitialWeather = 'CLEAR',

    -- How long a settled dynamic weather state lasts in real minutes.
    MinDurationMinutes = 15,
    MaxDurationMinutes = 35,

    TransitionSeconds = 60,

    -- After an admin manually sets weather, dynamic weather waits this many
    -- real minutes before taking over again. Set to 0 for immediate resume.
    ManualHoldMinutes = 30,

    -- Number of future entries made available through exports/events.
    ForecastLength = 6
}

Config.LBPhone = {
    Enabled = true,
    ResourceName = 'lb-phone',

    -- The stock LB Phone Weather app normally reads the actual client GTA
    -- weather, so applying the synchronized weather updates it naturally.
    -- This resource also exposes GetLBPhoneWeatherData for phone builds or
    -- custom bridges that want explicit current/forecast data.
    ProvideCompatibilityData = true,

    -- Base temperature is adjusted by weather and time of day.
    BaseTemperatureC = 23
}

Config.ValidWeather = {
    EXTRASUNNY = true,
    CLEAR = true,
    CLOUDS = true,
    OVERCAST = true,
    SMOG = true,
    FOGGY = true,
    RAIN = true,
    THUNDER = true,
    CLEARING = true,
    NEUTRAL = true,
    SNOW = true,
    BLIZZARD = true,
    SNOWLIGHT = true,
    XMAS = true,
    HALLOWEEN = true
}

-- Weighted Markov-style dynamic weather transitions. This avoids unrealistic
-- jumps such as EXTRASUNNY directly into BLIZZARD during normal operation.
Config.WeatherTransitions = {
    EXTRASUNNY = {
        { weather = 'EXTRASUNNY', weight = 30 },
        { weather = 'CLEAR', weight = 45 },
        { weather = 'CLOUDS', weight = 20 },
        { weather = 'SMOG', weight = 5 }
    },
    CLEAR = {
        { weather = 'EXTRASUNNY', weight = 20 },
        { weather = 'CLEAR', weight = 35 },
        { weather = 'CLOUDS', weight = 30 },
        { weather = 'OVERCAST', weight = 10 },
        { weather = 'SMOG', weight = 5 }
    },
    CLOUDS = {
        { weather = 'CLEAR', weight = 25 },
        { weather = 'CLOUDS', weight = 30 },
        { weather = 'OVERCAST', weight = 30 },
        { weather = 'FOGGY', weight = 5 },
        { weather = 'RAIN', weight = 10 }
    },
    OVERCAST = {
        { weather = 'CLOUDS', weight = 25 },
        { weather = 'OVERCAST', weight = 25 },
        { weather = 'CLEARING', weight = 15 },
        { weather = 'RAIN', weight = 25 },
        { weather = 'THUNDER', weight = 10 }
    },
    RAIN = {
        { weather = 'OVERCAST', weight = 20 },
        { weather = 'RAIN', weight = 25 },
        { weather = 'THUNDER', weight = 15 },
        { weather = 'CLEARING', weight = 40 }
    },
    THUNDER = {
        { weather = 'THUNDER', weight = 15 },
        { weather = 'RAIN', weight = 40 },
        { weather = 'CLEARING', weight = 45 }
    },
    CLEARING = {
        { weather = 'CLEARING', weight = 15 },
        { weather = 'CLOUDS', weight = 30 },
        { weather = 'CLEAR', weight = 45 },
        { weather = 'EXTRASUNNY', weight = 10 }
    },
    SMOG = {
        { weather = 'SMOG', weight = 25 },
        { weather = 'FOGGY', weight = 15 },
        { weather = 'CLOUDS', weight = 30 },
        { weather = 'CLEAR', weight = 30 }
    },
    FOGGY = {
        { weather = 'FOGGY', weight = 25 },
        { weather = 'SMOG', weight = 15 },
        { weather = 'CLOUDS', weight = 35 },
        { weather = 'OVERCAST', weight = 25 }
    },
    NEUTRAL = {
        { weather = 'CLEAR', weight = 50 },
        { weather = 'CLOUDS', weight = 50 }
    },
    SNOW = {
        { weather = 'SNOW', weight = 35 },
        { weather = 'SNOWLIGHT', weight = 35 },
        { weather = 'BLIZZARD', weight = 10 },
        { weather = 'XMAS', weight = 20 }
    },
    SNOWLIGHT = {
        { weather = 'SNOWLIGHT', weight = 35 },
        { weather = 'SNOW', weight = 30 },
        { weather = 'CLEARING', weight = 20 },
        { weather = 'XMAS', weight = 15 }
    },
    BLIZZARD = {
        { weather = 'BLIZZARD', weight = 15 },
        { weather = 'SNOW', weight = 45 },
        { weather = 'SNOWLIGHT', weight = 40 }
    },
    XMAS = {
        { weather = 'XMAS', weight = 35 },
        { weather = 'SNOW', weight = 35 },
        { weather = 'SNOWLIGHT', weight = 30 }
    },
    HALLOWEEN = {
        { weather = 'HALLOWEEN', weight = 40 },
        { weather = 'FOGGY', weight = 30 },
        { weather = 'OVERCAST', weight = 30 }
    }
}
