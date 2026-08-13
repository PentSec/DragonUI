local addon = select(2, ...)
local L = addon.L

-- ============================================================================
-- TOOLTIP MODULE FOR DRAGONUI
-- Enhances GameTooltip with class colors, health bars, target-of-target,
-- and cleaner styling inspired by Dragonflight tooltips.
-- ============================================================================

-- Module state tracking
local TooltipModule = {
    initialized = false,
    applied = false,
    originalStates = {},
    hooks = {},
    frames = {}
}

-- Register with ModuleRegistry (if available)
if addon.RegisterModule then
    addon:RegisterModule("tooltip", TooltipModule,
        addon.L["Tooltip"],
        addon.L["Enhanced tooltip styling with class colors and health bars"])
end

-- ============================================================================
-- CONFIGURATION FUNCTIONS
-- ============================================================================

local function GetModuleConfig()
    return addon:GetModuleConfig("tooltip")
end

local function IsModuleEnabled()
    return addon:IsModuleEnabled("tooltip")
end

-- ============================================================================
-- CLASS COLOR CACHE
-- ============================================================================

local CLASS_COLORS = {}
for class, color in pairs(RAID_CLASS_COLORS) do
    CLASS_COLORS[class] = { r = color.r, g = color.g, b = color.b }
end

-- Faction colors for hostile/friendly/neutral
local FACTION_COLORS = {
    friendly = { r = 0.2, g = 0.8, b = 0.2 },
    neutral  = { r = 1.0, g = 1.0, b = 0.0 },
    hostile  = { r = 1.0, g = 0.2, b = 0.2 },
    tapped   = { r = 0.6, g = 0.6, b = 0.6 },
}

-- ============================================================================
-- TOOLTIP HEALTH BAR ENHANCEMENT
-- ============================================================================

local HEALTHBAR_HEIGHT = 6
local HEALTHBAR_BOTTOM_PAD = 10  -- space between bar and tooltip bottom edge
local TOOLTIP_WIDGET_ANCHOR = "BOTTOMRIGHT"
local TOOLTIP_WIDGET_POSX = -90
local TOOLTIP_WIDGET_POSY = 100

-- Restyle the existing Blizzard GameTooltipStatusBar instead of creating a new one.
-- This avoids the double health bar bug.
local function StyleHealthBar()
    if TooltipModule.healthBarStyled then return end

    local bar = GameTooltipStatusBar
    if not bar then return end

    -- Restyle: slimmer, better texture
    bar:SetHeight(HEALTHBAR_HEIGHT)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")

    -- Position bar INSIDE the tooltip bottom area (like DragonflightUI)
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", GameTooltip, "BOTTOMLEFT", 9, HEALTHBAR_BOTTOM_PAD)
    bar:SetPoint("BOTTOMRIGHT", GameTooltip, "BOTTOMRIGHT", -9, HEALTHBAR_BOTTOM_PAD)

    -- Add dark background behind the bar
    if not bar.__DragonUI_bg then
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bg:SetVertexColor(0.15, 0.15, 0.15, 0.8)
        bar.__DragonUI_bg = bg
    end

    TooltipModule.healthBarStyled = true
end

-- Same trick Blizzard's own GameTooltip_ShowStatusBar uses: a real blank AddLine, so native auto-height covers it.
local function ReserveHealthBarLine()
    if not GameTooltipStatusBar or not GameTooltipStatusBar:IsShown() then return end
    GameTooltip:AddLine(" ")
    GameTooltip:Show()
end

-- Deferred one frame so it runs after every other addon's OnTooltipSetUnit hook (e.g. idWoW) has added its lines.
local reserveRunner = CreateFrame("Frame")
reserveRunner:Hide()
reserveRunner:SetScript("OnUpdate", function(self)
    self:Hide()
    ReserveHealthBarLine()
end)

local function AdjustTooltipForHealthBar()
    reserveRunner:Show()
end

