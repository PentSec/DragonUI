local addon = select(2, ...)
local NP = addon.Nameplates
local C = NP.const

-- Nameplates combo points widget.
-- Native Rogue/Druid combo points (GetComboPoints) plus Ascension custom-class
-- "stack" resources (Felsworm/Demonhunter Fellfury, Pyromancer Embers, Reaper
-- Souls, etc.) reusing the same widget on the target nameplate.

-- Per custom-class stack resource definition (mirror of Ascension's
-- ClassResources.lua / CoAResourceSegmentBar templates, but minimal: only the
-- atlas names + spell info we need to render segments on a nameplate).
--   spellID      : aura spell id to read stacks from (filter by MatchesSpellID).
--   source       : "buff" (AuraUtil.GetBuff "player") or "debuff" (GetDebuff).
--   maxStacks    : segment count (overrides per-class default if present).
--   emptyAtlas   : atlas name drawn for i > current stacks (segment "off").
--   fillAtlas    : atlas name drawn for i <= current stacks (segment "on").
--   segSize      : square edge length for each segment.
--   segSpacing   : horizontal gap between segments.
--   knownSpellID : optional; if set, segments only render when this spell is
--                  known (gates talents like Ranger 802036 or Prophet 4053).
--   Reaper extra states (optional; all or none):
--     shardSpellID : aura holding partial fill of the NEXT free soul slot.
--     shard1Atlas / shard2Atlas : atlas for 1 / 2+ shards on that slot.
--     infusedSpellID : aura active when every soul is full.
--     infusedAtlas   : fill recolor used while infused.
--   iconW/iconH  : optional host backing size (defaults derived from segSize).
local CLASS_STACKS = {
    DEMONHUNTER = { -- "Felsworm" in-game; native token is DEMONHUNTER.
        spellID    = 800058, -- Fellfury
        source     = "buff",
        emptyAtlas = "DemonHunterSegmentBg",
        fillAtlas  = "DemonHunterSegmentFill",
        segSize    = 16,
        segSpacing = 2,
    },
    REAPER = {
        spellID       = 500363, -- Soul shards (stacks); see Ascension_ReaperResource.lua.
        source        = "buff",
        maxStacks     = 3,
        emptyAtlas    = "ReaperSoulBG",
        fillAtlas     = "ReaperSoulFull",
        shardSpellID  = 805077, -- partial fill progress toward next soul.
        shard1Atlas   = "ReaperSoul1Shard",
        shard2Atlas   = "ReaperSoul2Shards",
        infusedSpellID = 803031, -- recolor once all souls are full.
        infusedAtlas  = "ReaperSoulInfused",
        segSize       = 32,
        segSpacing    = 2,
    },
    PYROMANCER = {
        spellID    = 807533, -- Embers (debuff on the player).
        source     = "debuff",
        emptyAtlas = "PyroEmber",
        fillAtlas  = "PyroEmberGlow",
        segSize    = 18,
        segSpacing = 2,
    },
    RANGER = {
        spellID      = 804329, -- Ranger combo points.
        source       = "buff",
        knownSpellID = 802036, -- only when the combo talent is known.
        emptyAtlas   = "RangerBarSegmentBg",
        fillAtlas    = "RangerBarSegmentFill",
        segSize      = 13,
        segSpacing   = 2,
    },
    PROPHET = { -- Venomancer kit on Prophet.
        spellID      = 804972,
        source       = "buff",
        knownSpellID = 4053, -- C_CharacterAdvancement.IsKnownID gating.
        emptyAtlas   = "VenomancerEmpty",
        fillAtlas    = "VenomancerFilled",
        segSize      = 16,
        segSpacing   = 2,
    },
    FLESHWARDEN = { -- Knight of Xoroth; FleshOrbs template.
        spellID    = 500906,
        source     = "buff",
        emptyAtlas = "KoXBarSegmentBg",
        fillAtlas  = "KoXBarSegmentFill",
        segSize    = 22,
        segSpacing = 2,
    },
}

local NATIVE_MAX = 5

-- Ascension-only API guards: the custom-class path must be inert on a vanilla
-- client. We resolve the symbols lazily and cache nil on first miss.
local _ascension_class_cache = {} -- ["<token>"] = token | false | nil-unknown-yet

