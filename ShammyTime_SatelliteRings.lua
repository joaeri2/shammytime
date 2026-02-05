-- ShammyTime_SatelliteRings.lua
-- Satellite rings around the center ring (CRIT%, MAX, MIN, AVG, PROCS, PROC%).
-- Reusable factory for creating satellite rings with same animation style as center.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local M = ShammyTime_Media
if not M then return end

local TEX = M.TEX

-- Satellite ring size: center is 20% larger (200), so satellites = 150 for even proportions
local SATELLITE_SIZE = 150
local SATELLITE_SCALE = 1.0

-- Bubble radius (half of SATELLITE_SIZE). Position = circleRadius + bubbleRadius + gap so bubbles touch circle when gap=0.
-- Scaling is applied only on the root (radialWrapper); children use fixed pixel offsets so nothing drifts on scale change.
local SATELLITE_HALF = 75  -- bubbleRadius = min(bubbleW,bubbleH)/2

local function GetSatelliteRadius()
    local centerSize = (ShammyTime.GetCenterSize and ShammyTime.GetCenterSize()) or 200
    local circleRadius = centerSize / 2
    local bubbleRadius = SATELLITE_HALF
    local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB() or {}
    local gap = db.wfSatelliteGap
    if gap == nil then gap = 0 end
    -- distance = circleRadius + bubbleRadius + gap (recompute on size/gap change; root scale preserves relationship)
    return circleRadius + bubbleRadius + gap
end

-- User scale for the small bubbles (0.1–3, default 1)
local function GetSatelliteBubbleScale()
    local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB() or {}
    local s = db.wfSatelliteBubbleScale
    if type(s) ~= "number" or s < 0.1 or s > 3 then return 1 end
    return s
end

-- Satellite text: font + X,Y position within each circle (pixels from center)
-- +X = right, +Y = up. Defaults to 0. Adjust via Developer panel, then export and update code.
local SATELLITE_FONT = {
    path   = "Fonts\\FRIZQT__.TTF",
    labelSize = 8,
    valueSize = 13,
    outline = "OUTLINE",
    labelX = 0,
    labelY = 0,
    valueX = 0,
    valueY = 0,
}

-- Effective text options for a satellite (global DB + per-bubble override). Returns labelSize, valueSize, labelX, labelY, valueX, valueY.
function ShammyTime.GetSatelliteTextOptions(bubbleName)
    local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB() or {}
    local o = db.wfSatelliteOverrides and db.wfSatelliteOverrides[bubbleName]
    local labelSize = (o and o.labelSize ~= nil) and o.labelSize or ((db.fontSatelliteLabel and db.fontSatelliteLabel >= 6 and db.fontSatelliteLabel <= 28) and db.fontSatelliteLabel or SATELLITE_FONT.labelSize)
    local valueSize = (o and o.valueSize ~= nil) and o.valueSize or ((db.fontSatelliteValue and db.fontSatelliteValue >= 6 and db.fontSatelliteValue <= 28) and db.fontSatelliteValue or SATELLITE_FONT.valueSize)
    local labelX = (o and o.labelX ~= nil) and o.labelX or (db.wfSatelliteLabelX ~= nil and db.wfSatelliteLabelX or SATELLITE_FONT.labelX)
    local labelY = (o and o.labelY ~= nil) and o.labelY or (db.wfSatelliteLabelY ~= nil and db.wfSatelliteLabelY or SATELLITE_FONT.labelY)
    local valueX = (o and o.valueX ~= nil) and o.valueX or (db.wfSatelliteValueX ~= nil and db.wfSatelliteValueX or SATELLITE_FONT.valueX)
    local valueY = (o and o.valueY ~= nil) and o.valueY or (db.wfSatelliteValueY ~= nil and db.wfSatelliteValueY or SATELLITE_FONT.valueY)
    return labelSize, valueSize, labelX, labelY, valueX, valueY
end

