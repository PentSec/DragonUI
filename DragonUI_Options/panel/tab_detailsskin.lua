--[[
===============================================================================
DragonUI Options Panel - Details Skin Tab
===============================================================================
Theme for the Details! Damage Meter: registers the "DragonUI" skin with
Details! and re-asserts the player's choice after reloads. Applying it stays
an explicit action (button or /duidetails) — registering alone only lists the
skin in Details!' own picker.
===============================================================================
]]

local addon = DragonUI
if not addon then return end

local LO = addon.LO
local C = addon.PanelControls
local Panel = addon.OptionsPanel

-- ============================================================================
-- HELPERS
-- ============================================================================

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

local function ReportApply(ok)
    if not addon.Print then return end
    if ok then
        addon:Print("|cff1784d1DragonUI|r: " .. addon.L["Details! skin applied."])
    else
        addon:Print("|cff1784d1DragonUI|r: " .. addon.L["Could not apply the skin - Details! is not ready yet."])
    end
end

-- ============================================================================
-- TAB BUILDER
-- ============================================================================

local function BuildDetailsskinTab(scroll)
    C:AddLabel(scroll, "|cffFFD700" .. (LO["Damage Meter Skin"] or "Damage Meter Skin") .. "|r",
        { color = C.Theme.textGold })

    local DS = addon.DetailsSkin
    if not (DS and DS.IsDetailsLoaded()) then
        C:AddDescription(scroll, LO["|cffff5555Details! is not installed.|r This module skins the Details! Damage Meter, it is not a meter of its own - with Details! absent there is nothing to skin."])
        return
    end

    C:AddDescription(scroll, LO["A retail-styled theme for |cffffcc55Details!|r, drawn with art from retail's own damage meter: a gold-titled header bar, class-coloured bars on a near-invisible panel, and abbreviated numbers. It is registered with Details! at login, so it also appears in Details!' own skin list under |cffffcc55DragonUI|r."])
    C:AddSpacer(scroll)

    -- ====================================================================
    -- INTEGRATION TOGGLE
    -- ====================================================================
    local mainSection = C:AddSection(scroll, LO["Damage Meter Skin"])

    C:AddToggle(mainSection, {
        label = LO["Enable Damage Meter Skin"] or "Enable Damage Meter Skin",
        desc = LO["Registers the DragonUI theme with Details! and puts your chosen skin back after a reload. Turning it off hands every window back to Details!' own chrome."],
        getFunc = function() return IsEnabled("detailsskin") end,
        setFunc = function(val)
            EnsureModuleTable("detailsskin").enabled = val
            if val then
                if addon.ApplyDetailsSkinSystem then addon.ApplyDetailsSkinSystem() end
            else
                if addon.RestoreDetailsSkinSystem then addon.RestoreDetailsSkinSystem() end
            end
            Panel:SelectTab("detailsskin")
        end,
        requiresReload = false,
    })

    -- ====================================================================
    -- APPLY ACTION
    -- ====================================================================
    C:AddSpacer(scroll)

    C:AddButton(mainSection, {
        label = LO["Apply the DragonUI Skin"],
        desc = LO["Switches every Details! window to the skin and sets K/M number abbreviation. Window size and position stay yours - use Details!' own scale slider for those. Your choice is remembered and put back after a reload; picking another skin in Details! ends that. Run this again after you customise something in Details! and want the theme back."],
        disabled = function() return not IsEnabled("detailsskin") end,
        callback = function()
            ReportApply(DS.Apply())
        end,
    })

    C:AddDescription(scroll, LO["Run |cffffcc55/duidetails|r to apply it from chat."])
end

-- Register the tab (order 15 = after Bags/BNet Toast, before Profiles)
Panel:RegisterTab("detailsskin", LO["Damage Meter Skin"], BuildDetailsskinTab, 15)
