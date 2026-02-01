-- ShammyTime: Movable totem icons with timers, "gone" animation, and out-of-range indicator.
-- When you're too far from a totem to receive its buff, a red overlay appears on that slot.
-- WoW Classic Anniversary 2026 (TBC Anniversary Edition, Interface 20505); compatible with builds 20501–20505.

local addonName, addon = ...
-- Chat colors for slash help (WoW: |cAARRGGBB text |r)
local C = {
    gold = "|cffffcc00",
    white = "|cffffffff",
    gray = "|cffb0b0b0",
    green = "|cff00ff00",
    red = "|cffff4040",
    r = "|r",
}
local SLOT_TO_ELEMENT = { [1] = "Fire", [2] = "Earth", [3] = "Water", [4] = "Air" }
-- Display order left-to-right: stone (Earth), fire, water, air. WoW API slots: 1=Fire, 2=Earth, 3=Water, 4=Air.
local DISPLAY_ORDER = { 2, 1, 3, 4 }
local ELEMENT_COLORS = {
    Fire  = { r = 0.9,  g = 0.3,  b = 0.2  },
    Earth = { r = 0.6,  g = 0.4,  b = 0.2  },
    Water = { r = 0.2,  g = 0.5,  b = 0.9  },
    Air   = { r = 0.4,  g = 0.8,  b = 0.9  },
}
-- Darkened elemental icons for empty slots (which element is missing)
local ELEMENT_EMPTY_ICONS = {
    Fire  = "Interface\\Icons\\INV_Elemental_Primal_Fire",
    Earth = "Interface\\Icons\\INV_Elemental_Primal_Earth",
    Water = "Interface\\Icons\\INV_Elemental_Primal_Water",
    Air   = "Interface\\Icons\\INV_Elemental_Primal_Air",
}
-- Lightning Shield: all TBC spell IDs (ranks 1–6) and icon when not active
local LIGHTNING_SHIELD_SPELL_IDS = { 324, 325, 905, 945, 8134, 10431 }
local LIGHTNING_SHIELD_ICON = "Interface\\Icons\\Spell_Nature_LightningShield"
-- Water Shield: TBC spell IDs (ranks 1–2); same slot as Lightning Shield (only one elemental shield active at a time)
local WATER_SHIELD_SPELL_IDS = { 24398, 33736 }
local WATER_SHIELD_ICON = "Interface\\Icons\\Ability_Shaman_WaterShield"
local WATER_SHIELD_ICON_ID = 132315  -- FileDataID for clients where SetTexture(path) doesn't display

-- Weapon imbue buff spell IDs (Flametongue, Frostbrand, Rockbiter, Windfury Weapon – all ranks)
local WEAPON_IMBUE_SPELL_IDS = {
    [8024]=true, [8027]=true, [8030]=true, [16339]=true, [16341]=true, [16342]=true, [25489]=true,  -- Flametongue
    [8033]=true, [8034]=true, [8037]=true, [10458]=true, [16352]=true, [16353]=true, [25500]=true, [25501]=true,  -- Frostbrand
    [8017]=true, [8018]=true, [8019]=true, [10399]=true, [16314]=true, [16315]=true, [16316]=true, [25479]=true,  -- Rockbiter
    [8232]=true, [8235]=true, [10486]=true, [16362]=true, [25505]=true,  -- Windfury Weapon
}
local WEAPON_IMBUE_ICON = "Interface\\Icons\\Spell_Fire_FlameTongue"
-- Numeric FileDataID for clients where SetTexture(path) doesn't display (e.g. TBC Anniversary); LibWeaponEnchantInfo uses 136040.
local WEAPON_IMBUE_ICON_ID = 136040
-- Icon when no weapon imbue is active (empty slot); Frostbrand icon = 135847 (Spell_Frost_FrostBrand).
local WEAPON_IMBUE_EMPTY_ICON_ID = 135847
-- Shamanistic Focus proc: "Focused" buff (spell 43339) from melee crit; next Shock costs 60% less, 15 sec (TBC).
local FOCUSED_BUFF_SPELL_ID = 43339
local FOCUSED_ICON = "Interface\\Icons\\Spell_Arcane_FocusedPower"
-- GetWeaponEnchantInfo returns mainHandEnchantID (4th) and offHandEnchantID (8th). Map enchant ID -> spellId (for name/GetSpellTexture) and icon FileDataID (fallback).
-- Sources: various clients; add more IDs from /st debug if your imbue isn't recognized.
local WEAPON_IMBUE_ENCHANT_TO_SPELL = {
    -- Flametongue (various ranks/sources)
    [3]=25489, [4]=25489, [5]=25489, [124]=8024, [285]=8027, [523]=16339, [543]=8030, [1683]=16342, [2634]=25489,
    -- Frostbrand
    [2]=25501, [12]=25501,
    -- Rockbiter (3031=TBC Anniversary; 503=Rockbiter 4, 683=Rockbiter 6; 1,6,29 from other clients). Spell 25479 = Rockbiter Weapon TBC.
    [1]=25479, [6]=25479, [29]=25479, [503]=25479, [683]=25479, [3031]=25479,
    -- Windfury Weapon (283=Windfury Rank 1 TBC Anniversary; 3787=Windfury 8; 563,564,1783 from totem/lib)
    [15]=25505, [16]=25505, [17]=25505, [283]=25505, [563]=25505, [564]=25505, [1783]=25505, [3787]=25505,
}
-- Windfury Attack: spell ID for the actual proc damage in combat log (TBC: 25584).
local WINDFURY_ATTACK_SPELL_ID = 25584

-- Enchant ID -> icon FileDataID. Rockbiter=136086 (Spell_Nature_RockBiter), Windfury=136114 (Spell_Nature_LightningShield/Windfury).
local WEAPON_IMBUE_ENCHANT_ICONS = {
    [3]=136040, [4]=136040, [5]=136040, [124]=136040, [285]=136040, [523]=136040, [543]=136040, [1683]=136040, [2634]=136040,
    [2]=135847, [12]=135847,
    [1]=136086, [6]=136086, [29]=136086, [503]=136086, [683]=136086, [3031]=136086,
    [15]=136114, [16]=136114, [17]=136114, [283]=136114, [563]=136114, [564]=136114, [1783]=136114, [3787]=136114,
}

-- Totems that do NOT put a buff on the player (no way to detect range via buffs). Never show buff-based out-of-range for these.
-- Stoneclaw: buff 8072 only appears when the totem absorbs damage, not when in range, so we use position-only.
local TOTEM_NO_RANGE_BUFF = {
    ["Windfury Totem"] = true,   -- weapon proc only, no persistent buff
    ["Stoneclaw Totem"] = true, -- buff only when totem is hit; use position-based range only
    ["Earth Elemental Totem"] = true,
    ["Fire Elemental Totem"] = true,
}

-- Secondary range check: totems with no player buff but a known effect radius. We approximate totem position
-- as player position when the totem was placed (UnitPosition only works outdoors). Totem name (or prefix) → max radius in yards.
-- Radii for TBC Anniversary / WoW Classic 2026 (classicdb, wowclassicdb, Wowhead TBC).
-- GetTotemInfo returns localized spell name. Prefix match handles ranks ("Mana Spring Totem II").
-- Totems with no player buff: we use position-based range (UnitPosition outdoors only).
local TOTEM_POSITION_RANGE = {
    -- Earth
    ["Stoneclaw Totem"] = 8,
    ["Earthbind Totem"] = 10,
    ["Tremor Totem"] = 30,
    -- Fire
    ["Searing Totem"] = 20,
    ["Magma Totem"] = 8,
    ["Fire Nova Totem"] = 10,
    -- Water (cleansing: no buff on player)
    ["Poison Cleansing Totem"] = 30,
    ["Disease Cleansing Totem"] = 30,
    -- Air (Windfury = weapon proc only; use position-based range)
    ["Windfury Totem"] = 20,
}

-- Totem name (from GetTotemInfo) → buff spell ID on player. When totem is down but player
-- doesn't have this buff, we're out of range. Match by exact name or by prefix (e.g. "Mana Spring Totem" matches "Mana Spring Totem II").
-- Only include totems that put a *persistent* aura on the player (not procs like Windfury).
local TOTEM_BUFF_SPELL_IDS = {
    -- Earth (Stoneclaw excluded: buff only when totem absorbs damage; use TOTEM_POSITION_RANGE only)
    ["Strength of Earth Totem"] = 8075,
    ["Stoneskin Totem"] = 8071,
    -- Fire
    ["Flametongue Totem"] = 8230,  -- Flametongue Totem Effect
    ["Totem of Wrath"] = 30708,    -- TBC: party spell crit aura
    -- Water: Mana Spring (multiple ranks = different buff IDs), Healing Stream, resistance totems
    ["Mana Spring Totem"] = { 5675, 10497, 24854 },  -- ranks 1–3+ (Classic/TBC)
    ["Healing Stream Totem"] = 10463,
    ["Frost Resistance Totem"] = 8181,
    ["Fire Resistance Totem"] = 8184,
    -- Air (Windfury Totem = weapon proc, no persistent buff; Grace of Air, Grounding, Wrath of Air = persistent)
    ["Grace of Air Totem"] = 10627,
    ["Grounding Totem"] = 8178,  -- Grounding Totem Effect
    ["Nature Resistance Totem"] = 10595,
    ["Wrath of Air Totem"] = 2895,  -- spell haste aura
}

-- Buff name(s) as shown on player (spell ID can differ by client; name is reliable for range check).
-- Same keys as TOTEM_BUFF_SPELL_IDS; value is string or table of strings to match aura name.
local TOTEM_BUFF_NAMES = {
    ["Strength of Earth Totem"] = "Strength of Earth",
    ["Stoneskin Totem"] = "Stoneskin",
    ["Flametongue Totem"] = "Flametongue Totem",
    ["Totem of Wrath"] = "Totem of Wrath",
    ["Mana Spring Totem"] = "Mana Spring",
    ["Healing Stream Totem"] = "Healing Stream",
    ["Frost Resistance Totem"] = "Frost Resistance",
    ["Fire Resistance Totem"] = "Fire Resistance",
    ["Grace of Air Totem"] = "Grace of Air",
    ["Grounding Totem"] = "Grounding Totem Effect",
    ["Nature Resistance Totem"] = "Nature Resistance",
    ["Wrath of Air Totem"] = "Wrath of Air",
}

