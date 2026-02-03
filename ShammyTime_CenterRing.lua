-- ShammyTime_CenterRing.lua
-- Phase 1: Center ring only — load 4 layered textures, stack them, add /wfcenter and /wfproc.
-- No satellites, no combat log. Purely asset + animation integration test.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local M = ShammyTime_Media
if not M then return end

local TEX = M.TEX
local centerFrame
local totemBarFrame

-- How long to keep satellite numbers visible after proc before starting chain fade (seconds)
local WF_NUMBERS_HOLD_BEFORE_FADE = 2
-- How long "Windfury!" + total text stays fully visible after proc anim ends before fading (seconds)
local WF_TEXT_HOLD_BEFORE_FADE = 1

-- Center ring (and all satellites, as children) scale; read/write via GetDB().wfRadialScale (0.5–2).
local function GetRadialScale()
    local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB() or {}
    return (db.wfRadialScale and db.wfRadialScale >= 0.5 and db.wfRadialScale <= 2) and db.wfRadialScale or 0.7
end

local function GetTotemBarScale()
    local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB() or {}
    return (db.wfTotemBarScale and db.wfTotemBarScale >= 0.5 and db.wfTotemBarScale <= 2) and db.wfTotemBarScale or 1.0
end

local function FormatNum(n)
    if not n or n < 0 then return "0" end
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

local function ApplyCenterPosition(f)
    local pos = ShammyTime.GetRadialPositionDB and ShammyTime.GetRadialPositionDB()
    if not pos or not pos.center then return end
    local c = pos.center
    local relTo = (c.relativeTo and _G[c.relativeTo]) or UIParent
    if relTo then
        f:ClearAllPoints()
        f:SetPoint(c.point or "CENTER", relTo, c.relativePoint or "CENTER", c.x or 0, c.y or 0)
    end
end

