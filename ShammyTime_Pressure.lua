-- ShammyTime_Pressure.lua
-- Production pressure frame + tier engine (ported from PoC model).
-- Reads outgoing damage from combat log, computes pressure/tier state, and
-- drives gauge + color overlay from T0-T5.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local ShammyTime = _G.ShammyTime
if not ShammyTime then return end

local M = _G.ShammyTime_Media
if not M then return end

local math_exp = math.exp
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local math_floor = math.floor
local bit_band = bit and bit.band

local ADDON_PREFIX = "|cff00b4ff[ShammyTime]|r"
local FONT_PATH = "Fonts\\FRIZQT__.TTF"
local WINDOWS = { 300, 60, 30, 15, 5 }
local NUM_WINDOWS = #WINDOWS

local SIZE = 1024
local DEFAULT_SCALE = 0.5
local CROP_TOP = 0.28
local CROP_BOTTOM = 0.33
local MIN_FILL_U = 0.001
local FILL_SHOW_EPS = 0.003
local FILL_HIDE_EPS = 0.0005
local FILL_SMOOTH_TAU_RISE = 0.30
local FILL_SMOOTH_TAU_FALL = 2.04
local FILL_FULL_HOLD_SEC = 0.40
local FILL_FULL_EPSILON = 0.995
local OVERLAY_COLOR_TAU_IN = 0.08
local OVERLAY_COLOR_TAU_OUT = 0.16
local PUSH_FEEL_CFG = {
    fillSmoothTauEdgeMult = 1.95,
    fillMass = 10.0,
    fillTransferDropSec = 0.78,
    fillTransferRubberDamping = 4.10,
    fillTransferRubberOscillations = 1.60,
    fillTransferLandingFloor = 0.08,
    promotionVisualFullEpsilon = 0.985,
    fillPullResistStart = 0.80,
    fillPullLowerPower = 1.12,
    fillPullEdgePower = 2.20,
    tierPullBaseResistMax = 0.06,
    tierPullBaseResistPower = 1.14,
    tierPullEdgeStart = 0.80,
    tierPullEdgeResistMax = 0.22,
    tierPullEdgeResistPower = 2.30,
    tierPromotionStepLockSec = 0.35,
    gaugeShakeTriggerFill = 0.90,
    gaugeShakeStressTauIn = 0.12,
    gaugeShakeStressTauOut = 0.26,
    gaugeShakeMaxX = 1.30,
    gaugeShakeMaxY = 0.95,
    gaugeShakeFreqX1 = 35.0,
    gaugeShakeFreqX2 = 52.0,
    gaugeShakeFreqY1 = 41.0,
}
local PS
local SmoothAlpha
local VISIBLE_HEIGHT_FRACTION = 1 - CROP_TOP - CROP_BOTTOM
if VISIBLE_HEIGHT_FRACTION <= 0 then
    VISIBLE_HEIGHT_FRACTION = 1
end
local DISPLAY_WIDTH = SIZE
local DISPLAY_HEIGHT = SIZE * VISIBLE_HEIGHT_FRACTION

local SLOT_CASTS = 1
local SLOT_FIRE = 2
local SLOT_WIND = 3
local SLOT_ORDER = { SLOT_CASTS, SLOT_FIRE, SLOT_WIND }

local STORMSTRIKE_SPELL_ID = 17364
local STORMSTRIKE_SPELL_IDS = {
    [17364] = true,
    [32175] = true, -- Stormstrike off-hand damage event
}
local LAVA_LASH_SPELL_IDS = {
    [60103] = true, -- WotLK/Cata-era ID (safe fallback)
    [73680] = true,
}
local CHAIN_LIGHTNING_SPELL_IDS = {
    [421] = true,
    [930] = true,
    [2860] = true,
    [10605] = true,
    [25439] = true,
    [25442] = true,
}
local EARTH_SHOCK_SPELL_IDS = {
    [8042] = true,
    [8044] = true,
    [8045] = true,
    [8046] = true,
    [10412] = true,
    [10413] = true,
    [10414] = true,
    [25454] = true,
}
local FLAME_SHOCK_SPELL_IDS = {
    [8050] = true,
    [8052] = true,
    [8053] = true,
    [10447] = true,
    [10448] = true,
    [29228] = true,
    [25457] = true,
}
local FROST_SHOCK_SPELL_IDS = {
    [8056] = true,
    [8058] = true,
    [10472] = true,
    [10473] = true,
    [25464] = true,
}
local FIRE_NOVA_SPELL_IDS = {
    [1535] = true,
    [8498] = true,
    [8499] = true,
    [11314] = true,
    [11315] = true,
    [25546] = true,
    [61649] = true,
}
local MAGMA_TOTEM_SPELL_IDS = {
    [8187] = true,
    [10579] = true,
    [10580] = true,
    [10581] = true,
    [25550] = true,
}
local WINDFURY_ATTACK_SPELL_ID = 25584
local WINDFURY_TOTEM_EXTRA_ATTACKS_SPELL_ID = 8516

local SLOT_POPUP_CFG = {
    iconSizeDefault = 74,
    iconSize = 74,
    iconInset = 0.08,
    popupHoldSecDefault = 5.20,
    popupHoldSec = 5.20,
    popupFadeSecDefault = 1.20,
    popupFadeSec = 1.20,
    popupSustainSecDefault = 6.00,
    popupSustainSec = 6.00,
    baseFontSizeDefault = 49,
    baseFontSize = 49,
    textCritPulseScaleDefault = 2.00,
    textCritPulseScale = 2.00,
    textCritPulseSecDefault = 0.20,
    textCritPulseSec = 0.20,
    popupFastEndFadeFraction = 0.50,
    jackpotBangThreshold = 6000,
    iconSizeMin = 24,
    iconSizeMax = 192,
    textSizeMin = 8,
    textSizeMax = 72,
    popupHoldSecMin = 0.10,
    popupHoldSecMax = 10.0,
    popupFadeSecMin = 0.10,
    popupFadeSecMax = 10.0,
    popupSustainSecMin = 0.20,
    popupSustainSecMax = 15.0,
    textCritPulseScaleMin = 1.00,
    textCritPulseScaleMax = 2.50,
    textCritPulseSecMin = 0.05,
    textCritPulseSecMax = 1.50,
}

local PRESSURE_VISUAL_CFG = {
    idleDamageGraceSec = 0.80,
    visualActivityEps = 0.015,
    visualOverlayEps = 0.004,
}

local STORMSTRIKE_SWING_WINDOW_SEC = 0.60
local STORMSTRIKE_SWING_MAX_HITS = 2
local STORMSTRIKE_MERGE_WINDOW_SEC = 0.24
local CHAIN_LIGHTNING_CAST_WINDOW_SEC = 0.40
local FLAME_SHOCK_ROLLING_RESET_SEC = 4.50
local MAGMA_ROLLING_RESET_SEC = 4.50
local FIRE_AOE_MERGE_WINDOW_SEC = 0.32
local FIRE_AOE_MIN_POP_INTERVAL_SEC = 0.30
local WINDFURY_BURST_WINDOW_SEC = (M and M.WF_CORRELATION_WINDOW) or 0.40
local WINDFURY_MAX_HITS_PER_BURST = 2

local SLOT_VISUAL = {
    [SLOT_CASTS] = {
        offsetX = -130,
        offsetY = -104,
        defaultOffsetX = -130,
        defaultOffsetY = -104,
        dbXKey = "pressureSlot1X",
        dbYKey = "pressureSlot1Y",
        textOffsetX = 0,
        textOffsetY = -14,
        defaultTextOffsetX = 0,
        defaultTextOffsetY = -14,
        dbTextXKey = "pressureSlot1TextX",
        dbTextYKey = "pressureSlot1TextY",
        rotationDeg = -15,
        defaultSpellId = STORMSTRIKE_SPELL_ID,
        fallbackTexture = "Interface\\Icons\\Spell_Nature_StormStrike",
    },
    [SLOT_FIRE] = {
        offsetX = 1,
        offsetY = -123,
        defaultOffsetX = 1,
        defaultOffsetY = -123,
        dbXKey = "pressureSlot2X",
        dbYKey = "pressureSlot2Y",
        textOffsetX = 0,
        textOffsetY = -16,
        defaultTextOffsetX = 0,
        defaultTextOffsetY = -16,
        dbTextXKey = "pressureSlot2TextX",
        dbTextYKey = "pressureSlot2TextY",
        rotationDeg = 0,
        defaultSpellId = 8187,
        fallbackTexture = "Interface\\Icons\\Spell_Fire_SealOfFire",
    },
    [SLOT_WIND] = {
        offsetX = 135,
        offsetY = -104,
        defaultOffsetX = 135,
        defaultOffsetY = -104,
        dbXKey = "pressureSlot3X",
        dbYKey = "pressureSlot3Y",
        textOffsetX = -7,
        textOffsetY = -18,
        defaultTextOffsetX = -7,
        defaultTextOffsetY = -18,
        dbTextXKey = "pressureSlot3TextX",
        dbTextYKey = "pressureSlot3TextY",
        rotationDeg = 15,
        defaultSpellId = WINDFURY_ATTACK_SPELL_ID,
        fallbackTexture = "Interface\\Icons\\Spell_Nature_Cyclone",
    },
}

local function ClampNumber(value, defaultValue, minValue, maxValue)
    local n = tonumber(value)
    if not n then
        n = defaultValue
    end
    if minValue and n < minValue then
        n = minValue
    end
    if maxValue and n > maxValue then
        n = maxValue
    end
    return n
end

local function GetPressurePopupDBNumber(key, defaultValue, minValue, maxValue)
    local db = ShammyTime.GetDB and ShammyTime.GetDB()
    local raw = db and db[key]
    return ClampNumber(raw, defaultValue, minValue, maxValue)
end

local STACK = {
    { key = "backgroundSquares",            file = "Pressure\\v2_pressure_bar_background_squares_1024x1024.tga", layer = "ARTWORK",    sub = 0 },
    { key = "background",                   file = "Pressure\\v2_pressure_bar_background_1024x1024.tga",         layer = "ARTWORK",    sub = 2 },
    { key = "colorOverlay",                 file = "Pressure\\v2_pressure_bar_color_overlay_on_1024x1024.tga",   layer = "ARTWORK",    sub = 3 },
    { key = "gaugeZero",                    file = "Pressure\\v2_pressure_gauge_zero_pct_1024x1024.tga",         layer = "ARTWORK",    sub = 4 },
    { key = "gaugeTen",                     file = "Pressure\\v2_pressure_gauge_ten_pct_1024x1024.tga",          layer = "ARTWORK",    sub = 5 },
    { key = "gaugeFifty",                   file = "Pressure\\v2_pressure_gauge_fifty_pct_1024x1024.tga",        layer = "ARTWORK",    sub = 6 },
    { key = "gaugeSeventyFive",             file = "Pressure\\v2_pressure_gauge_seventyfive_pct_1024x1024.tga",  layer = "ARTWORK",    sub = 7 },
    { key = "gaugeHundred",                 file = "Pressure\\v2_pressure_gauge_hundred_pct_1024x1024.tga",      layer = "ARTWORK",    sub = 7 },
}

local frame = CreateFrame("Frame", "ShammyTimePressureFrame", UIParent)
frame:SetSize(DISPLAY_WIDTH, DISPLAY_HEIGHT)
frame:SetPoint("CENTER", 0, 0)
frame:SetFrameStrata("LOW")
frame:SetScale(DEFAULT_SCALE)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame.textures = {}

for _, info in ipairs(STACK) do
    local tex = frame:CreateTexture(nil, info.layer)
    tex:SetDrawLayer(info.layer, info.sub)
    tex:SetTexture(M.MEDIA .. info.file)
    tex:SetTexCoord(0, 1, CROP_TOP, 1 - CROP_BOTTOM)
    tex:SetAllPoints(frame)
    frame.textures[info.key] = tex
end

local function FormatCompactDamage(value)
    local v = math_max(tonumber(value) or 0, 0)
    if v < 1000 then
        return tostring(math_floor(v + 0.5))
    end
    if v < 1000000 then
        local short = string.format("%.1fk", v / 1000)
        return (short:gsub("%.0k", "k"))
    end
    local short = string.format("%.1fm", v / 1000000)
    return (short:gsub("%.0m", "m"))
end

local function SpellNameEquals(spellName, expected)
    return spellName and expected and spellName == expected
end

local function SpellNameContains(spellName, token)
    return spellName and token and spellName:find(token, 1, true)
end

local function BuildPopupText(amount, hadCrit)
    local a = tonumber(amount) or 0
    local text = FormatCompactDamage(a)
    if a >= SLOT_POPUP_CFG.jackpotBangThreshold or (hadCrit and a >= 3500) then
        text = text .. "!"
    end
    return text
end

local SLOT_TEXT_NORMAL = { 1.00, 1.00, 0.00 }
local SLOT_TEXT_CRIT = { 1.00, 1.00, 0.00 }

