-- ShammyTime: Movable totem icons with timers, "gone" animation, and out-of-range indicator.
-- When you're too far from a totem to receive its buff, a red overlay appears on that slot.
-- WoW Classic Anniversary 2026 (TBC Anniversary Edition, Interface 20505); compatible with builds 20501–20505.

local addonName, addon = ...
-- Expose API for ShammyTime_Windfury.lua and AssetTest.lua (no require in WoW)
ShammyTime = ShammyTime or {}
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
    wfRadialEnabled = true,  -- show radial UI on Windfury proc (in addition to text popup option)
    wfRadialScale = 0.7,    -- scale for center ring + satellites (circle only) (0.5–2)
    wfTotemBarScale = 1.0,  -- scale for Windfury totem bar only (0.5–2)
    wfRadialShown = false,  -- persist: center + totem bar visible (restored after reload; set when /wfcenter on, proc, or placing totem)
    wfAlwaysShowNumbers = false,  -- if false (default): numbers fade after proc, show on hover; if true: numbers always visible
}

-- State: previous totem presence per slot (to detect "just gone")
local lastHadTotem = { [1] = false, [2] = false, [3] = false, [4] = false }
-- Windfury totem bar: set when a totem is just placed (for pop animation); consumed by GetTotemSlotData.
ShammyTime.windfurySlotJustPlaced = ShammyTime.windfurySlotJustPlaced or {}
-- Time of last placement per slot (for short range-overlay grace period).
local lastTotemPlacedTime = {}
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
-- count = Windfury Attack hits; procs = proc events (1 per WF proc, whether 1 or 2 hits); swings = eligible white swings.
local wfPull  = { total = 0, count = 0, procs = 0, min = nil, max = nil, crits = 0, swings = 0 }
local wfSession = { total = 0, count = 0, procs = 0, min = nil, max = nil, crits = 0, swings = 0 }
local lastWfHitTime = 0  -- used to group hits into one proc (0.4s window)
-- Windfury popup: buffer damage for one proc (2 hits), then show total in floating text
local wfPopupTotal = 0
local wfPopupTimer = nil
local wfPopupFrame = nil
local wfRadialHideNumbersTimer = nil  -- delay before hiding numbers on hover leave
local wfRadialHoverAnims = {}  -- cancel these when hover leave (fade-in animation groups)
local wfTestTimer = nil  -- /st test: Windfury proc every 5s (random hits/crits) + Shamanistic Focus every 10s (toggle off by /st test again)

local function GetDB()
    ShammyTimeDB = ShammyTimeDB or {}
    for k, v in pairs(DEFAULTS) do
        if ShammyTimeDB[k] == nil then ShammyTimeDB[k] = v end
    end
    return ShammyTimeDB
end

-- Per-character position for Windfury radial (center ring + totem bar placed separately)
local function GetRadialPositionKey()
    return (GetRealmName() or "") .. "\001" .. (UnitName("player") or "")
end

