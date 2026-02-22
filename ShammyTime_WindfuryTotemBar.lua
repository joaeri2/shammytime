-- ShammyTime_WindfuryTotemBar.lua
-- Totem functionality on the Windfury radial's totem bar (center ring). Uses the same logic as the main
-- totem bar (GetTotemInfo, timers, range) via ShammyTime.GetTotemSlotData; only the visuals live here.
-- Draw order: layer 1 = back (CenterRing), 2 = icon layer, 3 = front texture, 4 = text layer.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

local DISPLAY_ORDER = ShammyTime.DISPLAY_ORDER or { 2, 1, 3, 4 }
local FormatTime = ShammyTime.FormatTime
local GetTotemSlotData = ShammyTime.GetTotemSlotData

local windfurySlots = {}
local updateFrame
local timerTicker

-- ═══ LAYOUT DEFAULTS (overridden by DB values; adjust live with /st totem) ═══
local DEFAULTS = {
    iconsX       = -1,      -- horizontal offset for all 4 icons (positive = right)
    iconsY       = 2,       -- vertical offset from center (negative = down)
    iconsSpread  = 0.95,    -- spread multiplier (1.0 = default; <1 = tighter; >1 = wider)
    iconSize     = 40,      -- icon width & height in pixels
    timerOffsetX = 0,       -- timer text horizontal offset from icon center (positive = right)
    timerOffsetY = -2,      -- timer text offset below icon center (negative = down)
}
-- ═══════════════════════════════════════════════════════════════════════════════
local BAR_W = 286          -- frame size (matches CenterRing)
local TIMER_FONT_SIZE = 10 -- timer text size (also adjustable via /st font totem)

-- Read a layout value from saved DB, falling back to DEFAULTS.
local function L(key)
    local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
    if db and db.totemLayout and db.totemLayout[key] ~= nil then return db.totemLayout[key] end
    return DEFAULTS[key]
end
-- Fade into bar: slightly muted so the ornate frame shows through
local ICON_ALPHA_ACTIVE = 0.9
local ICON_ALPHA_EMPTY = 0
local TIMER_COLOR = { 0.88, 0.86, 0.82 }
local SLOT_FRAME_ALPHA = 0.94

