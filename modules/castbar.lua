local addon = select(2, ...)

-- ============================================================================
-- CASTBAR MODULE FOR DRAGONUI
-- Original code by Neticsoul
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
-- CONSTANTS AND TEXTURES
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
    frames = {},
    initialized = false,
    anchor = nil,
    blizzardHidden = {}  -- Track which Blizzard castbars we've hidden
}

-- Initialize frames for each castbar type
for _, unitType in ipairs({"player", "target", "focus"}) do
    CastbarModule.frames[unitType] = {}
end

-- ============================================================================
-- CONFIGURATION ACCESS
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

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

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
-- BLIZZARD CASTBAR MANAGEMENT 
-- ============================================================================

local function HideBlizzardCastbar(unitType)
    -- Skip if already hidden
    if CastbarModule.blizzardHidden[unitType] then
        return
    end
    
    local frames = {
        player = CastingBarFrame,
        target = TargetFrameSpellBar,
        focus = FocusFrameSpellBar
    }
    
    local frame = frames[unitType]
    if not frame then
        return
    end
    
    -- More aggressive hiding to prevent interference
    frame:Hide()
    frame:SetAlpha(0)
    
    if unitType == "target" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, -5000)
        frame:SetSize(1, 1)
    end
    
    -- Set OnShow hook only once
    if not frame._dragonUIHooked then
        frame:SetScript("OnShow", function(self)
            if CastbarModule.blizzardHidden[unitType] then
                self:Hide()
            end
        end)
        frame._dragonUIHooked = true
    end
    
    CastbarModule.blizzardHidden[unitType] = true
end

local function ShowBlizzardCastbar(unitType)
    CastbarModule.blizzardHidden[unitType] = false
    
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
    
    if unitType == "target" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", TargetFrame, "BOTTOMLEFT", 25, -5)
    end
end

-- ============================================================================
-- TEXTURE LAYER MANAGEMENT 
-- ============================================================================

local function ForceStatusBarLayer(statusBar)
    if not statusBar or statusBar._layerForced then
        return
    end
    
    local texture = statusBar:GetStatusBarTexture()
    if texture and texture.SetDrawLayer then
        texture:SetDrawLayer('BORDER', 0)
        statusBar._layerForced = true
    end
end

local function CreateTextureClipping(statusBar)
    -- Cache for performance
    local lastProgress = -1
    local lastChanneling = nil
    
    statusBar.UpdateTextureClipping = function(self, progress, isChanneling)
        local texture = self:GetStatusBarTexture()
        if not texture then
            return
        end
        
        -- Skip if values haven't changed significantly
        if abs(progress - lastProgress) < 0.001 and isChanneling == lastChanneling then
            return
        end
        lastProgress = progress
        lastChanneling = isChanneling
        
        local clampedProgress = max(0.01, min(0.99, progress))
        
        if isChanneling then
            -- CHANNELING: Hide from right
            texture:SetTexCoord(0, clampedProgress, 0, 1)
        else
            -- CASTING: Fill from left
            texture:SetTexCoord(0, clampedProgress, 0, 1)
        end
        
        texture:ClearAllPoints()
        texture:SetAllPoints(self)
    end
end

-- ============================================================================
-- FADE SYSTEM 
-- ============================================================================

local function RestoreCastbarVisibility(unitType)
    local frames = CastbarModule.frames[unitType]
    if not frames or not frames.container then
        return
    end
    
    -- Cancel any active fades and restore full visibility
    local container = frames.container
    UIFrameFadeRemoveFrame(container)
    container:SetAlpha(1.0)
    container.fadeOutEx = false
    container:Show()
    
    -- Also restore castbar itself
    if frames.castbar then
        UIFrameFadeRemoveFrame(frames.castbar)
        frames.castbar:SetAlpha(1.0)
        frames.castbar.fadeOutEx = false
    end
end

