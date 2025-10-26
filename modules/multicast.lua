local addon = select(2, ...);
local class = addon._class;
local noop = addon._noop;
local InCombatLockdown = InCombatLockdown;
local UnitAffectingCombat = UnitAffectingCombat;
local hooksecurefunc = hooksecurefunc;
local UIParent = UIParent;
local NUM_POSSESS_SLOTS = NUM_POSSESS_SLOTS or 10;

-- ============================================================================
-- MULTICAST MODULE FOR DRAGONUI
-- ============================================================================

-- Module state tracking
local MulticastModule = {
    initialized = false,
    applied = false,
    originalStates = {},       -- Store original states for restoration
    registeredEvents = {},     -- Track registered events
    hooks = {},                -- Track hooked functions
    stateDrivers = {},         -- Track state drivers
    frames = {}                -- Track created frames
}

-- ============================================================================
-- CONFIGURATION FUNCTIONS
-- ============================================================================

local function GetModuleConfig()
    return addon.db and addon.db.profile and addon.db.profile.modules and addon.db.profile.modules.multicast
end

local function IsModuleEnabled()
    local cfg = GetModuleConfig()
    return cfg and cfg.enabled
end

-- =============================================================================
-- OPTIMIZED TIMER HELPER (with timer pool for better memory management)
-- =============================================================================
local timerPool = {}
local function DelayedCall(delay, func)
    local timer = table.remove(timerPool) or CreateFrame("Frame")
    timer.elapsed = 0
    timer:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= delay then
            self:SetScript("OnUpdate", nil)
            table.insert(timerPool, self)     -- Recycle timer for reuse
            func()
        end
    end)
end

-- =============================================================================
-- CONFIG HELPER FUNCTIONS
-- =============================================================================
local function GetTotemConfig()
    if not (addon.db and addon.db.profile and addon.db.profile.additional and addon.db.profile.additional.totem) then
        return 0, 0
    end
    local totemConfig = addon.db.profile.additional.totem
    return totemConfig.x_position or 0, totemConfig.y_offset or 0
end

local function GetAdditionalConfig()
    return addon:GetConfigValue("additional") or {}
end

-- =============================================================================
-- ANCHOR FRAME: Handles positioning for both Totem and Possess bars
-- =============================================================================
local anchor = CreateFrame('Frame', 'DragonUI_MulticastAnchor', UIParent)
anchor:SetPoint('BOTTOM', UIParent, 'BOTTOM', 0, 52)
anchor:SetSize(37, 37)
-- CRÍTICO: Inicialmente oculto hasta que se active el módulo
anchor:Hide()

-- Track created frames
MulticastModule.frames.anchor = anchor

-- =============================================================================
-- SMART POSITIONING FUNCTION
-- =============================================================================
function anchor:update_position()
    if not IsModuleEnabled() then return end

    if InCombatLockdown() or UnitAffectingCombat('player') then return end

    local offsetX, offsetY = GetTotemConfig()
    self:ClearAllPoints()

    -- Check if pretty_actionbar addon is loaded for special positioning logic
    if IsAddOnLoaded('pretty_actionbar') and _G.pUiMainBar then
        local leftbar = MultiBarBottomLeft and MultiBarBottomLeft:IsShown()
        local rightbar = MultiBarBottomRight and MultiBarBottomRight:IsShown()

        -- Get additional config for pretty_actionbar compatibility
        local nobar = 52
        local leftbarOffset = 90
        local rightbarOffset = 40

        -- Read values from database if available
        if addon.db and addon.db.profile and addon.db.profile.additional then
            local additionalConfig = addon.db.profile.additional
            leftbarOffset = additionalConfig.leftbar_offset or 90
            rightbarOffset = additionalConfig.rightbar_offset or 40
        end

        local yPosition = nobar

        if leftbar and rightbar then
            yPosition = nobar + leftbarOffset
        elseif leftbar then
            yPosition = nobar + rightbarOffset
        elseif rightbar then
            yPosition = nobar + leftbarOffset
        end

        self:SetPoint('BOTTOM', UIParent, 'BOTTOM', offsetX, yPosition + offsetY)
    else
        -- Standard positioning logic
        local leftbar = MultiBarBottomLeft and MultiBarBottomLeft:IsShown()
        local rightbar = MultiBarBottomRight and MultiBarBottomRight:IsShown()
        local anchorFrame, anchorPoint, relativePoint, yOffset

        if leftbar or rightbar then
            if leftbar and rightbar then
                anchorFrame = MultiBarBottomRight
            elseif leftbar then
                anchorFrame = MultiBarBottomLeft
            else
                anchorFrame = MultiBarBottomRight
            end
            anchorPoint = 'TOP'
            relativePoint = 'BOTTOM'
            yOffset = 5 + offsetY
        else
            anchorFrame = addon.pUiMainBar or MainMenuBar
            anchorPoint = 'TOP'
            relativePoint = 'BOTTOM'
            yOffset = 5 + offsetY
        end

        self:SetPoint(relativePoint, anchorFrame, anchorPoint, offsetX, yOffset)
    end
