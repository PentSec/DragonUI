local addon = select(2, ...)

-- ============================================================================
-- COMBUCTOR MODULE FOR DRAGONUI
-- Ported from KPack Combuctor by bkader
-- All-in-one bag replacement with item filtering, search, bank integration.
-- ============================================================================

if _G.Combuctor then return end -- Don't load if standalone Combuctor is present

local _G = _G
local pairs, ipairs, next, select = pairs, ipairs, next, select
local format, strsplit = string.format, strsplit
local tinsert, tremove, tsort = table.insert, table.remove, table.sort
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local tonumber, tostring, type = tonumber, tostring, type
local GetItemInfo, GetItemIcon = GetItemInfo, GetItemIcon
local GetContainerItemInfo, GetContainerItemLink = GetContainerItemInfo, GetContainerItemLink
local GetContainerItemCooldown, GetContainerNumSlots = GetContainerItemCooldown, GetContainerNumSlots
local GetContainerNumFreeSlots = GetContainerNumFreeSlots
local GetKeyRingSize = GetKeyRingSize
local GetNumBankSlots = GetNumBankSlots
local GetInventoryItemLink = GetInventoryItemLink
local GetInventoryItemTexture = GetInventoryItemTexture
local GetInventoryItemCount = GetInventoryItemCount
local GetItemFamily = GetItemFamily
local IsInventoryItemLocked = IsInventoryItemLocked
local ContainerIDToInventoryID = ContainerIDToInventoryID
local BankButtonIDToInvSlotID = BankButtonIDToInvSlotID
local ContainerFrame_UpdateCooldown = ContainerFrame_UpdateCooldown
local CooldownFrame_SetTimer = CooldownFrame_SetTimer
local _OrigSetItemButtonTexture = SetItemButtonTexture
local function SetItemButtonTexture(button, texture)
    _OrigSetItemButtonTexture(button, texture)
    local name = button:GetName()
    if name then
        local icon = _G[name .. 'IconTexture']
        if icon then
            icon:SetDrawLayer('BORDER')
            icon:Show()
        end
        local count = _G[name .. 'Count']
        if count then
            count:SetDrawLayer('BORDER')
        end
    end
end
local SetItemButtonCount = SetItemButtonCount
local SetItemButtonDesaturated, SetItemButtonTextureVertexColor = SetItemButtonDesaturated, SetItemButtonTextureVertexColor
local CursorHasItem, PickupContainerItem = CursorHasItem, PickupContainerItem
local SetPortraitTexture = SetPortraitTexture
local IsAltKeyDown = IsAltKeyDown
local PlaySound = PlaySound
local UnitName = UnitName
local GetRealmName = GetRealmName
local time = time
local NUM_BAG_SLOTS = NUM_BAG_SLOTS
local NUM_BANKBAGSLOTS = NUM_BANKBAGSLOTS
local KEYRING_CONTAINER = KEYRING_CONTAINER
local BACKPACK_CONTAINER = BACKPACK_CONTAINER
local BANK_CONTAINER = BANK_CONTAINER
local NUM_BANKGENERIC_SLOTS = NUM_BANKGENERIC_SLOTS

local TEXTURE_ITEM_QUEST_BORDER = TEXTURE_ITEM_QUEST_BORDER or [[Interface\ContainerFrame\UI-ContainerQuestBorder]]
local TEXTURE_ITEM_QUEST_BANG = TEXTURE_ITEM_QUEST_BANG or [[Interface\ContainerFrame\UI-ContainerQuestBorder]]

local ItemSearch = LibStub("LibItemSearch-1.0")
local playerName = UnitName("player")
local playerClass = select(2, UnitClass("player"))

-- Module state tracking
local CombuctorModule = {
    initialized = false,
    applied = false,
    originalStates = {},
    hooks = {},
    frames = {}
}

-- Register with ModuleRegistry
if addon.RegisterModule then
    addon:RegisterModule("combuctor", CombuctorModule,
        (addon.L and addon.L["Combuctor"]) or "Combuctor",
        (addon.L and addon.L["All-in-one bag replacement with filtering and search"]) or "All-in-one bag replacement with filtering and search")
end


-- ============================================================================
-- COMBUCTOR SELF-CONTAINED RETAIL SKINNING
-- Combuctor manages its own textures and skinning functions.
-- Zero dependency on bags_skin module.
-- ============================================================================

local CombuctorAssets = addon._dir