local function FadeOutCastbar(unitType, duration)
    local frames = CastbarModule.frames[unitType]
    if not frames or not frames.container then
        return
    end
    
    local container = frames.container
    if container.fadeOutEx then
        return -- Already fading
    end
    
    container.fadeOutEx = true
    UIFrameFadeOut(container, duration or 1, 1.0, 0.0, function()
        container:Hide()
        container.fadeOutEx = false
    end)
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

local auraOffsetCache = {
    target = { offset = 0, guid = nil, lastUpdate = 0 },
    focus = { offset = 0, guid = nil, lastUpdate = 0 }
}

local function GetAuraOffset(unit)
    local cfg = GetConfig(unit)
    if not cfg or not cfg.autoAdjust then
        return 0
    end
    
    if not UnitExists(unit) then
        return 0
    end
    
    -- Check cache
    local cache = auraOffsetCache[unit]
    if cache and cache.guid == UnitGUID(unit) and (GetTime() - cache.lastUpdate) < 0.5 then
        return cache.offset
    end
    
    local buffCount = 0
    local debuffCount = 0
    
    -- Count auras
    if unit == "target" then
        for i = 1, 40 do
            if UnitBuff(unit, i) then
                buffCount = buffCount + 1
            else
                break
            end
        end
        for i = 1, 40 do
            if UnitDebuff(unit, i) then
                debuffCount = debuffCount + 1
            else
                break
            end
        end
    else
        local index = 1
        while index <= 40 do
            local name = UnitAura(unit, index, "HELPFUL")
            if not name then
                break
            end
            buffCount = buffCount + 1
            index = index + 1
        end
        
        index = 1
        while index <= 40 do
            local name = UnitAura(unit, index, "HARMFUL")
            if not name then
                break
            end
            debuffCount = debuffCount + 1
            index = index + 1
        end
    end
    
    local totalOffset = 0
    if buffCount > 0 or debuffCount > 0 then
        local AURAS_PER_ROW = 6
        local BUFF_ROW_HEIGHT = 10
        local DEBUFF_ROW_HEIGHT = 24
        
        if buffCount > 0 then
            local buffRows = ceil(buffCount / AURAS_PER_ROW)
            if buffRows > 1 then
                totalOffset = totalOffset + ((buffRows - 1) * BUFF_ROW_HEIGHT)
            end
        end
        
        if debuffCount > 0 then
            totalOffset = totalOffset + DEBUFF_ROW_HEIGHT
        end
    end
    
    -- Update cache
    if cache then
        cache.offset = totalOffset
        cache.guid = UnitGUID(unit)
        cache.lastUpdate = GetTime()
    end
    
    return totalOffset
end

local function ApplyAuraOffset(unit)
    local frames = CastbarModule.frames[unit]
    if not frames or not frames.container or not frames.container:IsVisible() then
        return
    end
    
    local cfg = GetConfig(unit)
    if not cfg or not cfg.enabled or not cfg.autoAdjust then
        return
    end
    
    local offset = GetAuraOffset(unit)
    local anchorFrame = _G[cfg.anchorFrame] or _G[unit:gsub("^%l", string.upper) .. "Frame"] or UIParent
    
    frames.container:ClearAllPoints()
    frames.container:SetPoint(cfg.anchor, anchorFrame, cfg.anchorParent, cfg.x_position, cfg.y_position - offset)
end

-- ============================================================================
-- TEXT MANAGEMENT
-- ============================================================================

local function SetTextMode(unitType, mode)
    local frames = CastbarModule.frames[unitType]
    if not frames then
        return
    end
    
    local elements = {
        frames.castText, 
        frames.castTextCompact, 
        frames.castTextCentered, 
        frames.castTimeText,
        frames.castTimeTextCompact
    }
    
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
    if not frames or not frames.castbar then
        return
    end
    
    local castbar = frames.castbar
    
    -- Skip if not casting/channeling
    if not castbar.castingEx and not castbar.channelingEx then
        return
    end
    
    local cfg = GetConfig(unitType)
    if not cfg then
        return
    end
    
    local seconds = 0
    local secondsMax = (castbar.endTime or 0) - (castbar.startTime or 0)
    
    local currentTime = GetTime()
    local elapsed = currentTime - (castbar.startTime or 0)
    seconds = max(0, secondsMax - elapsed)
    
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