local function SaveCenterPosition(f)
    if not ShammyTime.GetRadialPositionDB then return end
    local pos = ShammyTime.GetRadialPositionDB()
    local point, relTo, relativePoint, x, y = f:GetPoint(1)
    pos.center = {
        point = point,
        relativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent",
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function CreateCenterRingFrame()
    if centerFrame then return centerFrame end

    local f = CreateFrame("Frame", "ShammyTimeCenterRing", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetSize(260, 260)
    f:SetScale(GetRadialScale())
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    ApplyCenterPosition(f)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB().locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveCenterPosition(self)
    end)
    -- Right-click: show options menu (reset numbers); hover shows numbers (quick-peek)
    f:SetScript("OnEnter", function(self)
        if ShammyTime.OnRadialHoverEnter then ShammyTime.OnRadialHoverEnter() end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Right-click to reset numbers")
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function()
        if ShammyTime.OnRadialHoverLeave then ShammyTime.OnRadialHoverLeave() end
        GameTooltip:Hide()
    end)
    f:SetScript("OnMouseDown", function(self, button)
        if button ~= "RightButton" then return end
        if ShammyTime and ShammyTime.ResetWindfurySession then
            ShammyTime.ResetWindfurySession()
        end
        if ShammyTime then ShammyTime.lastProcTotal = 0 end
        if centerFrame and centerFrame.total then
            centerFrame.total:SetText("TOTAL: 0")
        end
        -- Refresh satellite numbers so they show reset values (0 / –)
        if ShammyTime.UpdateSatelliteValues and ShammyTime_Windfury_GetStats then
            ShammyTime.UpdateSatelliteValues(ShammyTime_Windfury_GetStats())
        end
        print("ShammyTime: Statistics have been reset.")
    end)
    f:Hide()

    -- Ring subframe: only this scales during proc so totem bar stays fixed; satellites parent here to move with ring
    local ringFrame = CreateFrame("Frame", nil, f)
    ringFrame:SetSize(260, 260)
    ringFrame:SetPoint("CENTER", f, "CENTER", 0, 0)
    ringFrame:SetFrameLevel(1)
    f.ringFrame = ringFrame

    -- 0. Shadow behind circle (wf_center_shadow.tga), custom for center ring: soft, scales with proc
    local ringShadowSize = 280
    local ringShadowOffsetY = -8
    ringFrame.shadow = ringFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
    ringFrame.shadow:SetSize(ringShadowSize, ringShadowSize)
    ringFrame.shadow:SetPoint("CENTER", 0, ringShadowOffsetY)
    ringFrame.shadow:SetTexture(TEX.CENTER_SHADOW)
    ringFrame.shadow:SetTexCoord(0, 1, 0, 1)
    ringFrame.shadow:SetVertexColor(1, 1, 1, 0.26)

    -- 1. BACKGROUND: wf_center_bg.tga (on ring so it scales with proc)
    ringFrame.bg = ringFrame:CreateTexture(nil, "BACKGROUND")
    ringFrame.bg:SetAllPoints(ringFrame)
    ringFrame.bg:SetTexture(TEX.CENTER_BG)
    ringFrame.bg:SetAlpha(1)

    -- 2. ARTWORK: wf_center_energy.tga (low alpha, ADD blend)
    ringFrame.energy = ringFrame:CreateTexture(nil, "ARTWORK")
    ringFrame.energy:SetAllPoints(ringFrame)
    ringFrame.energy:SetTexture(TEX.CENTER_ENERGY)
    ringFrame.energy:SetAlpha(0.12)
    ringFrame.energy:SetBlendMode("ADD")

    -- 3. BORDER: wf_center_border.tga
    ringFrame.border = ringFrame:CreateTexture(nil, "BORDER")
    ringFrame.border:SetAllPoints(ringFrame)
    ringFrame.border:SetTexture(TEX.CENTER_BORDER)
    ringFrame.border:SetAlpha(1)

    -- 4. OVERLAY: wf_center_runes.tga (on ring so it scales and rotates with proc)
    ringFrame.runes = ringFrame:CreateTexture(nil, "OVERLAY")
    ringFrame.runes:SetTexture(TEX.CENTER_RUNES)
    ringFrame.runes:SetAlpha(0.18)
    local runesInset = 20  -- smaller inset = larger runes ring (more overlay on border)
    ringFrame.runes:SetSize(260 - runesInset * 2, 260 - runesInset * 2)
    ringFrame.runes:SetPoint("CENTER", 0, 12)  -- slightly up

    -- Text as child of main frame so it stays crisp during proc (still scales with /wfresize)
    local textFrame = CreateFrame("Frame", "ShammyTimeCenterRingText", f)
    textFrame:SetFrameStrata("DIALOG")
    textFrame:SetFrameLevel(10)
    textFrame:SetSize(260, 260)
    textFrame:SetPoint("CENTER", f, "CENTER", 0, 0)
    textFrame:EnableMouse(false)  -- allow drag to pass through to center when clicking text
    textFrame:Hide()
    f.textFrame = textFrame

    -- Fade-out animation: when proc ends, fade text then hide (so "Windfury!" only visible during proc)
    local fadeOutAg = textFrame:CreateAnimationGroup()
    local aOut = fadeOutAg:CreateAnimation("Alpha")
    aOut:SetFromAlpha(1)
    aOut:SetToAlpha(0)
    aOut:SetDuration(1.2)  -- slow fade out for "Windfury!" + total
    aOut:SetSmoothing("OUT")
    fadeOutAg:SetScript("OnFinished", function()
        textFrame:SetAlpha(1)
        textFrame:Hide()
    end)
    textFrame.fadeOutAnim = fadeOutAg

    f.title = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("CENTER", 0, 17)
    f.title:SetText("Windfury!")
    f.title:SetTextColor(1, 0.9, 0.4)
    f.title:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    f.titleRestColor = {1, 0.9, 0.4}
    f.titleFlashColor = {1, 1, 1}  -- bright white flash

    f.total = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.total:SetPoint("CENTER", 0, -4)
    f.total:SetText("TOTAL: 3245")
    f.total:SetTextColor(1, 1, 1)
    f.total:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    f.totalRestColor = {1, 1, 1}
    f.totalFlashColor = {1, 1, 0.5}  -- bright yellow flash

    -- Proc pulse: ring scale is driven by the same ticker as satellites (quick expand, slow retract).
    -- Animation group only does energy, runes, rotation so the ring scale doesn't snap back.
    local pop = 1.18

    local function BuildProcAnim(rf)
        local g = rf:CreateAnimationGroup()

        -- Energy: instant flash to full, then long soften (lightning hit → fade)
        local aFlash = g:CreateAnimation("Alpha")
        aFlash:SetTarget(rf.energy)
        aFlash:SetOrder(1)
        aFlash:SetDuration(0.02)
        aFlash:SetFromAlpha(0.12)
        aFlash:SetToAlpha(1.0)

        local aSoft = g:CreateAnimation("Alpha")
        aSoft:SetTarget(rf.energy)
        aSoft:SetOrder(2)
        aSoft:SetDuration(0.35)
        aSoft:SetFromAlpha(1.0)
        aSoft:SetToAlpha(0.18)
        aSoft:SetSmoothing("OUT")

        -- Runes: quick flash then fade (they "light up" with the strike)
        local runeFlash = g:CreateAnimation("Alpha")
        runeFlash:SetTarget(rf.runes)
        runeFlash:SetOrder(1)
        runeFlash:SetDuration(0.02)
        runeFlash:SetFromAlpha(0.18)
        runeFlash:SetToAlpha(0.5)

        local runeSoft = g:CreateAnimation("Alpha")
        runeSoft:SetTarget(rf.runes)
        runeSoft:SetOrder(2)
        runeSoft:SetDuration(0.3)
        runeSoft:SetFromAlpha(0.5)
        runeSoft:SetToAlpha(0.18)
        runeSoft:SetSmoothing("OUT")

        -- Rune rotation: visible spin on proc
        local rot = g:CreateAnimation("Rotation")
        rot:SetTarget(rf.runes)
        rot:SetOrder(1)
        rot:SetDuration(0.7)
        rot:SetSmoothing("OUT")
        rot:SetDegrees(180)

        return g
    end

    ringFrame.procAnim = BuildProcAnim(ringFrame)
    local ag = ringFrame.procAnim
    local function onProcAnimEnd()
        if ringFrame.satelliteTicker then
            ringFrame.satelliteTicker:Cancel()
            ringFrame.satelliteTicker = nil
        end
        ringFrame:SetScale(1)
        if ShammyTime.ResetSatellitePositions then ShammyTime.ResetSatellitePositions() end
        local db = ShammyTime.GetDB and ShammyTime.GetDB() or {}
        local center = ringFrame:GetParent()
        if not center then return end
        -- Center "Windfury!" text: hold 1s then start slow fade out (unless always show numbers)
        if not db.wfAlwaysShowNumbers and center.textFrame and center.textFrame:IsShown() and center.textFrame.fadeOutAnim then
            center.textFrame.fadeOutAnim:Stop()
            center.textFrame:SetAlpha(1)
            if center.wfTextFadeTimer then center.wfTextFadeTimer:Cancel() end
            center.wfTextFadeTimer = C_Timer.NewTimer(WF_TEXT_HOLD_BEFORE_FADE, function()
                center.wfTextFadeTimer = nil
                if not center or not center.textFrame or not center.textFrame:IsShown() or not center.textFrame.fadeOutAnim then return end
                center.textFrame.fadeOutAnim:Stop()
                center.textFrame:SetAlpha(1)
                center.textFrame.fadeOutAnim:Play()
            end)
        end
        if db.wfAlwaysShowNumbers then return end
        -- Satellite numbers: wait 5s then start chain fade
        if center.wfFadeDelayTimer then
            center.wfFadeDelayTimer:Cancel()
            center.wfFadeDelayTimer = nil
        end
        center.wfFadeDelayTimer = C_Timer.NewTimer(WF_NUMBERS_HOLD_BEFORE_FADE, function()
            center.wfFadeDelayTimer = nil
            if not center or not center:IsShown() then return end
            if ShammyTime.StartSatelliteTextChainFade then ShammyTime.StartSatelliteTextChainFade() end
        end)
    end
    ag:SetScript("OnFinished", onProcAnimEnd)
    ag:SetScript("OnStop", onProcAnimEnd)

    -- Text color flash (no scaling): instant flash to bright, then fade back
    function f:FlashText()
        -- Instant flash to bright color
        self.title:SetTextColor(unpack(self.titleFlashColor))
        self.total:SetTextColor(unpack(self.totalFlashColor))
        -- Fade back to rest color over 0.4s
        local steps = 20
        local interval = 0.4 / steps
        local step = 0
        if self.textFlashTicker then self.textFlashTicker:Cancel() end
        self.textFlashTicker = C_Timer.NewTicker(interval, function()
            step = step + 1
            local t = step / steps  -- 0 to 1
            -- Lerp from flash to rest
            local tr = self.titleFlashColor[1] + (self.titleRestColor[1] - self.titleFlashColor[1]) * t
            local tg = self.titleFlashColor[2] + (self.titleRestColor[2] - self.titleFlashColor[2]) * t
            local tb = self.titleFlashColor[3] + (self.titleRestColor[3] - self.titleFlashColor[3]) * t
            self.title:SetTextColor(tr, tg, tb)
            local vr = self.totalFlashColor[1] + (self.totalRestColor[1] - self.totalFlashColor[1]) * t
            local vg = self.totalFlashColor[2] + (self.totalRestColor[2] - self.totalFlashColor[2]) * t
            local vb = self.totalFlashColor[3] + (self.totalRestColor[3] - self.totalFlashColor[3]) * t
            self.total:SetTextColor(vr, vg, vb)
            if step >= steps then
                self.textFlashTicker:Cancel()
                self.textFlashTicker = nil
                self.title:SetTextColor(unpack(self.titleRestColor))
                self.total:SetTextColor(unpack(self.totalRestColor))
            end
        end)
    end
    centerFrame = f
    -- Restore visibility after reload if radial was shown: show numbers so user sees it's not reset, then fade out
    local db = ShammyTime.GetDB and ShammyTime.GetDB()
    if db and db.wfRadialShown then
        f:Show()
        f.textFrame:Show()
        f.total:SetText("TOTAL: " .. FormatNum(ShammyTime and ShammyTime.lastProcTotal or 0))
        local bar = ShammyTime.EnsureWindfuryTotemBarFrame and ShammyTime.EnsureWindfuryTotemBarFrame()
        if bar then bar:Show() end
        -- Update satellite values (empty/0 will hide text per satellite), then after hold start fade
        C_Timer.After(0, function()
            local stats = (ShammyTime_Windfury_GetStats and ShammyTime_Windfury_GetStats()) or nil
            if ShammyTime.UpdateSatelliteValues then ShammyTime.UpdateSatelliteValues(stats) end
            local db2 = ShammyTime.GetDB and ShammyTime.GetDB()
            if not db2 or db2.wfAlwaysShowNumbers then return end
            C_Timer.After(WF_NUMBERS_HOLD_BEFORE_FADE, function()
                if not f or not f:IsShown() then return end
                if f.textFrame and f.textFrame:IsShown() and f.textFrame.fadeOutAnim then
                    f.textFrame.fadeOutAnim:Stop()
                    f.textFrame:SetAlpha(1)
                    f.textFrame.fadeOutAnim:Play()
                end
                if ShammyTime.StartSatelliteTextChainFade then ShammyTime.StartSatelliteTextChainFade() end
            end)
        end)
    end
    return f
end

-- Ensure center ring exists (for satellites that anchor to it)
function ShammyTime.EnsureCenterRingExists()
    return CreateCenterRingFrame()
end

-- Standalone totem bar (separate from center ring; position saved per character)
local function ApplyTotemBarPosition(barFrame)
    local pos = ShammyTime.GetRadialPositionDB and ShammyTime.GetRadialPositionDB()
    if not pos or not pos.totemBar then return end
    local t = pos.totemBar
    local relTo = (t.relativeTo and _G[t.relativeTo]) or UIParent
    if relTo then
        barFrame:ClearAllPoints()
        barFrame:SetPoint(t.point or "CENTER", relTo, t.relativePoint or "CENTER", t.x or 0, t.y or 0)
    end
end

local function SaveTotemBarPosition(barFrame)
    if not ShammyTime.GetRadialPositionDB then return end
    local pos = ShammyTime.GetRadialPositionDB()
    local point, relTo, relativePoint, x, y = barFrame:GetPoint(1)
    pos.totemBar = {
        point = point,
        relativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent",
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function CreateWindfuryTotemBarFrame()
    if totemBarFrame then return totemBarFrame end
    local barW = 286
    local barH = math.floor(barW * 277 / 996 + 0.5)
    local f = CreateFrame("Frame", "ShammyTimeWindfuryTotemBarFrame", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetSize(barW, barH)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    ApplyTotemBarPosition(f)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB().locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveTotemBarPosition(self)
    end)
    f.totemBar = f:CreateTexture(nil, "OVERLAY")
    f.totemBar:SetTexture(TEX.TOTEM_BAR)
    f.totemBar:SetAllPoints(f)
    f.totemBar:SetAlpha(1)
    f:SetScale(GetTotemBarScale())
    f:Hide()
    -- Restore visibility after reload if radial was shown
    local db = ShammyTime.GetDB and ShammyTime.GetDB()
    if db and db.wfRadialShown then
        f:Show()
    end
    totemBarFrame = f
    return f
end

function ShammyTime.EnsureWindfuryTotemBarFrame()
    return CreateWindfuryTotemBarFrame()
end

-- Ring subframe: proc scale runs here; satellites parent to this so they move with the ring
function ShammyTime.GetCenterRingFrame()
    local f = CreateCenterRingFrame()
    return f and f.ringFrame or nil
end

-- Called when a Windfury proc is detected (from ShammyTime_Windfury.lua combat log)
-- forceShow: if true, show even when wfRadialEnabled is off (e.g. /wfproc test)
function ShammyTime.PlayCenterRingProc(procTotal, forceShow)
    local db = ShammyTime.GetDB and ShammyTime.GetDB() or {}
    if not forceShow and not db.wfRadialEnabled then return end
    local f = CreateCenterRingFrame()
    f:Show()
    -- Cancel any pending delayed fade so this proc gets a fresh hold
    if f.wfFadeDelayTimer then
        f.wfFadeDelayTimer:Cancel()
        f.wfFadeDelayTimer = nil
    end
    if f.wfTextFadeTimer then
        f.wfTextFadeTimer:Cancel()
        f.wfTextFadeTimer = nil
    end
    if f.textFrame.fadeOutAnim then f.textFrame.fadeOutAnim:Stop() end
    f.textFrame:SetAlpha(1)
    f.textFrame:Show()
    local barFrame = ShammyTime.EnsureWindfuryTotemBarFrame and ShammyTime.EnsureWindfuryTotemBarFrame()
    if barFrame then barFrame:Show() end
    if db.wfRadialShown == nil then db.wfRadialShown = false end
    db.wfRadialShown = true  -- keep radial visible after proc
    f.total:SetText("TOTAL: " .. FormatNum(procTotal or 0))
    f:SetScale(GetRadialScale())
    local rf = f.ringFrame
    rf.energy:SetAlpha(0.12)
    rf.runes:SetAlpha(0.18)
    rf:SetScale(1)
    rf.procAnim:Stop()
    rf.procAnim:Play()
    -- Drive ring scale + satellite positions: quick expand, slow retract (force/explosion feel)
    if rf.satelliteTicker then
        rf.satelliteTicker:Cancel()
        rf.satelliteTicker = nil
    end
    local pop = 1.18
    local expandDur = 0.03
    local holdDur = 0.45
    local retractDur = 0.55
    local total = expandDur + holdDur + retractDur
    local start = GetTime()
    local interval = 0.02
    rf.satelliteTicker = C_Timer.NewTicker(interval, function()
        local t = GetTime() - start
        local scale
        if t <= expandDur then
            scale = 1 + (pop - 1) * (t / expandDur)
        elseif t <= expandDur + holdDur then
            scale = pop
        elseif t <= total then
            local u = (t - expandDur - holdDur) / retractDur
            scale = pop + (1 - pop) * u
        else
            scale = 1
        end
        rf:SetScale(scale)
        if ShammyTime.OnRingProcScaleUpdate then ShammyTime.OnRingProcScaleUpdate(scale) end
        if t >= total then
            if rf.satelliteTicker then
                rf.satelliteTicker:Cancel()
                rf.satelliteTicker = nil
            end
            rf:SetScale(1)
            if ShammyTime.ResetSatellitePositions then ShammyTime.ResetSatellitePositions() end
        end
    end)
    f:FlashText()
end

-- /wfcenter — toggle center ring frame and totem bar (positions saved separately per character)
SLASH_WFCENTER1 = "/wfcenter"
SlashCmdList["WFCENTER"] = function()
    local db = ShammyTime.GetDB and ShammyTime.GetDB() or {}
    local f = CreateCenterRingFrame()
    local barFrame = ShammyTime.EnsureWindfuryTotemBarFrame and ShammyTime.EnsureWindfuryTotemBarFrame()
    if f:IsShown() then
        f:Hide()
        f.textFrame:Hide()
        if barFrame then barFrame:Hide() end
        db.wfRadialShown = false
    else
        f:Show()
        f.textFrame:Show()
        f.total:SetText("TOTAL: " .. FormatNum(ShammyTime and ShammyTime.lastProcTotal or 0))
        if barFrame then barFrame:Show() end
        db.wfRadialShown = true
        -- Show numbers so user sees it's not reset, then fade out (same as on reload)
        C_Timer.After(0, function()
            local stats = (ShammyTime_Windfury_GetStats and ShammyTime_Windfury_GetStats()) or nil
            if ShammyTime.UpdateSatelliteValues then ShammyTime.UpdateSatelliteValues(stats) end
            if db.wfAlwaysShowNumbers then return end
            C_Timer.After(WF_NUMBERS_HOLD_BEFORE_FADE, function()
                if not f or not f:IsShown() then return end
                if f.textFrame and f.textFrame:IsShown() and f.textFrame.fadeOutAnim then
                    f.textFrame.fadeOutAnim:Stop()
                    f.textFrame:SetAlpha(1)
                    f.textFrame.fadeOutAnim:Play()
                end
                if ShammyTime.StartSatelliteTextChainFade then ShammyTime.StartSatelliteTextChainFade() end
            end)
        end)
    end
end

-- /wfproc — play proc pulse (energy glow + scale breath + rune rotation)
SLASH_WFPROC1 = "/wfproc"
SlashCmdList["WFPROC"] = function()
    ShammyTime.PlayCenterRingProc(3245, true)  -- forceShow so it always pops for testing
end

-- /wfresize [0.5–2.0] — set circle scale only; totem bar: /st totem scale
SLASH_WFRESIZE1 = "/wfresize"
SlashCmdList["WFRESIZE"] = function(msg)
    msg = msg and strmatch(msg, "^%s*(%S+)") or nil
    local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB() or {}
    if msg then
        local scale = tonumber(msg)
        if scale and scale >= 0.5 and scale <= 2 then
            db.wfRadialScale = scale
            if centerFrame then
                centerFrame:SetScale(scale)
            end
            print(("ShammyTime: Windfury circle scale set to %.2f."):format(scale))
        else
            print("ShammyTime: /wfresize expects 0.5–2 (e.g. /wfresize 0.8). Totem bar: /st totem scale 1")
        end
    else
        print(("ShammyTime: Circle scale %.2f. /wfresize <0.5-2> or /st radial scale. Totem bar: /st totem scale"):format(GetRadialScale()))
    end
end
