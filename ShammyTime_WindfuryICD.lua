-- ShammyTime_WindfuryICD.lua
-- Windfury Internal Cooldown indicator: shows an on/off lamp with a 3-second countdown
-- when Windfury procs (personal imbue or Windfury Totem). The lamp is "on" (bright) when
-- WF can proc again, and "off" (dark) with a countdown during the 3s internal cooldown.
-- Auto-hides when no Windfury is available on any weapon and no Windfury Totem is active.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local M = ShammyTime_Media
if not M then return end

local TEX = M.TEX

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------
local WF_ICD_DURATION       = 3.0    -- seconds of internal cooldown after a proc
local ICD_FADE_IN_DURATION  = 0.15   -- off→on transition (snappy)
local ICD_FADE_OUT_DURATION = 0.15   -- on→off transition (snappy)
local COUNTDOWN_TICK        = 0.05   -- update interval for countdown text (smooth decimal)
local STORMSTRIKE_TEXT_GAP  = 4      -- spacing between SS icon and cooldown text
local STORMSTRIKE_TEXT_WIDTH = 24    -- fixed width keeps icon+text centered without jitter
local STORMSTRIKE_Y_OFFSET = -3      -- slight upward nudge from previous position
local STORMSTRIKE_PAIR_X_OFFSET = -((STORMSTRIKE_TEXT_GAP + STORMSTRIKE_TEXT_WIDTH) * 0.5)
local WINDFURY_ATTACK_SPELL_ID = 25584  -- personal Windfury Weapon proc
local WF_TOTEM_SPELL_ID       = 8516   -- Windfury Totem proc
local STORMSTRIKE_SPELL_ID    = 17364  -- Stormstrike
local GCD_THRESHOLD            = 1.5    -- ignore short GCD-only cooldowns

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local icdFrame
local icdActive = false       -- true while 3s ICD is running
local icdStartTime = 0        -- GetTime() when ICD started
local icdCountdownTicker = nil
local icdAlphaTicker = nil
local stormstrikeCooldownTicker = nil
local icdTestActive = false
local icdTestTimer = nil
local icdTestFadeTimer = nil
local playerGUID
local icdDebug = false  -- set via /st icd debug

--------------------------------------------------------------------------------
-- DB helpers
--------------------------------------------------------------------------------
local DEFAULTS = {
    point = "CENTER",
    relativeTo = "UIParent",
    relativePoint = "CENTER",
    x = 0,
    y = -250,
    scale = 1,
    locked = false,
}

local function GetDB()
    local profile = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
    if profile and profile.windfuryIcdFrame then
        local db = profile.windfuryIcdFrame
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        return db
    end
    ShammyTimeDB = ShammyTimeDB or {}
    ShammyTimeDB.windfuryIcdFrame = ShammyTimeDB.windfuryIcdFrame or {}
    local db = ShammyTimeDB.windfuryIcdFrame
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

--------------------------------------------------------------------------------
-- Windfury availability: returns true when the player has Windfury on a weapon
-- (personal imbue) OR a Windfury Totem is active.
--------------------------------------------------------------------------------
local function HasWindfuryAvailable()
    -- 1) Personal Windfury Weapon imbue
    if ShammyTime.GetWeaponImbuePerHand then
        local hands = ShammyTime.GetWeaponImbuePerHand()
        if hands then
            local now = GetTime()
            for _, hand in pairs(hands) do
                if hand and hand.name and hand.expirationTime then
                    local remaining = hand.expirationTime - now
                    if remaining > 0 and hand.name:lower():find("windfury") then
                        return true
                    end
                end
            end
        end
    end
    -- 2) Windfury Totem active in any slot
    if GetTotemInfo then
        for slot = 1, 4 do
            local haveTotem, totemName = GetTotemInfo(slot)
            if haveTotem and totemName and totemName:find("Windfury Totem", 1, true) then
                return true
            end
        end
    end
    return false
end

-- Expose for fade system context
ShammyTime.HasWindfuryAvailable = HasWindfuryAvailable

--------------------------------------------------------------------------------
-- Stormstrike cooldown overlay
--------------------------------------------------------------------------------
local UpdateStormstrikeOverlay

