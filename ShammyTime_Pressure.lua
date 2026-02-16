-- ShammyTime_Pressure.lua
-- Production pressure frame + tier engine (ported from PoC model).
-- Reads outgoing damage from combat log, computes pressure/tier state, and
-- drives gauge + color overlay from T0-T5.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local ShammyTime = _G.ShammyTime
if not ShammyTime then return end

local M = _G.ShammyTime_Media
if not M then return end

local math_exp = math.exp
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local bit_band = bit and bit.band

local ADDON_PREFIX = "|cff00b4ff[ShammyTime]|r"
local FONT_PATH = "Fonts\\FRIZQT__.TTF"
local WINDOWS = { 300, 60, 30, 15, 5 }
local NUM_WINDOWS = #WINDOWS

local SIZE = 1024
local DEFAULT_SCALE = 0.5
local CROP_TOP = 0.20
local CROP_BOTTOM = 0.20
local PRESSURE_FILL_MAX = 4.0
local MIN_FILL_U = 0.001
local VISIBLE_HEIGHT_FRACTION = 1 - CROP_TOP - CROP_BOTTOM
if VISIBLE_HEIGHT_FRACTION <= 0 then
    VISIBLE_HEIGHT_FRACTION = 1
end
local DISPLAY_WIDTH = SIZE
local DISPLAY_HEIGHT = SIZE * VISIBLE_HEIGHT_FRACTION

local STACK = {
    { key = "background",                   file = "Pressure\\v2_pressure_bar_background_1024x1024.tga",         layer = "BACKGROUND", sub = 0 },
    { key = "backgroundSquares",            file = "Pressure\\v2_pressure_bar_background_squares_1024x1024.tga", layer = "ARTWORK",    sub = 0 },
    { key = "colorOverlay",                 file = "Pressure\\v2_pressure_bar_color_overlay_on_1024x1024.tga",   layer = "ARTWORK",    sub = 1 },
    { key = "gaugeZero",                    file = "Pressure\\v2_pressure_gauge_zero_pct_1024x1024.tga",         layer = "ARTWORK",    sub = 2 },
    { key = "gaugeTen",                     file = "Pressure\\v2_pressure_gauge_ten_pct_1024x1024.tga",          layer = "ARTWORK",    sub = 3 },
    { key = "gaugeFifty",                   file = "Pressure\\v2_pressure_gauge_fifty_pct_1024x1024.tga",        layer = "ARTWORK",    sub = 4 },
    { key = "gaugeSeventyFive",             file = "Pressure\\v2_pressure_gauge_seventyfive_pct_1024x1024.tga",  layer = "ARTWORK",    sub = 5 },
    { key = "gaugeHundred",                 file = "Pressure\\v2_pressure_gauge_hundred_pct_1024x1024.tga",      layer = "ARTWORK",    sub = 6 },
}

local frame = CreateFrame("Frame", "ShammyTimePressureFrame", UIParent)
frame:SetSize(DISPLAY_WIDTH, DISPLAY_HEIGHT)
frame:SetPoint("CENTER", 0, 0)
frame:SetScale(DEFAULT_SCALE)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame.textures = {}

for _, info in ipairs(STACK) do
    local tex = frame:CreateTexture(nil, info.layer)
    tex:SetDrawLayer(info.layer, info.sub)
    tex:SetTexture(M.MEDIA .. info.file)
    tex:SetTexCoord(0, 1, CROP_TOP, 1 - CROP_BOTTOM)
    tex:SetAllPoints(frame)
    frame.textures[info.key] = tex
end

local gaugeKeys = {
    "gaugeZero",
    "gaugeTen",
    "gaugeFifty",
    "gaugeSeventyFive",
    "gaugeHundred",
}

local gaugeCurrentAlpha = { 1, 0, 0, 0, 0 }
local colorOverlayFillFrac = 0

