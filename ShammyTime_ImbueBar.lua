-- ShammyTime_ImbueBar.lua
-- Movable weapon imbue bar (512×512, layered back/front): left = main hand, right = off hand.
-- Draw order: layer 1 = back, 2 = imbue icons, 3 = front texture, 4 = timer text.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local FormatTime = ShammyTime.FormatTime
local GetWeaponImbuePerHand = ShammyTime.GetWeaponImbuePerHand
local GetElementalShieldAura = ShammyTime.GetElementalShieldAura
local GetRadialPositionDB = ShammyTime.GetRadialPositionDB
local function GetDB()
    local st = _G.ShammyTime
    if st and st.GetDB then
        return st.GetDB()
    end
    return {}
end

-- Layout: 512×512 art, cropped vertically (same approach as totem bar)
local BAR_W = 286
local CROP_TOP = 0.15      -- skip top 30% of texture (empty)
local CROP_BOTTOM = 0.85   -- skip bottom 30% of texture (empty)
local BAR_H = math.floor(BAR_W * (CROP_BOTTOM - CROP_TOP) + 0.5)
local DEFAULT_IMBUE_BAR_SCALE = 0.85

-- ═══ IMBUE ICON LAYOUT (adjust live with /st imbue) ═══
local ICONS_X = 0           -- horizontal offset for both icons (positive = right)
local ICONS_Y = 0           -- vertical offset from center (negative = down)
local ICONS_SPREAD = 1.45    -- spread multiplier (1.0 = default; <1 = tighter; >1 = wider)
local ICON_SIZE = 57         -- icon width & height in pixels
local TIMER_OFFSET_X = 0    -- timer text horizontal offset from icon center (positive = right)
local TIMER_OFFSET_Y = -20  -- timer text offset below icon center (negative = down)
-- ═══════════════════════════════════════════════════════════════════════
local TIMER_FONT_SIZE = 16
local BASE_GAP = 60         -- default pixel gap between icon centers at spread 1.0
local ICON_ALPHA_ACTIVE = 0.9
local ICON_ALPHA_EMPTY = 0
local TIMER_COLOR = { 0.88, 0.86, 0.82 }
local EMPTY_ICON = 135847  -- Frostbrand-style empty slot

-- Elemental shield (Lightning Shield / Water Shield): off texture base, on texture fades in with alpha when active; orb count 1–3.
-- Assets are 256×256 (square); no crop needed.
local SHIELD_GAP = 16
local SHIELD_TEX_W = 256
local SHIELD_TEX_H = 256
local SHIELD_ICON_SIZE = SHIELD_TEX_H -- square output size
local SHIELD_TEX_CROP_LEFT = 0
local SHIELD_TEX_CROP_RIGHT = 1
local SHIELD_FADE_DURATION = 0.25  -- seconds for "on" overlay to fade in/out (light turning on/off)
local SHIELD_COUNT_FONT_SIZE = 86  -- orb count (1–3) text default
local SHIELD_COUNT_COLOR = { 0.95, 0.9, 0.7 }  -- light gold for count

local function GetImbueFontSize(db)
    db = db or (GetDB and GetDB() or {})
    return (db.fontImbueTimer and db.fontImbueTimer >= 6 and db.fontImbueTimer <= 64) and db.fontImbueTimer or TIMER_FONT_SIZE
end

local function GetImbueTextOffsetX(db)
    db = db or (GetDB and GetDB() or {})
    return (db.imbueTextX and type(db.imbueTextX) == "number") and db.imbueTextX or TIMER_OFFSET_X
end

local function GetImbueTextOffsetY(db)
    db = db or (GetDB and GetDB() or {})
    return (db.imbueTextY and type(db.imbueTextY) == "number") and db.imbueTextY or TIMER_OFFSET_Y
end

local function GetShieldCountFontSize(db)
    db = db or (GetDB and GetDB() or {})
    return (db.fontShieldCount and db.fontShieldCount >= 6 and db.fontShieldCount <= 200) and db.fontShieldCount or SHIELD_COUNT_FONT_SIZE
end

