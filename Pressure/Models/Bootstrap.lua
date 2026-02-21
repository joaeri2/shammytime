local addonName = ...
if addonName ~= "ShammyTime" then return end

local ShammyTime = _G.ShammyTime
if not ShammyTime then return end

ShammyTime.PressureModels = ShammyTime.PressureModels or {}