local function CreateCastbar(unitType)
    if CastbarModule.frames[unitType].castbar then
        return
    end
    
    local frameName = 'DragonUI' .. unitType:sub(1, 1):upper() .. unitType:sub(2) .. 'Castbar'
    local frames = CastbarModule.frames[unitType]
    
    -- Create unified container frame
    frames.container = CreateFrame('Frame', frameName .. 'Container', UIParent)
    frames.container:SetFrameStrata("MEDIUM")
    frames.container:SetFrameLevel(10)
    frames.container:SetSize(256, 16)
    frames.container:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    frames.container:Hide()
    
    -- Main StatusBar
    frames.castbar = CreateFrame('StatusBar', frameName, frames.container)
    frames.castbar:SetFrameLevel(2)
    frames.castbar:SetAllPoints(frames.container)
    frames.castbar:SetMinMaxValues(0, 1)
    frames.castbar:SetValue(0)
    
    -- State flags
    frames.castbar.castingEx = false
    frames.castbar.channelingEx = false
    frames.castbar.fadeOutEx = false
    frames.castbar.selfInterrupt = false
    
    -- Background
    local bg = frames.castbar:CreateTexture(nil, 'BACKGROUND')
    bg:SetTexture(TEXTURES.atlas)
    bg:SetTexCoord(unpack(UV_COORDS.background))
    bg:SetAllPoints()
    
    -- StatusBar texture
    frames.castbar:SetStatusBarTexture(TEXTURES.standard)
    local texture = frames.castbar:GetStatusBarTexture()
    if texture then
        texture:SetVertexColor(1, 1, 1, 1)
    end
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
    
    -- Text background frame
    frames.textBackground = CreateFrame('Frame', frameName .. 'TextBG', frames.container)
    frames.textBackground:SetFrameLevel(1)
    
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
    if unitType == "player" then
        frames.castText = frames.textBackground:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        frames.castText:SetPoint('BOTTOMLEFT', frames.textBackground, 'BOTTOMLEFT', 8, 2)
        frames.castText:SetJustifyH("LEFT")
        frames.castText:Hide()
        
        frames.castTextCentered = frames.textBackground:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        frames.castTextCentered:SetPoint('BOTTOM', frames.textBackground, 'BOTTOM', 0, 1)
        frames.castTextCentered:SetPoint('LEFT', frames.textBackground, 'LEFT', 8, 0)
        frames.castTextCentered:SetPoint('RIGHT', frames.textBackground, 'RIGHT', -8, 0)
        frames.castTextCentered:SetJustifyH("CENTER")
        frames.castTextCentered:Hide()
        
        frames.timeValue = frames.textBackground:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        frames.timeValue:SetPoint('BOTTOMRIGHT', frames.textBackground, 'BOTTOMRIGHT', -50, 2)
        frames.timeValue:SetJustifyH("RIGHT")
        frames.timeValue:Hide()
        
        frames.timeMax = frames.textBackground:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        frames.timeMax:SetPoint('LEFT', frames.timeValue, 'RIGHT', 2, 0)
        frames.timeMax:SetJustifyH("LEFT")
        frames.timeMax:Hide()
    else
        frames.castText = frames.textBackground:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        frames.castText:SetPoint('BOTTOMLEFT', frames.textBackground, 'BOTTOMLEFT', 6, 2)
        frames.castText:SetJustifyH("LEFT")
        frames.castText:Hide()
        
        frames.castTextCentered = frames.textBackground:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        frames.castTextCentered:SetPoint('BOTTOM', frames.textBackground, 'BOTTOM', 0, 1)
        frames.castTextCentered:SetPoint('LEFT', frames.textBackground, 'LEFT', 6, 0)
        frames.castTextCentered:SetPoint('RIGHT', frames.textBackground, 'RIGHT', -6, 0)
        frames.castTextCentered:SetJustifyH("CENTER")
        frames.castTextCentered:Hide()
        
        frames.castTextCompact = frames.textBackground:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        frames.castTextCompact:SetPoint('BOTTOMLEFT', frames.textBackground, 'BOTTOMLEFT', 6, 2)
        frames.castTextCompact:SetJustifyH("LEFT")
        frames.castTextCompact:Hide()
        
        frames.castTimeText = frames.textBackground:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        frames.castTimeText:SetPoint('BOTTOMRIGHT', frames.textBackground, 'BOTTOMRIGHT', -6, 2)
        frames.castTimeText:SetJustifyH("RIGHT")
        frames.castTimeText:Hide()
        
        frames.castTimeTextCompact = frames.textBackground:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
        frames.castTimeTextCompact:SetPoint('BOTTOMRIGHT', frames.textBackground, 'BOTTOMRIGHT', -6, 2)
        frames.castTimeTextCompact:SetJustifyH("RIGHT")
        frames.castTimeTextCompact:Hide()
    end
    
    -- Background frame
    if unitType ~= "player" then
        frames.background = CreateFrame('Frame', frameName .. 'Background', frames.container)
        frames.background:SetFrameLevel(0)
        frames.background:SetAllPoints(frames.castbar)
    else
        frames.background = frames.textBackground
    end
    
    -- Spark
    frames.spark = CreateFrame("Frame", frameName .. "Spark", frames.container)
    frames.spark:SetFrameLevel(5)
    frames.spark:SetSize(16, 16)
    frames.spark:Hide()
    
    local sparkTexture = frames.spark:CreateTexture(nil, 'OVERLAY')
    sparkTexture:SetTexture(TEXTURES.spark)
    sparkTexture:SetAllPoints()
    sparkTexture:SetBlendMode('ADD')
    
    -- Icon
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
    
    -- Apply texture clipping system
    CreateTextureClipping(frames.castbar)
    
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
    local castbar = frames.castbar
    
    -- Set GUID for target/focus verification
    if unitType == "target" or unitType == "focus" then
        castbar.unit = UnitGUID(unit)
    end
    
    local start, finish, duration = ParseCastTimes(startTime, endTime)
    
    -- Store times directly in statusBar frame
    castbar.startTime = start
    castbar.endTime = finish
    
    -- Cancel any active fade
    castbar.fadeOutEx = false
    if frames.container then
        frames.container.fadeOutEx = false
    end
    
    -- Always use 0-1 range
    castbar:SetMinMaxValues(0, 1)
    
    if isChanneling then
        castbar:SetValue(1.0)
        castbar.channelingEx = true
        castbar.castingEx = false
        if castbar.UpdateTextureClipping then
            castbar:UpdateTextureClipping(1.0, true)
        end
    else
        castbar:SetValue(0.0)
        castbar.castingEx = true
        castbar.channelingEx = false
        if castbar.UpdateTextureClipping then
            castbar:UpdateTextureClipping(0.0, false)
        end
    end
    
    RestoreCastbarVisibility(unitType)
    
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
        local texture = frames.castbar:GetStatusBarTexture()
        if texture then
            texture:SetVertexColor(1, 1, 1, 1)
        end
    else
        frames.castbar:SetStatusBarTexture(TEXTURES.standard)
        frames.castbar:SetStatusBarColor(1, 0.7, 0, 1)
        local texture = frames.castbar:GetStatusBarTexture()
        if texture then
            texture:SetVertexColor(1, 1, 1, 1)
        end
    end
    
    ForceStatusBarLayer(frames.castbar)
    SetCastText(unitType, displayName)
    
    -- Configure icon
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

