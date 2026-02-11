-------------------------------------------------------------------------------
-- ShammyTime: Combat Damage Capture, Rolling Metrics & Burst Pressure
-- Self-contained module – does NOT touch any ShammyTime globals/modules.
--
-- Provides:
--   Frame A  – live scrolling list of outgoing damage events
--   Frame B  – rolling damage / DPS metrics (5/15/30/60/300s windows)
--   Frame C  – burst pressure bar with tier system (T0–T5)
--
-- Usage:  /stpoc on | off | clear | help
--
-- Pressure model: fast/slow leaky battery with squeeze capacitor.
-- See /stpoc help for all tuning slash commands.
-------------------------------------------------------------------------------

local ADDON_PREFIX = "|cff00ccffST-POC|r"

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------
local events = {}       -- array of { t, amount, eventType, spellName, crit, targetName }
local headIndex = 1     -- first valid index in events[]
local retentionSec = 300
local visibleLines = 25
local tickInterval = 0.2
local pocStartTime = nil  -- set on first event or /stpoc on

-------------------------------------------------------------------------------
-- Pressure state (fast/slow leaky battery)
-------------------------------------------------------------------------------
local PS = {
    fastCharge = 0,
    slowCharge = 0,
    tauFast = 1.0,       -- fast decay time constant
    tauSlow = 20.0,      -- slow decay time constant
    epsilon = 1.0,       -- avoid division by zero in ratio
    pressureRatio = 0,   -- normalized pressure (steady-state ~1.0)
    displayGain = 1.20,  -- display multiplier for readability (tunable)
    burstDamping = 1.20, -- denominator blend; higher = fewer one-hit spikes
    displayTau = 0.30,   -- EMA tau for decay / general smoothing
    displayTauRise = 0.12, -- faster rise for snappy burst feedback
    pressureDisplaySmoothed = 0,
    pressureComposite = 0,
    instantScore = 0,
    squeezeScore = 0,
    tierScore = 0,
    currentTier = 0,
    lastTierChangeAt = 0,
    tierCapReason = "ok",
    recentHitImpulse = 0,
    -- "Squeeze battery": builds under sustained pressure, decays slowly.
    squeezeCharge = 0,
    squeezeDecayTau = 18.0,      -- seconds; how long the battery holds charge
    critBonusMult = 2.0,         -- crits feed this much extra into fast charge + impulse
    squeezeBuildRate = 0.25,     -- charge per sec per 1.0 pressure above baseline
    squeezeBonusMax = 0.85,      -- added pressure at full squeezeCharge
    squeezeBuildBaseline = 1.20, -- squeeze ONLY builds during genuine burst (not normal combat)
    squeezeBuildPower = 1.20,    -- nonlinear build favors sustained high pressure
    squeezeIdleDecayMult = 0.45, -- faster squeeze bleed when idle out of combat
    tierInstantWeight = 0.95,    -- burst contribution to tier score
    tierSqueezeWeight = 0.65,    -- sustained squeeze helps but can't carry you alone
    tierHysteresis = 0.10,       -- demote buffer below promote threshold
    tierHoldMinSec = 2.00,       -- minimum hold before a demotion step
    hitImpulseTau = 1.20,        -- seconds: big-hit impulse persistence
    nearTierProgressFrac = 0.75, -- if this close to next tier, a big hit can bump tier
    nearTierKickMin = 0.15,      -- minimum kick to apply near-threshold promotion
    nearTierKickWeight = 0.70,   -- how strongly big-hit kick affects promotion score
    -- Per-tier gates: index = tier + 1 (so 1->T0, 6->T5)
    tierMinSqueeze = { 0.00, 0.00, 0.18, 0.35, 0.70, 0.92 },
    tierMinActiveSec = { 0.0, 1.2, 2.5, 4.0, 7.0, 14.0 },
    firstPressureAt = nil,
    pressureTick = 0.05, -- 50ms update for snappy feel
    pressureElapsed = 0,
    lastDamageTime = 0,  -- for out-of-combat idle detection
    -- dt sanity check: throttled debug print once per second
    dtDebugAcc = 0,
    dtDebugInterval = 1.0,
    dtDebugEnabled = false,
    -- Pressure sample ring for bucketed avg/max
    pressureSamples = {},       -- { t, p } entries
    pressureSampleHead = 1,
    pressureSampleRetention = 300,
    -- Bucketed stats (recomputed every 0.5s to save CPU)
    bucketStatsElapsed = 0,
    bucketStatsInterval = 0.5,
    pressureBucketAvg = { 0, 0, 0, 0, 0 },  -- parallel to WINDOWS
    pressureBucketMax = { 0, 0, 0, 0, 0 },
    -- Tier thresholds (single hits stay T0; sustained pressure earns T1+)
    tierThresholds = { 1.15, 1.55, 1.90, 2.50, 3.20 },
}
local TIER_COLORS = {
    { 0.5, 0.5, 0.5 },   -- T0: grey (idle)
    { 0.2, 0.8, 0.2 },   -- T1: green
    { 0.4, 0.9, 0.1 },   -- T2: yellow-green
    { 1.0, 0.8, 0.0 },   -- T3: gold
    { 1.0, 0.4, 0.0 },   -- T4: orange
    { 1.0, 0.1, 0.1 },   -- T5: red
}

local function GetTier(ratio)
    for i = #PS.tierThresholds, 1, -1 do
        if ratio >= PS.tierThresholds[i] then return i end
    end
    return 0
end

