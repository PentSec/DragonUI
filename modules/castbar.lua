local addon = select(2, ...)

-- CASTBAR MODULE FOR DRAGONUI
-- Original code by Neticsoul
-- ============================================================================
-- CASTBAR MODULE - OPTIMIZED FOR WOW 3.3.5A
-- ============================================================================

local _G = _G
local pairs, ipairs = pairs, ipairs
local min, max, abs, floor, ceil = math.min, math.max, math.abs, math.floor, math.ceil
local format, gsub = string.format, string.gsub
local GetTime = GetTime
local UnitExists, UnitGUID = UnitExists, UnitGUID
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local UnitAura, GetSpellTexture, GetSpellInfo = UnitAura, GetSpellTexture, GetSpellInfo

-- ============================================================================
-- MODULE CONSTANTS
-- ============================================================================

local TEXTURE_PATH = "Interface\\AddOns\\DragonUI\\Textures\\CastbarOriginal\\"
local TEXTURES = {
    atlas = TEXTURE_PATH .. "uicastingbar2x",
    atlasSmall = TEXTURE_PATH .. "uicastingbar",
    standard = TEXTURE_PATH .. "CastingBarStandard2",
    channel = TEXTURE_PATH .. "CastingBarChannel",
    interrupted = TEXTURE_PATH .. "CastingBarInterrupted2",
    spark = TEXTURE_PATH .. "CastingBarSpark"
}

local UV_COORDS = {
    background = {0.0009765625, 0.4130859375, 0.3671875, 0.41796875},
    border = {0.412109375, 0.828125, 0.001953125, 0.060546875},
    flash = {0.0009765625, 0.4169921875, 0.2421875, 0.30078125},
    spark = {0.076171875, 0.0859375, 0.796875, 0.9140625},
    borderShield = {0.000976562, 0.0742188, 0.796875, 0.970703},
    textBorder = {0.001953125, 0.412109375, 0.00390625, 0.11328125}
}

local CHANNEL_TICKS = {
    -- Warlock
    ["Drain Soul"] = 5,
    ["Drain Life"] = 5,
    ["Drain Mana"] = 5,
    ["Rain of Fire"] = 4,
    ["Hellfire"] = 15,
    ["Ritual of Summoning"] = 5,
    -- Priest
    ["Mind Flay"] = 3,
    ["Mind Control"] = 8,
    ["Penance"] = 2,
    -- Mage
    ["Blizzard"] = 8,
    ["Evocation"] = 4,
    ["Arcane Missiles"] = 5,
    -- Druid/Others
    ["Tranquility"] = 4,
    ["Hurricane"] = 10,
    ["First Aid"] = 8
}

local MAX_TICKS = 15

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local CastbarModule = {
    states = {},
    frames = {},
    lastRefreshTime = {},
    auraCache = {
        target = {
            lastUpdate = 0,
            lastRows = 0,
            lastOffset = 0,
            lastGUID = nil
        },
        focus = {
            lastUpdate = 0,
            lastRows = 0,
            lastOffset = 0,
            lastGUID = nil
        }
    }
}

-- Initialize states for each castbar type
for _, unitType in ipairs({"player", "target", "focus"}) do
    CastbarModule.states[unitType] = {
        casting = false,
        isChanneling = false,
        currentValue = 0,
        maxValue = 0,
        spellName = "",
        holdTime = 0,
        castSucceeded = false,
        unitGUID = nil,
        endTime = 0,
        startTime = 0
    }
    CastbarModule.frames[unitType] = {}
    CastbarModule.lastRefreshTime[unitType] = 0
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function GetConfig(unitType)
    local cfg = addon.db and addon.db.profile and addon.db.profile.castbar
    if not cfg then
        return nil
    end

    if unitType == "player" then
        return cfg
    end

    return cfg[unitType]
end

local function IsEnabled(unitType)
    local cfg = GetConfig(unitType)
    return cfg and cfg.enabled
end

local function GetSpellIcon(spellName, texture)
    if texture and texture ~= "" then
        return texture
    end

    if spellName then
        local icon = GetSpellTexture(spellName)
        if icon then
            return icon
        end

        -- Search in spellbook
        for i = 1, 1024 do
            local name, _, icon = GetSpellInfo(i, BOOKTYPE_SPELL)
            if not name then
                break
            end
            if name == spellName and icon then
                return icon
            end
        end
    end

    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ParseCastTimes(startTime, endTime)
    local start = (startTime or 0) / 1000
    local finish = (endTime or 0) / 1000
    local duration = finish - start

    -- Sanity check for duration
    if duration > 3600 or duration < 0 then
        duration = 3.0
    end

    return start, finish, duration
end

-- ============================================================================
-- TEXTURE AND LAYER MANAGEMENT
-- ============================================================================

local function ForceStatusBarLayer(statusBar)
    if not statusBar then
        return
    end

    -- ✅ SOLO configurar UNA VEZ, no en cada frame
    local texture = statusBar:GetStatusBarTexture()
    if texture and texture.SetDrawLayer and not statusBar._layerForced then
        texture:SetDrawLayer('BORDER', 0)
        statusBar._layerForced = true -- Marcar como configurado
    end
end

local function SetupVertexColor(statusBar)
    if not statusBar or not statusBar.SetStatusBarColor then
        return
    end

    if not statusBar._originalSetStatusBarColor then
        statusBar._originalSetStatusBarColor = statusBar.SetStatusBarColor
        statusBar.SetStatusBarColor = function(self, r, g, b, a)
            self:_originalSetStatusBarColor(r, g, b, a or 1)
            local texture = self:GetStatusBarTexture()
            if texture then
                texture:SetVertexColor(1, 1, 1, 1)
            end
        end
    end
end

local function CreateTextureClipping(statusBar)
    statusBar.UpdateTextureClipping = function(self, progress, isChanneling)
        local texture = self:GetStatusBarTexture()
        if not texture then
            return
        end

        if isChanneling then
            -- ✅ CHANNELING: Ocultar desde la derecha
            local clampedProgress = math.max(0.01, math.min(0.99, progress))
            texture:ClearAllPoints()
            texture:SetAllPoints(self)
            texture:SetTexCoord(0, clampedProgress, 0, 1)
        else
            -- ✅ CASTING: Normal
            local clampedProgress = math.max(0.01, math.min(0.99, progress))
            texture:SetTexCoord(0, clampedProgress, 0, 1)
            texture:ClearAllPoints()
            texture:SetAllPoints(self)
        end
    end
end
-- ============================================================================
-- BLIZZARD CASTBAR MANAGEMENT
-- ============================================================================

local function HideBlizzardCastbar(unitType)
    local frames = {
        player = CastingBarFrame,
        target = TargetFrameSpellBar,
        focus = FocusFrameSpellBar
    }

    local frame = frames[unitType]
    if not frame then
        return
    end

    --  More aggressive hiding to prevent interference
    frame:Hide()
    frame:SetAlpha(0)

    if unitType == "target" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, -5000)
        frame:SetSize(1, 1) -- Minimize size

        --  Disable Blizzard's own show/hide logic
        if frame.SetScript then
            frame:SetScript("OnShow", function(self)
                self:Hide()
            end)
        end
    else
        if frame.SetScript then
            frame:SetScript("OnShow", function(self)
                self:Hide()
            end)
        end
    end