local CT = {
    slot_bg           = CombuctorAssets .. 'bagsitemslot2x',
    slot_depress      = CombuctorAssets .. 'ui-quickslot-depress',
    slot_highlight    = CombuctorAssets .. 'buttonhilight-square',
    frame_metal       = CombuctorAssets .. 'uiframemetal2x',
    frame_metal_h     = CombuctorAssets .. 'uiframemetalhorizontal2x',
    frame_metal_v     = CombuctorAssets .. 'uiframemetalvertical2x',
    frame_bg          = CombuctorAssets .. 'ui-background-rock',
    close_btn         = CombuctorAssets .. 'redbutton2x',
    bigbag            = CombuctorAssets .. 'bigbag',
    bigbag_highlight  = CombuctorAssets .. 'bigbagHighlight',
    bagslot           = CombuctorAssets .. 'bagslots2x',
    bagslot_cutout    = CombuctorAssets .. 'bagslotCutout',
    bag_border        = CombuctorAssets .. 'bagborder2',
    slot_border       = CombuctorAssets .. 'ui-quickslot2',
    coinbox           = CombuctorAssets .. 'commoncoinbox',
    currencybox       = CombuctorAssets .. 'commoncurrencybox',
    coinGold          = CombuctorAssets .. 'coingold',
    coinSilver        = CombuctorAssets .. 'coinsilver',
    coinCopper        = CombuctorAssets .. 'coincopper',
}


-- Retail-style nineslice border for Combuctor frames
local function CombuctorAddNineSlice(frame)
    if frame._BagSkin_NineSlice then return end

    local ns = {}
    frame._BagSkin_NineSlice = ns

    ns.TopLeftCorner     = frame:CreateTexture(nil, 'OVERLAY')
    ns.TopRightCorner    = frame:CreateTexture(nil, 'OVERLAY')
    ns.BottomLeftCorner  = frame:CreateTexture(nil, 'OVERLAY')
    ns.BottomRightCorner = frame:CreateTexture(nil, 'OVERLAY')
    ns.TopEdge           = frame:CreateTexture(nil, 'OVERLAY')
    ns.BottomEdge        = frame:CreateTexture(nil, 'OVERLAY')
    ns.LeftEdge          = frame:CreateTexture(nil, 'OVERLAY')
    ns.RightEdge         = frame:CreateTexture(nil, 'OVERLAY')

    local bg = CreateFrame('Frame', nil, frame)
    bg:SetPoint('TOPLEFT', frame, 'TOPLEFT', 3, -18)
    bg:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -3, 3)
    bg:SetFrameLevel(0)
    ns.Bg = bg

    local bgTex = bg:CreateTexture(nil, 'BACKGROUND')
    bgTex:SetTexture(CT.frame_bg)
    bgTex:SetAllPoints(bg)
    bgTex:SetAlpha(0.8)
    ns.BgTex = bgTex

    local tlc = ns.TopLeftCorner
    tlc:SetTexture(CT.frame_metal)
    tlc:SetTexCoord(0.00195312, 0.294922, 0.00195312, 0.294922)
    tlc:SetSize(75, 75)
    tlc:SetPoint('TOPLEFT', -12, 16)

    local trc = ns.TopRightCorner
    trc:SetTexture(CT.frame_metal)
    trc:SetTexCoord(0.298828, 0.591797, 0.00195312, 0.294922)
    trc:SetSize(75, 75)
    trc:SetPoint('TOPRIGHT', 4, 16)

    local blc = ns.BottomLeftCorner
    blc:SetTexture(CT.frame_metal)
    blc:SetTexCoord(0.298828, 0.423828, 0.298828, 0.423828)
    blc:SetSize(32, 32)
    blc:SetPoint('BOTTOMLEFT', -12, -3)

    local brc = ns.BottomRightCorner
    brc:SetTexture(CT.frame_metal)
    brc:SetTexCoord(0.427734, 0.552734, 0.298828, 0.423828)
    brc:SetSize(32, 32)
    brc:SetPoint('BOTTOMRIGHT', 4, -3)

    local te = ns.TopEdge
    te:SetTexture(CT.frame_metal_h)
    te:SetTexCoord(0, 1, 0.00390625, 0.589844)
    te:SetSize(32, 75)
    te:SetPoint('TOPLEFT', tlc, 'TOPRIGHT', -4, 0)
    te:SetPoint('TOPRIGHT', trc, 'TOPLEFT', 4, 0)

    local be = ns.BottomEdge
    be:SetTexture(CT.frame_metal_h)
    be:SetTexCoord(0, 0.5, 0.597656, 0.847656)
    be:SetSize(16, 32)
    be:SetPoint('TOPLEFT', blc, 'TOPRIGHT', 0, 0)
    be:SetPoint('TOPRIGHT', brc, 'TOPLEFT', 0, 0)

    local le = ns.LeftEdge
    le:SetTexture(CT.frame_metal_v)
    le:SetTexCoord(0.00195312, 0.294922, 0, 1)
    le:SetSize(75, 16)
    le:SetPoint('TOPLEFT', tlc, 'BOTTOMLEFT', 0, 0)
    le:SetPoint('BOTTOMLEFT', blc, 'TOPLEFT', 0, 0)

    local re = ns.RightEdge
    re:SetTexture(CT.frame_metal_v)
    re:SetTexCoord(0.298828, 0.591797, 0, 1)
    re:SetSize(75, 16)
    re:SetPoint('TOPRIGHT', trc, 'BOTTOMRIGHT', 0, 0)
    re:SetPoint('BOTTOMRIGHT', brc, 'TOPRIGHT', 0, 0)

    local closeBtn = frame.ClosePanelButton or _G[frame:GetName() .. 'CloseButton']
    if closeBtn then
        closeBtn:SetSize(24, 24)
        local nt = closeBtn:GetNormalTexture()
        if nt then
            nt:SetTexture(CT.close_btn)
            nt:SetTexCoord(0.152344, 0.292969, 0.0078125, 0.304688)
        end
        local pt = closeBtn:GetPushedTexture()
        if pt then
            pt:SetTexture(CT.close_btn)
            pt:SetTexCoord(0.152344, 0.292969, 0.320312, 0.617188)
        end
    end
