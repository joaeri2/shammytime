-- ShammyTime_Windfury.lua
-- Windfury proc radial UI: animates open on proc, shows aggregated stats, then closes.
-- Proc detection via SPELL_EXTRA_ATTACKS + damage correlation window.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local M = ShammyTime_Media
if not M then return end

local TEX = M.TEX
local RADIAL = M.RADIAL
local WF_WINDOW = M.WF_CORRELATION_WINDOW
local WINDFURY_ATTACK_SPELL_ID = 25584

-- Format number for display (compact)
local function FormatNum(n)
    if not n or n < 0 then return "0" end
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

-- Placeholder: load texture path into texture object (you add real TGAs to Media/)
local function SetTextureSafe(tex, path)
    if tex and path then
        tex:SetTexture(path)
    end
end

local radialFrame
local centerOrb, runeRing
local satellites = {}
local SATELLITE_LABELS = { "MIN", "AVG", "MAX", "PROC%", "PROCS", "LAST" }
local SATELLITE_RADIUS = 72
local CENTER_SIZE = 64
local SATELLITE_SIZE = 44

local wfExpectingDamage = false
local wfWindowTotal = 0
local wfWindowHits = 0
local wfWindowTimer = nil
local wfCloseTimer = nil

local function GetDB()
    return ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB() or {}
end

local function GetStatsForRadial()
    local pull, session, lastTotal = nil, nil, 0
    if ShammyTime and ShammyTime.GetWindfuryStats then
        pull, session, lastTotal = ShammyTime.GetWindfuryStats()
    end
    session = session or {}
    local count = session.count or 0
    local swings = session.swings or 0
    local procPct = (swings > 0 and count > 0) and (count / swings * 100) or 0
    local avg = (count > 0 and session.total) and math.floor(session.total / count + 0.5) or nil
    return {
        min = session.min,
        max = session.max,
        avg = avg,
        procPct = procPct,
        procCount = count,
        lastTotal = lastTotal,
    }
end

local function UpdateRadialText(stats)
    if not radialFrame or not radialFrame.centerText then return end
    radialFrame.centerText:SetText(FormatNum(stats.lastTotal))
    for i = 1, #satellites do
        local sf = satellites[i]
        if sf and sf.value then
            local v = "–"
            if i == 1 then v = stats.min and FormatNum(stats.min) or "–"
            elseif i == 2 then v = stats.avg and FormatNum(stats.avg) or "–"
            elseif i == 3 then v = stats.max and FormatNum(stats.max) or "–"
            elseif i == 4 then v = stats.procCount > 0 and ("%.1f%%"):format(stats.procPct) or "–"
            elseif i == 5 then v = tostring(stats.procCount)
            elseif i == 6 then v = FormatNum(stats.lastTotal)
            end
            sf.value:SetText(v)
        end
    end
end

