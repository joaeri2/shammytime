-- ShammyTime_WFImpact.lua
-- "Windfury Totem Bonus Damage Feed"
-- Tracks party members' Windfury Totem procs (from YOUR totem) and shows
-- scrolling damage text anchored above the WF totem slot on the totem bar,
-- plus a combat-end total popup.
--
-- Integrated with ShammyTime module system: settings via DB, options panel,
-- enable/disable, demo mode. Also has standalone /wfimpact commands.
--
-- Label: "WF bonus damage (estimate)" — attribution is heuristic-based.
-- WoW Classic TBC Anniversary 2026 (Interface 20501–20505).

local ADDON_NAME = "ShammyTime"
local M = _G.ShammyTime_Media  -- may be nil if Media hasn't loaded; we fallback

-- ---------------------------------------------------------------------------
-- Constants (non-configurable)
-- ---------------------------------------------------------------------------

-- Correlation window: how long after SPELL_EXTRA_ATTACKS we attribute SWING_DAMAGE
local WF_WINDOW = (M and M.WF_CORRELATION_WINDOW) or 0.40

-- Known Windfury Totem spell names (prefix-match handles rank suffixes).
local WF_TOTEM_NAMES = { "Windfury Totem" }

-- Windfury Totem BUFF spell ID (charge-based aura on party members).
-- Confirmed in TBC Anniversary Classic 2026: SPELL_EXTRA_ATTACKS fires with spell 8516.
local WF_TOTEM_BUFF_SPELL_ID = 8516

-- Windfury Attack (personal WF Weapon imbue, spell 25584). NOT tracked here —
-- that's the self-cast imbue, not the totem. Kept only for SPELL_EXTRA_ATTACKS
-- name matching (some clients may report "Windfury Attack" as the spell name).
local WF_ATTACK_SPELL_NAME = "Windfury Attack"

-- How many extra swings WF Totem grants per proc (1 in TBC).
local WF_TOTEM_EXTRA_SWINGS = 1

-- Non-configurable UI constants
local FONT_PATH       = "Fonts\\FRIZQT__.TTF"
local FONT_OUTLINE    = "OUTLINE"
local SCROLL_H_JITTER = 10     -- max horizontal offset (pixels)
local POOL_SIZE       = 10     -- pre-created FontStrings
local TOTAL_HOLD      = 1.8    -- seconds to hold the combat-end total
local TOTAL_FADE_OUT  = 1.2    -- seconds to fade out the total
local FRAME_WIDTH     = 200
local FRAME_HEIGHT    = 150
local TITLE_HEIGHT    = 16

-- Class colors
local CLASS_COLORS = RAID_CLASS_COLORS or {}

-- ---------------------------------------------------------------------------
-- DB access helpers
-- ---------------------------------------------------------------------------

--- Get the profile table, or nil if DB not ready.
local function GetDB()
    local st = _G.ShammyTime
    if st and st.db and st.db.profile then return st.db.profile end
    return nil
end

--- Get a flat DB value with default fallback.
local function GetSetting(key, default)
    local p = GetDB()
    if not p then return default end
    local v = p[key]
    if v ~= nil then return v end
    return default
end

--- Check if the module is enabled in the DB.
local function IsModuleEnabled()
    local p = GetDB()
    if not p then return true end  -- default on
    if p.modules and p.modules.wfImpact then
        return p.modules.wfImpact.enabled ~= false
    end
    return p.wfImpactEnabled ~= false
end

