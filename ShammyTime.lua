-- ShammyTime: Movable totem icons with timers, "gone" animation, and out-of-range indicator.
-- When you're too far from a totem to receive its buff, a red overlay appears on that slot.
-- WoW Classic Anniversary 2026 (TBC Anniversary Edition, Interface 20505); compatible with builds 20501–20505.

-- ShammyTime main logic (API, totems, windfury, fade). Core creates ShammyTime addon and DB.
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

-- DB from Core (AceDB profile); fallback if Core not loaded yet
local function GetDB()
    return (ShammyTime.GetDB and ShammyTime.GetDB()) or (ShammyTimeDB or {})
end

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


-- Windfury proc stats: pull (this combat) and session (since login / last reset).
-- All damage stats (min, max, total, avg) are per-PROC (sum of 1–2 hits per proc), not per hit.
-- count = total Windfury hits; procs = proc events (1 per WF proc); swings = eligible white swings.
local wfPull  = { total = 0, count = 0, procs = 0, min = nil, max = nil, crits = 0, swings = 0 }
local wfSession = { total = 0, count = 0, procs = 0, min = nil, max = nil, crits = 0, swings = 0 }
local lastWfHitTime = 0  -- used to group hits into one proc (0.4s window)
-- Current proc buffer: accumulated until proc window closes, then flushed (min/max/total from sum).
local wfProcBuffer = { total = 0, hits = 0, crits = 0 }
-- Timer to flush Windfury proc buffer after 0.4s (so 1-hit procs get committed to min/max/avg)
local wfPopupTimer = nil
local wfRadialHideNumbersTimer = nil  -- delay before hiding numbers on hover leave
local wfRadialHoverAnims = {}  -- cancel these when hover leave (fade-in animation groups)
local wfTestTimer = nil  -- /st test: global test (circle + Windfury + Shamanistic Focus); one proc immediately, then every 10s
local lastWfProcEndTime = 0  -- GetTime() when last Windfury proc animation ended; used for "fade when not procced" grace
local FADE_GRACE_AFTER_PROC = 15  -- seconds after proc end we still consider radial "procced" for fade logic (other elements)
local CIRCLE_SHOW_AFTER_PROC_SEC = 2  -- when "fade when not procced" is on: circle stays visible this long after proc animation, then fades out slowly
local FADE_ALPHA = 0  -- alpha when faded (e.g. when not procced) — 0% visibility
local FADE_OUT_OF_COMBAT_ALPHA = 0  -- alpha when faded out of combat (0% visibility)
local FADE_ANIM_OUT_DURATION = 2.5  -- slow fade-out when going out of combat / not procced (when user has fade settings on)
local FADE_ANIM_IN_DURATION = 1.5   -- slow fade-in when entering combat / procced
local NO_TOTEMS_FADE_ALPHA = 0  -- fully hidden when no totems (after delay)
local noTotemsFadeTimer = nil
local noTotemsFaded = false  -- true when radial has been faded due to no totems
local fadeGraceTimer = nil  -- one-shot: re-apply fade state when "procced" grace period ends (so "fade when not procced" takes effect)
local focusFadeHoldTimer = nil  -- delay focus fade-out so off art shows before frame fades
local circleFadeOutStarted = false  -- true once circle has started fading out; don't restore to 1 until next proc (avoids blink)
ShammyTime.circleHovered = false  -- true while mouse is over center ring; pauses fade-out (no revive from 0)
ShammyTime.radialNumbersVisible = false  -- true when radial numbers should be shown (prevents late re-show after fade)

-- Per-character position for Windfury radial (center ring + totem bar placed separately)
local function GetRadialPositionKey()
    return (GetRealmName() or "") .. "\001" .. (UnitName("player") or "")
end

function ShammyTime.GetRadialPositionDB()
    local db = GetDB()
    db.wfRadialPos = db.wfRadialPos or {}
    local key = GetRadialPositionKey()
    if not db.wfRadialPos[key] then
        db.wfRadialPos[key] = { center = nil, totemBar = nil, imbueBar = nil, shieldFrame = nil }
    end
    return db.wfRadialPos[key]
end

-- Hook called by Core's ResetAllToDefaults() to reset in-memory state that only ShammyTime.lua can access.
function ShammyTime:OnResetAll()
    wfPull.total, wfPull.count, wfPull.procs, wfPull.min, wfPull.max, wfPull.crits, wfPull.swings = 0, 0, 0, nil, nil, 0, 0
    wfSession.total, wfSession.count, wfSession.procs, wfSession.min, wfSession.max, wfSession.crits, wfSession.swings = 0, 0, 0, nil, nil, 0, 0
    wfProcBuffer.total, wfProcBuffer.hits, wfProcBuffer.crits = 0, 0, 0
    ShammyTime.lastProcTotal = 0
    noTotemsFaded = false
    circleFadeOutStarted = false
    if noTotemsFadeTimer then noTotemsFadeTimer:Cancel(); noTotemsFadeTimer = nil end
end

-- Reset all settings (delegate to Core AceDB reset + ApplyAllConfigs, which calls OnResetAll).
local function ResetAllToDefaults()
    if ShammyTime.ResetAllToDefaults then
        ShammyTime:ResetAllToDefaults()
        return true
    end
    return false
end

-- Format number for compact display (1234 -> "1.2k", 1234567 -> "1.2m").
local function FormatNumberShort(n)
    if not n or n < 0 then return "0" end
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
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

-- No-op: stats bar UI removed; data still used by center ring and satellites.
local function ScheduleWindfuryUpdate()
end

-- Record one eligible white swing (SWING_DAMAGE from player). Windfury procs only on white swings, not on WF hits.
local function RecordEligibleSwing()
    for _, st in ipairs({ wfPull, wfSession }) do
        st.swings = (st.swings or 0) + 1
    end
    ScheduleWindfuryUpdate()
    SaveWindfuryDB()
end

-- Flush current proc buffer into pull/session: min/max/total are per-PROC (sum of hits), not per hit.
local function FlushWindfuryProc()
    if not wfProcBuffer or wfProcBuffer.total <= 0 then return end
    local procTotal = wfProcBuffer.total
    local hits = wfProcBuffer.hits
    local crits = wfProcBuffer.crits
    wfProcBuffer.total, wfProcBuffer.hits, wfProcBuffer.crits = 0, 0, 0
    for _, st in ipairs({ wfPull, wfSession }) do
        st.total = st.total + procTotal
        st.count = (st.count or 0) + hits
        if st.min == nil or procTotal < st.min then st.min = procTotal end
        if st.max == nil or procTotal > st.max then st.max = procTotal end
        if crits and crits > 0 then st.crits = (st.crits or 0) + crits end
    end
    ScheduleWindfuryUpdate()
    SaveWindfuryDB()
    -- Refresh satellite numbers so new stats show immediately
    if ShammyTime.UpdateSatelliteValues and ShammyTime_Windfury_GetStats then
        ShammyTime.UpdateSatelliteValues(ShammyTime_Windfury_GetStats())
    end
end

-- Record one Windfury hit (amount, isCrit). Buffers hits; on proc end (timer or next proc) flushes combined total for min/max/total/avg.
-- One proc = 1 or 2 hits; min/max/avg are the sum of those hits per proc.
local WF_PROC_WINDOW = 0.4
local function RecordWindfuryHit(amount, isCrit)
    if not amount or amount <= 0 then return end
    if isCrit then ShammyTime.lastProcHadCrit = true end  -- for center ring "Windfury! CRITICAL!"
    local now = GetTime()
    local isNewProc = (now - lastWfHitTime) > WF_PROC_WINDOW
    lastWfHitTime = now
    -- If starting a new proc, flush the previous proc's combined total first
    if isNewProc and wfProcBuffer.total > 0 then
        FlushWindfuryProc()
    end
    wfProcBuffer.total = wfProcBuffer.total + amount
    wfProcBuffer.hits = wfProcBuffer.hits + 1
    if isCrit then wfProcBuffer.crits = wfProcBuffer.crits + 1 end
    for _, st in ipairs({ wfPull, wfSession }) do
        if isNewProc then st.procs = (st.procs or 0) + 1 end
    end
    ScheduleWindfuryUpdate()
    SaveWindfuryDB()
    -- When proc window closes (0.4s after last hit), flush so 1-hit procs get committed to min/max/avg
    if wfPopupTimer then wfPopupTimer:Cancel() end
    wfPopupTimer = C_Timer.NewTimer(0.4, function()
        wfPopupTimer = nil
        if wfProcBuffer.total > 0 then FlushWindfuryProc() end
    end)
end

-- Reset pull stats (call when entering combat). Clear proc buffer so new pull starts clean.
local function ResetWindfuryPull()
    wfPull.total, wfPull.count, wfPull.procs, wfPull.min, wfPull.max, wfPull.crits, wfPull.swings = 0, 0, 0, nil, nil, 0, 0
    wfProcBuffer.total, wfProcBuffer.hits, wfProcBuffer.crits = 0, 0, 0
    if wfPopupTimer then
        wfPopupTimer:Cancel()
        wfPopupTimer = nil
    end
    if ShammyTime.ResetWindfuryProcWindow then ShammyTime.ResetWindfuryProcWindow() end
    ScheduleWindfuryUpdate()
    SaveWindfuryDB()
    if ShammyTime.UpdateSatelliteValues and ShammyTime_Windfury_GetStats then
        ShammyTime.UpdateSatelliteValues(ShammyTime_Windfury_GetStats())
    end
end

-- Reset session stats (and pull). Also clear proc buffer so next hit starts fresh.
local function ResetWindfurySession()
    wfPull.total, wfPull.count, wfPull.procs, wfPull.min, wfPull.max, wfPull.crits, wfPull.swings = 0, 0, 0, nil, nil, 0, 0
    wfSession.total, wfSession.count, wfSession.procs, wfSession.min, wfSession.max, wfSession.crits, wfSession.swings = 0, 0, 0, nil, nil, 0, 0
    wfProcBuffer.total, wfProcBuffer.hits, wfProcBuffer.crits = 0, 0, 0
    if wfPopupTimer then
        wfPopupTimer:Cancel()
        wfPopupTimer = nil
    end
    if ShammyTime.ResetWindfuryProcWindow then ShammyTime.ResetWindfuryProcWindow() end
    ScheduleWindfuryUpdate()
    SaveWindfuryDB()
    if ShammyTime.UpdateSatelliteValues and ShammyTime_Windfury_GetStats then
        ShammyTime.UpdateSatelliteValues(ShammyTime_Windfury_GetStats())
    end
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
    FlushWindfuryProc()  -- commit this proc so min/max/avg reflect combined total
    if wfPopupTimer then wfPopupTimer:Cancel() wfPopupTimer = nil end
    ShammyTime.lastProcTotal = total  -- so radial/satellites and GetWindfuryStats() show this proc
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
    UpdateAllElementsFadeState()
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
    ShammyTime.radialNumbersVisible = true
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
    ShammyTime.radialNumbersVisible = false
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
    -- Cancel proc-based fade timers so numbers don't disappear while hovering
    local center = _G.ShammyTimeCenterRing
    if center then
        if center.wfTextFadeTimer then
            center.wfTextFadeTimer:Cancel()
            center.wfTextFadeTimer = nil
        end
        if center.wfFadeDelayTimer then
            center.wfFadeDelayTimer:Cancel()
            center.wfFadeDelayTimer = nil
        end
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
-- GetDB is provided by ShammyTime_Core.lua

-- Center circle size (diameter in pixels); used by CenterRing and SatelliteRings for tangent spacing
function ShammyTime.GetCenterSize()
    local db = GetDB()
    local s = db.wfCenterSize
    if s and s > 0 then return s end
    return 200
end

ShammyTime.ResetWindfurySession = ResetWindfurySession
ShammyTime.ShowWindfuryRadial = ShowWindfuryRadial
ShammyTime.HideWindfuryRadial = HideWindfuryRadial
ShammyTime.FlushWindfuryProc = FlushWindfuryProc  -- commit current proc buffer so min/max/avg include this proc (e.g. when radial opens)

-- When an element is hidden (not shown or alpha 0): click-through so no right-click/drag. When visible: circle keeps mouse for right-click reset; others follow lock.
local function ApplyElementMouseState()
    local db = GetDB()
    local useMouse = not db.locked
    local function visible(f) return f and f:IsShown() and (f:GetAlpha() or 1) >= 0.01 end
    local center = _G.ShammyTimeCenterRing
    if center then
        center:EnableMouse(visible(center) and true or false)
    end
    if ShammyTime.EnsureWindfuryTotemBarFrame then
        local bar = ShammyTime.EnsureWindfuryTotemBarFrame()
        if bar then bar:EnableMouse(visible(bar) and useMouse or false) end
    end
    local focusFrame = ShammyTime.GetShamanisticFocusFrame and ShammyTime.GetShamanisticFocusFrame()
    if focusFrame then focusFrame:EnableMouse(visible(focusFrame) and useMouse or false) end
    if ShammyTime.EnsureImbueBarFrame then
        local imbueBar = ShammyTime.EnsureImbueBarFrame()
        if imbueBar then imbueBar:EnableMouse(visible(imbueBar) and useMouse or false) end
    end
    if ShammyTime.EnsureShieldFrame then
        local shieldFrame = ShammyTime.EnsureShieldFrame()
        if shieldFrame then shieldFrame:EnableMouse(visible(shieldFrame) and useMouse or false) end
    end
    if ShammyTime.SetSatellitesEnableMouse then
        ShammyTime.SetSatellitesEnableMouse(visible(center) and useMouse or false)
    end
end

function ApplyLockStateToAllFrames()
    ApplyElementMouseState()
end
ShammyTime.ApplyElementMouseState = ApplyElementMouseState

