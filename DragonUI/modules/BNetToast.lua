local addon = select(2, ...)

--[[
==============================================================================
BNet Toast Module for DragonUI
Friend online/offline notifications via Battle.net toasts and/or chat messages.
Configurable: toast popup, chat notifications, toon name display, zone display.

Ascension WoW notes:
- BNet friends appear in the WoW friend list (not BNet list).
- GetFriendInfo returns: name=bnetName, level=bnetID, class="Unknown",
  area="Unknown Added as: (ToonName)".
- Real level/class/zone are NOT available from any API.
- The only extra data we can extract is the toon name from the area field.
==============================================================================
]]

local gmatch = string.gmatch
local gsub = string.gsub
local CreateFrame = CreateFrame
local GetFriendInfo = GetFriendInfo
local GetNumFriends = GetNumFriends
local PlaySound = PlaySound
local strmatch = string.match

-- Patterns to extract friend name from system messages
local pattern1 = ERR_FRIEND_ONLINE_SS:gsub("%%s", "(%.+)"):gsub("%[", "%%["):gsub("%]","%%]")
local pattern2 = ERR_FRIEND_OFFLINE_S:gsub("%%s", "(%.+)"):gsub("%[", "%%["):gsub("%]","%%]")

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local BNetToastModule = {
    initialized = false,
    applied = false,
    originalStates = {},
    hooks = {},
    frames = {},
}

-- Register with ModuleRegistry
if addon.RegisterModule then
    addon:RegisterModule("bnettoast", BNetToastModule,
        (addon.L and addon.L["BNet Toast"]) or "BNet Toast",
        (addon.L and addon.L["Friend online/offline notifications with Battle.net toasts and chat messages"]) or "Friend online/offline notifications with Battle.net toasts and chat messages")
end

-- ============================================================================
-- CONFIGURATION ACCESSORS
-- ============================================================================

local function GetModuleConfig()
    return addon:GetModuleConfig("bnettoast")
end

local function IsModuleEnabled()
    return addon:IsModuleEnabled("bnettoast")
end

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Strip hyperlink formatting from a captured friend name to get the plain name.
--- e.g. "|Hplayer:Test-Realm:0:WHISPER|h[Test]|h" -> "Test"
local function GetCleanName(rawName)
    if not rawName then return nil end
    local plain = strmatch(rawName, "%[(.+)%]")
    if plain then return plain end
    return rawName
end

--- Look up a friend in the WoW friend list and return Ascension-specific data.
--- On Ascension, GetFriendInfo returns:
---   name = BNet display name (e.g. "Tempok")
---   level = BNet presenceID (e.g. 47709784) — NOT a real level
---   class = "Unknown"
---   area = "Unknown Added as: (ToonName)" — toon name is hidden here
---
--- Returns: bnetName, bnetID, toonName, realLevel(nil), realClass(nil), realZone(nil), connected
--- On non-Ascension servers, returns standard: name, nil, nil, level, class, area, connected
local function FindFriendInfo(friendName)
    local clean = GetCleanName(friendName)
    if not clean then return end

    for i = 1, GetNumFriends() do
        local name, level, class, area, connected = GetFriendInfo(i)
        if name and (name == clean or name == friendName) then
            -- Detect Ascension: class="Unknown" and area matches "Added as:" pattern
            local toonFromArea = strmatch(area or "", "Added as: %((.+)%)")

            if toonFromArea then
                -- Ascension server: extract toon name from area field
                -- Real level/class/zone are not available from any API
                local bnetID = tonumber(level) -- On Ascension, "level" is actually the BNet ID
                return name, bnetID, toonFromArea, nil, nil, nil, connected
            end

            -- Standard WoW server: return normal data
            return name, nil, nil, level, class, area, connected
        end
    end
end

-- ============================================================================
-- FRIEND LIST LOOKUP
-- ============================================================================

--- Cache of friend names for O(1) lookup. Built on FRIENDLIST_UPDATE.
---
--- On Ascension the guild roster only ever contains members currently online
--- (a live snapshot), so it cannot be used to reliably detect guild members.
--- However, guild member online/offline broadcasts arrive as CHAT_MSG_SYSTEM
--- messages for people who are NOT in the friend list. The friend list is the
--- authoritative "real friends" set, so with guild_notify OFF we show a
--- notification ONLY when the name is in the friend list — everything else is
--- a guild broadcast and gets suppressed.
local friendNameCache = nil

