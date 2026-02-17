-- ShammyTime_Options.lua
-- AceConfig options table and Blizzard Interface Options integration.
-- Structure: General | Modules (tabs) | Developer (hidden unless devMode=true)

local LibStub = LibStub
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local ShammyTime = _G.ShammyTime
if not ShammyTime then return end

-- Satellite bubble names (for per-bubble text position overrides)
local SATELLITE_NAMES = { "air", "stone", "fire", "grass", "water", "grass_2" }
local SATELLITE_LABELS = {
    air = "MIN (Air)",
    stone = "MAX (Stone)",
    fire = "AVG (Fire)",
    grass = "PROCS (Grass)",
    water = "PROC% (Water)",
    grass_2 = "CRIT% (Grass 2)",
}

--------------------------------------------------------------------------------
-- Helpers (always use _G.ShammyTime to get the db set in OnInitialize)
--------------------------------------------------------------------------------
local function getDB()
    local st = _G.ShammyTime
    return st and st.db and st.db.profile
end

local function getGlobal()
    local p = getDB()
    if not p then return nil end
    if not p.global then
        p.global = { locked = false, demoMode = false, masterScale = 1, masterAlpha = 1, devMode = false }
    end
    return p.global
end

local function getModule(name)
    local p = getDB()
    return p and p.modules and p.modules[name]
end

-- Normalize user-facing scale values so "current default visual size" = 1.0
-- for specific circular indicators that historically used different raw scales.
local MODULE_SCALE_NORMALIZATION = {
    shieldIndicator = { base = 0.4, minRaw = 0.05, maxRaw = 3 },
    shamanisticFocus = { base = 1.3, minRaw = 0.1, maxRaw = 3 },
    windfuryIcd = { base = 1.1, minRaw = 0.1, maxRaw = 3 },
}
local MODULE_SCALE_STEP = 0.05

local function round2(v)
    return math.floor((v * 100) + 0.5) / 100
end

local function roundUpToStep(v, step)
    return math.ceil((v / step) - 1e-9) * step
end

local function roundDownToStep(v, step)
    return math.floor((v / step) + 1e-9) * step
end

local function getScaleRule(moduleName)
    return moduleName and MODULE_SCALE_NORMALIZATION[moduleName] or nil
end

local function toDisplayScale(moduleName, rawScale)
    local rule = getScaleRule(moduleName)
    if not rule then return rawScale end
    return rawScale / rule.base
end

local function toRawScale(moduleName, displayScale)
    local rule = getScaleRule(moduleName)
    if not rule then return displayScale end
    return displayScale * rule.base
end

local function getScaleRawDefault(moduleName)
    local rule = getScaleRule(moduleName)
    if rule then return rule.base end
    return 1
end

local function getScaleRawBounds(moduleName)
    local rule = getScaleRule(moduleName)
    if rule then
        return rule.minRaw, rule.maxRaw
    end
    return 0.1, 3
end

local function getScaleDisplayBounds(moduleName)
    local minRaw, maxRaw = getScaleRawBounds(moduleName)
    local minDisplay = toDisplayScale(moduleName, minRaw)
    local maxDisplay = toDisplayScale(moduleName, maxRaw)
    minDisplay = round2(roundUpToStep(minDisplay, MODULE_SCALE_STEP))
    maxDisplay = round2(roundDownToStep(maxDisplay, MODULE_SCALE_STEP))
    if maxDisplay < minDisplay then maxDisplay = minDisplay end
    return minDisplay, maxDisplay
end

-- Resolve module name from AceConfig info (arg, option.arg, or path when in Modules group)
local function getModuleKeyFromInfo(info)
    if info.arg and info.arg.module then return info.arg.module end
    if info.option and info.option.arg and info.option.arg.module then return info.option.arg.module end
    -- AceConfig path: ["Modules", "windfuryBubbles", "scale"] -> module is info[2]
    if info[1] == "Modules" and type(info[2]) == "string" and getModule(info[2]) then return info[2] end
    return nil
end

-- Generic getter/setter for module settings (AceConfig may pass module in info.arg or info.option.arg)
local function getModuleOption(info, key)
    local modKey = getModuleKeyFromInfo(info)
    local m = getModule(modKey)
    if not m then return nil end
    if key == "enabled" then return m.enabled ~= false end
    if key == "scale" then
        local rawScale = (type(m.scale) == "number") and m.scale or getScaleRawDefault(modKey)
        local displayScale = toDisplayScale(modKey, rawScale)
        local minDisplay, maxDisplay = getScaleDisplayBounds(modKey)
        if displayScale < minDisplay then displayScale = minDisplay end
        if displayScale > maxDisplay then displayScale = maxDisplay end
        return round2(displayScale)
    end
    if key == "alpha" then return m.alpha or 1 end
    if key == "fadeEnabled" then return m.fade and m.fade.enabled or false end
    if key == "inactiveAlpha" then return m.fade and m.fade.inactiveAlpha or 0 end
    if key == "outOfCombat" then return m.fade and m.fade.conditions and m.fade.conditions.outOfCombat or false end
    if key == "noTarget" then return m.fade and m.fade.conditions and m.fade.conditions.noTarget or false end
    if key == "inactiveBuff" then return m.fade and m.fade.conditions and m.fade.conditions.inactiveBuff or false end
    if key == "noTotemsPlaced" then return m.fade and m.fade.conditions and m.fade.conditions.noTotemsPlaced or false end
    if key == "outOfRange" then return m.fade and m.fade.conditions and m.fade.conditions.outOfRange or false end
    if key == "fadeInOnTarget" then return m.fade and m.fade.conditions and m.fade.conditions.fadeInOnTarget or false end
    if key == "hideWhenActive" then return m.fade and m.fade.conditions and m.fade.conditions.hideWhenActive or false end
    return nil
end

local function setModuleOption(info, val, key)
    local modKey = getModuleKeyFromInfo(info)
    local m = getModule(modKey)
    if not m then return end
    if key == "enabled" then m.enabled = val end
    if key == "scale" then
        local rawMin, rawMax = getScaleRawBounds(modKey)
        local displayScale = round2(tonumber(val) or 1)
        local rawScale = toRawScale(modKey, displayScale)
        if rawScale < rawMin then rawScale = rawMin end
        if rawScale > rawMax then rawScale = rawMax end
        m.scale = rawScale
    end
    if key == "alpha" then m.alpha = val end
    if key == "fadeEnabled" then m.fade = m.fade or {}; m.fade.enabled = val end
    if key == "inactiveAlpha" then m.fade = m.fade or {}; m.fade.inactiveAlpha = val end
    if key == "outOfCombat" then m.fade = m.fade or {}; m.fade.conditions = m.fade.conditions or {}; m.fade.conditions.outOfCombat = val end
    if key == "noTarget" then m.fade = m.fade or {}; m.fade.conditions = m.fade.conditions or {}; m.fade.conditions.noTarget = val end
    if key == "inactiveBuff" then m.fade = m.fade or {}; m.fade.conditions = m.fade.conditions or {}; m.fade.conditions.inactiveBuff = val end
    if key == "noTotemsPlaced" then m.fade = m.fade or {}; m.fade.conditions = m.fade.conditions or {}; m.fade.conditions.noTotemsPlaced = val end
    if key == "outOfRange" then m.fade = m.fade or {}; m.fade.conditions = m.fade.conditions or {}; m.fade.conditions.outOfRange = val end
    if key == "fadeInOnTarget" then m.fade = m.fade or {}; m.fade.conditions = m.fade.conditions or {}; m.fade.conditions.fadeInOnTarget = val end
    if key == "hideWhenActive" then m.fade = m.fade or {}; m.fade.conditions = m.fade.conditions or {}; m.fade.conditions.hideWhenActive = val end
    -- When any condition is enabled, turn on fade so the condition takes effect without requiring "Enable Fade" separately.
    -- When all conditions are off, turn off fade so the "Enable Fade" checkbox stays in sync.
    if key == "outOfCombat" or key == "noTarget" or key == "inactiveBuff" or key == "noTotemsPlaced" or key == "outOfRange" or key == "fadeInOnTarget" or key == "hideWhenActive" then
        local c = m.fade and m.fade.conditions
        if c and (c.outOfCombat or c.noTarget or c.inactiveBuff or c.noTotemsPlaced or c.outOfRange or c.fadeInOnTarget or c.hideWhenActive) then
            m.fade.enabled = true
        else
            if m.fade then m.fade.enabled = false end
        end
    end
    local st = _G.ShammyTime
    if st and st.ApplyAllConfigs then st:ApplyAllConfigs() end
end

-- Getter/setter for flat DB keys (used by Developer section)
local function getFlatDB(key, default)
    local p = getDB()
    if not p then return default end
    local val = p[key]
    if val == nil then return default end
    return val
end

local function setFlatDB(key, val)
    local p = getDB()
    if p then p[key] = val end
    local st = _G.ShammyTime
    if st and st.ApplyAllConfigs then st:ApplyAllConfigs() end
end

local PRESSURE_DEV_DEFAULTS = {
    pressurePopupIconSize = 74,
    pressurePopupTextSize = 49,
    pressurePopupHoldSec = 5.20,
    pressurePopupFadeSec = 1.20,
    pressurePopupSustainSec = 6.00,
    pressurePopupCritBounceScale = 2.00,
    pressurePopupCritBounceSec = 0.20,
    pressureSlot1X = -130,
    pressureSlot1Y = -104,
    pressureSlot1TextX = 0,
    pressureSlot1TextY = -14,
    pressureSlot2X = 1,
    pressureSlot2Y = -123,
    pressureSlot2TextX = 0,
    pressureSlot2TextY = -16,
    pressureSlot3X = 135,
    pressureSlot3Y = -104,
    pressureSlot3TextX = -7,
    pressureSlot3TextY = -18,
    pressureTierConcavityDepth = 0.00,
    pressureTierMomentumOnPromote = 0.08,
    pressureTierMomentumPerTier = 0.04,
    pressureTierMomentumMax = 0.22,
    pressureTierMomentumDecayTau = 3.20,
    pressureTierMomentumIdleDecayTau = 1.15,
    pressureTierDamageReq1 = 1.50,
    pressureTierDamageReq2 = 1.85,
    pressureTierDamageReq3 = 2.32,
    pressureTierDamageReq4 = 3.05,
    pressureTierDamageReq5 = 3.90,
    pressureTierForceReq1 = 0.00,
    pressureTierForceReq2 = 0.18,
    pressureTierForceReq3 = 0.35,
    pressureTierForceReq4 = 0.70,
    pressureTierForceReq5 = 0.92,
}

local function resetPressureDevOptions()
    local p = getDB()
    if not p then return end
    for key, value in pairs(PRESSURE_DEV_DEFAULTS) do
        p[key] = value
    end
    local st = _G.ShammyTime
    if st and st.ApplyAllConfigs then st:ApplyAllConfigs() end
end

-- Getter/setter for per-satellite overrides
local function getSatelliteOverride(bubbleName, key, default)
    local p = getDB()
    if not p then return default end
    local overrides = p.wfSatelliteOverrides
    if not overrides or not overrides[bubbleName] then return default end
    local val = overrides[bubbleName][key]
    return val ~= nil and val or default
end

local function setSatelliteOverride(bubbleName, key, val)
    local p = getDB()
    if not p then return end
    p.wfSatelliteOverrides = p.wfSatelliteOverrides or {}
    p.wfSatelliteOverrides[bubbleName] = p.wfSatelliteOverrides[bubbleName] or {}
    p.wfSatelliteOverrides[bubbleName][key] = val
    local st = _G.ShammyTime
    if st and st.ApplySatelliteTextPosition then st.ApplySatelliteTextPosition() end
    if st and st.ApplySatelliteFontSizes then st.ApplySatelliteFontSizes() end
end

--- Clear all overrides for one bubble so it uses global settings (effectively 0 / no override).
local function resetSatelliteOverrides(bubbleName)
    local p = getDB()
    if not p then return end
    if p.wfSatelliteOverrides then
        p.wfSatelliteOverrides[bubbleName] = nil
        if not next(p.wfSatelliteOverrides) then p.wfSatelliteOverrides = nil end
    end
    local st = _G.ShammyTime
    if st and st.ApplySatelliteTextPosition then st.ApplySatelliteTextPosition() end
    if st and st.ApplySatelliteFontSizes then st.ApplySatelliteFontSizes() end
end

