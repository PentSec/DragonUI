local addon = select(2, ...)

-- ============================================================================
-- POWER BARS MODULE
-- DragonUI background/border + texture for player & target classless power bars
-- (PlayerFrameClassless* and TargetFrameClassless*)
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

-- Bar definitions: { globalName, textGlobalName, texturePath, vertical, anchorTo, anchorOffset }
local BARS = {
    {
        globalName = "PlayerFrameClasslessEnergyBar",
        textGlobalName = "PlayerFrameClasslessEnergyBarText",
        texture = "Interface\\AddOns\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Player-PortraitOn-Bar-Energy",
        vertical = false,
    },
    {
        globalName = "PlayerFrameClasslessRageBar",
        textGlobalName = "PlayerFrameClasslessRageBarText",
        texture = "Interface\\AddOns\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Player-PortraitOn-Bar-Rage",
        vertical = false,
        anchorTo = "PlayerFrameClasslessEnergyBar",
        anchorOffset = -1,
    },
    {
        globalName = "TargetFrameClasslessEnergyBar",
        textGlobalName = "TargetFrameClasslessEnergyBarText",
        texture = "Interface\\AddOns\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Player-PortraitOn-Bar-Energy",
        vertical = false,
        xOffset = 12, -- 20px right of the player pair's position
        widthBonus = 10,
    },
    {
        globalName = "TargetFrameClasslessRageBar",
        textGlobalName = "TargetFrameClasslessRageBarText",
        texture = "Interface\\AddOns\\DragonUI\\Textures\\UnitFrames\\Bars\\UI-HUD-UnitFrame-Player-PortraitOn-Bar-Rage",
        vertical = false,
        anchorTo = "TargetFrameClasslessEnergyBar",
        anchorOffset = -1,
        widthBonus = 10,
    },
}

-- Module state
local applied = false
local barTexts = {} -- keyed by globalName

local function FindBarDef(globalName)
    for _, barDef in ipairs(BARS) do
        if barDef.globalName == globalName then
            return barDef
        end
    end
end

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
-- RUNE FRAME ANCHOR
-- ============================================================================

local function AnchorRuneFrame()
    local rageDef = FindBarDef("PlayerFrameClasslessRageBar")
    if not rageDef then return end

    local rageBar = _G[rageDef.globalName]
    if not rageBar then return end

    local runeFrame = _G["RuneFrame"]
    if not runeFrame then return end

    -- Anchor the container just below the rage bar
    runeFrame:ClearAllPoints()
    runeFrame:SetPoint("TOP", rageBar, "BOTTOM", 0, -4)

    -- Re-anchor the rune buttons as a row inside the container so they follow it.
    -- player.lua's SetupRuneFrame anchors them to PlayerFrame; we run later in the
    -- RefreshPlayerFrame hook so our layout wins.
    for index = 1, 6 do
        local button = _G["RuneButtonIndividual" .. index]
        if button then
            button:ClearAllPoints()
            if index > 1 then
                button:SetPoint("LEFT", _G["RuneButtonIndividual" .. (index - 1)], "RIGHT", 3, 0)
            else
                button:SetPoint("LEFT", runeFrame, "LEFT", 0, 0)
            end
        end
    end
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
            AnchorRuneFrame()
        end
        refreshHooked = true
    end
end

-- ============================================================================
-- POSITION PROTECTION
-- ============================================================================

-- The custom server re-anchors the classless power bars after our one-shot
-- apply, which desyncs the stack. Post-hook SetPoint so our position is
-- re-asserted in the same frame after ANY repositioning (same pattern as
-- player.lua and minimap.lua).
local function ProtectBarPosition(barDef)
    local bar = _G[barDef.globalName]
    if not bar or bar.DragonUISetPointHooked then return end

    hooksecurefunc(bar, "SetPoint", function()
        if bar.DragonUI_SettingPoint then return end

        bar.DragonUI_SettingPoint = true
        bar:ClearAllPoints()
        if barDef.anchorTo then
            local anchorBar = _G[barDef.anchorTo]
            if anchorBar then
                bar:SetPoint("TOP", anchorBar, "BOTTOM", 0, barDef.anchorOffset or -4)
            end
        elseif bar.DragonUIAnchor then
            bar:SetPoint(unpack(bar.DragonUIAnchor))
        end
        bar.DragonUI_SettingPoint = nil
    end)

    bar.DragonUISetPointHooked = true
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
        -- Horizontal bar: resize and reposition (20px narrower than the profile
        -- frame so it stays inside the player frame)
        local origW = bar:GetWidth() or 125
        local origH = bar:GetHeight() or 8
        bar:SetSize(((origW * 1.35) - 35) + (barDef.widthBonus or 0), origH * 0.7)

        if barDef.anchorTo then
            -- Anchor below another bar (rage below energy)
            local anchorBar = _G[barDef.anchorTo]
            if anchorBar then
                bar:ClearAllPoints()
                bar:SetPoint("TOP", anchorBar, "BOTTOM", 0, barDef.anchorOffset or -4)
            end
        else
            -- Capture our target anchor so ProtectBarPosition can re-assert it
            -- after any Blizzard/custom-server repositioning
            local point, relTo, relPoint, xOfs, yOfs = bar:GetPoint()
            if point then
                bar.DragonUIAnchor = { point, relTo, relPoint, (xOfs or 0) + (barDef.xOffset or -8), (yOfs or 0) - 2 }
                bar:ClearAllPoints()
                bar:SetPoint(unpack(bar.DragonUIAnchor))
            end
        end

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

    -- Check that at least one classless bar exists before applying
    -- (player and target bars each have their own pair)
    local anyExists = false
    for _, barDef in ipairs(BARS) do
        if _G[barDef.globalName] then
            anyExists = true
            break
        end
    end
    if not anyExists then return end

    applied = true

    for _, barDef in ipairs(BARS) do
        ApplyBarStyling(barDef)
        ProtectBarPosition(barDef)
    end

    -- Anchor RuneFrame below the rage bar
    AnchorRuneFrame()

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