local function IsAscensionClassPresent()
    if _ascension_class_cache.present ~= nil then
        return _ascension_class_cache.present
    end
    local ok = pcall(function()
        return _G.IsCustomClass and _G.IsCustomClass()
    end)
    _ascension_class_cache.present = (ok == true) and true or false
    return _ascension_class_cache.present
end

local function GetPlayerCustomClass()
    if not IsAscensionClassPresent() then return nil end
    local ok, token = pcall(function()
        return _G.C_Player and _G.C_Player.GetClass and _G.C_Player:GetClass()
    end)
    if not ok or type(token) ~= "string" or token == "" then return nil end
    return token
end

local function AuraStacks(spellID, source)
    local getter = (source == "debuff") and _G.AuraUtil and _G.AuraUtil.GetDebuff
        or _G.AuraUtil and _G.AuraUtil.GetBuff
    if not getter then return 0 end
    local ok, stacks = pcall(function()
        return select(4, getter("player", spellID, true, _G.AuraUtil.Predicate.MatchesSpellID))
    end)
    if not ok then return 0 end
    return tonumber(stacks) or 0
end

local function IsSpellKnown(spellID)
    if not spellID then return true end
    if _G.IsSpellIDKnown then
        local ok, known = pcall(_G.IsSpellIDKnown, spellID)
        if ok then return known and true or false end
    end
    if _G.C_CharacterAdvancement and _G.C_CharacterAdvancement.IsKnownID then
        local ok, known = pcall(_G.C_CharacterAdvancement.IsKnownID, spellID)
        if ok then return known and true or false end
    end
    return true
end

local function GetSpellMaxStacks(spellID, fallback)
    if _G.GetSpellMaxStack then
        local ok, n = pcall(_G.GetSpellMaxStack, spellID)
        if ok and tonumber(n) then return tonumber(n) end
    end
    return fallback
end

-- Resolve which combo provider is active for the player right now.
-- Returns:
--   "native",  5, currentStacks   -- Rogue/Druid combo points (or 0 native)
--   "class",   maxStacks, cur     -- Ascension custom-class resource
--   "none",    0, 0
local function ResolveComboProvider()
    if UnitExists("target") then
        local ok, n = pcall(_G.GetComboPoints, "player")
        if ok then
            local pts = tonumber(n) or 0
            if pts > 0 then
                return "native", NATIVE_MAX, pts
            end
        end
    end
    local token = GetPlayerCustomClass()
    if not token then return "none", 0, 0 end
    local entry = CLASS_STACKS[token]
    if not entry then return "none", 0, 0 end
    if entry.knownSpellID and not IsSpellKnown(entry.knownSpellID) then
        return "none", 0, 0
    end
    local maxStacks = GetSpellMaxStacks(entry.spellID, nil) or entry.maxStacks
    if not maxStacks or maxStacks <= 0 then maxStacks = entry.maxStacks or NATIVE_MAX end
    if not maxStacks or maxStacks <= 0 then return "none", 0, 0 end
    local cur = AuraStacks(entry.spellID, entry.source)
    return "class", maxStacks, cur
end

-- Cheap cached check: is the player an Ascension custom class with a stack
-- resource entry? Used to gate UNIT_AURA-driven combo refreshes on vanilla
-- clients / classes without a custom resource (avoids per-aura work).
function NP.widgets.HasCustomClassCombo()
    local token = GetPlayerCustomClass()
    if not token then return false end
    return CLASS_STACKS[token] ~= nil
end

function NP.widgets.GetPlayerComboPoints()
    local kind, _max, cur = ResolveComboProvider()
    return (kind == "none") and 0 or (tonumber(cur) or 0)
end

-- Returns the provider kind ("native" | "class" | "none") plus the active
-- class entry's segment atlas info when kind == "class"; nil otherwise.
local function GetComboRender()
    local kind, maxStacks, cur = ResolveComboProvider()
    if kind == "none" then return "none", 0, 0, nil end
    if kind == "native" then
        return "native", NATIVE_MAX, cur, nil
    end
    local token = GetPlayerCustomClass()
    return "class", maxStacks, cur, CLASS_STACKS[token]
end

