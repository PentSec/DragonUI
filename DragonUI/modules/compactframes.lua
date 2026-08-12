local addon = select(2, ...)

-- ============================================================================
-- COMPACT FRAMES MODULE FOR DRAGONUI
-- Flat retail-style health bars on compact party/raid frames.
-- Replaces the grungy Raid-Bar-Hp-Fill texture with a flat solid color
-- (tinted by the unit's health color via SetStatusBarColor).
-- ============================================================================

local FLAT_FILL = "Interface\\Buttons\\WHITE8X8"
local FLAT_BG = "Interface\\Buttons\\WHITE8X8"

-- Mute the vivid class/health colors applied by the client (1.0 = stock,
-- lower = darker). Tune to taste.
local COLOR_MULTIPLIER = 0.75

-- Module state tracking
local CompactFramesModule = {
    initialized = false,
    applied = false,
    originalStates = {}, -- frame -> { background = texture/texcoord/vertex, health = texture, power = texture, powerBg = texture }
    registeredEvents = {},
    hooks = {},
    frames = {},
}

-- Register with ModuleRegistry (if available)
if addon.RegisterModule then
    addon:RegisterModule("compactframes", CompactFramesModule,
        addon.L["Compact Frames"],
        addon.L["Flat retail-style health bars on compact party/raid frames"])
end

-- ============================================================================
-- CONFIGURATION FUNCTIONS
-- ============================================================================

local function IsModuleEnabled()
    return addon:IsModuleEnabled("compactframes")
end

-- ============================================================================
-- FLATTEN HELPERS
-- ============================================================================

local function GetTextureInfo(texture)
    if not texture then return end
    return {
        texture = texture:GetTexture(),
        texcoord = { texture:GetTexCoord() },
        vertex = { texture:GetVertexColor() },
        blend = texture:GetBlendMode(),
        alpha = texture:GetAlpha(),
    }
end

local function RestoreTextureInfo(texture, info)
    if not texture or not info then return end
    if info.texture then texture:SetTexture(info.texture) end
    if info.texcoord then texture:SetTexCoord(unpack(info.texcoord)) end
    if info.vertex then texture:SetVertexColor(unpack(info.vertex)) end
    if info.blend then texture:SetBlendMode(info.blend) end
    if info.alpha then texture:SetAlpha(info.alpha) end
end

-- Save the original art of a compact unit frame (called before first flatten).
local function CaptureOriginal(frame)
    if not frame or CompactFramesModule.originalStates[frame] then return end
    local state = {}

    if frame.background and frame.background.SetTexture then
        state.background = GetTextureInfo(frame.background)
    end
    if frame.healthBar and frame.healthBar.GetStatusBarTexture then
        local tex = frame.healthBar:GetStatusBarTexture()
        if tex then
            state.healthTexture = tex
            state.healthInfo = GetTextureInfo(tex)
        end
    end
    if frame.powerBar and frame.powerBar.GetStatusBarTexture then
        local tex = frame.powerBar:GetStatusBarTexture()
        if tex then
            state.powerTexture = tex
            state.powerInfo = GetTextureInfo(tex)
        end
        if frame.powerBar.background and frame.powerBar.background.SetTexture then
            state.powerBackground = GetTextureInfo(frame.powerBar.background)
        end
    end

    -- The wrap replaces the bar's color method; capture the original so restore
    -- can put it back (otherwise the wrap stays and stops dimming when applied=false).
    if frame.healthBar and frame.healthBar.SetStatusBarColor then
        state.healthSetColor = frame.healthBar.SetStatusBarColor
    end
    if frame.powerBar and frame.powerBar.SetStatusBarColor then
        state.powerSetColor = frame.powerBar.SetStatusBarColor
    end

    CompactFramesModule.originalStates[frame] = state
end

-- Wrap a status bar's color setter so every future color update (health change,
-- class color, aggro) is muted from the value the client passes in. Instance
-- level, so only our bars are affected. Also dims the color that was set BEFORE
-- the wrap existed (one-time, via the original method so it does not recurse),
-- so a frame already colored on apply goes dim immediately without waiting for
-- the next client update.
local function DimStatusBar(bar, multiplier)
    if not bar or not bar.SetStatusBarColor or bar._duiColorWrapped then return end
    bar._duiColorWrapped = true
    local orig = bar.SetStatusBarColor
    bar.SetStatusBarColor = function(self, r, g, b, a)
        if CompactFramesModule.applied then
            orig(self, (r or 1) * multiplier, (g or 1) * multiplier, (b or 1) * multiplier, a)
        else
            orig(self, r, g, b, a)
        end
    end
    -- One-time dim of the pre-existing color (set before the wrap existed).
    local r, g, b = bar:GetStatusBarColor()
    if r and g and b then
        orig(bar, r * multiplier, g * multiplier, b * multiplier)
    end
