-- ShammyTime_StaggerBar.lua
-- Dual-wield stagger visual: two swing timer bars (MH on top, OH below) with
-- dynamic color coding (gold / yellow / red) based on stagger quality, a delta
-- readout, and activity-based smart hide.
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
local GOOD_THRESHOLD       = 0.5       -- MH first, delta <= 0.5 s  → gold
local SAME_TIME_THRESHOLD  = 0.01     -- delta < 0.01 = same time (0.00), not gold; 0.05 is gold
-- MH first, delta > 0.5 s  → yellow (drifting)
-- OH first (negative delta)  → red (reversed)

-- Colors: { r, g, b }
local COLOR_GOLD   = { 1.00, 0.82, 0.00 }
local COLOR_YELLOW = { 1.00, 1.00, 0.00 }
local COLOR_RED    = { 1.00, 0.30, 0.30 }

-- Action cue colors
local COLOR_CUE_CLICK = { 0.20, 1.00, 0.20 }   -- bright green  "CLICK NOW!"
local COLOR_CUE_READY = { 1.00, 0.60, 0.30 }   -- orange        "Click after MH hit"
local COLOR_CUE_WAIT  = { 0.55, 0.55, 0.55 }   -- gray          "Wait..."

-- Stormstrike spell ID (resets MH swing timer)
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
}

local smartHide = {
    visible    = false,
    fadeAlpha  = 0,
    fadeTarget = 0,
}