function CastbarModule:HandleCastStop_Simple(unitType, wasInterrupted, isChannelStop)
    local frames = self.frames[unitType]
    local castbar = frames.castbar
    
    -- GUID verification for target/focus
    if unitType == "target" then
        if castbar.unit ~= UnitGUID("target") then
            return
        end
    elseif unitType == "focus" then
        if castbar.unit ~= UnitGUID("focus") then
            return
        end
    end
    
    if not (castbar.castingEx or castbar.channelingEx) and not wasInterrupted then
        return
    end
    
    local cfg = GetConfig(unitType)
    if not cfg then
        return
    end
    
    -- Clear casting/channeling flags
    castbar.castingEx = false
    castbar.channelingEx = false
    castbar.selfInterrupt = isChannelStop or false
    
    if wasInterrupted or castbar.selfInterrupt then
        -- Show interrupted state
        if frames.shield then frames.shield:Hide() end
        if frames.spark then frames.spark:Hide() end
        if frames.flash then frames.flash:Hide() end
        HideAllTicks(frames.ticks)
        
        castbar:SetStatusBarTexture(TEXTURES.interrupted)
        castbar:SetStatusBarColor(1, 0, 0, 1)
        castbar:SetValue(1.0)
        local texture = castbar:GetStatusBarTexture()
        if texture then
            texture:SetTexCoord(0, 1, 0, 1)
            texture:SetVertexColor(1, 1, 1, 1)
        end
        
        SetCastText(unitType, "Interrupted")
        FadeOutCastbar(unitType, 1)
    else
        -- Normal completion
        if frames.spark then frames.spark:Hide() end
        if frames.shield then frames.shield:Hide() end
        HideAllTicks(frames.ticks)
        
        local texture = castbar:GetStatusBarTexture()
        if texture then
            texture:SetTexCoord(0, 1, 0, 1)
        end
        
        if frames.flash then
            frames.flash:Show()
            addon.core:ScheduleTimer(function()
                if frames.flash then
                    frames.flash:Hide()
                end
            end, 0.3)
        end
        
        FadeOutCastbar(unitType, 1)
    end