end

-- Flatten one compact unit frame's bars (HP always; power if present).
local function FlattenFrame(frame)
    if not frame or not frame.healthBar then return end

    CaptureOriginal(frame)

    if frame.background and frame.background.SetTexture then
        frame.background:SetTexture(FLAT_BG)
        frame.background:SetTexCoord(0, 1, 0, 1)
        frame.background:SetVertexColor(0.03, 0.03, 0.03, 0.6)
    end

    if frame.healthBar and frame.healthBar.SetStatusBarTexture then
        frame.healthBar:SetStatusBarTexture(FLAT_FILL)
        DimStatusBar(frame.healthBar, COLOR_MULTIPLIER)
    end

    if frame.powerBar and frame.powerBar.SetStatusBarTexture then
        frame.powerBar:SetStatusBarTexture(FLAT_FILL)
        DimStatusBar(frame.powerBar, COLOR_MULTIPLIER)
        if frame.powerBar.background and frame.powerBar.background.SetTexture then
            frame.powerBar.background:SetTexture(FLAT_BG)
            frame.powerBar.background:SetTexCoord(0, 1, 0, 1)
            frame.powerBar.background:SetVertexColor(0.03, 0.03, 0.03, 0.6)
        end
    end
end

-- True once our flat art is already on the frame's health fill, so sweeps are
-- idempotent and cheap (no repeated SetStatusBarTexture calls).
local function FrameIsFlattened(frame)
    if not frame or not frame.healthBar or not frame.healthBar.GetStatusBarTexture then
        return true
    end
    local tex = frame.healthBar:GetStatusBarTexture()
    if not tex or not tex.GetTexture then return true end
    return tostring(tex:GetTexture() or ""):lower() == FLAT_FILL:lower()
end

local function FlattenIfNeeded(frame)
    if frame and not FrameIsFlattened(frame) then
        FlattenFrame(frame)
    end
end

-- Forward declaration (LayoutFrames hook below references SweepAll before
-- its full definition; Lua locals are lexically scoped and must be declared
-- first or the call hits the global nil).
local SweepAll

-- ============================================================================
-- SWEEP EXISTING FRAMES
-- ============================================================================

local MEMBERS_PER_RAID_GROUP = 5

-- On this client the group/party member buttons are created as $parentMemberN
-- with NO parentKey, so they are NOT reachable as frame.MemberN. The only
-- reliable way to resolve them is the global name <containerName>MemberN.
local function SweepGroupMembers(groupFrame)
    local name = groupFrame and groupFrame.GetName and groupFrame:GetName()
    if not name then return end
    for i = 1, MEMBERS_PER_RAID_GROUP do
        local member = _G[name .. "Member" .. i]
        if member then FlattenIfNeeded(member) end
    end
end

local function SweepContainer(container)
    if not container or not container.frameUpdateList then return end

    for _, list in pairs(container.frameUpdateList) do
        for _, frame in ipairs(list) do
            if frame and frame.healthBar then
                FlattenIfNeeded(frame)
            elseif frame and frame.GetName then
                -- A group container (raid group or party): flatten each member.
                SweepGroupMembers(frame)
            end
        end
    end
end

local function SweepPartyFrame()
    SweepGroupMembers(CompactPartyFrame)
end

-- Hook the container's LayoutFrames on the instance itself: fires whenever
-- the Ascension UI lays out (re)built frames, regardless of when the
-- container was created relative to our hooks. Runs before SweepAll so the
-- very first sweep also arms it.
local function HookContainerLayout()
    local container = _G.CompactRaidFrameContainer
    if not container or CompactFramesModule.hooks.containerHooked then return end
    if not container.LayoutFrames then return end
    local ok = pcall(hooksecurefunc, container, "LayoutFrames", function()
        if not CompactFramesModule.applied then return end
        SweepAll()
    end)
    if ok then
        CompactFramesModule.hooks.containerHooked = true
    end
end

function SweepAll()
    HookContainerLayout()
    SweepContainer(_G.CompactRaidFrameContainer)
    SweepPartyFrame()
end

-- ============================================================================
-- HOOKS
-- ============================================================================