local imbueBarFrame
local slots = {}  -- [1] = MH, [2] = OH
local shieldFrame  -- elemental shield indicator (off/on overlay + orb count)
local shieldAlphaTicker = nil  -- smooth fade for "on" overlay
local updateTicker
-- Pulse when no imbues for 15 sec (remind player); pulse for 15 sec then stop. Removal = stay still (reset delay).
local IMBUE_PULSE_DELAY = 15
local IMBUE_PULSE_DURATION = 15   -- pulse for this long, then stop until they have imbue again
local IMBUE_PULSE_MIN = 0.90
local IMBUE_PULSE_MAX = 1.0
local IMBUE_PULSE_PERIOD = 1.0    -- seconds per full cycle (90% <-> 100%, like Shamanistic Focus)
local noImbueSince = nil          -- when we first had no imbues; nil when we have an imbue
local hadImbueLastCheck = false   -- true if previous tick had imbue (so removal = stay still)
local imbuePulseCooldown = false  -- true after we pulsed for 15 sec; reset when they get an imbue

-- Compute icon X position (i = 1 for MH, 2 for OH), centered in bar
local function SlotX(i)
    local offset = (i - 1.5) * BASE_GAP * ICONS_SPREAD
    return BAR_W / 2 + ICONS_X + offset
end

-- Default position for imbue bar (when no saved position exists)
local IMBUE_DEFAULT_X, IMBUE_DEFAULT_Y = 0, -260