local function SetOptionalTextRotation(text, radians)
    if text and text.SetRotation then
        text:SetRotation(radians or 0)
    end
end

local function NewPopupState()
    return {
        active = false,
        spellId = nil,
        amount = 0,
        hadCrit = false,
        sustain = false,
        sustainUntil = 0,
        holdUntil = 0,
        fadeUntil = 0,
        critPulseStartAt = 0,
        critPulseUntil = 0,
    }
end

local function ResetPopupState(state)
    state.active = false
    state.spellId = nil
    state.amount = 0
    state.hadCrit = false
    state.sustain = false
    state.sustainUntil = 0
    state.holdUntil = 0
    state.fadeUntil = 0
    state.critPulseStartAt = 0
    state.critPulseUntil = 0
end

local driverSlots = {}
for _, slotId in ipairs(SLOT_ORDER) do
    local cfg = SLOT_VISUAL[slotId]
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetDrawLayer("ARTWORK", 1)
    icon:SetSize(SLOT_POPUP_CFG.iconSize, SLOT_POPUP_CFG.iconSize)
    icon:SetPoint("CENTER", frame, "CENTER", cfg.offsetX, cfg.offsetY)
    icon:SetTexture(GetSpellTexture(cfg.defaultSpellId) or cfg.fallbackTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetTexCoord(
        SLOT_POPUP_CFG.iconInset,
        1 - SLOT_POPUP_CFG.iconInset,
        SLOT_POPUP_CFG.iconInset,
        1 - SLOT_POPUP_CFG.iconInset
    )
    icon:SetRotation(math.rad(cfg.rotationDeg or 0))

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetFont(FONT_PATH, SLOT_POPUP_CFG.baseFontSize, "OUTLINE")
    text:SetPoint("TOP", icon, "TOP", cfg.textOffsetX or 0, cfg.textOffsetY or -3)
    text:SetTextColor(SLOT_TEXT_NORMAL[1], SLOT_TEXT_NORMAL[2], SLOT_TEXT_NORMAL[3])
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    SetOptionalTextRotation(text, math.rad(cfg.rotationDeg or 0))

    driverSlots[slotId] = {
        slotId = slotId,
        cfg = cfg,
        icon = icon,
        text = text,
        base = NewPopupState(),
        overlay = NewPopupState(),
    }
end

local spellSlotClaims = {}

local function HideSlotVisual(slot)
    if not slot then return end
    slot.icon:SetScale(1)
    slot.text:SetScale(1)
    slot.icon:SetAlpha(0)
    slot.text:SetAlpha(0)
    slot.icon:Hide()
    slot.text:Hide()
end

local function TriggerTextCritPulse(state, hadCritEvent, now)
    if not state or not hadCritEvent then return end
    state.critPulseStartAt = now
    state.critPulseUntil = now + SLOT_POPUP_CFG.textCritPulseSec
end

local function GetTextCritPulseScale(state, now)
    if not state then return 1 end
    local s = tonumber(state.critPulseStartAt) or 0
    local e = tonumber(state.critPulseUntil) or 0
    if now <= s or now >= e then
        return 1
    end
    local dur = math_max(e - s, 0.001)
    local t = math_min(math_max((now - s) / dur, 0), 1)
    if t <= 0.5 then
        return 1 + (SLOT_POPUP_CFG.textCritPulseScale - 1) * (t / 0.5)
    end
    return SLOT_POPUP_CFG.textCritPulseScale - (SLOT_POPUP_CFG.textCritPulseScale - 1) * ((t - 0.5) / 0.5)
end

local function ConfigurePopupStateFromEvent(state, spellId, amount, hadCritTotal, hadCritEvent, isSustain, now)
    if not state then return end
    state.active = true
    state.spellId = spellId
    state.amount = math_max(tonumber(amount) or 0, 0)
    state.hadCrit = hadCritTotal and true or false
    if isSustain then
        state.sustain = true
        state.sustainUntil = now + SLOT_POPUP_CFG.popupSustainSec
        state.holdUntil = state.sustainUntil
    else
        state.sustain = false
        state.sustainUntil = 0
        state.holdUntil = now + SLOT_POPUP_CFG.popupHoldSec
    end
    state.fadeUntil = state.holdUntil + SLOT_POPUP_CFG.popupFadeSec
    TriggerTextCritPulse(state, hadCritEvent, now)
end

local function AdvancePopupState(state, now)
    if not state or not state.active then
        return false
    end
    if state.sustain and now > state.sustainUntil then
        state.sustain = false
        state.sustainUntil = 0
        state.holdUntil = now
        state.fadeUntil = now + SLOT_POPUP_CFG.popupFadeSec
    end
    if now >= state.fadeUntil then
        ResetPopupState(state)
        return false
    end
    return true
end

local function GetPopupStateAlpha(state, now)
    if not state or not state.active then
        return 0
    end
    if state.sustain and now <= state.sustainUntil then
        return 1
    end
    if now <= state.holdUntil then
        return 1
    end
    if now < state.fadeUntil then
        -- Keep total lifetime unchanged, but do the visual fade in the last
        -- portion of the fade window so the end drop feels snappier.
        local fadeWindow = math_max(SLOT_POPUP_CFG.popupFadeSec, 0.01)
        local fastFadeWindow = math_max(fadeWindow * SLOT_POPUP_CFG.popupFastEndFadeFraction, 0.01)
        local fadeStart = state.fadeUntil - fastFadeWindow
        if now <= fadeStart then
            return 1
        end
        local fadeProgress = (now - fadeStart) / fastFadeWindow
        return 1 - math_min(math_max(fadeProgress, 0), 1)
    end
    return 0
end

local function ApplyPopupStateToSlot(slot, state, alpha, now)
    if not slot or not state or not state.active then return end
    local cfg = slot.cfg
    local amount = tonumber(state.amount) or 0
    local hadCrit = state.hadCrit and true or false
    local spellId = state.spellId or cfg.defaultSpellId

    slot.icon:SetTexture(GetSpellTexture(spellId) or cfg.fallbackTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
    slot.icon:SetSize(SLOT_POPUP_CFG.iconSize, SLOT_POPUP_CFG.iconSize)
    slot.icon:ClearAllPoints()
    slot.icon:SetPoint("CENTER", frame, "CENTER", cfg.offsetX, cfg.offsetY)
    slot.icon:SetRotation(math.rad(cfg.rotationDeg or 0))
    slot.icon:SetScale(1)

    slot.text:SetFont(FONT_PATH, SLOT_POPUP_CFG.baseFontSize, "OUTLINE")
    slot.text:SetText(BuildPopupText(amount, hadCrit))
    if hadCrit then
        slot.text:SetTextColor(SLOT_TEXT_CRIT[1], SLOT_TEXT_CRIT[2], SLOT_TEXT_CRIT[3])
    else
        slot.text:SetTextColor(SLOT_TEXT_NORMAL[1], SLOT_TEXT_NORMAL[2], SLOT_TEXT_NORMAL[3])
    end
    slot.text:ClearAllPoints()
    slot.text:SetPoint("TOP", slot.icon, "TOP", cfg.textOffsetX or 0, cfg.textOffsetY or -3)
    SetOptionalTextRotation(slot.text, math.rad(cfg.rotationDeg or 0))
    slot.text:SetScale(GetTextCritPulseScale(state, now))

    slot.icon:SetAlpha(alpha)
    slot.text:SetAlpha(alpha)
    slot.icon:Show()
    slot.text:Show()
end

local function GetClaimedBaseSlot(spellId)
    if not spellId then return nil end
    local slotId = spellSlotClaims[spellId]
    if not slotId then return nil end
    local slot = driverSlots[slotId]
    if not slot or (not slot.base.active) or slot.base.spellId ~= spellId then
        spellSlotClaims[spellId] = nil
        return nil
    end
    return slot
end

local function FindFirstFreeBaseSlot()
    for _, slotId in ipairs(SLOT_ORDER) do
        local slot = driverSlots[slotId]
        if slot and not slot.base.active then
            return slot
        end
    end
    return nil
end

local function GetBaseRemaining(state, now)
    if not state or not state.active then
        return 0
    end
    if state.sustain then
        return math_max((state.sustainUntil or now) - now, 0)
    end
    return math_max((state.fadeUntil or now) - now, 0)
end

local function SelectOverlaySlot(spellId, now)
    for _, slotId in ipairs(SLOT_ORDER) do
        local slot = driverSlots[slotId]
        if slot and slot.overlay.active and slot.overlay.spellId == spellId then
            return slot
        end
    end

    local best = nil
    local bestRemaining = nil
    local function consider(slot)
        local remaining = GetBaseRemaining(slot.base, now)
        if not best or remaining < bestRemaining then
            best = slot
            bestRemaining = remaining
        end
    end

    for _, slotId in ipairs(SLOT_ORDER) do
        local slot = driverSlots[slotId]
        if slot and slot.base.active and (not slot.base.sustain) then
            consider(slot)
        end
    end
    if best then
        return best
    end

    for _, slotId in ipairs(SLOT_ORDER) do
        local slot = driverSlots[slotId]
        if slot and slot.base.active then
            consider(slot)
        end
    end

    return best or driverSlots[SLOT_ORDER[1]]
end

local function StartOrUpdateBasePopup(spellId, amount, hadCritTotal, hadCritEvent, isSustain, now)
    local slot = GetClaimedBaseSlot(spellId)
    if slot then
        ConfigurePopupStateFromEvent(slot.base, spellId, amount, hadCritTotal, hadCritEvent, isSustain, now)
        return true
    end

    slot = FindFirstFreeBaseSlot()
    if not slot then
        return false
    end

    local previousSpellId = slot.base.spellId
    if previousSpellId then
        spellSlotClaims[previousSpellId] = nil
    end
    ResetPopupState(slot.base)
    ConfigurePopupStateFromEvent(slot.base, spellId, amount, hadCritTotal, hadCritEvent, isSustain, now)
    spellSlotClaims[spellId] = slot.slotId
    return true
end

local function StartOrUpdateOverlayPopup(slot, spellId, amount, hadCritTotal, hadCritEvent, now)
    if not slot then return end
    if slot.overlay.active and slot.overlay.spellId ~= spellId then
        ResetPopupState(slot.overlay)
    end
    ConfigurePopupStateFromEvent(slot.overlay, spellId, amount, hadCritTotal, hadCritEvent, false, now)
end

-- `_preferredSlotId` is accepted for compatibility with existing call sites,
-- but slot assignment is always dynamic left-to-right based on free claims.
local function QueueDriverSlotPopup(_preferredSlotId, spellId, amount, hadCritTotal, opts)
    local a = tonumber(amount) or 0
    if (not spellId) or a <= 0 then return end

    local options = opts or {}
    local now = options.now or GetTime()
    local isSustain = options.sustain and true or false
    local totalCrit = hadCritTotal and true or false
    local hadCritEvent = options.critEvent
    if hadCritEvent == nil then
        hadCritEvent = totalCrit
    else
        hadCritEvent = hadCritEvent and true or false
    end

    if StartOrUpdateBasePopup(spellId, a, totalCrit, hadCritEvent, isSustain, now) then
        return
    end

    local overlaySlot = SelectOverlaySlot(spellId, now)
    StartOrUpdateOverlayPopup(overlaySlot, spellId, a, totalCrit, hadCritEvent, now)
end

local function ShowOrUpdateSustainedSlot(_preferredSlotId, spellId, totalAmount, hadCritTotal, now, hadCritEvent)
    QueueDriverSlotPopup(_preferredSlotId, spellId, totalAmount, hadCritTotal, {
        now = now or GetTime(),
        sustain = true,
        critEvent = hadCritEvent,
    })
end

local function ApplyPressurePopupDevSettings()
    SLOT_POPUP_CFG.iconSize = GetPressurePopupDBNumber(
        "pressurePopupIconSize",
        SLOT_POPUP_CFG.iconSizeDefault,
        SLOT_POPUP_CFG.iconSizeMin,
        SLOT_POPUP_CFG.iconSizeMax
    )
    SLOT_POPUP_CFG.baseFontSize = GetPressurePopupDBNumber(
        "pressurePopupTextSize",
        SLOT_POPUP_CFG.baseFontSizeDefault,
        SLOT_POPUP_CFG.textSizeMin,
        SLOT_POPUP_CFG.textSizeMax
    )
    SLOT_POPUP_CFG.popupHoldSec = GetPressurePopupDBNumber(
        "pressurePopupHoldSec",
        SLOT_POPUP_CFG.popupHoldSecDefault,
        SLOT_POPUP_CFG.popupHoldSecMin,
        SLOT_POPUP_CFG.popupHoldSecMax
    )
    SLOT_POPUP_CFG.popupFadeSec = GetPressurePopupDBNumber(
        "pressurePopupFadeSec",
        SLOT_POPUP_CFG.popupFadeSecDefault,
        SLOT_POPUP_CFG.popupFadeSecMin,
        SLOT_POPUP_CFG.popupFadeSecMax
    )
    SLOT_POPUP_CFG.popupSustainSec = GetPressurePopupDBNumber(
        "pressurePopupSustainSec",
        SLOT_POPUP_CFG.popupSustainSecDefault,
        SLOT_POPUP_CFG.popupSustainSecMin,
        SLOT_POPUP_CFG.popupSustainSecMax
    )
    SLOT_POPUP_CFG.textCritPulseScale = GetPressurePopupDBNumber(
        "pressurePopupCritBounceScale",
        SLOT_POPUP_CFG.textCritPulseScaleDefault,
        SLOT_POPUP_CFG.textCritPulseScaleMin,
        SLOT_POPUP_CFG.textCritPulseScaleMax
    )
    SLOT_POPUP_CFG.textCritPulseSec = GetPressurePopupDBNumber(
        "pressurePopupCritBounceSec",
        SLOT_POPUP_CFG.textCritPulseSecDefault,
        SLOT_POPUP_CFG.textCritPulseSecMin,
        SLOT_POPUP_CFG.textCritPulseSecMax
    )

    local now = GetTime()
    for _, slotId in ipairs(SLOT_ORDER) do
        local cfg = SLOT_VISUAL[slotId]
        cfg.offsetX = GetPressurePopupDBNumber(cfg.dbXKey, cfg.defaultOffsetX)
        cfg.offsetY = GetPressurePopupDBNumber(cfg.dbYKey, cfg.defaultOffsetY)
        cfg.textOffsetX = GetPressurePopupDBNumber(cfg.dbTextXKey, cfg.defaultTextOffsetX)
        cfg.textOffsetY = GetPressurePopupDBNumber(cfg.dbTextYKey, cfg.defaultTextOffsetY)

        local slot = driverSlots[slotId]
        if slot and slot.overlay.active then
            ApplyPopupStateToSlot(slot, slot.overlay, GetPopupStateAlpha(slot.overlay, now), now)
        elseif slot and slot.base.active then
            ApplyPopupStateToSlot(slot, slot.base, GetPopupStateAlpha(slot.base, now), now)
        elseif slot then
            HideSlotVisual(slot)
        end
    end
end

ShammyTime.ApplyPressurePopupDevSettings = ApplyPressurePopupDevSettings
ApplyPressurePopupDevSettings()

local function HideDriverSlot(slot)
    if not slot then return end
    local baseSpellId = slot.base and slot.base.spellId
    if baseSpellId then
        spellSlotClaims[baseSpellId] = nil
    end
    if slot.base then ResetPopupState(slot.base) end
    if slot.overlay then ResetPopupState(slot.overlay) end
    HideSlotVisual(slot)
end

local function UpdateDriverSlots(now)
    for _, slotId in ipairs(SLOT_ORDER) do
        local slot = driverSlots[slotId]
        if slot then
            local previousBaseSpellId = slot.base.spellId
            local baseWasActive = slot.base.active
            AdvancePopupState(slot.base, now)
            if baseWasActive and (not slot.base.active) and previousBaseSpellId then
                if spellSlotClaims[previousBaseSpellId] == slot.slotId then
                    spellSlotClaims[previousBaseSpellId] = nil
                end
            end

            AdvancePopupState(slot.overlay, now)

            if slot.overlay.active then
                local alpha = GetPopupStateAlpha(slot.overlay, now)
                if alpha > 0 then
                    ApplyPopupStateToSlot(slot, slot.overlay, alpha, now)
                else
                    HideSlotVisual(slot)
                end
            elseif slot.base.active then
                local alpha = GetPopupStateAlpha(slot.base, now)
                if alpha > 0 then
                    ApplyPopupStateToSlot(slot, slot.base, alpha, now)
                else
                    HideSlotVisual(slot)
                end
            else
                HideSlotVisual(slot)
            end
        end
    end
end

for _, slotId in ipairs(SLOT_ORDER) do
    HideDriverSlot(driverSlots[slotId])
end

local playerGUID = UnitGUID("player")

local function IsPlayerSource(sourceGUID)
    if not sourceGUID then return false end
    if playerGUID and sourceGUID == playerGUID then
        return true
    end
    local currentPlayerGUID = UnitGUID("player")
    if currentPlayerGUID then
        playerGUID = currentPlayerGUID
    end
    return sourceGUID == playerGUID
end

local stormstrikeSwingWindow = {
    activeUntil = 0,
    remainingHits = 0,
}

local stormstrikeBurst = {
    total = 0,
    hadCrit = false,
    hits = 0,
    flushAt = 0,
}

local chainLightningBurst = {
    spellId = nil,
    total = 0,
    hadCrit = false,
    flushAt = 0,
}

local flameShockRolling = {
    total = 0,
    hadCrit = false,
    spellId = nil,
    lastTickAt = 0,
}

local magmaRolling = {
    total = 0,
    hadCrit = false,
    spellId = nil,
    lastTickAt = 0,
}

local fireAoeBurst = {
    spellId = nil,
    total = 0,
    hadCrit = false,
    flushAt = 0,
    lastPopAt = 0,
}

local windfuryBurst = {
    active = false,
    total = 0,
    hits = 0,
    hadCrit = false,
    expiresAt = 0,
    pendingTotemSwings = 0,
}

local function IsChainLightningSpell(spellId, spellName)
    return (spellId and CHAIN_LIGHTNING_SPELL_IDS[spellId]) or SpellNameEquals(spellName, "Chain Lightning")
end

local function IsStormstrikeSpell(spellId, spellName)
    return (spellId and STORMSTRIKE_SPELL_IDS[spellId]) or SpellNameContains(spellName, "Stormstrike")
end

local function IsLavaLashSpell(spellId, spellName)
    return (spellId and LAVA_LASH_SPELL_IDS[spellId]) or SpellNameEquals(spellName, "Lava Lash")
end

local function IsEarthShockSpell(spellId, spellName)
    return (spellId and EARTH_SHOCK_SPELL_IDS[spellId]) or SpellNameContains(spellName, "Earth Shock")
end

local function IsFlameShockSpell(spellId, spellName)
    return (spellId and FLAME_SHOCK_SPELL_IDS[spellId]) or SpellNameContains(spellName, "Flame Shock")
end

local function IsFrostShockSpell(spellId, spellName)
    return (spellId and FROST_SHOCK_SPELL_IDS[spellId]) or SpellNameContains(spellName, "Frost Shock")
end

local function IsShockSpell(spellId, spellName)
    return IsEarthShockSpell(spellId, spellName)
        or IsFlameShockSpell(spellId, spellName)
        or IsFrostShockSpell(spellId, spellName)
end

local function IsFireNovaSpell(spellId, spellName)
    return (spellId and FIRE_NOVA_SPELL_IDS[spellId]) or SpellNameContains(spellName, "Fire Nova")
end

local function IsMagmaTotemSpell(spellId, spellName)
    return (spellId and MAGMA_TOTEM_SPELL_IDS[spellId]) or SpellNameContains(spellName, "Magma Totem")
end

local function IsWindfuryAttackSpell(spellId, spellName)
    return spellId == WINDFURY_ATTACK_SPELL_ID or SpellNameEquals(spellName, "Windfury Attack")
end

local function StartStormstrikeBurst(now)
    stormstrikeBurst.total = 0
    stormstrikeBurst.hadCrit = false
    stormstrikeBurst.hits = 0
    stormstrikeBurst.flushAt = now + STORMSTRIKE_MERGE_WINDOW_SEC
end

local function AddStormstrikeDamage(amount, hadCrit, now)
    if stormstrikeBurst.flushAt <= 0 or now > stormstrikeBurst.flushAt then
        StartStormstrikeBurst(now)
    end
    stormstrikeBurst.total = stormstrikeBurst.total + (tonumber(amount) or 0)
    stormstrikeBurst.hadCrit = stormstrikeBurst.hadCrit or (hadCrit and true or false)
    stormstrikeBurst.hits = stormstrikeBurst.hits + 1
    stormstrikeBurst.flushAt = now + STORMSTRIKE_MERGE_WINDOW_SEC

    QueueDriverSlotPopup(SLOT_CASTS, STORMSTRIKE_SPELL_ID, stormstrikeBurst.total, stormstrikeBurst.hadCrit, {
        now = now,
        critEvent = stormstrikeBurst.hadCrit and true or false,
    })

    if stormstrikeBurst.hits >= STORMSTRIKE_SWING_MAX_HITS then
        stormstrikeBurst.total = 0
        stormstrikeBurst.hadCrit = false
        stormstrikeBurst.hits = 0
        stormstrikeBurst.flushAt = 0
    end
end

local function FlushStormstrikeBurstIfDue(now)
    if stormstrikeBurst.flushAt > 0 and now >= stormstrikeBurst.flushAt then
        stormstrikeBurst.total = 0
        stormstrikeBurst.hadCrit = false
        stormstrikeBurst.hits = 0
        stormstrikeBurst.flushAt = 0
    end
end

local function FlushChainLightningBurst(now)
    if chainLightningBurst.total <= 0 then
        chainLightningBurst.total = 0
        chainLightningBurst.hadCrit = false
        chainLightningBurst.flushAt = 0
        chainLightningBurst.spellId = nil
        return
    end
    ShowOrUpdateSustainedSlot(
        SLOT_CASTS,
        chainLightningBurst.spellId or 421,
        chainLightningBurst.total,
        chainLightningBurst.hadCrit,
        now
    )
    chainLightningBurst.total = 0
    chainLightningBurst.hadCrit = false
    chainLightningBurst.flushAt = 0
    chainLightningBurst.spellId = nil
end

local function StartChainLightningCast(now, spellId)
    if chainLightningBurst.total > 0 then
        FlushChainLightningBurst(now)
    end
    chainLightningBurst.spellId = spellId or 421
    chainLightningBurst.total = 0
    chainLightningBurst.hadCrit = false
    chainLightningBurst.flushAt = now + CHAIN_LIGHTNING_CAST_WINDOW_SEC
end

local function AddChainLightningDamage(spellId, amount, hadCrit, now)
    if chainLightningBurst.flushAt <= 0 or now > chainLightningBurst.flushAt then
        StartChainLightningCast(now, spellId)
    end
    chainLightningBurst.spellId = spellId or chainLightningBurst.spellId or 421
    chainLightningBurst.total = chainLightningBurst.total + amount
    chainLightningBurst.hadCrit = chainLightningBurst.hadCrit or hadCrit
    chainLightningBurst.flushAt = now + CHAIN_LIGHTNING_CAST_WINDOW_SEC
    ShowOrUpdateSustainedSlot(
        SLOT_CASTS,
        chainLightningBurst.spellId,
        chainLightningBurst.total,
        chainLightningBurst.hadCrit,
        now,
        chainLightningBurst.hadCrit
    )
end

local function FlushChainLightningBurstIfDue(now)
    if chainLightningBurst.total > 0 and chainLightningBurst.flushAt > 0 and now >= chainLightningBurst.flushAt then
        FlushChainLightningBurst(now)
    end
end

local function AddFlameShockRolling(amount, hadCrit, spellId, now)
    if (now - (flameShockRolling.lastTickAt or 0)) > FLAME_SHOCK_ROLLING_RESET_SEC then
        flameShockRolling.total = 0
        flameShockRolling.hadCrit = false
    end
    flameShockRolling.total = flameShockRolling.total + amount
    flameShockRolling.hadCrit = flameShockRolling.hadCrit or hadCrit
    flameShockRolling.spellId = spellId or flameShockRolling.spellId or 8050
    flameShockRolling.lastTickAt = now
    ShowOrUpdateSustainedSlot(
        SLOT_CASTS,
        flameShockRolling.spellId,
        flameShockRolling.total,
        flameShockRolling.hadCrit,
        now,
        flameShockRolling.hadCrit
    )
end

local function AddMagmaRolling(amount, hadCrit, spellId, now)
    if (now - (magmaRolling.lastTickAt or 0)) > MAGMA_ROLLING_RESET_SEC then
        magmaRolling.total = 0
        magmaRolling.hadCrit = false
    end
    magmaRolling.total = magmaRolling.total + amount
    magmaRolling.hadCrit = magmaRolling.hadCrit or hadCrit
    magmaRolling.spellId = spellId or magmaRolling.spellId or 8187
    magmaRolling.lastTickAt = now
    ShowOrUpdateSustainedSlot(
        SLOT_FIRE,
        magmaRolling.spellId,
        magmaRolling.total,
        magmaRolling.hadCrit,
        now,
        magmaRolling.hadCrit
    )
end

local function AddFireAoeDamage(amount, hadCrit, spellId, now)
    if fireAoeBurst.total > 0 and fireAoeBurst.flushAt > 0 and now >= fireAoeBurst.flushAt then
        QueueDriverSlotPopup(SLOT_FIRE, fireAoeBurst.spellId or spellId or 8187, fireAoeBurst.total, fireAoeBurst.hadCrit, {
            now = now,
            critEvent = fireAoeBurst.hadCrit,
        })
        fireAoeBurst.lastPopAt = now
        fireAoeBurst.total = 0
        fireAoeBurst.hadCrit = false
    end

    fireAoeBurst.total = fireAoeBurst.total + amount
    fireAoeBurst.hadCrit = fireAoeBurst.hadCrit or hadCrit
    fireAoeBurst.spellId = spellId or fireAoeBurst.spellId or 8187

    local dueAt = now + FIRE_AOE_MERGE_WINDOW_SEC
    local minDueAt = fireAoeBurst.lastPopAt + FIRE_AOE_MIN_POP_INTERVAL_SEC
    fireAoeBurst.flushAt = math_max(dueAt, minDueAt)
end

local function FlushFireAoeBurstIfDue(now)
    if fireAoeBurst.total <= 0 then
        return
    end
    if fireAoeBurst.flushAt <= 0 or now < fireAoeBurst.flushAt then
        return
    end
    QueueDriverSlotPopup(SLOT_FIRE, fireAoeBurst.spellId or 8187, fireAoeBurst.total, fireAoeBurst.hadCrit, {
        now = now,
        critEvent = fireAoeBurst.hadCrit,
    })
    fireAoeBurst.lastPopAt = now
    fireAoeBurst.total = 0
    fireAoeBurst.hadCrit = false
    fireAoeBurst.flushAt = 0
    fireAoeBurst.spellId = nil
end

local function StartWindfuryBurst(now, pendingTotemSwings)
    if windfuryBurst.active and windfuryBurst.total > 0 then
        QueueDriverSlotPopup(SLOT_WIND, WINDFURY_ATTACK_SPELL_ID, windfuryBurst.total, windfuryBurst.hadCrit, {
            now = now,
            critEvent = windfuryBurst.hadCrit,
        })
    end
    windfuryBurst.active = true
    windfuryBurst.total = 0
    windfuryBurst.hits = 0
    windfuryBurst.hadCrit = false
    windfuryBurst.expiresAt = now + WINDFURY_BURST_WINDOW_SEC
    windfuryBurst.pendingTotemSwings = pendingTotemSwings or 0
end

local function FlushWindfuryBurst(now, skipPopup)
    if windfuryBurst.total > 0 and not skipPopup then
        QueueDriverSlotPopup(SLOT_WIND, WINDFURY_ATTACK_SPELL_ID, windfuryBurst.total, windfuryBurst.hadCrit, {
            now = now,
            critEvent = windfuryBurst.hadCrit,
        })
    end
    windfuryBurst.active = false
    windfuryBurst.total = 0
    windfuryBurst.hits = 0
    windfuryBurst.hadCrit = false
    windfuryBurst.expiresAt = 0
    windfuryBurst.pendingTotemSwings = 0
end

local function AddWindfuryDamage(amount, hadCrit, now)
    if (not windfuryBurst.active) or now > windfuryBurst.expiresAt then
        StartWindfuryBurst(now, 0)
    end
    windfuryBurst.total = windfuryBurst.total + amount
    windfuryBurst.hadCrit = windfuryBurst.hadCrit or hadCrit
    windfuryBurst.hits = windfuryBurst.hits + 1

    -- Show/update immediately on each hit so WF feedback feels instant while
    -- still accumulating both hits into a single running total.
    QueueDriverSlotPopup(SLOT_WIND, WINDFURY_ATTACK_SPELL_ID, windfuryBurst.total, windfuryBurst.hadCrit, {
        now = now,
        critEvent = hadCrit and true or false,
    })

    if windfuryBurst.hits >= WINDFURY_MAX_HITS_PER_BURST and windfuryBurst.pendingTotemSwings <= 0 then
        FlushWindfuryBurst(now, true)
    end
end

local function FlushWindfuryBurstIfDue(now)
    if windfuryBurst.active and windfuryBurst.expiresAt > 0 and now >= windfuryBurst.expiresAt then
        FlushWindfuryBurst(now)
    end
end

local function ResetDriverPopupState()
    for _, slotId in ipairs(SLOT_ORDER) do
        local slot = driverSlots[slotId]
        HideDriverSlot(slot)
    end

    stormstrikeSwingWindow.activeUntil = 0
    stormstrikeSwingWindow.remainingHits = 0
    stormstrikeBurst.total = 0
    stormstrikeBurst.hadCrit = false
    stormstrikeBurst.hits = 0
    stormstrikeBurst.flushAt = 0

    chainLightningBurst.spellId = nil
    chainLightningBurst.total = 0
    chainLightningBurst.hadCrit = false
    chainLightningBurst.flushAt = 0

    flameShockRolling.total = 0
    flameShockRolling.hadCrit = false
    flameShockRolling.spellId = nil
    flameShockRolling.lastTickAt = 0

    magmaRolling.total = 0
    magmaRolling.hadCrit = false
    magmaRolling.spellId = nil
    magmaRolling.lastTickAt = 0

    fireAoeBurst.spellId = nil
    fireAoeBurst.total = 0
    fireAoeBurst.hadCrit = false
    fireAoeBurst.flushAt = 0
    fireAoeBurst.lastPopAt = 0

    windfuryBurst.active = false
    windfuryBurst.total = 0
    windfuryBurst.hits = 0
    windfuryBurst.hadCrit = false
    windfuryBurst.expiresAt = 0
    windfuryBurst.pendingTotemSwings = 0
end

local function UpdateDriverPopupState(now)
    FlushStormstrikeBurstIfDue(now)
    FlushChainLightningBurstIfDue(now)
    FlushFireAoeBurstIfDue(now)
    FlushWindfuryBurstIfDue(now)
    UpdateDriverSlots(now)
end

ResetDriverPopupState()

local gaugeKeys = {
    "gaugeZero",
    "gaugeTen",
    "gaugeFifty",
    "gaugeSeventyFive",
    "gaugeHundred",
}

local gaugeCurrentAlpha = { 1, 0, 0, 0, 0 }
local colorOverlayFillFrac = 0
local colorOverlayFullHoldRemaining = 0
local colorOverlayFillVisible = false
local colorOverlayCurrentColor = { 0.50, 0.50, 0.50 }
local visualAnimState = {
    colorOverlayTransferActive = false,
    colorOverlayTransferElapsed = 0,
    colorOverlayTransferFrom = 0,
    colorOverlayTransferTo = 0,
    promotionPending = false,
    gaugeShakeStress = 0,
    gaugeShakeOffsetX = 0,
    gaugeShakeOffsetY = 0,
}

local function ApplyProgressPullResistance(progressFrac)
    local p = math_min(math_max(progressFrac or 0, 0), 1)
    if p <= 0 then return 0 end
    if p >= 1 then return 1 end

    if p <= PUSH_FEEL_CFG.fillPullResistStart then
        local lowerSpan = math_max(PUSH_FEEL_CFG.fillPullResistStart, 0.001)
        local q = p / lowerSpan
        return (q ^ PUSH_FEEL_CFG.fillPullLowerPower) * PUSH_FEEL_CFG.fillPullResistStart
    end

    local q = (p - PUSH_FEEL_CFG.fillPullResistStart) / math_max(1 - PUSH_FEEL_CFG.fillPullResistStart, 0.001)
    return PUSH_FEEL_CFG.fillPullResistStart + ((q ^ PUSH_FEEL_CFG.fillPullEdgePower) * (1 - PUSH_FEEL_CFG.fillPullResistStart))
end

local function StartColorOverlayTransferDrop(fromFillFrac)
    visualAnimState.colorOverlayTransferActive = true
    visualAnimState.colorOverlayTransferElapsed = 0
    visualAnimState.colorOverlayTransferFrom = math_min(math_max(fromFillFrac or colorOverlayFillFrac or 0, 0), 1)
    visualAnimState.colorOverlayTransferTo = 0
    colorOverlayFullHoldRemaining = 0
end

local function SetGaugeTextureOffset(offsetX, offsetY)
    local x = tonumber(offsetX) or 0
    local y = tonumber(offsetY) or 0
    if math_abs((visualAnimState.gaugeShakeOffsetX or 0) - x) < 0.01 and math_abs((visualAnimState.gaugeShakeOffsetY or 0) - y) < 0.01 then
        return
    end
    visualAnimState.gaugeShakeOffsetX = x
    visualAnimState.gaugeShakeOffsetY = y
    for _, key in ipairs(gaugeKeys) do
        local tex = frame.textures[key]
        if tex then
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
            tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", x, y)
        end
    end
end

local function UpdateGaugeShake(elapsed, now, rawFillTarget)
    local fillStress = 0
    if rawFillTarget and rawFillTarget > PUSH_FEEL_CFG.gaugeShakeTriggerFill then
        fillStress = (rawFillTarget - PUSH_FEEL_CFG.gaugeShakeTriggerFill) / math_max(1 - PUSH_FEEL_CFG.gaugeShakeTriggerFill, 0.001)
    end
    local resistMax = math_max((PS and PS.tierEdgeResistMax) or 0.52, 0.001)
    local resistStress = math_min(math_max((PS and PS.tierEdgeResistance or 0) / resistMax, 0), 1)
    local stressTarget = math_min(math_max(math_max(fillStress, resistStress * 0.90), 0), 1)
    visualAnimState.gaugeShakeStress = SmoothAlpha(
        visualAnimState.gaugeShakeStress,
        stressTarget,
        elapsed,
        PUSH_FEEL_CFG.gaugeShakeStressTauIn,
        PUSH_FEEL_CFG.gaugeShakeStressTauOut
    )

    if visualAnimState.gaugeShakeStress <= 0.01 then
        SetGaugeTextureOffset(0, 0)
        return
    end

    local t = now or GetTime()
    local ampX = PUSH_FEEL_CFG.gaugeShakeMaxX * visualAnimState.gaugeShakeStress
    local ampY = PUSH_FEEL_CFG.gaugeShakeMaxY * visualAnimState.gaugeShakeStress
    local shakeX = (math.sin(t * PUSH_FEEL_CFG.gaugeShakeFreqX1) * ampX) + (math.cos(t * PUSH_FEEL_CFG.gaugeShakeFreqX2 + 0.9) * ampX * 0.35)
    local shakeY = math.sin(t * PUSH_FEEL_CFG.gaugeShakeFreqY1 + 1.2) * ampY
    SetGaugeTextureOffset(shakeX, shakeY)
end

local function SetColorOverlayFill(fillFrac)
    local colorOverlay = frame.textures.colorOverlay
    if not colorOverlay then return end

    local frac = math_min(math_max(fillFrac or 0, 0), 1)
    if frac <= FILL_HIDE_EPS then
        colorOverlayFillVisible = false
        colorOverlay:Hide()
        colorOverlay:SetWidth(1)
        colorOverlay:SetTexCoord(0, MIN_FILL_U, CROP_TOP, 1 - CROP_BOTTOM)
        return
    end

    if (not colorOverlayFillVisible) and frac < FILL_SHOW_EPS then
        colorOverlay:SetWidth(1)
        colorOverlay:SetTexCoord(0, MIN_FILL_U, CROP_TOP, 1 - CROP_BOTTOM)
        return
    end

    colorOverlayFillVisible = true
    local uRight = math_max(frac, MIN_FILL_U)
    colorOverlay:Show()
    colorOverlay:SetWidth(DISPLAY_WIDTH * uRight)
    colorOverlay:SetTexCoord(0, uRight, CROP_TOP, 1 - CROP_BOTTOM)
end

if frame.textures.colorOverlay then
    local colorOverlay = frame.textures.colorOverlay
    colorOverlay:ClearAllPoints()
    colorOverlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    colorOverlay:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    colorOverlay:SetWidth(1)
end

for i, key in ipairs(gaugeKeys) do
    local tex = frame.textures[key]
    if tex then
        tex:SetAlpha(gaugeCurrentAlpha[i] or 0)
    end
end
SetGaugeTextureOffset(0, 0)
if frame.textures.colorOverlay then
    frame.textures.colorOverlay:SetAlpha(1)
end
SetColorOverlayFill(colorOverlayFillFrac)

frame:Show()

local DEBUG_LAYOUT = {
    lineHeight = 14,
    headerHeight = 22,
    padding = 6,
    frameWidth = 340,
    barHeight = 24,
}
local DEBUG_FRAME_HEIGHT = DEBUG_LAYOUT.headerHeight + DEBUG_LAYOUT.padding * 2 + DEBUG_LAYOUT.barHeight + 4
    + DEBUG_LAYOUT.lineHeight + DEBUG_LAYOUT.lineHeight + 4
    + NUM_WINDOWS * (DEBUG_LAYOUT.lineHeight + 2) + DEBUG_LAYOUT.padding

local debugFrame = CreateFrame("Frame", "ShammyTimePressureDebugFrame", UIParent, "BackdropTemplate")
debugFrame:SetSize(DEBUG_LAYOUT.frameWidth, DEBUG_FRAME_HEIGHT)
debugFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -120)
debugFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
debugFrame:SetBackdropColor(0, 0, 0, 0.85)
debugFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)
debugFrame:SetFrameStrata("LOW")
debugFrame:SetClampedToScreen(true)
debugFrame:SetMovable(true)
debugFrame:EnableMouse(true)
debugFrame:RegisterForDrag("LeftButton")
debugFrame:SetScript("OnDragStart", debugFrame.StartMoving)
debugFrame:SetScript("OnDragStop", debugFrame.StopMovingOrSizing)
debugFrame:Hide()

