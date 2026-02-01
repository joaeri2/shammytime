-- ShammyTime: Movable totem icons with timers, "gone" animation, and out-of-range indicator.
-- When you're too far from a totem to receive its buff, a red overlay appears on that slot.
-- TBC Anniversary Edition (Interface 20505)

local addonName, addon = ...
local SLOT_TO_ELEMENT = { [1] = "Fire", [2] = "Earth", [3] = "Water", [4] = "Air" }
local ELEMENT_ORDER = { "Fire", "Earth", "Water", "Air" }
local ELEMENT_COLORS = {
    Fire  = { r = 0.9,  g = 0.3,  b = 0.2  },
    Earth = { r = 0.6,  g = 0.4,  b = 0.2  },
    Water = { r = 0.2,  g = 0.5,  b = 0.9  },
    Air   = { r = 0.4,  g = 0.8,  b = 0.9  },
}
-- Darkened elemental icons for empty slots (which element is missing)
local ELEMENT_EMPTY_ICONS = {
    Fire  = "Interface\\Icons\\INV_Elemental_Primal_Fire",
    Earth = "Interface\\Icons\\INV_Elemental_Primal_Earth",
    Water = "Interface\\Icons\\INV_Elemental_Primal_Water",
    Air   = "Interface\\Icons\\INV_Elemental_Primal_Air",
}
-- Lightning Shield: all TBC spell IDs (ranks 1–6) and icon when not active
local LIGHTNING_SHIELD_SPELL_IDS = { 324, 325, 905, 945, 8134, 10431 }
local LIGHTNING_SHIELD_ICON = "Interface\\Icons\\Spell_Nature_LightningShield"

-- Weapon imbue buff spell IDs (Flametongue, Frostbrand, Rockbiter, Windfury Weapon – all ranks)
local WEAPON_IMBUE_SPELL_IDS = {
    [8024]=true, [8027]=true, [8030]=true, [16339]=true, [16341]=true, [16342]=true, [25489]=true,  -- Flametongue
    [8033]=true, [8034]=true, [8037]=true, [10458]=true, [16352]=true, [16353]=true, [25500]=true, [25501]=true,  -- Frostbrand
    [8017]=true, [8018]=true, [8019]=true, [10399]=true, [16314]=true, [16315]=true, [16316]=true, [25479]=true,  -- Rockbiter
    [8232]=true, [8235]=true, [10486]=true, [16362]=true, [25505]=true,  -- Windfury Weapon
}
local WEAPON_IMBUE_ICON = "Interface\\Icons\\Spell_Fire_FlameTongue"

-- Totems that do NOT put a buff on the player (no way to detect range). Never show out-of-range overlay for these.
local TOTEM_NO_RANGE_BUFF = {
    ["Windfury Totem"] = true,   -- weapon proc only, no persistent buff
}

-- Totem name (from GetTotemInfo) → buff spell ID on player. When totem is down but player
-- doesn't have this buff, we're out of range. Match by exact name or by prefix (e.g. "Mana Spring Totem" matches "Mana Spring Totem II").
-- Only include totems that put a *persistent* aura on the player (not procs like Windfury).
local TOTEM_BUFF_SPELL_IDS = {
    -- Earth
    ["Strength of Earth Totem"] = 8075,
    ["Stoneskin Totem"] = 8071,
    ["Stoneclaw Totem"] = 8072,
    -- Fire
    ["Flametongue Totem"] = 8230,  -- Flametongue Totem Effect
    -- Water: Mana Spring (multiple ranks = different buff IDs), Healing Stream, resistance totems
    ["Mana Spring Totem"] = { 5675, 10497, 24854 },  -- ranks 1–3+ (Classic/TBC)
    ["Healing Stream Totem"] = 10463,
    ["Frost Resistance Totem"] = 8181,
    ["Fire Resistance Totem"] = 8184,
    -- Air (Windfury Totem = weapon proc, no persistent buff; Grace of Air, Grounding = persistent)
    ["Grace of Air Totem"] = 10627,
    ["Grounding Totem"] = 8178,  -- Grounding Totem Effect
    ["Nature Resistance Totem"] = 10595,
}