local function GetPromoteThreshold(tier)
    if tier <= 0 then return 0 end
    return PS.tierThresholds[tier] or PS.tierThresholds[#PS.tierThresholds]
end

local function GetDemoteThreshold(tier)
    if tier <= 0 then return -math.huge end
    return GetPromoteThreshold(tier) - PS.tierHysteresis
end

local function GetGateCappedTier(candidateTier, squeeze, activeSec)
    local capped = candidateTier
    local reason = "ok"
    while capped > 0 do
        local idx = capped + 1
        local needSqueeze = PS.tierMinSqueeze[idx] or 0
        local needTime = PS.tierMinActiveSec[idx] or 0
        local hasSqueeze = squeeze >= needSqueeze
        local hasTime = activeSec >= needTime
        if hasSqueeze and hasTime then
            break
        end
        if not hasSqueeze and not hasTime then
            reason = string.format("sqz<%.2f&t<%.0f", needSqueeze, needTime)
        elseif not hasSqueeze then
            reason = string.format("sqz<%.2f", needSqueeze)
        else
            reason = string.format("t<%.0f", needTime)
        end
        capped = capped - 1
    end
    return capped, reason
end

-- Cached player GUID (set on PLAYER_LOGIN)
local playerGUID = nil

-- sourceFlags bitmask: COMBATLOG_OBJECT_AFFILIATION_MINE covers player + totems + elementals
local AFFILIATION_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001

-------------------------------------------------------------------------------
-- Combat log subevent dispatch table
-- For each supported subevent: { category, spellNameIndex, amountIndex, critIndex }
-- SWING_DAMAGE has a different payload layout (no spell triplet).
-------------------------------------------------------------------------------
local SUBEVENT_MAP = {
    -- SWING: amount at 12, crit at 18 (no spell triplet)
    SWING_DAMAGE        = { "SWING",    nil, 12, 18 },
    SWING_DAMAGE_LANDED = { "SWING",    nil, 12, 18 },
    -- SPELL/RANGE/PERIODIC/SHIELD: spellName at 13, amount at 15, crit at 21
    SPELL_DAMAGE            = { "SPELL",    13, 15, 21 },
    RANGE_DAMAGE            = { "RANGE",    13, 15, 21 },
    SPELL_PERIODIC_DAMAGE   = { "PERIODIC", 13, 15, 21 },
    DAMAGE_SHIELD           = { "SHIELD",   13, 15, 21 },
}

-------------------------------------------------------------------------------
-- Combat log handler (HOT PATH – minimal work)
-- CombatLogGetCurrentEventInfo() is called at most twice:
--   1) select(2, ...) for the subevent early-out filter
--   2) { ... } to pack full payload only for events we actually process
-------------------------------------------------------------------------------
local function OnCombatLogEvent()
    -- Fast early-out: one cheap select() call to check subevent
    local subevent = select(2, CombatLogGetCurrentEventInfo())
    local info = SUBEVENT_MAP[subevent]
    if not info then return end

    -- We care about this event – pack payload once
    local p = { CombatLogGetCurrentEventInfo() }

    -- sourceFlags (index 6): AFFILIATION_MINE covers player + totems + elementals
    local sourceFlags = p[6]
    if not sourceFlags or bit.band(sourceFlags, AFFILIATION_MINE) == 0 then return end

    local sourceGUID = p[4]
    local sourceName = p[5] or ""
    local isPlayer = (sourceGUID == playerGUID)

    local category, spellIdx, amountIdx, critIdx = info[1], info[2], info[3], info[4]

    local amount = p[amountIdx]
    if not amount or amount <= 0 then return end

    local spellName
    if spellIdx then
        spellName = p[spellIdx]
    end
    if not spellName or spellName == "" then
        spellName = "(melee)"
    end

    -- Prefix totem/pet source name so it's visible in the event list
    if not isPlayer and sourceName ~= "" then
        spellName = spellName .. " [" .. sourceName .. "]"
    end

    local critFlag = p[critIdx]
    local isCrit = (critFlag == true or critFlag == 1)

    local destName = p[9] or ""

    local now = GetTime()
    if not pocStartTime then pocStartTime = now end
    if not PS.firstPressureAt then PS.firstPressureAt = now end

    local n = #events + 1
    events[n] = {
        t         = now,
        amount    = amount,
        eventType = category,
        spellName = spellName,
        crit      = isCrit,
        target    = destName,
    }

    -- Feed pressure accumulators.
    -- Crits are rocket fuel: they feed extra into fast charge + impulse
    -- but only normal amount into slow charge. This makes crits
    -- disproportionately spike the fast/slow ratio and drive tier climbing.
    local feedAmount = amount
    if isCrit then
        feedAmount = amount * PS.critBonusMult
    end
    PS.fastCharge = PS.fastCharge + feedAmount
    PS.slowCharge = PS.slowCharge + amount  -- slow always gets base amount
    PS.recentHitImpulse = PS.recentHitImpulse + feedAmount
    PS.lastDamageTime = now
end

-------------------------------------------------------------------------------
-- Event frame (registers COMBAT_LOG_EVENT_UNFILTERED)
-------------------------------------------------------------------------------
local clFrame = CreateFrame("Frame")
clFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
clFrame:RegisterEvent("PLAYER_LOGIN")
clFrame:SetScript("OnEvent", function(_, event)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLogEvent()
    elseif event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
    end
end)

-------------------------------------------------------------------------------
-- Frame A: Damage Events List
-------------------------------------------------------------------------------
local FONT_PATH = "Fonts\\FRIZQT__.TTF"
local LINE_HEIGHT = 14
local FRAME_A_WIDTH = 540
local HEADER_HEIGHT = 22
local PADDING = 6

