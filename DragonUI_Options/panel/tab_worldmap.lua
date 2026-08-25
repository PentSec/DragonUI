--[[
===============================================================================
DragonUI Options Panel - World Map Tab
===============================================================================
Retail-styled world map with breadcrumb navigation, drag-to-resize,
fog-of-war reveal, and quest log side panel.
===============================================================================
]]

local addon = DragonUI
if not addon then return end

local LO = addon.LO
local C = addon.PanelControls
local Panel = addon.OptionsPanel

local function EnsureModuleTable(moduleName)
    return C:EnsureModuleTable(moduleName)
end

local function GetModuleField(moduleName, field)
    local m = addon.db.profile.modules
    return m and m[moduleName] and m[moduleName][field]
end

local function IsEnabled(moduleName)
    return GetModuleField(moduleName, "enabled") == true
end

local function BuildWorldmapTab(scroll)
    C:AddLabel(scroll, "|cffFFD700" .. (LO["World Map"] or "World Map") .. "|r",
        { color = C.Theme.textGold })

    C:AddDescription(scroll, LO["Retail-styled world map with breadcrumb navigation, drag-to-resize and quest log side panel. Requires a full /reload after toggling."])
    C:AddSpacer(scroll)

    local mainSection = C:AddSection(scroll, LO["World Map"])

    C:AddToggle(mainSection, {
        label = LO["Enable World Map"],
        desc = LO["Activates the modern world map frame. Requires /reload to take effect."],
        getFunc = function() return IsEnabled("worldmap") end,
        setFunc = function(val)
            EnsureModuleTable("worldmap").enabled = val
            Panel:SelectTab("worldmap")
        end,
        requiresReload = true,
    })

    C:AddToggle(mainSection, {
        label = LO["Enable Fog Reveal"],
        desc = LO["Draw grey tint over undiscovered zones using account-wide exploration data. Each alt sees your main's exploration immediately."],
        getFunc = function() return GetModuleField("worldmap", "fog") end,
        setFunc = function(val)
            EnsureModuleTable("worldmap").fog = val
        end,
        disabled = function() return not IsEnabled("worldmap") end,
        requiresReload = false,
    })

    C:AddToggle(mainSection, {
        label = LO["Enable Wheel Zoom"],
        desc = LO["Mouse wheel zooms and pans the map canvas."],
        getFunc = function() return GetModuleField("worldmap", "wheelZoom") end,
        setFunc = function(val)
            EnsureModuleTable("worldmap").wheelZoom = val
        end,
        disabled = function() return not IsEnabled("worldmap") end,
        requiresReload = false,
    })
end

Panel:RegisterTab("worldmap", LO["World Map"], BuildWorldmapTab, 16)