local function CreateRadialFrame()
    if radialFrame then return radialFrame end

    local db = GetDB()
    local f = CreateFrame("Frame", "ShammyTimeWindfuryRadial", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(100)
    f:SetSize(400, 400)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:SetAlpha(0)
    f:SetScale(1)
    f:Hide()

    -- Soft shadow (static, underneath everything) — low alpha so no hard edge
    local shadow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    shadow:SetSize(340, 340)
    shadow:SetPoint("CENTER", 0, 0)
    SetTextureSafe(shadow, TEX.CENTER_SHADOW)
    shadow:SetVertexColor(1, 1, 1, 0.28)
    f.shadow = shadow

    -- Rune ring (behind)
    local ring = f:CreateTexture(nil, "BACKGROUND")
    ring:SetSize(320, 320)
    ring:SetPoint("CENTER", 0, 0)
    SetTextureSafe(ring, TEX.RING_RUNES)
    ring:SetVertexColor(0.7, 0.75, 0.85, 0.35)
    f.runeRing = ring

    -- Center orb (bg + border)
    local center = CreateFrame("Frame", nil, f)
    center:SetSize(CENTER_SIZE, CENTER_SIZE)
    center:SetPoint("CENTER", 0, 0)
    local cbg = center:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints()
    SetTextureSafe(cbg, TEX.ORB_BG)
    cbg:SetVertexColor(0.15, 0.18, 0.22, 0.95)
    local cbor = center:CreateTexture(nil, "ARTWORK")
    cbor:SetAllPoints()
    SetTextureSafe(cbor, TEX.ORB_BORDER)
    cbor:SetVertexColor(0.5, 0.55, 0.65, 1)
    local ctext = center:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ctext:SetPoint("CENTER", 0, 0)
    ctext:SetTextColor(1, 0.9, 0.4)
    ctext:SetText("0")
    f.centerOrb = center
    f.centerText = ctext

    -- Soft glow behind center
    local glow = f:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(180, 180)
    glow:SetPoint("CENTER", 0, 0)
    SetTextureSafe(glow, TEX.GLOW)
    glow:SetVertexColor(0.4, 0.6, 0.85, 0.25)

    -- 6 satellite orbs (MIN, AVG, MAX, PROC%, PROCS, LAST)
    local angleStep = 360 / 6
    for i = 1, 6 do
        local angle = (i - 1) * angleStep
        local rad = math.rad(angle)
        local dx = SATELLITE_RADIUS * math.cos(rad)
        local dy = SATELLITE_RADIUS * math.sin(rad)
        local sf = CreateFrame("Frame", nil, f)
        sf:SetSize(SATELLITE_SIZE, SATELLITE_SIZE)
        sf:SetPoint("CENTER", dx, dy)
        local sbg = sf:CreateTexture(nil, "BACKGROUND")
        sbg:SetAllPoints()
        SetTextureSafe(sbg, TEX.ORB_BG)
        sbg:SetVertexColor(0.12, 0.12, 0.14, 0.92)
        local sbor = sf:CreateTexture(nil, "ARTWORK")
        sbor:SetAllPoints()
        SetTextureSafe(sbor, TEX.ORB_BORDER)
        sbor:SetVertexColor(0.4, 0.42, 0.48, 1)
        local slab = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slab:SetPoint("TOP", 0, -2)
        slab:SetText(SATELLITE_LABELS[i] or "")
        slab:SetTextColor(0.7, 0.7, 0.75)
        local sval = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sval:SetPoint("BOTTOM", 0, 2)
        sval:SetTextColor(1, 1, 1)
        sf.label = slab
        sf.value = sval
        sf.startX = dx
        sf.startY = dy
        satellites[i] = sf
    end

    -- Animation: open
    local agOpen = f:CreateAnimationGroup()
    local aAlphaIn = agOpen:CreateAnimation("Alpha")
    aAlphaIn:SetFromAlpha(0)
    aAlphaIn:SetToAlpha(1)
    aAlphaIn:SetDuration(RADIAL.OPEN_DURATION)
    aAlphaIn:SetSmoothing("OUT")
    local aScaleIn = agOpen:CreateAnimation("Scale")
    aScaleIn:SetFromScale(0.3)
    aScaleIn:SetToScale(1)
    aScaleIn:SetDuration(RADIAL.OPEN_DURATION)
    aScaleIn:SetSmoothing("OUT")
    agOpen:SetScript("OnPlay", function()
        f:Show()
        f:SetAlpha(0)
        f:SetScale(0.3)
    end)
    agOpen:SetScript("OnFinished", function()
        f:SetAlpha(1)
        f:SetScale(1)
    end)

    -- Rune ring rotation (subtle)
    local agRune = ring:CreateAnimationGroup()
    local aRot = agRune:CreateAnimation("Rotation")
    aRot:SetDegrees(RADIAL.RUNE_ROTATION_DEG or 25)
    aRot:SetDuration(RADIAL.HOLD_DURATION or 2.7)
    aRot:SetSmoothing("IN_OUT")
    f.agRune = agRune

    -- Satellite stagger: start at center, move out (translation)
    for i = 1, #satellites do
        local sf = satellites[i]
        local agSat = sf:CreateAnimationGroup()
        local delay = (i - 1) * (RADIAL.SATELLITE_STAGGER or 0.03)
        agSat:SetDelay(delay)
        local aTrans = agSat:CreateAnimation("Translation")
        aTrans:SetOffset(-sf.startX, -sf.startY)
        aTrans:SetDuration(RADIAL.SATELLITE_MOVE or 0.18)
        aTrans:SetSmoothing("OUT")
        agSat:SetScript("OnPlay", function()
            sf:ClearAllPoints()
            sf:SetPoint("CENTER", f, "CENTER", 0, 0)
        end)
        agSat:SetScript("OnFinished", function()
            sf:ClearAllPoints()
            sf:SetPoint("CENTER", f, "CENTER", sf.startX, sf.startY)
        end)
        sf.animOpen = agSat
    end

    -- Animation: close (collapse + fade)
    local agClose = f:CreateAnimationGroup()
    local aAlphaOut = agClose:CreateAnimation("Alpha")
    aAlphaOut:SetFromAlpha(1)
    aAlphaOut:SetToAlpha(0)
    aAlphaOut:SetDuration(RADIAL.CLOSE_DURATION or 0.18)
    aAlphaOut:SetSmoothing("IN")
    local aScaleOut = agClose:CreateAnimation("Scale")
    aScaleOut:SetFromScale(1)
    aScaleOut:SetToScale(0.3)
    aScaleOut:SetDuration(RADIAL.CLOSE_DURATION or 0.18)
    aScaleOut:SetSmoothing("IN")
    agClose:SetScript("OnFinished", function()
        f:Hide()
        f:SetAlpha(0)
        f:SetScale(1)
    end)

    f.agOpen = agOpen
    f.agClose = agClose
    f.agRune = agRune
    radialFrame = f
    return f
end

-- Play open: center + rune + satellites, then hold then close. forceShow: true = play even if radial option off (e.g. /wftest)
function ShammyTime_Windfury_PlayRadial(forceShow)
    local f = CreateRadialFrame()
    if not f then return end
    local db = GetDB()
    if not forceShow and not db.wfRadialEnabled then return end

    if f.agClose:IsPlaying() then f.agClose:Stop() end
    if f.agOpen:IsPlaying() then f.agOpen:Stop() end

    local stats = GetStatsForRadial()
    UpdateRadialText(stats)

    f:Show()
    f:SetAlpha(0)
    f:SetScale(0.3)
    -- Satellites start at center
    for i = 1, #satellites do
        local sf = satellites[i]
        sf:ClearAllPoints()
        sf:SetPoint("CENTER", f, "CENTER", 0, 0)
    end

    f.agOpen:Play()
    if f.agRune then f.agRune:Play() end
    for i = 1, #satellites do
        if satellites[i].animOpen then satellites[i].animOpen:Play() end
    end

    local hold = RADIAL.HOLD_DURATION or 2.7
    if wfCloseTimer then wfCloseTimer:Cancel() end
    wfCloseTimer = C_Timer.NewTimer(hold, function()
        wfCloseTimer = nil
        if radialFrame and radialFrame.agClose then
            radialFrame.agClose:Play()
        end
    end)
end

-- Called when correlation window ends with a proc total (or from /wftest)
function ShammyTime_Windfury_ShowRadial(procTotal)
    if procTotal then
        ShammyTime.lastProcTotal = procTotal
    end
    -- Center ring (layered orb + text flash) — triggers on real proc
    if ShammyTime.PlayCenterRingProc then
        ShammyTime.PlayCenterRingProc(procTotal)
    end
    ShammyTime_Windfury_PlayRadial()
end

-- Start or extend the proc damage window (called from SPELL_EXTRA_ATTACKS or first WF damage)
local function StartProcWindow()
    wfExpectingDamage = true
    if wfWindowTimer then wfWindowTimer:Cancel() end
    wfWindowTimer = C_Timer.NewTimer(WF_WINDOW, function()
        wfWindowTimer = nil
        wfExpectingDamage = false
        if wfWindowHits > 0 then
            ShammyTime_Windfury_ShowRadial(wfWindowTotal)
        end
    end)
end

-- Combat log: SPELL_EXTRA_ATTACKS starts window; SPELL_DAMAGE 25584 sums. Fallback: first WF damage starts window if no SPELL_EXTRA_ATTACKS (e.g. Classic).
local function OnCombatLog()
    local db = GetDB()
    if not db.wfRadialEnabled then return end
    if not CombatLogGetCurrentEventInfo then return end

    local subevent = select(2, CombatLogGetCurrentEventInfo())
    if subevent == "SPELL_EXTRA_ATTACKS" then
        local srcGUID = select(4, CombatLogGetCurrentEventInfo())
        if srcGUID == UnitGUID("player") then
            wfWindowTotal = 0
            wfWindowHits = 0
            StartProcWindow()
        end
        return
    end

    if subevent ~= "SPELL_DAMAGE" and subevent ~= "SPELL_DAMAGE_CRIT" then return end

    local srcGUID = select(4, CombatLogGetCurrentEventInfo())
    if srcGUID ~= UnitGUID("player") then return end
    local spellId = select(12, CombatLogGetCurrentEventInfo())
    local spellName = select(13, CombatLogGetCurrentEventInfo())
    local amount = select(15, CombatLogGetCurrentEventInfo())
    if not amount or amount <= 0 then return end
    local isWindfury = (spellId == WINDFURY_ATTACK_SPELL_ID) or (spellName and spellName == "Windfury Attack")
    if not isWindfury then return end

    -- Fallback: if we didn't get SPELL_EXTRA_ATTACKS (e.g. TBC/Classic), first WF damage starts the window
    if not wfExpectingDamage then
        wfWindowTotal = 0
        wfWindowHits = 0
        StartProcWindow()
    end

    wfWindowTotal = wfWindowTotal + amount
    wfWindowHits = wfWindowHits + 1
    -- Windfury = up to 2 extra attacks; after 2 hits we can close window early
    if wfWindowHits >= 2 and wfWindowTimer then
        wfWindowTimer:Cancel()
        wfWindowTimer = nil
        wfExpectingDamage = false
        ShammyTime_Windfury_ShowRadial(wfWindowTotal)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    end
end)

-- Slash: /wftest — play radial animation without combat
SLASH_SHAMMYTIME_WFTEST1 = "/wftest"
SlashCmdList["SHAMMYTIME_WFTEST"] = function()
    ShammyTime.lastProcTotal = 1234  -- dummy for display
    ShammyTime_Windfury_PlayRadial(true)  -- forceShow so it plays without combat/option
end
