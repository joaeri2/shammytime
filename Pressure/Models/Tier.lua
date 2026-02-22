local addonName = ...
if addonName ~= "ShammyTime" then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

local ShammyTime = _G.ShammyTime
if not ShammyTime then return end

local Models = ShammyTime.PressureModels
if not Models then return end

function Models.CreateTierModel(ctx)
    local PS = ctx.PS
    local PUSH_FEEL_CFG = ctx.PUSH_FEEL_CFG
    local SmoothAlpha = ctx.SmoothAlpha
    local GetPressurePopupDBNumber = ctx.GetPressurePopupDBNumber
    local math_max = ctx.math_max
    local math_min = ctx.math_min

    local model = {}

    local OVERDRIVE_SAMPLE_CAP = 100
    local TIER_REQUIREMENT_SCALE = 0.68
    local TIER_STEP_GAIN = 0.84
    local OVERDRIVE_WARMUP_EXTRA_THRESHOLD = 0.60
    -- Single shared resistance curve across all tiers.
    -- Tier difficulty should come from thresholds, not per-tier special cases.
    local RESIST_BASE_GAIN = 0.031
    local RESIST_BASE_POWER = 1.22
    local RESIST_EDGE_START = 0.80
    local RESIST_EDGE_POWER = 1.95
    local RESIST_EDGE_GAIN = 0.055
    local IDLE_SLIP_GAIN = 0.035
    local DPS_LIVE_WINDOW_SEC = 5
    local DPS_MEDIAN_WINDOW_SEC = 30
    local DPS_RETENTION_SEC = 90
    local overdriveSamples = {}
    local overdriveHead = 1
    local overdriveCount = 0
    local overdrivePendingTierBoost = 0
    local overdriveLockUntil = 0
    local overdriveCache = {
        dirty = true,
        count = 0,
        sorted = {},
    }
    local dpsFightDamage = 0
    local dpsFightStartAt = 0
    local dpsBins = {}
    local dpsScratch = {}
    local dpsScratchCount = 0
    local lastDpsTelemetrySecond = -1
    local dpsCombatActive = false
    local dpsLockedUntil = 0
    local dpsLockedCurrent = 0
    local dpsLockedFight = 0
    local dpsLockedMedian = 0
    local dpsLockedAbovePct = 0
    local SIMPLE_DEFAULTS = {
        resistance = 1.25,
        rubberband = 1.10,
        tierBase = 2.03,
        tierStepPct = 11.00,
        tierHelp = 0.85,
        holdSec = 6.00,
        overdrivePercentile = 98.00,
        overdriveMultiplier = 1.16,
        shakeAmount = 1.00,
        shakeFromDamage = 0.85,
    }

    local function Clamp(value, minValue, maxValue)
        if value < minValue then return minValue end
        if value > maxValue then return maxValue end
        return value
    end

    local function GetSimpleDifficulty(resistance, rubberband)
        -- Normalize the two knobs into one scalar so default 1.0/1.0 is not overly punitive.
        return math_max(((resistance or 1) + (rubberband or 1)) * 0.65, 0.10)
    end

    local function PctDelta(value, baseline)
        local b = baseline or 0
        if b < 0.00001 and b > -0.00001 then
            return 0
        end
        return ((value or 0) / b - 1) * 100
    end

    local BuildSimpleThresholds

    local function BuildDerivedSnapshot(resistance, rubberband, tierBase, tierStepPct, tierHelp, overdriveMultiplier, shakeAmount, shakeFromDamage)
        local tierStepFrac = math_max((tierStepPct or 0) / 100, 0.001)
        local thresholds = BuildSimpleThresholds(tierBase, resistance, rubberband, tierStepFrac)
        local difficulty = GetSimpleDifficulty(resistance, rubberband)
        local resistanceScale = 0.46 + ((resistance or 1) * 0.52)
        local transferDropSec = 1.25 + ((rubberband or 1) * 4.00)
        local transferDamping = Clamp(5.80 - ((rubberband or 1) * 1.30), 1.00, 10.00)
        local transferOsc = Clamp(0.85 + ((rubberband or 1) * 0.90), 0.30, 5.00)
        local springiness = (transferDropSec * transferOsc) / math_max(transferDamping, 0.01)
        local landingFloor = Clamp(0.10 + ((tierHelp or 0) * 0.06), 0.00, 0.80)
        local helpMax = 0.10 + ((tierHelp or 0) * 0.30)
        local overloadThreshold = 1.00 + (((overdriveMultiplier or 1.10) - 1.00) * 0.75)
        local shakeCoupling = (shakeAmount or 0) * (shakeFromDamage or 0)

        return {
            difficulty = difficulty,
            thresholds = thresholds,
            resistanceScale = resistanceScale,
            transferDropSec = transferDropSec,
            transferDamping = transferDamping,
            transferOsc = transferOsc,
            springiness = springiness,
            landingFloor = landingFloor,
            helpMax = helpMax,
            overloadThreshold = overloadThreshold,
            shakeCoupling = shakeCoupling,
        }
    end

    local function PushOverdriveSample(hitAmount)
        overdriveSamples[overdriveHead] = hitAmount
        overdriveHead = overdriveHead + 1
        if overdriveHead > OVERDRIVE_SAMPLE_CAP then
            overdriveHead = 1
        end
        if overdriveCount < OVERDRIVE_SAMPLE_CAP then
            overdriveCount = overdriveCount + 1
        end
        overdriveCache.dirty = true
    end

    local function RebuildOverdriveCache()
        if not overdriveCache.dirty then
            return
        end
        local sorted = overdriveCache.sorted
        local oldCount = overdriveCache.count or 0
        for i = oldCount, 1, -1 do
            sorted[i] = nil
        end

        local count = 0
        for i = 1, overdriveCount do
            local v = overdriveSamples[i]
            if v and v > 0 then
                count = count + 1
                sorted[count] = v
            end
        end

        if count > 1 then
            table.sort(sorted)
        end
        overdriveCache.count = count
        overdriveCache.dirty = false
    end

    local function GetOverdriveRefs(percentile)
        if overdriveCount <= 0 then
            return 0, 0
        end
        RebuildOverdriveCache()
        local sorted = overdriveCache.sorted
        local count = overdriveCache.count or 0
        if count <= 0 then
            return 0, 0
        end

        local pct = Clamp(percentile or 0.95, 0.50, 0.999)
        local pctRank = math.floor(((count - 1) * pct) + 1.5)
        pctRank = Clamp(pctRank, 1, count)

        local medianRank = math.floor(((count - 1) * 0.50) + 1.5)
        medianRank = Clamp(medianRank, 1, count)

        return sorted[pctRank] or 0, sorted[medianRank] or 0
    end

    local function ClearDpsBuffers()
        for sec, _ in pairs(dpsBins) do
            dpsBins[sec] = nil
        end
        for i = dpsScratchCount, 1, -1 do
            dpsScratch[i] = nil
        end
        dpsScratchCount = 0
    end

    local function ResetDpsTelemetry(startAt)
        dpsFightDamage = 0
        dpsFightStartAt = startAt or 0
        lastDpsTelemetrySecond = -1
        PS.debugCurrentDps = 0
        PS.debugFightDps = 0
        PS.debugMedianDps = 0
        PS.debugDpsAbovePct = 0
        ClearDpsBuffers()
    end

    local function UpdateDpsTelemetry(now)
        local tNow = now or 0
        if (not dpsCombatActive) and dpsLockedUntil > 0 then
            if tNow <= dpsLockedUntil then
                PS.debugCurrentDps = dpsLockedCurrent or 0
                PS.debugFightDps = dpsLockedFight or 0
                PS.debugMedianDps = dpsLockedMedian or 0
                PS.debugDpsAbovePct = dpsLockedAbovePct or 0
                return
            end
            dpsLockedUntil = 0
            dpsLockedCurrent = 0
            dpsLockedFight = 0
            dpsLockedMedian = 0
            dpsLockedAbovePct = 0
            ResetDpsTelemetry(0)
            return
        end

        local secNow = math.floor(now or 0)
        if secNow <= 0 then
            ResetDpsTelemetry(0)
            return
        end
        if secNow == lastDpsTelemetrySecond then
            return
        end
        lastDpsTelemetrySecond = secNow

        local liveWindow = math_max(PS.debugDpsLiveWindowSec or DPS_LIVE_WINDOW_SEC, 1)
        local medianWindow = math_max(PS.debugDpsMedianWindowSec or DPS_MEDIAN_WINDOW_SEC, 1)
        local function GetWindowDpsAt(sec)
            local sum = 0
            for s = sec - liveWindow + 1, sec do
                sum = sum + (dpsBins[s] or 0)
            end
            return sum / liveWindow
        end
        local currentDps = GetWindowDpsAt(secNow)
        local fightDps = 0
        if dpsFightStartAt and dpsFightStartAt > 0 and dpsFightDamage > 0 then
            local fightSec = math_max((now or 0) - dpsFightStartAt, 0.25)
            fightDps = dpsFightDamage / fightSec
        end

        local count = 0
        for s = secNow - medianWindow + 1, secNow do
            local sampleDps = GetWindowDpsAt(s)
            if sampleDps > 0.0001 then
                count = count + 1
                dpsScratch[count] = sampleDps
            end
        end
        for i = count + 1, dpsScratchCount do
            dpsScratch[i] = nil
        end
        dpsScratchCount = count

        local medianDps = 0
        if count > 0 then
            table.sort(dpsScratch)
            if (count % 2) == 1 then
                medianDps = dpsScratch[(count + 1) / 2]
            else
                medianDps = (dpsScratch[count / 2] + dpsScratch[(count / 2) + 1]) * 0.5
            end
        end

        local abovePct = 0
        if medianDps > 0 then
            abovePct = ((currentDps / medianDps) - 1) * 100
        end

        PS.debugCurrentDps = currentDps
        PS.debugFightDps = fightDps
        PS.debugMedianDps = medianDps
        PS.debugDpsAbovePct = abovePct
    end

    local function PushDpsSample(hitAmount, now)
        local secNow = math.floor(now or 0)
        if secNow <= 0 then
            return
        end
        if dpsFightStartAt <= 0 then
            dpsFightStartAt = now or 0
            dpsFightDamage = 0
        end
        dpsFightDamage = dpsFightDamage + hitAmount
        dpsBins[secNow] = (dpsBins[secNow] or 0) + hitAmount
        local cutoff = secNow - math_max(PS.debugDpsRetentionSec or DPS_RETENTION_SEC, 1)
        for sec, _ in pairs(dpsBins) do
            if sec < cutoff then
                dpsBins[sec] = nil
            end
        end
        UpdateDpsTelemetry(now)
    end

    BuildSimpleThresholds = function(baseDamage, resistance, rubberband, tierStepFrac)
        local thresholds = {}
        local base = math_max((baseDamage or 1.50) * TIER_REQUIREMENT_SCALE, 0.01)
        local step = math_max(tierStepFrac or 0, 0.001)
        local difficulty = GetSimpleDifficulty(resistance, rubberband)
        local perTierGain = math_max(difficulty * step * TIER_STEP_GAIN, 0.01)
        local tierFactor = 1 + perTierGain

        thresholds[1] = base
        for tier = 2, 5 do
            thresholds[tier] = thresholds[tier - 1] * tierFactor
        end
        return thresholds
    end

    function model.GetTier(score)
        for i = #PS.tierThresholds, 1, -1 do
            if score >= PS.tierThresholds[i] then return i end
        end
        return 0
    end

    function model.GetPromoteThreshold(tier)
        if tier <= 0 then return 0 end
        return PS.tierThresholds[tier] or PS.tierThresholds[#PS.tierThresholds]
    end

    function model.GetDemoteThreshold(tier)
        if tier <= 0 then return -math.huge end
        return model.GetPromoteThreshold(tier) - PS.tierHysteresis
    end

    function model.GetTierFillTarget(score, tier)
        local clampedTier = math_min(math_max(tier or 0, 0), 5)
        if clampedTier >= 5 then
            local t5Req = model.GetPromoteThreshold(5)
            return math_min(math_max((score or 0) / math_max(t5Req, 0.001), 0), 1)
        end

        local lower
        if clampedTier <= 0 then
            lower = 0
        else
            lower = model.GetPromoteThreshold(clampedTier)
        end
        local upper = model.GetPromoteThreshold(clampedTier + 1)
        local span = math_max(upper - lower, 0.001)

        return math_min(math_max(((score or 0) - lower) / span, 0), 1)
    end

    function model.GetTierSegmentProgress(score)
        local s = score or 0
        local lower = 0
        for i = 1, #PS.tierThresholds do
            local upper = PS.tierThresholds[i]
            if s < upper then
                local span = math_max(upper - lower, 0.001)
                local frac = math_min(math_max((s - lower) / span, 0), 1)
                return i - 1, frac
            end
            lower = upper
        end
        return #PS.tierThresholds, 1
    end

    function model.GetTierResistanceAndSlip(score, now)
        local segTier, segFrac = model.GetTierSegmentProgress(score)
        if segTier >= #PS.tierThresholds then
            PS.tierEdgeResistMax = 0.001
            return 0, 0
        end

        local pressureScale = GetSimpleDifficulty(PS.simpleResistance or 1, PS.simpleRubberband or 1)

        local baseCurve = (segFrac ^ RESIST_BASE_POWER) * RESIST_BASE_GAIN
        local edgeCurve = 0
        if segFrac > RESIST_EDGE_START then
            local q = (segFrac - RESIST_EDGE_START) / math_max(1 - RESIST_EDGE_START, 0.001)
            edgeCurve = (q ^ RESIST_EDGE_POWER) * RESIST_EDGE_GAIN
        end

        local resistance = (baseCurve + edgeCurve) * pressureScale
        resistance = resistance * math_max(PUSH_FEEL_CFG.resistanceScale or 1, 0)

        PS.tierEdgeResistMax = math_max(0.22 * pressureScale, 0.001)

        local slip = 0
        local idleGrace = math_max(PS.tierMomentumIdleGrace or 0.90, 0)
        if (now - (PS.lastDamageTime or 0)) > idleGrace and segFrac > 0.65 then
            local q = (segFrac - 0.65) / 0.35
            local idleFor = (now - (PS.lastDamageTime or 0)) - idleGrace
            local holdSec = math_max(PS.tierHoldMinSec or 6.00, 0.20)
            local idleScale = math_min(idleFor / holdSec, 1)
            slip = (q ^ 1.20) * (IDLE_SLIP_GAIN * math_max(PS.simpleRubberband or 1, 0)) * idleScale
        end

        return resistance, slip
    end

    function model.UpdateTierMomentumBonus(elapsed, now)
        local target = 0
        if (PS.currentTier or 0) >= 1 then
            target = math_min(
                (PS.simpleTierHelpPerTier or 0) * PS.currentTier,
                math_max(PS.simpleTierHelpMax or 0, 0)
            )
        end

        local decayTau = PS.simpleTierHelpDecayTau or 4.20
        local idleGrace = math_max(PS.tierMomentumIdleGrace or 0.90, 0)
        if (now - (PS.lastDamageTime or 0)) > idleGrace then
            decayTau = PS.simpleTierHelpIdleDecayTau or decayTau
        end

        PS.tierMomentumBoost = SmoothAlpha(
            PS.tierMomentumBoost or 0,
            target,
            elapsed,
            PS.simpleTierHelpBuildTau or 0.45,
            decayTau
        )
    end

    function model.RecordDamageEvent(amount, now)
        local hitAmount = tonumber(amount) or 0
        if hitAmount <= 0 then return end
        PushDpsSample(hitAmount, now)

        local minSamples = PS.simpleOverdriveMinSamples or 40
        local warmupDen = math_max(OVERDRIVE_SAMPLE_CAP - minSamples, 1)
        local warmupProgress = Clamp((overdriveCount - minSamples) / warmupDen, 0, 1)
        local percentileRef = 0
        local medianRef = 0
        local threshold = 0
        PS.overdriveSampleCount = overdriveCount
        PS.overdriveWarmup = warmupProgress
        if overdriveCount >= minSamples then
            percentileRef, medianRef = GetOverdriveRefs(PS.simpleOverdrivePercentile or 0.95)
            threshold = math_max(
                percentileRef * math_max(PS.simpleOverdriveMultiplier or 1.10, 1.00),
                PS.simpleOverdriveFloor or 1
            )
            threshold = math_max(
                threshold,
                medianRef * (1.65 + ((math_max(PS.simpleOverdriveMultiplier or 1.10, 1.00) - 1.00) * 1.50))
            )
            -- Overdrive starts stricter and ramps toward normal behavior as the hit history fills.
            local warmupMultiplier = 1 + ((1 - warmupProgress) * OVERDRIVE_WARMUP_EXTRA_THRESHOLD)
            threshold = threshold * warmupMultiplier
            if threshold > 0 and (now or 0) >= overdriveLockUntil and hitAmount >= threshold then
                local tierBoost = 1
                overdrivePendingTierBoost = math_max(overdrivePendingTierBoost, tierBoost)
                overdriveLockUntil = (now or 0) + (PS.simpleOverdriveCooldownSec or 0.85)
            end
        end

        PushOverdriveSample(hitAmount)
        PS.overdriveSampleCount = overdriveCount
        PS.overdriveWarmup = Clamp((overdriveCount - minSamples) / warmupDen, 0, 1)
        PS.debugOverdriveHitPercentileRef = percentileRef
        PS.debugOverdriveHitMedianRef = medianRef
        PS.debugOverdriveHitThreshold = threshold
        PS.debugOverdriveLastHit = hitAmount
        if threshold > 0 then
            PS.debugOverdriveHitAbovePct = ((hitAmount / threshold) - 1) * 100
        else
            PS.debugOverdriveHitAbovePct = 0
        end
    end

    function model.ConsumeOverdriveTierBoost()
        local boost = overdrivePendingTierBoost or 0
        overdrivePendingTierBoost = 0
        return boost
    end

    function model.ResetRuntime(clearHistory)
        overdrivePendingTierBoost = 0
        overdriveLockUntil = 0
        local minSamples = PS.simpleOverdriveMinSamples or 40
        local warmupDen = math_max(OVERDRIVE_SAMPLE_CAP - minSamples, 1)
        PS.overdriveSampleCount = overdriveCount
        PS.overdriveWarmup = Clamp((overdriveCount - minSamples) / warmupDen, 0, 1)
        overdriveCache.dirty = true
        dpsCombatActive = false
        dpsLockedUntil = 0
        dpsLockedCurrent = 0
        dpsLockedFight = 0
        dpsLockedMedian = 0
        dpsLockedAbovePct = 0
        ResetDpsTelemetry(0)
        if clearHistory then
            for i = 1, OVERDRIVE_SAMPLE_CAP do
                overdriveSamples[i] = nil
            end
            overdriveHead = 1
            overdriveCount = 0
            local sorted = overdriveCache.sorted
            for i = overdriveCache.count, 1, -1 do
                sorted[i] = nil
            end
            overdriveCache.count = 0
            PS.overdriveSampleCount = 0
            PS.overdriveWarmup = 0
            PS.debugOverdriveHitPercentileRef = 0
            PS.debugOverdriveHitMedianRef = 0
            PS.debugOverdriveHitThreshold = 0
            PS.debugOverdriveLastHit = 0
            PS.debugOverdriveHitAbovePct = 0
        end
    end

    function model.StartCombatDamageMeter(now)
        dpsCombatActive = true
        dpsLockedUntil = 0
        ResetDpsTelemetry(now or 0)
    end

    function model.EndCombatDamageMeter(now, holdSec)
        UpdateDpsTelemetry(now or 0)
        dpsCombatActive = false
        local duration = math_max(tonumber(holdSec) or 10, 0)
        dpsLockedCurrent = PS.debugCurrentDps or 0
        dpsLockedFight = PS.debugFightDps or 0
        dpsLockedMedian = PS.debugMedianDps or 0
        dpsLockedAbovePct = PS.debugDpsAbovePct or 0
        dpsLockedUntil = (now or 0) + duration
    end

    function model.UpdateDebugTelemetry(now)
        UpdateDpsTelemetry(now)
    end

    function model.ApplyTuningSettings()
        local resistance = GetPressurePopupDBNumber("pressureSimpleResistance", 1.25, 0.20, 4.00)
        local rubberband = GetPressurePopupDBNumber("pressureSimpleRubberband", 1.10, 0.20, 3.00)
        local tierBase = GetPressurePopupDBNumber("pressureSimpleTierBase", 2.03, 0.20, 10.00)
        local tierStepPct = GetPressurePopupDBNumber("pressureSimpleTierStepPct", 11.00, 1.00, 30.00)
        local tierHelp = GetPressurePopupDBNumber("pressureSimpleTierHelp", 0.85, 0.00, 3.00)
        local holdSec = GetPressurePopupDBNumber("pressureSimpleTierHoldSec", 6.00, 0.10, 15.00)
        local overdrivePercentile = GetPressurePopupDBNumber("pressureSimpleOverdrivePercentile", 98.00, 85.00, 99.50)
        local overdriveMultiplier = GetPressurePopupDBNumber("pressureSimpleOverdriveMultiplier", 1.16, 1.00, 3.00)
        local shakeAmount = GetPressurePopupDBNumber("pressureSimpleShakeAmount", 1.00, 0.00, 2.50)
        local shakeFromDamage = GetPressurePopupDBNumber("pressureSimpleShakeFromDamage", 0.85, 0.00, 3.00)
        local tierStepFrac = tierStepPct / 100

        PS.simpleResistance = resistance
        PS.simpleRubberband = rubberband
        PS.simpleTierBase = tierBase
        PS.simpleTierStepPct = tierStepPct
        PS.simpleTierHelp = tierHelp
        PS.simpleTierHoldSec = holdSec
        PS.simpleShakeAmount = shakeAmount
        PS.simpleShakeFromDamage = shakeFromDamage
        PS.simpleTierStepFrac = tierStepFrac
        PS.tierThresholds = BuildSimpleThresholds(tierBase, resistance, rubberband, tierStepFrac)

        -- Simple mode: no hidden squeeze gate. Tier ups should follow bar/score directly.
        PS.tierMinSqueeze = { 0, 0, 0, 0, 0, 0 }
        PS.tierMinActiveSec = { 0, 0, 0, 0, 0, 0 }
        local effectiveHoldSec = math_max(holdSec, 2.50)
        PS.tierHoldMinSec = effectiveHoldSec

        PS.simpleTierHelpPerTier = 0.015 + (tierHelp * 0.022)
        PS.simpleTierHelpMax = 0.08 + (tierHelp * 0.22)
        PS.simpleTierHelpBuildTau = 0.45
        PS.simpleTierHelpDecayTau = 2.80 + (tierHelp * 1.20)
        PS.simpleTierHelpIdleDecayTau = 1.40 + (tierHelp * 0.70)
        PS.tierMomentumOnPromote = 0.035 + (tierHelp * 0.035)
        PS.tierMomentumMax = math_max(PS.simpleTierHelpMax, 0.10)
        PS.tierMomentumIdleGrace = 0.90

        PS.simpleOverdrivePercentile = overdrivePercentile / 100
        PS.simpleOverdriveMultiplier = overdriveMultiplier
        PS.simpleOverdriveMinSamples = 40
        PS.simpleOverdriveSampleCap = OVERDRIVE_SAMPLE_CAP
        PS.simpleOverdriveFloor = 1
        PS.simpleOverdriveCooldownSec = 0.85
        PS.debugDpsLiveWindowSec = DPS_LIVE_WINDOW_SEC
        PS.debugDpsMedianWindowSec = DPS_MEDIAN_WINDOW_SEC
        PS.debugDpsRetentionSec = DPS_RETENTION_SEC
        PS.debugFightDps = PS.debugFightDps or 0
        lastDpsTelemetrySecond = -1

        PUSH_FEEL_CFG.fillMass = 1.10 + (resistance * 0.95)
        PUSH_FEEL_CFG.resistanceScale = 0.46 + (resistance * 0.52)
        PUSH_FEEL_CFG.fillTransferDropSec = 1.25 + (rubberband * 4.00)
        PUSH_FEEL_CFG.fillTransferRubberDamping = Clamp(5.80 - (rubberband * 1.30), 1.00, 10.00)
        PUSH_FEEL_CFG.fillTransferRubberOscillations = Clamp(0.85 + (rubberband * 0.90), 0.30, 5.00)
        PUSH_FEEL_CFG.fillTransferLandingFloor = Clamp(0.10 + (tierHelp * 0.06), 0.00, 0.80)
        PUSH_FEEL_CFG.fillPullResistStart = Clamp(0.70 + ((resistance - 1.00) * 0.05), 0.58, 0.86)
        PUSH_FEEL_CFG.fillPullLowerPower = 1.18 + (resistance * 0.20)
        PUSH_FEEL_CFG.fillPullEdgePower = 1.65 + (resistance * 0.72)
        PUSH_FEEL_CFG.gaugeShakeAmount = shakeAmount
        PUSH_FEEL_CFG.gaugeShakeDamageScale = shakeFromDamage
        PUSH_FEEL_CFG.overloadThreshold = 1.00 + ((overdriveMultiplier - 1.00) * 0.75)

        do
            local current = BuildDerivedSnapshot(
                resistance,
                rubberband,
                tierBase,
                tierStepPct,
                tierHelp,
                overdriveMultiplier,
                shakeAmount,
                shakeFromDamage
            )
            local defaults = BuildDerivedSnapshot(
                SIMPLE_DEFAULTS.resistance,
                SIMPLE_DEFAULTS.rubberband,
                SIMPLE_DEFAULTS.tierBase,
                SIMPLE_DEFAULTS.tierStepPct,
                SIMPLE_DEFAULTS.tierHelp,
                SIMPLE_DEFAULTS.overdriveMultiplier,
                SIMPLE_DEFAULTS.shakeAmount,
                SIMPLE_DEFAULTS.shakeFromDamage
            )

            PS.debugTune = {
                resistance = resistance,
                rubberband = rubberband,
                tierBase = tierBase,
                tierStepPct = tierStepPct,
                tierHelp = tierHelp,
                holdSec = effectiveHoldSec,
                overdrivePercentile = overdrivePercentile,
                overdriveMultiplier = overdriveMultiplier,
                shakeAmount = shakeAmount,
                shakeFromDamage = shakeFromDamage,

                resistanceScalePct = PctDelta(current.resistanceScale, defaults.resistanceScale),
                difficultyPct = PctDelta(current.difficulty, defaults.difficulty),
                t1Pct = PctDelta(current.thresholds[1], defaults.thresholds[1]),
                t2Pct = PctDelta(current.thresholds[2], defaults.thresholds[2]),
                t3Pct = PctDelta(current.thresholds[3], defaults.thresholds[3]),
                t4Pct = PctDelta(current.thresholds[4], defaults.thresholds[4]),
                t5Pct = PctDelta(current.thresholds[5], defaults.thresholds[5]),
                springinessPct = PctDelta(current.springiness, defaults.springiness),
                transferDropPct = PctDelta(current.transferDropSec, defaults.transferDropSec),
                transferDampingPct = PctDelta(current.transferDamping, defaults.transferDamping),
                transferOscPct = PctDelta(current.transferOsc, defaults.transferOsc),
                helpMaxPct = PctDelta(current.helpMax, defaults.helpMax),
                landingFloorPct = PctDelta(current.landingFloor, defaults.landingFloor),
                overdriveThresholdPct = PctDelta(current.overloadThreshold, defaults.overloadThreshold),
                shakeCouplingPct = PctDelta(current.shakeCoupling, defaults.shakeCoupling),

                t1Req = current.thresholds[1],
                t2Req = current.thresholds[2],
                t3Req = current.thresholds[3],
                t4Req = current.thresholds[4],
                t5Req = current.thresholds[5],
                transferDropSec = current.transferDropSec,
                transferDamping = current.transferDamping,
                transferOsc = current.transferOsc,
            }
        end
    end

    return model
end