end

-- Retail-style item slot restyle for Combuctor item buttons
local function CombuctorRetailItemSlot(btn)
    if btn._BagSkin_Applied then return end
    btn._BagSkin_Applied = true

    local nt = btn:GetNormalTexture()
    if nt then
        nt:SetTexture(CT.slot_bg)
        nt:SetSize(37, 37)
        nt:ClearAllPoints()
        nt:SetPoint('CENTER', btn, 'CENTER')
        nt:SetDrawLayer('BACKGROUND')
        nt:Show()
        nt:SetAlpha(1)
    end

    -- Slot border ring overlay (64x64), reused from cache if present
    local border = btn._dragonuiSlotBorder
    if not border then
        border = btn:CreateTexture(nil, 'BORDER')
        btn._dragonuiSlotBorder = border
    end
    border:SetTexture(CT.slot_border)
    border:SetSize(64, 64)
    border:ClearAllPoints()
    border:SetPoint('CENTER', btn, 'CENTER', 0, -1)
    border:Show()

    local pt = btn:GetPushedTexture()
    if pt then
        pt:SetTexture(CT.slot_depress)
        pt:SetSize(37, 37)
        pt:ClearAllPoints()
        pt:SetPoint('CENTER', btn, 'CENTER')
    end

    local ht = btn:GetHighlightTexture()
    if ht then
        ht:SetTexture(CT.slot_highlight)
        ht:SetSize(37, 37)
        ht:ClearAllPoints()
        ht:SetPoint('CENTER', btn, 'CENTER')
    end

    local name = btn:GetName()
    if not name then return end

    local icon = _G[name .. 'IconTexture']
    if icon then
        icon:SetDrawLayer('BORDER')
        icon:SetTexCoord(0, 1, 0, 1)
        icon:ClearAllPoints()
        icon:SetAllPoints(btn)
        icon:Show()
    end

    local count = _G[name .. 'Count']
    if count then
        count:SetDrawLayer('BORDER')
    end

    local stock = _G[name .. 'Stock']
    if stock then
        stock:SetDrawLayer('BORDER')
    end
end