local function BuildFriendNameCache()
    friendNameCache = {}
    local num = GetNumFriends()
    for i = 1, num do
        local name = GetFriendInfo(i)
        if name then
            friendNameCache[name] = true
        end
    end
end

local function IsFriend(friendName)
    if not friendNameCache then return false end
    local clean = GetCleanName(friendName)
    if not clean then return false end
    return friendNameCache[clean] == true
end

-- ============================================================================
-- BROADCAST INPUT HANDLER
-- ============================================================================

local function BroadcastOnEnterPressed(self)
    local broadcastText = self:GetText()
    if GetNumFriends() < 1 then return end

    local numButtons = #FriendsFrameFriendsScrollFrame.buttons
    for i = 1, numButtons do
        local friend = _G["FriendsFrameFriendsScrollFrameButton" .. i]
        if friend.id and friend.buttonType == FRIENDS_BUTTON_TYPE_WOW then
            local name, level, class, zone, connected, status, note = GetFriendInfo(friend.id)
            if connected then
                SendChatMessage(broadcastText, "WHISPER", nil, name)
            end
        end
    end
    self:SetText("")
end

-- ============================================================================
-- TOAST CLICK HANDLER
-- ============================================================================

local function OnToastClick(self, btn, ...)
    local toastType = BNToastFrame.toastType
    local toastData = BNToastFrame.toastData
    local presenceID, givenName, surname = BNGetFriendInfoByID(toastData)

    if btn == "LeftButton" then
        if toastType == 1 then
            BNToastFrame:Hide()
            DropDownList1:Hide()
            ChatFrame_SendTell(givenName)
        end
    elseif btn == "RightButton" then
        local name, level, class, area, connected = GetFriendInfo(givenName)
        PlaySound("igMainMenuOptionCheckBoxOn")
        if name then
            FriendsFrame_ShowDropdown(name, connected, nil, nil, nil, 1)
        else
            FriendsFrame_ShowDropdown(givenName, 1)
        end
    end
end

-- ============================================================================
-- BNGetFriendInfoByID OVERRIDE
-- ============================================================================

local function OverrideBNGetFriendInfoByID(id)
    return nil, id, ""
end

