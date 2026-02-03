-- ShammyTime_ShamanisticFocus.lua
-- Standalone Shamanistic Focus proc indicator: off/on images with quick fade-in and slow fade-out.
-- Own frame, movable; does not touch legacy ShammyTime.lua Focus slot.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local M = ShammyTime_Media
if not M then return end

local TEX = M.TEX
local FOCUSED_BUFF_SPELL_ID = 43339  -- "Focused" (Shamanistic Focus proc), TBC
local FOCUS_FADE_IN_DURATION = 0.18
local FOCUS_FADE_OUT_DURATION = 0.6

local focusFrame
local lastFocusedActive = false
-- Test mode: proc every 10s, then fade out after hold (like real life)
local FOCUS_TEST_INTERVAL = 10
local FOCUS_TEST_HOLD = 4  -- seconds "on" before fading out
local focusTestTimer = nil
local focusTestFadeOutTimer = nil
local focusTestActive = false

local DEFAULTS = {
    point = "CENTER",
    relativeTo = "UIParent",
    relativePoint = "CENTER",
    x = 0,
    y = -150,
    scale = 1.0,
    locked = false,
}

local function GetDB()
    ShammyTimeDB = ShammyTimeDB or {}
    ShammyTimeDB.focusFrame = ShammyTimeDB.focusFrame or {}
    local df = DEFAULTS
    local db = ShammyTimeDB.focusFrame
    for k, v in pairs(df) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

-- WoW UnitAura return order can differ: 10-return has spellId at v10, 11-return at v11. Match by spellId or name.
local function HasFocusedBuff()
    for i = 1, 40 do
        local v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11 = UnitAura("player", i, "HELPFUL")
        if not v1 then break end
        local spellId = (type(v4) == "string") and v10 or v11
        if spellId == FOCUSED_BUFF_SPELL_ID then return true end
        if v1 == "Focused" then return true end
        if v1 and type(v1) == "string" and v1:find("Focus", 1, true) then return true end
    end
    return false
end

local function CreateFocusFrame()
    if focusFrame then return focusFrame end

    local db = GetDB()
    -- Images are 256x256; display at 80 so they look sharp and aren't cut off
    local iconSize = 80
    local padW, padH = 16, 24
    local f = CreateFrame("Frame", "ShammyTimeShamanisticFocus", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetSize(iconSize + padW, iconSize + padH)
    f:SetClipsChildren(false)
    f:SetScale(db.scale or 1)
    -- Use frame reference so position sticks; never re-set position in UpdateFocus
    local relTo = (db.relativeTo and _G[db.relativeTo]) or UIParent
    f:SetPoint(db.point or "CENTER", relTo, db.relativePoint or "CENTER", db.x or 0, db.y or -150)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        local mainDb = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
        if mainDb and mainDb.locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = GetDB()
        db.point, _, db.relativePoint, db.x, db.y = self:GetPoint(1)
        local relTo = select(2, self:GetPoint(1))
        db.relativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent"
    end)

    -- Shadow behind icon: same file as totems (wf_center_shadow.tga), custom size/offset/tint for this frame
    local FOCUS_SHADOW_SIZE = 90       -- slightly larger than 80px icon so soft edge shows
    local FOCUS_SHADOW_OFFSET_X = 2     -- drop shadow offset right
    local FOCUS_SHADOW_OFFSET_Y = -6    -- drop shadow offset down
    local FOCUS_SHADOW_TINT = { 0.1, 0.08, 0.1, 0.42 }  -- r, g, b, a (custom for Shamanistic Focus)
    local focusShadow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    focusShadow:SetSize(FOCUS_SHADOW_SIZE, FOCUS_SHADOW_SIZE)
    focusShadow:SetPoint("CENTER", FOCUS_SHADOW_OFFSET_X, FOCUS_SHADOW_OFFSET_Y)
    focusShadow:SetTexture(TEX.CENTER_SHADOW)
    focusShadow:SetTexCoord(0, 1, 0, 1)
    focusShadow:SetVertexColor(FOCUS_SHADOW_TINT[1], FOCUS_SHADOW_TINT[2], FOCUS_SHADOW_TINT[3], FOCUS_SHADOW_TINT[4])
    focusShadow:Show()
    f.focusShadow = focusShadow

    -- Base: "off" image always visible
    local focusOff = f:CreateTexture(nil, "ARTWORK")
    focusOff:SetSize(iconSize, iconSize)
    focusOff:SetPoint("CENTER", 0, 2)  -- nudge up so bottom isn't clipped
    focusOff:SetTexCoord(0, 1, 0, 1)
    focusOff:SetTexture(TEX.FOCUS_OFF)
    focusOff:SetVertexColor(1, 1, 1)
    focusOff:SetAlpha(1)
    focusOff:Show()
    f.focusOff = focusOff

    -- Overlay: "on" image on OVERLAY layer so it draws on top; alpha animated
    local focusOn = f:CreateTexture(nil, "OVERLAY")
    focusOn:SetSize(iconSize, iconSize)
    focusOn:SetPoint("CENTER", 0, 2)
    focusOn:SetTexCoord(0, 1, 0, 1)
    focusOn:SetTexture(TEX.FOCUS_ON)
    focusOn:SetVertexColor(1, 1, 1)
    focusOn:SetAlpha(0)
    focusOn:Show()
    f.focusOn = focusOn

    -- Manual alpha ticker (more reliable than AnimationGroup on some clients)
    f.focusAlphaTicker = nil
    local function stopAlphaTicker()
        if f.focusAlphaTicker then
            f.focusAlphaTicker:Cancel()
            f.focusAlphaTicker = nil
        end
    end
    local function fadeInOn()
        stopAlphaTicker()
        local startAlpha = focusOn:GetAlpha()
        local startTime = GetTime()
        f.focusAlphaTicker = C_Timer.NewTicker(1/60, function()
            local t = (GetTime() - startTime) / FOCUS_FADE_IN_DURATION
            if t >= 1 then
                focusOn:SetAlpha(1)
                stopAlphaTicker()
                return
            end
            focusOn:SetAlpha(startAlpha + (1 - startAlpha) * t)
        end)
    end
    local function fadeOutOn()
        stopAlphaTicker()
        local startAlpha = focusOn:GetAlpha()
        local startTime = GetTime()
        f.focusAlphaTicker = C_Timer.NewTicker(1/60, function()
            local t = (GetTime() - startTime) / FOCUS_FADE_OUT_DURATION
            if t >= 1 then
                focusOn:SetAlpha(0)
                stopAlphaTicker()
                return
            end
            focusOn:SetAlpha(startAlpha * (1 - t))
        end)
    end
    f.fadeInOn = fadeInOn
    f.fadeOutOn = fadeOutOn
    f.stopAlphaTicker = stopAlphaTicker

    focusFrame = f
    return f