end

-- =============================================================================
-- POSSESS BAR SETUP
-- =============================================================================
local possessbar = CreateFrame('Frame', 'DragonUI_PossessBar', UIParent, 'SecureHandlerStateTemplate')
possessbar:SetAllPoints(anchor)
-- CRÍTICO: Inicialmente oculto hasta que se active el módulo
possessbar:Hide()

-- Track created frames
MulticastModule.frames.possessbar = possessbar

-- NO MODIFICAR PossessBarFrame aquí - solo cuando el módulo esté habilitado

-- =============================================================================
-- POSSESS BUTTON POSITIONING FUNCTION
-- =============================================================================
local function PositionPossessButtons()
    if not IsModuleEnabled() then return end

    if InCombatLockdown() then return end

    -- Get config values safely
    local additionalConfig = GetAdditionalConfig()
    local btnsize = additionalConfig.size or 37
    local space = additionalConfig.spacing or 4

    for index = 1, NUM_POSSESS_SLOTS do
        local button = _G['PossessButton' .. index]
        if button then
            button:ClearAllPoints()
            button:SetParent(possessbar)
            button:SetSize(btnsize, btnsize)

            if index == 1 then
                button:SetPoint('BOTTOMLEFT', possessbar, 'BOTTOMLEFT', 0, 0)
            else
                local prevButton = _G['PossessButton' .. (index - 1)]
                if prevButton then
                    button:SetPoint('LEFT', prevButton, 'RIGHT', space, 0)
                end
            end

            -- CRÍTICO: NO mostrar botones de possess por defecto
            -- Solo se mostrarán cuando se entre en un vehículo
            button:Hide()
            possessbar:SetAttribute('addchild', button)
        end
    end

    -- Apply custom button template if available
    if addon.possessbuttons_template then
        addon.possessbuttons_template()
    end

    -- Set visibility driver for vehicle UI - pero solo si no hay totems de chamán
    -- Para chamanes, el possessbar debe mantenerse visible para mostrar totems
    local visibilityCondition
    if class == 'SHAMAN' and MultiCastActionBarFrame then
        -- Para chamanes: siempre visible (totems y possess)
        visibilityCondition = 'show'
    else
        -- Para otros: ocultar en vehículo, mostrar cuando no
        visibilityCondition = '[vehicleui][@vehicle,exists] hide; show'
    end

    RegisterStateDriver(possessbar, 'visibility', visibilityCondition)

    -- Track state driver for cleanup
    MulticastModule.stateDrivers.possessbar_visibility = { frame = possessbar, state = 'visibility', condition =
    visibilityCondition }
end

-- =============================================================================
-- SHAMAN MULTICAST (TOTEM) BAR SETUP
-- =============================================================================
-- CRÍTICO: No modificar nada aquí - todo se hace en ApplyMulticastSystem()
-- Esto evita que se rompan los frames de Blizzard cuando el módulo está deshabilitado

-- =============================================================================
-- HOOK ACTION BAR VISIBILITY CHANGES
-- =============================================================================
local function HookActionBarEvents()
    local bars = { MultiBarBottomLeft, MultiBarBottomRight }

    for _, bar in pairs(bars) do
        if bar then
            -- Safely hook without causing self-reference errors
            if not bar.__DragonUI_Hooked then
                bar:HookScript('OnShow', function()
                    DelayedCall(0.1, function() anchor:update_position() end)
                end)
                bar:HookScript('OnHide', function()
                    DelayedCall(0.1, function() anchor:update_position() end)
                end)
                bar.__DragonUI_Hooked = true
            end
        end
    end
end
-- =============================================================================
-- INITIALIZATION FUNCTION
-- =============================================================================
local function InitializeMulticast()
    if not IsModuleEnabled() then return end
    
    -- CRÍTICO: Verificar combate antes de mostrar frames
    if InCombatLockdown() then
        -- Defer until after combat
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            InitializeMulticast()
        end)
        return
    end
    
    -- Ensure anchor and possessbar are visible
    if anchor then
        anchor:Show()
    end
    if possessbar then
        possessbar:Show()
    end
    
    -- Position possess buttons
    PositionPossessButtons()
    
    -- Hook action bar events
    HookActionBarEvents()
    
    -- Update anchor position
    anchor:update_position()
