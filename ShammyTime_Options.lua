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
    if key == "scale" then return m.scale or 1 end
    if key == "alpha" then return m.alpha or 1 end
    if key == "fadeEnabled" then return m.fade and m.fade.enabled or false end
    if key == "inactiveAlpha" then return m.fade and m.fade.inactiveAlpha or 0 end
    if key == "outOfCombat" then return m.fade and m.fade.conditions and m.fade.conditions.outOfCombat or false end
    if key == "noTarget" then return m.fade and m.fade.conditions and m.fade.conditions.noTarget or false end
    if key == "inactiveBuff" then return m.fade and m.fade.conditions and m.fade.conditions.inactiveBuff or false end
    if key == "noTotemsPlaced" then return m.fade and m.fade.conditions and m.fade.conditions.noTotemsPlaced or false end
    if key == "outOfRange" then return m.fade and m.fade.conditions and m.fade.conditions.outOfRange or false end
    return nil
end

local function setModuleOption(info, val, key)
    local modKey = getModuleKeyFromInfo(info)
    local m = getModule(modKey)
    if not m then return end
    if key == "enabled" then m.enabled = val end
    if key == "scale" then m.scale = val end
    if key == "alpha" then m.alpha = val end
    if key == "fadeEnabled" then m.fade = m.fade or {}; m.fade.enabled = val end
    if key == "inactiveAlpha" then m.fade = m.fade or {}; m.fade.inactiveAlpha = val end
    if key == "outOfCombat" then m.fade = m.fade or {}; m.fade.conditions = m.fade.conditions or {}; m.fade.conditions.outOfCombat = val end
    if key == "noTarget" then m.fade = m.fade or {}; m.fade.conditions = m.fade.conditions or {}; m.fade.conditions.noTarget = val end
    if key == "inactiveBuff" then m.fade = m.fade or {}; m.fade.conditions = m.fade.conditions or {}; m.fade.conditions.inactiveBuff = val end
    if key == "noTotemsPlaced" then m.fade = m.fade or {}; m.fade.conditions = m.fade.conditions or {}; m.fade.conditions.noTotemsPlaced = val end
    if key == "outOfRange" then m.fade = m.fade or {}; m.fade.conditions = m.fade.conditions or {}; m.fade.conditions.outOfRange = val end
    local st = _G.ShammyTime
    if st and st.ApplyAllConfigs then st:ApplyAllConfigs() end
end

-- Getter/setter for flat DB keys (used by Developer section)
local function getFlatDB(key, default)
    local p = getDB()
    if not p then return default end
    local val = p[key]
    return val ~= nil and val or default
end

