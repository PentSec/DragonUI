local addon = select(2,...);
local config = addon.config;
local event = addon.package;
local class = addon._class;
local pUiMainBar = addon.pUiMainBar;
local unpack = unpack;
local select = select;
local pairs = pairs;
local _G = getfenv(0);

-- ============================================================================
-- STANCE MODULE FOR DRAGONUI
-- ============================================================================

-- Module state tracking
local StanceModule = {
    initialized = false,
    applied = false,
    originalStates = {},     -- Store original states for restoration
    registeredEvents = {},   -- Track registered events
    hooks = {},             -- Track hooked functions
    stateDrivers = {},      -- Track state drivers
    frames = {}             -- Track created frames
}

-- ============================================================================
-- CONFIGURATION FUNCTIONS
-- ============================================================================

local function GetModuleConfig()
    return addon.db and addon.db.profile and addon.db.profile.modules and addon.db.profile.modules.stance
end

local function IsModuleEnabled()
    local cfg = GetModuleConfig()
    return cfg and cfg.enabled
end

-- ============================================================================
-- CONSTANTS AND VARIABLES
-- ============================================================================

-- const
local InCombatLockdown = InCombatLockdown;
local GetNumShapeshiftForms = GetNumShapeshiftForms;
local GetShapeshiftFormInfo = GetShapeshiftFormInfo;
local GetShapeshiftFormCooldown = GetShapeshiftFormCooldown;
local CreateFrame = CreateFrame;
local UIParent = UIParent;
local hooksecurefunc = hooksecurefunc;
local UnitAffectingCombat = UnitAffectingCombat;

-- WOTLK 3.3.5a Constants
local NUM_SHAPESHIFT_SLOTS = 10; -- Fixed value for 3.3.5a compatibility

local stance = {
	['DEATHKNIGHT'] = 'show',
	['DRUID'] = 'show',
	['PALADIN'] = 'show',
	['PRIEST'] = 'show',
	['ROGUE'] = 'show',
	['WARLOCK'] = 'show',
	['WARRIOR'] = 'show'
};

-- Module frames (created only when enabled)
local anchor, stancebar

-- Initialize MultiBar references
local MultiBarBottomLeft = _G["MultiBarBottomLeft"]
local MultiBarBottomRight = _G["MultiBarBottomRight"]

-- Simple initialization tracking
local stanceBarInitialized = false;

-- SIMPLE STATIC POSITIONING - NO DYNAMIC LOGIC
local function stancebar_update()
    if not IsModuleEnabled() or not anchor then return end
    
    -- READ VALUES FROM DATABASE
    local stanceConfig = addon.db.profile.additional.stance
    local x_position = stanceConfig.x_position or -230  -- X position from center
    local y_offset = stanceConfig.y_offset or 0         -- Additional Y offset
    local base_y = 200                                  -- Base Y position from bottom
    local final_y = base_y + y_offset                   -- Final Y position
    
    -- Simple static positioning - no dependencies, no complexity
    anchor:ClearAllPoints()
    anchor:SetPoint('BOTTOM', UIParent, 'BOTTOM', x_position, final_y)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Simple update function - no queues needed
local function UpdateStanceBar()
    if not IsModuleEnabled() then return end
    stancebar_update()
end

-- ============================================================================
-- POSITIONING FUNCTIONS
-- ============================================================================


-- ============================================================================
-- FRAME CREATION FUNCTIONS
-- ============================================================================

local function CreateStanceFrames()
    if StanceModule.frames.anchor or not IsModuleEnabled() then return end
    
    -- Create simple anchor frame
    anchor = CreateFrame('Frame', 'pUiStanceHolder', UIParent)
    anchor:SetSize(37, 37)  -- Visual style matching reference
    StanceModule.frames.anchor = anchor
    
    -- Create stance bar frame
    stancebar = CreateFrame('Frame', 'pUiStanceBar', anchor, 'SecureHandlerStateTemplate')
    stancebar:SetAllPoints(anchor)
    StanceModule.frames.stancebar = stancebar
    
    -- Expose globally for compatibility
    _G.pUiStanceBar = stancebar
    
    -- Apply static positioning immediately
    stancebar_update()
    
    
end

-- ============================================================================
-- POSITIONING FUNCTIONS
-- ============================================================================

--



-- ============================================================================
-- STANCE BUTTON FUNCTIONS
-- ============================================================================

local function stancebutton_update()
    if not IsModuleEnabled() or not anchor then return end
    
	if not InCombatLockdown() then
		_G.ShapeshiftButton1:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 0, 0)
	end
end

