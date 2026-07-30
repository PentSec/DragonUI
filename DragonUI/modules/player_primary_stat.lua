local addon = select(2, ...)
local L = addon.L

-- ============================================================================
-- MODULE REGISTRATION
-- ============================================================================

local Module = {
    applied = false,
}
addon.PlayerPrimaryStatModule = Module

if addon.RegisterModule then
    addon:RegisterModule("playerPrimaryStat", Module,
        (L and L["PlayerPrimaryStat"]) or "PlayerPrimaryStat",
        (L and L["Primary stat icon movability widget"]) or "Primary stat icon movability widget")
end

-- ============================================================================
-- HELPERS
-- ============================================================================

local function IsEditorActive()
    return addon.EditorMode and addon.EditorMode.IsActive and addon.EditorMode:IsActive()
end

local function IsModuleEnabled()
    return addon.db and addon.db.profile and addon.db.profile.modules
        and addon.db.profile.modules.playerPrimaryStat
        and addon.db.profile.modules.playerPrimaryStat.enabled
end

-- ============================================================================
-- PLAYER PRIMARY STAT
-- ============================================================================

local playerAnchor
local playerDeferredUpdate = false
local playerOriginal_SetPoint
local movingWidget = false

local PLAYER_DEFAULT_ANCHOR = "TOPLEFT"
local PLAYER_DEFAULT_X = 80
local PLAYER_DEFAULT_Y = -6

local function ApplyPlayerAnchorPosition()
    if not playerAnchor then return end
    if InCombatLockdown() then return end

    local cfg = addon.db and addon.db.profile and addon.db.profile.widgets
        and addon.db.profile.widgets.playerPrimaryStat
    if not cfg then return end

    playerAnchor:ClearAllPoints()
    playerAnchor:SetPoint(cfg.anchor or PLAYER_DEFAULT_ANCHOR, UIParent,
        cfg.anchor or PLAYER_DEFAULT_ANCHOR, cfg.posX or PLAYER_DEFAULT_X, cfg.posY or PLAYER_DEFAULT_Y)
end

local function ApplyPlayerPosition()
    if InCombatLockdown() then
        playerDeferredUpdate = true
        return
    end

    local stat = PlayerPrimaryStat
    if not stat or not playerAnchor then return end

    movingWidget = true
    stat:ClearAllPoints()
    stat:SetPoint("CENTER", playerAnchor, "CENTER", 0, 0)
    movingWidget = false
end

local function ApplyPlayerTextures()
    local stat = PlayerPrimaryStat
    if not stat then return end

    if stat.Border then
        stat.Border:SetTexture(nil)
        stat.Border:SetAtlas(nil)
        stat.Border:SetTexture("Interface\\AddOns\\DragonUI\\Textures\\UI-Frame-PortraitMetal-CornerTopLeft.blp")
        stat.Border:ClearAllPoints()
        stat.Border:SetPoint("CENTER", stat, "CENTER", 0, 2)
        stat.Border:SetSize(34, 34)
    end

    for i = 1, stat:GetNumRegions() do
        local region = select(i, stat:GetRegions())
        if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "HIGHLIGHT" then
            region:SetTexture(nil)
        end
    end

    local ht = stat:CreateTexture(nil, "HIGHLIGHT")
    ht:SetPoint("CENTER", stat, "CENTER", 0, 0)
    ht:SetSize(34, 34)
    ht:SetTexture("Interface\\AddOns\\DragonUI\\Textures\\baghighlight2.blp")
    ht:SetBlendMode("ADD")
    stat:SetHighlightTexture(ht)
end

-- ============================================================================
-- TARGET PRIMARY STAT
-- ============================================================================

local targetAnchor
local targetDeferredUpdate = false
local targetOriginal_SetPoint
local targetMovingWidget = false

local TARGET_DEFAULT_ANCHOR = "TOPRIGHT"
local TARGET_DEFAULT_X = -80
local TARGET_DEFAULT_Y = -6

