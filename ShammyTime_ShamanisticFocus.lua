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
local FOCUS_FADE_IN_DURATION = 0.3   -- off→on transition (~300ms so change is visible but quick)
local FOCUS_FADE_OUT_DURATION = 0.6
local FOCUS_HOLD_AFTER_OFF = 3.0  -- seconds to hold "on" art after proc ends before fading to off

local focusFrame
local lastFocusedActive = false
-- CLEU-tracked buff state: set true on SPELL_AURA_APPLIED/REFRESH, false on SPELL_AURA_REMOVED.
-- This is the PRIMARY buff indicator because UnitAura can lag behind CLEU by one or more frames
-- for proc-triggered buffs on TBC Anniversary clients. HasFocusedBuff() checks this first, then
-- falls back to UnitAura as a secondary source (e.g. after /reload when CLEU history is lost).
local focusedBuffFromCLEU = false
-- Test mode: proc every 10s, then fade out after hold (like real life)
local FOCUS_TEST_INTERVAL = 10
local FOCUS_TEST_HOLD = 4  -- seconds "on" before fading out
local focusTestTimer = nil
local focusTestFadeOutTimer = nil
local focusTestActive = false
local focusOverlayFadingOff = false  -- true while overlay is fading on->off; prevents interruption
local focusOverlayFadingOn = false   -- true while overlay is fading off->on; prevents restart
local shockCDPollTicker = nil  -- polls for shock CD expiry when Focused buff is up but shocks on CD

local DEFAULTS = {
    point = "CENTER",
    relativeTo = "UIParent",
    relativePoint = "CENTER",
    x = 0,
    y = -150,
    scale = 1.3,
    locked = false,
}

-- Prefer AceDB profile.focusFrame when available so options panel and ApplyAllConfigs stay in sync.
local function GetDB()
    local profile = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
    if profile and profile.focusFrame then
        local db = profile.focusFrame
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        return db
    end
    ShammyTimeDB = ShammyTimeDB or {}
    ShammyTimeDB.focusFrame = ShammyTimeDB.focusFrame or {}
    local df = DEFAULTS
    local db = ShammyTimeDB.focusFrame
    for k, v in pairs(df) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

-- Check for the "Focused" buff (Shamanistic Focus proc).
-- Primary source: CLEU-tracked state (focusedBuffFromCLEU), which updates instantly when the
-- combat log records SPELL_AURA_APPLIED / SPELL_AURA_REMOVED for spell 43339. This avoids the
-- UnitAura lag that causes the ON image to never show on first proc.
-- Secondary source: UnitAura scan, which catches the buff after /reload (no CLEU history) or
-- if the combat log event was missed. Checks spellId at both v10 and v11 positions.
local function HasFocusedBuff()
    -- CLEU is the authoritative, immediate source
    if focusedBuffFromCLEU then return true end
    -- Fallback: scan UnitAura (covers /reload, login with active buff, etc.)
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, v10, v11 = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if v10 == FOCUSED_BUFF_SPELL_ID or v11 == FOCUSED_BUFF_SPELL_ID then return true end
        if name == "Focused" then return true end
        if type(name) == "string" and name:find("Focus", 1, true) then return true end
    end
    return false
end

-- Shock spells (all share a 6-second cooldown in TBC). We only need to find one the player knows.
local SHOCK_SPELLS = { "Earth Shock", "Flame Shock", "Frost Shock" }
local GCD_THRESHOLD = 1.5  -- durations <= 1.5s are just the GCD, not a real shock cooldown

-- Returns true when shock spells are off cooldown (ready to cast), ignoring the GCD.
local function AreShocksReady()
    for _, spellName in ipairs(SHOCK_SPELLS) do
        local start, duration, enabled = GetSpellCooldown(spellName)
        if start then
            -- Found a shock spell the player knows
            if duration and duration > GCD_THRESHOLD then
                return false  -- on real cooldown (not just GCD)
            end
            return true  -- off cooldown (or only GCD remaining)
        end
    end
    -- No shock spell found in spellbook — assume ready
    return true
end

-- Forward-declare UpdateFocus so the poll timer can call it (defined later).
local UpdateFocus

