-- ShammyTime_Core.lua
-- AceAddon init, AceDB, options hook, and ApplyAllConfigs. Uses installed Ace3 in Libs/.

local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0")
local AceDB = LibStub("AceDB-3.0")
local AceEvent = LibStub("AceEvent-3.0")

-- Create addon and expose globally (other files expect ShammyTime)
local ShammyTime = AceAddon:NewAddon("ShammyTime", "AceEvent-3.0")
_G.ShammyTime = ShammyTime

local PERF_MONITOR_TICK_SEC = 2.0
local PERF_SAMPLE_CACHE_SEC = 0.20

local CAddOns = C_AddOns
local CVarAPI = C_CVar

local AddOnsGetNum = (CAddOns and CAddOns.GetNumAddOns) or GetNumAddOns
local AddOnsGetInfo = (CAddOns and CAddOns.GetAddOnInfo) or GetAddOnInfo
local AddOnsUpdateMemory = (CAddOns and CAddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
local AddOnsGetMemory = (CAddOns and CAddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
local AddOnsUpdateCPU = (CAddOns and CAddOns.UpdateAddOnCPUUsage) or UpdateAddOnCPUUsage
local AddOnsGetCPU = (CAddOns and CAddOns.GetAddOnCPUUsage) or GetAddOnCPUUsage

local function GetScriptProfileState()
    local getBool = GetCVarBool or (CVarAPI and CVarAPI.GetCVarBool)
    if getBool then
        local ok, enabled = pcall(getBool, "scriptProfile")
        if ok then
            return enabled and true or false, true
        end
    end

    local getValue = GetCVar or (CVarAPI and CVarAPI.GetCVar)
    if getValue then
        local ok, raw = pcall(getValue, "scriptProfile")
        if ok then
            local txt = tostring(raw or ""):lower()
            if txt == "1" or txt == "true" then return true, true end
            if txt == "0" or txt == "false" then return false, true end
        end
    end

    return nil, false
end

local function GetAddOnInfoPair(idOrName)
    if not AddOnsGetInfo then return nil, nil end
    local ok, a, b = pcall(AddOnsGetInfo, idOrName)
    if not ok then return nil, nil end
    if type(a) == "table" then
        local name = a.name or a.Name or a.addonName
        local title = a.title or a.Title
        return name, title
    end
    return a, b
end

local function GetShammyTimeAddonIdentity()
    if ShammyTime._perfAddonIndex and ShammyTime._perfAddonIndex > 0 then
        return ShammyTime._perfAddonIndex, ShammyTime._perfAddonName or "ShammyTime"
    end

    local directName = select(1, GetAddOnInfoPair("ShammyTime"))
    if type(directName) == "string" and directName ~= "" then
        ShammyTime._perfAddonName = directName
    end

    if not AddOnsGetNum or not AddOnsGetInfo then
        return nil, ShammyTime._perfAddonName or "ShammyTime"
    end
    local okCount, count = pcall(AddOnsGetNum)
    if not okCount or type(count) ~= "number" or count <= 0 then
        return nil, ShammyTime._perfAddonName or "ShammyTime"
    end
    local target = (ShammyTime._perfAddonName or "ShammyTime"):lower()
    for i = 1, count do
        local name, title = GetAddOnInfoPair(i)
        local nameLower = type(name) == "string" and name:lower() or nil
        local titleLower = type(title) == "string" and title:lower() or nil
        if nameLower == target or nameLower == "shammytime" or (titleLower and titleLower:find("shammytime", 1, true)) then
            ShammyTime._perfAddonIndex = i
            ShammyTime._perfAddonName = type(name) == "string" and name or "ShammyTime"
            return i, ShammyTime._perfAddonName
        end
    end
    return nil, ShammyTime._perfAddonName or "ShammyTime"
end

local function GetAddOnMetricValue(getFn, addonIndex, addonName)
    if not getFn then return nil end
    if addonIndex and addonIndex > 0 then
        local okIndex, valueByIndex = pcall(getFn, addonIndex)
        if okIndex and type(valueByIndex) == "number" then
            return valueByIndex
        end
    end
    if addonName and addonName ~= "" then
        local okName, valueByName = pcall(getFn, addonName)
        if okName and type(valueByName) == "number" then
            return valueByName
        end
    end
    return nil
end

-- Per-module default structure (spec)
local function moduleDefaults(enabled, scale, alpha)
    return {
        enabled = enabled,
        scale = scale,
        alpha = alpha or 1,
        pos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
        font = { size = 14 },
        fade = {
            enabled = false,
            inactiveAlpha = 0,
            conditions = {
                outOfCombat = false,
                noTarget = false,
                inactiveBuff = false,
                noTotemsPlaced = false,
                outOfRange = false,
                fadeInOnTarget = false,  -- when true: slow fade-in when selecting an enemy target (windfury/focus only)
                hideWhenActive = false,  -- when true: hide element when its buff/shield is active (shield indicator only)
            },
        },
    }
end

-- AceDB defaults: flat keys for backward compat + profile.global and profile.modules for options UI
local DEFAULTS = {
    profile = {
        -- Global (spec)
        global = {
            locked = false,
            demoMode = false,
            masterScale = 1.0,
            masterAlpha = 1.0,
            devMode = false,  -- Show Developer panel in options
        },
        -- Per-module (spec)
        modules = {
            windfuryBubbles = moduleDefaults(true, 0.65, 1.0),
            shieldIndicator = moduleDefaults(true, 0.36, 1.0),
            shamanisticFocus = moduleDefaults(true, 1.17, 1.0),
            totemBar = moduleDefaults(true, 1.2, 1.0),
            weaponImbueBar = moduleDefaults(true, 0.75, 1.0),
            wfImpact = moduleDefaults(true, 1.3, 1.0),
            windfuryIcd = moduleDefaults(true, 1.045, 1.0),
            staggerBar = moduleDefaults(true, 0.5, 1.0),
            pressureVisual = moduleDefaults(true, 0.8, 1.0),
        },
        -- Flat keys (existing code)
        point = "CENTER",
        relativeTo = "UIParent",
        relativePoint = "CENTER",
        x = 0,
        y = -180,
        scale = 1.0,
        locked = false,
        wfPoint = "TOP",
        wfRelativeTo = "ShammyTimeFrame",
        wfRelativePoint = "BOTTOM",
        wfX = 0,
        wfY = -4,
        wfScale = 1.0,
        wfLocked = false,
        windfuryTrackerEnabled = true,
        wfRadialEnabled = false,
        wfTotemBarEnabled = true,
        wfFocusEnabled = true,
        wfImbueBarEnabled = true,
        wfShieldEnabled = true,
        wfIcdEnabled = true,
        uiErrorTextEnabled = false,
        shieldScale = 0.36,
        shieldCount = nil,
        shieldCountX = 1,
        shieldCountY = 127,
        wfRadialScale = 0.65,
        wfSatelliteGap = -78,
        wfSatelliteBubbleScale = 1,
        wfCenterSize = 300,
        wfCenterTextTitleY = 28,
        wfCenterTextTotalY = 4,
        wfCenterTextCriticalY = -40,
        wfTotemBarScale = 1.2,
        wfRadialShown = false,
        wfAlwaysShowNumbers = false,
        wfFadeOutOfCombat = false,
        wfFadeWhenNotProcced = false,
        wfFocusFadeWhenNotProcced = false,
        wfFadeWhenNoTotems = false,
        wfNoTotemsFadeDelay = 5,
        wfImbueFadeWhenLongDuration = false,
        wfImbueFadeThresholdSec = 120,
        fontCircleTitle = 22,
        fontCircleTotal = 24,
        fontCircleCritical = 17,
        fontSatelliteLabel = 16,
        fontSatelliteValue = 21,
        fontTotemTimer = 10,
        fontImbueTimer = 16,
        fontShieldCount = 86,
        wfSatelliteLabelX = 0,
        wfSatelliteLabelY = 20,
        wfSatelliteValueX = 0,
        wfSatelliteValueY = 0,
        wfSatelliteOverrides = {
            upper_right  = { labelY = 17, valueY = -3 },
            upper_left   = { labelY = 19, valueY = -2 },
            middle_left  = { labelY = 14, valueY = -5 },
            bottom_left  = { labelY = 29, valueY = 9 },
            middle_right = { labelY = 14, valueY = -5 },
            bottom_right = { labelY = 26, valueY = 6 },
        },
        -- WF Impact (Windfury Totem party damage feed)
        wfImpactEnabled = true,
        pressureEnabled = true,
        wfImpactOffsetX = 0,
        wfImpactOffsetY = -26,
        wfImpactFontScroll = 15,
        wfImpactFontTotal = 16,
        wfImpactScrollDuration = 2.0,
        wfImpactScrollDistance = 115,
        pressureScale = 0.8,
        -- Stagger bar
        staggerBarEnabled = true,
        staggerBarAlwaysShow = true,
        staggerBarWidth = 335,
        staggerBarHeight = 15,
        staggerBarGap = 5,
        staggerSwingBarAlpha = 0.8,
        staggerBarsX = 3,
        staggerBarsY = 2,
        staggerDeltaFontSize = 27,
        staggerDeltaX = 46,
        staggerDeltaY = 12,
        staggerHelperFontSize = 24,
        staggerHelperX = 0,
        staggerHelperY = -10,
        staggerHideDelay = 15,
        -- Pressure popup driver slots (Developer panel)
        pressureSlot1X = -130,
        pressureSlot1Y = -147,
        pressureSlot1TextX = 0,
        pressureSlot1TextY = -14,
        pressureSlot2X = 1,
        pressureSlot2Y = -171,
        pressureSlot2TextX = 0,
        pressureSlot2TextY = -16,
        pressureSlot3X = 135,
        pressureSlot3Y = -147,
        pressureSlot3TextX = -7,
        pressureSlot3TextY = -18,
        pressurePopupIconSize = 74,
        pressurePopupTextSize = 49,
        pressurePopupHoldSec = 5.20,
        pressurePopupFadeSec = 1.20,
        pressurePopupSustainSec = 6.00,
        pressurePopupCritBounceScale = 2.00,
        pressurePopupCritBounceSec = 0.20,
        pressureSimpleResistance = 1.25,
        pressureSimpleRubberband = 1.10,
        pressureSimpleTierBase = 2.10,
        pressureSimpleTierStepPct = 11.00,
        pressureSimpleTierHelp = 0.85,
        pressureSimpleOverdrivePercentile = 98.00,
        pressureSimpleOverdriveMultiplier = 1.16,
        pressureSimpleTierHoldSec = 5.00,
        pressureSimpleShakeAmount = 1.00,
        pressureSimpleShakeFromDamage = 0.85,
        imbueBarScale = 0.75,
        imbueBarMargin = nil,
        imbueBarGap = nil,
        imbueBarOffsetY = nil,
        wfSession = { total = 0, count = 0, procs = 0, min = nil, max = nil, crits = 0, swings = 0 },
        wfLastPull = { total = 0, count = 0, procs = 0, min = nil, max = nil, crits = 0, swings = 0 },
        wfRadialPos = {},
        focusFrame = {
            point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER",
            x = -381.49990844727, y = 0.51829099655151, scale = 1.17, locked = false,
        },
        windfuryIcdFrame = {
            point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER",
            x = 0, y = -250, scale = 0.8, locked = false,
        },
    },
}

DEFAULTS.profile.modules.shamanisticFocus.pos = {
    point = "CENTER",
    relPoint = "CENTER",
    x = -381.49990844727,
    y = 0.51829099655151,
}

function ShammyTime:OnInitialize()
    self.db = AceDB:New("ShammyTimeDB", DEFAULTS, true)
    local p = self.db and self.db.profile
    if p then
        p.modules = p.modules or {}
        if not p.modules.pressureVisual then
            p.modules.pressureVisual = moduleDefaults(true, 0.8, 1.0)
        end
    end
    self:MigrateOldDB()
    if self.SetupOptions then
        self:SetupOptions()
    end
    -- When the user switches profile or resets profile, apply the (new) profile to the UI
    if self.db.RegisterCallback then
        local addon = self
        self.db:RegisterCallback("OnProfileChanged", function()
            if addon.ApplyAllConfigs then addon:ApplyAllConfigs() end
        end)
        self.db:RegisterCallback("OnProfileReset", function()
            if addon.ApplyAllConfigs then addon:ApplyAllConfigs() end
        end)
    end
    -- Expose GetDB for all other files (returns profile = flat view)
    function ShammyTime.GetDB()
        local addon = AceAddon:GetAddon("ShammyTime", true)
        if not addon or not addon.db then return {} end
        return addon.db.profile
    end
end

function ShammyTime:OnEnable()
    self.state = {
        inCombat = false,
        hasTarget = false,
        hasAnyTotem = false,
        hasShield = false,
        hasImbue = false,
    }
    if self.ApplyErrorTextSetting then
        self:ApplyErrorTextSetting()
    end
    if self.ScheduleErrorTextSettingApply then
        self:ScheduleErrorTextSettingApply(2)
    end
    if self.ApplyAllConfigs then
        self:ApplyAllConfigs()
    end
end

--- Show/hide Blizzard red error text based on profile setting.
function ShammyTime:ApplyErrorTextSetting()
    if not UIErrorsFrame then return end
    local p = self.db and self.db.profile
    local shouldShow = (p and p.uiErrorTextEnabled == true)
    if shouldShow then
        UIErrorsFrame:Show()
        self._uiErrorTextDisableNotified = false
    else
        UIErrorsFrame:Hide()
        if not self._uiErrorTextDisableNotified then
            print("|cff00ff00ShammyTime:|r Blizzard error text disabled by ShammyTime. Enable it in General -> Show Blizzard Error Text.")
            self._uiErrorTextDisableNotified = true
        end
    end
end

--- Re-apply error text visibility shortly after login/reload.
function ShammyTime:ScheduleErrorTextSettingApply(delaySec)
    local delay = (type(delaySec) == "number" and delaySec >= 0) and delaySec or 2
    C_Timer.After(delay, function()
        local addon = _G.ShammyTime
        if addon and addon.ApplyErrorTextSetting then
            addon:ApplyErrorTextSetting()
        end
    end)
end

--- Capture one performance sample (memory always; CPU when script profiling is available/enabled).
function ShammyTime:GetPerformanceSample(force)
    local now = (GetTime and GetTime()) or 0
    local sample = self._perfSample
    if sample and not force and sample.at and (now - sample.at) <= PERF_SAMPLE_CACHE_SEC then
        return sample
    end
    sample = sample or {}

    local addonIndex, addonName = GetShammyTimeAddonIdentity()
    local memKB = nil
    if AddOnsUpdateMemory and AddOnsGetMemory and (addonIndex or addonName) then
        pcall(AddOnsUpdateMemory)
        local mem = GetAddOnMetricValue(AddOnsGetMemory, addonIndex, addonName)
        if type(mem) == "number" then
            memKB = mem
        end
    end
    if type(memKB) == "number" then
        sample.memKB = memKB
        sample.memMB = memKB / 1024
        sample.memUnavailableReason = nil
    else
        sample.memKB = 0
        sample.memMB = 0
        if not (AddOnsUpdateMemory and AddOnsGetMemory) then
            sample.memUnavailableReason = "API unavailable"
        elseif not (addonIndex or addonName) then
            sample.memUnavailableReason = "addon not found"
        else
            sample.memUnavailableReason = "unavailable"
        end
    end

    local cpuApiAvailable = AddOnsUpdateCPU and AddOnsGetCPU and (addonIndex or addonName)
    local cpuProfilingEnabled, cpuProfilingKnown = GetScriptProfileState()
    local canSampleCPU = cpuApiAvailable and (cpuProfilingEnabled ~= false)

    if canSampleCPU then
        local okUpdate = pcall(AddOnsUpdateCPU)
        local cpuMsTotal = GetAddOnMetricValue(AddOnsGetCPU, addonIndex, addonName)
        if okUpdate and type(cpuMsTotal) == "number" then
            local cpuMsPerSec = 0
            if sample.lastCpuMs ~= nil and sample.lastCpuAt and now > sample.lastCpuAt then
                cpuMsPerSec = (cpuMsTotal - sample.lastCpuMs) / math.max(now - sample.lastCpuAt, 0.001)
                if cpuMsPerSec < 0 then cpuMsPerSec = 0 end
            end
            local cpuPct = cpuMsPerSec / 10 -- 1000 ms/s == 100%
            sample.cpuMsTotal = cpuMsTotal
            sample.cpuMsPerSec = cpuMsPerSec
            sample.cpuPct = cpuPct
            sample.cpuUnavailableReason = nil
            sample.lastCpuMs = cpuMsTotal
            sample.lastCpuAt = now
        else
            sample.cpuMsTotal = nil
            sample.cpuMsPerSec = nil
            sample.cpuPct = nil
            sample.cpuUnavailableReason = "unavailable"
            sample.lastCpuMs = nil
            sample.lastCpuAt = nil
        end
    else
        sample.cpuMsTotal = nil
        sample.cpuMsPerSec = nil
        sample.cpuPct = nil
        if not cpuApiAvailable then
            sample.cpuUnavailableReason = "API unavailable"
        elseif cpuProfilingEnabled == false then
            sample.cpuUnavailableReason = "off (run /console scriptProfile 1 then /reload)"
        elseif not cpuProfilingKnown then
            sample.cpuUnavailableReason = "unavailable (scriptProfile unknown)"
        else
            sample.cpuUnavailableReason = "unavailable"
        end
        sample.lastCpuMs = nil
        sample.lastCpuAt = nil
    end

    sample.at = now
    self._perfSample = sample
    return sample
end

function ShammyTime:GetPerformanceStatsText(force)
    local sample = self:GetPerformanceSample(force)
    local memPart
    if sample.memUnavailableReason then
        memPart = "Memory " .. sample.memUnavailableReason
    else
        local memKB = sample.memKB or 0
        if memKB < 1024 then
            memPart = ("Memory %.0f KB"):format(memKB)
        else
            memPart = ("Memory %.2f MB"):format((sample.memMB or 0))
        end
    end
    local cpuPart
    if sample.cpuUnavailableReason then
        cpuPart = "CPU " .. sample.cpuUnavailableReason
    else
        cpuPart = ("CPU %.2f ms/s (%.2f%%) (total %.1f ms)"):format(
            sample.cpuMsPerSec or 0,
            sample.cpuPct or 0,
            sample.cpuMsTotal or 0
        )
    end
    local shown = self:IsPerformanceMonitorShown() and "ON" or "OFF"
    return memPart .. " | " .. cpuPart .. " | monitor " .. shown
end

function ShammyTime:EnsurePerformanceMonitorFrame()
    if self.performanceMonitorFrame then return self.performanceMonitorFrame end
    local f = CreateFrame("Frame", "ShammyTimePerformanceMonitorFrame", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetSize(290, 62)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -260)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0, 0, 0, 0.72)

    local border = f:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(1, 1, 1, 0.18)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetJustifyH("LEFT")
    title:SetText("ShammyTime Performance")

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 8, -22)
    text:SetJustifyH("LEFT")
    text:SetText("")
    f.statsText = text
    f:Hide()

    self.performanceMonitorFrame = f
    return f