local function ApplyTargetAnchorPosition()
    if not targetAnchor then return end
    if InCombatLockdown() then return end

    local cfg = addon.db and addon.db.profile and addon.db.profile.widgets
        and addon.db.profile.widgets.targetPrimaryStat
    if not cfg then return end

    targetAnchor:ClearAllPoints()
    targetAnchor:SetPoint(cfg.anchor or TARGET_DEFAULT_ANCHOR, UIParent,
        cfg.anchor or TARGET_DEFAULT_ANCHOR, cfg.posX or TARGET_DEFAULT_X, cfg.posY or TARGET_DEFAULT_Y)
end

local function ApplyTargetPosition()
    if InCombatLockdown() then
        targetDeferredUpdate = true
        return
    end

    local stat = TargetFramePrimaryStat
    if not stat or not targetAnchor then return end

    targetMovingWidget = true
    stat:ClearAllPoints()
    stat:SetPoint("CENTER", targetAnchor, "CENTER", 0, 0)
    targetMovingWidget = false
end

local function ApplyTargetTextures()
    local stat = TargetFramePrimaryStat
    if not stat then return end

    if stat.Border then
        stat.Border:SetTexture(nil)
        stat.Border:SetAtlas(nil)
        stat.Border:SetTexture("Interface\\AddOns\\DragonUI\\Textures\\UI-Frame-PortraitMetal-CornerTopLeft.blp")
        stat.Border:ClearAllPoints()
        stat.Border:SetPoint("CENTER", stat, "CENTER", 0, 2)
        stat.Border:SetSize(34, 34)
    end

    for i = 1, stat:GetNumRegions() do
        local region = select(i, stat:GetRegions())
        if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "HIGHLIGHT" then
            region:SetTexture(nil)
        end
    end

    local ht = stat:CreateTexture(nil, "HIGHLIGHT")
    ht:SetPoint("CENTER", stat, "CENTER", 0, 0)
    ht:SetSize(34, 34)
    ht:SetTexture("Interface\\AddOns\\DragonUI\\Textures\\baghighlight2.blp")
    ht:SetBlendMode("ADD")
    stat:SetHighlightTexture(ht)
end

-- ============================================================================
-- APPLY / RESTORE (idempotent)
-- ============================================================================

