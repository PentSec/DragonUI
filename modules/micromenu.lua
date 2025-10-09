--[[
    DragonUI MicroMenu Module
    Refactored version maintaining all functionality with better organization
    Now with module enable/disable system

    -- MODULAR VERSION FOR VANILLA & ASCENSION --
]]
local addon = select(2, ...);
local config = addon.config;

-- ============================================================================
-- SERVER DETECTION & MODULE STATE
-- ============================================================================

-- Detect if we are on an Ascension server by checking for one of its custom buttons.
-- This is the most reliable method.
local isAscensionServer = (_G.PathToAscensionMicroButton ~= nil)

local MicromenuModule = {
    initialized = false,
    applied = false,
    originalStates = {}, -- Store original states for restoration
    registeredEvents = {}, -- Track registered events
    hooks = {}, -- Track hooked functions
    stateDrivers = {}, -- Track state drivers
    frames = {}, -- Track created frames
    originalHandlers = {}, -- Store original button handlers
    originalSetPoints = {}, -- Store original SetPoint functions
    originalCVars = {}, -- Store original CVar values
    eventFrames = {} -- Track event handler frames
}

-- ============================================================================
-- CONFIGURATION FUNCTIONS
-- ============================================================================

local function GetModuleConfig()
    return addon.db and addon.db.profile and addon.db.profile.modules and addon.db.profile.modules.micromenu
end

local function IsModuleEnabled()
    local cfg = GetModuleConfig()
    return cfg and cfg.enabled
end

-- ============================================================================
-- SECTION 1: LOCALS AND CONSTANTS
-- ============================================================================

local pairs = pairs;
local gsub = string.gsub;
local UIParent = UIParent;
local hooksecurefunc = hooksecurefunc;
local _G = _G;

-- Performance constants
local PERFORMANCEBAR_LOW_LATENCY = 300;
local PERFORMANCEBAR_MEDIUM_LATENCY = 600;

-- Frame references
local MainMenuBarBackpackButton = _G.MainMenuBarBackpackButton;
local HelpMicroButton = _G.HelpMicroButton;
local KeyRingButton = _G.KeyRingButton;

-- Button collections (dynamically set based on server)
local MICRO_BUTTONS

if isAscensionServer then
    MICRO_BUTTONS = {
        _G.CharacterMicroButton,
        _G.SpellbookMicroButton,
        _G.TalentMicroButton,
        _G.AchievementMicroButton,
        _G.QuestLogMicroButton,
        _G.SocialsMicroButton,
        _G.LFDMicroButton,
        _G.PathToAscensionMicroButton,
        _G.ChallengesMicroButton,
        _G.MainMenuMicroButton,
        _G.HelpMicroButton
    }
else
    MICRO_BUTTONS = {
        _G.CharacterMicroButton,
        _G.SpellbookMicroButton,
        _G.TalentMicroButton,
        _G.AchievementMicroButton,
        _G.QuestLogMicroButton,
        _G.SocialsMicroButton,
        _G.LFDMicroButton,
        _G.CollectionsMicroButton,
        _G.PVPMicroButton,
        _G.MainMenuMicroButton,
        _G.HelpMicroButton
    }
end


local bagslots = {_G.CharacterBag0Slot, _G.CharacterBag1Slot, _G.CharacterBag2Slot, _G.CharacterBag3Slot};

-- State tracking
local originalBlizzardHandlers = {}
local bags_initialized = false
local MainMenuMicroButtonMixin = {};

-- ============================================================================
-- SECTION 2: ATLAS COORDINATES
-- ============================================================================

local MicromenuAtlas = {
    ["UI-HUD-MicroMenu-Achievements-Disabled"] = {0.000976562, 0.0634766, 0.00195312, 0.162109},
    ["UI-HUD-MicroMenu-Achievements-Down"] = {0.000976562, 0.0634766, 0.166016, 0.326172},
    ["UI-HUD-MicroMenu-Achievements-Mouseover"] = {0.000976562, 0.0634766, 0.330078, 0.490234},
    ["UI-HUD-MicroMenu-Achievements-Up"] = {0.000976562, 0.0634766, 0.494141, 0.654297},

    ["UI-HUD-MicroMenu-GameMenu-Disabled"] = {0.129883, 0.192383, 0.330078, 0.490234},
    ["UI-HUD-MicroMenu-GameMenu-Down"] = {0.129883, 0.192383, 0.494141, 0.654297},
    ["UI-HUD-MicroMenu-GameMenu-Mouseover"] = {0.129883, 0.192383, 0.658203, 0.818359},
    ["UI-HUD-MicroMenu-GameMenu-Up"] = {0.129883, 0.192383, 0.822266, 0.982422},

    ["UI-HUD-MicroMenu-Groupfinder-Disabled"] = {0.194336, 0.256836, 0.00195312, 0.162109},
    ["UI-HUD-MicroMenu-Groupfinder-Down"] = {0.194336, 0.256836, 0.166016, 0.326172},
    ["UI-HUD-MicroMenu-Groupfinder-Mouseover"] = {0.194336, 0.256836, 0.330078, 0.490234},
    ["UI-HUD-MicroMenu-Groupfinder-Up"] = {0.194336, 0.256836, 0.494141, 0.654297},

    ["UI-HUD-MicroMenu-GuildCommunities-Disabled"] = {0.194336, 0.256836, 0.658203, 0.818359},
    ["UI-HUD-MicroMenu-GuildCommunities-Down"] = {0.194336, 0.256836, 0.822266, 0.982422},
    ["UI-HUD-MicroMenu-GuildCommunities-Mouseover"] = {0.258789, 0.321289, 0.658203, 0.818359},
    ["UI-HUD-MicroMenu-GuildCommunities-Up"] = {0.258789, 0.321289, 0.822266, 0.982422},

    ["UI-HUD-MicroMenu-Questlog-Disabled"] = {0.323242, 0.385742, 0.494141, 0.654297},
    ["UI-HUD-MicroMenu-Questlog-Down"] = {0.323242, 0.385742, 0.658203, 0.818359},
    ["UI-HUD-MicroMenu-Questlog-Mouseover"] = {0.323242, 0.385742, 0.822266, 0.982422},
    ["UI-HUD-MicroMenu-Questlog-Up"] = {0.387695, 0.450195, 0.00195312, 0.162109},

    ["UI-HUD-MicroMenu-SpecTalents-Disabled"] = {0.387695, 0.450195, 0.822266, 0.982422},
    ["UI-HUD-MicroMenu-SpecTalents-Down"] = {0.452148, 0.514648, 0.00195312, 0.162109},
    ["UI-HUD-MicroMenu-SpecTalents-Mouseover"] = {0.452148, 0.514648, 0.166016, 0.326172},
    ["UI-HUD-MicroMenu-SpecTalents-Up"] = {0.452148, 0.514648, 0.330078, 0.490234},

    ["UI-HUD-MicroMenu-SpellbookAbilities-Disabled"] = {0.452148, 0.514648, 0.494141, 0.654297},
    ["UI-HUD-MicroMenu-SpellbookAbilities-Down"] = {0.452148, 0.514648, 0.658203, 0.818359},
    ["UI-HUD-MicroMenu-SpellbookAbilities-Mouseover"] = {0.452148, 0.514648, 0.822266, 0.982422},
    ["UI-HUD-MicroMenu-SpellbookAbilities-Up"] = {0.516602, 0.579102, 0.00195312, 0.162109},

    ["UI-HUD-MicroMenu-Shop-Disabled"] = {0.387695, 0.450195, 0.166016, 0.326172},
    ["UI-HUD-MicroMenu-Shop-Down"] = {0.387695, 0.450195, 0.494141, 0.654297},
    ["UI-HUD-MicroMenu-Shop-Mouseover"] = {0.387695, 0.450195, 0.330078, 0.490234},
    ["UI-HUD-MicroMenu-Shop-Up"] = {0.387695, 0.450195, 0.658203, 0.818359}
}

-- Add server-specific atlas data
if isAscensionServer then
    MicromenuAtlas["UI-HUD-MicroMenu-Challenges-Disabled"] = {0.000976562, 0.0634766, 0.658203, 0.818359}
    MicromenuAtlas["UI-HUD-MicroMenu-Challenges-Down"] = {0.000976562, 0.0634766, 0.822266, 0.982422}
    MicromenuAtlas["UI-HUD-MicroMenu-Challenges-Mouseover"] = {0.0654297, 0.12793, 0.00195312, 0.162109}
    MicromenuAtlas["UI-HUD-MicroMenu-Challenges-Up"] = {0.0654297, 0.12793, 0.166016, 0.326172}
    MicromenuAtlas["UI-HUD-MicroMenu-PathToAscension-Disabled"] = {0.0654297, 0.12793, 0.658203, 0.818359}
    MicromenuAtlas["UI-HUD-MicroMenu-PathToAscension-Down"] = {0.0654297, 0.12793, 0.822266, 0.982422}
    MicromenuAtlas["UI-HUD-MicroMenu-PathToAscension-Mouseover"] = {0.129883, 0.192383, 0.00195312, 0.162109}
    MicromenuAtlas["UI-HUD-MicroMenu-PathToAscension-Up"] = {0.129883, 0.192383, 0.166016, 0.326172}
else
    MicromenuAtlas["UI-HUD-MicroMenu-Collections-Disabled"] = {0.0654297, 0.12793, 0.658203, 0.818359}
    MicromenuAtlas["UI-HUD-MicroMenu-Collections-Down"] = {0.0654297, 0.12793, 0.822266, 0.982422}
    MicromenuAtlas["UI-HUD-MicroMenu-Collections-Mouseover"] = {0.129883, 0.192383, 0.00195312, 0.162109}
    MicromenuAtlas["UI-HUD-MicroMenu-Collections-Up"] = {0.129883, 0.192383, 0.166016, 0.326172}
end


-- ============================================================================
-- SECTION 3: UTILITY FUNCTIONS (ALL ORIGINAL CODE PRESERVED)
-- ============================================================================