local function StopStormstrikeCooldownTicker()
    if stormstrikeCooldownTicker then
        stormstrikeCooldownTicker:Cancel()
        stormstrikeCooldownTicker = nil
    end
end

local function StartStormstrikeCooldownTicker()
    if stormstrikeCooldownTicker then return end
    stormstrikeCooldownTicker = C_Timer.NewTicker(COUNTDOWN_TICK, function()
        if UpdateStormstrikeOverlay then
            UpdateStormstrikeOverlay()
        end
    end)
end

local function GetStormstrikeCooldownState()
    if not GetSpellInfo or not GetSpellCooldown then
        return false, 0, 0, 0, nil
    end
    local spellName, _, iconTexture = GetSpellInfo(STORMSTRIKE_SPELL_ID)
    if not spellName then
        return false, 0, 0, 0, nil
    end
    local start, duration, enabled = GetSpellCooldown(spellName)
    if not start or not duration or enabled == 0 then
        return false, 0, 0, 0, iconTexture
    end
    local remaining = (start + duration) - GetTime()
    if duration <= GCD_THRESHOLD or remaining <= 0 then
        return false, start, duration, 0, iconTexture
    end
    return true, start, duration, remaining, iconTexture
end

--------------------------------------------------------------------------------
-- Alpha animation helpers (same pattern as ShamanisticFocus)
--------------------------------------------------------------------------------
local function StopAlphaTicker()
    if icdAlphaTicker then
        icdAlphaTicker:Cancel()
        icdAlphaTicker = nil
    end
end

local function StopCountdownTicker()
    if icdCountdownTicker then
        icdCountdownTicker:Cancel()
        icdCountdownTicker = nil
    end
end

local function FadeOverlayTo(targetAlpha, duration, onComplete)
    StopAlphaTicker()
    if not icdFrame then return end
    local overlay = icdFrame.icdOn
    local startAlpha = overlay:GetAlpha()
    if math.abs(startAlpha - targetAlpha) < 0.01 then
        overlay:SetAlpha(targetAlpha)
        if onComplete then onComplete() end
        return
    end
    local startTime = GetTime()
    icdAlphaTicker = C_Timer.NewTicker(1/60, function()
        local t = (GetTime() - startTime) / duration
        if t >= 1 then
            overlay:SetAlpha(targetAlpha)
            StopAlphaTicker()
            if onComplete then onComplete() end
            return
        end
        overlay:SetAlpha(startAlpha + (targetAlpha - startAlpha) * t)
    end)
end

--------------------------------------------------------------------------------
-- Countdown text
--------------------------------------------------------------------------------
local function StartCountdown()
    StopCountdownTicker()
    if not icdFrame then return end
    icdFrame.countdownText:Show()
    icdCountdownTicker = C_Timer.NewTicker(COUNTDOWN_TICK, function()
        if not icdFrame or not icdActive then
            StopCountdownTicker()
            if icdFrame then icdFrame.countdownText:Hide() end
            return
        end
        local remaining = WF_ICD_DURATION - (GetTime() - icdStartTime)
        if remaining <= 0 then
            remaining = 0
            StopCountdownTicker()
            -- ICD expired: transition to "on" state
            icdActive = false
            icdFrame.countdownText:Hide()
            FadeOverlayTo(1, ICD_FADE_IN_DURATION)
            return
        end
        icdFrame.countdownText:SetText(("%.1f"):format(remaining))
    end)
end

--------------------------------------------------------------------------------
-- ICD trigger: called when Windfury procs
--------------------------------------------------------------------------------
local function TriggerICD()
    if not icdFrame then
        if icdDebug then print("|cffff0000ICD Debug:|r TriggerICD() called but icdFrame is nil!") end
        return
    end
    if icdDebug then
        print("|cff00ff00ICD Debug:|r TriggerICD() -> starting 3s ICD. Frame shown=" ..
              tostring(icdFrame:IsShown()) .. " alpha=" .. tostring(icdFrame:GetAlpha()))
    end
    icdActive = true
    icdStartTime = GetTime()
    -- Immediately show "off" state: fade overlay to 0
    FadeOverlayTo(0, ICD_FADE_OUT_DURATION)
    -- Start countdown text
    StartCountdown()