end


-- ============================================================================
-- APPLY/RESTORE FUNCTIONS
-- ============================================================================
local function RestoreMulticastSystem()
    if not MulticastModule.applied then return end

    -- CRÍTICO: NO modificar frames protegidos en combate
    if InCombatLockdown() then
        -- Schedule for after combat
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            RestoreMulticastSystem()
        end)
        return
    end

    -- Unregister all state drivers
    for name, data in pairs(MulticastModule.stateDrivers) do
        if data.frame then
            UnregisterStateDriver(data.frame, data.state)
        end
    end
    MulticastModule.stateDrivers = {}

    -- Hide custom frames (SAFE - our own frames)
    if anchor then anchor:Hide() end
    if possessbar then possessbar:Hide() end

    -- Restore PossessBarFrame to original state
    if PossessBarFrame and MulticastModule.originalStates.possessBarFrame then
        local original = MulticastModule.originalStates.possessBarFrame
        PossessBarFrame:SetParent(original.parent or UIParent)
        PossessBarFrame:ClearAllPoints()

        -- Restore original anchor points
        for _, pointData in ipairs(original.points) do
            local point, relativeTo, relativePoint, x, y = unpack(pointData)
            if relativeTo then
                PossessBarFrame:SetPoint(point, relativeTo, relativePoint, x, y)
            else
                PossessBarFrame:SetPoint(point, relativePoint, x, y)
            end
        end
    end

    -- Restore MultiCastActionBarFrame to original state (Shaman only)
    if MultiCastActionBarFrame and class == 'SHAMAN' and MulticastModule.originalStates.multiCastActionBarFrame then
        local original = MulticastModule.originalStates.multiCastActionBarFrame

        -- Restaurar scripts originales
        if original.originalScripts then
            MultiCastActionBarFrame:SetScript('OnUpdate', original.originalScripts.OnUpdate)
            MultiCastActionBarFrame:SetScript('OnShow', original.originalScripts.OnShow)
            MultiCastActionBarFrame:SetScript('OnHide', original.originalScripts.OnHide)
        end

        -- Restaurar parent y posición
        MultiCastActionBarFrame:SetParent(original.parent or UIParent)
        MultiCastActionBarFrame:ClearAllPoints()

        -- Restore original anchor points
        if original.points and #original.points > 0 then
            for _, pointData in ipairs(original.points) do
                local point, relativeTo, relativePoint, x, y = unpack(pointData)
                if relativeTo then
                    MultiCastActionBarFrame:SetPoint(point, relativeTo, relativePoint, x, y)
                else
                    MultiCastActionBarFrame:SetPoint(point, relativePoint, x, y)
                end
            end
        else
            -- Fallback to default Blizzard positioning
            MultiCastActionBarFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 52)
        end

        -- Restore recall button if it was modified
        if MultiCastRecallSpellButton and MulticastModule.originalStates.multiCastRecallButton then
            local recallOriginal = MulticastModule.originalStates.multiCastRecallButton
            if recallOriginal.originalSetPoint then
                MultiCastRecallSpellButton.SetPoint = recallOriginal.originalSetPoint
            else
                MultiCastRecallSpellButton.SetPoint = nil
            end
        end
    end

    -- Reset possess button parents to default
    for index = 1, NUM_POSSESS_SLOTS do
        local button = _G['PossessButton' .. index]
        if button then
            button:SetParent(PossessBarFrame or UIParent)
            button:ClearAllPoints()
        end
    end

    MulticastModule.applied = false
end