-- Database persistence helpers
local function GetBagCollapseState()
    if addon.db and addon.db.profile and addon.db.profile.micromenu then
        return addon.db.profile.micromenu.bags_collapsed
    end
    return false
end

local function SetBagCollapseState(collapsed)
    if addon.db and addon.db.profile and addon.db.profile.micromenu then
        addon.db.profile.micromenu.bags_collapsed = collapsed
    end
end

-- Atlas helpers
local function GetAtlasKey(buttonName)
    local buttonMap
    if isAscensionServer then
        buttonMap = {
            character = nil, -- Uses portrait
            spellbook = "UI-HUD-MicroMenu-SpellbookAbilities",
            talent = "UI-HUD-MicroMenu-SpecTalents",
            achievement = "UI-HUD-MicroMenu-Achievements",
            questlog = "UI-HUD-MicroMenu-Questlog",
            socials = "UI-HUD-MicroMenu-GuildCommunities",
            lfd = "UI-HUD-MicroMenu-Groupfinder",
            pathtoascension = "UI-HUD-MicroMenu-PathToAscension",
            challenges = "UI-HUD-MicroMenu-Challenges",
            mainmenu = "UI-HUD-MicroMenu-Shop",
            help = "UI-HUD-MicroMenu-GameMenu"
        }
    else
        buttonMap = {
            character = nil,
            spellbook = "UI-HUD-MicroMenu-SpellbookAbilities",
            talent = "UI-HUD-MicroMenu-SpecTalents",
            achievement = "UI-HUD-MicroMenu-Achievements",
            questlog = "UI-HUD-MicroMenu-Questlog",
            socials = "UI-HUD-MicroMenu-GuildCommunities",
            lfd = "UI-HUD-MicroMenu-Groupfinder",
            collections = "UI-HUD-MicroMenu-Collections",
            pvp = nil,
            mainmenu = "UI-HUD-MicroMenu-Shop",
            help = "UI-HUD-MicroMenu-GameMenu"
        }
    end
    return buttonMap[buttonName]
end

local function GetColoredTextureCoords(buttonName, textureType)
    local atlasKey = GetAtlasKey(buttonName)
    if not atlasKey then
        return nil
    end

    local coordsKey = atlasKey .. "-" .. textureType
    local coords = MicromenuAtlas[coordsKey]
    if coords and type(coords) == "table" and #coords >= 4 then
        return coords
    end
    return nil
end

-- Handler management
local function CaptureOriginalHandlers(button)
    local buttonName = button:GetName()
    if not originalBlizzardHandlers[buttonName] then
        originalBlizzardHandlers[buttonName] = {
            OnEnter = button:GetScript('OnEnter'),
            OnLeave = button:GetScript('OnLeave')
        }
    end
end

local function RestoreOriginalHandlers(button)
    local buttonName = button:GetName()
    local handlers = originalBlizzardHandlers[buttonName]
    if handlers then
        if handlers.OnEnter then
            button:SetScript('OnEnter', handlers.OnEnter)
        end
        if handlers.OnLeave then
            button:SetScript('OnLeave', handlers.OnLeave)
        end
    end
end

-- Loot animation helper
local function EnsureLootAnimationToMainBag()
    -- Simple approach: when bags are hidden, WoW should naturally redirect loot to main bag
end

-- [ALL OTHER UTILITY FUNCTIONS FROM SECTIONS 4-5 REMAIN THE SAME]
-- Including: HideUnwantedBagFrames, ScheduleHideFrames, SetupPVPButton, SetupCharacterButton, etc.
local function UpdateCharacterPortraitVisibility()
    if MicroButtonPortrait then
        if addon and addon.db and addon.db.profile and addon.db.profile.micromenu and
            addon.db.profile.micromenu.grayscale_icons then
            MicroButtonPortrait:Hide()
            MicroButtonPortrait:SetAlpha(0)
        else
            MicroButtonPortrait:Show()
            MicroButtonPortrait:SetAlpha(1)
        end
    end
end
-- ============================================================================
-- APPLY/RESTORE SYSTEM
-- ============================================================================

local function StoreOriginalMicroButtonStates()
    -- Store original positions and parents for all micro buttons
    for _, button in pairs(MICRO_BUTTONS) do
        if button then -- Check if button exists (e.g. PVPMicroButton might not)
            local buttonName = button:GetName()
            if not MicromenuModule.originalStates[buttonName] then
                MicromenuModule.originalStates[buttonName] = {
                    parent = button:GetParent(),
                    points = {},
                    size = {button:GetSize()},
                    scripts = {
                        OnEnter = button:GetScript('OnEnter'),
                        OnLeave = button:GetScript('OnLeave'),
                        OnClick = button:GetScript('OnClick'),
                        OnUpdate = button:GetScript('OnUpdate')
                    },
                    textures = {
                        normal = button:GetNormalTexture() and button:GetNormalTexture():GetTexture(),
                        pushed = button:GetPushedTexture() and button:GetPushedTexture():GetTexture(),
                        highlight = button:GetHighlightTexture() and button:GetHighlightTexture():GetTexture(),
                        disabled = button:GetDisabledTexture() and button:GetDisabledTexture():GetTexture()
                    },
                    SetPoint = button.SetPoint
                }
                -- Store all anchor points
                for i = 1, button:GetNumPoints() do
                    local point, relativeTo, relativePoint, x, y = button:GetPoint(i)
                    table.insert(MicromenuModule.originalStates[buttonName].points, {point, relativeTo, relativePoint, x, y})
                end
            end
        end
    end

    -- Store bag button states
    MicromenuModule.originalStates.MainMenuBarBackpackButton = {
        parent = MainMenuBarBackpackButton:GetParent(),
        points = {},
        size = {MainMenuBarBackpackButton:GetSize()},
        SetPoint = MainMenuBarBackpackButton.SetPoint
    }
    for i = 1, MainMenuBarBackpackButton:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = MainMenuBarBackpackButton:GetPoint(i)
        table.insert(MicromenuModule.originalStates.MainMenuBarBackpackButton.points,
            {point, relativeTo, relativePoint, x, y})
    end

    -- Store bag slots states
    for idx, bagSlot in pairs(bagslots) do
        local slotName = bagSlot:GetName()
        MicromenuModule.originalStates[slotName] = {
            parent = bagSlot:GetParent(),
            points = {},
            size = {bagSlot:GetSize()}
        }
        for i = 1, bagSlot:GetNumPoints() do
            local point, relativeTo, relativePoint, x, y = bagSlot:GetPoint(i)
            table.insert(MicromenuModule.originalStates[slotName].points, {point, relativeTo, relativePoint, x, y})
        end
    end

    -- Store KeyRingButton state
    if KeyRingButton then
        MicromenuModule.originalStates.KeyRingButton = {
            parent = KeyRingButton:GetParent(),
            points = {},
            size = {KeyRingButton:GetSize()}
        }
        for i = 1, KeyRingButton:GetNumPoints() do
            local point, relativeTo, relativePoint, x, y = KeyRingButton:GetPoint(i)
            table.insert(MicromenuModule.originalStates.KeyRingButton.points, {point, relativeTo, relativePoint, x, y})
        end
    end

    -- Store LFG frame states
    if MiniMapLFGFrame then
        MicromenuModule.originalStates.MiniMapLFGFrame = {
            points = {},
            scale = MiniMapLFGFrame:GetScale()
        }
        for i = 1, MiniMapLFGFrame:GetNumPoints() do
            local point, relativeTo, relativePoint, x, y = MiniMapLFGFrame:GetPoint(i)
            table.insert(MicromenuModule.originalStates.MiniMapLFGFrame.points, {point, relativeTo, relativePoint, x, y})
        end
    end

    -- Store LFDSearchStatus state
    if LFDSearchStatus then
        MicromenuModule.originalStates.LFDSearchStatus = {
            parent = LFDSearchStatus:GetParent(),
            points = {}
        }
        for i = 1, LFDSearchStatus:GetNumPoints() do
            local point, relativeTo, relativePoint, x, y = LFDSearchStatus:GetPoint(i)
            table.insert(MicromenuModule.originalStates.LFDSearchStatus.points, {point, relativeTo, relativePoint, x, y})
        end
    end
end