-- Configurable defaults (used when DB not available yet)
local DEFAULT_FONT_SCROLL     = 15
local DEFAULT_FONT_TOTAL      = 16
local DEFAULT_SCROLL_DURATION = 2.0
local DEFAULT_SCROLL_DISTANCE = 115
local DEFAULT_OFFSET_X        = 0
local DEFAULT_OFFSET_Y        = -26

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local state = {
    wfTotemActive      = false,
    inCombat           = false,
    pendingExtra       = {},   -- [sourceGUID] = { count = N, expiresAt = t }
    -- Per-fight (reset each combat, used for the end-of-combat popup)
    fightTotal         = 0,
    fightHits          = 0,
    fightPerPlayer     = {},   -- [sourceGUID] = { name=, damage=, hits=, guid= }
    -- Last-fight snapshot (survives into next combat for tooltip)
    lastFightTotal     = 0,
    lastFightHits      = 0,
    lastFightPerPlayer = {},   -- sorted array from previous fight
    -- Cumulative session (persists across fights, reset by user)
    sessionTotal       = 0,
    sessionHits        = 0,
    sessionStart       = nil,  -- GetTime() when session/reset started
    perPlayer          = {},   -- [sourceGUID] = { name=, damage=, hits=, guid= }
    fights             = 0,    -- number of fights with WF procs
    debug              = false, -- /wfimpact debug
    enabled            = true,  -- runtime enabled flag (synced from DB)
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function IsWindfuryTotemName(name)
    if not name or name == "" then return false end
    for _, wfName in ipairs(WF_TOTEM_NAMES) do
        if name == wfName or name:find(wfName, 1, true) == 1 then
            return true
        end
    end
    return false
end

local function IsPlayerOrParty(guid)
    if not guid then return false end
    if guid == UnitGUID("player") then return true end
    if IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) and UnitGUID(unit) == guid then
                return true
            end
        end
    end
    return false
end

local function GetClassColorForGUID(guid)
    if guid == UnitGUID("player") then
        local _, class = UnitClass("player")
        local c = class and CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
    end
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and UnitGUID(unit) == guid then
            local _, class = UnitClass(unit)
            local c = class and CLASS_COLORS[class]
            if c then return c.r, c.g, c.b end
        end
    end
    return 1, 0.82, 0
end

local function FormatNumber(n)
    if not n then return "0" end
    local formatted = tostring(math.floor(n))
    while true do
        local k
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

local function ShortName(name)
    if not name then return "?" end
    local dash = name:find("-", 1, true)
    if dash then return name:sub(1, dash - 1) end
    return name
end

-- ---------------------------------------------------------------------------
-- UI: Anchor Frame
-- ---------------------------------------------------------------------------
local anchor
local titleBar
local scrollPool = {}
local totalText
local totalAnimGroup