end

function ShammyTime:IsPerformanceMonitorShown()
    return self.performanceMonitorFrame and self.performanceMonitorFrame:IsShown() or false
end

function ShammyTime:UpdatePerformanceMonitorText(force)
    local f = self:EnsurePerformanceMonitorFrame()
    local sample = self:GetPerformanceSample(force == true)

    -- Minimize UI/string churn in the dev monitor unless values changed enough.
    if force ~= true then
        local memReasonSame = (sample.memUnavailableReason == f._lastMemReason)
        local cpuReasonSame = (sample.cpuUnavailableReason == f._lastCpuReason)
        local memChanged = (math.abs((sample.memKB or 0) - (f._lastMemKB or 0)) >= 16)
        local cpuRateChanged = (math.abs((sample.cpuMsPerSec or 0) - (f._lastCpuMsPerSec or 0)) >= 0.05)
        local cpuTotalChanged = (math.abs((sample.cpuMsTotal or 0) - (f._lastCpuMsTotal or 0)) >= 0.5)
        local cpuPctChanged = (math.abs((sample.cpuPct or 0) - (f._lastCpuPct or 0)) >= 0.01)
        if memReasonSame and cpuReasonSame and (not memChanged) and (not cpuRateChanged) and (not cpuTotalChanged) and (not cpuPctChanged) then
            return
        end
    end

    local memLine
    if sample.memUnavailableReason then
        memLine = "Memory: " .. sample.memUnavailableReason
    else
        local memKB = sample.memKB or 0
        if memKB < 1024 then
            memLine = ("Memory: %.0f KB"):format(memKB)
        else
            memLine = ("Memory: %.2f MB"):format(sample.memMB or 0)
        end
    end
    local cpuLine
    if sample.cpuUnavailableReason then
        cpuLine = "CPU: " .. sample.cpuUnavailableReason
    else
        cpuLine = ("CPU: %.2f ms/s (%.2f%%) | total %.1f ms"):format(
            sample.cpuMsPerSec or 0,
            sample.cpuPct or 0,
            sample.cpuMsTotal or 0
        )
    end
    if f.statsText then
        f.statsText:SetText(memLine .. "\n" .. cpuLine)
    end
    f._lastMemKB = sample.memKB or 0
    f._lastMemReason = sample.memUnavailableReason
    f._lastCpuMsPerSec = sample.cpuMsPerSec or 0
    f._lastCpuMsTotal = sample.cpuMsTotal or 0
    f._lastCpuPct = sample.cpuPct or 0
    f._lastCpuReason = sample.cpuUnavailableReason
