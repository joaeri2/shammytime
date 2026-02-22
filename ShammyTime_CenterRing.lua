-- ShammyTime_CenterRing.lua
-- Center ring: layered textures, proc animation. Toggle/scale via /st circle.
-- No satellites, no combat log. Purely asset + animation integration test.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

local M = ShammyTime_Media
if not M then return end

local TEX = M.TEX
local centerFrame      -- main center ring frame (created once; child of radialWrapper)
local radialWrapper    -- single scalable container for center + satellites (created once)
local totemBarFrame    -- separate draggable totem bar frame (created once)

-- ========== Timing constants ==========
-- Hold time used only when restoring a previously shown radial after reload.
local WF_NUMBERS_HOLD_BEFORE_FADE = 2

-- ========== Lightning pulse constants (energy layer only) ==========
-- Delay in seconds after the main "BOOM" proc animation before the first lightning blink.
local WF_LIGHTNING_DELAY_AFTER_BOOM = 0.42
-- Number of lightning blinks (energy layer brightens then dims).
local WF_LIGHTNING_PULSE_COUNT = 4
-- Random range for how bright the energy gets on each strike.
local WF_LIGHTNING_ENERGY_PEAK_MIN, WF_LIGHTNING_ENERGY_PEAK_MAX = 0.50, 0.95
-- Opening crack (first instant strike right when lightning starts).
local WF_LIGHTNING_OPENING_PEAK_MIN, WF_LIGHTNING_OPENING_PEAK_MAX = 0.90, 1.00
local WF_LIGHTNING_OPENING_SECONDARY_CHANCE = 0.55
local WF_LIGHTNING_OPENING_SECONDARY_MIN, WF_LIGHTNING_OPENING_SECONDARY_MAX = 0.62, 0.92
local WF_LIGHTNING_OPENING_RECOVER_MIN, WF_LIGHTNING_OPENING_RECOVER_MAX = 0.03, 0.07
-- Random duration for each blink: ramp-up and ramp-down time.
local WF_LIGHTNING_UP_DUR_MIN, WF_LIGHTNING_UP_DUR_MAX = 0.016, 0.042
local WF_LIGHTNING_DOWN_DUR_MIN, WF_LIGHTNING_DOWN_DUR_MAX = 0.08, 0.15
-- Random gap in seconds between one blink finishing and the next starting.
local WF_LIGHTNING_GAP_MIN, WF_LIGHTNING_GAP_MAX = 0.025, 0.07
-- Sometimes cluster pulses tightly for chaotic bursts.
local WF_LIGHTNING_CLUSTER_CHANCE = 0.25
local WF_LIGHTNING_CLUSTER_GAP_MIN, WF_LIGHTNING_CLUSTER_GAP_MAX = 0.008, 0.022
-- Extra per-tick instability so each strike looks jagged, not like a smooth fade.
local WF_LIGHTNING_UP_JITTER = 0.10
local WF_LIGHTNING_DOWN_JITTER_MIN, WF_LIGHTNING_DOWN_JITTER_MAX = 0.10, 0.20
local WF_LIGHTNING_STROBE_CHANCE = 0.28
local WF_LIGHTNING_STROBE_MIN, WF_LIGHTNING_STROBE_MAX = 0.05, 0.20
local WF_LIGHTNING_FALLOFF_PER_PULSE = 0.13
local WF_LIGHTNING_FALLOFF_MIN = 0.55
local WF_LIGHTNING_PULSE_VARIATION_MIN, WF_LIGHTNING_PULSE_VARIATION_MAX = -1, 1
local WF_LIGHTNING_STEP_DUR_MIN, WF_LIGHTNING_STEP_DUR_MAX = 0.012, 0.022

-- Center text palette aligned with satellite bubble styling.
-- Hex refs: title(label)=#E6C06A, total(value)=#F2E7C9.
local CENTER_TITLE_REST_COLOR = {0.902, 0.753, 0.416}
local CENTER_TITLE_FLASH_COLOR = {0.957, 0.847, 0.573}
local CENTER_TOTAL_REST_COLOR = {0.949, 0.906, 0.788}
local CENTER_TOTAL_FLASH_COLOR = {1.000, 0.957, 0.851}
local CENTER_CRIT_REST_COLOR = {1.00, 0.66, 0.46}
local CENTER_CRIT_FLASH_COLOR = {1.00, 0.84, 0.66}
local CENTER_TEXT_SHADOW_COLOR = {0, 0, 0, 0.55}
local CENTER_TEXT_SHADOW_X, CENTER_TEXT_SHADOW_Y = 1, -1

