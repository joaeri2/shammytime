-- ShammyTime_CenterRing.lua
-- Center ring: layered textures, proc animation. Toggle/scale via /st circle.
-- No satellites, no combat log. Purely asset + animation integration test.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local M = ShammyTime_Media
if not M then return end

local TEX = M.TEX
local centerFrame      -- main center ring frame (created once; child of radialWrapper)
local radialWrapper    -- single scalable container for center + satellites (created once)
local totemBarFrame    -- separate draggable totem bar frame (created once)

-- ========== Timing constants ==========
-- How long satellite numbers (MIN, AVG, MAX, etc.) stay visible after a proc before they start fading out.
local WF_NUMBERS_HOLD_BEFORE_FADE = 2
-- How long the center "Windfury!" + "TOTAL: xxx" text stays fully visible after the proc animation ends, before it fades.
local WF_TEXT_HOLD_BEFORE_FADE = 1

-- ========== Lightning pulse constants (energy layer only; runes are not pulsed) ==========
-- Delay in seconds after the main "BOOM" proc animation before the first lightning blink.
local WF_LIGHTNING_DELAY_AFTER_BOOM = 0.55
-- Number of lightning blinks (energy layer brightens then dims).
local WF_LIGHTNING_PULSE_COUNT = 3
-- Random range for how bright the energy gets on each blink (0.28–0.55).
local WF_LIGHTNING_ENERGY_PEAK_MIN, WF_LIGHTNING_ENERGY_PEAK_MAX = 0.28, 0.55
-- (Unused: rune peaks were removed so lightning doesn't touch the rune ring.)
local WF_LIGHTNING_RUNE_PEAK_MIN, WF_LIGHTNING_RUNE_PEAK_MAX = 0.22, 0.45
-- Random duration for each blink: ramp-up and ramp-down time.
local WF_LIGHTNING_UP_DUR_MIN, WF_LIGHTNING_UP_DUR_MAX = 0.03, 0.065
local WF_LIGHTNING_DOWN_DUR_MIN, WF_LIGHTNING_DOWN_DUR_MAX = 0.07, 0.14
-- Random gap in seconds between one blink finishing and the next starting.
local WF_LIGHTNING_GAP_MIN, WF_LIGHTNING_GAP_MAX = 0.09, 0.19

-- Returns the user's saved scale for the center ring (0.5–2). Used when showing the ring and by /st circle scale.
local function GetRadialScale()
    local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB() or {}
    return (db.wfRadialScale and db.wfRadialScale >= 0.5 and db.wfRadialScale <= 2) and db.wfRadialScale or 1
end

-- Returns the user's saved scale for the Windfury totem bar (0.5–2).
local function GetTotemBarScale()
    local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB() or {}
    return (db.wfTotemBarScale and db.wfTotemBarScale >= 0.5 and db.wfTotemBarScale <= 2) and db.wfTotemBarScale or 1.0
end

-- Formats a number for display (e.g. 1500 -> "1.5k", 2000000 -> "2.0m").
local function FormatNum(n)
    if not n or n < 0 then return "0" end
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

-- Default position when user has never dragged (so the radial is movable from first load).
local CENTER_DEFAULT_X, CENTER_DEFAULT_Y = 0, -180

-- Flag to prevent ApplyCenterPosition from overwriting position during drag
-- Exposed globally so satellites can also set it
local isRadialDragging = false
function ShammyTime.SetRadialDragging(dragging)
    isRadialDragging = dragging
end

-- Saves the center ring's current position when the user stops dragging (per character).
-- Must be defined before ApplyCenterPosition so it can be called when pos.center is nil.
local function SaveCenterPosition(f)
    if not ShammyTime.GetRadialPositionDB then return end
    local pos = ShammyTime.GetRadialPositionDB()
    local point, relTo, relativePoint, x, y = f:GetPoint(1)
    if not point then return end  -- safety check
    pos.center = {
        point = point,
        relativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent",
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

-- Applies saved position to the center ring frame (so it appears where the user last left it).
-- When pos.center is nil (first load), applies default position and saves it so it persists.
-- Does NOT apply during drag to prevent overwriting user's drag position.
local function ApplyCenterPosition(f)
    if isRadialDragging then return end  -- don't overwrite during drag
    local pos = ShammyTime.GetRadialPositionDB and ShammyTime.GetRadialPositionDB()
    if not pos then return end
    f:ClearAllPoints()
    if pos.center then
        local c = pos.center
        local relTo = (c.relativeTo and _G[c.relativeTo]) or UIParent
        if relTo then
            f:SetPoint(c.point or "CENTER", relTo, c.relativePoint or "CENTER", c.x or 0, c.y or 0)
        else
            f:SetPoint("CENTER", UIParent, "CENTER", CENTER_DEFAULT_X, CENTER_DEFAULT_Y)
        end
    else
        f:SetPoint("CENTER", UIParent, "CENTER", CENTER_DEFAULT_X, CENTER_DEFAULT_Y)
        SaveCenterPosition(f)
    end
end

-- Global wrapper for repositioning Windfury radial (wrapper frame) after scale change
function ShammyTime.ApplyCenterRingPosition()
    local f = _G.ShammyTimeWindfuryRadial
    if f then ApplyCenterPosition(f) end
end

-- Resize radial wrapper to match the actual circle+bubbles footprint.
function ShammyTime.ApplyWindfuryRadialWrapperSize()
    local f = _G.ShammyTimeWindfuryRadial
    if not f then return end
    local size = (ShammyTime.GetWindfuryRadialWrapperSize and ShammyTime.GetWindfuryRadialWrapperSize()) or nil
    if not size or size <= 0 then return end
    f:SetSize(size, size)
end

-- Current center circle size (diameter) from DB
local function GetCenterSize()
    return (ShammyTime.GetCenterSize and ShammyTime.GetCenterSize()) or 200
end

-- Current center text Y offsets from DB (pixels from center; +Y = up)
-- Defaults to 0. Adjust via Developer panel, then export and update code.
local function GetCenterTextOffsets()
    local db = ShammyTime.GetDB and ShammyTime.GetDB() or {}
    return {
        titleY    = (db.wfCenterTextTitleY ~= nil) and db.wfCenterTextTitleY or 0,
        totalY    = (db.wfCenterTextTotalY ~= nil) and db.wfCenterTextTotalY or 0,
        criticalY = (db.wfCenterTextCriticalY ~= nil) and db.wfCenterTextCriticalY or 0,
    }
end

-- Wrapper frame: one scalable container for center + satellites so the whole radial scales as a single object.
local function CreateRadialWrapper()
    if radialWrapper then return radialWrapper end
    local WrapperSize = (ShammyTime.GetWindfuryRadialWrapperSize and ShammyTime.GetWindfuryRadialWrapperSize()) or 600
    radialWrapper = CreateFrame("Frame", "ShammyTimeWindfuryRadial", UIParent)
    radialWrapper:SetFrameStrata("MEDIUM")
    radialWrapper:SetSize(WrapperSize, WrapperSize)
    radialWrapper:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    ApplyCenterPosition(radialWrapper)
    radialWrapper:SetScale(GetRadialScale())
    radialWrapper:SetMovable(true)
    radialWrapper:SetClampedToScreen(true)
    radialWrapper:EnableMouse(false)  -- pass-through; center handles drag and syncs wrapper
    radialWrapper:Hide()
    _G.ShammyTimeWindfuryRadial = radialWrapper
    return radialWrapper
end

-- Creates the main center ring frame once; subsequent calls return the same frame.
-- Center is a child of the radial wrapper so scale applies to the whole radial as one.
-- Contains: ring subframe (textures + proc animation), text frame ("Windfury!", "TOTAL: xxx"), and behavior (drag, right-click reset).
local function CreateCenterRingFrame()
    if centerFrame then return centerFrame end

    CreateRadialWrapper()
    local centerSize = GetCenterSize()
    local f = CreateFrame("Frame", "ShammyTimeCenterRing", radialWrapper)
    f.wfProcAnimPlaying = false
    f.wrapper = radialWrapper
    f:SetFrameStrata("MEDIUM")
    f:SetSize(centerSize, centerSize)
    f:SetScale(1)  -- scale is on wrapper only so center + satellites scale as one
    f:SetPoint("CENTER", radialWrapper, "CENTER", 0, 0)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    -- Drag: center moves itself, then syncs wrapper position after (StartMoving only works on frame that received mouse down)
    f:SetScript("OnDragStart", function(self)
        if ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB().locked then return end
        ShammyTime.SetRadialDragging(true)
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        ShammyTime.SetRadialDragging(false)
        self:StopMovingOrSizing()
        -- Get center's new screen position
        local point, _, relPoint, x, y = self:GetPoint(1)
        -- Move wrapper to match where center was dragged
        local wrapper = self.wrapper or radialWrapper
        if wrapper then
            wrapper:ClearAllPoints()
            wrapper:SetPoint(point or "CENTER", UIParent, relPoint or "CENTER", x or 0, y or 0)
            SaveCenterPosition(wrapper)
        end
        -- Re-anchor center to wrapper's center
        self:ClearAllPoints()
        self:SetPoint("CENTER", wrapper, "CENTER", 0, 0)
    end)
    -- Hover: show numbers (quick-peek). Reset hint is in the addon start message in chat.
    f:SetScript("OnEnter", function(self)
        ShammyTime.circleHovered = true
        if ShammyTime.OnRadialHoverEnter then ShammyTime.OnRadialHoverEnter() end
    end)
    f:SetScript("OnLeave", function()
        ShammyTime.circleHovered = false
        if ShammyTime.OnRadialHoverLeave then ShammyTime.OnRadialHoverLeave() end
    end)
    -- Right-click: reset Windfury stats (session/pull), clear "CRITICAL", set TOTAL to 0, refresh satellite numbers.
    f:SetScript("OnMouseDown", function(self, button)
        if button ~= "RightButton" then return end
        if ShammyTime and ShammyTime.ResetWindfurySession then
            ShammyTime.ResetWindfurySession()
        end
        if ShammyTime then ShammyTime.lastProcTotal = 0 end
        if ShammyTime and ShammyTime.UpdateSatelliteValues and ShammyTime_Windfury_GetStats then
            ShammyTime.UpdateSatelliteValues(ShammyTime_Windfury_GetStats())
        end
        if centerFrame then
            if centerFrame.criticalLine then centerFrame.criticalLine:Hide() end
            if centerFrame.total then
                centerFrame.total:SetPoint("CENTER", 0, GetCenterTextOffsets().totalY)
                centerFrame.total:SetText("TOTAL: 0")
            end
            if centerFrame.title then centerFrame.title:SetText("Windfury!") end
        end
        -- Refresh satellite numbers so they show reset values (0 / –)
        if ShammyTime.UpdateSatelliteValues and ShammyTime_Windfury_GetStats then
            ShammyTime.UpdateSatelliteValues(ShammyTime_Windfury_GetStats())
        end
        print("ShammyTime: Statistics have been reset.")
    end)
    f:Hide()

    -- Ring subframe: holds all visual layers (shadow, bg, energy, border, runes). This frame scales during proc (pop effect); satellites are parented here so they move with the ring. Totem bar is a sibling, so it does not scale.
    local ringFrame = CreateFrame("Frame", nil, f)
    ringFrame:SetSize(centerSize, centerSize)
    ringFrame:SetPoint("CENTER", f, "CENTER", 0, 0)
    ringFrame:SetFrameLevel(1)
    f.ringFrame = ringFrame

    -- Layer 0: Soft shadow behind the circle. Slightly larger than the ring; scales with the ring on proc.
    local scale = centerSize / 200
    local ringShadowSize = 222 * scale
    local ringShadowOffsetY = -7 * scale
    ringFrame.shadow = ringFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
    ringFrame.shadow:SetSize(ringShadowSize, ringShadowSize)
    ringFrame.shadow:SetPoint("CENTER", 0, ringShadowOffsetY)
    ringFrame.shadow:SetTexture(TEX.CENTER_SHADOW)
    ringFrame.shadow:SetTexCoord(0, 1, 0, 1)
    ringFrame.shadow:SetVertexColor(1, 1, 1, 0.26)

    -- Layer 1: Background disc (wf_center_bg.tga). Always full opacity.
    ringFrame.bg = ringFrame:CreateTexture(nil, "BACKGROUND")
    ringFrame.bg:SetAllPoints(ringFrame)
    ringFrame.bg:SetTexture(TEX.CENTER_BG)
    ringFrame.bg:SetAlpha(1)

    -- Layer 2: Energy/glow (wf_center_energy.tga). Low alpha when idle; flashes bright on proc and is used by lightning pulses. ADD blend makes it glow.
    ringFrame.energy = ringFrame:CreateTexture(nil, "ARTWORK")
    ringFrame.energy:SetAllPoints(ringFrame)
    ringFrame.energy:SetTexture(TEX.CENTER_ENERGY)
    ringFrame.energy:SetAlpha(0.12)
    ringFrame.energy:SetBlendMode("ADD")

    -- Layer 3: Ornate border ring (wf_center_border.tga). Always full opacity.
    ringFrame.border = ringFrame:CreateTexture(nil, "BORDER")
    ringFrame.border:SetAllPoints(ringFrame)
    ringFrame.border:SetTexture(TEX.CENTER_BORDER)
    ringFrame.border:SetAlpha(1)

    -- Layer 4: Rune circle overlay (wf_center_runes.tga). Hidden (alpha 0) when idle. On proc: flashes to full visibility, spins slightly, then fades out to 0 over a few seconds. No other system touches runes (e.g. lightning only affects energy).
    local RUNE_RING_SIZE = 144 * scale
    local RUNE_RING_OFFSET_X, RUNE_RING_OFFSET_Y = -1 * scale, 7 * scale
    ringFrame.runes = ringFrame:CreateTexture(nil, "OVERLAY")
    ringFrame.runes:SetTexture(TEX.CENTER_RUNES)
    ringFrame.runes:SetAlpha(0)
    ringFrame.runes:SetSize(RUNE_RING_SIZE, RUNE_RING_SIZE)
    ringFrame.runes:SetPoint("CENTER", RUNE_RING_OFFSET_X, RUNE_RING_OFFSET_Y)

    -- Text frame: holds "Windfury!", "TOTAL: xxx", and optional "CRITICAL". Child of main frame so it doesn't get scaled by the ring's proc pop; it stays crisp. Still scales with /st circle scale (whole frame scale).
    local textFrame = CreateFrame("Frame", "ShammyTimeCenterRingText", f)
    textFrame:SetFrameStrata("MEDIUM")
    textFrame:SetFrameLevel(10)
    textFrame:SetSize(centerSize, centerSize)
    textFrame:SetPoint("CENTER", f, "CENTER", 0, 0)
    textFrame:EnableMouse(false)  -- allow drag to pass through to center when clicking text
    textFrame:Hide()
    f.textFrame = textFrame

    -- Fade-out animation: when proc ends, fade text then hide (so "Windfury!" only visible during proc)
    local fadeOutAg = textFrame:CreateAnimationGroup()
    local aOut = fadeOutAg:CreateAnimation("Alpha")
    aOut:SetFromAlpha(1)
    aOut:SetToAlpha(0)
    aOut:SetDuration(1.2)  -- slow fade out for "Windfury!" + total
    aOut:SetSmoothing("OUT")
    fadeOutAg:SetScript("OnFinished", function()
        textFrame:SetAlpha(1)
        textFrame:Hide()
    end)
    textFrame.fadeOutAnim = fadeOutAg

    local dbFont = ShammyTime.GetDB and ShammyTime.GetDB() or {}
    local fontTitle = (dbFont.fontCircleTitle and dbFont.fontCircleTitle >= 6 and dbFont.fontCircleTitle <= 28) and dbFont.fontCircleTitle or 20
    local fontTotal = (dbFont.fontCircleTotal and dbFont.fontCircleTotal >= 6 and dbFont.fontCircleTotal <= 28) and dbFont.fontCircleTotal or 14
    local fontCritical = (dbFont.fontCircleCritical and dbFont.fontCircleCritical >= 6 and dbFont.fontCircleCritical <= 28) and dbFont.fontCircleCritical or 20
    local textOff = GetCenterTextOffsets()

    -- Optional "CRITICAL" line (shown when the proc included a crit). Sits above "Windfury!" when visible.
    f.criticalLine = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.criticalLine:SetPoint("CENTER", 0, textOff.criticalY)
    f.criticalLine:SetText("CRITICAL")
    f.criticalLine:SetTextColor(1, 0.5, 0.3)  -- orange-red for impact
    f.criticalLine:SetFont("Fonts\\FRIZQT__.TTF", fontCritical, "OUTLINE")
    f.criticalLine:Hide()
    f.criticalLineRestColor = {1, 0.5, 0.3}
    f.criticalLineFlashColor = {1, 0.9, 0.5}

    f.title = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("CENTER", 0, textOff.titleY)
    f.title:SetText("Windfury!")
    f.title:SetTextColor(1, 0.9, 0.4)
    f.title:SetFont("Fonts\\FRIZQT__.TTF", fontTitle, "OUTLINE")
    f.titleRestColor = {1, 0.9, 0.4}
    f.titleFlashColor = {1, 1, 1}  -- bright white flash

    f.total = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.total:SetPoint("CENTER", 0, textOff.totalY)  -- Y is adjusted in PlayCenterRingProc when "CRITICAL" is shown so three lines fit
    f.total:SetText("TOTAL: 3245")
    f.total:SetTextColor(1, 1, 1)
    f.total:SetFont("Fonts\\FRIZQT__.TTF", fontTotal, "OUTLINE")
    f.totalRestColor = {1, 1, 1}
    f.totalFlashColor = {1, 1, 0.5}  -- bright yellow flash

    -- Proc pulse: the ring's *scale* (pop/breath) is driven by a separate ticker in PlayCenterRingProc, not by this animation group. This group only animates: energy alpha, rune alpha, rune rotation.

    local function BuildProcAnim(rf)
        local g = rf:CreateAnimationGroup()

        -- Energy flash+soften is done in OnPlay with a ticker so the animation group does not "own" rf.energy for 6s (which would block lightning pulses from showing).

        -- Runes: instant flash from hidden to full visibility, then slow fade back to fully hidden (0). Duration of the fade is 3s; adjust for faster/slower fade-out.
        local runeFlash = g:CreateAnimation("Alpha")
        runeFlash:SetTarget(rf.runes)
        runeFlash:SetOrder(1)
        runeFlash:SetDuration(0.02)
        runeFlash:SetFromAlpha(0)
        runeFlash:SetToAlpha(1)

        local runeSoft = g:CreateAnimation("Alpha")
        runeSoft:SetTarget(rf.runes)
        runeSoft:SetOrder(2)
        runeSoft:SetDuration(4)
        runeSoft:SetFromAlpha(1)
        runeSoft:SetToAlpha(0)
        runeSoft:SetSmoothing("OUT")

        -- Rune rotation is driven by a momentum ticker (fast spin then lose momentum), not by an animation.

        return g
    end

    ringFrame.procAnim = BuildProcAnim(ringFrame)
    local ag = ringFrame.procAnim
    -- Start momentum spin when proc anim plays: fast at first, then slows down like a wheel (same 3s as rune fade).
    ag:SetScript("OnPlay", function()
        local rf = ringFrame
        -- Energy: flash to full then soften to 0.18 over 0.35s (timer-driven so lightning can later control energy without being overwritten)
        if rf.energy then
            rf.energy:SetAlpha(1)
            if rf.energySoftTicker then rf.energySoftTicker:Cancel() end
            local softDur = 0.35
            local steps = math.max(1, math.floor(softDur / 0.02))
            local step = 0
            rf.energySoftTicker = C_Timer.NewTicker(softDur / steps, function()
                step = step + 1
                local t = step / steps
                rf.energy:SetAlpha(1 + (0.18 - 1) * t)
                if step >= steps then
                    rf.energySoftTicker:Cancel()
                    rf.energySoftTicker = nil
                    rf.energy:SetAlpha(0.18)
                end
            end)
        end
        if not rf.runes then return end
        if rf.runeMomentumTicker then
            rf.runeMomentumTicker:Cancel()
            rf.runeMomentumTicker = nil
        end
        rf.runes:SetRotation(0)
        local startTime = GetTime()
        local spinDur = 3
        rf.runeMomentumTicker = C_Timer.NewTicker(0.03, function()
            local elapsed = GetTime() - startTime
            local t = elapsed / spinDur
            if t >= 1 then
                rf.runeMomentumTicker:Cancel()
                rf.runeMomentumTicker = nil
                rf.runes:SetRotation(math.rad(90))
                return
            end
            -- Angle curve: fast start, slow end (like a wheel losing momentum). 90° total over 3s.
            local angleDeg = 90 * (2 * t - t * t)
            rf.runes:SetRotation(math.rad(angleDeg))
        end)
    end)
    -- When the proc animation (energy + runes + rotation) finishes: stop scale ticker, reset ring scale to 1, reset satellite positions, then start timers for text fade and satellite number fade. Lightning pulses are started separately when the *scale* ticker ends (see PlayCenterRingProc).
    local function onProcAnimEnd()
        if ringFrame.energySoftTicker then
            ringFrame.energySoftTicker:Cancel()
            ringFrame.energySoftTicker = nil
        end
        if ringFrame.runeMomentumTicker then
            ringFrame.runeMomentumTicker:Cancel()
            ringFrame.runeMomentumTicker = nil
        end
        if ringFrame.runes then ringFrame.runes:SetRotation(0) end
        if ringFrame.satelliteTicker then
            ringFrame.satelliteTicker:Cancel()
            ringFrame.satelliteTicker = nil
        end
        ringFrame:SetScale(1)
        if ShammyTime.ResetSatellitePositions then ShammyTime.ResetSatellitePositions() end
        local db = ShammyTime.GetDB and ShammyTime.GetDB() or {}
        local center = ringFrame:GetParent()
        if not center then return end
        -- Center "Windfury!" text: hold 1s then start slow fade out (unless always show numbers)
        if not db.wfAlwaysShowNumbers and center.textFrame and center.textFrame:IsShown() and center.textFrame.fadeOutAnim then
            center.textFrame.fadeOutAnim:Stop()
            center.textFrame:SetAlpha(1)
            if center.wfTextFadeTimer then center.wfTextFadeTimer:Cancel() end
            center.wfTextFadeTimer = C_Timer.NewTimer(WF_TEXT_HOLD_BEFORE_FADE, function()
                center.wfTextFadeTimer = nil
                if not center or not center.textFrame or not center.textFrame:IsShown() or not center.textFrame.fadeOutAnim then return end
                center.textFrame.fadeOutAnim:Stop()
                center.textFrame:SetAlpha(1)
                center.textFrame.fadeOutAnim:Play()
            end)
        end
        if db.wfAlwaysShowNumbers then return end
        -- Satellite numbers: wait 5s then start chain fade
        if center.wfFadeDelayTimer then
            center.wfFadeDelayTimer:Cancel()
            center.wfFadeDelayTimer = nil
        end
        center.wfFadeDelayTimer = C_Timer.NewTimer(WF_NUMBERS_HOLD_BEFORE_FADE, function()
            center.wfFadeDelayTimer = nil
            if not center or not center:IsShown() then return end
            if ShammyTime.StartSatelliteTextChainFade then ShammyTime.StartSatelliteTextChainFade() end
        end)
        center.wfProcAnimPlaying = false  -- animation done; fade logic can apply now
        if ShammyTime.OnWindfuryProcAnimEnd then ShammyTime.OnWindfuryProcAnimEnd() end
    end
    ag:SetScript("OnFinished", onProcAnimEnd)
    ag:SetScript("OnStop", onProcAnimEnd)

    -- Lightning pulses: after the main proc, the energy layer blinks a few times (brighten then dim). Implemented with timers that call SetAlpha directly so it runs independently of the proc animation group (which can be 6s or longer); using an AnimationGroup on the same texture would be blocked while the proc anim is still playing.
    local function randBetween(lo, hi)
        return lo + math.random() * (hi - lo)
    end
    local ENERGY_REST_ALPHA = 0.12
    -- Called after the ring scale ticker finishes (see PlayCenterRingProc). Runs WF_LIGHTNING_PULSE_COUNT blinks by setting rf.energy alpha with timers/tickers (no AnimationGroup).
    function ShammyTime.StartLightningPulses(rf)
        if not rf or not rf.energy then return end
        if rf.lightningPulseTimer then
            rf.lightningPulseTimer:Cancel()
            rf.lightningPulseTimer = nil
        end
        if rf.lightningPulseTicker then
            rf.lightningPulseTicker:Cancel()
            rf.lightningPulseTicker = nil
        end
        if rf.lightningPulseGroup then rf.lightningPulseGroup:Stop() end
        local pulseIndex = 0
        local runNextPulse  -- forward declare so timer callbacks can capture it
        local function runRampDown(ePeak, downDur, thenGap)
            local downSteps = math.max(1, math.floor(downDur / 0.02))
            local downStep = 0
            rf.lightningPulseTicker = C_Timer.NewTicker(downDur / downSteps, function()
                downStep = downStep + 1
                local t = downStep / downSteps
                rf.energy:SetAlpha(ePeak + (ENERGY_REST_ALPHA - ePeak) * t)
                if downStep >= downSteps then
                    rf.lightningPulseTicker:Cancel()
                    rf.lightningPulseTicker = nil
                    rf.energy:SetAlpha(ENERGY_REST_ALPHA)
                    if thenGap then
                        rf.lightningPulseTimer = C_Timer.NewTimer(thenGap, function()
                            rf.lightningPulseTimer = nil
                            runNextPulse()
                        end)
                    end
                end
            end)
        end
        local function runRampUp(ePeak)
            local upDur = randBetween(WF_LIGHTNING_UP_DUR_MIN, WF_LIGHTNING_UP_DUR_MAX)
            local downDur = randBetween(WF_LIGHTNING_DOWN_DUR_MIN, WF_LIGHTNING_DOWN_DUR_MAX)
            local upSteps = math.max(1, math.floor(upDur / 0.02))
            local upStep = 0
            rf.lightningPulseTicker = C_Timer.NewTicker(upDur / upSteps, function()
                upStep = upStep + 1
                local t = upStep / upSteps
                rf.energy:SetAlpha(ENERGY_REST_ALPHA + (ePeak - ENERGY_REST_ALPHA) * t)
                if upStep >= upSteps then
                    rf.lightningPulseTicker:Cancel()
                    rf.lightningPulseTicker = nil
                    rf.energy:SetAlpha(ePeak)
                    local gap = (pulseIndex < WF_LIGHTNING_PULSE_COUNT) and randBetween(WF_LIGHTNING_GAP_MIN, WF_LIGHTNING_GAP_MAX) or nil
                    runRampDown(ePeak, downDur, gap)
                end
            end)
        end
        runNextPulse = function()
            pulseIndex = pulseIndex + 1
            if pulseIndex > WF_LIGHTNING_PULSE_COUNT then return end
            local falloff = 1 - (pulseIndex - 1) * 0.3
            if falloff < 0.35 then falloff = 0.35 end
            local ePeak = randBetween(WF_LIGHTNING_ENERGY_PEAK_MIN, WF_LIGHTNING_ENERGY_PEAK_MAX) * falloff
            runRampUp(ePeak)
        end
        runNextPulse()
    end

    -- Called on proc: "Windfury!" and "TOTAL:" (and "CRITICAL" if shown) instantly switch to bright flash colors, then tick back to normal rest colors over 0.4s. No scaling or movement.
    function f:FlashText()
        -- Instant flash to bright color
        self.title:SetTextColor(unpack(self.titleFlashColor))
        self.total:SetTextColor(unpack(self.totalFlashColor))
        if self.criticalLine:IsShown() then
            self.criticalLine:SetTextColor(unpack(self.criticalLineFlashColor))
        end
        -- Fade back to rest color over 0.4s
        local steps = 20
        local interval = 0.4 / steps
        local step = 0
        if self.textFlashTicker then self.textFlashTicker:Cancel() end
        self.textFlashTicker = C_Timer.NewTicker(interval, function()
            step = step + 1
            local t = step / steps  -- 0 to 1
            -- Lerp from flash to rest
            local tr = self.titleFlashColor[1] + (self.titleRestColor[1] - self.titleFlashColor[1]) * t
            local tg = self.titleFlashColor[2] + (self.titleRestColor[2] - self.titleFlashColor[2]) * t
            local tb = self.titleFlashColor[3] + (self.titleRestColor[3] - self.titleFlashColor[3]) * t
            self.title:SetTextColor(tr, tg, tb)
            local vr = self.totalFlashColor[1] + (self.totalRestColor[1] - self.totalFlashColor[1]) * t
            local vg = self.totalFlashColor[2] + (self.totalRestColor[2] - self.totalFlashColor[2]) * t
            local vb = self.totalFlashColor[3] + (self.totalRestColor[3] - self.totalFlashColor[3]) * t
            self.total:SetTextColor(vr, vg, vb)
            if self.criticalLine:IsShown() then
                local cr = self.criticalLineFlashColor[1] + (self.criticalLineRestColor[1] - self.criticalLineFlashColor[1]) * t
                local cg = self.criticalLineFlashColor[2] + (self.criticalLineRestColor[2] - self.criticalLineFlashColor[2]) * t
                local cb = self.criticalLineFlashColor[3] + (self.criticalLineRestColor[3] - self.criticalLineFlashColor[3]) * t
                self.criticalLine:SetTextColor(cr, cg, cb)
            end
            if step >= steps then
                self.textFlashTicker:Cancel()
                self.textFlashTicker = nil
                self.title:SetTextColor(unpack(self.titleRestColor))
                self.total:SetTextColor(unpack(self.totalRestColor))
                if self.criticalLine:IsShown() then
                    self.criticalLine:SetTextColor(unpack(self.criticalLineRestColor))
                end
            end
        end)
    end
    centerFrame = f
    -- After addon load: if the radial was visible before reload (wfRadialShown), show the frame and text, restore "TOTAL" from last proc, show totem bar, update satellites, then (if not always-show-numbers) start the same fade timers as after a proc.
    local db = ShammyTime.GetDB and ShammyTime.GetDB()
    if db and db.wfRadialShown then
        f:Show()
        f.textFrame:Show()
        f.criticalLine:Hide()
        f.title:SetText("Windfury!")
        f.total:SetPoint("CENTER", 0, GetCenterTextOffsets().totalY)
        f.total:SetText("TOTAL: " .. FormatNum(ShammyTime and ShammyTime.lastProcTotal or 0))
        local bar = ShammyTime.EnsureWindfuryTotemBarFrame and ShammyTime.EnsureWindfuryTotemBarFrame()
        if bar then bar:Show() end
        -- Update satellite values (empty/0 will hide text per satellite), then after hold start fade
        C_Timer.After(0, function()
            local stats = (ShammyTime_Windfury_GetStats and ShammyTime_Windfury_GetStats()) or nil
            if ShammyTime.UpdateSatelliteValues then ShammyTime.UpdateSatelliteValues(stats) end
            local db2 = ShammyTime.GetDB and ShammyTime.GetDB()
            if not db2 or db2.wfAlwaysShowNumbers then return end
            C_Timer.After(WF_NUMBERS_HOLD_BEFORE_FADE, function()
                if not f or not f:IsShown() then return end
                if f.textFrame and f.textFrame:IsShown() and f.textFrame.fadeOutAnim then
                    f.textFrame.fadeOutAnim:Stop()
                    f.textFrame:SetAlpha(1)
                    f.textFrame.fadeOutAnim:Play()
                end
                if ShammyTime.StartSatelliteTextChainFade then ShammyTime.StartSatelliteTextChainFade() end
            end)
        end)
    end
    return f
end

-- Ensures the center ring frame is created; used by other modules (e.g. satellites) that need to parent or anchor to it.
function ShammyTime.EnsureCenterRingExists()
    return CreateCenterRingFrame()
end

-- Apply font sizes from DB to center ring text (called when user changes /st font circle).
function ShammyTime.ApplyCenterRingFontSizes()
    local f = _G.ShammyTimeCenterRing
    if not f or not f.criticalLine then return end
    local db = ShammyTime.GetDB and ShammyTime.GetDB() or {}
    local fontTitle = (db.fontCircleTitle and db.fontCircleTitle >= 6 and db.fontCircleTitle <= 28) and db.fontCircleTitle or 20
    local fontTotal = (db.fontCircleTotal and db.fontCircleTotal >= 6 and db.fontCircleTotal <= 28) and db.fontCircleTotal or 14
    local fontCritical = (db.fontCircleCritical and db.fontCircleCritical >= 6 and db.fontCircleCritical <= 28) and db.fontCircleCritical or 20
    f.criticalLine:SetFont("Fonts\\FRIZQT__.TTF", fontCritical, "OUTLINE")
    f.title:SetFont("Fonts\\FRIZQT__.TTF", fontTitle, "OUTLINE")
    f.total:SetFont("Fonts\\FRIZQT__.TTF", fontTotal, "OUTLINE")
end

-- Resize center circle and its layers from DB (call when user changes /st circle size N).
function ShammyTime.ApplyCenterRingSize()
    local f = centerFrame or _G.ShammyTimeCenterRing
    if not f or not f.ringFrame then return end
    local s = GetCenterSize()
    local scale = s / 200
    f:SetSize(s, s)
    f.ringFrame:SetSize(s, s)
    if f.textFrame then f.textFrame:SetSize(s, s) end
    if f.ringFrame.shadow then
        f.ringFrame.shadow:SetSize(222 * scale, 222 * scale)
        f.ringFrame.shadow:SetPoint("CENTER", 0, -7 * scale)
    end
    if f.ringFrame.runes then
        f.ringFrame.runes:SetSize(144 * scale, 144 * scale)
        f.ringFrame.runes:SetPoint("CENTER", -1 * scale, 7 * scale)
    end
    if ShammyTime.ApplySatelliteRadius then ShammyTime.ApplySatelliteRadius() end
    if ShammyTime.ApplyWindfuryRadialWrapperSize then ShammyTime.ApplyWindfuryRadialWrapperSize() end
end

-- Reposition center text from DB (call when user changes /st circle text ...).
function ShammyTime.ApplyCenterRingTextPosition()
    local f = centerFrame or _G.ShammyTimeCenterRing
    if not f or not f.criticalLine then return end
    local off = GetCenterTextOffsets()
    f.criticalLine:SetPoint("CENTER", 0, off.criticalY)
    f.title:SetPoint("CENTER", 0, off.titleY)
    f.total:SetPoint("CENTER", 0, off.totalY)
end

-- Applies saved position to the totem bar frame (per character).
local function ApplyTotemBarPosition(barFrame)
    local pos = ShammyTime.GetRadialPositionDB and ShammyTime.GetRadialPositionDB()
    if not pos or not pos.totemBar then return end
    local t = pos.totemBar
    local relTo = (t.relativeTo and _G[t.relativeTo]) or UIParent
    if relTo then
        barFrame:ClearAllPoints()
        barFrame:SetPoint(t.point or "CENTER", relTo, t.relativePoint or "CENTER", t.x or 0, t.y or 0)
    end
end

-- Global wrapper for repositioning totem bar after scale change
function ShammyTime.ApplyTotemBarPosition()
    local f = _G.ShammyTimeWindfuryTotemBarFrame
    if f then ApplyTotemBarPosition(f) end
end

-- Saves the totem bar position when the user stops dragging (per character).
local function SaveTotemBarPosition(barFrame)
    if not ShammyTime.GetRadialPositionDB then return end
    local pos = ShammyTime.GetRadialPositionDB()
    local point, relTo, relativePoint, x, y = barFrame:GetPoint(1)
    pos.totemBar = {
        point = point,
        relativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent",
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

-- Creates the Windfury totem bar frame once (the bar that shows WF totem art). Separate from the center ring; has its own position and scale (/st totem scale).
local function CreateWindfuryTotemBarFrame()
    if totemBarFrame then return totemBarFrame end
    local barW = 286
    local barH = math.floor(barW * 277 / 996 + 0.5)
    local f = CreateFrame("Frame", "ShammyTimeWindfuryTotemBarFrame", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetSize(barW, barH)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    ApplyTotemBarPosition(f)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    local dbLocked = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB().locked
    f:EnableMouse(not dbLocked)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB().locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveTotemBarPosition(self)
    end)
    f.totemBar = f:CreateTexture(nil, "OVERLAY")
    f.totemBar:SetTexture(TEX.TOTEM_BAR)
    f.totemBar:SetAllPoints(f)
    f.totemBar:SetAlpha(1)
    f:SetScale(GetTotemBarScale())
    f:Hide()
    -- Restore visibility after reload if radial was shown
    local db = ShammyTime.GetDB and ShammyTime.GetDB()
    if db and db.wfRadialShown then
        f:Show()
    end
    totemBarFrame = f
    return f
end

function ShammyTime.EnsureWindfuryTotemBarFrame()
    return CreateWindfuryTotemBarFrame()
end

-- Returns the ring subframe (the one that scales on proc and holds shadow/bg/energy/border/runes). Satellites parent to this so they move with the ring.
function ShammyTime.GetCenterRingFrame()
    local f = CreateCenterRingFrame()
    return f and f.ringFrame or nil
end

-- Called when a Windfury proc is detected (from combat log in ShammyTime_Windfury.lua). Shows the center ring, totem bar, and "Windfury!" text; plays the proc animation (energy flash, rune flash+spin+fade, ring scale pop) and schedules lightning pulses and text/satellite fades.
-- forceShow: if true, show and play even when wfRadialEnabled is off (e.g. /st test).
function ShammyTime.PlayCenterRingProc(procTotal, forceShow)
    local db = ShammyTime.GetDB and ShammyTime.GetDB() or {}
    if not forceShow and not db.wfRadialEnabled then return end
    -- Mark proc as recent so UpdateAllElementsFadeState (fade when not procced) gives the circle alpha 1 when it runs below.
    if ShammyTime.NotifyWindfuryProcStarted then ShammyTime.NotifyWindfuryProcStarted() end
    local f = CreateCenterRingFrame()
    -- Keep center at saved position (stops demo/proc from shifting the bubbles)
    if ShammyTime.ApplyCenterRingPosition then ShammyTime.ApplyCenterRingPosition() end
    f.wfProcAnimPlaying = true  -- block fade-out until animation finishes (circle stays visible in/out of combat)
    f:Show()
    -- Cancel any pending text/satellite fade timers so this proc gets a full hold period
    if f.wfFadeDelayTimer then
        f.wfFadeDelayTimer:Cancel()
        f.wfFadeDelayTimer = nil
    end
    if f.wfTextFadeTimer then
        f.wfTextFadeTimer:Cancel()
        f.wfTextFadeTimer = nil
    end
    if f.textFrame.fadeOutAnim then f.textFrame.fadeOutAnim:Stop() end
    f.textFrame:SetAlpha(1)
    f.textFrame:Show()
    local barFrame = ShammyTime.EnsureWindfuryTotemBarFrame and ShammyTime.EnsureWindfuryTotemBarFrame()
    if barFrame then barFrame:Show() end
    if db.wfRadialShown == nil then db.wfRadialShown = false end
    db.wfRadialShown = true
    if ShammyTime.UpdateAllElementsFadeState then ShammyTime.UpdateAllElementsFadeState() end
    f.total:SetText("TOTAL: " .. FormatNum(procTotal or 0))
    local totY = GetCenterTextOffsets().totalY
    if ShammyTime.lastProcHadCrit then
        f.criticalLine:SetText("CRITICAL")
        f.criticalLine:Show()
        f.title:SetText("Windfury!")
        f.total:SetPoint("CENTER", 0, totY - 4)  -- lower so three lines fit
        ShammyTime.lastProcHadCritForPopup = true  -- so delayed popup can show CRITICAL! too
        ShammyTime.lastProcHadCrit = nil
    else
        f.criticalLine:Hide()
        f.title:SetText("Windfury!")
        f.total:SetPoint("CENTER", 0, totY)
    end
    -- Center frame stays at scale 1; radial scale is on the wrapper only (set in windfuryBubbles:ApplyConfig).
    local rf = f.ringFrame
    -- Cancel any lightning and energy-soften timers/tickers from a previous proc so we start clean
    if rf.energySoftTicker then
        rf.energySoftTicker:Cancel()
        rf.energySoftTicker = nil
    end
    if rf.lightningStartTimer then
        rf.lightningStartTimer:Cancel()
        rf.lightningStartTimer = nil
    end
    if rf.lightningPulseTimer then
        rf.lightningPulseTimer:Cancel()
        rf.lightningPulseTimer = nil
    end
    if rf.lightningPulseTicker then
        rf.lightningPulseTicker:Cancel()
        rf.lightningPulseTicker = nil
    end
    if rf.lightningPulseGroup then rf.lightningPulseGroup:Stop() end
    rf.energy:SetAlpha(0.12)
    rf.runes:SetAlpha(0)
    rf:SetScale(1)
    rf.procAnim:Stop()
    rf.procAnim:Play()
    -- Ring scale + satellite positions: ticker does a quick expand (pop), short hold, then slow retract. When the ticker finishes, we start the delayed lightning pulses.
    if rf.satelliteTicker then
        rf.satelliteTicker:Cancel()
        rf.satelliteTicker = nil
    end
    local pop = 1.18           -- peak scale (e.g. 1.18 = 18% bigger)
    local expandDur = 0.03    -- time to reach pop
    local holdDur = 0.45      -- time held at pop
    local retractDur = 0.55   -- time to return to scale 1
    local total = expandDur + holdDur + retractDur
    local start = GetTime()
    local interval = 0.02
    rf.satelliteTicker = C_Timer.NewTicker(interval, function()
        local t = GetTime() - start
        local scale
        if t <= expandDur then
            scale = 1 + (pop - 1) * (t / expandDur)
        elseif t <= expandDur + holdDur then
            scale = pop
        elseif t <= total then
            local u = (t - expandDur - holdDur) / retractDur
            scale = pop + (1 - pop) * u
        else
            scale = 1
        end
        rf:SetScale(scale)
        if ShammyTime.OnRingProcScaleUpdate then ShammyTime.OnRingProcScaleUpdate(scale) end
        if t >= total then
            if rf.satelliteTicker then
                rf.satelliteTicker:Cancel()
                rf.satelliteTicker = nil
            end
            rf:SetScale(1)
            if ShammyTime.ResetSatellitePositions then ShammyTime.ResetSatellitePositions() end
            -- After a short delay, start the energy-layer lightning blinks (BOOM ... pause ... blink blink blink).
            if rf.lightningStartTimer then rf.lightningStartTimer:Cancel() end
            rf.lightningStartTimer = C_Timer.NewTimer(WF_LIGHTNING_DELAY_AFTER_BOOM, function()
                rf.lightningStartTimer = nil
                if ShammyTime.StartLightningPulses then ShammyTime.StartLightningPulses(rf) end
            end)
        end
    end)
    f:FlashText()
end

-- True while the proc animation (energy + runes + scale pop) is playing; used so fade logic does not hide the circle until the animation finishes.
function ShammyTime.IsWindfuryProcAnimationPlaying()
    local c = _G.ShammyTimeCenterRing
    return c and c.wfProcAnimPlaying
end

-- Update just the "TOTAL: xxx" text without replaying the proc animation. Used when damage is calculated after the instant show.
function ShammyTime.UpdateCenterRingTotal(procTotal)
    local f = _G.ShammyTimeCenterRing
    if not f or not f.total then return end
    f.total:SetText("TOTAL: " .. FormatNum(procTotal or 0))
    -- Also update lastProcTotal so satellite values can use it
    if procTotal then
        ShammyTime.lastProcTotal = procTotal
    end
    -- Update satellite values with new stats
    if ShammyTime.UpdateSatelliteValues and ShammyTime_Windfury_GetStats then
        ShammyTime.UpdateSatelliteValues(ShammyTime_Windfury_GetStats())
    end
end

-- Circle/totem bar toggle and scale are handled via /st circle in ShammyTime.lua.