local function RestoreMicromenuSystem()
    if not MicromenuModule.applied then
        return
    end

    -- Unregister all state drivers
    for name, data in pairs(MicromenuModule.stateDrivers) do
        if data.frame then
            UnregisterStateDriver(data.frame, data.state)
        end
    end
    MicromenuModule.stateDrivers = {}

    -- Restore micro buttons to original state
    for _, button in pairs(MICRO_BUTTONS) do
        if button then
            local buttonName = button:GetName()
            local original = MicromenuModule.originalStates[buttonName]

            if original then
                -- Restore SetPoint function if it was nooped
                if original.SetPoint then
                    button.SetPoint = original.SetPoint
                end

                -- Restore parent
                if original.parent then
                    button:SetParent(original.parent)
                end

                -- Clear and restore points
                button:ClearAllPoints()
                for _, pointData in ipairs(original.points) do
                    local point, relativeTo, relativePoint, x, y = unpack(pointData)
                    if relativeTo then
                        button:SetPoint(point, relativeTo, relativePoint, x, y)
                    else
                        button:SetPoint(point, relativePoint, x, y)
                    end
                end

                -- Restore size
                if original.size then
                    button:SetSize(unpack(original.size))
                end

                -- Restore textures
                if original.textures then
                    if original.textures.normal and button:GetNormalTexture() then
                        button:GetNormalTexture():SetTexture(original.textures.normal)
                    end
                    if original.textures.pushed and button:GetPushedTexture() then
                        button:GetPushedTexture():SetTexture(original.textures.pushed)
                    end
                    if original.textures.highlight and button:GetHighlightTexture() then
                        button:GetHighlightTexture():SetTexture(original.textures.highlight)
                    end
                    if original.textures.disabled and button:GetDisabledTexture() then
                        button:GetDisabledTexture():SetTexture(original.textures.disabled)
                    end
                end

                -- Restore scripts
                if original.scripts then
                    for scriptName, scriptFunc in pairs(original.scripts) do
                        button:SetScript(scriptName, scriptFunc)
                    end
                end

                -- Clean up DragonUI custom textures
                if button.DragonUIBackground then
                    button.DragonUIBackground:Hide()
                    button.DragonUIBackground = nil
                end
                if button.DragonUIBackgroundPushed then
                    button.DragonUIBackgroundPushed:Hide()
                    button.DragonUIBackgroundPushed = nil
                end

                button.dragonUIState = nil
                button.dragonUITimer = nil
                button.dragonUILastState = nil
                button.HandleDragonUIState = nil
            end
        end
    end

    -- Restore MainMenuBarBackpackButton
    if MicromenuModule.originalStates.MainMenuBarBackpackButton then
        local original = MicromenuModule.originalStates.MainMenuBarBackpackButton

        if original.SetPoint then
            MainMenuBarBackpackButton.SetPoint = original.SetPoint
        end

        if original.parent then
            MainMenuBarBackpackButton:SetParent(original.parent)
        end

        MainMenuBarBackpackButton:ClearAllPoints()
        for _, pointData in ipairs(original.points) do
            local point, relativeTo, relativePoint, x, y = unpack(pointData)
            if relativeTo then
                MainMenuBarBackpackButton:SetPoint(point, relativeTo, relativePoint, x, y)
            else
                MainMenuBarBackpackButton:SetPoint(point, relativePoint, x, y)
            end
        end

        if original.size then
            MainMenuBarBackpackButton:SetSize(unpack(original.size))
        end
    end

    -- Restore bag slots
    for idx, bagSlot in pairs(bagslots) do
        local slotName = bagSlot:GetName()
        local original = MicromenuModule.originalStates[slotName]

        if original then
            if original.parent then
                bagSlot:SetParent(original.parent)
            end

            bagSlot:ClearAllPoints()
            for _, pointData in ipairs(original.points) do
                local point, relativeTo, relativePoint, x, y = unpack(pointData)
                if relativeTo then
                    bagSlot:SetPoint(point, relativeTo, relativePoint, x, y)
                else
                    bagSlot:SetPoint(point, relativePoint, x, y)
                end
            end

            if original.size then
                bagSlot:SetSize(unpack(original.size))
            end
        end
    end

    -- Restore KeyRingButton
    if KeyRingButton and MicromenuModule.originalStates.KeyRingButton then
        local original = MicromenuModule.originalStates.KeyRingButton

        if original.parent then
            KeyRingButton:SetParent(original.parent)
        end

        KeyRingButton:ClearAllPoints()
        for _, pointData in ipairs(original.points) do
            local point, relativeTo, relativePoint, x, y = unpack(pointData)
            if relativeTo then
                KeyRingButton:SetPoint(point, relativeTo, relativePoint, x, y)
            else
                KeyRingButton:SetPoint(point, relativePoint, x, y)
            end
        end

        if original.size then
            KeyRingButton:SetSize(unpack(original.size))
        end
    end

    -- Restore LFG frame
    if MiniMapLFGFrame and MicromenuModule.originalStates.MiniMapLFGFrame then
        local original = MicromenuModule.originalStates.MiniMapLFGFrame

        MiniMapLFGFrame:ClearAllPoints()
        for _, pointData in ipairs(original.points) do
            local point, relativeTo, relativePoint, x, y = unpack(pointData)
            if relativeTo then
                MiniMapLFGFrame:SetPoint(point, relativeTo, relativePoint, x, y)
            else
                MiniMapLFGFrame:SetPoint(point, relativePoint, x, y)
            end
        end

        if original.scale then
            MiniMapLFGFrame:SetScale(original.scale)
        end

        -- Restore border
        if MiniMapLFGFrameBorder then
            MiniMapLFGFrameBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        end
    end

    -- Restore LFDSearchStatus
    if LFDSearchStatus and MicromenuModule.originalStates.LFDSearchStatus then
        local original = MicromenuModule.originalStates.LFDSearchStatus

        if original.parent then
            LFDSearchStatus:SetParent(original.parent)
        end

        LFDSearchStatus:ClearAllPoints()
        for _, pointData in ipairs(original.points) do
            local point, relativeTo, relativePoint, x, y = unpack(pointData)
            if relativeTo then
                LFDSearchStatus:SetPoint(point, relativeTo, relativePoint, x, y)
            else
                LFDSearchStatus:SetPoint(point, relativePoint, x, y)
            end
        end
    end

    -- Hide custom frames
    if _G.pUiMicroMenu then
        _G.pUiMicroMenu:Hide()
    end
    if _G.pUiBagsBar then
        _G.pUiBagsBar:Hide()
    end
    if addon.pUiArrowManager then
        addon.pUiArrowManager:Hide()
    end

    -- Unregister all event frames
    for _, frame in pairs(MicromenuModule.eventFrames) do
        if frame and frame.UnregisterAllEvents then
            frame:UnregisterAllEvents()
        end
    end
    MicromenuModule.eventFrames = {}

    -- Clear module references
    MicromenuModule.frames = {}
    MicromenuModule.hooks = {}
    MicromenuModule.applied = false

    -- Update Blizzard UI
    if UpdateMicroButtons then
        UpdateMicroButtons()
    end
end

