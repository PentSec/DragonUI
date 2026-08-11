--[[
===============================================================================
DragonUI Options Panel - BNet Toast Tab
===============================================================================
Friend online/offline notification settings: toast popup, chat messages,
position and scale.
===============================================================================
]]

local addon = DragonUI
if not addon then return end

local L = addon.L
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

-- ============================================================================
-- TAB BUILDER
-- ============================================================================

local function BuildBNetToastTab(scroll)
    C:AddLabel(scroll, "|cffFFD700" .. LO["BNet Toast"] .. "|r", { color = C.Theme.textGold })
    C:AddDescription(scroll, LO["Configure how DragonUI notifies you when friends come online or go offline."])
    C:AddSpacer(scroll)

    -- ====================================================================
    -- MAIN TOGGLE
    -- ====================================================================
    local mainSection = C:AddSection(scroll, LO["BNet Toast"])

    C:AddToggle(mainSection, {
        label = LO["Enable BNet Toast"] or "Enable BNet Toast",
        desc = LO["Display Battle.net friend online/offline notifications via toast popup and/or chat messages."] or "Display Battle.net friend online/offline notifications via toast popup and/or chat messages.",
        getFunc = function() return IsEnabled("bnettoast") end,
        setFunc = function(val)
            EnsureModuleTable("bnettoast").enabled = val
            if val then
                if addon.ApplyBNetToast then addon.ApplyBNetToast() end
            else
                if addon.RestoreBNetToast then addon.RestoreBNetToast() end
            end
            -- Rebuild tab so sub-toggles update their disabled state
            Panel:SelectTab("bnettoast")
        end,
        requiresReload = true,
    })

    -- ====================================================================
    -- NOTIFICATION TYPE
    -- ====================================================================
    C:AddSpacer(scroll)
    local typeSection = C:AddSection(scroll, (LO["Notification Type"] or "Notification Type"))

    C:AddToggle(typeSection, {
        label = LO["Guild Notifications"] or "Guild Notifications",
        desc = LO["Show notifications for guild members coming online or going offline. Turn off to only receive friend notifications."] or "Show notifications for guild members coming online or going offline. Turn off to only receive friend notifications.",
        getFunc = function() return GetModuleField("bnettoast", "guild_notify") ~= false end,
        setFunc = function(val)
            EnsureModuleTable("bnettoast").guild_notify = val
        end,
        disabled = function() return not IsEnabled("bnettoast") end,
        requiresReload = false,
    })

    C:AddToggle(typeSection, {
        label = LO["Show Toast Popup"],
        desc = LO["Display the Battle.net toast frame when a friend comes online or goes offline."],
        getFunc = function() return GetModuleField("bnettoast", "show_toast") ~= false end,
        setFunc = function(val)
            EnsureModuleTable("bnettoast").show_toast = val
        end,
        disabled = function() return not IsEnabled("bnettoast") end,
        requiresReload = false,
    })

    C:AddToggle(typeSection, {
        label = LO["Show Chat Notification"],
        desc = LO["Display a chat message when a friend comes online or goes offline."],
        getFunc = function() return GetModuleField("bnettoast", "show_chat") ~= false end,
        setFunc = function(val)
            EnsureModuleTable("bnettoast").show_chat = val
        end,
        disabled = function() return not IsEnabled("bnettoast") end,
        requiresReload = false,
    })

    -- ====================================================================
    -- POSITION & SCALE
    -- ====================================================================
    C:AddSpacer(scroll)
    local posSection = C:AddSection(scroll, (LO["Position & Scale"] or "Position & Scale"))

    C:AddSlider(posSection, {
        label = LO["Scale"],
        desc = LO["Scale of the BNet toast frame."] or "Scale of the BNet toast frame.",
        getFunc = function() return GetModuleField("bnettoast", "scale") or 1.0 end,
        setFunc = function(val)
            EnsureModuleTable("bnettoast").scale = val
            if addon.UpdateBNetToastScale then addon.UpdateBNetToastScale() end
        end,
        min = 0.5, max = 2.0, step = 0.05,
        width = 200,
        disabled = function() return not IsEnabled("bnettoast") end,
    })

    C:AddSlider(posSection, {
        label = LO["X Position"],
        desc = LO["Horizontal position of the BNet toast from the screen center. Negative values move left, positive values move right."] or "Horizontal position of the BNet toast from the screen center. Negative values move left, positive values move right.",
        getFunc = function() return GetModuleField("bnettoast", "x_position") or 0 end,
        setFunc = function(val)
            EnsureModuleTable("bnettoast").x_position = val
            if addon.UpdateBNetToastPosition then addon.UpdateBNetToastPosition() end
        end,
        min = -600, max = 600, step = 1,
        width = 200,
        disabled = function() return not IsEnabled("bnettoast") end,
    })

    C:AddSlider(posSection, {
        label = LO["Y Offset"],
        desc = LO["Vertical offset of the BNet toast frame. Negative values move down, positive values move up."] or "Vertical offset of the BNet toast frame. Negative values move down, positive values move up.",
        getFunc = function() return GetModuleField("bnettoast", "y_offset") or 200 end,
        setFunc = function(val)
            EnsureModuleTable("bnettoast").y_offset = val
            if addon.UpdateBNetToastPosition then addon.UpdateBNetToastPosition() end
        end,
        min = -400, max = 600, step = 1,
        width = 200,
        disabled = function() return not IsEnabled("bnettoast") end,
    })
end

-- Register the tab (order 14 = after Bags, before Appearance/Profiles)
Panel:RegisterTab("bnettoast", LO["BNet Toast"], BuildBNetToastTab, 14)
