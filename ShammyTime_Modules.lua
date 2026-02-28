-- ShammyTime_Modules.lua
-- Registers UI modules with ShammyTime.Modules (Create, ApplyConfig, SetEnabled, DemoStart, DemoStop)
-- so the options panel and demo system can drive them. Uses existing Ensure*/Apply* APIs.

local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

local ShammyTime = _G.ShammyTime
if not ShammyTime then return end  -- ShammyTime.db is nil at load time; that's fine, it's set in OnInitialize

ShammyTime.Modules = ShammyTime.Modules or {}

local function getModuleConfig(name)
    -- Use _G.ShammyTime to ensure we get the db that was set in OnInitialize
    local st = _G.ShammyTime
    if not st or not st.db then return nil end
    local p = st.db.profile
    if not p or not p.modules then return nil end
    return p.modules[name]
end

--- Effective scale and alpha for a module (module value * global.masterScale / masterAlpha)
local function getEffectiveScaleAlpha(moduleScale, moduleAlpha)
    -- Use _G.ShammyTime to ensure we get the db that was set in OnInitialize
    local st = _G.ShammyTime
    local p = st and st.db and st.db.profile
    if not p or not p.global then
        return moduleScale or 1, moduleAlpha or 1
    end
    local g = p.global
    local scale = (moduleScale or 1) * (g.masterScale and (g.masterScale >= 0.5 and g.masterScale <= 2) and g.masterScale or 1)
    local alpha = (moduleAlpha or 1) * (g.masterAlpha and (g.masterAlpha >= 0 and g.masterAlpha <= 1) and g.masterAlpha or 1)
    return scale, alpha
end