-- SPELL_UPDATE_COOLDOWN doesn't reliably fire when cooldowns naturally expire in Classic WoW.
-- When the Focused buff is active but shocks are on CD, we poll every 0.1s until the CD expires
-- so the lamp lights up the moment shocks become usable again.
local function StopShockCDPoll()
    if shockCDPollTicker then
        shockCDPollTicker:Cancel()
        shockCDPollTicker = nil
    end
end
local function StartShockCDPoll()
    if shockCDPollTicker then return end  -- already polling
    shockCDPollTicker = C_Timer.NewTicker(0.1, function()
        if not focusTestActive then
            UpdateFocus()
        end
    end)
end

local function CreateFocusFrame()
    if focusFrame then return focusFrame end

    local db = GetDB()
    -- Images are 512×512; display at 80 so they look sharp and aren't cut off
    local iconSize = 80
    local padW, padH = 16, 24
    local f = CreateFrame("Frame", "ShammyTimeShamanisticFocus", UIParent)
    f:SetFrameStrata("LOW")
    f:SetSize(iconSize + padW, iconSize + padH)
    f:SetClipsChildren(false)
    f:SetScale(db.scale or 0.8)
    -- Use frame reference so position sticks; never re-set position in UpdateFocus
    local relTo = (db.relativeTo and _G[db.relativeTo]) or UIParent
    f:SetPoint(db.point or "CENTER", relTo, db.relativePoint or "CENTER", db.x or 0, db.y or -150)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    local mainDb = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
    f:EnableMouse(not (mainDb and mainDb.locked))
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        local mainDb = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
        if mainDb and mainDb.locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = GetDB()
        local point, relTo, relativePoint, x, y = self:GetPoint(1)
        db.point = point
        db.relativePoint = relativePoint
        db.x = x
        db.y = y
        db.relativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent"
        -- Keep modules.shamanisticFocus.pos in sync so ApplyAllConfigs
        -- doesn't overwrite focusFrame with stale default values on reload.
        local profile = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
        if profile and profile.modules and profile.modules.shamanisticFocus then
            local pos = profile.modules.shamanisticFocus.pos
            if not pos then
                pos = {}
                profile.modules.shamanisticFocus.pos = pos
            end
            pos.point = point
            pos.relPoint = relativePoint
            pos.x = x
            pos.y = y
        end
    end)

    f.baseIconSize = iconSize

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
    -- Pulse effect intentionally disabled; keep helpers for cleanup compatibility.
    f.focusPulseTicker = nil
    local function stopPulseTicker()
        if f.focusPulseTicker then
            f.focusPulseTicker:Cancel()
            f.focusPulseTicker = nil
        end
        local sz = f.baseIconSize
        f.focusOff:SetSize(sz, sz)
        f.focusOn:SetSize(sz, sz)
    end
    local function startPulse()
        stopPulseTicker()
    end
    local function fadeInOn()
        stopAlphaTicker()
        stopPulseTicker()
        focusOverlayFadingOff = false  -- cancel any in-progress fade-out
        focusOverlayFadingOn = true
        local startAlpha = focusOn:GetAlpha()
        local startTime = GetTime()
        f.focusAlphaTicker = C_Timer.NewTicker(1/60, function()
            local t = (GetTime() - startTime) / FOCUS_FADE_IN_DURATION
            if t >= 1 then
                focusOn:SetAlpha(1)
                stopAlphaTicker()
                focusOverlayFadingOn = false
                return
            end
            focusOn:SetAlpha(startAlpha + (1 - startAlpha) * t)
        end)
    end
    local function fadeOutOn(onComplete)
        stopAlphaTicker()
        stopPulseTicker()
        focusOverlayFadingOn = false  -- cancel any in-progress fade-in
        local startAlpha = focusOn:GetAlpha()
        local startTime = GetTime()
        f.focusAlphaTicker = C_Timer.NewTicker(1/60, function()
            local t = (GetTime() - startTime) / FOCUS_FADE_OUT_DURATION
            if t >= 1 then
                focusOn:SetAlpha(0)
                stopAlphaTicker()
                if onComplete then onComplete() end
                return
            end
            focusOn:SetAlpha(startAlpha * (1 - t))
        end)
    end
    f.fadeInOn = fadeInOn
    f.fadeOutOn = fadeOutOn
    f.startPulse = startPulse
    f.stopAlphaTicker = stopAlphaTicker
    f.stopPulseTicker = stopPulseTicker

    focusFrame = f
    return f
end