end

function ShammyTime:ShowPerformanceMonitor()
    local f = self:EnsurePerformanceMonitorFrame()
    f:Show()
    self:UpdatePerformanceMonitorText(true)
    if self.performanceMonitorTicker then
        self.performanceMonitorTicker:Cancel()
        self.performanceMonitorTicker = nil
    end
    self.performanceMonitorTicker = C_Timer.NewTicker(PERF_MONITOR_TICK_SEC, function()
        local addon = _G.ShammyTime
        if not addon or not addon.IsPerformanceMonitorShown or not addon:IsPerformanceMonitorShown() then return end
        if addon.UpdatePerformanceMonitorText then addon:UpdatePerformanceMonitorText(false) end
    end)
end

function ShammyTime:HidePerformanceMonitor()
    if self.performanceMonitorTicker then
        self.performanceMonitorTicker:Cancel()
        self.performanceMonitorTicker = nil
    end
    if self.performanceMonitorFrame then
        self.performanceMonitorFrame:Hide()
    end
end

function ShammyTime:TogglePerformanceMonitor()
    if self:IsPerformanceMonitorShown() then
        self:HidePerformanceMonitor()
        return false
    end
    self:ShowPerformanceMonitor()
    return true
end

--- One-time migration from flat ShammyTimeDB to AceDB profile
function ShammyTime:MigrateOldDB()
    local old = _G.ShammyTimeDB
    if not old then return end
    if old._ace3_migrated then return end
    -- Already in AceDB shape (from a previous load)
    if old.profiles and old.profileKeys then return end

    local p = self.db.profile
    -- Ensure substructure exists
    p.global = p.global or DEFAULTS.profile.global
    p.modules = p.modules or {}
    for name, def in pairs(DEFAULTS.profile.modules) do
        if not p.modules[name] then p.modules[name] = {} end
        for k, v in pairs(def) do
            if p.modules[name][k] == nil then p.modules[name][k] = v end
        end
    end

    -- Copy flat keys from old DB into profile (and sync into modules/global where applicable)
    for k, v in pairs(old) do
        if k == "_ace3_migrated" or k == "_migrated" then
            -- skip
        elseif k == "locked" then
            p.locked = v
            p.global.locked = (v == true)
        elseif k == "wfRadialEnabled" then
            p.wfRadialEnabled = v
            if p.modules.windfuryBubbles then p.modules.windfuryBubbles.enabled = (v ~= false) end
        elseif k == "wfTotemBarEnabled" then
            p.wfTotemBarEnabled = v
            if p.modules.totemBar then p.modules.totemBar.enabled = (v ~= false) end
        elseif k == "wfFocusEnabled" then
            p.wfFocusEnabled = v
            if p.modules.shamanisticFocus then p.modules.shamanisticFocus.enabled = (v ~= false) end
        elseif k == "wfImbueBarEnabled" then
            p.wfImbueBarEnabled = v
            if p.modules.weaponImbueBar then p.modules.weaponImbueBar.enabled = (v ~= false) end
        elseif k == "wfShieldEnabled" then
            p.wfShieldEnabled = v
            if p.modules.shieldIndicator then p.modules.shieldIndicator.enabled = (v ~= false) end
        elseif k == "wfRadialScale" then
            p.wfRadialScale = v
            if p.modules.windfuryBubbles then p.modules.windfuryBubbles.scale = v end
        elseif k == "wfTotemBarScale" then
            p.wfTotemBarScale = v
            if p.modules.totemBar then p.modules.totemBar.scale = v end
        elseif k == "shieldScale" then
            p.shieldScale = v
            if p.modules.shieldIndicator then p.modules.shieldIndicator.scale = v end
        elseif k == "imbueBarScale" then
            p.imbueBarScale = v
            if p.modules.weaponImbueBar then p.modules.weaponImbueBar.scale = v end
        elseif k == "focusFrame" then
            if type(v) == "table" then p.focusFrame = v end
            if p.modules.shamanisticFocus and type(v) == "table" then
                p.modules.shamanisticFocus.pos = p.modules.shamanisticFocus.pos or {}
                p.modules.shamanisticFocus.pos.x = v.x or 0
                p.modules.shamanisticFocus.pos.y = v.y or -150
                p.modules.shamanisticFocus.scale = v.scale or 1.17
            end
        elseif type(v) ~= "table" or k == "wfSession" or k == "wfLastPull" or k == "wfRadialPos" then
            p[k] = v
        end
    end

    old._ace3_migrated = true
    print("|cff00ff00ShammyTime:|r Settings migrated to Ace3 format.")