-- True if this totem has no player buff (we can't detect range; never show out-of-range overlay).
local function IsTotemWithNoRangeBuff(totemName)
    if not totemName or totemName == "" then return false end
    if TOTEM_NO_RANGE_BUFF[totemName] then return true end
    for key in pairs(TOTEM_NO_RANGE_BUFF) do
        if totemName:find(key, 1, true) == 1 then return true end
    end
    return false
end

-- Max range in yards for position-based totems (no player buff). Match by exact name or prefix. Returns number or nil.
local function GetTotemPositionRange(totemName)
    if not totemName or totemName == "" then return nil end
    local range = TOTEM_POSITION_RANGE[totemName]
    if range then return range end
    for key, yards in pairs(TOTEM_POSITION_RANGE) do
        if totemName:find(key, 1, true) == 1 then return yards end
    end
    return nil
end

-- Distance in yards between two positions. WoW UnitPosition returns posY, posX, posZ (coords in yards).
local function GetDistanceYards(ax, ay, az, bx, by, bz)
    if not (ax and ay and az and bx and by and bz) then return nil end
    local dx, dy, dz = bx - ax, by - ay, bz - az
    return (dx * dx + dy * dy + dz * dz) ^ 0.5
end

-- Get buff spell ID(s) for a totem name; match exact or by prefix. Returns number or table of numbers.
local function GetTotemBuffSpellId(totemName)
    if not totemName or totemName == "" then return nil end
    local id = TOTEM_BUFF_SPELL_IDS[totemName]
    if id then return id end
    for key, spellId in pairs(TOTEM_BUFF_SPELL_IDS) do
        if totemName:find(key, 1, true) == 1 then return spellId end
    end
    return nil
end

-- Get buff name(s) for a totem name (for name-based range fallback). Returns string or table of strings, or nil.
local function GetTotemBuffName(totemName)
    if not totemName or totemName == "" then return nil end
    local name = TOTEM_BUFF_NAMES[totemName]
    if name then return name end
    for key, buffName in pairs(TOTEM_BUFF_NAMES) do
        if totemName:find(key, 1, true) == 1 then return buffName end
    end
    return nil
end

-- True if player has a helpful aura whose name matches the totem's buff (fallback when spell ID fails).
local function HasPlayerBuffByTotemName(totemName)
    local expected = GetTotemBuffName(totemName)
    if not expected then return false end
    local names = type(expected) == "table" and expected or { expected }
    for i = 1, 40 do
        local auraName = UnitAura("player", i, "HELPFUL")
        if not auraName then break end
        for _, n in ipairs(names) do
            if auraName == n or auraName:find(n, 1, true) == 1 then return true end
        end
    end
    return false
end

-- Returns true if the player has a helpful aura with the given spell ID (used for totem range).
-- Per warcraft.wiki.gg: 10 returns → spellId at position 10; 11 returns → spellId at position 11. Detect by type(4th)=="string".
local function HasPlayerBuffBySpellId(spellId)
    if not spellId then return false end
    for i = 1, 40 do
        local v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11 = UnitAura("player", i, "HELPFUL")
        if not v1 then break end
        local auraSpellId = (type(v4) == "string") and v10 or v11
        if auraSpellId == spellId then return true end
    end
    return false
end

-- True if player has any of the given buff spell ID(s). idOrIds is a number or table of numbers.
local function HasPlayerBuffByAnySpellId(idOrIds)
    if not idOrIds then return false end
    if type(idOrIds) == "number" then return HasPlayerBuffBySpellId(idOrIds) end
    for _, id in ipairs(idOrIds) do
        if HasPlayerBuffBySpellId(id) then return true end
    end
    return false
end

-- Defaults
local DEFAULTS = {
    point = "CENTER",
    relativeTo = "UIParent",
    relativePoint = "CENTER",
    x = 0,
    y = -180,
    scale = 1.0,
    locked = false,
    -- Windfury stats frame (separate, below main bar by default)
    wfPoint = "TOP",
    wfRelativeTo = "ShammyTimeFrame",
    wfRelativePoint = "BOTTOM",
    wfX = 0,
    wfY = -4,
    wfScale = 1.0,
    wfLocked = false,
    windfuryTrackerEnabled = true,
    -- Windfury total popup (damage text when Windfury procs) — defaults:
    --   wfPopupEnabled=true, wfPopupScale=1.3 (0.5–2), wfPopupHold=2s (0.5–4),
    --   position CENTER/UIParent/0,80; lock/unlock with /st wf popup lock|unlock
    wfPopupEnabled = true,
    wfPopupPoint = "CENTER",
    wfPopupRelativeTo = "UIParent",
    wfPopupRelativePoint = "CENTER",
    wfPopupX = 0,
    wfPopupY = 80,
    wfPopupScale = 1.3,   -- text size, like ingame crits (0.5–2)
    wfPopupHold = 2.0,    -- seconds visible before fading (0.5–4)
    wfPopupLocked = false,
}

-- State: previous totem presence per slot (to detect "just gone")
local lastHadTotem = { [1] = false, [2] = false, [3] = false, [4] = false }
-- Approximate totem position (player position when placed); slot -> { x, y, z }. Used only for totems in TOTEM_POSITION_RANGE (UnitPosition works outdoors only).
local totemPosition = {}
-- Last totem name per slot so we clear stored position when the totem in that slot changes (e.g. Stoneclaw -> Earthbind).
local lastTotemName = {}
-- Last startTime per slot so we detect same-totem replace (e.g. Earthbind -> new Earthbind) and re-store position.
local lastTotemStartTime = {}

local mainFrame
local slotFrames = {}
local lightningShieldFrame
local weaponImbueFrame
local focusedFrame
local timerTicker
local windfuryStatsFrame

-- Windfury proc stats: pull (this combat) and session (since login / last reset).
-- count = Windfury Attack hits; swings = eligible white swings (SWING_DAMAGE from player; WF hits don't proc WF).
local wfPull  = { total = 0, count = 0, min = nil, max = nil, crits = 0, swings = 0 }
local wfSession = { total = 0, count = 0, min = nil, max = nil, crits = 0, swings = 0 }
-- Windfury popup: buffer damage for one proc (2 hits), then show total in floating text
local wfPopupTotal = 0
local wfPopupTimer = nil
local wfPopupFrame = nil

local function GetDB()
    ShammyTimeDB = ShammyTimeDB or {}
    for k, v in pairs(DEFAULTS) do
        if ShammyTimeDB[k] == nil then ShammyTimeDB[k] = v end
    end
    return ShammyTimeDB
end

local function ApplyScale()
    local db = GetDB()
    if mainFrame then
        mainFrame:SetScale(db.scale or 1)
    end
    if windfuryStatsFrame then
        windfuryStatsFrame:SetScale(db.wfScale or 1)
    end
end

-- Format number for compact display (1234 -> "1.2k", 1234567 -> "1.2m").
local function FormatNumberShort(n)
    if not n or n < 0 then return "0" end
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

-- Windfury total popup: large crit-style text, movable, small→large scale animation
local function CreateWindfuryPopupFrame()
    if wfPopupFrame then return wfPopupFrame end
    local db = GetDB()
    local f = CreateFrame("Frame", "ShammyTimeWindfuryPopup", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(100)
    f:SetSize(280, 70)
    f:SetPoint(db.wfPopupPoint or "CENTER", db.wfPopupRelativeTo or "UIParent", db.wfPopupRelativePoint or "CENTER", db.wfPopupX or 0, db.wfPopupY or 80)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not GetDB().wfPopupLocked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = GetDB()
        db.wfPopupPoint, _, db.wfPopupRelativePoint, db.wfPopupX, db.wfPopupY = self:GetPoint(1)
        local relTo = select(2, self:GetPoint(1))
        db.wfPopupRelativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent"
    end)
    -- Large font like ingame crits
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    fs:SetAllPoints(f)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(2, -2)
    f.text = fs
    wfPopupFrame = f
    return f
end

local function ShowWindfuryPopup(total)
    if not total or total <= 0 then return end
    local db = GetDB()
    if not db.wfPopupEnabled then return end
    local f = CreateWindfuryPopupFrame()
    if f.animTicker then
        f.animTicker:Cancel()
        f.animTicker = nil
    end
    f.text:SetText(("Windfury: %s"):format(FormatNumberShort(total)))
    f.text:SetTextColor(1, 0.85, 0.2)  -- gold/yellow
    local popupScale = db.wfPopupScale or 1.3
    f:ClearAllPoints()
    f:SetPoint(db.wfPopupPoint or "CENTER", db.wfPopupRelativeTo or "UIParent", db.wfPopupRelativePoint or "CENTER", db.wfPopupX or 0, db.wfPopupY or 80)
    f:SetAlpha(1)
    -- Number appears at 100% right away; then visible bounce to 140% and back to 100% over ~300 ms
    local TICK = 1 / 120   -- 120 Hz
    local startScale = 1.0 * popupScale   -- 100% — visible immediately, no grow-in
    local peakScale = 1.4 * popupScale     -- 140% overshoot (visible pop)
    local endScale = 1.0 * popupScale      -- 100% settle
    local bounceSec = 0.3   -- total bounce duration (~300 ms)
    local popSteps = math.floor((bounceSec / 2) / TICK + 0.5)   -- first half: 100% -> 140%
    local settleSteps = math.floor((bounceSec / 2) / TICK + 0.5) -- second half: 140% -> 100%
    local scalePhaseSteps = popSteps + settleSteps
    local holdSec = math.max(0.5, math.min(4, db.wfPopupHold or 2))
    local holdSteps = math.floor(holdSec / TICK + 0.5)
    local floatSteps = 50   -- short dissipation (~0.42s float+fade)
    local floatPxPerStep = 1
    -- Show at 100% immediately so the number is there before any animation
    f:SetScale(startScale)
    f:Show()
    local step = 0
    f.animTicker = C_Timer.NewTicker(TICK, function()
        step = step + 1
        if step <= popSteps then
            -- 100% -> 140% over first half of bounce
            local t = step / popSteps
            local s = startScale + (peakScale - startScale) * t
            f:SetScale(s)
        elseif step <= scalePhaseSteps then
            -- 140% -> 100% over second half of bounce (~150 ms)
            local t = (step - popSteps) / settleSteps
            local s = peakScale + (endScale - peakScale) * t
            f:SetScale(s)
        elseif step <= scalePhaseSteps + holdSteps then
            f:SetScale(endScale)
        else
            f:SetScale(endScale)
            local pt, relTo, relPt, x, y = f:GetPoint(1)
            f:SetPoint(pt, relTo, relPt, x or 0, (y or 0) + floatPxPerStep)
            local floatStep = step - scalePhaseSteps - holdSteps
            f:SetAlpha(1 - floatStep / floatSteps)
            if step >= scalePhaseSteps + holdSteps + floatSteps then
                if f.animTicker then f.animTicker:Cancel() f.animTicker = nil end
                f:Hide()
            end
        end
    end)
end

-- Persist Windfury stats to SavedVariables (survives relog / reload). Defined before RecordWindfuryHit/Reset* so they can call it.
local function SaveWindfuryDB()
    local db = GetDB()
    db.wfSession = {
        total = wfSession.total,
        count = wfSession.count,
        min = wfSession.min,
        max = wfSession.max,
        crits = wfSession.crits or 0,
        swings = wfSession.swings or 0,
    }
    db.wfLastPull = {
        total = wfPull.total,
        count = wfPull.count,
        min = wfPull.min,
        max = wfPull.max,
        crits = wfPull.crits or 0,
        swings = wfPull.swings or 0,
    }
end

-- Restore Windfury stats from SavedVariables (on load / relog).
local function RestoreWindfuryDB()
    local db = GetDB()
    if db.wfSession then
        wfSession.total = db.wfSession.total or 0
        wfSession.count = db.wfSession.count or 0
        wfSession.min = db.wfSession.min
        wfSession.max = db.wfSession.max
        wfSession.crits = db.wfSession.crits or 0
        wfSession.swings = db.wfSession.swings or 0
    end
    if db.wfLastPull then
        wfPull.total = db.wfLastPull.total or 0
        wfPull.count = db.wfLastPull.count or 0
        wfPull.min = db.wfLastPull.min
        wfPull.max = db.wfLastPull.max
        wfPull.crits = db.wfLastPull.crits or 0
        wfPull.swings = db.wfLastPull.swings or 0
    end
end

-- Schedule Windfury stats UI refresh on next frame so it updates in combat (avoids deferred/blocked updates during CLEU).
local function ScheduleWindfuryUpdate()
    if not windfuryStatsFrame or not windfuryStatsFrame.UpdateText then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if windfuryStatsFrame and windfuryStatsFrame.UpdateText then
                windfuryStatsFrame:UpdateText()
            end
        end)
    else
        windfuryStatsFrame:UpdateText()
    end
end

-- Record one eligible white swing (SWING_DAMAGE from player). Windfury procs only on white swings, not on WF hits.
local function RecordEligibleSwing()
    for _, st in ipairs({ wfPull, wfSession }) do
        st.swings = (st.swings or 0) + 1
    end
    ScheduleWindfuryUpdate()
    SaveWindfuryDB()
end

-- Record one Windfury hit (amount, isCrit) into pull and session stats.
-- Buffers damage for floating popup: after 0.4s with no new hit, show total (one proc = up to 2 hits).
local function RecordWindfuryHit(amount, isCrit)
    if not amount or amount <= 0 then return end
    for _, st in ipairs({ wfPull, wfSession }) do
        st.total = st.total + amount
        st.count = st.count + 1
        if st.min == nil or amount < st.min then st.min = amount end
        if st.max == nil or amount > st.max then st.max = amount end
        if isCrit then st.crits = (st.crits or 0) + 1 end
    end
    ScheduleWindfuryUpdate()
    SaveWindfuryDB()
    -- Floating popup: add to buffer and (re)start delay timer
    if GetDB().wfPopupEnabled then
        wfPopupTotal = wfPopupTotal + amount
        if wfPopupTimer then wfPopupTimer:Cancel() end
        wfPopupTimer = C_Timer.NewTimer(0.4, function()
            wfPopupTimer = nil
            if wfPopupTotal > 0 then
                ShowWindfuryPopup(wfPopupTotal)
                wfPopupTotal = 0
            end
        end)
    end
end

-- Reset pull stats (call when entering combat).
local function ResetWindfuryPull()
    wfPull.total, wfPull.count, wfPull.min, wfPull.max, wfPull.crits, wfPull.swings = 0, 0, nil, nil, 0, 0
    ScheduleWindfuryUpdate()
    SaveWindfuryDB()
end

-- Reset session stats (and pull).
local function ResetWindfurySession()
    wfPull.total, wfPull.count, wfPull.min, wfPull.max, wfPull.crits, wfPull.swings = 0, 0, nil, nil, 0, 0
    wfSession.total, wfSession.count, wfSession.min, wfSession.max, wfSession.crits, wfSession.swings = 0, 0, nil, nil, 0, 0
    ScheduleWindfuryUpdate()
    SaveWindfuryDB()
end

-- Returns Lightning Shield or Water Shield aura on player: icon, count (charges), duration, expirationTime, spellId; or nil if neither active.
-- Per warcraft.wiki.gg: 10 returns = name,icon(2),count(3),dispelType(4),duration(5),expirationTime(6),...; 11 = name,rank,icon(3),count(4),...,spellId(11).
local function GetElementalShieldAura()
    for i = 1, 40 do
        local v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11 = UnitAura("player", i, "HELPFUL")
        if not v1 then break end
        local name = v1
        local is10 = (type(v4) == "string")
        local icon = is10 and v2 or v3
        local count = is10 and v3 or v4
        local duration = is10 and v5 or v6
        local expTime = is10 and v6 or v7
        local spellId = is10 and v10 or v11
        if spellId then
            for _, sid in ipairs(LIGHTNING_SHIELD_SPELL_IDS) do
                if spellId == sid then
                    return icon, (type(count) == "number" and count or 0), duration, (type(expTime) == "number" and expTime or 0), spellId, LIGHTNING_SHIELD_ICON
                end
            end
            for _, sid in ipairs(WATER_SHIELD_SPELL_IDS) do
                if spellId == sid then
                    return icon, (type(count) == "number" and count or 0), duration, (type(expTime) == "number" and expTime or 0), spellId, WATER_SHIELD_ICON
                end
            end
        end
        if name == "Lightning Shield" then
            return icon, (type(count) == "number" and count or 0), duration, (type(expTime) == "number" and expTime or 0), spellId, LIGHTNING_SHIELD_ICON
        end
        if name == "Water Shield" then
            return icon, (type(count) == "number" and count or 0), duration, (type(expTime) == "number" and expTime or 0), spellId, WATER_SHIELD_ICON
        end
    end
    return nil
end

-- Get weapon imbue from GetWeaponEnchantInfo (primary on Classic/TBC – direct API for temp weapon enchants).
-- Returns: icon, expirationTime, name, spellId. Uses enchant ID (4th/8th return) to pick correct icon/name per imbue.
local function GetWeaponImbueFromEnchantInfo()
    if not GetWeaponEnchantInfo then return nil end
    -- Returns: hasMH, expMH, chargesMH, enchantIdMH, hasOH, expOH, chargesOH, enchantIdOH (exp in ms on some clients)
    local hasMH, expMH, _, enchantIdMH, hasOH, expOH, _, enchantIdOH = GetWeaponEnchantInfo()
    local hasEnchant = (hasMH and expMH and expMH > 0) or (hasOH and expOH and expOH > 0)
    if not hasEnchant then return nil end
    local enchantId = (hasMH and expMH and expMH > 0) and enchantIdMH or enchantIdOH
    local spellId = (enchantId and WEAPON_IMBUE_ENCHANT_TO_SPELL[enchantId]) or nil
    local name = (spellId and GetSpellInfo and GetSpellInfo(spellId)) or "Weapon Imbue"
    local icon = (enchantId and WEAPON_IMBUE_ENCHANT_ICONS[enchantId]) or WEAPON_IMBUE_ICON_ID
    -- Expiration: API returns time remaining in milliseconds (wowwiki: thousandths of seconds).
    local remaining = (hasMH and expMH and expMH > 0) and expMH or expOH
    local remainingSec = (type(remaining) == "number" and remaining / 1000) or 0
    local expirationTime = GetTime() + remainingSec
    return icon, expirationTime, name, spellId
end

-- Returns first weapon imbue on player: icon, expirationTime, name, spellId; or nil if none.
-- Uses UnitAura first (for name/icon/spellId), then GetWeaponEnchantInfo so imbue always shows on TBC Anniversary.
-- Per https://warcraft.wiki.gg/wiki/API_UnitAura: 10 returns = name,icon,count,dispelType,duration,expirationTime,source,...,spellId(10th).
local function GetWeaponImbueAura()
    for i = 1, 40 do
        local v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11 = UnitAura("player", i, "HELPFUL")
        if not v1 then break end
        local name = v1
        local is10 = (type(v4) == "string")
        local icon = is10 and v2 or v3
        local expTime = is10 and v6 or v7
        local spellId = is10 and v10 or v11
        if spellId and WEAPON_IMBUE_SPELL_IDS[spellId] then
            return icon, expTime, name, spellId
        end
        local lowerName = name and name:lower() or ""
        if lowerName:find("flametongue") or lowerName:find("frostbrand") or lowerName:find("rockbiter") or lowerName:find("windfury") then
            return icon, expTime, name, spellId
        end
    end
    -- UnitAura can miss imbue on some clients (e.g. TBC Anniversary); use GetWeaponEnchantInfo (see LibWeaponEnchantInfo).
    return GetWeaponImbueFromEnchantInfo()
end

-- Returns Focused buff aura (Shamanistic Focus proc): icon, duration, expirationTime, spellId; or nil if not present.
-- TBC: spell 43339 "Focused" — next Shock costs 60% less, lasts 15 sec.
local function GetFocusedAura()
    for i = 1, 40 do
        local v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11 = UnitAura("player", i, "HELPFUL")
        if not v1 then break end
        local is10 = (type(v4) == "string")
        local icon = is10 and v2 or v3
        local duration = is10 and v5 or v6
        local expTime = is10 and v6 or v7
        local spellId = is10 and v10 or v11
        if spellId == FOCUSED_BUFF_SPELL_ID then
            return icon, duration, expTime, spellId
        end
        if v1 == "Focused" then
            return icon, duration, expTime, spellId
        end
    end
    return nil
end

-- When >= 60 sec: show minutes rounded up with " min" (e.g. 1:40 → "2 min", 1:00 → "1 min"). When < 60 sec: show seconds with " sec".
local function FormatTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 60 then
        return ("%d min"):format(math.ceil(seconds / 60))
    end
    return ("%.0f sec"):format(seconds)
end

-- Use the same "cooldown finish" spiral as action buttons (native WoW UI)
local function PlayGoneAnimation(slotFrame, element)
    if not slotFrame or not slotFrame.expiryCooldown then return end
    local cd = slotFrame.expiryCooldown
    cd:Show()
    -- Brief cooldown that completes in ~0.5s: spiral sweeps and disappears like ability coming off CD
    cd:SetCooldown(GetTime() - 0.5, 0.5)
    C_Timer.After(0.6, function()
        if cd and cd.SetCooldown then
            cd:SetCooldown(0, 0)
            cd:Hide()
        end
    end)
end

local function UpdateSlot(slot)
    local haveTotem, totemName, startTime, duration, icon = GetTotemInfo(slot)
    local element = SLOT_TO_ELEMENT[slot]
    local sf = slotFrames[slot]
    if not sf then return end

    local nowHasTotem = (totemName and totemName ~= "")
    local wasJustPlaced = not lastHadTotem[slot] and nowHasTotem

    -- Detect "just gone" and trigger obvious animation
    if lastHadTotem[slot] and not nowHasTotem then
        PlayGoneAnimation(sf, element)
        totemPosition[slot] = nil
        lastTotemStartTime[slot] = nil
    end
    lastHadTotem[slot] = nowHasTotem

    local color = ELEMENT_COLORS[element]
    if nowHasTotem then
        -- When the totem in this slot changed (e.g. Strength -> Stoneclaw, or Stoneclaw -> Earthbind), clear stored position so we capture the new totem's location.
        if lastTotemName[slot] ~= totemName then
            totemPosition[slot] = nil
            lastTotemName[slot] = totemName
        end
        -- Same totem type replaced (e.g. Earthbind -> new Earthbind): startTime changes, so we must re-store position.
        local isNewInstance = (startTime and startTime ~= lastTotemStartTime[slot])
        if isNewInstance then
            totemPosition[slot] = nil
            lastTotemStartTime[slot] = startTime
        end
        -- Store approximate totem position (player position when placed) for position-based range totems. Store when just placed, new instance (same totem re-placed), or we don't have a position yet. UnitPosition works outdoors only.
        if GetTotemPositionRange(totemName) and UnitPosition and (wasJustPlaced or isNewInstance or not totemPosition[slot]) then
            local posY, posX, posZ = UnitPosition("player")
            if posX and posY and posZ then
                totemPosition[slot] = { x = posX, y = posY, z = posZ }
            end
        end
        if not isNewInstance and startTime then
            lastTotemStartTime[slot] = startTime
        end

        sf.icon:SetTexture(icon and icon ~= "" and icon or "Interface\\Icons\\INV_Elemental_Primal_Earth")
        sf.icon:SetVertexColor(1, 1, 1)
        sf.icon:Show()
        sf.goneOverlay:Hide()
        local timeLeft = GetTotemTimeLeft(slot)
        sf.timer:SetText(FormatTime(timeLeft))
        sf.timer:SetTextColor(1, 1, 1)
        sf.timer:Show()
        sf:SetBackdropBorderColor(color.r, color.g, color.b, 1)
        -- Out of range: (1) buff-based: totem has a buff but we don't have it; (2) position-based: totem has no buff but we track by distance (e.g. Stoneclaw, Earthbind).
        local buffSpellId = GetTotemBuffSpellId(totemName)
        local hasBuff = (buffSpellId and HasPlayerBuffByAnySpellId(buffSpellId)) or HasPlayerBuffByTotemName(totemName)
        local outOfRangeBuff = not IsTotemWithNoRangeBuff(totemName) and buffSpellId and not hasBuff
        local outOfRangePos = false
        if GetTotemPositionRange(totemName) and totemPosition[slot] and UnitPosition then
            local posY, posX, posZ = UnitPosition("player")
            if posX and totemPosition[slot].x then
                local dist = GetDistanceYards(totemPosition[slot].x, totemPosition[slot].y, totemPosition[slot].z, posX, posY, posZ)
                local maxRange = GetTotemPositionRange(totemName)
                if dist and maxRange and dist > maxRange then
                    outOfRangePos = true
                end
            end
        end
        if outOfRangeBuff or outOfRangePos then
            sf.rangeOverlay:Show()
        else
            sf.rangeOverlay:Hide()
        end
    else
        totemPosition[slot] = nil
        lastTotemName[slot] = nil
        lastTotemStartTime[slot] = nil
        -- Empty slot: show darkened element icon so you see which one is missing
        sf.icon:SetTexture(ELEMENT_EMPTY_ICONS[element] or "Interface\\Icons\\INV_Misc_QuestionMark")
        sf.icon:SetVertexColor(0.35, 0.35, 0.35)
        sf.timer:SetText("")
        sf.timer:Hide()
        sf.rangeOverlay:Hide()
        sf:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    end
end

local function UpdateAllSlots()
    for slot = 1, 4 do
        UpdateSlot(slot)
    end
end

local function UpdateLightningShield()
    if not lightningShieldFrame then return end
    local icon, count, duration, expirationTime, spellId, defaultIcon = GetElementalShieldAura()
    if icon or spellId then
        -- Prefer path from GetSpellTexture; some clients don't display SetTexture(path). Fall back to string path, then numeric icon.
        local tex = (spellId and GetSpellTexture and GetSpellTexture(spellId)) or (icon and type(icon) == "string" and icon) or (icon and type(icon) == "number" and icon) or (defaultIcon or LIGHTNING_SHIELD_ICON)
        -- TBC Anniversary: use numeric icon when default is Water Shield and path may not display
        if defaultIcon == WATER_SHIELD_ICON and (not tex or tex == WATER_SHIELD_ICON) then
            tex = WATER_SHIELD_ICON_ID
        end
        if tex then lightningShieldFrame.icon:SetTexture(tex) end
        lightningShieldFrame.icon:SetVertexColor(1, 1, 1)
        local numCount = (type(count) == "number" and count) or 0
        local expTime = (type(expirationTime) == "number" and expirationTime) or 0
        local timeLeft = expTime > 0 and (expTime - GetTime()) or 0
        -- Charges in the middle of the icon (Lightning Shield orbs, Water Shield globes)
        if lightningShieldFrame.charges then
            lightningShieldFrame.charges:SetText(numCount > 0 and tostring(numCount) or "")
            lightningShieldFrame.charges:Show()
        end
        -- Timer on the bottom
        lightningShieldFrame.timer:SetText(FormatTime(timeLeft))
        lightningShieldFrame.timer:Show()
        lightningShieldFrame:SetBackdropBorderColor(0.55, 0.48, 0.35, 1)
    else
        lightningShieldFrame.icon:SetTexture(LIGHTNING_SHIELD_ICON)
        lightningShieldFrame.icon:SetVertexColor(0.35, 0.35, 0.35)
        if lightningShieldFrame.charges then
            lightningShieldFrame.charges:SetText("")
            lightningShieldFrame.charges:Hide()
        end
        lightningShieldFrame.timer:SetText("")
        lightningShieldFrame.timer:Hide()
        lightningShieldFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)
    end