-- ============================================================================
-- TOOLTIP BORDER COLORING
-- ============================================================================

-- Color the tooltip border based on unit reaction/class
local function ColorTooltipBorder(unit)
    if not unit or not UnitExists(unit) then return end

    local config = GetModuleConfig()
    if not config or not config.class_colored_border then return end

    local r, g, b = 1, 1, 1

    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class and CLASS_COLORS[class] then
            r = CLASS_COLORS[class].r
            g = CLASS_COLORS[class].g
            b = CLASS_COLORS[class].b
        end
    else
        local reaction = UnitReaction(unit, "player")
        if not reaction then
            -- Tapped or unknown
            r, g, b = FACTION_COLORS.tapped.r, FACTION_COLORS.tapped.g, FACTION_COLORS.tapped.b
        elseif reaction >= 5 then
            r, g, b = FACTION_COLORS.friendly.r, FACTION_COLORS.friendly.g, FACTION_COLORS.friendly.b
        elseif reaction == 4 then
            r, g, b = FACTION_COLORS.neutral.r, FACTION_COLORS.neutral.g, FACTION_COLORS.neutral.b
        else
            r, g, b = FACTION_COLORS.hostile.r, FACTION_COLORS.hostile.g, FACTION_COLORS.hostile.b
        end
    end

    GameTooltip:SetBackdropBorderColor(r, g, b)
end

-- ============================================================================
-- TOOLTIP NAME COLORING
-- ============================================================================

-- Color the first line (unit name) by class color for players
local function ColorTooltipName(unit)
    if not unit or not UnitExists(unit) then return end

    local config = GetModuleConfig()
    if not config or not config.class_colored_name then return end

    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class and CLASS_COLORS[class] then
            local c = CLASS_COLORS[class]
            local name = UnitName(unit)
            if name then
                GameTooltipTextLeft1:SetTextColor(c.r, c.g, c.b)
            end
        end
    end
end

-- ============================================================================
-- TARGET-OF-TARGET LINE
-- ============================================================================

-- Add "Targeting: <name>" line to tooltip
local function AddTargetOfTarget(unit)
    if not unit or not UnitExists(unit) then return end

    local config = GetModuleConfig()
    if not config or not config.target_of_target then return end

    local targetUnit = unit .. "target"
    if UnitExists(targetUnit) then
        local targetName = UnitName(targetUnit)
        if targetName then
            local color = "|cFFFFFFFF"
            if UnitIsPlayer(targetUnit) then
                local _, class = UnitClass(targetUnit)
                if class and CLASS_COLORS[class] then
                    local c = CLASS_COLORS[class]
                    color = string.format("|cFF%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
                end
            end
            GameTooltip:AddLine(string.format(L["Targeting: %s"], color .. targetName .. "|r"), 0.7, 0.7, 0.7)
        end
    end
end

-- ============================================================================
-- PLAYER STATS LINE (item level / PvE-PvP power / prestige)
-- ============================================================================

-- Ascension-only data for another player (UnitPvEPower/UnitPvPPower/
-- UnitAverageItemLevel) only exists after the client has that player's gear.
-- That normally requires an Inspect, so on hover we fire NotifyInspect and
-- rebuild the tooltip when the data arrives — no manual Inspect needed.
--
-- Strategy: every hover reads the client's data live (works for group members
-- and already-inspected players). Whatever is displayable is cached per GUID
-- for 15 minutes so item level shows without an inspect round trip; when the
-- gear cache is missing for a max-level player we request the inspect. Once
-- INSPECT_READY lands, the cached snapshot is dropped so the next read picks
-- up the fresh data.
local INSPECT_CACHE_TTL = 900
local INSPECT_REQUEST_COOLDOWN = 3

local inspectCache = {}          -- guid -> { time, itemLevel, pvePower, pvpPower }
local pendingInspectGUID = nil   -- guid of the inspect request in flight
local pendingInspectUnit = nil   -- unit token of that request
local lastInspectRequest = {}    -- guid -> GetTime() of the last request
local inspectRequestCount = 0