end

--------------------------------------------------------------------------------
-- Frame creation
--------------------------------------------------------------------------------
local function CreateICDFrame()
    if icdFrame then return icdFrame end

    local db = GetDB()
    local iconSize = 80
    local padW, padH = 16, 24
    local f = CreateFrame("Frame", "ShammyTimeWindfuryICD", UIParent)
    f:SetFrameStrata("LOW")
    f:SetSize(iconSize + padW, iconSize + padH)
    f:SetClipsChildren(false)
    f:SetScale(db.scale or 0.8)
    local relTo = (db.relativeTo and _G[db.relativeTo]) or UIParent
    f:SetPoint(db.point or "CENTER", relTo, db.relativePoint or "CENTER", db.x or 0, db.y or -250)
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
        -- Keep modules.windfuryIcd.pos in sync
        local profile = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
        if profile and profile.modules and profile.modules.windfuryIcd then
            local pos = profile.modules.windfuryIcd.pos
            if not pos then
                pos = {}
                profile.modules.windfuryIcd.pos = pos
            end
            pos.point = point
            pos.relPoint = relativePoint
            pos.x = x
            pos.y = y
        end
    end)

    f.baseIconSize = iconSize

    -- Base: "off" image always visible (dark lamp)
    local icdOff = f:CreateTexture(nil, "ARTWORK")
    icdOff:SetSize(iconSize, iconSize)
    icdOff:SetPoint("CENTER", 0, 2)
    icdOff:SetTexCoord(0, 1, 0, 1)
    icdOff:SetTexture(TEX.WF_ICD_OFF)
    icdOff:SetVertexColor(1, 1, 1)
    icdOff:SetAlpha(1)
    icdOff:Show()
    f.icdOff = icdOff

    -- Overlay: "on" image (bright lamp); alpha animated
    local icdOn = f:CreateTexture(nil, "OVERLAY")
    icdOn:SetSize(iconSize, iconSize)
    icdOn:SetPoint("CENTER", 0, 2)
    icdOn:SetTexCoord(0, 1, 0, 1)
    icdOn:SetTexture(TEX.WF_ICD_ON)
    icdOn:SetVertexColor(1, 1, 1)
    icdOn:SetAlpha(1)  -- start as "on" (WF ready)
    icdOn:Show()
    f.icdOn = icdOn

    -- Countdown text (centered over the lamp)
    local countdownText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    countdownText:SetPoint("CENTER", f, "CENTER", 0, 2)
    countdownText:SetFont(countdownText:GetFont(), 18, "OUTLINE")
    countdownText:SetTextColor(1, 1, 1, 1)
    countdownText:SetText("")
    countdownText:Hide()
    f.countdownText = countdownText

    -- Overlay icon: compact Stormstrike marker at the top of the WF ICD lamp
    local stormstrikeIcon = f:CreateTexture(nil, "OVERLAY")
    stormstrikeIcon:SetSize(20, 20)
    stormstrikeIcon:SetPoint("BOTTOM", icdOff, "TOP", STORMSTRIKE_PAIR_X_OFFSET, STORMSTRIKE_Y_OFFSET)
    stormstrikeIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    stormstrikeIcon:SetAlpha(1)
    stormstrikeIcon:Hide()
    f.stormstrikeIcon = stormstrikeIcon

    local stormstrikeCooldown = CreateFrame("Cooldown", nil, f)
    stormstrikeCooldown:SetAllPoints(stormstrikeIcon)
    if stormstrikeCooldown.SetDrawEdge then stormstrikeCooldown:SetDrawEdge(false) end
    if stormstrikeCooldown.SetDrawBling then stormstrikeCooldown:SetDrawBling(false) end
    if stormstrikeCooldown.SetHideCountdownNumbers then
        stormstrikeCooldown:SetHideCountdownNumbers(true)
    end
    stormstrikeCooldown:Hide()
    f.stormstrikeCooldown = stormstrikeCooldown

    local stormstrikeCountdownText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stormstrikeCountdownText:SetPoint("LEFT", stormstrikeIcon, "RIGHT", STORMSTRIKE_TEXT_GAP, 0)
    stormstrikeCountdownText:SetWidth(STORMSTRIKE_TEXT_WIDTH)
    stormstrikeCountdownText:SetJustifyH("LEFT")
    stormstrikeCountdownText:SetFont(stormstrikeCountdownText:GetFont(), 13, "OUTLINE")
    stormstrikeCountdownText:SetTextColor(1, 1, 1, 1)
    stormstrikeCountdownText:SetText("")
    stormstrikeCountdownText:Hide()
    f.stormstrikeCountdownText = stormstrikeCountdownText

    icdFrame = f
    return f
