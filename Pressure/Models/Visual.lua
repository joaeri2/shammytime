local addonName = ...
if addonName ~= "ShammyTime" then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

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
    local getTierSegmentProgress = ctx.getTierSegmentProgress
    local getTierPromoteThreshold = ctx.getTierPromoteThreshold

    local model = {}
    local NON_T5_FULL_CAP = 0.998

    local function Clamp01(v)
        if v <= 0 then return 0 end
        if v >= 1 then return 1 end
        return v
    end

    local function Lerp(a, b, t)
        return a + ((b - a) * t)
    end

    local function GetColorForCharge(charge)
        local c = Clamp01(charge or 0)
        local pos = c * 5
        local i = math.floor(pos) + 1
        if i < 1 then i = 1 end
        if i >= 6 then
            local c6 = TIER_COLORS[6] or TIER_COLORS[1]
            return c6[1], c6[2], c6[3]
        end
        local t = pos - math.floor(pos)
        local cA = TIER_COLORS[i] or TIER_COLORS[1]
        local cB = TIER_COLORS[i + 1] or cA
        return Lerp(cA[1], cB[1], t), Lerp(cA[2], cB[2], t), Lerp(cA[3], cB[3], t)
    end

    local function NormalizeChargeFromThresholds(score, t1, t2, t3, t4, t5)
        local s = tonumber(score) or 0
        if s <= 0 then return 0 end
        local a = math_max(tonumber(t1) or 0, 0.001)
        local b = math_max(tonumber(t2) or a, a + 0.001)
        local c = math_max(tonumber(t3) or b, b + 0.001)
        local d = math_max(tonumber(t4) or c, c + 0.001)
        local e = math_max(tonumber(t5) or d, d + 0.001)

        if s < a then
            return Clamp01(s / a) * 0.20
        elseif s < b then
            return 0.20 + (Clamp01((s - a) / (b - a)) * 0.20)
        elseif s < c then
            return 0.40 + (Clamp01((s - b) / (c - b)) * 0.20)
        elseif s < d then
            return 0.60 + (Clamp01((s - c) / (d - c)) * 0.20)
        elseif s < e then
            return 0.80 + (Clamp01((s - d) / (e - d)) * 0.20)
        end
        return 1
    end

    local function StopChargeLightning()
        local fx = visualAnimState.chargeLightningFx
        if not fx then return end
        if fx.lightningPulseTimer then
            fx.lightningPulseTimer:Cancel()
            fx.lightningPulseTimer = nil
        end
        if fx.lightningPulseTicker then
            fx.lightningPulseTicker:Cancel()
            fx.lightningPulseTicker = nil
        end
        if fx.lightningPulseGroup then
            fx.lightningPulseGroup:Stop()
        end
    end

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
        local fromFill = math_min(math_max(fromFillFrac or colorOverlayState.fillFrac or 0, 0), 1)
        -- Charge mode: keep bar continuous from T0->T5; no tier step drop transfer.
        if PUSH_FEEL_CFG.chargeVisualMode ~= false then
            visualAnimState.colorOverlayTransferActive = false
            visualAnimState.colorOverlayTransferElapsed = 0
            visualAnimState.colorOverlayTransferFrom = fromFill
            visualAnimState.colorOverlayTransferTo = fromFill
            colorOverlayState.fullHoldRemaining = 0
            local promoSeed = 0.75 + (0.25 * fromFill)
            if promoSeed > (visualAnimState.tierPromoFlash or 0) then
                visualAnimState.tierPromoFlash = promoSeed
            end
            return
        end
        visualAnimState.colorOverlayTransferActive = true
        visualAnimState.colorOverlayTransferElapsed = 0
        visualAnimState.colorOverlayTransferFrom = fromFill
        visualAnimState.colorOverlayTransferTo = 0
        colorOverlayState.fullHoldRemaining = 0
        local promoSeed = 0.75 + (0.25 * fromFill)
        if promoSeed > (visualAnimState.tierPromoFlash or 0) then
            visualAnimState.tierPromoFlash = promoSeed
        end
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

    function model.UpdateGaugeShake(elapsed, now, chargeFrac, impulsePressure)
        local charge = Clamp01(chargeFrac or 0)
        -- Shake rises continuously with charge (not only near full).
        local fillStress = charge ^ 1.20

        local damageStress = 0
        do
            local overloadRef = math_max(PUSH_FEEL_CFG.overloadThreshold or 1.10, 0.05)
            local pressureScale = math_max(PUSH_FEEL_CFG.gaugeShakeDamageScale or 0.85, 0)
            local normalizedImpulse = math_max((impulsePressure or 0) / overloadRef, 0)
            damageStress = math_min(((normalizedImpulse * 2.10) ^ 0.68) * pressureScale, 1.0)
        end

        local resistMax = math_max((PS and PS.tierEdgeResistMax) or 0.52, 0.001)
        local resistStress = math_min(math_max((PS and PS.tierEdgeResistance or 0) / resistMax, 0), 1)
        if charge <= 0.02 and damageStress < 0.08 then
            resistStress = 0
        end

        local stressTarget = math_min(
            math_max(
                math_max(fillStress, resistStress * 0.90, damageStress * 0.95),
                0
            ),
            1
        )
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
        local ampCurve = 0.35 + (0.85 * (charge ^ 1.35))
        local ampX = PUSH_FEEL_CFG.gaugeShakeMaxX * shakeAmount * visualAnimState.gaugeShakeStress * ampCurve
        local ampY = PUSH_FEEL_CFG.gaugeShakeMaxY * shakeAmount * visualAnimState.gaugeShakeStress * ampCurve
        local shakeX = (math.sin(t * PUSH_FEEL_CFG.gaugeShakeFreqX1) * ampX) + (math.cos(t * PUSH_FEEL_CFG.gaugeShakeFreqX2 + 0.9) * ampX * 0.35)
        local shakeY = math.sin(t * PUSH_FEEL_CFG.gaugeShakeFreqY1 + 1.2) * ampY
        model.SetGaugeTextureOffset(shakeX, shakeY)
    end

    function model.ResetChargeEffects()
        StopChargeLightning()
        visualAnimState.chargeFrac = 0
        visualAnimState.chargeWasFull = false
        visualAnimState.lastChargeExplosionAt = 0
        visualAnimState.chargeTier5HoldUntil = 0
        visualAnimState.chargeEnergyAlpha = 0.00
        if frame.textures.chargeEnergy then
            frame.textures.chargeEnergy:SetAlpha(0.00)
        end
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
        local tNow = now or GetTime()
        local tierColor = TIER_COLORS[tier + 1] or TIER_COLORS[1]
        local coolingBlueBlend = 0
        local impulse = math_max(impulsePressure or 0, 0)
        local hitReactTarget = math_min(((impulse * 2.30) ^ 0.72), 1)
        if visualAnimState.promotionPending then
            hitReactTarget = math_max(hitReactTarget, 0.45)
        end
        visualAnimState.hitReact = SmoothAlpha(
            visualAnimState.hitReact or 0,
            hitReactTarget,
            elapsed,
            PUSH_FEEL_CFG.hitReactTauIn or 0.03,
            PUSH_FEEL_CFG.hitReactTauOut or 0.26
        )
        visualAnimState.tierPromoFlash = SmoothAlpha(
            visualAnimState.tierPromoFlash or 0,
            0,
            elapsed,
            0.04,
            PUSH_FEEL_CFG.tierPromoFlashTauOut or 0.45
        )
        local hitReact = math_min(math_max(visualAnimState.hitReact or 0, 0), 1)
        local promoFlash = math_min(math_max(visualAnimState.tierPromoFlash or 0, 0), 1)
        local rewardPulse = math_min(math_max((hitReact * 0.75) + (promoFlash * 0.90), 0), 1)

        local scoreForProgress = PS.tierEvalScore or PS.tierScore or 0
        local chargeTier = tier
        local chargeFrac = getTierFillTarget(scoreForProgress, tier)
        if getTierSegmentProgress then
            local segTier, segFrac = getTierSegmentProgress(scoreForProgress)
            if segTier ~= nil then
                chargeTier = math.floor(tonumber(segTier) or chargeTier)
            end
            if segFrac ~= nil then
                chargeFrac = segFrac
            end
        elseif getTierPromoteThreshold then
            -- Fallback only when the model does not expose segmented progress.
            local t1 = tonumber(getTierPromoteThreshold(1))
            local t2 = tonumber(getTierPromoteThreshold(2))
            local t3 = tonumber(getTierPromoteThreshold(3))
            local t4 = tonumber(getTierPromoteThreshold(4))
            local t5 = tonumber(getTierPromoteThreshold(5))
            if t1 and t2 and t3 and t4 and t5 and t5 > 0 then
                local normalized = NormalizeChargeFromThresholds(scoreForProgress, t1, t2, t3, t4, t5)
                chargeTier = math.floor(Clamp01(normalized) * 5)
                chargeFrac = (Clamp01(normalized) * 5) - chargeTier
            end
        end
        chargeTier = math_min(math_max(tonumber(chargeTier) or 0, 0), 5)
        chargeFrac = Clamp01(tonumber(chargeFrac) or 0)
        local topHoldSec = math_max(tonumber(PS.tierTopHoldMinSec) or 0, 0)
        if topHoldSec > 0 then
            local holdUntil = tonumber(visualAnimState.chargeTier5HoldUntil) or 0
            local tierHoldActive = false
            if tier >= 5 then
                local sinceTierChange = tNow - (PS.lastTierChangeAt or 0)
                if sinceTierChange < topHoldSec then
                    tierHoldActive = true
                end
            end
            if chargeTier >= 5 or tierHoldActive then
                holdUntil = math_max(holdUntil, tNow + topHoldSec)
            end
            if holdUntil > tNow and chargeTier < 5 then
                -- Once T5 is reached, hold visuals briefly to avoid flip-flop.
                chargeTier = 5
                chargeFrac = 1
            end
            visualAnimState.chargeTier5HoldUntil = holdUntil
        else
            visualAnimState.chargeTier5HoldUntil = 0
        end
        local chargeTarget
        if chargeTier >= 5 then
            chargeTarget = 1
        else
            chargeTarget = Clamp01((chargeTier + chargeFrac) / 5)
            chargeTarget = math_min(chargeTarget, NON_T5_FULL_CAP)
        end
        local prevCharge = Clamp01(visualAnimState.chargeFrac or 0)
        local chargeSmooth = SmoothAlpha(
            prevCharge,
            Clamp01(chargeTarget or 0),
            elapsed,
            0.11,
            0.90
        )
        local maxRisePerSec = 1.10
        local maxFallPerSec = 0.10
        local upCap = elapsed * maxRisePerSec
        local downCap = elapsed * maxFallPerSec
        if chargeSmooth > (prevCharge + upCap) then
            chargeSmooth = prevCharge + upCap
        elseif chargeSmooth < (prevCharge - downCap) then
            chargeSmooth = prevCharge - downCap
        end
        if chargeTier < 5 and chargeSmooth > NON_T5_FULL_CAP then
            chargeSmooth = NON_T5_FULL_CAP
        end
        visualAnimState.chargeFrac = Clamp01(chargeSmooth)
        local chargeShown = Clamp01(visualAnimState.chargeFrac or chargeTarget)
        local visualTier = math_min(math_max(math.floor(chargeShown * 5), 0), 5)
        local tr, tg, tb = GetColorForCharge(chargeShown)
        tierColor = { tr, tg, tb }

        if chargeTier >= 5 and chargeTarget >= 0.999 and chargeShown >= 0.995 then
            local lastExplosionAt = visualAnimState.lastChargeExplosionAt or 0
            if (not visualAnimState.chargeWasFull) and ((tNow - lastExplosionAt) >= 0.35) then
                visualAnimState.chargeWasFull = true
                visualAnimState.lastChargeExplosionAt = tNow
                visualAnimState.tierPromoFlash = 1
                local energyTex = frame.textures.chargeEnergy
                if energyTex and ShammyTime.StartLightningPulses then
                    local fx = visualAnimState.chargeLightningFx
                    if not fx then
                        fx = {}
                        visualAnimState.chargeLightningFx = fx
                    end
                    if not fx.energy then
                        fx.energy = {
                            SetAlpha = function(_, a)
                                local raw = tonumber(a) or 0
                                local norm = (raw - 0.12) / 0.88
                                if norm <= 0 then
                                    energyTex:SetAlpha(0)
                                    return
                                end
                                energyTex:SetAlpha(Clamp01(norm * 0.82))
                            end,
                        }
                    end
                    ShammyTime.StartLightningPulses(fx)
                end
            end
        else
            if chargeTarget <= 0.92 then
                visualAnimState.chargeWasFull = false
            end
        end

        -- Charge mode: bar is global T0->T5 progression.
        local fillTarget = chargeShown
        if chargeTier < 5 and fillTarget > NON_T5_FULL_CAP then
            fillTarget = NON_T5_FULL_CAP
        end
        -- In charge mode, keep fill truthful to computed charge so it does not
        -- fake-jump to full on hit-react.
        if PUSH_FEEL_CFG.chargeVisualMode == false and visualTier < 5 and hitReact > 0.001 then
            local kickMax = math_max(PUSH_FEEL_CFG.hitReactFillKick or 0.24, 0)
            fillTarget = math_min(1, fillTarget + (kickMax * (hitReact ^ 0.70)))
        end

        -- Keep charge continuity; tier transfers are visual noise in this mode.
        if PUSH_FEEL_CFG.chargeVisualMode ~= false then
            visualAnimState.colorOverlayTransferActive = false
            visualAnimState.promotionPending = false
            if chargeTier >= 5 and fillTarget >= 0.999 then
                fillTarget = 1
            end
        end

        if visualAnimState.promotionPending and (not visualAnimState.colorOverlayTransferActive) then
            fillTarget = 1
        end

        if PUSH_FEEL_CFG.chargeVisualMode == false and tier >= 5 then
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
                -- Keep cooldown transfer visible, but avoid multi-second lag.
                transferDuration = transferDuration * 1.35
            end
            local tLinear = math_min(math_max(visualAnimState.colorOverlayTransferElapsed / transferDuration, 0), 1)
            if descending then
                -- Keep a short top hold right after tier-up so the cooldown
                -- reads as a transfer, not an instant drop.
                local holdFrac = 0.06
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
                local fallShape = (1 - t) ^ 1.10
                local tailDrag = 0.82 + (0.18 * (1 - t))
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
                local carryFloor = landingTarget + ((fromFill - landingTarget) * 0.18 * ((1 - t) ^ 1.30))
                targetValue = math_max(targetValue, carryFloor)
                coolingBlueBlend = 0.90 * ((1 - t) ^ 0.35)
            end
            -- Add corner drag so both start/end naturally decelerate.
            local corner = 1 - (4 * t * (1 - t))
            corner = math_min(math_max(corner, 0), 1)
            local settleTau = 0.016 + (0.080 * (corner ^ 1.35))
            if descending then
                settleTau = settleTau * 1.25
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
            if PUSH_FEEL_CFG.chargeVisualMode ~= false then
                -- Pure 0-100 charge presentation: keep fill truthful to charge.
                colorOverlayState.fullHoldRemaining = 0
                local riseTau = 0.05
                local fallTau = 0.45
                if hitReact > 0.001 then
                    riseTau = math_max(0.02, riseTau * (1 - (0.55 * hitReact)))
                end
                colorOverlayState.fillFrac = SmoothAlpha(
                    colorOverlayState.fillFrac,
                    fillTarget,
                    elapsed,
                    riseTau,
                    fallTau
                )
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
                local currentFill = math_min(math_max(colorOverlayState.fillFrac or 0, 0), 1)
                local delta = fillTarget - currentFill
                local fallTau = FILL_SMOOTH_TAU_FALL
                if delta >= 0 then
                    -- Add a little viscosity on ascent so spikes still pop but do
                    -- not look twitchy.
                    riseTau = riseTau * (1.22 + (0.25 * (edgeProgress ^ 1.4)))
                    riseTau = riseTau * (1 - (0.45 * hitReact))
                    riseTau = math_max(riseTau, 0.02)
                else
                    -- Add stronger viscosity on descent, with extra drag near
                    -- empty so cooldown decelerates toward the start.
                    local nearStart = (1 - currentFill) ^ 1.8
                    -- Fast response high in the bar, slower near zero.
                    fallTau = fallTau * (0.26 + (0.66 * nearStart))
                    -- While hits are still landing, hold pressure a bit longer.
                    fallTau = fallTau * (1 + (1.10 * hitReact))
                end
                colorOverlayState.fillFrac = SmoothAlpha(
                    colorOverlayState.fillFrac,
                    fillTarget,
                    elapsed,
                    riseTau,
                    fallTau
                )
            end
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
            if rewardPulse > 0.001 then
                local burstR, burstG, burstB = 1.00, 0.97, 0.45
                local boost = math_min(
                    math_max(
                        ((PUSH_FEEL_CFG.hitReactColorBoost or 0.34) * hitReact)
                        + ((PUSH_FEEL_CFG.tierPromoFlashColorBoost or 0.42) * promoFlash),
                        0
                    ),
                    1
                )
                colorTargetR = colorTargetR + ((burstR - colorTargetR) * boost)
                colorTargetG = colorTargetG + ((burstG - colorTargetG) * boost)
                colorTargetB = colorTargetB + ((burstB - colorTargetB) * boost)
                colorTauIn = math_min(colorTauIn, 0.040)
                colorTauOut = math_min(colorTauOut, 0.120)
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

        local chargeEnergy = frame.textures.chargeEnergy
        if chargeEnergy then
            local fx = visualAnimState.chargeLightningFx
            local lightningActive = fx and (fx.lightningPulseTimer or fx.lightningPulseTicker)
            if not lightningActive then
                local overdriveGlow = math_max((visualAnimState.chargeFrac or 0) - 0.88, 0) * 0.08
                local energyTarget = Clamp01(overdriveGlow + (rewardPulse * 0.04))
                visualAnimState.chargeEnergyAlpha = SmoothAlpha(
                    visualAnimState.chargeEnergyAlpha or 0.00,
                    energyTarget,
                    elapsed,
                    0.06,
                    0.16
                )
                chargeEnergy:SetAlpha(visualAnimState.chargeEnergyAlpha)
            end
        end

        model.SetColorOverlayFill(colorOverlayState.fillFrac)

        local activeGauge = TIER_GAUGE_INDEX[visualTier] or 1
        for i, key in ipairs(gaugeKeys) do
            local targetAlpha
            if i == 1 then
                targetAlpha = 1
            elseif i == activeGauge then
                targetAlpha = math_min((TIER_GAUGE_ALPHA[visualTier] or 1) + (0.45 * rewardPulse), 1)
            else
                targetAlpha = 0
            end
            gaugeCurrentAlpha[i] = SmoothAlpha(gaugeCurrentAlpha[i], targetAlpha, elapsed, 0.05, 0.40)
            local tex = frame.textures[key]
            if tex then
                tex:SetAlpha(gaugeCurrentAlpha[i])
            end
        end

        model.UpdateGaugeShake(elapsed, now, chargeShown, impulsePressure)
    end

    return model
end