-- Saves the imbue bar position when the user stops dragging (exact CenterRing pattern).
local function SaveImbueBarPosition(frame)
    if not ShammyTime.GetRadialPositionDB then return end
    local pos = ShammyTime.GetRadialPositionDB()
    local point, relTo, relativePoint, x, y = frame:GetPoint(1)
    if not point then return end
    pos.imbueBar = {
        point = point,
        relativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent",
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

-- Applies saved position to the imbue bar frame (exact CenterRing pattern).
local function ApplyImbueBarPosition(frame)
    local pos = ShammyTime.GetRadialPositionDB and ShammyTime.GetRadialPositionDB()
    if not pos then return end
    frame:ClearAllPoints()
    if pos.imbueBar then
        local t = pos.imbueBar
        local relTo = (t.relativeTo and _G[t.relativeTo]) or UIParent
        if relTo then
            frame:SetPoint(t.point or "CENTER", relTo, t.relativePoint or "CENTER", t.x or 0, t.y or 0)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", IMBUE_DEFAULT_X, IMBUE_DEFAULT_Y)
        end
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", IMBUE_DEFAULT_X, IMBUE_DEFAULT_Y)
        SaveImbueBarPosition(frame)
    end
end

-- Global wrapper for repositioning imbue bar after scale change
function ShammyTime.ApplyImbueBarPosition()
    local f = _G.ShammyTimeImbueBarFrame
    if f then ApplyImbueBarPosition(f) end
end

local DEFAULT_SHIELD_SCALE = 0.4

-- Default position for shield (when no saved position exists)
local SHIELD_DEFAULT_X, SHIELD_DEFAULT_Y = 250, -180

-- Saves the shield position when the user stops dragging (exact CenterRing pattern).
local function SaveShieldPosition(frame)
    if not ShammyTime.GetRadialPositionDB then return end
    local pos = ShammyTime.GetRadialPositionDB()
    local point, relTo, relativePoint, x, y = frame:GetPoint(1)
    if not point then return end
    pos.shieldFrame = {
        point = point,
        relativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent",
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

-- Applies saved position to the shield frame (exact CenterRing pattern).
local function ApplyShieldPosition(frame)
    local pos = ShammyTime.GetRadialPositionDB and ShammyTime.GetRadialPositionDB()
    if not pos then return end
    frame:ClearAllPoints()
    if pos.shieldFrame then
        local t = pos.shieldFrame
        local relTo = (t.relativeTo and _G[t.relativeTo]) or UIParent
        if relTo then
            frame:SetPoint(t.point or "CENTER", relTo, t.relativePoint or "CENTER", t.x or 0, t.y or 0)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", SHIELD_DEFAULT_X, SHIELD_DEFAULT_Y)
        end
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", SHIELD_DEFAULT_X, SHIELD_DEFAULT_Y)
        SaveShieldPosition(frame)
    end
end

local function SetSlotTexture(icon, iconData)
    if not icon then return end
    local tex = iconData
    if type(tex) == "number" then
        icon:SetTexture(tex)
    else
        icon:SetTexture(tex or EMPTY_ICON)
    end
end

local function RenderImbueSlot(slotData, data)
    if not slotData then return end
    local iconFrame = slotData.iconFrame
    local textFrame = slotData.textFrame
    local icon = iconFrame and iconFrame.icon
    local timerText = textFrame and textFrame.timerText

    if data and data.expirationTime and (data.expirationTime - GetTime()) > 0 then
        local tex = (data.spellId and GetSpellTexture and GetSpellTexture(data.spellId)) or data.icon
        SetSlotTexture(icon, tex or EMPTY_ICON)
        icon:SetVertexColor(1, 1, 1)
        icon:SetAlpha(ICON_ALPHA_ACTIVE)
        if icon.SetDesaturated then icon:SetDesaturated(false) end
        icon:Show()
        local remaining = data.expirationTime - GetTime()
        if timerText then
            timerText:SetText(FormatTime(remaining))
            timerText:SetTextColor(TIMER_COLOR[1], TIMER_COLOR[2], TIMER_COLOR[3])
            timerText:Show()
        end
    else
        -- Empty slot: clear texture and alpha so no stale icon blinks during bar fade-in
        icon:SetTexture(nil)
        icon:SetAlpha(0)
        icon:Hide()
        if timerText then
            timerText:SetText("")
            timerText:Hide()
        end
    end
end

local function HasAnyImbue()
    local perHand = GetWeaponImbuePerHand and GetWeaponImbuePerHand()
    if not perHand then return false end
    return (perHand.mainHand and perHand.mainHand.expirationTime and (perHand.mainHand.expirationTime - GetTime()) > 0)
        or (perHand.offHand and perHand.offHand.expirationTime and (perHand.offHand.expirationTime - GetTime()) > 0)
end

local function StopShieldAlphaTicker()
    if shieldAlphaTicker then
        shieldAlphaTicker:Cancel()
        shieldAlphaTicker = nil
    end
end

-- Update elemental shield indicator: off texture always visible; on texture fades in when Lightning/Water Shield active; show orb count (1–3).
local function UpdateShieldIndicator()
    if not shieldFrame or not shieldFrame.shieldOn or not shieldFrame.shieldOff then return end
    if not GetElementalShieldAura then return end

    local icon, count, duration, expTime, spellId, fallbackIcon = GetElementalShieldAura()
    local hasShield = (icon or fallbackIcon) and true
    -- TBC: Lightning Shield and Water Shield have 1–3 orbs (UnitAura stack count); 0 when all consumed but aura may still be present
    count = (type(count) == "number" and count >= 0 and count <= 9) and count or (hasShield and 3 or 0)

    -- Override count from DB if set (shieldCount = 1–9 means fixed display; nil = auto from buff)
    local db = GetDB and GetDB() or {}
    if db.shieldCount and type(db.shieldCount) == "number" and db.shieldCount >= 1 and db.shieldCount <= 9 then
        count = db.shieldCount
    end

    local onTex = shieldFrame.shieldOn
    local currentAlpha = onTex:GetAlpha() or 0
    local targetAlpha = hasShield and 1 or 0

    -- Orb count: show when shield active (0–9 for Lightning/Water Shield, or override)
    if shieldFrame.countText then
        if hasShield then
            shieldFrame.countText:SetText(tostring(count))
            shieldFrame.countText:SetTextColor(SHIELD_COUNT_COLOR[1], SHIELD_COUNT_COLOR[2], SHIELD_COUNT_COLOR[3])
            shieldFrame.countText:Show()
        else
            shieldFrame.countText:SetText("")
            shieldFrame.countText:Hide()
        end
    end

    -- Already at target (or very close)
    if math.abs(currentAlpha - targetAlpha) < 0.02 then
        onTex:SetAlpha(targetAlpha)
        StopShieldAlphaTicker()
        return
    end

    -- Smooth fade: run ticker if not already running
    if shieldAlphaTicker then return end
    local startAlpha = currentAlpha
    local startTime = GetTime()
    shieldAlphaTicker = C_Timer.NewTicker(1/60, function()
        local t = (GetTime() - startTime) / SHIELD_FADE_DURATION
        if t >= 1 then
            onTex:SetAlpha(targetAlpha)
            StopShieldAlphaTicker()
            return
        end
        onTex:SetAlpha(startAlpha + (targetAlpha - startAlpha) * t)
    end)
end

local function UpdateImbueBar()
    if not imbueBarFrame or not imbueBarFrame:IsShown() then return end
    local perHand = GetWeaponImbuePerHand and GetWeaponImbuePerHand()
    if not perHand then return end
    RenderImbueSlot(slots[1], perHand.mainHand)
    RenderImbueSlot(slots[2], perHand.offHand)
    UpdateShieldIndicator()

    local db = GetDB and GetDB() or {}
    local imbueFontSz = GetImbueFontSize(db)
    if imbueBarFrame and imbueBarFrame.lastImbueFontSize ~= imbueFontSz then
        if ShammyTime.ApplyImbueBarFontSize then ShammyTime.ApplyImbueBarFontSize() end
    end
    local shieldFontSz = GetShieldCountFontSize(db)
    if shieldFrame and shieldFrame.lastShieldCountFontSize ~= shieldFontSz then
        if ShammyTime.ApplyShieldCountSettings then ShammyTime.ApplyShieldCountSettings() end
    end

    -- No-imbue pulse: only if no imbue for 15 sec (never applied / expired); pulse 15 sec then stop. Removal = stay still.
    local hasImbue = HasAnyImbue()
    if hasImbue then
        noImbueSince = nil
        hadImbueLastCheck = true
        imbuePulseCooldown = false
        if imbueBarFrame.stopImbuePulseTicker then imbueBarFrame.stopImbuePulseTicker() end
    else
        local now = GetTime()
        if hadImbueLastCheck then
            -- Just removed imbue: stay still, restart 15 sec delay
            noImbueSince = now
            hadImbueLastCheck = false
            if imbueBarFrame.stopImbuePulseTicker then imbueBarFrame.stopImbuePulseTicker() end
        else
            if noImbueSince == nil then
                noImbueSince = now
            end
            if not imbuePulseCooldown and (now - noImbueSince) >= IMBUE_PULSE_DELAY then
                if imbueBarFrame.startImbuePulse and not imbueBarFrame.imbuePulseTicker then
                    imbueBarFrame.startImbuePulse(now + IMBUE_PULSE_DURATION)
                end
            end
            hadImbueLastCheck = false
        end
    end
end

local function CreateImbueBarFrame()
    if imbueBarFrame then return imbueBarFrame end

    local f = CreateFrame("Frame", "ShammyTimeImbueBarFrame", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetSize(BAR_W, BAR_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -260)
    ApplyImbueBarPosition(f)
    local scale = (GetDB and GetDB().imbueBarScale) or DEFAULT_IMBUE_BAR_SCALE
    f:SetScale(scale)
    f.baseScale = scale
    f.imbuePulseTicker = nil
    -- Content frame: bar + slots live here; we pulse its scale (0.9–1.0) so the bar stays in place (no diagonal movement).
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("CENTER", f, "CENTER", 0, 0)
    content:SetSize(BAR_W, BAR_H)
    f.content = content
    local function stopImbuePulseTicker()
        if f.imbuePulseTicker then
            f.imbuePulseTicker:Cancel()
            f.imbuePulseTicker = nil
        end
        f.content:SetScale(1)
    end
    local function startImbuePulse(pulseEndTime)
        stopImbuePulseTicker()
        f.imbuePulseTicker = C_Timer.NewTicker(1/60, function()
            if not f.imbuePulseTicker then return end
            local now = GetTime()
            if pulseEndTime and now >= pulseEndTime then
                f.imbuePulseTicker:Cancel()
                f.imbuePulseTicker = nil
                imbuePulseCooldown = true
                f.content:SetScale(1)
                return
            end
            local t = now % IMBUE_PULSE_PERIOD
            local phase = t / IMBUE_PULSE_PERIOD
            local pulseScale = (phase <= 0.5) and (IMBUE_PULSE_MAX - (IMBUE_PULSE_MAX - IMBUE_PULSE_MIN) * 2 * phase)
                or (IMBUE_PULSE_MIN + (IMBUE_PULSE_MAX - IMBUE_PULSE_MIN) * 2 * (phase - 0.5))
            f.content:SetScale(pulseScale)
        end)
    end
    f.stopImbuePulseTicker = stopImbuePulseTicker
    f.startImbuePulse = startImbuePulse
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(not (GetDB and GetDB().locked))
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if GetDB and GetDB().locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveImbueBarPosition(self)
    end)

    local M = ShammyTime_Media
    local centerY = BAR_H / 2 + ICONS_Y
    local baseLevel = content:GetFrameLevel() + 1

    -- Layer 1: back texture
    f.bg = content:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(content)
    if M and M.TEX and M.TEX.IMBUE_BAR_BACK then
        f.bg:SetTexture(M.TEX.IMBUE_BAR_BACK)
    end
    f.bg:SetTexCoord(0, 1, CROP_TOP, CROP_BOTTOM)
    f.bg:SetAlpha(1)
    f.cropTop = CROP_TOP
    f.cropBottom = CROP_BOTTOM

    -- Layer 2: icon layer (2 icon frames, no text)
    local iconLayer = CreateFrame("Frame", "ShammyTimeImbueBarIconLayer", content)
    iconLayer:SetAllPoints(content)
    iconLayer:SetFrameLevel(baseLevel)
    iconLayer:EnableMouse(false)

    for i = 1, 2 do
        local cx = SlotX(i)
        local iconFrame = CreateFrame("Frame", ("ShammyTimeImbueBarSlot%dIcon"):format(i), iconLayer)
        iconFrame:SetFrameLevel(baseLevel)  -- keep below front
        iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
        iconFrame:SetPoint("CENTER", iconLayer, "BOTTOMLEFT", cx, centerY)
        iconFrame:EnableMouse(false)

        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("CENTER")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconFrame.icon = icon

        slots[i] = { iconFrame = iconFrame }
    end

    -- Layer 3: front texture (draws on top of icons, below text)
    local frontFrame = CreateFrame("Frame", "ShammyTimeImbueBarFrontLayer", content)
    frontFrame:SetAllPoints(content)
    frontFrame:SetFrameLevel(baseLevel + 1)
    frontFrame:EnableMouse(false)
    if M and M.TEX and M.TEX.IMBUE_BAR_FRONT then
        local frontTex = frontFrame:CreateTexture(nil, "ARTWORK")
        frontTex:SetTexture(M.TEX.IMBUE_BAR_FRONT)
        frontTex:SetAllPoints(frontFrame)
        frontTex:SetTexCoord(0, 1, CROP_TOP, CROP_BOTTOM)
        frontTex:SetAlpha(1)
    end

    -- Layer 4: text layer (timer text per slot, on top of everything)
    local textLayer = CreateFrame("Frame", "ShammyTimeImbueBarTextLayer", content)
    textLayer:SetAllPoints(content)
    textLayer:SetFrameLevel(baseLevel + 2)
    textLayer:EnableMouse(false)

    local fontSz = GetImbueFontSize()
    local textOX = GetImbueTextOffsetX()
    local textOY = GetImbueTextOffsetY()
    for i = 1, 2 do
        local cx = SlotX(i)
        local textFrame = CreateFrame("Frame", ("ShammyTimeImbueBarSlot%dText"):format(i), textLayer)
        textFrame:SetSize(ICON_SIZE + 30, 30)
        textFrame:SetPoint("CENTER", textLayer, "BOTTOMLEFT", cx + textOX, centerY + textOY)
        textFrame:EnableMouse(false)

        local timerText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timerText:SetPoint("CENTER")
        timerText:SetFont("Fonts\\FRIZQT__.TTF", fontSz, "OUTLINE")
        timerText:SetTextColor(TIMER_COLOR[1], TIMER_COLOR[2], TIMER_COLOR[3])
        timerText:SetShadowColor(0, 0, 0, 1)
        timerText:SetShadowOffset(1, -1)
        textFrame.timerText = timerText

        slots[i].textFrame = textFrame
    end

    imbueBarFrame = f
    f:Show()
    UpdateImbueBar()
    return f
end

-- Standalone elemental shield frame (Lightning/Water Shield): own position, movable, scale via /st shield scale.
local function CreateShieldFrame()
    if shieldFrame then return shieldFrame end

    local M = ShammyTime_Media
    local shieldTexOff = (M and M.TEX and M.TEX.LIGHTNING_SHIELD_OFF) or "Interface\\Icons\\Spell_Nature_LightningShield"
    local shieldTexOn  = (M and M.TEX and M.TEX.LIGHTNING_SHIELD_ON)  or "Interface\\Icons\\Spell_Nature_LightningShield"
    local db = GetDB and GetDB() or {}
    local scale = (db.shieldScale and db.shieldScale >= 0.05 and db.shieldScale <= 2) and db.shieldScale or DEFAULT_SHIELD_SCALE

    local f = CreateFrame("Frame", "ShammyTimeShieldFrame", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetSize(SHIELD_ICON_SIZE + 8, SHIELD_ICON_SIZE + 50)
    ApplyShieldPosition(f)
    f:SetScale(scale)
    f.baseScale = scale
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(not (db.locked))
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if GetDB and GetDB().locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveShieldPosition(self)
    end)

    local shieldOff = f:CreateTexture(nil, "ARTWORK")
    shieldOff:SetSize(SHIELD_ICON_SIZE, SHIELD_ICON_SIZE)
    shieldOff:SetPoint("TOP", 0, -3)
    -- Crop horizontally so the displayed shape is square (1:1)
    shieldOff:SetTexCoord(SHIELD_TEX_CROP_LEFT, SHIELD_TEX_CROP_RIGHT, 0, 1)
    shieldOff:SetTexture(shieldTexOff)
    shieldOff:SetVertexColor(1, 1, 1)
    shieldOff:SetAlpha(1)
    shieldOff:Show()
    f.shieldOff = shieldOff

    local shieldOn = f:CreateTexture(nil, "OVERLAY")
    shieldOn:SetSize(SHIELD_ICON_SIZE, SHIELD_ICON_SIZE)
    shieldOn:SetPoint("TOP", 0, -3)
    -- Same crop as the base layer so the overlay aligns perfectly.
    shieldOn:SetTexCoord(SHIELD_TEX_CROP_LEFT, SHIELD_TEX_CROP_RIGHT, 0, 1)
    shieldOn:SetTexture(shieldTexOn)
    shieldOn:SetVertexColor(1, 1, 1)
    shieldOn:SetAlpha(0)
    shieldOn:Show()
    f.shieldOn = shieldOn

    local countFontSz = GetShieldCountFontSize(db)
    local countText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Use position from DB (shieldCountX, shieldCountY) with defaults (0, 127)
    local countX = (db.shieldCountX and type(db.shieldCountX) == "number") and db.shieldCountX or 0
    local countY = (db.shieldCountY and type(db.shieldCountY) == "number") and db.shieldCountY or 127
    countText:SetPoint("BOTTOM", countX, countY)
    countText:SetFont("Fonts\\FRIZQT__.TTF", countFontSz, "OUTLINE")
    countText:SetTextColor(SHIELD_COUNT_COLOR[1], SHIELD_COUNT_COLOR[2], SHIELD_COUNT_COLOR[3])
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetShadowOffset(1, -1)
    countText:Hide()
    f.countText = countText
    f.lastShieldCountFontSize = countFontSz

    shieldFrame = f
    if db.wfShieldEnabled ~= false then f:Show() else f:Hide() end
    UpdateShieldIndicator()
    return f
end

function ShammyTime.GetShieldFrame()
    return shieldFrame
end

function ShammyTime.EnsureShieldFrame()
    return CreateShieldFrame()
end

function ShammyTime.ApplyShieldScale()
    if not shieldFrame then return end
    local db = GetDB and GetDB() or {}
    local scale = (db.shieldScale and db.shieldScale >= 0.05 and db.shieldScale <= 2) and db.shieldScale or DEFAULT_SHIELD_SCALE
    shieldFrame.baseScale = scale
    shieldFrame:SetScale(scale)
    -- Re-apply saved position after scale so the frame doesn't jump (same as Shamanistic Focus)
    if ShammyTime.ApplyShieldPosition then ShammyTime.ApplyShieldPosition() end
end

function ShammyTime.ApplyShieldPosition()
    if shieldFrame then ApplyShieldPosition(shieldFrame) end
end

-- Apply shield count settings (count override and number position) from DB
function ShammyTime.ApplyShieldCountSettings()
    if not shieldFrame or not shieldFrame.countText then return end
    local db = GetDB and GetDB() or {}
    -- Update count text position from DB
    local countX = (db.shieldCountX and type(db.shieldCountX) == "number") and db.shieldCountX or 0
    local countY = (db.shieldCountY and type(db.shieldCountY) == "number") and db.shieldCountY or 127
    shieldFrame.countText:ClearAllPoints()
    shieldFrame.countText:SetPoint("BOTTOM", countX, countY)
    local fontSz = GetShieldCountFontSize(db)
    shieldFrame.countText:SetFont("Fonts\\FRIZQT__.TTF", fontSz, "OUTLINE")
    shieldFrame.lastShieldCountFontSize = fontSz
    -- Refresh the indicator to update the count display (in case count override changed)
    UpdateShieldIndicator()
end

local function Init()
    CreateImbueBarFrame()
    CreateShieldFrame()
    if not updateTicker then
        updateTicker = C_Timer.NewTicker(1, UpdateImbueBar)
    end
end

-- Defer creation until PLAYER_LOGIN so SavedVariables and player name (for per-character positions) are ready
local imbueBarEventFrame = CreateFrame("Frame")
imbueBarEventFrame:RegisterEvent("PLAYER_LOGIN")
imbueBarEventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if ShammyTime.GetRadialPositionDB then
            Init()
        end
    end
end)

function ShammyTime.EnsureImbueBarFrame()
    return CreateImbueBarFrame()
end

-- Refresh slot content (call when bar is about to fade in so removed imbue doesn't blink)
function ShammyTime.RefreshImbueBar()
    if imbueBarFrame and imbueBarFrame:IsShown() then
        UpdateImbueBar()
    end
end

-- Apply saved scale (called when user changes /st imbue scale X). Re-apply position after scale so the bar doesn't jump (same as Shamanistic Focus).
function ShammyTime.ApplyImbueBarScale()
    if not imbueBarFrame then return end
    local scale = (GetDB and GetDB().imbueBarScale) or DEFAULT_IMBUE_BAR_SCALE
    imbueBarFrame.baseScale = scale
    if not imbueBarFrame.imbuePulseTicker then
        imbueBarFrame:SetScale(scale)
    end
    if ShammyTime.ApplyImbueBarPosition then ShammyTime.ApplyImbueBarPosition() end
end

-- Reposition imbue icon and text frames live (called from /st imbue commands or options panel).
function ShammyTime.ApplyImbueBarLayout()
    if not imbueBarFrame or not slots[1] then return end
    local centerY = BAR_H / 2 + ICONS_Y
    local textOX = GetImbueTextOffsetX()
    local textOY = GetImbueTextOffsetY()
    for i = 1, 2 do
        local slot = slots[i]
        local cx = SlotX(i)
        local iconFrame = slot.iconFrame
        if iconFrame then
            iconFrame:ClearAllPoints()
            iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
            iconFrame:SetPoint("CENTER", iconFrame:GetParent(), "BOTTOMLEFT", cx, centerY)
            if iconFrame.icon then iconFrame.icon:SetSize(ICON_SIZE, ICON_SIZE) end
        end
        local textFrame = slot.textFrame
        if textFrame then
            textFrame:ClearAllPoints()
            textFrame:SetSize(ICON_SIZE + 30, 30)
            textFrame:SetPoint("CENTER", textFrame:GetParent(), "BOTTOMLEFT", cx + textOX, centerY + textOY)
        end
    end
    UpdateImbueBar()
end

-- Apply timer font size from DB (called when user changes /st font imbue N)
function ShammyTime.ApplyImbueBarFontSize()
    local db = GetDB and GetDB() or {}
    local fontSz = GetImbueFontSize(db)
    if imbueBarFrame and slots[1] then
        for i = 1, 2 do
            local slot = slots[i]
            local tf = slot and slot.textFrame
            if tf and tf.timerText then
                tf.timerText:SetFont("Fonts\\FRIZQT__.TTF", fontSz, "OUTLINE")
            end
        end
        imbueBarFrame.lastImbueFontSize = fontSz
    end
    if ShammyTime.ApplyShieldCountSettings then ShammyTime.ApplyShieldCountSettings() end
end