end

--- Centralized fade evaluation: given module name and game context, returns whether to fade, target alpha, and use slow animation.
--- @param moduleName string One of: windfuryBubbles, totemBar, shamanisticFocus, weaponImbueBar, shieldIndicator, windfuryIcd, staggerBar, pressureVisual
--- @param context table { inCombat, hasTarget, hasEnemyTarget, hasTotems, noTotemsFaded, focusActive, imbueActive, imbueShortTime, wfProcced, procAnimPlaying, hasShield, shieldCharges, outOfRange, hasWindfury, pressureActive }
--- @return boolean shouldFade, number targetAlpha, boolean useSlowFade
function ShammyTime:EvaluateFade(moduleName, context)
    local p = self.db and self.db.profile
    if not p or not p.modules or not p.modules[moduleName] then
        return false, 1, false
    end
    local mod = p.modules[moduleName]
    local fade = mod.fade
    if not fade or not fade.enabled then
        return false, 1, false
    end
    local cond = fade.conditions or {}
    local inactiveAlpha = (type(fade.inactiveAlpha) == "number") and fade.inactiveAlpha or 0
    local shouldFade = false

    if cond.outOfCombat and not context.inCombat then
        if moduleName == "pressureVisual" then
            -- Keep pressure visible until it fully runs out of steam.
            if not context.pressureActive then
                shouldFade = true
            end
        else
            shouldFade = true
        end
    end
    if cond.noTarget and not context.hasTarget then
        shouldFade = true
    end
    if cond.fadeInOnTarget and not context.hasEnemyTarget then
        shouldFade = true
    end
    if cond.noTotemsPlaced and (not context.hasTotems or context.noTotemsFaded) then
        shouldFade = true
    end
    if cond.inactiveBuff then
        if moduleName == "shamanisticFocus" and not context.focusActive then
            shouldFade = true
        elseif moduleName == "weaponImbueBar" then
            -- Only fade when an imbue IS active but has plenty of time left.
            -- When no imbue is registered at all, keep the bar visible so the
            -- player notices they need to apply one.
            -- When dual-wielding and one weapon is missing an imbue, never fade
            -- so the player is reminded to apply the missing imbue.
            if context.imbueMissingDW then
                shouldFade = false  -- override: always visible when a weapon is unimbued
            elseif context.imbueActive and not context.imbueShortTime then
                shouldFade = true
            end
        elseif moduleName == "windfuryBubbles" and not context.wfProcced and not context.procAnimPlaying then
            shouldFade = true
        elseif moduleName == "shieldIndicator" and not context.hasShield then
            shouldFade = true
        elseif moduleName == "windfuryIcd" and not context.hasWindfury then
            shouldFade = true
        elseif moduleName == "pressureVisual" and not context.pressureActive then
            shouldFade = true
        end
    end
    if cond.hideWhenActive then
        if moduleName == "shieldIndicator" and context.hasShield and (context.shieldCharges or 0) >= 1 then
            shouldFade = true
        end
    end
    if cond.outOfRange and context.outOfRange then
        shouldFade = true
    end

    return shouldFade, shouldFade and inactiveAlpha or 1, true
end