local function SetColorOverlayFill(fillFrac)
    local colorOverlay = frame.textures.colorOverlay
    if not colorOverlay then return end

    local frac = math_min(math_max(fillFrac or 0, 0), 1)
    if frac <= 0 then
        colorOverlay:Hide()
        colorOverlay:SetWidth(1)
        colorOverlay:SetTexCoord(0, MIN_FILL_U, CROP_TOP, 1 - CROP_BOTTOM)
        return
    end

    local uRight = math_max(frac, MIN_FILL_U)
    colorOverlay:Show()
    colorOverlay:SetWidth(DISPLAY_WIDTH * uRight)
    colorOverlay:SetTexCoord(0, uRight, CROP_TOP, 1 - CROP_BOTTOM)
end

if frame.textures.colorOverlay then
    local colorOverlay = frame.textures.colorOverlay
    colorOverlay:ClearAllPoints()
    colorOverlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    colorOverlay:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    colorOverlay:SetWidth(1)
end

for i, key in ipairs(gaugeKeys) do
    local tex = frame.textures[key]
    if tex then
        tex:SetAlpha(gaugeCurrentAlpha[i] or 0)
    end
end
if frame.textures.colorOverlay then
    frame.textures.colorOverlay:SetAlpha(1)
end
SetColorOverlayFill(colorOverlayFillFrac)

frame:Show()

local LINE_HEIGHT = 14
local HEADER_HEIGHT = 22
local PADDING = 6
local DEBUG_FRAME_WIDTH = 340
local DEBUG_BAR_HEIGHT = 24
local DEBUG_FRAME_HEIGHT = HEADER_HEIGHT + PADDING * 2 + DEBUG_BAR_HEIGHT + 4
    + LINE_HEIGHT + LINE_HEIGHT + 4 + NUM_WINDOWS * (LINE_HEIGHT + 2) + PADDING

local debugFrame = CreateFrame("Frame", "ShammyTimePressureDebugFrame", UIParent, "BackdropTemplate")
debugFrame:SetSize(DEBUG_FRAME_WIDTH, DEBUG_FRAME_HEIGHT)
debugFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -120)
debugFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
debugFrame:SetBackdropColor(0, 0, 0, 0.85)
debugFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)
debugFrame:SetFrameStrata("MEDIUM")
debugFrame:SetClampedToScreen(true)
debugFrame:SetMovable(true)
debugFrame:EnableMouse(true)
debugFrame:RegisterForDrag("LeftButton")
debugFrame:SetScript("OnDragStart", debugFrame.StartMoving)
debugFrame:SetScript("OnDragStop", debugFrame.StopMovingOrSizing)
debugFrame:Hide()

local debugTitle = debugFrame:CreateFontString(nil, "OVERLAY")
debugTitle:SetFont(FONT_PATH, 12, "OUTLINE")
debugTitle:SetPoint("TOPLEFT", debugFrame, "TOPLEFT", PADDING, -PADDING)
debugTitle:SetText("ShammyTime Pressure Debug")
debugTitle:SetTextColor(1, 0.82, 0)

local debugBar = CreateFrame("StatusBar", nil, debugFrame)
debugBar:SetSize(DEBUG_FRAME_WIDTH - PADDING * 2 - 4, DEBUG_BAR_HEIGHT)
debugBar:SetPoint("TOPLEFT", debugFrame, "TOPLEFT", PADDING + 2, -(HEADER_HEIGHT + PADDING))
debugBar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
debugBar:SetMinMaxValues(0.0, 4.0)
debugBar:SetValue(0.0)
debugBar:SetStatusBarColor(0.5, 0.5, 0.5)

local debugBarBg = debugBar:CreateTexture(nil, "BACKGROUND")
debugBarBg:SetAllPoints()
debugBarBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

local debugBarText = debugBar:CreateFontString(nil, "OVERLAY")
debugBarText:SetFont(FONT_PATH, 13, "OUTLINE")
debugBarText:SetPoint("CENTER", debugBar, "CENTER", 0, 0)
debugBarText:SetText("0.00x")

local debugBarTierText = debugBar:CreateFontString(nil, "OVERLAY")
debugBarTierText:SetFont(FONT_PATH, 11, "OUTLINE")
debugBarTierText:SetPoint("RIGHT", debugBar, "RIGHT", -4, 0)
debugBarTierText:SetText("T0")
debugBarTierText:SetTextColor(0.6, 0.6, 0.6)

