local addonName = ...
if addonName ~= "ShammyTime" then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

local ShammyTime = _G.ShammyTime
if not ShammyTime then return end

local Models = ShammyTime.PressureModels
if not Models then return end

function Models.CreateTierModelPercentilePOC(ctx)
    local PS = ctx.PS
    local PUSH_FEEL_CFG = ctx.PUSH_FEEL_CFG
    local SmoothAlpha = ctx.SmoothAlpha
    local GetPressurePopupDBNumber = ctx.GetPressurePopupDBNumber
    local math_max = ctx.math_max
    local math_min = ctx.math_min
    local math_floor = math.floor
    local math_exp = math.exp

    local model = {}

    local DEFAULT_LIVE_WINDOW_SEC = 2.60
    local DEFAULT_MIN_HISTORY = 12
    local DEFAULT_MIN_SPIKE_HISTORY = 40
    local DEFAULT_LIVE_HISTORY_CAP = 320
    local DEFAULT_HIT_HISTORY_CAP = 600
    local DEFAULT_FLOOR_DECAY_TAU_SEC = 12.0
    local DEFAULT_FLOOR_MIN_SCALE = 0.80
    local DEFAULT_SPIKE_FLOOR_ACTIVE_SEC = 0.60
    local DEFAULT_FORCED_T4_SPIKE_FILL_MAX = 0.92
    local DEFAULT_FIGHT_HISTORY_CAP = 10
    local DEFAULT_FIGHT_EMA_ALPHA = 2 / 11

    local liveWindowEvents = {}
    local liveWindowHead = 1
    local liveWindowSum = 0

    local liveHistory = {}
    local hitHistory = {}
    local fightHistoryDps = {}
    local fightEmaDps = 0

    local liveSorted = {}
    local hitSorted = {}
    local liveSortedDirty = true
    local hitSortedDirty = true

    local computedTier = 0
    local computedTierFrac = 0
    local computedThresholds = { 0, 0, 0, 0, 0 }
    local computedNow = 0

    local inCombat = false
    local combatStartAt = 0
    local combatDamage = 0
    local lastHitAmount = 0
    local lastHitAt = 0
    local overdrivePendingTierBoost = 0

    local function Clamp(value, minValue, maxValue)
        if value < minValue then return minValue end
        if value > maxValue then return maxValue end
        return value
    end

    local function AppendCapped(list, cap, value)
        list[#list + 1] = value
        if #list > cap then
            table.remove(list, 1)
        end
    end

    local function CompactLiveWindowEvents()
        if liveWindowHead <= 64 then
            return
        end
        if liveWindowHead <= (#liveWindowEvents * 0.5) then
            return
        end
        local compacted = {}
        local idx = 1
        for i = liveWindowHead, #liveWindowEvents do
            compacted[idx] = liveWindowEvents[i]
            idx = idx + 1
        end
        liveWindowEvents = compacted
        liveWindowHead = 1
    end

    local function PruneLiveWindow(now)
        local windowSec = math_max(PS.pocLiveWindowSec or DEFAULT_LIVE_WINDOW_SEC, 0.20)
        while liveWindowHead <= #liveWindowEvents do
            local item = liveWindowEvents[liveWindowHead]
            if not item then
                break
            end
            if (now - item.t) <= windowSec then
                break
            end
            liveWindowSum = liveWindowSum - (item.a or 0)
            liveWindowHead = liveWindowHead + 1
        end

        if liveWindowSum < 0 then
            liveWindowSum = 0
        end
        CompactLiveWindowEvents()
    end

    local function PushLiveWindowDamage(now, amount)
        liveWindowEvents[#liveWindowEvents + 1] = { t = now, a = amount }
        liveWindowSum = liveWindowSum + amount
        PruneLiveWindow(now)
    end

    local function NearestRank(sortedValues, p)
        local n = #sortedValues
        if n <= 0 then return 0 end
        local pct = Clamp(p or 0.5, 0.0, 1.0)
        local rank = math_floor(((n - 1) * pct) + 1.5)
        rank = Clamp(rank, 1, n)
        return sortedValues[rank] or 0
    end

    local function EnsureLiveSorted()
        if not liveSortedDirty then
            return
        end
        for i = #liveSorted, 1, -1 do
            liveSorted[i] = nil
        end
        for i = 1, #liveHistory do
            liveSorted[i] = liveHistory[i]
        end
        if #liveSorted > 1 then
            table.sort(liveSorted)
        end
        liveSortedDirty = false
    end

    local function EnsureHitSorted()
        if not hitSortedDirty then
            return
        end
        for i = #hitSorted, 1, -1 do
            hitSorted[i] = nil
        end
        for i = 1, #hitHistory do
            hitSorted[i] = hitHistory[i]
        end
        if #hitSorted > 1 then
            table.sort(hitSorted)
        end
        hitSortedDirty = false
    end

    local function GetFightAvgDps()
        if #fightHistoryDps <= 0 then
            return 0
        end
        local sum = 0
        for i = 1, #fightHistoryDps do
            sum = sum + (fightHistoryDps[i] or 0)
        end
        return sum / #fightHistoryDps
    end

    local function GetFightBaselineDps()
        local avg = GetFightAvgDps()
        if fightEmaDps > 0 and avg > 0 then
            return (fightEmaDps + avg) * 0.5
        end
        if fightEmaDps > 0 then
            return fightEmaDps
        end
        return avg
    end

    local function GetFloorScale(now)
        if not inCombat or combatStartAt <= 0 then
            return 1.0
        end
        local elapsed = math_max((now or 0) - combatStartAt, 0)
        local tau = math_max(PS.pocFloorDecayTauSec or DEFAULT_FLOOR_DECAY_TAU_SEC, 0.50)
        local minScale = Clamp(PS.pocFloorMinScale or DEFAULT_FLOOR_MIN_SCALE, 0.40, 1.00)
        local decay = math_exp(-elapsed / tau)
        return minScale + (1 - minScale) * decay
    end

    local function UpdateComputedTier(now)
        local tNow = now or 0
        PruneLiveWindow(tNow)
        local minSamples = math_max(PS.pocMinHistorySamples or DEFAULT_MIN_HISTORY, 8)
        local minSpikeSamples = math_max(PS.pocMinSpikeHistorySamples or DEFAULT_MIN_SPIKE_HISTORY, 8)
        local floorScale = GetFloorScale(tNow)
        local t1, t2, t3, t4, t5

        if #liveHistory >= minSamples then
            EnsureLiveSorted()
            t1 = NearestRank(liveSorted, 0.10)
            t2 = NearestRank(liveSorted, 0.30)
            t3 = NearestRank(liveSorted, 0.55)
            t4 = NearestRank(liveSorted, 0.80)
            t5 = NearestRank(liveSorted, 0.95)
        else
            local liveWindowSec = math_max(PS.pocLiveWindowSec or DEFAULT_LIVE_WINDOW_SEC, 0.20)
            local fallbackDps = GetFightBaselineDps()
            local seed = math_max(liveWindowSum, fallbackDps * liveWindowSec, 1)
            t1 = seed * 0.65
            t2 = seed * 0.95
            t3 = seed * 1.25
            t4 = seed * 1.65
            t5 = seed * 2.15
        end

        t1 = math_max(t1 * floorScale, 1)
        t2 = math_max(t2 * floorScale, t1)
        t3 = math_max(t3 * floorScale, t2)
        t4 = math_max(t4 * floorScale, t3)
        t5 = math_max(t5 * floorScale, t4)

        computedThresholds[1] = t1
        computedThresholds[2] = t2
        computedThresholds[3] = t3
        computedThresholds[4] = t4
        computedThresholds[5] = t5

        local value = liveWindowSum
        local tier = 0
        if value >= t1 then tier = 1 end
        if value >= t2 then tier = 2 end
        if value >= t3 then tier = 3 end
        if value >= t4 then tier = 4 end
        if value >= t5 then tier = 5 end

        local floorTier = 0
        local floorP95 = 0
        local floorP99 = 0
        local spikeFloorActiveSec = math_max(PS.pocSpikeFloorActiveSec or DEFAULT_SPIKE_FLOOR_ACTIVE_SEC, 0.05)
        local spikeRecent = (tNow - (lastHitAt or 0)) <= spikeFloorActiveSec
        if #hitHistory >= minSpikeSamples then
            EnsureHitSorted()
            floorP95 = NearestRank(hitSorted, 0.95)
            floorP99 = NearestRank(hitSorted, 0.99)
            if inCombat and spikeRecent and lastHitAmount >= floorP99 and floorP99 > 0 then
                floorTier = 5
            elseif inCombat and spikeRecent and lastHitAmount >= floorP95 and floorP95 > 0 then
                floorTier = 4
            end
        end

        local forcedByFloor = false
        if floorTier > tier then
            tier = floorTier
            forcedByFloor = true
            if tier > (PS.currentTier or 0) then
                overdrivePendingTierBoost = math_max(overdrivePendingTierBoost, tier - (PS.currentTier or 0))
            end
        end

        local lower = 0
        local upper = t1
        if tier == 1 then
            lower = t1
            upper = t2
        elseif tier == 2 then
            lower = t2
            upper = t3
        elseif tier == 3 then
            lower = t3
            upper = t4
        elseif tier == 4 then
            lower = t4
            upper = t5
        elseif tier >= 5 then
            lower = t5
            upper = math_max(t5 * 1.25, lower + 1)
        end

        local frac = 0
        local span = math_max(upper - lower, 1)
        frac = Clamp((value - lower) / span, 0, 1)
        if tier > 0 and frac < 0.08 then
            frac = 0.08
        end
        if forcedByFloor then
            if tier >= 5 then
                frac = 1
            elseif tier == 4 then
                frac = DEFAULT_FORCED_T4_SPIKE_FILL_MAX
            end
        end

        computedTier = Clamp(tier, 0, 5)
        computedTierFrac = frac
        computedNow = tNow

        if #hitHistory > 0 then
            EnsureHitSorted()
        end
        PS.debugOverdriveHitPercentileRef = floorP95
        PS.debugOverdriveHitMedianRef = NearestRank(hitSorted, 0.50)
        PS.debugOverdriveHitThreshold = floorP99
        PS.debugOverdriveLastHit = lastHitAmount
        if floorP99 > 0 then
            PS.debugOverdriveHitAbovePct = ((lastHitAmount / floorP99) - 1) * 100
        else
            PS.debugOverdriveHitAbovePct = 0
        end

        local liveWindowSec = math_max(PS.pocLiveWindowSec or DEFAULT_LIVE_WINDOW_SEC, 0.20)
        local currentDps = liveWindowSum / liveWindowSec
        local baseline = GetFightBaselineDps()
        local fightDps = 0
        if inCombat and combatStartAt > 0 then
            local combatSec = math_max(tNow - combatStartAt, 0.25)
            fightDps = combatDamage / combatSec
        else
            fightDps = baseline
        end
        PS.debugCurrentDps = currentDps
        PS.debugFightDps = fightDps
        PS.debugMedianDps = baseline
        if baseline > 0 then
            PS.debugDpsAbovePct = ((currentDps / baseline) - 1) * 100
        else
            PS.debugDpsAbovePct = 0
        end
        PS.overdriveSampleCount = #hitHistory
        local warmDen = math_max(PS.simpleOverdriveSampleCap or DEFAULT_HIT_HISTORY_CAP, 1)
        PS.overdriveWarmup = Clamp((#hitHistory - minSamples) / warmDen, 0, 1)
    end

    function model.GetTier(score)
        if computedNow <= 0 then
            UpdateComputedTier(GetTime())
        end
        return computedTier or 0
    end

    function model.GetPromoteThreshold(tier)
        if computedNow <= 0 then
            UpdateComputedTier(GetTime())
        end
        local t = math_floor(tonumber(tier) or 0)
        if t <= 0 then
            return 0
        end
        if t > 5 then
            t = 5
        end
        return computedThresholds[t] or computedThresholds[5] or 1
    end

    function model.GetDemoteThreshold(tier)
        return model.GetPromoteThreshold(tier)
    end

    function model.GetTierFillTarget(score, tier)
        if computedNow <= 0 then
            UpdateComputedTier(GetTime())
        end
        local shownTier = Clamp(math_floor(tonumber(tier) or 0), 0, 5)
        local targetTier = computedTier or 0
        if shownTier < targetTier then
            return 1
        end
        if shownTier > targetTier then
            -- Avoid hard empty drops when tiers oscillate around boundaries.
            -- Keep a small residual fill that still trends down.
            local gap = shownTier - targetTier
            local frac = Clamp(computedTierFrac or 0, 0, 1)
            local residual = 0.05 + (frac * 0.22)
            if gap >= 2 then
                residual = residual * 0.60
            end
            return Clamp(residual, 0.02, 0.32)
        end
        return Clamp(computedTierFrac or 0, 0, 1)
    end

    function model.GetTierSegmentProgress(score)
        local tier = model.GetTier(score)
        return tier, Clamp(computedTierFrac or 0, 0, 1)
    end

    function model.GetTierResistanceAndSlip(score, now)
        UpdateComputedTier(now or GetTime())
        PS.tierEdgeResistMax = 0.001
        return 0, 0
    end

    function model.UpdateTierMomentumBonus(elapsed, now)
        local tNow = now or GetTime()
        UpdateComputedTier(tNow)
        local target = 0
        if (PS.currentTier or 0) >= 1 then
            target = math_min(
                (PS.simpleTierHelpPerTier or 0) * PS.currentTier,
                math_max(PS.simpleTierHelpMax or 0, 0)
            )
        end
        local decayTau = PS.simpleTierHelpDecayTau or 3.50
        if (tNow - (PS.lastDamageTime or 0)) > math_max(PS.tierMomentumIdleGrace or 0.90, 0) then
            decayTau = PS.simpleTierHelpIdleDecayTau or decayTau
        end
        PS.tierMomentumBoost = SmoothAlpha(
            PS.tierMomentumBoost or 0,
            target,
            elapsed or 0,
            PS.simpleTierHelpBuildTau or 0.45,
            decayTau
        )
    end

    function model.RecordDamageEvent(amount, now)
        local hitAmount = tonumber(amount) or 0
        if hitAmount <= 0 then
            return
        end
        local tNow = now or GetTime()
        lastHitAmount = hitAmount
        lastHitAt = tNow
        if inCombat then
            combatDamage = combatDamage + hitAmount
        end

        PushLiveWindowDamage(tNow, hitAmount)
        AppendCapped(liveHistory, math_max(PS.pocLiveHistoryCap or DEFAULT_LIVE_HISTORY_CAP, 40), liveWindowSum)
        AppendCapped(hitHistory, math_max(PS.pocHitHistoryCap or DEFAULT_HIT_HISTORY_CAP, 60), hitAmount)
        liveSortedDirty = true
        hitSortedDirty = true

        UpdateComputedTier(tNow)
    end

    function model.ConsumeOverdriveTierBoost()
        local boost = overdrivePendingTierBoost or 0
        overdrivePendingTierBoost = 0
        return boost
    end

    function model.ResetRuntime(clearHistory)
        overdrivePendingTierBoost = 0
        computedTier = 0
        computedTierFrac = 0
        computedNow = 0
        lastHitAmount = 0
        lastHitAt = 0
        liveWindowSum = 0
        liveWindowHead = 1
        for i = #liveWindowEvents, 1, -1 do
            liveWindowEvents[i] = nil
        end
        inCombat = false
        combatStartAt = 0
        combatDamage = 0
        if clearHistory then
            for i = #liveHistory, 1, -1 do
                liveHistory[i] = nil
            end
            for i = #hitHistory, 1, -1 do
                hitHistory[i] = nil
            end
            for i = #fightHistoryDps, 1, -1 do
                fightHistoryDps[i] = nil
            end
            fightEmaDps = 0
            liveSortedDirty = true
            hitSortedDirty = true
        end
        PS.overdriveSampleCount = #hitHistory
        PS.overdriveWarmup = 0
        PS.debugOverdriveHitPercentileRef = 0
        PS.debugOverdriveHitMedianRef = 0
        PS.debugOverdriveHitThreshold = 0
        PS.debugOverdriveLastHit = 0
        PS.debugOverdriveHitAbovePct = 0
        PS.debugCurrentDps = 0
        PS.debugFightDps = 0
        PS.debugMedianDps = GetFightBaselineDps()
        PS.debugDpsAbovePct = 0
    end

    function model.StartCombatDamageMeter(now)
        inCombat = true
        combatStartAt = now or GetTime()
        combatDamage = 0
    end

    function model.EndCombatDamageMeter(now, holdSec)
        local tNow = now or GetTime()
        if inCombat and combatStartAt > 0 and combatDamage > 0 then
            local sec = math_max(tNow - combatStartAt, 0.25)
            local dps = combatDamage / sec
            local cap = math_max(PS.pocFightHistoryCap or DEFAULT_FIGHT_HISTORY_CAP, 1)
            AppendCapped(fightHistoryDps, cap, dps)
            local alpha = Clamp(PS.pocFightEmaAlpha or DEFAULT_FIGHT_EMA_ALPHA, 0.01, 1.0)
            if fightEmaDps <= 0 then
                fightEmaDps = dps
            else
                fightEmaDps = (fightEmaDps * (1 - alpha)) + (dps * alpha)
            end
        end
        inCombat = false
        combatStartAt = 0
        combatDamage = 0
        UpdateComputedTier(tNow)
    end

    function model.UpdateDebugTelemetry(now)
        local tNow = now or GetTime()
        UpdateComputedTier(tNow)
        -- For this POC, the tier score is the live 2s damage directly.
        PS.tierScore = liveWindowSum
    end

    function model.ApplyTuningSettings()
        local tierHelp = GetPressurePopupDBNumber("pressureSimpleTierHelp", 0.85, 0.00, 3.00)
        local holdSec = GetPressurePopupDBNumber("pressureSimpleTierHoldSec", 5.00, 0.10, 15.00)
        local shakeAmount = GetPressurePopupDBNumber("pressureSimpleShakeAmount", 1.35, 0.00, 2.50)
        local shakeFromDamage = GetPressurePopupDBNumber("pressureSimpleShakeFromDamage", 1.30, 0.00, 3.00)
        -- Keep step-down stability, but avoid multi-second tier lag.
        local effectiveHoldSec = Clamp(holdSec * 0.18, 0.18, 0.95)

        PS.tierThresholds = { 1, 2, 3, 4, 5 }
        PS.tierHysteresis = 0
        PS.tierHoldMinSec = effectiveHoldSec
        PS.tierMomentumIdleGrace = 0.55

        PS.simpleTierHelp = tierHelp
        PS.simpleTierHelpPerTier = 0.010 + (tierHelp * 0.016)
        PS.simpleTierHelpMax = 0.05 + (tierHelp * 0.16)
        PS.simpleTierHelpBuildTau = 0.45
        PS.simpleTierHelpDecayTau = 1.80 + (tierHelp * 0.85)
        PS.simpleTierHelpIdleDecayTau = 0.85 + (tierHelp * 0.45)
        PS.tierMomentumOnPromote = 0.02 + (tierHelp * 0.02)
        PS.tierMomentumMax = math_max(PS.simpleTierHelpMax, 0.10)

        PS.pocLiveWindowSec = DEFAULT_LIVE_WINDOW_SEC
        PS.pocMinHistorySamples = DEFAULT_MIN_HISTORY
        PS.pocMinSpikeHistorySamples = DEFAULT_MIN_SPIKE_HISTORY
        PS.pocLiveHistoryCap = DEFAULT_LIVE_HISTORY_CAP
        PS.pocHitHistoryCap = DEFAULT_HIT_HISTORY_CAP
        PS.pocFloorDecayTauSec = DEFAULT_FLOOR_DECAY_TAU_SEC
        PS.pocFloorMinScale = DEFAULT_FLOOR_MIN_SCALE
        PS.pocSpikeFloorActiveSec = DEFAULT_SPIKE_FLOOR_ACTIVE_SEC
        PS.pocFightHistoryCap = DEFAULT_FIGHT_HISTORY_CAP
        PS.pocFightEmaAlpha = DEFAULT_FIGHT_EMA_ALPHA

        PUSH_FEEL_CFG.gaugeShakeAmount = shakeAmount
        PUSH_FEEL_CFG.gaugeShakeDamageScale = shakeFromDamage
        PUSH_FEEL_CFG.overloadThreshold = 1.02

        PS.debugTune = {
            resistance = 1.00,
            rubberband = 1.00,
            tierBase = 2.00,
            tierStepPct = 0.00,
            tierHelp = tierHelp,
            holdSec = effectiveHoldSec,
            overdrivePercentile = 99.00,
            overdriveMultiplier = 1.00,
            shakeAmount = shakeAmount,
            shakeFromDamage = shakeFromDamage,
        }
    end

    return model
end