local function setFlatDB(key, val)
    local p = getDB()
    if p then p[key] = val end
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
    line("fontTotemTimer = " .. tostring(p.fontTotemTimer or 7))
    line("")
    sec("Shamanistic Focus (position and scale)")
    if p.focusFrame then
        line("focusFrame.point = " .. tostring(p.focusFrame.point or "CENTER"))
        line("focusFrame.relativeTo = " .. tostring(p.focusFrame.relativeTo or "UIParent"))
        line("focusFrame.relativePoint = " .. tostring(p.focusFrame.relativePoint or "CENTER"))
        line("focusFrame.x = " .. tostring(p.focusFrame.x or 0))
        line("focusFrame.y = " .. tostring(p.focusFrame.y or -150))
        line("focusFrame.scale = " .. tostring(p.focusFrame.scale or 0.8))
        line("focusFrame.locked = " .. tostring(p.focusFrame.locked or false))
    end
    line("")
    sec("Imbue bar (scale, layout, offsets, font)")
    line("imbueBarScale = " .. tostring(p.imbueBarScale or 0.4))
    line("imbueBarMargin = " .. tostring(p.imbueBarMargin or "nil"))
    line("imbueBarGap = " .. tostring(p.imbueBarGap or "nil"))
    line("imbueBarOffsetY = " .. tostring(p.imbueBarOffsetY or "nil"))
    line("imbueBarIconSize = " .. tostring(p.imbueBarIconSize or "nil"))
    line("fontImbueTimer = " .. tostring(p.fontImbueTimer or 20))
    line("")
    sec("Shield indicator")
    line("shieldScale = " .. tostring(p.shieldScale or 0.2))
    line("shieldCountX = " .. tostring(p.shieldCountX or 0))
    line("shieldCountY = " .. tostring(p.shieldCountY or -50))
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
local function CreateModuleOptions(moduleName, displayName, extraArgs)
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
                min = 0.1, max = 3, step = 0.05,
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
            inactiveBuff = {
                type = "toggle",
                name = "No Active Buff/Proc",
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
            preview = {
                type = "execute",
                name = "Preview",
                desc = "Play a short demo of this element.",
                order = 51,
                func = function()
                    local st = _G.ShammyTime
                    if st and st.DemoModule then st:DemoModule(moduleName) end
                end,
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
            -- GENERAL
            -----------------------------------------------------------------
            general = {
                type = "group",
                name = "General",
                order = 1,
                args = {
                    desc = {
                        type = "description",
                        name = "ShammyTime displays Windfury procs, totem timers, weapon imbues, Shamanistic Focus, and shield charges.\n",
                        order = 0,
                    },
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
                        alwaysShowNumbers = {
                            type = "toggle",
                            name = "Always Show Numbers",
                            desc = "Show statistics numbers even when not hovering (otherwise fade until mouse-over).",
                            order = 4,
                            get = function() return getFlatDB("wfAlwaysShowNumbers", false) end,
                            set = function(_, v) setFlatDB("wfAlwaysShowNumbers", v) end,
                        },
                    }),
                    totemBar = CreateModuleOptions("totemBar", "Totem Bar", {
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
                    shamanisticFocus = CreateModuleOptions("shamanisticFocus", "Shamanistic Focus"),
                    weaponImbueBar = CreateModuleOptions("weaponImbueBar", "Weapon Imbue Bar", {
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
                    shieldIndicator = CreateModuleOptions("shieldIndicator", "Shield Indicator"),
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
                    fontTotemTimer = {
                        type = "range",
                        name = "Totem Timer Font",
                        min = 4, max = 20, step = 1,
                        order = 61,
                        get = function() return getFlatDB("fontTotemTimer", 7) end,
                        set = function(_, v)
                            setFlatDB("fontTotemTimer", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyTotemBarFontSize then st.ApplyTotemBarFontSize() end
                        end,
                    },
                    fontImbueTimer = {
                        type = "range",
                        name = "Imbue Timer Font",
                        min = 6, max = 32, step = 1,
                        order = 62,
                        get = function() return getFlatDB("fontImbueTimer", 20) end,
                        set = function(_, v)
                            setFlatDB("fontImbueTimer", v)
                            local st = _G.ShammyTime
                            if st and st.RefreshImbueBar then st.RefreshImbueBar() end
                        end,
                    },
                    shieldCountX = {
                        type = "range",
                        name = "Shield Count X",
                        min = -100, max = 100, step = 1,
                        order = 63,
                        get = function() return getFlatDB("shieldCountX", 0) end,
                        set = function(_, v)
                            setFlatDB("shieldCountX", v)
                            local st = _G.ShammyTime
                            if st and st.ApplyShieldCountSettings then st.ApplyShieldCountSettings() end
                        end,
                    },
                    shieldCountY = {
                        type = "range",
                        name = "Shield Count Y",
                        min = -100, max = 100, step = 1,
                        order = 64,
                        get = function() return getFlatDB("shieldCountY", -50) end,
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
                },
            },
        },
    }

    AceConfig:RegisterOptionsTable("ShammyTime", options)
    AceConfigDialog:AddToBlizOptions("ShammyTime", "ShammyTime")
end
