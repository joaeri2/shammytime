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

-- Distance from center ring center to satellite center (smaller = closer to center)
local SATELLITE_RADIUS = 120

-- Satellite text: font + X,Y position within each circle (pixels from center)
-- +X = right, +Y = up. Tweak these to center text in each ring (designs vary slightly).
local SATELLITE_FONT = {
    path   = "Fonts\\FRIZQT__.TTF",
    labelSize = 9,
    valueSize = 14,
    outline = "OUTLINE",
    -- Label (e.g. "PROCS", "CRIT%") position in circle:
    labelX = 0,
    labelY = 8,
    -- Value (e.g. "216", "8.3%") position in circle:
    valueX = 0,
    valueY = -6,
}

-- Positions: 8 o'clock to 4 o'clock (16) over the top; 0 = 3 o'clock, CCW
-- Arc 210° (8) → 330° (4) over top = 240°; 6 rings → 5 gaps = 48° apart
local SATELLITE_POSITIONS = {
    MIN    = 210,  -- 8 o'clock
    AVG    = 162,  -- 9–10
    PROCS  = 114,  -- 10–11 (was MAX)
    CRIT   = 66,   -- 11–12
    PROCPCT = 18,  -- 12–1
    MAX    = 330,  -- 4 o'clock (16) (was PROCS)
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
-- nudgeX, nudgeY = optional pixel nudge for circle position
-- textLabelX, textLabelY, textValueX, textValueY = optional text position within circle (+Y = up)
local function CreateSatelliteRing(name, textures, label, position, parentFrame, nudgeX, nudgeY, textLabelX, textLabelY, textValueX, textValueY)
    if satelliteFrames[name] then return satelliteFrames[name] end
    if not parentFrame then return nil end

    local angle = math.rad(position)
    local offsetX = SATELLITE_RADIUS * math.cos(angle) + (nudgeX or 0)
    local offsetY = SATELLITE_RADIUS * math.sin(angle) + (nudgeY or 0)

    -- Parent to center so we scale and move as one object; resize keeps satellites connected
    local f = CreateFrame("Frame", "ShammyTimeSatellite_" .. name, parentFrame)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(5)
    f:SetSize(SATELLITE_SIZE, SATELLITE_SIZE)
    f:SetScale(SATELLITE_SCALE)
    f:SetPoint("CENTER", parentFrame, "CENTER", offsetX, offsetY)
    f:EnableMouse(false)  -- no drag on satellites; only center is movable
    f:Hide()

    if textures.full then
        -- Full-design: single texture (no layers)
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints(f)
        f.bg:SetTexture(textures.full)
        f.bg:SetAlpha(1)
        f.glow = nil  -- no glow layer for full-design
        f.border = nil
    else
        -- Layered: shadow, bg, glow, border
        if textures.shadow then
            f.shadow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
            f.shadow:SetSize(SATELLITE_SIZE, SATELLITE_SIZE)
            f.shadow:SetPoint("CENTER", 0, 0)
            f.shadow:SetTexture(textures.shadow)
            f.shadow:SetAlpha(0.22)
        end

        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints(f)
        f.bg:SetTexture(textures.bg)
        f.bg:SetAlpha(1)

        f.glow = f:CreateTexture(nil, "ARTWORK", nil, 1)
        f.glow:SetAllPoints(f)
        f.glow:SetTexture(textures.glow)
        f.glow:SetAlpha(0.05)
        f.glow:SetBlendMode("ADD")

        f.border = f:CreateTexture(nil, "OVERLAY")
        f.border:SetAllPoints(f)
        f.border:SetTexture(textures.border)
        f.border:SetAlpha(1)
    end

    -- Text as child of satellite so it scales with the ring when radial is resized
    local textFrame = CreateFrame("Frame", "ShammyTimeSatelliteText_" .. name, f)
    textFrame:SetFrameStrata("DIALOG")
    textFrame:SetFrameLevel(10)
    textFrame:SetSize(SATELLITE_SIZE, SATELLITE_SIZE)
    textFrame:SetPoint("CENTER", f, "CENTER", 0, 0)
    textFrame:EnableMouse(false)  -- drag passes through to center
    textFrame:Hide()
    f.textFrame = textFrame

    local lx = textLabelX ~= nil and textLabelX or (SATELLITE_FONT.labelX or 0)
    local ly = textLabelY ~= nil and textLabelY or (SATELLITE_FONT.labelY or 8)
    local vx = textValueX ~= nil and textValueX or (SATELLITE_FONT.valueX or 0)
    local vy = textValueY ~= nil and textValueY or (SATELLITE_FONT.valueY or -6)
    f.label = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("CENTER", lx, ly)
    f.label:SetText(label or "")
    f.label:SetTextColor(0.9, 0.85, 0.7)
    f.label:SetFont(SATELLITE_FONT.path, SATELLITE_FONT.labelSize, SATELLITE_FONT.outline or "")
    f.labelRestColor = {0.9, 0.85, 0.7}
    f.labelFlashColor = {1, 1, 1}

    f.value = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.value:SetPoint("CENTER", vx, vy)
    f.value:SetText("0")
    f.value:SetTextColor(1, 1, 1)
    f.value:SetFont(SATELLITE_FONT.path, SATELLITE_FONT.valueSize, SATELLITE_FONT.outline or "")
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

        -- Glow (only if this satellite has a glow layer; full-design satellites don't)
        if frame.glow then
            local gFlash = g:CreateAnimation("Alpha")
            gFlash:SetTarget(frame.glow)
            gFlash:SetOrder(1)
            gFlash:SetDuration(0.02)
            gFlash:SetFromAlpha(0.05)
            gFlash:SetToAlpha(0.4)

            local gSoft = g:CreateAnimation("Alpha")
            gSoft:SetTarget(frame.glow)
            gSoft:SetOrder(2)
            gSoft:SetDuration(0.35)
            gSoft:SetFromAlpha(0.4)
            gSoft:SetToAlpha(0.05)
            gSoft:SetSmoothing("OUT")
        end

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
        if self.glow then self.glow:SetAlpha(0.05) end
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

-- Satellite config: 8 → 16 (4) o'clock over the top, 48° apart (MAX and PROCS swapped)
-- Optional: offsetX, offsetY = circle position nudge. textLabelY, textValueY = text position within circle (+Y = up).
local SATELLITE_CONFIG = {
    { name = "MIN",    label = "MIN",    position = 210,  value = "455",  tex = "AIR_FULL" },       -- 8 o'clock
    { name = "AVG",    label = "AVG",    position = 162,  value = "689",  tex = "AVG",    textLabelY = 14, textValueY = -2 },  -- text up a bit
    { name = "PROCS",  label = "PROCS",  position = 114,  value = "12",   tex = "PROCS" },          -- fire circle
    { name = "CRIT",   label = "CRIT%",  position = 66,   value = "42%",  tex = "GRASS_UPPER_RIGHT" },
    { name = "PROCPCT", label = "PROC%", position = 18,   value = "38%",  tex = "PROCPCT", offsetX = 8, offsetY = 10, textLabelY = 14, textValueY = -2 },  -- text up a bit
    { name = "MAX",    label = "MAX",    position = 330,  value = "1278", tex = "GRASS_FULL", textLabelY = 14, textValueY = -2 },  -- text up a bit
}

local function GetSatelliteTextureSet(texKey)
    -- Full-design (single texture): AIR_FULL, GRASS_FULL
    if TEX[texKey] then
        return { full = TEX[texKey] }
    end
    return {
        bg     = TEX[texKey .. "_BG"],
        border = TEX[texKey .. "_BORDER"],
        glow   = TEX[texKey .. "_GLOW"],
        shadow = TEX[texKey .. "_SHADOW"],
    }
end

-- Create a single satellite by name
local function GetSatellite(name)
    if satelliteFrames[name] then return satelliteFrames[name] end
    if ShammyTime.EnsureCenterRingExists then ShammyTime.EnsureCenterRingExists() end
    local centerFrame = GetCenterFrame()
    if not centerFrame then return nil end
    for _, cfg in ipairs(SATELLITE_CONFIG) do
        if cfg.name == name then
            local texSet = GetSatelliteTextureSet(cfg.tex)
            return CreateSatelliteRing(name, texSet, cfg.label, cfg.position, centerFrame, cfg.offsetX, cfg.offsetY, cfg.textLabelX, cfg.textLabelY, cfg.textValueX, cfg.textValueY)
        end
    end
    return nil
end

-- Create CRIT satellite ring (convenience)
local function GetCritRing()
    return GetSatellite("CRIT")
end

-- Create all 6 satellite rings (call once to ensure all exist)
local function EnsureAllSatellites()
    if ShammyTime.EnsureCenterRingExists then
        ShammyTime.EnsureCenterRingExists()
    end
    local centerFrame = GetCenterFrame()
    if not centerFrame then return end
    for _, cfg in ipairs(SATELLITE_CONFIG) do
        if not satelliteFrames[cfg.name] then
            local texSet = GetSatelliteTextureSet(cfg.tex)
            CreateSatelliteRing(cfg.name, texSet, cfg.label, cfg.position, centerFrame, cfg.offsetX, cfg.offsetY, cfg.textLabelX, cfg.textLabelY, cfg.textValueX, cfg.textValueY)
        end
    end
end

-- Show all 6 satellites with placeholder values
local function ShowAllSatellites()
    EnsureAllSatellites()
    for _, cfg in ipairs(SATELLITE_CONFIG) do
        local f = satelliteFrames[cfg.name]
        if f then
            f:SetValue(cfg.value)
            f:ShowSatellite()
        end
    end
end

-- Hide all 6 satellites
local function HideAllSatellites()
    for _, cfg in ipairs(SATELLITE_CONFIG) do
        local f = satelliteFrames[cfg.name]
        if f then f:HideSatellite() end
    end
end

-- Expose API for other files
ShammyTime.CreateSatelliteRing = CreateSatelliteRing
ShammyTime.GetSatelliteFrame = function(name) return satelliteFrames[name] end
ShammyTime.GetSatellite = GetSatellite
ShammyTime.SATELLITE_POSITIONS = SATELLITE_POSITIONS
ShammyTime.SATELLITE_CONFIG = SATELLITE_CONFIG
ShammyTime.ShowAllSatellites = ShowAllSatellites
ShammyTime.HideAllSatellites = HideAllSatellites

-- Map satellite name to stats key and formatter (must be above UpdateSatelliteValues so local is in scope)
local function GetSatelliteValueFromStats(name, stats)
    if not stats then return nil end
    if name == "MIN" then return stats.min and FormatNum(stats.min) or "–" end
    if name == "MAX" then return stats.max and FormatNum(stats.max) or "–" end
    if name == "AVG" then return stats.avg and FormatNum(stats.avg) or "–" end
    if name == "PROCS" then return tostring(stats.procCount or 0) end
    if name == "PROCPCT" then return (stats.procPct and ("%.1f%%"):format(stats.procPct)) or "–" end
    if name == "CRIT" then return (stats.critPct and ("%.0f%%"):format(stats.critPct)) or "–" end
    return nil
end

-- Update all satellite value text from stats (for show-on-load; stats = GetStatsForRadial return)
local function UpdateSatelliteValues(stats)
    for _, cfg in ipairs(SATELLITE_CONFIG) do
        local f = satelliteFrames[cfg.name]
        if f then
            local val = GetSatelliteValueFromStats(cfg.name, stats)
            f:SetValue(val or "–")
        end
    end
end
ShammyTime.UpdateSatelliteValues = UpdateSatelliteValues

-- Play center + all satellites with real Windfury stats; animate center + crit on proc
local originalPlayCenterRingProc = ShammyTime.PlayCenterRingProc
ShammyTime.PlayCenterRingProc = function(procTotal)
    if originalPlayCenterRingProc then
        originalPlayCenterRingProc(procTotal)
    end
    local stats = (ShammyTime_Windfury_GetStats and ShammyTime_Windfury_GetStats()) or nil
    ShowAllSatellites()
    for _, cfg in ipairs(SATELLITE_CONFIG) do
        local f = satelliteFrames[cfg.name]
        if f then
            local val = GetSatelliteValueFromStats(cfg.name, stats)
            f:SetValue(val or cfg.value)
        end
    end
    -- CRIT (upper right) is now 1 static texture — no proc animation
    local critRing = GetCritRing()
    if critRing then
        local critVal = GetSatelliteValueFromStats("CRIT", stats)
        critRing:SetValue(critVal or "–")
    end
end

-- /wfcrit — toggle crit ring only
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

-- /wfsatellites — toggle all 6 satellites (3 left, 3 right) with placeholder values
SLASH_WFSATELLITES1 = "/wfsatellites"
SlashCmdList["WFSATELLITES"] = function()
    EnsureAllSatellites()
    local anyShown = satelliteFrames.CRIT and satelliteFrames.CRIT:IsShown()
    if anyShown then
        HideAllSatellites()
    else
        ShowAllSatellites()
    end
end

-- /wfcritproc — show crit ring (no animation; CRIT is static full texture)
SLASH_WFCRITPROC1 = "/wfcritproc"
SlashCmdList["WFCRITPROC"] = function()
    local f = GetCritRing()
    f:ShowSatellite()
    f:SetValue("–")
end
