-- ShammyTime_ImbueBar.lua
-- Movable weapon imbue bar (512×261 nohalo): left = main hand, right = off hand.
-- Same look as Windfury totem bar: icon, shadow under icon, timer below. No range checks.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local FormatTime = ShammyTime.FormatTime
local GetWeaponImbuePerHand = ShammyTime.GetWeaponImbuePerHand
local GetElementalShieldAura = ShammyTime.GetElementalShieldAura
local GetRadialPositionDB = ShammyTime.GetRadialPositionDB
local GetDB = ShammyTime.GetDB

-- Layout: BAR_W/BAR_H match imbue_bar_512_261_nohalo.tga (512×261)
local BAR_W, BAR_H = 512, 261
local DEFAULT_IMBUE_BAR_SCALE = 0.4

-- ═══ EDIT THESE TO MOVE AND RESIZE THE IMBUE ICONS (left=MH, right=OH) ═══
-- Change numbers, save file, then /reload in game. No in-game commands needed.
local SLOT_MARGIN   = 78   -- pixels from bar left to first icon (bigger = both icons shift right)
local SLOT_GAP      = 80    -- pixels between main-hand and off-hand icon
local SLOT_OFFSET_Y = -117  -- vertical position: more negative = icons lower on the bar (e.g. -100 to -160)
local ICON_SIZE     = 80    -- icon size in pixels (e.g. 28–56). Larger = bigger icons.
-- ═══════════════════════════════════════════════════════════════════════

local SLOT_H = 32
local ICON_OFFSET_TOP = -3
local TIMER_OFFSET_BOTTOM = -50
local TIMER_FONT_SIZE = 20
-- Shadow behind icon (same style as totem bar: wf_center_shadow.tga, drop below icon)
local ICON_SHADOW_OFFSET_X = 2
local ICON_SHADOW_OFFSET_Y = 15
local ICON_SHADOW_TINT = { 0, 0, 0, 0.85 }
local ICON_ALPHA_ACTIVE = 0.9
local ICON_ALPHA_EMPTY = 0
local TIMER_COLOR = { 0.88, 0.86, 0.82 }
local SLOT_FRAME_ALPHA = 0.94
local EMPTY_ICON = 135847  -- Frostbrand-style empty slot

-- Elemental shield (Lightning Shield / Water Shield): off texture base, on texture fades in with alpha when active; orb count 1–3.
-- Assets are 256×213; render as a square (1:1) by center-cropping the extra width.
local SHIELD_GAP = 16
local SHIELD_TEX_W = 256
local SHIELD_TEX_H = 213
local SHIELD_ICON_SIZE = SHIELD_TEX_H -- square output size
local SHIELD_TEX_SQUARE_RATIO = SHIELD_TEX_H / SHIELD_TEX_W
local SHIELD_TEX_CROP_LEFT = (1 - SHIELD_TEX_SQUARE_RATIO) / 2
local SHIELD_TEX_CROP_RIGHT = 1 - SHIELD_TEX_CROP_LEFT
local SHIELD_FADE_DURATION = 0.25  -- seconds for "on" overlay to fade in/out (light turning on/off)
local SHIELD_COUNT_FONT_SIZE = 18  -- orb count (1–3) text
local SHIELD_COUNT_COLOR = { 0.95, 0.9, 0.7 }  -- light gold for count

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

local function GetLayout()
    return SLOT_MARGIN, SLOT_GAP, SLOT_OFFSET_Y, ICON_SIZE
end

local function ApplyImbueBarPosition(frame)
    local pos = GetRadialPositionDB and GetRadialPositionDB()
    if pos and pos.imbueBar then
        local t = pos.imbueBar
        local relTo = (t.relativeTo and _G[t.relativeTo]) or UIParent
        if relTo then
            frame:ClearAllPoints()
            frame:SetPoint(t.point or "CENTER", relTo, t.relativePoint or "CENTER", t.x or 0, t.y or 0)
        end
    end
    -- Always normalize to CENTER anchor so scaling in options (or /st imbue scale) doesn't move the bar diagonally
    local fx, fy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if fx and fy and ux and uy then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", fx - ux, fy - uy)
    end
end

-- Global wrapper for repositioning imbue bar after scale change
function ShammyTime.ApplyImbueBarPosition()
    local f = _G.ShammyTimeImbueBarFrame
    if f then ApplyImbueBarPosition(f) end
end

local function SaveImbueBarPosition(frame)
    if not GetRadialPositionDB then return end
    local pos = GetRadialPositionDB()
    pos.imbueBar = pos.imbueBar or {}
    local point, relTo, relativePoint, x, y = frame:GetPoint(1)
    pos.imbueBar.point = point
    pos.imbueBar.relativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent"
    pos.imbueBar.relativePoint = relativePoint
    pos.imbueBar.x = x
    pos.imbueBar.y = y