local frameA = CreateFrame("Frame", "STPocEventsFrame", UIParent, "BackdropTemplate")
frameA:SetSize(FRAME_A_WIDTH, HEADER_HEIGHT + PADDING * 2 + visibleLines * LINE_HEIGHT)
frameA:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -120)
frameA:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
frameA:SetBackdropColor(0, 0, 0, 0.80)
frameA:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)
frameA:EnableMouse(false)
frameA:SetFrameStrata("BACKGROUND")
frameA:Hide()

local frameATitle = frameA:CreateFontString(nil, "OVERLAY")
frameATitle:SetFont(FONT_PATH, 12, "OUTLINE")
frameATitle:SetPoint("TOPLEFT", frameA, "TOPLEFT", PADDING, -PADDING)
frameATitle:SetText(ADDON_PREFIX .. " Damage Events")
frameATitle:SetTextColor(1, 0.82, 0)

-- Pre-create line FontStrings
local lineStrings = {}

local function RebuildLineStrings()
    -- hide old
    for i = 1, #lineStrings do
        lineStrings[i]:Hide()
    end
    -- create/reuse
    for i = 1, visibleLines do
        if not lineStrings[i] then
            local fs = frameA:CreateFontString(nil, "OVERLAY")
            fs:SetFont(FONT_PATH, 11, "")
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            lineStrings[i] = fs
        end
        local fs = lineStrings[i]
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", frameA, "TOPLEFT", PADDING, -(HEADER_HEIGHT + PADDING + (i - 1) * LINE_HEIGHT))
        fs:SetPoint("RIGHT", frameA, "RIGHT", -PADDING, 0)
        fs:SetText("")
        fs:Show()
    end
    -- resize frame
    frameA:SetHeight(HEADER_HEIGHT + PADDING * 2 + visibleLines * LINE_HEIGHT)
end

RebuildLineStrings()

-------------------------------------------------------------------------------
-- Frame B: Rolling Metrics Panel
-------------------------------------------------------------------------------
local WINDOWS = { 300, 60, 30, 15, 5 }
local NUM_WINDOWS = #WINDOWS
local FRAME_B_WIDTH = 340
local FRAME_B_HEIGHT = HEADER_HEIGHT + PADDING * 2 + NUM_WINDOWS * (LINE_HEIGHT + 2) + LINE_HEIGHT

local frameB = CreateFrame("Frame", "STPocMetricsFrame", UIParent, "BackdropTemplate")
frameB:SetSize(FRAME_B_WIDTH, FRAME_B_HEIGHT)
frameB:SetPoint("TOPLEFT", frameA, "TOPRIGHT", 8, 0)
frameB:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
frameB:SetBackdropColor(0, 0, 0, 0.80)
frameB:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)
frameB:EnableMouse(false)
frameB:SetFrameStrata("BACKGROUND")
frameB:Hide()

local frameBTitle = frameB:CreateFontString(nil, "OVERLAY")
frameBTitle:SetFont(FONT_PATH, 12, "OUTLINE")
frameBTitle:SetPoint("TOPLEFT", frameB, "TOPLEFT", PADDING, -PADDING)
frameBTitle:SetText(ADDON_PREFIX .. " Rolling Metrics")
frameBTitle:SetTextColor(1, 0.82, 0)

local metricStrings = {}
for i = 1, NUM_WINDOWS do
    local fs = frameB:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT_PATH, 11, "")
    fs:SetJustifyH("LEFT")
    fs:SetPoint("TOPLEFT", frameB, "TOPLEFT", PADDING, -(HEADER_HEIGHT + PADDING + (i - 1) * (LINE_HEIGHT + 2)))
    fs:SetPoint("RIGHT", frameB, "RIGHT", -PADDING, 0)
    fs:SetText("")
    metricStrings[i] = fs
end

-- Extra line for event count at bottom
local countString = frameB:CreateFontString(nil, "OVERLAY")
countString:SetFont(FONT_PATH, 10, "")
countString:SetJustifyH("LEFT")
countString:SetTextColor(0.6, 0.6, 0.6)
countString:SetPoint("BOTTOMLEFT", frameB, "BOTTOMLEFT", PADDING, PADDING)
countString:SetText("")

-------------------------------------------------------------------------------
-- Frame C: Pressure Visual (StatusBar + bucketed stats)
-------------------------------------------------------------------------------
local FRAME_C_WIDTH = 340
local PRESSURE_BAR_HEIGHT = 24
local BUCKET_ROWS = NUM_WINDOWS
local FRAME_C_HEIGHT = HEADER_HEIGHT + PADDING * 2 + PRESSURE_BAR_HEIGHT + 4
                     + LINE_HEIGHT         -- tier + ratio line
                     + LINE_HEIGHT         -- debug fast/slow line
                     + 4                   -- spacer
                     + BUCKET_ROWS * (LINE_HEIGHT + 2)
                     + PADDING

local frameC = CreateFrame("Frame", "STPocPressureFrame", UIParent, "BackdropTemplate")
frameC:SetSize(FRAME_C_WIDTH, FRAME_C_HEIGHT)
frameC:SetPoint("TOPLEFT", frameB, "BOTTOMLEFT", 0, -8)
frameC:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
frameC:SetBackdropColor(0, 0, 0, 0.80)
frameC:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)
frameC:EnableMouse(false)
frameC:SetFrameStrata("BACKGROUND")
frameC:Hide()

local frameCTitle = frameC:CreateFontString(nil, "OVERLAY")
frameCTitle:SetFont(FONT_PATH, 12, "OUTLINE")
frameCTitle:SetPoint("TOPLEFT", frameC, "TOPLEFT", PADDING, -PADDING)
frameCTitle:SetText(ADDON_PREFIX .. " Pressure")
frameCTitle:SetTextColor(1, 0.82, 0)

