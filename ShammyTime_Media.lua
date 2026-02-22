-- ShammyTime_Media.lua
-- Single place for Media paths and design constants. Load early (TOC order).
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local ADDON = ...
local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

local M = {}

M.ADDON_NAME = ADDON or "ShammyTime"
M.MEDIA = "Interface\\AddOns\\" .. M.ADDON_NAME .. "\\Media\\"

M.TEX = {
    -- Center ring (512×512): bg, energy, shadow only.
    CENTER_BG     = M.MEDIA .. "v2_wf_bubbles_center_512x512.tga",
    CENTER_ENERGY = M.MEDIA .. "wf_center_energy.tga",
    CENTER_SHADOW = M.MEDIA .. "wf_center_shadow.tga",
    -- Totem bar (layered: back, icons, front, text) 512×512
    TOTEM_BAR_BACK  = M.MEDIA .. "v2_totem_bar_back_512x512.tga",
    TOTEM_BAR_FRONT = M.MEDIA .. "v2_totem_bar_front_512x512.tga",
    -- Weapon imbue bar (layered: back, icons, front, text) 512×512
    IMBUE_BAR_BACK  = M.MEDIA .. "v2_imbue_bar_back_512x512.tga",
    IMBUE_BAR_FRONT = M.MEDIA .. "v2_imbue_bar_front_512x512.tga",
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
    -- Windfury satellite bubbles (v2, 256×256 single texture per position)
    SATELLITE_MIDDLE_RIGHT = M.MEDIA .. "v2_wf_bubbles_middle_right_256x256.tga",   -- 0° mid-right  (MIN)
    SATELLITE_MIDDLE_RIGHT_DIFFUSE_OVERLAY = M.MEDIA .. "v2_wf_bubbles_middle_right_diffuse_overlay_256x256.tga",
    SATELLITE_UPPER_RIGHT  = M.MEDIA .. "v2_wf_bubbles_upper_right_256x256.tga",    -- 60° top-right (MAX)
    SATELLITE_UPPER_RIGHT_DIFFUSE_OVERLAY = M.MEDIA .. "v2_wf_bubbles_upper_right_diffuse_overlay_256x256.tga",
    SATELLITE_UPPER_LEFT   = M.MEDIA .. "v2_wf_bubbles_upper_left_256x256.tga",    -- 120° upper-left (AVG)
    SATELLITE_UPPER_LEFT_DIFFUSE_OVERLAY = M.MEDIA .. "v2_wf_bubbles_upper_left_diffuse_overlay_256x256.tga",
    SATELLITE_MIDDLE_LEFT  = M.MEDIA .. "v2_wf_bubbles_middle_left_256x256.tga",   -- 180° mid-left (PROCS)
    SATELLITE_MIDDLE_LEFT_DIFFUSE_OVERLAY = M.MEDIA .. "v2_wf_bubbles_middle_left_diffuse_overlay_256x256.tga",
    SATELLITE_BOTTOM_LEFT  = M.MEDIA .. "v2_wf_bubbles_bottom_left_256x256.tga",   -- 240° down-left (PROC%)
    SATELLITE_BOTTOM_LEFT_DIFFUSE_OVERLAY = M.MEDIA .. "v2_wf_bubbles_bottom_left_diffuse_overlay_256x256.tga",
    SATELLITE_BOTTOM_RIGHT = M.MEDIA .. "v2_wf_bubbles_bottom_right_256x256.tga",  -- 300° down-right (CRIT%)
    SATELLITE_BOTTOM_RIGHT_DIFFUSE_OVERLAY = M.MEDIA .. "v2_wf_bubbles_bottom_right_diffuse_overlay_256x256.tga",
    -- Legacy full-design satellites (single texture, kept for reference)
    AIR_FULL   = M.MEDIA .. "wf_air_full_256.tga",
    GRASS_FULL = M.MEDIA .. "wf_magic_gras_256.tga",
    GRASS_UPPER_RIGHT = M.MEDIA .. "wf_grass_upper_right.tga",
    -- Orb set (satellites / totems)
    ORB_BG     = M.MEDIA .. "orb_bg.tga",
    ORB_BORDER = M.MEDIA .. "orb_border.tga",
    GLOW       = M.MEDIA .. "glow_soft.tga",
    RING_RUNES = M.MEDIA .. "ring_runes.tga",
    ASSET_TEST = M.MEDIA .. "wf_asset_test.tga",
    -- Shamanistic Focus proc indicator (light on / light off, 512×512)
    FOCUS_ON  = M.MEDIA .. "v2_shamanistic_focus_on_256x256.tga",
    FOCUS_OFF = M.MEDIA .. "v2_shamanistic_focus_off_256x256.tga",
    -- Elemental shield (Lightning Shield / Water Shield): off = no shield, on = active (overlay with alpha), 256×256
    LIGHTNING_SHIELD_OFF = M.MEDIA .. "v2_lightning_shield_off_256x256.tga",
    LIGHTNING_SHIELD_ON  = M.MEDIA .. "v2_lightning_shield_on_256x256.tga",
    -- Windfury ICD indicator (on = WF ready, off = ICD active / WF on cooldown), 256×256
    WF_ICD_ON  = M.MEDIA .. "v2_windfury_icd_on_256x256.tga",
    WF_ICD_OFF = M.MEDIA .. "v2_windfury_icd_off_256x256.tga",
    -- Stagger bar (layered: back, bars, front, delta text) 512×512
    STAGGER_BACK  = M.MEDIA .. "v2_stagger_back_512x512.tga",
    STAGGER_FRONT = M.MEDIA .. "v2_stagger_front_512x512.tga",
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
