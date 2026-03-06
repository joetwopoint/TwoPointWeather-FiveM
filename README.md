████████╗██╗    ██╗ ██████╗ ██████╗  ██████╗ ██╗███╗   ██╗████████╗
╚══██╔══╝██║    ██║██╔═══██╗██╔══██╗██╔═══██╗██║████╗  ██║╚══██╔══╝
   ██║   ██║ █╗ ██║██║   ██║██████╔╝██║   ██║██║██╔██╗ ██║   ██║   
   ██║   ██║███╗██║██║   ██║██╔═══╝ ██║   ██║██║██║╚██╗██║   ██║   
   ██║   ╚███╔███╔╝╚██████╔╝██║     ╚██████╔╝██║██║ ╚████║   ██║   
   ╚═╝    ╚══╝╚══╝  ╚═════╝ ╚═╝      ╚═════╝ ╚═╝╚═╝  ╚═══╝   ╚═╝   
       TwoPoint Development

# TwoPoint_WeatherSync (v1.3.0)

✅ **Weather synced for everyone**  
✅ **Time synced for everyone** (server-authority, configurable speed)  
✅ Choose between:
- **REAL weather** from any location worldwide (default: Tucson, AZ)
- **GTA weather cycles** (server-controlled “vanilla-like” cycling, fully synced)

---

## Install
1) Drop `TwoPoint_WeatherSync` into your server `resources/` folder
2) Add to `server.cfg`:
```cfg
ensure TwoPoint_WeatherSync
```
3) Restart server (or `restart TwoPoint_WeatherSync`)

---

## Commands
- `/wx` — prints current synced weather to chat  
- `/twopoint_wx` — alias (backwards compatible)
- `/weather` — opens the Forecast UI (close with **X** or **ESC**)
- `/twopoint_time` — prints current synced game time + speed
- `/twopoint_settime <hour> <minute> [second]` — set synced time (ACE-gated)

### ACE permission for /twopoint_settime
```cfg
add_ace group.admin "twopoint.weather.admin" allow
```

---

## Weather mode (REAL vs GTA cycles)

Edit: `TwoPoint_WeatherSync/shared/config.lua`

### Option A: REAL weather (anywhere in the world)
```lua
Config.Weather.Mode = "REAL"
Config.Weather.Real.Latitude  = 32.2226
Config.Weather.Real.Longitude = -110.9747
Config.Weather.Real.UpdateIntervalMinutes = 10
```

### Option B: GTA weather cycles (fully synced)
```lua
Config.Weather.Mode = "GTA"
Config.Weather.Gta.Preset = "VANILLA_LIKE" -- or "DESERT", "STORMY", "CUSTOM"
Config.Weather.Gta.MinDurationMinutes = 15
Config.Weather.Gta.MaxDurationMinutes = 60
Config.Weather.Gta.AvoidRepeats = true
```

#### Presets
- `VANILLA_LIKE` — mostly clear with occasional clouds/rain
- `DESERT` — extra sunny / clear most of the time (Arizona vibe)
- `STORMY` — frequent rain/thunder
- `CUSTOM` — you control exact weights

#### Custom weights (Preset = "CUSTOM")
Higher number = more likely.
```lua
Config.Weather.Gta.Preset = "CUSTOM"
Config.Weather.Gta.Weights = {
  EXTRASUNNY = 40,
  CLEAR      = 30,
  CLOUDS     = 20,
  OVERCAST   = 8,
  RAIN       = 2,
  THUNDER    = 0,
  SNOW       = 0,
  BLIZZARD   = 0,
}
```

---

## REAL weather mapping (Open-Meteo -> GTA weather)
If you use `Mode = "REAL"`, the script maps Open‑Meteo weather codes to GTA weather types.

Edit this table:
`TwoPoint_WeatherSync/shared/config.lua` → `Config.OpenMeteoCodeToGTA`

Example (make it “less rainy”):
```lua
-- change drizzle/rain codes to CLOUDS instead of RAIN
Config.OpenMeteoCodeToGTA[51] = "CLOUDS"
Config.OpenMeteoCodeToGTA[53] = "CLOUDS"
Config.OpenMeteoCodeToGTA[55] = "OVERCAST"
```

---

## Time sync (NOT tied to IRL)
Edit: `TwoPoint_WeatherSync/shared/config.lua` → `Config.Time`

- `StartHour/StartMinute/StartSecond` — start time on resource start
- `GameMinutesPerRealMinute` — speed of time

Examples:
- `2`  → 24 in-game hours in **12** real hours  
- `4`  → 24 in-game hours in **6** real hours  
- `10` → 24 in-game hours in **2.4** real hours

---

## Notes / conflicts
If you run other scripts that force time/weather (vSync, qb-weathersync, cd_easytime, etc.), disable their time/weather features or remove them — otherwise they will fight this resource.

#### Weather blacklist (skip specific types)
In **GTA** cycle mode you can prevent certain weather types from ever being selected.

Edit `shared/config.lua`:
```lua
Config.Weather.Mode = "GTA"
Config.Weather.Gta.Blacklist = {
  "RAIN",
  "THUNDER",
  "XMAS",
}
```
If you blacklist everything by mistake, the script will fall back to a safe default (CLEAR/EXTRASUNNY/etc.).