end

local function UpdateFocus()
    local f = CreateFocusFrame()
    -- Only update alpha; never touch frame position so user's placement is kept
    local hasFocused = HasFocusedBuff()

    if hasFocused and not lastFocusedActive then
        f.stopAlphaTicker()
        f.focusOn:SetAlpha(0)
        f.fadeInOn()
    elseif not hasFocused and lastFocusedActive then
        f.stopAlphaTicker()
        f.focusOn:SetAlpha(1)
        f.fadeOutOn()
    elseif not hasFocused then
        f.stopAlphaTicker()
        f.focusOn:SetAlpha(0)
    end
    lastFocusedActive = hasFocused
end

-- Test mode: proc every 10s, quick fade in then hold then slow fade out (like real life)
function ShammyTime.StartShamanisticFocusTest()
    if focusTestActive then return end
    focusTestActive = true
    local f = CreateFocusFrame()
    f:Show()
    f.stopAlphaTicker()
    f.focusOn:SetAlpha(0)
    lastFocusedActive = false
    local function doProc()
        if not focusFrame or not focusTestActive then return end
        focusFrame.stopAlphaTicker()
        focusFrame.focusOn:SetAlpha(0)
        focusFrame.fadeInOn()
        if focusTestFadeOutTimer then focusTestFadeOutTimer:Cancel() end
        focusTestFadeOutTimer = C_Timer.NewTimer(FOCUS_TEST_HOLD, function()
            focusTestFadeOutTimer = nil
            if focusFrame and focusTestActive then
                focusFrame.stopAlphaTicker()
                focusFrame.focusOn:SetAlpha(1)
                focusFrame.fadeOutOn()
            end
        end)
    end
    doProc()  -- first proc immediately
    focusTestTimer = C_Timer.NewTicker(FOCUS_TEST_INTERVAL, doProc)
end

function ShammyTime.StopShamanisticFocusTest()
    if not focusTestActive then return end
    focusTestActive = false
    if focusTestTimer then
        focusTestTimer:Cancel()
        focusTestTimer = nil
    end
    if focusTestFadeOutTimer then
        focusTestFadeOutTimer:Cancel()
        focusTestFadeOutTimer = nil
    end
    UpdateFocus()
end

function ShammyTime.IsShamanisticFocusTestActive()
    return focusTestActive
end

-- Apply current scale from saved settings (called from /st focus scale X)
function ShammyTime.ApplyShamanisticFocusScale()
    local f = focusFrame
    if not f then return end
    local db = GetDB()
    local s = (db.scale and db.scale >= 0.5 and db.scale <= 2) and db.scale or 1
    f:SetScale(s)
end

-- Defer creation until ADDON_LOADED so SavedVariables (position) are loaded first
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
if eventFrame.RegisterUnitEvent then
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
else
    eventFrame:RegisterEvent("UNIT_AURA")
end
eventFrame:SetScript("OnEvent", function(_, event, unit, addon)
    if event == "ADDON_LOADED" and addon == "ShammyTime" then
        eventFrame:UnregisterEvent("ADDON_LOADED")
        CreateFocusFrame()
        focusFrame:Show()
        UpdateFocus()
        return
    end
    if event == "UNIT_AURA" and unit ~= "player" then return end
    if event == "UNIT_AURA" and not focusTestActive then UpdateFocus() end
end)