end

local function ShowBlizzardCastbar(unitType)
    local frames = {
        player = CastingBarFrame,
        target = TargetFrameSpellBar,
        focus = FocusFrameSpellBar
    }

    local frame = frames[unitType]
    if not frame then
        return
    end

    frame:SetAlpha(1)
    if frame.SetScript then
        frame:SetScript("OnShow", nil)
    end

    if unitType == "target" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", TargetFrame, "BOTTOMLEFT", 25, -5)
    end
end

-- ============================================================================
-- CHANNEL TICKS SYSTEM
-- ============================================================================

local function CreateChannelTicks(parent, ticksTable)
    for i = 1, MAX_TICKS do
        local tick = parent:CreateTexture('Tick' .. i, 'ARTWORK', nil, 1)
        tick:SetTexture('Interface\\ChatFrame\\ChatFrameBackground')
        tick:SetVertexColor(0, 0, 0, 0.75)
        tick:SetSize(3, max(parent:GetHeight() - 2, 10))
        tick:Hide()
        ticksTable[i] = tick
    end
end

local function UpdateChannelTicks(parent, ticksTable, spellName)
    -- Hide all ticks first
    for i = 1, MAX_TICKS do
        if ticksTable[i] then
            ticksTable[i]:Hide()
        end
    end

    local tickCount = CHANNEL_TICKS[spellName]

    if not tickCount or tickCount <= 1 then
        return
    end

    local width = parent:GetWidth()
    local height = parent:GetHeight()
    local tickDelta = width / tickCount

    for i = 1, min(tickCount - 1, MAX_TICKS) do
        if ticksTable[i] then
            ticksTable[i]:SetSize(3, max(height - 2, 10))
            ticksTable[i]:ClearAllPoints()
            ticksTable[i]:SetPoint('CENTER', parent, 'LEFT', i * tickDelta, 0)
            ticksTable[i]:Show()
        end
    end
end

local function HideAllTicks(ticksTable)
    for i = 1, MAX_TICKS do
        if ticksTable[i] then
            ticksTable[i]:Hide()
        end
    end
end

-- ============================================================================
-- SHIELD SYSTEM
-- ============================================================================

local function CreateShield(parent, icon, frameName, iconSize)
    if not parent or not icon then
        return nil
    end

    local shield = CreateFrame("Frame", frameName .. "Shield", parent)
    shield:SetFrameLevel(parent:GetFrameLevel() - 1)
    shield:SetSize(iconSize * 1.8, iconSize * 2.0)

    local texture = shield:CreateTexture(nil, "ARTWORK", nil, 3)
    texture:SetAllPoints(shield)
    texture:SetTexture(TEXTURES.atlas)
    texture:SetTexCoord(unpack(UV_COORDS.borderShield))
    texture:SetVertexColor(1, 1, 1, 1)

    shield:ClearAllPoints()
    shield:SetPoint("CENTER", icon, "CENTER", 0, -4)
    shield:Hide()

    return shield
end

-- ============================================================================
-- AURA OFFSET SYSTEM
-- ============================================================================

local function GetTargetAuraOffset()
    local cfg = GetConfig("target")
    if not cfg or not cfg.autoAdjust then
        return 0
    end

    -- CORREGIDO: Usar el mismo método manual que focus para consistencia
    local buffCount = 0
    local debuffCount = 0

    -- Count buffs
    for i = 1, 40 do
        if UnitBuff("target", i) then
            buffCount = buffCount + 1
        else
            break
        end
    end

    -- Count debuffs
    for i = 1, 40 do
        if UnitDebuff("target", i) then
            debuffCount = debuffCount + 1
        else
            break
        end
    end

    if buffCount == 0 and debuffCount == 0 then
        return 0
    end

    -- USAR EXACTAMENTE LOS MISMOS VALORES QUE FOCUS
    local AURAS_PER_ROW = 6 -- Mismos valores para ambos
    local BUFF_ROW_HEIGHT = 10
    local DEBUFF_ROW_HEIGHT = 24

    local totalOffset = 0

    -- Contar filas de buffs (solo filas adicionales)
    if buffCount > 0 then
        local buffRows = math.ceil(buffCount / AURAS_PER_ROW)
        if buffRows > 1 then
            totalOffset = totalOffset + ((buffRows - 1) * BUFF_ROW_HEIGHT)
        end
    end

    -- Siempre sumar debuffs si existen
    if debuffCount > 0 then
        totalOffset = totalOffset + DEBUFF_ROW_HEIGHT
    end

    return totalOffset
end

local function ApplyTargetAuraOffset()
    local frames = CastbarModule.frames.target
    if not frames.castbar or not frames.castbar:IsVisible() then
        return
    end

    local cfg = GetConfig("target")
    if not cfg or not cfg.enabled or not cfg.autoAdjust then
        return
    end

    local offset = GetTargetAuraOffset()
    local anchorFrame = _G[cfg.anchorFrame] or TargetFrame or UIParent

    frames.castbar:ClearAllPoints()
    frames.castbar:SetPoint(cfg.anchor, anchorFrame, cfg.anchorParent, cfg.x_position, cfg.y_position - offset)
end