local function RenderSlot(slotData, data)
    if not slotData or not data then return end
    local iconFrame = slotData.iconFrame
    local textFrame = slotData.textFrame
    local icon = iconFrame and iconFrame.icon
    local timerText = textFrame and textFrame.timerText
    local stateOverlay = iconFrame and iconFrame.stateOverlay
    local alertGlow = iconFrame and iconFrame.alertGlow
    if data.active then
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
        if data.justPlaced and iconFrame and iconFrame.PlayPlacePop then
            iconFrame:PlayPlacePop()
        end
    else
        -- Empty/expired: no overlay, just dimmed empty icon
        if stateOverlay then stateOverlay:Hide() end
        if icon then
            icon:SetTexture(data.emptyIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
            icon:SetVertexColor(0.45, 0.42, 0.38)
            icon:SetAlpha(ICON_ALPHA_EMPTY)
            if icon.SetDesaturated then icon:SetDesaturated(true) end
            icon:Show()
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

-- Compute slot positions from simplified layout. 4 icons centered on (iconsX, iconsY) with iconsSpread.
local BASE_GAP = 48  -- default pixel gap between icon centers at spread 1.0
local function SlotX(i)
    -- i = 1..4 → offsets: -1.5, -0.5, +0.5, +1.5 (centered around 0)
    local offset = (i - 2.5) * BASE_GAP * L("iconsSpread")
    return BAR_W / 2 + L("iconsX") + offset
end

local function CreateWindfuryTotemSlots()
    if windfurySlots[1] then return end
    local barFrame = ShammyTime.EnsureWindfuryTotemBarFrame and ShammyTime.EnsureWindfuryTotemBarFrame()
    if not barFrame then return end

    windfurySlots.parent = barFrame
    local baseLevel = barFrame:GetFrameLevel() + 1
    local M = ShammyTime_Media
    local iconSize = L("iconSize")
    local barH = barFrame:GetHeight()
    local centerY = barH / 2 + L("iconsY")
    local timerOY = L("timerOffsetY")

    -- Layer 2: icon layer (4 icon frames, no text)
    local iconLayer = CreateFrame("Frame", "ShammyTimeTotemBarIconLayer", barFrame)
    iconLayer:SetAllPoints(barFrame)
    iconLayer:SetFrameLevel(baseLevel)
    iconLayer:EnableMouse(false)

    for i = 1, 4 do
        local cx = SlotX(i)
        local iconFrame = CreateFrame("Frame", ("ShammyTimeWindfuryTotemSlot%dIcon"):format(i), iconLayer)
        iconFrame:SetFrameLevel(baseLevel)  -- keep icons below front frame
        iconFrame:SetSize(iconSize, iconSize)
        iconFrame:SetPoint("CENTER", iconLayer, "BOTTOMLEFT", cx, centerY)
        iconFrame:EnableMouse(false)

        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("CENTER")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconFrame.icon = icon

        local stateOverlay = iconFrame:CreateTexture(nil, "OVERLAY")
        stateOverlay:SetAllPoints(iconFrame)
        stateOverlay:SetColorTexture(0, 0, 0, 0)
        stateOverlay:Hide()
        iconFrame.stateOverlay = stateOverlay

        local alertGlow = iconFrame:CreateTexture(nil, "OVERLAY")
        alertGlow:SetAllPoints(iconFrame)
        alertGlow:SetColorTexture(1, 0.85, 0.3, 0.2)
        alertGlow:SetBlendMode("ADD")
        alertGlow:Hide()
        iconFrame.alertGlow = alertGlow

        function iconFrame:PlayPlacePop()
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

        windfurySlots[i] = { iconFrame = iconFrame }
    end

    -- Layer 3: front texture (draws on top of icons, below text)
    local frontFrame = CreateFrame("Frame", "ShammyTimeTotemBarFrontLayer", barFrame)
    frontFrame:SetAllPoints(barFrame)
    frontFrame:SetFrameLevel(baseLevel + 1)
    frontFrame:EnableMouse(false)
    if M and M.TEX and M.TEX.TOTEM_BAR_FRONT then
        local frontTex = frontFrame:CreateTexture(nil, "ARTWORK")
        frontTex:SetTexture(M.TEX.TOTEM_BAR_FRONT)
        frontTex:SetAllPoints(frontFrame)
        -- Match the same vertical crop as the back texture
        local ct = barFrame.cropTop or 0
        local cb = barFrame.cropBottom or 1
        frontTex:SetTexCoord(0, 1, ct, cb)
        frontTex:SetAlpha(1)
    end

    -- Layer 4: text layer (timer text per slot, on top of everything)
    local textLayer = CreateFrame("Frame", "ShammyTimeTotemBarTextLayer", barFrame)
    textLayer:SetAllPoints(barFrame)
    textLayer:SetFrameLevel(baseLevel + 2)
    textLayer:EnableMouse(false)

    local dbFont = ShammyTime.GetDB and ShammyTime.GetDB() or {}
    local fontSz = (dbFont.fontTotemTimer and dbFont.fontTotemTimer >= 6 and dbFont.fontTotemTimer <= 28) and dbFont.fontTotemTimer or TIMER_FONT_SIZE
    local timerOX = L("timerOffsetX")
    for i = 1, 4 do
        local cx = SlotX(i)
        local textFrame = CreateFrame("Frame", ("ShammyTimeWindfuryTotemSlot%dText"):format(i), textLayer)
        textFrame:SetSize(iconSize + 20, 20)
        textFrame:SetPoint("CENTER", textLayer, "BOTTOMLEFT", cx + timerOX, centerY + timerOY)
        textFrame:EnableMouse(false)

        local timerText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timerText:SetPoint("CENTER")
        timerText:SetFont("Fonts\\FRIZQT__.TTF", fontSz, "OUTLINE")
        timerText:SetTextColor(TIMER_COLOR[1], TIMER_COLOR[2], TIMER_COLOR[3])
        timerText:SetShadowColor(0, 0, 0, 1)
        timerText:SetShadowOffset(1, -1)
        textFrame.timerText = timerText

        windfurySlots[i].textFrame = textFrame
    end

    UpdateWindfuryTotemBar()
end

-- Reposition all slots and text live (called from /st totem commands).
function ShammyTime.ApplyTotemBarLayout()
    if not windfurySlots[1] then return end
    local barFrame = windfurySlots.parent
    local barH = barFrame and barFrame:GetHeight() or BAR_W
    local iconSize = L("iconSize")
    local centerY = barH / 2 + L("iconsY")
    local timerOX = L("timerOffsetX")
    local timerOY = L("timerOffsetY")
    for i = 1, 4 do
        local slot = windfurySlots[i]
        local cx = SlotX(i)
        local iconFrame = slot.iconFrame
        if iconFrame then
            iconFrame:ClearAllPoints()
            iconFrame:SetSize(iconSize, iconSize)
            iconFrame:SetPoint("CENTER", iconFrame:GetParent(), "BOTTOMLEFT", cx, centerY)
            if iconFrame.icon then iconFrame.icon:SetSize(iconSize, iconSize) end
        end
        local textFrame = slot.textFrame
        if textFrame then
            textFrame:ClearAllPoints()
            textFrame:SetSize(iconSize + 20, 20)
            textFrame:SetPoint("CENTER", textFrame:GetParent(), "BOTTOMLEFT", cx + timerOX, centerY + timerOY)
        end
    end
end

local function OnEvent(_, event)
    if event == "PLAYER_TOTEM_UPDATE" then
        CreateWindfuryTotemSlots()
        UpdateWindfuryTotemBar()
        -- Show only the totem bar when placing totems (not the center ring / Windfury! text)
        local db = ShammyTime.GetDB and ShammyTime.GetDB()
        if db and db.wfRadialEnabled then
            local barFrame = ShammyTime.EnsureWindfuryTotemBarFrame and ShammyTime.EnsureWindfuryTotemBarFrame()
            if barFrame then barFrame:Show() end
        end
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

-- Apply timer font size from DB (called when user changes /st font totem N)
function ShammyTime.ApplyTotemBarFontSize()
    for i = 1, 4 do
        local slot = windfurySlots[i]
        local tf = slot and slot.textFrame
        if tf and tf.timerText then
            local db = ShammyTime.GetDB and ShammyTime.GetDB() or {}
            local fontSz = (db.fontTotemTimer and db.fontTotemTimer >= 6 and db.fontTotemTimer <= 28) and db.fontTotemTimer or TIMER_FONT_SIZE
            tf.timerText:SetFont("Fonts\\FRIZQT__.TTF", fontSz, "OUTLINE")
        end
    end
end

-- Expose for /st totem pos
function ShammyTime.PrintTotemBarPos()
    local barFrame = ShammyTime.EnsureWindfuryTotemBarFrame and ShammyTime.EnsureWindfuryTotemBarFrame()
    if not barFrame then
        print("ShammyTime: Totem bar not created. Place a totem or show circle (/st circle toggle) then try again.")
        return
    end
    print("|cff00ff00ShammyTime totem bar layout|r")
    print(string.format("  Layout: iconsX=%d, iconsY=%d, spread=%.2f, iconSize=%d, textX=%d, textY=%d", L("iconsX"), L("iconsY"), L("iconsSpread"), L("iconSize"), L("timerOffsetX"), L("timerOffsetY")))
    if barFrame.GetCenter and barFrame:GetCenter() then
        local bx, by = barFrame:GetCenter()
        print(string.format("  Totem bar frame (screen): x=%.1f  y=%.1f", bx, by))
    end
    for i = 1, 4 do
        local slot = windfurySlots[i]
        local iconFrame = slot and slot.iconFrame
        if iconFrame and iconFrame.GetLeft and iconFrame:GetLeft() then
            local left, bottom, w, h = iconFrame:GetLeft(), iconFrame:GetBottom(), iconFrame:GetWidth(), iconFrame:GetHeight()
            local cx, cy = iconFrame:GetCenter()
            print(string.format("  Slot %d: left=%.1f  bottom=%.1f  width=%.0f  height=%.0f  |  center x=%.1f  y=%.1f", i, left, bottom, w, h, cx or 0, cy or 0))
        else
            print(string.format("  Slot %d: (not created yet — place a totem or reload)", i))
        end
    end
end