-- Buff name(s) as shown on player (spell ID can differ by client; name is reliable for range check).
-- Same keys as TOTEM_BUFF_SPELL_IDS; value is string or table of strings to match aura name.
local TOTEM_BUFF_NAMES = {
    ["Strength of Earth Totem"] = "Strength of Earth",
    ["Stoneskin Totem"] = "Stoneskin",
    ["Stoneclaw Totem"] = "Stoneclaw",
    ["Flametongue Totem"] = "Flametongue Totem",
    ["Mana Spring Totem"] = "Mana Spring",
    ["Healing Stream Totem"] = "Healing Stream",
    ["Frost Resistance Totem"] = "Frost Resistance",
    ["Fire Resistance Totem"] = "Fire Resistance",
    ["Grace of Air Totem"] = "Grace of Air",
    ["Grounding Totem"] = "Grounding Totem Effect",
    ["Nature Resistance Totem"] = "Nature Resistance",
}

-- True if this totem has no player buff (we can't detect range; never show out-of-range overlay).
local function IsTotemWithNoRangeBuff(totemName)
    if not totemName or totemName == "" then return false end
    if TOTEM_NO_RANGE_BUFF[totemName] then return true end
    for key in pairs(TOTEM_NO_RANGE_BUFF) do
        if totemName:find(key, 1, true) == 1 then return true end
    end
    return false
end

-- Get buff spell ID(s) for a totem name; match exact or by prefix. Returns number or table of numbers.
local function GetTotemBuffSpellId(totemName)
    if not totemName or totemName == "" then return nil end
    local id = TOTEM_BUFF_SPELL_IDS[totemName]
    if id then return id end
    for key, spellId in pairs(TOTEM_BUFF_SPELL_IDS) do
        if totemName:find(key, 1, true) == 1 then return spellId end
    end
    return nil
end

-- Get buff name(s) for a totem name (for name-based range fallback). Returns string or table of strings, or nil.
local function GetTotemBuffName(totemName)
    if not totemName or totemName == "" then return nil end
    local name = TOTEM_BUFF_NAMES[totemName]
    if name then return name end
    for key, buffName in pairs(TOTEM_BUFF_NAMES) do
        if totemName:find(key, 1, true) == 1 then return buffName end
    end
    return nil
end

-- True if player has a helpful aura whose name matches the totem's buff (fallback when spell ID fails).
local function HasPlayerBuffByTotemName(totemName)
    local expected = GetTotemBuffName(totemName)
    if not expected then return false end
    local names = type(expected) == "table" and expected or { expected }
    for i = 1, 40 do
        local auraName = UnitAura("player", i, "HELPFUL")
        if not auraName then break end
        for _, n in ipairs(names) do
            if auraName == n or auraName:find(n, 1, true) == 1 then return true end
        end
    end
    return false
end

-- Returns true if the player has a helpful aura with the given spell ID (used for totem range).
-- TBC Anniversary: UnitAura 11 returns (spellId 11th) or 10 returns (spellId 10th in shouldConsolidate).
local function HasPlayerBuffBySpellId(spellId)
    if not spellId then return false end
    for i = 1, 40 do
        local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellIdReturn = UnitAura("player", i, "HELPFUL")
        if not name then break end
        local auraSpellId = (type(count) == "string") and shouldConsolidate or spellIdReturn
        if auraSpellId == spellId then return true end
    end
    return false
end

-- True if player has any of the given buff spell ID(s). idOrIds is a number or table of numbers.
local function HasPlayerBuffByAnySpellId(idOrIds)
    if not idOrIds then return false end
    if type(idOrIds) == "number" then return HasPlayerBuffBySpellId(idOrIds) end
    for _, id in ipairs(idOrIds) do
        if HasPlayerBuffBySpellId(id) then return true end
    end
    return false
end

-- Defaults
local DEFAULTS = {
    point = "CENTER",
    relativeTo = "UIParent",
    relativePoint = "CENTER",
    x = 0,
    y = -180,
    scale = 1.0,
    locked = false,
}

-- State: previous totem presence per slot (to detect "just gone")
local lastHadTotem = { [1] = false, [2] = false, [3] = false, [4] = false }

local mainFrame
local slotFrames = {}
local lightningShieldFrame
local weaponImbueFrame
local timerTicker

local function GetDB()
    ShammyTimeDB = ShammyTimeDB or {}
    for k, v in pairs(DEFAULTS) do
        if ShammyTimeDB[k] == nil then ShammyTimeDB[k] = v end
    end
    return ShammyTimeDB
end

local function ApplyScale()
    if mainFrame then
        local db = GetDB()
        mainFrame:SetScale(db.scale or 1)
    end
end

-- Returns Lightning Shield aura on player: icon, count (charges), duration, expirationTime; or nil if not active.
-- TBC Anniversary client: UnitAura may return 11 values (with rank) or 10 (no rank; 4th = dispelType string). Detect by type(count).
local function GetLightningShieldAura()
    for i = 1, 40 do
        local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId = UnitAura("player", i, "HELPFUL")
        if not name then break end
        -- 10-return API (no rank): rank=icon, icon=count, count=dispelType, debuffType=duration, duration=expirationTime; spellId in shouldConsolidate (10th)
        local rIcon = (type(count) == "string") and rank or icon
        local rCount = (type(count) == "string") and icon or count
        local rDuration = (type(count) == "string") and debuffType or duration
        local rExpiration = (type(count) == "string") and duration or expirationTime
        local auraSpellId = (type(count) == "string") and shouldConsolidate or spellId
        if auraSpellId then
            for _, sid in ipairs(LIGHTNING_SHIELD_SPELL_IDS) do
                if auraSpellId == sid then
                    return rIcon, (type(rCount) == "number" and rCount or 0), rDuration, (type(rExpiration) == "number" and rExpiration or 0)
                end
            end
        end
        if name == "Lightning Shield" then
            return rIcon, (type(rCount) == "number" and rCount or 0), rDuration, (type(rExpiration) == "number" and rExpiration or 0)
        end
    end
    return nil
end

-- Returns first weapon imbue aura on player: icon, expirationTime, name; or nil if none.
-- TBC Anniversary: UnitAura 11 returns or 10 (no rank; icon=rank, expirationTime=duration, spellId=shouldConsolidate).
local function GetWeaponImbueAura()
    for i = 1, 40 do
        local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId = UnitAura("player", i, "HELPFUL")
        if not name then break end
        local rIcon = (type(count) == "string") and rank or icon
        local rExpiration = (type(count) == "string") and duration or expirationTime
        local auraSpellId = (type(count) == "string") and shouldConsolidate or spellId
        if auraSpellId and WEAPON_IMBUE_SPELL_IDS[auraSpellId] then
            return rIcon, rExpiration, name
        end
        if name and (name:find("Flametongue") or name:find("Frostbrand") or name:find("Rockbiter") or name:find("Windfury")) then
            return rIcon, rExpiration, name
        end
    end
    return nil
end

local function FormatTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 60 then
        return ("%d:%.0f"):format(floor(seconds / 60), seconds % 60)
    end
    return ("%.0f"):format(seconds)
end

-- Use the same "cooldown finish" spiral as action buttons (native WoW UI)
local function PlayGoneAnimation(slotFrame, element)
    if not slotFrame or not slotFrame.expiryCooldown then return end
    local cd = slotFrame.expiryCooldown
    cd:Show()
    -- Brief cooldown that completes in ~0.5s: spiral sweeps and disappears like ability coming off CD
    cd:SetCooldown(GetTime() - 0.5, 0.5)
    C_Timer.After(0.6, function()
        if cd and cd.SetCooldown then
            cd:SetCooldown(0, 0)
            cd:Hide()
        end
    end)
end

local function UpdateSlot(slot)
    local haveTotem, totemName, startTime, duration, icon = GetTotemInfo(slot)
    local element = SLOT_TO_ELEMENT[slot]
    local sf = slotFrames[slot]
    if not sf then return end

    local nowHasTotem = (totemName and totemName ~= "")

    -- Detect "just gone" and trigger obvious animation
    if lastHadTotem[slot] and not nowHasTotem then
        PlayGoneAnimation(sf, element)
    end
    lastHadTotem[slot] = nowHasTotem

    local color = ELEMENT_COLORS[element]
    if nowHasTotem then
        sf.icon:SetTexture(icon and icon ~= "" and icon or "Interface\\Icons\\INV_Elemental_Primal_Earth")
        sf.icon:SetVertexColor(1, 1, 1)
        sf.icon:Show()
        sf.goneOverlay:Hide()
        local timeLeft = GetTotemTimeLeft(slot)
        sf.timer:SetText(FormatTime(timeLeft))
        sf.timer:SetTextColor(1, 1, 1)
        sf.timer:Show()
        sf:SetBackdropBorderColor(color.r, color.g, color.b, 1)
        -- Out of range: totem is down but we don't have its buff (too far). Use spell ID first, then name fallback.
        -- Totems with no player buff (Grounding, Windfury) can't be range-checked; never show overlay.
        local buffSpellId = GetTotemBuffSpellId(totemName)
        local hasBuff = (buffSpellId and HasPlayerBuffByAnySpellId(buffSpellId)) or HasPlayerBuffByTotemName(totemName)
        if not IsTotemWithNoRangeBuff(totemName) and buffSpellId and not hasBuff then
            sf.rangeOverlay:Show()
        else
            sf.rangeOverlay:Hide()
        end
    else
        -- Empty slot: show darkened element icon so you see which one is missing
        sf.icon:SetTexture(ELEMENT_EMPTY_ICONS[element] or "Interface\\Icons\\INV_Misc_QuestionMark")
        sf.icon:SetVertexColor(0.35, 0.35, 0.35)
        sf.timer:SetText("")
        sf.timer:Hide()
        sf.rangeOverlay:Hide()
        sf:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    end
end

local function UpdateAllSlots()
    for slot = 1, 4 do
        UpdateSlot(slot)
    end
end

local function UpdateLightningShield()
    if not lightningShieldFrame then return end
    local icon, count, duration, expirationTime = GetLightningShieldAura()
    if icon then
        lightningShieldFrame.icon:SetTexture(icon)
        lightningShieldFrame.icon:SetVertexColor(1, 1, 1)
        local numCount = (type(count) == "number" and count) or 0
        local expTime = (type(expirationTime) == "number" and expirationTime) or 0
        local timeLeft = expTime > 0 and (expTime - GetTime()) or 0
        -- Charges in the middle of the icon
        if lightningShieldFrame.charges then
            lightningShieldFrame.charges:SetText(numCount > 0 and tostring(numCount) or "")
            lightningShieldFrame.charges:Show()
        end
        -- Timer on the bottom, no parenthesis
        lightningShieldFrame.timer:SetText(FormatTime(timeLeft))
        lightningShieldFrame.timer:Show()
        lightningShieldFrame:SetBackdropBorderColor(0.55, 0.48, 0.35, 1)
    else
        lightningShieldFrame.icon:SetTexture(LIGHTNING_SHIELD_ICON)
        lightningShieldFrame.icon:SetVertexColor(0.35, 0.35, 0.35)
        if lightningShieldFrame.charges then
            lightningShieldFrame.charges:SetText("")
            lightningShieldFrame.charges:Hide()
        end
        lightningShieldFrame.timer:SetText("")
        lightningShieldFrame.timer:Hide()
        lightningShieldFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)
    end