end

UpdateStormstrikeOverlay = function()
    if not icdFrame then return end
    local icon = icdFrame.stormstrikeIcon
    local cooldown = icdFrame.stormstrikeCooldown
    local text = icdFrame.stormstrikeCountdownText
    if not icon or not cooldown or not text then return end

    local onCooldown, start, duration, remaining, iconTexture = GetStormstrikeCooldownState()
    if iconTexture then
        icon:SetTexture(iconTexture)
    end

    if onCooldown then
        icon:Show()
        cooldown:Show()
        if cooldown._lastStart ~= start or cooldown._lastDuration ~= duration then
            cooldown:SetCooldown(start, duration)
            cooldown._lastStart = start
            cooldown._lastDuration = duration
        end
        text:SetText(remaining >= 10 and ("%.0f"):format(remaining) or ("%.1f"):format(remaining))
        text:Show()
        StartStormstrikeCooldownTicker()
        return
    end

    icon:Hide()
    cooldown:Hide()
    cooldown._lastStart = nil
    cooldown._lastDuration = nil
    text:Hide()
    StopStormstrikeCooldownTicker()
end

--------------------------------------------------------------------------------
-- Update visual state (called from fade system and on WF availability change)
--------------------------------------------------------------------------------
local function UpdateICDVisual()
    local f = CreateICDFrame()
    if not f then return end

    UpdateStormstrikeOverlay()

    -- If ICD is active, the countdown ticker handles the visual state
    if icdActive then
        local remaining = WF_ICD_DURATION - (GetTime() - icdStartTime)
        if remaining <= 0 then
            -- ICD expired naturally
            icdActive = false
            StopCountdownTicker()
            f.countdownText:Hide()
            FadeOverlayTo(1, ICD_FADE_IN_DURATION)
        end
        return
    end

    -- Not in ICD: show "on" state
    if f.icdOn:GetAlpha() < 0.99 then
        FadeOverlayTo(1, ICD_FADE_IN_DURATION)
    end
    f.countdownText:Hide()
end

--------------------------------------------------------------------------------
-- Scale helper
--------------------------------------------------------------------------------
local function ApplyICDScale()
    local f = icdFrame
    if not f then return end
    local db = GetDB()
    local s = (db.scale and db.scale >= 0.1 and db.scale <= 3) and db.scale or 0.8
    f:SetScale(s)
    -- Re-apply position after scale so frame doesn't drift
    local relTo = (db.relativeTo and _G[db.relativeTo]) or UIParent
    if relTo then
        f:ClearAllPoints()
        f:SetPoint(db.point or "CENTER", relTo, db.relativePoint or "CENTER", db.x or 0, db.y or -250)
    end
end

--------------------------------------------------------------------------------
-- Test mode
--------------------------------------------------------------------------------
local ICD_TEST_INTERVAL = 5  -- seconds between test procs

function ShammyTime.StartWindfuryICDTest()
    if icdTestActive then return end
    icdTestActive = true
    local f = CreateICDFrame()
    f:Show()
    UpdateStormstrikeOverlay()
    -- Reset to "on" state
    StopAlphaTicker()
    StopCountdownTicker()
    f.icdOn:SetAlpha(1)
    f.countdownText:Hide()
    icdActive = false

    local function doProc()
        if not icdFrame or not icdTestActive then return end
        TriggerICD()
    end
    doProc()  -- first proc immediately
    icdTestTimer = C_Timer.NewTicker(ICD_TEST_INTERVAL, doProc)
