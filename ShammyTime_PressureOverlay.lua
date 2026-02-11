-------------------------------------------------------------------------------
-- ShammyTime: Pressure Tier Visual Overlay
-- Displays tier-based atmospheric textures anchored to bottom-left corner.
-- Reads current tier from ShammyTime_PressureState (exposed by POC module).
--
-- Architecture:
--   5 texture frames stacked on top of each other (T1 at bottom, T5 on top).
--   Each frame's alpha is independently animated toward a target via EMA.
--   Only the active tier's texture(s) have non-zero target alpha.
--   T1 (smoke) lingers as a subtle underlayer during T2 for atmospheric depth.
--   T3-T5 images have enough atmosphere baked in to stand alone.
--
-- Usage:
--   /stpoc overlay on|off
--   /stpoc overlay scale N
--   /stpoc overlay alpha N
--   /stpoc overlay fadein N
--   /stpoc overlay fadeout N
--   /stpoc overlay blend|add    (toggle blend mode)
--   /stpoc overlay help
-------------------------------------------------------------------------------

local ADDON_PREFIX = "|cff00ccffST-POC|r"

-------------------------------------------------------------------------------
-- Texture paths
-- WoW resolves .tga automatically when extension is omitted in some clients,
-- but for TBC/Classic, specify the full extension to be safe.
-- Place final 32-bit TGA files (with alpha transparency!) at:
--   Interface/AddOns/ShammyTime/Media/Pressure/
-------------------------------------------------------------------------------
local TEXTURE_PATHS = {
    "Interface\\AddOns\\ShammyTime\\Media\\Pressure\\t1_smoke_lower_left_corner_1024.tga",
    "Interface\\AddOns\\ShammyTime\\Media\\Pressure\\t2_lightning_lower_left_corner_1024.tga",
    "Interface\\AddOns\\ShammyTime\\Media\\Pressure\\t3_lightningfire_lower_left_corner_1024.tga",
    "Interface\\AddOns\\ShammyTime\\Media\\Pressure\\t4_lightningfirelava_lower_left_corner_1024.tga",
    "Interface\\AddOns\\ShammyTime\\Media\\Pressure\\t5_lightningfirelavaexplosion_lower_left_corner_1024.tga",
}

local NUM_TIERS = #TEXTURE_PATHS

-------------------------------------------------------------------------------
-- Configuration (all tunable via slash commands)
-------------------------------------------------------------------------------
local CFG = {
    enabled     = true,
    globalAlpha = 0.70,     -- master opacity multiplier (0-1); lets player dial back
    baseWidth   = 512,      -- display width in UI pixels (power-of-2 for clean scaling from 1024)
    baseHeight  = 512,      -- display height in UI pixels
    fadeInTau   = 0.12,     -- seconds: how fast textures appear
    fadeOutTau  = 0.18,     -- seconds: how fast textures disappear (short overlap)
    tickRate    = 0.05,     -- animation update interval (matches pressure tick)
    blendMode   = "BLEND",  -- "BLEND" for proper alpha transparency, "ADD" for glow effect
}

-------------------------------------------------------------------------------
-- Per-tier alpha target table
-- Index: [tier][textureIndex]  where textureIndex 1..5 maps to T1..T5
-- Values are BEFORE globalAlpha multiplier is applied.
--
-- Design rationale:
--   T0: everything invisible (idle / no combat)
--   T1: subtle smoke only
--   T2: smoke stays as atmosphere base + lightning overlaid
--   T3+: higher-tier images have built-in atmosphere, so T1 smoke fades out
-------------------------------------------------------------------------------
local TIER_TARGETS = {
    [0] = { 0,    0,    0,    0,    0    },
    [1] = { 0.70, 0,    0,    0,    0    },
    [2] = { 0.30, 0.75, 0,    0,    0    },
    [3] = { 0,    0,    0.85, 0,    0    },
    [4] = { 0,    0,    0,    0.90, 0    },
    [5] = { 0,    0,    0,    0,    0.95 },
}

-------------------------------------------------------------------------------
-- Math upvalues
-------------------------------------------------------------------------------
local math_exp = math.exp
local math_abs = math.abs