-- Retail-style bag slot restyle for Combuctor bag toggle buttons
local function CombuctorRetailBagSlot(btn)
    if btn._BagSkin_Applied then return end
    btn._BagSkin_Applied = true

    for _, region in ipairs({ btn:GetRegions() }) do
        if region:GetObjectType() == 'Texture' then
            local tex = region:GetTexture() or ''
            local rname = (region.GetName and region:GetName()) or ''
            if not rname:find('IconTexture') then
                if tex:find('UI%-Quickslot') or tex:find('ButtonHilight') then
                    region:SetTexture(nil)
                    region:SetAlpha(0)
                    region:Hide()
                end
            end
        end
    end

    local size = 30.5

    local nt = btn:GetNormalTexture()
    if nt then
        nt:SetTexture(CT.bagslot)
        nt:SetTexCoord(0.576172, 0.695312, 0.5, 0.976562)
        nt:SetSize(size, size)
        nt:ClearAllPoints()
        nt:SetPoint('CENTER', 2, -1)
        nt:SetDrawLayer('BORDER', 0)
        nt:SetAlpha(1)
        nt:Show()
    end

    local ht = btn:GetHighlightTexture()
    if ht then
        ht:SetTexture(CT.bagslot)
        ht:SetTexCoord(0.699219, 0.818359, 0.0078125, 0.484375)
        ht:SetSize(size, size)
        ht:ClearAllPoints()
        ht:SetPoint('CENTER', 2, -1)
        ht:SetAlpha(1)
        ht:Show()
    end

    local pt = btn:GetPushedTexture()
    if pt then
        pt:SetTexture(CT.bagslot)
        pt:SetTexCoord(0.699219, 0.818359, 0.0078125, 0.484375)
        pt:SetSize(size, size)
        pt:ClearAllPoints()
        pt:SetPoint('CENTER', 2, -1)
        pt:SetAlpha(1)
        pt:Show()
    end
end

-- Retail-style backpack button restyle
local function CombuctorRetailBackpackButton()
    local btn = MainMenuBarBackpackButton
    if not btn or btn._BagSkin_Backpack then return end
    btn._BagSkin_Backpack = true

    SetItemButtonTexture(btn, CT.bigbag)
    btn:SetHighlightTexture(CT.bigbag_highlight)
    btn:SetPushedTexture(CT.bigbag_highlight)
    btn:SetCheckedTexture(CT.bigbag_highlight)

    if MainMenuBarBackpackButtonNormalTexture then
        MainMenuBarBackpackButtonNormalTexture:Hide()
        MainMenuBarBackpackButtonNormalTexture:SetTexture()
    end

    if not btn._BagSkin_Border then
        local border = btn:CreateTexture(nil, 'OVERLAY')
        border:SetTexture(CT.bagslot_cutout)
        border:SetPoint('TOPLEFT', btn, 'TOPLEFT', 0, 0)
        border:SetPoint('BOTTOMRIGHT', btn, 'BOTTOMRIGHT', 0, 0)
        btn._BagSkin_Border = border
    end
end

local function GetModuleConfig()
    return addon:GetModuleConfig("combuctor")
end

local function IsModuleEnabled()
    return addon:IsModuleEnabled("combuctor")
end

-- ============================================================================
-- MODULE INTERNALS (replaces KPack core:NewClass / core:NewModule)
-- ============================================================================

local mod = {}
mod.modules = {}

function mod:NewClass(ftype, parent)
    local class = CreateFrame(ftype)
    class:Hide()
    class.mt = { __index = class }
    if parent then
        class = setmetatable(class, { __index = parent })
        class.super = function(self, method, ...)
            return parent[method](self, ...)
        end
    end
    class.Bind = function(self, obj)
        return setmetatable(obj, self.mt)
    end
    return class
end

function mod:NewModule(name, proto)
    local m
    if proto then
        m = setmetatable({}, { __index = proto })
    else
        m = {}
    end
    self.modules[name] = m
    return m
end

function mod:GetModule(name)
    return self.modules[name]
end

-- Callable access: mod("ModuleName") returns module
setmetatable(mod, {
    __call = function(self, name)
        return self.modules[name]
    end
})

-- Expose the mod table so the split files (combuctor_data.lua,
-- combuctor_sets.lua, combuctor_classes.lua, combuctor_frame.lua,
-- combuctor_system.lua) can fetch it as `addon.CombuctorModule`.
-- (mod.CombuctorModule remains the metadata table for the module
-- registry — different namespace, intentionally.)
addon.CombuctorModule = mod

-- ============================================================================
-- DATABASE
-- ============================================================================

local DB
local SET_ALL = ALL or "All"
local SET_EQUIPMENT = "Equipment"
local SET_USABLE = "Usable"
local SET_NORMAL = "Normal"
local SET_TRADE = "Trade"