-- Sync flat keys TO profile.modules (reverse of ApplyAllConfigs sync)
-- Call this after slash commands modify flat keys so the options panel sees updated values.
-- opts.includeFade = false skips legacy fade flag sync (preserves per-module fade settings).
function ShammyTime:SyncFlatToModules(opts)
    local p = self.db and self.db.profile
    if not p then return end
    opts = opts or {}
    local includeFade = (opts.includeFade ~= false)
    p.modules = p.modules or {}
    if not p.modules.pressureVisual then
        p.modules.pressureVisual = moduleDefaults(true, 0.8, 1.0)
    end
    p.global = p.global or {}

    -- Enabled flags: flat → modules
    if p.modules.windfuryBubbles then
        p.modules.windfuryBubbles.enabled = (p.wfRadialEnabled ~= false)
    end
    if p.modules.totemBar then
        p.modules.totemBar.enabled = (p.wfTotemBarEnabled ~= false)
    end
    if p.modules.shamanisticFocus then
        p.modules.shamanisticFocus.enabled = (p.wfFocusEnabled ~= false)
    end
    if p.modules.weaponImbueBar then
        p.modules.weaponImbueBar.enabled = (p.wfImbueBarEnabled ~= false)
    end
    if p.modules.shieldIndicator then
        p.modules.shieldIndicator.enabled = (p.wfShieldEnabled ~= false)
    end
    if p.modules.windfuryIcd then
        p.modules.windfuryIcd.enabled = (p.wfIcdEnabled ~= false)
    end
    if p.modules.staggerBar then
        p.modules.staggerBar.enabled = (p.staggerBarEnabled ~= false)
    end
    if p.modules.pressureVisual then
        p.modules.pressureVisual.enabled = (p.pressureEnabled ~= false)
    end

    -- Scale: flat → modules
    if p.modules.windfuryBubbles and p.wfRadialScale then
        p.modules.windfuryBubbles.scale = p.wfRadialScale
    end
    if p.modules.totemBar and p.wfTotemBarScale then
        p.modules.totemBar.scale = p.wfTotemBarScale
    end
    if p.modules.shieldIndicator and p.shieldScale then
        p.modules.shieldIndicator.scale = p.shieldScale
    end
    if p.modules.weaponImbueBar and p.imbueBarScale then
        p.modules.weaponImbueBar.scale = p.imbueBarScale
    end
    if p.modules.pressureVisual and p.pressureScale then
        p.modules.pressureVisual.scale = p.pressureScale
    end

    -- Shamanistic Focus: flat focusFrame → modules
    if p.modules.shamanisticFocus and p.focusFrame then
        p.modules.shamanisticFocus.pos = p.modules.shamanisticFocus.pos or {}
        if p.focusFrame.x ~= nil then p.modules.shamanisticFocus.pos.x = p.focusFrame.x end
        if p.focusFrame.y ~= nil then p.modules.shamanisticFocus.pos.y = p.focusFrame.y end
        if p.focusFrame.point then p.modules.shamanisticFocus.pos.point = p.focusFrame.point end
        if p.focusFrame.relativePoint then p.modules.shamanisticFocus.pos.relPoint = p.focusFrame.relativePoint end
        if p.focusFrame.scale then p.modules.shamanisticFocus.scale = p.focusFrame.scale end
    end

    -- Global: flat → global
    p.global.locked = (p.locked == true)

    if includeFade then
        -- Fade conditions: flat → modules.*.fade.conditions
        -- Note: The options panel uses per-module fade conditions, but slash commands use global fade flags.
        -- We sync the global flags to all relevant modules for consistency.
        if p.modules.windfuryBubbles then
            p.modules.windfuryBubbles.fade = p.modules.windfuryBubbles.fade or {}
            p.modules.windfuryBubbles.fade.conditions = p.modules.windfuryBubbles.fade.conditions or {}
            p.modules.windfuryBubbles.fade.conditions.outOfCombat = (p.wfFadeOutOfCombat == true)
            p.modules.windfuryBubbles.fade.conditions.inactiveBuff = (p.wfFadeWhenNotProcced == true)
            -- Enable fade if any legacy condition is on
            p.modules.windfuryBubbles.fade.enabled = p.wfFadeOutOfCombat or p.wfFadeWhenNotProcced or p.modules.windfuryBubbles.fade.enabled or false
        end
        if p.modules.totemBar then
            p.modules.totemBar.fade = p.modules.totemBar.fade or {}
            p.modules.totemBar.fade.conditions = p.modules.totemBar.fade.conditions or {}
            p.modules.totemBar.fade.conditions.outOfCombat = (p.wfFadeOutOfCombat == true)
            p.modules.totemBar.fade.conditions.noTotemsPlaced = (p.wfFadeWhenNoTotems == true)
            p.modules.totemBar.fade.enabled = p.wfFadeOutOfCombat or p.wfFadeWhenNoTotems or p.modules.totemBar.fade.enabled or false
        end
        if p.modules.shamanisticFocus then
            p.modules.shamanisticFocus.fade = p.modules.shamanisticFocus.fade or {}
            p.modules.shamanisticFocus.fade.conditions = p.modules.shamanisticFocus.fade.conditions or {}
            p.modules.shamanisticFocus.fade.conditions.outOfCombat = (p.wfFadeOutOfCombat == true)
            p.modules.shamanisticFocus.fade.conditions.inactiveBuff = (p.wfFocusFadeWhenNotProcced == true)
            p.modules.shamanisticFocus.fade.enabled = p.wfFadeOutOfCombat or p.wfFocusFadeWhenNotProcced or p.modules.shamanisticFocus.fade.enabled or false
        end
        if p.modules.weaponImbueBar then
            p.modules.weaponImbueBar.fade = p.modules.weaponImbueBar.fade or {}
            p.modules.weaponImbueBar.fade.conditions = p.modules.weaponImbueBar.fade.conditions or {}
            p.modules.weaponImbueBar.fade.conditions.outOfCombat = (p.wfFadeOutOfCombat == true)
            p.modules.weaponImbueBar.fade.conditions.inactiveBuff = (p.wfImbueFadeWhenLongDuration == true)
            p.modules.weaponImbueBar.fade.enabled = p.wfFadeOutOfCombat or p.wfImbueFadeWhenLongDuration or p.modules.weaponImbueBar.fade.enabled or false
        end
        if p.modules.shieldIndicator then
            p.modules.shieldIndicator.fade = p.modules.shieldIndicator.fade or {}
            p.modules.shieldIndicator.fade.conditions = p.modules.shieldIndicator.fade.conditions or {}
            p.modules.shieldIndicator.fade.conditions.outOfCombat = (p.wfFadeOutOfCombat == true)
            p.modules.shieldIndicator.fade.enabled = p.wfFadeOutOfCombat or p.modules.shieldIndicator.fade.enabled or false
        end
        if p.modules.windfuryIcd then
            p.modules.windfuryIcd.fade = p.modules.windfuryIcd.fade or {}
            p.modules.windfuryIcd.fade.conditions = p.modules.windfuryIcd.fade.conditions or {}
            p.modules.windfuryIcd.fade.conditions.outOfCombat = (p.wfFadeOutOfCombat == true)
            p.modules.windfuryIcd.fade.enabled = p.wfFadeOutOfCombat or p.modules.windfuryIcd.fade.enabled or false
        end
        if p.modules.staggerBar then
            p.modules.staggerBar.fade = p.modules.staggerBar.fade or {}
            p.modules.staggerBar.fade.conditions = p.modules.staggerBar.fade.conditions or {}
            p.modules.staggerBar.fade.conditions.outOfCombat = (p.wfFadeOutOfCombat == true)
            p.modules.staggerBar.fade.enabled = p.wfFadeOutOfCombat or p.modules.staggerBar.fade.enabled or false
        end
        if p.modules.pressureVisual then
            p.modules.pressureVisual.fade = p.modules.pressureVisual.fade or {}
            p.modules.pressureVisual.fade.conditions = p.modules.pressureVisual.fade.conditions or {}
            p.modules.pressureVisual.fade.conditions.outOfCombat = (p.wfFadeOutOfCombat == true)
            p.modules.pressureVisual.fade.enabled = p.wfFadeOutOfCombat or p.modules.pressureVisual.fade.enabled or false
        end
    end
end

