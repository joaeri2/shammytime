local addonName = ...
if addonName ~= "ShammyTime" then return end

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
    local overdriveSamples = {}
    local overdriveHead = 1
    local overdriveCount = 0
    local overdrivePendingTierBoost = 0
    local overdriveLockUntil = 0
    local SIMPLE_DEFAULTS = {
        resistance = 0.85,
        rubberband = 1.00,
        tierBase = 1.50,
        tierStepPct = 8.00,
        tierHelp = 1.15,
        holdSec = 2.20,
        overdrivePercentile = 97.00,
        overdriveMultiplier = 1.10,
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
        local resistanceScale = 0.55 + ((resistance or 1) * 0.45)
        local transferDropSec = 0.30 + ((rubberband or 1) * 0.46)
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
    end

    local function GetOverdrivePercentileValue(percentile)
        if overdriveCount <= 0 then
            return 0
        end
        local tmp = {}
        for i = 1, overdriveCount do
            local v = overdriveSamples[i]
            if v and v > 0 then
                tmp[#tmp + 1] = v
            end
        end
        local count = #tmp
        if count <= 0 then
            return 0
        end
        table.sort(tmp)
        local pct = Clamp(percentile or 0.95, 0.50, 0.999)
        local rank = math.floor(((count - 1) * pct) + 1.5)
        rank = Clamp(rank, 1, count)
        return tmp[rank]
    end

    BuildSimpleThresholds = function(baseDamage, resistance, rubberband, tierStepFrac)
        local thresholds = {}
        local base = math_max(baseDamage or 1.50, 0.01)
        local step = math_max(tierStepFrac or 0, 0.001)
        local difficulty = GetSimpleDifficulty(resistance, rubberband)
        for tier = 1, 5 do
            if tier <= 1 then
                thresholds[tier] = base
            else
                -- Simple shared curve across tiers:
                -- base * (1 + (resistance + rubberband) * tierIndex * step%)
                local tierIndex = tier - 1
                local tierMult = 1 + (difficulty * tierIndex * step)
                thresholds[tier] = base * tierMult
            end
        end
        for i = 2, #thresholds do
            local minNext = thresholds[i - 1] + 0.01
            if thresholds[i] < minNext then
                thresholds[i] = minNext
            end
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
            return 1
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

        local tierScale = 1 + (segTier * math_max(PS.simpleTierStepFrac or 0.10, 0.01))
        local pressureScale = GetSimpleDifficulty(PS.simpleResistance or 1, PS.simpleRubberband or 1)

        local baseCurve = (segFrac ^ 1.20) * 0.035
        local edgeCurve = 0
        if segFrac > 0.82 then
            local q = (segFrac - 0.82) / 0.18
            edgeCurve = (q ^ 2.00) * 0.16
        end

        local resistance = (baseCurve + edgeCurve) * pressureScale * tierScale
        resistance = resistance * math_max(PUSH_FEEL_CFG.resistanceScale or 1, 0)

        local maxTierScale = 1 + (5 * math_max(PS.simpleTierStepFrac or 0.10, 0.01))
        PS.tierEdgeResistMax = math_max((0.20 * pressureScale) * maxTierScale, 0.001)

        local slip = 0
        local idleGrace = math_max(PS.tierMomentumIdleGrace or 0.70, 0)
        if (now - (PS.lastDamageTime or 0)) > idleGrace and segFrac > 0.65 then
            local q = (segFrac - 0.65) / 0.35
            local idleFor = (now - (PS.lastDamageTime or 0)) - idleGrace
            local holdSec = math_max(PS.tierHoldMinSec or 2.20, 0.20)
            local idleScale = math_min(idleFor / holdSec, 1)
            slip = (q ^ 1.20) * (0.05 * math_max(PS.simpleRubberband or 1, 0)) * tierScale * idleScale
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

        local decayTau = PS.simpleTierHelpDecayTau or 3.20
        local idleGrace = math_max(PS.tierMomentumIdleGrace or 0.70, 0)
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

        local minSamples = PS.simpleOverdriveMinSamples or 40
        if overdriveCount >= minSamples then
            local percentileRef = GetOverdrivePercentileValue(PS.simpleOverdrivePercentile or 0.95)
            local medianRef = GetOverdrivePercentileValue(0.50)
            local threshold = math_max(
                percentileRef * math_max(PS.simpleOverdriveMultiplier or 1.10, 1.00),
                PS.simpleOverdriveFloor or 1
            )
            threshold = math_max(
                threshold,
                medianRef * (1.65 + ((math_max(PS.simpleOverdriveMultiplier or 1.10, 1.00) - 1.00) * 1.50))
            )
            if threshold > 0 and (now or 0) >= overdriveLockUntil and hitAmount >= threshold then
                local tierBoost = 1
                overdrivePendingTierBoost = math_max(overdrivePendingTierBoost, tierBoost)
                overdriveLockUntil = (now or 0) + (PS.simpleOverdriveCooldownSec or 0.85)
            end
        end

        PushOverdriveSample(hitAmount)
    end

    function model.ConsumeOverdriveTierBoost()
        local boost = overdrivePendingTierBoost or 0
        overdrivePendingTierBoost = 0
        return boost
    end

    function model.ResetRuntime(clearHistory)
        overdrivePendingTierBoost = 0
        overdriveLockUntil = 0
        if clearHistory then
            for i = 1, OVERDRIVE_SAMPLE_CAP do
                overdriveSamples[i] = nil
            end
            overdriveHead = 1
            overdriveCount = 0
        end
    end

    function model.ApplyTuningSettings()
        local resistance = GetPressurePopupDBNumber("pressureSimpleResistance", 0.85, 0.20, 4.00)
        local rubberband = GetPressurePopupDBNumber("pressureSimpleRubberband", 1.00, 0.20, 3.00)
        local tierBase = GetPressurePopupDBNumber("pressureSimpleTierBase", 1.50, 0.20, 10.00)
        local tierStepPct = GetPressurePopupDBNumber("pressureSimpleTierStepPct", 8.00, 1.00, 30.00)
        local tierHelp = GetPressurePopupDBNumber("pressureSimpleTierHelp", 1.15, 0.00, 3.00)
        local holdSec = GetPressurePopupDBNumber("pressureSimpleTierHoldSec", 2.20, 0.10, 15.00)
        local overdrivePercentile = GetPressurePopupDBNumber("pressureSimpleOverdrivePercentile", 97.00, 85.00, 99.50)
        local overdriveMultiplier = GetPressurePopupDBNumber("pressureSimpleOverdriveMultiplier", 1.10, 1.00, 3.00)
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
        PS.tierHoldMinSec = holdSec

        PS.simpleTierHelpPerTier = 0.02 + (tierHelp * 0.03)
        PS.simpleTierHelpMax = 0.10 + (tierHelp * 0.30)
        PS.simpleTierHelpBuildTau = 0.45
        PS.simpleTierHelpDecayTau = 2.60 + (tierHelp * 1.20)
        PS.simpleTierHelpIdleDecayTau = 0.85 + (tierHelp * 0.45)
        PS.tierMomentumOnPromote = 0.04 + (tierHelp * 0.04)
        PS.tierMomentumMax = math_max(PS.simpleTierHelpMax, 0.10)
        PS.tierMomentumIdleGrace = 0.70

        PS.simpleOverdrivePercentile = overdrivePercentile / 100
        PS.simpleOverdriveMultiplier = overdriveMultiplier
        PS.simpleOverdriveMinSamples = 40
        PS.simpleOverdriveFloor = 1
        PS.simpleOverdriveCooldownSec = 0.85

        PUSH_FEEL_CFG.fillMass = 1.05 + (resistance * 0.85)
        PUSH_FEEL_CFG.resistanceScale = 0.55 + (resistance * 0.45)
        PUSH_FEEL_CFG.fillTransferDropSec = 0.30 + (rubberband * 0.46)
        PUSH_FEEL_CFG.fillTransferRubberDamping = Clamp(5.80 - (rubberband * 1.30), 1.00, 10.00)
        PUSH_FEEL_CFG.fillTransferRubberOscillations = Clamp(0.85 + (rubberband * 0.90), 0.30, 5.00)
        PUSH_FEEL_CFG.fillTransferLandingFloor = Clamp(0.10 + (tierHelp * 0.06), 0.00, 0.80)
        PUSH_FEEL_CFG.fillPullResistStart = Clamp(0.72 + ((resistance - 1.00) * 0.04), 0.60, 0.88)
        PUSH_FEEL_CFG.fillPullLowerPower = 1.10 + (resistance * 0.12)
        PUSH_FEEL_CFG.fillPullEdgePower = 1.45 + (resistance * 0.45)
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
                holdSec = holdSec,
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
