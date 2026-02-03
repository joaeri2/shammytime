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

-- Center ring (and all satellites, as children) scale; read/write via GetDB().wfRadialScale (0.5–2).
local function GetRadialScale()
    local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB() or {}
    return (db.wfRadialScale and db.wfRadialScale >= 0.5 and db.wfRadialScale <= 2) and db.wfRadialScale or 0.7
end

local function FormatNum(n)
    if not n or n < 0 then return "0" end
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

local function CreateCenterRingFrame()
    if centerFrame then return centerFrame end

    local f = CreateFrame("Frame", "ShammyTimeCenterRing", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetSize(260, 260)
    f:SetScale(GetRadialScale())
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    -- Right-click: show options menu (reset numbers)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Right-click to reset numbers")
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnMouseDown", function(self, button)
        if button ~= "RightButton" then return end
        if ShammyTime and ShammyTime.ResetWindfurySession then
            ShammyTime.ResetWindfurySession()
        end
        if ShammyTime then ShammyTime.lastProcTotal = 0 end
        if centerFrame and centerFrame.total then
            centerFrame.total:SetText("TOTAL: 0")
        end
    end)
    f:Hide()

    -- Ring subframe: only this scales during proc so totem bar stays fixed; satellites parent here to move with ring
    local ringFrame = CreateFrame("Frame", nil, f)
    ringFrame:SetSize(260, 260)
    ringFrame:SetPoint("CENTER", f, "CENTER", 0, 0)
    ringFrame:SetFrameLevel(1)
    f.ringFrame = ringFrame

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

    -- 3b. TOTEM BAR: on main frame so it does NOT scale during proc
    f.totemBar = f:CreateTexture(nil, "OVERLAY")
    f.totemBar:SetTexture(TEX.TOTEM_BAR)
    local barW = 286  -- 260 * 1.1 (10% larger)
    local barH = math.floor(barW * 277 / 996 + 0.5)  -- 996:277 aspect
    f.totemBar:SetSize(barW, barH)
    f.totemBar:SetAlpha(1)
    -- Anchor TOP of bar to BOTTOM of frame; positive Y moves bar up toward the circle
    f.totemBar:SetPoint("TOP", f, "BOTTOM", 0, 65)

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
    ag:SetScript("OnFinished", function()
        if ringFrame.satelliteTicker then
            ringFrame.satelliteTicker:Cancel()
            ringFrame.satelliteTicker = nil
        end
        ringFrame:SetScale(1)
        if ShammyTime.ResetSatellitePositions then ShammyTime.ResetSatellitePositions() end
    end)
    ag:SetScript("OnStop", function()
        if ringFrame.satelliteTicker then
            ringFrame.satelliteTicker:Cancel()
            ringFrame.satelliteTicker = nil
        end
        ringFrame:SetScale(1)
        if ShammyTime.ResetSatellitePositions then ShammyTime.ResetSatellitePositions() end
    end)

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
    return f
end

-- Ensure center ring exists (for satellites that anchor to it)
function ShammyTime.EnsureCenterRingExists()
    return CreateCenterRingFrame()
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
    f.textFrame:Show()
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

-- /wfcenter — toggle center ring frame
SLASH_WFCENTER1 = "/wfcenter"
SlashCmdList["WFCENTER"] = function()
    local f = CreateCenterRingFrame()
    if f:IsShown() then
        f:Hide()
        f.textFrame:Hide()
    else
        f:Show()
        f.textFrame:Show()
    end
end

-- /wfproc — play proc pulse (energy glow + scale breath + rune rotation)
SLASH_WFPROC1 = "/wfproc"
SlashCmdList["WFPROC"] = function()
    ShammyTime.PlayCenterRingProc(3245, true)  -- forceShow so it always pops for testing
end

-- /wfresize [0.5–2.0] — set radial scale (center + all satellites as one object; no arg = print current)
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
            print(("ShammyTime: Windfury radial scale set to %.2f (all rings resize together)."):format(scale))
        else
            print("ShammyTime: /wfresize expects a number between 0.5 and 2 (e.g. /wfresize 0.8)")
        end
    else
        print(("ShammyTime: Windfury radial scale is %.2f. Use /wfresize <0.5-2> to change."):format(GetRadialScale()))
    end
end