--- Apply all module configs (call after option change or reset)
function ShammyTime:ApplyAllConfigs()
    local p = self.db.profile
    p.global = p.global or { locked = false, demoMode = false, masterScale = 1, masterAlpha = 1, devMode = false }
    p.modules = p.modules or {}
    if not p.modules.pressureVisual then
        p.modules.pressureVisual = moduleDefaults(true, 0.8, 1.0)
    end
    -- Ensure flat enabled keys exist so Shamanistic Focus etc. show for old profiles that never had them
    if p.wfRadialEnabled == nil then p.wfRadialEnabled = false end
    if p.wfTotemBarEnabled == nil then p.wfTotemBarEnabled = true end
    if p.wfFocusEnabled == nil then p.wfFocusEnabled = true end
    if p.wfImbueBarEnabled == nil then p.wfImbueBarEnabled = true end
    if p.wfShieldEnabled == nil then p.wfShieldEnabled = true end
    if p.wfImpactEnabled == nil then p.wfImpactEnabled = true end
    if p.wfIcdEnabled == nil then p.wfIcdEnabled = true end
    if p.staggerBarEnabled == nil then p.staggerBarEnabled = true end
    if p.pressureEnabled == nil then p.pressureEnabled = true end
    if p.fontShieldCount == nil then p.fontShieldCount = p.fontImbueTimer or 86 end
    -- Sync flat keys from modules so existing code sees them
    if p.modules then
        if p.modules.windfuryBubbles then p.wfRadialEnabled = (p.modules.windfuryBubbles.enabled ~= false) end
        if p.modules.totemBar then p.wfTotemBarEnabled = (p.modules.totemBar.enabled ~= false) end
        if p.modules.shamanisticFocus then p.wfFocusEnabled = (p.modules.shamanisticFocus.enabled ~= false) end
        if p.modules.weaponImbueBar then p.wfImbueBarEnabled = (p.modules.weaponImbueBar.enabled ~= false) end
        if p.modules.shieldIndicator then p.wfShieldEnabled = (p.modules.shieldIndicator.enabled ~= false) end
        if p.modules.wfImpact then p.wfImpactEnabled = (p.modules.wfImpact.enabled ~= false) end
        if p.modules.windfuryIcd then p.wfIcdEnabled = (p.modules.windfuryIcd.enabled ~= false) end
        if p.modules.staggerBar then p.staggerBarEnabled = (p.modules.staggerBar.enabled ~= false) end
        if p.modules.pressureVisual then p.pressureEnabled = (p.modules.pressureVisual.enabled ~= false) end
        if p.modules.windfuryBubbles then p.wfRadialScale = p.modules.windfuryBubbles.scale or p.wfRadialScale end
        if p.modules.totemBar then p.wfTotemBarScale = p.modules.totemBar.scale or p.wfTotemBarScale end
        if p.modules.shieldIndicator then p.shieldScale = p.modules.shieldIndicator.scale or p.shieldScale end
        if p.modules.weaponImbueBar then p.imbueBarScale = p.modules.weaponImbueBar.scale or p.imbueBarScale end
        if p.modules.pressureVisual then p.pressureScale = p.modules.pressureVisual.scale or p.pressureScale end
        -- Sync font sizes between flat keys and modules (flat values win when set)
        local function clampFont(v) return (type(v)=="number" and v>=6 and v<=64) and v or nil end
        if p.modules.totemBar then
            p.modules.totemBar.font = p.modules.totemBar.font or {}
            if type(p.fontTotemTimer) == "number" then
                local sz = clampFont(p.fontTotemTimer)
                if sz then p.modules.totemBar.font.size = sz end
            elseif p.modules.totemBar.font.size then
                local sz = clampFont(p.modules.totemBar.font.size)
                if sz then p.fontTotemTimer = sz end
            end
        end
        if p.modules.weaponImbueBar then
            p.modules.weaponImbueBar.font = p.modules.weaponImbueBar.font or {}
            if type(p.fontImbueTimer) == "number" then
                local sz = clampFont(p.fontImbueTimer)
                if sz then p.modules.weaponImbueBar.font.size = sz end
            elseif p.modules.weaponImbueBar.font.size then
                local sz = clampFont(p.modules.weaponImbueBar.font.size)
                if sz then p.fontImbueTimer = sz end
            end
        end
        -- Sync shamanistic focus: focusFrame is authoritative for position (drag
        -- saves there), modules.pos is kept in sync for the options panel.
        -- Previous code synced modules.pos → focusFrame, which overwrote the
        -- user's saved position with AceDB defaults when modules.pos was never
        -- explicitly written (only drag writes to focusFrame). Fix: sync the
        -- other direction (focusFrame → modules.pos) for position, and keep
        -- modules → focusFrame for scale (set by the options panel slider).
        if p.modules.shamanisticFocus then
            p.focusFrame = p.focusFrame or {}
            p.modules.shamanisticFocus.pos = p.modules.shamanisticFocus.pos or {}
            local pos = p.modules.shamanisticFocus.pos
            local ff = p.focusFrame
            -- Position: focusFrame → modules.pos
            if ff.x ~= nil then pos.x = ff.x end
            if ff.y ~= nil then pos.y = ff.y end
            if ff.point then pos.point = ff.point end
            if ff.relativePoint then pos.relPoint = ff.relativePoint end
            -- Scale: modules → focusFrame (options panel writes here)
            p.focusFrame.scale = p.modules.shamanisticFocus.scale or p.focusFrame.scale
        end
    end
    if p.global then
        p.locked = (p.global.locked == true)
    end

    -- Ensure all frames exist before applying config (frames may not exist if opened options before PLAYER_LOGIN)
    if ShammyTime.EnsureCenterRingExists then ShammyTime.EnsureCenterRingExists() end
    if ShammyTime.EnsureWindfuryTotemBarFrame then ShammyTime.EnsureWindfuryTotemBarFrame() end
    if ShammyTime.EnsureImbueBarFrame then ShammyTime.EnsureImbueBarFrame() end
    if ShammyTime.EnsureShieldFrame then ShammyTime.EnsureShieldFrame() end
    if ShammyTime.GetShamanisticFocusFrame then ShammyTime.GetShamanisticFocusFrame() end
    if ShammyTime.EnsureWindfuryICDFrame then ShammyTime.EnsureWindfuryICDFrame() end
    if ShammyTime.EnsureStaggerBarFrame then ShammyTime.EnsureStaggerBarFrame() end
    if ShammyTime.EnsurePressureFrame then ShammyTime.EnsurePressureFrame() end

    -- Call each module's ApplyConfig() so scale/alpha/position from profile.modules are applied (spec)
    if self.Modules then
        for _, mod in pairs(self.Modules) do
            if mod.ApplyConfig then mod:ApplyConfig() end
        end
    end

    -- Clear fade cache on all module frames so UpdateAllElementsFadeState() re-evaluates from scratch.
    -- ApplyConfig() above resets frame alpha without updating _stFadeTarget, which would cause the
    -- fade system to think the frame is already at the correct alpha and skip the update.
    local framesToClearCache = {
        _G.ShammyTimeWindfuryRadial,
        _G.ShammyTimeWindfuryTotemBarFrame,
        _G.ShammyTimeImbueBarFrame,
        _G.ShammyTimeShieldFrame,
        ShammyTime.GetShamanisticFocusFrame and ShammyTime.GetShamanisticFocusFrame() or nil,
        ShammyTime.GetWindfuryICDFrame and ShammyTime.GetWindfuryICDFrame() or nil,
        _G.ShammyTimeStaggerBarFrame,
        ShammyTime.GetPressureFrame and ShammyTime.GetPressureFrame() or nil,
    }
    for _, frame in ipairs(framesToClearCache) do
        if frame then frame._stFadeTarget = nil end
    end

    if self.ApplyElementVisibility then self:ApplyElementVisibility() end
    if self.ApplyErrorTextSetting then self:ApplyErrorTextSetting() end
    if self.ApplyLockStateToAllFrames then self:ApplyLockStateToAllFrames() end
    if self.ApplyElementMouseState then self:ApplyElementMouseState() end
    -- Scale/position for imbue, shield, focus are applied by each module's ApplyConfig (with master scale). Do not re-apply here or master scale would be overwritten.
    if ShammyTime.ApplyCenterRingFontSizes then ShammyTime.ApplyCenterRingFontSizes() end
    if ShammyTime.ApplyTotemBarFontSize then ShammyTime.ApplyTotemBarFontSize() end
    if ShammyTime.ApplyImbueBarFontSize then ShammyTime.ApplyImbueBarFontSize() end
    if ShammyTime.ApplyShieldCountSettings then ShammyTime.ApplyShieldCountSettings() end
    if ShammyTime.RefreshImbueBar then ShammyTime.RefreshImbueBar() end
    if ShammyTime.ApplySatelliteRadius then ShammyTime.ApplySatelliteRadius() end
    if ShammyTime.ApplySatelliteBubbleScale then ShammyTime.ApplySatelliteBubbleScale() end
    if ShammyTime.ApplyPressureTuningSettings then ShammyTime.ApplyPressureTuningSettings() end
    if ShammyTime.RefreshPressureDebugMetrics then ShammyTime.RefreshPressureDebugMetrics() end
    if ShammyTime.ApplyPressurePopupDevSettings then ShammyTime.ApplyPressurePopupDevSettings() end
    if self.UpdateAllElementsFadeState then self:UpdateAllElementsFadeState() end