end

local DEFAULT_SHIELD_SCALE = 0.2

local function ApplyShieldPosition(frame)
    local pos = GetRadialPositionDB and GetRadialPositionDB()
    if not pos then return end
    pos.shieldFrame = pos.shieldFrame or {}
    local t = pos.shieldFrame
    if t.point and t.relativeTo then
        local relTo = (t.relativeTo and _G[t.relativeTo]) or UIParent
        frame:ClearAllPoints()
        frame:SetPoint(t.point or "CENTER", relTo, t.relativePoint or "CENTER", t.x or 0, t.y or 0)
    else
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 250, -180)
    end
    -- Normalize to CENTER anchor so changing scale doesn't cause weird movement (anchor stays fixed)
    local fx, fy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if fx and fy and ux and uy then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", fx - ux, fy - uy)
    end
end

local function SaveShieldPosition(frame)
    if not GetRadialPositionDB then return end
    local pos = GetRadialPositionDB()
    pos.shieldFrame = pos.shieldFrame or {}
    local point, relTo, relativePoint, x, y = frame:GetPoint(1)
    pos.shieldFrame.point = point
    pos.shieldFrame.relativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent"
    pos.shieldFrame.relativePoint = relativePoint
    pos.shieldFrame.x = x
    pos.shieldFrame.y = y
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

local function RenderImbueSlot(slotFrame, data)
    if not slotFrame then return end
    local icon = slotFrame.icon
    local timerText = slotFrame.timerText
    local iconShadow = slotFrame.iconShadow
    local isOffHand = (slotFrame.slotIndex == 2)

    if data and data.expirationTime and (data.expirationTime - GetTime()) > 0 then
        if iconShadow then iconShadow:Show() end
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
        if iconShadow then iconShadow:Hide() end
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
    local barTex = (M and M.TEX and M.TEX.IMBUE_BAR) or "Interface\\Tooltips\\UI-Tooltip-Background"
    f.bg = content:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(content)
    f.bg:SetTexture(barTex)
    f.bg:SetAlpha(1)

    local baseLevel = content:GetFrameLevel() + 2
    local margin, gap, offsetY, iconSize = GetLayout()
    local slotW = math.floor((BAR_W - 2 * margin - gap) / 2 + 0.5)

    for i = 1, 2 do
        local sf = CreateFrame("Frame", ("ShammyTimeImbueBarSlot%d"):format(i), content)
        sf.slotIndex = i
        sf:SetSize(slotW, SLOT_H)
        sf:SetFrameLevel(baseLevel)
        if i == 1 then
            sf:SetPoint("LEFT", content, "LEFT", margin, 0)
        else
            sf:SetPoint("LEFT", slots[1], "RIGHT", gap, 0)
        end
        sf:SetPoint("TOP", content, "TOP", 0, offsetY)
        sf:SetAlpha(SLOT_FRAME_ALPHA)
        sf:EnableMouse(false)

        -- Shadow behind icon (same texture as totem bar; size scales with icon so it stays visible)
        local shadowSize = iconSize + 28   -- e.g. 44px icon -> 72px shadow
        local iconShadow = sf:CreateTexture(nil, "ARTWORK")
        iconShadow:SetDrawLayer("ARTWORK", -1)
        iconShadow:SetSize(shadowSize, shadowSize)
        iconShadow:SetPoint("TOP", ICON_SHADOW_OFFSET_X, ICON_OFFSET_TOP + ICON_SHADOW_OFFSET_Y)
        if M and M.TEX and M.TEX.CENTER_SHADOW then
            iconShadow:SetTexture(M.TEX.CENTER_SHADOW)
            iconShadow:SetTexCoord(0, 1, 0, 1)
            iconShadow:SetVertexColor(ICON_SHADOW_TINT[1], ICON_SHADOW_TINT[2], ICON_SHADOW_TINT[3], ICON_SHADOW_TINT[4])
        else
            iconShadow:SetColorTexture(0.1, 0.08, 0.06, 0.7)
        end
        sf.iconShadow = iconShadow

        local icon = sf:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("TOP", 0, ICON_OFFSET_TOP)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        sf.icon = icon

        local fontSz = (GetDB and GetDB().fontImbueTimer and GetDB().fontImbueTimer >= 6 and GetDB().fontImbueTimer <= 28) and GetDB().fontImbueTimer or TIMER_FONT_SIZE
        local timerText = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timerText:SetPoint("BOTTOM", 0, TIMER_OFFSET_BOTTOM)
        timerText:SetFont("Fonts\\FRIZQT__.TTF", fontSz, "OUTLINE")
        timerText:SetTextColor(TIMER_COLOR[1], TIMER_COLOR[2], TIMER_COLOR[3])
        timerText:SetShadowColor(0, 0, 0, 1)
        timerText:SetShadowOffset(1, -1)
        sf.timerText = timerText

        slots[i] = sf
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
    shieldOff:SetPoint("TOP", 0, ICON_OFFSET_TOP)
    -- Crop horizontally so the displayed shape is square (1:1)
    shieldOff:SetTexCoord(SHIELD_TEX_CROP_LEFT, SHIELD_TEX_CROP_RIGHT, 0, 1)
    shieldOff:SetTexture(shieldTexOff)
    shieldOff:SetVertexColor(1, 1, 1)
    shieldOff:SetAlpha(1)
    shieldOff:Show()
    f.shieldOff = shieldOff

    local shieldOn = f:CreateTexture(nil, "OVERLAY")
    shieldOn:SetSize(SHIELD_ICON_SIZE, SHIELD_ICON_SIZE)
    shieldOn:SetPoint("TOP", 0, ICON_OFFSET_TOP)
    -- Same crop as the base layer so the overlay aligns perfectly.
    shieldOn:SetTexCoord(SHIELD_TEX_CROP_LEFT, SHIELD_TEX_CROP_RIGHT, 0, 1)
    shieldOn:SetTexture(shieldTexOn)
    shieldOn:SetVertexColor(1, 1, 1)
    shieldOn:SetAlpha(0)
    shieldOn:Show()
    f.shieldOn = shieldOn

    local countFontSz = (GetDB and GetDB().fontImbueTimer and GetDB().fontImbueTimer >= 6 and GetDB().fontImbueTimer <= 28) and GetDB().fontImbueTimer or SHIELD_COUNT_FONT_SIZE
    local countText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Use position from DB (shieldCountX, shieldCountY) with defaults (0, TIMER_OFFSET_BOTTOM)
    local countX = (db.shieldCountX and type(db.shieldCountX) == "number") and db.shieldCountX or 0
    local countY = (db.shieldCountY and type(db.shieldCountY) == "number") and db.shieldCountY or TIMER_OFFSET_BOTTOM
    countText:SetPoint("BOTTOM", countX, countY)
    countText:SetFont("Fonts\\FRIZQT__.TTF", countFontSz, "OUTLINE")
    countText:SetTextColor(SHIELD_COUNT_COLOR[1], SHIELD_COUNT_COLOR[2], SHIELD_COUNT_COLOR[3])
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetShadowOffset(1, -1)
    countText:Hide()
    f.countText = countText

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
    local countY = (db.shieldCountY and type(db.shieldCountY) == "number") and db.shieldCountY or TIMER_OFFSET_BOTTOM
    shieldFrame.countText:ClearAllPoints()
    shieldFrame.countText:SetPoint("BOTTOM", countX, countY)
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