local debugTitle = debugFrame:CreateFontString(nil, "OVERLAY")
debugTitle:SetFont(FONT_PATH, 12, "OUTLINE")
debugTitle:SetPoint("TOPLEFT", debugFrame, "TOPLEFT", DEBUG_LAYOUT.padding, -DEBUG_LAYOUT.padding)
debugTitle:SetText("ShammyTime Pressure Debug")
debugTitle:SetTextColor(1, 0.82, 0)

local debugBar = CreateFrame("StatusBar", nil, debugFrame)
debugBar:SetSize(DEBUG_LAYOUT.frameWidth - DEBUG_LAYOUT.padding * 2 - 4, DEBUG_LAYOUT.barHeight)
debugBar:SetPoint("TOPLEFT", debugFrame, "TOPLEFT", DEBUG_LAYOUT.padding + 2, -(DEBUG_LAYOUT.headerHeight + DEBUG_LAYOUT.padding))
debugBar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
debugBar:SetMinMaxValues(0.0, 4.0)
debugBar:SetValue(0.0)
debugBar:SetStatusBarColor(0.5, 0.5, 0.5)

local debugBarBg = debugBar:CreateTexture(nil, "BACKGROUND")
debugBarBg:SetAllPoints()
debugBarBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

local debugBarText = debugBar:CreateFontString(nil, "OVERLAY")
debugBarText:SetFont(FONT_PATH, 13, "OUTLINE")
debugBarText:SetPoint("CENTER", debugBar, "CENTER", 0, 0)
debugBarText:SetText("0.00x")