local function ApplyMicromenuSystem()
    if MicromenuModule.applied or not IsModuleEnabled() then
        return
    end

    -- Store original states first
    StoreOriginalMicroButtonStates()

    -- ============================================================================
    -- SECTION 4: BAG FRAME CLEANUP
    -- ============================================================================

    local function HideUnwantedBagFrames()
        -- Process all secondary bag slots
        for i, bags in pairs(bagslots) do
            local bagName = bags:GetName()

            local possibleFrames = {bagName .. "Background", bagName .. "Border", bagName .. "Frame",
                                    bagName .. "Texture", bagName .. "Highlight", bagName .. "Glow", bagName .. "Green",
                                    bagName .. "NormalTexture2", bagName .. "IconBorder", bagName .. "Flash",
                                    bagName .. "NewItemTexture", bagName .. "Shine", bagName .. "NewItemGlow"}

            for _, frameName in pairs(possibleFrames) do
                local frame = _G[frameName]
                if frame and frame.Hide then
                    frame:Hide()
                    if frame.SetAlpha then
                        frame:SetAlpha(0)
                    end
                end
            end

            -- Hide problematic texture regions
            local numRegions = bags:GetNumRegions()
            for j = 1, numRegions do
                local region = select(j, bags:GetRegions())
                if region and region:GetObjectType() == "Texture" then
                    local texture = region:GetTexture()
                    if texture then
                        local textureLower = tostring(texture):lower()
                        if textureLower:find("background") or textureLower:find("border") or textureLower:find("frame") or
                            textureLower:find("highlight") or textureLower:find("green") or textureLower:find("glow") or
                            textureLower:find("flash") or textureLower:find("shine") then
                            region:Hide()
                            if region.SetAlpha then
                                region:SetAlpha(0)
                            end
                        end
                    end
                end
            end
        end

        -- Handle KeyRing with same approach
        if KeyRingButton then
            local keyRingName = KeyRingButton:GetName()
            local possibleFrames = {keyRingName .. "Background", keyRingName .. "Border", keyRingName .. "Frame",
                                    keyRingName .. "Texture", keyRingName .. "Highlight", keyRingName .. "Glow",
                                    keyRingName .. "Green", keyRingName .. "NormalTexture2",
                                    keyRingName .. "IconBorder", keyRingName .. "Flash", keyRingName .. "Shine",
                                    keyRingName .. "NewItemGlow"}

            for _, frameName in pairs(possibleFrames) do
                local frame = _G[frameName]
                if frame and frame.Hide then
                    frame:Hide()
                    if frame.SetAlpha then
                        frame:SetAlpha(0)
                    end
                end
            end
        end
    end

    -- Frame cleanup scheduler
    local hideFramesScheduler = CreateFrame("Frame")
    local hideFramesQueue = {}

    local function ScheduleHideFrames(delay)
        local scheduleTime = GetTime() + (delay or 0)
        table.insert(hideFramesQueue, scheduleTime)

        if not hideFramesScheduler:GetScript("OnUpdate") then
            hideFramesScheduler:SetScript("OnUpdate", function(self)
                local currentTime = GetTime()
                local i = 1
                while i <= #hideFramesQueue do
                    if currentTime >= hideFramesQueue[i] then
                        HideUnwantedBagFrames()
                        table.remove(hideFramesQueue, i)
                    else
                        i = i + 1
                    end
                end

                if #hideFramesQueue == 0 then
                    self:SetScript("OnUpdate", nil)
                end
            end)
        end
    end

    -- ============================================================================
    -- SECTION 5: SPECIALIZED BUTTON SETUP
    -- ============================================================================
    local function SetupPVPButton(button)
        local microTexture = 'Interface\\AddOns\\DragonUI\\Textures\\Micromenu\\micropvp'
        local englishFaction, localizedFaction = UnitFactionGroup('player')

        if not englishFaction then
            -- Fallback to grayscale if faction not determined
            local normalTexture = button:GetNormalTexture()
            local pushedTexture = button:GetPushedTexture()
            local disabledTexture = button:GetDisabledTexture()
            local highlightTexture = button:GetHighlightTexture()

            if normalTexture then
                normalTexture:set_atlas('ui-hud-micromenu-pvp-up-2x')
            end
            if pushedTexture then
                pushedTexture:set_atlas('ui-hud-micromenu-pvp-down-2x')
            end
            if disabledTexture then
                disabledTexture:set_atlas('ui-hud-micromenu-pvp-disabled-2x')
            end
            if highlightTexture then
                highlightTexture:set_atlas('ui-hud-micromenu-pvp-mouseover-2x')
            end
            return
        end

        local coords = {}
        if englishFaction == 'Alliance' then
            coords = {0, 118 / 256, 0, 151 / 256}
        else
            coords = {118 / 256, 236 / 256, 0, 151 / 256}
        end

        -- Apply coordinates to all states
        local buttonWidth, buttonHeight = button:GetSize()

        local normalTexture = button:GetNormalTexture()
        if normalTexture then
            normalTexture:SetTexture(microTexture)
            normalTexture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            normalTexture:ClearAllPoints()
            normalTexture:SetPoint('CENTER', 0, 0)
            normalTexture:SetSize(buttonWidth, buttonHeight)
        end

        local pushedTexture = button:GetPushedTexture()
        if pushedTexture then
            pushedTexture:SetTexture(microTexture)
            pushedTexture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            pushedTexture:ClearAllPoints()
            pushedTexture:SetPoint('CENTER', 0, 0)
            pushedTexture:SetSize(buttonWidth, buttonHeight)
        end

        local disabledTexture = button:GetDisabledTexture()
        if disabledTexture then
            disabledTexture:SetTexture(microTexture)
            disabledTexture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            disabledTexture:ClearAllPoints()
            disabledTexture:SetPoint('CENTER', 0, 0)
            disabledTexture:SetSize(buttonWidth, buttonHeight)
        end

        local highlightTexture = button:GetHighlightTexture()
        if highlightTexture then
            highlightTexture:SetTexture(microTexture)
            highlightTexture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            highlightTexture:ClearAllPoints()
            highlightTexture:SetPoint('CENTER', 0, 0)
            highlightTexture:SetSize(buttonWidth, buttonHeight)
        end

        -- Add background for PVP button
        if not button.DragonUIBackground then
            local backgroundTexture = 'Interface\\AddOns\\DragonUI\\Textures\\Micromenu\\uimicromenu2x'
            local dx, dy = -1, 1
            local offX, offY = button:GetPushedTextOffset()
            local sizeX, sizeY = button:GetSize()

            local bg = button:CreateTexture('DragonUIBackground', 'BACKGROUND')
            bg:SetTexture(backgroundTexture)
            bg:SetSize(sizeX, sizeY + 1)
            bg:SetTexCoord(0.0654297, 0.12793, 0.330078, 0.490234)
            bg:SetPoint('CENTER', dx, dy)
            button.DragonUIBackground = bg

            local bgPushed = button:CreateTexture('DragonUIBackgroundPushed', 'BACKGROUND')
            bgPushed:SetTexture(backgroundTexture)
            bgPushed:SetSize(sizeX, sizeY + 1)
            bgPushed:SetTexCoord(0.0654297, 0.12793, 0.494141, 0.654297)
            bgPushed:SetPoint('CENTER', dx + offX, dy + offY)
            bgPushed:Hide()
            button.DragonUIBackgroundPushed = bgPushed

            -- Initialize state tracking properties
            button.dragonUIState = {
                pushed = false
            }
            button.dragonUITimer = 0
            button.dragonUILastState = false

            -- Create state handler
            local dx, dy = -1, 1
            local offX, offY = button:GetPushedTextOffset()

            button.HandleDragonUIState = function()
                local state = button.dragonUIState
                if state and state.pushed then
                    local subtleOffX = offX * 0.3
                    local subtleOffY = offY * 0.3
                    if button:GetNormalTexture() then
                        button:GetNormalTexture():ClearAllPoints()
                        button:GetNormalTexture():SetPoint('CENTER', subtleOffX, subtleOffY)
                        button:GetNormalTexture():SetAlpha(0.7)
                    end
                    if button.DragonUIBackground then
                        button.DragonUIBackground:Hide()
                    end
                    if button.DragonUIBackgroundPushed then
                        button.DragonUIBackgroundPushed:Show()
                    end
                else
                    if button:GetNormalTexture() then
                        button:GetNormalTexture():ClearAllPoints()
                        button:GetNormalTexture():SetPoint('CENTER', 0, 0)
                        button:GetNormalTexture():SetAlpha(1.0)
                    end
                    if button.DragonUIBackground then
                        button.DragonUIBackground:Show()
                    end
                    if button.DragonUIBackgroundPushed then
                        button.DragonUIBackgroundPushed:Hide()
                    end
                end
            end

            button:SetScript('OnUpdate', function(self, elapsed)
                -- Ensure timer is initialized
                if not self.dragonUITimer then
                    self.dragonUITimer = 0
                end

                self.dragonUITimer = self.dragonUITimer + elapsed
                if self.dragonUITimer >= 0.1 then
                    self.dragonUITimer = 0
                    local currentState = self:GetButtonState() == "PUSHED"
                    if currentState ~= self.dragonUILastState then
                        self.dragonUILastState = currentState
                        if self.dragonUIState then
                            self.dragonUIState.pushed = currentState
                        end
                        if self.HandleDragonUIState then
                            self.HandleDragonUIState()
                        end
                    end
                end
            end)

            button.HandleDragonUIState()
        end
    end
    local function SetupCharacterButton(button)
        -- PASO 1: Usar el portrait nativo de Blizzard (como RetailUI)
        local portraitTexture = MicroButtonPortrait
        portraitTexture:ClearAllPoints()
        portraitTexture:SetPoint('CENTER', button, 'CENTER', 0, -0.5) -- Sin offset
        portraitTexture:SetSize(18, 24) -- Tamaño ajustable
        portraitTexture:SetAlpha(1) -- Visible siempre

        -- PASO 2: Solo background (como otros botones)
        if not button.DragonUIBackground then
            local microTexture = 'Interface\\AddOns\\DragonUI\\Textures\\Micromenu\\uimicromenu2x'
            local dx, dy = -1, -1 -- OPRAVA: Sjednocení vertikálního posunu
            local offX, offY = button:GetPushedTextOffset()
            local sizeX, sizeY = button:GetSize()

            local bg = button:CreateTexture('DragonUIBackground', 'BACKGROUND')
            bg:SetTexture(microTexture)
            bg:SetSize(sizeX, sizeY + 1)
            bg:SetTexCoord(0.0654297, 0.12793, 0.330078, 0.490234)
            bg:SetPoint('CENTER', dx, dy)
            button.DragonUIBackground = bg

            local bgPushed = button:CreateTexture('DragonUIBackgroundPushed', 'BACKGROUND')
            bgPushed:SetTexture(microTexture)
            bgPushed:SetSize(sizeX, sizeY + 1)
            bgPushed:SetTexCoord(0.0654297, 0.12793, 0.494141, 0.654297)
            bgPushed:SetPoint('CENTER', dx + offX, dy + offY)
            bgPushed:Hide()
            button.DragonUIBackgroundPushed = bgPushed

            -- PASO 3: Initialize state tracking properties
            button.dragonUIState = {
                pushed = false
            }
            button.dragonUITimer = 0
            button.dragonUILastState = false

            button.HandleDragonUIState = function()
                local state = button.dragonUIState
                if state and state.pushed then
                    bg:Hide()
                    bgPushed:Show()
                else
                    bg:Show()
                    bgPushed:Hide()
                end
            end

            -- PASO 4: Timer simple (sin tocar el portrait)
            button:SetScript('OnUpdate', function(self, elapsed)
                -- Ensure timer is initialized
                if not self.dragonUITimer then
                    self.dragonUITimer = 0
                end

                self.dragonUITimer = self.dragonUITimer + elapsed
                if self.dragonUITimer >= 0.1 then
                    self.dragonUITimer = 0
                    local currentState = self:GetButtonState() == "PUSHED"
                    if currentState ~= self.dragonUILastState then
                        self.dragonUILastState = currentState
                        if self.dragonUIState then
                            self.dragonUIState.pushed = currentState
                        end
                        if self.HandleDragonUIState then
                            self.HandleDragonUIState()
                        end
                    end
                end
            end)

            button.HandleDragonUIState()
        end
    end

    -- ============================================================================
    -- SECTION 6: MAIN SETUP FUNCTIONS
    -- ============================================================================

    -- Create global bags bar
    _G.pUiBagsBar = CreateFrame('Frame', 'pUiBagsBar', UIParent);
    local pUiBagsBar = _G.pUiBagsBar;
    -- NO parentar automáticamente - se hará en el setup cuando sea necesario
    KeyRingButton:SetParent(_G.CharacterBag3Slot);

    function MainMenuMicroButtonMixin:bagbuttons_setup()
        -- Setup main backpack button
        MainMenuBarBackpackButton:SetSize(50, 50)
        MainMenuBarBackpackButton:SetNormalTexture(nil)
        MainMenuBarBackpackButton:SetPushedTexture(nil)
        MainMenuBarBackpackButton:SetHighlightTexture ''
        MainMenuBarBackpackButton:SetCheckedTexture ''
        MainMenuBarBackpackButton:GetHighlightTexture():set_atlas('bag-main-highlight-2x')
        MainMenuBarBackpackButton:GetCheckedTexture():set_atlas('bag-main-highlight-2x')
        MainMenuBarBackpackButtonIconTexture:set_atlas('bag-main-2x')

        -- NO posicionar MainMenuBarBackpackButton aquí si va a usar overlay - será posicionado por el overlay
        -- MainMenuBarBackpackButton:ClearAllPoints()
        -- MainMenuBarBackpackButton:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', 1, 41)

        MainMenuBarBackpackButtonCount:SetClearPoint('CENTER', MainMenuBarBackpackButton, 'BOTTOM', 0, 14)
        CharacterBag0Slot:SetClearPoint('RIGHT', MainMenuBarBackpackButton, 'LEFT', -14, -2)

        -- Setup KeyRingButton
        KeyRingButton:SetSize(34, 34)
        KeyRingButton:SetClearPoint('RIGHT', CharacterBag3Slot, 'LEFT', -4, 0)
        KeyRingButton:SetNormalTexture ''
        KeyRingButton:SetPushedTexture(nil)
        KeyRingButton:SetHighlightTexture ''
        KeyRingButton:SetCheckedTexture ''

        local highlight = KeyRingButton:GetHighlightTexture();
        highlight:SetAllPoints();
        highlight:SetBlendMode('ADD');
        highlight:SetAlpha(.4);
        highlight:set_atlas('bag-border-highlight-2x', true)
        KeyRingButton:GetNormalTexture():set_atlas('bag-reagent-border-2x')
        KeyRingButton:GetCheckedTexture():set_atlas('bag-border-highlight-2x', true)
        -- Fix KeyRing highlight sync
        local function SyncKeyRingButton()
            if KeyRingButton then
                KeyRingButton:SetChecked(IsBagOpen(-2) or false)
            end
        end

        hooksecurefunc("ToggleKeyRing", SyncKeyRingButton)
        hooksecurefunc("CloseAllBags", function()
            if KeyRingButton then
                KeyRingButton:SetChecked(false)
            end
        end)
        hooksecurefunc("ContainerFrame_OnHide", SyncKeyRingButton)

        local keyringIcon = KeyRingButtonIconTexture
        if keyringIcon then
            keyringIcon:ClearAllPoints()
            keyringIcon:SetPoint('TOPRIGHT', KeyRingButton, 'TOPRIGHT', -5, -2.9);
            keyringIcon:SetPoint('BOTTOMLEFT', KeyRingButton, 'BOTTOMLEFT', 2.9, 5);
            pcall(function()
                keyringIcon:SetTexCoord(.08, .92, .08, .92)
            end)
        end

        if KeyRingButtonCount then
            KeyRingButtonCount:SetClearPoint('CENTER', KeyRingButton, 'CENTER', 0, -10);
            KeyRingButtonCount:SetDrawLayer('OVERLAY')
        end

        -- Setup individual bag slots
        for _, bags in pairs(bagslots) do
            bags:SetHighlightTexture ''
            bags:SetCheckedTexture ''
            bags:SetPushedTexture(nil)
            bags:SetNormalTexture ''
            bags:SetSize(28, 28)

            bags:GetCheckedTexture():set_atlas('bag-border-highlight-2x', true)
            bags:GetCheckedTexture():SetDrawLayer('OVERLAY', 7)

            local highlight = bags:GetHighlightTexture();
            highlight:SetAllPoints();
            highlight:SetBlendMode('ADD');
            highlight:SetAlpha(.4);
            highlight:set_atlas('bag-border-highlight-2x', true)

            local icon = _G[bags:GetName() .. 'IconTexture']
            if icon then
                icon:ClearAllPoints()
                icon:SetPoint('TOPRIGHT', bags, 'TOPRIGHT', -5, -2.9);
                icon:SetPoint('BOTTOMLEFT', bags, 'BOTTOMLEFT', 2.9, 5);
                pcall(function()
                    icon:SetTexCoord(.08, .92, .08, .92)
                end)
            end

            if not bags.customBorder then
                bags.customBorder = bags:CreateTexture(nil, 'OVERLAY')
                bags.customBorder:SetPoint('CENTER')
                bags.customBorder:set_atlas('bag-border-2x', true)
            end

            local w, h = bags.customBorder:GetSize()
            if not bags.background then
                bags.background = bags:CreateTexture(nil, 'BACKGROUND')
                bags.background:SetSize(w, h)
                bags.background:SetPoint('CENTER')
                bags.background:SetTexture(addon._dir .. 'bagslots2x')
                bags.background:SetTexCoord(295 / 512, 356 / 512, 64 / 128, 125 / 128)
            end

            local count = _G[bags:GetName() .. 'Count']
            count:SetClearPoint('CENTER', 0, -10);
            count:SetDrawLayer('OVERLAY')
        end

        if not pUiBagsBar.registeredInEditor then
            -- Crear frame contenedor usando el sistema estándar
            local bagsFrame = addon.CreateUIFrame(210, 50, "BagsBar")

            -- Aplicar posición desde database o usar default
            local bagsConfig = addon.db and addon.db.profile.widgets and addon.db.profile.widgets.bagsbar
            if bagsConfig and bagsConfig.anchor then
                bagsFrame:SetPoint(bagsConfig.anchor or "BOTTOMRIGHT", UIParent, bagsConfig.anchor or "BOTTOMRIGHT",
                    bagsConfig.posX or 1, bagsConfig.posY or 41)
            else
                bagsFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 1, 41)

            end

            -- Asegurar que el frame de bolsas real siga al frame contenedor
            MainMenuBarBackpackButton:SetParent(UIParent)
            MainMenuBarBackpackButton:ClearAllPoints()
            MainMenuBarBackpackButton:SetPoint("CENTER", bagsFrame, "CENTER", 80, 0) -- Centrado en el overlay

            -- Hook para que las bolsas sigan al contenedor cuando se mueva
            bagsFrame:HookScript("OnDragStop", function(self)
                MainMenuBarBackpackButton:ClearAllPoints()
                MainMenuBarBackpackButton:SetPoint("CENTER", self, "CENTER", 80, 0)
            end)

            bagsFrame:HookScript("OnShow", function(self)
                MainMenuBarBackpackButton:ClearAllPoints()
                MainMenuBarBackpackButton:SetPoint("CENTER", self, "CENTER", 80, 0)
            end)

            -- Hook continuo para mantener la posición
            bagsFrame:HookScript("OnUpdate", function(self)
                if not MainMenuBarBackpackButton:GetPoint() then
                    MainMenuBarBackpackButton:ClearAllPoints()
                    MainMenuBarBackpackButton:SetPoint("CENTER", self, "CENTER", 80, 0)
                end
            end)

            addon:RegisterEditableFrame({
                name = "bagsbar",
                frame = bagsFrame,
                blizzardFrame = MainMenuBarBackpackButton,
                configPath = {"widgets", "bagsbar"},
                module = addon.BagsModule or {}
            })

            pUiBagsBar.registeredInEditor = true

        end

        EnsureLootAnimationToMainBag()
        HideUnwantedBagFrames()
        ScheduleHideFrames(0.5)
        ScheduleHideFrames(1.0)
        ScheduleHideFrames(2.0)
    end

    function MainMenuMicroButtonMixin:bagbuttons_reposition()
        CharacterBag0Slot:SetClearPoint('RIGHT', MainMenuBarBackpackButton, 'LEFT', -14, -2)

        if not GetBagCollapseState() then
            -- Expanded state
            for i, bags in pairs(bagslots) do
                bags:Show()
                bags:SetAlpha(1)
                bags:SetFrameLevel(MainMenuBarBackpackButton:GetFrameLevel())
                bags:SetScale(1.0)
                bags:SetSize(28, 28)

                if i == 1 then
                    -- Already positioned above
                elseif i == 2 then
                    bags:SetClearPoint('RIGHT', CharacterBag0Slot, 'LEFT', -4, 0)
                elseif i == 3 then
                    bags:SetClearPoint('RIGHT', CharacterBag1Slot, 'LEFT', -4, 0)
                elseif i == 4 then
                    bags:SetClearPoint('RIGHT', CharacterBag2Slot, 'LEFT', -4, 0)
                end
            end

            if KeyRingButton then
                KeyRingButton:SetClearPoint('RIGHT', CharacterBag3Slot, 'LEFT', -4, 0)
                KeyRingButton:SetFrameLevel(MainMenuBarBackpackButton:GetFrameLevel())
                KeyRingButton:SetScale(1.0)
                KeyRingButton:SetSize(34, 34)
            end
        else
            -- Collapsed state - bags behind main bag
            for i, bags in pairs(bagslots) do
                bags:Show()
                bags:SetAlpha(1)
                bags:ClearAllPoints()
                bags:SetPoint('CENTER', MainMenuBarBackpackButton, 'CENTER', 0, 0)
                bags:SetFrameLevel(MainMenuBarBackpackButton:GetFrameLevel() - 1)
            end

            if KeyRingButton then
                KeyRingButton:ClearAllPoints()
                KeyRingButton:SetPoint('CENTER', MainMenuBarBackpackButton, 'CENTER', 0, 0)
                KeyRingButton:SetFrameLevel(MainMenuBarBackpackButton:GetFrameLevel() - 1)
            end
        end
    end

    function MainMenuMicroButtonMixin:bagbuttons_refresh()
        if _G.pUiBagsBar then
            for _, bags in pairs(bagslots) do
                if bags:GetParent() ~= _G.pUiBagsBar then
                    bags:SetParent(_G.pUiBagsBar);
                end
            end
        end

        self:bagbuttons_setup();

        if HasKey() then
            KeyRingButton:Show();
        else
            KeyRingButton:Hide();
        end

        for _, bags in pairs(bagslots) do
            local icon = _G[bags:GetName() .. 'IconTexture']
            if icon then
                local empty = icon:GetTexture() == 'interface\\paperdoll\\UI-PaperDoll-Slot-Bag'
                if empty then
                    icon:SetAlpha(0)
                else
                    icon:SetAlpha(1)
                end
            end
        end

        HideUnwantedBagFrames()
        ScheduleHideFrames(0.3)
        ScheduleHideFrames(1.0)
    end

    local function setupMicroButtons(xOffset)
        local buttonxOffset = 0

        local useGrayscale = addon.db.profile.micromenu.grayscale_icons
        local configMode = useGrayscale and "grayscale" or "normal"
        local config = addon.db.profile.micromenu[configMode]

        local menuScale = config.scale_menu
        local xPosition = xOffset + config.x_position
        local yPosition = config.y_position
        local iconSpacing = config.icon_spacing

        local menu = _G.pUiMicroMenu
        if not menu then
            menu = CreateFrame('Frame', 'pUiMicroMenu', UIParent)
        end
        menu:SetScale(menuScale)
        menu:SetSize(10, 10)
        menu:ClearAllPoints()
        menu:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMRIGHT', xPosition, yPosition)

        if not menu.registeredInEditor then
            -- Create container frame
            local microMenuFrame = addon.CreateUIFrame(240, 40, "MicroMenu")

            -- Define conditional offset
            local menuXOffset = isAscensionServer and -170 or -140

            -- Apply position from widgets DB or use fallback
            local microMenuConfig = addon.db and addon.db.profile.widgets and addon.db.profile.widgets.micromenu
            if microMenuConfig and microMenuConfig.posX and microMenuConfig.posY then
                -- Use saved editor position
                microMenuFrame:SetPoint(microMenuConfig.anchor or "BOTTOMRIGHT", UIParent,
                    microMenuConfig.anchor or "BOTTOMRIGHT",
                    microMenuConfig.posX, microMenuConfig.posY)
            else
                -- Use default position only if no widget config exists
                microMenuFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT",
                    xOffset + config.x_position, config.y_position)
            end

            -- Anchor the real menu to the container frame
            menu:SetParent(UIParent)
            menu:ClearAllPoints()
            menu:SetPoint("CENTER", microMenuFrame, "CENTER", menuXOffset, -70) -- Use variable

            -- Hook for the menu to follow the container when moved
            microMenuFrame:HookScript("OnDragStop", function(self)
                menu:ClearAllPoints()
                menu:SetPoint("CENTER", self, "CENTER", menuXOffset, -70) -- Use variable
            end)

            microMenuFrame:HookScript("OnShow", function(self)
                menu:ClearAllPoints()
                menu:SetPoint("CENTER", self, "CENTER", menuXOffset, -70) -- Use variable
            end)

            -- Continuous hook to maintain position
            microMenuFrame:HookScript("OnUpdate", function(self)
                if not menu:GetPoint() then
                    menu:ClearAllPoints()
                    menu:SetPoint("CENTER", self, "CENTER", menuXOffset, -70) -- Use variable
                end
            end)

            -- Widget update function
            local function UpdateMicroMenuWidgets()
                local microMenuConfig = addon.db and addon.db.profile.widgets and addon.db.profile.widgets.micromenu
                if microMenuConfig and microMenuConfig.posX and microMenuConfig.posY then
                    microMenuFrame:ClearAllPoints()
                    microMenuFrame:SetPoint(microMenuConfig.anchor or "BOTTOMRIGHT", UIParent,
                        microMenuConfig.anchor or "BOTTOMRIGHT",
                        microMenuConfig.posX, microMenuConfig.posY)

                    -- Update real menu position
                    menu:ClearAllPoints()
                    menu:SetPoint("CENTER", microMenuFrame, "CENTER", menuXOffset, -70) -- Use variable
                end
            end

            addon:RegisterEditableFrame({
                name = "micromenu",
                frame = microMenuFrame,
                blizzardFrame = menu,
                configPath = {"widgets", "micromenu"},
                module = addon.MicroMenuModule or {},
                UpdateWidgets = UpdateMicroMenuWidgets -- Added update function
            })

            menu.registeredInEditor = true
        end

        for _, button in pairs(MICRO_BUTTONS) do
            if button then
                local buttonName = button:GetName():gsub('MicroButton', '')
                local name = string.lower(buttonName);

                CaptureOriginalHandlers(button)

                local wasEnabled = button.IsEnabled and button:IsEnabled() or true
                local wasVisible = button.IsVisible and button:IsVisible() or true

                button:texture_strip()
                CharacterMicroButton:SetDisabledTexture ''

                button:SetParent(menu)

                if useGrayscale then
                    button:SetSize(14, 19)
                else
                    button:SetSize(32, 40)
                end

                button:ClearAllPoints()
                button:SetPoint('BOTTOMLEFT', menu, 'BOTTOMRIGHT', buttonxOffset, 55)
                button.SetPoint = addon._noop
                button:SetHitRectInsets(0, 0, 0, 0)

                button:EnableMouse(true)
                if button.SetEnabled and wasEnabled then
                    button:SetEnabled(true)
                end
                if wasVisible then
                    button:Show()
                end

                local isCharacterButton = (buttonName == "Character")
                local isPVPButton = (buttonName == "PVP")

                local upCoords = not isCharacterButton and not isPVPButton and GetColoredTextureCoords(name, "Up") or nil
                local shouldUseGrayscale = useGrayscale or (not isPVPButton and not upCoords and not isCharacterButton)

                if shouldUseGrayscale then
                    -- Grayscale icons
                    local normalTexture = button:GetNormalTexture()
                    local pushedTexture = button:GetPushedTexture()
                    local disabledTexture = button:GetDisabledTexture()
                    local highlightTexture = button:GetHighlightTexture()

                    if normalTexture then
                        normalTexture:set_atlas('ui-hud-micromenu-' .. name .. '-up-2x')
                    end
                    if pushedTexture then
                        pushedTexture:set_atlas('ui-hud-micromenu-' .. name .. '-down-2x')
                    end
                    if disabledTexture then
                        disabledTexture:set_atlas('ui-hud-micromenu-' .. name .. '-disabled-2x')
                    end
                    if highlightTexture then
                        highlightTexture:set_atlas('ui-hud-micromenu-' .. name .. '-mouseover-2x')
                    end
                elseif isPVPButton then
                    SetupPVPButton(button)
                elseif isCharacterButton then
                    SetupCharacterButton(button)
                else
                    -- Colored icons
                    local microTexture = 'Interface\\AddOns\\DragonUI\\Textures\\Micromenu\\uimicromenu2x'

                    local downCoords = GetColoredTextureCoords(name, "Down")
                    local disabledCoords = GetColoredTextureCoords(name, "Disabled")
                    local mouseoverCoords = GetColoredTextureCoords(name, "Mouseover")

                    if upCoords and #upCoords >= 4 then
                        local tex = button:GetNormalTexture()
                        tex:SetTexture(microTexture)
                        tex:SetTexCoord(upCoords[1], upCoords[2], upCoords[3], upCoords[4])
                        tex:ClearAllPoints()
                        tex:SetAllPoints(button)
                    end

                    if downCoords and #downCoords >= 4 then
                        local tex = button:GetPushedTexture()
                        tex:SetTexture(microTexture)
                        tex:SetTexCoord(downCoords[1], downCoords[2], downCoords[3], downCoords[4])
                        tex:ClearAllPoints()
                        tex:SetAllPoints(button)
                    end

                    if disabledCoords and #disabledCoords >= 4 then
                        local tex = button:GetDisabledTexture()
                        tex:SetTexture(microTexture)
                        tex:SetTexCoord(disabledCoords[1], disabledCoords[2], disabledCoords[3], disabledCoords[4])
                        tex:ClearAllPoints()
                        tex:SetAllPoints(button)
                    end

                    if mouseoverCoords and #mouseoverCoords >= 4 then
                        local tex = button:GetHighlightTexture()
                        tex:SetTexture(microTexture)
                        tex:SetTexCoord(mouseoverCoords[1], mouseoverCoords[2], mouseoverCoords[3], mouseoverCoords[4])
                        tex:ClearAllPoints()
                        tex:SetAllPoints(button)
                    end

                    -- Add background
                    if not button.DragonUIBackground then
                        local backgroundTexture = 'Interface\\AddOns\\DragonUI\\Textures\\Micromenu\\uimicromenu2x'
                        local dx, dy = -1, -1
                        local offX, offY = button:GetPushedTextOffset()
                        local sizeX, sizeY = button:GetSize()

                        local bg = button:CreateTexture('DragonUIBackground', 'BACKGROUND')
                        bg:SetTexture(backgroundTexture)
                        bg:SetSize(sizeX, sizeY + 1)
                        bg:SetTexCoord(0.0654297, 0.12793, 0.330078, 0.490234)
                        bg:SetPoint('CENTER', dx, dy)
                        button.DragonUIBackground = bg

                        local bgPushed = button:CreateTexture('DragonUIBackgroundPushed', 'BACKGROUND')
                        bgPushed:SetTexture(backgroundTexture)
                        bgPushed:SetSize(sizeX, sizeY + 1)
                        bgPushed:SetTexCoord(0.0654297, 0.12793, 0.494141, 0.654297)
                        bgPushed:SetPoint('CENTER', dx + offX, dy + offY)
                        bgPushed:Hide()
                        button.DragonUIBackgroundPushed = bgPushed

                        -- Initialize state tracking properties
                        button.dragonUIState = {
                            pushed = false
                        }
                        button.dragonUITimer = 0
                        button.dragonUILastState = false

                        button.HandleDragonUIState = function()
                            local state = button.dragonUIState
                            if state and state.pushed then
                                button.DragonUIBackground:Hide()
                                button.DragonUIBackgroundPushed:Show()
                            else
                                button.DragonUIBackground:Show()
                                button.DragonUIBackgroundPushed:Hide()
                            end
                        end
                        button.HandleDragonUIState()

                        if buttonName ~= "MainMenu" then
                            button:SetScript('OnUpdate', function(self, elapsed)
                                -- Ensure timer is initialized
                                if not self.dragonUITimer then
                                    self.dragonUITimer = 0
                                end

                                self.dragonUITimer = self.dragonUITimer + elapsed
                                if self.dragonUITimer >= 0.1 then
                                    self.dragonUITimer = 0
                                    local currentState = self:GetButtonState() == "PUSHED"
                                    if currentState ~= self.dragonUILastState then
                                        self.dragonUILastState = currentState
                                        if self.dragonUIState then
                                            self.dragonUIState.pushed = currentState
                                        end
                                        if self.HandleDragonUIState then
                                            self.HandleDragonUIState()
                                        end
                                    end
                                end
                            end)
                        end
                    end
                end

                local highlightTexture = button:GetHighlightTexture()
                if highlightTexture then
                    highlightTexture:SetBlendMode('ADD')
                    highlightTexture:SetAlpha(1)
                end

                button:EnableMouse(true)
                if button.SetEnabled and wasEnabled then
                    button:SetEnabled(true)
                end

                if buttonName ~= "Character" then
                    RestoreOriginalHandlers(button)
                end

                buttonxOffset = buttonxOffset + iconSpacing
            end
        end
        UpdateCharacterPortraitVisibility()
    end

    -- ============================================================================
    -- SECTION 7: REFRESH FUNCTIONS
    -- ============================================================================

    local function updateMicroButtonSpacing()
        if not _G.pUiMicroMenu then
            return
        end

        local useGrayscale = addon.db.profile.micromenu.grayscale_icons
        local configMode = useGrayscale and "grayscale" or "normal"
        local config = addon.db.profile.micromenu[configMode]
        local iconSpacing = config.icon_spacing

        local buttonxOffset = 0
        for _, button in pairs(MICRO_BUTTONS) do
            if button then
                button:ClearAllPoints()
                button:SetPoint('BOTTOMLEFT', _G.pUiMicroMenu, 'BOTTOMRIGHT', buttonxOffset, 55)
                buttonxOffset = buttonxOffset + iconSpacing
            end
        end
    end

    function addon.RefreshMicromenuSpacing()
        updateMicroButtonSpacing()
    end

    function addon.RefreshMicromenuPosition()
    if not _G.pUiMicroMenu then
        return
    end

    local frameInfo = addon:GetEditableFrameInfo("micromenu")
    if frameInfo and frameInfo.frame then
        -- Corrected: Use widget system config instead of old one
        local microMenuConfig = addon.db and addon.db.profile.widgets and addon.db.profile.widgets.micromenu

        if microMenuConfig and microMenuConfig.posX and microMenuConfig.posY then
            -- Use saved editor position
            frameInfo.frame:ClearAllPoints()
            frameInfo.frame:SetPoint(microMenuConfig.anchor or "BOTTOMRIGHT", UIParent,
                microMenuConfig.anchor or "BOTTOMRIGHT",
                microMenuConfig.posX, microMenuConfig.posY)
        else
            -- Fallback only if no widget config
            local useGrayscale = addon.db.profile.micromenu.grayscale_icons
            local configMode = useGrayscale and "grayscale" or "normal"
            local config = addon.db.profile.micromenu[configMode]
            local xOffset = IsAddOnLoaded('ezCollections') and -180 or -166

            frameInfo.frame:ClearAllPoints()
            frameInfo.frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT",
                xOffset + config.x_position, config.y_position)
        end

        -- Define conditional offset
        local menuXOffset = isAscensionServer and -170 or -140

        -- Ensure the menu follows the container with corrected positioning
        _G.pUiMicroMenu:ClearAllPoints()
        _G.pUiMicroMenu:SetPoint("CENTER", frameInfo.frame, "CENTER", menuXOffset, -70)
    else
        -- Fallback to old method if no container
        local useGrayscale = addon.db.profile.micromenu.grayscale_icons
        local configMode = useGrayscale and "grayscale" or "normal"
        local config = addon.db.profile.micromenu[configMode]

        local microMenu = _G.pUiMicroMenu
        microMenu:SetScale(config.scale_menu)
        local xOffset = IsAddOnLoaded('ezCollections') and -180 or -166
        microMenu:ClearAllPoints()
        microMenu:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMRIGHT',
            xOffset + config.x_position, config.y_position)
    end

    updateMicroButtonSpacing()
