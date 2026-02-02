-- ShammyTime_Media.lua
-- Single place for Media paths and design constants. Load early (TOC order).
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local ADDON = ...
local M = {}

M.ADDON_NAME = ADDON or "ShammyTime"
M.MEDIA = "Interface\\AddOns\\" .. M.ADDON_NAME .. "\\Media\\"

M.TEX = {
    -- Center ring (512×512, layered)
    CENTER_BG     = M.MEDIA .. "wf_center_bg.tga",
    CENTER_BORDER = M.MEDIA .. "wf_center_border.tga",
    CENTER_RUNES  = M.MEDIA .. "wf_center_runes.tga",
    CENTER_ENERGY = M.MEDIA .. "wf_center_energy.tga",
    CENTER_SHADOW = M.MEDIA .. "wf_center_shadow.tga",
    -- Orb set (satellites / totems)
    ORB_BG     = M.MEDIA .. "orb_bg.tga",
    ORB_BORDER = M.MEDIA .. "orb_border.tga",
    GLOW       = M.MEDIA .. "glow_soft.tga",
    RING_RUNES = M.MEDIA .. "ring_runes.tga",
    ASSET_TEST = M.MEDIA .. "wf_asset_test.tga",
}

-- Optional font (use GameFontNormal etc. if not set)
M.FONT = {
    MAIN = M.MEDIA .. "font.ttf",
}

-- Radial animation timings (seconds)
M.RADIAL = {
    OPEN_DURATION   = 0.16,
    SATELLITE_STAGGER = 0.03,
    SATELLITE_MOVE   = 0.18,
    HOLD_DURATION   = 2.7,
    CLOSE_DURATION  = 0.18,
    RUNE_ROTATION_DEG = 25,
}

-- Windfury damage correlation window (seconds) after SPELL_EXTRA_ATTACKS
M.WF_CORRELATION_WINDOW = 0.4

-- Expose for other ShammyTime Lua files (no require in WoW)
ShammyTime_Media = M