-------------------------------------------------------------------------------
-- Create overlay frames
-- All anchored BOTTOMLEFT, stacked via frame level, fully click-through.
-------------------------------------------------------------------------------
local overlays = {}   -- { frame, texture, currentAlpha }

for i = 1, NUM_TIERS do
    local frame = CreateFrame("Frame", "STPressureOverlay" .. i, UIParent)
    frame:SetFrameStrata("LOW")
    frame:SetFrameLevel(i)

    frame:SetSize(CFG.baseWidth, CFG.baseHeight)
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    frame:EnableMouse(false)

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(TEXTURE_PATHS[i])
    tex:SetBlendMode(CFG.blendMode)

    frame:SetAlpha(0)
    frame:Show()

    overlays[i] = {
        frame        = frame,
        texture      = tex,
        currentAlpha = 0,
    }
end

-------------------------------------------------------------------------------
-- Animation tick – EMA crossfade toward target alphas
-------------------------------------------------------------------------------
local elapsed = 0

local function OnOverlayTick(_, dt)
    if not CFG.enabled then return end

    elapsed = elapsed + dt
    if elapsed < CFG.tickRate then return end
    local step = elapsed
    elapsed = 0

    -- Force-test mode: skip pressure system, hold forced alpha
    if testTier then return end

    -- Read current tier from the pressure system
    local ps = ShammyTime_PressureState
    if not ps then return end
    local tier = ps.currentTier or 0

    local targets = TIER_TARGETS[tier] or TIER_TARGETS[0]

    for i = 1, NUM_TIERS do
        local ov      = overlays[i]
        local target  = targets[i] * CFG.globalAlpha
        local current = ov.currentAlpha

        if math_abs(current - target) < 0.003 then
            -- Close enough – snap to avoid endless micro-updates
            ov.currentAlpha = target
        else
            local tau   = (target > current) and CFG.fadeInTau or CFG.fadeOutTau
            local alpha = 1 - math_exp(-step / tau)
            ov.currentAlpha = current + (target - current) * alpha
        end

        ov.frame:SetAlpha(ov.currentAlpha)
    end
end

local tickFrame = CreateFrame("Frame")
tickFrame:SetScript("OnUpdate", OnOverlayTick)
-- Starts active; alpha is 0 everywhere so nothing visible until tier > 0

-------------------------------------------------------------------------------
-- Show / Hide / Reset helpers
-------------------------------------------------------------------------------
local function ShowOverlay()
    CFG.enabled = true
    tickFrame:Show()
    print(ADDON_PREFIX .. " overlay enabled.")
end

local function HideOverlay()
    CFG.enabled = false
    for i = 1, NUM_TIERS do
        overlays[i].currentAlpha = 0
        overlays[i].frame:SetAlpha(0)
    end
    tickFrame:Hide()
    print(ADDON_PREFIX .. " overlay disabled.")
end

local function ResetOverlayAlphas()
    for i = 1, NUM_TIERS do
        overlays[i].currentAlpha = 0
        overlays[i].frame:SetAlpha(0)
    end
end

local function SetOverlayScale(scale)
    local width  = CFG.baseWidth * scale
    local height = CFG.baseHeight * scale
    for i = 1, NUM_TIERS do
        overlays[i].frame:SetSize(width, height)
    end
    print(ADDON_PREFIX .. string.format(" overlay size: %.0f x %.0f", width, height))
end

local function SetBlendMode(mode)
    CFG.blendMode = mode
    for i = 1, NUM_TIERS do
        overlays[i].texture:SetBlendMode(mode)
    end
    print(ADDON_PREFIX .. " overlay blend mode: " .. mode)
end

-- Force-test: show a specific tier texture at full alpha (bypasses pressure system)
local testTier = nil  -- nil = normal mode, 1-5 = forced tier