local yAfterBar = -(HEADER_HEIGHT + PADDING + DEBUG_BAR_HEIGHT + 4)
local debugText = debugFrame:CreateFontString(nil, "OVERLAY")
debugText:SetFont(FONT_PATH, 10, "")
debugText:SetJustifyH("LEFT")
debugText:SetPoint("TOPLEFT", debugFrame, "TOPLEFT", PADDING, yAfterBar)
debugText:SetPoint("RIGHT", debugFrame, "RIGHT", -PADDING, 0)
debugText:SetTextColor(0.6, 0.6, 0.6)
debugText:SetText("n:0.00 i:0.00 q:0.00 ts:0.00 hk:0.00 ok")

local yBucketStart = yAfterBar - LINE_HEIGHT - 4
local bucketStrings = {}
for i = 1, NUM_WINDOWS do
    local fs = debugFrame:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT_PATH, 11, "")
    fs:SetJustifyH("LEFT")
    fs:SetPoint("TOPLEFT", debugFrame, "TOPLEFT", PADDING, yBucketStart - (i - 1) * (LINE_HEIGHT + 2))
    fs:SetPoint("RIGHT", debugFrame, "RIGHT", -PADDING, 0)
    fs:SetText("")
    bucketStrings[i] = fs
end

local TIER_COLORS = {
    { 0.50, 0.50, 0.50 }, -- T0
    { 0.20, 0.80, 0.20 }, -- T1
    { 0.40, 0.90, 0.10 }, -- T2
    { 1.00, 0.80, 0.00 }, -- T3
    { 1.00, 0.40, 0.00 }, -- T4
    { 1.00, 0.10, 0.10 }, -- T5
}

local TIER_GAUGE_INDEX = {
    [0] = 1, -- gaugeZero
    [1] = 2, -- gaugeTen
    [2] = 3, -- gaugeFifty
    [3] = 4, -- gaugeSeventyFive
    [4] = 5, -- gaugeHundred
    [5] = 5, -- gaugeHundred
}

local TIER_GAUGE_ALPHA = {
    [0] = 1.00,
    [1] = 1.00,
    [2] = 1.00,
    [3] = 1.00,
    [4] = 0.90,
    [5] = 1.00,
}

local function SmoothAlpha(current, target, elapsed, tauIn, tauOut)
    if math_abs(current - target) < 0.003 then
        return target
    end
    local tau = (target > current) and tauIn or tauOut
    tau = math_max(tau or 0.1, 0.02)
    local alpha = 1 - math_exp(-elapsed / tau)
    return current + (target - current) * alpha
end

local PS = {
    fastCharge = 0,
    slowCharge = 0,
    tauFast = 1.0,
    tauSlow = 20.0,
    epsilon = 1.0,
    pressureRatio = 0,
    displayGain = 1.20,
    burstDamping = 1.20,
    denominatorFloor = 200,
    displayTau = 0.30,
    displayTauRise = 0.12,
    pressureDisplaySmoothed = 0,
    pressureComposite = 0,
    instantScore = 0,
    squeezeScore = 0,
    tierScore = 0,
    currentTier = 0,
    lastTierChangeAt = 0,
    tierCapReason = "ok",
    recentHitImpulse = 0,
    squeezeCharge = 0,
    squeezeDecayTau = 18.0,
    critBonusMult = 2.0,
    squeezeBuildRate = 0.25,
    squeezeBonusMax = 0.85,
    squeezeBuildBaseline = 1.20,
    squeezeBuildPower = 1.20,
    squeezeIdleDecayMult = 0.45,
    tierInstantWeight = 0.95,
    tierSqueezeWeight = 0.65,
    tierHysteresis = 0.10,
    tierHoldMinSec = 2.00,
    hitImpulseTau = 1.20,
    nearTierProgressFrac = 0.75,
    nearTierKickMin = 0.15,
    nearTierKickWeight = 0.70,
    tierMinSqueeze = { 0.00, 0.00, 0.18, 0.35, 0.70, 0.92 },
    tierMinActiveSec = { 0.0, 1.2, 2.5, 4.0, 7.0, 14.0 },
    firstPressureAt = nil,
    pressureTick = 0.05,
    pressureElapsed = 0,
    lastDamageTime = 0,
    pressureSamples = {},
    pressureSampleHead = 1,
    pressureSampleRetention = 300,
    bucketStatsElapsed = 0,
    bucketStatsInterval = 0.5,
    pressureBucketAvg = { 0, 0, 0, 0, 0 },
    pressureBucketMax = { 0, 0, 0, 0, 0 },
    tierThresholds = { 1.15, 1.55, 1.90, 2.50, 3.20 },
}

