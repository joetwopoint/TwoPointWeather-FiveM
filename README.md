████████╗██╗    ██╗ ██████╗ ██████╗  ██████╗ ██╗███╗   ██╗████████╗
╚══██╔══╝██║    ██║██╔═══██╗██╔══██╗██╔═══██╗██║████╗  ██║╚══██╔══╝
   ██║   ██║ █╗ ██║██║   ██║██████╔╝██║   ██║██║██╔██╗ ██║   ██║   
   ██║   ██║███╗██║██║   ██║██╔═══╝ ██║   ██║██║██║╚██╗██║   ██║   
   ██║   ╚███╔███╔╝╚██████╔╝██║     ╚██████╔╝██║██║ ╚████║   ██║   
   ╚═╝    ╚══╝╚══╝  ╚═════╝ ╚═╝      ╚═════╝ ╚═╝╚═╝  ╚═══╝   ╚═╝   
       TwoPoint Development — Tucson Weather (IRL) + Time Sync (NOT IRL)

# TwoPoint_WeatherSync (v1.1.4)

✅ **Real-world Tucson, Arizona weather** synced to all players  
✅ **In-game time** synced to all players (server authority) and advances at your chosen speed  
❌ Time is **NOT** pulled from Tucson/real-world time (only weather is).

---

## Install
1) Drop `TwoPoint_WeatherSync` into your resources folder
2) Add to `server.cfg`:

```cfg
ensure TwoPoint_WeatherSync
```

---

## Commands
- `/wx` — shows the current synced weather in chat (prefix: **Forecast**)
- `/twopoint_time` — shows the current synced in-game time
- `/twopoint_settime <hour 0-23> <minute 0-59> [second 0-59]` — set the synced time (**ACE gated**)

Grant an admin group the ability to set time:

```cfg
add_ace group.admin "twopoint.weather.admin" allow
```

(You can change the ACE string in config: `Config.Time.AdminAce`)

---

## Config
Edit: `TwoPoint_WeatherSync/shared/config.lua`

### Change the real-world weather location
By default, the script uses Tucson, AZ coordinates:

```lua
Config.Latitude  = 32.2226
Config.Longitude = -110.9747
```

To use a different city, just replace those numbers.

### Change how often it refreshes real weather
```lua
Config.UpdateIntervalMinutes = 10
```

### Change how smooth the transition looks
```lua
Config.WeatherTransitionMinutes = 2
```

---

## Customizing the weather output (how to “change the weather”)
The script reads an Open‑Meteo **weather code** and converts it to a GTA weather type using:

```lua
Config.OpenMeteoCodeToGTA = {
  [0] = 'CLEAR',
  [1] = 'EXTRASUNNY',
  [2] = 'CLOUDS',
  -- etc...
}
```

If you want the server to “feel” different (more sunny, more cloudy, no rain, etc.), edit this mapping.

### Example: make Tucson ALWAYS sunny (while still synced)
Map all codes to one GTA weather type:

```lua
Config.OpenMeteoCodeToGTA = {
  [0]='EXTRASUNNY',[1]='EXTRASUNNY',[2]='EXTRASUNNY',[3]='EXTRASUNNY',
  [45]='EXTRASUNNY',[48]='EXTRASUNNY',
  [51]='EXTRASUNNY',[53]='EXTRASUNNY',[55]='EXTRASUNNY',
  [56]='EXTRASUNNY',[57]='EXTRASUNNY',
  [61]='EXTRASUNNY',[63]='EXTRASUNNY',[65]='EXTRASUNNY',
  [66]='EXTRASUNNY',[67]='EXTRASUNNY',
  [71]='EXTRASUNNY',[73]='EXTRASUNNY',[75]='EXTRASUNNY',[77]='EXTRASUNNY',
  [80]='EXTRASUNNY',[81]='EXTRASUNNY',[82]='EXTRASUNNY',
  [85]='EXTRASUNNY',[86]='EXTRASUNNY',
  [95]='EXTRASUNNY',[96]='EXTRASUNNY',[99]='EXTRASUNNY',
}
```

### Example: disable snow entirely
Change the snow-related codes to a non-snow GTA type, like `CLOUDS` or `OVERCAST`:

```lua
[71] = 'CLOUDS'
[73] = 'CLOUDS'
[75] = 'OVERCAST'
[77] = 'CLOUDS'
[85] = 'CLOUDS'
[86] = 'OVERCAST'
```

### If a code isn’t mapped
This fallback is used:

```lua
Config.DefaultGTAWeather = 'CLEAR'
```

---

## Compatibility note
If you run another time sync resource (vSync, qb-weathersync, cd...), disable its **time** syncing or stop it to prevent conflicts.

TwoPoint Development