-- StatusBar
local pressureBar = CreateFrame("StatusBar", "STPocPressureBar", frameC)
pressureBar:SetSize(FRAME_C_WIDTH - PADDING * 2 - 4, PRESSURE_BAR_HEIGHT)
pressureBar:SetPoint("TOPLEFT", frameC, "TOPLEFT", PADDING + 2, -(HEADER_HEIGHT + PADDING))
pressureBar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
pressureBar:SetMinMaxValues(0.0, 4.0)
pressureBar:SetValue(0)
pressureBar:SetStatusBarColor(0.5, 0.5, 0.5)

-- Dark background behind bar
local barBg = pressureBar:CreateTexture(nil, "BACKGROUND")
barBg:SetAllPoints()
barBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

-- Ratio text overlay on bar (centered)
local barText = pressureBar:CreateFontString(nil, "OVERLAY")
barText:SetFont(FONT_PATH, 13, "OUTLINE")
barText:SetPoint("CENTER", pressureBar, "CENTER", 0, 0)
barText:SetText("1.00x")

-- Tier label (right of ratio on bar)
local barTierText = pressureBar:CreateFontString(nil, "OVERLAY")
barTierText:SetFont(FONT_PATH, 11, "OUTLINE")
barTierText:SetPoint("RIGHT", pressureBar, "RIGHT", -4, 0)
barTierText:SetText("T0")
barTierText:SetTextColor(0.6, 0.6, 0.6)

-- Debug line: fast/slow charge values
local yAfterBar = -(HEADER_HEIGHT + PADDING + PRESSURE_BAR_HEIGHT + 4)
local debugText = frameC:CreateFontString(nil, "OVERLAY")
debugText:SetFont(FONT_PATH, 10, "")
debugText:SetJustifyH("LEFT")
debugText:SetPoint("TOPLEFT", frameC, "TOPLEFT", PADDING, yAfterBar)
debugText:SetPoint("RIGHT", frameC, "RIGHT", -PADDING, 0)
debugText:SetTextColor(0.6, 0.6, 0.6)
debugText:SetText("n:0.00 i:0.00 q:0.00 ts:0.00 ok")

-- Bucketed pressure stats (avg/max per window)
local yBucketStart = yAfterBar - LINE_HEIGHT - 4
local pressureBucketStrings = {}
for i = 1, BUCKET_ROWS do
    local fs = frameC:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT_PATH, 11, "")
    fs:SetJustifyH("LEFT")
    fs:SetPoint("TOPLEFT", frameC, "TOPLEFT", PADDING, yBucketStart - (i - 1) * (LINE_HEIGHT + 2))
    fs:SetPoint("RIGHT", frameC, "RIGHT", -PADDING, 0)
    fs:SetText("")
    pressureBucketStrings[i] = fs
end

-------------------------------------------------------------------------------
-- Pressure tick (fast: 0.05s) – decay, sample, update Frame C
-------------------------------------------------------------------------------
local math_exp = math.exp
local math_max = math.max
local math_min = math.min

