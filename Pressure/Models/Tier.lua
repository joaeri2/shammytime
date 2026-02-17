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

    local function Clamp(value, minValue, maxValue)
        if value < minValue then return minValue end
        if value > maxValue then return maxValue end
        return value
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

    local function BuildSimpleThresholds(baseDamage, tierStepFrac)
        local thresholds = {}
        local stepMult = 1 + math_max(tierStepFrac or 0, 0)
        local current = math_max(baseDamage or 1.50, 0.01)
        for i = 1, 5 do
            thresholds[i] = current
            current = current * stepMult
        end
        return thresholds
    end

    local function BuildSimpleForceReq(resistance, rubberband, tierStepFrac)
        local req = {}
        local scalar = math_max((resistance + rubberband) * math_max(tierStepFrac, 0.01), 0.01)
        for tier = 1, 5 do
            if tier <= 1 then
                req[tier] = 0
            else
                req[tier] = math_min((tier - 1) * scalar, 0.95)
            end
        end
        return req
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
        local pressureScale = math_max((PS.simpleResistance or 1) + (PS.simpleRubberband or 1), 0.10)

        local baseCurve = (segFrac ^ 1.25) * 0.05
        local edgeCurve = 0
        if segFrac > 0.80 then
            local q = (segFrac - 0.80) / 0.20
            edgeCurve = (q ^ 2.20) * 0.24
        end

        local resistance = (baseCurve + edgeCurve) * pressureScale * tierScale
        resistance = resistance * math_max(PUSH_FEEL_CFG.resistanceScale or 1, 0)

        local maxTierScale = 1 + (5 * math_max(PS.simpleTierStepFrac or 0.10, 0.01))
        PS.tierEdgeResistMax = math_max((0.30 * pressureScale) * maxTierScale, 0.001)

        local slip = 0
        local idleGrace = math_max(PS.tierMomentumIdleGrace or 0.70, 0)
        if (now - (PS.lastDamageTime or 0)) > idleGrace and segFrac > 0.65 then
            local q = (segFrac - 0.65) / 0.35
            local idleFor = (now - (PS.lastDamageTime or 0)) - idleGrace
            local holdSec = math_max(PS.tierHoldMinSec or 2.20, 0.20)
            local idleScale = math_min(idleFor / holdSec, 1)
            slip = (q ^ 1.25) * (0.08 * math_max(PS.simpleRubberband or 1, 0)) * tierScale * idleScale
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

    function model.GetGateCappedTier(candidateTier, squeeze, activeSec)
        local capped = candidateTier
        local reason = "ok"
        while capped > 0 do
            local idx = capped + 1
            local needSqueeze = PS.tierMinSqueeze[idx] or 0
            local needTime = PS.tierMinActiveSec[idx] or 0
            local hasSqueeze = squeeze >= needSqueeze
            local hasTime = activeSec >= needTime
            if hasSqueeze and hasTime then
                break
            end
            if not hasSqueeze and not hasTime then
                reason = string.format("sqz<%.2f&t<%.0f", needSqueeze, needTime)
            elseif not hasSqueeze then
                reason = string.format("sqz<%.2f", needSqueeze)
            else
                reason = string.format("t<%.0f", needTime)
            end
            capped = capped - 1
        end
        return capped, reason
    end

    function model.RecordDamageEvent(amount, now)
        local hitAmount = tonumber(amount) or 0
        if hitAmount <= 0 then return end

        local minSamples = PS.simpleOverdriveMinSamples or 20
        if overdriveCount >= minSamples then
            local percentileRef = GetOverdrivePercentileValue(PS.simpleOverdrivePercentile or 0.95)
            local threshold = math_max(
                percentileRef * math_max(PS.simpleOverdriveMultiplier or 1.10, 1.00),
                PS.simpleOverdriveFloor or 1
            )
            if threshold > 0 and (now or 0) >= overdriveLockUntil and hitAmount >= threshold then
                local ratio = hitAmount / threshold
                local tierBoost = 1
                if ratio >= 1.75 then tierBoost = 2 end
                if ratio >= 2.60 then tierBoost = 3 end
                overdrivePendingTierBoost = math_max(overdrivePendingTierBoost, tierBoost)
                overdriveLockUntil = (now or 0) + (PS.simpleOverdriveCooldownSec or 0.45)
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
        local resistance = GetPressurePopupDBNumber("pressureSimpleResistance", 1.00, 0.20, 4.00)
        local rubberband = GetPressurePopupDBNumber("pressureSimpleRubberband", 1.00, 0.20, 3.00)
        local tierBase = GetPressurePopupDBNumber("pressureSimpleTierBase", 1.50, 0.20, 10.00)
        local tierStepPct = GetPressurePopupDBNumber("pressureSimpleTierStepPct", 10.00, 1.00, 30.00)
        local tierHelp = GetPressurePopupDBNumber("pressureSimpleTierHelp", 1.00, 0.00, 3.00)
        local holdSec = GetPressurePopupDBNumber("pressureSimpleTierHoldSec", 2.20, 0.10, 15.00)
        local overdrivePercentile = GetPressurePopupDBNumber("pressureSimpleOverdrivePercentile", 95.00, 85.00, 99.50)
        local overdriveMultiplier = GetPressurePopupDBNumber("pressureSimpleOverdriveMultiplier", 1.12, 1.00, 3.00)
        local shakeAmount = GetPressurePopupDBNumber("pressureSimpleShakeAmount", 1.00, 0.00, 2.50)
        local shakeFromDamage = GetPressurePopupDBNumber("pressureSimpleShakeFromDamage", 0.85, 0.00, 3.00)
        local tierStepFrac = tierStepPct / 100

        PS.simpleResistance = resistance
        PS.simpleRubberband = rubberband
        PS.simpleTierStepFrac = tierStepFrac
        PS.tierThresholds = BuildSimpleThresholds(tierBase, tierStepFrac)

        local forceReq = BuildSimpleForceReq(resistance, rubberband, tierStepFrac)
        PS.tierMinSqueeze = { 0.00, forceReq[1], forceReq[2], forceReq[3], forceReq[4], forceReq[5] }
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
        PS.simpleOverdriveMinSamples = 20
        PS.simpleOverdriveFloor = 1
        PS.simpleOverdriveCooldownSec = 0.45

        PUSH_FEEL_CFG.fillMass = 1.60 + (resistance * 1.80)
        PUSH_FEEL_CFG.resistanceScale = 0.55 + (resistance * 0.45)
        PUSH_FEEL_CFG.fillTransferDropSec = 0.30 + (rubberband * 0.46)
        PUSH_FEEL_CFG.fillTransferRubberDamping = Clamp(5.80 - (rubberband * 1.30), 1.00, 10.00)
        PUSH_FEEL_CFG.fillTransferRubberOscillations = Clamp(0.85 + (rubberband * 0.90), 0.30, 5.00)
        PUSH_FEEL_CFG.fillTransferLandingFloor = Clamp(0.04 + (tierHelp * 0.05), 0.00, 0.80)
        PUSH_FEEL_CFG.fillPullResistStart = Clamp(0.76 + ((resistance - 1.00) * 0.05), 0.65, 0.90)
        PUSH_FEEL_CFG.fillPullLowerPower = 1.10 + (resistance * 0.12)
        PUSH_FEEL_CFG.fillPullEdgePower = 1.85 + (resistance * 0.65)
        PUSH_FEEL_CFG.gaugeShakeAmount = shakeAmount
        PUSH_FEEL_CFG.gaugeShakeDamageScale = shakeFromDamage
        PUSH_FEEL_CFG.overloadThreshold = 1.00 + ((overdriveMultiplier - 1.00) * 0.75)
    end

    return model
end