-- Small center-ring impact shake during proc pop (kept subtle for a heavy feel, not jittery).
local WF_IMPACT_SHAKE_CENTER_MAX_PX = 1.4
local WF_IMPACT_SHAKE_CENTER_FREQ_X = 44
local WF_IMPACT_SHAKE_CENTER_FREQ_Y = 36
local WF_IMPACT_SHAKE_CENTER_DECAY = 3.8
local WF_IMPACT_SHAKE_CENTER_AMP_SCALE_MIN, WF_IMPACT_SHAKE_CENTER_AMP_SCALE_MAX = 0.82, 1.20
local WF_IMPACT_SHAKE_CENTER_FREQ_SCALE_MIN, WF_IMPACT_SHAKE_CENTER_FREQ_SCALE_MAX = 0.85, 1.18
local WF_IMPACT_SHAKE_CENTER_DECAY_SCALE_MIN, WF_IMPACT_SHAKE_CENTER_DECAY_SCALE_MAX = 0.82, 1.20
local WF_IMPACT_SHAKE_CENTER_Y_RATIO_MIN, WF_IMPACT_SHAKE_CENTER_Y_RATIO_MAX = 0.72, 0.95
local WF_IMPACT_SHAKE_CENTER_HARMONIC_CHANCE = 0.40

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
    radialWrapper:SetFrameStrata("LOW")
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
    f:SetFrameStrata("LOW")
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
        if ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB().locked then return end
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
        if ShammyTime.OnRadialHoverEnter then ShammyTime.OnRadialHoverEnter() end
    end)
    f:SetScript("OnLeave", function()
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

    -- Ring subframe: holds visual layers (shadow, bg, energy). This frame scales during proc (pop effect); satellites are parented here so they move with the ring. Totem bar is a sibling, so it does not scale.
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

    -- Text frame: holds "Windfury!", "TOTAL: xxx", and optional "CRITICAL". Child of main frame so it doesn't get scaled by the ring's proc pop; it stays crisp. Still scales with /st circle scale (whole frame scale).
    local textFrame = CreateFrame("Frame", "ShammyTimeCenterRingText", f)
    textFrame:SetFrameStrata("LOW")
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
    f.criticalLine:SetTextColor(unpack(CENTER_CRIT_REST_COLOR))
    f.criticalLine:SetFont("Fonts\\FRIZQT__.TTF", fontCritical, "OUTLINE")
    f.criticalLine:SetShadowColor(unpack(CENTER_TEXT_SHADOW_COLOR))
    f.criticalLine:SetShadowOffset(CENTER_TEXT_SHADOW_X, CENTER_TEXT_SHADOW_Y)
    f.criticalLine:Hide()
    f.criticalLineRestColor = {unpack(CENTER_CRIT_REST_COLOR)}
    f.criticalLineFlashColor = {unpack(CENTER_CRIT_FLASH_COLOR)}

    f.title = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("CENTER", 0, textOff.titleY)
    f.title:SetText("Windfury!")
    f.title:SetTextColor(unpack(CENTER_TITLE_REST_COLOR))
    f.title:SetFont("Fonts\\FRIZQT__.TTF", fontTitle, "OUTLINE")
    f.title:SetShadowColor(unpack(CENTER_TEXT_SHADOW_COLOR))
    f.title:SetShadowOffset(CENTER_TEXT_SHADOW_X, CENTER_TEXT_SHADOW_Y)
    f.titleRestColor = {unpack(CENTER_TITLE_REST_COLOR)}
    f.titleFlashColor = {unpack(CENTER_TITLE_FLASH_COLOR)}

    f.total = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.total:SetPoint("CENTER", 0, textOff.totalY)  -- Y is adjusted in PlayCenterRingProc when "CRITICAL" is shown so three lines fit
    f.total:SetText("TOTAL: 3245")
    f.total:SetTextColor(unpack(CENTER_TOTAL_REST_COLOR))
    f.total:SetFont("Fonts\\FRIZQT__.TTF", fontTotal, "OUTLINE")
    f.total:SetShadowColor(unpack(CENTER_TEXT_SHADOW_COLOR))
    f.total:SetShadowOffset(CENTER_TEXT_SHADOW_X, CENTER_TEXT_SHADOW_Y)
    f.totalRestColor = {unpack(CENTER_TOTAL_REST_COLOR)}
    f.totalFlashColor = {unpack(CENTER_TOTAL_FLASH_COLOR)}

    -- Proc pulse: the ring's *scale* (pop/breath) is driven by a separate ticker in PlayCenterRingProc, not by this animation group. This group only drives energy alpha (via OnPlay ticker).

    local function BuildProcAnim(rf)
        local g = rf:CreateAnimationGroup()
        -- Energy flash+soften is done in OnPlay with a ticker so the animation group does not "own" rf.energy for 6s (which would block lightning pulses from showing).
        return g
    end

    ringFrame.procAnim = BuildProcAnim(ringFrame)
    local ag = ringFrame.procAnim
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
    end)
    -- When the proc animation (energy) finishes: stop scale ticker, reset ring scale to 1, reset satellite positions, then start timers for text fade and satellite number fade. Lightning pulses are started separately when the *scale* ticker ends (see PlayCenterRingProc).
    local function onProcAnimEnd()
        -- Skip cleanup when Stop() was called to restart the animation for a new proc (avoids race: spurious fade timer + wfProcAnimPlaying briefly false)
        if ringFrame._suppressAnimEnd then return end
        if ringFrame._procAnimEnded then return end
        ringFrame._procAnimEnded = true
        if ringFrame.energySoftTicker then
            ringFrame.energySoftTicker:Cancel()
            ringFrame.energySoftTicker = nil
        end
        if ringFrame.satelliteTicker then
            ringFrame.satelliteTicker:Cancel()
            ringFrame.satelliteTicker = nil
        end
        ringFrame:SetScale(1)
        local db = ShammyTime.GetDB and ShammyTime.GetDB() or {}
        local center = ringFrame:GetParent()
        if not center then return end
        ringFrame:ClearAllPoints()
        ringFrame:SetPoint("CENTER", center, "CENTER", 0, 0)
        if ShammyTime.ResetSatellitePositions then ShammyTime.ResetSatellitePositions() end
        if db.wfAlwaysShowNumbers then
            center.wfProcAnimPlaying = false  -- animation done; fade logic can apply now
            if ShammyTime.OnWindfuryProcAnimEnd then ShammyTime.OnWindfuryProcAnimEnd() end
            return
        end
        center.wfProcAnimPlaying = false  -- animation done; fade logic can apply now
        if ShammyTime.OnWindfuryProcAnimEnd then ShammyTime.OnWindfuryProcAnimEnd() end
    end
    ringFrame._onProcAnimEnd = onProcAnimEnd
    ag:SetScript("OnFinished", onProcAnimEnd)
    ag:SetScript("OnStop", onProcAnimEnd)

    -- Lightning pulses: after the main proc, the energy layer blinks a few times (brighten then dim). Implemented with timers that call SetAlpha directly so it runs independently of the proc animation group (which can be 6s or longer); using an AnimationGroup on the same texture would be blocked while the proc anim is still playing.
    local function randBetween(lo, hi)
        return lo + math.random() * (hi - lo)
    end
    local ENERGY_REST_ALPHA = 0.12
    local function clampAlpha(a)
        if a < ENERGY_REST_ALPHA then return ENERGY_REST_ALPHA end
        if a > 1 then return 1 end
        return a
    end
    -- Called after the ring scale ticker finishes (see PlayCenterRingProc). Runs an opening crack plus a randomized number of follow-up blinks by setting rf.energy alpha with timers/tickers (no AnimationGroup).
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
        local pulseBudget = WF_LIGHTNING_PULSE_COUNT + math.random(WF_LIGHTNING_PULSE_VARIATION_MIN, WF_LIGHTNING_PULSE_VARIATION_MAX)
        if pulseBudget < 3 then pulseBudget = 3 end
        local falloffStep = randBetween(WF_LIGHTNING_FALLOFF_PER_PULSE * 0.75, WF_LIGHTNING_FALLOFF_PER_PULSE * 1.25)
        local runNextPulse  -- forward declare so timer callbacks can capture it
        local function scheduleNextPulse(delay)
            if not delay or delay <= 0 then
                return false
            end
            rf.lightningPulseTimer = C_Timer.NewTimer(delay, function()
                rf.lightningPulseTimer = nil
                runNextPulse()
            end)
            return true
        end
        local function runRampDown(ePeak, downDur, thenGap)
            local downStepDur = randBetween(WF_LIGHTNING_STEP_DUR_MIN, WF_LIGHTNING_STEP_DUR_MAX)
            local downSteps = math.max(1, math.floor(downDur / downStepDur))
            local downStep = 0
            rf.lightningPulseTicker = C_Timer.NewTicker(downDur / downSteps, function()
                downStep = downStep + 1
                local t = downStep / downSteps
                local base = ePeak + (ENERGY_REST_ALPHA - ePeak) * t
                local jitterAmp = randBetween(WF_LIGHTNING_DOWN_JITTER_MIN, WF_LIGHTNING_DOWN_JITTER_MAX) * (1 - t)
                local jitter = (math.random() * 2 - 1) * jitterAmp
                if math.random() < WF_LIGHTNING_STROBE_CHANCE then
                    jitter = jitter + randBetween(WF_LIGHTNING_STROBE_MIN, WF_LIGHTNING_STROBE_MAX) * (1 - t)
                end
                rf.energy:SetAlpha(clampAlpha(base + jitter))
                if downStep >= downSteps then
                    rf.lightningPulseTicker:Cancel()
                    rf.lightningPulseTicker = nil
                    rf.energy:SetAlpha(ENERGY_REST_ALPHA)
                    if thenGap then
                        scheduleNextPulse(thenGap)
                    end
                end
            end)
        end
        local function runRampUp(ePeak)
            local upDur = randBetween(WF_LIGHTNING_UP_DUR_MIN, WF_LIGHTNING_UP_DUR_MAX)
            local downDur = randBetween(WF_LIGHTNING_DOWN_DUR_MIN, WF_LIGHTNING_DOWN_DUR_MAX)
            local upStepDur = randBetween(WF_LIGHTNING_STEP_DUR_MIN, WF_LIGHTNING_STEP_DUR_MAX)
            local upSteps = math.max(1, math.floor(upDur / upStepDur))
            local upStep = 0
            rf.lightningPulseTicker = C_Timer.NewTicker(upDur / upSteps, function()
                upStep = upStep + 1
                local t = upStep / upSteps
                local base = ENERGY_REST_ALPHA + (ePeak - ENERGY_REST_ALPHA) * t
                local jitter = (math.random() * 2 - 1) * (WF_LIGHTNING_UP_JITTER * t)
                if math.random() < (WF_LIGHTNING_STROBE_CHANCE * 0.55) then
                    jitter = jitter + randBetween(0.03, WF_LIGHTNING_STROBE_MAX * 0.6) * t
                end
                rf.energy:SetAlpha(clampAlpha(base + jitter))
                if upStep >= upSteps then
                    rf.lightningPulseTicker:Cancel()
                    rf.lightningPulseTicker = nil
                    local strikePeak = clampAlpha(ePeak + randBetween(0.02, 0.09))
                    rf.energy:SetAlpha(strikePeak)
                    local gap = nil
                    if pulseIndex < pulseBudget then
                        if math.random() < WF_LIGHTNING_CLUSTER_CHANCE then
                            gap = randBetween(WF_LIGHTNING_CLUSTER_GAP_MIN, WF_LIGHTNING_CLUSTER_GAP_MAX)
                        else
                            gap = randBetween(WF_LIGHTNING_GAP_MIN, WF_LIGHTNING_GAP_MAX)
                        end
                    end
                    runRampDown(strikePeak, downDur, gap)
                end
            end)
        end
        runNextPulse = function()
            pulseIndex = pulseIndex + 1
            if pulseIndex > pulseBudget then return end
            local falloff = 1 - (pulseIndex - 1) * falloffStep
            if falloff < WF_LIGHTNING_FALLOFF_MIN then falloff = WF_LIGHTNING_FALLOFF_MIN end
            local ePeak = randBetween(WF_LIGHTNING_ENERGY_PEAK_MIN, WF_LIGHTNING_ENERGY_PEAK_MAX) * falloff
            if math.random() < 0.35 then
                ePeak = math.min(1, ePeak + randBetween(0.04, 0.12))
            end
            runRampUp(ePeak)
        end
        -- Opening crack: immediate strike when lightning starts, with optional secondary snap before the pulse train.
        rf.energy:SetAlpha(clampAlpha(randBetween(WF_LIGHTNING_OPENING_PEAK_MIN, WF_LIGHTNING_OPENING_PEAK_MAX)))
        local openerDelay = randBetween(0.018, 0.045)
        rf.lightningPulseTimer = C_Timer.NewTimer(openerDelay, function()
            rf.lightningPulseTimer = nil
            if math.random() < WF_LIGHTNING_OPENING_SECONDARY_CHANCE then
                rf.energy:SetAlpha(clampAlpha(randBetween(WF_LIGHTNING_OPENING_SECONDARY_MIN, WF_LIGHTNING_OPENING_SECONDARY_MAX)))
            else
                rf.energy:SetAlpha(clampAlpha(randBetween(0.30, 0.55)))
            end
            local settle = randBetween(WF_LIGHTNING_OPENING_RECOVER_MIN, WF_LIGHTNING_OPENING_RECOVER_MAX)
            rf.lightningPulseTimer = C_Timer.NewTimer(settle, function()
                rf.lightningPulseTimer = nil
                rf.energy:SetAlpha(ENERGY_REST_ALPHA)
                runNextPulse()
            end)
        end)
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
            if ShammyTime.RequestRadialTextFadeAfter then
                ShammyTime.RequestRadialTextFadeAfter(WF_NUMBERS_HOLD_BEFORE_FADE)
            end
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
    -- Totem bar art is 512×512 but only the middle band has art.
    -- Crop top/bottom via SetTexCoord; frame height = barW * visible fraction.
    local barW = 286
    local CROP_TOP = 0.33     -- skip top 30% of texture (empty)
    local CROP_BOTTOM = 0.65  -- skip bottom 30% of texture (empty)
    local barH = math.floor(barW * (CROP_BOTTOM - CROP_TOP) + 0.5)
    local f = CreateFrame("Frame", "ShammyTimeWindfuryTotemBarFrame", UIParent)
    f:SetFrameStrata("LOW")
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
    -- Tooltip: show last fight + cumulative session WF damage breakdown on hover
    local function AddPlayerLines(api, playerList, total, hits, totalR, totalG, totalB)
        if playerList and #playerList > 0 then
            for _, pp in ipairs(playerList) do
                local r, g, b = 1, 0.82, 0
                if api.GetClassColor then
                    r, g, b = api.GetClassColor(pp.guid)
                end
                local name = api.ShortName and api.ShortName(pp.name) or pp.name
                local dmgStr = "+" .. api.FormatNumber(pp.damage)
                local avg = pp.hits > 0 and math.floor(pp.damage / pp.hits) or 0
                local detailStr = pp.hits .. (pp.hits == 1 and " hit" or " hits") .. ", avg " .. api.FormatNumber(avg)
                GameTooltip:AddDoubleLine(
                    name,
                    dmgStr .. "  |cffaaaaaa(" .. detailStr .. ")|r",
                    r, g, b,
                    1, 1, 1
                )
            end
        end
        -- Total line
        local totalAvg = hits > 0 and math.floor(total / hits) or 0
        local totalDetail = hits .. " hits, avg " .. api.FormatNumber(totalAvg)
        GameTooltip:AddDoubleLine(
            "Total",
            "+" .. api.FormatNumber(total) .. "  |cffaaaaaa(" .. totalDetail .. ")|r",
            totalR, totalG, totalB,
            totalR, totalG, totalB
        )
    end
    f:SetScript("OnEnter", function(self)
        local api = _G.ShammyTime_WFImpact
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Totem Bar", 0.2, 0.8, 1)
        if api and api.GetSessionStats then
            local sessionTotal, sessionHits, sessionStart, fights = api.GetSessionStats()
            local lastTotal, lastHits, lastPerPlayer = 0, 0, {}
            if api.GetLastFight then
                lastTotal, lastHits, lastPerPlayer = api.GetLastFight()
            end
            if sessionTotal and sessionTotal > 0 then
                -- === Last Fight ===
                if lastTotal and lastTotal > 0 and lastPerPlayer and #lastPerPlayer > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Last Fight", 1, 0.82, 0)
                    AddPlayerLines(api, lastPerPlayer, lastTotal, lastHits, 0.7, 0.7, 0.7)
                end
                -- === Session Total ===
                local duration = ""
                if sessionStart then
                    local secs = math.floor(GetTime() - sessionStart)
                    if secs < 60 then
                        duration = secs .. "s"
                    elseif secs < 3600 then
                        duration = math.floor(secs / 60) .. "m"
                    else
                        duration = string.format("%dh %dm", math.floor(secs / 3600), math.floor((secs % 3600) / 60))
                    end
                end
                local subtitle = fights .. (fights == 1 and " fight" or " fights")
                if duration ~= "" then subtitle = subtitle .. ", " .. duration end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Session" .. "  |cff888888(" .. subtitle .. ")|r", 1, 0.82, 0)
                local sessionPerPlayer = api.GetPerPlayer and api.GetPerPlayer()
                AddPlayerLines(api, sessionPerPlayer, sessionTotal, sessionHits, 0.2, 1, 0.2)
            else
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("No WF bonus damage recorded yet.", 0.5, 0.5, 0.5)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Right-click to reset stats", 0.5, 0.5, 0.5)
        if ShammyTime and ShammyTime.GetDB and not ShammyTime.GetDB().locked then
            GameTooltip:AddLine("Drag to move", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    -- Right-click to reset WF stats
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            local api = _G.ShammyTime_WFImpact
            if api and api.ResetStats then
                api.ResetStats()
                print("|cff00ccff[WF Impact]|r Stats reset.")
                -- Refresh tooltip immediately
                if GameTooltip:IsOwned(self) then
                    GameTooltip:Hide()
                    self:GetScript("OnEnter")(self)
                end
            end
        end
    end)
    -- Layer 1: back (icons, front, text are added by ShammyTime_WindfuryTotemBar in draw order)
    f.totemBarBack = f:CreateTexture(nil, "BACKGROUND")
    f.totemBarBack:SetTexture(TEX.TOTEM_BAR_BACK)
    f.totemBarBack:SetAllPoints(f)
    f.totemBarBack:SetTexCoord(0, 1, CROP_TOP, CROP_BOTTOM)
    f.totemBarBack:SetAlpha(1)
    f.cropTop = CROP_TOP
    f.cropBottom = CROP_BOTTOM
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

-- Returns the ring subframe (the one that scales on proc and holds shadow/bg/energy). Satellites parent to this so they move with the ring.
function ShammyTime.GetCenterRingFrame()
    local f = CreateCenterRingFrame()
    return f and f.ringFrame or nil
end

-- Called when a Windfury proc is detected (from combat log in ShammyTime_Windfury.lua). Shows the center ring, totem bar, and "Windfury!" text; plays the proc animation (energy flash, ring scale pop) and schedules lightning pulses and text/satellite fades.
-- forceShow: if true, show and play even when wfRadialEnabled is off (e.g. /st test).
function ShammyTime.PlayCenterRingProc(procTotal, forceShow)
    local db = ShammyTime.GetDB and ShammyTime.GetDB() or {}
    if not forceShow and not db.wfRadialEnabled then return end
    local f = CreateCenterRingFrame()
    if ShammyTime.CancelRadialHoverSequence then ShammyTime.CancelRadialHoverSequence() end
    -- Keep center at saved position (stops demo/proc from shifting the bubbles)
    if ShammyTime.ApplyCenterRingPosition then ShammyTime.ApplyCenterRingPosition() end
    f.wfProcAnimPlaying = true  -- block fade-out until animation finishes (circle stays visible in/out of combat)
    f:Show()
    if f.textFrame.fadeOutAnim then f.textFrame.fadeOutAnim:Stop() end
    f.textFrame:SetAlpha(1)
    f.textFrame:Show()
    -- Mark proc as recent and trigger radial text controller only after center/text are shown.
    if ShammyTime.NotifyWindfuryProcStarted then ShammyTime.NotifyWindfuryProcStarted() end
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
    rf:SetScale(1)
    rf:ClearAllPoints()
    rf:SetPoint("CENTER", f, "CENTER", 0, 0)
    rf._procAnimEnded = false
    if ShammyTime.StartSatelliteImpactShake then ShammyTime.StartSatelliteImpactShake() end
    rf._suppressAnimEnd = true   -- prevent onProcAnimEnd from firing during Stop-before-new-Play
    rf.procAnim:Stop()
    rf.procAnim:Play()
    rf._suppressAnimEnd = nil
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
    local centerShakePhaseX = math.random() * (math.pi * 2)
    local centerShakePhaseY = math.random() * (math.pi * 2)
    local centerShakeAmp = WF_IMPACT_SHAKE_CENTER_MAX_PX * (WF_IMPACT_SHAKE_CENTER_AMP_SCALE_MIN + math.random() * (WF_IMPACT_SHAKE_CENTER_AMP_SCALE_MAX - WF_IMPACT_SHAKE_CENTER_AMP_SCALE_MIN))
    local centerShakeFreqX = WF_IMPACT_SHAKE_CENTER_FREQ_X * (WF_IMPACT_SHAKE_CENTER_FREQ_SCALE_MIN + math.random() * (WF_IMPACT_SHAKE_CENTER_FREQ_SCALE_MAX - WF_IMPACT_SHAKE_CENTER_FREQ_SCALE_MIN))
    local centerShakeFreqY = WF_IMPACT_SHAKE_CENTER_FREQ_Y * (WF_IMPACT_SHAKE_CENTER_FREQ_SCALE_MIN + math.random() * (WF_IMPACT_SHAKE_CENTER_FREQ_SCALE_MAX - WF_IMPACT_SHAKE_CENTER_FREQ_SCALE_MIN))
    local centerShakeDecay = WF_IMPACT_SHAKE_CENTER_DECAY * (WF_IMPACT_SHAKE_CENTER_DECAY_SCALE_MIN + math.random() * (WF_IMPACT_SHAKE_CENTER_DECAY_SCALE_MAX - WF_IMPACT_SHAKE_CENTER_DECAY_SCALE_MIN))
    local centerShakeYRatio = WF_IMPACT_SHAKE_CENTER_Y_RATIO_MIN + math.random() * (WF_IMPACT_SHAKE_CENTER_Y_RATIO_MAX - WF_IMPACT_SHAKE_CENTER_Y_RATIO_MIN)
    local centerShakeHarmonicMul = nil
    local centerShakeHarmonicMix = 0
    if math.random() < WF_IMPACT_SHAKE_CENTER_HARMONIC_CHANCE then
        centerShakeHarmonicMul = 1.5 + math.random() * 0.8
        centerShakeHarmonicMix = 0.10 + math.random() * 0.10
    end
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
        local procNorm = (pop > 1) and ((scale - 1) / (pop - 1)) or 0
        if procNorm < 0 then procNorm = 0 elseif procNorm > 1 then procNorm = 1 end
        local shakeX, shakeY = 0, 0
        if procNorm > 0 then
            local decay = math.exp(-t * centerShakeDecay)
            local amp = centerShakeAmp * procNorm * decay
            if amp > 0.01 then
                local x = math.sin((t * centerShakeFreqX) + centerShakePhaseX)
                local y = math.cos((t * centerShakeFreqY) + centerShakePhaseY)
                if centerShakeHarmonicMul then
                    x = x + (math.sin((t * centerShakeFreqX * centerShakeHarmonicMul) + centerShakePhaseX * 1.65) * centerShakeHarmonicMix)
                    y = y + (math.cos((t * centerShakeFreqY * (centerShakeHarmonicMul * 0.95)) + centerShakePhaseY * 1.55) * centerShakeHarmonicMix)
                end
                shakeX = x * amp
                shakeY = y * amp * centerShakeYRatio
            end
        end
        rf:ClearAllPoints()
        rf:SetPoint("CENTER", f, "CENTER", shakeX, shakeY)
        rf:SetScale(scale)
        if ShammyTime.OnRingProcScaleUpdate then ShammyTime.OnRingProcScaleUpdate(scale) end
        if t >= total then
            if rf.satelliteTicker then
                rf.satelliteTicker:Cancel()
                rf.satelliteTicker = nil
            end
            rf:ClearAllPoints()
            rf:SetPoint("CENTER", f, "CENTER", 0, 0)
            rf:SetScale(1)
            if ShammyTime.ResetSatellitePositions then ShammyTime.ResetSatellitePositions() end
            -- Fallback: run proc-end cleanup/scheduling when scale cycle ends, even if procAnim callbacks did not fire.
            if rf._onProcAnimEnd then rf._onProcAnimEnd() end
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

-- True while the proc animation (energy + scale pop) is playing; used so fade logic does not hide the circle until the animation finishes.
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