end

function ShammyTime.StopWindfuryICDTest()
    if not icdTestActive then return end
    icdTestActive = false
    if icdTestTimer then
        icdTestTimer:Cancel()
        icdTestTimer = nil
    end
    if icdTestFadeTimer then
        icdTestFadeTimer:Cancel()
        icdTestFadeTimer = nil
    end
    StopAlphaTicker()
    StopCountdownTicker()
    icdActive = false
    -- Sync to real state
    UpdateICDVisual()
end

function ShammyTime.IsWindfuryICDTestActive()
    return icdTestActive
end

--------------------------------------------------------------------------------
-- Combat log event handler
-- Uses the same detection pattern as ShammyTime_Windfury.lua:
-- 1) SPELL_EXTRA_ATTACKS from the player triggers ICD (no spell filter needed;
--    in TBC Classic, shamans only get this from Windfury — personal or totem).
-- 2) SPELL_DAMAGE with spellId 25584 "Windfury Attack" as a fallback in case
--    SPELL_EXTRA_ATTACKS was missed (e.g. some Classic clients).
--------------------------------------------------------------------------------
local function OnCombatLog()
    if icdTestActive then return end
    if not CombatLogGetCurrentEventInfo then return end

    local subevent = select(2, CombatLogGetCurrentEventInfo())
    local srcGUID  = select(4, CombatLogGetCurrentEventInfo())

    -- Debug: print ALL combat log events from the player when debug is on
    if icdDebug then
        if not playerGUID then playerGUID = UnitGUID and UnitGUID("player") or nil end
        if srcGUID == playerGUID then
            local spellId = select(12, CombatLogGetCurrentEventInfo())
            local spellName = select(13, CombatLogGetCurrentEventInfo())
            print("|cffff8800ICD Debug:|r subevent=" .. tostring(subevent) ..
                  " spellId=" .. tostring(spellId) ..
                  " spellName=" .. tostring(spellName) ..
                  " srcGUID=" .. tostring(srcGUID))
        end
    end

    -- Only track the player's own events
    if not playerGUID then playerGUID = UnitGUID and UnitGUID("player") or nil end
    if srcGUID ~= playerGUID then return end

    -- Check if enabled
    local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
    if not db or db.wfIcdEnabled == false then
        if icdDebug then print("|cffff0000ICD Debug:|r wfIcdEnabled is false or no db, skipping") end
        return
    end

    -- SPELL_EXTRA_ATTACKS — fires on some clients when WF procs.
    -- TBC Anniversary 2026 does NOT fire this event, but keep it for compatibility.
    if subevent == "SPELL_EXTRA_ATTACKS" then
        if icdDebug then print("|cff00ff00ICD Debug:|r SPELL_EXTRA_ATTACKS detected -> TriggerICD()") end
        TriggerICD()
        return
    end

    -- Primary path: SPELL_DAMAGE with "Windfury Attack" (the actual WF damage hits).
    -- On TBC Anniversary, SPELL_EXTRA_ATTACKS does not fire; WF procs show up as
    -- SPELL_DAMAGE with spellName="Windfury Attack". The spellId varies by rank
    -- (e.g. 25504, 25584) so we match by name, same as ShammyTime_Windfury.lua.
    -- Only trigger on the FIRST hit (not icdActive) so the second hit doesn't restart.
    if (subevent == "SPELL_DAMAGE" or subevent == "SPELL_DAMAGE_CRIT") and not icdActive then
        local spellId = select(12, CombatLogGetCurrentEventInfo())
        local spellName = select(13, CombatLogGetCurrentEventInfo())
        local isWindfury = (spellId == WINDFURY_ATTACK_SPELL_ID)
                        or (spellName and spellName == "Windfury Attack")
        if isWindfury then
            if icdDebug then print("|cff00ff00ICD Debug:|r Windfury Attack detected (id=" .. tostring(spellId) .. ") -> TriggerICD()") end
            TriggerICD()
        end
        return
    end
end

