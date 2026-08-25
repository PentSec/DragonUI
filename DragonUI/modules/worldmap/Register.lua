-- DragonUI/modules/worldmap/Register.lua — boot wiring for the world map.
--
-- Adapted from _ref-/DragonUI_NewEra-main/modules/worldmap/Register.lua for DragonUI's
-- ModuleRegistry (lifecyclePrefix "WorldMap"). The module has no enable toggle in DragonUI's
-- modules.xml — it is registered here directly. Turning it off writes the flag and the next
-- /reload never boots it.
--
-- THE RIVAL CHECK: Mapster clears UIPanelWindows["WorldMapFrame"] and takes over the frame
-- outright. Two addons cannot own it. conflictsWith makes ours stand down.

local addon = select(2, ...)
local L = addon.L
local NE = _G.DragonUIWorldMapHost
if not NE or NE.disabled then return end

local WM = NE.worldmap
if not WM then return end

-- ============================================================================
-- MODULE REGISTRATION
-- ============================================================================

local WMModule = {
	initialized = false,
	applied = false,
}

if addon.RegisterModule then
	addon:RegisterModule("worldmap", WMModule,
		L["World Map"],
		L["Modern frame, portrait and breadcrumb navigation on the world map, with the quest log as a side panel."],
		{ lifecyclePrefix = "WorldMap" })
end

-- ============================================================================
-- BOOT — one PLAYER_LOGIN builds the whole thing.
--
-- Reload-gated: turning the module off writes the flag and the next /reload never
-- boots it, leaving the client's own map untouched.
-- ============================================================================

local function boot()
	if not addon:IsModuleEnabled("worldmap") then return end
	NE.disabled = false

	-- Order matters: chrome builds the window and spacer that everything else
	-- anchors to, then breadcrumb, then pins, then side panel, then fog, zoom, filter.
	WM.Arm()
	if WM.BuildNavBar then WM.BuildNavBar() end
	if WM.ArmPins then WM.ArmPins() end
	if WM.dungeon and WM.dungeon.Arm then WM.dungeon.Arm() end
	if NE.questlogpanel and NE.questlogpanel.Arm then NE.questlogpanel.Arm() end
	if WM.fog and WM.fog.Arm then WM.fog.Arm() end
	if WM.canvaszoom and WM.canvaszoom.Arm then WM.canvaszoom.Arm() end
	if WM.wheel and WM.wheel.Arm then WM.wheel.Arm() end
	if WM.filter and WM.filter.Arm then WM.filter.Arm() end

	WMModule.initialized = true
	WMModule.applied = true
end

local function ApplyWorldMap()
	if not addon:IsModuleEnabled("worldmap") then return end
	if WMModule.applied then return end
	boot()
end

local function RestoreWorldMap()
	WMModule.applied = false
	-- No in-session teardown: the module is reload-gated.
end

addon.ApplyWorldMapSystem = ApplyWorldMap
addon.RestoreWorldMapSystem = RestoreWorldMap

-- ============================================================================
-- INIT — boot on PLAYER_LOGIN. This client's WorldMapFrame lives in FrameXML
-- (not LoadOnDemand), so everything is ready at that point.
-- ============================================================================

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:RegisterEvent("ADDON_LOADED")
init:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		-- Early install: ensure NE.worldmap exists before first PLAYER_LOGIN
		-- (some files do NE.worldmap = {} at file load; fine.)
		return
	end
	if not addon:IsModuleEnabled("worldmap") then return end
	boot()
end)
