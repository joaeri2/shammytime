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

-- Stagger quality thresholds
local GOOD_THRESHOLD   = 0.45         -- MH first, delta <= 0.45 s  → gold
-- MH first, delta > 0.45 s  → yellow
-- OH first (negative delta)  → red

-- Colors: { r, g, b }
local COLOR_GOLD   = { 1.00, 0.82, 0.00 }
local COLOR_YELLOW = { 1.00, 1.00, 0.00 }
local COLOR_RED    = { 1.00, 0.30, 0.30 }

-- Stormstrike spell ID (resets MH swing timer)
local STORMSTRIKE_ID = 17364

-- Swing timer update throttle (seconds)
local UPDATE_INTERVAL = 0.016  -- ~60 fps

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
    firstSwing = true,             -- next swing is the very first (always MH)
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
    elseif d > GOOD_THRESHOLD then
        return COLOR_YELLOW  -- MH first but drifting
    else
        return COLOR_GOLD    -- perfect stagger
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
    -- Both hands have swung: attribute to whichever hand's expected swing is closest
    local mhDiff = math.abs(now - swingState.mhExpected)
    local ohDiff = math.abs(now - swingState.ohExpected)
    if mhDiff <= ohDiff then
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

    -- Update delta: how close are the most recent MH and OH swings?
    if swingState.mhLast > 0 and swingState.ohLast > 0 then
        local raw = swingState.ohLast - swingState.mhLast
        -- Only consider the delta meaningful if the swings are within one weapon-speed cycle
        local maxWindow = math.max(swingState.mhSpeed, swingState.ohSpeed, 1)
        if math.abs(raw) <= maxWindow then
            swingState.delta = math.abs(raw)
            swingState.deltaSign = (raw >= 0) and 1 or -1
        end
    end
end

--- Reset swing state (e.g. when leaving combat or target dies).
local function ResetSwingState()
    swingState.mhLast = 0
    swingState.ohLast = 0
    swingState.mhExpected = 0
    swingState.ohExpected = 0
    swingState.firstSwing = true
    swingState.active = false
    swingState.delta = nil
    swingState.deltaSign = 0
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
        f:SetAlpha(1)
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

    -- Smooth fade
    local current = f:GetAlpha()
    local target = smartHide.fadeTarget
    if math.abs(current - target) > 0.01 then
        local speed = 3.0  -- fade speed
        local dt = UPDATE_INTERVAL
        if target > current then
            current = math.min(current + speed * dt, target)
        else
            current = math.max(current - speed * dt, target)
        end
        f:SetAlpha(current)
    elseif target == 0 and current < 0.02 then
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
    f.mhBar:SetColorTexture(c[1], c[2], c[3], 1)
    f.ohBar:SetColorTexture(c[1], c[2], c[3], 1)

    -- Delta text
    if swingState.delta then
        f.deltaText:SetText(string.format("%.2fs", swingState.delta))
        f.deltaText:SetTextColor(c[1], c[2], c[3], 1)
    else
        f.deltaText:SetText("")
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

            local hand = AttributeSwing(now)
            RecordSwing(hand, now)

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
                ActivateFrame()
            end
        end

    elseif event == "UNIT_ATTACK_SPEED" then
        local unit = ...
        if unit == "player" then
            RefreshWeaponSpeeds()
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Left combat: don't reset immediately; let smart hide timer handle it
        -- (keeps bars visible for the configured delay after combat ends)

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
