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

-- DragonUI_CombuctorIconButtonTemplate (portrait)
local function SetupIconButton(btn, parentFrame)
    btn:SetSize(64, 64)
    btn:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 4, -4)

    -- HighlightTexture: UI-Minimap-ZoomButton-Highlight
    local ht = btn:CreateTexture(nil, "HIGHLIGHT")
    ht:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    ht:SetSize(78, 78)
    ht:SetPoint("CENTER")
    ht:SetBlendMode("ADD")
    btn:SetHighlightTexture(ht)

    btn:RegisterForClicks("anyUp")
    btn.icon = _G[parentFrame:GetName() .. "Icon"]
    btn.icon:ClearAllPoints()
    btn.icon:SetPoint("CENTER", btn)

    btn:SetScript("OnEvent", function(self, event, ...)
        if self:IsShown() and arg1 == "player" then
            SetPortraitTexture(self.icon, arg1)
        end
    end)
    btn:SetScript("OnShow", function(self)
        SetPortraitTexture(self.icon, "player")
        self:RegisterEvent("UNIT_PORTRAIT_UPDATE")
    end)
    btn:SetScript("OnHide", function(self)
        self:UnregisterEvent("UNIT_PORTRAIT_UPDATE")
    end)
    btn:SetScript("OnMouseDown", function(self)
        self.icon:SetWidth(56)
        self.icon:SetHeight(56)
        self.icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self.icon:SetWidth(62)
        self.icon:SetHeight(62)
        self.icon:SetTexCoord(0, 1, 0, 1)
    end)
    btn:SetScript("OnEnter", function() GameTooltip:Hide() end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- DragonUI_CombuctorDragFrameTemplate (title/drag bar)
local function SetupDragFrame(btn, parentFrame)
    btn:SetSize(262, 14)
    btn:SetPoint("TOP", parentFrame, "TOP", 0, -16)

    btn:RegisterForClicks("anyUp")
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnClick", function(self, button)
        if IsAltKeyDown() and button == "RightButton" then
            self:GetParent():SavePosition(nil)
        end
    end)
    btn:SetScript("OnMouseDown", function(self)
        self.isMoving = true
        self:GetParent():StartMoving()
    end)
    btn:SetScript("OnMouseUp", function(self)
        if self.isMoving then
            self.isMoving = nil
            self:GetParent():StopMovingOrSizing()
            self:GetParent():SavePosition(self:GetParent():GetPoint())
        end
    end)
    btn:SetScript("OnEnter", function(self)
        self:GetParent():OnTitleEnter(self)
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetNormalFontObject(GameFontNormal)
    btn:SetHighlightFontObject(GameFontHighlight)
end

-- DragonUI_CombuctorSearchBoxTemplate
local function SetupSearchBox(eb, parentFrame)
    eb:SetAutoFocus(false)
    eb:SetHeight(20)
    eb:SetPoint("TOPLEFT",  parentFrame, "TOPLEFT",  84, -44)
    eb:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -116, -44)

    eb:SetScript("OnShow", function(self)
        if self:GetText() == '' then
            self:SetText(SEARCH)
        end
    end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self)
        self:SetText(SEARCH)
        self:ClearFocus()
        self:GetParent():SetFilter('name', nil, true)
    end)
    eb:SetScript("OnTextChanged", function(self)
        if self:HasFocus() then
            local text = self:GetText()
            self:GetParent():SetFilter('name', (text ~= '' and text:lower()) or nil, true)
        end
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        if self:GetText() == '' then
            self:SetText(SEARCH)
        end
    end)
    eb:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        if self:GetText() == SEARCH then
            self:SetText('')
        end
    end)
end