local debugBarTierText = debugBar:CreateFontString(nil, "OVERLAY")
debugBarTierText:SetFont(FONT_PATH, 11, "OUTLINE")
debugBarTierText:SetPoint("RIGHT", debugBar, "RIGHT", -4, 0)
debugBarTierText:SetText("T0")
debugBarTierText:SetTextColor(0.6, 0.6, 0.6)

local debugText = debugFrame:CreateFontString(nil, "OVERLAY")
debugText:SetFont(FONT_PATH, 10, "")
debugText:SetJustifyH("LEFT")
debugText:SetPoint("TOPLEFT", debugFrame, "TOPLEFT", DEBUG_LAYOUT.padding, -(DEBUG_LAYOUT.headerHeight + DEBUG_LAYOUT.padding + DEBUG_LAYOUT.barHeight + 4))
debugText:SetPoint("RIGHT", debugFrame, "RIGHT", -DEBUG_LAYOUT.padding, 0)
debugText:SetTextColor(0.6, 0.6, 0.6)
debugText:SetText("n:0.00 i:0.00 q:0.00 ts:0.00 te:0.00 m:0.00 hk:0.00 ok")

local bucketStrings = {}
for i = 1, NUM_WINDOWS do
    local fs = debugFrame:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT_PATH, 11, "")
    fs:SetJustifyH("LEFT")
    fs:SetPoint(
        "TOPLEFT",
        debugFrame,
        "TOPLEFT",
        DEBUG_LAYOUT.padding,
        -(DEBUG_LAYOUT.headerHeight + DEBUG_LAYOUT.padding + DEBUG_LAYOUT.barHeight + 4 + DEBUG_LAYOUT.lineHeight + 4)
            - (i - 1) * (DEBUG_LAYOUT.lineHeight + 2)
    )
    fs:SetPoint("RIGHT", debugFrame, "RIGHT", -DEBUG_LAYOUT.padding, 0)
    fs:SetText("")
    bucketStrings[i] = fs
