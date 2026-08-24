-- ============================================================================
-- DragonUI - DurabilityFrame Movability Widget
-- Makes the DurabilityFrame (armor durability alert) movable via Editor Mode
-- Coexists with Minimap module's DurabilityFrame handling (capture bars logic)
-- ============================================================================

local addon = select(2, ...)
local L = addon.L

-- ============================================================================
-- MODULE REGISTRATION
-- ============================================================================

local Module = {
    applied = false,
}
addon.DurabilityFrameModule = Module

if addon.RegisterModule then
    addon:RegisterModule("durabilityframe", Module,
        L["DurabilityFrameWidget"],
        L["Durability frame movability widget"])
end

-- ============================================================================
-- HELPERS
-- ============================================================================

local function IsEditorActive()
    return addon.EditorMode and addon.EditorMode.IsActive and addon.EditorMode:IsActive()
end

local function IsModuleEnabled()
    return addon.db and addon.db.profile and addon.db.profile.modules
        and addon.db.profile.modules.durabilityframe
        and addon.db.profile.modules.durabilityframe.enabled
end

-- Check if minimap module is controlling DurabilityFrame
local function IsMinimapControllingDurability()
    return addon.MinimapModule and addon.MinimapModule.applied
end

-- ============================================================================
-- STATE
-- ============================================================================

local durabilityAnchor
local durabilityDeferredUpdate = false
local durabilityOriginal_SetPoint
local movingWidget = false

local DEFAULT_ANCHOR = "TOP"
local DEFAULT_X = -15
local DEFAULT_Y = -5

-- Get actual DurabilityFrame dimensions (accounting for scale)
local function GetDurabilityFrameSize()
    if DurabilityFrame then
        local w = DurabilityFrame:GetWidth()
        local h = DurabilityFrame:GetHeight()
        local s = DurabilityFrame:GetScale() or 1
        if w and w > 0 and h and h > 0 then
            return w * s, h * s
        end
    end
    return 58, 58 -- fallback (base size ~58x58)
end

-- ============================================================================
-- POSITION FUNCTIONS (idempotent)
-- ============================================================================

local function ApplyDurabilityAnchorPosition()
    if not durabilityAnchor then return end
    if InCombatLockdown() then return end

    local cfg = addon.db and addon.db.profile and addon.db.profile.widgets
        and addon.db.profile.widgets.durabilityframe
    if not cfg then return end

    durabilityAnchor:ClearAllPoints()
    durabilityAnchor:SetPoint(cfg.anchor or DEFAULT_ANCHOR, UIParent,
        cfg.anchor or DEFAULT_ANCHOR, cfg.posX or DEFAULT_X, cfg.posY or DEFAULT_Y)
end

local function ApplyDurabilityPosition()
    if InCombatLockdown() then
        durabilityDeferredUpdate = true
        return
    end

    if not DurabilityFrame or not durabilityAnchor then return end

    movingWidget = true
    DurabilityFrame:ClearAllPoints()
    DurabilityFrame:SetPoint("CENTER", durabilityAnchor, "CENTER", 0, 0)
    movingWidget = false
end

-- ============================================================================
-- APPLY / RESTORE (idempotent)
-- ============================================================================