-- Action cue: time-gated "CLICK NOW!" / "Wait..." resync prompt
local actionCue = {
    state          = "idle",   -- idle | resync_needed | click_now | cooldown
    mhSwingAt      = 0,        -- GetTime() of most recent MH swing
    cooldownEnd    = 0,        -- GetTime() when cooldown expires
    cooldownSwings = 0,        -- swing events counted during cooldown
    stateEnteredAt = 0,        -- GetTime() when we entered current state
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function GetDB()
    local st = _G.ShammyTime
    return st and st.db and st.db.profile
end

--- Return the stagger color based on current delta.
local function GetStaggerColor()
    local d = swingState.delta
    if not d then return COLOR_GOLD end
    if swingState.deltaSign < 0 then
        return COLOR_RED     -- OH hit first
    elseif d < SAME_TIME_THRESHOLD then
        return COLOR_YELLOW  -- same time (0.00), synced but not staggered
    elseif d > GOOD_THRESHOLD then
        return COLOR_YELLOW  -- MH first but drifting
    else
        return COLOR_GOLD    -- MH first, small lead (e.g. 0.05–0.5 s)
    end
end

--- Return helper text and color based on current stagger state.
--- Returns (text, {r,g,b}) or ("", nil) when no advice is needed.
local function GetHelperText()
    local d = swingState.delta
    if not d then return "", nil end
    if swingState.deltaSign < 0 then
        -- Red: OH hit before MH — player needs to reset swing timers
        return "Resync swings!", COLOR_RED
    elseif d < SAME_TIME_THRESHOLD then
        -- Same time: synced but not staggered — one tap at MH 50%
        return "Click once to stagger!", COLOR_YELLOW
    elseif d > GOOD_THRESHOLD then
        -- Yellow: drifting apart — swings are getting out of sync
        return "Drifting — resync soon", COLOR_YELLOW
    else
        -- Gold: good stagger, no action needed
        return "", nil
    end
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
    if hand == "mh" then
        swingState.mhLast = now
        swingState.mhExpected = now + swingState.mhSpeed
        -- Seed OH expected time on the very first MH swing so future
        -- attribution has something sensible to compare against.
        -- In WoW dual wield, OH fires ~50% of OH speed after MH.
        if swingState.ohExpected == 0 and swingState.ohSpeed > 0 then
            swingState.ohExpected = now + swingState.ohSpeed * 0.5
        end
    else
        swingState.ohLast = now
        swingState.ohExpected = now + swingState.ohSpeed
        -- Mirror: seed MH if it somehow hasn't been set
        if swingState.mhExpected == 0 and swingState.mhSpeed > 0 then
            swingState.mhExpected = now + swingState.mhSpeed * 0.5
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
        local maxWindow = math.max(swingState.mhSpeed, swingState.ohSpeed, 1)
        local halfWindow = maxWindow * 0.5

        if raw < 0 and math.abs(raw) > halfWindow
           and swingState.ohExpected > swingState.mhLast then
            -- MH just started a new cycle; OH's last swing is from the previous
            -- cycle (cross-cycle).  Use OH's expected time to predict the
            -- stagger quality instead of flashing red incorrectly.
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
local function AttributeFirstTwoSwings(now)
    local t1 = swingState.pendingFirstSwingTime
    if t1 <= 0 then return end
    local t2 = now
    local gap = t2 - t1
    RefreshWeaponSpeeds()
    local maxWindow = math.max(swingState.mhSpeed, swingState.ohSpeed, 1)
    local halfWindow = maxWindow * 0.5

    if gap < halfWindow then
        -- Small gap: same-cycle pair, treat as OH then MH (left first) so pull/resync is correct
        swingState.ohLast = t1
        swingState.mhLast = t2
        swingState.ohExpected = t1 + swingState.ohSpeed
        swingState.mhExpected = t2 + swingState.mhSpeed
        actionCue.mhSwingAt = t2
        SwingDebugLog("Left (OH) hit")
        SwingDebugLog("Right (MH) hit")
    else
        -- Large gap: first swing started a cycle, second is other hand → MH then OH
        swingState.mhLast = t1
        swingState.ohLast = t2
        swingState.mhExpected = t1 + swingState.mhSpeed
        swingState.ohExpected = t2 + swingState.ohSpeed
        actionCue.mhSwingAt = t1
        SwingDebugLog("Right (MH) hit")
        SwingDebugLog("Left (OH) hit")
    end
    swingState.pendingFirstSwingTime = 0
    swingState.firstSwing = false
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
local function ClearStaggerVisuals()
    swingState.mhLast = 0
    swingState.ohLast = 0
    swingState.mhExpected = 0
    swingState.ohExpected = 0
    swingState.firstSwing = true
    swingState.pendingFirstSwingTime = 0
    swingState.delta = nil
    swingState.deltaSign = 0
    -- Reset action cue
    actionCue.state = "idle"
    actionCue.mhSwingAt = 0
    actionCue.cooldownEnd = 0
    actionCue.cooldownSwings = 0
    actionCue.stateEnteredAt = 0
end

--- Full reset: clear visuals AND deactivate tracking (used by smart-hide timeout).
local function ResetSwingState()
    ClearStaggerVisuals()
    swingState.active = false
end

--- Simulate the resync macro: set OH bar to 50% (OH held back to midpoint in-game).
--- Real OH swing events from the combat log remain the master and overwrite this on next swing.
--- Only runs when the player is in combat; out of combat the macro does nothing to the bar.
local function SimulateResyncMacro()
    if not (UnitAffectingCombat and UnitAffectingCombat("player")) then return end
    RefreshWeaponSpeeds()
    if swingState.ohSpeed <= 0 then return end
    local now = GetTime()
    swingState.ohLast = now - 0.5 * swingState.ohSpeed
    swingState.ohExpected = now + 0.5 * swingState.ohSpeed
    ActivateFrame()
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

    -- Tooltip on hover: sync and stagger resync guide
    f:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Sync and Stagger — When to Resync", 1, 0.82, 0, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("1. Main hand is first, but the stagger is wrong", 1, 1, 1, true)
            GameTooltip:AddLine("If your main hand is already hitting first, but the off hand is not following in the correct window, wait until the off hand passes the halfway point of its swing. Once it has passed halfway, press the macro repeatedly. Each press holds the off hand back while the main hand continues forward. Keep pressing until the off hand snaps into the correct follow position behind the main hand. Stop pressing immediately once it lines up correctly and let your swings continue.", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("2. Off hand is hitting first", 1, 1, 1, true)
            GameTooltip:AddLine("If the off hand is landing before the main hand, wait for the main hand to pass the halfway point of its swing. Press the macro once. This single press is usually enough to flip priority. Do not keep pressing unless you are still behind.", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("3. Both hands hit at the same time", 1, 1, 1, true)
            GameTooltip:AddLine("If both hands land together, you are synced but not staggered. Watch the main hand swing. When the main hand just passes the halfway point, press the macro one time. This creates a small main hand lead. Do not press again.", 0.9, 0.9, 0.9, true)
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
    f.mhBar:SetColorTexture(COLOR_GOLD[1], COLOR_GOLD[2], COLOR_GOLD[3], 1)

    -- OH bar texture
    f.ohBar = f.barFrame:CreateTexture(nil, "ARTWORK")
    f.ohBar:SetColorTexture(COLOR_GOLD[1], COLOR_GOLD[2], COLOR_GOLD[3], 1)

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

    -- Store barW for OnUpdate
    f._barMaxWidth = barW
    f._barHeight = barH
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

    -- Staleness check: if no swing has landed for more than one full weapon-
    -- speed cycle, clear the visual info so bars/text don't stay frozen.
    -- This handles always-show mode and cases where PLAYER_REGEN_ENABLED
    -- hasn't fired yet (e.g. still in combat but no longer meleeing).
    if swingState.mhLast > 0 then
        local maxSpeed = math.max(swingState.mhSpeed, swingState.ohSpeed, 1)
        if (now - swingState.lastSwing) > maxSpeed + 1.0 then
            ClearStaggerVisuals()
        end
    end

    local maxW = f._barMaxWidth or 200

    -- MH bar progress
    local mhProgress = 0
    if swingState.mhSpeed > 0 and swingState.mhLast > 0 then
        mhProgress = (now - swingState.mhLast) / swingState.mhSpeed
        mhProgress = math.max(0, math.min(1, mhProgress))
    end

    -- OH bar progress
    local ohProgress = 0
    if swingState.ohSpeed > 0 and swingState.ohLast > 0 then
        ohProgress = (now - swingState.ohLast) / swingState.ohSpeed
        ohProgress = math.max(0, math.min(1, ohProgress))
    end

    -- Set bar widths (minimum 1 pixel to avoid SetSize(0, h) issues)
    local mhW = math.max(1, math.floor(maxW * mhProgress + 0.5))
    local ohW = math.max(1, math.floor(maxW * ohProgress + 0.5))
    f.mhBar:SetWidth(mhW)
    f.ohBar:SetWidth(ohW)

    -- Color both bars based on stagger quality
    local c = GetStaggerColor()
    local p = GetDB()
    local barAlpha = (p and p.staggerSwingBarAlpha) or 1
    f.mhBar:SetColorTexture(c[1], c[2], c[3], barAlpha)
    f.ohBar:SetColorTexture(c[1], c[2], c[3], barAlpha)

    -- Delta text
    if swingState.delta then
        f.deltaText:SetText(string.format("%.2fs", swingState.delta))
        f.deltaText:SetTextColor(c[1], c[2], c[3], 1)
    else
        f.deltaText:SetText("")
    end

    -- Helper text / Action cue
    if f.helperText then
        local cueEnabled = p and p.staggerActionCueEnabled ~= false

        if cueEnabled and swingState.delta then
            -- Determine whether a resync is recommended
            local needsResync = false
            if swingState.deltaSign < 0 then
                needsResync = true   -- reversed (red)
            elseif swingState.delta < SAME_TIME_THRESHOLD then
                needsResync = true   -- same time (0.00), always prompt
            elseif swingState.delta > GOOD_THRESHOLD then
                needsResync = true   -- drifting: outside 0.5s window, always prompt per guide
            end

            local isRed      = (swingState.deltaSign < 0)
            local isSameTime = (swingState.deltaSign >= 0) and (swingState.delta < SAME_TIME_THRESHOLD)
            local isYellow  = (not isRed) and (not isSameTime) and needsResync  -- drifting only

            -- Zone = 60%–85% so players don't tap too early (guide says past 50%; we use 60% min to reduce early taps).
            local zoneWidth  = (p.staggerClickZoneWidth) or 0.25   -- width past 60%: 0.25 = zone 60%–85%
            local zoneLo     = 0.6                    -- minimum 60% (avoid triggering too early)
            local zoneHi     = math.min(0.95, 0.6 + zoneWidth)   -- e.g. 85% with default 0.25
            local cdTime     = (p.staggerCooldownDuration) or 2.0
            -- Red/same-time: wait for MAIN HAND to pass 60% then tap once. Yellow: wait for OFF HAND 60%.
            local inZoneMh   = mhProgress >= zoneLo and mhProgress <= zoneHi
            local inZoneOh   = ohProgress >= zoneLo and ohProgress <= zoneHi
            local inZone    = ((isRed or isSameTime) and inZoneMh) or (isYellow and inZoneOh)

            ----------------------------------------------------------------
            -- State machine: safe moment = bar in 60%–85% (MH or OH per scenario)
            ----------------------------------------------------------------
            if actionCue.state == "idle" then
                if needsResync then
                    actionCue.state = "resync_needed"
                    actionCue.stateEnteredAt = now
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
                    -- Bar left the zone (past 85% or reset to 0 from new swing)
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
                    actionCue.state = "resync_needed"
                    actionCue.stateEnteredAt = now
                end
            end

            ----------------------------------------------------------------
            -- Display: only show "Click once!" when MH is actually in zone (red/same-time)
            ----------------------------------------------------------------
            if actionCue.state == "click_now" then
                -- Red (OH first): must have MH in 60%-85% — wait for main hand, then tap once
                if isRed then
                    if inZoneMh then
                        f.helperText:SetText("Click once!")
                    else
                        f.helperText:SetText("")
                    end
                elseif isSameTime then
                    if inZoneMh then
                        f.helperText:SetText("Click once to stagger!")
                    else
                        f.helperText:SetText("")
                    end
                else
                    -- Yellow (drifting): OH in zone = spam to align
                    if inZoneOh then
                        f.helperText:SetText("Spam to align!")
                    else
                        f.helperText:SetText("")
                    end
                end
                if f.helperText:GetText() ~= "" then
                    f.helperText:SetTextColor(
                        COLOR_CUE_CLICK[1], COLOR_CUE_CLICK[2], COLOR_CUE_CLICK[3], 1)
                end
            elseif actionCue.state == "resync_needed" then
                -- Don't show wait text; only show something when in zone (click_now)
                f.helperText:SetText("")
            elseif actionCue.state == "cooldown" then
                -- Don't show "Observe..."; nothing to do
                f.helperText:SetText("")
            else
                -- idle: show basic helper so drifting (e.g. > 0.5s) still has guidance
                local helperStr, helperColor = GetHelperText()
                f.helperText:SetText(helperStr or "")
                if helperColor then
                    f.helperText:SetTextColor(helperColor[1], helperColor[2], helperColor[3], 1)
                end
            end
        else
            -- Action cue disabled or no swing data: basic helper text
            local helperStr, helperColor = GetHelperText()
            f.helperText:SetText(helperStr)
            if helperColor then
                f.helperText:SetTextColor(helperColor[1], helperColor[2], helperColor[3], 1)
            end
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

        if subevent == "SWING_DAMAGE" or subevent == "SWING_DAMAGE_LANDED"
        or subevent == "SWING_MISSED" then
            local now = GetTime()
            -- Make sure we have weapon speeds
            if swingState.mhSpeed == 0 then RefreshWeaponSpeeds() end
            -- Only track if dual wielding
            if swingState.ohSpeed == 0 or swingState.ohSpeed == nil then return end

            if subevent == "SWING_MISSED" then
                local _, _, _, _, _, _, _, _, _, _, _, missType, isOffHand = CombatLogGetCurrentEventInfo()
                local hand = (isOffHand and "oh") or "mh"
                local handLabel = (hand == "mh") and "Right (MH)" or "Left (OH)"
                SwingDebugLog(handLabel .. " " .. (missType and tostring(missType):lower() or "miss"))
                if swingState.pendingFirstSwingTime > 0 then
                    swingState.pendingFirstSwingTime = 0
                    swingState.firstSwing = false
                end
                RecordSwing(hand, now)
            else
                -- SWING_DAMAGE / SWING_DAMAGE_LANDED: no hand in API
                if swingState.pendingFirstSwingTime > 0 then
                    AttributeFirstTwoSwings(now)
                elseif swingState.firstSwing then
                    swingState.pendingFirstSwingTime = now
                    -- Tentatively show left (OH) bar so first swing has a visible bar; AttributeFirstTwoSwings will correct on second swing
                    swingState.ohLast = now
                    swingState.ohExpected = now + swingState.ohSpeed
                    swingState.lastSwing = now
                    swingState.active = true
                    ActivateFrame()
                else
                    local hand = AttributeSwing(now)
                    SwingDebugLog((hand == "mh" and "Right (MH)" or "Left (OH)") .. " hit")
                    RecordSwing(hand, now)
                end
            end

        elseif subevent == "SPELL_CAST_SUCCESS" then
            -- Stormstrike resets MH swing timer
            local spellId = select(12, CombatLogGetCurrentEventInfo())
            if spellId == STORMSTRIKE_ID then
                local now = GetTime()
                RefreshWeaponSpeeds()
                swingState.mhLast = now
                swingState.mhExpected = now + swingState.mhSpeed
                swingState.lastSwing = now
                swingState.active = true
                actionCue.mhSwingAt = now  -- Stormstrike resets MH; safe window opens
                ActivateFrame()
            end
        end

    elseif event == "UNIT_ATTACK_SPEED" then
        local unit = ...
        if unit == "player" then
            RefreshWeaponSpeeds()
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Left combat: clear stagger visual info (bars shrink, text clears)
        -- immediately so the frame shows its default empty state.
        -- Keep active/lastSwing intact so the smart-hide timer can still
        -- fade out the frame naturally after the configured delay.
        ClearStaggerVisuals()

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entered combat: refresh speeds
        RefreshWeaponSpeeds()

    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        RefreshWeaponSpeeds()
        ShammyTime.EnsureStaggerBarFrame()
    end
end

eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("UNIT_ATTACK_SPEED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
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
