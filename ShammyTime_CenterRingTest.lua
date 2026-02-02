-- ShammyTime_CenterRingTest.lua
-- Phase 1: Center ring only — load 4 layered textures, stack them, add /wfcenter and /wfproc.
-- No satellites, no combat log. Purely asset + animation integration test.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local M = ShammyTime_Media
if not M then return end

local TEX = M.TEX
local centerFrame

-- Resize the center ring: change this number (e.g. 0.85 = smaller, 1.0 = original 260px)
local CENTER_RING_SCALE = 1

local function FormatNum(n)
    if not n or n < 0 then return "0" end
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

local function CreateCenterRingFrame()
    if centerFrame then return centerFrame end

    local f = CreateFrame("Frame", "ShammyTimeCenterRingTest", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetSize(260, 260)
    f:SetScale(CENTER_RING_SCALE)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:Hide()

    -- 1. BACKGROUND: wf_center_bg.tga
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.bg:SetTexture(TEX.CENTER_BG)
    f.bg:SetAlpha(1)

    -- 2. ARTWORK: wf_center_energy.tga (low alpha, ADD blend)
    f.energy = f:CreateTexture(nil, "ARTWORK")
    f.energy:SetAllPoints(f)
    f.energy:SetTexture(TEX.CENTER_ENERGY)
    f.energy:SetAlpha(0.12)
    f.energy:SetBlendMode("ADD")

    -- 3. BORDER: wf_center_border.tga
    f.border = f:CreateTexture(nil, "BORDER")
    f.border:SetAllPoints(f)
    f.border:SetTexture(TEX.CENTER_BORDER)
    f.border:SetAlpha(1)

    -- 4. OVERLAY: wf_center_runes.tga (subtle) — inset so when it rotates it stays inside the border
    f.runes = f:CreateTexture(nil, "OVERLAY")
    f.runes:SetTexture(TEX.CENTER_RUNES)
    f.runes:SetAlpha(0.18)
    local runesInset = 20  -- smaller inset = larger runes ring (more overlay on border)
    f.runes:SetSize(260 - runesInset * 2, 260 - runesInset * 2)
    f.runes:SetPoint("CENTER", 0, 12)  -- slightly up

    -- Text on a SEPARATE frame (not a child of f) so it doesn't scale with the ring
    -- No scaling on text — stays crisp. Use color flash for dramatic effect instead.
    local textFrame = CreateFrame("Frame", "ShammyTimeCenterRingText", UIParent)
    textFrame:SetFrameStrata("DIALOG")
    textFrame:SetFrameLevel(f:GetFrameLevel() + 10)
    textFrame:SetSize(260, 260)
    textFrame:SetPoint("CENTER", f, "CENTER", 0, 0)
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

    -- Proc pulse: lightning-style — snappy pop then quick settle
    local pop = 1.18
    local inv = 1 / pop

    local function BuildProcAnim(frame)
        local g = frame:CreateAnimationGroup()

        -- Scale: snappy lightning pop, then quick settle

        local s1 = g:CreateAnimation("Scale")
        s1:SetOrder(1)
        s1:SetDuration(0.03)
        s1:SetScale(pop, pop)
        s1:SetSmoothing("OUT")

        local s2 = g:CreateAnimation("Scale")
        s2:SetOrder(2)
        s2:SetDuration(0.28)
        s2:SetScale(inv, inv)
        s2:SetSmoothing("OUT")  -- fast start, slow at end so it eases into 100%

        -- Energy: instant flash to full, then long soften (lightning hit → fade)
        local aFlash = g:CreateAnimation("Alpha")
        aFlash:SetTarget(frame.energy)
        aFlash:SetOrder(1)
        aFlash:SetDuration(0.02)
        aFlash:SetFromAlpha(0.12)
        aFlash:SetToAlpha(1.0)

        local aSoft = g:CreateAnimation("Alpha")
        aSoft:SetTarget(frame.energy)
        aSoft:SetOrder(2)
        aSoft:SetDuration(0.35)
        aSoft:SetFromAlpha(1.0)
        aSoft:SetToAlpha(0.18)
        aSoft:SetSmoothing("OUT")

        -- Runes: quick flash then fade (they "light up" with the strike)
        local runeFlash = g:CreateAnimation("Alpha")
        runeFlash:SetTarget(frame.runes)
        runeFlash:SetOrder(1)
        runeFlash:SetDuration(0.02)
        runeFlash:SetFromAlpha(0.18)
        runeFlash:SetToAlpha(0.5)

        local runeSoft = g:CreateAnimation("Alpha")
        runeSoft:SetTarget(frame.runes)
        runeSoft:SetOrder(2)
        runeSoft:SetDuration(0.3)
        runeSoft:SetFromAlpha(0.5)
        runeSoft:SetToAlpha(0.18)
        runeSoft:SetSmoothing("OUT")

        -- Rune rotation: visible spin on proc
        local rot = g:CreateAnimation("Rotation")
        rot:SetTarget(frame.runes)
        rot:SetOrder(1)
        rot:SetDuration(0.7)
        rot:SetSmoothing("OUT")
        rot:SetDegrees(180)

        return g
    end

    f.procAnim = BuildProcAnim(f)

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

-- Called when a Windfury proc is detected (from ShammyTime_Windfury.lua combat log)
function ShammyTime.PlayCenterRingProc(procTotal)
    local db = ShammyTime.GetDB and ShammyTime.GetDB() or {}
    if not db.wfRadialEnabled then return end
    local f = CreateCenterRingFrame()
    f:Show()
    f.textFrame:Show()
    f.total:SetText("TOTAL: " .. FormatNum(procTotal or 0))
    f:SetScale(CENTER_RING_SCALE)
    f.energy:SetAlpha(0.12)
    f.runes:SetAlpha(0.18)
    f.procAnim:Stop()
    f.procAnim:Play()
    f:FlashText()
end

-- /wfcenter — toggle center ring test frame
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
    ShammyTime.PlayCenterRingProc(3245)
end
