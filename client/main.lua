-- TwoPointWeather client synchronization
-- Built and maintained by TwoPoint Development.

local RESOURCE = GetCurrentResourceName()
local DAY_MINUTES = 24 * 60
local SYNC_EVENT = RESOURCE .. ':client:sync'
local REQUEST_EVENT = RESOURCE .. ':server:requestSync'
local ACK_EVENT = RESOURCE .. ':server:syncAck'
local FORCE_WEATHER_EVENT = RESOURCE .. ':client:forceWeatherReset'

local syncPaused = false
local latestPayload = nil
local timeSnapshot = nil
local activeWeatherTransition = nil
local hasReceivedSync = false
local lastPacket = 0
local lastRevision = 0
local lastFullWeatherApply = 0
local weatherMismatchStreak = 0
local weatherCorrectionCount = 0
local lastObservedWeather = nil

local weatherNameByHash = {}
local precipitationByWeather = {
    RAIN = { rain = 0.70, snow = 0.0 },
    THUNDER = { rain = 1.00, snow = 0.0 },
    CLEARING = { rain = 0.25, snow = 0.0 },
    SNOW = { rain = 0.0, snow = 0.75 },
    BLIZZARD = { rain = 0.0, snow = 1.00 },
    SNOWLIGHT = { rain = 0.0, snow = 0.40 },
    XMAS = { rain = 0.0, snow = 0.55 }
}

local clamp
local calculateWeatherProgress

local requestCounter = 0
local clockOffsetMs = nil
local clockSamples = {}
local bestRttMs = nil

local function normalizeHash(value)
    value = tonumber(value) or 0
    if value < 0 then
        value = value + 4294967296
    end
    return value
end

for weatherName in pairs(Config.ValidWeather or {}) do
    weatherNameByHash[normalizeHash(GetHashKey(weatherName))] = weatherName
end

local function weatherNameFromHash(value)
    return weatherNameByHash[normalizeHash(value)] or ('0x%08X'):format(normalizeHash(value))
end

local function lerp(a, b, t)
    return a + ((b - a) * t)
end

local function precipitationFor(weatherType)
    local values = precipitationByWeather[weatherType] or {}
    return values.rain or 0.0, values.snow or 0.0
end

local function applyPrecipitation(fromWeather, toWeather, progress)
    if Config.ForcePrecipitationLevels ~= true then
        return
    end

    progress = clamp and clamp(progress or 1.0, 0.0, 1.0) or math.max(0.0, math.min(1.0, progress or 1.0))
    local fromRain, fromSnow = precipitationFor(fromWeather)
    local toRain, toSnow = precipitationFor(toWeather or fromWeather)
    local rain = lerp(fromRain, toRain, progress)
    local snow = lerp(fromSnow, toSnow, progress)

    SetRainLevel(rain + 0.0)
    SetSnowLevel(snow + 0.0)

    if type(SetRainFxIntensity) == 'function' then
        SetRainFxIntensity(rain + 0.0)
    end
end