end

function CastbarModule:HandleCastFailed_Simple(unitType)
    -- Failed events do nothing - let cast continue normally
end

function CastbarModule:HandleCastDelayed_Simple(unitType, unit)
    local frames = self.frames[unitType]
    local castbar = frames.castbar
    
    if not castbar or not (castbar.castingEx or castbar.channelingEx) then
        return
    end
    
    local spell, startTime, endTime
    
    if castbar.castingEx then
        spell, _, _, _, startTime, endTime = UnitCastingInfo(unit)
    else
        spell, _, _, _, startTime, endTime = UnitChannelInfo(unit)
    end
    
    if not spell then
        self:HideCastbar(unitType)
        return
    end
    
    local start = startTime / 1000
    local finish = endTime / 1000
    
    castbar.startTime = start
    castbar.endTime = finish
end

-- ============================================================================
-- UPDATE HANDLER 
-- ============================================================================

function CastbarModule:OnUpdate(unitType, castbar, elapsed)
    -- Early exit if not casting/channeling
    if not castbar.castingEx and not castbar.channelingEx then
        return
    end
    
    local frames = self.frames[unitType]
    if not frames then
        return
    end
    
    local cfg = GetConfig(unitType)
    if not cfg or not cfg.enabled then
        return
    end
    
    local currentTime = GetTime()
    local value = 0
    
    if castbar.castingEx then
        local remainingTime = min(currentTime, castbar.endTime) - castbar.startTime
        value = remainingTime / (castbar.endTime - castbar.startTime)
    elseif castbar.channelingEx then
        local remainingTime = castbar.endTime - currentTime
        value = remainingTime / (castbar.endTime - castbar.startTime)
    end
    
    castbar:SetValue(value)
    
    -- Apply texture clipping
    if castbar.UpdateTextureClipping then
        castbar:UpdateTextureClipping(value, castbar.channelingEx)
    end
    
    if currentTime > castbar.endTime then
        castbar.castingEx = false
        castbar.channelingEx = false
        FadeOutCastbar(unitType, 1)
        return
    end
    
    -- Update spark position
    if frames.spark and frames.spark:IsShown() then
        frames.spark:ClearAllPoints()
        frames.spark:SetPoint('CENTER', castbar, 'LEFT', value * castbar:GetWidth(), 0)
    end
    
    UpdateTimeText(unitType)
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
    
    -- Calculate aura offset
    local auraOffset = cfg.autoAdjust and GetAuraOffset(unitType) or 0
    
    -- Calculate positioning
    local anchorFrame = UIParent
    local anchorPoint = "CENTER"
    local relativePoint = "BOTTOM"
    local xPos = cfg.x_position or 0
    local yPos = cfg.y_position or 200
    
    if unitType == "player" then
        if self.anchor then
            anchorFrame = self.anchor
            anchorPoint = "CENTER"
            relativePoint = "CENTER"
            xPos = 0
            yPos = 0
        else
            anchorFrame = UIParent
            anchorPoint = "BOTTOM"
            relativePoint = "BOTTOM"
        end
    elseif unitType ~= "player" then
        anchorFrame = _G[cfg.anchorFrame] or (unitType == "target" and TargetFrame or FocusFrame) or UIParent
        anchorPoint = cfg.anchor or "CENTER"
        relativePoint = cfg.anchorParent or "BOTTOM"
    end
    
    frames.container:ClearAllPoints()
    frames.container:SetPoint(anchorPoint, anchorFrame, relativePoint, xPos, yPos - auraOffset)
    frames.container:SetSize(cfg.sizeX or 200, cfg.sizeY or 16)
    frames.container:SetScale(cfg.scale or 1)
    
    -- Position text background
    if frames.textBackground then
        frames.textBackground:ClearAllPoints()
        frames.textBackground:SetPoint('TOP', frames.castbar, 'BOTTOM', 0, unitType == "player" and 6 or 8)
        frames.textBackground:SetSize(cfg.sizeX or 200, unitType == "player" and 22 or 20)
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
    end
    
    -- Update tick sizes
    if frames.ticks then
        for i = 1, MAX_TICKS do
            if frames.ticks[i] then
                local realHeight = frames.castbar:GetHeight()
                frames.ticks[i]:SetSize(3, max(realHeight - 2, 10))
            end
        end
    end
    
    -- Set text mode
    if unitType ~= "player" then
        SetTextMode(unitType, cfg.text_mode or "simple")
    end
    
    -- Ensure proper frame levels
    frames.castbar:SetFrameLevel(2)
    if frames.background then
        frames.background:SetFrameLevel(0)
    end
    if frames.textBackground then
        frames.textBackground:SetFrameLevel(1)
    end
    if frames.spark then
        frames.spark:SetFrameLevel(5)
    end
    
    HideBlizzardCastbar(unitType)
    
    if cfg.text_mode then
        SetTextMode(unitType, cfg.text_mode)
    end