local function OnPressureTick(_, dt)
    local s = PS
    s.pressureElapsed = s.pressureElapsed + dt
    if s.pressureElapsed < s.pressureTick then return end
    local elapsed = s.pressureElapsed
    s.pressureElapsed = 0

    -- Step 1A: dt sanity check (throttled print once per second)
    s.dtDebugAcc = s.dtDebugAcc + elapsed
    if s.dtDebugEnabled and s.dtDebugAcc >= s.dtDebugInterval then
        s.dtDebugAcc = s.dtDebugAcc - s.dtDebugInterval
        print(ADDON_PREFIX .. string.format(
            " [dt] dt=%.4fs  fast=%.1f  slow=%.1f  norm=%.3f  out=%.3f",
            elapsed, s.fastCharge, s.slowCharge, s.pressureRatio, s.pressureComposite))
    end

    -- Exponential decay
    s.fastCharge = s.fastCharge * math_exp(-elapsed / s.tauFast)
    s.slowCharge = s.slowCharge * math_exp(-elapsed / s.tauSlow)

    if s.fastCharge < 0.01 then s.fastCharge = 0 end
    if s.slowCharge < 0.01 then s.slowCharge = 0 end

    local scale = s.tauFast / s.tauSlow
    local steadyDen = s.slowCharge * scale
    local dampedDen = (steadyDen + (s.fastCharge * s.burstDamping)) / (1 + s.burstDamping)
    s.pressureRatio = s.fastCharge / math_max(dampedDen, s.epsilon)

    local now = GetTime()
    local ns = #s.pressureSamples + 1
    s.pressureSamples[ns] = { t = now, p = s.pressureRatio }

    local sampleCutoff = now - s.pressureSampleRetention
    while s.pressureSampleHead <= ns and s.pressureSamples[s.pressureSampleHead].t < sampleCutoff do
        s.pressureSamples[s.pressureSampleHead] = nil
        s.pressureSampleHead = s.pressureSampleHead + 1
    end
    if s.pressureSampleHead > 1 and s.pressureSampleHead > (ns / 2) then
        local newArr = {}
        local j = 0
        for i = s.pressureSampleHead, ns do
            if s.pressureSamples[i] then
                j = j + 1
                newArr[j] = s.pressureSamples[i]
            end
        end
        s.pressureSamples = newArr
        s.pressureSampleHead = 1
    end

    s.bucketStatsElapsed = s.bucketStatsElapsed + elapsed
    if s.bucketStatsElapsed >= s.bucketStatsInterval then
        s.bucketStatsElapsed = 0
        for wi = 1, BUCKET_ROWS do
            s.pressureBucketAvg[wi] = 0
            s.pressureBucketMax[wi] = 0
        end
        local bucketCount = { 0, 0, 0, 0, 0 }
        for i = s.pressureSampleHead, #s.pressureSamples do
            local sample = s.pressureSamples[i]
            if sample then
                local age = now - sample.t
                for wi = 1, BUCKET_ROWS do
                    if age <= WINDOWS[wi] then
                        s.pressureBucketAvg[wi] = s.pressureBucketAvg[wi] + sample.p
                        bucketCount[wi] = bucketCount[wi] + 1
                        if sample.p > s.pressureBucketMax[wi] then
                            s.pressureBucketMax[wi] = sample.p
                        end
                    end
                end
            end
        end
        for wi = 1, BUCKET_ROWS do
            if bucketCount[wi] > 0 then
                s.pressureBucketAvg[wi] = s.pressureBucketAvg[wi] / bucketCount[wi]
            end
        end
    end

    local targetDisplay = s.pressureRatio * s.displayGain
    -- Asymmetric smoothing: rise quickly on burst, decay more smoothly.
    local smoothingTau = (targetDisplay > s.pressureDisplaySmoothed) and s.displayTauRise or s.displayTau
    local displayAlpha = 1 - math_exp(-elapsed / smoothingTau)
    s.pressureDisplaySmoothed = s.pressureDisplaySmoothed + (targetDisplay - s.pressureDisplaySmoothed) * displayAlpha

    local overBaseline = math_max(s.pressureDisplaySmoothed - s.squeezeBuildBaseline, 0.0)
    local inCombat = UnitAffectingCombat("player")
    local decayTau = s.squeezeDecayTau
    if (not inCombat) and ((now - s.lastDamageTime) > 3.0) then
        decayTau = s.squeezeDecayTau * s.squeezeIdleDecayMult
    end
    s.squeezeCharge = s.squeezeCharge * math_exp(-elapsed / math_max(decayTau, 0.1))
    s.squeezeCharge = s.squeezeCharge + ((overBaseline ^ s.squeezeBuildPower) * s.squeezeBuildRate * elapsed)
    s.squeezeCharge = math_min(math_max(s.squeezeCharge, 0.0), 1.0)

    s.pressureComposite = s.pressureDisplaySmoothed + (s.squeezeCharge * s.squeezeBonusMax)

    s.instantScore = s.pressureDisplaySmoothed
    s.squeezeScore = s.squeezeCharge * s.squeezeBonusMax
    s.tierScore = (s.instantScore * s.tierInstantWeight) + (s.squeezeScore * s.tierSqueezeWeight)

    s.recentHitImpulse = s.recentHitImpulse * math_exp(-elapsed / math_max(s.hitImpulseTau, 0.1))
    local hitKick = math_min((s.recentHitImpulse / math_max(dampedDen, s.epsilon)) * 0.25, 1.0)

    local activeSec = s.firstPressureAt and (now - s.firstPressureAt) or 0
    local candidateTier = GetTier(s.tierScore)
    if s.currentTier < 5 then
        local nextTier = s.currentTier + 1
        local nextThreshold = GetPromoteThreshold(nextTier)
        if nextThreshold > 0 then
            local progress = s.tierScore / nextThreshold
            if progress >= s.nearTierProgressFrac and hitKick >= s.nearTierKickMin then
                -- Assist is only for the immediate next step, never multiple-tier jumps.
                local promotionScore = s.tierScore + (hitKick * s.nearTierKickWeight)
                local promotedTier = GetTier(promotionScore)
                candidateTier = math_max(candidateTier, math_min(promotedTier, nextTier))
            end
        end
    end

    local gatedTier
    gatedTier, s.tierCapReason = GetGateCappedTier(candidateTier, s.squeezeCharge, activeSec)

    if gatedTier > s.currentTier then
        s.currentTier = gatedTier
        s.lastTierChangeAt = now
    elseif gatedTier < s.currentTier then
        local currentIdx = s.currentTier + 1
        local gateFailsCurrentTier = (s.squeezeCharge < (s.tierMinSqueeze[currentIdx] or 0))
                                  or (activeSec < (s.tierMinActiveSec[currentIdx] or 0))
        local demoteThreshold = GetDemoteThreshold(s.currentTier)
        local scoreWantsDemote = s.tierScore <= demoteThreshold
        local holdElapsed = now - s.lastTierChangeAt
        if holdElapsed >= s.tierHoldMinSec and (gateFailsCurrentTier or scoreWantsDemote) then
            s.currentTier = math_max(gatedTier, s.currentTier - 1)
            s.lastTierChangeAt = now
        end
    end

    if not frameC:IsShown() then return end

    local pressureDisplay = s.pressureComposite
    local barValue = math_min(math_max(pressureDisplay, 0.0), 4.0)
    pressureBar:SetValue(barValue)

    local col = TIER_COLORS[s.currentTier + 1] or TIER_COLORS[1]
    pressureBar:SetStatusBarColor(col[1], col[2], col[3])

    barText:SetText(string.format("%.2fx", pressureDisplay))
    barTierText:SetText(string.format("T%d", s.currentTier))
    barTierText:SetTextColor(col[1], col[2], col[3])

    debugText:SetText(string.format(
        "n:%.2f i:%.2f q:%.2f ts:%.2f hk:%.2f %s",
        s.pressureRatio, s.instantScore, s.squeezeCharge, s.tierScore, hitKick, s.tierCapReason))

    for wi = 1, BUCKET_ROWS do
        local w = WINDOWS[wi]
        pressureBucketStrings[wi]:SetText(string.format(
            "%3ds:  avg %.2fx  max %.2fx",
            w, s.pressureBucketAvg[wi], s.pressureBucketMax[wi]
        ))
    end