local function stancebutton_position()
    if not IsModuleEnabled() or not stancebar or not anchor then return end
    
    -- READ VALUES FROM DATABASE - Scale approach
    local stanceConfig = addon.db.profile.additional.stance
    local additionalConfig = addon.db.profile.additional
    local btnsize = stanceConfig.button_size or additionalConfig.size or 29  -- Base size 29
    local space = stanceConfig.button_spacing or additionalConfig.spacing or 3
    local scale = btnsize / 29  -- Calculate scale factor from base size 29
    
    -- CLEAN SETUP - Avoid duplications
	for index=1, NUM_SHAPESHIFT_SLOTS do
		local button = _G['ShapeshiftButton'..index]
		if button then
		    -- Only modify parent if not already configured
		    if button:GetParent() ~= stancebar then
			    button:ClearAllPoints()
			    button:SetParent(stancebar)
		    end
		    -- Use scale instead of SetSize for better border scaling
		    button:SetSize(29, 29)  -- Keep base size
		    button:SetScale(scale)  -- Apply scale factor
		    
		    -- Always update positioning
		    if index == 1 then
			    button:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 0, 0)
		    else
			    local previous = _G['ShapeshiftButton'..index-1]
			    button:SetPoint('LEFT', previous, 'RIGHT', space, 0)
		    end
		    
		    -- Show/hide based on forms
		    local _,name = GetShapeshiftFormInfo(index)
		    if name then
			    button:Show()
		    else
			    button:Hide()
		    end
		end
	end
	
	-- Register state driver only once
	if not StanceModule.stateDrivers.visibility then
	    StanceModule.stateDrivers.visibility = {frame = stancebar, state = 'visibility', condition = stance[class] or 'hide'}
	    RegisterStateDriver(stancebar, 'visibility', stance[class] or 'hide')
	end
end

local function stancebutton_updatestate()
    if not IsModuleEnabled() then return end
    
	local numForms = GetNumShapeshiftForms()
	local texture, name, isActive, isCastable;
	local button, icon, cooldown;
	local start, duration, enable;
	for index=1, NUM_SHAPESHIFT_SLOTS do
		button = _G['ShapeshiftButton'..index]
		icon = _G['ShapeshiftButton'..index..'Icon']
		if index <= numForms then
			texture, name, isActive, isCastable = GetShapeshiftFormInfo(index)
			icon:SetTexture(texture)
			cooldown = _G['ShapeshiftButton'..index..'Cooldown']
			if texture then
				cooldown:SetAlpha(1)
			else
				cooldown:SetAlpha(0)
			end
			start, duration, enable = GetShapeshiftFormCooldown(index)
			CooldownFrame_SetTimer(cooldown, start, duration, enable)
			if isActive then
				ShapeshiftBarFrame.lastSelected = button:GetID()
				button:SetChecked(1)
			else
				button:SetChecked(0)
			end
			if isCastable then
				icon:SetVertexColor(255/255, 255/255, 255/255)
			else
				icon:SetVertexColor(102/255, 102/255, 102/255)
			end
		end
	end
end

local function stancebutton_setup()
    if not IsModuleEnabled() then return end
    
	if InCombatLockdown() then return end
	for index=1, NUM_SHAPESHIFT_SLOTS do
		local button = _G['ShapeshiftButton'..index]
		local _, name = GetShapeshiftFormInfo(index)
		if name then
			button:Show()
		else
			button:Hide()
		end
	end
	stancebutton_updatestate();
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

local function OnEvent(self,event,...)
    if not IsModuleEnabled() then return end
    
	if GetNumShapeshiftForms() < 1 then return; end
	if event == 'PLAYER_LOGIN' then
		stancebutton_position();
	elseif event == 'UPDATE_SHAPESHIFT_FORMS' then
		stancebutton_setup();
	elseif event == 'PLAYER_ENTERING_WORLD' then
		self:UnregisterEvent('PLAYER_ENTERING_WORLD');
		if addon.stancebuttons_template then
		    addon.stancebuttons_template();
		end
	else
		stancebutton_updatestate();
	end
end

-- ============================================================================
-- INITIALIZATION FUNCTIONS
-- ============================================================================

-- Simple initialization function
local function InitializeStanceBar()
    if not IsModuleEnabled() then return end
    
    -- Simple setup - no complex checks
    stancebutton_position()
    stancebar_update()
    
    if stancebar then
        stancebar:Show()
    end
    
    stanceBarInitialized = true
end

-- ============================================================================
-- APPLY/RESTORE FUNCTIONS
-- ============================================================================

