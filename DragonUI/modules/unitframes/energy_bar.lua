local addon = select(2, ...)

-- ============================================================================
-- POWER BARS MODULE
-- DragonUI background/border + texture for PlayerFrameEnergyBar & PlayerFrameRageBar
-- ============================================================================

local _G = _G

-- Semi-transparent background texture
local BG_TEXTURE = "Interface\\AddOns\\DragonUI\\Textures\\Nameplates\\bar-bg-power"

-- Border from castbar atlas
local TEXTURE_PATH = "Interface\\AddOns\\DragonUI\\Textures\\Castbar\\"
local ATLAS_TEXTURE = TEXTURE_PATH .. "uicastingbar2x"

-- UV coordinates from the atlas (border only)
local UV_COORDS = {
    border = {0.412109375, 0.828125, 0.001953125, 0.060546875},
}

-- Bar definitions: { globalName, textGlobalName, texturePath, vertical }
local BARS = {
    {
        globalName = "PlayerFrameEnergyBar",
        textGlobalName = "PlayerFrameEnergyBarText",
        texture = "Interface\\AddOns\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Player-PortraitOn-Bar-Energy",
        vertical = false,
    },
    {
        globalName = "PlayerFrameRageBar",
        textGlobalName = "PlayerFrameRageBarText",
        texture = "Interface\\AddOns\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Player-PortraitOn-Bar-Rage",
        vertical = true,
    },
}

-- Module state
local applied = false
local barTexts = {} -- keyed by globalName

-- ============================================================================
-- TEXT MANAGEMENT
-- ============================================================================

local function GetPlayerConfig()
    return addon.db and addon.db.profile and addon.db.profile.unitframe
        and addon.db.profile.unitframe.player or {}
end

local function UpdateBarText(barGlobalName)
    local text = barTexts[barGlobalName]
    if not text then return end

    local bar = _G[barGlobalName]
    if not bar then return end

    local currentValue = bar:GetValue() or 0
    text:SetText(tostring(math.floor(currentValue)))
end

local function ShowBarText(barGlobalName)
    local text = barTexts[barGlobalName]
    if text then
        UpdateBarText(barGlobalName)
        text:Show()
    end
end

local function HideBarText(barGlobalName)
    local text = barTexts[barGlobalName]
    if text then
        text:Hide()
    end
end

local function SetupAlwaysVisibleForBar(barGlobalName)
    local bar = _G[barGlobalName]
    if bar then bar.DragonUIHoverEnabled = false end
    ShowBarText(barGlobalName)
end

local function SetupHoverBehaviorForBar(barGlobalName)
    HideBarText(barGlobalName)

    local bar = _G[barGlobalName]
    if not bar or bar.DragonUIHoverHooked then return end

    bar:HookScript("OnEnter", function()
        if bar.DragonUIHoverEnabled then
            ShowBarText(barGlobalName)
        end
    end)

    bar:HookScript("OnLeave", function()
        if bar.DragonUIHoverEnabled then
            HideBarText(barGlobalName)
        end
    end)

    bar.DragonUIHoverHooked = true
    bar.DragonUIHoverEnabled = true
end

-- ============================================================================
-- CONFIG CHANGE HANDLING
-- ============================================================================

local function RefreshAllBarTextVisibility()
    if not applied then return end

    local config = GetPlayerConfig()
    local alwaysShow = config and config.showManaTextAlways

    for _, barDef in ipairs(BARS) do
        if alwaysShow then
            SetupAlwaysVisibleForBar(barDef.globalName)
        else
            SetupHoverBehaviorForBar(barDef.globalName)
        end
    end
end

local refreshHooked = false
local function HookRefresh()
    if refreshHooked then return end
    if addon.PlayerFrame and addon.PlayerFrame.RefreshPlayerFrame then
        local origRefresh = addon.PlayerFrame.RefreshPlayerFrame
        addon.PlayerFrame.RefreshPlayerFrame = function(...)
            origRefresh(...)
            RefreshAllBarTextVisibility()
        end
        refreshHooked = true
    end
end

-- ============================================================================
-- APPLY STYLING
-- ============================================================================

local function ApplyBarStyling(barDef)
    local bar = _G[barDef.globalName]
    if not bar then return end

    -- Hide Blizzard's default text
    local blizzardText = _G[barDef.textGlobalName]
    if blizzardText then
        blizzardText:Hide()
        blizzardText:SetAlpha(0)
    end

    if barDef.vertical then
        -- Vertical bar: adjust size and position
        local origW = bar:GetWidth() or 20
        local origH = bar:GetHeight() or 60
        bar:SetSize(origW * 0.7, origH * 0.68)

        local point, relTo, relPoint, xOfs, yOfs = bar:GetPoint()
        bar:ClearAllPoints()
        bar:SetPoint(point, relTo, relPoint, xOfs, yOfs - 12)

        bar:SetStatusBarTexture(barDef.texture)
        bar:SetStatusBarColor(1, 1, 1)

        -- Background (semi-transparent)
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(BG_TEXTURE)
        bg:SetAllPoints()
        bar.DragonUIBackground = bg

        -- Border (from atlas) - rotated 90 degrees for vertical bar
        local border = bar:CreateTexture(nil, "ARTWORK", nil, 0)
        border:SetTexture(ATLAS_TEXTURE)
        -- Rotate 90 degrees clockwise using 8-point SetTexCoord
        -- Format: ULx, ULy, LLx, LLy, URx, URy, LRx, LRy
        local minX, maxX, minY, maxY = unpack(UV_COORDS.border)
        border:SetTexCoord(minX, maxY, maxX, maxY, minX, minY, maxX, minY)
        border:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
        border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
        bar.DragonUIBorder = border
    else
        -- Horizontal bar: resize and reposition
        local origW = bar:GetWidth() or 125
        local origH = bar:GetHeight() or 8
        bar:SetSize(origW * 1.35, origH * 0.7)

        local point, relTo, relPoint, xOfs, yOfs = bar:GetPoint()
        bar:ClearAllPoints()
        bar:SetPoint(point, relTo, relPoint, xOfs - 18, yOfs)

        bar:SetStatusBarTexture(barDef.texture)
        bar:SetStatusBarColor(1, 1, 1)

        -- Background (semi-transparent)
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(BG_TEXTURE)
        bg:SetAllPoints()
        bar.DragonUIBackground = bg

        -- Border (from atlas)
        local border = bar:CreateTexture(nil, "ARTWORK", nil, 0)
        border:SetTexture(ATLAS_TEXTURE)
        border:SetTexCoord(unpack(UV_COORDS.border))
        border:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
        border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
        bar.DragonUIBorder = border
    end

    -- Create text (value only, no max)
    local text = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    text:Hide()
    barTexts[barDef.globalName] = text

    -- Hook SetValue to update text
    hooksecurefunc(bar, "SetValue", function()
        UpdateBarText(barDef.globalName)
    end)
end

local function ApplyAllStyling()
    if applied then return end

    -- Check if first bar exists (both should exist together for HERO class)
    if not _G[BARS[1].globalName] then return end

    applied = true

    for _, barDef in ipairs(BARS) do
        ApplyBarStyling(barDef)
    end

    -- Configure text visibility based on config
    RefreshAllBarTextVisibility()

    -- Hook refresh to re-apply text visibility on config changes
    HookRefresh()
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        ApplyAllStyling()
        -- Retry hook if PlayerFrame wasn't ready yet
        if not refreshHooked then
            HookRefresh()
        end
    end
end)