local function GetCachedInspect(guid)
    local entry = guid and inspectCache[guid]
    if entry then
        if GetTime() - entry.time < INSPECT_CACHE_TTL then
            return entry
        end
        inspectCache[guid] = nil
    end
    return nil
end

-- Per-GUID cooldown so rapidly alternating hovers don't spam NotifyInspect.
-- The map is pruned when it grows past 100 entries.
local function CanRequestInspect(guid, now)
    local last = lastInspectRequest[guid]
    return not last or now - last >= INSPECT_REQUEST_COOLDOWN
end

local function NoteInspectRequest(guid, now)
    if not lastInspectRequest[guid] then
        inspectRequestCount = inspectRequestCount + 1
    end
    lastInspectRequest[guid] = now
    if inspectRequestCount > 100 then
        local cutoff = now - 60
        for g, t in pairs(lastInspectRequest) do
            if t < cutoff then
                lastInspectRequest[g] = nil
            end
        end
        inspectRequestCount = 0
    end
end

local function RequestInspectData(unit, guid)
    if not guid then return end
    if not CanInspect or not CanInspect(unit) then return end
    if not NotifyInspect then return end
    local now = GetTime()
    if not CanRequestInspect(guid, now) then return end
    NoteInspectRequest(guid, now)
    pendingInspectGUID = guid
    pendingInspectUnit = unit
    NotifyInspect(unit)
end

local function CacheInspect(guid, itemLevel, pvePower, pvpPower)
    if not guid then return end
    inspectCache[guid] = { time = GetTime(), itemLevel = itemLevel, pvePower = pvePower, pvpPower = pvpPower }
    if pendingInspectGUID == guid then
        pendingInspectGUID = nil
        pendingInspectUnit = nil
    end
end