-- ============================================================================
-- FOCUS AURA OFFSET SYSTEM (Custom implementation since WoW doesn't have one)
-- ============================================================================

local function CountFocusAuras()
    if not UnitExists("focus") then
        return 0, 0
    end

    local buffCount = 0
    local debuffCount = 0

    -- Count buffs
    local index = 1
    while true do
        local name = UnitAura("focus", index, "HELPFUL")
        if not name then
            break
        end
        buffCount = buffCount + 1
        index = index + 1
        if index > 40 then
            break
        end
    end

    -- Count debuffs
    index = 1
    while true do
        local name = UnitAura("focus", index, "HARMFUL")
        if not name then
            break
        end
        debuffCount = debuffCount + 1
        index = index + 1
        if index > 40 then
            break
        end
    end

    return buffCount, debuffCount
end

local function GetFocusAuraOffset()
    local cfg = GetConfig("focus")
    if not cfg or not cfg.autoAdjust then
        return 0
    end

    local buffCount, debuffCount = CountFocusAuras()

    if buffCount == 0 and debuffCount == 0 then
        return 0
    end

    local AURAS_PER_ROW = 6 -- Tanto target como focus usan 6 auras por fila
    local BUFF_ROW_HEIGHT = 10 -- Cada fila de buffs = 18px
    local DEBUFF_ROW_HEIGHT = 24 -- Cada fila de debuffs = 24px (más grande)

    -- Calcular offset total
    local totalOffset = 0

    -- Contar filas de buffs
    if buffCount > 0 then
        local buffRows = math.ceil(buffCount / AURAS_PER_ROW)
        if buffRows > 1 then
            totalOffset = totalOffset + ((buffRows - 1) * BUFF_ROW_HEIGHT)
        end
    end

    -- Si hay debuffs, añadir offset de debuffs (más grande)
    if debuffCount > 0 then
        totalOffset = totalOffset + DEBUFF_ROW_HEIGHT
    end

    return totalOffset
end

local function ApplyFocusAuraOffset()
    local frames = CastbarModule.frames.focus
    if not frames.castbar or not frames.castbar:IsVisible() then
        return
    end

    local cfg = GetConfig("focus")
    if not cfg or not cfg.enabled or not cfg.autoAdjust then
        return
    end

    local offset = GetFocusAuraOffset()
    local anchorFrame = _G[cfg.anchorFrame] or FocusFrame or UIParent

    frames.castbar:ClearAllPoints()
    frames.castbar:SetPoint(cfg.anchor, anchorFrame, cfg.anchorParent, cfg.x_position, cfg.y_position - offset)
end

-- Debug function to test focus aura system
local function DebugFocusAuras()
    if not UnitExists("focus") then
        return
    end

    local buffCount, debuffCount = CountFocusAuras()
    local offset = GetFocusAuraOffset()

    -- Calculate layout details
    local AURAS_PER_ROW = 8
    local buffRows = buffCount > 0 and math.ceil(buffCount / AURAS_PER_ROW) or 0
    local debuffRows = debuffCount > 0 and math.ceil(debuffCount / AURAS_PER_ROW) or 0
    local separationRows = (buffCount > 0 and debuffCount > 0) and 1 or 0
    local totalRows = buffRows + separationRows + debuffRows

    -- Method 1: UnitAura with filters
    local buffCount1, debuffCount1 = 0, 0
    for i = 1, 40 do
        if UnitAura("focus", i, "HELPFUL") then
            buffCount1 = buffCount1 + 1
        end
        if UnitAura("focus", i, "HARMFUL") then
            debuffCount1 = debuffCount1 + 1
        end
    end

    -- Method 2: UnitBuff/UnitDebuff
    local buffCount2, debuffCount2 = 0, 0
    for i = 1, 40 do
        if UnitBuff("focus", i) then
            buffCount2 = buffCount2 + 1
        end
        if UnitDebuff("focus", i) then
            debuffCount2 = debuffCount2 + 1
        end
    end

    -- List actual auras found

    for i = 1, 40 do
        local name = UnitAura("focus", i, "HELPFUL")
        if name then
        else
            break
        end
    end

    for i = 1, 40 do
        local name = UnitAura("focus", i, "HARMFUL")
        if name then
        else
            break
        end
    end
end

-- Register debug command
SLASH_DRAGONUI_FOCUSAURAS1 = "/duifocusauras"
SlashCmdList["DRAGONUI_FOCUSAURAS"] = DebugFocusAuras

-- ============================================================================
-- TEXT MANAGEMENT
-- ============================================================================

local function SetTextMode(unitType, mode)
    local frames = CastbarModule.frames[unitType]
    if not frames then
        return
    end

    local elements = {frames.castText, frames.castTextCompact, frames.castTextCentered, frames.castTimeText,
                      frames.castTimeTextCompact}

    -- Hide all text elements first
    for _, element in ipairs(elements) do
        if element then
            element:Hide()
        end
    end

    -- Show appropriate elements based on mode
    if mode == "simple" then
        if frames.castTextCentered then
            frames.castTextCentered:Show()
        end
    else
        local cfg = GetConfig(unitType)
        local isCompact = cfg and cfg.compactLayout

        if isCompact then
            if frames.castTextCompact then
                frames.castTextCompact:Show()
            end
            if frames.castTimeTextCompact then
                frames.castTimeTextCompact:Show()
            end
        else
            if frames.castText then
                frames.castText:Show()
            end
            if frames.castTimeText then
                frames.castTimeText:Show()
            end
        end
    end
end

local function SetCastText(unitType, text)
    local cfg = GetConfig(unitType)
    if not cfg then
        return
    end

    local textMode = cfg.text_mode or "simple"
    SetTextMode(unitType, textMode)

    local frames = CastbarModule.frames[unitType]
    if not frames then
        return
    end

    if textMode == "simple" then
        if frames.castTextCentered then
            frames.castTextCentered:SetText(text)
        end
    else
        if frames.castText then
            frames.castText:SetText(text)
        end
        if frames.castTextCompact then
            frames.castTextCompact:SetText(text)
        end
    end
end
local function UpdateTimeText(unitType)
    local frames = CastbarModule.frames[unitType]
    local state = CastbarModule.states[unitType]

    if unitType == "player" then
        if not frames.timeValue and not frames.timeMax then
            return
        end
    else
        if not frames.castTimeText and not frames.castTimeTextCompact then
            return
        end
    end

    local cfg = GetConfig(unitType)
    if not cfg then
        return
    end

    local seconds = 0
    local secondsMax = state.maxValue or 0

    if state.casting or state.isChanneling then
        if state.casting then
            -- CASTING: Mostrar tiempo restante (cuenta atrás)
            seconds = max(0, state.maxValue - state.currentValue)
        else
            -- ✅ CHANNELING: Mostrar tiempo restante directo (ya decrece)
            seconds = max(0, state.currentValue)
        end
    end

    local timeText = format('%.' .. (cfg.precision_time or 1) .. 'f', seconds)
    local fullText

    if cfg.precision_max and cfg.precision_max > 0 then
        local maxText = format('%.' .. cfg.precision_max .. 'f', secondsMax)
        fullText = timeText .. ' / ' .. maxText
    else
        fullText = timeText .. 's'
    end

    if unitType == "player" then
        local textMode = cfg.text_mode or "simple"
        if textMode ~= "simple" and frames.timeValue and frames.timeMax then
            frames.timeValue:SetText(timeText)
            frames.timeMax:SetText(' / ' .. format('%.' .. (cfg.precision_max or 1) .. 'f', secondsMax))
        end
    else
        if frames.castTimeText then
            frames.castTimeText:SetText(fullText)
        end
        if frames.castTimeTextCompact then
            frames.castTimeTextCompact:SetText(fullText)
        end
    end
end

-- ============================================================================
-- CASTBAR CREATION
-- ============================================================================

local function CreateTextElements(parent, unitType)
    local fontSize = unitType == "player" and 'GameFontHighlight' or 'GameFontHighlightSmall'
    local elements = {}

    -- Main cast text
    elements.castText = parent:CreateFontString(nil, 'OVERLAY', fontSize)
    elements.castText:SetPoint('BOTTOMLEFT', parent, 'BOTTOMLEFT', unitType == "player" and 8 or 6, 2)
    elements.castText:SetJustifyH("LEFT")

    -- Compact cast text
    elements.castTextCompact = parent:CreateFontString(nil, 'OVERLAY', fontSize)
    elements.castTextCompact:SetPoint('BOTTOMLEFT', parent, 'BOTTOMLEFT', unitType == "player" and 8 or 6, 2)
    elements.castTextCompact:SetJustifyH("LEFT")
    elements.castTextCompact:Hide()

    -- Centered text for simple mode
    elements.castTextCentered = parent:CreateFontString(nil, 'OVERLAY', fontSize)
    elements.castTextCentered:SetPoint('BOTTOM', parent, 'BOTTOM', 0, 1)
    elements.castTextCentered:SetPoint('LEFT', parent, 'LEFT', unitType == "player" and 8 or 6, 0)
    elements.castTextCentered:SetPoint('RIGHT', parent, 'RIGHT', unitType == "player" and -8 or -6, 0)
    elements.castTextCentered:SetJustifyH("CENTER")
    elements.castTextCentered:Hide()

    -- Time text
    elements.castTimeText = parent:CreateFontString(nil, 'OVERLAY', fontSize)
    elements.castTimeText:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', unitType == "player" and -8 or -6, 2)
    elements.castTimeText:SetJustifyH("RIGHT")

    -- Compact time text
    elements.castTimeTextCompact = parent:CreateFontString(nil, 'OVERLAY', fontSize)
    elements.castTimeTextCompact:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', unitType == "player" and -8 or -6, 2)
    elements.castTimeTextCompact:SetJustifyH("RIGHT")
    elements.castTimeTextCompact:Hide()

    -- Player-specific time elements
    if unitType == "player" then
        elements.timeValue = parent:CreateFontString(nil, 'OVERLAY', fontSize)
        elements.timeValue:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', -50, 2)
        elements.timeValue:SetJustifyH("RIGHT")

        elements.timeMax = parent:CreateFontString(nil, 'OVERLAY', fontSize)
        elements.timeMax:SetPoint('LEFT', elements.timeValue, 'RIGHT', 2, 0)
        elements.timeMax:SetJustifyH("LEFT")
    end

    return elements
end
local function CreateCastbar(unitType)
    if CastbarModule.frames[unitType].castbar then
        return
    end

    local frameName = 'DragonUI' .. unitType:sub(1, 1):upper() .. unitType:sub(2) .. 'Castbar'
    local frames = CastbarModule.frames[unitType]

    -- Main StatusBar
    frames.castbar = CreateFrame('StatusBar', frameName, UIParent)
    frames.castbar:SetFrameStrata("MEDIUM")
    frames.castbar:SetFrameLevel(10)
    frames.castbar:SetMinMaxValues(0, 1)
    frames.castbar:SetValue(0)
    frames.castbar:Hide()

    -- Background
    local bg = frames.castbar:CreateTexture(nil, 'BACKGROUND')
    bg:SetTexture(TEXTURES.atlas)
    bg:SetTexCoord(unpack(UV_COORDS.background))
    bg:SetAllPoints()

    -- StatusBar texture
    frames.castbar:SetStatusBarTexture(TEXTURES.standard)
    frames.castbar:SetStatusBarColor(1, 0.7, 0, 1)

    -- Border
    local border = frames.castbar:CreateTexture(nil, 'ARTWORK', nil, 0)
    border:SetTexture(TEXTURES.atlas)
    border:SetTexCoord(unpack(UV_COORDS.border))
    border:SetPoint("TOPLEFT", frames.castbar, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", frames.castbar, "BOTTOMRIGHT", 2, -2)

    -- Channel ticks
    frames.ticks = {}
    CreateChannelTicks(frames.castbar, frames.ticks)

    -- Flash
    frames.flash = frames.castbar:CreateTexture(nil, 'OVERLAY')
    frames.flash:SetTexture(TEXTURES.atlas)
    frames.flash:SetTexCoord(unpack(UV_COORDS.flash))
    frames.flash:SetBlendMode('ADD')
    frames.flash:SetAllPoints()
    frames.flash:Hide()

    -- Icon y otros elementos...
    frames.icon = frames.castbar:CreateTexture(frameName .. "Icon", 'ARTWORK')
    frames.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frames.icon:Hide()

    -- Icon border
    local iconBorder = frames.castbar:CreateTexture(nil, 'ARTWORK')
    iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    iconBorder:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    iconBorder:SetVertexColor(0.8, 0.8, 0.8, 1)
    iconBorder:Hide()
    frames.icon.Border = iconBorder

    -- Shield (for target/focus)
    if unitType ~= "player" then
        frames.shield = CreateShield(frames.castbar, frames.icon, frameName, 20)
    end

    -- ✅ APLICAR SOLO TEXTURE CLIPPING SIMPLE
    CreateTextureClipping(frames.castbar)

    -- Text background frame y elementos de texto...
    frames.textBackground = CreateFrame('Frame', frameName .. 'TextBG', UIParent)
    frames.textBackground:SetFrameStrata("MEDIUM")
    frames.textBackground:SetFrameLevel(9)
    frames.textBackground:Hide()

    local textBg = frames.textBackground:CreateTexture(nil, 'BACKGROUND')
    if unitType == "player" then
        textBg:SetTexture(TEXTURES.atlas)
        textBg:SetTexCoord(0.001953125, 0.410109375, 0.00390625, 0.11328125)
    else
        textBg:SetTexture(TEXTURES.atlasSmall)
        textBg:SetTexCoord(unpack(UV_COORDS.textBorder))
    end
    textBg:SetAllPoints()

    -- Create text elements
    local textElements = CreateTextElements(frames.textBackground, unitType)
    for key, element in pairs(textElements) do
        frames[key] = element
    end

    -- Background frame
    if unitType ~= "player" then
        frames.background = CreateFrame('Frame', frameName .. 'Background', frames.castbar)
        frames.background:SetFrameLevel(frames.castbar:GetFrameLevel() - 1)
        frames.background:SetAllPoints(frames.castbar)
    else
        frames.background = frames.textBackground
    end

    -- OnUpdate handler
    frames.castbar:SetScript('OnUpdate', function(self, elapsed)
        CastbarModule:OnUpdate(unitType, self, elapsed)
    end)
end

-- ============================================================================
-- CASTING EVENT HANDLERS
-- ============================================================================
function CastbarModule:HandleCastStart_Simple(unitType, unit, isChanneling)
    local spell, displayName, icon, startTime, endTime

    if isChanneling then
        spell, _, displayName, icon, startTime, endTime = UnitChannelInfo(unit)
    else
        spell, _, displayName, icon, startTime, endTime = UnitCastingInfo(unit)
    end

    if not spell then
        return
    end

    self:RefreshCastbar(unitType)

    local frames = self.frames[unitType]
    local state = self.states[unitType]

    -- Clean state initialization
    state.casting = not isChanneling
    state.isChanneling = isChanneling
    state.spellName = spell

    local start, finish, duration = ParseCastTimes(startTime, endTime)
    state.startTime = start
    state.endTime = finish
    state.maxValue = duration

    -- Configure castbar
    frames.castbar:SetMinMaxValues(0, duration)
    
    if isChanneling then
        -- ✅ CHANNELING: Empieza LLENO, como casting pero al revés
        frames.castbar:SetValue(duration)  -- ← Empezar lleno
        state.currentValue = duration
        
        if frames.castbar.UpdateTextureClipping then
            frames.castbar:UpdateTextureClipping(1.0, true)  -- ← Progreso inicial = 1.0
        end
    else
        -- CASTING: Empieza vacío, se llena normalmente
        frames.castbar:SetValue(0)  
        state.currentValue = 0
        
        if frames.castbar.UpdateTextureClipping then
            frames.castbar:UpdateTextureClipping(0.0, false)  -- ← Progreso inicial = 0.0
        end
    end
    
    frames.castbar:Show()
    
    if frames.background and frames.background ~= frames.textBackground then
        frames.background:Show()
    end

    if frames.spark then
        frames.spark:Show()
    end
    if frames.flash then
        frames.flash:Hide()
    end

    HideAllTicks(frames.ticks)

    -- Set texture based on type
    if isChanneling then
        frames.castbar:SetStatusBarTexture(TEXTURES.channel)
        frames.castbar:SetStatusBarColor(unitType == "player" and 0 or 1, 1, unitType == "player" and 1 or 1, 1)
        UpdateChannelTicks(frames.castbar, frames.ticks, spell)
    else
        frames.castbar:SetStatusBarTexture(TEXTURES.standard)
        frames.castbar:SetStatusBarColor(1, 0.7, 0, 1)
    end

    ForceStatusBarLayer(frames.castbar)
    SetCastText(unitType, displayName)

 

    -- Configure icon and other elements...
    local cfg = GetConfig(unitType)
    if frames.icon and cfg and cfg.showIcon then
        frames.icon:SetTexture(GetSpellIcon(displayName, icon))
        frames.icon:Show()
        if frames.icon.Border then
            frames.icon.Border:Show()
        end
    else
        if frames.icon then
            frames.icon:Hide()
        end
        if frames.icon and frames.icon.Border then
            frames.icon.Border:Hide()
        end
    end

    if frames.textBackground then
        frames.textBackground:Show()
        frames.textBackground:ClearAllPoints()
        frames.textBackground:SetSize(frames.castbar:GetWidth(), unitType == "player" and 22 or 20)
        frames.textBackground:SetPoint("TOP", frames.castbar, "BOTTOM", 0, unitType == "player" and 6 or 8)
    end
end
function CastbarModule:HandleCastStop_Simple(unitType, wasInterrupted)
    local frames = self.frames[unitType]
    local state = self.states[unitType]

    if not (state.casting or state.isChanneling) and not wasInterrupted then
        return
    end

    local cfg = GetConfig(unitType)
    if not cfg then
        return
    end

    if wasInterrupted then
        -- Show interrupted state
        state.casting = false
        state.isChanneling = false

        if frames.shield then frames.shield:Hide() end
        if frames.spark then frames.spark:Hide() end
        if frames.flash then frames.flash:Hide() end
        HideAllTicks(frames.ticks)

        frames.castbar:SetStatusBarTexture(TEXTURES.interrupted)
        frames.castbar:SetStatusBarColor(1, 0, 0, 1)
        frames.castbar:SetValue(state.maxValue)

        -- ✅ RESETEAR TEXTURE CLIPPING para mostrar textura completa
        local texture = frames.castbar:GetStatusBarTexture()
        if texture then
            texture:SetTexCoord(0, 1, 0, 1)  -- Mostrar completo para interrupted
        end

        SetCastText(unitType, "Interrupted")
        state.holdTime = cfg.holdTimeInterrupt or 0.8

    else
        -- Normal completion
        if frames.spark then frames.spark:Hide() end
        if frames.shield then frames.shield:Hide() end
        HideAllTicks(frames.ticks)

        state.casting = false
        state.isChanneling = false

        -- ✅ RESETEAR CLIPPING para completion flash
        local texture = frames.castbar:GetStatusBarTexture()
        if texture then
            texture:SetTexCoord(0, 1, 0, 1)  -- Mostrar completo para flash
        end

        if frames.flash then
            frames.flash:Show()
            addon.core:ScheduleTimer(function()
                if frames.flash then
                    frames.flash:Hide()
                end
            end, 0.3)
        end

        state.holdTime = cfg.holdTime or 0.3
    end
end


-- ============================================================================
-- UPDATE HANDLER
-- ============================================================================
function CastbarModule:OnUpdate(unitType, castbar, elapsed)
    local state = self.states[unitType]
    local frames = self.frames[unitType]
    local cfg = GetConfig(unitType)

    if not cfg or not cfg.enabled then
        return
    end

    local currentTime = GetTime()

    if state.casting or state.isChanneling then
        local progress

        if state.casting then
            -- CASTING: Progreso normal de 0 a maxValue
            local elapsed = math.min(currentTime, state.endTime) - state.startTime
            local value = elapsed
            progress = elapsed / state.maxValue
            
            castbar:SetValue(value)  -- StatusBar se llena normalmente
            state.currentValue = value
        else
            -- ✅ CHANNELING: EXACTAMENTE IGUAL QUE CASTING PERO AL REVÉS
            local elapsed = math.min(currentTime, state.endTime) - state.startTime
            local remaining = state.maxValue - elapsed  -- ← INVERTIR: remaining en lugar de elapsed
            progress = remaining / state.maxValue  -- ← INVERTIR: progress de 1→0
            
            castbar:SetValue(remaining)  -- ← INVERTIR: StatusBar se vacía
            state.currentValue = remaining
        end

        if currentTime > state.endTime then
            self:HandleCastStop_Simple(unitType, false)
            return
        end

        -- ✅ APLICAR TEXTURE CLIPPING (IGUAL PARA AMBOS)
        if frames.castbar.UpdateTextureClipping then
            frames.castbar:UpdateTextureClipping(progress, state.isChanneling)
        end

        -- ✅ SPARK: Posición basada en el progreso visual
        if frames.spark and frames.spark:IsShown() then
            local sparkPosition = castbar:GetWidth() * progress
            frames.spark:ClearAllPoints()
            frames.spark:SetPoint('CENTER', castbar, 'LEFT', sparkPosition, 0)
        end

        UpdateTimeText(unitType)

    elseif state.holdTime > 0 then
        state.holdTime = state.holdTime - elapsed
        if state.holdTime <= 0 then
            self:HideCastbar(unitType)
        end
    end
end
-- ============================================================================
-- CASTBAR REFRESH
-- ============================================================================

function CastbarModule:RefreshCastbar(unitType)
    local cfg = GetConfig(unitType)
    if not cfg then
        return
    end

    if cfg.enabled then
        HideBlizzardCastbar(unitType)
    else
        ShowBlizzardCastbar(unitType)
        self:HideCastbar(unitType)
        return
    end

    if not self.frames[unitType].castbar then
        CreateCastbar(unitType)
    end

    local frames = self.frames[unitType]
    local frameName = 'DragonUI' .. unitType:sub(1, 1):upper() .. unitType:sub(2) .. 'Castbar'

    -- Calculate aura offset for target and focus
    local auraOffset = 0
    if unitType == "target" and cfg.autoAdjust then
        auraOffset = GetTargetAuraOffset()
    elseif unitType == "focus" and cfg.autoAdjust then
        auraOffset = GetFocusAuraOffset()
    end

    -- Position and size castbar
    frames.castbar:ClearAllPoints()
    local anchorFrame = UIParent
    local anchorPoint = "CENTER"
    local relativePoint = "BOTTOM"
    local xPos = cfg.x_position or 0
    local yPos = cfg.y_position or 200

    if unitType == "player" then
        --  USAR ANCHOR FRAME PARA PLAYER CASTBAR (SISTEMA CENTRALIZADO)
        if self.anchor then
            anchorFrame = self.anchor
            anchorPoint = "CENTER"
            relativePoint = "CENTER"
            xPos = 0 -- Relativo al anchor, no offset adicional
            yPos = 0
        else
            -- Fallback si no hay anchor (modo legacy)
            anchorFrame = UIParent
            anchorPoint = "BOTTOM"
            relativePoint = "BOTTOM"
        end
    elseif unitType ~= "player" then
        anchorFrame = _G[cfg.anchorFrame] or (unitType == "target" and TargetFrame or FocusFrame) or UIParent
        anchorPoint = cfg.anchor or "CENTER"
        relativePoint = cfg.anchorParent or "BOTTOM"
    end

    frames.castbar:SetPoint(anchorPoint, anchorFrame, relativePoint, xPos, yPos - auraOffset)
    frames.castbar:SetSize(cfg.sizeX or 200, cfg.sizeY or 16)
    frames.castbar:SetScale(cfg.scale or 1)

    -- Create spark if needed
    if not frames.spark then
        frames.spark = CreateFrame("Frame", frameName .. "Spark", UIParent)
        frames.spark:SetFrameStrata("MEDIUM")
        frames.spark:SetFrameLevel(11)
        frames.spark:SetSize(16, 16)
        frames.spark:Hide()

        local sparkTexture = frames.spark:CreateTexture(nil, 'ARTWORK')
        sparkTexture:SetTexture(TEXTURES.spark)
        sparkTexture:SetAllPoints()
        sparkTexture:SetBlendMode('ADD')
    end

    -- FIXED: Sincronizar escala del spark con el castbar
    frames.spark:SetScale(cfg.scale or 1)

    -- Position text background
    if frames.textBackground then
        frames.textBackground:ClearAllPoints()
        frames.textBackground:SetPoint('TOP', frames.castbar, 'BOTTOM', 0, unitType == "player" and 6 or 8)
        frames.textBackground:SetSize(cfg.sizeX or 200, unitType == "player" and 22 or 20)
        frames.textBackground:SetScale(cfg.scale or 1)
    end

    -- Configure icon
    if frames.icon then
        local iconSize = cfg.sizeIcon or 20
        frames.icon:SetSize(iconSize, iconSize)
        frames.icon:ClearAllPoints()

        if unitType == "player" then
            frames.icon:SetPoint('TOPLEFT', frames.castbar, 'TOPLEFT', -(iconSize + 6), -1)
        else
            local iconScale = iconSize / 16
            frames.icon:SetPoint('RIGHT', frames.castbar, 'LEFT', -7 * iconScale, -4)
        end

        if frames.icon.Border then
            frames.icon.Border:ClearAllPoints()
            frames.icon.Border:SetPoint('CENTER', frames.icon, 'CENTER', 0, 0)
            frames.icon.Border:SetSize(iconSize * 1.7, iconSize * 1.7)
        end

        if frames.shield then
            if unitType == "player" then
                frames.shield:ClearAllPoints()
                frames.shield:SetPoint('CENTER', frames.icon, 'CENTER', 0, 0)
                frames.shield:SetSize(iconSize * 0.8, iconSize * 0.8)
            else
                frames.shield:SetSize(iconSize * 1.8, iconSize * 2.0)
            end
        end
    end

    -- Update spark size
    if frames.spark then
        local sparkSize = cfg.sizeY or 16
        frames.spark:SetSize(sparkSize, sparkSize * 2)
        -- FIXED: Asegurar que la escala del spark coincida con el castbar
        frames.spark:SetScale(cfg.scale or 1)
    end

    -- Update tick sizes
    if frames.ticks then
        for i = 1, MAX_TICKS do
            if frames.ticks[i] then
                -- ✅ CRITICAL: Usar la altura REAL del castbar después de SetSize/SetScale
                local realHeight = frames.castbar:GetHeight()
                frames.ticks[i]:SetSize(3, max(realHeight - 2, 10))
            end
        end
    end

    -- Set compact layout for target/focus
    if unitType ~= "player" then
        SetTextMode(unitType, cfg.text_mode or "simple")
    end

    -- Ensure proper frame levels
    frames.castbar:SetFrameLevel(10)
    if frames.background then
        frames.background:SetFrameLevel(9)
    end
    if frames.textBackground then
        frames.textBackground:SetFrameLevel(9)
    end

    HideBlizzardCastbar(unitType)
    SetupVertexColor(frames.castbar)

    if cfg.text_mode then
        SetTextMode(unitType, cfg.text_mode)
    end
end

function CastbarModule:HideCastbar(unitType)
    local frames = self.frames[unitType]
    local state = self.states[unitType]

    if frames.castbar then
        frames.castbar:Hide()
    end
    if frames.background then
        frames.background:Hide()
    end
    if frames.textBackground then
        frames.textBackground:Hide()
    end
    if frames.flash then
        frames.flash:Hide()
    end
    if frames.spark then
        frames.spark:Hide()
    end
    if frames.shield then
        frames.shield:Hide()
    end
    if frames.icon then
        frames.icon:Hide()
    end

    -- Reset estado
    state.casting = false
    state.isChanneling = false
    state.holdTime = 0
    state.maxValue = 0
    state.currentValue = 0
    state.endTime = 0
    state.startTime = 0
    state.spellName = ""

    if unitType == "player" then
        state.castSucceeded = false
    else
        if not UnitExists(unitType) then
            state.unitGUID = nil
        end
    end
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

function CastbarModule:HandleCastingEvent(event, unit)
    local unitType
    if unit == "player" then
        unitType = "player"
    elseif unit == "target" then
        unitType = "target"
    elseif unit == "focus" then
        unitType = "focus"
    else
        return
    end

    if not IsEnabled(unitType) then
        return
    end

    HideBlizzardCastbar(unitType)

    -- GUID verification for target/focus
    if unitType ~= "player" then
        local frames = self.frames[unitType]
        if not frames.castbar then
            return
        end

        if event == 'UNIT_SPELLCAST_START' or event == 'UNIT_SPELLCAST_CHANNEL_START' then
            frames.castbar.unit = UnitGUID(unit)
        else
            if frames.castbar.unit ~= UnitGUID(unit) then
                return
            end
        end
    end

    -- Event handling
    if event == 'UNIT_SPELLCAST_START' then
        self:HandleCastStart_Simple(unitType, unit, false)
    elseif event == 'UNIT_SPELLCAST_CHANNEL_START' then
        self:HandleCastStart_Simple(unitType, unit, true)
    elseif event == 'UNIT_SPELLCAST_STOP' then
        self:HandleCastStop_Simple(unitType, false)
    elseif event == 'UNIT_SPELLCAST_CHANNEL_STOP' then
        self:HandleCastStop_Simple(unitType, false)
    elseif event == 'UNIT_SPELLCAST_FAILED' then
        self:HandleCastStop_Simple(unitType, false)
    elseif event == 'UNIT_SPELLCAST_INTERRUPTED' then
        self:HandleCastStop_Simple(unitType, true)
    elseif event == 'UNIT_SPELLCAST_CHANNEL_INTERRUPTED' then
        self:HandleCastStop_Simple(unitType, true)
    elseif event == 'UNIT_SPELLCAST_DELAYED' or event == 'UNIT_SPELLCAST_CHANNEL_UPDATE' then
        self:HandleCastDelayed_Simple(unitType, unit)
    end
end

function CastbarModule:HandleTargetChanged()
    local frames = self.frames.target
    local statusBar = frames.castbar

    if not statusBar then
        return
    end

    -- ✅ FIXED: Limpiar estado siempre que el GUID no coincida
    if UnitExists("target") and statusBar.unit == UnitGUID("target") then
        -- Same target, check if cast should still be visible
        if GetTime() > (self.states.target.endTime or 0) then
            self:HideCastbar("target") -- ← Usar HideCastbar para limpieza completa
        else
            statusBar:Show()
        end
    else
        -- Different target or no target - CLEAN EVERYTHING
        self:HideCastbar("target") -- ← CRITICAL: Limpiar estado completo
    end

    HideBlizzardCastbar("target")

    -- Check if new target has active cast
    if UnitExists("target") and IsEnabled("target") then
        if UnitCastingInfo("target") then
            self:HandleCastingEvent('UNIT_SPELLCAST_START', "target")
        elseif UnitChannelInfo("target") then
            self:HandleCastingEvent('UNIT_SPELLCAST_CHANNEL_START', "target")
        end
        ApplyTargetAuraOffset()
    end
end

function CastbarModule:HandleFocusChanged()
    local frames = self.frames.focus
    local statusBar = frames.castbar

    if not statusBar then
        return
    end

    -- ✅ FIXED: Misma lógica para focus
    if UnitExists("focus") and statusBar.unit == UnitGUID("focus") then
        -- Same focus, check if cast should still be visible
        if GetTime() > (self.states.focus.endTime or 0) then
            self:HideCastbar("focus") -- ← Usar HideCastbar para limpieza completa
        else
            statusBar:Show()
        end
    else
        -- Different focus or no focus - CLEAN EVERYTHING
        self:HideCastbar("focus") -- ← CRITICAL: Limpiar estado completo
    end

    HideBlizzardCastbar("focus")

    -- Check if new focus has active cast
    if UnitExists("focus") and IsEnabled("focus") then
        if UnitCastingInfo("focus") then
            self:HandleCastingEvent('UNIT_SPELLCAST_START', "focus")
        elseif UnitChannelInfo("focus") then
            self:HandleCastingEvent('UNIT_SPELLCAST_CHANNEL_START', "focus")
        end
        ApplyFocusAuraOffset()
    end
end

-- ============================================================================
-- Función de manejo de delays 
-- ============================================================================
function CastbarModule:HandleCastDelayed_Simple(unitType, unit)
    local state = self.states[unitType]

    if not (state.casting or state.isChanneling) then
        return
    end

    local spell, startTime, endTime

    if state.casting then
        spell, _, _, _, startTime, endTime = UnitCastingInfo(unit)
    else
        spell, _, _, _, startTime, endTime = UnitChannelInfo(unit)
    end

    if not spell or spell ~= state.spellName then
        self:HideCastbar(unitType)
        return
    end

    -- Update times only
    state.startTime = startTime / 1000
    state.endTime = endTime / 1000
    state.maxValue = state.endTime - state.startTime

    local frames = self.frames[unitType]
    frames.castbar:SetMinMaxValues(0, state.maxValue)
    
    -- ✅ Para channeling después de delay, mantener StatusBar lleno
    if state.isChanneling then
        frames.castbar:SetValue(state.maxValue)  -- Mantener lleno
        local currentTime = GetTime()
        state.currentValue = math.max(0, state.endTime - currentTime)
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
local function OnEvent(self, event, unit, ...)
    if event == 'UNIT_AURA' and unit == 'target' then
        local cfg = GetConfig("target")
        if cfg and cfg.enabled and cfg.autoAdjust then
            addon.core:ScheduleTimer(ApplyTargetAuraOffset, 0.05)
        end
    elseif event == 'UNIT_AURA' and unit == 'focus' then
        local cfg = GetConfig("focus")
        if cfg and cfg.enabled and cfg.autoAdjust then
            addon.core:ScheduleTimer(ApplyFocusAuraOffset, 0.05)
        end
    elseif event == 'PLAYER_TARGET_CHANGED' then
        CastbarModule:HandleTargetChanged()
    elseif event == 'PLAYER_FOCUS_CHANGED' then
        CastbarModule:HandleFocusChanged()
    elseif event == 'PLAYER_ENTERING_WORLD' then
        addon.core:ScheduleTimer(function()
            CastbarModule:RefreshCastbar("player")
            CastbarModule:RefreshCastbar("target")
            CastbarModule:RefreshCastbar("focus")

            addon.core:ScheduleTimer(function()
                if IsEnabled("player") then
                    HideBlizzardCastbar("player")
                end
                if IsEnabled("target") then
                    HideBlizzardCastbar("target")
                end
                if IsEnabled("focus") then
                    HideBlizzardCastbar("focus")
                end
            end, 1.0)
        end, 0.5)
    else
        CastbarModule:HandleCastingEvent(event, unit)
    end
end

-- Public API
function addon.RefreshCastbar()
    CastbarModule:RefreshCastbar("player")
end

function addon.RefreshTargetCastbar()
    CastbarModule:RefreshCastbar("target")
end

function addon.RefreshFocusCastbar()
    CastbarModule:RefreshCastbar("focus")
end

-- Initialize
local eventFrame = CreateFrame('Frame', 'DragonUICastbarEventHandler')
local events = {'PLAYER_ENTERING_WORLD', 'UNIT_SPELLCAST_START', 'UNIT_SPELLCAST_DELAYED', 'UNIT_SPELLCAST_STOP',
                'UNIT_SPELLCAST_FAILED', 'UNIT_SPELLCAST_INTERRUPTED', 'UNIT_SPELLCAST_CHANNEL_START',
                'UNIT_SPELLCAST_CHANNEL_STOP', 'UNIT_SPELLCAST_CHANNEL_UPDATE', 'UNIT_AURA', 'PLAYER_TARGET_CHANGED',
                'PLAYER_FOCUS_CHANGED'}

for _, event in ipairs(events) do
    eventFrame:RegisterEvent(event)
end

eventFrame:SetScript('OnEvent', OnEvent)

-- Hook native WoW aura positioning
if TargetFrameSpellBar then
    hooksecurefunc('Target_Spellbar_AdjustPosition', function()
        local cfg = GetConfig("target")
        if cfg and cfg.enabled and cfg.autoAdjust then
            addon.core:ScheduleTimer(ApplyTargetAuraOffset, 0.05)
        end
    end)
end

--  También necesitamos asegurar que el TargetFrameSpellBar no interfiera
if TargetFrameSpellBar then
    -- Disable Blizzard's own hiding logic that might interfere
    TargetFrameSpellBar:SetScript("OnHide", nil)
    TargetFrameSpellBar:SetScript("OnShow", function(self)
        local cfg = GetConfig("target")
        if cfg and cfg.enabled then
            self:Hide()
        end
    end)
end

-- ============================================================================
-- CENTRALIZED SYSTEM INTEGRATION
-- ============================================================================

-- Variables para el sistema centralizado
CastbarModule.anchor = nil
CastbarModule.initialized = false

-- Create auxiliary frame for anchoring (como party.lua)
local function CreateCastbarAnchorFrame()
    if CastbarModule.anchor then
        return CastbarModule.anchor
    end

    --  USAR FUNCIÓN CENTRALIZADA DE CORE.LUA
    CastbarModule.anchor = addon.CreateUIFrame(256, 16, "PlayerCastbar")

    --  PERSONALIZAR TEXTO PARA CASTBAR
    if CastbarModule.anchor.editorText then
        CastbarModule.anchor.editorText:SetText("Player Castbar")
    end

    return CastbarModule.anchor
end

--  FUNCIÓN PARA APLICAR POSICIÓN DESDE WIDGETS (COMO party.lua)
local function ApplyWidgetPosition()
    if not CastbarModule.anchor then
        return
    end

    if not addon.db or not addon.db.profile or not addon.db.profile.widgets then
        return
    end

    local widgetConfig = addon.db.profile.widgets.playerCastbar

    if widgetConfig and widgetConfig.posX and widgetConfig.posY then
        local anchor = widgetConfig.anchor or "BOTTOM"
        CastbarModule.anchor:ClearAllPoints()
        CastbarModule.anchor:SetPoint(anchor, UIParent, anchor, widgetConfig.posX, widgetConfig.posY)
    else
        -- Default position
        CastbarModule.anchor:ClearAllPoints()
        CastbarModule.anchor:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 270)
    end
end

--  FUNCIONES REQUERIDAS POR EL SISTEMA CENTRALIZADO
function CastbarModule:LoadDefaultSettings()
    if not addon.db.profile.widgets then
        addon.db.profile.widgets = {}
    end

    if not addon.db.profile.widgets.playerCastbar then
        addon.db.profile.widgets.playerCastbar = {
            anchor = "BOTTOM",
            posX = 0,
            posY = 270
        }
    end

    if not addon.db.profile.castbar then
        addon.db.profile.castbar = {}
    end
end

function CastbarModule:UpdateWidgets()
    ApplyWidgetPosition()
    --  REPOSICIONAR EL CASTBAR DEL PLAYER RELATIVO AL ANCHOR ACTUALIZADO
    if not InCombatLockdown() then
        -- El castbar del player debería seguir al anchor
        self:RefreshCastbar("player")
    end
end

--  FUNCIÓN PARA VERIFICAR SI EL CASTBAR DEBE ESTAR VISIBLE
local function ShouldPlayerCastbarBeVisible()
    local cfg = GetConfig("player")
    return cfg and cfg.enabled
end

--  FUNCIONES DE TESTEO PARA EL EDITOR
local function ShowPlayerCastbarTest()
    -- Mostrar el castbar aunque no haya casting
    local frames = CastbarModule.frames.player
    if frames.castbar then
        -- Simular un cast de prueba
        frames.castbar:SetMinMaxValues(0, 1)
        frames.castbar:SetValue(0.5)
        frames.castbar:Show()

        if frames.textBackground then
            frames.textBackground:Show()
        end

        -- Mostrar texto de prueba
        CastbarModule:ShowCastbar("player", "Fire ball", 0.5, 1, 1.5, false, false)
    end
end

local function HidePlayerCastbarTest()
    -- Ocultar el castbar de prueba
    CastbarModule:HideCastbar("player")
end

--  FUNCIÓN AUXILIAR PARA MOSTRAR CASTBAR (USADA EN TESTS)
function CastbarModule:ShowCastbar(unitType, spellName, currentValue, maxValue, duration, isChanneling, isInterrupted)
    local frames = self.frames[unitType]
    if not frames.castbar then
        self:RefreshCastbar(unitType)
        frames = self.frames[unitType]
    end

    if not frames.castbar then
        return
    end

    local state = self.states[unitType]
    state.casting = not isChanneling
    state.isChanneling = isChanneling
    state.spellName = spellName
    state.maxValue = maxValue
    state.currentValue = currentValue

    frames.castbar:SetMinMaxValues(0, maxValue)
    frames.castbar:SetValue(currentValue)
    frames.castbar:Show()

    if isInterrupted then
        frames.castbar:SetStatusBarTexture(TEXTURES.interrupted)
        frames.castbar:SetStatusBarColor(1, 0, 0, 1)
        SetCastText(unitType, "Interrupted")
    else
        if isChanneling then
            frames.castbar:SetStatusBarTexture(TEXTURES.channel)
            frames.castbar:SetStatusBarColor(0, 1, 0, 1)
        else
            frames.castbar:SetStatusBarTexture(TEXTURES.standard)
            frames.castbar:SetStatusBarColor(1, 0.7, 0, 1)
        end
        SetCastText(unitType, spellName)
    end

    if frames.textBackground then
        frames.textBackground:Show()
    end

    ForceStatusBarLayer(frames.castbar)
end

--  FUNCIÓN DE INICIALIZACIÓN DEL SISTEMA CENTRALIZADO
local function InitializeCastbarForEditor()
    -- Crear el anchor frame
    CreateCastbarAnchorFrame()

    --  REGISTRO COMPLETO CON TODAS LAS FUNCIONES (COMO party.lua)
    addon:RegisterEditableFrame({
        name = "PlayerCastbar",
        frame = CastbarModule.anchor,
        configPath = {"widgets", "playerCastbar"}, --  CORREGIDO: Array en lugar de string
        hasTarget = ShouldPlayerCastbarBeVisible, --  Visibilidad condicional
        showTest = ShowPlayerCastbarTest, --  CORREGIDO: Minúscula como party.lua
        hideTest = HidePlayerCastbarTest, --  CORREGIDO: Minúscula como party.lua
        onHide = function()
            CastbarModule:UpdateWidgets()
        end, --  AÑADIDO: Para aplicar cambios
        LoadDefaultSettings = function()
            CastbarModule:LoadDefaultSettings()
        end,
        UpdateWidgets = function()
            CastbarModule:UpdateWidgets()
        end
    })

    CastbarModule.initialized = true

end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

--  Initialize centralized system for editor
InitializeCastbarForEditor()

--  LISTENER PARA CUANDO EL ADDON ESTÉ COMPLETAMENTE CARGADO
local readyFrame = CreateFrame("Frame")
readyFrame:RegisterEvent("ADDON_LOADED")
readyFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "DragonUI" then
        -- Aplicar posición del widget cuando el addon esté listo
        if CastbarModule.UpdateWidgets then
            CastbarModule:UpdateWidgets()
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