end

function CastbarModule:HideCastbar(unitType)
    local frames = self.frames[unitType]
    
    if frames.container then
        frames.container:Hide()
    end
    
    local castbar = frames.castbar
    if castbar then
        castbar.castingEx = false
        castbar.channelingEx = false
        castbar.fadeOutEx = false
        castbar.selfInterrupt = false
        castbar.startTime = 0
        castbar.endTime = 0
        castbar.unit = nil
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
        self:HandleCastStop_Simple(unitType, false, true)
    elseif event == 'UNIT_SPELLCAST_FAILED' then
        self:HandleCastFailed_Simple(unitType)
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
    
    if UnitExists("target") and statusBar.unit == UnitGUID("target") then
        if GetTime() > (statusBar.endTime or 0) then
            self:HideCastbar("target")
        else
            statusBar:Show()
        end
    else
        self:HideCastbar("target")
    end
    
    HideBlizzardCastbar("target")
    
    -- Check if new target has active cast
    if UnitExists("target") and IsEnabled("target") then
        if UnitCastingInfo("target") then
            self:HandleCastingEvent('UNIT_SPELLCAST_START', "target")
        elseif UnitChannelInfo("target") then
            self:HandleCastingEvent('UNIT_SPELLCAST_CHANNEL_START', "target")
        end
        ApplyAuraOffset("target")
    end