end

local TIER_COLORS = {
    { 0.50, 0.50, 0.50 }, -- T0
    { 0.20, 0.80, 0.20 }, -- T1
    { 0.40, 0.90, 0.10 }, -- T2
    { 1.00, 0.80, 0.00 }, -- T3
    { 1.00, 0.40, 0.00 }, -- T4
    { 1.00, 0.10, 0.10 }, -- T5
}

local TIER_GAUGE_INDEX = {
    [0] = 1, -- gaugeZero
    [1] = 2, -- gaugeTen
    [2] = 3, -- gaugeFifty
    [3] = 4, -- gaugeSeventyFive
    [4] = 5, -- gaugeHundred
    [5] = 5, -- gaugeHundred
}

local TIER_GAUGE_ALPHA = {
    [0] = 1.00,
    [1] = 1.00,
    [2] = 1.00,
    [3] = 1.00,
    [4] = 0.90,
    [5] = 1.00,
}

SmoothAlpha = function(current, target, elapsed, tauIn, tauOut)
    if math_abs(current - target) < 0.003 then
        return target
    end
    local tau = (target > current) and tauIn or tauOut
    tau = math_max(tau or 0.1, 0.02)
    local alpha = 1 - math_exp(-elapsed / tau)
    return current + (target - current) * alpha
end

PS = {
    fastCharge = 0,
    slowCharge = 0,
    tauFast = 1.0,
    tauSlow = 20.0,
    epsilon = 1.0,
    pressureRatio = 0,
    displayGain = 1.20,
    burstDamping = 1.20,
    denominatorFloor = 200,
    displayTau = 0.30,
    displayTauRise = 0.12,
    pressureDisplaySmoothed = 0,
    pressureComposite = 0,
    instantScore = 0,
    squeezeScore = 0,
    tierScore = 0,
    tierEvalScore = 0,
    tierEdgeResistance = 0,
    tierEdgeSlip = 0,
    currentTier = 0,
    lastTierChangeAt = 0,
    tierCapReason = "ok",
    recentHitImpulse = 0,
    squeezeCharge = 0,
    squeezeDecayTau = 18.0,
    critBonusMult = 2.0,
    squeezeBuildRate = 0.25,
    squeezeBonusMax = 0.85,
    squeezeBuildBaseline = 1.20,
    squeezeBuildPower = 1.20,
    squeezeIdleDecayMult = 0.45,
    tierInstantWeight = 0.95,
    tierSqueezeWeight = 0.65,
    tierHysteresis = 0.14,
    tierHoldMinSec = 2.20,
    tierEdgeStartFrac = 0.62,
    tierEdgePower = 1.70,
    tierEdgeResistMax = 0.52,
    tierEdgeSlipStartFrac = 0.72,
    tierEdgeSlipMax = 0.16,
    tierConcavityDepth = 0.0,
    tierMomentumBoost = 0,
    tierMomentumOnPromote = 0.08,
    tierMomentumMax = 0.22,
    tierMomentumBuildTau = 0.55,
    tierMomentumDecayTau = 3.20,
    tierMomentumIdleDecayTau = 1.15,
    tierMomentumIdleGrace = 0.70,
    tierMomentumTierScalar = 0.04,
    hitImpulseTau = 1.20,
    nearTierProgressFrac = 0.90,
    nearTierKickMin = 0.24,
    nearTierKickWeight = 0.22,
    tierMinSqueeze = { 0.00, 0.00, 0.18, 0.35, 0.70, 0.92 },
    tierMinActiveSec = { 0.0, 1.2, 2.5, 4.0, 7.0, 14.0 },
    firstPressureAt = nil,
    pressureTick = 0.05,
    pressureElapsed = 0,
    lastDamageTime = 0,
    pressureSamples = {},
    pressureSampleValues = {},
    pressureSampleHead = 1,
    pressureSampleTail = 0,
    pressureSampleCount = 0,
    pressureSampleMaxCount = 7000,
    pressureSampleRetention = 300,
    bucketStatsElapsed = 0,
    bucketStatsInterval = 0.5,
    pressureBucketAvg = { 0, 0, 0, 0, 0 },
    pressureBucketMax = { 0, 0, 0, 0, 0 },
    tierThresholds = { 1.50, 1.85, 2.32, 3.05, 3.90 },
}

local function ClearPressureSamples()
    PS.pressureSamples = {}
    PS.pressureSampleValues = {}
    PS.pressureSampleHead = 1
    PS.pressureSampleTail = 0
    PS.pressureSampleCount = 0
end

local function ExportPressureState()
    ShammyTime.PressureState = PS
    ShammyTime.GetPressureState = function()
        return PS
    end
    _G.ShammyTimePressureState = PS
    _G.ShammyTime_PressureState = PS
end

ExportPressureState()

local function GetTier(score)
    for i = #PS.tierThresholds, 1, -1 do
        if score >= PS.tierThresholds[i] then return i end
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

local function GetTierFillTarget(score, tier)
    local clampedTier = math_min(math_max(tier or 0, 0), 5)
    if clampedTier >= 5 then
        return 1
    end

    local lower
    if clampedTier <= 0 then
        lower = 0
    else
        lower = GetPromoteThreshold(clampedTier)
    end
    local upper = GetPromoteThreshold(clampedTier + 1)
    local span = math_max(upper - lower, 0.001)

    return math_min(math_max(((score or 0) - lower) / span, 0), 1)
end

local function GetTierSegmentProgress(score)
    local s = score or 0
    local lower = 0
    for i = 1, #PS.tierThresholds do
        local upper = PS.tierThresholds[i]
        if s < upper then
            local span = math_max(upper - lower, 0.001)
            local frac = math_min(math_max((s - lower) / span, 0), 1)
            return i - 1, frac
        end
        lower = upper
    end
    return #PS.tierThresholds, 1
end

local function GetTierResistanceAndSlip(score, now)
    local segTier, segFrac = GetTierSegmentProgress(score)
    if segTier >= #PS.tierThresholds then
        return 0, 0
    end

    local resistance = (segFrac ^ PUSH_FEEL_CFG.tierPullBaseResistPower) * PUSH_FEEL_CFG.tierPullBaseResistMax

    local edgeStart = math_min(math_max(PS.tierEdgeStartFrac or 0.50, 0.0), 0.95)
    if segFrac > edgeStart then
        local q = (segFrac - edgeStart) / math_max(1 - edgeStart, 0.001)
        local concavityDepth = math_max(PS.tierConcavityDepth or 0, 0)
        local power = math_max((PS.tierEdgePower or 1.0) + concavityDepth, 1.0)
        local resistMax = math_max(PS.tierEdgeResistMax or 0, 0) * (1 + (concavityDepth * 0.75))
        resistance = resistance + ((q ^ power) * resistMax)
    end

    if segFrac > PUSH_FEEL_CFG.tierPullEdgeStart then
        local q = (segFrac - PUSH_FEEL_CFG.tierPullEdgeStart) / math_max(1 - PUSH_FEEL_CFG.tierPullEdgeStart, 0.001)
        resistance = resistance + ((q ^ PUSH_FEEL_CFG.tierPullEdgeResistPower) * PUSH_FEEL_CFG.tierPullEdgeResistMax)
    end

    local slip = 0
    local idleGrace = math_max(PS.tierMomentumIdleGrace or 0.70, 0)
    if (now - (PS.lastDamageTime or 0)) > idleGrace then
        local slipStart = math_min(math_max(PS.tierEdgeSlipStartFrac or 0.72, 0.0), 0.98)
        if segFrac > slipStart then
            local q = (segFrac - slipStart) / math_max(1 - slipStart, 0.001)
            slip = (q ^ 1.25) * math_max(PS.tierEdgeSlipMax or 0, 0)
        end
    end

    return resistance, slip
end

local function UpdateTierMomentumBonus(elapsed, now)
    local target = 0
    if (PS.currentTier or 0) >= 1 then
        target = math_min(
            math_max(PS.tierMomentumTierScalar or 0, 0) * PS.currentTier,
            math_max(PS.tierMomentumMax or 0, 0)
        )
    end

    local idleGrace = math_max(PS.tierMomentumIdleGrace or 0.70, 0)
    local decayTau = (PS.tierMomentumDecayTau or 3.20)
    if (now - (PS.lastDamageTime or 0)) > idleGrace then
        decayTau = PS.tierMomentumIdleDecayTau or decayTau
    end

    PS.tierMomentumBoost = SmoothAlpha(
        PS.tierMomentumBoost or 0,
        target,
        elapsed,
        PS.tierMomentumBuildTau or 0.55,
        decayTau
    )
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

local function BuildPressureTierThresholdsFromDB()
    local thresholds = {
        GetPressurePopupDBNumber("pressureTierDamageReq1", 1.50, 0.20, 10.0),
        GetPressurePopupDBNumber("pressureTierDamageReq2", 1.85, 0.20, 10.0),
        GetPressurePopupDBNumber("pressureTierDamageReq3", 2.32, 0.20, 10.0),
        GetPressurePopupDBNumber("pressureTierDamageReq4", 3.05, 0.20, 10.0),
        GetPressurePopupDBNumber("pressureTierDamageReq5", 3.90, 0.20, 10.0),
    }
    for i = 2, #thresholds do
        local minNext = thresholds[i - 1] + 0.01
        if thresholds[i] < minNext then
            thresholds[i] = minNext
        end
    end
    return thresholds