-- ============================================================================
-- INLINE ICONS (textures from Blizzard's FriendsFrame.lua / FriendsFrame.xml)
-- ============================================================================

-- Official Blizzard constants from FriendsFrame.lua:
-- FRIENDS_TEXTURE_ONLINE  = "Interface\\FriendsFrame\\StatusIcon-Online"
-- FRIENDS_TEXTURE_OFFLINE = "Interface\\FriendsFrame\\StatusIcon-Offline"
-- FRIENDS_BNET_NAME_COLOR = {r=0.510, g=0.773, b=1.0}  -> #82C5FF
-- FRIENDS_WOW_NAME_COLOR  = {r=0.996, g=0.882, b=0.361} -> #FDE05C

-- Status icons (16x16 native, no UV coords — full texture renders clean)
local ICON_ONLINE  = "|TInterface\\FriendsFrame\\StatusIcon-Online:14:14|t"
local ICON_OFFLINE = "|TInterface\\FriendsFrame\\StatusIcon-Offline:14:14|t"

-- PlusManz-PlusManz is 64x64, used at 32x32 in FriendsFrame.xml with no UV coords
-- At 14px it scales down the full texture (2x2 friend grid, shows one face)
local ICON_FRIEND  = "|TInterface\\FriendsFrame\\PlusManz-PlusManz:14:14|t"

-- ============================================================================
-- CHAT NOTIFICATION
-- ============================================================================

local function BuildFriendOnlineMessage(bnetName, toonName)
    -- Colors from Blizzard's FriendsFrame.lua
    local C = "|cff82c5ff" -- FRIENDS_BNET_NAME_COLOR (#82C5FF)
    local G = "|cff88FF88" -- Green for online text
    local Y = "|cffFDE05C" -- FRIENDS_WOW_NAME_COLOR (#FDE05C) for toon name
    local R = "|r"

    local msg = ICON_ONLINE .. ICON_FRIEND .. " "
        .. C .. bnetName .. R
        .. " " .. C .. "Added as:" .. R
        .. " " .. Y .. "(" .. toonName .. ")" .. R
        .. " " .. C .. "has come " .. G .. "online" .. R .. "."

    return msg
end

local function BuildFriendOfflineMessage(bnetName, toonName)
    local C = "|cff82c5ff" -- FRIENDS_BNET_NAME_COLOR (#82C5FF)
    local RED = "|cffFF4444" -- Red for offline text
    local Y = "|cffFDE05C" -- FRIENDS_WOW_NAME_COLOR (#FDE05C) for toon name
    local R = "|r"

    local msg = ICON_OFFLINE .. ICON_FRIEND .. " "
        .. C .. bnetName .. R
        .. " " .. C .. "Added as:" .. R
        .. " " .. Y .. "(" .. toonName .. ")" .. R
        .. " " .. C .. "has gone " .. RED .. "offline" .. R .. "."

    return msg
end

local function SendChatNotification(name, isOnline)
    local config = GetModuleConfig()
    if not name then return end

    local bnetName, bnetID, toonName, realLevel, realClass, realZone, connected = FindFriendInfo(name)

    -- Always use the toon name (the name they were added as) as the display name
    -- Fall back to bnetName if we couldn't parse the toon name
    local displayName = toonName or bnetName or name

    local msg
    if isOnline then
        msg = BuildFriendOnlineMessage(bnetName or name, displayName)
    else
        msg = BuildFriendOfflineMessage(bnetName or name, displayName)
    end

    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

-- ============================================================================
-- EVENT HANDLER
-- ============================================================================

local eventFrame

local function OnSystemMessage(self, event, arg1, ...)
    -- FRIENDLIST_UPDATE: rebuild the friend name cache.
    if event == "FRIENDLIST_UPDATE" then
        BuildFriendNameCache()
        return
    end

    local config = GetModuleConfig()
    if not config then return end

    -- Friend came online
    local name = arg1:gmatch(pattern1)()
    if name then
        -- Guild filter: with guild_notify OFF, show ONLY friends. On Ascension
        -- every other "X has come online" is a guild broadcast.
        if config.guild_notify == false and not IsFriend(name) then
            return
        end
        if config.show_toast ~= false then
            BNToastFrame_AddToast(1, name)
        end
        if config.show_chat ~= false then
            SendChatNotification(name, true)
        end
        return
    end

    -- Friend went offline
    name = arg1:gmatch(pattern2)()
    if name then
        if config.guild_notify == false and not IsFriend(name) then
            return
        end
        if config.show_toast ~= false then
            BNToastFrame_AddToast(2, name)
        end
        if config.show_chat ~= false then
            SendChatNotification(name, false)
        end
    end
end

-- ============================================================================
-- CHAT FILTER
-- ============================================================================

local function SystemMessageFilter(self, event, arg1, ...)
    local name = arg1:gmatch(pattern1)() or arg1:gmatch(pattern2)()
    if name then
        return true
    end
end

-- ============================================================================
-- APPLY / RESTORE
-- ============================================================================

-- Forward declarations (defined in EDITOR MODE SUPPORT section below)
local SetupToastEditorAnchor

local function ApplyBNetToast()
    if BNetToastModule.applied then return end
    local orig = BNetToastModule.originalStates

    -- 1. Override BNGetFriendInfoByID
    if not orig.BNGetFriendInfoByID then
        orig.BNGetFriendInfoByID = _G.BNGetFriendInfoByID
    end
    _G.BNGetFriendInfoByID = OverrideBNGetFriendInfoByID

    -- 2. Override broadcast input handler
    if not orig.broadcastHandler then
        orig.broadcastHandler = FriendsFrameBroadcastInput:GetScript("OnEnterPressed")
    end

    -- Save original position before repositioning
    if not orig.broadcastPoint then
        orig.broadcastPoint = { FriendsFrameBroadcastInput:GetPoint() }
    end

    FriendsFrameBroadcastInput:SetScript("OnEnterPressed", BroadcastOnEnterPressed)
    FriendsFrameBroadcastInput:Show()

    -- Reposition broadcast input to the right of FriendsTabHeader
    FriendsFrameBroadcastInput:ClearAllPoints()
    FriendsFrameBroadcastInput:SetPoint("LEFT", FriendsTabHeaderTab2, "RIGHT", 20, -5)
    FriendsFrameBroadcastInput:SetWidth(150)

    -- Prevent broadcast input from being hidden
    if not orig.broadcastHide then
        orig.broadcastHide = FriendsFrameBroadcastInput.Hide
    end
    FriendsFrameBroadcastInput.Hide = function() end

    -- 3. Override toast click handler
    if not orig.toastClickHandler then
        orig.toastClickHandler = BNToastFrameClickFrame:GetScript("OnClick")
    end
    BNToastFrameClickFrame:RegisterForClicks("AnyUp", "AnyDown")
    BNToastFrameClickFrame:SetScript("OnClick", OnToastClick)

    -- 4. Create event frame for CHAT_MSG_SYSTEM + FRIENDLIST_UPDATE
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnSystemMessage)
    end
    eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")

    -- 4b. Friend list cache for guild_notify filtering. The friend list is the
    -- authoritative "real friends" set on Ascension (guild broadcasts come for
    -- names that are NOT in the friend list).
    BuildFriendNameCache()
    eventFrame:RegisterEvent("FRIENDLIST_UPDATE")

    -- 5. Add chat filter to suppress default system messages
    if not BNetToastModule.hooks.chatFilter then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemMessageFilter)
        BNetToastModule.hooks.chatFilter = true
    end

    -- 6. Ensure BNToastFrame stays on screen
    if BNToastFrame then
        BNToastFrame:SetClampedToScreen(true)
    end

    -- 7. Editor Mode support — create movable anchor for BNToastFrame
    SetupToastEditorAnchor()

    -- 8. Apply toast scale
    local applyConfig = GetModuleConfig()
    if BNToastFrame and applyConfig and applyConfig.scale then
        BNToastFrame:SetScale(applyConfig.scale)
    end

    BNetToastModule.applied = true
end

-- ============================================================================
-- EDITOR MODE SUPPORT
-- ============================================================================

local toastAnchor = nil

local function PersistToastPosition()
    if not toastAnchor or not addon.db or not addon.db.profile then return end

    addon.db.profile.widgets = addon.db.profile.widgets or {}
    addon.db.profile.widgets.bnToast = addon.db.profile.widgets.bnToast or {}

    local cx, cy = toastAnchor:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and cy and ux and uy) then return end

    local cfg = addon.db.profile.widgets.bnToast
    cfg.anchor = "CENTER"
    cfg.posX = math.floor((cx - ux) + 0.5)
    cfg.posY = math.floor((cy - uy) + 0.5)
    cfg.custom_position = true

    -- Sync slider values so X/Y sliders reflect the dragged position
    local modCfg = GetModuleConfig()
    if modCfg then
        modCfg.x_position = cfg.posX
        modCfg.y_offset = cfg.posY
    end
end

local function ApplyToastAnchorPosition()
    if InCombatLockdown() then return end
    if not toastAnchor then return end
    local cfg = addon.db and addon.db.profile and addon.db.profile.widgets and addon.db.profile.widgets.bnToast
    if not cfg or not cfg.custom_position then return end

    toastAnchor:ClearAllPoints()
    toastAnchor:SetPoint(cfg.anchor or "CENTER", UIParent, cfg.anchor or "CENTER", cfg.posX or 0, cfg.posY or 200)

    -- Sync slider values so X/Y sliders reflect the loaded position
    local modCfg = GetModuleConfig()
    if modCfg then
        modCfg.x_position = cfg.posX
        modCfg.y_offset = cfg.posY
    end
end

-- Make BNToastFrame follow toastAnchor regardless of Blizzard repositioning.
-- We hook SetPoint so every call is redirected to anchor relative to toastAnchor.
local function HookToastPosition()
    if not BNToastFrame or BNetToastModule.hooks.toastSetPoint then return end

    local origSetPoint = BNToastFrame.SetPoint
    BNetToastModule.hooks.toastSetPoint = origSetPoint

    BNToastFrame.SetPoint = function(self, ...)
        if InCombatLockdown() then
            return origSetPoint(self, ...)
        end

        if toastAnchor and toastAnchor:IsShown() then
            -- Editor mode active: anchor toast to mover
            return origSetPoint(self, "CENTER", toastAnchor, "CENTER", 0, 0)
        end

        local cfg = addon.db and addon.db.profile and addon.db.profile.widgets and addon.db.profile.widgets.bnToast
        if cfg and cfg.custom_position then
            -- Custom position saved: anchor toast to saved coords on UIParent
            return origSetPoint(self, cfg.anchor or "CENTER", UIParent, cfg.anchor or "CENTER", cfg.posX or 0, cfg.posY or 200)
        end

        -- No custom position: let Blizzard handle it
        return origSetPoint(self, ...)
    end
end

local function UnhookToastPosition()
    if not BNToastFrame then return end
    if BNetToastModule.hooks.toastSetPoint then
        BNToastFrame.SetPoint = BNetToastModule.hooks.toastSetPoint
        BNetToastModule.hooks.toastSetPoint = nil
    end
end

-- =============================================================================
-- WIDGET POSITION SYNC (guide pattern)
-- =============================================================================

local function ApplyWidgetPosition()
    if InCombatLockdown() then return end
    if addon.EditorMode and addon.EditorMode:IsActive() then return end

    local cfg = addon.db and addon.db.profile and addon.db.profile.widgets and addon.db.profile.widgets.bnToast
    if not cfg then return end

    if toastAnchor then
        toastAnchor:ClearAllPoints()
        toastAnchor:SetPoint(cfg.anchor or "CENTER", UIParent, cfg.anchor or "CENTER",
            cfg.posX or 0, cfg.posY or 200)
    end

    if BNToastFrame then
        BNToastFrame:ClearAllPoints()
        BNToastFrame:SetPoint("CENTER", toastAnchor, "CENTER", 0, 0)
    end
end

function SetupToastEditorAnchor()
    if toastAnchor or not addon.CreateUIFrame then return end

    -- BNToastFrame is ~230x60 in Blizzard XML
    toastAnchor = addon.CreateUIFrame(230, 60, "bnToast")
    toastAnchor:HookScript("OnDragStop", function(self)
        self.DragonUI_WasDragged = true
        PersistToastPosition()
    end)

    if toastAnchor.editorText then
        toastAnchor.editorText:SetText((addon.L and addon.L["BNet Toast"]) or "BNet Toast")
    end

    addon:RegisterEditableFrame({
        name = "bnToast",
        frame = toastAnchor,
        blizzardFrame = BNToastFrame,
        configPath = {"widgets", "bnToast"},
        showTest = function()
            local cfg = addon.db.profile.widgets.bnToast
            toastAnchor:ClearAllPoints()
            if cfg and cfg.custom_position then
                toastAnchor:SetPoint(cfg.anchor or "CENTER", UIParent, cfg.anchor or "CENTER", cfg.posX or 0, cfg.posY or 200)
            else
                toastAnchor:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
            end
            toastAnchor:Show()
        end,
        onHide = function()
            if toastAnchor.DragonUI_WasDragged or toastAnchor.DragonUI_WasAdjustedByEditor then
                PersistToastPosition()
                toastAnchor.DragonUI_WasDragged = nil
                toastAnchor.DragonUI_WasAdjustedByEditor = nil
            end
            toastAnchor:Hide()
            ApplyWidgetPosition()
        end,
        module = BNetToastModule,
    })

    -- Apply saved anchor position on login
    ApplyToastAnchorPosition()

    -- Hook BNToastFrame.SetPoint so it always uses our position
    HookToastPosition()
end

local function RestoreBNetToast()
    if not BNetToastModule.applied then return end
    local orig = BNetToastModule.originalStates

    -- 1. Restore BNGetFriendInfoByID
    if orig.BNGetFriendInfoByID then
        _G.BNGetFriendInfoByID = orig.BNGetFriendInfoByID
        orig.BNGetFriendInfoByID = nil
    end

    -- 2. Restore broadcast input handler
    if orig.broadcastHandler then
        FriendsFrameBroadcastInput:SetScript("OnEnterPressed", orig.broadcastHandler)
        orig.broadcastHandler = nil
    end

    -- Restore original position
    if orig.broadcastPoint then
        FriendsFrameBroadcastInput:ClearAllPoints()
        FriendsFrameBroadcastInput:SetPoint(unpack(orig.broadcastPoint))
        orig.broadcastPoint = nil
    end

    -- 3. Restore broadcast input Hide
    if orig.broadcastHide then
        FriendsFrameBroadcastInput.Hide = orig.broadcastHide
        orig.broadcastHide = nil
    end

    -- 4. Restore toast click handler
    if orig.toastClickHandler then
        BNToastFrameClickFrame:SetScript("OnClick", orig.toastClickHandler)
        orig.toastClickHandler = nil
    end

    -- 5. Unregister event
    if eventFrame then
        eventFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
        eventFrame:UnregisterEvent("FRIENDLIST_UPDATE")
    end

    -- 5b. Clear caches
    friendNameCache = nil

    -- 6. Remove chat filter
    if BNetToastModule.hooks.chatFilter then
        ChatFrame_RemoveMessageEventFilter("CHAT_MSG_SYSTEM", SystemMessageFilter)
        BNetToastModule.hooks.chatFilter = nil
    end

    -- 7. Unhook toast position
    UnhookToastPosition()

    -- 8. Restore toast scale to 1.0
    if BNToastFrame then
        BNToastFrame:SetScale(1.0)
    end

    -- 9. Hide toast anchor
    if toastAnchor then
        toastAnchor:Hide()
    end

    BNetToastModule.applied = false
end

-- ============================================================================
-- PROFILE CHANGE HANDLER
-- ============================================================================

local function OnProfileChanged()
    if IsModuleEnabled() then
        if not BNetToastModule.applied then
            ApplyBNetToast()
        end
    else
        if addon:ShouldDeferModuleDisable("bnettoast", BNetToastModule) then
            return
        end
        RestoreBNetToast()
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "DragonUI" then
        if not IsModuleEnabled() then return end

        -- Register profile callbacks after AceDB is ready
        addon:After(0.5, function()
            if addon.db and addon.db.RegisterCallback then
                addon.db.RegisterCallback(addon, "OnProfileChanged", OnProfileChanged)
                addon.db.RegisterCallback(addon, "OnProfileCopied", OnProfileChanged)
                addon.db.RegisterCallback(addon, "OnProfileReset", OnProfileChanged)
            end
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not IsModuleEnabled() then return end
        ApplyBNetToast()
    end
end)

-- ============================================================================
-- SCALE UPDATE (called from Scale slider — does NOT touch saved position)
-- ============================================================================

local function UpdateBNetToastScale()
    local config = GetModuleConfig()
    if not config or not BNToastFrame then return end
    BNToastFrame:SetScale(config.scale or 1.0)
end

-- ============================================================================
-- POSITION UPDATE (called from X/Y sliders — reapplies scale + position)
-- ============================================================================

local function UpdateBNetToastPosition()
    local config = GetModuleConfig()
    if not config or not BNToastFrame then return end

    -- Apply scale (in case it was changed without repositioning)
    BNToastFrame:SetScale(config.scale or 1.0)

    -- Update saved widget position for the toast anchor
    local cfg = addon.db and addon.db.profile and addon.db.profile.widgets and addon.db.profile.widgets.bnToast
    if cfg then
        cfg.posX = config.x_position or 0
        cfg.posY = config.y_offset or 200
        cfg.custom_position = true
    end

    -- Reposition toastAnchor to match new config
    if toastAnchor and cfg then
        toastAnchor:ClearAllPoints()
        toastAnchor:SetPoint(cfg.anchor or "CENTER", UIParent, cfg.anchor or "CENTER", cfg.posX or 0, cfg.posY or 200)
    end
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

addon.ApplyBNetToast = ApplyBNetToast
addon.RestoreBNetToast = RestoreBNetToast
addon.UpdateBNetToastScale = UpdateBNetToastScale
addon.UpdateBNetToastPosition = UpdateBNetToastPosition