local function ExportPressureState()
    ShammyTime.PressureState = PS
    ShammyTime.GetPressureState = function()
        return PS
    end
    _G.ShammyTimePressureState = PS
    _G.ShammyTime_PressureState = PS
end

ExportPressureState()

local function GetTier(score)
    for i = #PS.tierThresholds, 1, -1 do
        if score >= PS.tierThresholds[i] then return i end
    end
    return 0
end

local function GetPromoteThreshold(tier)
    if tier <= 0 then return 0 end
    return PS.tierThresholds[tier] or PS.tierThresholds[#PS.tierThresholds]
end

local function GetDemoteThreshold(tier)
    if tier <= 0 then return -math.huge end
    return GetPromoteThreshold(tier) - PS.tierHysteresis
end

local function GetGateCappedTier(candidateTier, squeeze, activeSec)
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

local SUBEVENT_MAP = {
    SWING_DAMAGE        = { 12, 18 },
    SWING_DAMAGE_LANDED = { 12, 18 },
    SPELL_DAMAGE          = { 15, 21 },
    RANGE_DAMAGE          = { 15, 21 },
    SPELL_PERIODIC_DAMAGE = { 15, 21 },
    DAMAGE_SHIELD         = { 15, 21 },
}

local AFFILIATION_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001

local function OnCombatLogPressure()
    if not CombatLogGetCurrentEventInfo then return end
    if not bit_band then return end

    local subevent = select(2, CombatLogGetCurrentEventInfo())
    local info = SUBEVENT_MAP[subevent]
    if not info then return end

    local p = { CombatLogGetCurrentEventInfo() }
    local sourceFlags = p[6]
    if not sourceFlags or bit_band(sourceFlags, AFFILIATION_MINE) == 0 then return end

    local amount = p[info[1]]
    if not amount or amount <= 0 then return end

    local critFlag = p[info[2]]
    local isCrit = (critFlag == true or critFlag == 1)

    local now = GetTime()
    if not PS.firstPressureAt then
        PS.firstPressureAt = now
    end

    local feedAmount = amount
    if isCrit then
        feedAmount = amount * PS.critBonusMult
    end

    PS.fastCharge = PS.fastCharge + feedAmount
    PS.slowCharge = PS.slowCharge + amount
    PS.recentHitImpulse = PS.recentHitImpulse + feedAmount
    PS.lastDamageTime = now
end

local function UpdatePressureVisuals(elapsed)
    local tier = PS.currentTier or 0
    local tierColor = TIER_COLORS[tier + 1] or TIER_COLORS[1]

    local fillTarget = math_min(math_max((PS.pressureComposite or 0) / PRESSURE_FILL_MAX, 0), 1)
    colorOverlayFillFrac = SmoothAlpha(colorOverlayFillFrac, fillTarget, elapsed, 0.08, 0.20)
    local colorOverlay = frame.textures.colorOverlay
    if colorOverlay then
        colorOverlay:SetVertexColor(tierColor[1], tierColor[2], tierColor[3])
        colorOverlay:SetAlpha(1)
    end
    SetColorOverlayFill(colorOverlayFillFrac)

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
        gaugeCurrentAlpha[i] = SmoothAlpha(gaugeCurrentAlpha[i], targetAlpha, elapsed, 0.10, 0.20)
        local tex = frame.textures[key]
        if tex then
            tex:SetAlpha(gaugeCurrentAlpha[i])
        end
    end
end

local function ClearPressureDebugFrame()
    debugBar:SetValue(0.0)
    debugBar:SetStatusBarColor(0.5, 0.5, 0.5)
    debugBarText:SetText("0.00x")
    debugBarTierText:SetText("T0")
    debugBarTierText:SetTextColor(0.6, 0.6, 0.6)
    debugText:SetText("n:0.00 i:0.00 q:0.00 ts:0.00 hk:0.00 ok")
    for i = 1, NUM_WINDOWS do
        bucketStrings[i]:SetText("")
    end
end

local function UpdatePressureDebugFrame(hitKick)
    if not debugFrame:IsShown() then return end

    local tier = PS.currentTier or 0
    local col = TIER_COLORS[tier + 1] or TIER_COLORS[1]
    local display = PS.pressureComposite or 0
    local barValue = math_min(math_max(display, 0.0), 4.0)

    debugBar:SetValue(barValue)
    debugBar:SetStatusBarColor(col[1], col[2], col[3])
    debugBarText:SetText(string.format("%.2fx", display))
    debugBarTierText:SetText(string.format("T%d", tier))
    debugBarTierText:SetTextColor(col[1], col[2], col[3])

    debugText:SetText(string.format(
        "n:%.2f i:%.2f q:%.2f ts:%.2f hk:%.2f %s",
        PS.pressureRatio or 0,
        PS.instantScore or 0,
        PS.squeezeCharge or 0,
        PS.tierScore or 0,
        hitKick or 0,
        PS.tierCapReason or "ok"
    ))

    for wi = 1, NUM_WINDOWS do
        local w = WINDOWS[wi]
        bucketStrings[wi]:SetText(string.format(
            "%3ds:  avg %.2fx  max %.2fx",
            w, PS.pressureBucketAvg[wi] or 0, PS.pressureBucketMax[wi] or 0
        ))
    end
end

local function SetPressureDebugVisible(visible)
    if visible then
        debugFrame:Show()
    else
        debugFrame:Hide()
    end
end

local function ResetPressureState()
    PS.fastCharge = 0
    PS.slowCharge = 0
    PS.pressureRatio = 0
    PS.pressureDisplaySmoothed = 0
    PS.pressureComposite = 0
    PS.instantScore = 0
    PS.squeezeScore = 0
    PS.tierScore = 0
    PS.currentTier = 0
    PS.lastTierChangeAt = 0
    PS.tierCapReason = "ok"
    PS.recentHitImpulse = 0
    PS.squeezeCharge = 0
    PS.firstPressureAt = nil
    PS.lastDamageTime = 0
    PS.pressureElapsed = 0
    PS.pressureSamples = {}
    PS.pressureSampleHead = 1
    PS.bucketStatsElapsed = 0
    for wi = 1, NUM_WINDOWS do
        PS.pressureBucketAvg[wi] = 0
        PS.pressureBucketMax[wi] = 0
    end
    ClearPressureDebugFrame()
end

ShammyTime.ResetPressureState = ResetPressureState

local function OnPressureTick(_, dt)
    PS.pressureElapsed = PS.pressureElapsed + dt
    if PS.pressureElapsed < PS.pressureTick then return end
    local elapsed = PS.pressureElapsed
    PS.pressureElapsed = 0

    local now = GetTime()
    PS.fastCharge = PS.fastCharge * math_exp(-elapsed / math_max(PS.tauFast, 0.01))
    PS.slowCharge = PS.slowCharge * math_exp(-elapsed / math_max(PS.tauSlow, 0.01))
    if PS.fastCharge < 0.01 then PS.fastCharge = 0 end
    if PS.slowCharge < 0.01 then PS.slowCharge = 0 end

    local scale = PS.tauFast / math_max(PS.tauSlow, 0.001)
    local steadyDen = PS.slowCharge * scale
    local dampedDen = (steadyDen + (PS.fastCharge * PS.burstDamping)) / (1 + PS.burstDamping)
    dampedDen = math_max(dampedDen, PS.denominatorFloor)
    PS.pressureRatio = PS.fastCharge / math_max(dampedDen, PS.epsilon)

    local ns = #PS.pressureSamples + 1
    PS.pressureSamples[ns] = { t = now, p = PS.pressureRatio }

    local sampleCutoff = now - PS.pressureSampleRetention
    while PS.pressureSampleHead <= ns do
        local headSample = PS.pressureSamples[PS.pressureSampleHead]
        if not headSample then
            PS.pressureSampleHead = PS.pressureSampleHead + 1
        elseif headSample.t < sampleCutoff then
            PS.pressureSamples[PS.pressureSampleHead] = nil
            PS.pressureSampleHead = PS.pressureSampleHead + 1
        else
            break
        end
    end

    if PS.pressureSampleHead > 1 and PS.pressureSampleHead > (ns / 2) then
        local newArr = {}
        local j = 0
        for i = PS.pressureSampleHead, ns do
            local sample = PS.pressureSamples[i]
            if sample then
                j = j + 1
                newArr[j] = sample
            end
        end
        PS.pressureSamples = newArr
        PS.pressureSampleHead = 1
    end

    PS.bucketStatsElapsed = PS.bucketStatsElapsed + elapsed
    if PS.bucketStatsElapsed >= PS.bucketStatsInterval then
        PS.bucketStatsElapsed = 0
        for wi = 1, NUM_WINDOWS do
            PS.pressureBucketAvg[wi] = 0
            PS.pressureBucketMax[wi] = 0
        end
        local bucketCount = { 0, 0, 0, 0, 0 }
        for i = PS.pressureSampleHead, #PS.pressureSamples do
            local sample = PS.pressureSamples[i]
            if sample then
                local age = now - sample.t
                for wi = 1, NUM_WINDOWS do
                    if age <= WINDOWS[wi] then
                        PS.pressureBucketAvg[wi] = PS.pressureBucketAvg[wi] + sample.p
                        bucketCount[wi] = bucketCount[wi] + 1
                        if sample.p > PS.pressureBucketMax[wi] then
                            PS.pressureBucketMax[wi] = sample.p
                        end
                    end
                end
            end
        end
        for wi = 1, NUM_WINDOWS do
            if bucketCount[wi] > 0 then
                PS.pressureBucketAvg[wi] = PS.pressureBucketAvg[wi] / bucketCount[wi]
            end
        end
    end

    local targetDisplay = PS.pressureRatio * PS.displayGain
    local smoothingTau = (targetDisplay > PS.pressureDisplaySmoothed) and PS.displayTauRise or PS.displayTau
    local displayAlpha = 1 - math_exp(-elapsed / math_max(smoothingTau, 0.01))
    PS.pressureDisplaySmoothed = PS.pressureDisplaySmoothed + (targetDisplay - PS.pressureDisplaySmoothed) * displayAlpha

    local overBaseline = math_max(PS.pressureDisplaySmoothed - PS.squeezeBuildBaseline, 0.0)
    local inCombat = UnitAffectingCombat("player")
    local decayTau = PS.squeezeDecayTau
    if (not inCombat) and ((now - PS.lastDamageTime) > 3.0) then
        decayTau = PS.squeezeDecayTau * PS.squeezeIdleDecayMult
    end
    PS.squeezeCharge = PS.squeezeCharge * math_exp(-elapsed / math_max(decayTau, 0.1))
    PS.squeezeCharge = PS.squeezeCharge + ((overBaseline ^ PS.squeezeBuildPower) * PS.squeezeBuildRate * elapsed)
    PS.squeezeCharge = math_min(math_max(PS.squeezeCharge, 0.0), 1.0)

    PS.pressureComposite = PS.pressureDisplaySmoothed + (PS.squeezeCharge * PS.squeezeBonusMax)
    PS.instantScore = PS.pressureDisplaySmoothed
    PS.squeezeScore = PS.squeezeCharge * PS.squeezeBonusMax
    PS.tierScore = (PS.instantScore * PS.tierInstantWeight) + (PS.squeezeScore * PS.tierSqueezeWeight)

    PS.recentHitImpulse = PS.recentHitImpulse * math_exp(-elapsed / math_max(PS.hitImpulseTau, 0.1))
    local hitKick = math_min((PS.recentHitImpulse / math_max(dampedDen, PS.epsilon)) * 0.25, 1.0)

    local activeSec = PS.firstPressureAt and (now - PS.firstPressureAt) or 0
    local candidateTier = GetTier(PS.tierScore)

    if PS.currentTier < 5 then
        local nextTier = PS.currentTier + 1
        local nextThreshold = GetPromoteThreshold(nextTier)
        if nextThreshold > 0 then
            local progress = PS.tierScore / nextThreshold
            if progress >= PS.nearTierProgressFrac and hitKick >= PS.nearTierKickMin then
                local promotionScore = PS.tierScore + (hitKick * PS.nearTierKickWeight)
                local promotedTier = GetTier(promotionScore)
                candidateTier = math_max(candidateTier, math_min(promotedTier, nextTier))
            end
        end
    end

    local gatedTier
    gatedTier, PS.tierCapReason = GetGateCappedTier(candidateTier, PS.squeezeCharge, activeSec)

    if gatedTier > PS.currentTier then
        PS.currentTier = gatedTier
        PS.lastTierChangeAt = now
    elseif gatedTier < PS.currentTier then
        local currentIdx = PS.currentTier + 1
        local gateFailsCurrentTier = (PS.squeezeCharge < (PS.tierMinSqueeze[currentIdx] or 0))
                                  or (activeSec < (PS.tierMinActiveSec[currentIdx] or 0))
        local demoteThreshold = GetDemoteThreshold(PS.currentTier)
        local scoreWantsDemote = PS.tierScore <= demoteThreshold
        local holdElapsed = now - PS.lastTierChangeAt
        if holdElapsed >= PS.tierHoldMinSec and (gateFailsCurrentTier or scoreWantsDemote) then
            PS.currentTier = math_max(gatedTier, PS.currentTier - 1)
            PS.lastTierChangeAt = now
        end
    end

    UpdatePressureVisuals(elapsed)
    UpdatePressureDebugFrame(hitKick)
    ExportPressureState()
end

local pressureTickFrame = CreateFrame("Frame")
pressureTickFrame:SetScript("OnUpdate", OnPressureTick)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "ShammyTime" then
        eventFrame:UnregisterEvent("ADDON_LOADED")
        ExportPressureState()
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLogPressure()
    end
end)

