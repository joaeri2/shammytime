local addonName = ...
if addonName ~= "ShammyTime" then return end

local ShammyTime = _G.ShammyTime
if not ShammyTime then return end

local Models = ShammyTime.PressureModels
if not Models then return end

function Models.CreateVisualModel(ctx)
    local frame = ctx.frame
    local gaugeKeys = ctx.gaugeKeys
    local gaugeCurrentAlpha = ctx.gaugeCurrentAlpha
    local visualAnimState = ctx.visualAnimState
    local colorOverlayState = ctx.colorOverlayState
    local PUSH_FEEL_CFG = ctx.PUSH_FEEL_CFG
    local PS = ctx.PS
    local TIER_COLORS = ctx.TIER_COLORS
    local TIER_GAUGE_INDEX = ctx.TIER_GAUGE_INDEX
    local TIER_GAUGE_ALPHA = ctx.TIER_GAUGE_ALPHA
    local DISPLAY_WIDTH = ctx.DISPLAY_WIDTH
    local MIN_FILL_U = ctx.MIN_FILL_U
    local CROP_TOP = ctx.CROP_TOP
    local CROP_BOTTOM = ctx.CROP_BOTTOM
    local FILL_HIDE_EPS = ctx.FILL_HIDE_EPS
    local FILL_SHOW_EPS = ctx.FILL_SHOW_EPS
    local FILL_FULL_EPSILON = ctx.FILL_FULL_EPSILON
    local FILL_FULL_HOLD_SEC = ctx.FILL_FULL_HOLD_SEC
    local FILL_SMOOTH_TAU_RISE = ctx.FILL_SMOOTH_TAU_RISE
    local FILL_SMOOTH_TAU_FALL = ctx.FILL_SMOOTH_TAU_FALL
    local OVERLAY_COLOR_TAU_IN = ctx.OVERLAY_COLOR_TAU_IN
    local OVERLAY_COLOR_TAU_OUT = ctx.OVERLAY_COLOR_TAU_OUT
    local SmoothAlpha = ctx.SmoothAlpha
    local math_abs = ctx.math_abs
    local math_exp = ctx.math_exp
    local math_max = ctx.math_max
    local math_min = ctx.math_min
    local GetTime = ctx.GetTime
    local getTierFillTarget = ctx.getTierFillTarget

    local model = {}

    function model.ApplyProgressPullResistance(progressFrac)
        local p = math_min(math_max(progressFrac or 0, 0), 1)
        if p <= 0 then return 0 end
        if p >= 1 then return 1 end

        if p <= PUSH_FEEL_CFG.fillPullResistStart then
            local lowerSpan = math_max(PUSH_FEEL_CFG.fillPullResistStart, 0.001)
            local q = p / lowerSpan
            return (q ^ PUSH_FEEL_CFG.fillPullLowerPower) * PUSH_FEEL_CFG.fillPullResistStart
        end

        local q = (p - PUSH_FEEL_CFG.fillPullResistStart) / math_max(1 - PUSH_FEEL_CFG.fillPullResistStart, 0.001)
        return PUSH_FEEL_CFG.fillPullResistStart + ((q ^ PUSH_FEEL_CFG.fillPullEdgePower) * (1 - PUSH_FEEL_CFG.fillPullResistStart))
    end

    function model.StartColorOverlayTransferDrop(fromFillFrac)
        visualAnimState.colorOverlayTransferActive = true
        visualAnimState.colorOverlayTransferElapsed = 0
        visualAnimState.colorOverlayTransferFrom = math_min(math_max(fromFillFrac or colorOverlayState.fillFrac or 0, 0), 1)
        visualAnimState.colorOverlayTransferTo = 0
        colorOverlayState.fullHoldRemaining = 0
    end

    function model.SetGaugeTextureOffset(offsetX, offsetY)
        local x = tonumber(offsetX) or 0
        local y = tonumber(offsetY) or 0
        if math_abs((visualAnimState.gaugeShakeOffsetX or 0) - x) < 0.01 and math_abs((visualAnimState.gaugeShakeOffsetY or 0) - y) < 0.01 then
            return
        end
        visualAnimState.gaugeShakeOffsetX = x
        visualAnimState.gaugeShakeOffsetY = y
        for _, key in ipairs(gaugeKeys) do
            local tex = frame.textures[key]
            if tex then
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
                tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", x, y)
            end
        end
    end

    function model.UpdateGaugeShake(elapsed, now, rawFillTarget, impulsePressure)
        local triggerFill = math_min(math_max(PUSH_FEEL_CFG.gaugeShakeTriggerFill or 0.90, 0), 0.99)
        local fillStress = 0
        if rawFillTarget and rawFillTarget > triggerFill then
            fillStress = (rawFillTarget - triggerFill) / math_max(1 - triggerFill, 0.001)
        end

        local damageStress = 0
        if fillStress > 0 then
            local overloadRef = math_max(PUSH_FEEL_CFG.overloadThreshold or 1.10, 0.05)
            local pressureScale = math_max(PUSH_FEEL_CFG.gaugeShakeDamageScale or 0.85, 0)
            local normalizedImpulse = math_max((impulsePressure or 0) / overloadRef, 0)
            damageStress = math_min((normalizedImpulse ^ 0.70) * pressureScale, 1.0)
        end

        local resistMax = math_max((PS and PS.tierEdgeResistMax) or 0.52, 0.001)
        local resistStress = math_min(math_max((PS and PS.tierEdgeResistance or 0) / resistMax, 0), 1)
        if fillStress <= 0 then
            resistStress = 0
        end

        local stressTarget = math_min(math_max(math_max(fillStress, resistStress * 0.90, damageStress), 0), 1)
        visualAnimState.gaugeShakeStress = SmoothAlpha(
            visualAnimState.gaugeShakeStress,
            stressTarget,
            elapsed,
            PUSH_FEEL_CFG.gaugeShakeStressTauIn,
            PUSH_FEEL_CFG.gaugeShakeStressTauOut
        )

        if visualAnimState.gaugeShakeStress <= 0.01 then
            model.SetGaugeTextureOffset(0, 0)
            return
        end

        local t = now or GetTime()
        local shakeAmount = math_max(PUSH_FEEL_CFG.gaugeShakeAmount or 1.00, 0)
        local ampX = PUSH_FEEL_CFG.gaugeShakeMaxX * shakeAmount * visualAnimState.gaugeShakeStress
        local ampY = PUSH_FEEL_CFG.gaugeShakeMaxY * shakeAmount * visualAnimState.gaugeShakeStress
        local shakeX = (math.sin(t * PUSH_FEEL_CFG.gaugeShakeFreqX1) * ampX) + (math.cos(t * PUSH_FEEL_CFG.gaugeShakeFreqX2 + 0.9) * ampX * 0.35)
        local shakeY = math.sin(t * PUSH_FEEL_CFG.gaugeShakeFreqY1 + 1.2) * ampY
        model.SetGaugeTextureOffset(shakeX, shakeY)
    end

    function model.SetColorOverlayFill(fillFrac)
        local colorOverlay = frame.textures.colorOverlay
        if not colorOverlay then return end

        local frac = math_min(math_max(fillFrac or 0, 0), 1)
        if frac <= FILL_HIDE_EPS then
            colorOverlayState.fillVisible = false
            colorOverlay:Hide()
            colorOverlay:SetWidth(1)
            colorOverlay:SetTexCoord(0, MIN_FILL_U, CROP_TOP, 1 - CROP_BOTTOM)
            return
        end

        if (not colorOverlayState.fillVisible) and frac < FILL_SHOW_EPS then
            colorOverlay:SetWidth(1)
            colorOverlay:SetTexCoord(0, MIN_FILL_U, CROP_TOP, 1 - CROP_BOTTOM)
            return
        end

        colorOverlayState.fillVisible = true
        local uRight = math_max(frac, MIN_FILL_U)
        colorOverlay:Show()
        colorOverlay:SetWidth(DISPLAY_WIDTH * uRight)
        colorOverlay:SetTexCoord(0, uRight, CROP_TOP, 1 - CROP_BOTTOM)
    end

    function model.Update(elapsed, now, impulsePressure)
        local tier = PS.currentTier or 0
        local tierColor = TIER_COLORS[tier + 1] or TIER_COLORS[1]
        local coolingBlueBlend = 0

        local scoreForProgress = PS.tierEvalScore or PS.tierScore or 0
        local rawFillTarget = getTierFillTarget(scoreForProgress, tier)
        local fillTarget = model.ApplyProgressPullResistance(rawFillTarget)

        if visualAnimState.promotionPending and (not visualAnimState.colorOverlayTransferActive) then
            fillTarget = 1
        end

        if tier >= 5 then
            fillTarget = 1
            visualAnimState.colorOverlayTransferActive = false
            visualAnimState.colorOverlayTransferTo = 1
            colorOverlayState.fullHoldRemaining = 0
        end

        if visualAnimState.colorOverlayTransferActive then
            local fromFill = visualAnimState.colorOverlayTransferFrom or colorOverlayState.fillFrac or 0
            local landingTarget = fillTarget
            if tier >= 1 then
                landingTarget = math_max(landingTarget, PUSH_FEEL_CFG.fillTransferLandingFloor)
            end
            local smoothedLandingTarget = SmoothAlpha(
                visualAnimState.colorOverlayTransferTo or landingTarget,
                landingTarget,
                elapsed,
                0.18,
                0.32
            )
            landingTarget = smoothedLandingTarget
            visualAnimState.colorOverlayTransferTo = smoothedLandingTarget
            visualAnimState.colorOverlayTransferElapsed = visualAnimState.colorOverlayTransferElapsed + elapsed
            local descending = fromFill > landingTarget
            local transferDuration = math_max(PUSH_FEEL_CFG.fillTransferDropSec, 0.01)
            if descending then
                -- Extra time only for cooldown fall, so descent feels heavier.
                transferDuration = transferDuration * 1.72
            end
            local tLinear = math_min(math_max(visualAnimState.colorOverlayTransferElapsed / transferDuration, 0), 1)
            if descending then
                -- Keep a short top hold right after tier-up so the cooldown
                -- reads as a transfer, not an instant drop.
                local holdFrac = 0.10
                if tLinear <= holdFrac then
                    tLinear = 0
                else
                    tLinear = (tLinear - holdFrac) / math_max(1 - holdFrac, 0.001)
                end
            end
            -- Bowl-like transfer timing: slow near both corners, faster through center.
            local t = 0.5 - (0.5 * math.cos(math.pi * tLinear))
            local rubber
            if descending then
                -- Monotonic cooldown descent (no fast back-and-forth oscillation).
                local fallShape = (1 - t) ^ 1.45
                local tailDrag = 0.72 + (0.28 * (1 - t))
                rubber = fallShape * tailDrag
            else
                local decay = math_exp(-math_max(PUSH_FEEL_CFG.fillTransferRubberDamping, 0.01) * t)
                local omega = (math.pi * 2) * math_max(PUSH_FEEL_CFG.fillTransferRubberOscillations, 0.01)
                rubber = decay * (0.20 + (0.80 * math.cos(omega * t)))
            end
            local value = landingTarget + ((fromFill - landingTarget) * rubber)
            local targetValue = math_min(math_max(value, 0), 1)
            if descending then
                -- Preserve some carried pressure early in cooldown so the bar
                -- reads as "cooling" instead of dropping to empty.
                local carryFloor = landingTarget + ((fromFill - landingTarget) * 0.24 * ((1 - t) ^ 1.35))
                targetValue = math_max(targetValue, carryFloor)
                coolingBlueBlend = 0.90 * ((1 - t) ^ 0.35)
            end
            -- Add corner drag so both start/end naturally decelerate.
            local corner = 1 - (4 * t * (1 - t))
            corner = math_min(math_max(corner, 0), 1)
            local settleTau = 0.016 + (0.080 * (corner ^ 1.35))
            if descending then
                settleTau = settleTau * 1.30
            end
            colorOverlayState.fillFrac = SmoothAlpha(
                colorOverlayState.fillFrac,
                targetValue,
                elapsed,
                settleTau,
                settleTau * 1.10
            )
            if tLinear >= 1 then
                visualAnimState.colorOverlayTransferActive = false
                if math_abs(colorOverlayState.fillFrac - visualAnimState.colorOverlayTransferTo) < 0.004 then
                    colorOverlayState.fillFrac = visualAnimState.colorOverlayTransferTo
                end
            end
        else
            if tier < 5 then
                if fillTarget >= FILL_FULL_EPSILON then
                    colorOverlayState.fullHoldRemaining = FILL_FULL_HOLD_SEC
                    fillTarget = 1
                elseif colorOverlayState.fullHoldRemaining > 0 then
                    colorOverlayState.fullHoldRemaining = math_max(colorOverlayState.fullHoldRemaining - elapsed, 0)
                    fillTarget = 1
                end
            else
                colorOverlayState.fullHoldRemaining = 0
            end

            local edgeProgress = 0
            if fillTarget > PUSH_FEEL_CFG.fillPullResistStart then
                edgeProgress = (fillTarget - PUSH_FEEL_CFG.fillPullResistStart) / math_max(1 - PUSH_FEEL_CFG.fillPullResistStart, 0.001)
            end
            local heavyMass = math_max(PUSH_FEEL_CFG.fillMass, 1)
            local lightMass = 1 + ((heavyMass - 1) * 0.25)
            local massBlend = lightMass + ((heavyMass - lightMass) * (edgeProgress ^ 1.6))
            local riseTau = FILL_SMOOTH_TAU_RISE * massBlend * (1 + (edgeProgress * edgeProgress * PUSH_FEEL_CFG.fillSmoothTauEdgeMult))
            colorOverlayState.fillFrac = SmoothAlpha(
                colorOverlayState.fillFrac,
                fillTarget,
                elapsed,
                riseTau,
                FILL_SMOOTH_TAU_FALL
            )
        end

        local colorOverlay = frame.textures.colorOverlay
        if colorOverlay then
            local colorTargetR = tierColor[1]
            local colorTargetG = tierColor[2]
            local colorTargetB = tierColor[3]
            local colorTauIn = OVERLAY_COLOR_TAU_IN
            local colorTauOut = OVERLAY_COLOR_TAU_OUT
            if coolingBlueBlend > 0 then
                local coolR, coolG, coolB = 0.10, 0.46, 1.00
                colorTargetR = colorTargetR + ((coolR - colorTargetR) * coolingBlueBlend)
                colorTargetG = colorTargetG + ((coolG - colorTargetG) * coolingBlueBlend)
                colorTargetB = colorTargetB + ((coolB - colorTargetB) * coolingBlueBlend)
                colorTauIn = 0.030
                colorTauOut = 0.090
            end
            colorOverlayState.currentColor[1] = SmoothAlpha(
                colorOverlayState.currentColor[1], colorTargetR, elapsed, colorTauIn, colorTauOut
            )
            colorOverlayState.currentColor[2] = SmoothAlpha(
                colorOverlayState.currentColor[2], colorTargetG, elapsed, colorTauIn, colorTauOut
            )
            colorOverlayState.currentColor[3] = SmoothAlpha(
                colorOverlayState.currentColor[3], colorTargetB, elapsed, colorTauIn, colorTauOut
            )
            colorOverlay:SetVertexColor(
                colorOverlayState.currentColor[1],
                colorOverlayState.currentColor[2],
                colorOverlayState.currentColor[3]
            )
            colorOverlay:SetAlpha(1)
        end
        model.SetColorOverlayFill(colorOverlayState.fillFrac)

        local activeGauge = TIER_GAUGE_INDEX[tier] or 1
        for i, key in ipairs(gaugeKeys) do
            local targetAlpha
            if i == 1 then
                -- Keep 0% gauge as a persistent base; higher gauges fade over it.
                targetAlpha = 1
            elseif i == activeGauge then
                targetAlpha = TIER_GAUGE_ALPHA[tier] or 1
            else
                targetAlpha = 0
            end
            gaugeCurrentAlpha[i] = SmoothAlpha(gaugeCurrentAlpha[i], targetAlpha, elapsed, 0.05, 0.40)
            local tex = frame.textures[key]
            if tex then
                tex:SetAlpha(gaugeCurrentAlpha[i])
            end
        end

        model.UpdateGaugeShake(elapsed, now, rawFillTarget, impulsePressure)
    end

    return model
end