function addon.ApplyDurabilityFrameSystem()
    if Module.applied then return end
    if not DurabilityFrame then return end

    Module.applied = true

    -- Create anchor with actual DurabilityFrame dimensions
    local w, h = GetDurabilityFrameSize()
    durabilityAnchor = addon.CreateUIFrame(w, h, "DurabilityFrameWidget")

    -- Hook SetPoint to prevent Blizzard/Ascension from overriding our position
    -- Only redirect when user has custom position OR editor is active
    -- If minimap module is controlling, let it handle capture bars unless custom_position
    durabilityOriginal_SetPoint = DurabilityFrame.SetPoint
    DurabilityFrame.SetPoint = function(self, ...)
        -- Allow our own SetPoint calls through
        if movingWidget then
            return durabilityOriginal_SetPoint(self, ...)
        end

        local cfg = addon.db and addon.db.profile and addon.db.profile.widgets
            and addon.db.profile.widgets.durabilityframe

        -- If user has custom position, always redirect to our anchor (override minimap)
        if cfg and cfg.custom_position and durabilityAnchor then
            ApplyDurabilityPosition()
            return
        end

        -- Block Blizzard SetPoint while editor is active
        if IsEditorActive() then return end

        -- If minimap module is controlling and no custom position, let minimap handle it
        if IsMinimapControllingDurability() then
            return durabilityOriginal_SetPoint(self, ...)
        end

        -- Otherwise allow Blizzard to position normally
        return durabilityOriginal_SetPoint(self, ...)
    end

    -- Register editable frame FIRST — registration is critical, textures are cosmetic
    addon:RegisterEditableFrame({
        name = "durabilityframe",
        frame = durabilityAnchor,
        blizzardFrame = DurabilityFrame,
        configPath = {"widgets", "durabilityframe"},
        editorVisible = function() return true end,
        showTest = function()
            -- Position anchor at DurabilityFrame's actual current location
            durabilityAnchor:ClearAllPoints()
            if DurabilityFrame:IsShown() then
                local point, relativeTo, relativePoint, xOfs, yOfs = DurabilityFrame:GetPoint()
                if point and relativeTo then
                    durabilityAnchor:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)
                else
                    -- Fallback: below minimap (where minimap module puts it)
                    durabilityAnchor:SetPoint("TOP", Minimap, "BOTTOM", -15, -5)
                end
            else
                -- If not visible, use minimap-relative position (where minimap module puts it)
                durabilityAnchor:SetPoint("TOP", Minimap, "BOTTOM", -15, -5)
            end
            durabilityAnchor:Show()
            -- Also show the actual frame
            DurabilityFrame:ClearAllPoints()
            DurabilityFrame:SetPoint("CENTER", durabilityAnchor, "CENTER", 0, 0)
            DurabilityFrame:Show()
        end,
        onHide = function()
            local w = addon.db.profile.widgets.durabilityframe
            if w then
                local isDefault = w.anchor == DEFAULT_ANCHOR
                    and math.abs((w.posX or 0) - DEFAULT_X) <= 5
                    and math.abs((w.posY or 0) - DEFAULT_Y) <= 5
                w.custom_position = not isDefault
            end
            ApplyDurabilityAnchorPosition()
            ApplyDurabilityPosition()
        end,
        module = Module,
    })

    -- Combat regen handler
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(self, event)
        if durabilityDeferredUpdate then
            durabilityDeferredUpdate = false
            ApplyDurabilityAnchorPosition()
            ApplyDurabilityPosition()
        end
    end)

    -- Initial positioning: only apply if user has custom position
    local cfg = addon.db and addon.db.profile and addon.db.profile.widgets
        and addon.db.profile.widgets.durabilityframe
    if cfg and cfg.custom_position then
        ApplyDurabilityAnchorPosition()
        ApplyDurabilityPosition()
    end
end

function addon.RestoreDurabilityFrameSystem()
    if not Module.applied then return end

    Module.applied = false

    if durabilityAnchor then durabilityAnchor:Hide() end

    -- Restore original SetPoint
    if durabilityOriginal_SetPoint then
        DurabilityFrame.SetPoint = durabilityOriginal_SetPoint
        durabilityOriginal_SetPoint = nil
    end

    -- Return frame to Blizzard default position (below MinimapCluster)
    -- Minimap module will re-apply its positioning if it's active
    if DurabilityFrame then
        DurabilityFrame:ClearAllPoints()
        DurabilityFrame:SetPoint("TOP", Minimap, "BOTTOM", -15, -5)
        DurabilityFrame:SetScale(1.0)
    end
end

-- ============================================================================
-- SELF-INITIALIZATION
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
                        addon.ApplyDurabilityFrameSystem()
                    else
                        addon.RestoreDurabilityFrameSystem()
                    end
                end)
            end
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not IsModuleEnabled() then return end
        addon.ApplyDurabilityFrameSystem()
    end
end)