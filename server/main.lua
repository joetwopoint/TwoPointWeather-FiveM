-- TwoPointWeather server authority
-- Built and maintained by TwoPoint Development.

local RESOURCE = GetCurrentResourceName()
local DAY_MINUTES = 24 * 60
local SYNC_EVENT = RESOURCE .. ':client:sync'
local REQUEST_EVENT = RESOURCE .. ':server:requestSync'
local ACK_EVENT = RESOURCE .. ':server:syncAck'
local FORCE_WEATHER_EVENT = RESOURCE .. ':client:forceWeatherReset'

math.randomseed(os.time())
math.random(); math.random(); math.random()

local function debugLog(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

local function normalizeMinutes(value)
    value = value % DAY_MINUTES
    if value < 0 then
        value = value + DAY_MINUTES
    end
    return value
end

local function shortestMinuteDelta(fromMinutes, toMinutes)
    return ((toMinutes - fromMinutes + 720) % DAY_MINUTES) - 720
end

local function randomWeatherDurationSeconds()
    local minMinutes = math.max(1, tonumber(Config.Dynamic.MinDurationMinutes) or 15)
    local maxMinutes = math.max(minMinutes, tonumber(Config.Dynamic.MaxDurationMinutes) or minMinutes)
    return math.random(minMinutes, maxMinutes) * 60
end

local initialMinutes = normalizeMinutes((Config.Time.StartHour * 60) + Config.Time.StartMinute)
local now = os.time()

local packetSequence = 0
local stateRevision = 1
local clientAcks = {}
local requestRateLimit = {}

local state = {
    weather = string.upper(Config.Dynamic.InitialWeather or 'CLEAR'),
    weatherTransition = nil,
    weatherEndsAt = now + randomWeatherDurationSeconds(),
    dynamicEnabled = Config.Dynamic.Enabled == true,
    manualUntil = 0,
    forecast = {},

    time = {
        baseMinutes = initialMinutes,
        baseUnix = now,
        speed = tonumber(Config.Time.MinutesPerRealMinute) or 2.0,
        frozen = Config.Time.Frozen == true,
        transition = nil
    }
}

local function getCurrentTimeMinutes(atUnix)
    atUnix = atUnix or os.time()
    local timeState = state.time
    local transition = timeState.transition

    if transition then
        local elapsed = math.max(0, atUnix - transition.startedAt)
        local progress = math.min(1.0, elapsed / transition.duration)
        return normalizeMinutes(transition.fromMinutes + (transition.deltaMinutes * progress))
    end

    if timeState.frozen then
        return normalizeMinutes(timeState.baseMinutes)
    end

    local elapsedSeconds = math.max(0, atUnix - timeState.baseUnix)
    local elapsedGameMinutes = elapsedSeconds * (timeState.speed / 60.0)
    return normalizeMinutes(timeState.baseMinutes + elapsedGameMinutes)
end

local function finalizeTimeTransition(atUnix)
    local transition = state.time.transition
    if not transition or atUnix < transition.endsAt then
        return false
    end

    state.time.baseMinutes = normalizeMinutes(transition.targetMinutes)
    state.time.baseUnix = transition.endsAt
    state.time.transition = nil
    return true
end

local function pickWeightedWeather(currentWeather)
    local options = Config.WeatherTransitions[currentWeather]
    if not options or #options == 0 then
        options = Config.WeatherTransitions.CLEAR
    end

    local totalWeight = 0
    for i = 1, #options do
        totalWeight = totalWeight + math.max(0, tonumber(options[i].weight) or 0)
    end

    if totalWeight <= 0 then
        return 'CLEAR'
    end

    local roll = math.random() * totalWeight
    local cumulative = 0

    for i = 1, #options do
        cumulative = cumulative + math.max(0, tonumber(options[i].weight) or 0)
        if roll <= cumulative then
            return string.upper(options[i].weather)
        end
    end

    return string.upper(options[#options].weather)
end

local function rebuildForecast()
    state.forecast = {}
    local cursor = state.weatherTransition and state.weatherTransition.toWeather or state.weather

    for _ = 1, math.max(1, Config.Dynamic.ForecastLength or 6) do
        local nextWeather = pickWeightedWeather(cursor)
        state.forecast[#state.forecast + 1] = {
            weather = nextWeather,
            durationSeconds = randomWeatherDurationSeconds(),
            transitionSeconds = math.max(1, Config.Dynamic.TransitionSeconds or 60)
        }
        cursor = nextWeather
    end
end

local function ensureForecast()
    local wanted = math.max(1, Config.Dynamic.ForecastLength or 6)
    local cursor

    if #state.forecast > 0 then
        cursor = state.forecast[#state.forecast].weather
    else
        cursor = state.weatherTransition and state.weatherTransition.toWeather or state.weather
    end

    while #state.forecast < wanted do
        local nextWeather = pickWeightedWeather(cursor)
        state.forecast[#state.forecast + 1] = {
            weather = nextWeather,
            durationSeconds = randomWeatherDurationSeconds(),
            transitionSeconds = math.max(1, Config.Dynamic.TransitionSeconds or 60)
        }
        cursor = nextWeather
    end
end

local function getWeatherProgress(atUnix)
    local transition = state.weatherTransition
    if not transition then
        return 1.0
    end

    return math.min(1.0, math.max(0, atUnix - transition.startedAt) / transition.duration)
end

local function buildForecastPayload()
    local payload = {}
    local startAt = state.weatherEndsAt

    if state.weatherTransition then
        startAt = state.weatherTransition.endsAt + state.weatherTransition.holdSeconds
    end

    for i = 1, #state.forecast do
        local entry = state.forecast[i]
        payload[#payload + 1] = {
            weather = entry.weather,
            startsAt = startAt,
            durationSeconds = entry.durationSeconds,
            transitionSeconds = entry.transitionSeconds
        }
        startAt = startAt + entry.transitionSeconds + entry.durationSeconds
    end

    return payload
end

local function buildPayload()
    local atUnix = os.time()
    local currentMinutes = getCurrentTimeMinutes(atUnix)
    local timeTransition = state.time.transition
    local weatherTransition = state.weatherTransition

    local payload = {
        packet = 0,
        revision = stateRevision,
        serverEpoch = atUnix,
        serverTimer = GetGameTimer(),
        weather = {
            current = state.weather,
            dynamicEnabled = state.dynamicEnabled,
            manualUntil = state.manualUntil,
            nextChangeAt = state.weatherEndsAt,
            transition = nil,
            forecast = buildForecastPayload()
        },
        time = {
            currentMinutes = currentMinutes,
            speed = state.time.speed,
            frozen = state.time.frozen,
            transition = nil
        }
    }

    if weatherTransition then
        payload.weather.transition = {
            id = weatherTransition.id,
            fromWeather = weatherTransition.fromWeather,
            toWeather = weatherTransition.toWeather,
            duration = weatherTransition.duration,
            remaining = math.max(0, weatherTransition.endsAt - atUnix),
            progress = getWeatherProgress(atUnix)
        }
    end

    if timeTransition then
        payload.time.transition = {
            targetMinutes = timeTransition.targetMinutes,
            remaining = math.max(0, timeTransition.endsAt - atUnix),
            deltaRemaining = shortestMinuteDelta(currentMinutes, timeTransition.targetMinutes)
        }
    end

    return payload
end

local function updateGlobalState(payload)
    payload = payload or buildPayload()
    GlobalState.TwoPointWeather = payload
    GlobalState.syncedWeather = payload.weather
    GlobalState.syncedTime = payload.time
end

local function broadcastState(target, requestId, echoedClientTimer)
    packetSequence = packetSequence + 1
    local payload = buildPayload()
    payload.packet = packetSequence

    if requestId ~= nil then
        payload.request = {
            id = requestId,
            clientSentAt = tonumber(echoedClientTimer)
        }
    end

    if target and target ~= -1 then
        TriggerClientEvent(SYNC_EVENT, target, payload)
    else
        for _, playerId in ipairs(GetPlayers()) do
            TriggerClientEvent(SYNC_EVENT, tonumber(playerId), payload)
        end
    end

    updateGlobalState(payload)
end

local function forceWeatherReset(target)
    packetSequence = packetSequence + 1
    local payload = buildPayload()
    payload.packet = packetSequence

    if target and target ~= -1 then
        TriggerClientEvent(FORCE_WEATHER_EVENT, target, payload)
    else
        for _, playerId in ipairs(GetPlayers()) do
            TriggerClientEvent(FORCE_WEATHER_EVENT, tonumber(playerId), payload)
        end
    end

    updateGlobalState(payload)
end

local function publishState()
    stateRevision = stateRevision + 1
    broadcastState(-1)
end

local transitionCounter = 0

local function beginWeatherTransition(targetWeather, durationSeconds, holdSeconds, reason)
    targetWeather = string.upper(tostring(targetWeather or ''))
    if not Config.ValidWeather[targetWeather] then
        return false, 'invalid_weather'
    end

    local atUnix = os.time()
    local fromWeather = state.weather

    if state.weatherTransition then
        local progress = getWeatherProgress(atUnix)
        fromWeather = progress >= 0.5 and state.weatherTransition.toWeather or state.weatherTransition.fromWeather
    end

    durationSeconds = math.max(1, math.floor(tonumber(durationSeconds) or Config.CommandTransitionSeconds or 60))
    holdSeconds = math.max(0, math.floor(tonumber(holdSeconds) or randomWeatherDurationSeconds()))

    transitionCounter = transitionCounter + 1

    state.weather = fromWeather
    state.weatherTransition = {
        id = ('%d:%d'):format(atUnix, transitionCounter),
        fromWeather = fromWeather,
        toWeather = targetWeather,
        startedAt = atUnix,
        endsAt = atUnix + durationSeconds,
        duration = durationSeconds,
        holdSeconds = holdSeconds,
        reason = reason or 'unknown'
    }
    state.weatherEndsAt = state.weatherTransition.endsAt + holdSeconds

    rebuildForecast()
    publishState()
    debugLog(('Weather transition %s -> %s over %ss (%s)'):format(fromWeather, targetWeather, durationSeconds, reason or 'unknown'))
    return true
end

local function finalizeWeatherTransition(atUnix)
    local transition = state.weatherTransition
    if not transition or atUnix < transition.endsAt then
        return false
    end

    state.weather = transition.toWeather
    state.weatherEndsAt = transition.endsAt + transition.holdSeconds
    state.weatherTransition = nil
    ensureForecast()
    return true
end

local function setTimeTarget(hour, minute, durationSeconds)
    hour = tonumber(hour)
    minute = tonumber(minute) or 0

    if not hour or hour < 0 or hour > 23 or minute < 0 or minute > 59 then
        return false, 'invalid_time'
    end

    local atUnix = os.time()
    finalizeTimeTransition(atUnix)

    local fromMinutes = getCurrentTimeMinutes(atUnix)
    local targetMinutes = normalizeMinutes((math.floor(hour) * 60) + math.floor(minute))
    local duration = math.max(1, math.floor(tonumber(durationSeconds) or Config.Time.TransitionSeconds or 60))

    state.time.transition = {
        fromMinutes = fromMinutes,
        targetMinutes = targetMinutes,
        deltaMinutes = shortestMinuteDelta(fromMinutes, targetMinutes),
        startedAt = atUnix,
        endsAt = atUnix + duration,
        duration = duration
    }

    publishState()
    return true
end

local function freezeTime(shouldFreeze)
    local atUnix = os.time()
    local currentMinutes = getCurrentTimeMinutes(atUnix)

    state.time.baseMinutes = currentMinutes
    state.time.baseUnix = atUnix
    state.time.transition = nil
    state.time.frozen = shouldFreeze == true

    publishState()
end

local function hasPermission(playerSource)
    return playerSource == 0 or IsPlayerAceAllowed(playerSource, Config.AdminAce)
end

local function reply(playerSource, message, kind)
    if playerSource == 0 then
        print(('[%s] %s'):format(RESOURCE, message))
        return
    end

    TriggerClientEvent('chat:addMessage', playerSource, {
        color = kind == 'error' and { 255, 80, 80 } or { 100, 190, 255 },
        args = { 'Weather', message }
    })
end

local function getSyncCounts(requireWeatherMatch)
    if requireWeatherMatch == nil then
        requireWeatherMatch = true
    end

    local players = GetPlayers()
    local acknowledged = 0
    local paused = 0
    local missing = {}
    local mismatched = {}
    local timeout = math.max(10, tonumber(Config.AckTimeoutSeconds) or 15)
    local nowUnix = os.time()

    for _, playerIdString in ipairs(players) do
        local playerId = tonumber(playerIdString)
        local ack = clientAcks[playerId]
        local recentAndApplied = ack
            and ack.applied == true
            and ack.revision == stateRevision
            and (nowUnix - ack.receivedAt) <= timeout
        local weatherOkay = not requireWeatherMatch or (ack and ack.weatherMatched == true)
        local valid = recentAndApplied and weatherOkay

        if valid then
            acknowledged = acknowledged + 1
        else
            if ack and ack.paused then
                paused = paused + 1
            end
            missing[#missing + 1] = tostring(playerId)

            if ack and recentAndApplied and ack.weatherMatched ~= true then
                local conflicts = ack.conflicts and #ack.conflicts > 0 and table.concat(ack.conflicts, ',') or 'none'
                mismatched[#mismatched + 1] = ('%d[%s>%s p=%s rain=%s snow=%s fixes=%d conflicts=%s]'):format(
                    playerId,
                    ack.observedPrevious or '?',
                    ack.observedNext or '?',
                    ack.observedProgress and ('%.2f'):format(ack.observedProgress) or '?',
                    ack.rainLevel and ('%.2f'):format(ack.rainLevel) or '?',
                    ack.snowLevel and ('%.2f'):format(ack.snowLevel) or '?',
                    ack.corrections or 0,
                    conflicts
                )
            end
        end
    end

    return acknowledged, #players, paused, missing, mismatched
end

RegisterNetEvent(REQUEST_EVENT, function(requestId, clientTimer)
    local playerSource = source
    local currentTimer = GetGameTimer()
    local previous = requestRateLimit[playerSource] or 0

    if currentTimer - previous < 200 then
        return
    end

    requestRateLimit[playerSource] = currentTimer
    broadcastState(playerSource, requestId, clientTimer)
end)

RegisterNetEvent(ACK_EVENT, function(ack)
    local playerSource = source
    if type(ack) ~= 'table' then
        return
    end

    clientAcks[playerSource] = {
        packet = tonumber(ack.packet) or 0,
        revision = tonumber(ack.revision) or 0,
        receivedAt = os.time(),
        applied = ack.applied == true,
        paused = ack.paused == true,
        weather = tostring(ack.weather or ''),
        weatherProgress = tonumber(ack.weatherProgress),
        observedPrevious = tostring(ack.observedPrevious or ''),
        observedNext = tostring(ack.observedNext or ''),
        observedProgress = tonumber(ack.observedProgress),
        rainLevel = tonumber(ack.rainLevel),
        snowLevel = tonumber(ack.snowLevel),
        weatherMatched = ack.weatherMatched == true,
        mismatchStreak = tonumber(ack.mismatchStreak) or 0,
        corrections = tonumber(ack.corrections) or 0,
        conflicts = type(ack.conflicts) == 'table' and ack.conflicts or {},
        timeMinutes = tonumber(ack.timeMinutes),
        rtt = tonumber(ack.rtt)
    }
end)

AddEventHandler('playerDropped', function()
    clientAcks[source] = nil
    requestRateLimit[source] = nil
end)

AddEventHandler('playerJoining', function()
    local playerSource = source
    SetTimeout(3000, function()
        if GetPlayerName(playerSource) then
            broadcastState(playerSource)
        end
    end)
end)

RegisterCommand('weather', function(playerSource, args)
    if not hasPermission(playerSource) then
        reply(playerSource, 'You do not have permission to use /weather.', 'error')
        return
    end

    local action = args[1] and string.upper(args[1]) or nil

    if not action then
        reply(playerSource, 'Usage: /weather [type|dynamic|freeze|status|resync] [transition seconds|player ID]', 'error')
        return
    end

    if action == 'DYNAMIC' then
        state.dynamicEnabled = true
        state.manualUntil = 0
        ensureForecast()
        publishState()
        reply(playerSource, 'Dynamic weather enabled.')
        return
    end

    if action == 'FREEZE' or action == 'STATIC' then
        state.dynamicEnabled = false
        state.manualUntil = 0
        publishState()
        reply(playerSource, ('Dynamic weather frozen on %s.'):format(state.weatherTransition and state.weatherTransition.toWeather or state.weather))
        return
    end

    if action == 'RESYNC' or action == 'FORCERESYNC' then
        local targetArg = args[2] and string.lower(args[2]) or 'all'

        if targetArg == 'all' or targetArg == '*' then
            forceWeatherReset(-1)
            reply(playerSource, ('Forced a hard weather reset for %d connected clients.'):format(#GetPlayers()))
            return
        end

        local target = tonumber(targetArg)
        if not target or not GetPlayerName(target) then
            reply(playerSource, 'Invalid player ID. Use /weather resync all or /weather resync [player ID].', 'error')
            return
        end

        forceWeatherReset(target)
        reply(playerSource, ('Forced a hard weather reset for player %d.'):format(target))
        return
    end

    if action == 'STATUS' or action == 'AUDIT' then
        local transition = state.weatherTransition
        local current = transition and transition.toWeather or state.weather
        local acknowledged, playerCount, paused, missing, mismatched = getSyncCounts(true)
        local missingText = #missing > 0 and (' | Missing IDs: %s'):format(table.concat(missing, ',')) or ''
        local mismatchText = #mismatched > 0 and (' | Render mismatch: %s'):format(table.concat(mismatched, ' ')) or ''

        reply(playerSource, ('Current: %s | Dynamic: %s | Transitioning: %s | Revision: %d | Render-synced clients: %d/%d | Paused: %d%s%s'):format(
            current,
            state.dynamicEnabled and 'yes' or 'no',
            transition and ('yes, %ss remaining'):format(math.max(0, transition.endsAt - os.time())) or 'no',
            stateRevision,
            acknowledged,
            playerCount,
            paused,
            missingText,
            mismatchText
        ))
        return
    end

    if not Config.ValidWeather[action] then
        reply(playerSource, ('Unknown weather type: %s'):format(action), 'error')
        return
    end

    local duration = tonumber(args[2]) or Config.CommandTransitionSeconds
    local manualHold = math.max(0, Config.Dynamic.ManualHoldMinutes or 0) * 60
    state.manualUntil = state.dynamicEnabled and (os.time() + manualHold) or 0

    local ok = beginWeatherTransition(action, duration, manualHold, 'admin')
    if ok then
        reply(playerSource, ('Weather changing to %s over %d seconds.'):format(action, math.max(1, math.floor(duration))))
    end
end, false)

RegisterCommand('time', function(playerSource, args)
    if not hasPermission(playerSource) then
        reply(playerSource, 'You do not have permission to use /time.', 'error')
        return
    end

    local action = args[1] and string.lower(args[1]) or nil

    if not action then
        reply(playerSource, 'Usage: /time [hour] [minute] [transition seconds], /time freeze, /time unfreeze, /time status', 'error')
        return
    end

    if action == 'freeze' then
        freezeTime(true)
        reply(playerSource, 'Time frozen.')
        return
    end

    if action == 'unfreeze' or action == 'resume' then
        freezeTime(false)
        reply(playerSource, 'Time resumed.')
        return
    end

    if action == 'status' then
        local minutes = getCurrentTimeMinutes(os.time())
        local hour = math.floor(minutes / 60)
        local minute = math.floor(minutes % 60)
        local acknowledged, playerCount = getSyncCounts(false)
        reply(playerSource, ('Time: %02d:%02d | Frozen: %s | Speed: %.2f game min/real min | Revision: %d | Synced clients: %d/%d'):format(
            hour,
            minute,
            state.time.frozen and 'yes' or 'no',
            state.time.speed,
            stateRevision,
            acknowledged,
            playerCount
        ))
        return
    end

    local hour = tonumber(args[1])
    local minute = tonumber(args[2]) or 0
    local duration = tonumber(args[3]) or Config.CommandTransitionSeconds
    local ok = setTimeTarget(hour, minute, duration)

    if not ok then
        reply(playerSource, 'Invalid time. Use /time [0-23] [0-59] [transition seconds].', 'error')
        return
    end

    reply(playerSource, ('Time changing to %02d:%02d over %d seconds.'):format(
        math.floor(hour),
        math.floor(minute),
        math.max(1, math.floor(duration))
    ))
end, false)

exports('GetWeather', function()
    return buildPayload().weather
end)

exports('GetForecast', function()
    return buildForecastPayload()
end)

exports('GetTime', function()
    return buildPayload().time
end)

exports('GetSyncStatus', function()
    local acknowledged, playerCount, paused, missing, mismatched = getSyncCounts(true)
    return {
        revision = stateRevision,
        acknowledged = acknowledged,
        players = playerCount,
        paused = paused,
        missing = missing,
        mismatched = mismatched
    }
end)

exports('SetWeather', function(weatherType, transitionSeconds, holdSeconds)
    return beginWeatherTransition(weatherType, transitionSeconds, holdSeconds, 'export')
end)

exports('ForceWeatherResync', function(playerId)
    local target = tonumber(playerId) or -1
    forceWeatherReset(target)
    return true
end)

exports('SetTime', function(hour, minute, transitionSeconds)
    return setTimeTarget(hour, minute, transitionSeconds)
end)

exports('SetDynamicWeather', function(enabled)
    state.dynamicEnabled = enabled == true
    state.manualUntil = 0
    ensureForecast()
    publishState()
    return state.dynamicEnabled
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE then
        return
    end

    print(('[%s] Started with event namespace %s'):format(RESOURCE, RESOURCE))

    if Config.WarnAboutConflictingResources then
        for _, otherResource in ipairs(Config.KnownConflictingResources or {}) do
            if otherResource ~= RESOURCE and GetResourceState(otherResource) == 'started' then
                print(('[%s] WARNING: %s is also started and may override synchronized time/weather.'):format(RESOURCE, otherResource))
            end
        end
    end

    SetTimeout(1500, function()
        broadcastState(-1)
    end)
end)

CreateThread(function()
    rebuildForecast()
    updateGlobalState()

    while true do
        Wait(1000)
        local atUnix = os.time()
        local changed = false

        if finalizeTimeTransition(atUnix) then
            changed = true
        end

        if finalizeWeatherTransition(atUnix) then
            changed = true
        end

        if state.dynamicEnabled and not state.weatherTransition then
            local manualExpired = state.manualUntil == 0 or atUnix >= state.manualUntil
            if manualExpired and atUnix >= state.weatherEndsAt then
                ensureForecast()
                local nextEntry = table.remove(state.forecast, 1)
                ensureForecast()

                if nextEntry then
                    beginWeatherTransition(
                        nextEntry.weather,
                        nextEntry.transitionSeconds,
                        nextEntry.durationSeconds,
                        'dynamic'
                    )
                end
            end
        end

        if changed then
            publishState()
        end
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(2, tonumber(Config.SyncIntervalSeconds) or 5) * 1000)
        broadcastState(-1)
    end
end)