-- Positions: 6 satellites evenly around the circle (60° apart). 0° = 3 o'clock (right), angles counter-clockwise.
-- Layout: top-right=MAX(stone), mid-right=MIN(air), down-right=CRIT%(grass_2), down-left=PROC%(water), mid-left=PROCS(grass), upper-left=AVG(fire).
local SATELLITE_POSITIONS = {
    MIN    = 0,     -- mid-right   — air
    MAX    = 60,    -- top-right   — stone
    AVG    = 120,   -- upper-left  — fire
    PROCS  = 180,   -- mid-left    — grass
    PROCPCT = 240,  -- down-left   — water
    CRIT   = 300,   -- down-right  — grass_2
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
    local radius = GetSatelliteRadius()
    local offsetX = radius * math.cos(angle) + (nudgeX or 0)
    local offsetY = radius * math.sin(angle) + (nudgeY or 0)

    -- Parent to main center; base offsets stored so we can move satellites with the ring (rubber-band style)
    local f = CreateFrame("Frame", "ShammyTimeSatellite_" .. name, parentFrame)
    f.baseOffsetX = offsetX
    f.baseOffsetY = offsetY
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(5)
    f:SetSize(SATELLITE_SIZE, SATELLITE_SIZE)
    f:SetScale(GetSatelliteBubbleScale())
    -- Center (parent) has scale 1; use raw offsets so the whole radial scales as one with the wrapper
    f:SetPoint("CENTER", parentFrame, "CENTER", offsetX, offsetY)
    local dbLocked = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB().locked
    f:EnableMouse(not dbLocked)   -- hover for quick-peek; when locked, click-through
    f:EnableMouseWheel(false)
    f:Hide()
    f:SetScript("OnEnter", function()
        if ShammyTime.OnRadialHoverEnter then ShammyTime.OnRadialHoverEnter() end
    end)
    f:SetScript("OnLeave", function()
        if ShammyTime.OnRadialHoverLeave then ShammyTime.OnRadialHoverLeave() end
    end)

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
    textFrame:SetFrameStrata("MEDIUM")
    textFrame:SetFrameLevel(10)
    textFrame:SetSize(SATELLITE_SIZE, SATELLITE_SIZE)
    textFrame:SetPoint("CENTER", f, "CENTER", 0, 0)
    textFrame:EnableMouse(false)  -- drag passes through to center
    textFrame:Hide()
    f.textFrame = textFrame

    -- Fade-out animation for chain fade (next satellite starts when previous has 500ms left)
    local fadeOutAg = textFrame:CreateAnimationGroup()
    local aOut = fadeOutAg:CreateAnimation("Alpha")
    aOut:SetFromAlpha(1)
    aOut:SetToAlpha(0)
    aOut:SetDuration(0.7)
    aOut:SetSmoothing("OUT")
    fadeOutAg:SetScript("OnFinished", function()
        textFrame:SetAlpha(1)
        textFrame:Hide()
    end)
    textFrame.fadeOutAnim = fadeOutAg

    local labelSize, valueSize, lx, ly, vx, vy
    if ShammyTime.GetSatelliteTextOptions then
        labelSize, valueSize, lx, ly, vx, vy = ShammyTime.GetSatelliteTextOptions(name)
    else
        labelSize, valueSize = SATELLITE_FONT.labelSize, SATELLITE_FONT.valueSize
        lx = textLabelX ~= nil and textLabelX or (SATELLITE_FONT.labelX or 0)
        ly = textLabelY ~= nil and textLabelY or (SATELLITE_FONT.labelY or 8)
        vx = textValueX ~= nil and textValueX or (SATELLITE_FONT.valueX or 0)
        vy = textValueY ~= nil and textValueY or (SATELLITE_FONT.valueY or -6)
    end
    f.label = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("CENTER", lx, ly)
    f.label:SetText(label or "")
    f.label:SetTextColor(0.9, 0.85, 0.7)
    f.label:SetFont(SATELLITE_FONT.path, labelSize, SATELLITE_FONT.outline or "")
    f.labelRestColor = {0.9, 0.85, 0.7}
    f.labelFlashColor = {1, 1, 1}

    f.value = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.value:SetPoint("CENTER", vx, vy)
    f.value:SetText("0")
    f.value:SetTextColor(1, 1, 1)
    f.value:SetFont(SATELLITE_FONT.path, valueSize, SATELLITE_FONT.outline or "")
    f.valueRestColor = {1, 1, 1}
    f.valueFlashColor = {1, 1, 0.5}
    f.currentValue = nil  -- used to hide text when 0/empty

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

    -- Show satellite (ring always; text only if value is non-empty)
    function f:ShowSatellite()
        self:Show()
        local val = self.currentValue
        local empty = (val == nil or val == "" or val == "0" or val == "0%" or val == "–")
        local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB() or {}
        local showText = not empty and (db.wfAlwaysShowNumbers or ShammyTime.radialNumbersVisible)
        if showText then
            self.textFrame:Show()
        else
            self.textFrame:Hide()
        end
    end

    -- Hide satellite
    function f:HideSatellite()
        self:Hide()
        self.textFrame:Hide()
    end

    -- Set value text; if 0 or empty, hide text so satellite shows ring only (no numbers)
    function f:SetValue(val)
        self.currentValue = val
        local empty = (val == nil or val == "" or val == "0" or val == "0%" or val == "–")
        if empty then
            self.textFrame:Hide()
        else
            self.value:SetText(val)
            local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB() or {}
            local showText = (db.wfAlwaysShowNumbers or ShammyTime.radialNumbersVisible)
            if showText and self:IsShown() then
                self.textFrame:Show()
            else
                self.textFrame:Hide()
            end
        end
    end

    satelliteFrames[name] = f
    return f
end

-- Main center container (satellites parent here; we move them explicitly when ring scales)
local function GetCenterFrame()
    return _G["ShammyTimeCenterRing"]
end

-- Ring frame (we read its scale during proc to drive satellite positions)
local function GetCenterRingFrame()
    return ShammyTime.GetCenterRingFrame and ShammyTime.GetCenterRingFrame()
end

-- Satellite config (what controls what).
--
-- Each row here creates ONE satellite ring frame. The *ring art* (textures) and the *ring placement* are controlled
-- independently from the *text that is shown*:
--
-- - name:
--   - Unique id for the frame (stored in `satelliteFrames[name]`). Use GetSatellite(name) to get it.
--   - Named by *appearance* (same as `tex`): the ring is independent of which stat it displays.
--   - Does NOT have to match the stat being displayed (that's `statName`).
--
-- - position:
--   - Where the ring is placed around the center (degrees; 0 = right / 3 o’clock, counter-clockwise positive)
--   - This is the ONLY thing that changes the ring’s angular placement (media positions stay the same if this stays the same)
--
-- - tex:
--   - Which texture set/art is used for that ring (see `GetSatelliteTextureSet()`)
--   - Changing this swaps the ring art, but not its position
--
-- - label:
--   - The *top* text shown inside the ring (e.g. "MIN", "CRIT%")
--
-- - statName:
--   - Which stat value is shown as the *bottom* text (fed into `GetSatelliteValueFromStats(statName, stats)`)
--   - This is what we remap when you want to reorder text left-to-right without moving ring art
--
-- - value:
--   - Placeholder value used by `ShowAllSatellites()` (test / default display)
--
-- - offsetX / offsetY:
--   - Nudges the whole ring (and its text) by pixels AFTER the polar placement from `position`
--
-- - textLabelX / textLabelY, textValueX / textValueY:
--   - Pixel offsets of label/value relative to the ring center.
--   - If you want “no override”, set to 0 (which effectively uses the base placement plus 0 offset).
-- Layout: top-right=MAX(stone), mid-right=MIN(air), down-right=CRIT%(grass_2), down-left=PROC%(water), mid-left=PROCS(grass), upper-left=AVG(fire).
-- 0°=mid-right, 60°=top-right, 120°=upper-left, 180°=mid-left, 240°=down-left, 300°=down-right.
-- Text positions reset to 0 - adjust via Developer panel in /st options, then export settings.
local SATELLITE_CONFIG = {
    { name = "air",     position = 0,   tex = "AIR_FULL",          label = "MIN",   statName = "MIN",     value = "455",  offsetX = 0, offsetY = 0,  textLabelX = 0, textLabelY = 0, textValueX = 0, textValueY = 0 },
    { name = "stone",   position = 60,  tex = "AVG",               label = "MAX",   statName = "MAX",     value = "1278", offsetX = 0, offsetY = 0,  textLabelX = 0, textLabelY = 0, textValueX = 0, textValueY = 0 },
    { name = "fire",    position = 120, tex = "PROCS",             label = "AVG",   statName = "AVG",     value = "689",  offsetX = 0, offsetY = 0,  textLabelX = 0, textLabelY = 0, textValueX = 0, textValueY = 0 },
    { name = "grass",   position = 180, tex = "GRASS_UPPER_RIGHT", label = "PROCS", statName = "PROCS",   value = "12",   offsetX = 0, offsetY = 0,  textLabelX = 0, textLabelY = 0, textValueX = 0, textValueY = 0 },
    { name = "water",   position = 240, tex = "PROCPCT",           label = "PROC%", statName = "PROCPCT", value = "38%",  offsetX = 0, offsetY = 0,  textLabelX = 0, textLabelY = 0, textValueX = 0, textValueY = 0 },
    { name = "grass_2", position = 300, tex = "GRASS_FULL",        label = "CRIT%", statName = "CRIT",    value = "42%",  offsetX = 0, offsetY = 0,  textLabelX = 0, textLabelY = 0, textValueX = 0, textValueY = 0 },
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

-- Create a single satellite by name (parent = main center so we can move them with ring scale)
local function GetSatellite(name)
    if satelliteFrames[name] then return satelliteFrames[name] end
    if ShammyTime.EnsureCenterRingExists then ShammyTime.EnsureCenterRingExists() end
    local centerFrame = GetCenterFrame()
    if not centerFrame then return nil end
    for _, cfg in ipairs(SATELLITE_CONFIG) do
        if cfg.name == name then
            local texSet = GetSatelliteTextureSet(cfg.tex)
            local position = cfg.position or SATELLITE_POSITIONS[name] or 90
            return CreateSatelliteRing(name, texSet, cfg.label, position, centerFrame, cfg.offsetX, cfg.offsetY, cfg.textLabelX, cfg.textLabelY, cfg.textValueX, cfg.textValueY)
        end
    end
    return nil
end

-- Ring that displays CRIT% (grass_2 = wf_magic_gras / GRASS_FULL art)
local function GetCritRing()
    return GetSatellite("grass_2")
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
            local position = cfg.position or SATELLITE_POSITIONS[cfg.name] or 90
            CreateSatelliteRing(cfg.name, texSet, cfg.label, position, centerFrame, cfg.offsetX, cfg.offsetY, cfg.textLabelX, cfg.textLabelY, cfg.textValueX, cfg.textValueY)
        end
    end
end

-- Show all 6 satellites (no placeholder values)
local function ShowAllSatellites()
    EnsureAllSatellites()
    for _, cfg in ipairs(SATELLITE_CONFIG) do
        local f = satelliteFrames[cfg.name]
        if f then
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

-- Chain fade: order left (195°) → around → top (27°) → end (345°) = SATELLITE_CONFIG order
-- Next satellite starts when previous has 500ms left (stagger = 700 - 500 = 200ms)
local SATELLITE_FADE_DURATION = 0.7
local SATELLITE_FADE_STAGGER = 0.2  -- next starts when previous has 500ms left

function ShammyTime.StartSatelliteTextChainFade()
    ShammyTime.radialNumbersVisible = false
    EnsureAllSatellites()
    for i, cfg in ipairs(SATELLITE_CONFIG) do
        local f = satelliteFrames[cfg.name]
        if f and f.textFrame and f.textFrame:IsShown() and f.textFrame.fadeOutAnim then
            local delay = (i - 1) * SATELLITE_FADE_STAGGER
            C_Timer.After(delay, function()
                if not f or not f.textFrame or not f.textFrame.fadeOutAnim then return end
                f.textFrame.fadeOutAnim:Stop()
                f.textFrame:SetAlpha(1)
                f.textFrame.fadeOutAnim:Play()
            end)
        end
    end
end

-- Show all satellite text frames (for hover quick-peek)
function ShammyTime.ShowAllSatelliteTexts()
    ShammyTime.radialNumbersVisible = true
    for _, cfg in ipairs(SATELLITE_CONFIG) do
        local f = satelliteFrames[cfg.name]
        if f and f:IsShown() and f.textFrame then
            if f.textFrame.fadeOutAnim then f.textFrame.fadeOutAnim:Stop() end
            f.textFrame:SetAlpha(1)
            f.textFrame:Show()
        end
    end
end

-- Hide all satellite text frames (after hover leave or chain fade)
function ShammyTime.HideAllSatelliteTexts()
    ShammyTime.radialNumbersVisible = false
    for _, cfg in ipairs(SATELLITE_CONFIG) do
        local f = satelliteFrames[cfg.name]
        if f and f.textFrame then
            if f.textFrame.fadeOutAnim then f.textFrame.fadeOutAnim:Stop() end
            f.textFrame:SetAlpha(1)
            f.textFrame:Hide()
        end
    end
end

-- Ring proc peak scale (must match CenterRing pop) for satellite "pop out" scaling
local PROC_POP_SCALE = 1.18

-- Called every frame during center ring proc: move satellites outward + scale up 10% (rubber-band + pop toward player)
function ShammyTime.OnRingProcScaleUpdate(scale)
    local centerFrame = GetCenterFrame()
    if not centerFrame then return end
    local centerScale = centerFrame:GetScale()
    if not centerScale or centerScale <= 0 then centerScale = 1 end
    -- Satellite visual scale: base at rest, 10% bigger at proc peak (pop toward player)
    local scaleFactor = 1 + 0.1 * (scale - 1) / (PROC_POP_SCALE - 1)
    local satelliteScale = GetSatelliteBubbleScale() * scaleFactor
    for _, f in pairs(satelliteFrames) do
        if f and f.baseOffsetX then
            -- Rest position is baseOffset/centerScale; during proc expand by scale
            local x = (f.baseOffsetX / centerScale) * scale
            local y = (f.baseOffsetY / centerScale) * scale
            f:SetPoint("CENTER", centerFrame, "CENTER", x, y)
            f:SetScale(satelliteScale)
        end
    end
end

-- Reset satellite positions and scale to base when proc animation finishes or stops
function ShammyTime.ResetSatellitePositions()
    local centerFrame = GetCenterFrame()
    if not centerFrame then return end
    local centerScale = centerFrame and centerFrame:GetScale() or 1
    for _, f in pairs(satelliteFrames) do
        if f and f.baseOffsetX then
            local sx = (centerScale and centerScale > 0) and (f.baseOffsetX / centerScale) or f.baseOffsetX
            local sy = (centerScale and centerScale > 0) and (f.baseOffsetY / centerScale) or f.baseOffsetY
            f:SetPoint("CENTER", centerFrame, "CENTER", sx, sy)
            f:SetScale(GetSatelliteBubbleScale())
        end
    end
end

-- Re-position satellites. Scale is on the radial wrapper (center has scale 1), so use raw base offsets.
-- centerScale is only used when caller still uses old per-center scale; pass 1 for wrapper-based scaling.
function ShammyTime.ApplySatellitePositionsForCenterScale(centerScale)
    local centerFrame = GetCenterFrame()
    if not centerFrame then return end
    local div = (centerScale and centerScale > 0) and centerScale or 1
    for _, f in pairs(satelliteFrames) do
        if f and f.baseOffsetX ~= nil and f.baseOffsetY ~= nil then
            local sx = f.baseOffsetX / div
            local sy = f.baseOffsetY / div
            f:SetPoint("CENTER", centerFrame, "CENTER", sx, sy)
        end
    end
end

-- Reapply satellite bubble scale from DB (call when user changes Developer option)
function ShammyTime.ApplySatelliteBubbleScale()
    local baseScale = GetSatelliteBubbleScale()
    for _, f in pairs(satelliteFrames) do
        if f then f:SetScale(baseScale) end
    end
end

-- Reapply satellite radius from DB and move all outer bubbles (call when user changes /st circle gap N)
function ShammyTime.ApplySatelliteRadius()
    local centerFrame = GetCenterFrame()
    if not centerFrame then return end
    local radius = GetSatelliteRadius()
    local centerScale = centerFrame:GetScale()
    if not centerScale or centerScale <= 0 then centerScale = 1 end
    for _, f in pairs(satelliteFrames) do
        if f and f.baseOffsetX ~= nil and f.baseOffsetY ~= nil then
            local angle = math.atan2(f.baseOffsetY, f.baseOffsetX)
            f.baseOffsetX = radius * math.cos(angle)
            f.baseOffsetY = radius * math.sin(angle)
            f:SetPoint("CENTER", centerFrame, "CENTER", f.baseOffsetX / centerScale, f.baseOffsetY / centerScale)
        end
    end
end

-- Set alpha on all satellite frames (for fade-out-of-combat / fade-when-not-procced)
function ShammyTime.SetSatelliteFadeAlpha(alpha)
    for _, f in pairs(satelliteFrames) do
        if f and f.SetAlpha then
            -- If a previous fade animation is still running, stop it so satellites snap visible on proc.
            if f._stFadeAg then
                f._stFadeAg:Stop()
                f._stFadeAg = nil
            end
            f:SetAlpha(alpha)
        end
    end
end

-- Set EnableMouse on all satellite frames (when locked, click-through)
function ShammyTime.SetSatellitesEnableMouse(enable)
    for _, f in pairs(satelliteFrames) do
        if f and f.EnableMouse then f:EnableMouse(enable) end
    end
end

-- Animate all satellite frames to target alpha over duration (0 = instant). Uses ShammyTime.AnimateFrameToAlpha when duration > 0.
function ShammyTime.AnimateSatellitesToAlpha(targetAlpha, duration)
    if not duration or duration <= 0 then
        if ShammyTime.SetSatelliteFadeAlpha then ShammyTime.SetSatelliteFadeAlpha(targetAlpha) end
        return
    end
    local anim = ShammyTime.AnimateFrameToAlpha
    if not anim then
        if ShammyTime.SetSatelliteFadeAlpha then ShammyTime.SetSatelliteFadeAlpha(targetAlpha) end
        return
    end
    for _, f in pairs(satelliteFrames) do
        if f then anim(f, targetAlpha, duration) end
    end
end

-- Apply font sizes and text position from DB to all satellite text (called when user changes bubbles outer font/pos).
function ShammyTime.ApplySatelliteFontSizes()
    for bubbleName, f in pairs(satelliteFrames) do
        if f and f.label and f.value and ShammyTime.GetSatelliteTextOptions then
            local labelSize, valueSize, lx, ly, vx, vy = ShammyTime.GetSatelliteTextOptions(bubbleName)
            f.label:SetFont(SATELLITE_FONT.path, labelSize, SATELLITE_FONT.outline or "")
            f.value:SetFont(SATELLITE_FONT.path, valueSize, SATELLITE_FONT.outline or "")
            f.label:SetPoint("CENTER", lx, ly)
            f.value:SetPoint("CENTER", vx, vy)
        end
    end
end

-- Apply only text position from DB (when only position changed).
function ShammyTime.ApplySatelliteTextPosition()
    for bubbleName, f in pairs(satelliteFrames) do
        if f and f.label and f.value and ShammyTime.GetSatelliteTextOptions then
            local _, _, lx, ly, vx, vy = ShammyTime.GetSatelliteTextOptions(bubbleName)
            f.label:SetPoint("CENTER", lx, ly)
            f.value:SetPoint("CENTER", vx, vy)
        end
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
    if name == "PROCPCT" then return (stats.procPct and ("%.0f%%"):format(stats.procPct)) or "–" end
    if name == "CRIT" then return (stats.critPct and ("%.0f%%"):format(stats.critPct)) or "–" end
    return nil
end

-- Update all satellite value text from stats (for show-on-load; stats = GetStatsForRadial return)
local function UpdateSatelliteValues(stats)
    for _, cfg in ipairs(SATELLITE_CONFIG) do
        local f = satelliteFrames[cfg.name]
        if f then
            local val = GetSatelliteValueFromStats(cfg.statName or cfg.name, stats)
            f:SetValue(val or "–")
        end
    end
end
ShammyTime.UpdateSatelliteValues = UpdateSatelliteValues

-- Play center + all satellites with real Windfury stats; animate center + crit on proc
local originalPlayCenterRingProc = ShammyTime.PlayCenterRingProc
ShammyTime.PlayCenterRingProc = function(procTotal, forceShow)
    local stats = (ShammyTime_Windfury_GetStats and ShammyTime_Windfury_GetStats()) or nil
    ShammyTime.radialNumbersVisible = true
    -- Create and show satellites before playing proc so they exist when ring scale drives their position
    ShowAllSatellites()
    for _, cfg in ipairs(SATELLITE_CONFIG) do
        local f = satelliteFrames[cfg.name]
        if f then
            local val = GetSatelliteValueFromStats(cfg.statName or cfg.name, stats)
            f:SetValue(val)
        end
    end
    local critRing = GetCritRing()
    if critRing then
        critRing:SetValue(GetSatelliteValueFromStats("CRIT", stats) or "–")
    end
    if originalPlayCenterRingProc then
        originalPlayCenterRingProc(procTotal, forceShow)
    end
end

-- Expose for /st satellites
function ShammyTime.ToggleSatelliteCrit()
    local f = GetCritRing()
    if f:IsShown() then
        f:HideSatellite()
    else
        f:ShowSatellite()
        f:SetValue("42%")
    end
end

function ShammyTime.ToggleSatellites()
    EnsureAllSatellites()
    local anyShown = satelliteFrames.CRIT and satelliteFrames.CRIT:IsShown()
    if anyShown then
        HideAllSatellites()
    else
        ShowAllSatellites()
    end
end

function ShammyTime.ShowSatelliteCritProc()
    local f = GetCritRing()
    f:ShowSatellite()
    f:SetValue("–")
end