-- Apply show/hide for each element based on enabled flags (/st show X on|off).
-- Treat nil as enabled so old profiles without these keys show all elements.
local function ApplyElementVisibility()
    local db = GetDB()
    local function enabled(key) return (db[key] ~= false) end
    -- Circle (center + satellites)
    if enabled("wfRadialEnabled") then
        if ShammyTime.ShowWindfuryRadial then ShammyTime.ShowWindfuryRadial() end
    else
        if ShammyTime.HideWindfuryRadial then ShammyTime.HideWindfuryRadial() end
    end
    -- Totem bar
    if ShammyTime.EnsureWindfuryTotemBarFrame then
        local bar = ShammyTime.EnsureWindfuryTotemBarFrame()
        if bar then
            if enabled("wfTotemBarEnabled") then bar:Show() else bar:Hide() end
        end
    end
    -- Shamanistic Focus
    local focusFrame = ShammyTime.GetShamanisticFocusFrame and ShammyTime.GetShamanisticFocusFrame()
    if focusFrame then
        if enabled("wfFocusEnabled") then focusFrame:Show() else focusFrame:Hide() end
    end
    -- Imbue bar
    if ShammyTime.EnsureImbueBarFrame then
        local imbueBar = ShammyTime.EnsureImbueBarFrame()
        if imbueBar then
            if enabled("wfImbueBarEnabled") then imbueBar:Show() else imbueBar:Hide() end
        end
    end
    -- Lightning/Water Shield indicator (standalone)
    if ShammyTime.EnsureShieldFrame then
        local shieldFrame = ShammyTime.EnsureShieldFrame()
        if shieldFrame then
            if enabled("wfShieldEnabled") then shieldFrame:Show() else shieldFrame:Hide() end
        end
    end
    ApplyElementMouseState()
end
ShammyTime.ApplyElementVisibility = ApplyElementVisibility

-- Animate a frame's alpha to target over duration (used for slow fade when wfFadeOutOfCombat is on). Stops any in-progress fade on the frame.
local function AnimateFrameToAlpha(frame, targetAlpha, duration)
    if not frame or not frame.CreateAnimationGroup then return end
    if frame._stFadeAg then
        frame._stFadeAg:Stop()
        frame._stFadeAg = nil
    end
    local fromAlpha = frame:GetAlpha()
    if math.abs((fromAlpha or 1) - targetAlpha) < 0.01 then
        frame:SetAlpha(targetAlpha)
        frame._stFadeTarget = targetAlpha
        return
    end
    frame._stFadeTarget = targetAlpha
    local ag = frame:CreateAnimationGroup()
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(fromAlpha)
    anim:SetToAlpha(targetAlpha)
    anim:SetDuration(duration)
    anim:SetSmoothing("OUT")
    ag:SetScript("OnFinished", function()
        frame:SetAlpha(targetAlpha)
        if frame._stFadeAg == ag then frame._stFadeAg = nil end
        if targetAlpha < 0.01 and ShammyTime.ApplyElementMouseState then ShammyTime.ApplyElementMouseState() end
    end)
    ag:SetScript("OnStop", function()
        if frame._stFadeAg == ag then frame._stFadeAg = nil end
    end)
    frame._stFadeAg = ag
    ag:Play()
end

-- Set alpha on frame; when useSlowFade and target changed, animate over duration instead of instant.
local function SetOrAnimateFade(frame, targetAlpha, useSlowFade, fadeOut)
    if not frame then return end
    -- When restoring to full opacity, force update if frame is currently faded (fixes focus/imbue staying transparent after turning "fade out of combat" off)
    if targetAlpha >= 0.99 and (frame:GetAlpha() or 1) < 0.5 then
        frame._stFadeTarget = nil
    end
    if frame._stFadeTarget and math.abs(frame._stFadeTarget - targetAlpha) < 0.01 then return end
    local duration = useSlowFade and (fadeOut and FADE_ANIM_OUT_DURATION or FADE_ANIM_IN_DURATION) or 0
    if duration > 0 then
        AnimateFrameToAlpha(frame, targetAlpha, duration)
    else
        if frame._stFadeAg then
            frame._stFadeAg:Stop()
            frame._stFadeAg = nil
        end
        frame:SetAlpha(targetAlpha)
        frame._stFadeTarget = targetAlpha
    end
end

-- True if player has at least one totem in any slot.
local function HasAnyTotem()
    for slot = 1, 4 do
        local _, totemName = GetTotemInfo(slot)
        if totemName and totemName ~= "" then return true end
    end
    return false
end

-- True if any weapon imbue has remaining time <= thresholdSec (used for "fade imbue bar unless short time left").
local function AnyImbueRemainingUnder(thresholdSec)
    local hands = ShammyTime.GetWeaponImbuePerHand and ShammyTime.GetWeaponImbuePerHand()
    if not hands or not thresholdSec or thresholdSec <= 0 then return false end
    local now = GetTime()
    for _, hand in pairs(hands) do
        if hand and hand.expirationTime and type(hand.expirationTime) == "number" then
            local remaining = hand.expirationTime - now
            if remaining <= thresholdSec then return true end
        end
    end
    return false
end