local function CreateAnchorFrame()
    if anchor then return anchor end

    anchor = CreateFrame("Frame", "ShammyTimeWFImpactFrame", UIParent)
    anchor:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetFrameLevel(50)
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    anchor:EnableMouse(false)

    -- Default position (will be overridden by ApplyPosition if totem bar exists)
    anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 100)

    -- Title bar: drag handle (shown only when unlocked)
    titleBar = CreateFrame("Frame", nil, anchor)
    titleBar:SetSize(FRAME_WIDTH, TITLE_HEIGHT)
    titleBar:SetPoint("TOP", anchor, "TOP", 0, 0)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(0.1, 0.6, 0.9, 0.5)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(FONT_PATH, 10, FONT_OUTLINE)
    titleText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    titleText:SetText("WF Impact (drag)")
    titleText:SetTextColor(1, 1, 1, 0.9)

    titleBar:SetMovable(true)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        anchor:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
    end)

    titleBar:Hide()

    titleBar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("WF Impact", 1, 1, 1)
        GameTooltip:AddLine("WF bonus damage (estimate)", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag to reposition.", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    titleBar:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return anchor
end

-- ---------------------------------------------------------------------------
-- UI: Position — anchor above totem bar's air slot (slot 4)
-- ---------------------------------------------------------------------------
local function ApplyPosition()
    if not anchor then return end
    local offsetX = GetSetting("wfImpactOffsetX", DEFAULT_OFFSET_X)
    local offsetY = GetSetting("wfImpactOffsetY", DEFAULT_OFFSET_Y)

    -- Try to anchor to the air/WF totem slot (visual position 4 = rightmost)
    local airSlot = _G.ShammyTimeWindfuryTotemSlot4
    if airSlot and airSlot:GetParent() and airSlot:GetParent():IsShown() then
        anchor:ClearAllPoints()
        anchor:SetPoint("BOTTOM", airSlot, "TOP", offsetX, offsetY)
    else
        -- Fallback: anchor to totem bar frame if it exists
        local barFrame = _G.ShammyTimeWindfuryTotemBarFrame
        if barFrame then
            anchor:ClearAllPoints()
            anchor:SetPoint("BOTTOM", barFrame, "TOP", offsetX, offsetY)
        end
        -- else: keep whatever position it has (CENTER default or user-dragged)
    end
end

-- ---------------------------------------------------------------------------
-- UI: Scrolling text pool — DB-driven font/animation
-- ---------------------------------------------------------------------------

--- Get current scroll settings from DB.
local function GetScrollSettings()
    return {
        fontSize       = GetSetting("wfImpactFontScroll", DEFAULT_FONT_SCROLL),
        fontSizeTotal  = GetSetting("wfImpactFontTotal", DEFAULT_FONT_TOTAL),
        scrollDuration = GetSetting("wfImpactScrollDuration", DEFAULT_SCROLL_DURATION),
        scrollDistance  = GetSetting("wfImpactScrollDistance", DEFAULT_SCROLL_DISTANCE),
    }
end

local function CreateScrollLine(parent)
    local cfg = GetScrollSettings()
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT_PATH, cfg.fontSize, FONT_OUTLINE)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:Hide()

    local ag = fs:CreateAnimationGroup()

    local translate = ag:CreateAnimation("Translation")
    translate:SetOffset(0, cfg.scrollDistance)
    translate:SetDuration(cfg.scrollDuration)
    translate:SetSmoothing("OUT")

    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(cfg.scrollDuration)
    fade:SetSmoothing("IN")
    fade:SetStartDelay(0.15)

    ag:SetScript("OnFinished", function()
        fs:Hide()
        fs._poolInUse = false
    end)

    -- Store references for later updates
    fs._poolAG = ag
    fs._poolTranslate = translate
    fs._poolFade = fade
    fs._poolInUse = false

    return fs
end

local function InitScrollPool()
    local parent = CreateAnchorFrame()
    for i = 1, POOL_SIZE do
        scrollPool[i] = CreateScrollLine(parent)
    end
end

--- Update all pool entries with current DB settings (called when user changes options).
local function UpdateScrollPoolSettings()
    local cfg = GetScrollSettings()
    for i = 1, #scrollPool do
        local fs = scrollPool[i]
        if fs then
            fs:SetFont(FONT_PATH, cfg.fontSize, FONT_OUTLINE)
            if fs._poolTranslate then
                fs._poolTranslate:SetOffset(0, cfg.scrollDistance)
                fs._poolTranslate:SetDuration(cfg.scrollDuration)
            end
            if fs._poolFade then
                fs._poolFade:SetDuration(cfg.scrollDuration)
            end
        end
    end
    -- Update total popup font too
    if totalText then
        totalText:SetFont(FONT_PATH, cfg.fontSizeTotal, FONT_OUTLINE)
    end
end

