-- ShammyTime_WindfuryTotemBar.lua
-- Totem functionality on the Windfury radial's totem bar (center ring). Uses the same logic as the main
-- totem bar (GetTotemInfo, timers, range) via ShammyTime.GetTotemSlotData; only the visuals live here.
-- Layers per slot: background art (existing texture), icon, state overlays, timer text.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local DISPLAY_ORDER = ShammyTime.DISPLAY_ORDER or { 2, 1, 3, 4 }
local FormatTime = ShammyTime.FormatTime
local GetTotemSlotData = ShammyTime.GetTotemSlotData

local windfurySlots = {}
local updateFrame
local timerTicker

-- ═══ LAYOUT: edit these to position the totem slots (reload UI after changes) ═══
-- Horizontal spacing:
local SLOT_MARGIN = 29   -- pixels from bar left edge to first slot (increase = row more centered/narrower)
local SLOT_GAP = 40       -- horizontal gap between slots (increase = more space between icons)
local BAR_W = 286
local SLOT_W = math.floor((BAR_W - 2 * SLOT_MARGIN - 3 * SLOT_GAP) / 4 + 0.5)
local SLOT_H = 32
-- Vertical (Y-axis): move the slot row up/down within the bar texture
local SLOT_OFFSET_Y = -25  -- 0 = slots at bar TOP; negative = push slots down; positive = push slots up
local ICON_SIZE = 22
local ICON_OFFSET_TOP = -3   -- icon position from slot TOP (negative = down)
local TIMER_OFFSET_BOTTOM = -4  -- timer from slot BOTTOM
-- Bar position (whole bar up/down): ShammyTime_CenterRing.lua line ~88: SetPoint(..., 0, 65)  -- lower = bar further down
-- ═══════════════════════════════════════════════════════════════════════════════
-- Fade into bar: slightly muted so the ornate frame shows through
local ICON_ALPHA_ACTIVE = 0.9
local ICON_ALPHA_EMPTY = 0
local TIMER_COLOR = { 0.88, 0.86, 0.82 }
local SLOT_FRAME_ALPHA = 0.94