end

local function UpdateWeaponImbue()
    if not weaponImbueFrame then return end
    local icon, expirationTime, name, spellId = GetWeaponImbueAura()
    if name then
        -- Prefer path from GetSpellTexture; some clients don't display SetTexture(path) and need FileDataID (number).
        local tex = (spellId and GetSpellTexture and GetSpellTexture(spellId)) or (icon and type(icon) == "string" and icon) or (icon and type(icon) == "number" and icon) or WEAPON_IMBUE_ICON
        local texToSet = tex or WEAPON_IMBUE_ICON
        -- When we have no spellId (GetWeaponEnchantInfo path), use numeric icon ID so TBC Anniversary displays it.
        if not spellId and (texToSet == WEAPON_IMBUE_ICON or not texToSet) then
            texToSet = WEAPON_IMBUE_ICON_ID
        end
        weaponImbueFrame.icon:SetTexture(texToSet)
        weaponImbueFrame.icon:Show()
        weaponImbueFrame.icon:SetVertexColor(1, 1, 1)
        local expTime = (type(expirationTime) == "number" and expirationTime) or 0
        local timeLeft = expTime > 0 and (expTime - GetTime()) or 0
        weaponImbueFrame.timer:SetText(FormatTime(timeLeft))
        weaponImbueFrame.timer:Show()
        weaponImbueFrame.imbueName = name
        weaponImbueFrame:SetBackdropBorderColor(0.55, 0.48, 0.35, 1)
    else
        weaponImbueFrame.icon:SetTexture(WEAPON_IMBUE_EMPTY_ICON_ID)
        weaponImbueFrame.icon:Show()
        weaponImbueFrame.icon:SetVertexColor(0.35, 0.35, 0.35)
        weaponImbueFrame.timer:SetText("")
        weaponImbueFrame.timer:Hide()
        weaponImbueFrame.imbueName = nil
        weaponImbueFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)
    end