end

function CastbarModule:HandleFocusChanged()
    local frames = self.frames.focus
    local statusBar = frames.castbar
    
    if not statusBar then
        return
    end
    
    if UnitExists("focus") and statusBar.unit == UnitGUID("focus") then
        if GetTime() > (statusBar.endTime or 0) then
            self:HideCastbar("focus")
        else
            statusBar:Show()
        end
    else
        self:HideCastbar("focus")
    end
    
    HideBlizzardCastbar("focus")
    
    -- Check if new focus has active cast
    if UnitExists("focus") and IsEnabled("focus") then
        if UnitCastingInfo("focus") then
            self:HandleCastingEvent('UNIT_SPELLCAST_START', "focus")
        elseif UnitChannelInfo("focus") then
            self:HandleCastingEvent('UNIT_SPELLCAST_CHANNEL_START', "focus")
        end
        ApplyAuraOffset("focus")
    end
end

-- ============================================================================
-- CENTRALIZED SYSTEM INTEGRATION
-- ============================================================================

local function CreateCastbarAnchorFrame()
    if CastbarModule.anchor then
        return CastbarModule.anchor
    end
    
    CastbarModule.anchor = addon.CreateUIFrame(256, 16, "PlayerCastbar")
    
    if CastbarModule.anchor.editorText then
        CastbarModule.anchor.editorText:SetText("Player Castbar")
    end
    
    return CastbarModule.anchor
end

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
        CastbarModule.anchor:ClearAllPoints()
        CastbarModule.anchor:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 270)
    end
end

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
    if not InCombatLockdown() then
        self:RefreshCastbar("player")
    end
end

local function ShouldPlayerCastbarBeVisible()
    local cfg = GetConfig("player")
    return cfg and cfg.enabled
end

local function ShowPlayerCastbarTest()
    local frames = CastbarModule.frames.player
    if not frames.container then
        CreateCastbar("player")
    end
    
    if frames.container then
        frames.container:Show()
        CastbarModule:ShowCastbar("player", "Fire ball", 0.5, 1, 1.5, false, false)
    end
end

local function HidePlayerCastbarTest()
    CastbarModule:HideCastbar("player")
end

function CastbarModule:ShowCastbar(unitType, spellName, currentValue, maxValue, duration, isChanneling, isInterrupted)
    local frames = self.frames[unitType]
    if not frames.castbar then
        self:RefreshCastbar(unitType)
        frames = self.frames[unitType]
    end
    
    if not frames.castbar then
        return
    end
    
    local castbar = frames.castbar
    local currentTime = GetTime()
    
    castbar.startTime = currentTime
    castbar.endTime = currentTime + (duration or maxValue or 1)
    castbar.castingEx = not isChanneling
    castbar.channelingEx = isChanneling
    castbar.fadeOutEx = false
    castbar.selfInterrupt = false
    
    castbar:SetMinMaxValues(0, 1)
    
    local progress = maxValue > 0 and (currentValue / maxValue) or 0
    if isChanneling then
        progress = 1 - progress
    end
    castbar:SetValue(progress)
    
    if not frames.container then
        CreateCastbar(unitType)
    end
    
    frames.container:Show()
    UIFrameFadeRemoveFrame(frames.container)
    frames.container:SetAlpha(1.0)
    
    if isInterrupted then
        castbar:SetStatusBarTexture(TEXTURES.interrupted)
        local texture = castbar:GetStatusBarTexture()
        if texture then
            texture:SetVertexColor(1, 1, 1, 1)
        end
        castbar:SetStatusBarColor(1, 0, 0, 1)
        SetCastText(unitType, "Interrupted")
        castbar.selfInterrupt = true
    else
        if isChanneling then
            castbar:SetStatusBarTexture(TEXTURES.channel)
            local texture = castbar:GetStatusBarTexture()
            if texture then
                texture:SetVertexColor(1, 1, 1, 1)
            end
            castbar:SetStatusBarColor(0, 1, 0, 1)
        else
            castbar:SetStatusBarTexture(TEXTURES.standard)
            local texture = castbar:GetStatusBarTexture()
            if texture then
                texture:SetVertexColor(1, 1, 1, 1)
            end
            castbar:SetStatusBarColor(1, 0.7, 0, 1)
        end
        SetCastText(unitType, spellName)
    end
    
    if frames.textBackground then
        frames.textBackground:Show()
    end
    
    ForceStatusBarLayer(castbar)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local function InitializeCastbarForEditor()
    CreateCastbarAnchorFrame()
    
    addon:RegisterEditableFrame({
        name = "PlayerCastbar",
        frame = CastbarModule.anchor,
        configPath = {"widgets", "playerCastbar"},
        hasTarget = ShouldPlayerCastbarBeVisible,
        showTest = ShowPlayerCastbarTest,
        hideTest = HidePlayerCastbarTest,
        onHide = function()
            CastbarModule:UpdateWidgets()
        end,
        LoadDefaultSettings = function()
            CastbarModule:LoadDefaultSettings()
        end,
        UpdateWidgets = function()
            CastbarModule:UpdateWidgets()
        end
    })
    
    CastbarModule.initialized = true