end

    function addon.RefreshBagsPosition()
        if not _G.pUiBagsBar then
            return
        end

        local frameInfo = addon:GetEditableFrameInfo("bagsbar")
        if frameInfo and frameInfo.frame then
            -- Aplicar posición desde database o usar default
            local bagsConfig = addon.db and addon.db.profile.widgets and addon.db.profile.widgets.bagsbar
            if bagsConfig and bagsConfig.anchor then
                frameInfo.frame:ClearAllPoints()
                frameInfo.frame:SetPoint(bagsConfig.anchor or "BOTTOMRIGHT", UIParent,
                    bagsConfig.anchor or "BOTTOMRIGHT", bagsConfig.posX or 1, bagsConfig.posY or 41)
            else
                frameInfo.frame:ClearAllPoints()
                frameInfo.frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 1, 41)
            end

            -- Asegurar que las bolsas sigan al contenedor con posicionamiento corregido
            MainMenuBarBackpackButton:ClearAllPoints()
            MainMenuBarBackpackButton:SetPoint("CENTER", frameInfo.frame, "CENTER", 80, 0)
        else
            -- Fallback al método anterior si no hay contenedor
            if not addon.db or not addon.db.profile or not addon.db.profile.bags then
                return
            end

            local bagsConfig = addon.db.profile.bags
            _G.pUiBagsBar:SetScale(bagsConfig.scale)

            local originalSetPoint = MainMenuBarBackpackButton.SetPoint
            if MainMenuBarBackpackButton.SetPoint == addon._noop then
                MainMenuBarBackpackButton.SetPoint = UIParent.SetPoint
            end

            MainMenuBarBackpackButton:ClearAllPoints()
            MainMenuBarBackpackButton:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', bagsConfig.x_position,
                bagsConfig.y_position)

            if originalSetPoint == addon._noop then
                MainMenuBarBackpackButton.SetPoint = originalSetPoint
            end
        end
    end

    function addon.RefreshMicromenuVehicle()
        if not _G.pUiMicroMenu then
            return
        end

        if addon.db.profile.micromenu.hide_on_vehicle then
            RegisterStateDriver(_G.pUiMicroMenu, 'visibility', '[vehicleui] hide;show')
        else
            UnregisterStateDriver(_G.pUiMicroMenu, 'visibility')
        end
    end

    function addon.RefreshBagsVehicle()
        if not _G.pUiBagsBar then
            return
        end

        if addon.db.profile.micromenu.hide_on_vehicle then
            RegisterStateDriver(_G.pUiBagsBar, 'visibility', '[vehicleui] hide;show')
        else
            UnregisterStateDriver(_G.pUiBagsBar, 'visibility')
        end
    end

    function addon.RefreshMicromenuIcons()
        -- Icon refresh handled in main setup
    end

    function addon.RefreshMicromenu()
    if not addon.db or not addon.db.profile or not addon.db.profile.micromenu then
        return
    end

    if not _G.pUiMicroMenu then
        return
    end

    local useGrayscale = addon.db.profile.micromenu.grayscale_icons
    local configMode = useGrayscale and "grayscale" or "normal"
    local config = addon.db.profile.micromenu[configMode]

    -- CORREGIDO: Solo aplicar escala, NO posición (eso lo maneja el editor)
    _G.pUiMicroMenu:SetScale(config.scale_menu)

    -- ELIMINADO: No sobrescribir posición del editor
    -- _G.pUiMicroMenu:ClearAllPoints()
    -- _G.pUiMicroMenu:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMRIGHT', xOffset + config.x_position, config.y_position)

    addon.RefreshMicromenuIcons()

    local buttonxOffset = 0
    for _, button in pairs(MICRO_BUTTONS) do
        if button then
            local originalSetPoint = button.SetPoint
            if button.SetPoint == addon._noop then
                button.SetPoint = UIParent.SetPoint
            end

            button:ClearAllPoints()
            button:SetPoint('BOTTOMLEFT', _G.pUiMicroMenu, 'BOTTOMRIGHT', buttonxOffset, 55)

            if originalSetPoint == addon._noop then
                button.SetPoint = originalSetPoint
            end

            buttonxOffset = buttonxOffset + config.icon_spacing
        end
    end

    addon.RefreshMicromenuVehicle()
    UpdateCharacterPortraitVisibility()