end

local function BuildPressureTierForceReqFromDB()
    local req = {
        GetPressurePopupDBNumber("pressureTierForceReq1", 0.00, 0.00, 1.00),
        GetPressurePopupDBNumber("pressureTierForceReq2", 0.18, 0.00, 1.00),
        GetPressurePopupDBNumber("pressureTierForceReq3", 0.35, 0.00, 1.00),
        GetPressurePopupDBNumber("pressureTierForceReq4", 0.70, 0.00, 1.00),
        GetPressurePopupDBNumber("pressureTierForceReq5", 0.92, 0.00, 1.00),
    }
    for i = 2, #req do
        if req[i] < req[i - 1] then
            req[i] = req[i - 1]
        end
    end
    return req
end

local function ApplyPressureTuningSettings()
    local thresholds = BuildPressureTierThresholdsFromDB()
    PS.tierThresholds = thresholds

    local forceReq = BuildPressureTierForceReqFromDB()
    PS.tierMinSqueeze = { 0.00, forceReq[1], forceReq[2], forceReq[3], forceReq[4], forceReq[5] }

    PS.tierMomentumOnPromote = GetPressurePopupDBNumber("pressureTierMomentumOnPromote", 0.08, 0.00, 1.00)
    PS.tierMomentumTierScalar = GetPressurePopupDBNumber("pressureTierMomentumPerTier", 0.04, 0.00, 0.25)
    PS.tierMomentumMax = GetPressurePopupDBNumber("pressureTierMomentumMax", 0.22, 0.00, 1.50)
    PS.tierMomentumDecayTau = GetPressurePopupDBNumber("pressureTierMomentumDecayTau", 3.20, 0.20, 12.0)
    PS.tierMomentumIdleDecayTau = GetPressurePopupDBNumber("pressureTierMomentumIdleDecayTau", 1.15, 0.10, 8.0)
    PS.tierConcavityDepth = GetPressurePopupDBNumber("pressureTierConcavityDepth", 0.00, 0.00, 3.00)
end

ShammyTime.ApplyPressureTuningSettings = ApplyPressureTuningSettings
ApplyPressureTuningSettings()

local SUBEVENT_MAP = {
    SWING_DAMAGE = { amountIdx = 12, critIdx = 18 },
    SWING_DAMAGE_LANDED = { amountIdx = 12, critIdx = 18 },
    SPELL_DAMAGE = { amountIdx = 15, critIdx = 21, spellIdIdx = 12 },
    SPELL_DAMAGE_LANDED = { amountIdx = 15, critIdx = 21, spellIdIdx = 12 },
    RANGE_DAMAGE = { amountIdx = 15, critIdx = 21, spellIdIdx = 12 },
    RANGE_DAMAGE_LANDED = { amountIdx = 15, critIdx = 21, spellIdIdx = 12 },
    SPELL_PERIODIC_DAMAGE = { amountIdx = 15, critIdx = 21, spellIdIdx = 12 },
    DAMAGE_SHIELD = { amountIdx = 15, critIdx = 21, spellIdIdx = 12 },
}

local AFFILIATION_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001

local function OnCombatLogPressure()
    if not CombatLogGetCurrentEventInfo then return end
    if not bit_band then return end

    local _, subevent, _, sourceGUID, _, sourceFlags, _, _, _, _, _, arg12, arg13, _, arg15, _, _, arg18, _, _, arg21 =
        CombatLogGetCurrentEventInfo()
    local info = SUBEVENT_MAP[subevent]
    if not sourceFlags or bit_band(sourceFlags, AFFILIATION_MINE) == 0 then return end
    local isPlayerSource = IsPlayerSource(sourceGUID)
    local spellId = arg12
    local spellName = arg13
    local now = GetTime()

    if subevent == "SPELL_CAST_SUCCESS" then
        if isPlayerSource and IsStormstrikeSpell(spellId, spellName) then
            stormstrikeSwingWindow.activeUntil = now + STORMSTRIKE_SWING_WINDOW_SEC
            stormstrikeSwingWindow.remainingHits = STORMSTRIKE_SWING_MAX_HITS
            StartStormstrikeBurst(now)
            return
        end
        if isPlayerSource and IsChainLightningSpell(spellId, spellName) then
            StartChainLightningCast(now, spellId)
            return
        end
    elseif subevent == "SPELL_EXTRA_ATTACKS" then
        if isPlayerSource and (
            spellId == WINDFURY_TOTEM_EXTRA_ATTACKS_SPELL_ID
            or IsWindfuryAttackSpell(spellId, spellName)
            or SpellNameContains(spellName, "Windfury")
        ) then
            local extraCount = arg15
            local pendingTotemSwings = 0
            if spellId == WINDFURY_TOTEM_EXTRA_ATTACKS_SPELL_ID then
                pendingTotemSwings = (extraCount and extraCount > 0) and extraCount or 1
            end
            StartWindfuryBurst(now, pendingTotemSwings)
            return
        end
    end

    if not info then return end

    local amount
    if info.amountIdx == 12 then
        amount = arg12
    else
        amount = arg15
    end
    if not amount or amount <= 0 then return end

    local critFlag
    if info.critIdx == 18 then
        critFlag = arg18
    else
        critFlag = arg21
    end
    local isCrit = (critFlag == true or critFlag == 1)

    if not PS.firstPressureAt then
        PS.firstPressureAt = now
    end

    local feedAmount = amount
    if isCrit then
        feedAmount = amount * PS.critBonusMult
    end

    PS.fastCharge = PS.fastCharge + feedAmount
    PS.slowCharge = PS.slowCharge + amount
    PS.recentHitImpulse = PS.recentHitImpulse + feedAmount
    PS.lastDamageTime = now

    spellId = info.spellIdIdx and arg12
    spellName = info.spellIdIdx and arg13

    if isPlayerSource then
        if IsChainLightningSpell(spellId, spellName) then
            AddChainLightningDamage(spellId, amount, isCrit, now)
        elseif IsStormstrikeSpell(spellId, spellName) then
            AddStormstrikeDamage(amount, isCrit, now)
            if stormstrikeSwingWindow.remainingHits > 0 then
                stormstrikeSwingWindow.remainingHits = stormstrikeSwingWindow.remainingHits - 1
                if stormstrikeSwingWindow.remainingHits <= 0 then
                    stormstrikeSwingWindow.remainingHits = 0
                    stormstrikeSwingWindow.activeUntil = 0
                end
            end
        elseif IsLavaLashSpell(spellId, spellName) then
            QueueDriverSlotPopup(SLOT_CASTS, spellId, amount, isCrit)
        elseif IsShockSpell(spellId, spellName) then
            if IsFlameShockSpell(spellId, spellName) and subevent == "SPELL_PERIODIC_DAMAGE" then
                AddFlameShockRolling(amount, isCrit, spellId, now)
            else
                QueueDriverSlotPopup(SLOT_CASTS, spellId, amount, isCrit)
                if IsFlameShockSpell(spellId, spellName) then
                    flameShockRolling.total = amount
                    flameShockRolling.hadCrit = isCrit and true or false
                    flameShockRolling.spellId = spellId or flameShockRolling.spellId or 8050
                    flameShockRolling.lastTickAt = now
                end
            end
        end
    end

    if spellId and IsMagmaTotemSpell(spellId, spellName) then
        AddMagmaRolling(amount, isCrit, spellId, now)
    elseif spellId and IsFireNovaSpell(spellId, spellName) then
        AddFireAoeDamage(amount, isCrit, spellId, now)
    end

    if isPlayerSource then
        if IsWindfuryAttackSpell(spellId, spellName) then
            AddWindfuryDamage(amount, isCrit, now)
        elseif (subevent == "SWING_DAMAGE" or subevent == "SWING_DAMAGE_LANDED")
            and windfuryBurst.active
            and windfuryBurst.pendingTotemSwings > 0
            and now <= windfuryBurst.expiresAt
        then
            AddWindfuryDamage(amount, isCrit, now)
            windfuryBurst.pendingTotemSwings = windfuryBurst.pendingTotemSwings - 1
            if windfuryBurst.pendingTotemSwings <= 0 then
                windfuryBurst.pendingTotemSwings = 0
                if windfuryBurst.hits > 0 then
                    FlushWindfuryBurst(now)
                end
            end
        end
    end

    if stormstrikeSwingWindow.activeUntil > 0 and now > stormstrikeSwingWindow.activeUntil then
        stormstrikeSwingWindow.activeUntil = 0
        stormstrikeSwingWindow.remainingHits = 0
    end
end

local function UpdatePressureVisuals(elapsed, now)
    local tier = PS.currentTier or 0
    local tierColor = TIER_COLORS[tier + 1] or TIER_COLORS[1]

    local scoreForProgress = PS.tierEvalScore or PS.tierScore or 0
    local rawFillTarget = GetTierFillTarget(scoreForProgress, tier)
    local fillTarget = ApplyProgressPullResistance(rawFillTarget)

    if visualAnimState.promotionPending and (not visualAnimState.colorOverlayTransferActive) then
        fillTarget = 1
    end

    if tier >= 5 then
        fillTarget = 1
        visualAnimState.colorOverlayTransferActive = false
        visualAnimState.colorOverlayTransferTo = 1
        colorOverlayFullHoldRemaining = 0
    end

    if visualAnimState.colorOverlayTransferActive then
        local landingTarget = fillTarget
        if tier >= 1 then
            landingTarget = math_max(landingTarget, PUSH_FEEL_CFG.fillTransferLandingFloor)
        end
        visualAnimState.colorOverlayTransferTo = landingTarget
        visualAnimState.colorOverlayTransferElapsed = visualAnimState.colorOverlayTransferElapsed + elapsed
        local t = math_min(math_max(visualAnimState.colorOverlayTransferElapsed / math_max(PUSH_FEEL_CFG.fillTransferDropSec, 0.01), 0), 1)
        local decay = math_exp(-math_max(PUSH_FEEL_CFG.fillTransferRubberDamping, 0.01) * t)
        local omega = (math.pi * 2) * math_max(PUSH_FEEL_CFG.fillTransferRubberOscillations, 0.01)
        local rubber = decay * (0.20 + (0.80 * math.cos(omega * t)))
        local value = landingTarget + ((visualAnimState.colorOverlayTransferFrom - landingTarget) * rubber)
        colorOverlayFillFrac = math_min(math_max(value, 0), 1)
        if t >= 1 then
            visualAnimState.colorOverlayTransferActive = false
            colorOverlayFillFrac = visualAnimState.colorOverlayTransferTo
        end
    else
        if tier < 5 then
            if fillTarget >= FILL_FULL_EPSILON then
                colorOverlayFullHoldRemaining = FILL_FULL_HOLD_SEC
                fillTarget = 1
            elseif colorOverlayFullHoldRemaining > 0 then
                colorOverlayFullHoldRemaining = math_max(colorOverlayFullHoldRemaining - elapsed, 0)
                fillTarget = 1
            end
        else
            colorOverlayFullHoldRemaining = 0
        end

        local edgeProgress = 0
        if fillTarget > PUSH_FEEL_CFG.fillPullResistStart then
            edgeProgress = (fillTarget - PUSH_FEEL_CFG.fillPullResistStart) / math_max(1 - PUSH_FEEL_CFG.fillPullResistStart, 0.001)
        end
        local riseTau = FILL_SMOOTH_TAU_RISE * math_max(PUSH_FEEL_CFG.fillMass, 1) * (1 + (edgeProgress * edgeProgress * PUSH_FEEL_CFG.fillSmoothTauEdgeMult))
        colorOverlayFillFrac = SmoothAlpha(
            colorOverlayFillFrac,
            fillTarget,
            elapsed,
            riseTau,
            FILL_SMOOTH_TAU_FALL
        )
    end

    local colorOverlay = frame.textures.colorOverlay
    if colorOverlay then
        colorOverlayCurrentColor[1] = SmoothAlpha(
            colorOverlayCurrentColor[1], tierColor[1], elapsed, OVERLAY_COLOR_TAU_IN, OVERLAY_COLOR_TAU_OUT
        )
        colorOverlayCurrentColor[2] = SmoothAlpha(
            colorOverlayCurrentColor[2], tierColor[2], elapsed, OVERLAY_COLOR_TAU_IN, OVERLAY_COLOR_TAU_OUT
        )
        colorOverlayCurrentColor[3] = SmoothAlpha(
            colorOverlayCurrentColor[3], tierColor[3], elapsed, OVERLAY_COLOR_TAU_IN, OVERLAY_COLOR_TAU_OUT
        )
        colorOverlay:SetVertexColor(
            colorOverlayCurrentColor[1],
            colorOverlayCurrentColor[2],
            colorOverlayCurrentColor[3]
        )
        colorOverlay:SetAlpha(1)
    end
    SetColorOverlayFill(colorOverlayFillFrac)

    local activeGauge = TIER_GAUGE_INDEX[tier] or 1
    for i, key in ipairs(gaugeKeys) do
        local targetAlpha
        if i == 1 then
            -- Keep 0% gauge as a persistent base; higher gauges fade over it.
            targetAlpha = 1
        elseif i == activeGauge then
            targetAlpha = TIER_GAUGE_ALPHA[tier] or 1
        else
            targetAlpha = 0
        end
        gaugeCurrentAlpha[i] = SmoothAlpha(gaugeCurrentAlpha[i], targetAlpha, elapsed, 0.05, 0.40)
        local tex = frame.textures[key]
        if tex then
            tex:SetAlpha(gaugeCurrentAlpha[i])
        end
    end

    UpdateGaugeShake(elapsed, now, rawFillTarget)