ShammyTime.GetPressureFrame = function()
    return frame
end

ShammyTime.EnsurePressureFrame = function()
    return frame
end

local function PrintPressureHelp()
    print(ADDON_PREFIX .. " pressure commands:")
    print("  /st pressure on|off|toggle")
    print("  /st pressure reset")
    print("  /st pressure status")
    print("  /st pressure taufast N")
    print("  /st pressure tauslow N")
    print("  /st pressure gain N")
    print("  /st pressure damp N")
    print("  /st pressure smoothtau N")
    print("  /st pressure squeezetau N")
    print("  /st pressure squeezebuild N")
    print("  /st pressure hysteresis N")
    print("  /stpressure ... (same commands)")
end

local function HandlePressureSlash(msg)
    local trimmed = (msg or ""):lower():match("^%s*(.-)%s*$")
    local cmd, arg = trimmed:match("^(%S+)%s*(.-)$")
    if not cmd or cmd == "" then
        cmd = "toggle"
    end

    if cmd == "on" then
        SetPressureDebugVisible(true)
        print(ADDON_PREFIX .. " pressure debug panel shown.")
        return
    end
    if cmd == "off" then
        SetPressureDebugVisible(false)
        print(ADDON_PREFIX .. " pressure debug panel hidden.")
        return
    end
    if cmd == "toggle" then
        local nextShown = not debugFrame:IsShown()
        SetPressureDebugVisible(nextShown)
        print(ADDON_PREFIX .. " pressure debug panel " .. (nextShown and "shown." or "hidden."))
        return
    end
    if cmd == "reset" or cmd == "clear" then
        ResetPressureState()
        print(ADDON_PREFIX .. " pressure state reset.")
        return
    end
    if cmd == "status" then
        print(ADDON_PREFIX .. string.format(
            " n=%.3f i=%.3f q=%.2f ts=%.3f tier=T%d cap=%s",
            PS.pressureRatio, PS.instantScore, PS.squeezeCharge, PS.tierScore,
            PS.currentTier or 0, PS.tierCapReason or "ok"
        ))
        print(ADDON_PREFIX .. string.format(
            " tauFast=%.2f tauSlow=%.2f gain=%.2f damp=%.2f smoothTau=%.2f squeezeTau=%.1f squeezeBuild=%.2f hyst=%.2f",
            PS.tauFast, PS.tauSlow, PS.displayGain, PS.burstDamping,
            PS.displayTau, PS.squeezeDecayTau, PS.squeezeBuildRate, PS.tierHysteresis
        ))
        return
    end

    local n = tonumber(arg)
    if cmd == "taufast" then
        if n and n >= 0.1 and n <= 30 then
            PS.tauFast = n
            print(ADDON_PREFIX .. " tauFast set to " .. string.format("%.2f", n) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /st pressure taufast 0.1-30")
        end
        return
    end
    if cmd == "tauslow" then
        if n and n >= 1 and n <= 120 then
            PS.tauSlow = n
            print(ADDON_PREFIX .. " tauSlow set to " .. string.format("%.2f", n) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /st pressure tauslow 1-120")
        end
        return
    end
    if cmd == "gain" then
        if n and n >= 0.1 and n <= 10 then
            PS.displayGain = n
            print(ADDON_PREFIX .. " displayGain set to " .. string.format("%.2f", n))
        else
            print(ADDON_PREFIX .. " usage: /st pressure gain 0.1-10")
        end
        return
    end
    if cmd == "damp" then
        if n and n >= 0 and n <= 2 then
            PS.burstDamping = n
            print(ADDON_PREFIX .. " burstDamping set to " .. string.format("%.2f", n))
        else
            print(ADDON_PREFIX .. " usage: /st pressure damp 0-2")
        end
        return
    end
    if cmd == "smoothtau" then
        if n and n >= 0.05 and n <= 5 then
            PS.displayTau = n
            print(ADDON_PREFIX .. " displayTau set to " .. string.format("%.2f", n) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /st pressure smoothtau 0.05-5")
        end
        return
    end
    if cmd == "squeezetau" then
        if n and n >= 3 and n <= 60 then
            PS.squeezeDecayTau = n
            print(ADDON_PREFIX .. " squeezeDecayTau set to " .. string.format("%.1f", n) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /st pressure squeezetau 3-60")
        end
        return
    end
    if cmd == "squeezebuild" then
        if n and n >= 0.05 and n <= 3 then
            PS.squeezeBuildRate = n
            print(ADDON_PREFIX .. " squeezeBuildRate set to " .. string.format("%.2f", n))
        else
            print(ADDON_PREFIX .. " usage: /st pressure squeezebuild 0.05-3")
        end
        return
    end
    if cmd == "hysteresis" then
        if n and n >= 0 and n <= 1 then
            PS.tierHysteresis = n
            print(ADDON_PREFIX .. " tierHysteresis set to " .. string.format("%.2f", n))
        else
            print(ADDON_PREFIX .. " usage: /st pressure hysteresis 0-1")
        end
        return
    end

    PrintPressureHelp()
end

ShammyTime.HandlePressureSlash = HandlePressureSlash
SLASH_STPRESSURE1 = "/stpressure"
SlashCmdList["STPRESSURE"] = function(msg)
    HandlePressureSlash(msg)
end

-- Optional helpers for quick in-game tweaks:
-- /script ShammyTimePressureSetScale(0.5)
-- /script ShammyTimePressureReset()
function ShammyTimePressureSetScale(scale)
    if type(scale) ~= "number" or scale <= 0 then return end
    local f = _G.ShammyTimePressureFrame
    if not f then return end
    f:SetScale(scale)
    print(string.format("ShammyTime Pressure scale: %.2f", scale))
end

function ShammyTimePressureReset()
    ResetPressureState()
end