if ShammyTime.GetRadialPositionDB then
    C_Timer.After(0, Init)
end

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

-- Reapply layout (margin, gap, offsetY, iconSize) so you can move/resize icons without /reload
function ShammyTime.ApplyImbueBarLayout()
    if not imbueBarFrame or not imbueBarFrame.content or not slots[1] or not slots[2] then return end
    local margin, gap, offsetY, iconSize = GetLayout()
    local slotW = math.floor((BAR_W - 2 * margin - gap) / 2 + 0.5)
    local content = imbueBarFrame.content
    slots[1]:ClearAllPoints()
    slots[1]:SetPoint("LEFT", content, "LEFT", margin, 0)
    slots[1]:SetPoint("TOP", content, "TOP", 0, offsetY)
    slots[1]:SetSize(slotW, SLOT_H)
    slots[1].icon:SetSize(iconSize, iconSize)
    slots[2]:ClearAllPoints()
    slots[2]:SetPoint("LEFT", slots[1], "RIGHT", gap, 0)
    slots[2]:SetPoint("TOP", content, "TOP", 0, offsetY)
    slots[2]:SetSize(slotW, SLOT_H)
    slots[2].icon:SetSize(iconSize, iconSize)
    UpdateImbueBar()
end

-- Apply timer font size from DB (called when user changes /st font imbue N)
function ShammyTime.ApplyImbueBarFontSize()
    if not imbueBarFrame or not slots[1] then return end
    local db = GetDB and GetDB() or {}
    local fontSz = (db.fontImbueTimer and db.fontImbueTimer >= 6 and db.fontImbueTimer <= 28) and db.fontImbueTimer or TIMER_FONT_SIZE
    for i = 1, #slots do
        if slots[i] and slots[i].timerText then
            slots[i].timerText:SetFont("Fonts\\FRIZQT__.TTF", fontSz, "OUTLINE")
        end
    end
end