end

    function addon.RefreshBags()
        if not _G.pUiBagsBar then
            return
        end

        addon.RefreshBagsPosition();

        if MainMenuMicroButtonMixin.bagbuttons_refresh then
            MainMenuMicroButtonMixin:bagbuttons_refresh();
        end

        if addon.pUiArrowManager then
            local arrow = addon.pUiArrowManager
            local isCollapsed = GetBagCollapseState()
            local normal = arrow:GetNormalTexture()
            local pushed = arrow:GetPushedTexture()
            local highlight = arrow:GetHighlightTexture()

            if isCollapsed then
                normal:set_atlas('bag-arrow-2x')
                pushed:set_atlas('bag-arrow-2x')
                highlight:set_atlas('bag-arrow-2x')
                arrow:SetChecked(true)
            else
                normal:set_atlas('bag-arrow-invert-2x')
                pushed:set_atlas('bag-arrow-invert-2x')
                highlight:set_atlas('bag-arrow-invert-2x')
                arrow:SetChecked(nil)
            end
        end

        MainMenuMicroButtonMixin:bagbuttons_reposition()
        addon.RefreshBagsVehicle();
    end

    -- ============================================================================
    -- SECTION 8: SPECIAL UI ELEMENTS
    -- ============================================================================

    -- Collapse arrow
    do
        local arrow = CreateFrame('CheckButton', 'pUiArrowManager', MainMenuBarBackpackButton)
        addon.pUiArrowManager = arrow
        arrow:SetSize(12, 18)
        arrow:SetPoint('RIGHT', MainMenuBarBackpackButton, 'LEFT', 0, -2)
        arrow:SetNormalTexture ''
        arrow:SetPushedTexture ''
        arrow:SetHighlightTexture ''
        arrow:RegisterForClicks('LeftButtonUp')

        local normal = arrow:GetNormalTexture()
        local pushed = arrow:GetPushedTexture()
        local highlight = arrow:GetHighlightTexture()

        arrow:SetScript('OnClick', function(self)
            local checked = self:GetChecked();
            if checked then
                normal:set_atlas('bag-arrow-2x')
                pushed:set_atlas('bag-arrow-2x')
                highlight:set_atlas('bag-arrow-2x')
                SetBagCollapseState(true)
                MainMenuMicroButtonMixin:bagbuttons_reposition()
            else
                normal:set_atlas('bag-arrow-invert-2x')
                pushed:set_atlas('bag-arrow-invert-2x')
                highlight:set_atlas('bag-arrow-invert-2x')
                SetBagCollapseState(false)
                MainMenuMicroButtonMixin:bagbuttons_reposition()
            end
        end)
    end

    -- LFG Frame customization
    hooksecurefunc('MiniMapLFG_UpdateIsShown', function()
        MiniMapLFGFrame:SetClearPoint('LEFT', _G.CharacterMicroButton, -32, 2)
        MiniMapLFGFrame:SetScale(1.6)
        MiniMapLFGFrameBorder:SetTexture(nil)
        MiniMapLFGFrame.eye.texture:SetTexture(addon._dir .. 'uigroupfinderflipbookeye.tga')
    end)

    MiniMapLFGFrame:SetScript('OnClick', function(self, button)
        local mode, submode = GetLFGMode();
        if (button == "RightButton" or mode == "lfgparty" or mode == "abandonedInDungeon") then
            PlaySound("igMainMenuOpen");
            local yOffset;
            if (mode == "queued") then
                MiniMapLFGFrameDropDown.point = "BOTTOMRIGHT";
                MiniMapLFGFrameDropDown.relativePoint = "TOPLEFT";
                yOffset = 105;
            else
                MiniMapLFGFrameDropDown.point = nil;
                MiniMapLFGFrameDropDown.relativePoint = nil;
                yOffset = 110;
            end
            ToggleDropDownMenu(1, nil, MiniMapLFGFrameDropDown, "MiniMapLFGFrame", -60, yOffset);
        elseif (mode == "proposal") then
            if (not LFDDungeonReadyPopup:IsShown()) then
                PlaySound("igCharacterInfoTab");
                StaticPopupSpecial_Show(LFDDungeonReadyPopup);
            end
        elseif (mode == "queued" or mode == "rolecheck") then
            ToggleLFDParentFrame();
        elseif (mode == "listed") then
            ToggleLFRParentFrame();
        end
    end)

    LFDSearchStatus:SetParent(MinimapBackdrop)
    LFDSearchStatus:SetClearPoint('TOPRIGHT', MinimapBackdrop, 'TOPLEFT')

    -- LFD Status reanchor
    local function ReanchorLFDStatus()
        if not LFDSearchStatus or not MiniMapLFGFrame then
            return
        end
        LFDSearchStatus:ClearAllPoints()
        LFDSearchStatus:SetPoint("BOTTOM", MiniMapLFGFrame, "TOP", 0, 30)
    end

    ReanchorLFDStatus()
    hooksecurefunc("LFDSearchStatus_Update", ReanchorLFDStatus)

    -- ============================================================================
    -- SECTION 9: EVENT HANDLERS
    -- ============================================================================

    addon.package:RegisterEvents(function(self, event)
        if event == 'BAG_UPDATE' then
            if HasKey() then
                if not KeyRingButton:IsShown() then
                    KeyRingButton:Show();
                end
            else
                if KeyRingButton:IsShown() then
                    KeyRingButton:Hide();
                end
            end

            ScheduleHideFrames(0.1)
        end
    end, 'BAG_UPDATE');

    addon.package:RegisterEvents(function(self, event)
        local updateFrame = CreateFrame("Frame")
        local elapsed = 0
        updateFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= 1 then
                self:SetScript("OnUpdate", nil)

                for i, bags in pairs(bagslots) do
                    local icon = _G[bags:GetName() .. 'IconTexture']
                    if icon then
                        PaperDollItemSlotButton_Update(bags)

                        local empty = icon:GetTexture() == 'interface\\paperdoll\\UI-PaperDoll-Slot-Bag'
                        if empty then
                            icon:SetAlpha(0)
                        else
                            icon:SetAlpha(1)
                        end
                    end
                end

                if KeyRingButton and HasKey() then
                    KeyRingButton:Show()
                end

                ScheduleHideFrames(0.2)
                ScheduleHideFrames(0.5)
            end
        end)
    end, 'PLAYER_ENTERING_WORLD');

    addon.package:RegisterEvents(function(self, event, bagID)
        if bagID then
            local bagSlot = bagslots[bagID + 1]
            if bagSlot then
                local icon = _G[bagSlot:GetName() .. 'IconTexture']
                if icon then
                    local empty = icon:GetTexture() == 'interface\\paperdoll\\UI-PaperDoll-Slot-Bag'
                    if empty then
                        icon:SetAlpha(0)
                    else
                        icon:SetAlpha(1)
                    end
                end
            end
        end
    end, 'BAG_UPDATE');

    addon.package:RegisterEvents(function()
        local xOffset
        if IsAddOnLoaded('ezCollections') then
            xOffset = -180
            if _G.CollectionsMicroButton then
                _G.CollectionsMicroButton:UnregisterEvent('UPDATE_BINDINGS')
            end
        else
            xOffset = -166
        end

        setupMicroButtons(xOffset);

        if addon.RefreshBags then
            addon.RefreshBags();
        end

        addon.core:ScheduleTimer(function()
            -- Verificar si los frames necesitan ser registrados
            if _G.pUiMicroMenu and not _G.pUiMicroMenu.registeredInEditor then
                -- Force re-setup to register frames
                setupMicroButtons(xOffset)
            end

            if _G.pUiBagsBar and not _G.pUiBagsBar.registeredInEditor then
                -- Force bags setup
                if MainMenuMicroButtonMixin.bagbuttons_setup then
                    MainMenuMicroButtonMixin:bagbuttons_setup()
                end
            end
        end, 0.5)
    end, 'PLAYER_LOGIN');

    -- Mark as applied
    MicromenuModule.applied = true

    -- Execute the main setup
    local xOffset
    if IsAddOnLoaded('ezCollections') then
        xOffset = -180
        if _G.CollectionsMicroButton then
            _G.CollectionsMicroButton:UnregisterEvent('UPDATE_BINDINGS')
        end
    else
        xOffset = -166
    end

    setupMicroButtons(xOffset)

    if MainMenuMicroButtonMixin.bagbuttons_setup then
        MainMenuMicroButtonMixin:bagbuttons_setup()
    end

    if addon.RefreshBags then
        addon.RefreshBags()
    end

    if addon.RefreshMicromenu then
        addon.RefreshMicromenu()
    end

    -- Setup all hooks
    if not MicromenuModule.hooks.MiniMapLFG_UpdateIsShown then
        MicromenuModule.hooks.MiniMapLFG_UpdateIsShown = true
        hooksecurefunc('MiniMapLFG_UpdateIsShown', function()
            if IsModuleEnabled() then
                MiniMapLFGFrame:SetClearPoint('LEFT', _G.CharacterMicroButton, -32, 2)
                MiniMapLFGFrame:SetScale(1.6)
                MiniMapLFGFrameBorder:SetTexture(nil)
                MiniMapLFGFrame.eye.texture:SetTexture(addon._dir .. 'uigroupfinderflipbookeye.tga')
            end
        end)
    end

    -- Register all events
    local eventFrame1 = MicromenuModule.eventFrames.bagUpdate or CreateFrame("Frame")
    MicromenuModule.eventFrames.bagUpdate = eventFrame1
    addon.package:RegisterEvents(function(self, event)
        if IsModuleEnabled() then
            if event == 'BAG_UPDATE' then
                if HasKey() then
                    if not KeyRingButton:IsShown() then
                        KeyRingButton:Show()
                    end
                else
                    if KeyRingButton:IsShown() then
                        KeyRingButton:Hide()
                    end
                end
                ScheduleHideFrames(0.1)
            end
        end
    end, 'BAG_UPDATE')

    local eventFrame2 = MicromenuModule.eventFrames.playerEntering or CreateFrame("Frame")
    MicromenuModule.eventFrames.playerEntering = eventFrame2
    addon.package:RegisterEvents(function(self, event)
        if IsModuleEnabled() then
            local updateFrame = CreateFrame("Frame")
            local elapsed = 0
            updateFrame:SetScript("OnUpdate", function(self, dt)
                elapsed = elapsed + dt
                if elapsed >= 1 then
                    self:SetScript("OnUpdate", nil)

                    for i, bags in pairs(bagslots) do
                        local icon = _G[bags:GetName() .. 'IconTexture']
                        if icon then
                            PaperDollItemSlotButton_Update(bags)

                            local empty = icon:GetTexture() == 'interface\\paperdoll\\UI-PaperDoll-Slot-Bag'
                            if empty then
                                icon:SetAlpha(0)
                            else
                                icon:SetAlpha(1)
                            end
                        end
                    end

                    if KeyRingButton and HasKey() then
                        KeyRingButton:Show()
                    end

                    ScheduleHideFrames(0.2)
                    ScheduleHideFrames(0.5)
                end
            end)
        end
    end, 'PLAYER_ENTERING_WORLD')
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function addon.RefreshMicromenuSystem()
    if IsModuleEnabled() then
        if not MicromenuModule.applied then
            ApplyMicromenuSystem()
        end
        -- Refresh settings if already applied
        if addon.RefreshMicromenu then
            addon.RefreshMicromenu()
        end
        if addon.RefreshBags then
            addon.RefreshBags()
        end
    else
        RestoreMicromenuSystem()
    end
