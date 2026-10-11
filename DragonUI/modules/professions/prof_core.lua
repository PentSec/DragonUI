-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)

-- Forever professions: Blizzard's TradeSkillFrame stays the UIPanel host and engine; DragonUI only adds the presentation.
local P = addon.Professions or {}
addon.Professions = P

local Module = { initialized = false, applied = false }
P.Module = Module
P.active = false

addon:RegisterModule("professions", Module, addon.L["Professions"],
    addon.L["Forever-style professions window that keeps every stock function."],
    { lifecyclePrefix = "Professions", loadOnce = true })

local REPLACEMENTS = { "Skillet", "AdvancedTradeSkillWindow", "ATSW" }

local listeners = {}

function P.On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end

function P.Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end

function P.YieldsTo()
    for _, name in ipairs(REPLACEMENTS) do
        if IsAddOnLoaded(name) then return name end
    end
end

function P.HostReady()
    return TradeSkillFrame ~= nil and type(TradeSkillFrame_Update) == "function"
end

local hooked = false
local function InstallHooks()
    if hooked or not P.HostReady() then return end
    hooked = true
    hooksecurefunc("TradeSkillFrame_Update", function()
        if not P.active then return end
        local line = GetTradeSkillLine()
        local linked = IsTradeSkillLinked() and true or false
        if line ~= P.currentLine or linked ~= P.currentLinked then
            P.currentLine, P.currentLinked = line, linked
            P.Fire("ProfessionChanged", line, linked)
        end
        P.Fire("Update")
    end)
    hooksecurefunc("TradeSkillFrame_SetSelection", function(id)
        if P.active then P.Fire("Selection", id) end
    end)
    TradeSkillFrame:HookScript("OnShow", function()
        if P.active then P.Fire("Show") end
    end)
    TradeSkillFrame:HookScript("OnHide", function()
        P.currentLine = nil
        if P.active then P.Fire("Hide") end
    end)
end

local function Activate()
    if P.active or not addon:IsModuleEnabled("professions") or not P.HostReady() then return end
    local other = IsLoggedIn() and P.YieldsTo()
    if other then
        addon:Debug("professions: yielding to", other)
        return
    end
    InstallHooks()
    P.active = true
    P.Fire("Activate")
end

local function Deactivate()
    if not P.active then return end
    P.active = false
    P.Fire("Deactivate")
end

-- The micro button can open the window before any profession has loaded Blizzard_TradeSkillUI.
function P.EnsureHost()
    if not Module.applied then return false end
    if not P.HostReady() then TradeSkillFrame_LoadUI() end
    Activate()
    return P.active
end

-- Nothing here is protected, so activation runs in combat too: a first First Aid open mid-fight gets the Forever window.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_TradeSkillUI" then return end
    if Module.applied then Activate() end
end)

function Module:ApplyProfessionsSystem()
    self.initialized, self.applied = true, true
    Activate()
end

function Module:RestoreProfessionsSystem()
    self.applied = false
    Deactivate()
end

function Module:RefreshProfessionsSystem()
    if addon:IsModuleEnabled("professions") then
        self:ApplyProfessionsSystem()
        P.Fire("Refresh")
    else
        self:RestoreProfessionsSystem()
    end
end
