-- AssetTest.lua
-- Standalone visual tester for Media textures. /wfassets toggles the frame and prints paths.
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local M = ShammyTime_Media
if not M then return end

local TEX = M.TEX
local assetTestFrame

local function CreateAssetTestFrame()
    if assetTestFrame then return assetTestFrame end

    local f = CreateFrame("Frame", "ShammyTimeAssetTest", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetSize(420, 280)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.1, 0.1, 0.12, 0.95)
    f:SetBackdropBorderColor(0.45, 0.42, 0.38, 1)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("ShammyTime Media — Texture Test")
    title:SetTextColor(1, 0.9, 0.5)

    -- Stupid-simple load: one texture, center (source 1024x1024, show 256)
    if TEX.ASSET_TEST then
        local stupid = f:CreateTexture(nil, "ARTWORK")
        stupid:SetSize(256, 256)
        stupid:SetPoint("CENTER", 0, 20)
        stupid:SetTexture(TEX.ASSET_TEST)
        stupid:SetTexCoord(0, 1, 0, 1)
        stupid:SetVertexColor(1, 1, 1, 1)
        local stupidLab = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        stupidLab:SetPoint("TOP", stupid, "BOTTOM", 0, -4)
        stupidLab:SetText("wf_asset_test.tga (1024×1024)")
        stupidLab:SetTextColor(0.9, 0.9, 0.5)
    end

    local paths = { TEX.ORB_BG, TEX.ORB_BORDER, TEX.GLOW, TEX.RING_RUNES }
    local labels = { "orb_bg", "orb_border", "glow_soft", "ring_runes" }
    local sizes = { 128, 128, 256, 256 }

    for i = 1, 4 do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 30 + col * 200
        local y = -50 - row * 110
        local size = sizes[i] and math.min(sizes[i], 128) or 128

        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetSize(size, size)
        tex:SetPoint("TOPLEFT", x, y)
        tex:SetTexture(paths[i])
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetVertexColor(1, 1, 1, 1)

        local lab = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lab:SetPoint("TOP", tex, "BOTTOM", 0, -4)
        lab:SetText(labels[i] or ("Tex " .. i))
        lab:SetTextColor(0.75, 0.75, 0.75)
    end

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOM", 0, 10)
    hint:SetText("/wfassets to close — Add .tga files to Media/ if you see green/missing")
    hint:SetTextColor(0.6, 0.6, 0.6)

    assetTestFrame = f
    return f
end

local function ToggleAssetTest()
    local f = CreateAssetTestFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        -- Print resolved paths to chat
        print("|cffffcc00ShammyTime Media paths:|r")
        print("  " .. (TEX.ORB_BG or ""))
        print("  " .. (TEX.ORB_BORDER or ""))
        print("  " .. (TEX.GLOW or ""))
        print("  " .. (TEX.RING_RUNES or ""))
        if TEX.ASSET_TEST then print("  " .. TEX.ASSET_TEST) end
    end
end

SLASH_WFASSETS1 = "/wfassets"
SlashCmdList["WFASSETS"] = function()
    ToggleAssetTest()
end