--- Return effective alpha for a module (for fade state so user's alpha is respected)
local function GetModuleEffectiveAlpha(moduleName)
    local cfg = getModuleConfig(moduleName)
    if not cfg then return 1 end
    local _, effAlpha = getEffectiveScaleAlpha(cfg.scale or 1, cfg.alpha or 1)
    return effAlpha
end
-- Expose as both a method (self:GetModuleEffectiveAlpha) and a function (ShammyTime.GetModuleEffectiveAlpha)
ShammyTime.GetModuleEffectiveAlpha = GetModuleEffectiveAlpha

-- ---------------------------------------------------------------------------
-- Windfury Bubbles (center ring + satellites)
-- ---------------------------------------------------------------------------
local windfuryBubbles = {
    frame = nil,  -- set in Create; center ring is the main frame
    demoTimer = nil,
}

function windfuryBubbles:Create()
    if ShammyTime.EnsureCenterRingExists then ShammyTime.EnsureCenterRingExists() end
    if ShammyTime.ShowAllSatellites then ShammyTime.ShowAllSatellites() end
    self.frame = _G.ShammyTimeCenterRing
    return self.frame
end

--- Apply config from profile.modules.windfuryBubbles only. Does not touch Shamanistic Focus or other modules.
function windfuryBubbles:ApplyConfig()
    local cfg = getModuleConfig("windfuryBubbles")
    if not cfg then return end
    self:Create()
    local st = _G.ShammyTime
    local moduleScale = (type(cfg.scale) == "number" and cfg.scale >= 0.1 and cfg.scale <= 3) and cfg.scale or 1
    local effScale, effAlpha = getEffectiveScaleAlpha(moduleScale, cfg.alpha or 1)
    local db = st and st.GetDB and st.GetDB()
    if db then
        db.wfRadialScale = moduleScale
    end
    -- Scale and position apply to the single wrapper so the whole radial (center + satellites) scales as one object.
    -- Re-apply position after scale (same pattern as Shamanistic Focus) so the radial stays in place and doesn't jump diagonally.
    -- Alpha is NOT set here; UpdateAllElementsFadeState() is the sole owner of frame alpha
    -- (setting it here would cause all modules to blink when any single setting changes).
    local wrapper = _G.ShammyTimeWindfuryRadial
    if wrapper then
        if st and st.ApplyCenterRingPosition then st.ApplyCenterRingPosition() end
        wrapper:SetScale(effScale)
        if st and st.ApplyCenterRingPosition then st.ApplyCenterRingPosition() end  -- re-anchor after scale so position doesn't drift
        -- Center has scale 1; satellites use fixed offsets (no per-bubble scaling from this slider)
        if st and st.ApplySatellitePositionsForCenterScale then st.ApplySatellitePositionsForCenterScale(1) end
    end
end

function windfuryBubbles:SetEnabled(enabled)
    local p = ShammyTime.db.profile
    if p.modules and p.modules.windfuryBubbles then
        p.modules.windfuryBubbles.enabled = enabled
    end
    p.wfRadialEnabled = enabled
    if ShammyTime.ApplyElementVisibility then ShammyTime.ApplyElementVisibility() end
end

function windfuryBubbles:DemoStart()
    self:DemoStop()
    local st = _G.ShammyTime
    if st and st.EnsureCenterRingExists then st.EnsureCenterRingExists() end
    if st and st.ApplyCenterRingPosition then st.ApplyCenterRingPosition() end
    local wrapper = _G.ShammyTimeWindfuryRadial
    local center = _G.ShammyTimeCenterRing
    if wrapper then wrapper:Show(); wrapper:SetAlpha(1) end
    if center then
        center:Show()
        if center.textFrame then center.textFrame:Show() end
    end
    if st and st.ShowAllSatellites then st.ShowAllSatellites() end
    -- Use the same SimulateTestProc as /st test (records fake hits, updates stats, plays proc)
    if st and st.SimulateTestProc then
        st.SimulateTestProc()
    end
    -- Repeat every 3s while demo is active
    local mod = self
    self.demoTimer = C_Timer.NewTicker(3, function()
        local addon = _G.ShammyTime
        -- Stop if timer was cancelled or demo ended
        if not mod.demoTimer or (addon and not addon.demoActive) then
            if mod.demoTimer then
                mod.demoTimer:Cancel()
                mod.demoTimer = nil
            end
            return
        end
        if addon and addon.SimulateTestProc then
            addon.SimulateTestProc()
        end
    end)
end

function windfuryBubbles:DemoStop()
    if self.demoTimer then
        self.demoTimer:Cancel()
        self.demoTimer = nil
    end
    local st = _G.ShammyTime
    if st and st.UpdateAllElementsFadeState then st.UpdateAllElementsFadeState() end
end

ShammyTime.Modules.windfuryBubbles = windfuryBubbles

-- ---------------------------------------------------------------------------
-- Totem Bar
-- ---------------------------------------------------------------------------
local totemBar = {
    frame = nil,
}

function totemBar:Create()
    if ShammyTime.EnsureWindfuryTotemBarFrame then
        self.frame = ShammyTime.EnsureWindfuryTotemBarFrame()
    end
    return self.frame
end

function totemBar:ApplyConfig()
    local cfg = getModuleConfig("totemBar")
    if not cfg then return end
    self:Create()
    local st = _G.ShammyTime
    local moduleScale = (type(cfg.scale) == "number" and cfg.scale >= 0.1 and cfg.scale <= 3) and cfg.scale or 1
    local effScale, effAlpha = getEffectiveScaleAlpha(moduleScale, cfg.alpha or 1)
    local db = st and st.GetDB and st.GetDB()
    if db then db.wfTotemBarScale = moduleScale end
    local bar = self.frame or (st and st.EnsureWindfuryTotemBarFrame and st.EnsureWindfuryTotemBarFrame())
    if bar then
        -- Position first, then scale, then re-apply position so the bar doesn't move diagonally (same as Shamanistic Focus)
        -- Alpha is NOT set here; UpdateAllElementsFadeState() is the sole owner of frame alpha.
        if st and st.ApplyTotemBarPosition then st.ApplyTotemBarPosition() end
        bar:SetScale(effScale)
        if st and st.ApplyTotemBarPosition then st.ApplyTotemBarPosition() end
    end
end

function totemBar:SetEnabled(enabled)
    local p = ShammyTime.db.profile
    if p.modules and p.modules.totemBar then p.modules.totemBar.enabled = enabled end
    p.wfTotemBarEnabled = enabled
    if ShammyTime.ApplyElementVisibility then ShammyTime.ApplyElementVisibility() end
end

function totemBar:DemoStart()
    local bar = self:Create()
    if bar then bar:Show(); bar:SetAlpha(1) end
end

function totemBar:DemoStop()
    local st = _G.ShammyTime
    if st and st.UpdateAllElementsFadeState then st.UpdateAllElementsFadeState() end
end

ShammyTime.Modules.totemBar = totemBar

-- ---------------------------------------------------------------------------
-- Shamanistic Focus
-- ---------------------------------------------------------------------------
local shamanisticFocus = {
    frame = nil,
}

function shamanisticFocus:Create()
    if ShammyTime.GetShamanisticFocusFrame then
        self.frame = ShammyTime.GetShamanisticFocusFrame()
    end
    return self.frame
end

--- Apply config from profile.modules.shamanisticFocus and profile.focusFrame only. Never read windfury or other module settings.
function shamanisticFocus:ApplyConfig()
    local cfg = getModuleConfig("shamanisticFocus")
    if not cfg then return end
    self:Create()
    local st = _G.ShammyTime
    local f = self.frame or (st and st.GetShamanisticFocusFrame and st.GetShamanisticFocusFrame())
    if not f then return end
    -- Position from focusFrame; scale/alpha from this module only (not windfuryBubbles). Position first, then scale, then re-apply position so the frame doesn't drift.
    local db = st and st.GetDB and st.GetDB()
    if db and db.focusFrame then
        local ff = db.focusFrame
        local relTo = (ff.relativeTo and _G[ff.relativeTo]) or UIParent
        if relTo then
            f:ClearAllPoints()
            f:SetPoint(ff.point or "CENTER", relTo, ff.relativePoint or "CENTER", ff.x or 0, ff.y or -150)
        end
    end
    local moduleScale = (type(cfg.scale) == "number" and cfg.scale >= 0.1 and cfg.scale <= 3) and cfg.scale or 1.17
    local effScale = getEffectiveScaleAlpha(moduleScale, cfg.alpha or 1)
    -- Alpha is NOT set here; UpdateAllElementsFadeState() is the sole owner of frame alpha.
    f:SetScale(effScale)
    if db and db.focusFrame then
        local ff = db.focusFrame
        local relTo = (ff.relativeTo and _G[ff.relativeTo]) or UIParent
        if relTo then
            f:ClearAllPoints()
            f:SetPoint(ff.point or "CENTER", relTo, ff.relativePoint or "CENTER", ff.x or 0, ff.y or -150)
        end
    end
end

function shamanisticFocus:SetEnabled(enabled)
    local p = ShammyTime.db.profile
    if p.modules and p.modules.shamanisticFocus then p.modules.shamanisticFocus.enabled = enabled end
    p.wfFocusEnabled = enabled
    if ShammyTime.ApplyElementVisibility then ShammyTime.ApplyElementVisibility() end
end

function shamanisticFocus:DemoStart()
    local st = _G.ShammyTime
    if st and st.StartShamanisticFocusTest then st.StartShamanisticFocusTest() end
    self:Create()
    if self.frame then self.frame:Show(); self.frame:SetAlpha(1) end
end

function shamanisticFocus:DemoStop()
    local st = _G.ShammyTime
    if st and st.StopShamanisticFocusTest then st.StopShamanisticFocusTest() end
    if st and st.UpdateAllElementsFadeState then st.UpdateAllElementsFadeState() end
end

ShammyTime.Modules.shamanisticFocus = shamanisticFocus

-- ---------------------------------------------------------------------------
-- Weapon Imbue Bar
-- ---------------------------------------------------------------------------
local weaponImbueBar = {
    frame = nil,
}

function weaponImbueBar:Create()
    if ShammyTime.EnsureImbueBarFrame then
        self.frame = ShammyTime.EnsureImbueBarFrame()
    end
    return self.frame
end

function weaponImbueBar:ApplyConfig()
    local cfg = getModuleConfig("weaponImbueBar")
    if not cfg then return end
    self:Create()
    local st = _G.ShammyTime
    local f = self.frame or (st and st.EnsureImbueBarFrame and st.EnsureImbueBarFrame())
    if not f then return end
    -- Position first (normalized to CENTER in ApplyImbueBarPosition), then scale, then re-apply position so it doesn't drift
    if st and st.ApplyImbueBarPosition then
        st.ApplyImbueBarPosition()
    end
    local moduleScale = (type(cfg.scale) == "number" and cfg.scale >= 0.1 and cfg.scale <= 3) and cfg.scale or 0.75
    local effScale = getEffectiveScaleAlpha(moduleScale, cfg.alpha or 1)
    -- Alpha is NOT set here; UpdateAllElementsFadeState() is the sole owner of frame alpha.
    f:SetScale(effScale)
    if st and st.ApplyImbueBarPosition then
        st.ApplyImbueBarPosition()
    end
end

function weaponImbueBar:SetEnabled(enabled)
    local p = ShammyTime.db.profile
    if p.modules and p.modules.weaponImbueBar then p.modules.weaponImbueBar.enabled = enabled end
    p.wfImbueBarEnabled = enabled
    if ShammyTime.ApplyElementVisibility then ShammyTime.ApplyElementVisibility() end
end

function weaponImbueBar:DemoStart()
    local f = self:Create()
    if f then f:Show(); f:SetAlpha(1) end
end

function weaponImbueBar:DemoStop()
    local st = _G.ShammyTime
    if st and st.UpdateAllElementsFadeState then st.UpdateAllElementsFadeState() end
end

ShammyTime.Modules.weaponImbueBar = weaponImbueBar

-- ---------------------------------------------------------------------------
-- Shield Indicator
-- ---------------------------------------------------------------------------
local shieldIndicator = {
    frame = nil,
}

function shieldIndicator:Create()
    if ShammyTime.EnsureShieldFrame then
        self.frame = ShammyTime.EnsureShieldFrame()
    end
    return self.frame
end

function shieldIndicator:ApplyConfig()
    local cfg = getModuleConfig("shieldIndicator")
    if not cfg then return end
    self:Create()
    local st = _G.ShammyTime
    local f = self.frame or (st and st.EnsureShieldFrame and st.EnsureShieldFrame())
    if not f then return end
    -- Position first (normalized to CENTER in ApplyShieldPosition), then scale, then re-apply position so it doesn't drift
    if st and st.ApplyShieldPosition then
        st.ApplyShieldPosition()
    end
    local moduleScale = (type(cfg.scale) == "number" and cfg.scale >= 0.05 and cfg.scale <= 3) and cfg.scale or 0.36
    local effScale = getEffectiveScaleAlpha(moduleScale, cfg.alpha or 1)
    -- Alpha is NOT set here; UpdateAllElementsFadeState() is the sole owner of frame alpha.
    f:SetScale(effScale)
    if st and st.ApplyShieldPosition then
        st.ApplyShieldPosition()
    end
end

function shieldIndicator:SetEnabled(enabled)
    local p = ShammyTime.db.profile
    if p.modules and p.modules.shieldIndicator then p.modules.shieldIndicator.enabled = enabled end
    p.wfShieldEnabled = enabled
    if ShammyTime.ApplyElementVisibility then ShammyTime.ApplyElementVisibility() end
end

function shieldIndicator:DemoStart()
    local f = self:Create()
    if f then f:Show(); f:SetAlpha(1) end
end

function shieldIndicator:DemoStop()
    local st = _G.ShammyTime
    if st and st.UpdateAllElementsFadeState then st.UpdateAllElementsFadeState() end
end

ShammyTime.Modules.shieldIndicator = shieldIndicator

-- ---------------------------------------------------------------------------
-- WF Impact (Windfury Totem party damage feed)
-- ---------------------------------------------------------------------------
local wfImpact = {
    frame = nil,
    demoTimer = nil,
}

function wfImpact:Create()
    local api = _G.ShammyTime_WFImpact
    if api and api.EnsureFrame then
        self.frame = api.EnsureFrame()
    end
    return self.frame
end

function wfImpact:ApplyConfig()
    local cfg = getModuleConfig("wfImpact")
    if not cfg then return end
    self:Create()
    local api = _G.ShammyTime_WFImpact
    if api and api.ApplyConfig then
        api.ApplyConfig()
    end
end

function wfImpact:SetEnabled(enabled)
    local p = ShammyTime.db.profile
    if p.modules and p.modules.wfImpact then p.modules.wfImpact.enabled = enabled end
    p.wfImpactEnabled = enabled
    local api = _G.ShammyTime_WFImpact
    if api and api.SetEnabled then api.SetEnabled(enabled) end
end

function wfImpact:DemoStart()
    self:DemoStop()
    self:Create()
    local api = _G.ShammyTime_WFImpact
    if api and api.Simulate then
        api.Simulate()
    end
    -- Repeat every 3s while demo is active
    local mod = self
    self.demoTimer = C_Timer.NewTicker(3, function()
        local addon = _G.ShammyTime
        if not mod.demoTimer or (addon and not addon.demoActive) then
            if mod.demoTimer then
                mod.demoTimer:Cancel()
                mod.demoTimer = nil
            end
            return
        end
        local a = _G.ShammyTime_WFImpact
        if a and a.Simulate then a.Simulate() end
    end)
end

function wfImpact:DemoStop()
    if self.demoTimer then
        self.demoTimer:Cancel()
        self.demoTimer = nil
    end
end

ShammyTime.Modules.wfImpact = wfImpact

-- ---------------------------------------------------------------------------
-- Windfury ICD (Internal Cooldown indicator)
-- ---------------------------------------------------------------------------
local windfuryIcd = {
    frame = nil,
}

function windfuryIcd:Create()
    if ShammyTime.EnsureWindfuryICDFrame then
        self.frame = ShammyTime.EnsureWindfuryICDFrame()
    end
    return self.frame
end

function windfuryIcd:ApplyConfig()
    local cfg = getModuleConfig("windfuryIcd")
    if not cfg then return end
    self:Create()
    local st = _G.ShammyTime
    local f = self.frame or (st and st.GetWindfuryICDFrame and st.GetWindfuryICDFrame())
    if not f then return end
    -- Position from windfuryIcdFrame; scale/alpha from this module only.
    local db = st and st.GetDB and st.GetDB()
    if db and db.windfuryIcdFrame then
        local ff = db.windfuryIcdFrame
        local relTo = (ff.relativeTo and _G[ff.relativeTo]) or UIParent
        if relTo then
            f:ClearAllPoints()
            f:SetPoint(ff.point or "CENTER", relTo, ff.relativePoint or "CENTER", ff.x or 0, ff.y or -250)
        end
    end
    local moduleScale = (type(cfg.scale) == "number" and cfg.scale >= 0.1 and cfg.scale <= 3) and cfg.scale or 1.045
    local effScale = getEffectiveScaleAlpha(moduleScale, cfg.alpha or 1)
    -- Alpha is NOT set here; UpdateAllElementsFadeState() is the sole owner of frame alpha.
    f:SetScale(effScale)
    if db and db.windfuryIcdFrame then
        local ff = db.windfuryIcdFrame
        local relTo = (ff.relativeTo and _G[ff.relativeTo]) or UIParent
        if relTo then
            f:ClearAllPoints()
            f:SetPoint(ff.point or "CENTER", relTo, ff.relativePoint or "CENTER", ff.x or 0, ff.y or -250)
        end
    end
end

function windfuryIcd:SetEnabled(enabled)
    local p = ShammyTime.db.profile
    if p.modules and p.modules.windfuryIcd then p.modules.windfuryIcd.enabled = enabled end
    p.wfIcdEnabled = enabled
    if ShammyTime.ApplyElementVisibility then ShammyTime.ApplyElementVisibility() end
end

function windfuryIcd:DemoStart()
    local st = _G.ShammyTime
    if st and st.StartWindfuryICDTest then st.StartWindfuryICDTest() end
    self:Create()
    if self.frame then self.frame:Show(); self.frame:SetAlpha(1) end
end

function windfuryIcd:DemoStop()
    local st = _G.ShammyTime
    if st and st.StopWindfuryICDTest then st.StopWindfuryICDTest() end
    if st and st.UpdateAllElementsFadeState then st.UpdateAllElementsFadeState() end
end

ShammyTime.Modules.windfuryIcd = windfuryIcd

-- ---------------------------------------------------------------------------
-- Stagger Bar (dual-wield swing timer visual)
-- ---------------------------------------------------------------------------
local staggerBar = {
    frame = nil,
}

function staggerBar:Create()
    if ShammyTime.EnsureStaggerBarFrame then
        self.frame = ShammyTime.EnsureStaggerBarFrame()
    end
    return self.frame
end

function staggerBar:ApplyConfig()
    local cfg = getModuleConfig("staggerBar")
    if not cfg then return end
    self:Create()
    local st = _G.ShammyTime
    local f = self.frame or (st and st.EnsureStaggerBarFrame and st.EnsureStaggerBarFrame())
    if not f then return end
    -- Position first, then scale, then re-apply position so the frame doesn't drift
    if st and st.ApplyStaggerBarPosition then st.ApplyStaggerBarPosition() end
    local moduleScale = (type(cfg.scale) == "number" and cfg.scale >= 0.1 and cfg.scale <= 3) and cfg.scale or 0.5
    local effScale = getEffectiveScaleAlpha(moduleScale, cfg.alpha or 1)
    -- Alpha is NOT set here; UpdateAllElementsFadeState() is the sole owner of frame alpha.
    f:SetScale(effScale)
    if st and st.ApplyStaggerBarPosition then st.ApplyStaggerBarPosition() end
    if st and st.ApplyStaggerBarLayout then st.ApplyStaggerBarLayout() end
end

function staggerBar:SetEnabled(enabled)
    local p = ShammyTime.db.profile
    if p.modules and p.modules.staggerBar then p.modules.staggerBar.enabled = enabled end
    p.staggerBarEnabled = enabled
    if ShammyTime.ApplyElementVisibility then ShammyTime.ApplyElementVisibility() end
end

function staggerBar:DemoStart()
    local st = _G.ShammyTime
    if st and st.StartStaggerBarDemo then st.StartStaggerBarDemo() end
    self:Create()
    if self.frame then self.frame:Show(); self.frame:SetAlpha(1) end
end

function staggerBar:DemoStop()
    local st = _G.ShammyTime
    if st and st.StopStaggerBarDemo then st.StopStaggerBarDemo() end
    if st and st.UpdateAllElementsFadeState then st.UpdateAllElementsFadeState() end
end

ShammyTime.Modules.staggerBar = staggerBar

-- ---------------------------------------------------------------------------
-- Pressure Visual (bar + popup slots)
-- ---------------------------------------------------------------------------
local pressureVisual = {
    frame = nil,
}

function pressureVisual:Create()
    if ShammyTime.EnsurePressureFrame then
        self.frame = ShammyTime.EnsurePressureFrame()
    elseif ShammyTime.GetPressureFrame then
        self.frame = ShammyTime.GetPressureFrame()
    end
    return self.frame
end

function pressureVisual:ApplyConfig()
    local cfg = getModuleConfig("pressureVisual")
    if not cfg then return end
    self:Create()
    local st = _G.ShammyTime
    local f = self.frame or (st and st.GetPressureFrame and st.GetPressureFrame())
    if not f then return end
    if st and st.ApplyPressureFramePosition then
        st.ApplyPressureFramePosition()
    end
    local moduleScale = (type(cfg.scale) == "number" and cfg.scale >= 0.1 and cfg.scale <= 3) and cfg.scale or 0.8
    local effScale = getEffectiveScaleAlpha(moduleScale, cfg.alpha or 1)
    local baseScale = (st and st.GetPressureBaseScale and st.GetPressureBaseScale()) or 0.5
    f:SetScale(baseScale * effScale)
    if st and st.ApplyPressureFramePosition then
        st.ApplyPressureFramePosition()
    end
    local db = st and st.GetDB and st.GetDB()
    if db then db.pressureScale = moduleScale end
end

function pressureVisual:SetEnabled(enabled)
    local p = ShammyTime.db.profile
    if p.modules and p.modules.pressureVisual then p.modules.pressureVisual.enabled = enabled end
    p.pressureEnabled = enabled
    if ShammyTime.ApplyElementVisibility then ShammyTime.ApplyElementVisibility() end
end

function pressureVisual:DemoStart()
    local f = self:Create()
    if f then f:Show(); f:SetAlpha(1) end
end

function pressureVisual:DemoStop()
    local st = _G.ShammyTime
    if st and st.UpdateAllElementsFadeState then st.UpdateAllElementsFadeState() end
end

ShammyTime.Modules.pressureVisual = pressureVisual
