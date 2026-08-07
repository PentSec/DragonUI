--[[
================================================================================
DragonUI Options Panel - General Tab
================================================================================
Editor Mode, KeyBind Mode, and general settings.
================================================================================
]]

local addon = DragonUI
if not addon then return end

local C = addon.PanelControls
local Panel = addon.OptionsPanel
local LO = addon.LO

-- ============================================================================
-- GENERAL TAB BUILDER
-- ============================================================================

local function BuildGeneralTab(scroll)
    -- ====================================================================
    -- ABOUT
    -- ====================================================================
    local about = C:AddSection(scroll, LO["About"])

    C:AddLabel(about, "|cff1784d1" .. LO["DragonUI"] .. " v" .. (addon.RELEASE_VERSION or "?") .. "|r")
    C:AddDescription(about, LO["Bringing the retail WoW look to 3.3.5a, inspired by Dragonflight UI."])
    C:AddSpacer(about)
    C:AddDescription(about, LO["This Fork is maintained by PentSec for AscensionWow, based on the original work by Neticsoul."])
    C:AddSpacer(about)
    C:AddDescription(about, LO["Created and maintained by Neticsoul, with community contributions."])
    C:AddSpacer(about)
    C:AddDescription(about, LO["Use the tabs on the left to configure modules, action bars, unit frames, minimap, and more."])
    C:AddSpacer(about)
    C:AddDescription(about, LO["Commands: /dragonui, /dui, /pi — /dragonui edit (editor) — /dragonui help"])
    C:AddSpacer(about)
    C:AddDescription(about, LO["GitHub (select and Ctrl+C to copy):"])
    C:AddCopyableText(about, "https://github.com/PentSec/DragonUI")

    C:AddSpacer(scroll)

    -- ====================================================================
    -- LANGUAGE
    -- ====================================================================
    local language = C:AddSection(scroll, LO["Language"])

    C:AddDescription(language, LO["Choose the language used by the DragonUI interface."])

    local localeNames = {
        enUS = "English",
        esES = "Español",
        esMX = "Español (México)",
        ptBR = "Português",
        deDE = "Deutsch",
        frFR = "Français",
        ruRU = "Русский",
        zhCN = "简体中文",
        zhTW = "繁體中文",
        koKR = "한국어",
    }

    -- Hide languages the client font cannot draw; their names would already show as "?" here.
    local localeValues = { auto = LO["Follow the client language"] }
    for code, name in pairs(localeNames) do
        if not addon.CanRenderLocale or addon.CanRenderLocale(code) then
            localeValues[code] = name
        end
    end

    C:AddDropdown(language, {
        label = LO["Language"],
        desc  = LO["Choose the language used by the DragonUI interface."],
        values = localeValues,
        getFunc = function()
            return (addon.db and addon.db.global and addon.db.global.locale) or "auto"
        end,
        setFunc = function(value)
            if addon.db and addon.db.global then
                addon.db.global.locale = value
            end
        end,
        callback = function()
            StaticPopup_Show("DRAGONUI_RELOAD_UI")
        end,
        width = 200,
    })

    C:AddSpacer(scroll)

    -- ====================================================================
    -- QUICK ACCESS
    -- ====================================================================
    local actions = C:AddSection(scroll, LO["Quick Actions"])

    C:AddDescription(actions, LO["Jump to popular settings sections."])

    C:AddButton(actions, {
        label = LO["Dark Mode"],
        desc = LO["Configure dark tinting for all UI chrome."],
        width = 200,
        callback = function() Panel:SelectTab("enhancements") end,
    })

    C:AddButton(actions, {
        label = LO["Fat Health Bar"],
        desc = LO["Full-width health bar that fills the entire player frame."],
        width = 200,
        callback = function() Panel:SelectTab("unitframes") end,
    })

    C:AddButton(actions, {
        label = LO["Dragon Decoration"],
        desc = LO["Add a decorative dragon to your player frame."],
        width = 200,
        callback = function() Panel:SelectTab("unitframes") end,
    })

    C:AddButton(actions, {
        label = LO["Unit Frame Layers"],
        desc = LO["Heal prediction, absorb shields and animated health loss."],
        width = 200,
        callback = function() Panel:SelectTab("enhancements") end,
    })

    C:AddButton(actions, {
        label = LO["Action Bar Layout"],
        desc = LO["Change columns, rows, and buttons shown per action bar."],
        width = 200,
        callback = function()
            if addon.SetActionBarSubTab then addon.SetActionBarSubTab("layout") end
            Panel:SelectTab("actionbars")
        end,
    })

    C:AddButton(actions, {
        label = LO["Grayscale Icons"],
        desc = LO["Switch micro menu icons between colored and grayscale style."],
        width = 200,
        callback = function() Panel:SelectTab("micromenu") end,
    })
end

-- Register the tab
Panel:RegisterTab("general", LO["General"], BuildGeneralTab, 1)
