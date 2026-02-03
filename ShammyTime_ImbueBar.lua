-- ShammyTime_ImbueBar.lua
-- Movable weapon imbue bar (512×261 nohalo): left = main hand, right = off hand.
-- Same look as Windfury totem bar: icon, shadow under icon, timer below. No range checks.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local FormatTime = ShammyTime.FormatTime
local GetWeaponImbuePerHand = ShammyTime.GetWeaponImbuePerHand
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
local PLACEHOLDER_OH_ALPHA = 0.55
-- Shadow behind icon (same style as totem bar: wf_center_shadow.tga, drop below icon)
local ICON_SHADOW_OFFSET_X = 2
local ICON_SHADOW_OFFSET_Y = 15
local ICON_SHADOW_TINT = { 0, 0, 0, 0.85 }
local ICON_ALPHA_ACTIVE = 0.9
local ICON_ALPHA_EMPTY = 0
local TIMER_COLOR = { 0.88, 0.86, 0.82 }
local SLOT_FRAME_ALPHA = 0.94
local EMPTY_ICON = 135847  -- Frostbrand-style empty slot

local imbueBarFrame
local slots = {}  -- [1] = MH, [2] = OH
local updateTicker

local function GetLayout()
    return SLOT_MARGIN, SLOT_GAP, SLOT_OFFSET_Y, ICON_SIZE
end

local function ApplyImbueBarPosition(frame)
    local pos = GetRadialPositionDB and GetRadialPositionDB()
    if not pos or not pos.imbueBar then return end
    local t = pos.imbueBar
    local relTo = (t.relativeTo and _G[t.relativeTo]) or UIParent
    if relTo then
        frame:ClearAllPoints()
        frame:SetPoint(t.point or "CENTER", relTo, t.relativePoint or "CENTER", t.x or 0, t.y or 0)
    end
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
        -- Empty: show dummy/placeholder for off-hand so you can see where OH sits on the artwork
        if isOffHand then
            if iconShadow then iconShadow:Show() end
            SetSlotTexture(icon, EMPTY_ICON)
            icon:SetVertexColor(0.6, 0.55, 0.5)
            icon:SetAlpha(PLACEHOLDER_OH_ALPHA)
            if icon.SetDesaturated then icon:SetDesaturated(true) end
            icon:Show()
            if timerText then
                timerText:SetText("OH")
                timerText:SetTextColor(TIMER_COLOR[1] * 0.8, TIMER_COLOR[2] * 0.8, TIMER_COLOR[3] * 0.8)
                timerText:Show()
            end
        else
            if iconShadow then iconShadow:Hide() end
            SetSlotTexture(icon, EMPTY_ICON)
            icon:SetVertexColor(0.45, 0.42, 0.38)
            icon:SetAlpha(ICON_ALPHA_EMPTY)
            if icon.SetDesaturated then icon:SetDesaturated(true) end
            icon:Show()
            if timerText then
                timerText:SetText("")
                timerText:Hide()
            end
        end
    end
end

local function UpdateImbueBar()
    if not imbueBarFrame or not imbueBarFrame:IsShown() then return end
    local perHand = GetWeaponImbuePerHand and GetWeaponImbuePerHand()
    if not perHand then return end
    RenderImbueSlot(slots[1], perHand.mainHand)
    RenderImbueSlot(slots[2], perHand.offHand)
end

local function CreateImbueBarFrame()
    if imbueBarFrame then return imbueBarFrame end

    local f = CreateFrame("Frame", "ShammyTimeImbueBarFrame", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetSize(BAR_W, BAR_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -260)
    ApplyImbueBarPosition(f)
    local scale = (GetDB and GetDB().imbueBarScale) or DEFAULT_IMBUE_BAR_SCALE
    f:SetScale(scale)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
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
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.bg:SetTexture(barTex)
    f.bg:SetAlpha(1)

    local baseLevel = f:GetFrameLevel() + 2
    local margin, gap, offsetY, iconSize = GetLayout()
    local slotW = math.floor((BAR_W - 2 * margin - gap) / 2 + 0.5)

    for i = 1, 2 do
        local sf = CreateFrame("Frame", ("ShammyTimeImbueBarSlot%d"):format(i), f)
        sf.slotIndex = i
        sf:SetSize(slotW, SLOT_H)
        sf:SetFrameLevel(baseLevel)
        if i == 1 then
            sf:SetPoint("LEFT", f, "LEFT", margin, 0)
        else
            sf:SetPoint("LEFT", slots[1], "RIGHT", gap, 0)
        end
        sf:SetPoint("TOP", f, "TOP", 0, offsetY)
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

        local timerText = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timerText:SetPoint("BOTTOM", 0, TIMER_OFFSET_BOTTOM)
        timerText:SetFont("Fonts\\FRIZQT__.TTF", TIMER_FONT_SIZE, "OUTLINE")
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

local function Init()
    CreateImbueBarFrame()
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

-- Apply saved scale (called when user changes /st imbue scale X)
function ShammyTime.ApplyImbueBarScale()
    if not imbueBarFrame then return end
    local scale = (GetDB and GetDB().imbueBarScale) or DEFAULT_IMBUE_BAR_SCALE
    imbueBarFrame:SetScale(scale)
end

-- Reapply layout (margin, gap, offsetY, iconSize) so you can move/resize icons without /reload
function ShammyTime.ApplyImbueBarLayout()
    if not imbueBarFrame or not slots[1] or not slots[2] then return end
    local margin, gap, offsetY, iconSize = GetLayout()
    local slotW = math.floor((BAR_W - 2 * margin - gap) / 2 + 0.5)
    slots[1]:ClearAllPoints()
    slots[1]:SetPoint("LEFT", imbueBarFrame, "LEFT", margin, 0)
    slots[1]:SetPoint("TOP", imbueBarFrame, "TOP", 0, offsetY)
    slots[1]:SetSize(slotW, SLOT_H)
    slots[1].icon:SetSize(iconSize, iconSize)
    slots[2]:ClearAllPoints()
    slots[2]:SetPoint("LEFT", slots[1], "RIGHT", gap, 0)
    slots[2]:SetPoint("TOP", imbueBarFrame, "TOP", 0, offsetY)
    slots[2]:SetSize(slotW, SLOT_H)
    slots[2].icon:SetSize(iconSize, iconSize)
    UpdateImbueBar()
end