-- Fade state: apply "fade out of combat", "fade when not procced", and "fade when no totems" to all elements. Uses slow fade animations when wfFadeOutOfCombat is on.
-- When profile.modules[moduleName].fade.enabled is set, uses ShammyTime:EvaluateFade(moduleName, context) for per-module conditions.
function UpdateAllElementsFadeState()
    -- During Play Demo, keep all elements visible at full alpha
    if ShammyTime.demoActive then
        local center = _G.ShammyTimeCenterRing
        if center then center:Show(); center:SetAlpha(1) end
        if ShammyTime.SetSatelliteFadeAlpha then ShammyTime.SetSatelliteFadeAlpha(1) end
        if ShammyTime.EnsureWindfuryTotemBarFrame then
            local bar = ShammyTime.EnsureWindfuryTotemBarFrame()
            if bar then bar:Show(); bar:SetAlpha(1) end
        end
        local focusFrame = ShammyTime.GetShamanisticFocusFrame and ShammyTime.GetShamanisticFocusFrame()
        if focusFrame then focusFrame:Show(); focusFrame:SetAlpha(1) end
        if ShammyTime.EnsureImbueBarFrame then
            local imbue = ShammyTime.EnsureImbueBarFrame()
            if imbue then imbue:Show(); imbue:SetAlpha(1) end
        end
        if ShammyTime.EnsureShieldFrame then
            local shield = ShammyTime.EnsureShieldFrame()
            if shield then shield:Show(); shield:SetAlpha(1) end
        end
        ApplyElementMouseState()
        return
    end
    local db = GetDB()
    if db.wfAlwaysShowNumbers then
        ShammyTime.radialNumbersVisible = true
    end
    local inCombat = UnitAffectingCombat and UnitAffectingCombat("player")
    if inCombat == nil then inCombat = false end
    local fadedCombat = db.wfFadeOutOfCombat and not inCombat
    local useSlowFade = db.wfFadeOutOfCombat or db.wfFadeWhenNotProcced or db.wfFadeWhenNoTotems or db.wfFocusFadeWhenNotProcced or db.wfImbueFadeWhenLongDuration
    local alphaWf = 1
    -- Circle: when "fade when not procced" is on, only show for a short window after an actual proc (not on combat/totem)
    local recentWfProc = (GetTime() - lastWfProcEndTime) < FADE_GRACE_AFTER_PROC
    local circleShowSec = db.wfFadeWhenNotProcced and CIRCLE_SHOW_AFTER_PROC_SEC or FADE_GRACE_AFTER_PROC
    local circleRecentProc = (GetTime() - lastWfProcEndTime) < circleShowSec
    local wfProcced = (not db.wfFadeWhenNotProcced and db.wfRadialShown) or circleRecentProc
    if fadedCombat then
        alphaWf = FADE_OUT_OF_COMBAT_ALPHA
    elseif db.wfFadeWhenNotProcced and not wfProcced then
        alphaWf = FADE_ALPHA
    end
    local procAnimPlaying = ShammyTime.IsWindfuryProcAnimationPlaying and ShammyTime.IsWindfuryProcAnimationPlaying()
    local hasTarget = UnitExists and UnitExists("target")
    local hasTotems = HasAnyTotem()
    local hasFocusBuff = ShammyTime.HasFocusedBuff and ShammyTime.HasFocusedBuff()
    local imbueProcced = ShammyTime.HasAnyWeaponImbue and ShammyTime.HasAnyWeaponImbue()
    local imbueShortTime = AnyImbueRemainingUnder(db.wfImbueFadeThresholdSec or 120)
    local hasShield = (ShammyTime.GetElementalShieldAura and ShammyTime.GetElementalShieldAura()) and true or false
    local anyTotemOutOfRange = false
    if ShammyTime.GetTotemSlotData then
        for slot = 1, 4 do
            local data = ShammyTime.GetTotemSlotData(slot)
            if data and data.rangeState == "out" then anyTotemOutOfRange = true; break end
        end
    end
    local fadeContext = {
        inCombat = inCombat,
        hasTarget = hasTarget,
        hasTotems = hasTotems,
        noTotemsFaded = noTotemsFaded,
        focusActive = hasFocusBuff,
        imbueActive = imbueProcced,
        imbueShortTime = imbueShortTime,
        wfProcced = wfProcced,
        procAnimPlaying = procAnimPlaying,
        outOfRange = anyTotemOutOfRange,
        hasShield = hasShield,
    }
    local useModuleFade = ShammyTime.EvaluateFade and ShammyTime.db and ShammyTime.db.profile and ShammyTime.db.profile.modules

    -- Circle (center + satellites): only visible when procced or toggled on; not affected by no-totems fade. While proc animation is playing, always show at full alpha. After animation + 2s hold, fade out slowly (never blink/hide).
    local center = _G.ShammyTimeCenterRing
    if not db.wfRadialEnabled then
        if center then center:Hide() end
        if ShammyTime.HideAllSatellites then ShammyTime.HideAllSatellites() end
    else
        -- Lock fade-out as soon as we're not procced (not just when alpha < 0.01) so we never briefly restore to 1 during fade = no blink
        if not procAnimPlaying and not wfProcced then circleFadeOutStarted = true end
        -- Reset circleFadeOutStarted when circle should be shown (e.g. when fade rules are turned off and wfRadialShown is true)
        if wfProcced then circleFadeOutStarted = false end
        local currentAlpha = (center and center.GetAlpha and center:GetAlpha()) or 0
        local circleAlpha, circleFadeOut, circleUseSlowFade, holdHover
        local mod = useModuleFade and ShammyTime.db.profile.modules.windfuryBubbles
        local useModulePath = mod and true
        if useModulePath and ShammyTime.EvaluateFade then
            if mod.fade and mod.fade.enabled then
                local shouldFade, targetAlpha, useSlowMod = ShammyTime:EvaluateFade("windfuryBubbles", fadeContext)
                circleAlpha = procAnimPlaying and 1 or (shouldFade and targetAlpha or 1)
                circleFadeOut = circleAlpha < 1
                holdHover = ShammyTime.circleHovered and currentAlpha >= 0.01 and circleFadeOut and not procAnimPlaying
                if holdHover then circleAlpha = currentAlpha; circleFadeOut = false end
                circleUseSlowFade = (not holdHover) and useSlowMod and circleFadeOut
            else
                -- Panel: fade disabled = show at full alpha (don't fall back to legacy flat keys)
                circleAlpha = 1
                circleFadeOut = false
                holdHover = false
                circleUseSlowFade = false
            end
        else
            circleAlpha = procAnimPlaying and 1 or (circleFadeOutStarted and 0 or (wfProcced and alphaWf or 0))
            circleFadeOut = circleAlpha < 1
            holdHover = ShammyTime.circleHovered and currentAlpha >= 0.01 and circleFadeOut and not procAnimPlaying
            if holdHover then
                circleAlpha = currentAlpha
                circleFadeOut = false
            end
            circleUseSlowFade = (not holdHover) and useSlowFade and circleFadeOut
        end
        local effAlphaWf = (ShammyTime.GetModuleEffectiveAlpha and ShammyTime.GetModuleEffectiveAlpha("windfuryBubbles")) or 1
        if center then
            center:Show()
            SetOrAnimateFade(center, effAlphaWf * circleAlpha, circleUseSlowFade, circleFadeOut)
            -- Satellites: only when center exists; deferred retry next frame so they're not missing when center was just created
            if circleAlpha >= 0.01 and ShammyTime.ShowAllSatellites then
                ShammyTime.ShowAllSatellites()
                C_Timer.After(0, function()
                    if center and center:IsShown() and (center:GetAlpha() or 0) >= 0.01 and ShammyTime.ShowAllSatellites then
                        ShammyTime.ShowAllSatellites()
                    end
                end)
            end
        end
        if holdHover then
            if ShammyTime.SetSatelliteFadeAlpha then ShammyTime.SetSatelliteFadeAlpha(effAlphaWf * circleAlpha) end
        else
            if ShammyTime.AnimateSatellitesToAlpha then
                ShammyTime.AnimateSatellitesToAlpha(effAlphaWf * circleAlpha, circleUseSlowFade and FADE_ANIM_OUT_DURATION or 0)
            else
                if ShammyTime.SetSatelliteFadeAlpha then ShammyTime.SetSatelliteFadeAlpha(effAlphaWf * circleAlpha) end
            end
        end
    end
    -- Totem bar: show when (have totems) OR (in combat); otherwise fade when no totems + out of combat
    if ShammyTime.EnsureWindfuryTotemBarFrame then
        local bar = ShammyTime.EnsureWindfuryTotemBarFrame()
        if bar then
            if not db.wfTotemBarEnabled then bar:Hide()
            else
                local totemBarAlpha, totemBarFadeOut, totemUseSlow
                local mod = useModuleFade and ShammyTime.db.profile.modules.totemBar
                if mod and ShammyTime.EvaluateFade then
                    if mod.fade and mod.fade.enabled then
                        local shouldFade, targetAlpha, useSlowMod = ShammyTime:EvaluateFade("totemBar", fadeContext)
                        totemBarAlpha = shouldFade and targetAlpha or 1
                        totemBarFadeOut = shouldFade
                        totemUseSlow = useSlowMod
                    else
                        totemBarAlpha = 1
                        totemBarFadeOut = false
                        totemUseSlow = false
                    end
                else
                    if hasTotems then
                        totemBarAlpha = 1
                    else
                        totemBarAlpha = noTotemsFaded and NO_TOTEMS_FADE_ALPHA or alphaWf
                    end
                    totemBarFadeOut = totemBarAlpha < 1
                    totemUseSlow = useSlowFade
                end
                bar:Show()
                local effAlphaBar = (ShammyTime.GetModuleEffectiveAlpha and ShammyTime.GetModuleEffectiveAlpha("totemBar")) or 1
                SetOrAnimateFade(bar, effAlphaBar * totemBarAlpha, totemUseSlow, totemBarFadeOut)
            end
        end
    end
    local focusFrame = ShammyTime.GetShamanisticFocusFrame and ShammyTime.GetShamanisticFocusFrame()
    if focusFrame then
        if not db.wfFocusEnabled then focusFrame:Hide()
        else
            local testActive = ShammyTime.IsShamanisticFocusTestActive and ShammyTime.IsShamanisticFocusTestActive()
            local focusFaded, focusAlpha, focusUseSlow
            if testActive then
                focusFaded = false
                focusAlpha = 1
                focusUseSlow = useSlowFade
            else
                local mod = useModuleFade and ShammyTime.db.profile.modules.shamanisticFocus
                if mod and ShammyTime.EvaluateFade then
                    if mod.fade and mod.fade.enabled then
                        local shouldFade, targetAlpha, useSlowMod = ShammyTime:EvaluateFade("shamanisticFocus", fadeContext)
                        focusFaded = shouldFade
                        focusAlpha = shouldFade and targetAlpha or 1
                        focusUseSlow = useSlowMod
                    else
                        focusFaded = false
                        focusAlpha = 1
                        focusUseSlow = false
                    end
                else
                    focusFaded = fadedCombat or db.wfFocusFadeWhenNotProcced
                    focusAlpha = focusFaded and (fadedCombat and FADE_OUT_OF_COMBAT_ALPHA or FADE_ALPHA) or 1
                    focusUseSlow = useSlowFade
                end
            end
            -- If focus just turned off, hold frame fade until on->off transition completes
            local holdUntil = ShammyTime.focusFadeHoldUntil
            if holdUntil and GetTime() < holdUntil and focusFaded then
                focusFaded = false
                focusAlpha = 1
            end
            focusFrame:Show()
            local effAlphaFocus = (ShammyTime.GetModuleEffectiveAlpha and ShammyTime.GetModuleEffectiveAlpha("shamanisticFocus")) or 1
            SetOrAnimateFade(focusFrame, effAlphaFocus * focusAlpha, focusUseSlow, focusFaded)
            -- Sync "on/off" overlay: pass our computed hasFocusBuff so focus shows "on" even if UNIT_AURA/event order lags.
            if (not testActive) and ShammyTime.UpdateShamanisticFocusVisual then
                ShammyTime.UpdateShamanisticFocusVisual(hasFocusBuff)
            end
        end
    end
    local imbueBar = ShammyTime.EnsureImbueBarFrame and ShammyTime.EnsureImbueBarFrame()
    if imbueBar then
        if not db.wfImbueBarEnabled then imbueBar:Hide()
        else
            local imbueFaded, imbueAlpha, imbueUseSlow
            local mod = useModuleFade and ShammyTime.db.profile.modules.weaponImbueBar
            if mod and ShammyTime.EvaluateFade then
                if mod.fade and mod.fade.enabled then
                    local shouldFade, targetAlpha, useSlowMod = ShammyTime:EvaluateFade("weaponImbueBar", fadeContext)
                    imbueFaded = shouldFade
                    imbueAlpha = shouldFade and targetAlpha or 1
                    imbueUseSlow = useSlowMod
                else
                    imbueFaded = false
                    imbueAlpha = 1
                    imbueUseSlow = false
                end
            else
                if not imbueProcced then
                    imbueFaded = fadedCombat
                else
                    imbueFaded = fadedCombat or (db.wfFadeWhenNotProcced and not imbueProcced) or (db.wfImbueFadeWhenLongDuration and not imbueShortTime)
                end
                imbueAlpha = imbueFaded and (fadedCombat and FADE_OUT_OF_COMBAT_ALPHA or FADE_ALPHA) or 1
                imbueUseSlow = useSlowFade
            end
            imbueBar:Show()
            if imbueAlpha >= 0.99 and ShammyTime.RefreshImbueBar then ShammyTime.RefreshImbueBar() end
            local effAlphaImbue = (ShammyTime.GetModuleEffectiveAlpha and ShammyTime.GetModuleEffectiveAlpha("weaponImbueBar")) or 1
            SetOrAnimateFade(imbueBar, effAlphaImbue * imbueAlpha, imbueUseSlow, imbueFaded)
        end
    end
    -- Shield indicator: per-module fade when enabled; otherwise full alpha
    if ShammyTime.EnsureShieldFrame and db.wfShieldEnabled then
        local shieldFrame = ShammyTime.EnsureShieldFrame()
        if shieldFrame then
            shieldFrame:Show()
            local effAlphaShield = (ShammyTime.GetModuleEffectiveAlpha and ShammyTime.GetModuleEffectiveAlpha("shieldIndicator")) or 1
            local mod = useModuleFade and ShammyTime.db.profile.modules.shieldIndicator
            if mod and ShammyTime.EvaluateFade then
                if mod.fade and mod.fade.enabled then
                    local shouldFade, targetAlpha, useSlowMod = ShammyTime:EvaluateFade("shieldIndicator", fadeContext)
                    SetOrAnimateFade(shieldFrame, effAlphaShield * (shouldFade and targetAlpha or 1), useSlowMod, shouldFade)
                else
                    SetOrAnimateFade(shieldFrame, effAlphaShield, false, false)
                end
            else
                SetOrAnimateFade(shieldFrame, effAlphaShield, false, false)
            end
        end
    end
    -- Hidden or faded (alpha 0) elements: click-through so no right-click/drag
    ApplyElementMouseState()
end

-- Call when a WF proc is detected (circle about to show) so "fade when not procced" sees a recent proc and shows the circle.
function ShammyTime.NotifyWindfuryProcStarted()
    lastWfProcEndTime = GetTime()
    circleFadeOutStarted = false
end

-- Request a one-shot fade refresh (used by Focus to start frame fade after on->off transition)
function ShammyTime.RequestFocusFadeUpdate(delay)
    if focusFadeHoldTimer then
        focusFadeHoldTimer:Cancel()
        focusFadeHoldTimer = nil
    end
    local d = delay or 0
    focusFadeHoldTimer = C_Timer.NewTimer(d, function()
        focusFadeHoldTimer = nil
        UpdateAllElementsFadeState()
    end)
end

function ShammyTime.OnWindfuryProcAnimEnd()
    lastWfProcEndTime = GetTime()
    if fadeGraceTimer then fadeGraceTimer:Cancel(); fadeGraceTimer = nil end
    fadeGraceTimer = C_Timer.NewTimer(FADE_GRACE_AFTER_PROC, function()
        fadeGraceTimer = nil
        UpdateAllElementsFadeState()
    end)
    UpdateAllElementsFadeState()
end

-- Called from UpdateAllSlots / PLAYER_TOTEM_UPDATE: start or cancel no-totems fade timer; when totem placed, clear noTotemsFaded and refresh fade state.
function UpdateNoTotemsFadeState()
    local db = GetDB()
    if not db.wfFadeWhenNoTotems then
        if noTotemsFadeTimer then
            noTotemsFadeTimer:Cancel()
            noTotemsFadeTimer = nil
        end
        noTotemsFaded = false
        UpdateAllElementsFadeState()
        return
    end
    if HasAnyTotem() then
        if noTotemsFadeTimer then
            noTotemsFadeTimer:Cancel()
            noTotemsFadeTimer = nil
        end
        if noTotemsFaded then
            noTotemsFaded = false
            UpdateAllElementsFadeState()
        end
        return
    end
    -- No totems: start delay timer if not already running
    if not noTotemsFadeTimer then
        local delay = math.max(1, tonumber(db.wfNoTotemsFadeDelay) or 5)
        noTotemsFadeTimer = C_Timer.NewTimer(delay, function()
            noTotemsFadeTimer = nil
            noTotemsFaded = true
            UpdateAllElementsFadeState()
        end)
    end
end

ShammyTime.UpdateAllElementsFadeState = UpdateAllElementsFadeState
ShammyTime.AnimateFrameToAlpha = AnimateFrameToAlpha
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
ShammyTime.GetElementalShieldAura = GetElementalShieldAura

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

function ShammyTime.HasAnyWeaponImbue()
    local hands = ShammyTime.GetWeaponImbuePerHand and ShammyTime.GetWeaponImbuePerHand()
    if not hands then return false end
    return (hands.mainHand and hands.mainHand.expirationTime) or (hands.offHand and hands.offHand.expirationTime)
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

-- Update totem state only (for GetTotemSlotData / Windfury totem bar). No legacy main bar UI.
local function UpdateSlot(slot)
    local haveTotem, totemName, startTime, duration, icon = GetTotemInfo(slot)
    local nowHasTotem = (totemName and totemName ~= "")
    local wasJustPlaced = not lastHadTotem[slot] and nowHasTotem

    if lastHadTotem[slot] and not nowHasTotem then
        totemPosition[slot] = nil
        lastTotemStartTime[slot] = nil
    end
    lastHadTotem[slot] = nowHasTotem
    if nowHasTotem and wasJustPlaced then
        lastTotemPlacedTime[slot] = GetTime()
        ShammyTime.windfurySlotJustPlaced[slot] = true
    end

    if nowHasTotem then
        if lastTotemName[slot] ~= totemName then
            totemPosition[slot] = nil
            lastTotemName[slot] = totemName
        end
        local isNewInstance = (startTime and startTime ~= lastTotemStartTime[slot])
        if isNewInstance then
            totemPosition[slot] = nil
            lastTotemStartTime[slot] = startTime
        end
        if GetTotemPositionRange(totemName) and UnitPosition and (wasJustPlaced or isNewInstance or not totemPosition[slot]) then
            local posY, posX, posZ = UnitPosition("player")
            if posX and posY and posZ then
                totemPosition[slot] = { x = posX, y = posY, z = posZ }
            end
        end
        if not isNewInstance and startTime then
            lastTotemStartTime[slot] = startTime
        end
    else
        totemPosition[slot] = nil
        lastTotemName[slot] = nil
        lastTotemStartTime[slot] = nil
    end
end

local function UpdateAllSlots()
    for slot = 1, 4 do
        UpdateSlot(slot)
    end
    UpdateNoTotemsFadeState()
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
    if not db.windfuryTrackerEnabled then return end
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
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
        UpdateAllSlots()
        -- Show Windfury radial (center ring + satellites) if enabled; always visible unless disabled
        ShowWindfuryRadial()
        C_Timer.After(0, function()
            UpdateNoTotemsFadeState()
            UpdateAllElementsFadeState()
            ApplyElementVisibility()
            ApplyLockStateToAllFrames()
        end)
        print(C.green .. "ShammyTime is enabled." .. C.r .. C.gray .. " Type " .. C.gold .. "/st" .. C.r .. C.gray .. " for settings. Right click on the windfury circle to reset statistics." .. C.r)
    elseif event == "PLAYER_TOTEM_UPDATE" then
        UpdateAllSlots()
    elseif event == "UNIT_AURA" then
        if not eventFrame.RegisterUnitEvent or arg1 == "player" then
            UpdateAllSlots()
            UpdateAllElementsFadeState()
        end
    elseif event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLogWindfury(...)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Reset pull when entering combat so new pull starts fresh; last pull persists out of combat
        if GetDB().windfuryTrackerEnabled then ResetWindfuryPull() end
        UpdateAllElementsFadeState()
    elseif event == "PLAYER_REGEN_ENABLED" then
        UpdateAllElementsFadeState()
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
    print(C.green .. "  QUICK COMMANDS" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "/st options" .. C.r .. C.gray .. "  — Open the settings panel (recommended)" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "/st lock" .. C.r .. C.gray .. " / " .. C.gold .. "/st unlock" .. C.r .. C.gray .. "  — Lock or unlock all frames" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "/st test" .. C.r .. C.gray .. "  — Test mode (run again to stop)" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "/st reset" .. C.r .. C.gray .. "  — Reset all settings to defaults" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "/st print" .. C.r .. C.gray .. "  — Export settings to chat" .. C.r)
    print(C.gray .. "    • " .. C.gold .. "/st dev on|off" .. C.r .. C.gray .. "  — Toggle Developer tab in options" .. C.r)
    print("")
    print(C.gray .. "  For all settings, use " .. C.gold .. "/st options" .. C.r .. C.gray .. " to open the settings panel." .. C.r)
    print(C.gold .. "═══════════════════════════════════════" .. C.r)
    print("")
end

local function PrintAllSettings()
    local db = GetDB()
    print("")
    print(C.gold .. "——— ShammyTime: all current settings (for defaults) ———" .. C.r)
    print(C.gray .. "Show/hide elements:" .. C.r)
    print("  wfRadialEnabled = " .. tostring(db.wfRadialEnabled))
    print("  wfTotemBarEnabled = " .. tostring(db.wfTotemBarEnabled))
    print("  wfFocusEnabled = " .. tostring(db.wfFocusEnabled))
    print("  wfImbueBarEnabled = " .. tostring(db.wfImbueBarEnabled))
    print("  wfShieldEnabled = " .. tostring(db.wfShieldEnabled))
    print("  locked = " .. tostring(db.locked))
    print("  wfRadialShown = " .. tostring(db.wfRadialShown))
    print("  windfuryTrackerEnabled = " .. tostring(db.windfuryTrackerEnabled))
    print(C.gray .. "Fade:" .. C.r)
    print("  wfFadeOutOfCombat = " .. tostring(db.wfFadeOutOfCombat))
    print("  wfFadeWhenNotProcced = " .. tostring(db.wfFadeWhenNotProcced))
    print("  wfFocusFadeWhenNotProcced = " .. tostring(db.wfFocusFadeWhenNotProcced))
    print("  wfFadeWhenNoTotems = " .. tostring(db.wfFadeWhenNoTotems))
    print("  wfNoTotemsFadeDelay = " .. tostring(db.wfNoTotemsFadeDelay))
    print("  wfImbueFadeWhenLongDuration = " .. tostring(db.wfImbueFadeWhenLongDuration))
    print("  wfImbueFadeThresholdSec = " .. tostring(db.wfImbueFadeThresholdSec))
    print(C.gray .. "Bubbles (Windfury circles) — center:" .. C.r)
    print("  wfRadialScale = " .. tostring(db.wfRadialScale))
    print("  wfCenterSize = " .. tostring(db.wfCenterSize))
    print("  wfCenterTextTitleY = " .. tostring(db.wfCenterTextTitleY))
    print("  wfCenterTextTotalY = " .. tostring(db.wfCenterTextTotalY))
    print("  wfCenterTextCriticalY = " .. tostring(db.wfCenterTextCriticalY))
    print("  wfAlwaysShowNumbers = " .. tostring(db.wfAlwaysShowNumbers))
    print(C.gray .. "Bubbles — outer (gap; label/value position X Y in pixels from center of each circle, X +right -left, Y +up -down):" .. C.r)
    print("  wfSatelliteGap = " .. tostring(db.wfSatelliteGap))
    print("  wfSatelliteLabelX = " .. tostring(db.wfSatelliteLabelX) .. "  -- label pos X (nil = 0)")
    print("  wfSatelliteLabelY = " .. tostring(db.wfSatelliteLabelY) .. "  -- label pos Y (nil = 8)")
    print("  wfSatelliteValueX = " .. tostring(db.wfSatelliteValueX) .. "  -- value pos X (nil = 0)")
    print("  wfSatelliteValueY = " .. tostring(db.wfSatelliteValueY) .. "  -- value pos Y (nil = -6)")
    if db.wfSatelliteOverrides and next(db.wfSatelliteOverrides) then
        for bn, ov in pairs(db.wfSatelliteOverrides) do
            if type(ov) == "table" then
                print("  wfSatelliteOverrides[" .. tostring(bn) .. "] = { labelSize=" .. tostring(ov.labelSize) .. ", valueSize=" .. tostring(ov.valueSize) .. ", labelX=" .. tostring(ov.labelX) .. ", labelY=" .. tostring(ov.labelY) .. ", valueX=" .. tostring(ov.valueX) .. ", valueY=" .. tostring(ov.valueY) .. " }")
            end
        end
    else
        print("  wfSatelliteOverrides = " .. tostring(db.wfSatelliteOverrides))
    end
    print(C.gray .. "Font sizes:" .. C.r)
    print("  fontCircleTitle = " .. tostring(db.fontCircleTitle))
    print("  fontCircleTotal = " .. tostring(db.fontCircleTotal))
    print("  fontCircleCritical = " .. tostring(db.fontCircleCritical))
    print("  fontSatelliteLabel = " .. tostring(db.fontSatelliteLabel))
    print("  fontSatelliteValue = " .. tostring(db.fontSatelliteValue))
    print("  fontTotemTimer = " .. tostring(db.fontTotemTimer))
    print("  fontImbueTimer = " .. tostring(db.fontImbueTimer))
    print(C.gray .. "Totem bar:" .. C.r)
    print("  wfTotemBarScale = " .. tostring(db.wfTotemBarScale))
    print(C.gray .. "Imbue bar:" .. C.r)
    print("  imbueBarScale = " .. tostring(db.imbueBarScale))
    print("  imbueBarMargin = " .. tostring(db.imbueBarMargin))
    print("  imbueBarGap = " .. tostring(db.imbueBarGap))
    print("  imbueBarOffsetY = " .. tostring(db.imbueBarOffsetY))
    print("  imbueBarIconSize = " .. tostring(db.imbueBarIconSize))
    -- Helper to get actual frame position (point, relativeTo, relativePoint, x, y)
    local function GetFramePos(frameName)
        local frame = _G[frameName]
        if not frame or not frame.GetPoint then return nil end
        local point, relTo, relPoint, x, y = frame:GetPoint(1)
        if not point then return nil end
        local relToName = (relTo and relTo.GetName and relTo:GetName()) or "UIParent"
        return {
            point = point,
            relativeTo = relToName,
            relativePoint = relPoint,
            x = x and math.floor(x + 0.5) or 0,
            y = y and math.floor(y + 0.5) or 0,
        }
    end
    local function PrintFramePos(label, frameName, savedPos)
        local actual = GetFramePos(frameName)
        if actual then
            local src = savedPos and "(saved)" or "(current)"
            print("  " .. label .. ": " .. src .. " point=\"" .. actual.point .. "\", relativeTo=\"" .. actual.relativeTo .. "\", relativePoint=\"" .. actual.relativePoint .. "\", x=" .. actual.x .. ", y=" .. actual.y)
        elseif savedPos then
            print("  " .. label .. ": (saved) point=\"" .. tostring(savedPos.point) .. "\", relativeTo=\"" .. tostring(savedPos.relativeTo) .. "\", relativePoint=\"" .. tostring(savedPos.relativePoint) .. "\", x=" .. tostring(savedPos.x) .. ", y=" .. tostring(savedPos.y))
        else
            print("  " .. label .. ": (not loaded)")
        end
    end
    print(C.gray .. "Frame positions (actual current offsets; move frames with /st unlock then drag):" .. C.r)
    local posKey = GetRadialPositionKey and GetRadialPositionKey() or ""
    local pos = (db.wfRadialPos and posKey and db.wfRadialPos[posKey]) or {}
    PrintFramePos("center (Windfury circle)", "ShammyTimeCenterRing", pos.center)
    PrintFramePos("totemBar", "ShammyTimeWindfuryTotemBarFrame", pos.totemBar)
    PrintFramePos("imbueBar", "ShammyTimeImbueBarFrame", pos.imbueBar)
    PrintFramePos("shieldFrame", "ShammyTimeShieldFrame", pos.shieldFrame)
    ShammyTimeDB = ShammyTimeDB or {}
    local focusDb = ShammyTimeDB.focusFrame
    PrintFramePos("focusFrame (Shamanistic Focus)", "ShammyTimeShamanisticFocus", focusDb)
    print(C.gray .. "Lightning/Water Shield indicator:" .. C.r)
    print("  wfShieldEnabled = " .. tostring(db.wfShieldEnabled))
    print("  shieldScale = " .. tostring(db.shieldScale) .. "  -- size (0.05–2); /st adv shield size X")
    print("  shieldCount = " .. tostring(db.shieldCount) .. "  -- override charge count (nil = auto; 1–9 = fixed); /st adv shield count X")
    print("  shieldCountX = " .. tostring(db.shieldCountX) .. "  -- number X offset; /st adv shield numx X")
    print("  shieldCountY = " .. tostring(db.shieldCountY) .. "  -- number Y offset; /st adv shield numy Y")
    print(C.gray .. "Shamanistic Focus:" .. C.r)
    local focusScale = (focusDb and focusDb.scale) or 0.8
    print("  scale = " .. tostring(focusScale) .. "  -- /st adv focus scale X")
    print(C.gold .. "——— Copy above to share or use as new defaults ———" .. C.r)
    print("")
end

local function PrintCircleHelp()
    print("")
    print(C.green .. "ShammyTime — Circle (" .. C.gold .. "/st circle" .. C.r .. C.green .. ")" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "on" .. C.r .. C.gray .. "  / " .. C.gold .. "off" .. C.r .. C.gray .. "     — Show or hide circle" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "scale 0.8" .. C.r .. C.gray .. "  — Overall scale (0.5–2)" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "size 200" .. C.r .. C.gray .. "  — Center circle diameter (pixels)" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "gap 0" .. C.r .. C.gray .. "  — Space between center edge and outer bubbles (0=touch, + = apart, − = overlap)" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "text title 13" .. C.r .. C.gray .. "  — Y offset of \"Windfury!\" (pixels from center)" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "text total 0" .. C.r .. C.gray .. "  — Y offset of \"TOTAL: xxx\"" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "text critical 31" .. C.r .. C.gray .. "  — Y offset of \"CRITICAL\"" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "numbers on|off" .. C.r .. C.gray .. "  — Numbers always visible or fade on hover" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "toggle" .. C.r .. C.gray .. "  — Show/hide circle and totem bar" .. C.r)
    print(C.gray .. "  Test: " .. C.gold .. "/st test" .. C.r .. C.gray .. " (global; affects circle, Windfury, focus)" .. C.r)
    print("")
end

local function PrintFontHelp()
    print("")
    print(C.green .. "ShammyTime — Font sizes (" .. C.gold .. "/st font" .. C.r .. C.green .. ")" .. C.r)
    print(C.gray .. "  Set text size per element (6–28). Defaults unchanged until you set." .. C.r)
    print(C.gray .. "  • " .. C.gold .. "circle title 20" .. C.r .. C.gray .. "  — Center ring \"Windfury!\"" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "circle total 14" .. C.r .. C.gray .. "  — Center ring \"TOTAL: xxx\"" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "circle critical 20" .. C.r .. C.gray .. "  — Center \"CRITICAL\" line" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "satellite label 8" .. C.r .. C.gray .. "  — Satellite labels (MIN, CRIT%, etc.)" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "satellite value 13" .. C.r .. C.gray .. "  — Satellite numbers" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "totem 7" .. C.r .. C.gray .. "  — Totem bar timers" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "imbue 20" .. C.r .. C.gray .. "  — Imbue bar timers" .. C.r)
    print(C.gray .. "  Bubbles (Windfury circles): " .. C.gold .. "/st bubbles center" .. C.r .. C.gray .. ", " .. C.gold .. "outer" .. C.r)
    print("")
end

local function PrintShowHelp()
    print("")
    print(C.green .. "ShammyTime — Show / Hide (" .. C.gold .. "/st show" .. C.r .. C.green .. ")" .. C.r)
    print(C.gray .. "  Turn elements on or off. Hidden elements are not shown and ignore fade rules." .. C.r)
    print(C.gray .. "  • " .. C.gold .. "circle on|off" .. C.r .. C.gray .. "  — Windfury circle (center + satellites)" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "totem on|off" .. C.r .. C.gray .. "  — Windfury totem bar" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "focus on|off" .. C.r .. C.gray .. "  — Shamanistic Focus" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "imbue on|off" .. C.r .. C.gray .. "  — Weapon imbue bar" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "shield on|off" .. C.r .. C.gray .. "  — Lightning/Water Shield indicator" .. C.r)
    print("")
end

local function PrintFadeHelp()
    print("")
    print(C.green .. "ShammyTime — Fade (" .. C.gold .. "/st fade" .. C.r .. C.green .. ")" .. C.r)
    print(C.gray .. "  Dim elements when conditions are met. " .. C.gold .. "all on" .. C.r .. C.gray .. " enables all rules at once (default)." .. C.r)
    print(C.gray .. "  • " .. C.gold .. "all on|off" .. C.r .. C.gray .. "  — One toggle: circle (on WF proc), totem (totems or combat), imbue ≤2 min, focus (on proc), out of combat" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "combat on|off" .. C.r .. C.gray .. "  — Fade when out of combat (slow fade)" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "procced on|off" .. C.r .. C.gray .. "  — Fade circle/imbue when not procced" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "focus on|off" .. C.r .. C.gray .. "  — Shamanistic Focus fades when no Focus buff; fades in on proc (default on)" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "imbue on|off" .. C.r .. C.gray .. "  — Imbue bar fades unless at least one imbue has ≤ threshold left (default 2 min)" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "imbueduration 120" .. C.r .. C.gray .. "  — Show imbue bar when any imbue has this many seconds or less left (60–600)" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "nototems on|off" .. C.r .. C.gray .. "  — Fade totem bar when no totems (after delay); placing a totem fades back in" .. C.r)
    print(C.gray .. "  • " .. C.gold .. "nototemsdelay 5" .. C.r .. C.gray .. "  — Seconds with no totems before fade (1–30)" .. C.r)
    print("")
end

local function PrintAdvHelp()
    print("")
    print(C.green .. "ShammyTime — Advanced (" .. C.gold .. "/st adv" .. C.r .. C.green .. ")" .. C.r)
    print(C.gray .. "  Fine‑tune sizes, positions, and layout per element. Use " .. C.gold .. "/st test" .. C.r .. C.gray .. " to see effects." .. C.r)
    print("")
    print(C.gray .. "  " .. C.gold .. "totembar" .. C.r .. C.gray .. "  — Windfury totem bar: scale, timer font." .. C.r)
    print(C.gray .. "  " .. C.gold .. "bubbles" .. C.r .. C.gray .. "   — Windfury circles: " .. C.gold .. "center" .. C.r .. C.gray .. " (size, text, font) or " .. C.gold .. "outer" .. C.r .. C.gray .. " (gap, font, position)." .. C.r)
    print(C.gray .. "  " .. C.gold .. "shield" .. C.r .. C.gray .. "    — Lightning/Water Shield: scale, count override, number X/Y position." .. C.r)
    print(C.gray .. "  " .. C.gold .. "focus" .. C.r .. C.gray .. "     — Shamanistic Focus: scale." .. C.r)
    print(C.gray .. "  " .. C.gold .. "imbue" .. C.r .. C.gray .. "     — Weapon imbue bar: scale, layout (margin, gap, offset, icon size)." .. C.r)
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

    -- Advanced: route /st adv <element> [rest] to /st <mapped> [rest]
    while cmd == "adv" or cmd == "advanced" do
        local elem, rest2 = arg:match("^(%S+)%s*(.*)$")
        elem = elem and elem:lower() or ""
        rest2 = rest2 and rest2:gsub("^%s+", ""):gsub("%s+$", "") or ""
        if elem == "" then
            PrintAdvHelp()
            return
        end
        local mapped
        if elem == "totembar" or elem == "totem" then mapped = "totem"
        elseif elem == "bubbles" then mapped = "bubbles"
        elseif elem == "shield" then mapped = "shield"
        elseif elem == "focus" then mapped = "focus"
        elseif elem == "imbue" then mapped = "imbue"
        else
            print(C.red .. "ShammyTime: Unknown advanced element '" .. elem .. "'. Use: totembar, bubbles, shield, focus, imbue." .. C.r)
            PrintAdvHelp()
            return
        end
        cmd, arg = mapped, rest2
    end

    -- Global: lock / unlock (all bars)
    if cmd == "lock" then
        db.locked = true
        db.wfLocked = true
        ApplyLockStateToAllFrames()
        print(C.green .. "ShammyTime: All bars locked (click-through except right-click reset on circle)." .. C.r)
    elseif cmd == "unlock" or cmd == "move" then
        db.locked = false
        db.wfLocked = false
        ApplyLockStateToAllFrames()
        print(C.green .. "ShammyTime: All bars unlocked — you can drag to move." .. C.r)
    elseif cmd == "reset" then
        if ResetAllToDefaults() then
            print(C.green .. "ShammyTime: All settings and positions reset to defaults." .. C.r)
        end
    elseif cmd == "print" or cmd == "defaults" or cmd == "export" then
        if ShammyTime.ExportSettings then ShammyTime.ExportSettings() else PrintAllSettings() end
    -- Open options panel
    elseif cmd == "options" or cmd == "config" or cmd == "settings" or cmd == "opt" then
        if Settings and Settings.OpenToCategory then
            Settings.OpenToCategory("ShammyTime")
        elseif InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory("ShammyTime")
            InterfaceOptionsFrame_OpenToCategory("ShammyTime")  -- call twice for Blizzard bug
        end
        print(C.green .. "ShammyTime: Options panel opened." .. C.r)
    -- Developer mode toggle
    elseif cmd == "dev" or cmd == "developer" then
        local sub = arg:lower()
        local g = db.global or {}
        if sub == "on" or sub == "enable" or sub == "1" then
            db.global = db.global or {}
            db.global.devMode = true
            print(C.gold .. "ShammyTime: Developer mode ON." .. C.r .. C.gray .. " Open options panel to see Developer tab." .. C.r)
        elseif sub == "off" or sub == "disable" or sub == "0" then
            db.global = db.global or {}
            db.global.devMode = false
            print(C.green .. "ShammyTime: Developer mode OFF." .. C.r)
        else
            local current = (db.global and db.global.devMode) and "ON" or "OFF"
            print(C.gray .. "ShammyTime: Developer mode is " .. C.gold .. current .. C.r .. C.gray .. ". Use " .. C.gold .. "/st dev on" .. C.r .. C.gray .. " or " .. C.gold .. "/st dev off" .. C.r)
        end
    -- Global test: Windfury proc + Shamanistic Focus (one proc immediately, then every 10s). Run /st test again to stop.
    elseif cmd == "test" then
        if wfTestTimer then
            wfTestTimer:Cancel()
            wfTestTimer = nil
            if ShammyTime.StopShamanisticFocusTest then ShammyTime.StopShamanisticFocusTest() end
            print(C.green .. "ShammyTime: Test mode off." .. C.r)
        else
            if ShammyTime.StartShamanisticFocusTest then ShammyTime.StartShamanisticFocusTest() end
            SimulateTestProc()  -- one proc immediately so circle + focus react right away
            wfTestTimer = C_Timer.NewTicker(10, function()
                SimulateTestProc()
            end)
            print(C.green .. "ShammyTime: Test mode on (circle, focus, Windfury). Run " .. C.gold .. "/st test" .. C.r .. C.green .. " again to stop." .. C.r)
        end
    elseif cmd == "debug" then
        DebugWeaponImbue()
    -- Show/hide elements: /st show [circle|totem|focus|imbue] [on|off]
    elseif cmd == "show" then
        local sub, subarg = arg:match("^(%S+)%s*(.*)$")
        sub = sub and sub:lower() or ""
        subarg = subarg and subarg:gsub("^%s+", ""):gsub("%s+$", ""):lower() or ""
        local on = (subarg == "on" or subarg == "enable" or subarg == "1")
        local off = (subarg == "off" or subarg == "disable" or subarg == "0")
        if sub == "circle" then
            if on then db.wfRadialEnabled = true; ApplyElementVisibility(); UpdateAllElementsFadeState(); print(C.green .. "ShammyTime: Circle shown." .. C.r)
            elseif off then db.wfRadialEnabled = false; ApplyElementVisibility(); UpdateAllElementsFadeState(); print(C.green .. "ShammyTime: Circle hidden." .. C.r)
            else print(C.gray .. "ShammyTime: Circle " .. (db.wfRadialEnabled and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)) .. C.gray .. ". " .. C.gold .. "/st show circle on|off" .. C.r) end
        elseif sub == "totem" then
            if on then db.wfTotemBarEnabled = true; UpdateAllElementsFadeState(); print(C.green .. "ShammyTime: Totem bar shown." .. C.r)
            elseif off then db.wfTotemBarEnabled = false; UpdateAllElementsFadeState(); print(C.green .. "ShammyTime: Totem bar hidden." .. C.r)
            else print(C.gray .. "ShammyTime: Totem bar " .. (db.wfTotemBarEnabled and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)) .. C.gray .. ". " .. C.gold .. "/st show totem on|off" .. C.r) end
        elseif sub == "focus" then
            if on then db.wfFocusEnabled = true; UpdateAllElementsFadeState(); print(C.green .. "ShammyTime: Shamanistic Focus shown." .. C.r)
            elseif off then db.wfFocusEnabled = false; UpdateAllElementsFadeState(); print(C.green .. "ShammyTime: Shamanistic Focus hidden." .. C.r)
            else print(C.gray .. "ShammyTime: Focus " .. (db.wfFocusEnabled and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)) .. C.gray .. ". " .. C.gold .. "/st show focus on|off" .. C.r) end
        elseif sub == "imbue" then
            if on then db.wfImbueBarEnabled = true; UpdateAllElementsFadeState(); print(C.green .. "ShammyTime: Imbue bar shown." .. C.r)
            elseif off then db.wfImbueBarEnabled = false; UpdateAllElementsFadeState(); print(C.green .. "ShammyTime: Imbue bar hidden." .. C.r)
            else print(C.gray .. "ShammyTime: Imbue bar " .. (db.wfImbueBarEnabled and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)) .. C.gray .. ". " .. C.gold .. "/st show imbue on|off" .. C.r) end
        elseif sub == "shield" then
            if on then db.wfShieldEnabled = true; UpdateAllElementsFadeState(); print(C.green .. "ShammyTime: Lightning/Water Shield indicator shown." .. C.r)
            elseif off then db.wfShieldEnabled = false; UpdateAllElementsFadeState(); print(C.green .. "ShammyTime: Lightning/Water Shield indicator hidden." .. C.r)
            else print(C.gray .. "ShammyTime: Shield " .. (db.wfShieldEnabled and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)) .. C.gray .. ". " .. C.gold .. "/st show shield on|off" .. C.r) end
        elseif sub == "" or sub == "list" then
            local c = db.wfRadialEnabled and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)
            local t = db.wfTotemBarEnabled and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)
            local f = db.wfFocusEnabled and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)
            local i = db.wfImbueBarEnabled and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)
            local sh = db.wfShieldEnabled and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)
            print(C.gray .. "ShammyTime: Show — circle " .. c .. C.gray .. ", totem " .. t .. C.gray .. ", focus " .. f .. C.gray .. ", imbue " .. i .. C.gray .. ", shield " .. sh .. C.gray .. ". " .. C.gold .. "/st show <element> on|off" .. C.r)
            PrintShowHelp()
        else
            print(C.red .. "ShammyTime: Unknown element " .. (C.gold .. "'" .. sub .. "'" .. C.r) .. C.red .. ". Use circle, totem, focus, imbue, shield. " .. C.gold .. "/st show" .. C.r .. C.red .. " for list." .. C.r)
            PrintShowHelp()
        end
    -- Scale (simple): resize Windfury circles as a whole (0.5–2). Other elements: /st totem scale, /st focus scale, /st imbue scale.
    elseif cmd == "scale" then
        local num = tonumber(arg:match("^(%S+)"))
        if num and num >= 0.5 and num <= 2 then
            db.wfRadialScale = num
            local center = _G.ShammyTimeCenterRing
            if center then center:SetScale(num) end
            print(C.green .. "ShammyTime: Windfury circles scale " .. ("%.2f"):format(num) .. " (overall size)." .. C.r)
        elseif arg and arg:gsub("^%s+", ""):gsub("%s+$", "") ~= "" then
            print(C.red .. "ShammyTime: Scale 0.5–2. " .. C.gold .. "/st scale 0.8" .. C.r .. C.red .. " — Resizes the Windfury bubbles. Totem/focus/imbue: /st totem scale, /st focus scale, /st imbue scale." .. C.r)
        else
            local s = db.wfRadialScale or 1
            print(C.gray .. "ShammyTime: Windfury circles scale " .. C.gold .. ("%.2f"):format(s) .. C.r .. C.gray .. " (0.5–2). " .. C.gold .. "/st scale 0.8" .. C.r .. C.gray .. " to change. Totem/focus/imbue have their own scale." .. C.r)
        end
    -- Fade: /st fade [combat on|off | procced on|off]
    elseif cmd == "fade" then
        local sub, subarg = arg:match("^(%S+)%s*(.*)$")
        sub = sub and sub:lower() or ""
        subarg = subarg and subarg:gsub("^%s+", ""):gsub("%s+$", ""):lower() or ""
        if sub == "all" then
            if subarg == "on" or subarg == "enable" or subarg == "1" then
                db.wfFadeOutOfCombat = true
                db.wfFadeWhenNotProcced = true
                db.wfFadeWhenNoTotems = true
                db.wfFocusFadeWhenNotProcced = true
                db.wfImbueFadeWhenLongDuration = true
                db.wfImbueFadeThresholdSec = 120
                if ShammyTime.SyncFlatToModules then ShammyTime:SyncFlatToModules() end
                UpdateNoTotemsFadeState()
                UpdateAllElementsFadeState()
                print(C.green .. "ShammyTime: Fade all on — circle (on WF proc), totem bar (totems or combat), imbue (≤2 min), focus (on proc), combat fade." .. C.r)
            elseif subarg == "off" or subarg == "disable" or subarg == "0" then
                db.wfFadeOutOfCombat = false
                db.wfFadeWhenNotProcced = false
                db.wfFadeWhenNoTotems = false
                db.wfFocusFadeWhenNotProcced = false
                db.wfImbueFadeWhenLongDuration = false
                if ShammyTime.SyncFlatToModules then ShammyTime:SyncFlatToModules() end
                UpdateNoTotemsFadeState()
                UpdateAllElementsFadeState()
                print(C.green .. "ShammyTime: Fade all off — all elements always visible (no fade rules)." .. C.r)
            else
                local allOn = db.wfFadeOutOfCombat and db.wfFadeWhenNotProcced and db.wfFadeWhenNoTotems and db.wfFocusFadeWhenNotProcced and db.wfImbueFadeWhenLongDuration
                print(C.gray .. "ShammyTime: Fade all " .. (allOn and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)) .. C.gray .. " — One command to enable/disable all fade rules (circle on proc, totem when totems/combat, imbue ≤2 min, focus on proc, out of combat). " .. C.gold .. "/st fade all on|off" .. C.r)
            end
        elseif sub == "combat" then
            if subarg == "on" or subarg == "enable" or subarg == "1" then
                db.wfFadeOutOfCombat = true
                if ShammyTime.SyncFlatToModules then ShammyTime:SyncFlatToModules() end
                UpdateAllElementsFadeState()
                print(C.green .. "ShammyTime: Fade out of combat on." .. C.r)
            elseif subarg == "off" or subarg == "disable" or subarg == "0" then
                db.wfFadeOutOfCombat = false
                if ShammyTime.SyncFlatToModules then ShammyTime:SyncFlatToModules() end
                UpdateAllElementsFadeState()
                print(C.green .. "ShammyTime: Fade out of combat off." .. C.r)
            else
                print(C.gray .. "ShammyTime: Fade combat " .. (db.wfFadeOutOfCombat and (C.green .. "on" .. C.r) or (C.gray .. "off" .. C.r)) .. C.gray .. ". " .. C.gold .. "/st fade combat on|off" .. C.r)
            end
        elseif sub == "procced" then
            if subarg == "on" or subarg == "enable" or subarg == "1" then
                db.wfFadeWhenNotProcced = true
                if ShammyTime.SyncFlatToModules then ShammyTime:SyncFlatToModules() end
                UpdateAllElementsFadeState()
                print(C.green .. "ShammyTime: Fade when not procced on." .. C.r)
            elseif subarg == "off" or subarg == "disable" or subarg == "0" then
                db.wfFadeWhenNotProcced = false
                if ShammyTime.SyncFlatToModules then ShammyTime:SyncFlatToModules() end
                UpdateAllElementsFadeState()
                print(C.green .. "ShammyTime: Fade when not procced off." .. C.r)
            else
                print(C.gray .. "ShammyTime: Fade procced " .. (db.wfFadeWhenNotProcced and (C.green .. "on" .. C.r) or (C.gray .. "off" .. C.r)) .. C.gray .. ". " .. C.gold .. "/st fade procced on|off" .. C.r)
            end
        elseif sub == "nototems" then
            if subarg == "on" or subarg == "enable" or subarg == "1" then
                db.wfFadeWhenNoTotems = true
                if ShammyTime.SyncFlatToModules then ShammyTime:SyncFlatToModules() end
                UpdateNoTotemsFadeState()
                UpdateAllElementsFadeState()
                print(C.green .. "ShammyTime: Fade when no totems on." .. C.r)
            elseif subarg == "off" or subarg == "disable" or subarg == "0" then
                db.wfFadeWhenNoTotems = false
                if ShammyTime.SyncFlatToModules then ShammyTime:SyncFlatToModules() end
                UpdateNoTotemsFadeState()
                UpdateAllElementsFadeState()
                print(C.green .. "ShammyTime: Fade when no totems off." .. C.r)
            else
                print(C.gray .. "ShammyTime: Fade nototems " .. (db.wfFadeWhenNoTotems and (C.green .. "on" .. C.r) or (C.gray .. "off" .. C.r)) .. C.gray .. ", delay " .. C.gold .. tostring(db.wfNoTotemsFadeDelay or 5) .. "s" .. C.r .. C.gray .. ". " .. C.gold .. "/st fade nototems on|off" .. C.r)
            end
        elseif sub == "focus" then
            if subarg == "on" or subarg == "enable" or subarg == "1" then
                db.wfFocusFadeWhenNotProcced = true
                if ShammyTime.SyncFlatToModules then ShammyTime:SyncFlatToModules() end
                UpdateAllElementsFadeState()
                print(C.green .. "ShammyTime: Shamanistic Focus fades when not procced (on)." .. C.r)
            elseif subarg == "off" or subarg == "disable" or subarg == "0" then
                db.wfFocusFadeWhenNotProcced = false
                if ShammyTime.SyncFlatToModules then ShammyTime:SyncFlatToModules() end
                UpdateAllElementsFadeState()
                print(C.green .. "ShammyTime: Shamanistic Focus always visible (fade when not procced off)." .. C.r)
            else
                print(C.gray .. "ShammyTime: Fade focus " .. (db.wfFocusFadeWhenNotProcced and (C.green .. "on" .. C.r) or (C.gray .. "off" .. C.r)) .. C.gray .. " — Focus icon fades to 0% when no Focus buff, fades in on proc. " .. C.gold .. "/st fade focus on|off" .. C.r)
            end
        elseif sub == "imbue" then
            if subarg == "on" or subarg == "enable" or subarg == "1" then
                db.wfImbueFadeWhenLongDuration = true
                if ShammyTime.SyncFlatToModules then ShammyTime:SyncFlatToModules() end
                UpdateAllElementsFadeState()
                print(C.green .. "ShammyTime: Imbue bar fades unless at least one imbue has ≤ " .. tostring(db.wfImbueFadeThresholdSec or 120) .. " s left." .. C.r)
            elseif subarg == "off" or subarg == "disable" or subarg == "0" then
                db.wfImbueFadeWhenLongDuration = false
                if ShammyTime.SyncFlatToModules then ShammyTime:SyncFlatToModules() end
                UpdateAllElementsFadeState()
                print(C.green .. "ShammyTime: Imbue bar fade (by duration) off." .. C.r)
            else
                local th = db.wfImbueFadeThresholdSec or 120
                print(C.gray .. "ShammyTime: Fade imbue " .. (db.wfImbueFadeWhenLongDuration and (C.green .. "on" .. C.r) or (C.gray .. "off" .. C.r)) .. C.gray .. " — Bar visible when any imbue has ≤ " .. C.gold .. th .. " s" .. C.r .. C.gray .. " left. " .. C.gold .. "/st fade imbue on|off" .. C.r .. C.gray .. ", " .. C.gold .. "/st fade imbueduration 120" .. C.r)
            end
        elseif sub == "imbueduration" then
            local num = tonumber(subarg)
            if num and num >= 60 and num <= 600 then
                db.wfImbueFadeThresholdSec = num
                UpdateAllElementsFadeState()
                print(C.green .. "ShammyTime: Imbue bar shows when any imbue has ≤ " .. num .. " s left." .. C.r)
            else
                print(C.red .. "ShammyTime: Imbue duration 60–600 s (e.g. 120 = 2 min). " .. C.gold .. "/st fade imbueduration 120" .. C.r)
            end
        elseif sub == "nototemsdelay" then
            local num = tonumber(subarg)
            if num and num >= 1 and num <= 30 then
                db.wfNoTotemsFadeDelay = num
                UpdateNoTotemsFadeState()
                print(C.green .. "ShammyTime: No-totems fade delay " .. num .. " s." .. C.r)
            else
                print(C.red .. "ShammyTime: Delay 1–30 s. " .. C.gold .. "/st fade nototemsdelay 5" .. C.r)
            end
        elseif sub == "" then
            local allOn = db.wfFadeOutOfCombat and db.wfFadeWhenNotProcced and db.wfFadeWhenNoTotems and db.wfFocusFadeWhenNotProcced and db.wfImbueFadeWhenLongDuration
            local nt = db.wfFadeWhenNoTotems and (C.green .. "on" .. C.r) or (C.gray .. "off" .. C.r)
            local nd = C.gold .. tostring(db.wfNoTotemsFadeDelay or 5) .. "s" .. C.r
            local foc = db.wfFocusFadeWhenNotProcced and (C.green .. "on" .. C.r) or (C.gray .. "off" .. C.r)
            local imb = db.wfImbueFadeWhenLongDuration and (C.green .. "on" .. C.r) or (C.gray .. "off" .. C.r)
            local imbSec = C.gold .. tostring(db.wfImbueFadeThresholdSec or 120) .. "s" .. C.r
            print(C.gray .. "ShammyTime: Fade — " .. C.gold .. "all " .. (allOn and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)) .. C.gray .. " | combat " .. (db.wfFadeOutOfCombat and (C.green .. "on" .. C.r) or (C.gray .. "off" .. C.r)) .. C.gray .. ", procced " .. (db.wfFadeWhenNotProcced and (C.green .. "on" .. C.r) or (C.gray .. "off" .. C.r)) .. C.gray .. ", focus " .. foc .. C.gray .. ", imbue " .. imb .. C.gray .. " (≤" .. imbSec .. C.gray .. "), nototems " .. nt .. C.gray .. " (delay " .. nd .. C.gray .. "). " .. C.gold .. "/st fade all on|off" .. C.r .. C.gray .. ", " .. C.gold .. "/st fade" .. C.r .. C.gray .. " for list." .. C.r)
            PrintFadeHelp()
        else
            print(C.red .. "ShammyTime: Unknown fade option " .. (C.gold .. "'" .. sub .. "'" .. C.r) .. C.red .. ". " .. C.gold .. "/st fade" .. C.r .. C.red .. " for list." .. C.r)
            PrintFadeHelp()
        end
    -- Circle: /st circle [on|off|scale X|size N|gap N|text title|total|critical N|numbers on|off|toggle]
    elseif cmd == "circle" then
        local a = arg:lower()
        local scaleArg = a:match("^scale%s+(%S+)$")
        local sizeArg = a:match("^size%s+(%S+)$")
        local gapArg = a:match("^gap%s+([-%d%.]+)$")
        local textWhich, textVal = a:match("^text%s+(%S+)%s+([-%d%.]+)$")
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
                print(C.red .. "ShammyTime: Circle scale 0.5–2. " .. C.gold .. "/st circle scale 0.8" .. C.r)
            end
        elseif sizeArg then
            local num = tonumber(sizeArg)
            if num and num > 0 then
                db.wfCenterSize = num
                if ShammyTime.ApplyCenterRingSize then ShammyTime.ApplyCenterRingSize() end
                print(C.green .. "ShammyTime: Center circle size " .. num .. " px." .. C.r)
            else
                print(C.red .. "ShammyTime: Enter a positive number. " .. C.gold .. "/st circle size 200" .. C.r)
            end
        elseif gapArg then
            local num = tonumber(gapArg)
            if num then
                db.wfSatelliteGap = num
                if ShammyTime.ApplySatelliteRadius then ShammyTime.ApplySatelliteRadius() end
                if num == 0 then
                    print(C.green .. "ShammyTime: Outer bubbles touch center ring edge (gap 0)." .. C.r)
                elseif num > 0 then
                    print(C.green .. "ShammyTime: Gap between center edge and outer bubbles " .. num .. " px." .. C.r)
                else
                    print(C.green .. "ShammyTime: Outer bubbles overlap center by " .. (-num) .. " px." .. C.r)
                end
            else
                print(C.red .. "ShammyTime: Enter a number. " .. C.gold .. "/st circle gap 0" .. C.r .. C.red .. " = touch; positive = space; negative = overlap." .. C.r)
            end
        elseif textWhich and textVal then
            local which = textWhich:lower()
            local val = tonumber(textVal)
            if which == "title" and val then
                db.wfCenterTextTitleY = val
                if ShammyTime.ApplyCenterRingTextPosition then ShammyTime.ApplyCenterRingTextPosition() end
                print(C.green .. "ShammyTime: Center text \"Windfury!\" Y = " .. val .. "." .. C.r)
            elseif which == "total" and val then
                db.wfCenterTextTotalY = val
                if ShammyTime.ApplyCenterRingTextPosition then ShammyTime.ApplyCenterRingTextPosition() end
                print(C.green .. "ShammyTime: Center text \"TOTAL\" Y = " .. val .. "." .. C.r)
            elseif which == "critical" and val then
                db.wfCenterTextCriticalY = val
                if ShammyTime.ApplyCenterRingTextPosition then ShammyTime.ApplyCenterRingTextPosition() end
                print(C.green .. "ShammyTime: Center text \"CRITICAL\" Y = " .. val .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Use " .. C.gold .. "/st circle text title 13" .. C.r .. C.red .. ", " .. C.gold .. "text total 0" .. C.r .. C.red .. ", or " .. C.gold .. "text critical 31" .. C.r)
            end
        elseif numArg == "on" or numArg == "enable" or numArg == "1" then
            db.wfAlwaysShowNumbers = true
            print(C.green .. "ShammyTime: Circle numbers always on." .. C.r)
        elseif numArg == "off" or numArg == "disable" or numArg == "0" then
            db.wfAlwaysShowNumbers = false
            print(C.green .. "ShammyTime: Circle numbers fade; show on hover." .. C.r)
        elseif a == "numbers" then
            print(C.gray .. "ShammyTime: Circle numbers " .. (db.wfAlwaysShowNumbers and (C.green .. "always on" .. C.r) or (C.gray .. "fade; show on hover" .. C.r)) .. C.gray .. ". " .. C.gold .. "/st circle numbers on|off" .. C.r)
        elseif a == "toggle" then
            local center = _G.ShammyTimeCenterRing
            if center and center:IsShown() then
                HideWindfuryRadial()
                db.wfRadialShown = false
                print(C.green .. "ShammyTime: Circle hidden." .. C.r)
            else
                ShowWindfuryRadial()
                db.wfRadialShown = true
                print(C.green .. "ShammyTime: Circle shown." .. C.r)
            end
        elseif a == "" then
            local sz = db.wfCenterSize
            local szStr = (sz and sz > 0) and tostring(sz) or "200"
            local g = db.wfSatelliteGap
            local gStr = (g ~= nil) and tostring(g) or "0 (touch)"
            local tTitle = (db.wfCenterTextTitleY ~= nil) and tostring(db.wfCenterTextTitleY) or "13"
            local tTotal = (db.wfCenterTextTotalY ~= nil) and tostring(db.wfCenterTextTotalY) or "0"
            local tCrit = (db.wfCenterTextCriticalY ~= nil) and tostring(db.wfCenterTextCriticalY) or "31"
            print(C.gray .. "ShammyTime: Circle " .. (db.wfRadialEnabled and (C.green .. "on" .. C.r) or (C.red .. "off" .. C.r)) .. C.gray .. ", scale " .. C.gold .. ("%.2f"):format(db.wfRadialScale or 1) .. C.r .. C.gray .. ", size " .. C.gold .. szStr .. C.r .. C.gray .. ", gap " .. C.gold .. gStr .. C.r .. C.gray .. ", text(title " .. tTitle .. ", total " .. tTotal .. ", critical " .. tCrit .. "), numbers " .. (db.wfAlwaysShowNumbers and (C.green .. "on" .. C.r) or (C.gray .. "hover" .. C.r)) .. C.r)
            PrintCircleHelp()
        else
            PrintCircleHelp()
        end
    -- Totem bar: /st totem [scale X] (via /st adv totembar)
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
                print(C.red .. "ShammyTime: Totem bar scale 0.5–2. " .. C.gold .. "/st adv totembar scale 1" .. C.r)
            end
        elseif a == "pos" then
            if ShammyTime.PrintTotemBarPos then ShammyTime.PrintTotemBarPos() end
        elseif a == "" then
            print(C.gray .. "ShammyTime: Totem bar (" .. C.gold .. "/st adv totembar" .. C.r .. C.gray .. "):" .. C.r)
            print(C.gray .. "  scale " .. C.gold .. ("%.2f"):format(db.wfTotemBarScale or 1) .. C.r .. C.gray .. " (0.5–2)" .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st adv totembar scale 1" .. C.r .. C.gray .. " — Change size." .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st show totem on|off" .. C.r .. C.gray .. " — Show/hide." .. C.r)
        else
            print(C.gray .. "ShammyTime: Totem bar (" .. C.gold .. "/st adv totembar" .. C.r .. C.gray .. "):" .. C.r)
            print(C.gray .. "  " .. C.gold .. "scale 1" .. C.r .. C.gray .. " — size (0.5–2)" .. C.r)
            print(C.gray .. "  Position frame by dragging when " .. C.gold .. "/st unlock" .. C.r .. C.gray .. "." .. C.r)
        end
    -- Shamanistic Focus: /st focus [scale X] (via /st adv focus)
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
                print(C.red .. "ShammyTime: Shamanistic Focus scale 0.5–2. " .. C.gold .. "/st adv focus scale 0.8" .. C.r)
            end
        elseif a == "" then
            local s = focusDb.scale
            if s == nil then s = 0.8 end
            print(C.gray .. "ShammyTime: Shamanistic Focus (" .. C.gold .. "/st adv focus" .. C.r .. C.gray .. "):" .. C.r)
            print(C.gray .. "  scale " .. C.gold .. ("%.2f"):format(s) .. C.r .. C.gray .. " (0.5–2)" .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st adv focus scale 0.8" .. C.r .. C.gray .. " — Change size." .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st show focus on|off" .. C.r .. C.gray .. " — Show/hide." .. C.r)
        else
            print(C.gray .. "ShammyTime: Shamanistic Focus (" .. C.gold .. "/st adv focus" .. C.r .. C.gray .. "):" .. C.r)
            print(C.gray .. "  " .. C.gold .. "scale 0.8" .. C.r .. C.gray .. " — size (0.5–2)" .. C.r)
            print(C.gray .. "  Position frame by dragging when " .. C.gold .. "/st unlock" .. C.r .. C.gray .. "." .. C.r)
        end
    -- Imbue bar (weapon imbues): /st imbue [scale X | layout | margin X | gap X | offsety X | iconsize X] (via /st adv imbue)
    elseif cmd == "imbue" or cmd == "imbuebar" then
        local a = arg:lower()
        local scaleArg = a:match("^scale%s+(%S+)$")
        local marginArg = a:match("^margin%s+(%S+)$")
        local gapArg = a:match("^gap%s+(%S+)$")
        local offsetyArg = a:match("^offsety%s+([-%d%.]+)$")
        local iconsizeArg = a:match("^iconsize%s+(%S+)$")
        if scaleArg then
            local num = tonumber(scaleArg)
            if num and num >= 0.1 and num <= 2 then
                db.imbueBarScale = num
                if ShammyTime.ApplyImbueBarScale then ShammyTime.ApplyImbueBarScale() end
                print(C.green .. "ShammyTime: Imbue bar scale " .. ("%.2f"):format(num) .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Imbue bar scale 0.1–2. " .. C.gold .. "/st adv imbue scale 0.4" .. C.r)
            end
        elseif marginArg then
            local num = tonumber(marginArg)
            if num and num >= 0 and num <= 400 then
                db.imbueBarMargin = num
                if ShammyTime.ApplyImbueBarLayout then ShammyTime.ApplyImbueBarLayout() end
                print(C.green .. "ShammyTime: Imbue bar margin " .. num .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Imbue bar margin 0–400. " .. C.gold .. "/st adv imbue margin 169" .. C.r)
            end
        elseif gapArg then
            local num = tonumber(gapArg)
            if num and num >= 0 and num <= 200 then
                db.imbueBarGap = num
                if ShammyTime.ApplyImbueBarLayout then ShammyTime.ApplyImbueBarLayout() end
                print(C.green .. "ShammyTime: Imbue bar gap " .. num .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Imbue bar gap 0–200. " .. C.gold .. "/st adv imbue gap 48" .. C.r)
            end
        elseif offsetyArg then
            local num = tonumber(offsetyArg)
            if num and num >= -200 and num <= 200 then
                db.imbueBarOffsetY = num
                if ShammyTime.ApplyImbueBarLayout then ShammyTime.ApplyImbueBarLayout() end
                print(C.green .. "ShammyTime: Imbue bar offset Y " .. num .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Imbue bar offsety -200–200. " .. C.gold .. "/st adv imbue offsety -52" .. C.r)
            end
        elseif iconsizeArg then
            local num = tonumber(iconsizeArg)
            if num and num >= 12 and num <= 64 then
                db.imbueBarIconSize = num
                if ShammyTime.ApplyImbueBarLayout then ShammyTime.ApplyImbueBarLayout() end
                print(C.green .. "ShammyTime: Imbue bar icon size " .. num .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Imbue bar iconsize 12–64. " .. C.gold .. "/st adv imbue iconsize 22" .. C.r)
            end
        elseif a == "layout" then
            local m = db.imbueBarMargin or 169
            local g = db.imbueBarGap or 48
            local oy = db.imbueBarOffsetY or -52
            local isz = db.imbueBarIconSize or 22
            print(C.gray .. "ShammyTime: Imbue bar layout:" .. C.r)
            print(C.gray .. "  margin " .. C.gold .. m .. C.r .. C.gray .. ", gap " .. C.gold .. g .. C.r .. C.gray .. ", offsety " .. C.gold .. oy .. C.r .. C.gray .. ", iconsize " .. C.gold .. isz .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st adv imbue margin 180" .. C.r .. C.gray .. " — Icon left margin." .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st adv imbue gap 50" .. C.r .. C.gray .. " — Gap between icons." .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st adv imbue offsety -60" .. C.r .. C.gray .. " — Vertical offset." .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st adv imbue iconsize 24" .. C.r .. C.gray .. " — Icon size." .. C.r)
        elseif a == "" then
            local s = db.imbueBarScale or 0.4
            print(C.gray .. "ShammyTime: Imbue bar (" .. C.gold .. "/st adv imbue" .. C.r .. C.gray .. "):" .. C.r)
            print(C.gray .. "  scale " .. C.gold .. ("%.2f"):format(s) .. C.r .. C.gray .. " (0.1–2)" .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st adv imbue scale 0.5" .. C.r .. C.gray .. " — Change size." .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st adv imbue layout" .. C.r .. C.gray .. " — Icon positions/sizes." .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st show imbue on|off" .. C.r .. C.gray .. " — Show/hide." .. C.r)
        else
            print(C.gray .. "ShammyTime: Imbue bar (" .. C.gold .. "/st adv imbue" .. C.r .. C.gray .. "):" .. C.r)
            print(C.gray .. "  " .. C.gold .. "scale 0.4" .. C.r .. C.gray .. " — size (0.1–2)" .. C.r)
            print(C.gray .. "  " .. C.gold .. "layout" .. C.r .. C.gray .. " — icon margin, gap, offsety, iconsize" .. C.r)
            print(C.gray .. "  Position frame by dragging when " .. C.gold .. "/st unlock" .. C.r .. C.gray .. "." .. C.r)
        end
    -- Lightning/Water Shield indicator: /st shield [scale X | size X | count X | numx X | numy Y]
    elseif cmd == "shield" then
        local a = arg:lower():gsub("^%s+", ""):gsub("%s+$", "")
        local scaleArg = a:match("^scale%s+(%S+)$") or a:match("^size%s+(%S+)$")
        local countArg = a:match("^count%s+(%S+)$")
        local numxArg = a:match("^numx%s+(%S+)$")
        local numyArg = a:match("^numy%s+(%S+)$")
        if scaleArg then
            local num = tonumber(scaleArg)
            if num and num >= 0.05 and num <= 2 then
                db.shieldScale = num
                if ShammyTime.ApplyShieldScale then ShammyTime.ApplyShieldScale() end
                print(C.green .. "ShammyTime: Shield indicator size " .. ("%.2f"):format(num) .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Shield size 0.05–2. " .. C.gold .. "/st shield size 0.2" .. C.r .. C.gray .. " or " .. C.gold .. "/st shield scale 0.2" .. C.r)
            end
        elseif countArg then
            if countArg == "auto" or countArg == "nil" or countArg == "off" then
                db.shieldCount = nil
                if ShammyTime.ApplyShieldCountSettings then ShammyTime.ApplyShieldCountSettings() end
                print(C.green .. "ShammyTime: Shield count set to auto (from buff)." .. C.r)
            else
                local num = tonumber(countArg)
                if num and num >= 1 and num <= 9 then
                    db.shieldCount = math.floor(num)
                    if ShammyTime.ApplyShieldCountSettings then ShammyTime.ApplyShieldCountSettings() end
                    print(C.green .. "ShammyTime: Shield count override set to " .. db.shieldCount .. "." .. C.r)
                else
                    print(C.red .. "ShammyTime: Shield count 1–9, or 'auto'. " .. C.gold .. "/st shield count 3" .. C.r .. C.gray .. " or " .. C.gold .. "/st shield count auto" .. C.r)
                end
            end
        elseif numxArg then
            local num = tonumber(numxArg)
            if num and num >= -200 and num <= 200 then
                db.shieldCountX = num
                if ShammyTime.ApplyShieldCountSettings then ShammyTime.ApplyShieldCountSettings() end
                print(C.green .. "ShammyTime: Shield number X offset set to " .. num .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Shield numx -200 to 200. " .. C.gold .. "/st shield numx 10" .. C.r)
            end
        elseif numyArg then
            local num = tonumber(numyArg)
            if num and num >= -200 and num <= 200 then
                db.shieldCountY = num
                if ShammyTime.ApplyShieldCountSettings then ShammyTime.ApplyShieldCountSettings() end
                print(C.green .. "ShammyTime: Shield number Y offset set to " .. num .. "." .. C.r)
            else
                print(C.red .. "ShammyTime: Shield numy -200 to 200. " .. C.gold .. "/st shield numy -50" .. C.r)
            end
        elseif a == "" then
            local s = db.shieldScale or 0.2
            local cnt = db.shieldCount
            local nx = db.shieldCountX or 0
            local ny = db.shieldCountY or -50
            print(C.gray .. "ShammyTime: Lightning/Water Shield (" .. C.gold .. "/st adv shield" .. C.r .. C.gray .. "):" .. C.r)
            print(C.gray .. "  size " .. C.gold .. ("%.2f"):format(s) .. C.r .. C.gray .. " (0.05–2). Drag to move when unlocked." .. C.r)
            print(C.gray .. "  count " .. C.gold .. (cnt and tostring(cnt) or "auto") .. C.r .. C.gray .. " (1–9 = fixed, auto = from buff)" .. C.r)
            print(C.gray .. "  numx " .. C.gold .. nx .. C.r .. C.gray .. ", numy " .. C.gold .. ny .. C.r .. C.gray .. " (number position offset)" .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st adv shield size 0.25" .. C.r .. C.gray .. "  — Change size." .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st adv shield count 3" .. C.r .. C.gray .. "  — Override charge count (or 'auto')." .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st adv shield numx 10" .. C.r .. C.gray .. "  — Number X offset." .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st adv shield numy -50" .. C.r .. C.gray .. "  — Number Y offset." .. C.r)
            print(C.gray .. "  " .. C.gold .. "/st show shield on|off" .. C.r .. C.gray .. "  — Show/hide. " .. C.gold .. "/st print" .. C.r .. C.gray .. "  — All settings." .. C.r)
        else
            print(C.gray .. "ShammyTime: Shield options (" .. C.gold .. "/st adv shield" .. C.r .. C.gray .. "):" .. C.r)
            print(C.gray .. "  " .. C.gold .. "size 0.2" .. C.r .. C.gray .. " — scale (0.05–2)" .. C.r)
            print(C.gray .. "  " .. C.gold .. "count 3" .. C.r .. C.gray .. " or " .. C.gold .. "auto" .. C.r .. C.gray .. " — override charge display" .. C.r)
            print(C.gray .. "  " .. C.gold .. "numx 10" .. C.r .. C.gray .. " — number X position (-200 to 200)" .. C.r)
            print(C.gray .. "  " .. C.gold .. "numy -50" .. C.r .. C.gray .. " — number Y position (-200 to 200)" .. C.r)
            print(C.gray .. "  Position frame by dragging when " .. C.gold .. "/st unlock" .. C.r .. C.gray .. "." .. C.r)
        end
    -- Font sizes: /st font [circle title|total|critical N | satellite label|value N | totem N | imbue N]
    elseif cmd == "font" then
        local sub, subarg = arg:match("^(%S+)%s*(.*)$")
        sub = sub and sub:lower() or ""
        subarg = subarg and subarg:gsub("^%s+", ""):gsub("%s+$", "") or ""
        local num = tonumber(subarg:match("%s+(%S+)$")) or tonumber(subarg:match("^(%S+)$"))
        local clamp = function(n) return (n and n >= 6 and n <= 28) and n or nil end
        if sub == "circle" then
            local which = subarg:match("^(%S+)") and subarg:match("^(%S+)"):lower() or ""
            local val = clamp(num)
            if which == "title" and val then
                db.fontCircleTitle = val
                if ShammyTime.ApplyCenterRingFontSizes then ShammyTime.ApplyCenterRingFontSizes() end
                print(C.green .. "ShammyTime: Circle title font size " .. val .. "." .. C.r)
            elseif which == "total" and val then
                db.fontCircleTotal = val
                if ShammyTime.ApplyCenterRingFontSizes then ShammyTime.ApplyCenterRingFontSizes() end
                print(C.green .. "ShammyTime: Circle total font size " .. val .. "." .. C.r)
            elseif which == "critical" and val then
                db.fontCircleCritical = val
                if ShammyTime.ApplyCenterRingFontSizes then ShammyTime.ApplyCenterRingFontSizes() end
                print(C.green .. "ShammyTime: Circle critical font size " .. val .. "." .. C.r)
            elseif subarg == "" or not val then
                local t1 = db.fontCircleTitle or 20
                local t2 = db.fontCircleTotal or 14
                local t3 = db.fontCircleCritical or 20
                print(C.gray .. "ShammyTime: Circle font — title " .. C.gold .. t1 .. C.r .. C.gray .. ", total " .. C.gold .. t2 .. C.r .. C.gray .. ", critical " .. C.gold .. t3 .. C.r .. C.gray .. ". " .. C.gold .. "/st font circle title 20" .. C.r)
            else
                PrintFontHelp()
            end
        elseif sub == "satellite" then
            local which = subarg:match("^%S+%s+(%S+)") and subarg:match("^%S+%s+(%S+)"):lower() or ""
            local val = clamp(num)
            if which == "label" and val then
                db.fontSatelliteLabel = val
                if ShammyTime.ApplySatelliteFontSizes then ShammyTime.ApplySatelliteFontSizes() end
                print(C.green .. "ShammyTime: Satellite label font size " .. val .. "." .. C.r)
            elseif which == "value" and val then
                db.fontSatelliteValue = val
                if ShammyTime.ApplySatelliteFontSizes then ShammyTime.ApplySatelliteFontSizes() end
                print(C.green .. "ShammyTime: Satellite value font size " .. val .. "." .. C.r)
            elseif subarg == "" or not val then
                local l = db.fontSatelliteLabel or 8
                local v = db.fontSatelliteValue or 13
                print(C.gray .. "ShammyTime: Satellite font — label " .. C.gold .. l .. C.r .. C.gray .. ", value " .. C.gold .. v .. C.r .. C.gray .. ". " .. C.gold .. "/st font satellite label 8" .. C.r)
            else
                PrintFontHelp()
            end
        elseif sub == "totem" and clamp(num) then
            db.fontTotemTimer = clamp(num)
            if ShammyTime.ApplyTotemBarFontSize then ShammyTime.ApplyTotemBarFontSize() end
            print(C.green .. "ShammyTime: Totem bar timer font size " .. db.fontTotemTimer .. "." .. C.r)
        elseif sub == "imbue" and clamp(num) then
            db.fontImbueTimer = clamp(num)
            if ShammyTime.ApplyImbueBarFontSize then ShammyTime.ApplyImbueBarFontSize() end
            print(C.green .. "ShammyTime: Imbue bar timer font size " .. db.fontImbueTimer .. "." .. C.r)
        elseif sub == "" then
            local ct = db.fontCircleTitle or 20
            local ctot = db.fontCircleTotal or 14
            local cc = db.fontCircleCritical or 20
            local sl = db.fontSatelliteLabel or 8
            local sv = db.fontSatelliteValue or 13
            local tt = db.fontTotemTimer or 7
            local ib = db.fontImbueTimer or 20
            print(C.gray .. "ShammyTime: Font — circle title " .. C.gold .. ct .. C.r .. C.gray .. ", total " .. C.gold .. ctot .. C.r .. C.gray .. ", critical " .. C.gold .. cc .. C.r)
            print(C.gray .. "  satellite label " .. C.gold .. sl .. C.r .. C.gray .. ", value " .. C.gold .. sv .. C.r .. C.gray .. ", totem " .. C.gold .. tt .. C.r .. C.gray .. ", imbue " .. C.gold .. ib .. C.r .. C.gray .. ". " .. C.gold .. "/st font" .. C.r .. C.gray .. " for list." .. C.r)
            PrintFontHelp()
        else
            PrintFontHelp()
        end
    elseif cmd == "bubbles" then
        local sub1, rest = arg:match("^(%S+)%s*(.*)$")
        sub1 = sub1 and sub1:lower() or ""
        rest = rest and rest:gsub("^%s+", ""):gsub("%s+$", "") or ""
        local BUBBLE_NAMES = { air = true, stone = true, fire = true, grass = true, water = true, grass_2 = true }
        local function PrintBubblesHelp()
            print("")
            print(C.green .. "ShammyTime — Bubbles (" .. C.gold .. "/st bubbles" .. C.r .. C.green .. ")" .. C.r)
            print(C.gray .. "  Windfury statistic circles (center + 6 outer). Not totem/imbue bars." .. C.r)
            print(C.gray .. "  " .. C.gold .. "center" .. C.r .. C.gray .. "  — Center circle: size, text (title/total/critical), font (title/total/critical)" .. C.r)
            print(C.gray .. "  " .. C.gold .. "outer" .. C.r .. C.gray .. "   — Outer circles: gap, font label/value, pos label/value, or per-circle (air, stone, fire, grass, water, grass_2)" .. C.r)
            print("")
        end
        local function PrintBubblesCenterHelp()
            print("")
            print(C.green .. "  Bubbles → Center (" .. C.gold .. "/st bubbles center" .. C.r .. C.green .. ")" .. C.r)
            print(C.gray .. "  size 200" .. C.r .. C.gray .. "  — Center circle diameter (px)" .. C.r)
            print(C.gray .. "  text title 13" .. C.r .. C.gray .. "  — Y offset of \"Windfury!\"" .. C.r)
            print(C.gray .. "  text total 0" .. C.r .. C.gray .. "  — Y offset of \"TOTAL: xxx\"" .. C.r)
            print(C.gray .. "  text critical 31" .. C.r .. C.gray .. "  — Y offset of \"CRITICAL\"" .. C.r)
            print(C.gray .. "  font title 20" .. C.r .. C.gray .. "  — Font size for title" .. C.r)
            print(C.gray .. "  font total 14" .. C.r .. C.gray .. "  — Font size for total" .. C.r)
            print(C.gray .. "  font critical 20" .. C.r .. C.gray .. "  — Font size for critical" .. C.r)
            print("")
        end
        local function PrintBubblesOuterHelp()
            print("")
            print(C.green .. "  Bubbles → Outer (" .. C.gold .. "/st bubbles outer" .. C.r .. C.green .. ")" .. C.r)
            print(C.gray .. "  gap 0" .. C.r .. C.gray .. "  — Space between center edge and outer circles (0=touch)" .. C.r)
            print(C.gray .. "  font label 8" .. C.r .. C.gray .. "  — Label font size (e.g. \"CRIT%\")" .. C.r)
            print(C.gray .. "  font value 13" .. C.r .. C.gray .. "  — Value font size (e.g. \"35\")" .. C.r)
            print(C.gray .. "  pos label 0 8" .. C.r .. C.gray .. "  — Move the label (e.g. \"CRIT%\") inside each small circle. Two numbers: horizontal then vertical, in pixels from the circle center. Right = positive X, Left = negative X. Up = positive Y, Down = negative Y. Example: 0 8 = 8 px above center." .. C.r)
            print(C.gray .. "  pos value 0 -6" .. C.r .. C.gray .. "  — Same for the number (e.g. \"42\"). Example: 0 -6 = 6 px below center." .. C.r)
            print(C.gray .. "  <name> font label 8" .. C.r .. C.gray .. "  — Override one circle (name: air, stone, fire, grass, water, grass_2)" .. C.r)
            print(C.gray .. "  <name> pos label 0 8" .. C.r .. C.gray .. "  — Override position for one circle" .. C.r)
            print("")
        end
        if sub1 == "" then
            print(C.gray .. "ShammyTime: Bubbles (Windfury circles) — " .. C.gold .. "center" .. C.r .. C.gray .. "  |  " .. C.gold .. "outer" .. C.r .. C.gray .. " (size, text, font, gap, per-circle)" .. C.r)
            PrintBubblesHelp()
        elseif sub1 == "center" then
            local sub2, rest2 = rest:match("^(%S+)%s*(.*)$")
            sub2 = sub2 and sub2:lower() or ""
            rest2 = rest2 and rest2:gsub("^%s+", ""):gsub("%s+$", "") or ""
            if sub2 == "size" then
                local num = tonumber(rest2)
                if num and num > 0 then
                    db.wfCenterSize = num
                    if ShammyTime.ApplyCenterRingSize then ShammyTime.ApplyCenterRingSize() end
                    print(C.green .. "ShammyTime: Center circle size " .. num .. " px." .. C.r)
                else
                    print(C.red .. "ShammyTime: Enter a positive number. " .. C.gold .. "/st bubbles center size 200" .. C.r)
                end
            elseif sub2 == "text" then
                local which = rest2:match("^(%S+)") and rest2:match("^(%S+)"):lower() or ""
                local val = tonumber(rest2:match("%s+([-%d%.]+)$") or rest2:match("^([-%d%.]+)$"))
                if which == "title" and val ~= nil then db.wfCenterTextTitleY = val; if ShammyTime.ApplyCenterRingTextPosition then ShammyTime.ApplyCenterRingTextPosition() end; print(C.green .. "ShammyTime: Center text title Y = " .. val .. "." .. C.r)
                elseif which == "total" and val ~= nil then db.wfCenterTextTotalY = val; if ShammyTime.ApplyCenterRingTextPosition then ShammyTime.ApplyCenterRingTextPosition() end; print(C.green .. "ShammyTime: Center text total Y = " .. val .. "." .. C.r)
                elseif which == "critical" and val ~= nil then db.wfCenterTextCriticalY = val; if ShammyTime.ApplyCenterRingTextPosition then ShammyTime.ApplyCenterRingTextPosition() end; print(C.green .. "ShammyTime: Center text critical Y = " .. val .. "." .. C.r)
                else print(C.gray .. "ShammyTime: Center text — title " .. (db.wfCenterTextTitleY or 13) .. ", total " .. (db.wfCenterTextTotalY or 0) .. ", critical " .. (db.wfCenterTextCriticalY or 31) .. ". " .. C.gold .. "/st bubbles center text title 13" .. C.r) end
            elseif sub2 == "font" then
                local which = rest2:match("^(%S+)") and rest2:match("^(%S+)"):lower() or ""
                local val = tonumber(rest2:match("%s+(%S+)$"))
                local clamp = function(n) return (n and n >= 6 and n <= 28) and n or nil end
                if which == "title" and clamp(val) then db.fontCircleTitle = clamp(val); if ShammyTime.ApplyCenterRingFontSizes then ShammyTime.ApplyCenterRingFontSizes() end; print(C.green .. "ShammyTime: Center font title " .. db.fontCircleTitle .. "." .. C.r)
                elseif which == "total" and clamp(val) then db.fontCircleTotal = clamp(val); if ShammyTime.ApplyCenterRingFontSizes then ShammyTime.ApplyCenterRingFontSizes() end; print(C.green .. "ShammyTime: Center font total " .. db.fontCircleTotal .. "." .. C.r)
                elseif which == "critical" and clamp(val) then db.fontCircleCritical = clamp(val); if ShammyTime.ApplyCenterRingFontSizes then ShammyTime.ApplyCenterRingFontSizes() end; print(C.green .. "ShammyTime: Center font critical " .. db.fontCircleCritical .. "." .. C.r)
                else print(C.gray .. "ShammyTime: Center font — title " .. (db.fontCircleTitle or 20) .. ", total " .. (db.fontCircleTotal or 14) .. ", critical " .. (db.fontCircleCritical or 20) .. ". " .. C.gold .. "/st bubbles center font title 20" .. C.r) end
            elseif sub2 == "" then
                print(C.gray .. "ShammyTime: Bubbles → Center — size " .. (db.wfCenterSize or "200") .. ", text(title " .. (db.wfCenterTextTitleY or 13) .. ", total " .. (db.wfCenterTextTotalY or 0) .. ", critical " .. (db.wfCenterTextCriticalY or 31) .. "), font(title " .. (db.fontCircleTitle or 20) .. ", total " .. (db.fontCircleTotal or 14) .. ", critical " .. (db.fontCircleCritical or 20) .. ")" .. C.r)
                PrintBubblesCenterHelp()
            else
                PrintBubblesCenterHelp()
            end
        elseif sub1 == "outer" then
            local sub2, rest2 = rest:match("^(%S+)%s*(.*)$")
            sub2 = sub2 and sub2:lower() or ""
            rest2 = rest2 and rest2:gsub("^%s+", ""):gsub("%s+$", "") or ""
            if sub2 == "gap" then
                local num = tonumber(rest2)
                if num then
                    db.wfSatelliteGap = num
                    if ShammyTime.ApplySatelliteRadius then ShammyTime.ApplySatelliteRadius() end
                    print(C.green .. "ShammyTime: Outer bubbles gap " .. num .. "." .. C.r)
                else
                    print(C.red .. "ShammyTime: Enter a number. " .. C.gold .. "/st bubbles outer gap 0" .. C.r)
                end
            elseif sub2 == "font" then
                local which = rest2:match("^(%S+)") and rest2:match("^(%S+)"):lower() or ""
                local val = tonumber(rest2:match("%s+(%S+)$"))
                local clamp = function(n) return (n and n >= 6 and n <= 28) and n or nil end
                if which == "label" and clamp(val) then db.fontSatelliteLabel = clamp(val); if ShammyTime.ApplySatelliteFontSizes then ShammyTime.ApplySatelliteFontSizes() end; print(C.green .. "ShammyTime: Outer font label " .. db.fontSatelliteLabel .. "." .. C.r)
                elseif which == "value" and clamp(val) then db.fontSatelliteValue = clamp(val); if ShammyTime.ApplySatelliteFontSizes then ShammyTime.ApplySatelliteFontSizes() end; print(C.green .. "ShammyTime: Outer font value " .. db.fontSatelliteValue .. "." .. C.r)
                else print(C.gray .. "ShammyTime: Outer font — label " .. (db.fontSatelliteLabel or 8) .. ", value " .. (db.fontSatelliteValue or 13) .. ". " .. C.gold .. "/st bubbles outer font label 8" .. C.r) end
            elseif sub2 == "pos" then
                local which = rest2:match("^(%S+)") and rest2:match("^(%S+)"):lower() or ""
                local x, y = rest2:match("%s+([-%d%.]+)%s+([-%d%.]+)$")
                x, y = tonumber(x), tonumber(y)
                if which == "label" and x and y then db.wfSatelliteLabelX = x; db.wfSatelliteLabelY = y; if ShammyTime.ApplySatelliteTextPosition then ShammyTime.ApplySatelliteTextPosition() end; print(C.green .. "ShammyTime: Outer label pos " .. x .. " " .. y .. "." .. C.r)
                elseif which == "value" and x and y then db.wfSatelliteValueX = x; db.wfSatelliteValueY = y; if ShammyTime.ApplySatelliteTextPosition then ShammyTime.ApplySatelliteTextPosition() end; print(C.green .. "ShammyTime: Outer value pos " .. x .. " " .. y .. "." .. C.r)
                else print(C.gray .. "ShammyTime: Outer text position (pixels from center of each circle: X +right -left, Y +up -down). Label " .. (db.wfSatelliteLabelX or 0) .. " " .. (db.wfSatelliteLabelY or 8) .. ", value " .. (db.wfSatelliteValueX or 0) .. " " .. (db.wfSatelliteValueY or -6) .. ". " .. C.gold .. "/st bubbles outer pos label 0 8" .. C.r .. C.gray .. ", " .. C.gold .. "pos value 0 -6" .. C.r) end
            elseif BUBBLE_NAMES[sub2] then
                local bubbleName = sub2
                local sub3, rest3 = rest2:match("^(%S+)%s*(.*)$")
                sub3 = sub3 and sub3:lower() or ""
                rest3 = rest3 and rest3:gsub("^%s+", ""):gsub("%s+$", "") or ""
                db.wfSatelliteOverrides = db.wfSatelliteOverrides or {}
                if not db.wfSatelliteOverrides[bubbleName] then db.wfSatelliteOverrides[bubbleName] = {} end
                local ov = db.wfSatelliteOverrides[bubbleName]
                if sub3 == "font" then
                    local which = rest3:match("^(%S+)") and rest3:match("^(%S+)"):lower() or ""
                    local val = tonumber(rest3:match("%s+(%S+)$"))
                    local clamp = function(n) return (n and n >= 6 and n <= 28) and n or nil end
                    if which == "label" and clamp(val) then ov.labelSize = clamp(val); if ShammyTime.ApplySatelliteFontSizes then ShammyTime.ApplySatelliteFontSizes() end; print(C.green .. "ShammyTime: Outer " .. bubbleName .. " font label " .. ov.labelSize .. "." .. C.r)
                    elseif which == "value" and clamp(val) then ov.valueSize = clamp(val); if ShammyTime.ApplySatelliteFontSizes then ShammyTime.ApplySatelliteFontSizes() end; print(C.green .. "ShammyTime: Outer " .. bubbleName .. " font value " .. ov.valueSize .. "." .. C.r)
                    else print(C.gray .. "ShammyTime: " .. bubbleName .. " font — label " .. tostring(ov.labelSize or "–") .. ", value " .. tostring(ov.valueSize or "–") .. ". " .. C.gold .. "/st bubbles outer " .. bubbleName .. " font label 8" .. C.r) end
                elseif sub3 == "pos" then
                    local which = rest3:match("^(%S+)") and rest3:match("^(%S+)"):lower() or ""
                    local x, y = rest3:match("%s+([-%d%.]+)%s+([-%d%.]+)$")
                    x, y = tonumber(x), tonumber(y)
                    if which == "label" and x and y then ov.labelX = x; ov.labelY = y; if ShammyTime.ApplySatelliteTextPosition then ShammyTime.ApplySatelliteTextPosition() end; print(C.green .. "ShammyTime: Outer " .. bubbleName .. " label pos " .. x .. " " .. y .. "." .. C.r)
                    elseif which == "value" and x and y then ov.valueX = x; ov.valueY = y; if ShammyTime.ApplySatelliteTextPosition then ShammyTime.ApplySatelliteTextPosition() end; print(C.green .. "ShammyTime: Outer " .. bubbleName .. " value pos " .. x .. " " .. y .. "." .. C.r)
                    else print(C.gray .. "ShammyTime: " .. bubbleName .. " pos — label " .. tostring(ov.labelX or "–") .. " " .. tostring(ov.labelY or "–") .. ", value " .. tostring(ov.valueX or "–") .. " " .. tostring(ov.valueY or "–") .. ". " .. C.gold .. "/st bubbles outer " .. bubbleName .. " pos label 0 8" .. C.r) end
                elseif sub3 == "" then
                    print(C.gray .. "ShammyTime: Bubbles → Outer → " .. bubbleName .. " — font(label " .. tostring(ov.labelSize or "–") .. ", value " .. tostring(ov.valueSize or "–") .. "), pos(label " .. tostring(ov.labelX or "–") .. " " .. tostring(ov.labelY or "–") .. ", value " .. tostring(ov.valueX or "–") .. " " .. tostring(ov.valueY or "–") .. ")" .. C.r)
                    PrintBubblesOuterHelp()
                else
                    PrintBubblesOuterHelp()
                end
            elseif sub2 == "" then
                print(C.gray .. "ShammyTime: Bubbles → Outer — gap " .. tostring(db.wfSatelliteGap or 0) .. ", font(label " .. (db.fontSatelliteLabel or 8) .. ", value " .. (db.fontSatelliteValue or 13) .. "), pos(label " .. (db.wfSatelliteLabelX or 0) .. " " .. (db.wfSatelliteLabelY or 8) .. ", value " .. (db.wfSatelliteValueX or 0) .. " " .. (db.wfSatelliteValueY or -6) .. ")" .. C.r)
                PrintBubblesOuterHelp()
            else
                PrintBubblesOuterHelp()
            end
        else
            PrintBubblesHelp()
        end
    else
        if cmd ~= "" then
            print(C.red .. "ShammyTime: Unknown command " .. (C.gold .. "'" .. cmd .. "'" .. C.r) .. C.red .. ". Type " .. C.gold .. "/st" .. C.r .. C.red .. " for options." .. C.r)
        end
        PrintMainHelp()
    end

    -- Sync flat keys to profile.modules so the options panel sees updated values
    if ShammyTime.SyncFlatToModules then
        ShammyTime:SyncFlatToModules()
    end
end