local function getKnownClientConflicts()
    local conflicts = {}
    for _, resourceName in ipairs(Config.KnownConflictingResources or {}) do
        if resourceName ~= RESOURCE and GetResourceState(resourceName) == 'started' then
            conflicts[#conflicts + 1] = resourceName
        end
    end
    return conflicts
end

local function observeWeather()
    local observed = {
        previousHash = normalizeHash(GetPrevWeatherTypeHashName()),
        nextHash = normalizeHash(GetNextWeatherTypeHashName()),
        progress = nil,
        rainLevel = nil,
        snowLevel = nil
    }

    local ok, previousHash, nextHash, progress = pcall(function()
        return GetWeatherTypeTransition()
    end)

    if ok then
        if previousHash ~= nil then
            observed.previousHash = normalizeHash(previousHash)
        end
        if nextHash ~= nil then
            observed.nextHash = normalizeHash(nextHash)
        end
        observed.progress = tonumber(progress)
    end

    local rainOk, rainLevel = pcall(GetRainLevel)
    if rainOk then
        observed.rainLevel = tonumber(rainLevel)
    end

    local snowOk, snowLevel = pcall(GetSnowLevel)
    if snowOk then
        observed.snowLevel = tonumber(snowLevel)
    end

    observed.previous = weatherNameFromHash(observed.previousHash)
    observed.next = weatherNameFromHash(observed.nextHash)
    return observed
end

local function isObservedWeatherMatched(observed)
    if not latestPayload or not latestPayload.weather or not observed then
        return false
    end

    if activeWeatherTransition then
        local expectedProgress = calculateWeatherProgress and calculateWeatherProgress(activeWeatherTransition) or 0.0
        local namesMatch = observed.previous == activeWeatherTransition.fromWeather
            and observed.next == activeWeatherTransition.toWeather
        local progressMatch = observed.progress == nil
            or math.abs(observed.progress - expectedProgress) <= (tonumber(Config.WeatherProgressTolerance) or 0.20)
        return namesMatch and progressMatch
    end

    local expected = latestPayload.weather.current
    return observed.previous == expected or observed.next == expected
end

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

clamp = function(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function localTimerDelta(later, earlier)
    local delta = later - earlier
    if delta < 0 then
        delta = delta + 4294967296
    end
    return delta
end

local function calibrateClock(payload, receivedAt)
    local request = payload.request
    if not request or request.clientSentAt == nil or payload.serverTimer == nil then
        return
    end

    local sentAt = tonumber(request.clientSentAt)
    if not sentAt then
        return
    end

    local rtt = localTimerDelta(receivedAt, sentAt)
    if rtt < 0 or rtt > 10000 then
        return
    end

    local sample = {
        rtt = rtt,
        offset = (tonumber(payload.serverTimer) + (rtt / 2.0)) - receivedAt,
        capturedAt = receivedAt
    }

    clockSamples[#clockSamples + 1] = sample
    local maxSamples = math.max(3, tonumber(Config.CalibrationSampleCount) or 8)
    while #clockSamples > maxSamples do
        table.remove(clockSamples, 1)
    end

    local best = clockSamples[1]
    for i = 2, #clockSamples do
        if clockSamples[i].rtt < best.rtt then
            best = clockSamples[i]
        end
    end

    clockOffsetMs = best.offset
    bestRttMs = best.rtt
    debugLog(('Clock calibrated: RTT %.0fms, offset %.1fms'):format(best.rtt, best.offset))
end

local function estimateServerTimer(snapshot)
    if clockOffsetMs ~= nil then
        return GetGameTimer() + clockOffsetMs
    end

    return snapshot.serverTimer + localTimerDelta(GetGameTimer(), snapshot.receivedAtClientTimer)
end

local function elapsedSinceSnapshot(snapshot)
    local elapsed = estimateServerTimer(snapshot) - snapshot.serverTimer
    return math.max(0, elapsed) / 1000.0
end

local function applySettledWeather(weatherType, forceFullReset)
    if syncPaused or not weatherType then
        return
    end

    local nowTimer = GetGameTimer()
    local fullResetInterval = math.max(250, tonumber(Config.ClientWeatherFullResetIntervalMs) or 2000)
    local shouldFullReset = forceFullReset == true
        or lastFullWeatherApply == 0
        or localTimerDelta(nowTimer, lastFullWeatherApply) >= fullResetInterval

    if shouldFullReset then
        ClearOverrideWeather()
        ClearWeatherTypePersist()
        SetWeatherTypeNowPersist(weatherType)
        SetWeatherTypeNow(weatherType)
        lastFullWeatherApply = nowTimer
    end

    SetOverrideWeather(weatherType)
    applyPrecipitation(weatherType, weatherType, 1.0)
end

local function enforceSettledWeather(weatherType)
    applySettledWeather(weatherType, false)
end

calculateWeatherProgress = function(transition)
    local elapsed = elapsedSinceSnapshot(transition)
    local duration = math.max(0.001, transition.duration)
    return clamp(transition.progressAtSnapshot + (elapsed / duration), 0.0, 1.0)
end

local function applyExactWeatherBlend(transition, progress, forceFullReset)
    ClearOverrideWeather()

    local nowTimer = GetGameTimer()
    local fullResetInterval = math.max(250, tonumber(Config.ClientWeatherFullResetIntervalMs) or 2000)
    local shouldFullReset = forceFullReset == true
        or lastFullWeatherApply == 0
        or localTimerDelta(nowTimer, lastFullWeatherApply) >= fullResetInterval

    if shouldFullReset then
        ClearWeatherTypePersist()
        SetWeatherTypeNowPersist(transition.fromWeather)
        SetWeatherTypeNow(transition.fromWeather)
        lastFullWeatherApply = nowTimer
    end

    if Config.UseExactWeatherBlendNative ~= false then
        SetWeatherTypeTransition(
            GetHashKey(transition.fromWeather),
            GetHashKey(transition.toWeather),
            progress + 0.0
        )
    else
        local remaining = math.max(1.0, (1.0 - progress) * transition.duration)
        SetWeatherTypeOvertimePersist(transition.toWeather, remaining)
    end

    applyPrecipitation(transition.fromWeather, transition.toWeather, progress)
end

local function startOrUpdateWeatherTransition(transition, payload, receivedAt)
    if syncPaused or not transition then
        return
    end

    local isNew = not activeWeatherTransition or activeWeatherTransition.id ~= transition.id

    activeWeatherTransition = {
        id = transition.id,
        fromWeather = transition.fromWeather,
        toWeather = transition.toWeather,
        duration = math.max(1.0, tonumber(transition.duration) or 1.0),
        progressAtSnapshot = clamp(tonumber(transition.progress) or 0.0, 0.0, 1.0),
        serverTimer = tonumber(payload.serverTimer) or 0,
        receivedAtClientTimer = receivedAt
    }

    local progress = calculateWeatherProgress(activeWeatherTransition)

    if isNew then
        lastFullWeatherApply = 0
        applyExactWeatherBlend(activeWeatherTransition, progress, true)

        debugLog(('Applying weather transition %s -> %s at %.1f%%'):format(
            transition.fromWeather,
            transition.toWeather,
            progress * 100.0
        ))
    end
end

local function setTimeSnapshot(payload, receivedAt)
    local timeData = payload.time
    timeSnapshot = {
        receivedAtClientTimer = receivedAt,
        serverTimer = tonumber(payload.serverTimer) or 0,
        currentMinutes = tonumber(timeData.currentMinutes) or 0.0,
        speed = tonumber(timeData.speed) or 0.0,
        frozen = timeData.frozen == true,
        transition = timeData.transition
    }
end

local function getEstimatedMinutes()
    if not timeSnapshot then
        return nil
    end

    local elapsedSeconds = elapsedSinceSnapshot(timeSnapshot)
    local transition = timeSnapshot.transition

    if transition then
        local remaining = math.max(0.001, tonumber(transition.remaining) or 0.001)
        local deltaRemaining = tonumber(transition.deltaRemaining) or 0.0
        local targetMinutes = tonumber(transition.targetMinutes) or timeSnapshot.currentMinutes

        if elapsedSeconds <= remaining then
            local progress = math.min(1.0, elapsedSeconds / remaining)
            return normalizeMinutes(timeSnapshot.currentMinutes + (deltaRemaining * progress))
        end

        if timeSnapshot.frozen then
            return normalizeMinutes(targetMinutes)
        end

        local afterTransitionSeconds = elapsedSeconds - remaining
        return normalizeMinutes(targetMinutes + (afterTransitionSeconds * (timeSnapshot.speed / 60.0)))
    end

    if timeSnapshot.frozen then
        return normalizeMinutes(timeSnapshot.currentMinutes)
    end

    return normalizeMinutes(timeSnapshot.currentMinutes + (elapsedSeconds * (timeSnapshot.speed / 60.0)))
end

local function currentWeatherDiagnostic()
    if activeWeatherTransition then
        local progress = calculateWeatherProgress(activeWeatherTransition)
        return progress >= 0.5 and activeWeatherTransition.toWeather or activeWeatherTransition.fromWeather, progress
    end

    if latestPayload and latestPayload.weather then
        return latestPayload.weather.current, 1.0
    end

    return '', nil
end

local function sendAck(payload)
    if not payload then
        return
    end

    local minutes = getEstimatedMinutes()
    local weather, weatherProgress = currentWeatherDiagnostic()
    local observed = observeWeather()
    local weatherMatched = isObservedWeatherMatched(observed)
    lastObservedWeather = observed

    TriggerServerEvent(ACK_EVENT, {
        packet = tonumber(payload.packet) or 0,
        revision = tonumber(payload.revision) or 0,
        applied = not syncPaused,
        paused = syncPaused,
        weather = weather,
        weatherProgress = weatherProgress,
        observedPrevious = observed.previous,
        observedNext = observed.next,
        observedProgress = observed.progress,
        rainLevel = observed.rainLevel,
        snowLevel = observed.snowLevel,
        weatherMatched = weatherMatched,
        mismatchStreak = weatherMismatchStreak,
        corrections = weatherCorrectionCount,
        conflicts = getKnownClientConflicts(),
        timeMinutes = minutes,
        rtt = bestRttMs
    })
end

local function requestSync()
    requestCounter = requestCounter + 1
    TriggerServerEvent(REQUEST_EVENT, requestCounter, GetGameTimer())
end

RegisterNetEvent(SYNC_EVENT, function(payload)
    if type(payload) ~= 'table' or type(payload.weather) ~= 'table' or type(payload.time) ~= 'table' then
        return
    end

    local receivedAt = GetGameTimer()
    calibrateClock(payload, receivedAt)

    payload.receivedAtClientTimer = receivedAt
    latestPayload = payload
    hasReceivedSync = true
    lastPacket = tonumber(payload.packet) or lastPacket
    lastRevision = tonumber(payload.revision) or lastRevision
    setTimeSnapshot(payload, receivedAt)

    if not syncPaused then
        if payload.weather.transition then
            startOrUpdateWeatherTransition(payload.weather.transition, payload, receivedAt)
        else
            activeWeatherTransition = nil
            applySettledWeather(payload.weather.current)
        end
    end

    TriggerEvent(RESOURCE .. ':client:updated', payload)
    if RESOURCE ~= 'TwoPointWeather' then
        TriggerEvent('TwoPointWeather:client:updated', payload)
    end
    sendAck(payload)
end)

RegisterNetEvent(FORCE_WEATHER_EVENT, function(payload)
    if type(payload) == 'table' and type(payload.weather) == 'table' and type(payload.time) == 'table' then
        local receivedAt = GetGameTimer()
        payload.receivedAtClientTimer = receivedAt
        latestPayload = payload
        setTimeSnapshot(payload, receivedAt)
    end

    if syncPaused or not latestPayload or not latestPayload.weather then
        return
    end

    lastFullWeatherApply = 0
    weatherCorrectionCount = weatherCorrectionCount + 1

    if latestPayload.weather.transition then
        startOrUpdateWeatherTransition(latestPayload.weather.transition, latestPayload, GetGameTimer())
        if activeWeatherTransition then
            applyExactWeatherBlend(activeWeatherTransition, calculateWeatherProgress(activeWeatherTransition), true)
        end
    else
        activeWeatherTransition = nil
        applySettledWeather(latestPayload.weather.current, true)
    end

    sendAck(latestPayload)
end)

RegisterNetEvent(RESOURCE .. ':client:pauseSync', function(paused)
    syncPaused = paused == true
    if not syncPaused then
        requestSync()
    end
end)

RegisterNetEvent('ToggleWeatherSync', function(enabled)
    if Config.AllowExternalPauseEvents ~= true then
        return
    end

    syncPaused = enabled == false
    if not syncPaused then
        requestSync()
    end
end)

RegisterNetEvent('qb-weathersync:client:DisableSync', function()
    if Config.AllowExternalPauseEvents == true then
        syncPaused = true
    end
end)

RegisterNetEvent('qb-weathersync:client:EnableSync', function()
    if Config.AllowExternalPauseEvents ~= true then
        return
    end

    syncPaused = false
    requestSync()
end)

exports('PauseSync', function(paused)
    syncPaused = paused == true
    if not syncPaused then
        requestSync()
    end
end)

exports('GetWeather', function()
    return latestPayload and latestPayload.weather or nil
end)

exports('GetForecast', function()
    return latestPayload and latestPayload.weather and latestPayload.weather.forecast or {}
end)

exports('GetTime', function()
    local minutes = getEstimatedMinutes()
    if not minutes then
        return nil
    end

    return {
        minutes = minutes,
        hour = math.floor(minutes / 60),
        minute = math.floor(minutes % 60),
        second = math.floor((minutes - math.floor(minutes)) * 60),
        frozen = timeSnapshot and timeSnapshot.frozen or false,
        rtt = bestRttMs
    }
end)

exports('GetSyncDiagnostics', function()
    local weather, progress = currentWeatherDiagnostic()
    return {
        received = hasReceivedSync,
        packet = lastPacket,
        revision = lastRevision,
        paused = syncPaused,
        rtt = bestRttMs,
        clockOffsetMs = clockOffsetMs,
        weather = weather,
        weatherProgress = progress,
        observedWeather = lastObservedWeather,
        weatherMismatchStreak = weatherMismatchStreak,
        weatherCorrections = weatherCorrectionCount,
        conflicts = getKnownClientConflicts(),
        timeMinutes = getEstimatedMinutes()
    }
end)

RegisterCommand('tpweatherdiag', function()
    local weather, progress = currentWeatherDiagnostic()
    local minutes = getEstimatedMinutes()
    local observed = observeWeather()
    local conflicts = getKnownClientConflicts()
    print(('[%s] received=%s packet=%d revision=%d paused=%s rtt=%sms expected=%s progress=%s observed=%s->%s observedProgress=%s matched=%s rain=%s snow=%s corrections=%d conflicts=%s timeMinutes=%s'):format(
        RESOURCE,
        tostring(hasReceivedSync),
        lastPacket,
        lastRevision,
        tostring(syncPaused),
        bestRttMs and ('%.0f'):format(bestRttMs) or 'n/a',
        tostring(weather),
        progress and ('%.3f'):format(progress) or 'n/a',
        tostring(observed.previous),
        tostring(observed.next),
        observed.progress and ('%.3f'):format(observed.progress) or 'n/a',
        tostring(isObservedWeatherMatched(observed)),
        observed.rainLevel and ('%.3f'):format(observed.rainLevel) or 'n/a',
        observed.snowLevel and ('%.3f'):format(observed.snowLevel) or 'n/a',
        weatherCorrectionCount,
        #conflicts > 0 and table.concat(conflicts, ',') or 'none',
        minutes and ('%.3f'):format(minutes) or 'n/a'
    ))
end, false)

CreateThread(function()
    Wait(500)

    while not hasReceivedSync do
        requestSync()
        Wait(2000)
    end

    while true do
        Wait(math.max(5000, (tonumber(Config.CalibrationIntervalSeconds) or 30) * 1000))
        requestSync()
    end
end)

CreateThread(function()
    if Config.StrictSync ~= false then
        PauseClock(true)
    end

    while true do
        Wait(math.max(25, tonumber(Config.ClientTimeApplyIntervalMs) or 50))

        if not syncPaused then
            if Config.StrictSync ~= false then
                PauseClock(true)
            end

            local minutes = getEstimatedMinutes()
            if minutes then
                local hour = math.floor(minutes / 60)
                local minuteFloat = minutes % 60
                local minute = math.floor(minuteFloat)
                local second = math.floor((minuteFloat - minute) * 60)
                NetworkOverrideClockTime(hour, minute, second)
            end
        end
    end
end)

CreateThread(function()
    while true do
        local waitMs = tonumber(Config.ClientWeatherApplyIntervalMs) or 0
        if activeWeatherTransition then
            waitMs = tonumber(Config.ClientWeatherTransitionApplyIntervalMs) or 0
        end
        Wait(math.max(0, waitMs))

        if not syncPaused and activeWeatherTransition then
            local progress = calculateWeatherProgress(activeWeatherTransition)

            if progress >= 1.0 then
                local target = activeWeatherTransition.toWeather
                activeWeatherTransition = nil
                applySettledWeather(target, true)

                if latestPayload and latestPayload.weather then
                    latestPayload.weather.current = target
                    latestPayload.weather.transition = nil
                end
            else
                applyExactWeatherBlend(activeWeatherTransition, progress, false)
            end
        elseif not syncPaused and latestPayload and latestPayload.weather then
            enforceSettledWeather(latestPayload.weather.current)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(250, tonumber(Config.ClientWeatherDiagnosticIntervalMs) or 1000))

        if not syncPaused and latestPayload and latestPayload.weather then
            local observed = observeWeather()
            lastObservedWeather = observed

            if isObservedWeatherMatched(observed) then
                weatherMismatchStreak = 0
            else
                weatherMismatchStreak = weatherMismatchStreak + 1

                if weatherMismatchStreak >= 2 then
                    weatherCorrectionCount = weatherCorrectionCount + 1
                    lastFullWeatherApply = 0

                    if activeWeatherTransition then
                        applyExactWeatherBlend(activeWeatherTransition, calculateWeatherProgress(activeWeatherTransition), true)
                    else
                        applySettledWeather(latestPayload.weather.current, true)
                    end
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(1000, tonumber(Config.ClientAckIntervalMs) or 2000))
        if latestPayload then
            sendAck(latestPayload)
        end
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == RESOURCE then
        requestSync()
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then
        return
    end

    ClearOverrideWeather()
    ClearWeatherTypePersist()
    if Config.ForcePrecipitationLevels == true then
        SetRainLevel(0.0)
        SetSnowLevel(0.0)
        if type(SetRainFxIntensity) == 'function' then
            SetRainFxIntensity(-1.0)
        end
    end
    PauseClock(false)
end)
