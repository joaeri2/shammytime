-- ShammyTime_StaggerBar.lua
-- Dual-wield stagger visual: two swing timer bars (MH on top, OH below) with
-- bar coloring (gold when perfect, otherwise white), a delta readout, and
-- activity-based smart hide.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local ShammyTime = _G.ShammyTime
if not ShammyTime then return end

local M = _G.ShammyTime_Media
local GetTime = GetTime

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------
local FRAME_NAME       = "ShammyTimeStaggerBarFrame"
local FRAME_W          = 512          -- base width (native 512×512 texture)
local CROP_TOP         = 0.35         -- skip top 35 % of 512 px texture
local CROP_BOTTOM      = 0.65         -- skip bottom 35 %
local FRAME_H          = math.floor(FRAME_W * (CROP_BOTTOM - CROP_TOP) + 0.5)

-- Stagger quality thresholds (per enhanceshaman.com: 0.5 s sync window)
local GOOD_THRESHOLD       = 0.5       -- MH first and <= 0.5s is the target window
local SAME_TIME_THRESHOLD  = 0.01      -- below this counts as same-time (0.00), not staggered
local OVERDUE_GRACE        = 0.45      -- tolerate normal event jitter before overdue/resync
local OVERDUE_CONFIRM_TIME = 0.08      -- require brief persistence to avoid single-frame false positives

-- Colors: { r, g, b }
local COLOR_GOLD   = { 1.00, 0.84, 0.00 }
local COLOR_WHITE  = { 1.00, 1.00, 1.00 }
local COLOR_DELTA  = { 1.00, 0.82, 0.00 }  -- fixed WoW-like yellow for delta readout

-- Action cue colors
local COLOR_CUE_CLICK = { 0.20, 1.00, 0.20 }   -- bright green "Click!"

-- Stormstrike spell ID (logging only; does NOT affect swing timers)
local STORMSTRIKE_ID = 17364

-- Swing timer update throttle (seconds)
local UPDATE_INTERVAL = 0.016  -- ~60 fps

-- Tooltip: resync guide (source: enhanceshaman.com)
local TOOLTIP_SOURCE = "https://www.enhanceshaman.com/pages/guide/sync_stagger"

-- Swing debug log: controlled by /st staggerdebug (saved in profile; default off)
local function IsSwingDebugEnabled()
    local st = _G.ShammyTime
    local p = st and st.db and st.db.profile
    return p and p.staggerSwingDebugLog == true
end
local function SwingDebugLog(msg)
    if IsSwingDebugEnabled() then
        print("|cff00b4ff[ShammyTime]|r " .. msg)
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local staggerFrame = nil           -- the main frame
local swingState = {
    mhSpeed    = 0,                -- current MH weapon speed (haste-adjusted)
    ohSpeed    = 0,                -- current OH weapon speed
    mhSpeedAtStart = 0,            -- MH speed snapshot taken at MH swing start
    ohSpeedAtStart = 0,            -- OH speed snapshot taken at OH swing start
    mhLast     = 0,                -- GetTime() of last MH swing
    ohLast     = 0,                -- GetTime() of last OH swing
    mhExpected = 0,                -- expected next MH swing time
    ohExpected = 0,                -- expected next OH swing time
    firstSwing = true,             -- next swing is the very first (for SWING_DAMAGE heuristic)
    pendingFirstSwingTime = 0,     -- time of first SWING_DAMAGE when not yet attributed (0 = none)
    active     = false,            -- are we currently tracking swings?
    lastSwing  = 0,                -- GetTime() of any last swing (for smart hide)
    delta      = nil,              -- current stagger delta (seconds), nil = unknown
    deltaSign  = 0,                -- 1 = MH first, -1 = OH first, 0 = unknown
    extraAttacksFlag = false,      -- next MH swing is extra attack, skip recording (SPELL_EXTRA_ATTACKS)
    ohSeeded   = false,            -- true if ohExpected/ohLast came from MH-seed only (not a real OH swing yet)
    mhSeeded   = false,            -- true if mhExpected came from OH-seed only (not a real MH swing yet)
}

local smartHide = {
    visible    = false,
    fadeAlpha  = 0,
    fadeTarget = 0,
}

-- Action cue: time-gated resync prompt that only shows "Click!" in the tap window
local actionCue = {
    state          = "idle",   -- idle | resync_needed | click_now | cooldown
    mhSwingAt      = 0,        -- GetTime() of most recent MH swing
    cooldownEnd    = 0,        -- GetTime() when cooldown expires
    cooldownSwings = 0,        -- swing events counted during cooldown
    stateEnteredAt = 0,        -- GetTime() when we entered current state
}

-- Cast-time detection: non-instant spell completion resets weapon swing in-game
local castState = {
    lastCastStartSpellId = nil,  -- spellId when UNIT_SPELLCAST_START fired
    lastCastStartTime    = 0,    -- GetTime() at START; SUCCEEDED within ~30s = same cast
}

-- Tracks when each hand first went overdue; cleared by real swing updates.
local overdueState = {
    mhSince = nil,
    ohSince = nil,
}

-- Temporary instrumentation counters (printed when resync_needed is entered).
local swingDebugCounters = {
    mhEventsSeen = 0,
    ohEventsSeen = 0,
    missEventsSeenNilIsOffHand = 0,
}

local function ResetSwingDebugCounters()
    swingDebugCounters.mhEventsSeen = 0
    swingDebugCounters.ohEventsSeen = 0
    swingDebugCounters.missEventsSeenNilIsOffHand = 0
end

local function BumpSwingDebugCounters(hand, isMissNilIsOffHand)
    if hand == "mh" then
        swingDebugCounters.mhEventsSeen = swingDebugCounters.mhEventsSeen + 1
    elseif hand == "oh" then
        swingDebugCounters.ohEventsSeen = swingDebugCounters.ohEventsSeen + 1
    end
    if isMissNilIsOffHand then
        swingDebugCounters.missEventsSeenNilIsOffHand = swingDebugCounters.missEventsSeenNilIsOffHand + 1
    end
end

local function SwingDebugCounterSummary()
    return string.format(
        "mhEventsSeen=%d ohEventsSeen=%d missEventsSeenNilIsOffHand=%d",
        swingDebugCounters.mhEventsSeen,
        swingDebugCounters.ohEventsSeen,
        swingDebugCounters.missEventsSeenNilIsOffHand
    )
end

local function GetHandCycleSpeed(hand)
    if hand == "mh" then
        if swingState.mhSpeedAtStart and swingState.mhSpeedAtStart > 0 then
            return swingState.mhSpeedAtStart
        end
        return swingState.mhSpeed
    end
    if swingState.ohSpeedAtStart and swingState.ohSpeedAtStart > 0 then
        return swingState.ohSpeedAtStart
    end
    return swingState.ohSpeed
end

--- Shared visual snapshot used by both bars and debug output.
--- Returns clamped next swing deltas and clamped bar progress values.
local function BuildSwingVisualSnapshot(now)
    now = now or GetTime()
    local snap = {
        nextMh = nil,
        nextOh = nil,
        mhProgress = 0,
        ohProgress = 0,
        mhPct = 0,
        ohPct = 0,
    }

    if swingState.mhExpected > 0 then
        snap.nextMh = math.max(0, swingState.mhExpected - now)
    end
    if swingState.ohExpected > 0 then
        snap.nextOh = math.max(0, swingState.ohExpected - now)
    end

    local mhCycleSpeed = GetHandCycleSpeed("mh")
    local ohCycleSpeed = GetHandCycleSpeed("oh")

    if mhCycleSpeed > 0 and swingState.mhLast > 0 then
        snap.mhProgress = math.max(0, math.min(1, (now - swingState.mhLast) / mhCycleSpeed))
    end
    if ohCycleSpeed > 0 and swingState.ohLast > 0 then
        snap.ohProgress = math.max(0, math.min(1, (now - swingState.ohLast) / ohCycleSpeed))
    end

    snap.mhPct = math.floor(100 * snap.mhProgress + 0.5)
    snap.ohPct = math.floor(100 * snap.ohProgress + 0.5)
    return snap
