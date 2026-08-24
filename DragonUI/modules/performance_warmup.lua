-- ============================================================================
-- DragonUI - Performance Warmup Module
-- Forces select native panels to show/hide once on login. Several Blizzard
-- panels do expensive first-time layout work only the first time they are
-- shown per session. DragonUI's own frames anchored to PlayerFrame make some
-- of that first-show cost worse, causing freezes during gameplay. Paying
-- that cost here, during the loading screen, avoids the mid-gameplay hitch.
-- ============================================================================
local addon = select(2, ...)

local WarmupModule = {
    initialized = false,
    applied = false,
}

if addon.RegisterModule then
    addon:RegisterModule("performance_warmup", WarmupModule,
        addon.L["UI Warmup"],
        addon.L["Pre-loads select Blizzard panels on login to avoid first-use freezes during gameplay."])
end

local function IsWarmupEnabled()
    return addon.db and addon.db.profile and addon.db.profile.modules
        and addon.db.profile.modules.performance_warmup
        and addon.db.profile.modules.performance_warmup.enabled
end

-- Validate each entry individually before adding it here (Canary/profiler).
local WARMUP_PANELS = {
    "QuestFrame",
    "SpellBookFrame",
    "LFDParentFrame",
    "FriendsFrame",
    "WorldMapFrame",
    "TradeFrame",
    "AscensionLFGFrame",
}

-- Show/Hide triggers each panel's own OnShow sound. Muting SFX only around
-- the call avoids an audible "windows opening" burst on login.
local function WarmupPanel(name)
    local frame = _G[name]
    if not (frame and frame.Show and frame.Hide) then
        return
    end

    local prevSFX = GetCVar("Sound_EnableSFX")
    SetCVar("Sound_EnableSFX", "0")

    pcall(function()
        frame:Show()
        frame:Hide()
    end)

    SetCVar("Sound_EnableSFX", prevSFX)
end

local function WarmupNext(index)
    if InCombatLockdown() then
        return
    end
    if not IsWarmupEnabled() then
        return
    end

    local name = WARMUP_PANELS[index]
    if not name then
        WarmupModule.applied = true
        return
    end

    WarmupPanel(name)

    if WARMUP_PANELS[index + 1] then
        addon:After(0.3, function() WarmupNext(index + 1) end)
    else
        WarmupModule.applied = true
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    addon:After(0.3, function() WarmupNext(1) end)
end)

WarmupModule.initialized = true