local function ForceTestTier(tier)
    if tier == nil or tier == 0 then
        testTier = nil
        print(ADDON_PREFIX .. " overlay test OFF – back to pressure-driven.")
        return
    end
    testTier = tier
    -- Immediately show the texture
    for i = 1, NUM_TIERS do
        if i == tier then
            overlays[i].currentAlpha = CFG.globalAlpha
            overlays[i].frame:SetAlpha(CFG.globalAlpha)
        else
            overlays[i].currentAlpha = 0
            overlays[i].frame:SetAlpha(0)
        end
    end
    print(ADDON_PREFIX .. string.format(" overlay test: forcing T%d at alpha %.2f", tier, CFG.globalAlpha))
end

-------------------------------------------------------------------------------
-- Extend /stpoc with "overlay" subcommand
-- Wraps the existing handler so both systems share one slash command.
-------------------------------------------------------------------------------
local originalHandler = SlashCmdList["STPOC"]

SlashCmdList["STPOC"] = function(msg)
    local trimmed = (msg or ""):lower():match("^%s*(.-)%s*$")
    local cmd, rest = trimmed:match("^(%S+)%s*(.-)$")

    if cmd == "overlay" then
        local subcmd, arg = (rest or ""):match("^(%S+)%s*(.-)$")
        if not subcmd or subcmd == "" or subcmd == "on" then
            ShowOverlay()
        elseif subcmd == "off" then
            HideOverlay()
        elseif subcmd == "scale" then
            local n = tonumber(arg)
            if n and n >= 0.2 and n <= 5 then
                SetOverlayScale(n)
            else
                print(ADDON_PREFIX .. " usage: /stpoc overlay scale 0.2-5  (1 = default)")
            end
        elseif subcmd == "alpha" then
            local n = tonumber(arg)
            if n and n >= 0 and n <= 1 then
                CFG.globalAlpha = n
                print(ADDON_PREFIX .. string.format(" overlay alpha: %.2f", n))
            else
                print(ADDON_PREFIX .. " usage: /stpoc overlay alpha 0-1  (default 0.70)")
            end
        elseif subcmd == "fadein" then
            local n = tonumber(arg)
            if n and n >= 0.05 and n <= 3 then
                CFG.fadeInTau = n
                print(ADDON_PREFIX .. string.format(" overlay fadeIn: %.2fs", n))
            else
                print(ADDON_PREFIX .. " usage: /stpoc overlay fadein 0.05-3  (default 0.25)")
            end
        elseif subcmd == "fadeout" then
            local n = tonumber(arg)
            if n and n >= 0.05 and n <= 5 then
                CFG.fadeOutTau = n
                print(ADDON_PREFIX .. string.format(" overlay fadeOut: %.2fs", n))
            else
                print(ADDON_PREFIX .. " usage: /stpoc overlay fadeout 0.05-5  (default 0.80)")
            end
        elseif subcmd == "test" then
            local n = tonumber(arg)
            if n and n >= 1 and n <= 5 then
                ForceTestTier(n)
            else
                ForceTestTier(nil)
            end
        elseif subcmd == "add" then
            SetBlendMode("ADD")
        elseif subcmd == "blend" then
            SetBlendMode("BLEND")
        else
            print(ADDON_PREFIX .. " overlay commands:")
            print("  /stpoc overlay on         - enable overlay")
            print("  /stpoc overlay off        - disable overlay")
            print("  /stpoc overlay scale N    - resize (0.2-5, default 1)")
            print("  /stpoc overlay alpha N    - master opacity (0-1, default 0.70)")
            print("  /stpoc overlay fadein N   - fade-in tau (0.05-3s, default 0.25)")
            print("  /stpoc overlay fadeout N  - fade-out tau (0.05-5s, default 0.80)")
            print("  /stpoc overlay test N     - force-show tier N (1-5); 0 or omit = off")
            print("  /stpoc overlay add        - additive blend (glowing fire/lightning)")
            print("  /stpoc overlay blend      - normal alpha blend (solid look)")
        end
        return
    end

    -- Intercept on/off/clear to also manage overlay state
    if cmd == "clear" or cmd == "reset" then
        ResetOverlayAlphas()
    end

    -- Pass through to original handler for everything else
    if originalHandler then
        originalHandler(msg)
    end
end