-- DragonUI_CombuctorResetButtonTemplate
local function SetupResetButton(btn)
    btn:SetSize(20, 20)
    local icon = "Interface\\Icons\\INV_Pet_Broom"
    local nt = btn:CreateTexture(nil, "ARTWORK")
    nt:SetTexture(icon)
    nt:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    nt:SetAllPoints(btn)
    btn:SetNormalTexture(nt)
    local pt = btn:CreateTexture(nil, "OVERLAY")
    pt:SetTexture(icon)
    pt:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    pt:SetAllPoints(btn)
    pt:Hide()
    btn:SetPushedTexture(pt)
    local ht = btn:CreateTexture(nil, "HIGHLIGHT")
    ht:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    ht:SetBlendMode("ADD")
    ht:SetAllPoints(btn)
    btn:SetHighlightTexture(ht)
end

-- DragonUI_CombuctorBagToggleTemplate
local function SetupBagToggle(btn, parentFrame)
    btn:SetSize(32, 32)

    -- $parentIcon: Button-Backpack-Up
    local icon = btn:CreateTexture(btn:GetName() .. "Icon", "BACKGROUND")
    icon:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -6)
    icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)

    -- $parentBorder: MiniMap-TrackingBorder
    local border = btn:CreateTexture(btn:GetName() .. "Border", "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT")
    border:SetDesaturated(true)
    border:SetAlpha(0.6)

    btn:RegisterForClicks("anyUp")

    btn:SetScript("OnClick", function(self, button)
        self:GetParent():OnBagToggleClick(self, button)
    end)
    btn:SetScript("OnMouseDown", function(self)
        icon:SetTexCoord(0, 1, 0, 1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
    end)
    btn:SetScript("OnEnter", function(self)
        self:GetParent():OnBagToggleEnter(self)
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- HighlightTexture
    local ht = btn:CreateTexture(nil, "HIGHLIGHT")
    ht:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    ht:SetBlendMode("ADD")
    btn:SetHighlightTexture(ht)
end

-- Replaces DragonUI_CombuctorInventoryTemplate entirely
-- Creates the main inventory/bank frame with all children in pure Lua.
local function CreateInventoryFrame(name, parent)
    parent = parent or UIParent
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(384, 512)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetFrameStrata("HIGH")
    f:Hide()
    f:SetHitRectInsets(0, 35, 0, 75)

    -- BACKGROUND: $parentIcon (62x62, portrait target)
    local portraitTex = f:CreateTexture(name .. "Icon", "BACKGROUND")
    portraitTex:SetSize(62, 62)

    -- $parentCloseButton (UIPanelCloseButton)
    local closeBtn = CreateFrame("Button", name .. "CloseButton", f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -20)

    -- $parentIconButton
    local iconBtn = CreateFrame("Button", name .. "IconButton", f)
    SetupIconButton(iconBtn, f)

    -- $parentTitle
    local titleBtn = CreateFrame("Button", name .. "Title", f)
    SetupDragFrame(titleBtn, f)

    -- $parentSearch
    local searchEb = CreateFrame("EditBox", name .. "Search", f, "InputBoxTemplate")
    SetupSearchBox(searchEb, f)

    -- $parentBagToggle (create first, anchor from RIGHT)
    local bagToggleBtn = CreateFrame("Button", name .. "BagToggle", f)
    SetupBagToggle(bagToggleBtn, f)

    -- $parentReset
    local resetBtn = CreateFrame("Button", name .. "Reset", f)
    SetupResetButton(resetBtn)
    resetBtn:SetScript("OnClick", function()
        searchEb:SetText(SEARCH)
        searchEb:ClearFocus()
        f:SetFilter('name', nil, true)
    end)

    -- bagToggle (32x32) anchored top-right
    bagToggleBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -38)

    -- resetBtn (32x32): anchor to bag toggle, shift down 6px so visual
    -- center aligns with the 20px search bar (search top=-44, height=20).
    -- ClearAllPoints is REQUIRED — without it, SetPoint ADDS a second
    -- anchor and the button appears stuck because two points fight.
    resetBtn:ClearAllPoints()
    resetBtn:SetPoint("TOPRIGHT", bagToggleBtn, "TOPLEFT", 3, -11)

    -- searchBox (20px tall): TOPRIGHT Y=0 keeps it horizontal with resetBtn
    searchEb:SetPoint("TOPLEFT",  f, "TOPLEFT",  14, -44)
    searchEb:SetPoint("TOPRIGHT", resetBtn, "TOPLEFT", -4, 0)

    -- $parentResize
    local resizeBtn = CreateFrame("Button", name .. "Resize", f)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:GetNormalTexture():SetAllPoints(resizeBtn)
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:GetPushedTexture():SetAllPoints(resizeBtn)
    local resizeHt = resizeBtn:CreateTexture(nil, "HIGHLIGHT")
    resizeHt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeHt:SetBlendMode("ADD")
    resizeHt:SetAllPoints(resizeBtn)
    resizeBtn:SetHighlightTexture(resizeHt)

    resizeBtn:SetScript("OnLoad", function(self)
        self:SetFrameLevel(self:GetFrameLevel() + 4)
        self:GetNormalTexture():SetVertexColor(1, 0.82, 0)
    end)
    resizeBtn:SetScript("OnMouseDown", function(self)
        self:GetParent():StartSizing()
    end)
    resizeBtn:SetScript("OnMouseUp", function(self)
        self:GetParent():StopMovingOrSizing()
    end)

    -- OnSizeChanged
    f:SetScript("OnSizeChanged", function(self)
        self:OnSizeChanged(self:GetWidth(), self:GetHeight())
    end)

    return f
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
-- ITEM SLOT CLASS
-- ============================================================================


-- ============================================================================
-- ITEM FRAME EVENTS
-- ============================================================================


-- ============================================================================
-- ITEM FRAME CLASS (grid of items)
-- ============================================================================


-- ============================================================================
-- BAG CLASS
-- ============================================================================


-- ============================================================================
-- MONEY FRAME
-- ============================================================================


-- ============================================================================
-- TOKEN BAR (honor/emblem tracking — retail-style currency bar)
-- ============================================================================


-- ============================================================================
-- QUALITY FILTER
-- ============================================================================


-- ============================================================================
-- SIDE FILTER (category tabs on left/right)
-- ============================================================================


-- ============================================================================
-- FRAME EVENTS (set configuration relay)
-- ============================================================================

do
    local FrameEvents = mod:NewModule("FrameEvents")
    local frames = {}

    function FrameEvents:Load()
        local CSet = mod("Sets")
        CSet:RegisterMessage(self, "COMBUCTOR_SET_ADD", "UpdateSets")
        CSet:RegisterMessage(self, "COMBUCTOR_SET_UPDATE", "UpdateSets")
        CSet:RegisterMessage(self, "COMBUCTOR_SET_REMOVE", "UpdateSets")
        CSet:RegisterMessage(self, "COMBUCTOR_CONFIG_SET_ADD", "UpdateSetConfig")
        CSet:RegisterMessage(self, "COMBUCTOR_CONFIG_SET_REMOVE", "UpdateSetConfig")
        CSet:RegisterMessage(self, "COMBUCTOR_SUBSET_ADD", "UpdateSubSets")
        CSet:RegisterMessage(self, "COMBUCTOR_SUBSET_UPDATE", "UpdateSubSets")
        CSet:RegisterMessage(self, "COMBUCTOR_SUBSET_REMOVE", "UpdateSubSets")
        CSet:RegisterMessage(self, "COMBUCTOR_CONFIG_SUBSET_ADD", "UpdateSubSetConfig")
        CSet:RegisterMessage(self, "COMBUCTOR_CONFIG_SUBSET_REMOVE", "UpdateSubSetConfig")
    end

    function FrameEvents:UpdateSets(msg, name)
        for f in self:GetFrames() do
            if f:HasSet(name) then f:UpdateSets() end
        end
    end

    function FrameEvents:UpdateSetConfig(msg, key, name)
        for f in self:GetFrames() do
            if f.key == key then f:UpdateSets() end
        end
    end

    function FrameEvents:UpdateSubSetConfig(msg, key, name, parent)
        for f in self:GetFrames() do
            if f.key == key and f:GetCategory() == parent then f:UpdateSubSets() end
        end
    end

    function FrameEvents:UpdateSubSets(msg, name, parent)
        for f in self:GetFrames() do
            if f:GetCategory() == parent then f:UpdateSubSets() end
        end
    end

    function FrameEvents:Register(f) frames[f] = true end
    function FrameEvents:Unregister(f) frames[f] = nil end
    function FrameEvents:GetFrames() return pairs(frames) end

    FrameEvents:Load()
end

-- ============================================================================
-- INVENTORY FRAME CLASS (main window)
-- ============================================================================

do
    local InventoryFrame = mod:NewClass("Frame")
    mod.Frame = InventoryFrame

    local CombuctorSet = mod("Sets")
    local FrameEvents = mod("FrameEvents")

    local BASE_WIDTH = 384
    local ITEM_FRAME_WIDTH_OFFSET = 354 - BASE_WIDTH
    local BASE_HEIGHT = 512
    local ITEM_FRAME_HEIGHT_OFFSET = 432 - BASE_HEIGHT

    local lastID = 1
    function InventoryFrame:New(titleText, settings, isBank, key)
        local f = self:Bind(CreateInventoryFrame(format("DragonUI_CombuctorFrame%d", lastID)))
        f:SetScript("OnShow", self.OnShow)
        f:SetScript("OnHide", self.OnHide)

        f.sets = settings
        f.isBank = isBank
        f.key = key
        f.titleText = titleText
        f.bagButtons = {}
        f.filter = { quality = 0 }

        f:SetWidth(settings.w or BASE_WIDTH)
        f:SetHeight(settings.h or BASE_HEIGHT)

        -- Override min resize to allow smaller heights than the NineSlice base
        f:SetMinResize(BASE_WIDTH, 350)

        f.title = _G[f:GetName() .. "Title"]
        f.sideFilter = mod.SideFilter:New(f, f:IsSideFilterOnLeft())
        f.bottomFilter = mod.BottomFilter:New(f)
        f.nameFilter = _G[f:GetName() .. "Search"]

        f.qualityFilter = mod.QualityFilter:New(f)
        f.qualityFilter:SetPoint("BOTTOMLEFT", 14, 10)

        f.itemFrame = mod.ItemFrame:New(f)
        f.itemFrame:SetPoint("TOPLEFT", 14, -70)

        -- Token bar (honor/emblem tracking) — inventory only, at the very bottom
        if not isBank then
            f.tokenBar = mod.TokenBar:New(f)
            f.tokenBar:SetSize(180, 19)
            f.tokenBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -9, 10)
        end

        -- Coinbox frame (pill background for money, shifted up when token bar exists)
        local coinY = not isBank and (10 + 19 + 3) or 10
        f.coinFrame = CreateFrame("Frame", nil, f)
        f.coinFrame:SetSize(180, 19)
        f.coinFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -9, coinY)

        local coinLeft = f.coinFrame:CreateTexture(nil, "BACKGROUND")
        coinLeft:SetSize(8, 19)
        coinLeft:SetPoint("LEFT", f.coinFrame, "LEFT")
        coinLeft:SetTexture(mod.CT.coinbox)
        coinLeft:SetTexCoord(0.03125, 0.53125, 0.289062, 0.554688)

        local coinRight = f.coinFrame:CreateTexture(nil, "BACKGROUND")
        coinRight:SetSize(8, 19)
        coinRight:SetPoint("RIGHT", f.coinFrame, "RIGHT")
        coinRight:SetTexture(mod.CT.coinbox)
        coinRight:SetTexCoord(0.03125, 0.53125, 0.570312, 0.835938)

        local coinMiddle = f.coinFrame:CreateTexture(nil, "BACKGROUND")
        coinMiddle:SetPoint("TOPLEFT", coinLeft, "TOPRIGHT")
        coinMiddle:SetPoint("BOTTOMRIGHT", coinRight, "BOTTOMLEFT")
        coinMiddle:SetTexture(mod.CT.coinbox)
        coinMiddle:SetTexCoord(0, 0.5, 0.0078125, 0.273438)

        f.moneyFrame = mod.MoneyFrame:New(f)
        f.moneyFrame:SetPoint("BOTTOMRIGHT", -12, coinY)

        f:UpdateTitleText()
        f:UpdateBagToggleHighlight()
        f:UpdateBagFrame()
        f.sideFilter:UpdateFilters()
        f:LoadPosition()
        f:UpdateClampInsets()

        lastID = lastID + 1
        tinsert(UISpecialFrames, f:GetName())
        return f
    end

    function InventoryFrame:UpdateTitleText()
        self.title:SetFormattedText(self.titleText, self:GetPlayer())
    end

    function InventoryFrame:OnTitleEnter(title)
        GameTooltip:SetOwner(title, "ANCHOR_LEFT")
        local text = title:GetText()
        if text then
            GameTooltip:SetText(text, 1, 1, 1)
        end
        GameTooltip:AddLine(mod.L.MoveTip)
        GameTooltip:AddLine(mod.L.ResetPositionTip)
        GameTooltip:Show()
    end

    function InventoryFrame:OnBagToggleClick(toggle, button)
        if button == "LeftButton" then
            _G[toggle:GetName() .. "Icon"]:SetTexCoord(0.075, 0.925, 0.075, 0.925)
            self:ToggleBagFrame()
        else
            if self.isBank then
                mod:Toggle(BACKPACK_CONTAINER)
            else
                mod:Toggle(BANK_CONTAINER)
            end
        end
    end

    function InventoryFrame:OnBagToggleEnter(toggle)
        GameTooltip:SetOwner(toggle, "ANCHOR_LEFT")
        GameTooltip:SetText(mod.L.Bags, 1, 1, 1)
        GameTooltip:AddLine(mod.L.BagToggle)
        if self.isBank then
            GameTooltip:AddLine(mod.L.InventoryToggle)
        else
            GameTooltip:AddLine(mod.L.BankToggle)
        end
        GameTooltip:Show()
    end

    function InventoryFrame:ToggleBagFrame()
        self.sets.showBags = not self.sets.showBags
        self:UpdateBagToggleHighlight()
        self:UpdateBagFrame()
    end

    function InventoryFrame:UpdateBagFrame()
        for i, bag in pairs(self.bagButtons) do
            self.bagButtons[i] = nil
            bag:Release()
        end
        if self.sets.showBags then
            for _, bagID in ipairs(self.sets.bags) do
                if bagID ~= KEYRING_CONTAINER then
                    local bag = mod.Bag:Get()
                    bag:Set(self, bagID)
                    tinsert(self.bagButtons, bag)
                end
            end
            for i, bag in ipairs(self.bagButtons) do
                bag:ClearAllPoints()
                if i > 1 then
                    bag:SetPoint("TOP", self.bagButtons[i - 1], "BOTTOM", 0, -6)
                else
                    bag:SetPoint("TOPRIGHT", -14, -70)
                end
                bag:Show()
            end
        end
        self:UpdateItemFrameSize()
    end

    function InventoryFrame:UpdateBagToggleHighlight()
        if self.sets.showBags then
            _G[self:GetName() .. "BagToggle"]:LockHighlight()
        else
            _G[self:GetName() .. "BagToggle"]:UnlockHighlight()
        end
    end

    function InventoryFrame:SetFilter(key, value)
        if self.filter[key] ~= value then
            self.filter[key] = value
            self.itemFrame:Regenerate()
            return true
        end
    end

    function InventoryFrame:GetFilter(key)
        return self.filter[key]
    end

    function InventoryFrame:SetPlayer(player)
        if self:GetPlayer() ~= player then
            self.player = player
            self:UpdateTitleText()
            self:UpdateBagFrame()
            self:UpdateSets()
            self.itemFrame:SetPlayer(player)
            self.moneyFrame:Update()
        end
    end

    function InventoryFrame:GetPlayer()
        return self.player or mod.playerName
    end

    function InventoryFrame:UpdateSets(category)
        self.sideFilter:UpdateFilters()
        self:SetCategory(category or self:GetCategory())
        self:UpdateSubSets()
    end

    function InventoryFrame:UpdateSubSets(subCategory)
        self.bottomFilter:UpdateFilters()
        self:SetSubCategory(subCategory or self:GetSubCategory())
    end

    function InventoryFrame:HasSet(name)
        for _, setName in self:GetSets() do
            if setName == name then return true end
        end
        return false
    end

    function InventoryFrame:HasSubSet(name, parent)
        if self:HasSet(parent) then
            local excludeSets = self:GetExcludedSubsets(parent)
            if excludeSets then
                for _, childSet in pairs(excludeSets) do
                    if childSet == name then return false end
                end
            end
            return true
        end
        return false
    end

    function InventoryFrame:GetSets()
        local profile = mod:GetProfile()
        return ipairs(profile[self.key].sets)
    end

    function InventoryFrame:GetExcludedSubsets(parent)
        local profile = mod:GetProfile()
        return profile[self.key].exclude[parent]
    end

    function InventoryFrame:SetCategory(name)
        if not (self:HasSet(name) and CombuctorSet:Get(name)) then
            name = self:GetDefaultCategory()
        end
        local set = name and CombuctorSet:Get(name)
        if self:SetFilter("rule", (set and set.rule) or nil) then
            self.category = name
            self.sideFilter:UpdateHighlight()
            self:UpdateSubSets()
        end
    end

    function InventoryFrame:GetCategory()
        return self.category or self:GetDefaultCategory()
    end

    function InventoryFrame:GetDefaultCategory()
        for _, set in CombuctorSet:GetParentSets() do
            if self:HasSet(set.name) then return set.name end
        end
    end

    function InventoryFrame:SetSubCategory(name)
        local parent = self:GetCategory()
        if not (parent and self:HasSubSet(name, parent) and CombuctorSet:Get(name, parent)) then
            name = self:GetDefaultSubCategory()
        end
        local set = name and CombuctorSet:Get(name, parent)
        if self:SetFilter("subRule", (set and set.rule) or nil) then
            self.subCategory = name
            self.bottomFilter:UpdateHighlight()
        end
    end

    function InventoryFrame:GetSubCategory()
        return self.subCategory or self:GetDefaultSubCategory()
    end

    function InventoryFrame:GetDefaultSubCategory()
        local parent = self:GetCategory()
        if parent then
            for _, set in CombuctorSet:GetChildSets(parent) do
                if self:HasSubSet(set.name, parent) then return set.name end
            end
        end
    end

    function InventoryFrame:AddQuality(quality)
        self:SetFilter("quality", self:GetFilter("quality") + quality)
        self.qualityFilter:UpdateHighlight()
    end

    function InventoryFrame:RemoveQuality(quality)
        self:SetFilter("quality", self:GetFilter("quality") - quality)
        self.qualityFilter:UpdateHighlight()
    end

    function InventoryFrame:SetQuality(quality)
        self:SetFilter("quality", quality)
        self.qualityFilter:UpdateHighlight()
    end

    function InventoryFrame:GetQuality()
        return self:GetFilter("quality") or 0
    end

    function InventoryFrame:OnSizeChanged()
        local w, h = self:GetWidth(), self:GetHeight()
        self.sets.w = w
        self.sets.h = h
        self:UpdateItemFrameSize()
    end

    function InventoryFrame:UpdateItemFrameSize()
        if not self.itemFrame then return end
        local prevW, prevH = self.itemFrame:GetWidth(), self.itemFrame:GetHeight()
        local newW = self:GetWidth() + ITEM_FRAME_WIDTH_OFFSET
        if next(self.bagButtons) then
            newW = newW - 36
        end
        local newH = self:GetHeight() + ITEM_FRAME_HEIGHT_OFFSET
        -- Reserve bottom space for token bar (19px) + gap (3px) when inventory (not bank)
        if not self.isBank and self.tokenBar then
            newH = newH - 25
        end
        if not (prevW == newW and prevH == newH) then
            self.itemFrame:SetWidth(newW)
            self.itemFrame:SetHeight(newH)
            self.itemFrame:RequestLayout()
        end
    end

    function InventoryFrame:UpdateClampInsets()
        local l, r, t, b
        -- Base bottom: room for coinFrame (19px at y=10) + padding
        local bottomBase = self.bottomFilter:IsShown() and 35 or 65
        -- Reserve extra space for token bar when inventory (not bank)
        if not self.isBank and self.tokenBar then
            bottomBase = bottomBase + 25
        end
        t, b = -15, bottomBase
        if self.sideFilter:IsShown() then
            if self.sideFilter:Reversed() then
                l, r = -20, -35
            else
                l, r = 15, 0
            end
        else
            l, r = 15, -35
        end
        self:SetClampRectInsets(l, r, t, b)
    end

    function InventoryFrame:SavePosition(point, parent, relPoint, x, y)
        if point then
            self.sets.position = { point, nil, relPoint, x, y }
        else
            self.sets.position = nil
        end
        self:LoadPosition()
    end

    function InventoryFrame:LoadPosition()
        if self.sets.position then
            local point, _, relPoint, x, y = unpack(self.sets.position)
            self:ClearAllPoints()
            self:SetPoint(point, self:GetParent(), relPoint, x, y)
            self:SetUserPlaced(true)
        else
            -- No saved position: anchor at a visible default so the frame actually renders
            self:ClearAllPoints()
            if self.isBank then
                self:SetPoint("LEFT", UIParent, "LEFT", 24, 0)
            else
                self:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -64, 64)
            end
            self:SetUserPlaced(nil)
        end
    end

    function InventoryFrame:OnShow()
        PlaySound("igBackPackOpen")
        FrameEvents:Register(self)
        self:UpdateSets(self:GetDefaultCategory())
    end

    function InventoryFrame:OnHide()
        PlaySound("igBackPackClose")
        FrameEvents:Unregister(self)
        if self:IsBank() and self:AtBank() then
            CloseBankFrame()
        end
        self:SetPlayer(mod.playerName)
    end

    function InventoryFrame:ToggleFrame(auto)
        if self:IsShown() then self:HideFrame(auto) else self:ShowFrame(auto) end
    end

    function InventoryFrame:ShowFrame(auto)
        if not self:IsShown() then
            ShowUIPanel(self)
            self.autoShown = auto or nil
        end
    end

    function InventoryFrame:HideFrame(auto)
        if self:IsShown() then
            if not auto or self.autoShown then
                HideUIPanel(self)
                self.autoShown = nil
            end
        end
    end

    function InventoryFrame:SetLeftSideFilter(enable)
        self.sets.leftSideFilter = enable and true or nil
        self.sideFilter:SetReversed(enable)
    end

    function InventoryFrame:IsSideFilterOnLeft()
        return self.sets.leftSideFilter
    end

    function InventoryFrame:IsBank()
        return self.isBank
    end

    function InventoryFrame:AtBank()
        return mod("PlayerInfo"):AtBank()
    end