local defaults = {
    inventory = {
        bags = { 0, 1, 2, 3, 4 },
        position = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", -64, 64 },
        showBags = false,
        leftSideFilter = true,
        w = 384,
        h = 512,
        sets = {},
        exclude = {}
    },
    bank = {
        bags = { -1, 5, 6, 7, 8, 9, 10, 11 },
        position = { "LEFT", nil, "LEFT", 24, 0 },
        showBags = false,
        leftSideFilter = false,
        w = 512,
        h = 512,
        sets = {},
        exclude = {}
    }
}

-- Localization strings
local L = {}
L.InventoryTitle = (addon.L and addon.L["%s's Inventory"]) or "%s's Inventory"
L.BankTitle = (addon.L and addon.L["%s's Bank"]) or "%s's Bank"
L.Inventory = (addon.L and addon.L["Inventory"]) or "Inventory"
L.Bank = (addon.L and addon.L["Bank"]) or "Bank"
L.Bags = (addon.L and addon.L["Bags"]) or "Bags"
L.BagToggle = (addon.L and addon.L["|cff00ff00Left-Click|r to toggle bag display"]) or "|cff00ff00Left-Click|r to toggle bag display"
L.InventoryToggle = (addon.L and addon.L["|cff00ff00Right-Click|r to toggle inventory"]) or "|cff00ff00Right-Click|r to toggle inventory"
L.BankToggle = (addon.L and addon.L["|cff00ff00Right-Click|r to toggle bank"]) or "|cff00ff00Right-Click|r to toggle bank"
L.MoveTip = (addon.L and addon.L["|cff00ff00Drag|r to move"]) or "|cff00ff00Drag|r to move"
L.ResetPositionTip = (addon.L and addon.L["|cff00ff00Alt+Right-Click|r to reset position"]) or "|cff00ff00Alt+Right-Click|r to reset position"
L.ToggleInventory = (addon.L and addon.L["Toggle Inventory"]) or "Toggle Inventory"
L.ToggleBank = (addon.L and addon.L["Toggle Bank"]) or "Toggle Bank"

local function GetSetDisplayName(name)
    if name == SET_EQUIPMENT then
        return (addon.L and addon.L["Equipment"]) or (addon.LO and addon.LO["Equipment"]) or name
    elseif name == SET_USABLE then
        return (addon.L and addon.L["Usable"]) or (addon.LO and addon.LO["Usable"]) or name
    elseif name == SET_NORMAL then
        return (addon.L and addon.L["Normal"]) or name
    elseif name == SET_TRADE then
        return (addon.L and addon.L["Trade"]) or name
    end
    return name
end

-- Localize auction item classes
L.Weapon, L.Armor, L.Container, L.Consumable, L.Glyph, L.TradeGood, _, _, L.Recipe, L.Gem, L.Misc, L.Quest = GetAuctionItemClasses()
L.Devices, L.Explosives = select(10, GetAuctionItemSubClasses(6))
L.SimpleGem = select(8, GetAuctionItemSubClasses(7))

local function SetupDatabase()
    if not addon.db then return end
    if not addon.db.profile.modules then addon.db.profile.modules = {} end
    if not addon.db.profile.modules.combuctor then addon.db.profile.modules.combuctor = {} end

    local mc = addon.db.profile.modules.combuctor
    if not mc.db then mc.db = {} end
    if mc.money_display == nil then mc.money_display = "icons" end

    DB = mc.db
    if not DB.inventory then
        DB.inventory = {}
        for k, v in pairs(defaults.inventory) do
            if type(v) == "table" then
                DB.inventory[k] = {}
                for kk, vv in pairs(v) do DB.inventory[k][kk] = vv end
            else
                DB.inventory[k] = v
            end
        end
    end
    if not DB.bank then
        DB.bank = {}
        for k, v in pairs(defaults.bank) do
            if type(v) == "table" then
                DB.bank[k] = {}
                for kk, vv in pairs(v) do DB.bank[k][kk] = vv end
            else
                DB.bank[k] = v
            end
        end
    end
    if not DB.inventory.sets then DB.inventory.sets = {} end
    if not DB.inventory.exclude then DB.inventory.exclude = {} end
    if not DB.bank.sets then DB.bank.sets = {} end
    if not DB.bank.exclude then DB.bank.exclude = {} end

    local localizedEquipment = (addon.L and addon.L["Equipment"]) or (addon.LO and addon.LO["Equipment"])
    local localizedUsable = (addon.L and addon.L["Usable"]) or (addon.LO and addon.LO["Usable"])
    local function NormalizeLocalizedSetName(name)
        if not name then return name end
        if name == SET_EQUIPMENT or (localizedEquipment and name == localizedEquipment) then
            return SET_EQUIPMENT
        end
        if name == SET_USABLE or (localizedUsable and name == localizedUsable) then
            return SET_USABLE
        end
        return name
    end

    local function NormalizeSetList(list)
        if not list then return end
        for i, name in ipairs(list) do
            list[i] = NormalizeLocalizedSetName(name)
        end
    end

    local function NormalizeExcludeTable(exclude)
        if not exclude then return end
        local normalized = {}
        for parentName, childList in pairs(exclude) do
            normalized[NormalizeLocalizedSetName(parentName)] = childList
        end
        for key in pairs(exclude) do
            exclude[key] = nil
        end
        for key, value in pairs(normalized) do
            exclude[key] = value
        end
    end

    NormalizeSetList(DB.inventory.sets)
    NormalizeSetList(DB.bank.sets)
    NormalizeExcludeTable(DB.inventory.exclude)
    NormalizeExcludeTable(DB.bank.exclude)