function addon.ApplyPlayerPrimaryStatSystem()
    if Module.applied then return end
    if not PlayerPrimaryStat or not TargetFramePrimaryStat then return end

    Module.applied = true

    -- Create anchors
    playerAnchor = addon.CreateUIFrame(30, 30, "PlayerPrimaryStat")
    targetAnchor = addon.CreateUIFrame(30, 30, "TargetPrimaryStat")

    -- Hook SetPoint (block Blizzard repositioning during editor mode)
    playerOriginal_SetPoint = PlayerPrimaryStat.SetPoint
    PlayerPrimaryStat.SetPoint = function(self, ...)
        if not movingWidget and IsEditorActive() then return end
        return playerOriginal_SetPoint(self, ...)
    end

    targetOriginal_SetPoint = TargetFramePrimaryStat.SetPoint
    TargetFramePrimaryStat.SetPoint = function(self, ...)
        if not targetMovingWidget and IsEditorActive() then return end
        return targetOriginal_SetPoint(self, ...)
    end

    -- Register editable frames FIRST — registration is critical, textures are cosmetic
    addon:RegisterEditableFrame({
        name = "playerPrimaryStat",
        frame = playerAnchor,
        blizzardFrame = PlayerPrimaryStat,
        configPath = {"widgets", "playerPrimaryStat"},
        editorVisible = function() return true end,
        showTest = function()
            playerAnchor:Show()
            local cfg = addon.db.profile.widgets.playerPrimaryStat
            if cfg and not cfg.custom_position then
                playerAnchor:ClearAllPoints()
                playerAnchor:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 88, -2)
            else
                ApplyPlayerAnchorPosition()
            end
        end,
        onHide = function()
            local w = addon.db.profile.widgets.playerPrimaryStat
            if w then
                local isDefault = w.anchor == PLAYER_DEFAULT_ANCHOR
                    and math.abs((w.posX or 0) - PLAYER_DEFAULT_X) <= 5
                    and math.abs((w.posY or 0) - PLAYER_DEFAULT_Y) <= 5
                w.custom_position = not isDefault
            end
            ApplyPlayerAnchorPosition()
            ApplyPlayerPosition()
        end,
        module = Module,
    })

    addon:RegisterEditableFrame({
        name = "targetPrimaryStat",
        frame = targetAnchor,
        blizzardFrame = TargetFramePrimaryStat,
        configPath = {"widgets", "targetPrimaryStat"},
        editorVisible = function() return true end,
        showTest = function()
            targetAnchor:Show()
            local cfg = addon.db.profile.widgets.targetPrimaryStat
            if cfg and not cfg.custom_position then
                targetAnchor:ClearAllPoints()
                targetAnchor:SetPoint("TOPRIGHT", TargetFrame, "TOPRIGHT", -88, -2)
            else
                ApplyTargetAnchorPosition()
            end
        end,
        onHide = function()
            local w = addon.db.profile.widgets.targetPrimaryStat
            if w then
                local isDefault = w.anchor == TARGET_DEFAULT_ANCHOR
                    and math.abs((w.posX or 0) - TARGET_DEFAULT_X) <= 5
                    and math.abs((w.posY or 0) - TARGET_DEFAULT_Y) <= 5
                w.custom_position = not isDefault
            end
            ApplyTargetAnchorPosition()
            ApplyTargetPosition()
        end,
        module = Module,
    })

    -- Combat regen handler
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(self, event)
        if playerDeferredUpdate then
            playerDeferredUpdate = false
            ApplyPlayerAnchorPosition()
            ApplyPlayerPosition()
        end
        if targetDeferredUpdate then
            targetDeferredUpdate = false
            ApplyTargetAnchorPosition()
            ApplyTargetPosition()
        end
    end)

    -- Apply textures in pcall — cosmetic, must not block positioning
    pcall(ApplyPlayerTextures)
    pcall(ApplyTargetTextures)

    -- Initial positioning
    ApplyPlayerAnchorPosition()
    ApplyPlayerPosition()
    ApplyTargetAnchorPosition()
    ApplyTargetPosition()
end

function addon.RestorePlayerPrimaryStatSystem()
    if not Module.applied then return end

    Module.applied = false

    if playerAnchor then playerAnchor:Hide() end
    if targetAnchor then targetAnchor:Hide() end

    if playerOriginal_SetPoint then
        PlayerPrimaryStat.SetPoint = playerOriginal_SetPoint
        playerOriginal_SetPoint = nil
    end

    if targetOriginal_SetPoint then
        TargetFramePrimaryStat.SetPoint = targetOriginal_SetPoint
        targetOriginal_SetPoint = nil
    end

    if PlayerPrimaryStat then
        PlayerPrimaryStat:ClearAllPoints()
        PlayerPrimaryStat:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 88, -2)
    end

    if TargetFramePrimaryStat then
        TargetFramePrimaryStat:ClearAllPoints()
        TargetFramePrimaryStat:SetPoint("TOPRIGHT", TargetFrame, "TOPRIGHT", -88, -2)
    end
end

-- ============================================================================
-- SELF-INITIALIZATION (Guia_NewModules.md: event-driven pattern)
-- ============================================================================

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "DragonUI" then
        if not IsModuleEnabled() then return end

        addon:After(0.5, function()
            if addon.db and addon.db.RegisterCallback then
                addon.db.RegisterCallback(addon, "OnProfileChanged", function()
                    if IsModuleEnabled() then
                        addon.ApplyPlayerPrimaryStatSystem()
                    else
                        addon.RestorePlayerPrimaryStatSystem()
                    end
                end)
            end
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not IsModuleEnabled() then return end
        addon.ApplyPlayerPrimaryStatSystem()
    end
end)