local function ApplyMulticastSystem()
    if MulticastModule.applied or not IsModuleEnabled() then return end

    -- CRÍTICO: NO modificar frames protegidos en combate
    if InCombatLockdown() then
        -- Schedule for after combat
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            ApplyMulticastSystem()
        end)
        return
    end

    -- Store original states for restoration
    if PossessBarFrame then
        MulticastModule.originalStates.possessBarFrame = {
            parent = PossessBarFrame:GetParent(),
            points = {}
        }
        -- Store all anchor points
        for i = 1, PossessBarFrame:GetNumPoints() do
            local point, relativeTo, relativePoint, x, y = PossessBarFrame:GetPoint(i)
            table.insert(MulticastModule.originalStates.possessBarFrame.points, { point, relativeTo, relativePoint, x, y })
        end

        -- CONFIGURAR PossessBarFrame para DragonUI
        PossessBarFrame:SetParent(possessbar)
        PossessBarFrame:ClearAllPoints()
        if class == 'SHAMAN' then
            PossessBarFrame:SetPoint('BOTTOMRIGHT', possessbar, 'BOTTOMLEFT', -10, 0)
        else
            PossessBarFrame:SetPoint('BOTTOMLEFT', possessbar, 'BOTTOMLEFT', -68, 0)
        end
    end

    -- SHAMAN MULTICAST (TOTEM) BAR SETUP
    if MultiCastActionBarFrame and class == 'SHAMAN' then
        -- Store original state BEFORE modifying
        MulticastModule.originalStates.multiCastActionBarFrame = {
            parent = MultiCastActionBarFrame:GetParent(),
            points = {},
            originalSetParent = MultiCastActionBarFrame.SetParent,
            originalSetPoint = MultiCastActionBarFrame.SetPoint,
            originalScripts = {
                OnUpdate = MultiCastActionBarFrame:GetScript('OnUpdate'),
                OnShow = MultiCastActionBarFrame:GetScript('OnShow'),
                OnHide = MultiCastActionBarFrame:GetScript('OnHide')
            }
        }

        -- Store all anchor points
        for i = 1, MultiCastActionBarFrame:GetNumPoints() do
            local point, relativeTo, relativePoint, x, y = MultiCastActionBarFrame:GetPoint(i)
            table.insert(MulticastModule.originalStates.multiCastActionBarFrame.points,
                { point, relativeTo, relativePoint, x, y })
        end

        -- Track MultiCastActionBarFrame
        MulticastModule.frames.multiCastActionBarFrame = MultiCastActionBarFrame

        -- Remove default scripts that might interfere
        MultiCastActionBarFrame:SetScript('OnUpdate', nil)
        MultiCastActionBarFrame:SetScript('OnShow', nil)
        MultiCastActionBarFrame:SetScript('OnHide', nil)

        -- Parent and position the MultiCastActionBarFrame
        MultiCastActionBarFrame:SetParent(possessbar)
        MultiCastActionBarFrame:ClearAllPoints()
        MultiCastActionBarFrame:SetPoint('BOTTOM', possessbar, 'BOTTOM', 0, 0)

        possessbar:Show()
        anchor:Show()

        -- SAFE: Use hooks instead of function replacement to avoid taint
        if not MulticastModule.hooks.multiCastSetParent then
            MulticastModule.hooks.multiCastSetParent = true
            hooksecurefunc(MultiCastActionBarFrame, "SetParent", function(self, newParent)
                if MulticastModule.applied and newParent ~= possessbar and newParent ~= UIParent then
                    DelayedCall(0.01, function()
                        if not InCombatLockdown() and MulticastModule.applied and MultiCastActionBarFrame:GetParent() ~= possessbar then
                            MultiCastActionBarFrame:SetParent(possessbar)
                        end
                    end)
                end
            end)
        end

        if not MulticastModule.hooks.multiCastSetPoint then
            MulticastModule.hooks.multiCastSetPoint = true
            hooksecurefunc(MultiCastActionBarFrame, "SetPoint", function(self, ...)
                if MulticastModule.applied then
                    DelayedCall(0.01, function()
                        if not InCombatLockdown() and MulticastModule.applied then
                            local point, relativeTo, relativePoint = MultiCastActionBarFrame:GetPoint(1)
                            if relativeTo ~= possessbar or relativePoint ~= 'BOTTOM' then
                                MultiCastActionBarFrame:ClearAllPoints()
                                MultiCastActionBarFrame:SetPoint('BOTTOM', possessbar, 'BOTTOM', 0, 0)
                            end
                        end
                    end)
                end
            end)
        end
    end

    -- Hook action bar events for dynamic positioning
    HookActionBarEvents()

    -- Initialize the system
    InitializeMulticast()

    MulticastModule.applied = true
end
-- =============================================================================
-- UNIFIED REFRESH FUNCTION
-- =============================================================================

-- Enhanced refresh function with module control
function addon.RefreshMulticastSystem()
    if IsModuleEnabled() then
        ApplyMulticastSystem()
        -- Call original refresh for settings
        if addon.RefreshMulticast then
            addon.RefreshMulticast()
        end
    else
        RestoreMulticastSystem()
    end
end