end

local function UpdateWeaponImbue()
    if not weaponImbueFrame then return end
    local icon, expirationTime, name = GetWeaponImbueAura()
    if name then
        -- Show active imbue; use fallback icon if client didn't return one
        weaponImbueFrame.icon:SetTexture(icon and icon ~= "" and icon or WEAPON_IMBUE_ICON)
        weaponImbueFrame.icon:SetVertexColor(1, 1, 1)
        local expTime = (type(expirationTime) == "number" and expirationTime) or 0
        local timeLeft = expTime > 0 and (expTime - GetTime()) or 0
        weaponImbueFrame.timer:SetText(FormatTime(timeLeft))
        weaponImbueFrame.timer:Show()
        weaponImbueFrame.imbueName = name
        weaponImbueFrame:SetBackdropBorderColor(0.55, 0.48, 0.35, 1)
    else
        weaponImbueFrame.icon:SetTexture(WEAPON_IMBUE_ICON)
        weaponImbueFrame.icon:SetVertexColor(0.35, 0.35, 0.35)
        weaponImbueFrame.timer:SetText("")
        weaponImbueFrame.timer:Hide()
        weaponImbueFrame.imbueName = nil
        weaponImbueFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)
    end
end

local function RefreshTimers()
    if not mainFrame or not mainFrame:IsShown() then return end
    for slot = 1, 4 do
        local haveTotem, totemName = GetTotemInfo(slot)
        if totemName and totemName ~= "" then
            local sf = slotFrames[slot]
            if sf and sf.timer then
                sf.timer:SetText(FormatTime(GetTotemTimeLeft(slot)))
                -- Refresh range overlay (in case UNIT_AURA didn't fire)
                local buffSpellId = GetTotemBuffSpellId(totemName)
                local hasBuff = (buffSpellId and HasPlayerBuffByAnySpellId(buffSpellId)) or HasPlayerBuffByTotemName(totemName)
                if not IsTotemWithNoRangeBuff(totemName) and buffSpellId and not hasBuff then
                    sf.rangeOverlay:Show()
                else
                    sf.rangeOverlay:Hide()
                end
            end
        end
    end
    UpdateLightningShield()
    UpdateWeaponImbue()
end

local function CreateMainFrame()
    local db = GetDB()
    local f = CreateFrame("Frame", "ShammyTimeFrame", UIParent, "BackdropTemplate")
    local iconSize = 36
    local gap = 4
    local slotW, slotH = iconSize + 6, iconSize + 18
    local fw = 6 * slotW + 5 * gap  -- 4 totems + Lightning Shield + Weapon Imbue
    local fh = slotH
    f:SetSize(fw, fh)
    f:SetScale(db.scale or 1)
    f:SetPoint(db.point or "CENTER", db.relativeTo or "UIParent", db.relativePoint or "CENTER", db.x or 0, db.y or -180)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not (db.locked) then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        db.point, _, db.relativePoint, db.x, db.y = self:GetPoint(1)
    end)
    -- No bar-wide background: texture is on each button

    -- Slot row: chained left-to-right, unit-frame style border per slot
    for i, element in ipairs(ELEMENT_ORDER) do
        local slot = i
        local sf = CreateFrame("Frame", nil, f, "BackdropTemplate")
        sf:SetSize(slotW, slotH)
        if i == 1 then
            sf:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        else
            sf:SetPoint("LEFT", slotFrames[i - 1], "RIGHT", gap, 0)
            sf:SetPoint("TOP", slotFrames[1], "TOP", 0, 0)
        end
        -- Slot: dark background; bar texture only in the timer (numbers) area at bottom
        sf:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        sf:SetBackdropColor(0.12, 0.1, 0.08, 0.94)
        local c = ELEMENT_COLORS[element]
        sf:SetBackdropBorderColor(0.55, 0.48, 0.35, 1)

        -- Bar texture strip behind where the numbers show (bottom of slot)
        local timerBar = CreateFrame("Frame", nil, sf)
        timerBar:SetPoint("BOTTOMLEFT", 2, 2)
        timerBar:SetPoint("BOTTOMRIGHT", -2, 2)
        timerBar:SetHeight(14)
        timerBar:SetFrameLevel(sf:GetFrameLevel())
        local timerBarTex = timerBar:CreateTexture(nil, "BACKGROUND")
        timerBarTex:SetAllPoints(timerBar)
        timerBarTex:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
        timerBarTex:SetTexCoord(0, 1, 0, 0.5)
        timerBarTex:SetVertexColor(0.35, 0.3, 0.25, 0.95)

        local icon = sf:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("TOP", 0, -4)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(ELEMENT_EMPTY_ICONS[element])
        icon:SetVertexColor(0.35, 0.35, 0.35)
        sf.icon = icon

        -- Cooldown spiral (same as action buttons): used for "expired" effect
        local expiryCd = CreateFrame("Cooldown", nil, sf, "CooldownFrameTemplate")
        expiryCd:SetPoint("TOP", sf, "TOP", 0, -4)
        expiryCd:SetSize(iconSize, iconSize)
        expiryCd:SetFrameLevel(sf:GetFrameLevel() + 1)
        if expiryCd.SetDrawEdge then expiryCd:SetDrawEdge(false) end
        if expiryCd.SetHideCountdownNumbers then
            expiryCd:SetHideCountdownNumbers(true)
        else
            local regions = { expiryCd:GetRegions() }
            for _, r in ipairs(regions) do
                if r and r.SetText then r:SetText("") end
                if r and r.Hide then r:Hide() end
            end
        end
        expiryCd:Hide()
        sf.expiryCooldown = expiryCd

        local timer = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timer:SetPoint("BOTTOM", 0, 4)
        timer:SetTextColor(1, 1, 1)
        sf.timer = timer

        -- "GONE" overlay (flashes when totem dies/expires)
        local overlay = CreateFrame("Frame", nil, sf)
        overlay:SetAllPoints(sf)
        overlay:SetFrameLevel(sf:GetFrameLevel() + 2)
        local ot = overlay:CreateTexture(nil, "BACKGROUND")
        ot:SetAllPoints()
        ot:SetColorTexture(0.5, 0, 0, 0.6)
        overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        overlay.text:SetPoint("CENTER")
        overlay.text:SetText("GONE")
        overlay.text:SetTextColor(1, 0.3, 0.3)
        overlay:Hide()
        sf.goneOverlay = overlay

        -- "Out of range" overlay: totem is down but player is too far to get the buff
        local rangeOverlay = CreateFrame("Frame", nil, sf)
        rangeOverlay:SetAllPoints(sf)
        rangeOverlay:SetFrameLevel(sf:GetFrameLevel() + 1)
        local rt = rangeOverlay:CreateTexture(nil, "BACKGROUND")
        rt:SetAllPoints()
        rt:SetColorTexture(0.6, 0, 0, 0.5)
        rangeOverlay:Hide()
        sf.rangeOverlay = rangeOverlay

        slotFrames[slot] = sf
    end

    -- Lightning Shield slot (same style as totem slots)
    local lsf = CreateFrame("Frame", nil, f, "BackdropTemplate")
    lsf:SetSize(slotW, slotH)
    lsf:SetPoint("LEFT", slotFrames[4], "RIGHT", gap, 0)
    lsf:SetPoint("TOP", slotFrames[1], "TOP", 0, 0)
    lsf:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    lsf:SetBackdropColor(0.12, 0.1, 0.08, 0.94)
    lsf:SetBackdropBorderColor(0.55, 0.48, 0.35, 1)
    -- Bar texture strip behind where the numbers show (bottom of slot)
    local lsfTimerBar = CreateFrame("Frame", nil, lsf)
    lsfTimerBar:SetPoint("BOTTOMLEFT", 2, 2)
    lsfTimerBar:SetPoint("BOTTOMRIGHT", -2, 2)
    lsfTimerBar:SetHeight(14)
    lsfTimerBar:SetFrameLevel(lsf:GetFrameLevel())
    local lsfTimerBarTex = lsfTimerBar:CreateTexture(nil, "BACKGROUND")
    lsfTimerBarTex:SetAllPoints(lsfTimerBar)
    lsfTimerBarTex:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
    lsfTimerBarTex:SetTexCoord(0, 1, 0, 0.5)
    lsfTimerBarTex:SetVertexColor(0.35, 0.3, 0.25, 0.95)
    local icon = lsf:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("TOP", 0, -4)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(LIGHTNING_SHIELD_ICON)
    icon:SetVertexColor(0.35, 0.35, 0.35)
    lsf.icon = icon
    -- Charge count in the middle of the icon (like WoW buff stacks)
    local charges = lsf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    charges:SetPoint("CENTER", icon, "CENTER", 0, 0)
    charges:SetTextColor(1, 1, 1)
    lsf.charges = charges
    local timer = lsf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timer:SetPoint("BOTTOM", 0, 4)
    timer:SetTextColor(1, 1, 1)
    lsf.timer = timer
    lightningShieldFrame = lsf

    -- Weapon Imbue slot (Flametongue / Frostbrand / Rockbiter / Windfury Weapon)
    local wif = CreateFrame("Frame", nil, f, "BackdropTemplate")
    wif:SetSize(slotW, slotH)
    wif:SetPoint("LEFT", lightningShieldFrame, "RIGHT", gap, 0)
    wif:SetPoint("TOP", slotFrames[1], "TOP", 0, 0)
    wif:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    wif:SetBackdropColor(0.12, 0.1, 0.08, 0.94)
    wif:SetBackdropBorderColor(0.55, 0.48, 0.35, 1)
    local wifIcon = wif:CreateTexture(nil, "ARTWORK")
    wifIcon:SetSize(iconSize, iconSize)
    wifIcon:SetPoint("TOP", 0, -4)
    wifIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    wifIcon:SetTexture(WEAPON_IMBUE_ICON)
    wifIcon:SetVertexColor(0.35, 0.35, 0.35)
    wif.icon = wifIcon
    local wifTimer = wif:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wifTimer:SetPoint("BOTTOM", 0, 4)
    wifTimer:SetTextColor(1, 1, 1)
    wif.timer = wifTimer
    wif:SetScript("OnEnter", function(self)
        if self.imbueName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.imbueName)
            GameTooltip:AddLine("Time until imbue expires", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    wif:SetScript("OnLeave", function() GameTooltip:Hide() end)
    weaponImbueFrame = wif

    mainFrame = f
    return f
end

local function OnEvent(_, event)
    if event == "PLAYER_TOTEM_UPDATE" then
        UpdateAllSlots()
    elseif event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
        if addonName ~= "ShammyTime" then return end
        CreateMainFrame()
        UpdateAllSlots()
        if timerTicker then timerTicker:Cancel() end
        timerTicker = C_Timer.NewTicker(1, RefreshTimers)
        mainFrame:UnregisterEvent("ADDON_LOADED")
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
eventFrame:RegisterEvent("ADDON_LOADED")
if eventFrame.RegisterUnitEvent then
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    eventFrame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
else
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
end
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "ShammyTime" then
        if not mainFrame then
            CreateMainFrame()
            mainFrame:Show()
            if timerTicker then timerTicker:Cancel() end
            timerTicker = C_Timer.NewTicker(1, RefreshTimers)
        end
        UpdateAllSlots()
        UpdateLightningShield()
        UpdateWeaponImbue()
    elseif event == "PLAYER_TOTEM_UPDATE" then
        UpdateAllSlots()
    elseif event == "UNIT_AURA" then
        if not eventFrame.RegisterUnitEvent or arg1 == "player" then
            UpdateAllSlots()
            UpdateLightningShield()
            UpdateWeaponImbue()
        end
    elseif event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then
        UpdateWeaponImbue()
    end
end)