end

local function UpdateFocused()
    if not focusedFrame then return end
    local icon, duration, expirationTime, spellId = GetFocusedAura()
    if icon or spellId then
        local tex = (spellId and GetSpellTexture and GetSpellTexture(spellId)) or (icon and type(icon) == "string" and icon) or (icon and type(icon) == "number" and icon) or FOCUSED_ICON
        focusedFrame.icon:SetTexture(tex or FOCUSED_ICON)
        focusedFrame.icon:SetVertexColor(1, 1, 1)
        local expTime = (type(expirationTime) == "number" and expirationTime) or 0
        local timeLeft = expTime > 0 and (expTime - GetTime()) or 0
        focusedFrame.timer:SetText(FormatTime(timeLeft))
        focusedFrame.timer:Show()
        focusedFrame:SetBackdropBorderColor(0.55, 0.48, 0.35, 1)
    else
        focusedFrame.icon:SetTexture(FOCUSED_ICON)
        focusedFrame.icon:SetVertexColor(0.35, 0.35, 0.35)
        focusedFrame.timer:SetText("")
        focusedFrame.timer:Hide()
        focusedFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)
    end
end

local function RefreshTimers()
    if not mainFrame or not mainFrame:IsShown() then return end
    for slot = 1, 4 do
        local haveTotem, totemName = GetTotemInfo(slot)
        if totemName and totemName ~= "" then
            local sf = slotFrames[slot]
            if sf and sf.timer then
                sf.timer:SetText(FormatTime(GetTotemTimeLeft(slot)))
                -- Refresh range overlay: buff-based and position-based (in case UNIT_AURA didn't fire or player moved)
                local buffSpellId = GetTotemBuffSpellId(totemName)
                local hasBuff = (buffSpellId and HasPlayerBuffByAnySpellId(buffSpellId)) or HasPlayerBuffByTotemName(totemName)
                local outOfRangeBuff = not IsTotemWithNoRangeBuff(totemName) and buffSpellId and not hasBuff
                local outOfRangePos = false
                if GetTotemPositionRange(totemName) and totemPosition[slot] and UnitPosition then
                    local posY, posX, posZ = UnitPosition("player")
                    if posX and totemPosition[slot].x then
                        local dist = GetDistanceYards(totemPosition[slot].x, totemPosition[slot].y, totemPosition[slot].z, posX, posY, posZ)
                        local maxRange = GetTotemPositionRange(totemName)
                        if dist and maxRange and dist > maxRange then
                            outOfRangePos = true
                        end
                    end
                end
                if outOfRangeBuff or outOfRangePos then
                    sf.rangeOverlay:Show()
                else
                    sf.rangeOverlay:Hide()
                end
            end
        end
    end
    UpdateLightningShield()
    UpdateWeaponImbue()
    UpdateFocused()
end

local function CreateMainFrame()
    local db = GetDB()
    local f = CreateFrame("Frame", "ShammyTimeFrame", UIParent, "BackdropTemplate")
    local iconSize = 36
    local gap = 2
    local slotW, slotH = iconSize + 6, iconSize + 18
    local fw = 7 * slotW + 6 * gap  -- 4 totems + Lightning Shield + Weapon Imbue + Focused
    local fh = slotH
    f:SetSize(fw, fh)
    f:SetScale(db.scale or 1)
    f:SetPoint(db.point or "CENTER", db.relativeTo or "UIParent", db.relativePoint or "CENTER", db.x or 0, db.y or -180)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not (db.locked) then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        db.point, _, db.relativePoint, db.x, db.y = self:GetPoint(1)
    end)
    -- No bar-wide background: texture is on each button

    -- Slot row: chained left-to-right as stone, fire, water, air (then shield, imbue)
    for i = 1, 4 do
        local slot = DISPLAY_ORDER[i]
        local element = SLOT_TO_ELEMENT[slot]
        local sf = CreateFrame("Frame", nil, f, "BackdropTemplate")
        sf:SetSize(slotW, slotH)
        if i == 1 then
            sf:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        else
            sf:SetPoint("LEFT", slotFrames[DISPLAY_ORDER[i - 1]], "RIGHT", gap, 0)
            sf:SetPoint("TOP", slotFrames[DISPLAY_ORDER[1]], "TOP", 0, 0)
        end
        -- Slot: dark background; bar texture only in the timer (numbers) area at bottom
        sf:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        sf:SetBackdropColor(0.12, 0.1, 0.08, 0.94)
        local c = ELEMENT_COLORS[element]
        sf:SetBackdropBorderColor(0.55, 0.48, 0.35, 1)

        -- Bar texture strip behind where the numbers show (bottom of slot)
        local timerBar = CreateFrame("Frame", nil, sf)
        timerBar:SetPoint("BOTTOMLEFT", 2, 2)
        timerBar:SetPoint("BOTTOMRIGHT", -2, 2)
        timerBar:SetHeight(14)
        timerBar:SetFrameLevel(sf:GetFrameLevel())
        local timerBarTex = timerBar:CreateTexture(nil, "BACKGROUND")
        timerBarTex:SetAllPoints(timerBar)
        timerBarTex:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
        timerBarTex:SetTexCoord(0, 1, 0, 0.5)
        timerBarTex:SetVertexColor(0.35, 0.3, 0.25, 0.95)

        local icon = sf:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("TOP", 0, -4)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(ELEMENT_EMPTY_ICONS[element])
        icon:SetVertexColor(0.35, 0.35, 0.35)
        sf.icon = icon

        -- Cooldown spiral (same as action buttons): used for "expired" effect
        local expiryCd = CreateFrame("Cooldown", nil, sf, "CooldownFrameTemplate")
        expiryCd:SetPoint("TOP", sf, "TOP", 0, -4)
        expiryCd:SetSize(iconSize, iconSize)
        expiryCd:SetFrameLevel(sf:GetFrameLevel() + 1)
        if expiryCd.SetDrawEdge then expiryCd:SetDrawEdge(false) end
        if expiryCd.SetHideCountdownNumbers then
            expiryCd:SetHideCountdownNumbers(true)
        else
            local regions = { expiryCd:GetRegions() }
            for _, r in ipairs(regions) do
                if r and r.SetText then r:SetText("") end
                if r and r.Hide then r:Hide() end
            end
        end
        expiryCd:Hide()
        sf.expiryCooldown = expiryCd

        local timer = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timer:SetPoint("BOTTOM", 0, 4)
        timer:SetTextColor(1, 1, 1)
        sf.timer = timer

        -- "GONE" overlay (flashes when totem dies/expires)
        local overlay = CreateFrame("Frame", nil, sf)
        overlay:SetAllPoints(sf)
        overlay:SetFrameLevel(sf:GetFrameLevel() + 2)
        local ot = overlay:CreateTexture(nil, "BACKGROUND")
        ot:SetAllPoints()
        ot:SetColorTexture(0.5, 0, 0, 0.6)
        overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        overlay.text:SetPoint("CENTER")
        overlay.text:SetText("GONE")
        overlay.text:SetTextColor(1, 0.3, 0.3)
        overlay:Hide()
        sf.goneOverlay = overlay

        -- "Out of range" overlay: totem is down but player is too far to get the buff
        local rangeOverlay = CreateFrame("Frame", nil, sf)
        rangeOverlay:SetAllPoints(sf)
        rangeOverlay:SetFrameLevel(sf:GetFrameLevel() + 1)
        local rt = rangeOverlay:CreateTexture(nil, "BACKGROUND")
        rt:SetAllPoints()
        rt:SetColorTexture(0.6, 0, 0, 0.5)
        rangeOverlay:Hide()
        sf.rangeOverlay = rangeOverlay

        slotFrames[slot] = sf
    end

    -- Lightning Shield slot (same style as totem slots)
    local lsf = CreateFrame("Frame", nil, f, "BackdropTemplate")
    lsf:SetSize(slotW, slotH)
    lsf:SetPoint("LEFT", slotFrames[4], "RIGHT", gap, 0)
    lsf:SetPoint("TOP", slotFrames[DISPLAY_ORDER[1]], "TOP", 0, 0)
    lsf:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    lsf:SetBackdropColor(0.12, 0.1, 0.08, 0.94)
    lsf:SetBackdropBorderColor(0.55, 0.48, 0.35, 1)
    -- Bar texture strip behind where the numbers show (bottom of slot)
    local lsfTimerBar = CreateFrame("Frame", nil, lsf)
    lsfTimerBar:SetPoint("BOTTOMLEFT", 2, 2)
    lsfTimerBar:SetPoint("BOTTOMRIGHT", -2, 2)
    lsfTimerBar:SetHeight(14)
    lsfTimerBar:SetFrameLevel(lsf:GetFrameLevel())
    local lsfTimerBarTex = lsfTimerBar:CreateTexture(nil, "BACKGROUND")
    lsfTimerBarTex:SetAllPoints(lsfTimerBar)
    lsfTimerBarTex:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
    lsfTimerBarTex:SetTexCoord(0, 1, 0, 0.5)
    lsfTimerBarTex:SetVertexColor(0.35, 0.3, 0.25, 0.95)
    local icon = lsf:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("TOP", 0, -4)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(LIGHTNING_SHIELD_ICON)
    icon:SetVertexColor(0.35, 0.35, 0.35)
    lsf.icon = icon
    -- Charge count in the middle of the icon (like WoW buff stacks)
    local charges = lsf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    charges:SetPoint("CENTER", icon, "CENTER", 0, 0)
    charges:SetTextColor(1, 1, 1)
    lsf.charges = charges
    local timer = lsf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timer:SetPoint("BOTTOM", 0, 4)
    timer:SetTextColor(1, 1, 1)
    lsf.timer = timer
    lightningShieldFrame = lsf

    -- Weapon Imbue slot (Flametongue / Frostbrand / Rockbiter / Windfury Weapon)
    local wif = CreateFrame("Frame", nil, f, "BackdropTemplate")
    wif:SetSize(slotW, slotH)
    wif:SetPoint("LEFT", lightningShieldFrame, "RIGHT", gap, 0)
    wif:SetPoint("TOP", slotFrames[DISPLAY_ORDER[1]], "TOP", 0, 0)
    wif:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    wif:SetBackdropColor(0.12, 0.1, 0.08, 0.94)
    wif:SetBackdropBorderColor(0.55, 0.48, 0.35, 1)
    -- Bar texture strip behind where the numbers show (bottom of slot); same as totem/Lightning Shield slots
    local wifTimerBar = CreateFrame("Frame", nil, wif)
    wifTimerBar:SetPoint("BOTTOMLEFT", 2, 2)
    wifTimerBar:SetPoint("BOTTOMRIGHT", -2, 2)
    wifTimerBar:SetHeight(14)
    wifTimerBar:SetFrameLevel(wif:GetFrameLevel())
    local wifTimerBarTex = wifTimerBar:CreateTexture(nil, "BACKGROUND")
    wifTimerBarTex:SetAllPoints(wifTimerBar)
    wifTimerBarTex:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
    wifTimerBarTex:SetTexCoord(0, 1, 0, 0.5)
    wifTimerBarTex:SetVertexColor(0.35, 0.3, 0.25, 0.95)
    local wifIcon = wif:CreateTexture(nil, "ARTWORK")
    wifIcon:SetSize(iconSize, iconSize)
    wifIcon:SetPoint("TOP", 0, -4)
    wifIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    wifIcon:SetTexture(WEAPON_IMBUE_EMPTY_ICON_ID)
    wifIcon:SetVertexColor(0.35, 0.35, 0.35)
    wif.icon = wifIcon
    local wifTimer = wif:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wifTimer:SetPoint("BOTTOM", 0, 4)
    wifTimer:SetTextColor(1, 1, 1)
    wif.timer = wifTimer
    weaponImbueFrame = wif

    -- Focused slot (Shamanistic Focus proc: next Shock costs 60% less, 15 sec)
    local ff = CreateFrame("Frame", nil, f, "BackdropTemplate")
    ff:SetSize(slotW, slotH)
    ff:SetPoint("LEFT", weaponImbueFrame, "RIGHT", gap, 0)
    ff:SetPoint("TOP", slotFrames[DISPLAY_ORDER[1]], "TOP", 0, 0)
    ff:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    ff:SetBackdropColor(0.12, 0.1, 0.08, 0.94)
    ff:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)
    local ffTimerBar = CreateFrame("Frame", nil, ff)
    ffTimerBar:SetPoint("BOTTOMLEFT", 2, 2)
    ffTimerBar:SetPoint("BOTTOMRIGHT", -2, 2)
    ffTimerBar:SetHeight(14)
    ffTimerBar:SetFrameLevel(ff:GetFrameLevel())
    local ffTimerBarTex = ffTimerBar:CreateTexture(nil, "BACKGROUND")
    ffTimerBarTex:SetAllPoints(ffTimerBar)
    ffTimerBarTex:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
    ffTimerBarTex:SetTexCoord(0, 1, 0, 0.5)
    ffTimerBarTex:SetVertexColor(0.35, 0.3, 0.25, 0.95)
    local ffIcon = ff:CreateTexture(nil, "ARTWORK")
    ffIcon:SetSize(iconSize, iconSize)
    ffIcon:SetPoint("TOP", 0, -4)
    ffIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ffIcon:SetTexture(FOCUSED_ICON)
    ffIcon:SetVertexColor(0.35, 0.35, 0.35)
    ff.icon = ffIcon
    local ffTimer = ff:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ffTimer:SetPoint("BOTTOM", 0, 4)
    ffTimer:SetTextColor(1, 1, 1)
    ff.timer = ffTimer
    focusedFrame = ff

    mainFrame = f
    return f