function NP.widgets.UpdateComboTargetPlate()
    if not UnitExists("target") then
        NP.module.comboTargetPlate = nil
        return
    end
    -- Keyed by target GUID; GetTargetPlate() caches UpdateTargetContext's scan.
    local plate = NP.identity.GetTargetPlate()
    if not plate then
        local targetGUID = UnitGUID("target")
        if targetGUID then
            plate = NP.state.GUIDToPlate[targetGUID]
        end
    end
    NP.module.comboTargetPlate = plate
end

function NP.widgets.IsPlateComboTarget(plateData)
    if not plateData or not UnitExists("target") then
        return false
    end
    if NP.identity.PlateHasUniqueUnitMatch(plateData, "target") then
        return true
    end
    local targetGUID = UnitGUID("target")
    if targetGUID then
        local plateGUID = NP.state.GetPlateGUID(plateData)
        if plateGUID and plateGUID == targetGUID then
            return true
        end
    end
    return NP.module.comboTargetPlate ~= nil
        and plateData == NP.module.comboTargetPlate
end

-- Host + N segment textures created lazily. We keep the historical _comboHost
-- name (engine.lua inspects it) but the host now owns a pool of segment frames
-- rather than a single textured icon. For the native path the original single
-- `combo-<points>` icon is preserved via host.icon.
function NP.widgets.EnsureComboWidget(plateData)
    if plateData._comboHost then return plateData._comboHost end
    local plate = plateData.plate
    if not plate then return nil end
    local host = CreateFrame("Frame", nil, plate)
    host:SetSize(C.COMBO_ICON_W or 64, C.COMBO_ICON_H or 32)
    host:Hide()
    host.segments = {}
    plateData._comboHost = host
    -- Native-path icon: single texture covering the host (original behavior).
    -- Segmented class resources use host.segments instead; icon stays hidden.
    local icon = host:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints(host)
    icon:Hide()
    host.icon = icon
    plateData._depthDirty = true
    return host
end

local function AcquireSegment(host, i)
    local seg = host.segments[i]
    if seg then return seg end
    seg = CreateFrame("Frame", nil, host)
    local bg = seg:CreateTexture(nil, "ARTWORK")
    bg:SetAllPoints(seg)
    seg.bg = bg
    host.segments[i] = seg
    return seg
end

local function ApplySegmentAtlas(seg, atlasName)
    if not seg or not atlasName then return end
    -- SetAtlas falls back gracefully on vanilla; if AtlasUtil is present we
    -- probe to avoid SetAtlas log noise for unknown names.
    if _G.AtlasUtil and _G.AtlasUtil.AtlasExists and not _G.AtlasUtil:AtlasExists(atlasName) then
        seg.bg:SetTexture(0, 0, 0, 0)
        return
    end
    seg.bg:SetAtlas(atlasName, true)
end

-- Lay out the widget. Native combo keeps the original single 64x32 icon;
-- custom-class resources lay out N square segments centered on the host.
function NP.widgets.LayoutComboWidget(plateData)
    local host = plateData._comboHost
    local hp = plateData.minaHp
    local plate = plateData.plate
    if not host or not hp or not plate then return false end
    local kind, maxStacks, _cur, entry = GetComboRender()
    if kind == "none" then return false end

    if kind == "native" then
        host:SetSize(C.COMBO_ICON_W or 64, C.COMBO_ICON_H or 32)
        host:ClearAllPoints()
        host:SetPoint("BOTTOM", hp, "TOP", 0, 3)
        return true
    end

    local segSize = (entry and entry.segSize) or 16
    local spacing = (entry and entry.segSpacing) or 2
    -- Ensure the right N segments exist; refresh geometry.
    local count = tonumber(maxStacks) or NATIVE_MAX
    local totalW = count * segSize + math.max(0, count - 1) * spacing
    host:SetSize(totalW, segSize)

    for i = 1, count do
        local seg = AcquireSegment(host, i)
        seg:SetSize(segSize, segSize)
        seg:ClearAllPoints()
        local xOffset = (i - 1) * (segSize + spacing) - (totalW - segSize) / 2
        seg:SetPoint("CENTER", host, "CENTER", xOffset, 0)
    end
    -- Trim leftover segments if max shrank.
    for i = count + 1, #host.segments do
        host.segments[i]:Hide()
    end

    host:ClearAllPoints()
    host:SetPoint("BOTTOM", hp, "TOP", 0, C.COMBO_CLASS_OFFSET_Y or 6)
    return true