--------------------------------------------------------------------------------
-- Export Settings (100% coverage: all menu settings, bubbles, offsets, modules)
--------------------------------------------------------------------------------
local function BuildFullExportLines(useColorCodes)
    local p = getDB()
    local lines = {}
    local function sec(s) -- section header
        if useColorCodes then
            table.insert(lines, "|cff888888-- " .. s .. ":|r")
        else
            table.insert(lines, "-- " .. s)
        end
    end
    local function line(s)
        table.insert(lines, s)
    end

    if not p then
        if useColorCodes then
            table.insert(lines, "|cffff0000ShammyTime: No profile loaded.|r")
        else
            table.insert(lines, "ShammyTime: No profile loaded.")
        end
        return lines
    end

    sec("Global")
    line("locked = " .. tostring(p.locked))
    line("uiErrorTextEnabled = " .. tostring(p.uiErrorTextEnabled == true))
    if p.global then
        line("masterScale = " .. tostring(p.global.masterScale or 1))
        line("masterAlpha = " .. tostring(p.global.masterAlpha or 1))
        line("demoMode = " .. tostring(p.global.demoMode or false))
        line("devMode = " .. tostring(p.global.devMode or false))
    end
    line("")
    sec("Main frame position")
    line("point = " .. tostring(p.point or "CENTER"))
    line("relativeTo = " .. tostring(p.relativeTo or "UIParent"))
    line("relativePoint = " .. tostring(p.relativePoint or "CENTER"))
    line("x = " .. tostring(p.x or 0))
    line("y = " .. tostring(p.y or -180))
    line("scale = " .. tostring(p.scale or 1))
    line("")
    sec("Windfury frame position")
    line("wfPoint = " .. tostring(p.wfPoint or "TOP"))
    line("wfRelativeTo = " .. tostring(p.wfRelativeTo or "ShammyTimeFrame"))
    line("wfRelativePoint = " .. tostring(p.wfRelativePoint or "BOTTOM"))
    line("wfX = " .. tostring(p.wfX or 0))
    line("wfY = " .. tostring(p.wfY or -4))
    line("wfScale = " .. tostring(p.wfScale or 1))
    line("wfLocked = " .. tostring(p.wfLocked or false))
    line("windfuryTrackerEnabled = " .. tostring(p.windfuryTrackerEnabled ~= false))
    line("")
    sec("Show/hide elements")
    line("wfRadialEnabled = " .. tostring(p.wfRadialEnabled))
    line("wfTotemBarEnabled = " .. tostring(p.wfTotemBarEnabled))
    line("wfFocusEnabled = " .. tostring(p.wfFocusEnabled))
    line("wfImbueBarEnabled = " .. tostring(p.wfImbueBarEnabled))
    line("wfShieldEnabled = " .. tostring(p.wfShieldEnabled))
    line("wfAlwaysShowNumbers = " .. tostring(p.wfAlwaysShowNumbers))
    line("")
    sec("Fade settings")
    line("wfFadeOutOfCombat = " .. tostring(p.wfFadeOutOfCombat))
    line("wfFadeWhenNotProcced = " .. tostring(p.wfFadeWhenNotProcced))
    line("wfFocusFadeWhenNotProcced = " .. tostring(p.wfFocusFadeWhenNotProcced))
    line("wfFadeWhenNoTotems = " .. tostring(p.wfFadeWhenNoTotems))
    line("wfNoTotemsFadeDelay = " .. tostring(p.wfNoTotemsFadeDelay or 5))
    line("wfImbueFadeWhenLongDuration = " .. tostring(p.wfImbueFadeWhenLongDuration))
    line("wfImbueFadeThresholdSec = " .. tostring(p.wfImbueFadeThresholdSec or 120))
    line("")
    sec("Center ring")
    line("wfRadialScale = " .. tostring(p.wfRadialScale or 1))
    line("wfCenterSize = " .. tostring(p.wfCenterSize or "nil"))
    line("wfCenterTextTitleY = " .. tostring(p.wfCenterTextTitleY or 0))
    line("wfCenterTextTotalY = " .. tostring(p.wfCenterTextTotalY or 0))
    line("wfCenterTextCriticalY = " .. tostring(p.wfCenterTextCriticalY or 0))
    line("fontCircleTitle = " .. tostring(p.fontCircleTitle or 20))
    line("fontCircleTotal = " .. tostring(p.fontCircleTotal or 14))
    line("fontCircleCritical = " .. tostring(p.fontCircleCritical or 20))
    line("")
    sec("Satellite bubbles (global: gap, scale, text offsets)")
    line("wfSatelliteGap = " .. tostring(p.wfSatelliteGap or "nil"))
    line("wfSatelliteBubbleScale = " .. tostring(p.wfSatelliteBubbleScale or 1))
    line("wfSatelliteLabelX = " .. tostring(p.wfSatelliteLabelX or 0))
    line("wfSatelliteLabelY = " .. tostring(p.wfSatelliteLabelY or 0))
    line("wfSatelliteValueX = " .. tostring(p.wfSatelliteValueX or 0))
    line("wfSatelliteValueY = " .. tostring(p.wfSatelliteValueY or 0))
    line("fontSatelliteLabel = " .. tostring(p.fontSatelliteLabel or 8))
    line("fontSatelliteValue = " .. tostring(p.fontSatelliteValue or 13))
    line("")
    sec("Per-satellite overrides (small bubbles: labelX/Y, valueX/Y, labelSize, valueSize)")
    if p.wfSatelliteOverrides and next(p.wfSatelliteOverrides) then
        for name, ov in pairs(p.wfSatelliteOverrides) do
            if type(ov) == "table" and next(ov) then
                line("wfSatelliteOverrides[\"" .. tostring(name) .. "\"] = {")
                for k, v in pairs(ov) do
                    line("    " .. tostring(k) .. " = " .. tostring(v) .. ",")
                end
                line("}")
            end
        end
    else
        line("wfSatelliteOverrides = nil")
    end
    line("")
    sec("Totem bar")
    line("wfTotemBarScale = " .. tostring(p.wfTotemBarScale or 1))
    line("fontTotemTimer = " .. tostring(p.fontTotemTimer or 10))
    line("")
    sec("Shamanistic Focus (position and scale)")
    if p.focusFrame then
        line("focusFrame.point = " .. tostring(p.focusFrame.point or "CENTER"))
        line("focusFrame.relativeTo = " .. tostring(p.focusFrame.relativeTo or "UIParent"))
        line("focusFrame.relativePoint = " .. tostring(p.focusFrame.relativePoint or "CENTER"))
        line("focusFrame.x = " .. tostring(p.focusFrame.x or 0))
        line("focusFrame.y = " .. tostring(p.focusFrame.y or -150))
        line("focusFrame.scale = " .. tostring(p.focusFrame.scale or 1.17))
        line("focusFrame.locked = " .. tostring(p.focusFrame.locked or false))
    end
    line("")
    sec("Imbue bar (scale, layout, offsets, font)")
    line("imbueBarScale = " .. tostring(p.imbueBarScale or 0.75))
    line("imbueBarMargin = " .. tostring(p.imbueBarMargin or "nil"))
    line("imbueBarGap = " .. tostring(p.imbueBarGap or "nil"))
    line("imbueBarOffsetY = " .. tostring(p.imbueBarOffsetY or "nil"))
    line("imbueBarIconSize = " .. tostring(p.imbueBarIconSize or "nil"))
    line("fontImbueTimer = " .. tostring(p.fontImbueTimer or 16))
    line("")
    sec("Shield indicator")
    line("shieldScale = " .. tostring(p.shieldScale or 0.36))
    line("fontShieldCount = " .. tostring(p.fontShieldCount or 86))
    line("shieldCountX = " .. tostring(p.shieldCountX or 0))
    line("shieldCountY = " .. tostring(p.shieldCountY or 127))
    line("")
    sec("Pressure popup slots")
    line("pressurePopupIconSize = " .. tostring(p.pressurePopupIconSize or 74))
    line("pressurePopupTextSize = " .. tostring(p.pressurePopupTextSize or 49))
    line("pressurePopupHoldSec = " .. tostring(p.pressurePopupHoldSec or 5.20))
    line("pressurePopupFadeSec = " .. tostring(p.pressurePopupFadeSec or 1.20))
    line("pressurePopupSustainSec = " .. tostring(p.pressurePopupSustainSec or 6.00))
    line("pressurePopupCritBounceScale = " .. tostring(p.pressurePopupCritBounceScale or 2.00))
    line("pressurePopupCritBounceSec = " .. tostring(p.pressurePopupCritBounceSec or 0.20))
    line("pressureTierConcavityDepth = " .. tostring(p.pressureTierConcavityDepth or 0.00))
    line("pressureTierMomentumOnPromote = " .. tostring(p.pressureTierMomentumOnPromote or 0.08))
    line("pressureTierMomentumPerTier = " .. tostring(p.pressureTierMomentumPerTier or 0.04))
    line("pressureTierMomentumMax = " .. tostring(p.pressureTierMomentumMax or 0.22))
    line("pressureTierMomentumDecayTau = " .. tostring(p.pressureTierMomentumDecayTau or 3.20))
    line("pressureTierMomentumIdleDecayTau = " .. tostring(p.pressureTierMomentumIdleDecayTau or 1.15))
    line("pressureTierDamageReq1 = " .. tostring(p.pressureTierDamageReq1 or 1.50))
    line("pressureTierDamageReq2 = " .. tostring(p.pressureTierDamageReq2 or 1.85))
    line("pressureTierDamageReq3 = " .. tostring(p.pressureTierDamageReq3 or 2.32))
    line("pressureTierDamageReq4 = " .. tostring(p.pressureTierDamageReq4 or 3.05))
    line("pressureTierDamageReq5 = " .. tostring(p.pressureTierDamageReq5 or 3.90))
    line("pressureTierForceReq1 = " .. tostring(p.pressureTierForceReq1 or 0.00))
    line("pressureTierForceReq2 = " .. tostring(p.pressureTierForceReq2 or 0.18))
    line("pressureTierForceReq3 = " .. tostring(p.pressureTierForceReq3 or 0.35))
    line("pressureTierForceReq4 = " .. tostring(p.pressureTierForceReq4 or 0.70))
    line("pressureTierForceReq5 = " .. tostring(p.pressureTierForceReq5 or 0.92))
    line("pressureSlot1X = " .. tostring(p.pressureSlot1X or -130))
    line("pressureSlot1Y = " .. tostring(p.pressureSlot1Y or -104))
    line("pressureSlot1TextX = " .. tostring(p.pressureSlot1TextX or 0))
    line("pressureSlot1TextY = " .. tostring(p.pressureSlot1TextY or -14))
    line("pressureSlot2X = " .. tostring(p.pressureSlot2X or 1))
    line("pressureSlot2Y = " .. tostring(p.pressureSlot2Y or -123))
    line("pressureSlot2TextX = " .. tostring(p.pressureSlot2TextX or 0))
    line("pressureSlot2TextY = " .. tostring(p.pressureSlot2TextY or -16))
    line("pressureSlot3X = " .. tostring(p.pressureSlot3X or 135))
    line("pressureSlot3Y = " .. tostring(p.pressureSlot3Y or -104))
    line("pressureSlot3TextX = " .. tostring(p.pressureSlot3TextX or -7))
    line("pressureSlot3TextY = " .. tostring(p.pressureSlot3TextY or -18))
    line("")
    sec("Modules (per-element: enabled, scale, alpha, fade)")
    if p.modules then
        for modName in pairs(p.modules) do
            local m = p.modules[modName]
            if type(m) == "table" then
                line("modules." .. modName .. ".enabled = " .. tostring(m.enabled ~= false))
                line("modules." .. modName .. ".scale = " .. tostring(m.scale or 1))
                line("modules." .. modName .. ".alpha = " .. tostring(m.alpha or 1))
                if m.pos and type(m.pos) == "table" then
                    line("modules." .. modName .. ".pos.point = " .. tostring(m.pos.point or "CENTER"))
                    line("modules." .. modName .. ".pos.relPoint = " .. tostring(m.pos.relPoint or "CENTER"))
                    line("modules." .. modName .. ".pos.x = " .. tostring(m.pos.x or 0))
                    line("modules." .. modName .. ".pos.y = " .. tostring(m.pos.y or 0))
                end
                if m.fade and type(m.fade) == "table" then
                    line("modules." .. modName .. ".fade.enabled = " .. tostring(m.fade.enabled or false))
                    line("modules." .. modName .. ".fade.inactiveAlpha = " .. tostring(m.fade.inactiveAlpha or 0))
                    local c = m.fade.conditions
                    if c and type(c) == "table" then
                        line("modules." .. modName .. ".fade.conditions.outOfCombat = " .. tostring(c.outOfCombat or false))
                        line("modules." .. modName .. ".fade.conditions.noTarget = " .. tostring(c.noTarget or false))
                        line("modules." .. modName .. ".fade.conditions.inactiveBuff = " .. tostring(c.inactiveBuff or false))
                        line("modules." .. modName .. ".fade.conditions.noTotemsPlaced = " .. tostring(c.noTotemsPlaced or false))
                        line("modules." .. modName .. ".fade.conditions.outOfRange = " .. tostring(c.outOfRange or false))
                        line("modules." .. modName .. ".fade.conditions.fadeInOnTarget = " .. tostring(c.fadeInOnTarget or false))
                        line("modules." .. modName .. ".fade.conditions.hideWhenActive = " .. tostring(c.hideWhenActive or false))
                    end
                end
            end
        end
    end
    return lines
end

local function ExportSettings()
    local p = getDB()
    if not p then print("|cffff0000ShammyTime:|r No profile loaded.") return end
    print("")
    print("|cffffff00═══════════════════════════════════════|r")
    print("|cffffff00  ShammyTime Settings Export|r")
    print("|cffffff00═══════════════════════════════════════|r")
    print("")
    for _, ln in ipairs(BuildFullExportLines(true)) do
        print(ln)
    end
    print("")
    print("|cffffff00═══════════════════════════════════════|r")
    print("|cff00ff00Copy above and paste to developer.|r")
    print("")
end

-- Expose for /st print
_G.ShammyTime.ExportSettings = ExportSettings

--------------------------------------------------------------------------------
-- Export All to Clipboard (via popup EditBox) - 100% settings coverage
--------------------------------------------------------------------------------
local copyFrame = nil