end

-- Windfury stats: same layout/design as totem bar — row of slots (Procs, Proc %, Crits, Min, Avg, Max, Total), each with Pull/Session values.
-- Procs = Windfury proc hits (WF Attack damage events; parry/dodge/miss not counted).
local WF_STAT_LABELS = { "Procs", "Proc %", "Crits", "Min", "Avg", "Max", "Total" }
local function CreateWindfuryStatsFrame()
    if windfuryStatsFrame then return windfuryStatsFrame end
    if not mainFrame then return nil end
    local db = GetDB()
    local iconSize = 36
    local gap = 2
    local slotW, slotH = iconSize + 6, iconSize + 18
    local numSlots = 7
    local fw = numSlots * slotW + (numSlots - 1) * gap
    local fh = slotH

    local wf = CreateFrame("Frame", "ShammyTimeWindfuryFrame", UIParent, "BackdropTemplate")
    wf:SetSize(fw, fh)
    wf:SetScale(db.wfScale or 1)
    local wfRelTo = (db.wfRelativeTo and _G[db.wfRelativeTo]) or mainFrame or UIParent
    wf:SetPoint(db.wfPoint or "TOP", wfRelTo, db.wfRelativePoint or "BOTTOM", db.wfX or 0, db.wfY or -4)
    wf:SetMovable(true)
    wf:SetClampedToScreen(true)
    wf:EnableMouse(true)
    wf:RegisterForDrag("LeftButton")
    wf:SetScript("OnDragStart", function(self)
        if not (db.wfLocked) then self:StartMoving() end
    end)
    wf:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, relTo, relPt, x, y = self:GetPoint(1)
        db.wfPoint = pt
        db.wfRelativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent"
        db.wfRelativePoint = relPt
        db.wfX = x
        db.wfY = y
    end)
    wf:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            ResetWindfurySession()
            print(C.green .. "ShammyTime: Windfury stats reset." .. C.r)
        end
    end)
    wf:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Right-click to reset stats")
        GameTooltip:Show()
    end)
    wf:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Same backdrop and styling as totem slots
    local slotFrames = {}
    for i = 1, numSlots do
        local sf = CreateFrame("Frame", nil, wf, "BackdropTemplate")
        sf:SetSize(slotW, slotH)
        if i == 1 then
            sf:SetPoint("TOPLEFT", wf, "TOPLEFT", 0, 0)
        else
            sf:SetPoint("LEFT", slotFrames[i - 1], "RIGHT", gap, 0)
            sf:SetPoint("TOP", slotFrames[1], "TOP", 0, 0)
        end
        sf:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        sf:SetBackdropColor(0.12, 0.1, 0.08, 0.94)
        sf:SetBackdropBorderColor(0.55, 0.48, 0.35, 1)

        -- Dark bar strip at bottom (same as totem timer area)
        local timerBar = CreateFrame("Frame", nil, sf)
        timerBar:SetPoint("BOTTOMLEFT", 2, 2)
        timerBar:SetPoint("BOTTOMRIGHT", -2, 2)
        timerBar:SetHeight(14)
        timerBar:SetFrameLevel(sf:GetFrameLevel())
        local timerBarTex = timerBar:CreateTexture(nil, "BACKGROUND")
        timerBarTex:SetAllPoints(timerBar)
        timerBarTex:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
        timerBarTex:SetTexCoord(0, 1, 0, 0.5)
        timerBarTex:SetVertexColor(0.35, 0.3, 0.25, 0.95)

        -- Label at top (Procs, Min, Max, Avg, Total)
        local label = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOP", 0, -6)
        label:SetText(WF_STAT_LABELS[i])
        label:SetTextColor(0.7, 0.68, 0.62)
        sf.label = label

        -- Values: Pull above Session, spaced so they don't overlap (same value = was drawing twice)
        local pullVal = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pullVal:SetPoint("BOTTOM", 0, 20)
        pullVal:SetTextColor(0.65, 0.62, 0.58)
        sf.pullVal = pullVal
        local sessionVal = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sessionVal:SetPoint("BOTTOM", 0, 4)
        sessionVal:SetTextColor(1, 1, 1)
        sf.sessionVal = sessionVal

        slotFrames[i] = sf
    end
    wf.slotFrames = slotFrames

    function wf:UpdateText()
        local function val(st, kind)
            if st.count == 0 then
                if kind == "procs" or kind == "crits" then return "0" end
                -- Proc %: show 0% when we have swings but no procs; otherwise "–"
                if kind == "procrate" then
                    local swings = st.swings or 0
                    return (swings > 0) and "0%" or "–"
                end
                return "–"
            end
            -- Procs = Windfury proc hits (WF Attack damage events; parry/dodge/miss not counted)
            if kind == "procs" then return tostring(st.count) end
            -- Proc rate = WF proc hits / eligible white swings (WF hits don't proc WF)
            if kind == "procrate" then
                local swings = st.swings or 0
                if swings <= 0 then return "–" end
                local rate = st.count / swings
                if rate >= 1 then return "100%" end
                return ("%.1f%%"):format(rate * 100)
            end
            -- Min/Avg/Max = single-hit stats (not sums). Total = sum only.
            if kind == "min" then return st.min and FormatNumberShort(st.min) or "–" end
            if kind == "max" then return st.max and FormatNumberShort(st.max) or "–" end
            if kind == "avg" then return FormatNumberShort(math.floor(st.total / st.count + 0.5)) end
            if kind == "total" then return FormatNumberShort(st.total) end
            if kind == "crits" then return tostring(st.crits or 0) end
            return "–"
        end
        local kinds = { "procs", "procrate", "crits", "min", "avg", "max", "total" }
        for i = 1, numSlots do
            local sf = self.slotFrames[i]
            local pullStr = val(wfPull, kinds[i])
            local sessionStr = val(wfSession, kinds[i])
            sf.pullVal:SetText(pullStr)
            sf.sessionVal:SetText(sessionStr)
            -- Show pull row whenever in a pull (count > 0) so both rows are visible in combat; hide when out of combat
            if wfPull.count > 0 then sf.pullVal:Show() else sf.pullVal:Hide() end
        end
    end
    wf:UpdateText()
    windfuryStatsFrame = wf
    return wf
end

local function OnEvent(_, event)
    if event == "PLAYER_TOTEM_UPDATE" then
        UpdateAllSlots()
    elseif event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
        if addonName ~= "ShammyTime" then return end
        CreateMainFrame()
        UpdateAllSlots()
        if timerTicker then timerTicker:Cancel() end
        timerTicker = C_Timer.NewTicker(1, RefreshTimers)
        mainFrame:UnregisterEvent("ADDON_LOADED")
    end
end

-- WoW Classic Anniversary 2026 (Interface 20505) and older builds (20501–20504): payload may come from
-- CombatLogGetCurrentEventInfo() or from event varargs; spellId can be 0 in Classic so we match by spell name too.
local function ParseCombatLogWindfuryDamage()
    if not CombatLogGetCurrentEventInfo then return nil end
    local subevent = select(2, CombatLogGetCurrentEventInfo())
    if subevent ~= "SPELL_DAMAGE" and subevent ~= "SPELL_DAMAGE_CRIT" then return nil end
    local sourceGUID = select(4, CombatLogGetCurrentEventInfo())
    local sourceName = select(5, CombatLogGetCurrentEventInfo())
    local spellId = select(12, CombatLogGetCurrentEventInfo())
    local spellName = select(13, CombatLogGetCurrentEventInfo())
    local amount = select(15, CombatLogGetCurrentEventInfo())
    -- Critical: subevent SPELL_DAMAGE_CRIT, or payload param 21 (1/true = crit; 0/nil = not; in Lua 0 is truthy so check explicitly)
    local critFlag = select(21, CombatLogGetCurrentEventInfo())
    local isCrit = (subevent == "SPELL_DAMAGE_CRIT") or (critFlag == true or critFlag == 1)
    return sourceGUID, sourceName, spellId, spellName, amount, isCrit
end

local function OnCombatLogWindfury(...)
    local db = GetDB()
    -- Process when bar and/or popup is enabled (popup can work even if bar is hidden)
    if not db.windfuryTrackerEnabled and not db.wfPopupEnabled then return end
    local subevent
    if CombatLogGetCurrentEventInfo then
        subevent = select(2, CombatLogGetCurrentEventInfo())
    else
        subevent = select(2, ...)
    end
    -- Windfury procs only on white (auto) swings; WF Attack hits cannot proc WF. Count eligible swings for proc rate.
    if subevent == "SWING_DAMAGE" or subevent == "SWING_DAMAGE_LANDED" then
        if db.windfuryTrackerEnabled then
            local sourceGUID = (CombatLogGetCurrentEventInfo and select(4, CombatLogGetCurrentEventInfo())) or select(3, ...)
            if sourceGUID and sourceGUID == UnitGUID("player") then
                RecordEligibleSwing()
            end
        end
        return
    end
    if subevent ~= "SPELL_DAMAGE" and subevent ~= "SPELL_DAMAGE_CRIT" then return end

    local sourceGUID, sourceName, spellId, spellName, amount, isCrit
    if CombatLogGetCurrentEventInfo then
        sourceGUID, sourceName, spellId, spellName, amount, isCrit = ParseCombatLogWindfuryDamage()
    end
    if not sourceGUID and select(1, ...) then
        -- Fallback: varargs ... = (subevent, hideCaster, sourceGUID, ...) so indices are offset by 1 vs full payload.
        -- Full: 4=sourceGUID 5=sourceName 12=spellId 13=spellName 15=amount 21=critical → ...: 3 4 11 12 14 20.
        sourceGUID = select(3, ...)
        sourceName = select(4, ...)
        spellId = select(11, ...) or select(12, ...)
        spellName = select(12, ...) or select(13, ...)
        amount = select(14, ...)
        local critFlag = select(20, ...)
        isCrit = (subevent == "SPELL_DAMAGE_CRIT") or (critFlag == true or critFlag == 1)
    end
    if not amount or amount <= 0 then return end
    if sourceGUID ~= UnitGUID("player") then return end
    local isWindfury = (spellId and spellId == WINDFURY_ATTACK_SPELL_ID) or (spellName and spellName == "Windfury Attack")
    if isWindfury then
        RecordWindfuryHit(amount, isCrit)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
if eventFrame.RegisterUnitEvent then
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    eventFrame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
else
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
end
eventFrame:SetScript("OnEvent", function(_, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == "ShammyTime" then
        RestoreWindfuryDB()
        if not mainFrame then
            CreateMainFrame()
            mainFrame:Show()
            if timerTicker then timerTicker:Cancel() end
            timerTicker = C_Timer.NewTicker(1, RefreshTimers)
        end
        CreateWindfuryStatsFrame()
        if windfuryStatsFrame then
            if GetDB().windfuryTrackerEnabled then windfuryStatsFrame:Show() else windfuryStatsFrame:Hide() end
        end
        UpdateAllSlots()
        UpdateLightningShield()
        UpdateWeaponImbue()
        UpdateFocused()
        print(C.green .. "ShammyTime is enabled." .. C.r .. C.gray .. " Type " .. C.gold .. "/st" .. C.r .. C.gray .. " for settings." .. C.r)
    elseif event == "PLAYER_TOTEM_UPDATE" then
        UpdateAllSlots()
    elseif event == "UNIT_AURA" then
        if not eventFrame.RegisterUnitEvent or arg1 == "player" then
            UpdateAllSlots()
            UpdateLightningShield()
            UpdateWeaponImbue()
            UpdateFocused()
        end
    elseif event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then
        UpdateWeaponImbue()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLogWindfury(...)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Reset pull when entering combat so new pull starts fresh; last pull persists out of combat
        if GetDB().windfuryTrackerEnabled then ResetWindfuryPull() end
    end
end)

-- Debug: dump UnitAura return order and weapon imbue detection (run with /st debug).
local function DebugWeaponImbue()
    print("=== ShammyTime weapon imbue debug ===")
    -- 1) GetWeaponEnchantInfo (primary on Classic/TBC); 4th/8th = mainHandEnchantID, offHandEnchantID
    if GetWeaponEnchantInfo then
        local hasMH, expMH, _, enchantIdMH, hasOH, expOH, _, enchantIdOH = GetWeaponEnchantInfo()
        print(("GetWeaponEnchantInfo: hasMH=%s expMH=%s enchantIdMH=%s hasOH=%s expOH=%s enchantIdOH=%s"):format(
            tostring(hasMH), tostring(expMH), tostring(enchantIdMH), tostring(hasOH), tostring(expOH), tostring(enchantIdOH)))
    end
    -- 2) What GetWeaponImbueAura returns (UnitAura + GetWeaponEnchantInfo fallback)
    local icon, expTime, name, spellId = GetWeaponImbueAura()
    if name then
        print(("GetWeaponImbueAura: name=%q icon=%s (type=%s) expTime=%s (type=%s) spellId=%s"):format(
            tostring(name), tostring(icon), type(icon), tostring(expTime), type(expTime), tostring(spellId)))
    else
        print("GetWeaponImbueAura: returned nil (no imbue found)")
    end
    -- 3) First 8 buffs: raw UnitAura returns (positions 1-11) so we see API order
    print("First 8 HELPFUL auras (raw positions 1-11 from UnitAura):")
    for i = 1, 8 do
        local v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11 = UnitAura("player", i, "HELPFUL")
        if not v1 then
            print(("  [%d] (none)"):format(i))
            break
        end
        local is10 = (type(v4) == "string")
        print(("  [%d] name=%q | v2=%s v3=%s v4=%s (type=%s) v5=%s v6=%s v7=%s | v10=%s v11=%s | is10=%s"):format(
            i, tostring(v1), tostring(v2), tostring(v3), tostring(v4), type(v4), tostring(v5), tostring(v6), tostring(v7), tostring(v10), tostring(v11), tostring(is10)))
        -- If this looks like a weapon imbue by name, say so
        if v1 and (tostring(v1):find("Flametongue") or tostring(v1):find("Frostbrand") or tostring(v1):find("Rockbiter") or tostring(v1):find("Windfury")) then
            print(("       ^^^ weapon imbue by name; spellId would be v10=%s or v11=%s"):format(tostring(v10), tostring(v11)))
        end
    end
    print("=== end debug ===")
