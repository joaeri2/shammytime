-- ShammyTime_Core.lua
-- AceAddon init, AceDB, options hook, and ApplyAllConfigs. Uses installed Ace3 in Libs/.

local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0")
local AceDB = LibStub("AceDB-3.0")
local AceEvent = LibStub("AceEvent-3.0")

-- Create addon and expose globally (other files expect ShammyTime)
local ShammyTime = AceAddon:NewAddon("ShammyTime", "AceEvent-3.0")
_G.ShammyTime = ShammyTime

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
            shieldIndicator = moduleDefaults(true, 0.3, 1.0),
            shamanisticFocus = moduleDefaults(true, 0.9, 1.0),
            totemBar = moduleDefaults(true, 1.2, 1.0),
            weaponImbueBar = moduleDefaults(true, 0.35, 1.0),
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
        wfRadialEnabled = true,
        wfTotemBarEnabled = true,
        wfFocusEnabled = true,
        wfImbueBarEnabled = true,
        wfShieldEnabled = true,
        shieldScale = 0.3,
        shieldCount = nil,
        shieldCountX = 1,
        shieldCountY = 101,
        wfRadialScale = 0.65,
        wfSatelliteGap = -89,
        wfSatelliteBubbleScale = 1,
        wfCenterSize = 270,
        wfCenterTextTitleY = 34,
        wfCenterTextTotalY = 10,
        wfCenterTextCriticalY = -20,
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
        fontCircleTitle = 17,
        fontCircleTotal = 18,
        fontCircleCritical = 17,
        fontSatelliteLabel = 12,
        fontSatelliteValue = 17,
        fontTotemTimer = 13,
        fontImbueTimer = 28,
        fontShieldCount = 86,
        wfSatelliteLabelX = 0,
        wfSatelliteLabelY = 20,
        wfSatelliteValueX = 0,
        wfSatelliteValueY = 0,
        wfSatelliteOverrides = {
            air = { labelY = 14, valueY = -5 },
            grass = { labelY = 14, valueY = -5 },
        },
        imbueBarScale = 0.35,
        imbueBarMargin = nil,
        imbueBarGap = nil,
        imbueBarOffsetY = nil,
        wfSession = { total = 0, count = 0, procs = 0, min = nil, max = nil, crits = 0, swings = 0 },
        wfLastPull = { total = 0, count = 0, procs = 0, min = nil, max = nil, crits = 0, swings = 0 },
        wfRadialPos = {},
        focusFrame = {
            point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER",
            x = -381.49990844727, y = 0.51829099655151, scale = 0.9, locked = false,
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
    if self.ApplyAllConfigs then
        self:ApplyAllConfigs()
    end
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
                p.modules.shamanisticFocus.scale = v.scale or 0.8
            end
        elseif type(v) ~= "table" or k == "wfSession" or k == "wfLastPull" or k == "wfRadialPos" then
            p[k] = v
        end
    end

    old._ace3_migrated = true
    print("|cff00ff00ShammyTime:|r Settings migrated to Ace3 format.")
end

--- Centralized fade evaluation: given module name and game context, returns whether to fade, target alpha, and use slow animation.
--- @param moduleName string One of: windfuryBubbles, totemBar, shamanisticFocus, weaponImbueBar, shieldIndicator
--- @param context table { inCombat, hasTarget, hasEnemyTarget, hasTotems, noTotemsFaded, focusActive, imbueActive, imbueShortTime, wfProcced, procAnimPlaying, hasShield, outOfRange }
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
        shouldFade = true
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
            if not context.imbueActive or (context.imbueShortTime == false) then
                shouldFade = true
            end
        elseif moduleName == "windfuryBubbles" and not context.wfProcced and not context.procAnimPlaying then
            shouldFade = true
        elseif moduleName == "shieldIndicator" and not context.hasShield then
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
    end
end

--- Apply all module configs (call after option change or reset)
function ShammyTime:ApplyAllConfigs()
    local p = self.db.profile
    p.global = p.global or { locked = false, demoMode = false, masterScale = 1, masterAlpha = 1, devMode = false }
    -- Ensure flat enabled keys exist so Shamanistic Focus etc. show for old profiles that never had them
    if p.wfRadialEnabled == nil then p.wfRadialEnabled = true end
    if p.wfTotemBarEnabled == nil then p.wfTotemBarEnabled = true end
    if p.wfFocusEnabled == nil then p.wfFocusEnabled = true end
    if p.wfImbueBarEnabled == nil then p.wfImbueBarEnabled = true end
    if p.wfShieldEnabled == nil then p.wfShieldEnabled = true end
    if p.fontShieldCount == nil then p.fontShieldCount = p.fontImbueTimer or 86 end
    -- Sync flat keys from modules so existing code sees them
    if p.modules then
        if p.modules.windfuryBubbles then p.wfRadialEnabled = (p.modules.windfuryBubbles.enabled ~= false) end
        if p.modules.totemBar then p.wfTotemBarEnabled = (p.modules.totemBar.enabled ~= false) end
        if p.modules.shamanisticFocus then p.wfFocusEnabled = (p.modules.shamanisticFocus.enabled ~= false) end
        if p.modules.weaponImbueBar then p.wfImbueBarEnabled = (p.modules.weaponImbueBar.enabled ~= false) end
        if p.modules.shieldIndicator then p.wfShieldEnabled = (p.modules.shieldIndicator.enabled ~= false) end
        if p.modules.windfuryBubbles then p.wfRadialScale = p.modules.windfuryBubbles.scale or p.wfRadialScale end
        if p.modules.totemBar then p.wfTotemBarScale = p.modules.totemBar.scale or p.wfTotemBarScale end
        if p.modules.shieldIndicator then p.shieldScale = p.modules.shieldIndicator.scale or p.shieldScale end
        if p.modules.weaponImbueBar then p.imbueBarScale = p.modules.weaponImbueBar.scale or p.imbueBarScale end
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
        -- Sync shamanistic focus position from module pos to flat focusFrame (used by ShammyTime_ShamanisticFocus.lua)
        if p.modules.shamanisticFocus then
            p.focusFrame = p.focusFrame or {}
            local pos = p.modules.shamanisticFocus.pos
            if pos then
                p.focusFrame.x = (pos.x ~= nil) and pos.x or p.focusFrame.x
                p.focusFrame.y = (pos.y ~= nil) and pos.y or p.focusFrame.y
                p.focusFrame.point = pos.point or p.focusFrame.point
                p.focusFrame.relativePoint = pos.relPoint or p.focusFrame.relativePoint
            end
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

    -- Call each module's ApplyConfig() so scale/alpha/position from profile.modules are applied (spec)
    if self.Modules then
        for _, mod in pairs(self.Modules) do
            if mod.ApplyConfig then mod:ApplyConfig() end
        end
    end

    if self.ApplyElementVisibility then self:ApplyElementVisibility() end
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
    if self.UpdateAllElementsFadeState then self:UpdateAllElementsFadeState() end
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
    local order = { "windfuryBubbles", "totemBar", "shamanisticFocus", "weaponImbueBar", "shieldIndicator" }
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