end

--------------------------------------------------------------------------------
-- Presets: quickly switch between "always visible" and "smart fade" configs
--------------------------------------------------------------------------------

--- Preset: Always Visible – disable all fade settings so every module stays on screen.
function ShammyTime:ApplyPresetAlwaysVisible()
    local p = self.db and self.db.profile
    if not p or not p.modules then return end
    local moduleNames = { "windfuryBubbles", "totemBar", "shamanisticFocus", "weaponImbueBar", "shieldIndicator", "windfuryIcd", "staggerBar", "pressureVisual" }
    for _, name in ipairs(moduleNames) do
        local m = p.modules[name]
        if m then
            m.fade = m.fade or {}
            m.fade.enabled = false
            m.fade.inactiveAlpha = 0
            m.fade.conditions = m.fade.conditions or {}
            m.fade.conditions.outOfCombat = false
            m.fade.conditions.noTarget = false
            m.fade.conditions.inactiveBuff = false
            m.fade.conditions.noTotemsPlaced = false
            m.fade.conditions.outOfRange = false
            m.fade.conditions.fadeInOnTarget = false
        end
    end
    -- Sync legacy flat keys
    p.wfFadeOutOfCombat = false
    p.wfFadeWhenNotProcced = false
    p.wfFocusFadeWhenNotProcced = false
    p.wfFadeWhenNoTotems = false
    p.wfImbueFadeWhenLongDuration = false
    -- Stagger bar: always show (bypasses smart hide)
    p.staggerBarAlwaysShow = true
    self:ApplyAllConfigs()
    print("|cff00ff00ShammyTime:|r Preset applied: |cffffffffAlways Visible|r – all fade disabled.")
end

--- Preset: Smart Fade – context-aware fading so modules disappear when irrelevant.
--- Matches the recommended settings:
---   Shamanistic Focus  → fade when buff not active
---   Totem Bar          → fade when no totems placed (5s delay)
---   Weapon Imbue Bar   → fade when no short-duration imbue (threshold 120s)
---   Shield Indicator   → fade when out of combat
---   Windfury Bubbles   → fade when not recently procced
---   Pressure Visual    → fade when out of combat or no recent pressure activity
function ShammyTime:ApplyPresetSmartFade()
    local p = self.db and self.db.profile
    if not p or not p.modules then return end

    -- Shamanistic Focus: fade when buff not active
    local sf = p.modules.shamanisticFocus
    if sf then
        sf.fade = sf.fade or {}
        sf.fade.enabled = true
        sf.fade.inactiveAlpha = 0
        sf.fade.conditions = sf.fade.conditions or {}
        sf.fade.conditions.outOfCombat = false
        sf.fade.conditions.noTarget = false
        sf.fade.conditions.inactiveBuff = true
        sf.fade.conditions.fadeInOnTarget = false
    end

    -- Totem Bar: fade when no totems placed
    local tb = p.modules.totemBar
    if tb then
        tb.fade = tb.fade or {}
        tb.fade.enabled = true
        tb.fade.inactiveAlpha = 0
        tb.fade.conditions = tb.fade.conditions or {}
        tb.fade.conditions.outOfCombat = false
        tb.fade.conditions.noTarget = false
        tb.fade.conditions.inactiveBuff = false
        tb.fade.conditions.noTotemsPlaced = true
        tb.fade.conditions.outOfRange = false
    end
    p.wfNoTotemsFadeDelay = 5

    -- Weapon Imbue Bar: fade when no short-duration imbue
    local wb = p.modules.weaponImbueBar
    if wb then
        wb.fade = wb.fade or {}
        wb.fade.enabled = true
        wb.fade.inactiveAlpha = 0
        wb.fade.conditions = wb.fade.conditions or {}
        wb.fade.conditions.outOfCombat = false
        wb.fade.conditions.noTarget = false
        wb.fade.conditions.inactiveBuff = true
    end
    p.wfImbueFadeThresholdSec = 120

    -- Shield Indicator: fade when out of combat
    local si = p.modules.shieldIndicator
    if si then
        si.fade = si.fade or {}
        si.fade.enabled = true
        si.fade.inactiveAlpha = 0
        si.fade.conditions = si.fade.conditions or {}
        si.fade.conditions.outOfCombat = true
        si.fade.conditions.noTarget = false
        si.fade.conditions.inactiveBuff = false
    end

    -- Windfury Bubbles: fade when not recently procced
    local wf = p.modules.windfuryBubbles
    if wf then
        wf.fade = wf.fade or {}
        wf.fade.enabled = true
        wf.fade.inactiveAlpha = 0
        wf.fade.conditions = wf.fade.conditions or {}
        wf.fade.conditions.outOfCombat = false
        wf.fade.conditions.noTarget = false
        wf.fade.conditions.inactiveBuff = true
        wf.fade.conditions.fadeInOnTarget = false
    end

    -- Windfury ICD: fade when out of combat
    local icd = p.modules.windfuryIcd
    if icd then
        icd.fade = icd.fade or {}
        icd.fade.enabled = true
        icd.fade.inactiveAlpha = 0
        icd.fade.conditions = icd.fade.conditions or {}
        icd.fade.conditions.outOfCombat = true
        icd.fade.conditions.noTarget = false
        icd.fade.conditions.inactiveBuff = false
    end

    -- Stagger Bar: fade when out of combat
    local sb = p.modules.staggerBar
    if sb then
        sb.fade = sb.fade or {}
        sb.fade.enabled = true
        sb.fade.inactiveAlpha = 0
        sb.fade.conditions = sb.fade.conditions or {}
        sb.fade.conditions.outOfCombat = true
        sb.fade.conditions.noTarget = false
        sb.fade.conditions.inactiveBuff = false
    end

    -- Pressure visual: fade when out of combat or no recent pressure activity
    local pv = p.modules.pressureVisual
    if pv then
        pv.fade = pv.fade or {}
        pv.fade.enabled = true
        pv.fade.inactiveAlpha = 0
        pv.fade.conditions = pv.fade.conditions or {}
        pv.fade.conditions.outOfCombat = true
        pv.fade.conditions.noTarget = false
        pv.fade.conditions.inactiveBuff = true
        pv.fade.conditions.fadeInOnTarget = false
    end

    -- Sync legacy flat keys
    p.wfFadeOutOfCombat = false
    p.wfFadeWhenNotProcced = true
    p.wfFocusFadeWhenNotProcced = true
    p.wfFadeWhenNoTotems = true
    p.wfImbueFadeWhenLongDuration = true
    -- Stagger bar: use smart hide (not always visible)
    p.staggerBarAlwaysShow = false

    self:ApplyAllConfigs()
    print("|cff00ff00ShammyTime:|r Preset applied: |cffffffffSmart Fade|r – modules fade when not needed.")
end

--- Reset all to defaults
function ShammyTime:ResetAllToDefaults()
    self.db:ResetProfile()
    self:ApplyAllConfigs()
    -- Hook for ShammyTime.lua to reset in-memory state (wfSession, wfPull, etc.)
    if self.OnResetAll then self:OnResetAll() end
    print("|cff00ff00ShammyTime:|r All settings reset to defaults.")
end

--- Deep copy a table (for resetting nested defaults like fade.conditions)
local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