end

local function PrintMainHelp()
    print(C.gold .. "ShammyTime — Commands" .. C.r)
    print(C.gray .. "  You can type " .. C.gold .. "/st" .. C.r .. C.gray .. " or " .. C.gold .. "/shammytime" .. C.r .. C.gray .. "." .. C.r)
    print("")
    print(C.gold .. "  Main bar" .. C.r .. C.gray .. " (totems, Lightning Shield, weapon imbue):" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "lock" .. C.r .. C.gray .. " — Lock the bar so it can't be moved" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "unlock" .. C.r .. C.gray .. " — Unlock so you can drag the bar (same as " .. C.gold .. "move" .. C.r .. C.gray .. ")" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "scale" .. C.r .. C.gray .. " — Make the bar bigger or smaller. Size: 0.5 to 2, default is 1." .. C.r)
    print(C.gray .. "    • " .. C.gold .. "debug" .. C.r .. C.gray .. " — Show technical info (for troubleshooting)" .. C.r)
    print("")
    print(C.gold .. "  Windfury bar" .. C.r .. C.gray .. " (proc stats when you have Windfury Weapon):" .. C.r)
    print(C.gray .. "    Type " .. C.gold .. "/st wf" .. C.r .. C.gray .. " to see all Windfury options." .. C.r)