local function ShowCopyPopup(title, text)
    if not copyFrame then
        copyFrame = CreateFrame("Frame", "ShammyTimeCopyFrame", UIParent, "BackdropTemplate")
        copyFrame:SetSize(450, 350)
        copyFrame:SetPoint("CENTER")
        copyFrame:SetFrameStrata("DIALOG")
        copyFrame:SetMovable(true)
        copyFrame:EnableMouse(true)
        copyFrame:RegisterForDrag("LeftButton")
        copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
        copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
        copyFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
        copyFrame:SetBackdropColor(0, 0, 0, 1)

        copyFrame.title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        copyFrame.title:SetPoint("TOP", 0, -20)

        local scrollFrame = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 20, -50)
        scrollFrame:SetPoint("BOTTOMRIGHT", -35, 50)

        copyFrame.editBox = CreateFrame("EditBox", nil, scrollFrame)
        copyFrame.editBox:SetMultiLine(true)
        copyFrame.editBox:SetFontObject(GameFontHighlightSmall)
        copyFrame.editBox:SetWidth(390)
        copyFrame.editBox:SetAutoFocus(false)
        copyFrame.editBox:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
        scrollFrame:SetScrollChild(copyFrame.editBox)

        local closeBtn = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)
        closeBtn:SetScript("OnClick", function() copyFrame:Hide() end)

        local selectAllBtn = CreateFrame("Button", nil, copyFrame, "UIPanelButtonTemplate")
        selectAllBtn:SetSize(100, 22)
        selectAllBtn:SetPoint("BOTTOM", 0, 15)
        selectAllBtn:SetText("Select All")
        selectAllBtn:SetScript("OnClick", function()
            copyFrame.editBox:SetFocus()
            copyFrame.editBox:HighlightText()
        end)
    end
    copyFrame.title:SetText(title)
    copyFrame.editBox:SetText(text)
    copyFrame:Show()
    copyFrame.editBox:SetFocus()
    copyFrame.editBox:HighlightText()
end

local STAGGER_GUIDE_URL = "https://www.enhanceshaman.com/pages/guide/sync_stagger"
local STAGGER_RESYNC_MACRO = table.concat({
    "/cleartarget",
    "/targetlasttarget",
    "/startattack",
    "/st resync",
}, "\n")

local function CopyStaggerGuideLink()
    ShowCopyPopup("ShammyTime - Sync/Stagger Guide Link", STAGGER_GUIDE_URL)
end

local function CopyStaggerMacro()
    ShowCopyPopup("ShammyTime - ShammyTime Custom Resync Macro", STAGGER_RESYNC_MACRO)
end

local function ExportAllToClipboard()
    local header = { "ShammyTime - All Settings (100% coverage)", "Copy everything below; paste to developer or backup.", "" }
    local body = BuildFullExportLines(false)
    local full = {}
    for _, ln in ipairs(header) do table.insert(full, ln) end
    for _, ln in ipairs(body) do table.insert(full, ln) end
    ShowCopyPopup("ShammyTime - Export All to Clipboard", table.concat(full, "\n"))
end

_G.ShammyTime.CopyTextSettings = ExportAllToClipboard

--------------------------------------------------------------------------------
-- Module Options Builder (simplified)
--------------------------------------------------------------------------------
local function CreateModuleOptions(moduleName, displayName, extraArgs, noFade)
    local scaleMin, scaleMax = getScaleDisplayBounds(moduleName)
    local opts = {
        type = "group",
        name = displayName,
        arg = { module = moduleName },
        args = {
            enabled = {
                type = "toggle",
                name = "Enable",
                desc = "Show or hide this element.",
                order = 1,
                width = "full",
                arg = { module = moduleName },
                get = function(info) return getModuleOption(info, "enabled") end,
                set = function(info, v) setModuleOption(info, v, "enabled") end,
            },
            scale = {
                type = "range",
                name = "Scale",
                min = scaleMin,
                max = scaleMax,
                step = 0.05,
                order = 2,
                arg = { module = moduleName },
                get = function(info) return getModuleOption(info, "scale") end,
                set = function(info, v) setModuleOption(info, v, "scale") end,
            },
            alpha = {
                type = "range",
                name = "Alpha",
                min = 0, max = 1, step = 0.05,
                order = 3,
                arg = { module = moduleName },
                get = function(info) return getModuleOption(info, "alpha") end,
                set = function(info, v) setModuleOption(info, v, "alpha") end,
            },
            fadeHeader = {
                type = "header",
                name = "Fade Settings",
                order = 10,
            },
            fadeEnabled = {
                type = "toggle",
                name = "Enable Fade",
                desc = "Fade this element when conditions are met.",
                order = 11,
                arg = { module = moduleName },
                get = function(info) return getModuleOption(info, "fadeEnabled") end,
                set = function(info, v) setModuleOption(info, v, "fadeEnabled") end,
            },
            inactiveAlpha = {
                type = "range",
                name = "Faded Alpha",
                desc = "Alpha when faded.",
                min = 0, max = 1, step = 0.05,
                order = 12,
                arg = { module = moduleName },
                get = function(info) return getModuleOption(info, "inactiveAlpha") end,
                set = function(info, v) setModuleOption(info, v, "inactiveAlpha") end,
            },
            outOfCombat = {
                type = "toggle",
                name = "Out of Combat",
                order = 13,
                arg = { module = moduleName },
                get = function(info) return getModuleOption(info, "outOfCombat") end,
                set = function(info, v) setModuleOption(info, v, "outOfCombat") end,
            },
            noTarget = {
                type = "toggle",
                name = "No Target",
                order = 14,
                arg = { module = moduleName },
                get = function(info) return getModuleOption(info, "noTarget") end,
                set = function(info, v) setModuleOption(info, v, "noTarget") end,
            },
            fadeInOnTarget = {
                type = "toggle",
                name = "Fade In When Targeting Enemy",
                desc = "When enabled, this element fades in slowly when you select an enemy target. When disabled, it appears instantly.",
                order = 14.5,
                arg = { module = moduleName },
                get = function(info) return getModuleOption(info, "fadeInOnTarget") end,
                set = function(info, v) setModuleOption(info, v, "fadeInOnTarget") end,
                hidden = function()
                    return moduleName ~= "windfuryBubbles"
                        and moduleName ~= "shamanisticFocus"
                        and moduleName ~= "pressureVisual"
                end,
            },
            inactiveBuff = {
                type = "toggle",
                name = "No Active Effect",
                order = 15,
                arg = { module = moduleName },
                get = function(info) return getModuleOption(info, "inactiveBuff") end,
                set = function(info, v) setModuleOption(info, v, "inactiveBuff") end,
            },
            noTotemsPlaced = {
                type = "toggle",
                name = "No Totems Placed",
                order = 16,
                arg = { module = moduleName },
                get = function(info) return getModuleOption(info, "noTotemsPlaced") end,
                set = function(info, v) setModuleOption(info, v, "noTotemsPlaced") end,
                hidden = function() return moduleName ~= "totemBar" end,
            },
            actionsHeader = {
                type = "header",
                name = "",
                order = 50,
            },
            resetModule = {
                type = "execute",
                name = "Reset",
                desc = "Reset this module to defaults.",
                order = 52,
                confirm = true,
                confirmText = "Reset " .. displayName .. " to defaults?",
                func = function()
                    local st = _G.ShammyTime
                    if st and st.ResetModule then st:ResetModule(moduleName) end
                end,
            },
        },
    }
    -- Strip fade options when they don't apply (e.g. WF Totem Damage feed)
    if noFade then
        opts.args.fadeHeader = nil
        opts.args.fadeEnabled = nil
        opts.args.inactiveAlpha = nil
        opts.args.outOfCombat = nil
        opts.args.noTarget = nil
        opts.args.fadeInOnTarget = nil
        opts.args.inactiveBuff = nil
        opts.args.noTotemsPlaced = nil
    end
    -- Merge extra args if provided
    if extraArgs then
        for k, v in pairs(extraArgs) do
            opts.args[k] = v
        end
    end
    return opts
end

--------------------------------------------------------------------------------
-- Developer Section: Per-satellite text position options
--------------------------------------------------------------------------------
local function CreateSatelliteGroup(bubbleName, displayName, order)
    return {
        type = "group",
        name = displayName,
        inline = true,
        order = order,
        args = {
            labelX = {
                type = "range",
                name = "Label X",
                min = -50, max = 50, step = 1,
                order = 1,
                get = function() return getSatelliteOverride(bubbleName, "labelX", 0) end,
                set = function(_, v) setSatelliteOverride(bubbleName, "labelX", v) end,
            },
            labelY = {
                type = "range",
                name = "Label Y",
                min = -50, max = 50, step = 1,
                order = 2,
                get = function() return getSatelliteOverride(bubbleName, "labelY", 0) end,
                set = function(_, v) setSatelliteOverride(bubbleName, "labelY", v) end,
            },
            valueX = {
                type = "range",
                name = "Value X",
                min = -50, max = 50, step = 1,
                order = 3,
                get = function() return getSatelliteOverride(bubbleName, "valueX", 0) end,
                set = function(_, v) setSatelliteOverride(bubbleName, "valueX", v) end,
            },
            valueY = {
                type = "range",
                name = "Value Y",
                min = -50, max = 50, step = 1,
                order = 4,
                get = function() return getSatelliteOverride(bubbleName, "valueY", 0) end,
                set = function(_, v) setSatelliteOverride(bubbleName, "valueY", v) end,
            },
            labelSize = {
                type = "range",
                name = "Label Font",
                min = 4, max = 24, step = 1,
                order = 5,
                get = function() return getSatelliteOverride(bubbleName, "labelSize", 0) end,
                set = function(_, v) setSatelliteOverride(bubbleName, "labelSize", v) end,
            },
            valueSize = {
                type = "range",
                name = "Value Font",
                min = 4, max = 24, step = 1,
                order = 6,
                get = function() return getSatelliteOverride(bubbleName, "valueSize", 0) end,
                set = function(_, v) setSatelliteOverride(bubbleName, "valueSize", v) end,
            },
            resetBubble = {
                type = "execute",
                name = "Reset this bubble",
                desc = "Clear all overrides for this bubble so it uses global position/font (no per-bubble offset).",
                order = 10,
                func = function()
                    resetSatelliteOverrides(bubbleName)
                end,
            },
        },
    }
end