end

function mod:GetProfile()
    return DB
end

function mod:SetMaxItemScale(scale)
    if DB then DB.maxScale = scale or 1 end
end

function mod:GetMaxItemScale()
    return (DB and DB.maxScale) or 1
end

-- ============================================================================
-- BAG TOGGLE
-- ============================================================================

function mod:Show(bag, auto)
    for _, frame in pairs(self.frames) do
        for _, bagID in pairs(frame.sets.bags) do
            if bagID == bag then
                frame:ShowFrame(auto)
                return
            end
        end
    end
end

function mod:Hide(bag, auto)
    for _, frame in pairs(self.frames) do
        for _, bagID in pairs(frame.sets.bags) do
            if bagID == bag then
                frame:HideFrame(auto)
                return
            end
        end
    end
end

function mod:Toggle(bag)
    for _, frame in pairs(self.frames) do
        for _, bagID in pairs(frame.sets.bags) do
            if bagID == bag then
                frame:ToggleFrame()
                return
            end
        end
    end
end

-- ============================================================================
-- SHARED LOCALS → mod.X PROMOTIONS
-- Promotes file-local upvalues to mod fields so downstream split files can
-- access them via mod.X after extraction (PR #2). The locals remain valid
-- as upvalues within this file; behaviors are unchanged.
-- ============================================================================

mod.CT = CT
mod.L = L
mod.DB = DB
mod.defaults = defaults
mod.playerName = playerName
mod.ItemSearch = ItemSearch
mod.GetModuleConfig = GetModuleConfig
mod.IsModuleEnabled = IsModuleEnabled
mod.SetupDatabase = SetupDatabase
mod.CombuctorModule = CombuctorModule
mod.CombuctorAddNineSlice = CombuctorAddNineSlice
mod.CombuctorRetailItemSlot = CombuctorRetailItemSlot
mod.CombuctorRetailBagSlot = CombuctorRetailBagSlot
mod.CombuctorRetailBackpackButton = CombuctorRetailBackpackButton
mod.TEXTURE_ITEM_QUEST_BORDER = TEXTURE_ITEM_QUEST_BORDER
mod.TEXTURE_ITEM_QUEST_BANG = TEXTURE_ITEM_QUEST_BANG


-- ============================================================================
-- APPLY / RESTORE SYSTEM
-- ============================================================================

local AutoShowInventory, AutoHideInventory

local function ApplyCombuctorSystem()
    if mod.CombuctorModule.applied then return end

    mod.SetupDatabase()
    if not mod.DB then return end

    -- Sets are empty by default (no category tabs shown)
    -- Users can enable individual tabs via the options panel

    -- Create frames only once; toggling module should reuse existing frames.
    mod.frames = mod.frames or {}
    if not mod.frames[1] then
        mod.frames[1] = mod.Frame:New(mod.L.InventoryTitle, mod.DB.inventory, false, "inventory")
    end
    if not mod.frames[2] then
        mod.frames[2] = mod.Frame:New(mod.L.BankTitle, mod.DB.bank, true, "bank")
    end

    -- Apply retail skin to frames (independent of bags_skin module)
    mod.CombuctorApplySkin()

    AutoShowInventory = function()
        mod:Show(BACKPACK_CONTAINER, true)
    end
    AutoHideInventory = function()
        mod:Hide(BACKPACK_CONTAINER, true)
    end

    mod.CombuctorModule.originalStates.OpenBackpack = _G.OpenBackpack
    mod.CombuctorModule.originalStates.ToggleBank = _G.ToggleBank
    mod.CombuctorModule.originalStates.ToggleBackpack = _G.ToggleBackpack
    mod.CombuctorModule.originalStates.OpenAllBags = _G.OpenAllBags
    mod.CombuctorModule.originalStates.ToggleAllBags = _G.ToggleAllBags
    mod.CombuctorModule.originalStates.ToggleBag = _G.ToggleBag

    -- Hook bag functions
    _G.OpenBackpack = AutoShowInventory
    if not mod.CombuctorModule.hooks.closeBackpack then
        hooksecurefunc("CloseBackpack", AutoHideInventory)
        mod.CombuctorModule.hooks.closeBackpack = true
    end

    _G.ToggleBank = function(bag) mod:Toggle(bag) end
    _G.ToggleBackpack = function() mod:Toggle(BACKPACK_CONTAINER) end
    _G.ToggleBag = function(slot)
        if slot == BACKPACK_CONTAINER then
            mod:Toggle(BACKPACK_CONTAINER)
        else
            mod:Toggle(slot)
        end
    end
    -- Some keybind paths call OpenAllBags directly, so make it a true toggle.
    _G.OpenAllBags = function() mod:Toggle(BACKPACK_CONTAINER) end
    if _G.ToggleAllBags then
        _G.ToggleAllBags = function() mod:Toggle(BACKPACK_CONTAINER) end
    end

    if not mod.CombuctorModule.hooks.closeAllBags then
        hooksecurefunc("CloseAllBags", function() mod:Hide(BACKPACK_CONTAINER) end)
        mod.CombuctorModule.hooks.closeAllBags = true
    end
    BankFrame:UnregisterAllEvents()
    BankFrame:Hide()

    if not mod.CombuctorModule.hooks.inventoryEvents then
        mod("InventoryEvents"):Register(mod, "BANK_OPENED", function()
            mod:Show(BANK_CONTAINER, true)
            mod:Show(BACKPACK_CONTAINER, true)
        end)
        mod("InventoryEvents"):Register(mod, "BANK_CLOSED", function()
            mod:Hide(BANK_CONTAINER, true)
            mod:Hide(BACKPACK_CONTAINER, true)
        end)
        mod.CombuctorModule.hooks.inventoryEvents = true
    end

    -- Auto show/hide on trade/auction/mail
    local autoEventFrame = mod.CombuctorModule.frames.autoEventFrame or CreateFrame("Frame")
    autoEventFrame:UnregisterAllEvents()
    autoEventFrame:SetScript("OnEvent", function(self, event)
        if event == "MAIL_CLOSED" or event == "TRADE_CLOSED" or
           event == "TRADE_SKILL_CLOSE" or event == "AUCTION_HOUSE_CLOSED" then
            AutoHideInventory()
        elseif event == "TRADE_SHOW" or event == "TRADE_SKILL_SHOW" or
               event == "AUCTION_HOUSE_SHOW" then
            AutoShowInventory()
        end
    end)
    autoEventFrame:RegisterEvent("MAIL_CLOSED")
    autoEventFrame:RegisterEvent("TRADE_CLOSED")
    autoEventFrame:RegisterEvent("TRADE_SKILL_CLOSE")
    autoEventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
    autoEventFrame:RegisterEvent("TRADE_SHOW")
    autoEventFrame:RegisterEvent("TRADE_SKILL_SHOW")
    autoEventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
    mod.CombuctorModule.frames.autoEventFrame = autoEventFrame

    -- Slash commands
    SlashCmdList["DRAGONUI_COMBUCTOR"] = function(msg)
        msg = msg and msg:lower() or ""
        if msg == "bank" then
            mod:Toggle(BANK_CONTAINER)
        elseif msg == "bags" or msg == "inventory" then
            mod:Toggle(BACKPACK_CONTAINER)
        else
            mod:Toggle(BACKPACK_CONTAINER)
        end
    end
    SLASH_DRAGONUI_COMBUCTOR1 = "/cbt"
    SLASH_DRAGONUI_COMBUCTOR2 = "/combuctor"

    mod.CombuctorModule.applied = true
end

local function RestoreCombuctorSystem()
    if not mod.CombuctorModule.applied then return end

    if mod.CombuctorModule.frames.autoEventFrame then
        mod.CombuctorModule.frames.autoEventFrame:UnregisterAllEvents()
        mod.CombuctorModule.frames.autoEventFrame:SetScript("OnEvent", nil)
    end

    -- Hide all frames
    if mod.frames then
        for _, frame in pairs(mod.frames) do
            if frame.HideFrame then frame:HideFrame() end
        end
    end

    -- Restore original bag functions
    if mod.CombuctorModule.originalStates.OpenBackpack then
        _G.OpenBackpack = mod.CombuctorModule.originalStates.OpenBackpack
    end
    if mod.CombuctorModule.originalStates.ToggleBank then
        _G.ToggleBank = mod.CombuctorModule.originalStates.ToggleBank
    end
    if mod.CombuctorModule.originalStates.ToggleBackpack then
        _G.ToggleBackpack = mod.CombuctorModule.originalStates.ToggleBackpack
    end
    if mod.CombuctorModule.originalStates.OpenAllBags then
        _G.OpenAllBags = mod.CombuctorModule.originalStates.OpenAllBags
    end
    if mod.CombuctorModule.originalStates.ToggleAllBags then
        _G.ToggleAllBags = mod.CombuctorModule.originalStates.ToggleAllBags
    end
    if mod.CombuctorModule.originalStates.ToggleBag then
        _G.ToggleBag = mod.CombuctorModule.originalStates.ToggleBag
    end

    mod.CombuctorModule.originalStates = {}
    mod.CombuctorModule.applied = false
end

local function RefreshCombuctorFrames()
    if not mod.frames then return end

    for _, frame in pairs(mod.frames) do
        if frame and frame.UpdateSets then
            frame:UpdateSets()
        end
        if frame and frame.SetLeftSideFilter then
            frame:SetLeftSideFilter(frame:IsSideFilterOnLeft())
        end
        if frame and frame.UpdateClampInsets then
            frame:UpdateClampInsets()
        end

        -- Re-skin items and bag slots (local functions guard via _BagSkin_Applied)
        if frame then
            local name = frame:GetName()
            local gframe = _G[name]
            if gframe then
                mod.CombuctorSkinItems(gframe)
                mod.CombuctorSkinBagSlots(gframe)
            end
        end

        if frame and frame.moneyFrame and frame.moneyFrame.RefreshDisplay then
            frame.moneyFrame:RefreshDisplay()
        end
    end
end

-- ============================================================================
-- PROFILE CHANGE HANDLER
-- ============================================================================

local function OnProfileChanged()
    if mod.IsModuleEnabled() then
        if not mod.CombuctorModule.applied then
            ApplyCombuctorSystem()
        else
            -- Profile changed while module is active: refresh mod.DB and existing frames
            mod.SetupDatabase()
            if not mod.DB then return end

            -- Sets remain as stored in profile (empty = no category tabs)

            -- Update existing frames to point to new mod.DB tables
            if mod.frames then
                for _, frame in pairs(mod.frames) do
                    if frame.key and mod.DB[frame.key] then
                        frame.sets = mod.DB[frame.key]
                        frame:SetWidth(frame.sets.w or 384)
                        frame:SetHeight(frame.sets.h or 440)
                        if frame.UpdateSets then
                            frame:UpdateSets()
                        end
                    end
                end
            end
        end
    else
        if addon:ShouldDeferModuleDisable("combuctor", mod.CombuctorModule) then
            return
        end
        RestoreCombuctorSystem()
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
        if not mod.IsModuleEnabled() then return end

        addon:After(0.5, function()
            if addon.db and addon.db.RegisterCallback then
                addon.db.RegisterCallback(addon, "OnProfileChanged", OnProfileChanged)
                addon.db.RegisterCallback(addon, "OnProfileCopied", OnProfileChanged)
                addon.db.RegisterCallback(addon, "OnProfileReset", OnProfileChanged)
            end
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not mod.IsModuleEnabled() then return end
        ApplyCombuctorSystem()
    end
end)

-- Export for external use
addon.ApplyCombuctorSystem = ApplyCombuctorSystem
addon.RestoreCombuctorSystem = RestoreCombuctorSystem
addon.RefreshCombuctorFrames = RefreshCombuctorFrames
addon.CombuctorItemSlot = mod.ItemSlot