-- Simple light logic: ON when buff is on AND shocks off CD, OFF otherwise, with smooth animations.
-- hasBuffOverride: hint from main addon, but we always verify with HasFocusedBuff() for ground truth.
UpdateFocus = function(hasBuffOverride)
    local f = CreateFocusFrame()
    
    -- Always check the REAL buff state - this is ground truth
    local buffIsOn = HasFocusedBuff()
    
    -- Only trust override if we're NOT already in a fade-off sequence
    -- (fade-off means we saw the buff end via UNIT_AURA, so we have fresher info than the override)
    if hasBuffOverride == true and not buffIsOn and not focusOverlayFadingOff then
        buffIsOn = true
    end
    
    -- Even with the Focused buff active, only glow when shocks are off cooldown.
    -- This makes the lamp signal "you can use your cheap shock RIGHT NOW."
    if buffIsOn and not AreShocksReady() then
        buffIsOn = false
        -- Buff is up but shocks on CD — poll until CD expires so the lamp re-lights.
        StartShockCDPoll()
    else
        -- Either buff is off or shocks are ready; no need to poll.
        StopShockCDPoll()
    end
    
    local currentAlpha = f.focusOn:GetAlpha() or 0
    
    -- BUFF IS ON: show "on" overlay
    if buffIsOn then
        -- Cancel any fade-out in progress
        if focusOverlayFadingOff then
            focusOverlayFadingOff = false
            f.stopAlphaTicker()
            f.stopPulseTicker()
        end
        ShammyTime.focusFadeHoldUntil = nil
        
        -- If already fading in, let it continue
        if focusOverlayFadingOn then
            lastFocusedActive = true
            return
        end
        
        if currentAlpha < 0.99 then
            -- Need to show "on" - fade in from current alpha
            f.fadeInOn()
        end
        lastFocusedActive = true
        return
    end
    
    -- BUFF IS OFF: show "off" overlay (fade out if needed)
    
    -- If we're already fading out, let it continue
    if focusOverlayFadingOff then
        lastFocusedActive = false
        return
    end
    
    -- If we were fading in but buff went off, cancel and fade out
    if focusOverlayFadingOn then
        focusOverlayFadingOn = false
        f.stopAlphaTicker()
        f.stopPulseTicker()
        -- Start fade out from current position
        focusOverlayFadingOff = true
        f.fadeOutOn(function()
            focusOverlayFadingOff = false
            ShammyTime.focusFadeHoldUntil = GetTime() + FOCUS_HOLD_AFTER_OFF
            if ShammyTime.RequestFocusFadeUpdate then
                ShammyTime.RequestFocusFadeUpdate(FOCUS_HOLD_AFTER_OFF)
            end
        end)
        lastFocusedActive = false
        return
    end
    
    -- If buff just ended (was on, now off), start the fade-out animation
    if lastFocusedActive or currentAlpha > 0.01 then
        f.stopAlphaTicker()
        f.stopPulseTicker()
        focusOverlayFadingOff = true
        f.fadeOutOn(function()
            focusOverlayFadingOff = false
            -- After overlay fade completes, hold the "off" art visible before frame fades
            ShammyTime.focusFadeHoldUntil = GetTime() + FOCUS_HOLD_AFTER_OFF
            if ShammyTime.RequestFocusFadeUpdate then
                ShammyTime.RequestFocusFadeUpdate(FOCUS_HOLD_AFTER_OFF)
            end
        end)
        lastFocusedActive = false
        return
    end
    
    lastFocusedActive = false
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
        focusFrame.stopPulseTicker()
        focusFrame.focusOn:SetAlpha(0)
        focusFrame.fadeInOn()
        if focusTestFadeOutTimer then focusTestFadeOutTimer:Cancel() end
        -- After hold, fade "on" to "off" (same as real proc)
        focusTestFadeOutTimer = C_Timer.NewTimer(FOCUS_TEST_HOLD, function()
            focusTestFadeOutTimer = nil
            if focusFrame and focusTestActive then
                focusFrame.stopAlphaTicker()
                focusFrame.stopPulseTicker()
                focusOverlayFadingOff = true
                focusFrame.fadeOutOn(function()
                    focusOverlayFadingOff = false
                end)
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
    -- Clean up any in-progress fade state from test
    focusOverlayFadingOff = false
    focusOverlayFadingOn = false
    StopShockCDPoll()
    if focusFrame then
        focusFrame.stopAlphaTicker()
        focusFrame.stopPulseTicker()
    end
    -- Sync to real buff state
    UpdateFocus()
end

function ShammyTime.IsShamanisticFocusTestActive()
    return focusTestActive
end

-- Apply current scale from saved settings (called from /st focus scale X). Re-apply saved position so the frame does not appear to move when scaling.
function ShammyTime.ApplyShamanisticFocusScale()
    local f = focusFrame
    if not f then return end
    local db = GetDB()
    local s = (db.scale and db.scale >= 0.5 and db.scale <= 2) and db.scale or 0.8
    f:SetScale(s)
    -- Keep position fixed: re-apply saved anchor so scale change doesn't shift the frame
    local relTo = (db.relativeTo and _G[db.relativeTo]) or UIParent
    if relTo then
        f:ClearAllPoints()
        f:SetPoint(db.point or "CENTER", relTo, db.relativePoint or "CENTER", db.x or 0, db.y or -150)
    end
end

-- Defer creation until ADDON_LOADED so SavedVariables (position) are loaded first.
-- Also register COMBAT_LOG_EVENT_UNFILTERED as a secondary detection path: UNIT_AURA can
-- be delayed or missing for proc-triggered buffs on some TBC Anniversary clients, so we
-- also detect SPELL_AURA_APPLIED / SPELL_AURA_REMOVED for "Focused" (spell 43339) directly
-- from the combat log. This fires immediately on proc and explains the "works on second proc"
-- symptom: the first crit's UNIT_AURA was delayed, but the second crit's combat log events
-- cause additional aura traffic that finally triggers detection.
local playerGUID  -- cached on ADDON_LOADED; UnitGUID("player") is not available at file load time
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
if eventFrame.RegisterUnitEvent then
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
else
    eventFrame:RegisterEvent("UNIT_AURA")
end
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "ShammyTime" then
        eventFrame:UnregisterEvent("ADDON_LOADED")
        playerGUID = UnitGUID and UnitGUID("player") or nil
        CreateFocusFrame()
        focusFrame:Show()
        UpdateFocus()
        return
    end
    if event == "UNIT_AURA" then
        if arg1 ~= "player" then return end
        if not focusTestActive then UpdateFocus() end
        return
    end
    if event == "SPELL_UPDATE_COOLDOWN" then
        -- Re-evaluate lamp: shock cooldown may have just expired while Focused buff is still up
        if not focusTestActive then UpdateFocus() end
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" and not focusTestActive then
        -- CombatLogGetCurrentEventInfo() returns: timestamp, subevent, hideCaster,
        -- sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
        -- destGUID, destName, destFlags, destRaidFlags, spellId, ...
        if not CombatLogGetCurrentEventInfo then return end
        local _, subevent, _, _, _, _, _, destGUID, _, _, _, spellId = CombatLogGetCurrentEventInfo()
        if spellId ~= FOCUSED_BUFF_SPELL_ID then return end
        if subevent ~= "SPELL_AURA_APPLIED" and subevent ~= "SPELL_AURA_REMOVED"
           and subevent ~= "SPELL_AURA_REFRESH" then return end
        -- Verify it's on the player (not a party member with same talent)
        if not playerGUID then playerGUID = UnitGUID and UnitGUID("player") or nil end
        if destGUID ~= playerGUID then return end
        -- Update CLEU-tracked state BEFORE calling UpdateFocus / UpdateAllElementsFadeState
        -- so HasFocusedBuff() returns the correct value immediately (UnitAura may still lag).
        if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
            focusedBuffFromCLEU = true
        elseif subevent == "SPELL_AURA_REMOVED" then
            focusedBuffFromCLEU = false
        end
        UpdateFocus()
        -- Also nudge the main addon's fade system so frame alpha updates immediately
        if ShammyTime.UpdateAllElementsFadeState then
            ShammyTime.UpdateAllElementsFadeState()
        end
        return
    end
end)

ShammyTime.HasFocusedBuff = HasFocusedBuff
ShammyTime.AreShocksReady = AreShocksReady
ShammyTime.GetShamanisticFocusFrame = function() return focusFrame end
-- Called from main addon after setting focus frame alpha. Pass hasBuff when main addon already computed it so "on" art shows even if UNIT_AURA order lags.
ShammyTime.UpdateShamanisticFocusVisual = UpdateFocus