end

local function ClearPressureDebugFrame()
    debugBar:SetValue(0.0)
    debugBar:SetStatusBarColor(0.5, 0.5, 0.5)
    debugBarText:SetText("0.00x")
    debugBarTierText:SetText("T0")
    debugBarTierText:SetTextColor(0.6, 0.6, 0.6)
    debugText:SetText("n:0.00 i:0.00 q:0.00 ts:0.00 te:0.00 m:0.00 hk:0.00 ok")
    for i = 1, NUM_WINDOWS do
        bucketStrings[i]:SetText("")
    end
end

local function UpdatePressureDebugFrame(hitKick)
    if not debugFrame:IsShown() then return end

    local tier = PS.currentTier or 0
    local col = TIER_COLORS[tier + 1] or TIER_COLORS[1]
    local display = PS.pressureComposite or 0
    local barValue = math_min(math_max(display, 0.0), 4.0)

    debugBar:SetValue(barValue)
    debugBar:SetStatusBarColor(col[1], col[2], col[3])
    debugBarText:SetText(string.format("%.2fx", display))
    debugBarTierText:SetText(string.format("T%d", tier))
    debugBarTierText:SetTextColor(col[1], col[2], col[3])

    debugText:SetText(string.format(
        "n:%.2f i:%.2f q:%.2f ts:%.2f te:%.2f m:%.2f hk:%.2f %s",
        PS.pressureRatio or 0,
        PS.instantScore or 0,
        PS.squeezeCharge or 0,
        PS.tierScore or 0,
        PS.tierEvalScore or 0,
        PS.tierMomentumBoost or 0,
        hitKick or 0,
        PS.tierCapReason or "ok"
    ))

    for wi = 1, NUM_WINDOWS do
        local w = WINDOWS[wi]
        bucketStrings[wi]:SetText(string.format(
            "%3ds:  avg %.2fx  max %.2fx",
            w, PS.pressureBucketAvg[wi] or 0, PS.pressureBucketMax[wi] or 0
        ))
    end
end

local function SetPressureDebugVisible(visible)
    if visible then
        debugFrame:Show()
    else
        debugFrame:Hide()
    end
end

local function ResetPressureState()
    PS.fastCharge = 0
    PS.slowCharge = 0
    PS.pressureRatio = 0
    PS.pressureDisplaySmoothed = 0
    PS.pressureComposite = 0
    PS.instantScore = 0
    PS.squeezeScore = 0
    PS.tierScore = 0
    PS.tierEvalScore = 0
    PS.tierEdgeResistance = 0
    PS.tierEdgeSlip = 0
    PS.tierMomentumBoost = 0
    PS.currentTier = 0
    PS.lastTierChangeAt = 0
    PS.tierCapReason = "ok"
    PS.recentHitImpulse = 0
    PS.squeezeCharge = 0
    PS.firstPressureAt = nil
    PS.lastDamageTime = 0
    PS.pressureElapsed = 0
    ClearPressureSamples()
    PS.bucketStatsElapsed = 0
    for wi = 1, NUM_WINDOWS do
        PS.pressureBucketAvg[wi] = 0
        PS.pressureBucketMax[wi] = 0
    end
    colorOverlayFillFrac = 0
    colorOverlayFullHoldRemaining = 0
    colorOverlayFillVisible = false
    visualAnimState.colorOverlayTransferActive = false
    visualAnimState.colorOverlayTransferElapsed = 0
    visualAnimState.colorOverlayTransferFrom = 0
    visualAnimState.colorOverlayTransferTo = 0
    visualAnimState.promotionPending = false
    visualAnimState.gaugeShakeStress = 0
    SetGaugeTextureOffset(0, 0)
    for i, key in ipairs(gaugeKeys) do
        gaugeCurrentAlpha[i] = (i == 1) and 1 or 0
        local tex = frame.textures[key]
        if tex then
            tex:SetAlpha(gaugeCurrentAlpha[i])
        end
    end
    colorOverlayCurrentColor[1] = TIER_COLORS[1][1]
    colorOverlayCurrentColor[2] = TIER_COLORS[1][2]
    colorOverlayCurrentColor[3] = TIER_COLORS[1][3]
    if frame.textures.colorOverlay then
        frame.textures.colorOverlay:SetVertexColor(
            colorOverlayCurrentColor[1],
            colorOverlayCurrentColor[2],
            colorOverlayCurrentColor[3]
        )
    end
    ResetDriverPopupState()
    SetColorOverlayFill(colorOverlayFillFrac)
    ClearPressureDebugFrame()
end

ShammyTime.ResetPressureState = ResetPressureState

local function HasDriverPopupActivity()
    for _, slotId in ipairs(SLOT_ORDER) do
        local slot = driverSlots[slotId]
        if slot and ((slot.base and slot.base.active) or (slot.overlay and slot.overlay.active)) then
            return true
        end
    end
    return false
end

local function HasResidualPressureVisual()
    if (PS.currentTier or 0) > 0 then return true end
    if (PS.pressureDisplaySmoothed or 0) > PRESSURE_VISUAL_CFG.visualActivityEps then return true end
    if (PS.squeezeCharge or 0) > PRESSURE_VISUAL_CFG.visualActivityEps then return true end
    if (PS.pressureComposite or 0) > PRESSURE_VISUAL_CFG.visualActivityEps then return true end
    if colorOverlayFillVisible and (colorOverlayFillFrac or 0) > PRESSURE_VISUAL_CFG.visualOverlayEps then return true end
    for i = 2, #gaugeCurrentAlpha do
        if (gaugeCurrentAlpha[i] or 0) > PRESSURE_VISUAL_CFG.visualActivityEps then
            return true
        end
    end
    return false
end

local function EnterPressureIdleState()
    PS.pressureElapsed = 0
    PS.fastCharge = 0
    PS.slowCharge = 0
    PS.pressureRatio = 0
    PS.pressureDisplaySmoothed = 0
    PS.pressureComposite = 0
    PS.instantScore = 0
    PS.squeezeScore = 0
    PS.tierScore = 0
    PS.tierEvalScore = 0
    PS.tierEdgeResistance = 0
    PS.tierEdgeSlip = 0
    PS.tierMomentumBoost = 0
    PS.squeezeCharge = 0
    PS.recentHitImpulse = 0
    PS.tierCapReason = "ok"
    PS.firstPressureAt = nil
    ClearPressureSamples()
    visualAnimState.colorOverlayTransferActive = false
    visualAnimState.colorOverlayTransferElapsed = 0
    visualAnimState.colorOverlayTransferFrom = 0
    visualAnimState.colorOverlayTransferTo = 0
    visualAnimState.promotionPending = false
    visualAnimState.gaugeShakeStress = 0
    SetGaugeTextureOffset(0, 0)
    PS.bucketStatsElapsed = 0
    for wi = 1, NUM_WINDOWS do
        PS.pressureBucketAvg[wi] = 0
        PS.pressureBucketMax[wi] = 0
    end
end

local pressureMathIdle = false
local pressureTickFrame = nil
local pressureTickRunning = false