end

local function PrintWindfuryHelp()
    print(C.gold .. "ShammyTime — Windfury bar options" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "reset" .. C.r .. C.gray .. " — Clear all Windfury stats (same as right-clicking the bar)" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "lock" .. C.r .. C.gray .. " | " .. C.gold .. "unlock" .. C.r .. C.gray .. " — Lock or unlock the Windfury bar" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "scale 1.2" .. C.r .. C.gray .. " — Windfury bar size (0.5 to 2)" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "enable" .. C.r .. C.gray .. " | " .. C.gold .. "disable" .. C.r .. C.gray .. " — Turn the Windfury tracker on or off" .. C.r)
    print("")
    print(C.gold .. "  Windfury total popup" .. C.r .. C.gray .. " (damage text when Windfury procs):" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "popup on" .. C.r .. C.gray .. " | " .. C.gold .. "popup off" .. C.r .. C.gray .. " — Show or hide the popup" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "popup lock" .. C.r .. C.gray .. " | " .. C.gold .. "popup unlock" .. C.r .. C.gray .. " — Lock position or unlock to drag the popup" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "popup scale 1.3" .. C.r .. C.gray .. " — Popup text size, like ingame crits (0.5 to 2)" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "popup hold 2" .. C.r .. C.gray .. " — Seconds the popup stays visible before fading (0.5 to 4)" .. C.r)
