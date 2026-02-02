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
    -- Crit satellite ring (layered, aligned)
    CRIT_BG     = M.MEDIA .. "wf_crit_bg_aligned.tga",
    CRIT_BORDER = M.MEDIA .. "wf_crit_border_aligned.tga",
    CRIT_GLOW   = M.MEDIA .. "wf_crit_glow_aligned.tga",
    CRIT_SHADOW = M.MEDIA .. "wf_crit_shadow_aligned.tga",
    -- Procs satellite (fire art)
    PROCS_BG     = M.MEDIA .. "wf_fire_bg.tga",
    PROCS_BORDER = M.MEDIA .. "wf_fire_border.tga",
    PROCS_GLOW   = M.MEDIA .. "wf_fire_glow.tga",
    PROCS_SHADOW = M.MEDIA .. "wf_fire_shadow.tga",
    -- Placeholders: add wf_max_*.tga, wf_min_*.tga, wf_avg_*.tga, wf_procpct_*.tga when ready
    MAX_BG     = M.MEDIA .. "wf_max_bg.tga",
    MAX_BORDER = M.MEDIA .. "wf_max_border.tga",
    MAX_GLOW   = M.MEDIA .. "wf_max_glow.tga",
    MAX_SHADOW = M.MEDIA .. "wf_max_shadow.tga",
    -- Left center satellite (wf_wind_*)
    MIN_BG     = M.MEDIA .. "wf_wind_bg.tga",
    MIN_BORDER = M.MEDIA .. "wf_wind_border.tga",
    MIN_GLOW   = M.MEDIA .. "wf_wind_glow.tga",
    MIN_SHADOW = M.MEDIA .. "wf_wind_shadow.tga",
    -- Lower 3rd left (wf_next_*)
    AVG_BG     = M.MEDIA .. "wf_next_bg.tga",
    AVG_BORDER = M.MEDIA .. "wf_next_border.tga",
    AVG_GLOW   = M.MEDIA .. "wf_next_glow.tga",
    AVG_SHADOW = M.MEDIA .. "wf_next_shadow.tga",
    -- Center-right satellite (wf_sat_*)
    PROCPCT_BG     = M.MEDIA .. "wf_sat_bg.tga",
    PROCPCT_BORDER = M.MEDIA .. "wf_sat_border.tga",
    PROCPCT_GLOW   = M.MEDIA .. "wf_sat_glow.tga",
    PROCPCT_SHADOW = M.MEDIA .. "wf_sat_shadow.tga",
    -- Full-design satellites (single texture, not layered)
    AIR_FULL   = M.MEDIA .. "wf_air_full_256.tga",
    GRASS_FULL = M.MEDIA .. "wf_magic_gras_256.tga",
    GRASS_UPPER_RIGHT = M.MEDIA .. "wf_grass_upper_right.tga",  -- upper right (CRIT% slot)
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