local function AcquireScrollLine()
    for i = 1, #scrollPool do
        if not scrollPool[i]._poolInUse then
            scrollPool[i]._poolInUse = true
            return scrollPool[i]
        end
    end
    local fs = CreateScrollLine(anchor)
    fs._poolInUse = true
    scrollPool[#scrollPool + 1] = fs
    return fs
end

-- ---------------------------------------------------------------------------
-- UI: Spawn a scrolling damage line
-- ---------------------------------------------------------------------------
local function SpawnScrollLine(playerName, damageAmount, sourceGUID)
    if not anchor then return end
    if not state.enabled then return end

    local fs = AcquireScrollLine()
    local shortName = ShortName(playerName)
    local r, g, b = GetClassColorForGUID(sourceGUID)

    local hexColor = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
    fs:SetText(hexColor .. shortName .. "|r +" .. FormatNumber(damageAmount))

    local hOffset = math.random(-SCROLL_H_JITTER, SCROLL_H_JITTER)
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", anchor, "CENTER", hOffset, 0)
    fs:SetAlpha(1)
    fs:Show()

    if fs._poolAG then
        fs._poolAG:Stop()
        fs._poolAG:Play()
    end
end

-- ---------------------------------------------------------------------------
-- UI: Combat-end total popup
-- ---------------------------------------------------------------------------
local function CreateTotalPopup()
    if totalText then return end
    local parent = CreateAnchorFrame()
    local cfg = GetScrollSettings()

    totalText = parent:CreateFontString(nil, "OVERLAY")
    totalText:SetFont(FONT_PATH, cfg.fontSizeTotal, FONT_OUTLINE)
    totalText:SetShadowColor(0, 0, 0, 1)
    totalText:SetShadowOffset(1, -1)
    totalText:SetTextColor(0.2, 1, 0.2)
    totalText:SetPoint("CENTER", parent, "CENTER", 0, -20)
    totalText:Hide()

    totalAnimGroup = totalText:CreateAnimationGroup()

    local fadeIn = totalAnimGroup:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.15)
    fadeIn:SetOrder(1)

    local hold = totalAnimGroup:CreateAnimation("Alpha")
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(TOTAL_HOLD)
    hold:SetOrder(2)

    local fadeOut = totalAnimGroup:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(TOTAL_FADE_OUT)
    fadeOut:SetSmoothing("IN")
    fadeOut:SetOrder(3)

    totalAnimGroup:SetScript("OnFinished", function()
        totalText:Hide()
    end)
end

local function ShowTotalPopup(total, hitCount)
    if not totalText then CreateTotalPopup() end
    if not totalText then return end
    if not state.enabled then return end

    local hitsStr = hitCount and hitCount > 0 and (" (" .. hitCount .. " hits)") or ""
    totalText:SetText("WF Bonus: " .. FormatNumber(total) .. hitsStr)
    totalText:SetAlpha(0)
    totalText:Show()

    if totalAnimGroup then
        totalAnimGroup:Stop()
        totalAnimGroup:Play()
    end
end

local function HideTotalPopup()
    if totalText then
        totalText:Hide()
        if totalAnimGroup then totalAnimGroup:Stop() end
    end
end

-- ---------------------------------------------------------------------------
-- Totem detection
-- ---------------------------------------------------------------------------
local function CheckWindfuryTotemActive()
    for slot = 1, 4 do
        local haveTotem, totemName = GetTotemInfo(slot)
        if haveTotem and IsWindfuryTotemName(totemName) then
            state.wfTotemActive = true
            return
        end
    end
    state.wfTotemActive = false
end

-- ---------------------------------------------------------------------------
-- Combat state
-- ---------------------------------------------------------------------------
local function OnCombatStart()
    state.inCombat = true
    state.fightTotal = 0
    state.fightHits  = 0
    wipe(state.fightPerPlayer)
    wipe(state.pendingExtra)
    HideTotalPopup()
    -- Lazy-init session start time
    if not state.sessionStart then
        state.sessionStart = GetTime()
    end
end