end

-- Keep all the existing refresh functions as they are
-- They will only work when the module is enabled
-- ============================================================================
-- Función para cargar configuración por defecto de widgets
-- ============================================================================

-- Añadir esta función cerca del final del archivo, antes de la inicialización:

local function LoadDefaultWidgetSettings()
    -- Asegurar que existe la configuración de widgets
    if not addon.db.profile.widgets then
        addon.db.profile.widgets = {}
    end

    if not addon.db.profile.widgets.micromenu then
        -- Calcular posición por defecto basada en configuración actual
        local useGrayscale = addon.db.profile.micromenu and addon.db.profile.micromenu.grayscale_icons
        local configMode = useGrayscale and "grayscale" or "normal"
        local config = addon.db.profile.micromenu and addon.db.profile.micromenu[configMode]

        if config then
            local xOffset = IsAddOnLoaded('ezCollections') and -180 or -166
            addon.db.profile.widgets.micromenu = {
                anchor = "BOTTOMRIGHT",
                posX = xOffset + config.x_position,
                posY = config.y_position
            }
        else
            -- Fallback absoluto
            addon.db.profile.widgets.micromenu = {
                anchor = "BOTTOMRIGHT",
                posX = -166,
                posY = 4
            }
        end
    end
end
-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local function Initialize()
    if MicromenuModule.initialized then
        return
    end

    -- AÑADIDO: Cargar configuración por defecto de widgets
    LoadDefaultWidgetSettings()

    -- Solo apply if module is enabled
    if IsModuleEnabled() then
        -- Wait for PLAYER_LOGIN to apply system
        addon.package:RegisterEvents(function()
            ApplyMicromenuSystem()
        end, 'PLAYER_LOGIN')
    end

    MicromenuModule.initialized = true
end

-- Auto-initialize when addon loads
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "DragonUI" then
        Initialize()
        self:UnregisterAllEvents()
    end
end)