-- These setup functions are called by frame:SetUpFrame() for every compact
-- frame (raid container buttons, party members, raid group members, minis),
-- at creation time and on re-setup. Hooked after the fact so our flat art
-- always wins.
local function SetupHooks()
    if CompactFramesModule.hooks.setupHooked then return end
    CompactFramesModule.hooks.setupHooked = true

    -- The real chokepoint: every compact frame is set up via
    -- CompactUnitMixin:SetUpFrame(func), which calls the stored setup-func
    -- reference directly. hooksecurefunc on the global NAME would not fire,
    -- because frameCreationSpecifiers captures the function VALUE before our
    -- hook. Hooking the mixin method catches every SetUpFrame regardless of
    -- which setup func was passed in. pcall-guarded so one failure never
    -- aborts the module mid-setup (sweeps + remaining hooks still run).
    if CompactUnitMixin and CompactUnitMixin.SetUpFrame then
        pcall(hooksecurefunc, CompactUnitMixin, "SetUpFrame", function(self, func)
            if not CompactFramesModule.applied then return end
            FlattenFrame(self)
        end)
    end

    -- Keep the global-name hooks too: harmless, and catch any direct calls to
    -- the setup functions outside the SetUpFrame path.
    pcall(hooksecurefunc, "DefaultCompactUnitFrameSetup", function(frame)
        if not CompactFramesModule.applied then return end
        FlattenFrame(frame)
    end)

    pcall(hooksecurefunc, "DefaultCompactMiniFrameSetup", function(frame)
        if not CompactFramesModule.applied then return end
        FlattenFrame(frame)
    end)
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local function ApplyCompactFramesSystem()
    if CompactFramesModule.applied then return end

    SetupHooks()
    SweepAll()

    CompactFramesModule.applied = true
end

local function RestoreCompactFramesSystem()
    if not CompactFramesModule.applied then return end

    for frame, state in pairs(CompactFramesModule.originalStates) do
        if state.background then
            RestoreTextureInfo(frame.background, state.background)
        end
        if state.healthInfo then
            RestoreTextureInfo(state.healthTexture, state.healthInfo)
        end
        if state.powerInfo then
            RestoreTextureInfo(state.powerTexture, state.powerInfo)
        end
        if state.powerBackground then
            RestoreTextureInfo(frame.powerBar and frame.powerBar.background, state.powerBackground)
        end
        if state.healthSetColor and frame.healthBar then
            frame.healthBar.SetStatusBarColor = state.healthSetColor
            frame.healthBar._duiColorWrapped = nil
        end
        if state.powerSetColor and frame.powerBar then
            frame.powerBar.SetStatusBarColor = state.powerSetColor
            frame.powerBar._duiColorWrapped = nil
        end
    end
    CompactFramesModule.originalStates = {}

    CompactFramesModule.applied = false
end

local function RefreshCompactFramesSystem()
    if CompactFramesModule.applied then
        RestoreCompactFramesSystem()
    end
    if IsModuleEnabled() then
        ApplyCompactFramesSystem()
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- The Ascension container rebuilds its frames on these events; re-sweep so
-- any frame that existed before our hooks were installed still gets flattened.
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "DragonUI" then
        if not IsModuleEnabled() then return end

        -- The Ascension compact raid frame container is its own addon that may
        -- load after DragonUI; sweep it once it is up.
        addon:After(1, function()
            if not CompactFramesModule.applied then return end
            SweepAll()
        end)

    elseif event == "ADDON_LOADED" then
        -- Any addon finishing its load may have just created the compact
        -- container (or rebuilt its frames). Re-arm + re-sweep cheaply.
        if not IsModuleEnabled() then return end
        if CompactFramesModule.applied then
            SweepAll()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not IsModuleEnabled() then return end

        SetupHooks()
        if not CompactFramesModule.applied then
            -- Belt-and-suspenders: apply directly even if the registry never
            -- refreshed us, so a fresh profile works without a reload.
            ApplyCompactFramesSystem()
        else
            SweepAll()
        end

    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
        if not CompactFramesModule.applied then return end
        SweepAll()
    end
end)

-- Safety net: compact frames can appear at any time (container addon load,
-- raid layout rebuild, group re-setup). A low-frequency re-sweep guarantees
-- they get flattened no matter how or when they were created.
local SWEEP_INTERVAL = 1.5
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    if not CompactFramesModule.applied then return end
    self.sweepTimer = (self.sweepTimer or 0) + elapsed
    if self.sweepTimer >= SWEEP_INTERVAL then
        self.sweepTimer = 0
        SweepAll()
    end
end)

-- Expose lifecycle functions for the ModuleRegistry
addon.ApplyCompactFramesSystem = ApplyCompactFramesSystem
addon.RestoreCompactFramesSystem = RestoreCompactFramesSystem
addon.RefreshCompactFramesSystem = RefreshCompactFramesSystem