end

function NP.widgets.SyncComboPoints(plateData)
    local cfg = NP.config.GetCfg()
    local host = plateData._comboHost
    if cfg.showComboPoints == false then
        if host then host:Hide() end
        if NP.widgets and NP.widgets.ReflowTopOverlays then
            NP.widgets.ReflowTopOverlays(plateData)
        end
        return
    end
    if not NP.widgets.IsPlateComboTarget(plateData) then
        if host then host:Hide() end
        if NP.widgets and NP.widgets.ReflowTopOverlays then
            NP.widgets.ReflowTopOverlays(plateData)
        end
        return
    end

    local kind, maxStacks, cur, entry = GetComboRender()

    -- Reaper-style extra state, resolved up front: a shard-only fill (0 souls
    -- but shards > 0) must still render, and the infused recolor triggers once
    -- every soul is full (cur >= maxStacks) or the infused aura is present.
    local shards = 0
    local infused = false
    if kind == "class" and entry then
        if entry.shardSpellID then
            shards = AuraStacks(entry.shardSpellID, entry.source)
        end
        if entry.infusedSpellID then
            infused = AuraStacks(entry.infusedSpellID, entry.source) > 0
        end
        if not infused and entry.infusedAtlas and maxStacks > 0 and cur >= maxStacks then
            infused = true
        end
    end

    if kind == "none" or maxStacks <= 0 or (cur <= 0 and shards <= 0) then
        if host then host:Hide() end
        if NP.widgets and NP.widgets.ReflowTopOverlays then
            NP.widgets.ReflowTopOverlays(plateData)
        end
        return
    end
    local count = maxStacks

    host = NP.widgets.EnsureComboWidget(plateData)
    if not host or not NP.widgets.LayoutComboWidget(plateData) then
        if host then host:Hide() end
        return
    end

    local pts = math.min(cur, count)
    if kind == "native" then
        -- Original behavior: a single combo-<points> icon already draws the
        -- 1..5 pips; do NOT split into per-pip segments.
        host.icon:SetTexture(C.COMBO_TEX .. pts)
        host.icon:SetVertexColor(1, 1, 1, 1)
        host.icon:Show()
        for _, seg in ipairs(host.segments) do
            seg:Hide()
        end
    else
        host.icon:Hide()
        for i = 1, count do
            local seg = host.segments[i]
            if seg then
                seg.bg:SetVertexColor(1, 1, 1, 1)
                if i <= pts then
                    -- Filled soul: ReaperSoulFull, or ReaperSoulInfused once all full.
                    if infused and entry.infusedAtlas then
                        ApplySegmentAtlas(seg, entry.infusedAtlas)
                    else
                        ApplySegmentAtlas(seg, entry.fillAtlas)
                    end
                elseif i == pts + 1 and shards > 0 and entry.shard1Atlas then
                    -- Next free slot shows the partial fill: 1 or 2 shards.
                    if shards >= 2 and entry.shard2Atlas then
                        ApplySegmentAtlas(seg, entry.shard2Atlas)
                    else
                        ApplySegmentAtlas(seg, entry.shard1Atlas)
                    end
                else
                    ApplySegmentAtlas(seg, entry.emptyAtlas)
                end
                seg:Show()
            end
        end
    end

    host:Show()
    if NP.widgets and NP.widgets.ReflowTopOverlays then
        NP.widgets.ReflowTopOverlays(plateData)
    end
end

function NP.widgets.RefreshAllComboPoints()
    NP.widgets.UpdateComboTargetPlate()
    local targetPlate = NP.module.comboTargetPlate
    for _, plateData in pairs(NP.module.plates) do
        if plateData ~= targetPlate then
            local host = plateData._comboHost
            if host then host:Hide() end
        else
            NP.widgets.SyncComboPoints(plateData)
        end
    end
end

NP.widgets.Register("Combo", {
    Ensure = function(plateData)
        return NP.widgets.EnsureComboWidget(plateData) ~= nil
    end,
    Layout = function(plateData)
        return NP.widgets.LayoutComboWidget(plateData)
    end,
    Sync = function(plateData)
        NP.widgets.SyncComboPoints(plateData)
    end,
    Hide = function(plateData)
        local host = plateData and plateData._comboHost
        if host then
            host:Hide()
        end
    end,
})