end

local pressureTickFrame = CreateFrame("Frame")
pressureTickFrame:SetScript("OnUpdate", OnPressureTick)
pressureTickFrame:Hide()  -- starts hidden; /stpoc on enables it

-------------------------------------------------------------------------------
-- Number formatting helper
-------------------------------------------------------------------------------
local function FormatDmg(n)
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 10000 then
        return string.format("%.1fk", n / 1000)
    else
        return tostring(math.floor(n))
    end
end

local function FormatDPS(n)
    return string.format("%.1f", n)
end

-------------------------------------------------------------------------------
-- OnUpdate tick: prune, compute, display
-------------------------------------------------------------------------------
local elapsed_acc = 0

local function OnTick(_, dt)
    elapsed_acc = elapsed_acc + dt
    if elapsed_acc < tickInterval then return end
    elapsed_acc = 0

    local now = GetTime()
    local start = pocStartTime or now
    local count = #events

    -----------------------------------------------------------------------
    -- 1) Prune expired events (head-pointer approach)
    -----------------------------------------------------------------------
    local cutoff = now - retentionSec
    while headIndex <= count and events[headIndex].t < cutoff do
        events[headIndex] = nil  -- free for GC
        headIndex = headIndex + 1
    end

    -- Compact when head has drifted past half the array
    if headIndex > 1 and headIndex > (count / 2) then
        local newArr = {}
        local j = 0
        for i = headIndex, count do
            if events[i] then
                j = j + 1
                newArr[j] = events[i]
            end
        end
        events = newArr
        headIndex = 1
    end

    -----------------------------------------------------------------------
    -- 2) Single-pass: accumulate damage into window buckets
    -----------------------------------------------------------------------
    local dmg = {}  -- parallel to WINDOWS {300,60,30,15,5}
    for wi = 1, NUM_WINDOWS do dmg[wi] = 0 end
    local eventCount300 = 0
    local liveCount = 0

    for i = headIndex, #events do
        local ev = events[i]
        if ev then
            local age = now - ev.t
            liveCount = liveCount + 1
            for wi = 1, NUM_WINDOWS do
                if age <= WINDOWS[wi] then
                    dmg[wi] = dmg[wi] + ev.amount
                    if wi == 1 then eventCount300 = eventCount300 + 1 end
                end
            end
        end
    end

    -----------------------------------------------------------------------
    -- 3) Update Frame B: metrics text
    -----------------------------------------------------------------------
    if frameB:IsShown() then
        for wi = 1, NUM_WINDOWS do
            local w = WINDOWS[wi]
            local dps = (w > 0) and (dmg[wi] / w) or 0
            local label = string.format("%3ds", w)
            local extra = ""
            if wi == 1 then
                extra = string.format("  (%d events)", eventCount300)
            end
            metricStrings[wi]:SetText(string.format(
                "%s:  %s dmg   %s DPS%s",
                label, FormatDmg(dmg[wi]), FormatDPS(dps), extra
            ))
        end
        countString:SetText(string.format("Buffer: %d events | head: %d | uptime: %.0fs",
            liveCount, headIndex, now - start))
    end

    -----------------------------------------------------------------------
    -- 4) Update Frame A: recent events list (newest first)
    -----------------------------------------------------------------------
    if frameA:IsShown() then
        local total = #events
        local written = 0
        for idx = total, headIndex, -1 do
            if written >= visibleLines then break end
            local ev = events[idx]
            if ev then
                written = written + 1
                local relTime = ev.t - start
                local critStr = ev.crit and "CRIT" or ""
                local targetStr = (ev.target and ev.target ~= "") and ("-> " .. ev.target) or ""
                lineStrings[written]:SetText(string.format(
                    "%-7.2f  %-9s %-18s %6d  %-4s  %s",
                    relTime, ev.eventType, ev.spellName, ev.amount, critStr, targetStr
                ))
                -- Color crit lines
                if ev.crit then
                    lineStrings[written]:SetTextColor(1, 0.4, 0.4)
                else
                    lineStrings[written]:SetTextColor(0.9, 0.9, 0.9)
                end
            end
        end
        -- Clear remaining lines
        for i = written + 1, visibleLines do
            if lineStrings[i] then
                lineStrings[i]:SetText("")
            end
        end
    end
end

-- Attach tick to Frame A (runs when either frame is shown)
local tickFrame = CreateFrame("Frame")
tickFrame:SetScript("OnUpdate", OnTick)
tickFrame:Hide()  -- starts hidden; /stpoc on enables it

-------------------------------------------------------------------------------
-- Show / Hide helpers
-------------------------------------------------------------------------------
local function ShowPOC()
    if not pocStartTime then pocStartTime = GetTime() end
    frameA:Show()
    frameB:Show()
    frameC:Show()
    tickFrame:Show()
    pressureTickFrame:Show()
    print(ADDON_PREFIX .. " frames shown. Attack a mob to see events.")
end

local function HidePOC()
    frameA:Hide()
    frameB:Hide()
    frameC:Hide()
    tickFrame:Hide()
    pressureTickFrame:Hide()
    print(ADDON_PREFIX .. " frames hidden.")
end

