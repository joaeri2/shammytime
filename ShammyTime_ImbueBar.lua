-- ShammyTime_ImbueBar.lua
-- Movable weapon imbue bar (256×123): left square = main hand, right square = off hand.
-- Same look as Windfury totem bar: icon, shadow under icon, timer below. No range checks.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local FormatTime = ShammyTime.FormatTime
local GetWeaponImbuePerHand = ShammyTime.GetWeaponImbuePerHand
local GetRadialPositionDB = ShammyTime.GetRadialPositionDB
local GetDB = ShammyTime.GetDB

-- Layout (256×123 bar): two slots — left = MH, right = OH (reuse totem bar visual style)
local BAR_W, BAR_H = 256, 123
local SLOT_MARGIN = 44
local SLOT_GAP = 48
local SLOT_W = math.floor((BAR_W - 2 * SLOT_MARGIN - SLOT_GAP) / 2 + 0.5)
local SLOT_H = 32
local SLOT_OFFSET_Y = -24
local ICON_SIZE = 22
local ICON_OFFSET_TOP = -3
local TIMER_OFFSET_BOTTOM = -3
local TIMER_FONT_SIZE = 7
-- Shadow (same as Windfury totem bar)
local ICON_SHADOW_SIZE = 50
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

    for i = 1, 2 do
        local sf = CreateFrame("Frame", ("ShammyTimeImbueBarSlot%d"):format(i), f)
        sf:SetSize(SLOT_W, SLOT_H)
        sf:SetFrameLevel(baseLevel)
        if i == 1 then
            sf:SetPoint("LEFT", f, "LEFT", SLOT_MARGIN, 0)
        else
            sf:SetPoint("LEFT", slots[1], "RIGHT", SLOT_GAP, 0)
        end
        sf:SetPoint("TOP", f, "TOP", 0, SLOT_OFFSET_Y)
        sf:SetAlpha(SLOT_FRAME_ALPHA)
        sf:EnableMouse(false)

        local iconShadow = sf:CreateTexture(nil, "ARTWORK")
        iconShadow:SetDrawLayer("ARTWORK", -1)
        iconShadow:SetSize(ICON_SHADOW_SIZE, ICON_SHADOW_SIZE)
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
        icon:SetSize(ICON_SIZE, ICON_SIZE)
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