end

SLASH_SHAMMYTIME1 = "/shammytime"
SLASH_SHAMMYTIME2 = "/st"
SlashCmdList["SHAMMYTIME"] = function(msg)
    local db = GetDB()
    msg = msg and msg:gsub("^%s+", ""):gsub("%s+$", "") or ""
    local cmd, arg = msg:match("^(%S+)%s*(.*)$")
    if not cmd then cmd = msg end
    cmd = cmd and cmd:lower() or ""
    arg = arg and arg:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if cmd == "lock" then
        db.locked = true
        print(C.green .. "ShammyTime: Main bar is now locked." .. C.r)
    elseif cmd == "unlock" or cmd == "move" then
        db.locked = false
        print(C.green .. "ShammyTime: Main bar unlocked — you can drag it to move." .. C.r)
    elseif cmd == "scale" then
        if arg == "" then
            print(C.gray .. "ShammyTime: Main bar scale is " .. C.gold .. ("%.2f"):format(db.scale or 1) .. C.r .. C.gray .. ". Use " .. C.gold .. "/st scale" .. C.r .. C.gray .. " with a number from 0.5 to 2 (default is 1)." .. C.r)
        else
            local num = tonumber(arg)
            if num and num >= 0.5 and num <= 2 then
                db.scale = num
                ApplyScale()
                print(C.green .. "ShammyTime: Main bar scale set to " .. ("%.2f"):format(num) .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Scale must be a number between 0.5 and 2 (default is 1)." .. C.r .. C.gray .. " Example: " .. C.gold .. "/st scale 1.2" .. C.r)
            end
        end
    elseif cmd == "debug" then
        DebugWeaponImbue()
    elseif cmd == "wf" then
        local subcmd, subarg = arg:match("^(%S+)%s*(.*)$")
        subcmd = subcmd and subcmd:lower() or ""
        subarg = subarg and subarg:gsub("^%s+", ""):gsub("%s+$", "") or ""
        if subcmd == "reset" then
            ResetWindfurySession()
            print(C.green .. "ShammyTime: Windfury stats reset." .. C.r)
        elseif subcmd == "lock" then
            db.wfLocked = true
            print(C.green .. "ShammyTime: Windfury bar is now locked." .. C.r)
        elseif subcmd == "unlock" then
            db.wfLocked = false
            print(C.green .. "ShammyTime: Windfury bar unlocked — you can drag it to move." .. C.r)
        elseif subcmd == "scale" then
            if subarg == "" then
                print(C.gray .. "ShammyTime: Windfury bar scale is " .. C.gold .. ("%.2f"):format(db.wfScale or 1) .. C.r .. C.gray .. ". Use " .. C.gold .. "/st wf scale" .. C.r .. C.gray .. " with a number from 0.5 to 2 (default is 1)." .. C.r)
            else
                local num = tonumber(subarg)
                if num and num >= 0.5 and num <= 2 then
                    db.wfScale = num
                    ApplyScale()
                    print(C.green .. "ShammyTime: Windfury bar scale set to " .. ("%.2f"):format(num) .. "." .. C.r)
                else
                    print(C.red .. "ShammyTime: Windfury scale must be between 0.5 and 2 (default is 1)." .. C.r .. C.gray .. " Example: " .. C.gold .. "/st wf scale 1.2" .. C.r)
                end
            end
        elseif subcmd == "disable" or subcmd == "off" then
            db.windfuryTrackerEnabled = false
            if windfuryStatsFrame then windfuryStatsFrame:Hide() end
            print(C.green .. "ShammyTime: Windfury tracker is now off." .. C.r)
        elseif subcmd == "enable" or subcmd == "on" then
            db.windfuryTrackerEnabled = true
            if windfuryStatsFrame then windfuryStatsFrame:Show() end
            print(C.green .. "ShammyTime: Windfury tracker is now on." .. C.r)
        elseif subcmd == "popup" then
            local popupSub, popupArg = subarg:match("^(%S+)%s*(.*)$")
            popupSub = popupSub and popupSub:lower() or ""
            popupArg = popupArg and popupArg:gsub("^%s+", ""):gsub("%s+$", "") or ""
            if popupSub == "on" or popupSub == "enable" or popupSub == "1" then
                db.wfPopupEnabled = true
                print(C.green .. "ShammyTime: Windfury total popup is now on." .. C.r)
            elseif popupSub == "off" or popupSub == "disable" or popupSub == "0" then
                db.wfPopupEnabled = false
                print(C.green .. "ShammyTime: Windfury total popup is now off." .. C.r)
            elseif popupSub == "lock" then
                db.wfPopupLocked = true
                print(C.green .. "ShammyTime: Windfury total popup position is now locked." .. C.r)
            elseif popupSub == "unlock" then
                db.wfPopupLocked = false
                print(C.green .. "ShammyTime: Windfury total popup unlocked — drag the popup when it appears to move it." .. C.r)
            elseif popupSub == "scale" then
                if popupArg == "" then
                    print(C.gray .. "ShammyTime: Windfury popup scale is " .. C.gold .. ("%.2f"):format(db.wfPopupScale or 1.3) .. C.r .. C.gray .. ". Use " .. C.gold .. "/st wf popup scale 1.3" .. C.r .. C.gray .. " (0.5 to 2, larger = like ingame crits)." .. C.r)
                else
                    local num = tonumber(popupArg)
                    if num and num >= 0.5 and num <= 2 then
                        db.wfPopupScale = num
                        print(C.green .. "ShammyTime: Windfury total popup scale set to " .. ("%.2f"):format(num) .. "." .. C.r)
                    else
                        print(C.red .. "ShammyTime: Popup scale must be between 0.5 and 2." .. C.r .. C.gray .. " Example: " .. C.gold .. "/st wf popup scale 1.3" .. C.r)
                    end
                end
            elseif popupSub == "hold" or popupSub == "time" or popupSub == "dissipation" then
                if popupArg == "" then
                    print(C.gray .. "ShammyTime: Windfury popup hold is " .. C.gold .. ("%.1f"):format(db.wfPopupHold or 2) .. C.r .. C.gray .. " s. Use " .. C.gold .. "/st wf popup hold 2" .. C.r .. C.gray .. " (0.5 to 4 s, how long before fading)." .. C.r)
                else
                    local num = tonumber(popupArg)
                    if num and num >= 0.5 and num <= 4 then
                        db.wfPopupHold = num
                        print(C.green .. "ShammyTime: Windfury total popup will stay visible for " .. ("%.1f"):format(num) .. " s before fading." .. C.r)
                    else
                        print(C.red .. "ShammyTime: Popup hold must be between 0.5 and 4 seconds." .. C.r .. C.gray .. " Example: " .. C.gold .. "/st wf popup hold 2" .. C.r)
                    end
                end
            elseif popupSub == "" then
                local popupOn = db.wfPopupEnabled
                local popupLocked = db.wfPopupLocked
                print(C.gold .. "ShammyTime — Windfury total popup" .. C.r)
                print(C.gray .. "  Show: " .. C.r .. (popupOn and (C.green .. "On" .. C.r) or (C.red .. "Off" .. C.r)) .. C.gray .. "  |  Position: " .. C.r .. (popupLocked and (C.green .. "Locked" .. C.r) or (C.gray .. "Unlocked (drag to move)" .. C.r)) .. C.gray .. "  |  Scale: " .. C.gold .. ("%.2f"):format(db.wfPopupScale or 1.3) .. C.r .. C.gray .. "  |  Hold: " .. C.gold .. ("%.1f"):format(db.wfPopupHold or 2) .. " s" .. C.r)
                print(C.gray .. "  Defaults: scale 1.3, hold 2 s, position center. Popup works even if Windfury bar is disabled." .. C.r)
                print("")
                print(C.gray .. "  " .. C.gold .. "/st wf popup on|off" .. C.r .. C.gray .. " — Show or hide" .. C.r)
                print(C.gray .. "  " .. C.gold .. "/st wf popup lock|unlock" .. C.r .. C.gray .. " — Lock position or unlock to drag" .. C.r)
                print(C.gray .. "  " .. C.gold .. "/st wf popup scale 1.3" .. C.r .. C.gray .. " — Text size (0.5 to 2)" .. C.r)
                print(C.gray .. "  " .. C.gold .. "/st wf popup hold 2" .. C.r .. C.gray .. " — Seconds visible before fading (0.5 to 4)" .. C.r)
            else
                local popupOn = db.wfPopupEnabled
                print(C.gray .. "ShammyTime: Windfury total popup is " .. C.r .. (popupOn and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)) .. C.gray .. ". Use " .. C.gold .. "/st wf popup" .. C.r .. C.gray .. " for all popup options." .. C.r)
            end
        elseif subcmd == "" then
            local on = db.windfuryTrackerEnabled
            local popupOn = db.wfPopupEnabled
            print(C.gold .. "ShammyTime — Windfury tracker" .. C.r)
            print(C.gray .. "  Tracker: " .. C.r .. (on and (C.green .. "On" .. C.r) or (C.red .. "Off" .. C.r)) .. C.gray .. "  |  Damage popup: " .. C.r .. (popupOn and (C.green .. "On" .. C.r) or (C.red .. "Off" .. C.r)))
            print("")
            PrintWindfuryHelp()
        else
            print(C.gray .. "ShammyTime: Unknown Windfury option. Options:" .. C.r)
            PrintWindfuryHelp()
        end
    else
        PrintMainHelp()
    end
end
