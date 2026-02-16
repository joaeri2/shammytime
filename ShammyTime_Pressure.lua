-- ShammyTime_Pressure.lua
-- Clean pressure asset stack test frame.
-- All pressure textures are overlaid 1:1 at 1024x1024 with default scale 0.5.

local ShammyTime = _G.ShammyTime
if not ShammyTime then return end

local M = _G.ShammyTime_Media
if not M then return end

local SIZE = 1024
local DEFAULT_SCALE = 0.5
local CROP_TOP = 0.20
local CROP_BOTTOM = 0.20
local VISIBLE_HEIGHT_FRACTION = 1 - CROP_TOP - CROP_BOTTOM
if VISIBLE_HEIGHT_FRACTION <= 0 then
    VISIBLE_HEIGHT_FRACTION = 1
end
local DISPLAY_WIDTH = SIZE
local DISPLAY_HEIGHT = SIZE * VISIBLE_HEIGHT_FRACTION

local STACK = {
    { key = "background",       file = "Pressure\\v2_pressure_bar_background_1024x1024.tga",          layer = "BACKGROUND", sub = 0 },
    { key = "backgroundSquares",file = "Pressure\\v2_pressure_bar_background_squares_1024x1024.tga",  layer = "ARTWORK",    sub = 0 },
    { key = "colorOverlay",     file = "Pressure\\v2_pressure_bar_color_overlay_on_1024x1024.tga",    layer = "ARTWORK",    sub = 1 },
    { key = "gaugeZero",        file = "Pressure\\v2_pressure_gauge_zero_pct_1024x1024.tga",          layer = "ARTWORK",    sub = 2 },
    { key = "gaugeTen",         file = "Pressure\\v2_pressure_gauge_ten_pct_1024x1024.tga",           layer = "ARTWORK",    sub = 3 },
    { key = "gaugeFifty",       file = "Pressure\\v2_pressure_gauge_fifty_pct_1024x1024.tga",         layer = "ARTWORK",    sub = 4 },
    { key = "gaugeSeventyFive", file = "Pressure\\v2_pressure_gauge_seventyfive_pct_1024x1024.tga",   layer = "ARTWORK",    sub = 5 },
    { key = "gaugeHundred",     file = "Pressure\\v2_pressure_gauge_hundred_pct_1024x1024.tga",       layer = "ARTWORK",    sub = 6 },
}

local frame = CreateFrame("Frame", "ShammyTimePressureFrame", UIParent)
frame:SetSize(DISPLAY_WIDTH, DISPLAY_HEIGHT)
frame:SetPoint("CENTER", 0, 0)
frame:SetScale(DEFAULT_SCALE)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame.textures = {}

for _, info in ipairs(STACK) do
    local tex = frame:CreateTexture(nil, info.layer)
    tex:SetDrawLayer(info.layer, info.sub)
    tex:SetTexture(M.MEDIA .. info.file)
    tex:SetTexCoord(0, 1, CROP_TOP, 1 - CROP_BOTTOM)
    tex:SetAllPoints(frame)
    frame.textures[info.key] = tex
end

frame:Show()

-- Optional helper for quick scale tweaks in-game:
-- /script ShammyTimePressureSetScale(0.5)
function ShammyTimePressureSetScale(scale)
    if type(scale) ~= "number" or scale <= 0 then return end

    local f = _G.ShammyTimePressureFrame
    if not f then return end

    f:SetScale(scale)
    print(string.format("ShammyTime Pressure scale: %.2f", scale))
end
