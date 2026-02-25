-- ShammyTime_Pressure.lua
-- Production pressure frame + tier engine (ported from PoC model).
-- Reads outgoing damage from combat log, computes pressure/tier state, and
-- drives gauge + color overlay from T0-T5.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

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
local CROP_TOP = 0.20
local CROP_BOTTOM = 0.33
local MIN_FILL_U = 0.001
local FILL_SHOW_EPS = 0.003
local FILL_HIDE_EPS = 0.0005
local FILL_SMOOTH_TAU_RISE = 0.18
local FILL_SMOOTH_TAU_FALL = 5.20
local FILL_FULL_HOLD_SEC = 0.40
local FILL_FULL_EPSILON = 0.985
local OVERLAY_COLOR_TAU_IN = 0.08
local OVERLAY_COLOR_TAU_OUT = 0.16
local PUSH_FEEL_CFG = {
    fillSmoothTauEdgeMult = 1.95,
    fillMass = 3.40,
    fillTransferDropSec = 0.78,
    fillTransferRubberDamping = 4.10,
    fillTransferRubberOscillations = 1.60,
    fillTransferLandingFloor = 0.08,
    promotionVisualFullEpsilon = 0.985,
    fillPullResistStart = 0.80,
    fillPullLowerPower = 1.12,
    fillPullEdgePower = 2.20,
    chargeVisualMode = true,
    tierPromotionStepLockSec = 0.35,
    resistanceScale = 1.00,
    gaugeShakeTriggerFill = 0.90,
    gaugeShakeStressTauIn = 0.12,
    gaugeShakeStressTauOut = 0.26,
    gaugeShakeAmount = 1.35,
    gaugeShakeDamageScale = 1.30,
    gaugeShakeMaxX = 1.30,
    gaugeShakeMaxY = 0.95,
    gaugeShakeFreqX1 = 35.0,
    gaugeShakeFreqX2 = 52.0,
    gaugeShakeFreqY1 = 41.0,
    overloadThreshold = 1.10,
    hitReactTauIn = 0.02,
    hitReactTauOut = 0.40,
    hitReactFillKick = 0.55,
    hitReactColorBoost = 0.72,
    tierPromoFlashTauOut = 0.75,
    tierPromoFlashColorBoost = 0.90,
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
    popupHoldSecMax = 30.0,
    popupFadeSecMin = 0.10,
    popupFadeSecMax = 20.0,
    popupSustainSecMin = 0.20,
    popupSustainSecMax = 30.0,
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
        offsetY = -147,
        defaultOffsetX = -130,
        defaultOffsetY = -147,
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
        offsetY = -171,
        defaultOffsetX = 1,
        defaultOffsetY = -171,
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
        offsetY = -147,
        defaultOffsetX = 135,
        defaultOffsetY = -147,
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
    { key = "chargeEnergy",                 file = "wf_center_energy.tga",                                        layer = "OVERLAY",    sub = 2 },
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
    if info.key == "chargeEnergy" then
        local energySize = math.floor(math_min(DISPLAY_HEIGHT * 0.98, DISPLAY_WIDTH * 0.52) + 0.5)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", frame, "CENTER", 0, 0)
        tex:SetSize(energySize, energySize)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(0.82, 0.94, 1.00)
        tex:SetAlpha(0.00)
    else
        tex:SetTexCoord(0, 1, CROP_TOP, 1 - CROP_BOTTOM)
        tex:SetAllPoints(frame)
    end
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

local DAMAGE_METER_POST_COMBAT_SEC = 11.25  -- duration passed to Tier model on combat end (no overlay)

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
    local popupLifetimeMult = 2.00
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
    SLOT_POPUP_CFG.popupHoldSec = ClampNumber(
        SLOT_POPUP_CFG.popupHoldSec * popupLifetimeMult,
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
    SLOT_POPUP_CFG.popupFadeSec = ClampNumber(
        SLOT_POPUP_CFG.popupFadeSec * popupLifetimeMult,
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
    SLOT_POPUP_CFG.popupSustainSec = ClampNumber(
        SLOT_POPUP_CFG.popupSustainSec * popupLifetimeMult,
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
local colorOverlayState = {
    fillFrac = 0,
    fullHoldRemaining = 0,
    fillVisible = false,
    currentColor = { 0.50, 0.50, 0.50 },
}
local visualAnimState = {
    colorOverlayTransferActive = false,
    colorOverlayTransferElapsed = 0,
    colorOverlayTransferFrom = 0,
    colorOverlayTransferTo = 0,
    promotionPending = false,
    gaugeShakeStress = 0,
    gaugeShakeOffsetX = 0,
    gaugeShakeOffsetY = 0,
    hitReact = 0,
    tierPromoFlash = 0,
    chargeFrac = 0,
    chargeEnergyAlpha = 0.00,
    chargeWasFull = false,
    lastChargeExplosionAt = 0,
    chargeTier5HoldUntil = 0,
    chargeLightningFx = nil,
}

local PressureVisualModel
local PressureTierModel
local PressureSampleModel

local PRESSURE_TIER_MODE_SIMPLE = "simple"
local PRESSURE_TIER_MODE_PERCENTILE_POC = "percentile_live_poc"

local function ResolvePressureTierMode(rawMode)
    local mode = tostring(rawMode or ""):lower()
    if mode == "percentile"
        or mode == "poc"
        or mode == "live"
        or mode == PRESSURE_TIER_MODE_PERCENTILE_POC
    then
        return PRESSURE_TIER_MODE_PERCENTILE_POC
    end
    return PRESSURE_TIER_MODE_SIMPLE
end

local function GetConfiguredPressureTierMode()
    local db = ShammyTime.GetDB and ShammyTime.GetDB()
    local configured = db and db.pressureTierModelMode
    local explicit = db and db.pressureTierModelModeExplicit
    local resolved = ResolvePressureTierMode(configured)
    -- Migration behavior: existing profiles that never explicitly chose a mode
    -- should default to the new percentile model.
    if explicit ~= true and resolved == PRESSURE_TIER_MODE_SIMPLE then
        return PRESSURE_TIER_MODE_PERCENTILE_POC
    end
    return resolved
end

local function MakePressureTierModelContext()
    return {
        PS = PS,
        PUSH_FEEL_CFG = PUSH_FEEL_CFG,
        SmoothAlpha = SmoothAlpha,
        GetPressurePopupDBNumber = GetPressurePopupDBNumber,
        math_max = math_max,
        math_min = math_min,
    }
end

local function CreatePressureTierModelForMode(requestedMode)
    local PressureModels = ShammyTime.PressureModels
    if not PressureModels then
        return nil, PRESSURE_TIER_MODE_SIMPLE, "missing_models"
    end

    local resolved = ResolvePressureTierMode(requestedMode)
    local model = nil
    local fallback = nil
    if resolved == PRESSURE_TIER_MODE_PERCENTILE_POC
        and type(PressureModels.CreateTierModelPercentilePOC) == "function"
    then
        model = PressureModels.CreateTierModelPercentilePOC(MakePressureTierModelContext())
    else
        model = PressureModels.CreateTierModel(MakePressureTierModelContext())
        if resolved ~= PRESSURE_TIER_MODE_SIMPLE then
            fallback = "simple"
            resolved = PRESSURE_TIER_MODE_SIMPLE
        end
    end

    return model, resolved, fallback
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

frame:Show()

local DEBUG_LAYOUT = {
    lineHeight = 14,
    headerHeight = 22,
    padding = 6,
    frameWidth = 340,
    barHeight = 24,
}
local DEBUG_SUMMARY_LINES = 2
local DEBUG_SUMMARY_GAP = 4
local DEBUG_FRAME_HEIGHT = DEBUG_LAYOUT.headerHeight + DEBUG_LAYOUT.padding * 2 + DEBUG_LAYOUT.barHeight + 4
    + (DEBUG_LAYOUT.lineHeight * DEBUG_SUMMARY_LINES) + DEBUG_SUMMARY_GAP
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
debugText:SetText("ratio:0.00 eval:0.00 hold:0.00 tier:T0 (want T0 comp T0 0%) ok\nflow:hold +0% gate:0% target:0% shown:0%")

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
        -(DEBUG_LAYOUT.headerHeight + DEBUG_LAYOUT.padding + DEBUG_LAYOUT.barHeight + 4 + (DEBUG_LAYOUT.lineHeight * DEBUG_SUMMARY_LINES) + DEBUG_SUMMARY_GAP)
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
    [4] = 4, -- gaugeSeventyFive
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
    tauFast = 1.55,
    tauSlow = 20.0,
    epsilon = 1.0,
    pressureRatio = 0,
    displayGain = 1.20,
    burstDamping = 1.20,
    denominatorFloor = 200,
    startupSeedWindowSec = 2.40,
    displayTau = 0.42,
    displayTauRise = 0.07,
    pressureDisplaySmoothed = 0,
    pressureComposite = 0,
    instantScore = 0,
    squeezeScore = 0,
    tierScore = 0,
    tierEvalScore = 0,
    tierHoldScore = 0,
    tierEdgeResistance = 0,
    tierEdgeSlip = 0,
    currentTier = 0,
    lastTierChangeAt = 0,
    tierCapReason = "ok",
    recentHitImpulse = 0,
    squeezeCharge = 0,
    squeezeDecayTau = 18.0,
    squeezeBuildRate = 0.25,
    squeezeBonusMax = 0.85,
    squeezeBuildBaseline = 1.20,
    squeezeBuildPower = 1.20,
    squeezeIdleDecayMult = 0.45,
    tierInstantWeight = 0.95,
    tierSqueezeWeight = 0.65,
    tierHysteresis = 0.28,
    tierHoldMinSec = 5.00,
    tierTopHoldMinSec = 1.00,
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
    tierMomentumIdleDecayTau = 2.20,
    tierMomentumIdleGrace = 0.90,
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
    tierModelMode = PRESSURE_TIER_MODE_PERCENTILE_POC,
}

local function ExportPressureState()
    ShammyTime.PressureState = PS
    ShammyTime.GetPressureState = function()
        return PS
    end
    _G.ShammyTimePressureState = PS
    _G.ShammyTime_PressureState = PS
end

ExportPressureState()

do
    local PressureModels = ShammyTime.PressureModels
    if not PressureModels
        or (type(PressureModels.CreateSampleModel) ~= "function")
        or (type(PressureModels.CreateTierModel) ~= "function")
        or (type(PressureModels.CreateVisualModel) ~= "function")
    then
        print(ADDON_PREFIX .. " pressure models missing; disabling pressure engine.")
        return
    end

    PressureSampleModel = PressureModels.CreateSampleModel({
        PS = PS,
        WINDOWS = WINDOWS,
        NUM_WINDOWS = NUM_WINDOWS,
        math_max = math_max,
    })

    local requestedMode = GetConfiguredPressureTierMode()
    local fallbackMode
    PressureTierModel, PS.tierModelMode, fallbackMode = CreatePressureTierModelForMode(requestedMode)
    if not PressureTierModel then
        print(ADDON_PREFIX .. " failed to create pressure tier model; disabling pressure engine.")
        return
    end
    if fallbackMode then
        print(ADDON_PREFIX .. " pressure mode '" .. tostring(requestedMode) .. "' unavailable; using 'simple'.")
    end
    do
        local db = ShammyTime.GetDB and ShammyTime.GetDB()
        if db then
            db.pressureTierModelMode = PS.tierModelMode
            if db.pressureTierModelModeExplicit == nil then
                db.pressureTierModelModeExplicit = false
            end
        end
    end

    PressureVisualModel = PressureModels.CreateVisualModel({
        frame = frame,
        gaugeKeys = gaugeKeys,
        gaugeCurrentAlpha = gaugeCurrentAlpha,
        visualAnimState = visualAnimState,
        colorOverlayState = colorOverlayState,
        PUSH_FEEL_CFG = PUSH_FEEL_CFG,
        PS = PS,
        TIER_COLORS = TIER_COLORS,
        TIER_GAUGE_INDEX = TIER_GAUGE_INDEX,
        TIER_GAUGE_ALPHA = TIER_GAUGE_ALPHA,
        DISPLAY_WIDTH = DISPLAY_WIDTH,
        MIN_FILL_U = MIN_FILL_U,
        CROP_TOP = CROP_TOP,
        CROP_BOTTOM = CROP_BOTTOM,
        FILL_HIDE_EPS = FILL_HIDE_EPS,
        FILL_SHOW_EPS = FILL_SHOW_EPS,
        FILL_FULL_EPSILON = FILL_FULL_EPSILON,
        FILL_FULL_HOLD_SEC = FILL_FULL_HOLD_SEC,
        FILL_SMOOTH_TAU_RISE = FILL_SMOOTH_TAU_RISE,
        FILL_SMOOTH_TAU_FALL = FILL_SMOOTH_TAU_FALL,
        OVERLAY_COLOR_TAU_IN = OVERLAY_COLOR_TAU_IN,
        OVERLAY_COLOR_TAU_OUT = OVERLAY_COLOR_TAU_OUT,
        SmoothAlpha = SmoothAlpha,
        math_abs = math_abs,
        math_exp = math_exp,
        math_max = math_max,
        math_min = math_min,
        GetTime = GetTime,
        getTierFillTarget = function(score, tier)
            return PressureTierModel.GetTierFillTarget(score, tier)
        end,
        getTierSegmentProgress = function(score)
            if PressureTierModel and PressureTierModel.GetTierSegmentProgress then
                return PressureTierModel.GetTierSegmentProgress(score)
            end
            local t = PressureTierModel and PressureTierModel.GetTier and PressureTierModel.GetTier(score) or 0
            local f = PressureTierModel and PressureTierModel.GetTierFillTarget and PressureTierModel.GetTierFillTarget(score, t) or 0
            return t or 0, f or 0
        end,
        getTierPromoteThreshold = function(tier)
            if PressureTierModel and PressureTierModel.GetPromoteThreshold then
                return PressureTierModel.GetPromoteThreshold(tier)
            end
            return nil
        end,
    })

    PressureVisualModel.SetGaugeTextureOffset(0, 0)
    if frame.textures.colorOverlay then
        frame.textures.colorOverlay:SetAlpha(1)
    end
    PressureVisualModel.SetColorOverlayFill(colorOverlayState.fillFrac)

    ShammyTime.ApplyPressureTuningSettings = PressureTierModel.ApplyTuningSettings
    PressureTierModel.ApplyTuningSettings()
end

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

    -- Pressure is raw-damage driven: every hit contributes its real damage amount.
    local feedAmount = amount

    PS.fastCharge = PS.fastCharge + feedAmount
    PS.slowCharge = PS.slowCharge + feedAmount
    PS.recentHitImpulse = PS.recentHitImpulse + feedAmount
    PS.lastDamageTime = now
    if PressureTierModel and PressureTierModel.RecordDamageEvent then
        -- Overdrive is also based on raw hit size.
        PressureTierModel.RecordDamageEvent(amount, now)
    end

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

local function ClearPressureDebugFrame()
    debugBar:SetValue(0.0)
    debugBar:SetStatusBarColor(0.5, 0.5, 0.5)
    debugBarText:SetText("0.00x")
    debugBarTierText:SetText("T0")
    debugBarTierText:SetTextColor(0.6, 0.6, 0.6)
    debugText:SetText("ratio:0.00 eval:0.00 hold:0.00 tier:T0 (want T0 comp T0 0%) ok\nflow:hold +0% gate:0% target:0% shown:0%")
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

    local liveResPct = 0
    local resistMax = math_max(PS.tierEdgeResistMax or 0.001, 0.001)
    liveResPct = math_min(math_max(((PS.tierEdgeResistance or 0) / resistMax) * 100, 0), 999)

    local liveSlipPct = 0
    local slipCap = 0.035 * math_max(PS.simpleRubberband or 1, 0)
    if slipCap > 0 then
        liveSlipPct = math_min(math_max(((PS.tierEdgeSlip or 0) / slipCap) * 100, 0), 999)
    end

    local scoreForBuild = PS.tierEvalScore or PS.tierScore or 0
    local targetFillRaw = 0
    if PressureTierModel and PressureTierModel.GetTierFillTarget then
        targetFillRaw = PressureTierModel.GetTierFillTarget(scoreForBuild, tier)
    end
    local shownFill = colorOverlayState.fillFrac or 0
    local flowPct = (targetFillRaw - shownFill) * 100
    local flowDir = "hold"
    if flowPct > 1 then
        flowDir = "up"
    elseif flowPct < -1 then
        flowDir = "down"
    end
    local nextGate = 0
    if PressureTierModel and PressureTierModel.GetPromoteThreshold then
        if tier >= 5 then
            nextGate = (scoreForBuild > 0) and scoreForBuild or 1
        else
            nextGate = PressureTierModel.GetPromoteThreshold(tier + 1)
        end
    end
    local gatePct = 0
    if nextGate > 0 then
        gatePct = math_min(math_max((scoreForBuild / nextGate) * 100, 0), 999)
    end
    local candidateTier = tier
    if PressureTierModel and PressureTierModel.GetTier then
        candidateTier = PressureTierModel.GetTier(scoreForBuild or 0)
    end
    local computedTier = candidateTier
    local computedFrac = targetFillRaw
    if PressureTierModel and PressureTierModel.GetTierSegmentProgress then
        local segTier, segFrac = PressureTierModel.GetTierSegmentProgress(scoreForBuild or 0)
        if segTier ~= nil then
            computedTier = math_min(math_max(math_floor(tonumber(segTier) or computedTier), 0), 5)
        end
        if segFrac ~= nil then
            computedFrac = math_min(math_max(tonumber(segFrac) or computedFrac, 0), 1)
        end
    end
    local nextReq = nextGate
    if tier >= 5 then
        nextReq = scoreForBuild
    end

    local tune = PS.debugTune
    if tune then
        debugText:SetText(string.format(
            "ratio:%.2f eval:%.2f hold:%.2f tier:T%d (want T%d comp T%d %.0f%%) %s\nmode:%s flow:%s %+.0f%% gate:%.0f%% target:%.0f%% shown:%.0f%%",
            PS.pressureRatio or 0,
            PS.tierEvalScore or 0,
            PS.tierHoldScore or 0,
            tier,
            candidateTier,
            computedTier,
            computedFrac * 100,
            PS.tierCapReason or "ok",
            PS.tierModelMode or PRESSURE_TIER_MODE_SIMPLE,
            flowDir,
            flowPct,
            gatePct,
            targetFillRaw * 100,
            shownFill * 100
        ))

        bucketStrings[1]:SetText(string.format(
            "DPS: live %.0f  fight %.0f  base %.0f  delta %+.0f%%",
            PS.debugCurrentDps or 0,
            PS.debugFightDps or 0,
            PS.debugMedianDps or 0,
            PS.debugDpsAbovePct or 0
        ))
        bucketStrings[2]:SetText(string.format(
            "Req next: %.2f  now:%.2f  hold:%.2f",
            nextReq or 0,
            scoreForBuild or 0,
            PS.tierHoldScore or 0
        ))
        bucketStrings[3]:SetText(string.format(
            "Feel: R %.2f  RB %.2f  Base %.2f  Step %.1f%%",
            tune.resistance or 0,
            tune.rubberband or 0,
            tune.tierBase or 0,
            tune.tierStepPct or 0
        ))
        bucketStrings[4]:SetText(string.format(
            "Hold cfg: help %.2f  hold %.2fs  hyst %.2f",
            tune.tierHelp or 0,
            tune.holdSec or 0,
            PS.tierHysteresis or 0
        ))
        bucketStrings[5]:SetText(string.format(
            "Overdrive: need %.0f  hit %+.0f%%  samples %d",
            PS.debugOverdriveHitThreshold or 0,
            PS.debugOverdriveHitAbovePct or 0,
            PS.overdriveSampleCount or 0
        ))
        if NUM_WINDOWS > 5 then
            for wi = 6, NUM_WINDOWS do
                bucketStrings[wi]:SetText("")
            end
        end
    else
        debugText:SetText(string.format(
            "ratio:%.2f eval:%.2f hold:%.2f tier:T%d (want T%d comp T%d %.0f%%) %s\nmode:%s flow:%s %+.0f%% gate:%.0f%% target:%.0f%% shown:%.0f%%",
            PS.pressureRatio or 0,
            PS.tierEvalScore or 0,
            PS.tierHoldScore or 0,
            tier,
            candidateTier,
            computedTier,
            computedFrac * 100,
            PS.tierCapReason or "ok",
            PS.tierModelMode or PRESSURE_TIER_MODE_SIMPLE,
            flowDir,
            flowPct,
            gatePct,
            targetFillRaw * 100,
            shownFill * 100
        ))
        for wi = 1, NUM_WINDOWS do
            local w = WINDOWS[wi]
            bucketStrings[wi]:SetText(string.format(
                "%3ds:  avg %.2fx  max %.2fx",
                w, PS.pressureBucketAvg[wi] or 0, PS.pressureBucketMax[wi] or 0
            ))
        end
    end
end

local function SetPressureDebugVisible(visible)
    if visible then
        debugFrame:Show()
        UpdatePressureDebugFrame(0)
    else
        debugFrame:Hide()
    end
end

ShammyTime.RefreshPressureDebugMetrics = function()
    UpdatePressureDebugFrame(0)
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
    PS.tierHoldScore = 0
    PS.tierEdgeResistance = 0
    PS.tierEdgeSlip = 0
    PS.tierMomentumBoost = 0
    PS.currentTier = 0
    PS.lastTierChangeAt = 0
    PS.tierCapReason = "ok"
    PS.recentHitImpulse = 0
    PS.squeezeCharge = 0
    if PressureTierModel and PressureTierModel.ResetRuntime then
        PressureTierModel.ResetRuntime(true)
    end
    PS.firstPressureAt = nil
    PS.lastDamageTime = 0
    PS.pressureElapsed = 0
    PressureSampleModel.Clear()
    PS.bucketStatsElapsed = 0
    for wi = 1, NUM_WINDOWS do
        PS.pressureBucketAvg[wi] = 0
        PS.pressureBucketMax[wi] = 0
    end
    colorOverlayState.fillFrac = 0
    colorOverlayState.fullHoldRemaining = 0
    colorOverlayState.fillVisible = false
    visualAnimState.colorOverlayTransferActive = false
    visualAnimState.colorOverlayTransferElapsed = 0
    visualAnimState.colorOverlayTransferFrom = 0
    visualAnimState.colorOverlayTransferTo = 0
    visualAnimState.promotionPending = false
    visualAnimState.gaugeShakeStress = 0
    visualAnimState.hitReact = 0
    visualAnimState.tierPromoFlash = 0
    visualAnimState.chargeFrac = 0
    visualAnimState.chargeEnergyAlpha = 0.00
    visualAnimState.chargeWasFull = false
    visualAnimState.lastChargeExplosionAt = 0
    visualAnimState.chargeTier5HoldUntil = 0
    PressureVisualModel.SetGaugeTextureOffset(0, 0)
    if PressureVisualModel and PressureVisualModel.ResetChargeEffects then
        PressureVisualModel.ResetChargeEffects()
    end
    for i, key in ipairs(gaugeKeys) do
        gaugeCurrentAlpha[i] = (i == 1) and 1 or 0
        local tex = frame.textures[key]
        if tex then
            tex:SetAlpha(gaugeCurrentAlpha[i])
        end
    end
    colorOverlayState.currentColor[1] = TIER_COLORS[1][1]
    colorOverlayState.currentColor[2] = TIER_COLORS[1][2]
    colorOverlayState.currentColor[3] = TIER_COLORS[1][3]
    if frame.textures.colorOverlay then
        frame.textures.colorOverlay:SetVertexColor(
            colorOverlayState.currentColor[1],
            colorOverlayState.currentColor[2],
            colorOverlayState.currentColor[3]
        )
    end
    ResetDriverPopupState()
    PressureVisualModel.SetColorOverlayFill(colorOverlayState.fillFrac)
    ClearPressureDebugFrame()
end

ShammyTime.ResetPressureState = ResetPressureState

local function SetPressureTierMode(mode, quiet)
    local requested = ResolvePressureTierMode(mode)
    local newModel, activeMode, fallbackMode = CreatePressureTierModelForMode(requested)
    if not newModel then
        if not quiet then
            print(ADDON_PREFIX .. " failed to switch pressure mode.")
        end
        return false
    end

    PressureTierModel = newModel
    PS.tierModelMode = activeMode

    local db = ShammyTime.GetDB and ShammyTime.GetDB()
    if db then
        db.pressureTierModelMode = activeMode
        db.pressureTierModelModeExplicit = true
    end

    ShammyTime.ApplyPressureTuningSettings = PressureTierModel.ApplyTuningSettings
    if PressureTierModel and PressureTierModel.ApplyTuningSettings then
        PressureTierModel.ApplyTuningSettings()
    end
    ResetPressureState()
    ExportPressureState()

    if not quiet then
        if fallbackMode then
            print(ADDON_PREFIX .. " pressure mode '" .. tostring(mode) .. "' unavailable; using 'simple'.")
        else
            print(ADDON_PREFIX .. " pressure mode set to '" .. activeMode .. "'.")
        end
    end
    return true
end

ShammyTime.SetPressureTierMode = SetPressureTierMode

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
    local now = GetTime()
    if (PS.currentTier or 0) > 0 then return true end
    if (PS.pressureDisplaySmoothed or 0) > PRESSURE_VISUAL_CFG.visualActivityEps then return true end
    if (PS.squeezeCharge or 0) > PRESSURE_VISUAL_CFG.visualActivityEps then return true end
    if (PS.pressureComposite or 0) > PRESSURE_VISUAL_CFG.visualActivityEps then return true end
    if colorOverlayState.fillVisible and (colorOverlayState.fillFrac or 0) > PRESSURE_VISUAL_CFG.visualOverlayEps then return true end
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
    PS.tierHoldScore = 0
    PS.tierEdgeResistance = 0
    PS.tierEdgeSlip = 0
    PS.tierMomentumBoost = 0
    PS.squeezeCharge = 0
    PS.recentHitImpulse = 0
    PS.tierCapReason = "ok"
    if PressureTierModel and PressureTierModel.ResetRuntime then
        PressureTierModel.ResetRuntime(false)
    end
    PS.firstPressureAt = nil
    PressureSampleModel.Clear()
    visualAnimState.colorOverlayTransferActive = false
    visualAnimState.colorOverlayTransferElapsed = 0
    visualAnimState.colorOverlayTransferFrom = 0
    visualAnimState.colorOverlayTransferTo = 0
    visualAnimState.promotionPending = false
    visualAnimState.gaugeShakeStress = 0
    visualAnimState.hitReact = 0
    visualAnimState.tierPromoFlash = 0
    visualAnimState.chargeFrac = 0
    visualAnimState.chargeEnergyAlpha = 0.00
    visualAnimState.chargeWasFull = false
    visualAnimState.lastChargeExplosionAt = 0
    visualAnimState.chargeTier5HoldUntil = 0
    PressureVisualModel.SetGaugeTextureOffset(0, 0)
    if PressureVisualModel and PressureVisualModel.ResetChargeEffects then
        PressureVisualModel.ResetChargeEffects()
    end
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
    local visualElapsed = math_min(math_max(dt or 0, 0), 0.05)
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

    local visualSlowCharge = PS.slowCharge
    if PS.firstPressureAt and PS.firstPressureAt > 0 and PS.fastCharge > 0 then
        local warmWindow = math_max(PS.startupSeedWindowSec or 2.40, 0.01)
        local age = now - PS.firstPressureAt
        local fade = 1 - math_min(math_max(age / warmWindow, 0), 1)
        if fade > 0 then
            local seedSlow = (PS.fastCharge * (PS.tauSlow / math_max(PS.tauFast, 0.001))) * fade
            if visualSlowCharge < seedSlow then
                visualSlowCharge = seedSlow
            end
        end
    end

    local visualScale = PS.tauFast / math_max(PS.tauSlow, 0.001)
    local visualSteadyDen = visualSlowCharge * visualScale
    local visualDampedDen = (visualSteadyDen + (PS.fastCharge * PS.burstDamping)) / (1 + PS.burstDamping)
    visualDampedDen = math_max(visualDampedDen, PS.denominatorFloor)
    local visualImpulsePressure = PS.recentHitImpulse / math_max(visualDampedDen, PS.epsilon)

    PS.pressureElapsed = PS.pressureElapsed + dt
    if PS.pressureElapsed < PS.pressureTick then
        PressureVisualModel.Update(visualElapsed, now, visualImpulsePressure)
        return
    end
    local elapsed = PS.pressureElapsed
    PS.pressureElapsed = 0

    PS.fastCharge = PS.fastCharge * math_exp(-elapsed / math_max(PS.tauFast, 0.01))
    PS.slowCharge = PS.slowCharge * math_exp(-elapsed / math_max(PS.tauSlow, 0.01))
    if PS.fastCharge < 0.01 then PS.fastCharge = 0 end
    if PS.slowCharge < 0.01 then PS.slowCharge = 0 end

    -- Fight-start stabilization: seed the long-window reference from fast charge,
    -- then fade it out over the startup window to avoid spike-then-collapse behavior.
    if PS.firstPressureAt and PS.firstPressureAt > 0 and PS.fastCharge > 0 then
        local warmWindow = math_max(PS.startupSeedWindowSec or 2.40, 0.01)
        local age = now - PS.firstPressureAt
        local fade = 1 - math_min(math_max(age / warmWindow, 0), 1)
        if fade > 0 then
            local seedSlow = (PS.fastCharge * (PS.tauSlow / math_max(PS.tauFast, 0.001))) * fade
            if PS.slowCharge < seedSlow then
                PS.slowCharge = seedSlow
            end
        end
    end

    local scale = PS.tauFast / math_max(PS.tauSlow, 0.001)
    local steadyDen = PS.slowCharge * scale
    local dampedDen = (steadyDen + (PS.fastCharge * PS.burstDamping)) / (1 + PS.burstDamping)
    dampedDen = math_max(dampedDen, PS.denominatorFloor)
    PS.pressureRatio = PS.fastCharge / math_max(dampedDen, PS.epsilon)
    PressureSampleModel.Update(now, elapsed, PS.pressureRatio)

    local targetDisplay = PS.pressureRatio * PS.displayGain
    local smoothingTau = (targetDisplay > PS.pressureDisplaySmoothed) and PS.displayTauRise or PS.displayTau
    local displayAlpha = 1 - math_exp(-elapsed / math_max(smoothingTau, 0.01))
    PS.pressureDisplaySmoothed = PS.pressureDisplaySmoothed + (targetDisplay - PS.pressureDisplaySmoothed) * displayAlpha

    PS.squeezeCharge = 0
    PS.pressureComposite = PS.pressureDisplaySmoothed
    PS.instantScore = PS.pressureDisplaySmoothed
    PS.squeezeScore = 0
    PS.tierScore = PS.instantScore
    PressureTierModel.UpdateTierMomentumBonus(elapsed, now)
    if PressureTierModel and PressureTierModel.UpdateDebugTelemetry then
        PressureTierModel.UpdateDebugTelemetry(now)
    end
    local edgeResistance, edgeSlip = PressureTierModel.GetTierResistanceAndSlip(PS.tierScore, now)
    PS.tierEdgeResistance = edgeResistance
    PS.tierEdgeSlip = edgeSlip
    -- Climb score stays "pure" (damage pressure vs resistance).
    PS.tierEvalScore = PS.tierScore - edgeResistance - edgeSlip
    -- Hold score adds tier-help so reached tiers feel stable instead of instantly dropping.
    PS.tierHoldScore = PS.tierEvalScore + math_max(PS.tierMomentumBoost or 0, 0)

    PS.recentHitImpulse = PS.recentHitImpulse * math_exp(-elapsed / math_max(PS.hitImpulseTau, 0.1))
    local impulsePressure = PS.recentHitImpulse / math_max(dampedDen, PS.epsilon)
    local hitKick = math_min(impulsePressure * 0.25, 1.0)

    local candidateTier = PressureTierModel.GetTier(PS.tierEvalScore)
    local gatedTier = candidateTier
    PS.tierCapReason = "ok"
    local canPromoteNow = (now - (PS.lastTierChangeAt or 0)) >= PUSH_FEEL_CFG.tierPromotionStepLockSec
    local isPercentilePOC = (PS.tierModelMode == PRESSURE_TIER_MODE_PERCENTILE_POC)
    visualAnimState.promotionPending = false
    local overdriveTierBoost = 0
    if PressureTierModel and PressureTierModel.ConsumeOverdriveTierBoost then
        overdriveTierBoost = math_max(PressureTierModel.ConsumeOverdriveTierBoost() or 0, 0)
    end

    if overdriveTierBoost > 0 and PS.currentTier < 5 then
        local overdriveTarget = math_min(PS.currentTier + overdriveTierBoost, 5)
        if overdriveTarget > PS.currentTier then
            PS.currentTier = overdriveTarget
            PS.lastTierChangeAt = now
            PS.tierMomentumBoost = math_min(
                (PS.tierMomentumBoost or 0) + (PS.tierMomentumOnPromote or 0),
                math_max(PS.tierMomentumMax or 0, 0)
            )
            local transferFrom = math_min(math_max(colorOverlayState.fillFrac or 0, 0), 1)
            if PUSH_FEEL_CFG.chargeVisualMode == false and PS.currentTier >= 5 then
                transferFrom = 1
                colorOverlayState.fillFrac = 1
            end
            PressureVisualModel.StartColorOverlayTransferDrop(transferFrom)
            visualAnimState.promotionPending = false
        end
    elseif gatedTier > PS.currentTier then
        if isPercentilePOC then
            if canPromoteNow then
                local previousTier = PS.currentTier
                local promoteStep = 1
                -- Big spikes can still jump faster, but avoid full tier whiplash.
                if gatedTier >= 5 and (gatedTier - previousTier) >= 2 then
                    promoteStep = 2
                end
                PS.currentTier = math_min(gatedTier, PS.currentTier + promoteStep)
                PS.lastTierChangeAt = now
                PS.tierMomentumBoost = math_min(
                    (PS.tierMomentumBoost or 0) + (PS.tierMomentumOnPromote or 0),
                    math_max(PS.tierMomentumMax or 0, 0)
                )
                if PS.currentTier > previousTier then
                    local transferFrom = math_min(math_max(colorOverlayState.fillFrac or 0, 0), 1)
                    if PUSH_FEEL_CFG.chargeVisualMode == false and PS.currentTier >= 5 then
                        transferFrom = 1
                        colorOverlayState.fillFrac = 1
                    end
                    PressureVisualModel.StartColorOverlayTransferDrop(transferFrom)
                end
            end
            visualAnimState.promotionPending = false
        else
            local currentTierFillRaw = PressureTierModel.GetTierFillTarget(PS.tierEvalScore or PS.tierScore or 0, PS.currentTier)
            local scoreReadyForPromotion = currentTierFillRaw >= FILL_FULL_EPSILON
            if scoreReadyForPromotion then
                visualAnimState.promotionPending = true
            end

            if canPromoteNow and visualAnimState.promotionPending then
                local previousTier = PS.currentTier
                PS.currentTier = math_min(gatedTier, PS.currentTier + 1)
                PS.lastTierChangeAt = now
                PS.tierMomentumBoost = math_min(
                    (PS.tierMomentumBoost or 0) + (PS.tierMomentumOnPromote or 0),
                    math_max(PS.tierMomentumMax or 0, 0)
                )
                if PS.currentTier > previousTier then
                    local transferFrom = math_min(math_max(colorOverlayState.fillFrac or 0, 0), 1)
                    if PUSH_FEEL_CFG.chargeVisualMode == false and PS.currentTier >= 5 then
                        transferFrom = 1
                        colorOverlayState.fillFrac = 1
                    end
                    PressureVisualModel.StartColorOverlayTransferDrop(transferFrom)
                end
                visualAnimState.promotionPending = false
            end
        end
    elseif gatedTier < PS.currentTier then
        -- If the pure score wants a lower tier, step down after hold time.
        -- This avoids getting stuck at high tiers when hold-assist is active.
        local holdMinSec = PS.tierHoldMinSec or 0
        if PS.currentTier >= 5 then
            -- Keep T5 stable long enough for top-end visuals to read cleanly.
            holdMinSec = math_max(holdMinSec, PS.tierTopHoldMinSec or 1.00)
        end
        local holdElapsed = now - PS.lastTierChangeAt
        if holdElapsed >= holdMinSec then
            PS.currentTier = math_max(gatedTier, PS.currentTier - 1)
            PS.lastTierChangeAt = now
        end
    end

    PressureVisualModel.Update(visualElapsed, now, impulsePressure)
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
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
    if event == "PLAYER_REGEN_DISABLED" then
        local now = GetTime()
        if PressureTierModel and PressureTierModel.StartCombatDamageMeter then
            PressureTierModel.StartCombatDamageMeter(now)
        elseif PressureTierModel and PressureTierModel.ResetRuntime then
            PressureTierModel.ResetRuntime(false)
        end
        UpdatePressureDebugFrame(0)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        local now = GetTime()
        if PressureTierModel and PressureTierModel.EndCombatDamageMeter then
            PressureTierModel.EndCombatDamageMeter(now, DAMAGE_METER_POST_COMBAT_SEC)
        elseif PressureTierModel and PressureTierModel.ResetRuntime then
            PressureTierModel.ResetRuntime(false)
        end
        UpdatePressureDebugFrame(0)
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
    print("  /st pressure mode simple|percentile")
    print("  /st pressure taufast N")
    print("  /st pressure tauslow N")
    print("  /st pressure gain N")
    print("  /st pressure damp N")
    print("  /st pressure smoothtau N")
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
            " n=%.3f i=%.3f ts=%.3f te=%.3f m=%.3f r=%.3f s=%.3f tier=T%d cap=%s",
            PS.pressureRatio, PS.instantScore, PS.tierScore,
            PS.tierEvalScore or 0, PS.tierMomentumBoost or 0, PS.tierEdgeResistance or 0, PS.tierEdgeSlip or 0,
            PS.currentTier or 0, PS.tierCapReason or "ok"
        ))
        print(ADDON_PREFIX .. string.format(
            " tauFast=%.2f tauSlow=%.2f gain=%.2f damp=%.2f smoothTau=%.2f",
            PS.tauFast, PS.tauSlow, PS.displayGain, PS.burstDamping,
            PS.displayTau
        ))
        print(ADDON_PREFIX .. " mode=" .. tostring(PS.tierModelMode or PRESSURE_TIER_MODE_SIMPLE))
        return
    end

    if cmd == "mode" then
        local modeArg = (arg or ""):lower():match("^%s*(.-)%s*$")
        if modeArg == "" or modeArg == "status" or modeArg == "show" then
            print(ADDON_PREFIX .. " mode=" .. tostring(PS.tierModelMode or PRESSURE_TIER_MODE_SIMPLE))
            print(ADDON_PREFIX .. " available: simple, percentile")
            return
        end
        if modeArg == "simple"
            or modeArg == "percentile"
            or modeArg == "poc"
            or modeArg == "live"
            or modeArg == PRESSURE_TIER_MODE_PERCENTILE_POC
        then
            SetPressureTierMode(modeArg, false)
        else
            print(ADDON_PREFIX .. " unknown mode '" .. tostring(modeArg) .. "'. Available: simple, percentile")
        end
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