end

local function FirstBoolean(...)
    local n = select("#", ...)
    for i = 1, n do
        local v = select(i, ...)
        if type(v) == "boolean" then
            return v
        end
    end
    return nil
end

local function ResolveHandFromIsOffHandFlag(isOffHand)
    -- Only trust explicit booleans; numeric fields in some CLEU layouts are damage/amount values.
    if type(isOffHand) == "boolean" then
        return isOffHand and "oh" or "mh"
    end
    return nil
end

local function SwingDebugDumpIndexedArgs(eventName, args)
    if not IsSwingDebugEnabled() then return end
    local parts = {}
    for i = 1, #args do
        parts[#parts + 1] = string.format("%d=%s(%s)", i, type(args[i]), tostring(args[i]))
    end
    SwingDebugLog(eventName .. " args[" .. tostring(#args) .. "]: " .. table.concat(parts, " | "))
end

local function ResetOverdueTracking()
    overdueState.mhSince = nil
    overdueState.ohSince = nil
end

local function ClearOverdueTrackingForHand(hand)
    if hand == "mh" then
        overdueState.mhSince = nil
    elseif hand == "oh" then
        overdueState.ohSince = nil
    end
end

local function SwingDebugLogEventTrace(eventName, missType, isOffHand, chosenHand, now, decision)
    if not IsSwingDebugEnabled() then return end
    SwingDebugLog(string.format(
        "trace event=%s missType=%s isOffHand=%s chosenHand=%s now=%.2f mhLast=%.2f ohLast=%.2f mhExpected=%.2f ohExpected=%.2f decision=%s",
        tostring(eventName),
        missType and tostring(missType) or "-",
        tostring(isOffHand),
        chosenHand or "-",
        now or 0,
        swingState.mhLast or 0,
        swingState.ohLast or 0,
        swingState.mhExpected or 0,
        swingState.ohExpected or 0,
        decision or "-"
    ))
end

local function EnterResyncNeeded(now, reason)
    if actionCue.state == "resync_needed" then return end
    actionCue.state = "resync_needed"
    actionCue.stateEnteredAt = now
    SwingDebugLog("cue -> resync_needed (" .. (reason or "unknown") .. ") | " .. SwingDebugCounterSummary())
end

--- Log current visual state (delta, next swing times, bar fill %, action cue) so chat matches the bar.
--- Call after swing events when staggerSwingDebugLog is enabled. Defined after swingState/actionCue so closure captures them.
local function SwingDebugLogVisualState(now)
    if not IsSwingDebugEnabled() then return end
    now = now or GetTime()
    local snap = BuildSwingVisualSnapshot(now)
    local deltaStr = (swingState.delta ~= nil) and string.format("%.2fs", swingState.delta) or "?"
    local signStr = (swingState.deltaSign > 0) and "MH first" or ((swingState.deltaSign < 0) and "OH first" or "?")
    local nextMh = (snap.nextMh ~= nil) and string.format("%.2fs", snap.nextMh) or "-"
    local nextOh = (snap.nextOh ~= nil) and string.format("%.2fs", snap.nextOh) or "-"
    if swingState.mhSeeded and nextMh ~= "-" then nextMh = nextMh .. " (seeded)" end
    if swingState.ohSeeded and nextOh ~= "-" then nextOh = nextOh .. " (seeded)" end
    local cueStr = actionCue.state or "idle"
    local speedStr = string.format("MH %.2fs OH %.2fs", swingState.mhSpeed or 0, swingState.ohSpeed or 0)
    print("|cff00b4ff[ShammyTime]|r   → delta " .. deltaStr .. " " .. signStr .. " | next MH " .. nextMh .. " OH " .. nextOh .. " | bar MH " .. snap.mhPct .. "% OH " .. snap.ohPct .. "% | cue " .. cueStr .. " | speeds: " .. speedStr)
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function GetDB()
    local st = _G.ShammyTime
    return st and st.db and st.db.profile
end

--- Return the stagger color based on current delta.
local function IsPerfectStagger()
    local d = swingState.delta
    return d ~= nil
       and swingState.deltaSign > 0
       and d >= SAME_TIME_THRESHOLD
       and d <= GOOD_THRESHOLD
end

--- Return swing bar fill color (gold only for perfect stagger, otherwise white).
local function GetSwingBarColor()
    return IsPerfectStagger() and COLOR_GOLD or COLOR_WHITE
end

--- Refresh weapon speeds from UnitAttackSpeed.
local function RefreshWeaponSpeeds()
    local mh, oh = UnitAttackSpeed("player")
    swingState.mhSpeed = mh or 0
    swingState.ohSpeed = oh or 0
end

--- Determine which hand a swing belongs to based on expected timing.
local function AttributeSwing(now)
    if swingState.firstSwing then
        swingState.firstSwing = false
        return "mh"  -- first swing in combat is always MH
    end
    -- If only MH has swung so far, the next swing must be OH
    if swingState.mhLast > 0 and swingState.ohLast == 0 then
        return "oh"
    end
    -- If only OH has swung (shouldn't happen, but be safe), next is MH
    if swingState.ohLast > 0 and swingState.mhLast == 0 then
        return "mh"
    end
    -- Both hands have swung: attribute to the hand whose expected swing is
    -- earliest (i.e. the most overdue hand gets the swing).  The previous
    -- abs()-based diff made long-overdue hands LESS likely to be picked,
    -- which caused one hand to "lock" and never update.
    if swingState.mhExpected <= swingState.ohExpected then
        return "mh"
    else
        return "oh"
    end
end

--- Wake the frame so OnUpdate can take over animation / fading.
local function ActivateFrame()
    if not staggerFrame then return end
    -- Check enabled flag
    local p = GetDB()
    if p and p.staggerBarEnabled == false then return end
    if not smartHide.visible then
        smartHide.visible = true
        smartHide.fadeTarget = 1
        staggerFrame:Show()
        -- Start from 0 alpha so the fade-in is smooth
        if staggerFrame:GetAlpha() < 0.01 then
            staggerFrame:SetAlpha(0)
        end
    end
end

--- Record a swing for the given hand.
local function RecordSwing(hand, now)
    RefreshWeaponSpeeds()  -- pick up haste changes (Flurry etc.)
    -- Any real swing means we're still receiving events; clear overdue latches.
    ResetOverdueTracking()
    if hand == "mh" then
        swingState.mhSpeedAtStart = swingState.mhSpeed or 0
        swingState.mhLast = now
        swingState.mhExpected = (swingState.mhSpeedAtStart > 0) and (now + swingState.mhSpeedAtStart) or 0
        swingState.mhSeeded = false  -- real MH swing
        -- Seed OH expected time on the very first MH swing so future
        -- attribution has something sensible to compare against.
        -- In WoW dual wield, OH fires ~50% of OH speed after MH.
        if swingState.ohExpected == 0 and swingState.ohSpeed > 0 then
            swingState.ohSpeedAtStart = swingState.ohSpeed
            swingState.ohExpected = now + swingState.ohSpeedAtStart * 0.5
            swingState.ohLast = now - swingState.ohSpeedAtStart * 0.5  -- synthetic: OH bar shows 50% to match "next OH"
            swingState.ohSeeded = true
        end
    else
        swingState.ohSpeedAtStart = swingState.ohSpeed or 0
        swingState.ohLast = now
        swingState.ohExpected = (swingState.ohSpeedAtStart > 0) and (now + swingState.ohSpeedAtStart) or 0
        swingState.ohSeeded = false  -- real OH swing
        -- Mirror: seed MH if it somehow hasn't been set (e.g. first event was OH, or state was cleared by staleness).
        -- Set mhLast so MH bar shows 50% and matches "next MH (seeded)" instead of staying at 0%.
        if swingState.mhExpected == 0 and swingState.mhSpeed > 0 then
            swingState.mhSpeedAtStart = swingState.mhSpeed
            swingState.mhExpected = now + swingState.mhSpeedAtStart * 0.5
            swingState.mhLast = now - swingState.mhSpeedAtStart * 0.5  -- synthetic: MH bar shows 50% to match "next MH"
            swingState.mhSeeded = true
        end
    end
    swingState.lastSwing = now
    swingState.active = true

    -- Show the frame now that we have a swing (fixes OnUpdate chicken-and-egg)
    ActivateFrame()

    -- Action cue: track MH swing timing and cooldown swing count
    if hand == "mh" then
        actionCue.mhSwingAt = now
    end
    if actionCue.state == "cooldown" then
        actionCue.cooldownSwings = (actionCue.cooldownSwings or 0) + 1
    end

    -- Update delta: how close are the most recent MH and OH swings?
    if swingState.mhLast > 0 and swingState.ohLast > 0 then
        local raw = swingState.ohLast - swingState.mhLast
        local maxWindow = math.max(GetHandCycleSpeed("mh"), GetHandCycleSpeed("oh"), 1)
        local halfWindow = maxWindow * 0.5

        if raw < 0 and math.abs(raw) > halfWindow
           and swingState.ohExpected > swingState.mhLast then
            -- MH just started a new cycle; OH's last swing is from the previous
            -- cycle (cross-cycle).  Use OH's expected time to predict the
            -- stagger quality instead of incorrectly flagging OH-first.
            local predicted = swingState.ohExpected - swingState.mhLast
            swingState.delta = math.min(predicted, maxWindow)
            swingState.deltaSign = 1   -- MH first (predicted)

        elseif raw > 0 and raw > halfWindow
               and swingState.mhExpected > swingState.ohLast then
            -- Mirror: OH just started a new cycle; MH is from the previous
            -- cycle.  Use MH's expected time to predict.
            local predicted = swingState.mhExpected - swingState.ohLast
            swingState.delta = math.min(predicted, maxWindow)
            swingState.deltaSign = -1  -- OH first (predicted)

        elseif math.abs(raw) <= maxWindow then
            -- Same-cycle comparison: both swings are recent enough to compare
            -- directly.  This is the normal case (second hand completes the pair).
            swingState.delta = math.abs(raw)
            swingState.deltaSign = (raw >= 0) and 1 or -1
        end
    end
end

--- Attribute the first two SWING_DAMAGE events by gap: small gap = OH then MH (left first), large gap = MH then OH.
--- Always assigns both mhLast and ohLast from t1 and t2 so both bars get valid state.
local function AttributeFirstTwoSwings(now)
    local t1 = swingState.pendingFirstSwingTime
    if t1 <= 0 then return end
    local t2 = now
    local gap = t2 - t1
    RefreshWeaponSpeeds()
    swingState.mhSpeedAtStart = swingState.mhSpeed or 0
    swingState.ohSpeedAtStart = swingState.ohSpeed or 0
    local maxWindow = math.max(swingState.mhSpeedAtStart, swingState.ohSpeedAtStart, 1)
    local halfWindow = maxWindow * 0.5

    if gap < halfWindow then
        -- Small gap: same-cycle pair, treat as OH then MH (left first) so pull/resync is correct
        if IsSwingDebugEnabled() then
            SwingDebugLog(string.format("First two swings: gap=%.2fs < halfWindow -> OH then MH", gap))
        end
        swingState.ohLast = t1
        swingState.mhLast = t2
        swingState.ohExpected = t1 + swingState.ohSpeedAtStart
        swingState.mhExpected = t2 + swingState.mhSpeedAtStart
        actionCue.mhSwingAt = t2
        SwingDebugLog("Left (OH) hit")
        SwingDebugLog("Right (MH) hit")
    else
        -- Large gap: first swing started a cycle, second is other hand → MH then OH
        if IsSwingDebugEnabled() then
            SwingDebugLog(string.format("First two swings: gap=%.2fs >= halfWindow -> MH then OH", gap))
        end
        swingState.mhLast = t1
        swingState.ohLast = t2
        swingState.mhExpected = t1 + swingState.mhSpeedAtStart
        swingState.ohExpected = t2 + swingState.ohSpeedAtStart
        actionCue.mhSwingAt = t1
        SwingDebugLog("Right (MH) hit")
        SwingDebugLog("Left (OH) hit")
    end
    swingState.pendingFirstSwingTime = 0
    swingState.firstSwing = false
    ResetOverdueTracking()
    swingState.ohSeeded = false
    swingState.mhSeeded = false
    swingState.lastSwing = now
    swingState.active = true
    ActivateFrame()

    -- Update delta (same logic as RecordSwing when both hands set)
    local raw = swingState.ohLast - swingState.mhLast
    if raw < 0 and math.abs(raw) > halfWindow and swingState.ohExpected > swingState.mhLast then
        local predicted = swingState.ohExpected - swingState.mhLast
        swingState.delta = math.min(predicted, maxWindow)
        swingState.deltaSign = 1
    elseif raw > 0 and raw > halfWindow and swingState.mhExpected > swingState.ohLast then
        local predicted = swingState.mhExpected - swingState.ohLast
        swingState.delta = math.min(predicted, maxWindow)
        swingState.deltaSign = -1
    elseif math.abs(raw) <= maxWindow then
        swingState.delta = math.abs(raw)
        swingState.deltaSign = (raw >= 0) and 1 or -1
    end
end

--- Clear stagger visual data (bars, text) without affecting smart-hide state.
--- Called when leaving combat and when swings go stale so the frame shows
--- its default (empty) look while remaining visible.
--- @param reason string|nil Optional: "staleness" | "leave_combat" | "smart_hide" for debug log.
local function ClearStaggerVisuals(reason)
    if reason and IsSwingDebugEnabled() then
        local now = GetTime()
        print("|cff00b4ff[ShammyTime]|r state cleared: " .. reason .. " | now=" .. string.format("%.2f", now) ..
            " mhLast=" .. string.format("%.2f", swingState.mhLast) .. " ohLast=" .. string.format("%.2f", swingState.ohLast) ..
            " mhExpected=" .. string.format("%.2f", swingState.mhExpected) .. " ohExpected=" .. string.format("%.2f", swingState.ohExpected))
    end
    swingState.mhLast = 0
    swingState.ohLast = 0
    swingState.mhSpeedAtStart = 0
    swingState.ohSpeedAtStart = 0
    swingState.mhExpected = 0
    swingState.ohExpected = 0
    swingState.firstSwing = true
    swingState.pendingFirstSwingTime = 0
    swingState.extraAttacksFlag = false
    swingState.ohSeeded = false
    swingState.mhSeeded = false
    swingState.delta = nil
    swingState.deltaSign = 0
    -- Reset action cue
    actionCue.state = "idle"
    actionCue.mhSwingAt = 0
    actionCue.cooldownEnd = 0
    actionCue.cooldownSwings = 0
    actionCue.stateEnteredAt = 0
    ResetOverdueTracking()
    ResetSwingDebugCounters()
end

--- Full reset: clear visuals AND deactivate tracking (used by smart-hide timeout).
local function ResetSwingState()
    ClearStaggerVisuals("smart_hide")
    swingState.active = false
end

--- Simulate the resync macro: only applies once OH has passed midpoint.
--- If OH progress is below 50%, macro does nothing (matches in-game behavior).
--- If OH progress is >= 50%, pull OH back to 50%.
--- Real OH swing events from the combat log remain the master and overwrite this on next swing.
--- Only runs when the player is in combat; out of combat the macro does nothing to the bar.
local function SimulateResyncMacro()
    if not (UnitAffectingCombat and UnitAffectingCombat("player")) then return end
    RefreshWeaponSpeeds()
    if swingState.ohSpeed <= 0 then return end
    local now = GetTime()

    local ohCycleSpeed = GetHandCycleSpeed("oh")
    if swingState.ohLast <= 0 or ohCycleSpeed <= 0 then
        SwingDebugLog("Resync macro ignored (OH progress unknown)")
        return
    end

    local ohProgress = math.max(0, math.min(1, (now - swingState.ohLast) / ohCycleSpeed))
    if ohProgress < 0.5 then
        SwingDebugLog(string.format("Resync macro ignored (OH %.0f%% < 50%%)", ohProgress * 100))
        SwingDebugLogVisualState(now)
        return
    end

    swingState.ohSpeedAtStart = swingState.ohSpeed
    swingState.ohLast = now - 0.5 * swingState.ohSpeedAtStart
    swingState.ohExpected = now + 0.5 * swingState.ohSpeedAtStart
    ClearOverdueTrackingForHand("oh")
    swingState.ohSeeded = false  -- resync is user-driven, not seeded
    swingState.active = true
    swingState.lastSwing = now
    swingState.delta = nil
    swingState.deltaSign = 0
    ActivateFrame()
    SwingDebugLog("Resync macro (OH 50%)")
    SwingDebugLogVisualState(now)
end

--------------------------------------------------------------------------------
-- Position save / restore (uses per-character radial position DB)
--------------------------------------------------------------------------------
local function SaveStaggerBarPosition(frame)
    if not ShammyTime.GetRadialPositionDB then return end
    local pos = ShammyTime.GetRadialPositionDB()
    local point, relTo, relativePoint, x, y = frame:GetPoint(1)
    if not point then return end
    pos.staggerBar = {
        point = point,
        relativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent",
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

--------------------------------------------------------------------------------
-- Frame creation
--------------------------------------------------------------------------------
local function CreateStaggerBarFrame()
    if _G[FRAME_NAME] then
        staggerFrame = _G[FRAME_NAME]
        return staggerFrame
    end

    local TEX = M and M.TEX

    -- Main container
    local f = CreateFrame("Frame", FRAME_NAME, UIParent)
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -320)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    local mainDb = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
    f:EnableMouse(not (mainDb and mainDb.locked))
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
        if db and db.locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveStaggerBarPosition(self)
    end)

    -- Tooltip on hover: when to resync (simplified guide)
    f:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("When to Resync", 1, 0.82, 0, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("OH hitting first (wrong order)", 1, 0.82, 0, true)
            GameTooltip:AddLine("Wait until OH is between 50%-60% of its swing, then press once. Usually enough to flip priority.", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Both hands hit at same time (synced but not staggered)", 1, 0.82, 0, true)
            GameTooltip:AddLine("Wait until OH is between 50%-60%, then press once. Creates a small MH lead. Do not press again.", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("MH first but OH not in window (drifting)", 1, 0.82, 0, true)
            GameTooltip:AddLine("Wait until OH is between 50%-60%. Press repeatedly while OH stays in that window; stop as soon as OH lines up behind MH.", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Source: " .. TOOLTIP_SOURCE, 0.5, 0.7, 1, true)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    local baseLevel = f:GetFrameLevel()

    -- Layer 1: Back texture (BACKGROUND)
    f.backTex = f:CreateTexture(nil, "BACKGROUND")
    if TEX and TEX.STAGGER_BACK then
        f.backTex:SetTexture(TEX.STAGGER_BACK)
    end
    f.backTex:SetAllPoints(f)
    f.backTex:SetTexCoord(0, 1, CROP_TOP, CROP_BOTTOM)
    f.cropTop = CROP_TOP
    f.cropBottom = CROP_BOTTOM

    -- Layer 2: Bar container (same frame level as base; bars are ARTWORK)
    f.barFrame = CreateFrame("Frame", nil, f)
    f.barFrame:SetAllPoints(f)
    f.barFrame:SetFrameLevel(baseLevel)
    f.barFrame:EnableMouse(false)

    -- MH bar texture
    f.mhBar = f.barFrame:CreateTexture(nil, "ARTWORK")
    f.mhBar:SetColorTexture(COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3], 1)

    -- OH bar texture
    f.ohBar = f.barFrame:CreateTexture(nil, "ARTWORK")
    f.ohBar:SetColorTexture(COLOR_WHITE[1], COLOR_WHITE[2], COLOR_WHITE[3], 1)

    -- Markers overlay: zone lines (50%, 60%) and OH cursor (moves with offhand progress)
    f.markersFrame = CreateFrame("Frame", nil, f)
    f.markersFrame:SetAllPoints(f)
    f.markersFrame:SetFrameLevel(baseLevel + 0.5)
    f.markersFrame:EnableMouse(false)

    f.ohCursorTex = f.markersFrame:CreateTexture(nil, "OVERLAY")
    f.ohCursorTex:SetColorTexture(0.2, 1, 0.2, 0.9)  -- bright green
    f.ohCursorTex:SetSize(4, 8)

    f.mhZone50 = f.markersFrame:CreateTexture(nil, "OVERLAY")
    f.mhZone50:SetColorTexture(1, 0.6, 0.2, 0.7)  -- orange
    f.mhZone50:SetSize(2, 6)
    f.mhZone60 = f.markersFrame:CreateTexture(nil, "OVERLAY")
    f.mhZone60:SetColorTexture(0.2, 1, 0.2, 0.7)  -- green
    f.mhZone60:SetSize(2, 6)
    f.ohZone50 = f.markersFrame:CreateTexture(nil, "OVERLAY")
    f.ohZone50:SetColorTexture(1, 0.6, 0.2, 0.7)
    f.ohZone50:SetSize(2, 6)
    f.ohZone60 = f.markersFrame:CreateTexture(nil, "OVERLAY")
    f.ohZone60:SetColorTexture(0.2, 1, 0.2, 0.7)
    f.ohZone60:SetSize(2, 6)

    -- Layer 3: Front texture (one level above bars)
    f.frontFrame = CreateFrame("Frame", nil, f)
    f.frontFrame:SetAllPoints(f)
    f.frontFrame:SetFrameLevel(baseLevel + 1)
    f.frontFrame:EnableMouse(false)

    f.frontTex = f.frontFrame:CreateTexture(nil, "ARTWORK")
    if TEX and TEX.STAGGER_FRONT then
        f.frontTex:SetTexture(TEX.STAGGER_FRONT)
    end
    f.frontTex:SetAllPoints(f.frontFrame)
    f.frontTex:SetTexCoord(0, 1, CROP_TOP, CROP_BOTTOM)

    -- Layer 4: Delta text (two levels above bars, on top of front texture)
    f.textFrame = CreateFrame("Frame", nil, f)
    f.textFrame:SetAllPoints(f)
    f.textFrame:SetFrameLevel(baseLevel + 2)
    f.textFrame:EnableMouse(false)

    local font = "Fonts\\FRIZQT__.TTF"
    f.deltaText = f.textFrame:CreateFontString(nil, "OVERLAY")
    f.deltaText:SetFont(font, 14, "OUTLINE")
    f.deltaText:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.deltaText:SetText("")

    -- MH / OH labels (tiny, left of bars)
    f.mhLabel = f.textFrame:CreateFontString(nil, "OVERLAY")
    f.mhLabel:SetFont(font, 8, "OUTLINE")
    f.mhLabel:SetText("MH")
    f.mhLabel:SetTextColor(0.7, 0.7, 0.7, 0.8)

    f.ohLabel = f.textFrame:CreateFontString(nil, "OVERLAY")
    f.ohLabel:SetFont(font, 8, "OUTLINE")
    f.ohLabel:SetText("OH")
    f.ohLabel:SetTextColor(0.7, 0.7, 0.7, 0.8)

    -- Helper text (advice based on stagger state)
    f.helperText = f.textFrame:CreateFontString(nil, "OVERLAY")
    f.helperText:SetFont(font, 11, "OUTLINE")
    f.helperText:SetPoint("CENTER", f, "CENTER", 0, -20)
    f.helperText:SetText("")

    -- Start at alpha 0 but shown, so OnUpdate fires immediately.
    -- UpdateSmartHide will manage visibility (show/hide) from the first frame.
    f:SetAlpha(0)

    staggerFrame = f
    _G[FRAME_NAME] = f
    return f
end

--------------------------------------------------------------------------------
-- Layout: position bars, delta text within the frame
--------------------------------------------------------------------------------
local function ApplyStaggerBarLayout()
    local f = staggerFrame
    if not f then return end
    local p = GetDB()
    if not p then return end

    local barW  = p.staggerBarWidth or 200
    local barH  = p.staggerBarHeight or 6
    local gap   = p.staggerBarGap or 4
    local bx    = p.staggerBarsX or 0    -- dev: horizontal offset for bars
    local by    = p.staggerBarsY or 0    -- dev: vertical offset for bars
    local fontSz = p.staggerDeltaFontSize or 14
    local dx    = p.staggerDeltaX or 0
    local dy    = p.staggerDeltaY or 0

    -- Center the two bars vertically in the frame, plus dev offsets
    local totalBarH = barH * 2 + gap
    local topY = totalBarH / 2

    -- MH bar (top)
    f.mhBar:ClearAllPoints()
    f.mhBar:SetPoint("LEFT", f, "CENTER", -(barW / 2) + bx, topY - barH / 2 + by)
    f.mhBar:SetSize(1, barH)  -- width set dynamically in OnUpdate

    -- OH bar (below MH)
    f.ohBar:ClearAllPoints()
    f.ohBar:SetPoint("LEFT", f, "CENTER", -(barW / 2) + bx, topY - barH - gap - barH / 2 + by)
    f.ohBar:SetSize(1, barH)

    -- MH / OH labels
    f.mhLabel:ClearAllPoints()
    f.mhLabel:SetPoint("RIGHT", f.mhBar, "LEFT", -3, 0)
    f.ohLabel:ClearAllPoints()
    f.ohLabel:SetPoint("RIGHT", f.ohBar, "LEFT", -3, 0)

    -- Delta text
    f.deltaText:SetFont("Fonts\\FRIZQT__.TTF", fontSz, "OUTLINE")
    f.deltaText:ClearAllPoints()
    f.deltaText:SetPoint("CENTER", f, "CENTER", dx, dy)

    -- Helper text
    local helperSz = p.staggerHelperFontSize or 11
    local hx = p.staggerHelperX or 0
    local hy = p.staggerHelperY or -20
    if f.helperText then
        f.helperText:SetFont("Fonts\\FRIZQT__.TTF", helperSz, "OUTLINE")
        f.helperText:ClearAllPoints()
        f.helperText:SetPoint("CENTER", f, "CENTER", hx, hy)
    end

    -- Store barW and bar layout for OnUpdate (cursor + markers)
    f._barMaxWidth = barW
    f._barHeight = barH
    f._barBarsX = bx
    f._barBarsY = by
    f._barTopY = topY
    f._barGap = gap

    if f.mhZone50 and f.ohCursorTex then
        local leftEdge = -(barW / 2) + bx
        local mhY = topY - barH / 2 + by
        local ohY = topY - barH - gap - barH / 2 + by

        -- Zone markers at 50% and 60% of bar width (resync "click here" reference)
        f.mhZone50:ClearAllPoints()
        f.mhZone50:SetPoint("LEFT", f, "CENTER", leftEdge + barW * 0.5, mhY)
        f.mhZone50:SetSize(2, barH)
        f.mhZone60:ClearAllPoints()
        f.mhZone60:SetPoint("LEFT", f, "CENTER", leftEdge + barW * 0.6, mhY)
        f.mhZone60:SetSize(2, barH)
        f.ohZone50:ClearAllPoints()
        f.ohZone50:SetPoint("LEFT", f, "CENTER", leftEdge + barW * 0.5, ohY)
        f.ohZone50:SetSize(2, barH)
        f.ohZone60:ClearAllPoints()
        f.ohZone60:SetPoint("LEFT", f, "CENTER", leftEdge + barW * 0.6, ohY)
        f.ohZone60:SetSize(2, barH)

        -- OH cursor size (position set in OnUpdate)
        f.ohCursorTex:SetSize(4, barH + 2)
    end
end
ShammyTime.ApplyStaggerBarLayout = ApplyStaggerBarLayout

--------------------------------------------------------------------------------
-- Position (for drag saving / restoring)
--------------------------------------------------------------------------------
local function ApplyStaggerBarPosition()
    local f = staggerFrame
    if not f then return end
    if not ShammyTime.GetRadialPositionDB then return end
    local posDB = ShammyTime.GetRadialPositionDB()
    local pos = posDB and posDB.staggerBar
    if pos then
        local relTo = (pos.relativeTo and _G[pos.relativeTo]) or UIParent
        f:ClearAllPoints()
        f:SetPoint(pos.point or "CENTER", relTo, pos.relativePoint or "CENTER", pos.x or 0, pos.y or -320)
    end
end
ShammyTime.ApplyStaggerBarPosition = ApplyStaggerBarPosition

--------------------------------------------------------------------------------
-- Smart hide
--------------------------------------------------------------------------------
local function UpdateSmartHide(now)
    local f = staggerFrame
    if not f then return end
    local p = GetDB()
    if not p then return end

    -- Module effective alpha (module alpha * master alpha)
    local effAlpha = (ShammyTime.GetModuleEffectiveAlpha
                      and ShammyTime.GetModuleEffectiveAlpha("staggerBar")) or 1

    -- Disabled: hide immediately
    if p.staggerBarEnabled == false then
        f:SetAlpha(0)
        f:Hide()
        smartHide.visible = false
        return
    end

    -- Always-show mode: keep visible, skip smart hide entirely
    if p.staggerBarAlwaysShow then
        if not smartHide.visible then
            smartHide.visible = true
        end
        smartHide.fadeTarget = 1
        f:SetAlpha(effAlpha)
        return
    end

    local delay = p.staggerHideDelay or 15
    local elapsed = now - swingState.lastSwing

    if swingState.active and elapsed < delay then
        -- Should be visible
        if not smartHide.visible then
            smartHide.visible = true
            f:Show()
        end
        smartHide.fadeTarget = 1
    else
        -- Should fade out
        smartHide.fadeTarget = 0
        if swingState.active and elapsed >= delay then
            ResetSwingState()
        end
    end

    -- Smooth fade (fadeTarget is 0 or 1; actual target is scaled by effAlpha)
    local current = f:GetAlpha()
    local target = smartHide.fadeTarget * effAlpha
    if math.abs(current - target) > 0.01 then
        local speed = 3.0  -- fade speed
        local dt = UPDATE_INTERVAL
        if target > current then
            current = math.min(current + speed * dt, target)
        else
            current = math.max(current - speed * dt, target)
        end
        f:SetAlpha(current)
    elseif smartHide.fadeTarget == 0 and current < 0.02 then
        f:SetAlpha(0)
        f:Hide()
        smartHide.visible = false
    end
end

--------------------------------------------------------------------------------
-- OnUpdate: animate bars and delta
--------------------------------------------------------------------------------
local lastUpdate = 0

local function OnUpdate(self, elapsed)
    local now = GetTime()
    if now - lastUpdate < UPDATE_INTERVAL then return end
    lastUpdate = now

    local f = staggerFrame
    if not f then return end

    -- Smart hide
    UpdateSmartHide(now)
    if not smartHide.visible then return end

    -- Staleness check: if no swing has landed for long enough, clear the visual info so bars don't stay frozen.
    -- Use a generous threshold (2 full cycles + 2s) so brief pauses (one cast, target swap) don't wipe state
    -- and cause repeated "(seeded)" bootstrapping mid-fight.
    if swingState.mhLast > 0 then
        local maxSpeed = math.max(swingState.mhSpeed, swingState.ohSpeed, 1)
        if (now - swingState.lastSwing) > (maxSpeed * 2 + 2.0) then
            ClearStaggerVisuals("staleness")
        end
    end

    -- Overdue detection: if we're past expected swing time and didn't get an event, mark as desynced
    -- so the UI shows resync_needed instead of silently showing 100% bar / negative "next".
    local mhDelta = (swingState.mhExpected > 0) and (swingState.mhExpected - now) or nil
    local ohDelta = (swingState.ohExpected > 0) and (swingState.ohExpected - now) or nil
    local mhOverdueRaw = mhDelta ~= nil and mhDelta < -OVERDUE_GRACE and swingState.mhLast > 0
    local ohOverdueRaw = ohDelta ~= nil and ohDelta < -OVERDUE_GRACE and swingState.ohLast > 0
    if mhOverdueRaw then
        if overdueState.mhSince == nil then overdueState.mhSince = now end
    else
        overdueState.mhSince = nil
    end
    if ohOverdueRaw then
        if overdueState.ohSince == nil then overdueState.ohSince = now end
    else
        overdueState.ohSince = nil
    end
    local mhOverdue = overdueState.mhSince ~= nil and (now - overdueState.mhSince) >= OVERDUE_CONFIRM_TIME
    local ohOverdue = overdueState.ohSince ~= nil and (now - overdueState.ohSince) >= OVERDUE_CONFIRM_TIME
    if (mhOverdue or ohOverdue) and actionCue.state ~= "click_now" and actionCue.state ~= "cooldown" then
        if actionCue.state ~= "resync_needed" then
            local reasonParts = {}
            if mhOverdue then
                SwingDebugLog(string.format(
                    "overdue: MH | now=%.2f expected=%.2f last=%.2f speed=%.2f delta=%.2f",
                    now, swingState.mhExpected, swingState.mhLast, GetHandCycleSpeed("mh") or 0, mhDelta or 0
                ))
                reasonParts[#reasonParts + 1] = "MH"
            end
            if ohOverdue then
                SwingDebugLog(string.format(
                    "overdue: OH | now=%.2f expected=%.2f last=%.2f speed=%.2f delta=%.2f",
                    now, swingState.ohExpected, swingState.ohLast, GetHandCycleSpeed("oh") or 0, ohDelta or 0
                ))
                reasonParts[#reasonParts + 1] = "OH"
            end
            EnterResyncNeeded(now, "overdue:" .. table.concat(reasonParts, "+"))
        end
    end

    local maxW = f._barMaxWidth or 200
    local snap = BuildSwingVisualSnapshot(now)
    local mhProgress = snap.mhProgress
    local ohProgress = snap.ohProgress

    -- Set bar widths (minimum 1 pixel to avoid SetSize(0, h) issues)
    local mhW = math.max(1, math.floor(maxW * mhProgress + 0.5))
    local ohW = math.max(1, math.floor(maxW * ohProgress + 0.5))
    f.mhBar:SetWidth(mhW)
    f.ohBar:SetWidth(ohW)

    -- Bars are gold only for perfect stagger; otherwise white.
    local p = GetDB()
    local barAlpha = (p and p.staggerSwingBarAlpha) or 1
    local barColor = GetSwingBarColor()
    f.mhBar:SetColorTexture(barColor[1], barColor[2], barColor[3], barAlpha)
    f.ohBar:SetColorTexture(barColor[1], barColor[2], barColor[3], barAlpha)
    -- Zone markers (50%, 60%) and OH cursor (moving line with offhand progress)
    if f.mhZone50 and f.ohCursorTex then
    local showZones = not p or p.staggerShowZoneMarkers ~= false
    local showCursor = not p or p.staggerShowOhCursor ~= false
    local bx = f._barBarsX or 0
    local by = f._barBarsY or 0
    local barH = f._barHeight or 6
    local gap = f._barGap or 4
    local topY = f._barTopY or (barH * 2 + gap) / 2
    local leftEdge = -(maxW / 2) + bx
    local ohY = topY - barH - gap - barH / 2 + by

    if showZones then
        f.mhZone50:Show()
        f.mhZone60:Show()
        f.ohZone50:Show()
        f.ohZone60:Show()
    else
        f.mhZone50:Hide()
        f.mhZone60:Hide()
        f.ohZone50:Hide()
        f.ohZone60:Hide()
    end

    if showCursor and swingState.ohLast > 0 then
        f.ohCursorTex:ClearAllPoints()
        f.ohCursorTex:SetPoint("LEFT", f, "CENTER", leftEdge + maxW * ohProgress, ohY)
        f.ohCursorTex:Show()
    else
        f.ohCursorTex:Hide()
    end
    end

    -- Delta text
    if swingState.delta then
        f.deltaText:SetText(string.format("%.2fs", swingState.delta))
        f.deltaText:SetTextColor(COLOR_DELTA[1], COLOR_DELTA[2], COLOR_DELTA[3], 1)
    else
        f.deltaText:SetText("")
    end

    -- Helper text / Action cue
    if f.helperText then
        local cueEnabled = p and p.staggerActionCueEnabled ~= false

        if cueEnabled and swingState.delta then
            local showDriftCue = p.staggerActionCueYellow ~= false
            local isOHFirst = (swingState.deltaSign < 0)
            local isSameTime = (swingState.deltaSign >= 0) and (swingState.delta < SAME_TIME_THRESHOLD)
            local isDrifting = (not isOHFirst) and (not isSameTime) and (swingState.delta > GOOD_THRESHOLD)
            local needsResync = isOHFirst or isSameTime or (showDriftCue and isDrifting)

            -- Resync tap window: OH must be between 50% and 60%.
            -- This is where the in-game macro reliably shifts the offhand timer.
            local zoneLo     = 0.50
            local zoneHi     = 0.60
            local cdTime     = (p.staggerCooldownDuration) or 2.0
            -- All scenarios use OH 50-60 for macro timing.
            local inZoneOh   = ohProgress >= zoneLo and ohProgress <= zoneHi
            local inZone     = needsResync and inZoneOh

            ----------------------------------------------------------------
            -- State machine: safe moment = OH in 50%-60% window.
            ----------------------------------------------------------------
            if actionCue.state == "idle" then
                if needsResync then
                    local reason = isOHFirst and "delta:OH_first"
                        or (isSameTime and "delta:same_time")
                        or (isDrifting and "delta:drift")
                        or "delta:unspecified"
                    EnterResyncNeeded(now, reason)
                end

            elseif actionCue.state == "resync_needed" then
                if not needsResync then
                    actionCue.state = "idle"
                    actionCue.stateEnteredAt = now
                elseif inZone then
                    actionCue.state = "click_now"
                    actionCue.stateEnteredAt = now
                end

            elseif actionCue.state == "click_now" then
                if not needsResync then
                    actionCue.state = "idle"
                    actionCue.stateEnteredAt = now
                elseif not inZone then
                    -- Bar left the 50-60% window (or reset to 0 from new swing)
                    actionCue.state = "cooldown"
                    actionCue.cooldownEnd = now + cdTime
                    actionCue.cooldownSwings = 0
                    actionCue.stateEnteredAt = now
                end

            elseif actionCue.state == "cooldown" then
                if not needsResync then
                    -- Resync worked; clear immediately
                    actionCue.state = "idle"
                    actionCue.stateEnteredAt = now
                elseif now >= actionCue.cooldownEnd
                       or actionCue.cooldownSwings >= 2 then
                    -- Time or swing-count based exit
                    EnterResyncNeeded(now, "cooldown:exit")
                end
            end

            ----------------------------------------------------------------
            -- Display text by cue state
            ----------------------------------------------------------------
            if actionCue.state == "click_now" then
                f.helperText:SetText("Click!")
                f.helperText:SetTextColor(
                    COLOR_CUE_CLICK[1], COLOR_CUE_CLICK[2], COLOR_CUE_CLICK[3], 1)
            else
                -- Keep helper clear outside the actual click window.
                f.helperText:SetText("")
            end
        else
            -- Action cue disabled or no swing data: keep helper clear.
            f.helperText:SetText("")
        end
    end
end

--------------------------------------------------------------------------------
-- Event handling
--------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subevent, _, sourceGUID = CombatLogGetCurrentEventInfo()
        if sourceGUID ~= UnitGUID("player") then return end

        if subevent == "SPELL_EXTRA_ATTACKS" then
            swingState.extraAttacksFlag = true
            return
        end

        if subevent == "SWING_DAMAGE" or subevent == "SWING_DAMAGE_LANDED"
        or subevent == "SWING_MISSED" then
            local now = GetTime()
            -- Make sure we have weapon speeds
            if swingState.mhSpeed == 0 then RefreshWeaponSpeeds() end
            -- Only track if dual wielding
            if swingState.ohSpeed == 0 or swingState.ohSpeed == nil then return end

            if subevent == "SWING_MISSED" then
                -- Parry/dodge/miss all consume the swing and reset that hand's timer; we record them like hits.
                -- SWING has no prefix: suffix starts at 9 (8 base) or 12 (11 base). Support both.
                local ev = { CombatLogGetCurrentEventInfo() }
                SwingDebugDumpIndexedArgs("SWING_MISSED", ev)
                local p9, p10, p12, p13 = ev[9], ev[10], ev[12], ev[13]
                local missType = (type(p12) == "string") and p12 or (type(p9) == "string") and p9
                local isOffHand = FirstBoolean(p13, p10)
                local hand = ResolveHandFromIsOffHandFlag(isOffHand)
                local nilIsOffHand = false
                local decision = "cleu:isOffHand"
                if hand == nil then
                    nilIsOffHand = true
                    hand = AttributeSwing(now)
                    decision = "heuristic:AttributeSwing"
                    SwingDebugLog("SWING_MISSED isOffHand=nil args (p9=" .. tostring(p9) .. " p10=" .. tostring(p10) .. " p12=" .. tostring(p12) .. " p13=" .. tostring(p13) .. ") decision=" .. string.upper(hand) .. " (boolean-only trust)")
                end
                BumpSwingDebugCounters(hand, nilIsOffHand)
                SwingDebugLogEventTrace("SWING_MISSED", missType, isOffHand, hand, now, decision)
                local handLabel = (hand == "mh") and "Right (MH)" or "Left (OH)"
                SwingDebugLog(handLabel .. " " .. (missType and tostring(missType):lower() or "miss"))
                if hand == "mh" then
                    swingState.extraAttacksFlag = false
                end
                if swingState.pendingFirstSwingTime > 0 then
                    swingState.pendingFirstSwingTime = 0
                    swingState.firstSwing = false
                end
                RecordSwing(hand, now)
                SwingDebugLogVisualState(now)
            elseif subevent == "SWING_DAMAGE" then
                -- Only SWING_DAMAGE (ignore SWING_DAMAGE_LANDED to avoid double processing).
                -- Try isOffHand from combat log (TBC index 21 or 12/13), else use gap heuristic.
                local raw21 = select(21, CombatLogGetCurrentEventInfo())
                local raw13 = select(13, CombatLogGetCurrentEventInfo())
                local raw12 = select(12, CombatLogGetCurrentEventInfo())
                local isOffHand = FirstBoolean(raw21, raw13, raw12)
                local hand = ResolveHandFromIsOffHandFlag(isOffHand)

                if hand ~= nil then
                    SwingDebugLogEventTrace("SWING_DAMAGE", nil, isOffHand, hand, now, "cleu:isOffHand")
                    if hand == "mh" and swingState.extraAttacksFlag then
                        swingState.extraAttacksFlag = false
                        SwingDebugLog("Right (MH) extra attack (skipped)")
                        SwingDebugLogVisualState(now)
                    else
                        BumpSwingDebugCounters(hand, false)
                        SwingDebugLog((hand == "mh" and "Right (MH)" or "Left (OH)") .. " hit")
                        RecordSwing(hand, now)
                        SwingDebugLogVisualState(now)
                    end
                else
                    -- No valid isOffHand from combat log; use heuristic (first-swing / gap / earliest-expected).
                    local chosenHand = nil
                    local decision = "heuristic:unknown"
                    if swingState.pendingFirstSwingTime > 0 then
                        local gap = now - swingState.pendingFirstSwingTime
                        local maxWindow = math.max(swingState.mhSpeed, swingState.ohSpeed, 1)
                        local halfWindow = maxWindow * 0.5
                        chosenHand = (gap < halfWindow) and "mh" or "oh"
                        decision = string.format("heuristic:first_two gap=%.2f halfWindow=%.2f", gap, halfWindow)
                        SwingDebugLog("SWING_DAMAGE isOffHand=nil args (p12=" .. tostring(raw12) .. " p13=" .. tostring(raw13) .. " p21=" .. tostring(raw21) .. ") decision=" .. string.upper(chosenHand) .. " (pending first swing)")
                        BumpSwingDebugCounters(chosenHand, false)
                        SwingDebugLogEventTrace("SWING_DAMAGE", nil, isOffHand, chosenHand, now, decision)
                        AttributeFirstTwoSwings(now)
                        SwingDebugLogVisualState(now)
                    elseif swingState.firstSwing and (swingState.ohLast > 0 or swingState.mhLast > 0) then
                        -- One hand already set from SWING_MISSED; this damage is the second swing.
                        swingState.pendingFirstSwingTime = (swingState.ohLast > 0) and swingState.ohLast or swingState.mhLast
                        local gap = now - swingState.pendingFirstSwingTime
                        local maxWindow = math.max(swingState.mhSpeed, swingState.ohSpeed, 1)
                        local halfWindow = maxWindow * 0.5
                        chosenHand = (gap < halfWindow) and "mh" or "oh"
                        decision = string.format("heuristic:second_after_miss gap=%.2f halfWindow=%.2f", gap, halfWindow)
                        SwingDebugLog("SWING_DAMAGE isOffHand=nil args (p12=" .. tostring(raw12) .. " p13=" .. tostring(raw13) .. " p21=" .. tostring(raw21) .. ") decision=" .. string.upper(chosenHand) .. " (after missed-first)")
                        BumpSwingDebugCounters(chosenHand, false)
                        SwingDebugLogEventTrace("SWING_DAMAGE", nil, isOffHand, chosenHand, now, decision)
                        AttributeFirstTwoSwings(now)
                        SwingDebugLogVisualState(now)
                    elseif swingState.firstSwing then
                        chosenHand = "oh"
                        decision = "heuristic:first_swing_tentative_oh"
                        SwingDebugLog("SWING_DAMAGE isOffHand=nil args (p12=" .. tostring(raw12) .. " p13=" .. tostring(raw13) .. " p21=" .. tostring(raw21) .. ") decision=OH (tentative first swing)")
                        BumpSwingDebugCounters(chosenHand, false)
                        SwingDebugLogEventTrace("SWING_DAMAGE", nil, isOffHand, chosenHand, now, decision)
                        RefreshWeaponSpeeds()
                        swingState.ohSpeedAtStart = swingState.ohSpeed
                        swingState.pendingFirstSwingTime = now
                        -- Tentatively show left (OH) bar so first swing has a visible bar; AttributeFirstTwoSwings will correct on second swing.
                        swingState.ohLast = now
                        swingState.ohExpected = now + swingState.ohSpeedAtStart
                        swingState.lastSwing = now
                        swingState.active = true
                        ActivateFrame()
                        SwingDebugLog("First swing (tentative OH)")
                        SwingDebugLogVisualState(now)
                    else
                        chosenHand = AttributeSwing(now)
                        decision = "heuristic:AttributeSwing"
                        SwingDebugLog("SWING_DAMAGE isOffHand=nil args (p12=" .. tostring(raw12) .. " p13=" .. tostring(raw13) .. " p21=" .. tostring(raw21) .. ") decision=" .. string.upper(chosenHand))
                        SwingDebugLogEventTrace("SWING_DAMAGE", nil, isOffHand, chosenHand, now, decision)
                        if chosenHand == "mh" and swingState.extraAttacksFlag then
                            swingState.extraAttacksFlag = false
                            SwingDebugLog("Right (MH) extra attack (skipped)")
                            SwingDebugLogVisualState(now)
                        else
                            BumpSwingDebugCounters(chosenHand, false)
                            SwingDebugLog((chosenHand == "mh" and "Right (MH)" or "Left (OH)") .. " hit")
                            RecordSwing(chosenHand, now)
                            SwingDebugLogVisualState(now)
                        end
                    end
                end
            end

        elseif subevent == "SPELL_CAST_SUCCESS" then
            -- Stormstrike does not reset white-swing timers in TBC; log only.
            local spellId = select(12, CombatLogGetCurrentEventInfo())
            if spellId == STORMSTRIKE_ID then
                local now = GetTime()
                SwingDebugLog("Stormstrike hit (ignored for swing timers)")
                SwingDebugLogVisualState(now)
            end
        end

    elseif event == "UNIT_ATTACK_SPEED" then
        local unit = ...
        if unit == "player" then
            local oldMh, oldOh = swingState.mhSpeed, swingState.ohSpeed
            RefreshWeaponSpeeds()
            if IsSwingDebugEnabled() then
                SwingDebugLog(string.format(
                    "UNIT_ATTACK_SPEED oldMH=%.2f newMH=%.2f oldOH=%.2f newOH=%.2f (applies next swing only)",
                    oldMh or 0, swingState.mhSpeed or 0, oldOh or 0, swingState.ohSpeed or 0
                ))
            end
        end

    elseif event == "UNIT_SPELLCAST_START" then
        local unit, castGUID, spellId = ...
        if unit == "player" and spellId then
            castState.lastCastStartSpellId = spellId
            castState.lastCastStartTime = GetTime()
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellId = ...
        if unit == "player" and spellId and castState.lastCastStartSpellId == spellId then
            local now = GetTime()
            if (now - castState.lastCastStartTime) < 30 then
                -- Non-instant cast just completed; game resets swing timer
                RefreshWeaponSpeeds()
                ResetOverdueTracking()
                swingState.mhSpeedAtStart = swingState.mhSpeed or 0
                swingState.ohSpeedAtStart = swingState.ohSpeed or 0
                swingState.mhLast = now
                swingState.mhExpected = now + swingState.mhSpeedAtStart
                swingState.ohLast = now
                swingState.ohExpected = now + swingState.ohSpeedAtStart
                swingState.lastSwing = now
                swingState.active = true
                swingState.pendingFirstSwingTime = 0
                swingState.firstSwing = false
                swingState.ohSeeded = false
                swingState.mhSeeded = false
                swingState.delta = 0
                swingState.deltaSign = 1
                ActivateFrame()
                SwingDebugLog("Cast complete (full sync)")
                SwingDebugLogVisualState(now)
            end
            castState.lastCastStartSpellId = nil
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Left combat: clear stagger visual info (bars shrink, text clears)
        -- immediately so the frame shows its default empty state.
        -- Keep active/lastSwing intact so the smart-hide timer can still
        -- fade out the frame naturally after the configured delay.
        ClearStaggerVisuals("leave_combat")

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entered combat: refresh speeds
        RefreshWeaponSpeeds()

    elseif event == "UNIT_INVENTORY_CHANGED" then
        local unitId = ...
        if unitId == "player" then
            RefreshWeaponSpeeds()
            if swingState.ohSpeed == 0 or swingState.ohSpeed == nil then
                swingState.ohLast = 0
                swingState.ohSpeedAtStart = 0
                swingState.ohExpected = 0
                swingState.delta = nil
                swingState.deltaSign = 0
                ClearOverdueTrackingForHand("oh")
            end
        end

    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        RefreshWeaponSpeeds()
        ShammyTime.EnsureStaggerBarFrame()
    end
end

eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("UNIT_ATTACK_SPEED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", OnEvent)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Ensure the stagger bar frame exists; create if needed; apply layout.
function ShammyTime.EnsureStaggerBarFrame()
    local f = staggerFrame or CreateStaggerBarFrame()
    staggerFrame = f  -- ensure local is always set (survives /reload)
    -- Re-attach scripts (destroyed on /reload even though the frame persists)
    f:SetScript("OnUpdate", OnUpdate)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        local db = ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB()
        if db and db.locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveStaggerBarPosition(self)
    end)
    ApplyStaggerBarPosition()
    ApplyStaggerBarLayout()
    -- Always ensure the frame is shown so OnUpdate can fire.
    -- UpdateSmartHide handles everything: always-show keeps alpha 1,
    -- smart-hide with no swings fades to 0 and hides on the next frame.
    f:Show()
    return f
end

--- Return the frame (nil if not created yet).
function ShammyTime.GetStaggerBarFrame()
    return staggerFrame
end

--- Called when the user runs /st resync (e.g. from their resync macro). Sets OH bar to 50%.
--- Real OH swing from combat log overwrites this on next swing.
ShammyTime.SimulateResyncMacro = SimulateResyncMacro

--- Demo: simulate bar fills for the options preview.
function ShammyTime.StartStaggerBarDemo()
    local f = ShammyTime.EnsureStaggerBarFrame()
    if not f then return end
    f:Show()
    f:SetAlpha(1)
    smartHide.visible = true
    smartHide.fadeTarget = 1

    -- Simulate: pretend we just swung with good stagger
    local now = GetTime()
    swingState.mhSpeed = 2.6
    swingState.ohSpeed = 2.6
    swingState.mhSpeedAtStart = 2.6
    swingState.ohSpeedAtStart = 2.6
    swingState.mhLast = now
    swingState.ohLast = now + 0.2
    swingState.mhExpected = now + 2.6
    swingState.ohExpected = now + 2.8
    swingState.firstSwing = false
    swingState.active = true
    swingState.lastSwing = now + 0.2
    swingState.delta = 0.2
    swingState.deltaSign = 1
end

function ShammyTime.StopStaggerBarDemo()
    local st = _G.ShammyTime
    if st and st.UpdateAllElementsFadeState then st:UpdateAllElementsFadeState() end
end