local function OnCombatEnd()
    state.inCombat = false
    if state.fightTotal > 0 then
        state.fights = state.fights + 1
        -- Snapshot per-fight breakdown for "Last Fight" tooltip section
        state.lastFightTotal = state.fightTotal
        state.lastFightHits  = state.fightHits
        local snapshot = {}
        for _, pp in pairs(state.fightPerPlayer) do
            snapshot[#snapshot + 1] = { name = pp.name, damage = pp.damage, hits = pp.hits, guid = pp.guid }
        end
        table.sort(snapshot, function(a, b) return a.damage > b.damage end)
        state.lastFightPerPlayer = snapshot
        ShowTotalPopup(state.fightTotal, state.fightHits)
    end
    wipe(state.pendingExtra)
end

local function ResetStats()
    state.sessionTotal = 0
    state.sessionHits  = 0
    state.fights       = 0
    state.sessionStart = GetTime()
    wipe(state.perPlayer)
    -- Also reset per-fight and last-fight
    state.fightTotal = 0
    state.fightHits  = 0
    state.lastFightTotal = 0
    state.lastFightHits  = 0
    wipe(state.fightPerPlayer)
    state.lastFightPerPlayer = {}
    wipe(state.pendingExtra)
    HideTotalPopup()
end

-- ---------------------------------------------------------------------------
-- Combat log processing
-- ---------------------------------------------------------------------------
local function CleanExpiredPending()
    local now = GetTime()
    for guid, info in pairs(state.pendingExtra) do
        if now > info.expiresAt then
            state.pendingExtra[guid] = nil
        end
    end
end

local function OnCombatLogEvent()
    if not CombatLogGetCurrentEventInfo then return end

    local timestamp, subevent, hideCaster,
          sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

    -- DEBUG MODE
    if state.debug then
        local isRelevant = IsPlayerOrParty(sourceGUID) or IsPlayerOrParty(destGUID)
        if isRelevant then
            local spellId   = select(12, CombatLogGetCurrentEventInfo()) or "?"
            local spellName = select(13, CombatLogGetCurrentEventInfo()) or "?"
            local arg15     = select(15, CombatLogGetCurrentEventInfo()) or "?"
            local arg21     = select(21, CombatLogGetCurrentEventInfo()) or "?"
            print(string.format(
                "|cffff8800[WFI DBG]|r %s src=%s dst=%s spell=%s/%s arg15=%s arg21=%s",
                tostring(subevent), tostring(sourceName), tostring(destName),
                tostring(spellId), tostring(spellName), tostring(arg15), tostring(arg21)
            ))
        end
    end

    -- Gate: need enabled + totem active (no combat gate — first swing that
    -- pulls a mob can proc WF before PLAYER_REGEN_DISABLED fires)
    if not state.enabled then return end
    if not state.wfTotemActive then return end

    -- ===================================================================
    -- METHOD 1 (PRIMARY): SPELL_EXTRA_ATTACKS with spell 8516 "Windfury Totem"
    -- Confirmed in TBC Anniversary Classic 2026. Event order:
    --   1. SPELL_EXTRA_ATTACKS spell=8516 arg15=1  ← FIRES FIRST
    --   2. SWING_DAMAGE (extra attack)              ← right after
    --   3. SPELL_AURA_REMOVED_DOSE spell=8516       ← too late
    -- ===================================================================
    if subevent == "SPELL_EXTRA_ATTACKS" then
        local spellId    = select(12, CombatLogGetCurrentEventInfo())
        local spellName  = select(13, CombatLogGetCurrentEventInfo())
        local extraCount = select(15, CombatLogGetCurrentEventInfo())

        local isWF = (spellId and spellId == WF_TOTEM_BUFF_SPELL_ID)
                  or (spellName and IsWindfuryTotemName(spellName))
                  or (spellName and spellName == WF_ATTACK_SPELL_NAME)

        if isWF then
            local procGUID = sourceGUID
            local procName = sourceName
            if not IsPlayerOrParty(sourceGUID) and IsPlayerOrParty(destGUID) then
                procGUID = destGUID
                procName = destName
            end

            if IsPlayerOrParty(procGUID) then
                local count = (extraCount and extraCount > 0) and extraCount or WF_TOTEM_EXTRA_SWINGS
                local existing = state.pendingExtra[procGUID]
                if existing and GetTime() <= existing.expiresAt then
                    existing.count = existing.count + count
                    existing.expiresAt = GetTime() + WF_WINDOW
                else
                    state.pendingExtra[procGUID] = {
                        count     = count,
                        expiresAt = GetTime() + WF_WINDOW,
                        name      = procName,
                    }
                end
                if state.debug then
                    print("|cff00ff00[WFI]|r WF proc! " .. tostring(procName) .. " — capturing next " .. count .. " swing(s)")
                end
            end
        end
        return
    end

    -- NOTE: We intentionally do NOT track SPELL_DAMAGE "Windfury Attack" (spell 25584).
    -- That event comes from the personal Windfury Weapon imbue, not the totem.
    -- We only want totem procs: SPELL_EXTRA_ATTACKS (8516) → SWING_DAMAGE.

    -- ===================================================================
    -- SWING_DAMAGE: attribute to WF if pending proc window is open
    -- ===================================================================
    if subevent == "SWING_DAMAGE" or subevent == "SWING_DAMAGE_LANDED" then
        local pending = state.pendingExtra[sourceGUID]
        if pending and GetTime() <= pending.expiresAt and pending.count > 0 then
            local dmgAmount = select(12, CombatLogGetCurrentEventInfo())
            if dmgAmount and dmgAmount > 0 then
                -- Per-fight (for end-of-combat popup)
                state.fightTotal = state.fightTotal + dmgAmount
                state.fightHits  = state.fightHits + 1
                -- Cumulative session
                state.sessionTotal = state.sessionTotal + dmgAmount
                state.sessionHits  = state.sessionHits + 1
                -- Per-player accumulation (session-level)
                local pp = state.perPlayer[sourceGUID]
                if not pp then
                    pp = { name = pending.name or sourceName, damage = 0, hits = 0, guid = sourceGUID }
                    state.perPlayer[sourceGUID] = pp
                end
                pp.damage = pp.damage + dmgAmount
                pp.hits = pp.hits + 1
                -- Per-player accumulation (fight-level)
                local fp = state.fightPerPlayer[sourceGUID]
                if not fp then
                    fp = { name = pending.name or sourceName, damage = 0, hits = 0, guid = sourceGUID }
                    state.fightPerPlayer[sourceGUID] = fp
                end
                fp.damage = fp.damage + dmgAmount
                fp.hits = fp.hits + 1
                pending.count = pending.count - 1
                SpawnScrollLine(pending.name or sourceName, dmgAmount, sourceGUID)
                if state.debug then
                    print("|cff00ff00[WFI]|r Attributed swing! " .. tostring(sourceName) .. " +" .. tostring(dmgAmount) .. " (remaining=" .. pending.count .. ")")
                end
                if pending.count <= 0 then
                    state.pendingExtra[sourceGUID] = nil
                end
            end
        end
        return
    end

    CleanExpiredPending()
end

-- ---------------------------------------------------------------------------
-- Lock / Unlock
-- ---------------------------------------------------------------------------
local isUnlocked = false

local function SetUnlocked(unlock)
    isUnlocked = unlock
    if not anchor then CreateAnchorFrame() end

    if unlock then
        titleBar:Show()
        anchor:EnableMouse(true)
        if not anchor._debugBg then
            anchor._debugBg = anchor:CreateTexture(nil, "BACKGROUND")
            anchor._debugBg:SetAllPoints()
            anchor._debugBg:SetColorTexture(0, 0, 0, 0.2)
        end
        anchor._debugBg:Show()
        anchor:Show()
    else
        titleBar:Hide()
        anchor:EnableMouse(false)
        if anchor._debugBg then anchor._debugBg:Hide() end
    end
end

local function ToggleLock()
    SetUnlocked(not isUnlocked)
end

-- ---------------------------------------------------------------------------
-- Test / simulate
-- ---------------------------------------------------------------------------
local function SimulateWFProcs()
    if not anchor then CreateAnchorFrame() end
    anchor:Show()

    -- Build a list of real party members (with GUIDs for class colors), pad with player
    local fakeUnits = {}
    -- Always include the player
    local playerName = UnitName("player")
    local playerGUID = UnitGUID("player")
    fakeUnits[#fakeUnits + 1] = { name = playerName or "You", guid = playerGUID }
    -- Add party members if in a group
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            fakeUnits[#fakeUnits + 1] = { name = UnitName(unit), guid = UnitGUID(unit) }
        end
    end
    -- If solo, add some fake names with player's GUID (so they get player's class color)
    if #fakeUnits == 1 then
        fakeUnits[#fakeUnits + 1] = { name = "Legolas", guid = playerGUID }
        fakeUnits[#fakeUnits + 1] = { name = "Gimli", guid = playerGUID }
        fakeUnits[#fakeUnits + 1] = { name = "Aragorn", guid = playerGUID }
    end

    local fakeDamages = { 312, 487, 256, 621, 389, 445, 198, 533 }
    local total = 0

    for i = 1, 6 do
        C_Timer.After(i * 0.3, function()
            local unit = fakeUnits[math.random(#fakeUnits)]
            local dmg = fakeDamages[math.random(#fakeDamages)]
            total = total + dmg
            SpawnScrollLine(unit.name, dmg, unit.guid)

            if i == 6 then
                C_Timer.After(1.5, function()
                    ShowTotalPopup(total, 6)
                end)
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Module API: exposed for ShammyTime_Modules.lua and options panel
-- ---------------------------------------------------------------------------

--- Ensure the anchor frame exists, apply position, return it.
local function EnsureFrame()
    CreateAnchorFrame()
    InitScrollPool()
    CreateTotalPopup()
    ApplyPosition()
    return anchor
end

--- Apply all config from DB (scale, alpha, position, fonts, etc.)
local function ApplyConfig()
    if not anchor then EnsureFrame() end
    if not anchor then return end

    -- Read module config
    local p = GetDB()
    local cfg = p and p.modules and p.modules.wfImpact
    local moduleScale = (cfg and type(cfg.scale) == "number" and cfg.scale >= 0.1 and cfg.scale <= 3) and cfg.scale or 1
    local moduleAlpha = (cfg and type(cfg.alpha) == "number" and cfg.alpha >= 0 and cfg.alpha <= 1) and cfg.alpha or 1

    -- Apply effective scale (module * master)
    local masterScale = 1
    local masterAlpha = 1
    if p and p.global then
        local g = p.global
        masterScale = (g.masterScale and g.masterScale >= 0.5 and g.masterScale <= 2) and g.masterScale or 1
        masterAlpha = (g.masterAlpha and g.masterAlpha >= 0 and g.masterAlpha <= 1) and g.masterAlpha or 1
    end

    anchor:SetScale(moduleScale * masterScale)
    anchor:SetAlpha(moduleAlpha * masterAlpha)

    -- Update position (anchored to totem slot)
    ApplyPosition()

    -- Update font sizes and animation timing
    UpdateScrollPoolSettings()

    -- Update enabled state
    state.enabled = IsModuleEnabled()

    -- Show/hide based on enabled
    if state.enabled then
        anchor:Show()
    else
        anchor:Hide()
        HideTotalPopup()
    end
end

--- Set enabled/disabled from module system.
local function SetEnabled(enabled)
    state.enabled = enabled
    local p = GetDB()
    if p then
        if p.modules and p.modules.wfImpact then
            p.modules.wfImpact.enabled = enabled
        end
        p.wfImpactEnabled = enabled
    end
    if anchor then
        if enabled then
            anchor:Show()
        else
            anchor:Hide()
            HideTotalPopup()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Event frame
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        EnsureFrame()
        CheckWindfuryTotemActive()
        state.enabled = IsModuleEnabled()
        if state.enabled and anchor then anchor:Show() end

    elseif event == "PLAYER_TOTEM_UPDATE" then
        CheckWindfuryTotemActive()
        -- Re-anchor in case totem bar just appeared
        ApplyPosition()

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLogEvent()

    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()

    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    end
end)

-- ---------------------------------------------------------------------------
-- Slash command: /wfimpact
-- ---------------------------------------------------------------------------
SLASH_WFIMPACT1 = "/wfimpact"
SlashCmdList["WFIMPACT"] = function(msg)
    msg = (msg or ""):lower():trim()
    if msg == "lock" or msg == "unlock" or msg == "toggle" then
        ToggleLock()
    elseif msg == "test" or msg == "sim" then
        SimulateWFProcs()
    elseif msg == "reset" then
        ResetStats()
        print("|cff00ccff[WF Impact]|r Stats reset.")
    elseif msg == "debug" then
        state.debug = not state.debug
        if state.debug then
            print("|cff00ccff[WF Impact]|r Debug ON — printing ALL combat log events from you/party.")
            print("|cff00ccff[WF Impact]|r Totem active: " .. tostring(state.wfTotemActive))
        else
            print("|cff00ccff[WF Impact]|r Debug OFF.")
        end
    elseif msg == "status" then
        print("|cff00ccff[WF Impact]|r Status:")
        print("  Enabled: " .. tostring(state.enabled))
        print("  Totem active: " .. tostring(state.wfTotemActive))
        print("  In combat: " .. tostring(state.inCombat))
        print("  Session total: " .. FormatNumber(state.sessionTotal) .. " (" .. state.sessionHits .. " hits, " .. state.fights .. " fights)")
        print("  This fight: " .. FormatNumber(state.fightTotal) .. " (" .. state.fightHits .. " hits)")
        print("  Debug: " .. tostring(state.debug))
    else
        print("|cff00ccff[WF Impact]|r Commands:")
        print("  /wfimpact lock/unlock — toggle frame lock")
        print("  /wfimpact test — simulate WF procs")
        print("  /wfimpact reset — reset combat state")
        print("  /wfimpact debug — toggle CLEU debug output")
        print("  /wfimpact status — show current state")
    end
end

-- Hook into /st wfimpact
C_Timer.After(1, function()
    local origHandler = SlashCmdList["SHAMMYTIME"] or SlashCmdList["ST"]
    if origHandler then
        local function hookedHandler(msg)
            if msg and msg:lower():find("^wfimpact") then
                local sub = msg:lower():match("^wfimpact%s*(.*)")
                SlashCmdList["WFIMPACT"](sub or "")
                return
            end
            origHandler(msg)
        end
        if SlashCmdList["SHAMMYTIME"] then
            SlashCmdList["SHAMMYTIME"] = hookedHandler
        end
        if SlashCmdList["ST"] then
            SlashCmdList["ST"] = hookedHandler
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Expose API globally for module system and options panel
-- ---------------------------------------------------------------------------
ShammyTime_WFImpact = {
    state              = state,
    EnsureFrame        = EnsureFrame,
    ApplyConfig        = ApplyConfig,
    ApplyPosition      = ApplyPosition,
    SetEnabled         = SetEnabled,
    Simulate           = SimulateWFProcs,
    ToggleLock         = ToggleLock,
    CheckTotem         = CheckWindfuryTotemActive,
    UpdateScrollPool   = UpdateScrollPoolSettings,
    FormatNumber       = FormatNumber,
    ShortName          = ShortName,
    GetClassColor      = GetClassColorForGUID,
    ResetStats         = ResetStats,
    GetSessionStats    = function()
        return state.sessionTotal, state.sessionHits, state.sessionStart, state.fights
    end,
    GetPerPlayer       = function()
        -- Return a sorted snapshot of the cumulative per-player table
        local sorted = {}
        for _, pp in pairs(state.perPlayer) do
            sorted[#sorted + 1] = { name = pp.name, damage = pp.damage, hits = pp.hits, guid = pp.guid }
        end
        table.sort(sorted, function(a, b) return a.damage > b.damage end)
        return sorted
    end,
    GetLastFight       = function()
        return state.lastFightTotal, state.lastFightHits, state.lastFightPerPlayer
    end,
}