local function ApplyStanceSystem()
    if StanceModule.applied or not IsModuleEnabled() then return end
    
    -- Create frames
    CreateStanceFrames()
    
    if not anchor or not stancebar then return end
    
    -- Register only essential events
    local events = {
        'PLAYER_LOGIN',
        'UPDATE_SHAPESHIFT_FORMS',
        'UPDATE_SHAPESHIFT_FORM'
    }
    
    for _, eventName in ipairs(events) do
        stancebar:RegisterEvent(eventName)
        StanceModule.registeredEvents[eventName] = stancebar
    end
    stancebar:SetScript('OnEvent', OnEvent)
    
    -- Simple hook for Blizzard updates - REGISTER ONLY ONCE
    if not StanceModule.hooks.ShapeshiftBar_Update then
        StanceModule.hooks.ShapeshiftBar_Update = true
        hooksecurefunc('ShapeshiftBar_Update', function()
            if IsModuleEnabled() then
                stancebutton_update()
            end
        end)
    end
    
    -- Initial setup
    InitializeStanceBar()
    
    StanceModule.applied = true
    
end

local function RestoreStanceSystem()
    if not StanceModule.applied then return end
    
    -- Unregister all events
    for eventName, frame in pairs(StanceModule.registeredEvents) do
        if frame and frame.UnregisterEvent then
            frame:UnregisterEvent(eventName)
        end
    end
    StanceModule.registeredEvents = {}
    
    -- Unregister all state drivers
    for name, data in pairs(StanceModule.stateDrivers) do
        if data.frame then
            UnregisterStateDriver(data.frame, data.state)
        end
    end
    StanceModule.stateDrivers = {}
    
    -- Hide custom frames
    if anchor then anchor:Hide() end
    if stancebar then stancebar:Hide() end
    
    -- Reset stance button parents to default
    for index=1, NUM_SHAPESHIFT_SLOTS do
        local button = _G['ShapeshiftButton'..index]
        if button then
            button:SetParent(ShapeshiftBarFrame or UIParent)
            button:ClearAllPoints()
            -- Don't reset positions here - let Blizzard handle it
        end
    end
    
    -- Clear global reference
    _G.pUiStanceBar = nil
    
    -- Reset variables
    stanceBarInitialized = false
    
    StanceModule.applied = false
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Enhanced refresh function with module control
function addon.RefreshStanceSystem()
    if IsModuleEnabled() then
        ApplyStanceSystem()
        -- Call original refresh for settings
        if addon.RefreshStance then
            addon.RefreshStance()
        end
    else
        RestoreStanceSystem()
    end
end

-- Original refresh function for configuration changes
function addon.RefreshStance()
    if not IsModuleEnabled() then return end
    
	if InCombatLockdown() or UnitAffectingCombat('player') then 
		return 
	end
	
	-- Ensure frames exist
	if not anchor or not stancebar then
	    return
	end
	
	-- Update button scale and spacing with visual style
	local stanceConfig = addon.db.profile.additional.stance
	local additionalConfig = addon.db.profile.additional
	local btnsize = stanceConfig.button_size or additionalConfig.size or 29  -- Base size 29
	local space = stanceConfig.button_spacing or additionalConfig.spacing or 3
	local scale = btnsize / 29  -- Calculate scale factor
	
	-- Reposition stance buttons with scale refresh
	for i = 1, NUM_SHAPESHIFT_SLOTS do
		local button = _G["ShapeshiftButton"..i]
		if button then
			button:SetSize(29, 29)  -- Keep base size
			button:SetScale(scale)  -- Apply scale
			if i == 1 then
				button:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 0, 0)
			else
				local prevButton = _G["ShapeshiftButton"..(i-1)]
				if prevButton then
					button:SetPoint('LEFT', prevButton, 'RIGHT', space, 0)
				end
			end
		end
	end
	
	-- Update position
	stancebar_update()
end

-- Debug function for troubleshooting stance bar issues
function addon.DebugStanceBar()
    if not IsModuleEnabled() then
        
        return {enabled = false}
    end
    
	local info = {
		stanceBarInitialized = stanceBarInitialized,
		moduleEnabled = IsModuleEnabled(),
		inCombat = InCombatLockdown(),
		unitInCombat = UnitAffectingCombat('player'),
		anchorExists = anchor and true or false,
		stanceBarExists = _G.pUiStanceBar and true or false,
		numShapeshiftForms = GetNumShapeshiftForms(),
		stanceConfig = addon.db.profile.additional.stance
	};
	
	
	for k, v in pairs(info) do
	
	end
	
	if anchor then
		local point, relativeTo, relativePoint, x, y = anchor:GetPoint();
	
	end
	
	return info;
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local function Initialize()
    if StanceModule.initialized then return end
    
    -- Only apply if module is enabled
    if IsModuleEnabled() then
        ApplyStanceSystem()
    end
    
    StanceModule.initialized = true
end

-- Auto-initialize when addon loads
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "DragonUI" then
        -- Just mark as loaded, don't initialize yet
        self.addonLoaded = true
    elseif event == "PLAYER_LOGIN" and self.addonLoaded then
        -- Initialize after both addon is loaded and player is logged in
        Initialize()
        self:UnregisterAllEvents()
    end
end)
-- End of stance module