end

local function OnEvent(self, event, unit, ...)
    if event == 'UNIT_AURA' and unit == 'target' then
        local cfg = GetConfig("target")
        if cfg and cfg.enabled and cfg.autoAdjust then
            addon.core:ScheduleTimer(function() ApplyAuraOffset("target") end, 0.05)
        end
    elseif event == 'UNIT_AURA' and unit == 'focus' then
        local cfg = GetConfig("focus")
        if cfg and cfg.enabled and cfg.autoAdjust then
            addon.core:ScheduleTimer(function() ApplyAuraOffset("focus") end, 0.05)
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

-- Initialize event frame
local eventFrame = CreateFrame('Frame', 'DragonUICastbarEventHandler')
local events = {
    'PLAYER_ENTERING_WORLD',
    'UNIT_SPELLCAST_START',
    'UNIT_SPELLCAST_DELAYED',
    'UNIT_SPELLCAST_STOP',
    'UNIT_SPELLCAST_FAILED',
    'UNIT_SPELLCAST_INTERRUPTED',
    'UNIT_SPELLCAST_CHANNEL_START',
    'UNIT_SPELLCAST_CHANNEL_STOP',
    'UNIT_SPELLCAST_CHANNEL_UPDATE',
    'UNIT_AURA',
    'PLAYER_TARGET_CHANGED',
    'PLAYER_FOCUS_CHANGED'
}

for _, event in ipairs(events) do
    eventFrame:RegisterEvent(event)
end

eventFrame:SetScript('OnEvent', OnEvent)

-- Hook native WoW aura positioning
if TargetFrameSpellBar then
    hooksecurefunc('Target_Spellbar_AdjustPosition', function()
        local cfg = GetConfig("target")
        if cfg and cfg.enabled and cfg.autoAdjust then
            addon.core:ScheduleTimer(function() ApplyAuraOffset("target") end, 0.05)
        end
    end)
end

-- Disable Blizzard's own hiding logic
if TargetFrameSpellBar then
    TargetFrameSpellBar:SetScript("OnHide", nil)
    TargetFrameSpellBar:SetScript("OnShow", function(self)
        local cfg = GetConfig("target")
        if cfg and cfg.enabled then
            self:Hide()
        end
    end)
end

-- Initialize centralized system
InitializeCastbarForEditor()

-- Load settings when addon is ready
local readyFrame = CreateFrame("Frame")
readyFrame:RegisterEvent("ADDON_LOADED")
readyFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "DragonUI" then
        if CastbarModule.UpdateWidgets then
            CastbarModule:UpdateWidgets()
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)