end

local function CombuctorSkinFrame(frame)
    if not frame or frame._BagSkin_Combuctor then return end
    frame._BagSkin_Combuctor = true

    mod.CombuctorAddNineSlice(frame)

    -- Adjust NineSlice so it doesn't cover the header
    if frame._BagSkin_NineSlice then
        local ns = frame._BagSkin_NineSlice
        ns.Bg:SetPoint('TOPLEFT',     frame, 'TOPLEFT',     3, -18)
        ns.Bg:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -3, 3)
    end

    -- Icon/Portrait — shrink, move above nineslice background
    local icon = _G[frame:GetName() .. 'IconButton']
    if icon then
        icon:SetSize(36, 36)
        icon:ClearAllPoints()
        icon:SetPoint('TOPLEFT', frame, 'TOPLEFT', -4, 4)
        if icon.icon then
            icon.icon:SetSize(36, 36)
            icon.icon:SetDrawLayer('OVERLAY', 0)
        end
        icon:EnableMouse(true)
        -- Kill old SetupIconButton resize handlers that blow icon to 56-62px
        icon:SetScript('OnMouseDown', nil)
        icon:SetScript('OnMouseUp', nil)
        icon:SetScript('OnClick', function()
            ToggleCharacter('PaperDollFrame')
        end)
    end

    -- Bag border frame on top of icon
    if icon and not frame._BagSkin_PortraitBorder then
        local borderFrame = CreateFrame('Frame', nil, frame)
        borderFrame:SetSize(48, 48)
        borderFrame:SetPoint('TOPLEFT', frame, 'TOPLEFT', -10, 8)

        local iconLevel = 0
        if icon.GetFrameLevel then
            iconLevel = icon:GetFrameLevel()
        elseif frame.GetFrameLevel then
            iconLevel = frame:GetFrameLevel()
        end
        borderFrame:SetFrameLevel(iconLevel + 10)

        local pp = borderFrame:CreateTexture(nil, 'OVERLAY')
        pp:SetTexture(mod.CT.bag_border)
        pp:SetAllPoints(borderFrame)
        pp:SetDrawLayer('OVERLAY', 7)

        frame._BagSkin_PortraitBorder = borderFrame
    end

    -- CloseButton: reposition
    local close = _G[frame:GetName() .. 'CloseButton']
    if close then
        close:ClearAllPoints()
        close:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
    end

    -- Title: centered "Combuctor" label on the header border
    local title = _G[frame:GetName() .. 'Title']
    if title then
        title:SetText('Combuctor')
        title:ClearAllPoints()
        title:SetPoint('TOP', frame, 'TOP', 0, -5)
    end

    -- Bag toggle — reposition
    local bagToggle = _G[frame:GetName() .. 'BagToggle']
    if bagToggle then
        bagToggle:ClearAllPoints()
        bagToggle:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -14, -38)
    end

    -- Portrait click opens CharacterFrame
    local portBtn = _G[frame:GetName() .. 'PortraitButton']
    if portBtn then
        portBtn:EnableMouse(true)
        portBtn:SetScript('OnClick', function()
            ToggleCharacter('PaperDollFrame')
        end)
    end