local function ClearPOC()
    events = {}
    headIndex = 1
    pocStartTime = nil
    -- Reset pressure
    PS.fastCharge = 0
    PS.slowCharge = 0
    PS.pressureRatio = 0
    PS.pressureDisplaySmoothed = 0
    PS.pressureComposite = 0
    PS.instantScore = 0
    PS.squeezeScore = 0
    PS.tierScore = 0
    PS.currentTier = 0
    PS.lastTierChangeAt = 0
    PS.tierCapReason = "ok"
    PS.recentHitImpulse = 0
    PS.squeezeCharge = 0
    PS.firstPressureAt = nil
    PS.lastDamageTime = 0
    PS.pressureSamples = {}
    PS.pressureSampleHead = 1
    PS.pressureElapsed = 0
    PS.bucketStatsElapsed = 0
    PS.dtDebugAcc = 0
    for wi = 1, #WINDOWS do
        PS.pressureBucketAvg[wi] = 0
        PS.pressureBucketMax[wi] = 0
    end
    -- Clear Frame A display
    for i = 1, visibleLines do
        if lineStrings[i] then
            lineStrings[i]:SetText("")
        end
    end
    -- Clear Frame B display
    for i = 1, NUM_WINDOWS do
        metricStrings[i]:SetText("")
    end
    countString:SetText("")
    -- Clear Frame C display
    pressureBar:SetValue(0.0)
    pressureBar:SetStatusBarColor(0.5, 0.5, 0.5)
    barText:SetText("0.00x")
    barTierText:SetText("T0")
    debugText:SetText("n:0.00 i:0.00 q:0.00 ts:0.00 hk:0.00 ok")
    for i = 1, BUCKET_ROWS do
        pressureBucketStrings[i]:SetText("")
    end
    print(ADDON_PREFIX .. " cleared all events and reset.")
end