local function RenderSlot(slotFrame, data)
    if not slotFrame or not data then return end
    local icon = slotFrame.icon
    local timerText = slotFrame.timerText
    local stateOverlay = slotFrame.stateOverlay
    local alertGlow = slotFrame.alertGlow

    if data.active then
        -- Totem is down: show icon, timer text; state/glow by range and time left (no cooldown spiral)
        if icon then
            icon:SetTexture(data.icon)
            icon:SetVertexColor(1, 1, 1)
            icon:SetAlpha(ICON_ALPHA_ACTIVE)
            if icon.SetDesaturated then icon:SetDesaturated(false) end
            icon:Show()
        end
        if data.rangeState == "out" then
            if icon then
                icon:SetAlpha(ICON_ALPHA_ACTIVE * 0.65)
                if icon.SetDesaturated then icon:SetDesaturated(true) end
                icon:SetVertexColor(0.9, 0.5, 0.5)
            end
            if stateOverlay then
                stateOverlay:SetColorTexture(0.5, 0, 0, 0.3)
                stateOverlay:Show()
            end
        else
            if stateOverlay then stateOverlay:Hide() end
        end
        local remaining = data.remainingSeconds or 0
        if timerText then
            timerText:SetText(FormatTime(remaining))
            timerText:SetTextColor(TIMER_COLOR[1], TIMER_COLOR[2], TIMER_COLOR[3])
            timerText:Show()
        end
        if alertGlow then
            if remaining > 0 and remaining <= 5 then
                alertGlow:SetAlpha(0.25 + 0.1 * math.sin(GetTime() * 3))
                alertGlow:Show()
            else
                alertGlow:Hide()
            end
        end
        if data.justPlaced and slotFrame.PlayPlacePop then
            slotFrame:PlayPlacePop()
        end
    else
        -- Empty/expired: desaturated + low alpha so bar art shows through
        if icon then
            icon:SetTexture(data.emptyIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
            icon:SetVertexColor(0.45, 0.42, 0.38)
            icon:SetAlpha(ICON_ALPHA_EMPTY)
            if icon.SetDesaturated then icon:SetDesaturated(true) end
            icon:Show()
        end
        if stateOverlay then
            stateOverlay:SetColorTexture(0.18, 0.16, 0.14, 0.4)
            stateOverlay:Show()
        end
        if timerText then
            timerText:SetText("")
            timerText:Hide()
        end
        if alertGlow then alertGlow:Hide() end
    end
end

local function UpdateWindfuryTotemBar()
    local parent = windfurySlots.parent
    if not parent or not parent:IsShown() then return end
    for i = 1, 4 do
        local slot = DISPLAY_ORDER[i]
        local data = GetTotemSlotData(slot)
        local sf = windfurySlots[i]
        if sf and data then
            RenderSlot(sf, data)
        end
    end
end

local function CreateWindfuryTotemSlots()
    if windfurySlots[1] then return end
    local center = ShammyTime.EnsureCenterRingExists and ShammyTime.EnsureCenterRingExists()
    if not center or not center.totemBar then return end

    local bar = center.totemBar
    windfurySlots.parent = center
    -- Slot frames sit above the center frame (and its textures); Texture has no GetFrameLevel()
    local baseLevel = center:GetFrameLevel() + 2

    for i = 1, 4 do
        local slot = DISPLAY_ORDER[i]
        local sf = CreateFrame("Frame", ("ShammyTimeWindfuryTotemSlot%d"):format(i), center)
        sf:SetSize(SLOT_W, SLOT_H)
        sf:SetFrameLevel(baseLevel)
        if i == 1 then
            sf:SetPoint("LEFT", bar, "LEFT", SLOT_MARGIN, 0)
        else
            sf:SetPoint("LEFT", windfurySlots[i - 1], "RIGHT", SLOT_GAP, 0)
        end
        sf:SetPoint("TOP", bar, "TOP", 0, SLOT_OFFSET_Y)
        sf:SetAlpha(SLOT_FRAME_ALPHA)
        sf:EnableMouse(false)

        -- Icon (layer 2)
        local icon = sf:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("TOP", 0, ICON_OFFSET_TOP)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        sf.icon = icon

        -- Timer text at bottom of slot (no cooldown spiral) (muted so it sits in the bar)
        local timerText = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timerText:SetPoint("BOTTOM", 0, TIMER_OFFSET_BOTTOM)
        timerText:SetTextColor(TIMER_COLOR[1], TIMER_COLOR[2], TIMER_COLOR[3])
        timerText:SetShadowColor(0, 0, 0, 1)
        timerText:SetShadowOffset(1, -1)
        sf.timerText = timerText

        -- State overlay (expired = dark; out of range = red tint over icon area)
        local stateOverlay = sf:CreateTexture(nil, "OVERLAY")
        stateOverlay:SetAllPoints(sf)
        stateOverlay:SetColorTexture(0, 0, 0, 0)
        stateOverlay:Hide()
        sf.stateOverlay = stateOverlay

        -- Alert glow when remaining <= 5 sec (subtle pulse)
        local alertGlow = sf:CreateTexture(nil, "OVERLAY")
        alertGlow:SetAllPoints(sf)
        alertGlow:SetColorTexture(1, 0.85, 0.3, 0.2)
        alertGlow:SetBlendMode("ADD")
        alertGlow:Hide()
        sf.alertGlow = alertGlow

        -- Just-placed pop: 150ms scale 1.0 -> 1.08 -> 1.0
        function sf:PlayPlacePop()
            if self.popAnim then
                self.popAnim:Stop()
                self.popAnim:Play()
                return
            end
            local ag = self:CreateAnimationGroup()
            local s1 = ag:CreateAnimation("Scale")
            s1:SetOrder(1)
            s1:SetDuration(0.05)
            s1:SetScale(1.08, 1.08)
            local s2 = ag:CreateAnimation("Scale")
            s2:SetOrder(2)
            s2:SetDuration(0.1)
            s2:SetScale(1, 1)
            s2:SetSmoothing("OUT")
            self.popAnim = ag
            ag:Play()
        end

        windfurySlots[i] = sf
    end

    UpdateWindfuryTotemBar()
end

local function OnEvent(_, event)
    if event == "PLAYER_TOTEM_UPDATE" then
        CreateWindfuryTotemSlots()
        UpdateWindfuryTotemBar()
    end
end

local function Init()
    CreateWindfuryTotemSlots()
    UpdateWindfuryTotemBar()
    if not updateFrame then
        updateFrame = CreateFrame("Frame")
        updateFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
        updateFrame:SetScript("OnEvent", OnEvent)
    end
    if not timerTicker then
        timerTicker = C_Timer.NewTicker(1, UpdateWindfuryTotemBar)
    end
end

-- Run after center ring and main addon are ready (ADDON_LOADED ShammyTime already created center if radial is shown).
if ShammyTime.EnsureCenterRingExists then
    C_Timer.After(0, Init)
end

-- /wftotempos — print layout constants and current screen x,y coords for bar + slots (so you can adjust positioning)
SLASH_WFTOTEMPOS1 = "/wftotempos"
SlashCmdList["WFTOTEMPOS"] = function()
    local center = ShammyTime.EnsureCenterRingExists and ShammyTime.EnsureCenterRingExists()
    if not center then
        print("ShammyTime: Center ring not created. Show the Windfury radial first (/wfcenter).")
        return
    end
    print("|cff00ff00ShammyTime totem bar layout|r")
    print(string.format("  Constants (edit in ShammyTime_WindfuryTotemBar.lua): SLOT_MARGIN=%d, SLOT_GAP=%d, SLOT_W=%d, SLOT_H=%d, SLOT_OFFSET_Y=%d", SLOT_MARGIN, SLOT_GAP, SLOT_W, SLOT_H, SLOT_OFFSET_Y))
    print("  Bar Y offset: ShammyTime_CenterRing.lua line ~88  SetPoint(..., 0, 34)  (lower = bar further down)")
    local bar = center.totemBar
    if center.GetCenter then
        local bx, by = center:GetCenter()
        if bx then
            print(string.format("  Center frame (screen): x=%.1f  y=%.1f  (bar is below this)", bx, by))
        end
    end
    for i = 1, 4 do
        local sf = windfurySlots[i]
        if sf and sf.GetLeft and sf:GetLeft() then
            local left, bottom, w, h = sf:GetLeft(), sf:GetBottom(), sf:GetWidth(), sf:GetHeight()
            local cx, cy = sf:GetCenter()
            print(string.format("  Slot %d: left=%.1f  bottom=%.1f  width=%.0f  height=%.0f  |  center x=%.1f  y=%.1f", i, left, bottom, w, h, cx or 0, cy or 0))
        else
            print(string.format("  Slot %d: (not created yet — place a totem or reload)", i))
        end
    end
end
