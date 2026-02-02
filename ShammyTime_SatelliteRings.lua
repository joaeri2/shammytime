-- ShammyTime_SatelliteRings.lua
-- Satellite rings around the center ring (CRIT%, MAX, MIN, AVG, PROCS, PROC%).
-- Reusable factory for creating satellite rings with same animation style as center.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local M = ShammyTime_Media
if not M then return end

local TEX = M.TEX

-- Satellite ring size (smaller than center's 260)
local SATELLITE_SIZE = 120
local SATELLITE_SCALE = 0.85

-- Distance from center ring center to satellite center
local SATELLITE_RADIUS = 155

-- Positions for 6 satellites (angle in degrees, 0 = right, counter-clockwise)
-- Upper right, right, lower right, lower left, left, upper left
local SATELLITE_POSITIONS = {
    CRIT   = 45,   -- upper right
    MAX    = 135,  -- upper left
    MIN    = 180,  -- left
    AVG    = 225,  -- lower left
    PROCS  = 315,  -- lower right
    PROCPCT = 0,   -- right
}

-- Storage for satellite frames
local satelliteFrames = {}

local function FormatNum(n)
    if not n or n < 0 then return "0" end
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

-- Factory: create a satellite ring with layered textures
-- textures = { bg, glow, border, shadow (optional) }
-- label = text label (e.g. "CRIT%")
-- position = angle in degrees (0 = right, counter-clockwise)
local function CreateSatelliteRing(name, textures, label, position, parentFrame)
    if satelliteFrames[name] then return satelliteFrames[name] end

    local angle = math.rad(position)
    local offsetX = SATELLITE_RADIUS * math.cos(angle)
    local offsetY = SATELLITE_RADIUS * math.sin(angle)

    local f = CreateFrame("Frame", "ShammyTimeSatellite_" .. name, UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(parentFrame and (parentFrame:GetFrameLevel() + 5) or 50)
    f:SetSize(SATELLITE_SIZE, SATELLITE_SIZE)
    f:SetScale(SATELLITE_SCALE)
    f:SetPoint("CENTER", parentFrame or UIParent, "CENTER", offsetX, offsetY)
    f:Hide()

    -- Shadow (optional, behind everything)
    if textures.shadow then
        f.shadow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
        f.shadow:SetSize(SATELLITE_SIZE * 1.3, SATELLITE_SIZE * 1.3)
        f.shadow:SetPoint("CENTER", 0, 0)
        f.shadow:SetTexture(textures.shadow)
        f.shadow:SetAlpha(0.4)
    end

    -- 1. BACKGROUND (bottom)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.bg:SetTexture(textures.bg)
    f.bg:SetAlpha(1)

    -- 2. GLOW/ENERGY (ADD blend for brightness, below border)
    f.glow = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.glow:SetAllPoints(f)
    f.glow:SetTexture(textures.glow)
    f.glow:SetAlpha(0.8)
    f.glow:SetBlendMode("ADD")

    -- 3. BORDER (on top of glow)
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetAllPoints(f)
    f.border:SetTexture(textures.border)
    f.border:SetAlpha(1)

    -- Text on a SEPARATE frame (not a child) so it doesn't scale with the ring
    local textFrame = CreateFrame("Frame", "ShammyTimeSatelliteText_" .. name, UIParent)
    textFrame:SetFrameStrata("DIALOG")
    textFrame:SetFrameLevel(f:GetFrameLevel() + 10)
    textFrame:SetSize(SATELLITE_SIZE, SATELLITE_SIZE)
    textFrame:SetPoint("CENTER", f, "CENTER", 0, 0)
    textFrame:Hide()
    f.textFrame = textFrame

    f.label = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("CENTER", 0, 8)
    f.label:SetText(label or "")
    f.label:SetTextColor(0.9, 0.85, 0.7)
    f.label:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    f.labelRestColor = {0.9, 0.85, 0.7}
    f.labelFlashColor = {1, 1, 1}

    f.value = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.value:SetPoint("CENTER", 0, -6)
    f.value:SetText("0")
    f.value:SetTextColor(1, 1, 1)
    f.value:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    f.valueRestColor = {1, 1, 1}
    f.valueFlashColor = {1, 1, 0.5}

    -- Proc pulse animation (same style as center ring)
    local pop = 1.18
    local inv = 1 / pop

    local function BuildProcAnim(frame)
        local g = frame:CreateAnimationGroup()

        -- Scale: snappy pop, then quick settle
        local s1 = g:CreateAnimation("Scale")
        s1:SetOrder(1)
        s1:SetDuration(0.03)
        s1:SetScale(pop, pop)
        s1:SetSmoothing("OUT")

        local s2 = g:CreateAnimation("Scale")
        s2:SetOrder(2)
        s2:SetDuration(0.28)
        s2:SetScale(inv, inv)
        s2:SetSmoothing("OUT")

        -- Glow: instant flash to full, then soften back to resting
        local gFlash = g:CreateAnimation("Alpha")
        gFlash:SetTarget(frame.glow)
        gFlash:SetOrder(1)
        gFlash:SetDuration(0.02)
        gFlash:SetFromAlpha(0.8)
        gFlash:SetToAlpha(1.0)

        local gSoft = g:CreateAnimation("Alpha")
        gSoft:SetTarget(frame.glow)
        gSoft:SetOrder(2)
        gSoft:SetDuration(0.35)
        gSoft:SetFromAlpha(1.0)
        gSoft:SetToAlpha(0.8)
        gSoft:SetSmoothing("OUT")

        return g
    end

    f.procAnim = BuildProcAnim(f)

    -- Text color flash
    function f:FlashText()
        self.label:SetTextColor(unpack(self.labelFlashColor))
        self.value:SetTextColor(unpack(self.valueFlashColor))
        local steps = 20
        local interval = 0.4 / steps
        local step = 0
        if self.textFlashTicker then self.textFlashTicker:Cancel() end
        self.textFlashTicker = C_Timer.NewTicker(interval, function()
            step = step + 1
            local t = step / steps
            local lr = self.labelFlashColor[1] + (self.labelRestColor[1] - self.labelFlashColor[1]) * t
            local lg = self.labelFlashColor[2] + (self.labelRestColor[2] - self.labelFlashColor[2]) * t
            local lb = self.labelFlashColor[3] + (self.labelRestColor[3] - self.labelFlashColor[3]) * t
            self.label:SetTextColor(lr, lg, lb)
            local vr = self.valueFlashColor[1] + (self.valueRestColor[1] - self.valueFlashColor[1]) * t
            local vg = self.valueFlashColor[2] + (self.valueRestColor[2] - self.valueFlashColor[2]) * t
            local vb = self.valueFlashColor[3] + (self.valueRestColor[3] - self.valueFlashColor[3]) * t
            self.value:SetTextColor(vr, vg, vb)
            if step >= steps then
                self.textFlashTicker:Cancel()
                self.textFlashTicker = nil
                self.label:SetTextColor(unpack(self.labelRestColor))
                self.value:SetTextColor(unpack(self.valueRestColor))
            end
        end)
    end

    -- Play proc animation
    function f:PlayProc()
        self:SetScale(SATELLITE_SCALE)
        self.glow:SetAlpha(0.8)
        self.procAnim:Stop()
        self.procAnim:Play()
        self:FlashText()
    end

    -- Show satellite
    function f:ShowSatellite()
        self:Show()
        self.textFrame:Show()
    end

    -- Hide satellite
    function f:HideSatellite()
        self:Hide()
        self.textFrame:Hide()
    end

    -- Set value text
    function f:SetValue(val)
        self.value:SetText(val or "0")
    end

    satelliteFrames[name] = f
    return f
end

-- Get the center ring frame (from CenterRingTest)
local function GetCenterFrame()
    return _G["ShammyTimeCenterRingTest"]
end

-- Create CRIT satellite ring
local function GetCritRing()
    local centerFrame = GetCenterFrame()
    return CreateSatelliteRing("CRIT", {
        bg     = TEX.CRIT_BG,
        glow   = TEX.CRIT_GLOW,
        border = TEX.CRIT_BORDER,
        shadow = TEX.CRIT_SHADOW,
    }, "CRIT%", SATELLITE_POSITIONS.CRIT, centerFrame)
end

-- Expose API for other files
ShammyTime.CreateSatelliteRing = CreateSatelliteRing
ShammyTime.GetSatelliteFrame = function(name) return satelliteFrames[name] end
ShammyTime.SATELLITE_POSITIONS = SATELLITE_POSITIONS

-- Play crit ring with center ring
local originalPlayCenterRingProc = ShammyTime.PlayCenterRingProc
ShammyTime.PlayCenterRingProc = function(procTotal)
    -- Call original center ring proc
    if originalPlayCenterRingProc then
        originalPlayCenterRingProc(procTotal)
    end
    -- Also show and animate crit ring
    local critRing = GetCritRing()
    if critRing then
        critRing:ShowSatellite()
        critRing:SetValue("42%")  -- placeholder, will be dynamic later
        critRing:PlayProc()
    end
end

-- /wfcrit — toggle crit ring test
SLASH_WFCRIT1 = "/wfcrit"
SlashCmdList["WFCRIT"] = function()
    local f = GetCritRing()
    if f:IsShown() then
        f:HideSatellite()
    else
        f:ShowSatellite()
        f:SetValue("42%")
    end
end

-- /wfcritproc — play crit ring proc animation
SLASH_WFCRITPROC1 = "/wfcritproc"
SlashCmdList["WFCRITPROC"] = function()
    local f = GetCritRing()
    f:ShowSatellite()
    f:SetValue("42%")
    f:PlayProc()
end