--------------------------------------------------------------------------------
-- Main Options Setup
--------------------------------------------------------------------------------
function ShammyTime:SetupOptions()
    local options = {
        type = "group",
        name = "ShammyTime",
        args = {
            -----------------------------------------------------------------
            -- WELCOME (first page when opening settings)
            -----------------------------------------------------------------
            welcome = {
                type = "group",
                name = "Welcome",
                order = 0,
                args = {
                    authorLine = {
                        type = "description",
                        name = "|cffaaaaaaAuthor: Joachim Eriksson (05.02.2026)|r\n",
                        order = 0,
                        width = "full",
                    },
                    reloadBox = {
                        type = "group",
                        inline = true,
                        name = "|cffffcc00Note|r",
                        order = 1,
                        args = {
                            reloadNotice = {
                                type = "description",
                                name = "|cff00ff00Settings apply in real time.|r No |cffffcc00/reload|r needed.\n",
                                order = 1,
                                width = "full",
                            },
                        },
                    },
                    welcomeBox = {
                        type = "group",
                        inline = true,
                        name = "Welcome to ShammyTime",
                        order = 2,
                        args = {
                            welcomeDesc = {
                                type = "description",
                                name = "ShammyTime is a shaman addon that shows Windfury procs (center ring and stat bubbles), totem timers, weapon imbues, Shamanistic Focus, and shield charges. Use the General and Modules tabs to lock frames, scale elements, and configure each part.\n",
                                order = 1,
                                width = "full",
                            },
                        },
                    },
                    aboutBox = {
                        type = "group",
                        inline = true,
                        name = "About",
                        order = 3,
                        args = {
                            aboutDesc = {
                                type = "description",
                                name = "This addon was made to make Windfury feel even more exciting and to give you a clear picture of how well it's performing. You get instant feedback on proc damage (min, max, average, crits) so you can see the numbers that matter, have a bit of fun with it, and compare weapons and setups at a glance.\n",
                                order = 1,
                                width = "full",
                            },
                        },
                    },
                    metricsBox = {
                        type = "group",
                        inline = true,
                        name = "How the numbers are calculated",
                        order = 4,
                        args = {
                            metricsDesc = {
                                type = "description",
                                name = "|cffccccccMIN|r - Lowest total damage from one Windfury proc (1 or 2 hits combined).\n|cffccccccMAX|r - Highest total damage from one proc.\n|cffccccccAVG|r - Total Windfury damage / number of procs.\n|cffccccccPROCS|r - How many Windfury procs so far this session.\n|cffccccccPROC%|r - Procs / white swings (how often Windfury procced).\n|cffccccccCRIT%|r - Windfury hits that were crits / all Windfury hits.\n",
                                order = 1,
                                width = "full",
                            },
                        },
                    },
                    tipBox = {
                        type = "group",
                        inline = true,
                        name = "Tip",
                        order = 5,
                        args = {
                            resetTip = {
                                type = "description",
                                name = "Right-click the Windfury circle to reset all statistics (MIN, MAX, PROCS, etc. start over).\n",
                                order = 1,
                                width = "full",
                            },
                        },
                    },
                    fadeBox = {
                        type = "group",
                        inline = true,
                        name = "Fading elements",
                        order = 6,
                        args = {
                            fadeDesc = {
                                type = "description",
                                name = "Each module (Windfury Bubbles, Totem Bar, Shamanistic Focus, etc.) has a |cffccccccFade|r section under Modules. Turn on |cffccccccEnable Fade|r, set |cffccccccFaded Alpha|r (how see-through when faded), then pick when to fade:\n\n- |cffccccccOut of Combat|r - fade when you're not in combat.\n- |cffccccccNo Target|r - fade when you have no target.\n- |cffccccccNo Active Effect|r - fade when that module has no relevant active state (for example no recent proc, buff, or pressure event).\n- |cffccccccNo Totems Placed|r - totem bar fades when you have no totems down.\n- |cffccccccFade In When Targeting Enemy|r - fade in slowly when you select an enemy instead of appearing instantly.\n\nIf any condition you enable is true, that element fades to the alpha you set.\n",
                                order = 1,
                                width = "full",
                            },
                        },
                    },
                },
            },
            -----------------------------------------------------------------
            -- GENERAL
            -----------------------------------------------------------------
            general = {
                type = "group",
                name = "General",
                order = 1,
                args = {
                    lockFrames = {
                        type = "toggle",
                        name = "Lock Frames",
                        desc = "Prevent dragging frames. Unlock to reposition.",
                        order = 1,
                        width = "full",
                        get = function()
                            local g = getGlobal()
                            return g and g.locked
                        end,
                        set = function(_, v)
                            local g = getGlobal()
                            local p = getDB()
                            if g then g.locked = v end
                            if p then p.locked = v end
                            local addon = LibStub("AceAddon-3.0"):GetAddon("ShammyTime", true)
                            if addon and addon.ApplyAllConfigs then addon:ApplyAllConfigs() end
                        end,
                    },
                    masterScale = {
                        type = "range",
                        name = "Master Scale",
                        desc = "Scale all elements at once.",
                        min = 0.5, max = 2, step = 0.05,
                        order = 2,
                        get = function()
                            local g = getGlobal()
                            return g and g.masterScale or 1
                        end,
                        set = function(_, v)
                            local g = getGlobal()
                            if g then g.masterScale = v end
                            local addon = LibStub("AceAddon-3.0"):GetAddon("ShammyTime", true)
                            if addon and addon.ApplyAllConfigs then addon:ApplyAllConfigs() end
                        end,
                    },
                    masterAlpha = {
                        type = "range",
                        name = "Master Alpha",
                        desc = "Overall transparency for all elements.",
                        min = 0, max = 1, step = 0.05,
                        order = 3,
                        get = function()
                            local g = getGlobal()
                            return g and g.masterAlpha or 1
                        end,
                        set = function(_, v)
                            local g = getGlobal()
                            if g then g.masterAlpha = v end
                            local addon = LibStub("AceAddon-3.0"):GetAddon("ShammyTime", true)
                            if addon and addon.ApplyAllConfigs then addon:ApplyAllConfigs() end
                        end,
                    },
                    uiErrorTextEnabled = {
                        type = "toggle",
                        name = "Show Blizzard Error Text",
                        desc = "Show/hide red UI error text (for example: Not enough mana).",
                        order = 3.1,
                        width = "full",
                        get = function()
                            return getFlatDB("uiErrorTextEnabled", false)
                        end,
                        set = function(_, v)
                            setFlatDB("uiErrorTextEnabled", v)
                        end,
                    },
                    presetsHeader = {
                        type = "header",
                        name = "Presets",
                        order = 4,
                    },
                    presetsDesc = {
                        type = "description",
                        name = "Quickly configure fade behaviour for all modules at once. This only changes fade settings - scale, position, and other options stay the same.\n",
                        order = 4.1,
                    },
                    presetAlwaysVisible = {
                        type = "execute",
                        name = "Always Visible",
                        desc = "Disable all fade: every module stays fully visible at all times.",
                        order = 4.2,
                        confirm = true,
                        confirmText = "Apply the 'Always Visible' preset? This will disable all fade settings on every module.",
                        func = function()
                            local st = _G.ShammyTime
                            if st and st.ApplyPresetAlwaysVisible then st:ApplyPresetAlwaysVisible() end
                        end,
                    },
                    presetSmartFade = {
                        type = "execute",
                        name = "Smart Fade",
                        desc = "Context-aware fading: modules disappear when not relevant (e.g. no buff active, no totems placed, out of combat).",
                        order = 4.3,
                        confirm = true,
                        confirmText = "Apply the 'Smart Fade' preset? This will enable recommended fade settings on every module.",
                        func = function()
                            local st = _G.ShammyTime
                            if st and st.ApplyPresetSmartFade then st:ApplyPresetSmartFade() end
                        end,
                    },
                    profile = {
                        type = "select",
                        name = "Profile",
                        desc = "Switch settings profile.",
                        order = 5,
                        get = function()
                            local st = _G.ShammyTime
                            return st and st.db and st.db:GetCurrentProfile() or "Default"
                        end,
                        set = function(_, key)
                            local st = _G.ShammyTime
                            if st and st.db and st.db.SetProfile then
                                st.db:SetProfile(key)
                            end
                        end,
                        values = function()
                            local t = {}
                            local st = _G.ShammyTime
                            if st and st.db and st.db.GetProfiles then
                                for _, name in pairs(st.db:GetProfiles()) do
                                    t[name] = name
                                end
                            end
                            if not next(t) then t["Default"] = "Default" end
                            return t
                        end,
                    },
                    testHeader = {
                        type = "header",
                        name = "Testing",
                        order = 10,
                    },
                    playDemo = {
                        type = "execute",
                        name = "Play Demo",
                        desc = "Start looping demo of all modules.",
                        order = 11,
                        func = function()
                            local st = _G.ShammyTime
                            if st then
                                -- Enable loop mode and start demo
                                local g = getGlobal()
                                if g then g.demoMode = true end
                                if st.PlayDemo then st:PlayDemo() end
                            end
                        end,
                    },
                    stopDemo = {
                        type = "execute",
                        name = "Stop Demo",
                        desc = "Stop the demo immediately.",
                        order = 12,
                        func = function()
                            local st = _G.ShammyTime
                            if st and st.StopDemo then
                                st:StopDemo()
                            end
                        end,
                    },
                    resetHeader = {
                        type = "header",
                        name = "",
                        order = 20,
                    },
                    resetAll = {
                        type = "execute",
                        name = "Reset All to Defaults",
                        order = 21,
                        confirm = true,
                        confirmText = "Reset ALL ShammyTime settings to defaults?",
                        func = function()
                            local st = _G.ShammyTime
                            if st and st.ResetAllToDefaults then st:ResetAllToDefaults() end
                        end,
                    },
                },
            },
            -----------------------------------------------------------------
            -- MODULES
            -----------------------------------------------------------------
            modules = {
                type = "group",
                name = "Modules",
                order = 2,
                childGroups = "tab",
                args = {
                    windfuryBubbles = CreateModuleOptions("windfuryBubbles", "Windfury Bubbles", {
                        moduleDesc = {
                            type = "group",
                            inline = true,
                            name = "Info",
                            order = 0,
                            args = {
                                desc = {
                                    type = "description",
                                    name = "Shows when you proc Windfury: a center ring plus bubbles with your proc stats (min, max, avg, proc%, crit%) so you can see how well Windfury is performing.\n",
                                    order = 1,
                                    width = "full",
                                },
                            },
                        },
                        alwaysShowNumbers = {
                            type = "toggle",
                            name = "Always Show Numbers",
                            desc = "Show statistics numbers even when not hovering (otherwise fade until mouse-over).",
                            order = 4,
                            get = function() return getFlatDB("wfAlwaysShowNumbers", false) end,
                            set = function(_, v) setFlatDB("wfAlwaysShowNumbers", v) end,
                        },
                        textHeader = {
                            type = "header",
                            name = "Text Sizes",
                            order = 4.1,
                        },
                        fontCircleTitle = {
                            type = "range",
                            name = "Center Title Font",
                            min = 6, max = 32, step = 1,
                            order = 4.2,
                            get = function() return getFlatDB("fontCircleTitle", 20) end,
                            set = function(_, v)
                                setFlatDB("fontCircleTitle", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyCenterRingFontSizes then st.ApplyCenterRingFontSizes() end
                            end,
                        },
                        fontCircleTotal = {
                            type = "range",
                            name = "Center Total Font",
                            min = 6, max = 32, step = 1,
                            order = 4.3,
                            get = function() return getFlatDB("fontCircleTotal", 14) end,
                            set = function(_, v)
                                setFlatDB("fontCircleTotal", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyCenterRingFontSizes then st.ApplyCenterRingFontSizes() end
                            end,
                        },
                        fontCircleCritical = {
                            type = "range",
                            name = "Center Critical Font",
                            min = 6, max = 32, step = 1,
                            order = 4.4,
                            get = function() return getFlatDB("fontCircleCritical", 20) end,
                            set = function(_, v)
                                setFlatDB("fontCircleCritical", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyCenterRingFontSizes then st.ApplyCenterRingFontSizes() end
                            end,
                        },
                        fontSatelliteLabel = {
                            type = "range",
                            name = "Satellite Label Font",
                            min = 4, max = 24, step = 1,
                            order = 4.5,
                            get = function() return getFlatDB("fontSatelliteLabel", 8) end,
                            set = function(_, v)
                                setFlatDB("fontSatelliteLabel", v)
                                local st = _G.ShammyTime
                                if st and st.ApplySatelliteFontSizes then st.ApplySatelliteFontSizes() end
                            end,
                        },
                        fontSatelliteValue = {
                            type = "range",
                            name = "Satellite Value Font",
                            min = 4, max = 24, step = 1,
                            order = 4.6,
                            get = function() return getFlatDB("fontSatelliteValue", 13) end,
                            set = function(_, v)
                                setFlatDB("fontSatelliteValue", v)
                                local st = _G.ShammyTime
                                if st and st.ApplySatelliteFontSizes then st.ApplySatelliteFontSizes() end
                            end,
                        },
                    }),
                    totemBar = CreateModuleOptions("totemBar", "Totem Bar", {
                        moduleDesc = {
                            type = "group",
                            inline = true,
                            name = "Info",
                            order = 0,
                            args = {
                                desc = {
                                    type = "description",
                                    name = "Shows your four totem slots with timers and range: totems fade when you go out of range. Range fade does not work for totems that don't appear as a buff (e.g. in some instances).\n",
                                    order = 1,
                                    width = "full",
                                },
                            },
                        },
                        textHeader = {
                            type = "header",
                            name = "Text",
                            order = 4.1,
                        },
                        fontTotemTimer = {
                            type = "range",
                            name = "Text Size",
                            min = 4, max = 20, step = 1,
                            order = 4.2,
                            get = function() return getFlatDB("fontTotemTimer", 10) end,
                            set = function(_, v)
                                setFlatDB("fontTotemTimer", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyTotemBarFontSize then st.ApplyTotemBarFontSize() end
                            end,
                        },
                        totemModTextX = {
                            type = "range",
                            name = "Text X",
                            desc = "Horizontal offset for totem timer text (positive = right).",
                            min = -100, max = 100, step = 1,
                            order = 4.3,
                            get = function()
                                local p = getDB()
                                if p and p.totemLayout and p.totemLayout.timerOffsetX ~= nil then
                                    return p.totemLayout.timerOffsetX
                                end
                                return 0
                            end,
                            set = function(_, v)
                                local p = getDB()
                                if p then
                                    p.totemLayout = p.totemLayout or {}
                                    p.totemLayout.timerOffsetX = v
                                end
                                local st = _G.ShammyTime
                                if st and st.ApplyTotemBarLayout then st.ApplyTotemBarLayout() end
                            end,
                        },
                        totemModTextY = {
                            type = "range",
                            name = "Text Y",
                            desc = "Vertical offset for totem timer text (negative = down).",
                            min = -100, max = 100, step = 1,
                            order = 4.4,
                            get = function()
                                local p = getDB()
                                if p and p.totemLayout and p.totemLayout.timerOffsetY ~= nil then
                                    return p.totemLayout.timerOffsetY
                                end
                                return -2
                            end,
                            set = function(_, v)
                                local p = getDB()
                                if p then
                                    p.totemLayout = p.totemLayout or {}
                                    p.totemLayout.timerOffsetY = v
                                end
                                local st = _G.ShammyTime
                                if st and st.ApplyTotemBarLayout then st.ApplyTotemBarLayout() end
                            end,
                        },
                        noTotemsFadeDelay = {
                            type = "range",
                            name = "No Totems Fade Delay",
                            desc = "Seconds to wait before fading when no totems are placed.",
                            min = 1, max = 30, step = 1,
                            order = 17,
                            get = function() return getFlatDB("wfNoTotemsFadeDelay", 5) end,
                            set = function(_, v) setFlatDB("wfNoTotemsFadeDelay", v) end,
                        },
                    }),
                    shamanisticFocus = CreateModuleOptions("shamanisticFocus", "Shamanistic Focus", {
                        moduleDesc = {
                            type = "group",
                            inline = true,
                            name = "Info",
                            order = 0,
                            args = {
                                desc = {
                                    type = "description",
                                    name = "Shows when your Shamanistic Focus buff is active (after a crit), so you know when your next spell costs less mana.\n",
                                    order = 1,
                                    width = "full",
                                },
                            },
                        },
                    }),
                    weaponImbueBar = CreateModuleOptions("weaponImbueBar", "Weapon Imbue Bar", {
                        moduleDesc = {
                            type = "group",
                            inline = true,
                            name = "Info",
                            order = 0,
                            args = {
                                desc = {
                                    type = "description",
                                    name = "Shows your weapon imbues (e.g. Windfury, Flametongue) and their remaining time so you can refresh them before they drop.\n",
                                    order = 1,
                                    width = "full",
                                },
                            },
                        },
                        textHeader = {
                            type = "header",
                            name = "Text",
                            order = 4.1,
                        },
                        fontImbueTimer = {
                            type = "range",
                            name = "Text Size",
                            min = 6, max = 64, step = 1,
                            order = 4.2,
                            get = function() return getFlatDB("fontImbueTimer", 16) end,
                            set = function(_, v)
                                setFlatDB("fontImbueTimer", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyImbueBarFontSize then st.ApplyImbueBarFontSize() end
                            end,
                        },
                        imbueModTextX = {
                            type = "range",
                            name = "Text X",
                            desc = "Horizontal offset for imbue timer text (positive = right).",
                            min = -100, max = 100, step = 1,
                            order = 4.3,
                            get = function() return getFlatDB("imbueTextX", 0) end,
                            set = function(_, v)
                                setFlatDB("imbueTextX", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyImbueBarLayout then st.ApplyImbueBarLayout() end
                            end,
                        },
                        imbueModTextY = {
                            type = "range",
                            name = "Text Y",
                            desc = "Vertical offset for imbue timer text (negative = down).",
                            min = -100, max = 100, step = 1,
                            order = 4.4,
                            get = function() return getFlatDB("imbueTextY", -20) end,
                            set = function(_, v)
                                setFlatDB("imbueTextY", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyImbueBarLayout then st.ApplyImbueBarLayout() end
                            end,
                        },
                        imbueFadeThreshold = {
                            type = "range",
                            name = "Imbue Fade Threshold",
                            desc = "Show imbue bar when any imbue has this many seconds or less remaining.",
                            min = 30, max = 600, step = 10,
                            order = 17,
                            get = function() return getFlatDB("wfImbueFadeThresholdSec", 120) end,
                            set = function(_, v) setFlatDB("wfImbueFadeThresholdSec", v) end,
                        },
                    }),
                    shieldIndicator = CreateModuleOptions("shieldIndicator", "Shield Indicator", {
                        moduleDesc = {
                            type = "group",
                            inline = true,
                            name = "Info",
                            order = 0,
                            args = {
                                desc = {
                                    type = "description",
                                    name = "Shows when Lightning Shield or Water Shield is active and how many charges you have left.\n",
                                    order = 1,
                                    width = "full",
                                },
                            },
                        },
                        hideWhenActive = {
                            type = "toggle",
                            name = "Hide When Active",
                            desc = "Hide the shield indicator when Lightning Shield or Water Shield is active with at least 1 charge. The indicator will appear when the shield drops or expires, serving as a reminder to recast.",
                            order = 16,
                            arg = { module = "shieldIndicator" },
                            get = function(info) return getModuleOption(info, "hideWhenActive") end,
                            set = function(info, v) setModuleOption(info, v, "hideWhenActive") end,
                        },
                        textHeader = {
                            type = "header",
                            name = "Text Sizes",
                            order = 4.1,
                        },
                        fontShieldCount = {
                            type = "range",
                            name = "Count Font",
                            desc = "Shield count text size.",
                            min = 6, max = 200, step = 1,
                            order = 4.2,
                            get = function() return getFlatDB("fontShieldCount", 86) end,
                            set = function(_, v)
                                setFlatDB("fontShieldCount", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyShieldCountSettings then st.ApplyShieldCountSettings() end
                            end,
                        },
                    }),
                    wfImpact = CreateModuleOptions("wfImpact", "WF Totem Damage", {
                        moduleDesc = {
                            type = "group",
                            inline = true,
                            name = "",
                            order = 0,
                            args = {
                                desc = {
                                    type = "description",
                                    name = "Ever wondered how much your Windfury Totem actually contributes to your party's damage? " ..
                                           "This shows a live scrolling damage feed whenever you or your party members land bonus hits from " ..
                                           "your totem - right above it, so you can feel the impact in real time.\n\n" ..
                                           "When combat ends, a total is shown so you can see how much extra damage your totem brought to the fight.\n\n" ..
                                           "|cffaaaaaa" .. "Damage values are estimated based on combat log events." .. "|r\n",
                                    order = 1,
                                    width = "full",
                                },
                            },
                        },
                        -- Position
                        posHeader = {
                            type = "header",
                            name = "Position Offset",
                            order = 4.0,
                        },
                        posDesc = {
                            type = "description",
                            name = "Adjusts where the damage text appears relative to your Windfury Totem slot on the totem bar.",
                            order = 4.01,
                        },
                        wfImpactOffsetX = {
                            type = "range",
                            name = "X Offset",
                            desc = "Horizontal offset from the WF totem slot.",
                            min = -200, max = 200, step = 1,
                            order = 4.1,
                            get = function() return getFlatDB("wfImpactOffsetX", 0) end,
                            set = function(_, v)
                                setFlatDB("wfImpactOffsetX", v)
                                local api = _G.ShammyTime_WFImpact
                                if api and api.ApplyPosition then api.ApplyPosition() end
                            end,
                        },
                        wfImpactOffsetY = {
                            type = "range",
                            name = "Y Offset",
                            desc = "Vertical offset above the WF totem slot.",
                            min = -200, max = 200, step = 1,
                            order = 4.2,
                            get = function() return getFlatDB("wfImpactOffsetY", -26) end,
                            set = function(_, v)
                                setFlatDB("wfImpactOffsetY", v)
                                local api = _G.ShammyTime_WFImpact
                                if api and api.ApplyPosition then api.ApplyPosition() end
                            end,
                        },
                        -- Text Sizes
                        textHeader = {
                            type = "header",
                            name = "Text Sizes",
                            order = 5.0,
                        },
                        wfImpactFontScroll = {
                            type = "range",
                            name = "Scrolling Text Font",
                            desc = "Font size for the scrolling damage lines.",
                            min = 6, max = 32, step = 1,
                            order = 5.1,
                            get = function() return getFlatDB("wfImpactFontScroll", 15) end,
                            set = function(_, v)
                                setFlatDB("wfImpactFontScroll", v)
                                local api = _G.ShammyTime_WFImpact
                                if api and api.UpdateScrollPool then api.UpdateScrollPool() end
                            end,
                        },
                        wfImpactFontTotal = {
                            type = "range",
                            name = "Total Popup Font",
                            desc = "Font size for the end-of-combat total popup.",
                            min = 6, max = 32, step = 1,
                            order = 5.2,
                            get = function() return getFlatDB("wfImpactFontTotal", 16) end,
                            set = function(_, v)
                                setFlatDB("wfImpactFontTotal", v)
                                local api = _G.ShammyTime_WFImpact
                                if api and api.UpdateScrollPool then api.UpdateScrollPool() end
                            end,
                        },
                        -- Animation / Scroll Speed
                        animHeader = {
                            type = "header",
                            name = "Animation",
                            order = 6.0,
                        },
                        wfImpactScrollDuration = {
                            type = "range",
                            name = "Scroll Duration",
                            desc = "How long each damage line is visible (seconds). Lower = faster scroll.",
                            min = 0.3, max = 3.0, step = 0.1,
                            order = 6.1,
                            get = function() return getFlatDB("wfImpactScrollDuration", 2.0) end,
                            set = function(_, v)
                                setFlatDB("wfImpactScrollDuration", v)
                                local api = _G.ShammyTime_WFImpact
                                if api and api.UpdateScrollPool then api.UpdateScrollPool() end
                            end,
                        },
                        wfImpactScrollDistance = {
                            type = "range",
                            name = "Scroll Distance",
                            desc = "How far each damage line travels upward (pixels).",
                            min = 20, max = 150, step = 5,
                            order = 6.2,
                            get = function() return getFlatDB("wfImpactScrollDistance", 115) end,
                            set = function(_, v)
                                setFlatDB("wfImpactScrollDistance", v)
                                local api = _G.ShammyTime_WFImpact
                                if api and api.UpdateScrollPool then api.UpdateScrollPool() end
                            end,
                        },
                        -- Test button
                        testHeader = {
                            type = "header",
                            name = "Preview",
                            order = 7.0,
                        },
                        testButton = {
                            type = "execute",
                            name = "Preview Damage Feed",
                            desc = "Shows a preview with fake damage numbers so you can see how it looks and adjust your settings.",
                            order = 7.1,
                            func = function()
                                local api = _G.ShammyTime_WFImpact
                                if api and api.Simulate then api.Simulate() end
                            end,
                        },
                    }, true),  -- noFade: fade settings don't apply to the damage feed
                    pressureVisual = CreateModuleOptions("pressureVisual", "Pressure Visual", {
                        moduleDesc = {
                            type = "group",
                            inline = true,
                            name = "Info",
                            order = 0,
                            args = {
                                desc = {
                                    type = "description",
                                    name = "Pressure Visual tracks your outgoing damage momentum and shows it as a live pressure bar. " ..
                                           "The three popup slots below the bar summarize your recent high-impact spells so you can read your pressure spikes at a glance.\n\n" ..
                                           "How it works:\n" ..
                                           "- Sustained effects (like Flame Shock and Magma Totem) keep accumulating while active.\n" ..
                                           "- Burst events (like Stormstrike, Windfury bursts, and shocks) pop quickly and fade.\n" ..
                                           "- Slot assignment is dynamic from left to right, with temporary overlays when all slots are occupied.\n",
                                    order = 1,
                                    width = "full",
                                },
                            },
                        },
                        pressureTextHeader = {
                            type = "header",
                            name = "Popup Text",
                            order = 4.1,
                        },
                        pressurePopupTextSize = {
                            type = "range",
                            name = "Text Size",
                            desc = "Size of the popup damage numbers shown above pressure slot icons.",
                            min = 8, max = 72, step = 1,
                            order = 4.2,
                            get = function() return getFlatDB("pressurePopupTextSize", 49) end,
                            set = function(_, v) setFlatDB("pressurePopupTextSize", v) end,
                        },
                    }),
                    staggerBar = CreateModuleOptions("staggerBar", "Stagger Bar", {
                        moduleDesc = {
                            type = "group",
                            inline = true,
                            name = "Quick Guide",
                            order = 0,
                            args = {
                                infoTitle = {
                                    type = "description",
                                    name = "|cffffd700Sync and Stagger - Simple Setup|r\n" ..
                                           "Good staggering increases DPS because Flurry charges are more often spent on two white hits instead of one, and your stronger main-hand gets more valuable Windfury proc opportunities than off-hand.",
                                    order = 1,
                                    width = "full",
                                },
                                infoHowItWorks = {
                                    type = "description",
                                    name = "Goal:\n" ..
                                           "Gold = perfect stagger (MH first, OH lands within 0.5s).\n" ..
                                           "White = not perfect (OH-first, same-time, or drifting).\n\n" ..
                                           "When to press your macro:\n" ..
                                           "Only press while OH is in |cffffff0050%-60%|r.\n" ..
                                           "OH-first: press once.\n" ..
                                           "Same-time (0.00): press once.\n" ..
                                           "Drifting (MH first, gap too wide): press while OH stays in 50%-60%, then stop when it turns gold.\n\n" ..
                                           "If OH is below 50%, pressing does nothing.",
                                    order = 2,
                                    width = "full",
                                },
                                infoMacro = {
                                    type = "description",
                                    name = "|cffffd700Custom ShammyTime Macro (bind this):|r\n" ..
                                           "|cffffcc00/cleartarget|r\n" ..
                                           "|cffffcc00/targetlasttarget|r\n" ..
                                           "|cffffcc00/startattack|r\n" ..
                                           "|cff33ff33/st resync|r\n\n" ..
                                           "This macro is custom for this addon and makes stagger timing easier to learn with the bar.",
                                    order = 3,
                                    width = "full",
                                },
                                infoReference = {
                                    type = "description",
                                    name = "External guide (not my website):\n" ..
                                           STAGGER_GUIDE_URL .. "\n" ..
                                           "There are also useful YouTube videos covering sync/stagger.",
                                    order = 4,
                                    width = "full",
                                },
                                staggerGuideCopy = {
                                    type = "execute",
                                    name = "Copy Guide Link",
                                    desc = "Open a copy box with the guide URL.",
                                    order = 5,
                                    width = "full",
                                    func = CopyStaggerGuideLink,
                                },
                                staggerCopyMacro = {
                                    type = "execute",
                                    name = "Copy Custom ShammyTime Macro",
                                    desc = "Open a copy box with the custom ShammyTime resync macro.",
                                    order = 6,
                                    width = "full",
                                    func = CopyStaggerMacro,
                                },
                            },
                        },
                        settingsHeader = {
                            type = "header",
                            name = "Settings",
                            order = 0.9,
                        },
                        barHeader = {
                            type = "header",
                            name = "Bar Dimensions",
                            order = 4.0,
                        },
                        staggerBarWidth = {
                            type = "range",
                            name = "Bar Width",
                            desc = "Length of each swing bar in pixels.",
                            min = 50, max = 400, step = 5,
                            order = 4.1,
                            get = function() return getFlatDB("staggerBarWidth", 335) end,
                            set = function(_, v)
                                setFlatDB("staggerBarWidth", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyStaggerBarLayout then st.ApplyStaggerBarLayout() end
                            end,
                        },
                        staggerBarHeight = {
                            type = "range",
                            name = "Bar Height",
                            desc = "Thickness of each swing bar in pixels.",
                            min = 2, max = 20, step = 1,
                            order = 4.2,
                            get = function() return getFlatDB("staggerBarHeight", 15) end,
                            set = function(_, v)
                                setFlatDB("staggerBarHeight", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyStaggerBarLayout then st.ApplyStaggerBarLayout() end
                            end,
                        },
                        staggerBarGap = {
                            type = "range",
                            name = "Bar Gap",
                            desc = "Vertical space between MH and OH bars.",
                            min = 0, max = 20, step = 1,
                            order = 4.3,
                            get = function() return getFlatDB("staggerBarGap", 5) end,
                            set = function(_, v)
                                setFlatDB("staggerBarGap", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyStaggerBarLayout then st.ApplyStaggerBarLayout() end
                            end,
                        },
                        staggerSwingBarAlpha = {
                            type = "range",
                            name = "Bar Alpha",
                            desc = "Transparency of the MH/OH swing bars. Lower values let the background texture show through.",
                            min = 0, max = 1, step = 0.05,
                            order = 4.4,
                            get = function() return getFlatDB("staggerSwingBarAlpha", 0.8) end,
                            set = function(_, v)
                                setFlatDB("staggerSwingBarAlpha", v)
                            end,
                        },
                        deltaHeader = {
                            type = "header",
                            name = "Delta Text",
                            order = 5.0,
                        },
                        staggerDeltaFontSize = {
                            type = "range",
                            name = "Font Size",
                            desc = "Size of the stagger delta readout.",
                            min = 6, max = 48, step = 1,
                            order = 5.1,
                            get = function() return getFlatDB("staggerDeltaFontSize", 27) end,
                            set = function(_, v)
                                setFlatDB("staggerDeltaFontSize", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyStaggerBarLayout then st.ApplyStaggerBarLayout() end
                            end,
                        },
                        staggerDeltaX = {
                            type = "range",
                            name = "Text X Offset",
                            desc = "Horizontal offset for the delta text (positive = right).",
                            min = -100, max = 100, step = 1,
                            order = 5.2,
                            get = function() return getFlatDB("staggerDeltaX", 46) end,
                            set = function(_, v)
                                setFlatDB("staggerDeltaX", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyStaggerBarLayout then st.ApplyStaggerBarLayout() end
                            end,
                        },
                        staggerDeltaY = {
                            type = "range",
                            name = "Text Y Offset",
                            desc = "Vertical offset for the delta text (positive = up).",
                            min = -100, max = 100, step = 1,
                            order = 5.3,
                            get = function() return getFlatDB("staggerDeltaY", 12) end,
                            set = function(_, v)
                                setFlatDB("staggerDeltaY", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyStaggerBarLayout then st.ApplyStaggerBarLayout() end
                            end,
                        },
                        helperHeader = {
                            type = "header",
                            name = "Helper Text",
                            order = 5.5,
                        },
                        staggerHelperFontSize = {
                            type = "range",
                            name = "Font Size",
                            desc = "Size of the helper advice text.",
                            min = 6, max = 48, step = 1,
                            order = 5.6,
                            get = function() return getFlatDB("staggerHelperFontSize", 24) end,
                            set = function(_, v)
                                setFlatDB("staggerHelperFontSize", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyStaggerBarLayout then st.ApplyStaggerBarLayout() end
                            end,
                        },
                        staggerHelperX = {
                            type = "range",
                            name = "Helper X Offset",
                            desc = "Horizontal offset for the helper text (positive = right).",
                            min = -200, max = 200, step = 1,
                            order = 5.7,
                            get = function() return getFlatDB("staggerHelperX", 0) end,
                            set = function(_, v)
                                setFlatDB("staggerHelperX", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyStaggerBarLayout then st.ApplyStaggerBarLayout() end
                            end,
                        },
                        staggerHelperY = {
                            type = "range",
                            name = "Helper Y Offset",
                            desc = "Vertical offset for the helper text (positive = up).",
                            min = -100, max = 100, step = 1,
                            order = 5.8,
                            get = function() return getFlatDB("staggerHelperY", -10) end,
                            set = function(_, v)
                                setFlatDB("staggerHelperY", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyStaggerBarLayout then st.ApplyStaggerBarLayout() end
                            end,
                        },
                        actionCueHeader = {
                            type = "header",
                            name = "Resync Action Cue Settings",
                            order = 5.82,
                        },
                        staggerActionCueEnabled = {
                            type = "toggle",
                            name = "Enable Action Cue",
                            desc = "Show timing-aware resync prompts instead of the basic helper text.",
                            width = "full",
                            order = 5.84,
                            get = function() return getFlatDB("staggerActionCueEnabled", true) end,
                            set = function(_, v) setFlatDB("staggerActionCueEnabled", v) end,
                        },
                        staggerActionCueYellow = {
                            type = "toggle",
                            name = "Also Show for Drifting",
                            desc = "Show the resync action cue when MH is still first but the gap is too wide (>0.5s), not only when OH-first/same-time.",
                            width = "full",
                            order = 5.85,
                            disabled = function() return not getFlatDB("staggerActionCueEnabled", true) end,
                            get = function() return getFlatDB("staggerActionCueYellow", true) end,
                            set = function(_, v) setFlatDB("staggerActionCueYellow", v) end,
                        },
                        staggerCooldownDuration = {
                            type = "range",
                            name = "Observe Duration (seconds)",
                            desc = "After the 50%-60% tap window closes, how long to show \"Observe...\" before the next resync prompt. Also ends early after 2 swing events.",
                            min = 0.5, max = 5.0, step = 0.5,
                            order = 5.87,
                            disabled = function() return not getFlatDB("staggerActionCueEnabled", true) end,
                            get = function() return getFlatDB("staggerCooldownDuration", 2.0) end,
                            set = function(_, v) setFlatDB("staggerCooldownDuration", v) end,
                        },
                        hideHeader = {
                            type = "header",
                            name = "Visibility",
                            order = 6.0,
                        },
                        staggerBarAlwaysShow = {
                            type = "toggle",
                            name = "Always Show",
                            desc = "Keep the stagger bar visible at all times (disables smart hide). When off, the bar only appears while swinging.",
                            width = "full",
                            order = 6.05,
                            get = function() return getFlatDB("staggerBarAlwaysShow", false) end,
                            set = function(_, v)
                                setFlatDB("staggerBarAlwaysShow", v)
                                local st = _G.ShammyTime
                                if st and st.ApplyElementVisibility then st.ApplyElementVisibility() end
                                if st and st.UpdateAllElementsFadeState then st:UpdateAllElementsFadeState() end
                            end,
                        },
                        staggerHideDelay = {
                            type = "range",
                            name = "Hide After (seconds)",
                            desc = "Hide the stagger bars after this many seconds of no swings. Only used when 'Always Show' is off.",
                            min = 3, max = 60, step = 1,
                            order = 6.1,
                            disabled = function() return getFlatDB("staggerBarAlwaysShow", false) end,
                            get = function() return getFlatDB("staggerHideDelay", 15) end,
                            set = function(_, v) setFlatDB("staggerHideDelay", v) end,
                        },
                    }),
                    windfuryIcd = CreateModuleOptions("windfuryIcd", "Windfury ICD", {
                        moduleDesc = {
                            type = "group",
                            inline = true,
                            name = "Info",
                            order = 0,
                            args = {
                                desc = {
                                    type = "description",
                                    name = "Windfury has a 3-second internal cooldown after each proc. This indicator lamp shows whether Windfury can proc (bright) or is on cooldown (dark, with a countdown). Works with both the personal Windfury Weapon imbue and the Windfury Totem buff.\n\nThe indicator automatically hides when you have no Windfury on any weapon and no Windfury Totem is active.\n",
                                    order = 1,
                                    width = "full",
                                },
                            },
                        },
                    }),
                },
            },
            -----------------------------------------------------------------
            -- DEVELOPER (hidden unless devMode)
            -----------------------------------------------------------------
            developer = {
                type = "group",
                name = "Developer",
                order = 100,
                hidden = function()
                    local g = getGlobal()
                    return not (g and g.devMode)
                end,
                args = {
                    devNote = {
                        type = "description",
                        name = "|cffff8800Developer Mode|r: Fine-tune text positions and export settings. Use |cffffd700/st dev off|r to hide this section.\n",
                        order = 0,
                    },
                    exportSettings = {
                        type = "execute",
                        name = "Export Settings to Chat",
                        desc = "Print all current settings to chat (for copy/paste to developer).",
                        order = 1,
                        func = ExportSettings,
                    },
                    exportAllToClipboard = {
                        type = "execute",
                        name = "Export All to Clipboard",
                        desc = "Open a popup with ALL settings (elements, scales, positions, bubbles, offsets, modules, fade) for copy/paste.",
                        order = 2,
                        func = ExportAllToClipboard,
                    },
                    performanceHeader = {
                        type = "header",
                        name = "Performance Monitor",
                        order = 3,
                    },
                    performanceDesc = {
                        type = "description",
                        name = "Simple ShammyTime memory/CPU monitor.\nUse |cffffd700/st dev performance|r to toggle from chat.\nCPU numbers require: |cffffd700/console scriptProfile 1|r then |cffffd700/reload|r.",
                        order = 3.05,
                        width = "full",
                    },
                    performanceStatus = {
                        type = "description",
                        name = function()
                            local st = _G.ShammyTime
                            if st and st.GetPerformanceStatsText then
                                return "Current: " .. st:GetPerformanceStatsText(true)
                            end
                            return "Current: unavailable"
                        end,
                        order = 3.1,
                        width = "full",
                    },
                    performanceToggle = {
                        type = "execute",
                        name = "Toggle Monitor",
                        order = 3.2,
                        width = "half",
                        func = function()
                            local st = _G.ShammyTime
                            if not st or not st.TogglePerformanceMonitor then return end
                            local enabled = st:TogglePerformanceMonitor()
                            if enabled then
                                print("|cff00ff00ShammyTime:|r Performance monitor ON.")
                            else
                                print("|cff00ff00ShammyTime:|r Performance monitor OFF.")
                            end
                        end,
                    },
                    performanceRefresh = {
                        type = "execute",
                        name = "Refresh Sample",
                        order = 3.3,
                        width = "half",
                        func = function()
                            local st = _G.ShammyTime
                            if not st or not st.GetPerformanceStatsText then return end
                            if st.UpdatePerformanceMonitorText then st:UpdatePerformanceMonitorText(true) end
                            print("|cff00ff00ShammyTime:|r " .. st:GetPerformanceStatsText(true))
                        end,
                    },
                    ---------------------------------------------------------
                    -- Center Ring
                    ---------------------------------------------------------
                    centerHeader = {
                        type = "header",
                        name = "Center Ring",
                        order = 10,
                    },
                    centerSize = {
                        type = "range",
                        name = "Center Size",
                        desc = "Diameter of the center ring in pixels.",
                        min = 100, max = 400, step = 10,
                        order = 10.5,
                        get = function() return getFlatDB("wfCenterSize", 200) end,
                        set = function(_, v)
                            setFlatDB("wfCenterSize", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyCenterRingSize then st.ApplyCenterRingSize() end
                        end,
                    },
                    centerTextTitleY = {
                        type = "range",
                        name = "Title Y",
                        desc = "\"Windfury!\" text Y offset.",
                        min = -50, max = 50, step = 1,
                        order = 11,
                        get = function() return getFlatDB("wfCenterTextTitleY", 0) end,
                        set = function(_, v)
                            setFlatDB("wfCenterTextTitleY", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyCenterRingTextPosition then st.ApplyCenterRingTextPosition() end
                        end,
                    },
                    centerTextTotalY = {
                        type = "range",
                        name = "Total Y",
                        desc = "\"TOTAL: xxx\" text Y offset.",
                        min = -50, max = 50, step = 1,
                        order = 12,
                        get = function() return getFlatDB("wfCenterTextTotalY", 0) end,
                        set = function(_, v)
                            setFlatDB("wfCenterTextTotalY", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyCenterRingTextPosition then st.ApplyCenterRingTextPosition() end
                        end,
                    },
                    centerTextCriticalY = {
                        type = "range",
                        name = "Critical Y",
                        desc = "\"CRITICAL\" text Y offset.",
                        min = -50, max = 50, step = 1,
                        order = 13,
                        get = function() return getFlatDB("wfCenterTextCriticalY", 0) end,
                        set = function(_, v)
                            setFlatDB("wfCenterTextCriticalY", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyCenterRingTextPosition then st.ApplyCenterRingTextPosition() end
                        end,
                    },
                    centerFontHeader = {
                        type = "header",
                        name = "Center Ring Fonts",
                        order = 20,
                    },
                    fontCircleTitle = {
                        type = "range",
                        name = "Title Font",
                        min = 6, max = 32, step = 1,
                        order = 21,
                        get = function() return getFlatDB("fontCircleTitle", 20) end,
                        set = function(_, v)
                            setFlatDB("fontCircleTitle", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyCenterRingFontSizes then st.ApplyCenterRingFontSizes() end
                        end,
                    },
                    fontCircleTotal = {
                        type = "range",
                        name = "Total Font",
                        min = 6, max = 32, step = 1,
                        order = 22,
                        get = function() return getFlatDB("fontCircleTotal", 14) end,
                        set = function(_, v)
                            setFlatDB("fontCircleTotal", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyCenterRingFontSizes then st.ApplyCenterRingFontSizes() end
                        end,
                    },
                    fontCircleCritical = {
                        type = "range",
                        name = "Critical Font",
                        min = 6, max = 32, step = 1,
                        order = 23,
                        get = function() return getFlatDB("fontCircleCritical", 20) end,
                        set = function(_, v)
                            setFlatDB("fontCircleCritical", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyCenterRingFontSizes then st.ApplyCenterRingFontSizes() end
                        end,
                    },
                    ---------------------------------------------------------
                    -- Satellite Global
                    ---------------------------------------------------------
                    satelliteGlobalHeader = {
                        type = "header",
                        name = "Satellite Bubbles (Global)",
                        order = 30,
                    },
                    satelliteGap = {
                        type = "range",
                        name = "Gap from Center",
                        desc = "Space between center ring and satellite bubbles (0=touching, negative=overlap).",
                        min = -100, max = 100, step = 1,
                        order = 30.5,
                        get = function() return getFlatDB("wfSatelliteGap", 0) end,
                        set = function(_, v)
                            setFlatDB("wfSatelliteGap", v)
                            local st = _G.ShammyTime
                            if st and st.ApplySatelliteRadius then st.ApplySatelliteRadius() end
                        end,
                    },
                    satelliteBubbleScale = {
                        type = "range",
                        name = "Bubble Scale",
                        desc = "Scale of the small satellite bubbles around the center ring.",
                        min = 0.1, max = 3, step = 0.05,
                        order = 30.6,
                        get = function() return getFlatDB("wfSatelliteBubbleScale", 1) end,
                        set = function(_, v)
                            setFlatDB("wfSatelliteBubbleScale", v)
                            local st = _G.ShammyTime
                            if st and st.ApplySatelliteBubbleScale then st.ApplySatelliteBubbleScale() end
                        end,
                    },
                    satelliteLabelX = {
                        type = "range",
                        name = "Label X (all)",
                        min = -50, max = 50, step = 1,
                        order = 31,
                        get = function() return getFlatDB("wfSatelliteLabelX", 0) end,
                        set = function(_, v)
                            setFlatDB("wfSatelliteLabelX", v)
                            local st = _G.ShammyTime
                            if st and st.ApplySatelliteTextPosition then st.ApplySatelliteTextPosition() end
                        end,
                    },
                    satelliteLabelY = {
                        type = "range",
                        name = "Label Y (all)",
                        min = -50, max = 50, step = 1,
                        order = 32,
                        get = function() return getFlatDB("wfSatelliteLabelY", 0) end,
                        set = function(_, v)
                            setFlatDB("wfSatelliteLabelY", v)
                            local st = _G.ShammyTime
                            if st and st.ApplySatelliteTextPosition then st.ApplySatelliteTextPosition() end
                        end,
                    },
                    satelliteValueX = {
                        type = "range",
                        name = "Value X (all)",
                        min = -50, max = 50, step = 1,
                        order = 33,
                        get = function() return getFlatDB("wfSatelliteValueX", 0) end,
                        set = function(_, v)
                            setFlatDB("wfSatelliteValueX", v)
                            local st = _G.ShammyTime
                            if st and st.ApplySatelliteTextPosition then st.ApplySatelliteTextPosition() end
                        end,
                    },
                    satelliteValueY = {
                        type = "range",
                        name = "Value Y (all)",
                        min = -50, max = 50, step = 1,
                        order = 34,
                        get = function() return getFlatDB("wfSatelliteValueY", 0) end,
                        set = function(_, v)
                            setFlatDB("wfSatelliteValueY", v)
                            local st = _G.ShammyTime
                            if st and st.ApplySatelliteTextPosition then st.ApplySatelliteTextPosition() end
                        end,
                    },
                    fontSatelliteLabel = {
                        type = "range",
                        name = "Label Font (all)",
                        min = 4, max = 24, step = 1,
                        order = 35,
                        get = function() return getFlatDB("fontSatelliteLabel", 8) end,
                        set = function(_, v)
                            setFlatDB("fontSatelliteLabel", v)
                            local st = _G.ShammyTime
                            if st and st.ApplySatelliteFontSizes then st.ApplySatelliteFontSizes() end
                        end,
                    },
                    fontSatelliteValue = {
                        type = "range",
                        name = "Value Font (all)",
                        min = 4, max = 24, step = 1,
                        order = 36,
                        get = function() return getFlatDB("fontSatelliteValue", 13) end,
                        set = function(_, v)
                            setFlatDB("fontSatelliteValue", v)
                            local st = _G.ShammyTime
                            if st and st.ApplySatelliteFontSizes then st.ApplySatelliteFontSizes() end
                        end,
                    },
                    ---------------------------------------------------------
                    -- Per-Satellite Overrides
                    ---------------------------------------------------------
                    perSatelliteHeader = {
                        type = "header",
                        name = "Per-Bubble Overrides",
                        order = 40,
                    },
                    perSatelliteNote = {
                        type = "description",
                        name = "Set per-bubble text positions. Values of 0 use the global setting above.\n",
                        order = 41,
                    },
                    air = CreateSatelliteGroup("air", SATELLITE_LABELS.air, 42),
                    stone = CreateSatelliteGroup("stone", SATELLITE_LABELS.stone, 43),
                    fire = CreateSatelliteGroup("fire", SATELLITE_LABELS.fire, 44),
                    grass = CreateSatelliteGroup("grass", SATELLITE_LABELS.grass, 45),
                    water = CreateSatelliteGroup("water", SATELLITE_LABELS.water, 46),
                    grass_2 = CreateSatelliteGroup("grass_2", SATELLITE_LABELS.grass_2, 47),
                    ---------------------------------------------------------
                    -- Other Dev Settings
                    ---------------------------------------------------------
                    otherHeader = {
                        type = "header",
                        name = "Other",
                        order = 60,
                    },
                    totemTextHeader = {
                        type = "header",
                        name = "Totem Bar Text",
                        order = 60.5,
                    },
                    fontTotemTimer = {
                        type = "range",
                        name = "Totem Text Size",
                        min = 4, max = 20, step = 1,
                        order = 61,
                        get = function() return getFlatDB("fontTotemTimer", 10) end,
                        set = function(_, v)
                            setFlatDB("fontTotemTimer", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyTotemBarFontSize then st.ApplyTotemBarFontSize() end
                        end,
                    },
                    totemTextX = {
                        type = "range",
                        name = "Totem Text X",
                        desc = "Horizontal offset for totem timer text (positive = right).",
                        min = -100, max = 100, step = 1,
                        order = 61.1,
                        get = function()
                            local p = getDB()
                            if p and p.totemLayout and p.totemLayout.timerOffsetX ~= nil then
                                return p.totemLayout.timerOffsetX
                            end
                            return 0
                        end,
                        set = function(_, v)
                            local p = getDB()
                            if p then
                                p.totemLayout = p.totemLayout or {}
                                p.totemLayout.timerOffsetX = v
                            end
                            local st = _G.ShammyTime
                            if st and st.ApplyTotemBarLayout then st.ApplyTotemBarLayout() end
                        end,
                    },
                    totemTextY = {
                        type = "range",
                        name = "Totem Text Y",
                        desc = "Vertical offset for totem timer text (negative = down).",
                        min = -100, max = 100, step = 1,
                        order = 61.2,
                        get = function()
                            local p = getDB()
                            if p and p.totemLayout and p.totemLayout.timerOffsetY ~= nil then
                                return p.totemLayout.timerOffsetY
                            end
                            return -33
                        end,
                        set = function(_, v)
                            local p = getDB()
                            if p then
                                p.totemLayout = p.totemLayout or {}
                                p.totemLayout.timerOffsetY = v
                            end
                            local st = _G.ShammyTime
                            if st and st.ApplyTotemBarLayout then st.ApplyTotemBarLayout() end
                        end,
                    },
                    imbueTextHeader = {
                        type = "header",
                        name = "Imbue Bar Text",
                        order = 61.9,
                    },
                    fontImbueTimer = {
                        type = "range",
                        name = "Imbue Text Size",
                        min = 6, max = 64, step = 1,
                        order = 62,
                        get = function() return getFlatDB("fontImbueTimer", 16) end,
                        set = function(_, v)
                            setFlatDB("fontImbueTimer", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyImbueBarFontSize then st.ApplyImbueBarFontSize() end
                        end,
                    },
                    imbueTextX = {
                        type = "range",
                        name = "Imbue Text X",
                        desc = "Horizontal offset for imbue timer text (positive = right).",
                        min = -100, max = 100, step = 1,
                        order = 62.1,
                        get = function() return getFlatDB("imbueTextX", 0) end,
                        set = function(_, v)
                            setFlatDB("imbueTextX", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyImbueBarLayout then st.ApplyImbueBarLayout() end
                        end,
                    },
                    imbueTextY = {
                        type = "range",
                        name = "Imbue Text Y",
                        desc = "Vertical offset for imbue timer text (negative = down).",
                        min = -100, max = 100, step = 1,
                        order = 62.2,
                        get = function() return getFlatDB("imbueTextY", -20) end,
                        set = function(_, v)
                            setFlatDB("imbueTextY", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyImbueBarLayout then st.ApplyImbueBarLayout() end
                        end,
                    },
                    shieldTextHeader = {
                        type = "header",
                        name = "Shield Indicator Text",
                        order = 62.5,
                    },
                    shieldCountX = {
                        type = "range",
                        name = "Text X",
                        desc = "Horizontal offset for the shield count text.",
                        min = -100, max = 100, step = 1,
                        order = 62.6,
                        get = function() return getFlatDB("shieldCountX", 0) end,
                        set = function(_, v)
                            setFlatDB("shieldCountX", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyShieldCountSettings then st.ApplyShieldCountSettings() end
                        end,
                    },
                    shieldCountY = {
                        type = "range",
                        name = "Text Y",
                        desc = "Vertical offset for the shield count text (positive = up).",
                        min = -200, max = 300, step = 1,
                        order = 62.7,
                        get = function() return getFlatDB("shieldCountY", 127) end,
                        set = function(_, v)
                            setFlatDB("shieldCountY", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyShieldCountSettings then st.ApplyShieldCountSettings() end
                        end,
                    },
                    imbueBarMargin = {
                        type = "range",
                        name = "Imbue Margin",
                        min = 0, max = 50, step = 1,
                        order = 65,
                        get = function() return getFlatDB("imbueBarMargin", 10) end,
                        set = function(_, v)
                            setFlatDB("imbueBarMargin", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyImbueBarLayout then st.ApplyImbueBarLayout() end
                        end,
                    },
                    imbueBarGap = {
                        type = "range",
                        name = "Imbue Gap",
                        min = 0, max = 50, step = 1,
                        order = 66,
                        get = function() return getFlatDB("imbueBarGap", 4) end,
                        set = function(_, v)
                            setFlatDB("imbueBarGap", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyImbueBarLayout then st.ApplyImbueBarLayout() end
                        end,
                    },
                    imbueBarOffsetY = {
                        type = "range",
                        name = "Imbue Offset Y",
                        min = -50, max = 50, step = 1,
                        order = 67,
                        get = function() return getFlatDB("imbueBarOffsetY", 0) end,
                        set = function(_, v)
                            setFlatDB("imbueBarOffsetY", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyImbueBarLayout then st.ApplyImbueBarLayout() end
                        end,
                    },
                    ---------------------------------------------------------
                    -- Stagger Bar
                    ---------------------------------------------------------
                    staggerHeader = {
                        type = "header",
                        name = "Stagger Bar Positions",
                        order = 70,
                    },
                    staggerBarsX = {
                        type = "range",
                        name = "Bars X",
                        desc = "Horizontal offset for the MH/OH swing bars (positive = right).",
                        min = -250, max = 250, step = 1,
                        order = 71,
                        get = function() return getFlatDB("staggerBarsX", 0) end,
                        set = function(_, v)
                            setFlatDB("staggerBarsX", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyStaggerBarLayout then st.ApplyStaggerBarLayout() end
                        end,
                    },
                    staggerBarsY = {
                        type = "range",
                        name = "Bars Y",
                        desc = "Vertical offset for the MH/OH swing bars (positive = up).",
                        min = -100, max = 100, step = 1,
                        order = 72,
                        get = function() return getFlatDB("staggerBarsY", 0) end,
                        set = function(_, v)
                            setFlatDB("staggerBarsY", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyStaggerBarLayout then st.ApplyStaggerBarLayout() end
                        end,
                    },
                    ---------------------------------------------------------
                    -- Pressure Popup Slots
                    ---------------------------------------------------------
                    pressurePopupHeader = {
                        type = "header",
                        name = "Pressure Popup Slots",
                        order = 80,
                    },
                    pressurePopupIconSize = {
                        type = "range",
                        name = "Icon Size",
                        desc = "Base icon size for the three pressure popup slots.",
                        min = 24, max = 192, step = 1,
                        order = 81,
                        get = function() return getFlatDB("pressurePopupIconSize", 74) end,
                        set = function(_, v) setFlatDB("pressurePopupIconSize", v) end,
                    },
                    pressurePopupTextSize = {
                        type = "range",
                        name = "Text Size",
                        desc = "Base damage text size for the three pressure popup slots.",
                        min = 8, max = 72, step = 1,
                        order = 82,
                        get = function() return getFlatDB("pressurePopupTextSize", 49) end,
                        set = function(_, v) setFlatDB("pressurePopupTextSize", v) end,
                    },
                    pressurePopupHoldSec = {
                        type = "range",
                        name = "Popup Hold (sec)",
                        desc = "How long non-sustained spell popups stay fully visible before fading.",
                        min = 0.10, max = 10.0, step = 0.05,
                        order = 82.1,
                        get = function() return getFlatDB("pressurePopupHoldSec", 5.20) end,
                        set = function(_, v) setFlatDB("pressurePopupHoldSec", v) end,
                    },
                    pressurePopupFadeSec = {
                        type = "range",
                        name = "Popup Fade (sec)",
                        desc = "Fade duration after hold time ends.",
                        min = 0.10, max = 10.0, step = 0.05,
                        order = 82.2,
                        get = function() return getFlatDB("pressurePopupFadeSec", 1.20) end,
                        set = function(_, v) setFlatDB("pressurePopupFadeSec", v) end,
                    },
                    pressurePopupSustainSec = {
                        type = "range",
                        name = "Sustain Linger (sec)",
                        desc = "How long CL/Flame Shock/Magma stay visible since their last damage event.",
                        min = 0.20, max = 15.0, step = 0.05,
                        order = 82.3,
                        get = function() return getFlatDB("pressurePopupSustainSec", 6.00) end,
                        set = function(_, v) setFlatDB("pressurePopupSustainSec", v) end,
                    },
                    pressurePopupCritBounceScale = {
                        type = "range",
                        name = "Crit Bounce Scale",
                        desc = "How big the damage text expands on crit pulses (1.00 = no bounce).",
                        min = 1.00, max = 2.50, step = 0.01,
                        order = 82.4,
                        get = function() return getFlatDB("pressurePopupCritBounceScale", 2.00) end,
                        set = function(_, v) setFlatDB("pressurePopupCritBounceScale", v) end,
                    },
                    pressurePopupCritBounceSec = {
                        type = "range",
                        name = "Crit Bounce Time (sec)",
                        desc = "Duration of the text crit bounce animation.",
                        min = 0.05, max = 1.50, step = 0.01,
                        order = 82.5,
                        get = function() return getFlatDB("pressurePopupCritBounceSec", 0.20) end,
                        set = function(_, v) setFlatDB("pressurePopupCritBounceSec", v) end,
                    },
                    pressureSlot1X = {
                        type = "range",
                        name = "Slot 1 X",
                        min = -500, max = 500, step = 1,
                        order = 83,
                        get = function() return getFlatDB("pressureSlot1X", -130) end,
                        set = function(_, v) setFlatDB("pressureSlot1X", v) end,
                    },
                    pressureSlot1Y = {
                        type = "range",
                        name = "Slot 1 Y",
                        min = -500, max = 500, step = 1,
                        order = 84,
                        get = function() return getFlatDB("pressureSlot1Y", -104) end,
                        set = function(_, v) setFlatDB("pressureSlot1Y", v) end,
                    },
                    pressureSlot1TextX = {
                        type = "range",
                        name = "Slot 1 Text X",
                        min = -500, max = 500, step = 1,
                        order = 84.1,
                        get = function() return getFlatDB("pressureSlot1TextX", 0) end,
                        set = function(_, v) setFlatDB("pressureSlot1TextX", v) end,
                    },
                    pressureSlot1TextY = {
                        type = "range",
                        name = "Slot 1 Text Y",
                        min = -500, max = 500, step = 1,
                        order = 84.2,
                        get = function() return getFlatDB("pressureSlot1TextY", -14) end,
                        set = function(_, v) setFlatDB("pressureSlot1TextY", v) end,
                    },
                    pressureSlot2X = {
                        type = "range",
                        name = "Slot 2 X",
                        min = -500, max = 500, step = 1,
                        order = 85,
                        get = function() return getFlatDB("pressureSlot2X", 1) end,
                        set = function(_, v) setFlatDB("pressureSlot2X", v) end,
                    },
                    pressureSlot2Y = {
                        type = "range",
                        name = "Slot 2 Y",
                        min = -500, max = 500, step = 1,
                        order = 86,
                        get = function() return getFlatDB("pressureSlot2Y", -123) end,
                        set = function(_, v) setFlatDB("pressureSlot2Y", v) end,
                    },
                    pressureSlot2TextX = {
                        type = "range",
                        name = "Slot 2 Text X",
                        min = -500, max = 500, step = 1,
                        order = 86.1,
                        get = function() return getFlatDB("pressureSlot2TextX", 0) end,
                        set = function(_, v) setFlatDB("pressureSlot2TextX", v) end,
                    },
                    pressureSlot2TextY = {
                        type = "range",
                        name = "Slot 2 Text Y",
                        min = -500, max = 500, step = 1,
                        order = 86.2,
                        get = function() return getFlatDB("pressureSlot2TextY", -16) end,
                        set = function(_, v) setFlatDB("pressureSlot2TextY", v) end,
                    },
                    pressureSlot3X = {
                        type = "range",
                        name = "Slot 3 X",
                        min = -500, max = 500, step = 1,
                        order = 87,
                        get = function() return getFlatDB("pressureSlot3X", 135) end,
                        set = function(_, v) setFlatDB("pressureSlot3X", v) end,
                    },
                    pressureSlot3Y = {
                        type = "range",
                        name = "Slot 3 Y",
                        min = -500, max = 500, step = 1,
                        order = 88,
                        get = function() return getFlatDB("pressureSlot3Y", -104) end,
                        set = function(_, v) setFlatDB("pressureSlot3Y", v) end,
                    },
                    pressureSlot3TextX = {
                        type = "range",
                        name = "Slot 3 Text X",
                        min = -500, max = 500, step = 1,
                        order = 88.1,
                        get = function() return getFlatDB("pressureSlot3TextX", -7) end,
                        set = function(_, v) setFlatDB("pressureSlot3TextX", v) end,
                    },
                    pressureSlot3TextY = {
                        type = "range",
                        name = "Slot 3 Text Y",
                        min = -500, max = 500, step = 1,
                        order = 88.2,
                        get = function() return getFlatDB("pressureSlot3TextY", -18) end,
                        set = function(_, v) setFlatDB("pressureSlot3TextY", v) end,
                    },
                    pressureEngineTuneHeader = {
                        type = "header",
                        name = "Pressure Engine Tuning",
                        order = 89,
                    },
                    pressureEngineTuneDesc = {
                        type = "description",
                        name = "Developer-only pressure tuning. Adjust momentum, per-tier damage breakpoints, per-tier force gates, and concavity depth (easier early climb, tougher high-end push).",
                        order = 89.05,
                        width = "full",
                    },
                    pressureDevReset = {
                        type = "execute",
                        name = "Reset Pressure Dev Options",
                        desc = "Reset pressure popup slots and pressure engine tuning values to defaults.",
                        order = 89.06,
                        width = "full",
                        confirm = true,
                        confirmText = "Reset all Pressure developer options to defaults?",
                        func = resetPressureDevOptions,
                    },
                    pressureTierConcavityDepth = {
                        type = "range",
                        name = "Concavity Depth",
                        desc = "Adds gravity near the top of each tier segment (higher = easier around mid-fill, harder near 70%-100%).",
                        min = 0.00, max = 3.00, step = 0.01,
                        order = 89.1,
                        get = function() return getFlatDB("pressureTierConcavityDepth", 0.00) end,
                        set = function(_, v) setFlatDB("pressureTierConcavityDepth", v) end,
                    },
                    pressureTierMomentumOnPromote = {
                        type = "range",
                        name = "Momentum Gain On Promote",
                        desc = "Extra momentum injected on each successful tier promotion.",
                        min = 0.00, max = 1.00, step = 0.01,
                        order = 89.2,
                        get = function() return getFlatDB("pressureTierMomentumOnPromote", 0.08) end,
                        set = function(_, v) setFlatDB("pressureTierMomentumOnPromote", v) end,
                    },
                    pressureTierMomentumPerTier = {
                        type = "range",
                        name = "Momentum Per Tier",
                        desc = "Passive momentum bonus per current tier (higher tiers carry more momentum).",
                        min = 0.00, max = 0.25, step = 0.005,
                        order = 89.3,
                        get = function() return getFlatDB("pressureTierMomentumPerTier", 0.04) end,
                        set = function(_, v) setFlatDB("pressureTierMomentumPerTier", v) end,
                    },
                    pressureTierMomentumMax = {
                        type = "range",
                        name = "Momentum Max",
                        desc = "Maximum momentum bonus cap.",
                        min = 0.00, max = 1.50, step = 0.01,
                        order = 89.4,
                        get = function() return getFlatDB("pressureTierMomentumMax", 0.22) end,
                        set = function(_, v) setFlatDB("pressureTierMomentumMax", v) end,
                    },
                    pressureTierMomentumDecayTau = {
                        type = "range",
                        name = "Momentum Decay Tau",
                        desc = "How quickly momentum decays during normal pressure activity.",
                        min = 0.20, max = 12.0, step = 0.05,
                        order = 89.5,
                        get = function() return getFlatDB("pressureTierMomentumDecayTau", 3.20) end,
                        set = function(_, v) setFlatDB("pressureTierMomentumDecayTau", v) end,
                    },
                    pressureTierMomentumIdleDecayTau = {
                        type = "range",
                        name = "Momentum Idle Decay Tau",
                        desc = "How quickly momentum decays while idle.",
                        min = 0.10, max = 8.0, step = 0.05,
                        order = 89.6,
                        get = function() return getFlatDB("pressureTierMomentumIdleDecayTau", 1.15) end,
                        set = function(_, v) setFlatDB("pressureTierMomentumIdleDecayTau", v) end,
                    },
                    pressureTierDamageReq1 = {
                        type = "range",
                        name = "Damage Req T1",
                        desc = "Damage pressure needed to break into tier 1.",
                        min = 0.20, max = 10.0, step = 0.01,
                        order = 89.7,
                        get = function() return getFlatDB("pressureTierDamageReq1", 1.50) end,
                        set = function(_, v) setFlatDB("pressureTierDamageReq1", v) end,
                    },
                    pressureTierDamageReq2 = {
                        type = "range",
                        name = "Damage Req T2",
                        desc = "Damage pressure needed to break into tier 2.",
                        min = 0.20, max = 10.0, step = 0.01,
                        order = 89.8,
                        get = function() return getFlatDB("pressureTierDamageReq2", 1.85) end,
                        set = function(_, v) setFlatDB("pressureTierDamageReq2", v) end,
                    },
                    pressureTierDamageReq3 = {
                        type = "range",
                        name = "Damage Req T3",
                        desc = "Damage pressure needed to break into tier 3.",
                        min = 0.20, max = 10.0, step = 0.01,
                        order = 89.9,
                        get = function() return getFlatDB("pressureTierDamageReq3", 2.32) end,
                        set = function(_, v) setFlatDB("pressureTierDamageReq3", v) end,
                    },
                    pressureTierDamageReq4 = {
                        type = "range",
                        name = "Damage Req T4",
                        desc = "Damage pressure needed to break into tier 4.",
                        min = 0.20, max = 10.0, step = 0.01,
                        order = 90.0,
                        get = function() return getFlatDB("pressureTierDamageReq4", 3.05) end,
                        set = function(_, v) setFlatDB("pressureTierDamageReq4", v) end,
                    },
                    pressureTierDamageReq5 = {
                        type = "range",
                        name = "Damage Req T5",
                        desc = "Damage pressure needed to break into tier 5.",
                        min = 0.20, max = 10.0, step = 0.01,
                        order = 90.1,
                        get = function() return getFlatDB("pressureTierDamageReq5", 3.90) end,
                        set = function(_, v) setFlatDB("pressureTierDamageReq5", v) end,
                    },
                    pressureTierForceReq1 = {
                        type = "range",
                        name = "Force Req T1",
                        desc = "Minimum force gate (squeeze) required to enter tier 1.",
                        min = 0.00, max = 1.00, step = 0.01,
                        order = 90.2,
                        get = function() return getFlatDB("pressureTierForceReq1", 0.00) end,
                        set = function(_, v) setFlatDB("pressureTierForceReq1", v) end,
                    },
                    pressureTierForceReq2 = {
                        type = "range",
                        name = "Force Req T2",
                        desc = "Minimum force gate (squeeze) required to enter tier 2.",
                        min = 0.00, max = 1.00, step = 0.01,
                        order = 90.3,
                        get = function() return getFlatDB("pressureTierForceReq2", 0.18) end,
                        set = function(_, v) setFlatDB("pressureTierForceReq2", v) end,
                    },
                    pressureTierForceReq3 = {
                        type = "range",
                        name = "Force Req T3",
                        desc = "Minimum force gate (squeeze) required to enter tier 3.",
                        min = 0.00, max = 1.00, step = 0.01,
                        order = 90.4,
                        get = function() return getFlatDB("pressureTierForceReq3", 0.35) end,
                        set = function(_, v) setFlatDB("pressureTierForceReq3", v) end,
                    },
                    pressureTierForceReq4 = {
                        type = "range",
                        name = "Force Req T4",
                        desc = "Minimum force gate (squeeze) required to enter tier 4.",
                        min = 0.00, max = 1.00, step = 0.01,
                        order = 90.5,
                        get = function() return getFlatDB("pressureTierForceReq4", 0.70) end,
                        set = function(_, v) setFlatDB("pressureTierForceReq4", v) end,
                    },
                    pressureTierForceReq5 = {
                        type = "range",
                        name = "Force Req T5",
                        desc = "Minimum force gate (squeeze) required to enter tier 5.",
                        min = 0.00, max = 1.00, step = 0.01,
                        order = 90.6,
                        get = function() return getFlatDB("pressureTierForceReq5", 0.92) end,
                        set = function(_, v) setFlatDB("pressureTierForceReq5", v) end,
                    },
                },
            },
        },
    }

    AceConfig:RegisterOptionsTable("ShammyTime", options)
    AceConfigDialog:AddToBlizOptions("ShammyTime", "ShammyTime")
end