--------------------------------------------------------------------------------
-- Event registration (deferred to ADDON_LOADED for SavedVariables)
--------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "ShammyTime" then
        eventFrame:UnregisterEvent("ADDON_LOADED")
        playerGUID = UnitGUID and UnitGUID("player") or nil
        CreateICDFrame()
        -- Start hidden if no windfury available; visibility managed by ShammyTime.lua
        local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
        local wfAvail = HasWindfuryAvailable()
        if db and db.wfIcdEnabled ~= false then
            if wfAvail then
                icdFrame:Show()
            else
                icdFrame:Hide()
            end
        else
            icdFrame:Hide()
        end
        UpdateICDVisual()
        UpdateStormstrikeOverlay()
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
        return
    end
    if event == "SPELL_UPDATE_COOLDOWN" or event == "PLAYER_ENTERING_WORLD" then
        UpdateStormstrikeOverlay()
        return
    end
    -- Re-check windfury availability when totems change or weapons change
    if event == "PLAYER_TOTEM_UPDATE" or event == "UNIT_INVENTORY_CHANGED" then
        if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then return end
        if ShammyTime.UpdateAllElementsFadeState then
            ShammyTime.UpdateAllElementsFadeState()
        end
        return
    end
end)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
ShammyTime.GetWindfuryICDFrame = function() return icdFrame end
ShammyTime.EnsureWindfuryICDFrame = function() return CreateICDFrame() end
ShammyTime.UpdateWindfuryICDVisual = UpdateICDVisual
ShammyTime.ApplyWindfuryICDScale = ApplyICDScale
ShammyTime.IsWindfuryICDActive = function() return icdActive end

-- Debug: toggle verbose combat log output for ICD
function ShammyTime.ToggleICDDebug()
    icdDebug = not icdDebug
    if icdDebug then
        print("|cff00ff00ShammyTime ICD Debug ON|r — combat log events from the player will print to chat. Attack a mob to see them. Type |cffffd700/st icd debug|r again to stop.")
    else
        print("|cffff8800ShammyTime ICD Debug OFF|r")
    end
end

-- Debug: print current ICD state
function ShammyTime.PrintICDStatus()
    local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
    local wfAvail = HasWindfuryAvailable()
    print("|cff00ff00ShammyTime ICD Status:|r")
    print("  wfIcdEnabled = " .. tostring(db and db.wfIcdEnabled))
    print("  playerGUID = " .. tostring(playerGUID))
    print("  HasWindfuryAvailable() = " .. tostring(wfAvail))
    print("  icdFrame exists = " .. tostring(icdFrame ~= nil))
    if icdFrame then
        print("  icdFrame:IsShown() = " .. tostring(icdFrame:IsShown()))
        print("  icdFrame:GetAlpha() = " .. tostring(icdFrame:GetAlpha()))
        print("  icdOn overlay alpha = " .. tostring(icdFrame.icdOn and icdFrame.icdOn:GetAlpha()))
    end
    print("  icdActive = " .. tostring(icdActive))
    print("  icdDebug = " .. tostring(icdDebug))
    -- Check imbue details
    if ShammyTime.GetWeaponImbuePerHand then
        local hands = ShammyTime.GetWeaponImbuePerHand()
        if hands then
            local now = GetTime()
            if hands.mainHand then
                local rem = hands.mainHand.expirationTime and (hands.mainHand.expirationTime - now) or 0
                print("  MH imbue: name=" .. tostring(hands.mainHand.name) .. " remaining=" .. ("%.0f"):format(rem) .. "s")
            else
                print("  MH imbue: none")
            end
            if hands.offHand then
                local rem = hands.offHand.expirationTime and (hands.offHand.expirationTime - now) or 0
                print("  OH imbue: name=" .. tostring(hands.offHand.name) .. " remaining=" .. ("%.0f"):format(rem) .. "s")
            else
                print("  OH imbue: none")
            end
        end
    end
    -- Check totems
    if GetTotemInfo then
        for slot = 1, 4 do
            local haveTotem, totemName = GetTotemInfo(slot)
            if haveTotem and totemName and totemName ~= "" then
                print("  Totem slot " .. slot .. ": " .. totemName)
            end
        end
    end
end