-- Slash: /st lock | unlock | move | scale [0.5-2]
SLASH_SHAMMYTIME1 = "/shammytime"
SLASH_SHAMMYTIME2 = "/st"
SlashCmdList["SHAMMYTIME"] = function(msg)
    local db = GetDB()
    msg = msg and msg:gsub("^%s+", ""):gsub("%s+$", "") or ""
    local cmd, arg = msg:match("^(%S+)%s*(.*)$")
    if not cmd then cmd = msg end
    cmd = cmd and cmd:lower() or ""
    arg = arg and arg:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if cmd == "lock" then
        db.locked = true
        print("ShammyTime: frame locked.")
    elseif cmd == "unlock" or cmd == "move" then
        db.locked = false
        print("ShammyTime: frame unlocked — drag to move.")
    elseif cmd == "scale" then
        if arg == "" then
            print(("ShammyTime: scale is %.2f. Use /st scale <0.5-2> to change."):format(db.scale or 1))
        else
            local num = tonumber(arg)
            if num and num >= 0.5 and num <= 2 then
                db.scale = num
                ApplyScale()
                print(("ShammyTime: scale set to %.2f."):format(num))
            else
                print("ShammyTime: scale must be a number between 0.5 and 2 (e.g. /st scale 1.2)")
            end
        end
    else
        print("ShammyTime: /st lock | unlock | move | scale [0.5-2]")
    end
end