-------------------------------------------------------------------------------
-- Slash commands: /stpoc
-------------------------------------------------------------------------------
SLASH_STPOC1 = "/stpoc"
SlashCmdList["STPOC"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")  -- trim
    local cmd, arg = msg:match("^(%S+)%s*(.-)$")
    if not cmd or cmd == "" then cmd = "on" end

    if cmd == "on" then
        ShowPOC()
    elseif cmd == "off" then
        HidePOC()
    elseif cmd == "clear" or cmd == "reset" then
        ClearPOC()
    elseif cmd == "lines" then
        local n = tonumber(arg)
        if n and n >= 5 and n <= 100 then
            visibleLines = n
            RebuildLineStrings()
            print(ADDON_PREFIX .. " visible lines set to " .. visibleLines)
        else
            print(ADDON_PREFIX .. " usage: /stpoc lines 5-100  (current: " .. visibleLines .. ")")
        end
    elseif cmd == "history" then
        local n = tonumber(arg)
        if n and n >= 10 and n <= 600 then
            retentionSec = n
            print(ADDON_PREFIX .. " retention set to " .. retentionSec .. "s")
        else
            print(ADDON_PREFIX .. " usage: /stpoc history 10-600  (current: " .. retentionSec .. "s)")
        end
    elseif cmd == "pressure" then
        if arg == "off" then
            frameC:Hide()
            print(ADDON_PREFIX .. " pressure frame hidden.")
        else
            frameC:Show()
            pressureTickFrame:Show()
            print(ADDON_PREFIX .. " pressure frame shown.")
        end
    elseif cmd == "taufast" then
        local n = tonumber(arg)
        if n and n >= 0.1 and n <= 30 then
            PS.tauFast = n
            print(ADDON_PREFIX .. " tauFast set to " .. string.format("%.2f", PS.tauFast) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /stpoc taufast 0.1-30  (current: " .. string.format("%.2f", PS.tauFast) .. "s)")
        end
    elseif cmd == "tauslow" then
        local n = tonumber(arg)
        if n and n >= 1 and n <= 120 then
            PS.tauSlow = n
            print(ADDON_PREFIX .. " tauSlow set to " .. string.format("%.2f", PS.tauSlow) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /stpoc tauslow 1-120  (current: " .. string.format("%.2f", PS.tauSlow) .. "s)")
        end
    elseif cmd == "gain" then
        local n = tonumber(arg)
        if n and n >= 0.1 and n <= 10 then
            PS.displayGain = n
            print(ADDON_PREFIX .. " displayGain set to " .. string.format("%.1f", PS.displayGain))
        else
            print(ADDON_PREFIX .. " usage: /stpoc gain 0.1-10  (current: " .. string.format("%.1f", PS.displayGain) .. ")")
        end
    elseif cmd == "damp" then
        local n = tonumber(arg)
        if n and n >= 0 and n <= 2 then
            PS.burstDamping = n
            print(ADDON_PREFIX .. " burstDamping set to " .. string.format("%.2f", PS.burstDamping))
        else
            print(ADDON_PREFIX .. " usage: /stpoc damp 0-2  (current: " .. string.format("%.2f", PS.burstDamping) .. ")")
        end
    elseif cmd == "smoothtau" then
        local n = tonumber(arg)
        if n and n >= 0.05 and n <= 5 then
            PS.displayTau = n
            print(ADDON_PREFIX .. " displayTau set to " .. string.format("%.2f", PS.displayTau) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /stpoc smoothtau 0.05-5  (current: " .. string.format("%.2f", PS.displayTau) .. "s)")
        end
    elseif cmd == "squeezetau" then
        local n = tonumber(arg)
        if n and n >= 3 and n <= 60 then
            PS.squeezeDecayTau = n
            print(ADDON_PREFIX .. " squeezeDecayTau set to " .. string.format("%.1f", PS.squeezeDecayTau) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /stpoc squeezetau 3-60  (current: " .. string.format("%.1f", PS.squeezeDecayTau) .. "s)")
        end
    elseif cmd == "squeezebuild" then
        local n = tonumber(arg)
        if n and n >= 0.05 and n <= 3 then
            PS.squeezeBuildRate = n
            print(ADDON_PREFIX .. " squeezeBuildRate set to " .. string.format("%.2f", PS.squeezeBuildRate))
        else
            print(ADDON_PREFIX .. " usage: /stpoc squeezebuild 0.05-3  (current: " .. string.format("%.2f", PS.squeezeBuildRate) .. ")")
        end
    elseif cmd == "t4charge" then
        local n = tonumber(arg)
        if n and n >= 0 and n <= 1 then
            PS.tierMinSqueeze[5] = n
            print(ADDON_PREFIX .. " T4 squeeze gate set to " .. string.format("%.2f", PS.tierMinSqueeze[5]))
        else
            print(ADDON_PREFIX .. " usage: /stpoc t4charge 0-1  (current: " .. string.format("%.2f", PS.tierMinSqueeze[5]) .. ")")
        end
    elseif cmd == "t5charge" then
        local n = tonumber(arg)
        if n and n >= 0 and n <= 1 then
            PS.tierMinSqueeze[6] = n
            print(ADDON_PREFIX .. " T5 squeeze gate set to " .. string.format("%.2f", PS.tierMinSqueeze[6]))
        else
            print(ADDON_PREFIX .. " usage: /stpoc t5charge 0-1  (current: " .. string.format("%.2f", PS.tierMinSqueeze[6]) .. ")")
        end
    elseif cmd == "t4time" then
        local n = tonumber(arg)
        if n and n >= 0 and n <= 30 then
            PS.tierMinActiveSec[5] = n
            print(ADDON_PREFIX .. " T4 time gate set to " .. string.format("%.1f", PS.tierMinActiveSec[5]) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /stpoc t4time 0-30  (current: " .. string.format("%.1f", PS.tierMinActiveSec[5]) .. "s)")
        end
    elseif cmd == "t5time" then
        local n = tonumber(arg)
        if n and n >= 0 and n <= 60 then
            PS.tierMinActiveSec[6] = n
            print(ADDON_PREFIX .. " T5 time gate set to " .. string.format("%.1f", PS.tierMinActiveSec[6]) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /stpoc t5time 0-60  (current: " .. string.format("%.1f", PS.tierMinActiveSec[6]) .. "s)")
        end
    elseif cmd == "hysteresis" then
        local n = tonumber(arg)
        if n and n >= 0 and n <= 1 then
            PS.tierHysteresis = n
            print(ADDON_PREFIX .. " tierHysteresis set to " .. string.format("%.2f", PS.tierHysteresis))
        else
            print(ADDON_PREFIX .. " usage: /stpoc hysteresis 0-1  (current: " .. string.format("%.2f", PS.tierHysteresis) .. ")")
        end
    elseif cmd == "dtcheck" then
        if arg == "on" then
            PS.dtDebugEnabled = true
            PS.dtDebugAcc = 0
            print(ADDON_PREFIX .. " dt sanity stream ON (prints ~1/sec)")
        elseif arg == "off" then
            PS.dtDebugEnabled = false
            print(ADDON_PREFIX .. " dt sanity stream OFF")
        end
        print(ADDON_PREFIX .. string.format(" [dt sanity] tauFast=%.2f  tauSlow=%.2f  scale=%.4f  tick=%.3fs",
            PS.tauFast, PS.tauSlow, PS.tauFast / PS.tauSlow, PS.pressureTick))
        print(ADDON_PREFIX .. string.format(
            " [dt sanity] n=%.3f i=%.3f q=%.2f ts=%.3f hk=%.2f T%d cap=%s",
            PS.pressureRatio, PS.instantScore, PS.squeezeCharge, PS.tierScore,
            math_min((PS.recentHitImpulse / math_max(PS.epsilon, PS.slowCharge * (PS.tauFast / math_max(PS.tauSlow, 0.001)))) * 0.25, 1.0),
            PS.currentTier, PS.tierCapReason))
    else
        print(ADDON_PREFIX .. " commands:")
        print("  /stpoc on          - show all frames")
        print("  /stpoc off         - hide all frames")
        print("  /stpoc clear       - clear all events + pressure")
        print("  /stpoc lines N     - visible lines (5-100, default 25)")
        print("  /stpoc history N   - retention seconds (10-600, default 300)")
        print("  /stpoc pressure on|off  - toggle pressure frame")
        print("  /stpoc taufast N   - fast decay tau (0.1-30, default 1.0)")
        print("  /stpoc tauslow N   - slow decay tau (1-120, default 20.0)")
        print("  /stpoc gain N      - display multiplier (0.1-10, default 1.20)")
        print("  /stpoc damp N      - burst damping (0-2, default 1.20)")
        print("  /stpoc smoothtau N - display EMA tau (0.05-5, default 0.30)")
        print("  /stpoc squeezetau N   - squeeze decay seconds (3-60, default 18.0)")
        print("  /stpoc squeezebuild N - squeeze build rate (0.05-3, default 0.30)")
        print("  /stpoc t4charge N     - min squeeze for T4 (0-1, default 0.70)")
        print("  /stpoc t5charge N     - min squeeze for T5 (0-1, default 0.92)")
        print("  /stpoc t4time N       - min active seconds for T4 (0-30, default 7)")
        print("  /stpoc t5time N       - min active seconds for T5 (0-60, default 14)")
        print("  /stpoc hysteresis N   - tier demote margin (0-1, default 0.10)")
        print("  /stpoc dtcheck [on|off] - dt sanity values (+ optional stream)")
    end
end