local function OnPressureTick(_, dt)
    local now = GetTime()
    local hadPopupActivity = HasDriverPopupActivity()

    local recentDamage = false
    if PS.lastDamageTime and PS.lastDamageTime > 0 then
        recentDamage = (now - PS.lastDamageTime) <= PRESSURE_VISUAL_CFG.idleDamageGraceSec
    end

    local residualVisual = HasResidualPressureVisual()
    if (not recentDamage) and (not hadPopupActivity) and (not residualVisual) then
        if not pressureMathIdle then
            EnterPressureIdleState()
            pressureMathIdle = true
        end
        if pressureTickFrame and pressureTickRunning then
            pressureTickFrame:SetScript("OnUpdate", nil)
            pressureTickRunning = false
        end
        return
    end
    pressureMathIdle = false

    -- Only update popup state when there's potential activity.
    UpdateDriverPopupState(now)

    PS.pressureElapsed = PS.pressureElapsed + dt
    if PS.pressureElapsed < PS.pressureTick then return end
    local elapsed = PS.pressureElapsed
    PS.pressureElapsed = 0

    PS.fastCharge = PS.fastCharge * math_exp(-elapsed / math_max(PS.tauFast, 0.01))
    PS.slowCharge = PS.slowCharge * math_exp(-elapsed / math_max(PS.tauSlow, 0.01))
    if PS.fastCharge < 0.01 then PS.fastCharge = 0 end
    if PS.slowCharge < 0.01 then PS.slowCharge = 0 end

    local scale = PS.tauFast / math_max(PS.tauSlow, 0.001)
    local steadyDen = PS.slowCharge * scale
    local dampedDen = (steadyDen + (PS.fastCharge * PS.burstDamping)) / (1 + PS.burstDamping)
    dampedDen = math_max(dampedDen, PS.denominatorFloor)
    PS.pressureRatio = PS.fastCharge / math_max(dampedDen, PS.epsilon)

    local sampleMaxCount = math_max(PS.pressureSampleMaxCount or 7000, 64)
    local nextTail = (PS.pressureSampleTail or 0) + 1
    if nextTail > sampleMaxCount then
        nextTail = 1
    end
    PS.pressureSampleTail = nextTail
    PS.pressureSamples[nextTail] = now
    PS.pressureSampleValues[nextTail] = PS.pressureRatio
    if (PS.pressureSampleCount or 0) >= sampleMaxCount then
        local newHead = (PS.pressureSampleHead or 1) + 1
        if newHead > sampleMaxCount then
            newHead = 1
        end
        PS.pressureSampleHead = newHead
    else
        PS.pressureSampleCount = (PS.pressureSampleCount or 0) + 1
        if PS.pressureSampleCount == 1 then
            PS.pressureSampleHead = nextTail
        end
    end

    local sampleCutoff = now - PS.pressureSampleRetention
    while (PS.pressureSampleCount or 0) > 0 do
        local headIdx = PS.pressureSampleHead or 1
        local headTime = PS.pressureSamples[headIdx]
        if not headTime or headTime < sampleCutoff then
            PS.pressureSamples[headIdx] = nil
            PS.pressureSampleValues[headIdx] = nil
            local newHead = headIdx + 1
            if newHead > sampleMaxCount then
                newHead = 1
            end
            PS.pressureSampleHead = newHead
            PS.pressureSampleCount = (PS.pressureSampleCount or 0) - 1
        else
            break
        end
    end
    if (PS.pressureSampleCount or 0) <= 0 then
        PS.pressureSampleHead = 1
        PS.pressureSampleTail = 0
    end

    PS.bucketStatsElapsed = PS.bucketStatsElapsed + elapsed
    if PS.bucketStatsElapsed >= PS.bucketStatsInterval then
        PS.bucketStatsElapsed = 0
        for wi = 1, NUM_WINDOWS do
            PS.pressureBucketAvg[wi] = 0
            PS.pressureBucketMax[wi] = 0
        end
        local bucketCount = { 0, 0, 0, 0, 0 }
        local sampleCount = PS.pressureSampleCount or 0
        local sampleIdx = PS.pressureSampleHead or 1
        for _ = 1, sampleCount do
            local sampleTime = PS.pressureSamples[sampleIdx]
            local samplePressure = PS.pressureSampleValues[sampleIdx]
            if sampleTime and samplePressure then
                local age = now - sampleTime
                for wi = 1, NUM_WINDOWS do
                    if age <= WINDOWS[wi] then
                        PS.pressureBucketAvg[wi] = PS.pressureBucketAvg[wi] + samplePressure
                        bucketCount[wi] = bucketCount[wi] + 1
                        if samplePressure > PS.pressureBucketMax[wi] then
                            PS.pressureBucketMax[wi] = samplePressure
                        end
                    end
                end
            end
            sampleIdx = sampleIdx + 1
            if sampleIdx > sampleMaxCount then
                sampleIdx = 1
            end
        end
        for wi = 1, NUM_WINDOWS do
            if bucketCount[wi] > 0 then
                PS.pressureBucketAvg[wi] = PS.pressureBucketAvg[wi] / bucketCount[wi]
            end
        end
    end

    local targetDisplay = PS.pressureRatio * PS.displayGain
    local smoothingTau = (targetDisplay > PS.pressureDisplaySmoothed) and PS.displayTauRise or PS.displayTau
    local displayAlpha = 1 - math_exp(-elapsed / math_max(smoothingTau, 0.01))
    PS.pressureDisplaySmoothed = PS.pressureDisplaySmoothed + (targetDisplay - PS.pressureDisplaySmoothed) * displayAlpha

    local overBaseline = math_max(PS.pressureDisplaySmoothed - PS.squeezeBuildBaseline, 0.0)
    local inCombat = UnitAffectingCombat("player")
    local decayTau = PS.squeezeDecayTau
    if (not inCombat) and ((now - PS.lastDamageTime) > 3.0) then
        decayTau = PS.squeezeDecayTau * PS.squeezeIdleDecayMult
    end
    PS.squeezeCharge = PS.squeezeCharge * math_exp(-elapsed / math_max(decayTau, 0.1))
    PS.squeezeCharge = PS.squeezeCharge + ((overBaseline ^ PS.squeezeBuildPower) * PS.squeezeBuildRate * elapsed)
    PS.squeezeCharge = math_min(math_max(PS.squeezeCharge, 0.0), 1.0)

    PS.pressureComposite = PS.pressureDisplaySmoothed + (PS.squeezeCharge * PS.squeezeBonusMax)
    PS.instantScore = PS.pressureDisplaySmoothed
    PS.squeezeScore = PS.squeezeCharge * PS.squeezeBonusMax
    PS.tierScore = (PS.instantScore * PS.tierInstantWeight) + (PS.squeezeScore * PS.tierSqueezeWeight)
    UpdateTierMomentumBonus(elapsed, now)
    local edgeResistance, edgeSlip = GetTierResistanceAndSlip(PS.tierScore, now)
    PS.tierEdgeResistance = edgeResistance
    PS.tierEdgeSlip = edgeSlip
    PS.tierEvalScore = PS.tierScore - edgeResistance - edgeSlip + (PS.tierMomentumBoost or 0)

    PS.recentHitImpulse = PS.recentHitImpulse * math_exp(-elapsed / math_max(PS.hitImpulseTau, 0.1))
    local hitKick = math_min((PS.recentHitImpulse / math_max(dampedDen, PS.epsilon)) * 0.25, 1.0)

    local activeSec = PS.firstPressureAt and (now - PS.firstPressureAt) or 0
    local candidateTier = GetTier(PS.tierEvalScore)

    if PS.currentTier < 5 then
        local nextTier = PS.currentTier + 1
        local nextThreshold = GetPromoteThreshold(nextTier)
        if nextThreshold > 0 then
            local progress = PS.tierEvalScore / nextThreshold
            if progress >= PS.nearTierProgressFrac and hitKick >= PS.nearTierKickMin then
                local promotionScore = PS.tierEvalScore + (hitKick * PS.nearTierKickWeight)
                local promotedTier = GetTier(promotionScore)
                candidateTier = math_max(candidateTier, math_min(promotedTier, nextTier))
            end
        end
    end

    local gatedTier
    gatedTier, PS.tierCapReason = GetGateCappedTier(candidateTier, PS.squeezeCharge, activeSec)
    local canPromoteNow = (now - (PS.lastTierChangeAt or 0)) >= PUSH_FEEL_CFG.tierPromotionStepLockSec
    visualAnimState.promotionPending = false

    if gatedTier > PS.currentTier then
        local currentTierFillRaw = GetTierFillTarget(PS.tierEvalScore or PS.tierScore or 0, PS.currentTier)
        local scoreReadyForPromotion = currentTierFillRaw >= FILL_FULL_EPSILON
        if scoreReadyForPromotion then
            visualAnimState.promotionPending = true
        end

        local visualReadyForPromotion = colorOverlayFillFrac >= PUSH_FEEL_CFG.promotionVisualFullEpsilon
        if canPromoteNow and visualAnimState.promotionPending and visualReadyForPromotion and (not visualAnimState.colorOverlayTransferActive) then
            local previousTier = PS.currentTier
            PS.currentTier = math_min(gatedTier, PS.currentTier + 1)
            PS.lastTierChangeAt = now
            PS.tierMomentumBoost = math_min(
                (PS.tierMomentumBoost or 0) + (PS.tierMomentumOnPromote or 0),
                math_max(PS.tierMomentumMax or 0, 0)
            )
            if PS.currentTier > previousTier then
                StartColorOverlayTransferDrop(1)
            end
            visualAnimState.promotionPending = false
        end
    elseif gatedTier < PS.currentTier then
        local currentIdx = PS.currentTier + 1
        local gateFailsCurrentTier = (PS.squeezeCharge < (PS.tierMinSqueeze[currentIdx] or 0))
                                  or (activeSec < (PS.tierMinActiveSec[currentIdx] or 0))
        local demoteThreshold = GetDemoteThreshold(PS.currentTier)
        local scoreWantsDemote = PS.tierEvalScore <= demoteThreshold
        local holdElapsed = now - PS.lastTierChangeAt
        if holdElapsed >= PS.tierHoldMinSec and (gateFailsCurrentTier or scoreWantsDemote) then
            PS.currentTier = math_max(gatedTier, PS.currentTier - 1)
            PS.lastTierChangeAt = now
        end
    end

    UpdatePressureVisuals(elapsed, now)
    UpdatePressureDebugFrame(hitKick)
    ExportPressureState()
end

pressureTickFrame = CreateFrame("Frame")
pressureTickFrame:SetScript("OnUpdate", OnPressureTick)
pressureTickRunning = true

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "ShammyTime" then
        eventFrame:UnregisterEvent("ADDON_LOADED")
        ExportPressureState()
        return
    end
    if event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local beforeLastDamage = PS.lastDamageTime or 0
        OnCombatLogPressure()
        local now = GetTime()
        local recentRelevantDamage = (PS.lastDamageTime or 0) > beforeLastDamage
            and ((now - (PS.lastDamageTime or 0)) <= PRESSURE_VISUAL_CFG.idleDamageGraceSec)
        if pressureTickFrame and not pressureTickRunning and (recentRelevantDamage or HasDriverPopupActivity()) then
            pressureTickFrame:SetScript("OnUpdate", OnPressureTick)
            pressureTickRunning = true
        end
    end
end)

ShammyTime.GetPressureFrame = function()
    return frame
end

ShammyTime.EnsurePressureFrame = function()
    return frame
end

ShammyTime.GetPressureBaseScale = function()
    return DEFAULT_SCALE
end

ShammyTime.IsPressureActive = function(windowSec)
    local sec = tonumber(windowSec) or 3.0
    if sec < 0.1 then sec = 0.1 end
    if HasDriverPopupActivity() then
        return true
    end
    if HasResidualPressureVisual() then
        return true
    end
    if PS.currentTier and PS.currentTier > 0 then
        return true
    end
    if not PS.lastDamageTime or PS.lastDamageTime <= 0 then
        return false
    end
    return (GetTime() - PS.lastDamageTime) <= sec
end

local function PrintPressureHelp()
    print(ADDON_PREFIX .. " pressure commands:")
    print("  /st pressure on|off|toggle")
    print("  /st pressure reset")
    print("  /st pressure status")
    print("  /st pressure taufast N")
    print("  /st pressure tauslow N")
    print("  /st pressure gain N")
    print("  /st pressure damp N")
    print("  /st pressure smoothtau N")
    print("  /st pressure squeezetau N")
    print("  /st pressure squeezebuild N")
    print("  /st pressure hysteresis N")
    print("  /stpressure ... (same commands)")
end

local function HandlePressureSlash(msg)
    local trimmed = (msg or ""):lower():match("^%s*(.-)%s*$")
    local cmd, arg = trimmed:match("^(%S+)%s*(.-)$")
    if not cmd or cmd == "" then
        cmd = "toggle"
    end

    if cmd == "on" then
        SetPressureDebugVisible(true)
        print(ADDON_PREFIX .. " pressure debug panel shown.")
        return
    end
    if cmd == "off" then
        SetPressureDebugVisible(false)
        print(ADDON_PREFIX .. " pressure debug panel hidden.")
        return
    end
    if cmd == "toggle" then
        local nextShown = not debugFrame:IsShown()
        SetPressureDebugVisible(nextShown)
        print(ADDON_PREFIX .. " pressure debug panel " .. (nextShown and "shown." or "hidden."))
        return
    end
    if cmd == "reset" or cmd == "clear" then
        ResetPressureState()
        print(ADDON_PREFIX .. " pressure state reset.")
        return
    end
    if cmd == "status" then
        print(ADDON_PREFIX .. string.format(
            " n=%.3f i=%.3f q=%.2f ts=%.3f te=%.3f m=%.3f r=%.3f s=%.3f tier=T%d cap=%s",
            PS.pressureRatio, PS.instantScore, PS.squeezeCharge, PS.tierScore,
            PS.tierEvalScore or 0, PS.tierMomentumBoost or 0, PS.tierEdgeResistance or 0, PS.tierEdgeSlip or 0,
            PS.currentTier or 0, PS.tierCapReason or "ok"
        ))
        print(ADDON_PREFIX .. string.format(
            " tauFast=%.2f tauSlow=%.2f gain=%.2f damp=%.2f smoothTau=%.2f squeezeTau=%.1f squeezeBuild=%.2f hyst=%.2f",
            PS.tauFast, PS.tauSlow, PS.displayGain, PS.burstDamping,
            PS.displayTau, PS.squeezeDecayTau, PS.squeezeBuildRate, PS.tierHysteresis
        ))
        return
    end

    local n = tonumber(arg)
    if cmd == "taufast" then
        if n and n >= 0.1 and n <= 30 then
            PS.tauFast = n
            print(ADDON_PREFIX .. " tauFast set to " .. string.format("%.2f", n) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /st pressure taufast 0.1-30")
        end
        return
    end
    if cmd == "tauslow" then
        if n and n >= 1 and n <= 120 then
            PS.tauSlow = n
            print(ADDON_PREFIX .. " tauSlow set to " .. string.format("%.2f", n) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /st pressure tauslow 1-120")
        end
        return
    end
    if cmd == "gain" then
        if n and n >= 0.1 and n <= 10 then
            PS.displayGain = n
            print(ADDON_PREFIX .. " displayGain set to " .. string.format("%.2f", n))
        else
            print(ADDON_PREFIX .. " usage: /st pressure gain 0.1-10")
        end
        return
    end
    if cmd == "damp" then
        if n and n >= 0 and n <= 2 then
            PS.burstDamping = n
            print(ADDON_PREFIX .. " burstDamping set to " .. string.format("%.2f", n))
        else
            print(ADDON_PREFIX .. " usage: /st pressure damp 0-2")
        end
        return
    end
    if cmd == "smoothtau" then
        if n and n >= 0.05 and n <= 5 then
            PS.displayTau = n
            print(ADDON_PREFIX .. " displayTau set to " .. string.format("%.2f", n) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /st pressure smoothtau 0.05-5")
        end
        return
    end
    if cmd == "squeezetau" then
        if n and n >= 3 and n <= 60 then
            PS.squeezeDecayTau = n
            print(ADDON_PREFIX .. " squeezeDecayTau set to " .. string.format("%.1f", n) .. "s")
        else
            print(ADDON_PREFIX .. " usage: /st pressure squeezetau 3-60")
        end
        return
    end
    if cmd == "squeezebuild" then
        if n and n >= 0.05 and n <= 3 then
            PS.squeezeBuildRate = n
            print(ADDON_PREFIX .. " squeezeBuildRate set to " .. string.format("%.2f", n))
        else
            print(ADDON_PREFIX .. " usage: /st pressure squeezebuild 0.05-3")
        end
        return
    end
    if cmd == "hysteresis" then
        if n and n >= 0 and n <= 1 then
            PS.tierHysteresis = n
            print(ADDON_PREFIX .. " tierHysteresis set to " .. string.format("%.2f", n))
        else
            print(ADDON_PREFIX .. " usage: /st pressure hysteresis 0-1")
        end
        return
    end

    PrintPressureHelp()
end

ShammyTime.HandlePressureSlash = HandlePressureSlash
SLASH_STPRESSURE1 = "/stpressure"
SlashCmdList["STPRESSURE"] = function(msg)
    HandlePressureSlash(msg)
end

-- Optional helpers for quick in-game tweaks:
-- /script ShammyTimePressureSetScale(0.5)
-- /script ShammyTimePressureReset()
function ShammyTimePressureSetScale(scale)
    if type(scale) ~= "number" or scale <= 0 then return end
    local f = _G.ShammyTimePressureFrame
    if not f then return end
    f:SetScale(scale)
    print(string.format("ShammyTime Pressure scale: %.2f", scale))
end

function ShammyTimePressureReset()
    ResetPressureState()
end