function ShammyTime.GetRadialPositionDB()
    local db = GetDB()
    db.wfRadialPos = db.wfRadialPos or {}
    local key = GetRadialPositionKey()
    if not db.wfRadialPos[key] then
        db.wfRadialPos[key] = { center = nil, totemBar = nil, imbueBar = nil }
    end
    return db.wfRadialPos[key]
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
    ShammyTime.lastProcTotal = total  -- for Windfury radial module
    local f = CreateWindfuryPopupFrame()
    if f.animTicker then
        f.animTicker:Cancel()
        f.animTicker = nil
    end
    local hadCrit = ShammyTime.lastProcHadCritForPopup or ShammyTime.lastProcHadCrit
    ShammyTime.lastProcHadCritForPopup = nil
    ShammyTime.lastProcHadCrit = nil
    local popupText = ("Windfury: %s"):format(FormatNumberShort(total))
    if hadCrit then popupText = popupText .. "  CRITICAL!" end
    f.text:SetText(popupText)
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
        procs = wfSession.procs or 0,
        min = wfSession.min,
        max = wfSession.max,
        crits = wfSession.crits or 0,
        swings = wfSession.swings or 0,
    }
    db.wfLastPull = {
        total = wfPull.total,
        count = wfPull.count,
        procs = wfPull.procs or 0,
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
        wfSession.procs = db.wfSession.procs or 0
        wfSession.min = db.wfSession.min
        wfSession.max = db.wfSession.max
        wfSession.crits = db.wfSession.crits or 0
        wfSession.swings = db.wfSession.swings or 0
    end
    if db.wfLastPull then
        wfPull.total = db.wfLastPull.total or 0
        wfPull.count = db.wfLastPull.count or 0
        wfPull.procs = db.wfLastPull.procs or 0
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
-- One proc = 1 or 2 hits; we count proc events (procs) once per burst using a 0.4s window; count = total hits.
local WF_PROC_WINDOW = 0.4
local function RecordWindfuryHit(amount, isCrit)
    if not amount or amount <= 0 then return end
    if isCrit then ShammyTime.lastProcHadCrit = true end  -- for "Windfury! CRITICAL!" / popup
    local now = GetTime()
    local isNewProc = (now - lastWfHitTime) > WF_PROC_WINDOW
    lastWfHitTime = now
    for _, st in ipairs({ wfPull, wfSession }) do
        if isNewProc then st.procs = (st.procs or 0) + 1 end
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
    wfPull.total, wfPull.count, wfPull.procs, wfPull.min, wfPull.max, wfPull.crits, wfPull.swings = 0, 0, 0, nil, nil, 0, 0
    ScheduleWindfuryUpdate()
    SaveWindfuryDB()
end

-- Reset session stats (and pull).
local function ResetWindfurySession()
    wfPull.total, wfPull.count, wfPull.procs, wfPull.min, wfPull.max, wfPull.crits, wfPull.swings = 0, 0, 0, nil, nil, 0, 0
    wfSession.total, wfSession.count, wfSession.procs, wfSession.min, wfSession.max, wfSession.crits, wfSession.swings = 0, 0, 0, nil, nil, 0, 0
    ScheduleWindfuryUpdate()
    SaveWindfuryDB()
end

-- Test mode: simulate one Windfury proc with 2 random hits, some random crits; update stats and play center ring.
local function SimulateTestProc()
    local critChance = math.random(20, 45)  -- 20–45% crit per hit so crit % varies
    local function rollCrit() return math.random(1, 100) <= critChance end
    local amount1 = math.random(700, 2200)
    local amount2 = math.random(700, 2200)
    local crit1 = rollCrit()
    local crit2 = rollCrit()
    if crit1 then amount1 = math.floor(amount1 * (math.random(140, 200) / 100) + 0.5) end
    if crit2 then amount2 = math.floor(amount2 * (math.random(140, 200) / 100) + 0.5) end
    local numSwings = math.random(4, 10)
    for _ = 1, numSwings do RecordEligibleSwing() end
    RecordWindfuryHit(amount1, crit1)
    RecordWindfuryHit(amount2, crit2)
    local total = amount1 + amount2
    ShammyTime.lastProcTotal = total  -- so radial/satellites and GetWindfuryStats() show this proc
    if windfuryStatsFrame and windfuryStatsFrame.UpdateText then
        windfuryStatsFrame:UpdateText()
    end
    if ShammyTime.PlayCenterRingProc then ShammyTime.PlayCenterRingProc(total, true) end
end

-- Show Windfury radial (center ring + satellites) with current stats; no proc animation.
local function ShowWindfuryRadial()
    local db = GetDB()
    if not db.wfRadialEnabled then return end
    if ShammyTime.EnsureCenterRingExists then ShammyTime.EnsureCenterRingExists() end
    local center = _G.ShammyTimeCenterRing
    if center then
        center:Show()
        if center.textFrame then center.textFrame:Show() end
        if center.total then
            center.total:SetText("TOTAL: " .. FormatNumberShort(ShammyTime.lastProcTotal or 0))
        end
    end
    if ShammyTime.ShowAllSatellites then ShammyTime.ShowAllSatellites() end
    if ShammyTime.UpdateSatelliteValues and ShammyTime_Windfury_GetStats then
        ShammyTime.UpdateSatelliteValues(ShammyTime_Windfury_GetStats())
    end
end

-- Hide Windfury radial (center ring + satellites).
local function HideWindfuryRadial()
    local center = _G.ShammyTimeCenterRing
    if center then
        center:Hide()
        if center.textFrame then center.textFrame:Hide() end
    end
    if ShammyTime.HideAllSatellites then ShammyTime.HideAllSatellites() end
end

-- Hover: smooth fade-in left-to-right (satellites then center), fade-out uses same animation as after-hold
local HOVER_FADE_IN_DURATION = 0.22
local HOVER_STAGGER = 0.07  -- delay between starting each element (left-to-right)

local function CancelHoverFadeIn()
    for _, ag in pairs(wfRadialHoverAnims) do
        if ag and ag.Stop then ag:Stop() end
    end
    wfRadialHoverAnims = {}
end

-- Animate one frame's alpha from startAlpha -> 1 over duration (startAlpha defaults to 0; use current alpha to avoid blink on re-enter)
local function FadeInFrame(frame, duration, startAlpha)
    if not frame or not frame.CreateAnimationGroup then return end
    startAlpha = (startAlpha == nil or startAlpha < 0) and 0 or math.min(1, startAlpha)
    frame:SetAlpha(startAlpha)
    local ag = frame:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(startAlpha)
    a:SetToAlpha(1)
    a:SetDuration(duration)
    a:SetSmoothing("OUT")
    ag:SetScript("OnFinished", function()
        frame:SetAlpha(1)
        wfRadialHoverAnims[frame] = nil
    end)
    ag:SetScript("OnStop", function()
        wfRadialHoverAnims[frame] = nil
    end)
    wfRadialHoverAnims[frame] = ag
    ag:Play()
end

-- Show numbers with smooth fade-in: satellites left-to-right, then Windfury/total in center
-- If all numbers already visible (mouse kept over), do nothing. If a frame is already fading in, don't restart.
-- When re-entering after leave stopped anims, fade from current alpha to 1 (no reset to 0 = no blink).
local function StartRadialNumbersFadeIn()
    local center = _G.ShammyTimeCenterRing
    if not center or not center:IsShown() then return end
    if center.textFrame and center.textFrame.fadeOutAnim then center.textFrame.fadeOutAnim:Stop() end
    if center.textFrame then center.textFrame:Show() end
    local config = ShammyTime.SATELLITE_CONFIG or {}
    local elements = {}
    for _, cfg in ipairs(config) do
        local f = ShammyTime.GetSatelliteFrame and ShammyTime.GetSatelliteFrame(cfg.name)
        if f and f:IsShown() and f.textFrame and f.currentValue and f.currentValue ~= "" and f.currentValue ~= "0" and f.currentValue ~= "0%" and f.currentValue ~= "–" then
            if f.textFrame.fadeOutAnim then f.textFrame.fadeOutAnim:Stop() end
            f.textFrame:Show()
            elements[#elements + 1] = f.textFrame
        end
    end
    elements[#elements + 1] = center.textFrame
    -- If mouse is kept over and all numbers already visible, don't start any animation
    local allVisible = true
    for _, textFrame in ipairs(elements) do
        if textFrame and textFrame.GetAlpha and textFrame:GetAlpha() < 0.99 then
            allVisible = false
            break
        end
    end
    if allVisible then return end
    for i, textFrame in ipairs(elements) do
        C_Timer.After((i - 1) * HOVER_STAGGER, function()
            if not textFrame or not textFrame.SetAlpha then return end
            -- If this frame is already fading in, don't restart (prevents blink)
            local ag = wfRadialHoverAnims[textFrame]
            if ag and ag.IsPlaying and ag:IsPlaying() then return end
            -- If already fully visible, nothing to do
            if textFrame:GetAlpha() >= 0.99 then return end
            -- Fade from current alpha to 1 so re-entering after leave doesn't reset to 0 and blink
            local fromAlpha = textFrame:GetAlpha()
            FadeInFrame(textFrame, HOVER_FADE_IN_DURATION, fromAlpha)
        end)
    end
end

-- Fade out numbers (same as after-hold: center fade + satellite chain)
local function StartRadialNumbersFadeOut()
    local db = GetDB()
    if db.wfAlwaysShowNumbers then return end
    local center = _G.ShammyTimeCenterRing
    if center and center.textFrame and center.textFrame:IsShown() and center.textFrame.fadeOutAnim then
        center.textFrame.fadeOutAnim:Stop()
        center.textFrame:SetAlpha(1)
        center.textFrame.fadeOutAnim:Play()
    end
    if ShammyTime.StartSatelliteTextChainFade then ShammyTime.StartSatelliteTextChainFade() end
end

function ShammyTime.OnRadialHoverEnter()
    if wfRadialHideNumbersTimer then
        wfRadialHideNumbersTimer:Cancel()
        wfRadialHideNumbersTimer = nil
    end
    StartRadialNumbersFadeIn()
end

function ShammyTime.OnRadialHoverLeave()
    if wfRadialHideNumbersTimer then wfRadialHideNumbersTimer:Cancel() end
    CancelHoverFadeIn()
    wfRadialHideNumbersTimer = C_Timer.NewTimer(0.15, function()
        wfRadialHideNumbersTimer = nil
        StartRadialNumbersFadeOut()
    end)
end

-- API for ShammyTime_Windfury.lua (radial UI), CenterRing, and AssetTest.lua
ShammyTime.lastProcTotal = 0
ShammyTime.GetDB = GetDB
ShammyTime.ResetWindfurySession = ResetWindfurySession
ShammyTime.ShowWindfuryRadial = ShowWindfuryRadial
ShammyTime.HideWindfuryRadial = HideWindfuryRadial
ShammyTime.GetWindfuryStats = function()
    return wfPull, wfSession, ShammyTime.lastProcTotal or 0
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

-- Returns main hand and off hand weapon imbue data for the imbue bar (left = MH, right = OH).
-- Returns: { mainHand = { icon, expirationTime, name, spellId } or nil, offHand = { ... } or nil }
function ShammyTime.GetWeaponImbuePerHand()
    local out = { mainHand = nil, offHand = nil }
    if not GetWeaponEnchantInfo then return out end
    local hasMH, expMH, _, enchantIdMH, hasOH, expOH, _, enchantIdOH = GetWeaponEnchantInfo()
    local function makeSlot(hasEnchant, expMs, enchantId)
        if not hasEnchant or not expMs or expMs <= 0 or not enchantId then return nil end
        local spellId = WEAPON_IMBUE_ENCHANT_TO_SPELL[enchantId]
        local name = (spellId and GetSpellInfo and GetSpellInfo(spellId)) or "Weapon Imbue"
        local icon = WEAPON_IMBUE_ENCHANT_ICONS[enchantId] or WEAPON_IMBUE_ICON_ID
        local remainingSec = (type(expMs) == "number" and expMs / 1000) or 0
        local expirationTime = GetTime() + remainingSec
        return { icon = icon, expirationTime = expirationTime, name = name, spellId = spellId }
    end
    out.mainHand = makeSlot(hasMH, expMH, enchantIdMH)
    out.offHand = makeSlot(hasOH, expOH, enchantIdOH)
    return out
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

-- Returns "in", "out", or "unknown" for Windfury bar and slot data (reuses main bar range logic).
local function GetSlotRangeState(slot, totemName)
    if not totemName or totemName == "" then return "unknown" end
    -- Water totems: give a brief grace window on placement so the buff has time to apply (prevents dark flash).
    if SLOT_TO_ELEMENT[slot] == "Water" then
        local placedAt = lastTotemPlacedTime[slot]
        if placedAt and (GetTime() - placedAt) < 0.4 then
            return "in"
        end
    end
    if IsTotemWithNoRangeBuff(totemName) and not GetTotemPositionRange(totemName) then return "unknown" end
    local buffSpellId = GetTotemBuffSpellId(totemName)
    local hasBuff = (buffSpellId and HasPlayerBuffByAnySpellId(buffSpellId)) or HasPlayerBuffByTotemName(totemName)
    local outOfRangeBuff = not IsTotemWithNoRangeBuff(totemName) and buffSpellId and not hasBuff
    local outOfRangePos = false
    if GetTotemPositionRange(totemName) and totemPosition[slot] and UnitPosition then
        local posY, posX, posZ = UnitPosition("player")
        if posX and totemPosition[slot].x then
            local dist = GetDistanceYards(totemPosition[slot].x, totemPosition[slot].y, totemPosition[slot].z, posX, posY, posZ)
            local maxRange = GetTotemPositionRange(totemName)
            if dist and maxRange and dist > maxRange then outOfRangePos = true end
        end
    end
    if outOfRangeBuff or outOfRangePos then return "out" end
    return "in"
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
    if nowHasTotem and wasJustPlaced then
        lastTotemPlacedTime[slot] = GetTime()
        ShammyTime.windfurySlotJustPlaced[slot] = true
    end

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

-- API for Windfury totem bar: one source of truth for totem state (no duplicate GetTotemInfo/range logic).
-- Returns: active, remainingSeconds, durationSeconds, icon, rangeState ("in"|"out"|"unknown"), justPlaced, emptyIcon.
-- Consumes justPlaced (clears windfurySlotJustPlaced[slot] when read).
function ShammyTime.GetTotemSlotData(slot)
    if not slot or slot < 1 or slot > 4 then return nil end
    local haveTotem, totemName, startTime, duration, icon = GetTotemInfo(slot)
    local active = (totemName and totemName ~= "")
    local remaining = active and GetTotemTimeLeft(slot) or 0
    local durationSec = (type(duration) == "number" and duration > 0) and duration or 0
    local iconTex = (icon and icon ~= "") and icon or "Interface\\Icons\\INV_Elemental_Primal_Earth"
    local rangeState = active and GetSlotRangeState(slot, totemName) or "unknown"
    local justPlaced = ShammyTime.windfurySlotJustPlaced[slot]
    if justPlaced then ShammyTime.windfurySlotJustPlaced[slot] = nil end
    local element = SLOT_TO_ELEMENT[slot]
    local emptyIcon = ELEMENT_EMPTY_ICONS[element] or "Interface\\Icons\\INV_Misc_QuestionMark"
    return {
        active = active,
        remainingSeconds = remaining,
        durationSeconds = durationSec,
        icon = iconTex,
        rangeState = rangeState,
        justPlaced = justPlaced,
        emptyIcon = emptyIcon,
    }
end

ShammyTime.DISPLAY_ORDER = DISPLAY_ORDER
ShammyTime.FormatTime = FormatTime

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
-- Procs = number of proc events (1 per WF proc, whether it hits 1 or 2 times).
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
            -- Procs = number of proc events (1 per WF proc, whether 1 or 2 hits)
            if kind == "procs" then return tostring(st.procs or 0) end
            -- Proc % = proc events / eligible white swings
            if kind == "procrate" then
                local swings = st.swings or 0
                if swings <= 0 then return "–" end
                local procs = st.procs or 0
                if procs <= 0 then return "0%" end
                local rate = procs / swings
                if rate >= 1 then return "100%" end
                return ("%.0f%%"):format(rate * 100)
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
            if (wfPull.count or 0) > 0 then sf.pullVal:Show() else sf.pullVal:Hide() end
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
        -- Show Windfury radial (center ring + satellites) if enabled; always visible unless disabled
        ShowWindfuryRadial()
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
    print("")
    print(C.gold .. "═══════════════════════════════════════" .. C.r)
    print(C.gold .. "  ShammyTime" .. C.r .. C.gray .. "  —  " .. C.r .. C.gold .. "/st" .. C.r .. C.gray .. " or " .. C.r .. C.gold .. "/shammytime" .. C.r)
    print(C.gold .. "═══════════════════════════════════════" .. C.r)
    print("")
    print(C.green .. "  GLOBAL (affects everything)" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "/st lock" .. C.r .. C.gray .. "   — Lock all bars (no drag)" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "/st unlock" .. C.r .. C.gray .. " — Unlock so you can drag" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "/st test" .. C.r .. C.gray .. "  — Windfury proc every 5s (random hits/crits), Shamanistic Focus every 10s (toggle; run again to stop)" .. C.r)
    print("")
    print(C.green .. "  CIRCLE" .. C.r .. C.gray .. "  —  " .. C.gold .. "/st radial" .. C.r .. C.gray .. "  on|off, scale, numbers" .. C.r)
    print(C.gray .. "    " .. C.gold .. "/st radial" .. C.r .. C.gray .. " for list" .. C.r)
    print("")
    print(C.green .. "  TOTEM BAR" .. C.r .. C.gray .. "  —  " .. C.gold .. "/st totem" .. C.r .. C.gray .. "  scale" .. C.r)
    print(C.gray .. "    " .. C.gold .. "/st totem" .. C.r .. C.gray .. " for list" .. C.r)
    print("")
    print(C.green .. "  SHAMANISTIC FOCUS" .. C.r .. C.gray .. "  —  " .. C.gold .. "/st focus" .. C.r .. C.gray .. "  scale (proc indicator)" .. C.r)
    print(C.gray .. "    " .. C.gold .. "/st focus" .. C.r .. C.gray .. " for list" .. C.r)
    print("")
    print(C.gray .. "  LEGACY (deprecating soon)" .. C.r .. C.gray .. "  —  " .. C.gold .. "/st legacy" .. C.r .. C.gray .. "  reset, bar, popup, main" .. C.r)
    print(C.gray .. "    " .. C.gold .. "/st legacy" .. C.r .. C.gray .. " for list" .. C.r)
    print("")
    print(C.gold .. "═══════════════════════════════════════" .. C.r)
    print("")
end

local function PrintRadialHelp()
    print("")
    print(C.green .. "ShammyTime — Circle (" .. C.gold .. "/st radial" .. C.r .. C.green .. ")" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "on" .. C.r .. C.gray .. "  / " .. C.gold .. "off" .. C.r .. C.gray .. "     — Show or hide circle" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "scale 0.8" .. C.r .. C.gray .. "  — Size (0.5–2). Shortcut: " .. C.gold .. "/wfresize 0.8" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "numbers on" .. C.r .. C.gray .. "  — Numbers always visible" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "numbers off" .. C.r .. C.gray .. "  — Numbers fade; show on hover (default)" .. C.r)
    print(C.gray .. "  Toggle UI: " .. C.gold .. "/wfcenter" .. C.r .. C.gray .. "  |  One-shot test: " .. C.gold .. "/wftest" .. C.r)
    print("")
end

local function PrintTotemHelp()
    print("")
    print(C.green .. "ShammyTime — Totem bar (" .. C.gold .. "/st totem" .. C.r .. C.green .. ")" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "scale 1" .. C.r .. C.gray .. "  — Size (0.5–2, default 1)" .. C.r)
    print("")
end

local function PrintFocusHelp()
    print("")
    print(C.green .. "ShammyTime — Shamanistic Focus (" .. C.gold .. "/st focus" .. C.r .. C.green .. ")" .. C.r)
    print(C.gray .. "  Proc indicator (light on/off when Shamanistic Focus is active)." .. C.r)
    print(C.gray .. "  • " .. C.gold .. "scale 1" .. C.r .. C.gray .. "  — Size (0.5–2, default 1)" .. C.r)
    print("")
end

local function PrintLegacyHelp()
    print("")
    print(C.gray .. "ShammyTime — Legacy (" .. C.gold .. "/st legacy" .. C.r .. C.gray .. ") — deprecating soon" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "reset" .. C.r .. C.gray .. "     — Clear Windfury stats" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "bar lock|unlock|scale 1|on|off" .. C.r .. C.gray .. "  — Stats bar" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "popup on|off|lock|unlock|scale 1|hold 2" .. C.r .. C.gray .. "  — Damage popup" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "main lock|unlock|scale 1|debug" .. C.r .. C.gray .. "  — Main totem bar" .. C.r)
    print("")
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

    -- Global: lock / unlock (all bars)
    if cmd == "lock" then
        db.locked = true
        db.wfLocked = true
        db.wfPopupLocked = true
        print(C.green .. "ShammyTime: All bars locked." .. C.r)
    elseif cmd == "unlock" or cmd == "move" then
        db.locked = false
        db.wfLocked = false
        db.wfPopupLocked = false
        print(C.green .. "ShammyTime: All bars unlocked — you can drag to move." .. C.r)
    -- Global: test mode — Windfury proc every 5s (random hits/crits), Shamanistic Focus every 10s (toggle)
    elseif cmd == "test" then
        if wfTestTimer then
            wfTestTimer:Cancel()
            wfTestTimer = nil
            if ShammyTime.StopShamanisticFocusTest then ShammyTime.StopShamanisticFocusTest() end
            print(C.green .. "ShammyTime: Test mode off." .. C.r)
        else
            wfTestTimer = C_Timer.NewTicker(5, function()
                SimulateTestProc()
            end)
            if ShammyTime.StartShamanisticFocusTest then ShammyTime.StartShamanisticFocusTest() end
            print(C.green .. "ShammyTime: Test mode on — Windfury proc every 5s (random hits/crits), Shamanistic Focus every 10s. Run " .. C.gold .. "/st test" .. C.r .. C.green .. " again to stop." .. C.r)
        end
    -- Global: scale (legacy main bar) and debug
    elseif cmd == "scale" then
        if arg == "" then
            print(C.gray .. "ShammyTime: Main bar scale " .. C.gold .. ("%.2f"):format(db.scale or 1) .. C.r .. C.gray .. ". " .. C.gold .. "/st legacy main scale 1" .. C.r .. C.gray .. " (0.5–2)." .. C.r)
        else
            local num = tonumber(arg)
            if num and num >= 0.5 and num <= 2 then
                db.scale = num
                ApplyScale()
                print(C.green .. "ShammyTime: Main bar scale " .. ("%.2f"):format(num) .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Scale 0.5–2. " .. C.gold .. "/st legacy main scale 1" .. C.r)
            end
        end
    elseif cmd == "debug" then
        DebugWeaponImbue()
    -- Circle: /st radial [on|off|scale X|numbers on|off]
    elseif cmd == "radial" then
        local a = arg:lower()
        local scaleArg = a:match("^scale%s+(%S+)$")
        local numArg = a:match("^numbers%s+(%S+)$")
        if a == "on" or a == "enable" or a == "1" then
            db.wfRadialEnabled = true
            ShowWindfuryRadial()
            print(C.green .. "ShammyTime: Circle on." .. C.r)
        elseif a == "off" or a == "disable" or a == "0" then
            db.wfRadialEnabled = false
            HideWindfuryRadial()
            print(C.green .. "ShammyTime: Circle off." .. C.r)
        elseif scaleArg then
            local num = tonumber(scaleArg)
            if num and num >= 0.5 and num <= 2 then
                db.wfRadialScale = num
                local center = _G.ShammyTimeCenterRing
                if center then center:SetScale(num) end
                print(C.green .. "ShammyTime: Circle scale " .. ("%.2f"):format(num) .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Circle scale 0.5–2. " .. C.gold .. "/st radial scale 0.8" .. C.r)
            end
        elseif numArg == "on" or numArg == "enable" or numArg == "1" then
            db.wfAlwaysShowNumbers = true
            print(C.green .. "ShammyTime: Circle numbers always on." .. C.r)
        elseif numArg == "off" or numArg == "disable" or numArg == "0" then
            db.wfAlwaysShowNumbers = false
            print(C.green .. "ShammyTime: Circle numbers fade; show on hover." .. C.r)
        elseif a == "numbers" then
            print(C.gray .. "ShammyTime: Circle numbers " .. (db.wfAlwaysShowNumbers and (C.green .. "always on" .. C.r) or (C.gray .. "fade; show on hover" .. C.r)) .. C.gray .. ". " .. C.gold .. "/st radial numbers on|off" .. C.r)
        elseif a == "" then
            print(C.gray .. "ShammyTime: Circle " .. (db.wfRadialEnabled and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)) .. C.gray .. ", scale " .. C.gold .. ("%.2f"):format(db.wfRadialScale or 0.7) .. C.r .. C.gray .. ", numbers " .. (db.wfAlwaysShowNumbers and (C.green .. "on" .. C.r) or (C.gray .. "hover" .. C.r)) .. C.r)
            PrintRadialHelp()
        else
            PrintRadialHelp()
        end
    -- Totem bar: /st totem [scale X]
    elseif cmd == "totem" then
        local a = arg:lower()
        local scaleArg = a:match("^scale%s+(%S+)$")
        if scaleArg then
            local num = tonumber(scaleArg)
            if num and num >= 0.5 and num <= 2 then
                db.wfTotemBarScale = num
                local bar = ShammyTime.EnsureWindfuryTotemBarFrame and ShammyTime.EnsureWindfuryTotemBarFrame()
                if bar then bar:SetScale(num) end
                print(C.green .. "ShammyTime: Totem bar scale " .. ("%.2f"):format(num) .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Totem bar scale 0.5–2. " .. C.gold .. "/st totem scale 1" .. C.r)
            end
        elseif a == "" then
            print(C.gray .. "ShammyTime: Totem bar scale " .. C.gold .. ("%.2f"):format(db.wfTotemBarScale or 1) .. C.r .. C.gray .. " (0.5–2)." .. C.r)
            PrintTotemHelp()
        else
            PrintTotemHelp()
        end
    -- Shamanistic Focus: /st focus [scale X]
    elseif cmd == "focus" then
        local a = arg:lower()
        local scaleArg = a:match("^scale%s+(%S+)$")
        ShammyTimeDB = ShammyTimeDB or {}
        ShammyTimeDB.focusFrame = ShammyTimeDB.focusFrame or {}
        local focusDb = ShammyTimeDB.focusFrame
        if scaleArg then
            local num = tonumber(scaleArg)
            if num and num >= 0.5 and num <= 2 then
                focusDb.scale = num
                if ShammyTime.ApplyShamanisticFocusScale then ShammyTime.ApplyShamanisticFocusScale() end
                print(C.green .. "ShammyTime: Shamanistic Focus scale " .. ("%.2f"):format(num) .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Shamanistic Focus scale 0.5–2. " .. C.gold .. "/st focus scale 1" .. C.r)
            end
        elseif a == "" then
            local s = focusDb.scale
            if s == nil then s = 1 end
            print(C.gray .. "ShammyTime: Shamanistic Focus scale " .. C.gold .. ("%.2f"):format(s) .. C.r .. C.gray .. " (0.5–2)." .. C.r)
            PrintFocusHelp()
        else
            PrintFocusHelp()
        end
    -- Legacy: /st legacy [reset|bar ...|popup ...|main ...]
    elseif cmd == "legacy" then
        local sub, subarg = arg:match("^(%S+)%s*(.*)$")
        sub = sub and sub:lower() or ""
        subarg = subarg and subarg:gsub("^%s+", ""):gsub("%s+$", "") or ""
        if sub == "reset" then
            ResetWindfurySession()
            print(C.green .. "ShammyTime: Statistics reset." .. C.r)
        elseif sub == "bar" then
            local b, val = subarg:match("^(%S+)%s*(.*)$")
            b = b and b:lower() or ""
            val = val and val:gsub("^%s+", ""):gsub("%s+$", "") or ""
            if b == "lock" then
                db.wfLocked = true
                print(C.green .. "ShammyTime: Legacy stats bar locked." .. C.r)
            elseif b == "unlock" then
                db.wfLocked = false
                print(C.green .. "ShammyTime: Legacy stats bar unlocked." .. C.r)
            elseif b == "on" or b == "enable" or b == "1" then
                db.windfuryTrackerEnabled = true
                if windfuryStatsFrame then windfuryStatsFrame:Show() end
                print(C.green .. "ShammyTime: Legacy tracker on." .. C.r)
            elseif b == "off" or b == "disable" or b == "0" then
                db.windfuryTrackerEnabled = false
                if windfuryStatsFrame then windfuryStatsFrame:Hide() end
                print(C.green .. "ShammyTime: Legacy tracker off." .. C.r)
            elseif b == "scale" then
                local num = tonumber(val)
                if num and num >= 0.5 and num <= 2 then
                    db.wfScale = num
                    ApplyScale()
                    print(C.green .. "ShammyTime: Legacy bar scale " .. ("%.2f"):format(num) .. "." .. C.r)
                else
                    print(C.red .. "ShammyTime: Scale 0.5–2. " .. C.gold .. "/st legacy bar scale 1" .. C.r)
                end
            else
                print(C.gray .. "ShammyTime: " .. C.gold .. "/st legacy bar lock|unlock|on|off|scale 1" .. C.r)
            end
        elseif sub == "popup" then
            local p, pval = subarg:match("^(%S+)%s*(.*)$")
            p = p and p:lower() or ""
            pval = pval and pval:gsub("^%s+", ""):gsub("%s+$", "") or ""
            if p == "on" or p == "enable" or p == "1" then
                db.wfPopupEnabled = true
                print(C.green .. "ShammyTime: Damage popup on." .. C.r)
            elseif p == "off" or p == "disable" or p == "0" then
                db.wfPopupEnabled = false
                print(C.green .. "ShammyTime: Damage popup off." .. C.r)
            elseif p == "lock" then
                db.wfPopupLocked = true
                print(C.green .. "ShammyTime: Popup locked." .. C.r)
            elseif p == "unlock" then
                db.wfPopupLocked = false
                print(C.green .. "ShammyTime: Popup unlocked." .. C.r)
            elseif p == "scale" then
                local num = tonumber(pval)
                if num and num >= 0.5 and num <= 2 then
                    db.wfPopupScale = num
                    print(C.green .. "ShammyTime: Popup scale " .. ("%.2f"):format(num) .. "." .. C.r)
                else
                    print(C.red .. "ShammyTime: Popup scale 0.5–2." .. C.r)
                end
            elseif p == "hold" or p == "time" then
                local num = tonumber(pval)
                if num and num >= 0.5 and num <= 4 then
                    db.wfPopupHold = num
                    print(C.green .. "ShammyTime: Popup hold " .. ("%.1f"):format(num) .. " s." .. C.r)
                else
                    print(C.red .. "ShammyTime: Popup hold 0.5–4 s." .. C.r)
                end
            else
                print(C.gray .. "ShammyTime: " .. C.gold .. "/st legacy popup on|off|lock|unlock|scale 1|hold 2" .. C.r)
            end
        elseif sub == "main" then
            local m, mval = subarg:match("^(%S+)%s*(.*)$")
            m = m and m:lower() or ""
            mval = mval and mval:gsub("^%s+", ""):gsub("%s+$", "") or ""
            if m == "lock" then
                db.locked = true
                print(C.green .. "ShammyTime: Main bar locked." .. C.r)
            elseif m == "unlock" then
                db.locked = false
                print(C.green .. "ShammyTime: Main bar unlocked." .. C.r)
            elseif m == "scale" then
                local num = tonumber(mval)
                if num and num >= 0.5 and num <= 2 then
                    db.scale = num
                    ApplyScale()
                    print(C.green .. "ShammyTime: Main bar scale " .. ("%.2f"):format(num) .. "." .. C.r)
                else
                    print(C.red .. "ShammyTime: Main bar scale 0.5–2." .. C.r)
                end
            elseif m == "debug" then
                DebugWeaponImbue()
            else
                print(C.gray .. "ShammyTime: " .. C.gold .. "/st legacy main lock|unlock|scale 1|debug" .. C.r)
            end
        elseif sub == "" then
            PrintLegacyHelp()
        else
            print(C.gray .. "ShammyTime: Unknown legacy option. " .. C.gold .. "/st legacy" .. C.r .. C.gray .. " for list." .. C.r)
            PrintLegacyHelp()
        end
    else
        if cmd ~= "" then
            print(C.gray .. "ShammyTime: Unknown command. Use " .. C.gold .. "/st" .. C.r .. C.gray .. " for menu." .. C.r)
        end
        PrintMainHelp()
    end
end
