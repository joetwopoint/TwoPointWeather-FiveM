# TwoPointWeather

**Built and maintained by TwoPoint Development.**

TwoPointWeather is a standalone, server-authoritative FiveM resource that synchronizes GTA V time and weather for every connected player. It includes smooth transitions, configurable dynamic weather, ACE-protected admin commands, late-join correction, render-state verification, hard resynchronization tools, and LB Phone weather compatibility data.

## Features

- Server-authoritative synchronized time and weather
- Smooth configurable weather and time transitions
- Weighted dynamic weather progression
- Late-join transition correction
- Latency-compensated clock synchronization
- Render-state verification instead of packet-only acknowledgments
- Per-frame weather ownership and precipitation enforcement
- Targeted and whole-server hard resynchronization
- ACE-protected `/weather` and `/time` commands
- LB Phone current-weather and forecast compatibility exports
- Diagnostics for conflicting weather resources

## Requirements

- A current FiveM server artifact
- OneSync-compatible server configuration
- No other active resource controlling GTA time or weather
- LB Phone only when its weather integration data is needed

## Repository installation

Clone or download this repository into your resources directory so the final path is:

```text
resources/[standalone]/TwoPointWeather
```

Add the following to `server.cfg`:

```cfg
add_ace group.cd TwoPointWeather.admin allow
ensure TwoPointWeather
```

Assign a player license to `group.cd` when needed:

```cfg
add_principal identifier.license:YOUR_LICENSE_HERE group.cd
```

The ACE object in `config.lua` must match:

```lua
Config.AdminAce = 'TwoPointWeather.admin'
```

Restart the full server after installing or replacing the resource.

## Important: only run one weather controller

Disable every other resource that changes GTA weather or time. Common examples include:

```cfg
# ensure qb-weathersync
# ensure cd_easytime
# ensure vSync
# ensure easytime
# ensure Renewed-Weathersync
# ensure nd-weathersync
```

Two resources calling the same client weather natives will overwrite each other and can create player-specific weather differences.

## Commands

### Weather

```text
/weather CLEAR
/weather RAIN 60
/weather THUNDER 120
/weather dynamic
/weather freeze
/weather status
/weather audit
/weather resync all
/weather resync [player ID]
```

### Time

```text
/time 12 30
/time 23 00 60
/time freeze
/time unfreeze
/time status
```

The transition value is measured in seconds. When omitted, `Config.CommandTransitionSeconds` is used.

## Permission setup

Grant only the TwoPointWeather permission to `group.cd`:

```cfg
add_ace group.cd TwoPointWeather.admin allow
```

Do not set the config permission to the group name. This is correct:

```lua
Config.AdminAce = 'TwoPointWeather.admin'
```

This is not correct:

```lua
Config.AdminAce = 'group.cd'
```

Test permission inheritance from the server console:

```text
test_ace group.cd TwoPointWeather.admin
test_ace identifier.license:YOUR_LICENSE_HERE TwoPointWeather.admin
```

## Multi-client synchronization test

Use at least two connected players:

1. Run `/weather CLEAR 1` and wait two seconds.
2. Run `/weather THUNDER 60`.
3. Have another player join around 30 seconds into the transition.
4. Confirm the joining player enters at approximately the same transition stage.
5. Run `/time 23 45 60` and compare multiple clients.
6. Wait a few seconds, then run `/weather audit`.

Expected output:

```text
Render-synced clients: 3/3 | Paused: 0
```

A mismatched player can be forced back into sync with:

```text
/weather resync 12
```

Force every connected player to rebuild the authoritative weather state with:

```text
/weather resync all
```

## Client diagnostics

An affected player can run the following command in the F8 console:

```text
tpweatherdiag
```

The diagnostic output includes expected and observed weather, transition progress, rain and snow levels, packet revision, correction count, detected conflicts, measured round-trip latency, and calculated game time.

## Strict synchronization defaults

The packaged settings prioritize whole-server consistency:

```lua
Config.StrictSync = true
Config.AllowExternalPauseEvents = false
Config.SyncIntervalSeconds = 5
Config.CalibrationIntervalSeconds = 30
Config.ClientTimeApplyIntervalMs = 50
Config.ClientWeatherApplyIntervalMs = 0
Config.ClientWeatherTransitionApplyIntervalMs = 0
Config.ClientWeatherFullResetIntervalMs = 2000
Config.ClientWeatherDiagnosticIntervalMs = 1000
Config.ClientAckIntervalMs = 2000
Config.ForcePrecipitationLevels = true
```

Resources that genuinely need temporary local weather control should use the resource export:

```lua
exports['TwoPointWeather']:PauseSync(true)
exports['TwoPointWeather']:PauseSync(false)
```

Paused players are reported separately by `/weather audit`.

## LB Phone integration

TwoPointWeather applies the synchronized GTA weather on every client and exposes current conditions plus forecast data for LB Phone integrations.

Client export:

```lua
local weatherData = exports['TwoPointWeather']:GetLBPhoneWeatherData()
```

Resource-aware event:

```lua
AddEventHandler('TwoPointWeather:lb-phone:updated', function(data)
    print(json.encode(data))
end)
```

The returned data includes the current weather, display label, estimated temperature, synchronized time, dynamic-weather status, transition status, and forecast entries.

## Exports

### Server

```lua
exports['TwoPointWeather']:GetWeather()
exports['TwoPointWeather']:GetForecast()
exports['TwoPointWeather']:GetTime()
exports['TwoPointWeather']:GetSyncStatus()
exports['TwoPointWeather']:SetWeather(weather, transitionSeconds, holdSeconds)
exports['TwoPointWeather']:SetTime(hour, minute, transitionSeconds)
exports['TwoPointWeather']:SetDynamicWeather(enabled)
```

### Client

```lua
exports['TwoPointWeather']:GetWeather()
exports['TwoPointWeather']:GetForecast()
exports['TwoPointWeather']:GetTime()
exports['TwoPointWeather']:GetSyncDiagnostics()
exports['TwoPointWeather']:GetLBPhoneWeatherData()
exports['TwoPointWeather']:PauseSync(paused)
```

## Debugging

Enable debug logging in `config.lua`:

```lua
Config.Debug = true
```

Restart `TwoPointWeather`, then review the server console and affected clients' F8 consoles.

`/weather audit` reports what GTA is actually rendering on each client. A compact mismatch entry can look like:

```text
12[CLEAR>RAIN p=0.42 rain=0.30 snow=0.00 fixes=2 conflicts=qb-weathersync]
```

This identifies the player, observed transition, precipitation levels, automatic correction count, and detected competing resources.

## Resource name

Keep the repository folder and resource name exactly as:

```text
TwoPointWeather
```

The packaged ACE permission remains:

```text
TwoPointWeather.admin
```

Do not run an older copy under another folder name at the same time.

## Version

Current release: **1.3.1**

See [CHANGELOG.md](CHANGELOG.md) for release history.

## License

TwoPointWeather is released under the TwoPoint Development Community License included in [LICENSE](LICENSE).