-- Add one line per stat (sidepanel order: Item Level, PvE, PvP, Prestige).
local function AddPlayerStatsInfo(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    -- Vanilla 3.3.5a has no UnitPvEPower / UnitAverageItemLevel (Ascension client only)
    if not UnitPvEPower or not UnitAverageItemLevel then return end

    local config = GetModuleConfig()
    if not config or not config.player_stats then return end

    local guid = UnitGUID(unit)
    local itemLevel, pvePower, pvpPower, prestige

    if unit == "player" then
        -- Local player: always available, no inspect needed
        itemLevel = UnitAverageItemLevel("player")
        pvePower = UnitPvEPower("player")
        pvpPower = UnitPvPPower and UnitPvPPower("player")
        if GetPrestigeLevel then
            prestige = select(1, GetPrestigeLevel()) -- local-only, no server data
        end
    else
        local cached = GetCachedInspect(guid)
        if cached then
            itemLevel, pvePower, pvpPower = cached.itemLevel, cached.pvePower, cached.pvpPower
        else
            -- Live read: works for group members and players already inspected
            itemLevel = UnitAverageItemLevel(unit)
            pvePower = UnitPvEPower(unit)
            pvpPower = UnitPvPPower and UnitPvPPower(unit)

            -- PvE/PvP power only applies at max level (the Ascension sidepanel
            -- gates it with minLevel = GetMaxLevel()); below that it is always 0.
            local atMaxLevel = (not GetMaxLevel) or (UnitLevel(unit) >= GetMaxLevel())
            local hasPowers = (pvePower and pvePower > 0) or (pvpPower and pvpPower > 0)
            local hasData = (itemLevel and itemLevel > 0)
                or (pvePower and pvePower > 0)
                or (pvpPower and pvpPower > 0)

            -- Cache whatever is displayable right away so item level shows
            -- without waiting for an inspect round trip. Never cache an empty
            -- snapshot, or a failed read would block retries for the TTL.
            if hasData then
                CacheInspect(guid, itemLevel, pvePower, pvpPower)
            end

            -- No data at all (any level), or a max-level player whose powers the
            -- client only knows after an inspect: request the gear data.
            if not hasData or (not hasPowers and atMaxLevel) then
                RequestInspectData(unit, guid)
            end
        end
    end

    if itemLevel and itemLevel > 0 then
        GameTooltip:AddLine(string.format("%s: |cFFFFFFFF%.2f|r", STAT_ITEM_LEVEL or "Item Level", itemLevel), 0.7, 0.7, 0.7)
    end
    if pvePower and pvePower > 0 then
        GameTooltip:AddLine(string.format("%s: |cFFFFFFFF%d/%d|r", PVE_POWER_LABEL or "PvE Power", pvePower, PVE_POWER_CAP or 495), 0.7, 0.7, 0.7)
    end
    if pvpPower and pvpPower > 0 then
        GameTooltip:AddLine(string.format("%s: |cFFFFFFFF%d/%d|r", PVP_POWER_LABEL or "PvP Power", pvpPower, PVP_POWER_CAP or 495), 0.7, 0.7, 0.7)
    end
    if prestige and prestige > 0 then
        GameTooltip:AddLine(string.format("%s: |cFFFFFFFF%d|r", PRESTIGE_LEVEL_LABEL or "Prestige", prestige), 0.7, 0.7, 0.7)
    end
end

-- Inspect data for the pending request has arrived: drop our cached snapshot
-- so the next read picks up the fresh gear, and if the same player is still
-- hovered, re-set the unit so OnTooltipSetUnit re-runs with real values.
-- SetUnit with the same unit always re-fires OnTooltipSetUnit and clears
-- previous lines first.
local function OnInspectReady(event, unit)
    if not IsModuleEnabled() then return end
    local config = GetModuleConfig()
    if not config or not config.player_stats then return end

    -- Ignore readies for a unit we did not request (args may be empty on some
    -- clients, in which case we rely on the pending-guid match below).
    if unit and pendingInspectUnit and unit ~= pendingInspectUnit then return end

    local guid = pendingInspectGUID
    if not guid then return end
    pendingInspectGUID = nil
    pendingInspectUnit = nil

    if inspectCache[guid] then
        inspectCache[guid] = nil
    end

    local _, ttUnit = GameTooltip:GetUnit()
    if not ttUnit or not UnitExists(ttUnit) then return end
    if UnitGUID(ttUnit) ~= guid then return end

    GameTooltip:SetUnit(ttUnit)
end

local inspectEventFrame = CreateFrame("Frame")

-- ============================================================================
-- HEALTH BAR UPDATE
-- ============================================================================

-- Store current tooltip unit and its bar color so OnValueChanged can re-apply
local currentTooltipBarColor = nil

local function UpdateHealthBar(unit)
    local bar = GameTooltipStatusBar
    if not bar then return end

    if not unit or not UnitExists(unit) then
        currentTooltipBarColor = nil
        return
    end

    local config = GetModuleConfig()
    if not config or not config.health_bar then
        currentTooltipBarColor = nil
        return
    end

    -- Style the bar on first use
    StyleHealthBar()

    -- Color by class or reaction
    local r, g, b = 0.2, 0.8, 0.2
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class and CLASS_COLORS[class] then
            r = CLASS_COLORS[class].r
            g = CLASS_COLORS[class].g
            b = CLASS_COLORS[class].b
        end
    end
    bar:SetStatusBarColor(r, g, b)
    -- Cache the color so OnValueChanged can re-apply it
    currentTooltipBarColor = { r, g, b }
end

-- ============================================================================
-- TOOLTIP ANCHOR (optional: anchor to cursor vs default)
-- ============================================================================

local function GetTooltipWidgetConfig()
    if not addon.db or not addon.db.profile then
        return nil
    end

    addon.db.profile.widgets = addon.db.profile.widgets or {}
    addon.db.profile.widgets.tooltip = addon.db.profile.widgets.tooltip or {}

    local cfg = addon.db.profile.widgets.tooltip
    if not cfg.anchor then cfg.anchor = TOOLTIP_WIDGET_ANCHOR end
    if cfg.posX == nil then cfg.posX = TOOLTIP_WIDGET_POSX end
    if cfg.posY == nil then cfg.posY = TOOLTIP_WIDGET_POSY end

    return cfg
end

local function IsTooltipCursorAnchored()
    local config = GetModuleConfig()
    return config and config.anchor_cursor == true
end

local function ApplyTooltipWidgetPosition()
    local anchorFrame = TooltipModule.frames and TooltipModule.frames.tooltipAnchor
    local cfg = GetTooltipWidgetConfig()
    if not anchorFrame or not cfg then return end

    anchorFrame:ClearAllPoints()
    anchorFrame:SetPoint(cfg.anchor or TOOLTIP_WIDGET_ANCHOR, UIParent, cfg.anchor or TOOLTIP_WIDGET_ANCHOR, cfg.posX or TOOLTIP_WIDGET_POSX, cfg.posY or TOOLTIP_WIDGET_POSY)
end

local function SyncTooltipEditorPreviewLayout()
    local anchorFrame = TooltipModule.frames and TooltipModule.frames.tooltipAnchor
    if not anchorFrame or not GameTooltip or not GameTooltip:IsShown() then
        return
    end

    local width = GameTooltip:GetWidth()
    local height = GameTooltip:GetHeight()
    if width and width > 0 and height and height > 0 then
        anchorFrame:SetSize(width, height)
    end

    anchorFrame:SetFrameStrata(GameTooltip:GetFrameStrata() or "TOOLTIP")
    anchorFrame:SetFrameLevel((GameTooltip:GetFrameLevel() or 1) + 20)
end

local function ShowTooltipEditorPreview()
    local anchorFrame = TooltipModule.frames and TooltipModule.frames.tooltipAnchor
    if not anchorFrame or IsTooltipCursorAnchored() then
        return
    end

    if anchorFrame.editorText then
        anchorFrame.editorText:ClearAllPoints()
        anchorFrame.editorText:SetPoint("BOTTOM", anchorFrame, "BOTTOM", 0, 6)
    end

    GameTooltip:SetOwner(anchorFrame, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    GameTooltip:SetUnit("player")
    GameTooltip:Show()

    SyncTooltipEditorPreviewLayout()
    anchorFrame:SetScript("OnUpdate", function()
        SyncTooltipEditorPreviewLayout()
    end)
end

local function HideTooltipEditorPreview()
    local anchorFrame = TooltipModule.frames and TooltipModule.frames.tooltipAnchor
    if anchorFrame then
        anchorFrame:SetScript("OnUpdate", nil)
        anchorFrame:SetSize(180, 50)
    end

    if GameTooltip and GameTooltip:IsShown() then
        GameTooltip:Hide()
    end
end

local function EnsureTooltipWidget()
    if TooltipModule.frames.tooltipAnchor or not addon.CreateUIFrame then
        return
    end

    local anchorFrame = addon.CreateUIFrame(180, 50, "TooltipWidget")
    TooltipModule.frames.tooltipAnchor = anchorFrame

    anchorFrame:SetFrameStrata("TOOLTIP")
    anchorFrame:SetFrameLevel((GameTooltip and GameTooltip:GetFrameLevel() or 1) + 20)

    if anchorFrame.editorText then
        anchorFrame.editorText:ClearAllPoints()
        anchorFrame.editorText:SetPoint("BOTTOM", anchorFrame, "BOTTOM", 0, 6)
    end

    ApplyTooltipWidgetPosition()

    if addon.RegisterEditableFrame then
        addon:RegisterEditableFrame({
            name = "tooltip",
            frame = anchorFrame,
            blizzardFrame = GameTooltip,
            configPath = {"widgets", "tooltip"},
            editorVisible = function()
                return not IsTooltipCursorAnchored()
            end,
            showTest = ShowTooltipEditorPreview,
            hideTest = HideTooltipEditorPreview,
            onShow = ShowTooltipEditorPreview,
            onHide = function()
                HideTooltipEditorPreview()
                ApplyTooltipWidgetPosition()
            end,
            module = TooltipModule,
        })
    end
end

local function EnsureTooltipAnchorHook()
    if TooltipModule.hooks["DefaultAnchor"] then
        return
    end

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if tooltip ~= GameTooltip then return end

        if IsTooltipCursorAnchored() then
            tooltip:SetOwner(parent, "ANCHOR_CURSOR")
            return
        end

        local anchorFrame = TooltipModule.frames and TooltipModule.frames.tooltipAnchor
        if anchorFrame then
            local point, _, relativePoint, x, y = anchorFrame:GetPoint(1)
            tooltip:SetOwner(parent or UIParent, "ANCHOR_NONE")
            tooltip:ClearAllPoints()
            tooltip:SetPoint(point or TOOLTIP_WIDGET_ANCHOR, UIParent, relativePoint or point or TOOLTIP_WIDGET_ANCHOR, x or TOOLTIP_WIDGET_POSX, y or TOOLTIP_WIDGET_POSY)
        end
    end)

    TooltipModule.hooks["DefaultAnchor"] = true
end

-- ============================================================================
-- AURA SOURCE (caster name on buff/debuff tooltips)
-- ============================================================================

local function ShouldShowAuraSource()
    if not IsModuleEnabled() then
        return false
    end
    local cfg = GetModuleConfig()
    return not cfg or cfg.show_aura_source ~= false
end

local function RGBToHex(r, g, b)
    return string.format("|cff%02x%02x%02x",
        math.floor((r or 1) * 255 + 0.5),
        math.floor((g or 1) * 255 + 0.5),
        math.floor((b or 1) * 255 + 0.5))
end

local AURA_ID_LABEL = _G.ID or "ID"
local AURA_SOURCE_FALLBACK_COLOR = { r = 1, g = 1, b = 1 }

local function AuraSourceAlreadyShown(tt, spellId)
    if not spellId then
        return false
    end
    local needle = tostring(spellId)
    for i = 1, tt:NumLines() do
        local left = _G["GameTooltipTextLeft" .. i]
        local text = left and left:GetText()
        if text and text:find(needle, 1, true) and text:find(AURA_ID_LABEL, 1, true) then
            return true
        end
    end
    return false
end

-- Returns UnitAura's 8th..11th values: unitCaster, isStealable, shouldConsolidate, spellId.
local function GetAuraCasterAndSpellId(unit, index, filter)
    if filter == "HARMFUL" then
        return select(8, UnitDebuff(unit, index))
    elseif filter == "HELPFUL" then
        return select(8, UnitBuff(unit, index))
    end
    return select(8, UnitAura(unit, index, filter))
end

local function AddAuraSourceInfo(tt, unit, index, filter)
    if not ShouldShowAuraSource() or not unit or not index then
        return
    end

    local caster, _, _, spellId = GetAuraCasterAndSpellId(unit, index, filter)

    if AuraSourceAlreadyShown(tt, spellId) then
        return
    end

    local leftText
    if spellId then
        leftText = string.format("|cFFCA3C3C%s|r %d", AURA_ID_LABEL, spellId)
    end

    local rightText
    if caster then
        local name = UnitName(caster)
        if name then
            local _, class = UnitClass(caster)
            local color = (class and CLASS_COLORS[class]) or AURA_SOURCE_FALLBACK_COLOR
            rightText = RGBToHex(color.r, color.g, color.b) .. name
        end
    end

    if leftText and rightText then
        tt:AddDoubleLine(leftText, rightText)
        tt:Show()
    elseif leftText then
        tt:AddLine(leftText)
        tt:Show()
    elseif rightText then
        tt:AddLine(rightText)
        tt:Show()
    end
end

local function HookAuraTooltips()
    if TooltipModule.hooks["AuraSource"] then
        return
    end

    if GameTooltip.SetUnitBuff then
        hooksecurefunc(GameTooltip, "SetUnitBuff", function(self, unit, index)
            AddAuraSourceInfo(self, unit, index, "HELPFUL")
        end)
    end

    if GameTooltip.SetUnitDebuff then
        hooksecurefunc(GameTooltip, "SetUnitDebuff", function(self, unit, index)
            AddAuraSourceInfo(self, unit, index, "HARMFUL")
        end)
    end

    if GameTooltip.SetUnitAura then
        hooksecurefunc(GameTooltip, "SetUnitAura", function(self, unit, index, filter)
            AddAuraSourceInfo(self, unit, index, filter)
        end)
    end

    TooltipModule.hooks["AuraSource"] = true
end

-- ============================================================================
-- APPLY / RESTORE SYSTEM
-- ============================================================================

local function ApplyTooltipSystem()
    if TooltipModule.applied then return end

    EnsureTooltipAnchorHook()
    EnsureTooltipWidget()
    ApplyTooltipWidgetPosition()
    HookAuraTooltips()

    -- Hook GameTooltip:SetUnit
    if not TooltipModule.hooks["SetUnit"] then
        GameTooltip:HookScript("OnTooltipSetUnit", function(self)
            if not IsModuleEnabled() then return end
            local _, unit = self:GetUnit()
            if unit then
                ColorTooltipBorder(unit)
                AddTargetOfTarget(unit)
                AddPlayerStatsInfo(unit)
                UpdateHealthBar(unit)
                self:Show() -- Resize after adding lines
                -- Color name AFTER Show() — calling Show() can reset text colors
                ColorTooltipName(unit)
                -- Extend tooltip to fit health bar inside the border
                AdjustTooltipForHealthBar()
            end
        end)
        TooltipModule.hooks["SetUnit"] = true
    end

    -- Inspect data for hovered players (item level / powers). Ascension client
    -- fires the retail-named event; register both, only one will fire.
    if not TooltipModule.hooks["InspectReady"] then
        inspectEventFrame:RegisterEvent("INSPECT_READY")
        inspectEventFrame:RegisterEvent("INSPECT_TALENT_READY")
        inspectEventFrame:SetScript("OnEvent", function(self, event, ...)
            OnInspectReady(event, ...)
        end)
        TooltipModule.hooks["InspectReady"] = true
    end

    -- UnitFrame_UpdateTooltip recolors TextLeft1 with GameTooltip_UnitColor after SetUnit.
    if not TooltipModule.hooks["UnitFrameTooltip"] then
        hooksecurefunc("UnitFrame_UpdateTooltip", function(self)
            if not IsModuleEnabled() or not self or not self.unit then return end
            ColorTooltipName(self.unit)
        end)
        TooltipModule.hooks["UnitFrameTooltip"] = true
    end

    -- GameObject tooltips (e.g. BG doors) never call SetUnit, so OnTooltipSetUnit never fires for them — hook the bar's own OnShow instead.
    if not TooltipModule.hooks["BarShow"] then
        GameTooltipStatusBar:HookScript("OnShow", function(self)
            if not IsModuleEnabled() then return end
            StyleHealthBar()
            AdjustTooltipForHealthBar()
        end)
        TooltipModule.hooks["BarShow"] = true
    end

    -- Hook GameTooltipStatusBar OnValueChanged to persist class color through
    -- health updates (Blizzard resets the bar color on each value change)
    if not TooltipModule.hooks["BarValueChanged"] then
        GameTooltipStatusBar:HookScript("OnValueChanged", function(self)
            if not IsModuleEnabled() then return end
            if currentTooltipBarColor then
                local c = currentTooltipBarColor
                self:SetStatusBarColor(c[1], c[2], c[3])
            end
        end)
        TooltipModule.hooks["BarValueChanged"] = true
    end

    -- Hook OnTooltipCleared to reset state
    if not TooltipModule.hooks["OnCleared"] then
        GameTooltip:HookScript("OnTooltipCleared", function(self)
            if not IsModuleEnabled() then return end
            -- Reset border color
            self:SetBackdropBorderColor(1, 1, 1)
            -- Clear cached bar color so OnValueChanged stops overriding
            currentTooltipBarColor = nil
            -- Reset health bar color to default green
            if GameTooltipStatusBar then
                GameTooltipStatusBar:SetStatusBarColor(0.2, 0.8, 0.2)
            end
        end)
        TooltipModule.hooks["OnCleared"] = true
    end

    TooltipModule.applied = true
    TooltipModule.initialized = true
end

local function RestoreTooltipSystem()
    -- Hooks can't be removed, but they check IsModuleEnabled()
    -- Stop processing inspect events and drop any pending request
    inspectEventFrame:UnregisterAllEvents()
    pendingInspectGUID = nil
    pendingInspectUnit = nil
    -- Reset health bar color
    if GameTooltipStatusBar then
        GameTooltipStatusBar:SetStatusBarColor(0.2, 0.8, 0.2)
    end
    TooltipModule.applied = false
end

-- ============================================================================
-- PROFILE CHANGE HANDLER
-- ============================================================================

local function OnProfileChanged()
    EnsureTooltipAnchorHook()
    EnsureTooltipWidget()
    ApplyTooltipWidgetPosition()

    if IsModuleEnabled() then
        ApplyTooltipSystem()
    else
        if addon:ShouldDeferModuleDisable("tooltip", TooltipModule) then
            return
        end
        RestoreTooltipSystem()
    end
end

-- ============================================================================
-- ERROR GUARD: GameTooltipMods nil lineText fix
-- Blizzard's GameTooltipMods.lua can crash when a spell has incomplete
-- tooltip data (nil lineText from corrupt server data). Wrapping the
-- OnUpdate in pcall prevents these errors from killing the UI.
-- ============================================================================

local function InstallTooltipErrorGuard()
    if TooltipModule.guardInstalled then return end

    local origOnUpdate = GameTooltip:GetScript("OnUpdate")
    if origOnUpdate then
        GameTooltip:SetScript("OnUpdate", function(self, elapsed)
            local ok, err = pcall(origOnUpdate, self, elapsed)
            if not ok then
                -- Log to error frame without crashing the UI
                geterrorhandler()(err)
            end
        end)
        TooltipModule.guardInstalled = true
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "DragonUI" then
        -- Install error guard first — always active, even if module is disabled
        InstallTooltipErrorGuard()

        EnsureTooltipAnchorHook()
        EnsureTooltipWidget()
        ApplyTooltipWidgetPosition()

        if not IsModuleEnabled() then return end

        -- Register profile callbacks
        addon:After(0.5, function()
            if addon.db and addon.db.RegisterCallback then
                addon.db.RegisterCallback(TooltipModule, "OnProfileChanged", OnProfileChanged)
                addon.db.RegisterCallback(TooltipModule, "OnProfileCopied", OnProfileChanged)
                addon.db.RegisterCallback(TooltipModule, "OnProfileReset", OnProfileChanged)
            end
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Safety net: ensure guard is installed even if ADDON_LOADED was missed
        InstallTooltipErrorGuard()

        EnsureTooltipAnchorHook()
        EnsureTooltipWidget()
        ApplyTooltipWidgetPosition()

        if not IsModuleEnabled() then return end
        ApplyTooltipSystem()
    end
end)

-- Export for external use
addon.ApplyTooltipSystem = ApplyTooltipSystem
addon.RestoreTooltipSystem = RestoreTooltipSystem