-- Flat DB keys that belong to each module's options tab (reset with module).
local MODULE_RESET_FLAT_KEYS = {
    windfuryBubbles = {
        "wfAlwaysShowNumbers",
        "fontCircleTitle",
        "fontCircleTotal",
        "fontCircleCritical",
        "fontSatelliteLabel",
        "fontSatelliteValue",
    },
    totemBar = {
        "fontTotemTimer",
        "wfNoTotemsFadeDelay",
    },
    weaponImbueBar = {
        "fontImbueTimer",
        "wfImbueFadeThresholdSec",
    },
    shieldIndicator = {
        "fontShieldCount",
    },
    windfuryIcd = {},
    staggerBar = {
        "staggerBarAlwaysShow",
        "staggerBarWidth",
        "staggerBarHeight",
        "staggerBarGap",
        "staggerBarsX",
        "staggerBarsY",
        "staggerDeltaFontSize",
        "staggerDeltaX",
        "staggerDeltaY",
        "staggerHelperFontSize",
        "staggerHelperX",
        "staggerHelperY",
        "staggerHideDelay",
    },
    pressureVisual = {
        "pressureEnabled",
        "pressureScale",
        "pressurePopupIconSize",
        "pressurePopupTextSize",
        "pressurePopupHoldSec",
        "pressurePopupFadeSec",
        "pressurePopupSustainSec",
        "pressurePopupCritBounceScale",
        "pressurePopupCritBounceSec",
        "pressureSimpleResistance",
        "pressureSimpleRubberband",
        "pressureSimpleTierBase",
        "pressureSimpleTierStepPct",
        "pressureSimpleTierHelp",
        "pressureSimpleOverdrivePercentile",
        "pressureSimpleOverdriveMultiplier",
        "pressureSimpleTierHoldSec",
        "pressureSimpleShakeAmount",
        "pressureSimpleShakeFromDamage",
        -- Legacy pressure tuning keys (removed from UI, cleared on module reset)
        "pressureFeelMass",
        "pressureFeelResistanceScale",
        "pressureFeelRubberDropSec",
        "pressureFeelRubberDamping",
        "pressureFeelRubberOscillations",
        "pressureFeelRubberLandingFloor",
        "pressureFeelTierHelpScale",
        "pressureFeelShakeAmount",
        "pressureFeelShakeDamageScale",
        "pressureOverloadThreshold",
        "pressureOverloadTierBoost",
        "pressureOverloadCooldownSec",
        "pressureTierHoldMinSec",
        "pressureTierConcavityDepth",
        "pressureTierMomentumOnPromote",
        "pressureTierMomentumPerTier",
        "pressureTierMomentumMax",
        "pressureTierMomentumDecayTau",
        "pressureTierMomentumIdleDecayTau",
        "pressureTierDamageReq1",
        "pressureTierDamageReq2",
        "pressureTierDamageReq3",
        "pressureTierDamageReq4",
        "pressureTierDamageReq5",
        "pressureTierForceReq1",
        "pressureTierForceReq2",
        "pressureTierForceReq3",
        "pressureTierForceReq4",
        "pressureTierForceReq5",
    },
}

--- Reset a single module to defaults
function ShammyTime:ResetModule(moduleName)
    local def = DEFAULTS.profile.modules[moduleName]
    if not def then return end
    -- Replace the module table with a fresh deep copy of defaults
    self.db.profile.modules[moduleName] = DeepCopy(def)
    -- Reset flat keys that are part of this module's options
    local p = self.db.profile
    local defaults = DEFAULTS.profile
    local flatKeys = MODULE_RESET_FLAT_KEYS[moduleName]
    if p and flatKeys then
        for _, key in ipairs(flatKeys) do
            if defaults[key] == nil then
                p[key] = nil
            else
                p[key] = DeepCopy(defaults[key])
            end
        end
    end
    self:ApplyAllConfigs()
    print("|cff00ff00ShammyTime:|r " .. tostring(moduleName) .. " reset to defaults.")
end

--- Demo: play module preview then stop after 5s
function ShammyTime:DemoModule(moduleName)
    -- Modules will implement DemoStart/DemoStop; here we just trigger and schedule stop
    local mod = self.Modules and self.Modules[moduleName]
    if mod and mod.DemoStart then
        mod:DemoStart()
        C_Timer.After(5, function()
            if mod.DemoStop then mod:DemoStop() end
            if mod.ApplyConfig then mod:ApplyConfig() end
            self:ApplyAllConfigs()
        end)
    end
end

--- Play full demo sequence (all modules over ~12s). If profile.global.demoMode is true, restarts after 12s (loop).
function ShammyTime:PlayDemo()
    local addon = self  -- Capture for closures
    addon.demoActive = true
    if addon.UpdateAllElementsFadeState then addon:UpdateAllElementsFadeState() end
    local order = { "windfuryBubbles", "totemBar", "shamanisticFocus", "weaponImbueBar", "shieldIndicator", "windfuryIcd", "staggerBar", "pressureVisual" }
    for i, name in ipairs(order) do
        C_Timer.After((i - 1) * 2, function()
            if not addon.demoActive then return end
            local mod = addon.Modules and addon.Modules[name]
            if mod and mod.DemoStart then mod:DemoStart() end
        end)
    end
    C_Timer.After(12, function()
        local p = addon.db and addon.db.profile
        local loop = p and p.global and p.global.demoMode
        if loop and addon.demoActive then
            addon:PlayDemo()
        else
            addon:StopDemo()
        end
    end)
end

--- Save current on-screen position of all draggable elements so ApplyAllConfigs doesn't move them.
function ShammyTime:SaveAllCurrentPositions()
    local posDB = self.GetRadialPositionDB and self:GetRadialPositionDB()
    if not posDB then return end
    local function saveFramePos(frame, key)
        if not frame or not frame.GetPoint then return end
        local point, relTo, relativePoint, x, y = frame:GetPoint(1)
        posDB[key] = {
            point = point,
            relativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent",
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
    end
    local wrapper = _G.ShammyTimeWindfuryRadial
    if wrapper then saveFramePos(wrapper, "center") end
    local totemBar = _G.ShammyTimeWindfuryTotemBarFrame
    if totemBar then saveFramePos(totemBar, "totemBar") end
    local imbueBar = _G.ShammyTimeImbueBarFrame
    if imbueBar then saveFramePos(imbueBar, "imbueBar") end
    local shield = _G.ShammyTimeShieldFrame
    if shield then saveFramePos(shield, "shieldFrame") end
    local staggerBar = _G.ShammyTimeStaggerBarFrame
    if staggerBar then saveFramePos(staggerBar, "staggerBar") end
    local focusFrame = self.GetShamanisticFocusFrame and self:GetShamanisticFocusFrame()
    if focusFrame and self.db and self.db.profile then
        local p = self.db.profile
        local point, relTo, relativePoint, x, y = focusFrame:GetPoint(1)
        p.focusFrame = p.focusFrame or {}
        local ff = p.focusFrame
        ff.point = point
        ff.relativeTo = (relTo and relTo.GetName and relTo:GetName()) or "UIParent"
        ff.relativePoint = relativePoint
        ff.x = x
        ff.y = y
        if p.modules and p.modules.shamanisticFocus then
            p.modules.shamanisticFocus.pos = p.modules.shamanisticFocus.pos or {}
            local pos = p.modules.shamanisticFocus.pos
            pos.point = point
            pos.relPoint = relativePoint
            pos.x = x
            pos.y = y
        end
    end
end

--- Stop demo: only stop animations and timers. Do NOT call layout (SetPoint, ClearAllPoints, ApplyAllConfigs, etc.).
function ShammyTime:StopDemo()
    local addon = self  -- Capture for closures
    addon.demoActive = false
    if addon.db and addon.db.profile and addon.db.profile.global then
        addon.db.profile.global.demoMode = false
    end
    -- Stop all module demos (animations/timers only; modules must not touch layout in DemoStop)
    if addon.Modules then
        for name, mod in pairs(addon.Modules) do
            if mod and mod.DemoStop then
                mod:DemoStop()
            end
        end
    end
    -- Refresh fade state (alpha only); do NOT call ApplyAllConfigs or SaveAllCurrentPositions
    if addon.UpdateAllElementsFadeState then addon:UpdateAllElementsFadeState() end
end

-- Module registry (optional; modules can register themselves)
ShammyTime.Modules = ShammyTime.Modules or {}