-- Fast refresh: Only updates size and spacing WITHOUT repositioning
function addon.RefreshMulticast(fullRefresh)
    if not IsModuleEnabled() then return end

    if InCombatLockdown() or UnitAffectingCombat("player") then
        -- Schedule refresh after combat
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            addon.RefreshMulticast(fullRefresh)
        end)
        return
    end

    -- Only update anchor position if NOT a full refresh (X/Y changes)
    if not fullRefresh then
        if anchor and anchor.update_position then
            anchor:update_position()
        end
        return     -- Exit here for X/Y changes
    end

    -- Get config values once (cached for performance)
    local additionalConfig = GetAdditionalConfig()
    local btnsize = additionalConfig.size or 37
    local space = additionalConfig.spacing or 4

    --  UPDATE POSSESS BUTTONS - ONLY SIZE, NO REPOSITIONING
    for index = 1, NUM_POSSESS_SLOTS do
        local button = _G["PossessButton" .. index]
        if button then
            button:SetSize(btnsize, btnsize)
            -- DO NOT reposition - keep existing positions
        end
    end

    --  UPDATE TOTEM BUTTONS - ONLY SIZE, NO REPOSITIONING
    if MultiCastActionBarFrame and class == 'SHAMAN' then
        -- Update totem slot buttons
        for i = 1, 4 do
            local button = _G["MultiCastSlotButton" .. i]
            if button then
                button:SetSize(btnsize, btnsize)
                -- DO NOT reposition - keep existing positions
            end
        end

        -- Update summon button if it exists
        if MultiCastSummonSpellButton then
            MultiCastSummonSpellButton:SetSize(btnsize, btnsize)
        end

        -- Update recall button if it exists
        if MultiCastRecallSpellButton then
            MultiCastRecallSpellButton:SetSize(btnsize, btnsize)
        end
    end
end

-- Full rebuild: Only for major changes (profile changes, etc.)
function addon.RefreshMulticastFull()
    if not IsModuleEnabled() then return end

    if InCombatLockdown() or UnitAffectingCombat("player") then return end

    -- Reinitialize everything from scratch
    InitializeMulticast()
end

-- =============================================================================
-- PROFILE CHANGE HANDLER
-- =============================================================================
local function OnProfileChanged()
    -- Delay to ensure profile data is fully loaded
    DelayedCall(0.2, function()
        if InCombatLockdown() or UnitAffectingCombat("player") then
            -- Schedule for after combat if in combat
            local frame = CreateFrame("Frame")
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
            frame:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                OnProfileChanged()
            end)
            return
        end

        -- Use the same refresh that works for X/Y sliders (prevents ghost elements)
        addon.RefreshMulticast()
    end)
end

-- =============================================================================
-- CENTRALIZED EVENT HANDLER (optimized event management)
-- =============================================================================
local eventFrame = CreateFrame("Frame")
local function RegisterEvents()
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    
    eventFrame:SetScript("OnEvent", function(self, event, addonName)
        if event == "ADDON_LOADED" and addonName == "DragonUI" then
            DelayedCall(0.5, function()
                if IsModuleEnabled() then
                    eventFrame:RegisterEvent("PLAYER_LOGOUT")
                    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                end
            end)
            
        elseif event == "PLAYER_LOGIN" then
            DelayedCall(0.3, function()
                if IsModuleEnabled() then
                    -- CRÍTICO: Solo aplicar si NO estamos en combate
                    if not InCombatLockdown() then
                        ApplyMulticastSystem()
                    else
                        -- Defer until after combat
                        local frame = CreateFrame("Frame")
                        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
                        frame:SetScript("OnEvent", function(self)
                            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                            ApplyMulticastSystem()
                        end)
                    end
                    
                    -- Register profile callbacks
                    if addon.db and addon.db.RegisterCallback then
                        addon.db.RegisterCallback(addon, "OnProfileChanged", OnProfileChanged)
                        addon.db.RegisterCallback(addon, "OnProfileCopied", OnProfileChanged)
                        addon.db.RegisterCallback(addon, "OnProfileReset", OnProfileChanged)
                    end
                    
                    -- Also register with addon core if available
                    if addon.core and addon.core.RegisterMessage then
                        addon.core.RegisterMessage(addon, "DRAGONUI_PROFILE_CHANGED", OnProfileChanged)
                        addon.core.RegisterMessage(addon, "DRAGONUI_READY", function()
                            if not InCombatLockdown() then
                                ApplyMulticastSystem()
                            end
                        end)
                    end
                end
            end)
            
        elseif event == "PLAYER_LOGOUT" then
            if addon.db and addon.db.UnregisterCallback then
                addon.db.UnregisterCallback(addon, "OnProfileChanged")
                addon.db.UnregisterCallback(addon, "OnProfileCopied") 
                addon.db.UnregisterCallback(addon, "OnProfileReset")
            end
            
        elseif event == "PLAYER_REGEN_ENABLED" then
            DelayedCall(0.5, function()
                if IsModuleEnabled() and anchor and anchor.update_position then
                    anchor:update_position()
                end
            end)
        end
    end)
end

-- Initialize event system
RegisterEvents()