end

local function CombuctorSkinItems(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == 'Frame' then
            for _, subchild in ipairs({ child:GetChildren() }) do
                if subchild:GetObjectType() == 'Button' and subchild:GetName() then
                    if subchild:GetName():find('DragonUI_CombuctorItem') then
                        mod.CombuctorRetailItemSlot(subchild)
                    end
                end
            end
        end
    end
end

local function CombuctorSkinBagSlots(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == 'Frame' then
            for _, subchild in ipairs({ child:GetChildren() }) do
                if subchild:GetObjectType() == 'Button' and subchild:GetName() then
                    local name = subchild:GetName()
                    if name:find('DragonUI_CombuctorBag') then
                        mod.CombuctorRetailBagSlot(subchild)
                    end
                end
            end
        end
    end
end

local function CombuctorApplySkin()
    -- Skin all existing Combuctor frames
    for i = 1, 2 do
        local frame = _G['DragonUI_CombuctorFrame' .. i]
        if frame then
            mod.CombuctorSkinFrame(frame)
            mod.CombuctorSkinItems(frame)
            mod.CombuctorSkinBagSlots(frame)
        end
    end

    -- Backpack button on main bar
    mod.CombuctorRetailBackpackButton()

    -- Character bag slots on action bar
    for i = 0, 3 do
        local slot = _G['CharacterBag' .. i .. 'Slot']
        if slot then
            mod.CombuctorRetailBagSlot(slot)
        end
    end
end

mod.CombuctorSkinFrame = CombuctorSkinFrame
mod.CombuctorSkinItems = CombuctorSkinItems
mod.CombuctorSkinBagSlots = CombuctorSkinBagSlots
mod.CombuctorApplySkin = CombuctorApplySkin

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
