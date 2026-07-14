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
-- ============================================================================
-- XML TEMPLATE EQUIVALENTS (replaces combuctor.xml entirely)
-- Builds frames with all properties previously defined in XML virtual templates.
-- ============================================================================

-- DragonUI_CombuctorSideTabButtonTemplate
local function SetupSideTabButton(btn)
    btn:SetSize(32, 32)
    btn:Hide()

    -- $parentBorder: SpellBook-SkillLineTab
    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    border:SetSize(64, 64)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 11)
    btn._BagSkin_SideBorder = border

    -- NormalTexture (blank so GetNormalTexture() works)
    btn:SetNormalTexture("")

    -- HighlightTexture
    local ht = btn:CreateTexture(nil, "HIGHLIGHT")
    ht:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    ht:SetBlendMode("ADD")
    btn:SetHighlightTexture(ht)

    -- CheckedTexture
    local ct = btn:CreateTexture(nil, "HIGHLIGHT")
    ct:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    ct:SetBlendMode("ADD")
    btn:SetCheckedTexture(ct)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltip)
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
end

local function DebugItemSlot(btn)
    local name = btn:GetName() or "?"
    print("=== " .. name .. " ===")
    print("NormalTexture:", btn:GetNormalTexture() and btn:GetNormalTexture():GetTexture() or "nil")
    local i = 0
    for _, region in ipairs({ btn:GetRegions() }) do
        i = i + 1
        if region:GetObjectType() == 'Texture' then
            local layer, sublayer = region:GetDrawLayer()
            print(string.format("  Region %d: layer=%s sublayer=%d tex=%s alpha=%.2f",
                i, layer, sublayer or 0,
                tostring(region:GetTexture()):sub(1, 40),
                region:GetAlpha()))
        end
    end
end

-- DragonUI_CombuctorFrameTabButtonTemplate
local function SetupBottomTabButton(btn)
    btn:SetFrameLevel(btn:GetFrameLevel() + 4)
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
-- QUALITY FLAGS
-- ============================================================================

mod.QualityFlags = {}
for i = 0, 7 do
    mod.QualityFlags[i] = 2 ^ i
end

-- ============================================================================
-- ITEM SLOT CLASS
-- ============================================================================

do
    local ItemSlot = mod:NewClass("Button")
    mod.ItemSlot = ItemSlot

    local BagSlotInfo = mod.BagSlotInfo
    local ItemSlotInfo = mod.ItemSlotInfo
    local PlayerInfo = mod("PlayerInfo")

    local unused = {}
    local id = 1

    local function DebugItemSlot(btn)
        local name = btn:GetName() or "?"
        print("=== " .. name .. " ===")
        print("NormalTexture:", btn:GetNormalTexture() and btn:GetNormalTexture():GetTexture() or "nil")
        local i = 0
        for _, region in ipairs({ btn:GetRegions() }) do
            i = i + 1
            if region:GetObjectType() == 'Texture' then
                local layer, sublayer = region:GetDrawLayer()
                print(string.format("  Region %d: layer=%s sublayer=%d tex=%s alpha=%.2f",
                    i, layer, sublayer or 0,
                    tostring(region:GetTexture()):sub(1, 40),
                    region:GetAlpha()))
            end
        end
    end

    function ItemSlot:GetNextItemSlotID()
        local nextID = id
        id = id + 1
        return nextID
    end

    function ItemSlot:New()
        local item = next(unused)
        if item then
            unused[item] = nil
            return item
        end

        local itemID = self:GetNextItemSlotID()
        local item = self:Bind(CreateFrame("Button", format("DragonUI_CombuctorItem%d", itemID), nil, "ContainerFrameItemButtonTemplate"))

        local name = item:GetName()
        item:SetID(itemID)
        item:SetScript("OnEnter", self.OnEnter)
        item:SetScript("OnLeave", self.OnLeave)
        item:SetScript("OnShow", self.OnShow)
        item:SetScript("OnHide", self.OnHide)
        item:SetScript("OnUpdate", self.OnUpdate)
        item:RegisterForClicks("anyUp")
        item.UpdateTooltip = nil

        -- Quality border (gold ring for uncommon+ items)
        local border = item:CreateTexture(nil, "OVERLAY")
        border:SetWidth(67)
        border:SetHeight(67)
        border:SetPoint("CENTER", item, "CENTER", 0, -1)
        border:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
        border:SetBlendMode("ADD")
        border:SetDrawLayer("OVERLAY", 3)
        border:Hide()
        item.border = border

        -- Kill template's built-in IconQuestTexture and IconBorder to avoid overlap
        local templateQuest = _G[name .. "IconQuestTexture"]
        if templateQuest then
            templateQuest:SetTexture(nil)
            templateQuest:Hide()
        end
        local templateBorder = _G[name .. "IconBorder"]
        if templateBorder then
            templateBorder:Hide()
        end

        -- Quest item border (yellow overlay for quest items)
        local questBorder = item:CreateTexture(nil, "OVERLAY")
        questBorder:SetSize(item:GetWidth(), item:GetHeight())
        questBorder:SetPoint("CENTER")
        questBorder:SetTexture(mod.TEXTURE_ITEM_QUEST_BORDER)
        questBorder:SetDrawLayer("OVERLAY", 4)
        questBorder:Hide()
        item.questBorder = questBorder

        -- Cooldown
        item.cooldown = _G[name .. "Cooldown"]

        return item
    end

    function ItemSlot:Free()
        self:Hide()
        self:SetParent(nil)
        self:UnlockHighlight()
        unused[self] = true
    end

    function ItemSlot:Set(parent, bag, slot)
        self:SetParent(ItemSlot:GetDummyBag(parent, bag))
        self:SetID(slot)
        self:Update()

        -- Apply retail skin from bags_skin module (if available).
        -- The _BagSkin_Applied guard prevents duplicate work.
        -- This is necessary because ItemSlots are created dynamically
        -- and mod.CombuctorSkinItems() may run before the slot exists.
        if not self._BagSkin_Applied then
            mod.CombuctorRetailItemSlot(self)
        end
    end

    function ItemSlot:OnShow()
        self:Update()
    end

    function ItemSlot:OnHide()
        if self.hasStackSplit and self.hasStackSplit == 1 then
            StackSplitFrame:Hide()
        end
    end

    function ItemSlot:OnEnter()
        local dummySlot = self:GetDummyItemSlot()
        if self:IsCached() then
            dummySlot:SetParent(self)
            dummySlot:SetAllPoints(self)
            dummySlot:Show()
        else
            dummySlot:Hide()
            self._lastShiftState = nil  -- reset so OnUpdate detects shift on first hover
            if self:IsBank() then
                -- BANK_CONTAINER slots: use SetInventoryItem (bank-specific API)
                if self:GetItem() then
                    self:AnchorTooltip()
                    GameTooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(self:GetID()))
                    GameTooltip:Show()
                    CursorUpdate(self)
                    if IsModifiedClick("COMPAREITEMS") then
                        GameTooltip_ShowCompareItem()
                    end
                    self.UpdateTooltip = self.OnEnter
                end
            else
                -- Inventory/bank-bag slots: native Blizzard handler correctly shows
                -- Soulbound, durability, and handles initial shift+compare
                ContainerFrameItemButton_OnEnter(self)
                -- Keep tooltip content in sync while the hovered slot updates
                -- (for example, right-click equip swaps the hovered item).
                self.UpdateTooltip = ContainerFrameItemButton_OnEnter
            end
        end
    end

    function ItemSlot:OnUpdate()
        -- Detect shift key state change WHILE hovering and show/hide the comparison
        -- tooltip WITHOUT rebuilding the main GameTooltip (which would corrupt
        -- Soulbound/durability text).
        if not self:IsMouseOver() or self:IsCached() then
            self._lastShiftState = nil
            return
        end
        if not GameTooltip:IsOwned(self) then return end
        local shiftDown = IsModifiedClick("COMPAREITEMS")
        if self._lastShiftState == shiftDown then return end
        self._lastShiftState = shiftDown
        if shiftDown then
            -- Shift just pressed: show comparison side-tooltip (does NOT touch main GameTooltip)
            GameTooltip_ShowCompareItem()
        else
            -- Shift released: hide comparison side-tooltips
            if GameTooltip.shoppingTooltips then
                for _, tt in ipairs(GameTooltip.shoppingTooltips) do
                    tt:Hide()
                end
            end
        end
    end

    function ItemSlot:OnLeave()
        self._lastShiftState = nil
        self.UpdateTooltip = nil
        GameTooltip:Hide()
        if GameTooltip.shoppingTooltips then
            for _, tt in ipairs(GameTooltip.shoppingTooltips) do
                tt:Hide()
            end
        end
        ResetCursor()
    end

    function ItemSlot:OnModifiedClick(button)
        local link = self:IsCached() and self:GetItem()
        if link then
            HandleModifiedItemClick(link)
        end
    end

    function ItemSlot:Update()
        if not self:IsVisible() then return end

        local texture, count, locked, quality, readable, lootable, link = self:GetItemSlotInfo()
        self:SetItem(link)
        self:SetTexture(texture)
        self:SetCount(count)
        self:SetLocked(locked)
        self:SetReadable(readable)
        self:SetBorderQuality(quality)
        self:UpdateSlotColor()
        self:UpdateCooldown()
        if GameTooltip:IsOwned(self) and self.UpdateTooltip then
            self:UpdateTooltip()
        end
    end

    function ItemSlot:SetItem(itemLink)
        self.hasItem = itemLink or nil
    end

    function ItemSlot:GetItem()
        return self.hasItem
    end

    function ItemSlot:SetTexture(texture)
        SetItemButtonTexture(self, texture)
    end

    function ItemSlot:GetEmptyItemTexture()
        return [[Interface\PaperDoll\UI-Backpack-EmptySlot]]
    end

    function ItemSlot:UpdateSlotColor()
        if (not self:GetItem()) and self:IsTradeBagSlot() then
            SetItemButtonTextureVertexColor(self, 0.5, 1, 0.5)
            return
        end
        SetItemButtonTextureVertexColor(self, 1, 1, 1)
    end

    function ItemSlot:SetCount(count)
        SetItemButtonCount(self, count)
    end

    function ItemSlot:SetReadable(readable)
        self.readable = readable
    end

    function ItemSlot:SetLocked(locked)
        SetItemButtonDesaturated(self, locked)
    end

    function ItemSlot:UpdateLocked()
        self:SetLocked(self:IsLocked())
    end

    function ItemSlot:IsLocked()
        return ItemSlotInfo:IsLocked(self:GetPlayer(), self:GetBag(), self:GetID())
    end

    function ItemSlot:UpdateCooldown()
        if self:GetItem() and not self:IsCached() then
            local start, duration, enable = GetContainerItemCooldown(self:GetBag(), self:GetID())
            CooldownFrame_SetTimer(self.cooldown, start or 0, duration or 0, enable or 0)
        else
            CooldownFrame_SetTimer(self.cooldown, 0, 0, 0)
            SetItemButtonTextureVertexColor(self, 1, 1, 1)
        end
    end

    function ItemSlot:SetBorderQuality(quality)
        local border = self.border
        local qBorder = self.questBorder

        -- Quest item check
        local isQuestItem, isQuestStarter = self:IsQuestItem()
        if isQuestItem then
            qBorder:SetTexture(mod.TEXTURE_ITEM_QUEST_BORDER)
            qBorder:SetAlpha(0.5)
            qBorder:Show()
            border:Hide()
            return
        end
        if isQuestStarter then
            qBorder:SetTexture(mod.TEXTURE_ITEM_QUEST_BANG)
            qBorder:SetAlpha(0.5)
            qBorder:Show()
            border:Hide()
            return
        end

        -- Quality border
        if self:GetItem() and quality and quality > 1 then
            local r, g, b = GetItemQualityColor(quality)
            border:SetVertexColor(r, g, b, 0.5)
            border:Show()
            qBorder:Hide()
            return
        end

        qBorder:Hide()
        border:Hide()
    end

    function ItemSlot:UpdateBorder()
        local _, _, _, quality = self:GetItemSlotInfo()
        self:SetBorderQuality(quality)
    end

    -- UpdateTooltip is set to nil per-instance in Create() to prevent
    -- Update() from re-triggering OnEnter and clearing bank tooltips.
    ItemSlot.UpdateTooltip = nil

    function ItemSlot:AnchorTooltip()
        if self:GetRight() >= (GetScreenWidth() / 2) then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        end
    end

    function ItemSlot:Highlight(enable)
        if enable then
            self:LockHighlight()
        else
            self:UnlockHighlight()
        end
    end

    function ItemSlot:GetPlayer()
        local player
        if self:GetParent() then
            local p = self:GetParent():GetParent()
            player = p and p.GetPlayer and p:GetPlayer()
        end
        return player or mod.playerName
    end

    function ItemSlot:GetBag()
        return self:GetParent() and self:GetParent():GetID() or -1
    end

    function ItemSlot:IsSlot(bag, slot)
        return self:GetBag() == bag and self:GetID() == slot
    end

    function ItemSlot:IsCached()
        return BagSlotInfo:IsCached(self:GetPlayer(), self:GetBag())
    end

    function ItemSlot:IsBank()
        return BagSlotInfo:IsBank(self:GetBag())
    end

    function ItemSlot:IsBankSlot()
        local bag = self:GetBag()
        return BagSlotInfo:IsBank(bag) or BagSlotInfo:IsBankBag(bag)
    end

    function ItemSlot:AtBank()
        return PlayerInfo:AtBank()
    end

    function ItemSlot:GetItemSlotInfo()
        return ItemSlotInfo:GetItemInfo(self:GetPlayer(), self:GetBag(), self:GetID())
    end

    local QUEST_ITEM_SEARCH = format("t:%s|%s", select(10, GetAuctionItemClasses()), "quest")
    function ItemSlot:IsQuestItem()
        local itemLink = self:GetItem()
        if not itemLink then return false, false end
        if self:IsCached() then
            return mod.ItemSearch:Find(itemLink, QUEST_ITEM_SEARCH), false
        else
            local isQuestItem, questID, isActive = GetContainerItemQuestInfo(self:GetBag(), self:GetID())
            return isQuestItem, (questID and not isActive)
        end
    end

    function ItemSlot:IsTradeBagSlot()
        return BagSlotInfo:IsTradeBag(self:GetPlayer(), self:GetBag())
    end

    function ItemSlot:GetDummyBag(parent, bag)
        local dummyBags = parent.dummyBags
        if not dummyBags then
            dummyBags = setmetatable({}, { __index = function(t, k)
                local f = CreateFrame("Frame", nil, parent)
                f:SetID(k)
                t[k] = f
                return f
            end })
            parent.dummyBags = dummyBags
        end
        return dummyBags[bag]
    end

    function ItemSlot:GetDummyItemSlot()
        if not ItemSlot.dummySlot then
            ItemSlot.dummySlot = ItemSlot:CreateDummyItemSlot()
        end
        return ItemSlot.dummySlot
    end

    function ItemSlot:CreateDummyItemSlot()
        local slot = CreateFrame("Button")
        slot:RegisterForClicks("anyUp")
        slot:SetToplevel(true)
        slot:Hide()

        local function Slot_OnEnter(self)
            local parent = self:GetParent()
            parent:LockHighlight()
            if parent:IsCached() and parent:GetItem() then
                ItemSlot.AnchorTooltip(self)
                GameTooltip:SetHyperlink(parent:GetItem())
                GameTooltip:Show()
            end
        end

        local function Slot_OnLeave(self)
            GameTooltip:Hide()
            self:Hide()
        end

        local function Slot_OnHide(self)
            local parent = self:GetParent()
            if parent then parent:UnlockHighlight() end
        end

        local function Slot_OnClick(self, button)
            self:GetParent():OnModifiedClick(button)
        end

        slot.UpdateTooltip = Slot_OnEnter
        slot:SetScript("OnClick", Slot_OnClick)
        slot:SetScript("OnEnter", Slot_OnEnter)
        slot:SetScript("OnLeave", Slot_OnLeave)
        slot:SetScript("OnShow", Slot_OnEnter)
        slot:SetScript("OnHide", Slot_OnHide)

        return slot
    end
end

-- ============================================================================
-- ITEM FRAME EVENTS
-- ============================================================================

do
    local FrameEvents = mod:NewModule("ItemFrameEvents")
    local frames = {}

    function FrameEvents:ITEM_LOCK_CHANGED(msg, ...) self:UpdateSlotLock(...) end
    function FrameEvents:ITEM_SLOT_ADD(msg, ...) self:UpdateSlot(...) end
    function FrameEvents:ITEM_SLOT_REMOVE(msg, ...) self:RemoveItem(...) end

    function FrameEvents:ITEM_SLOT_UPDATE(msg, ...) self:UpdateSlot(...) end
    function FrameEvents:ITEM_SLOT_UPDATE_COOLDOWN(msg, ...) self:UpdateSlotCooldown(...) end
    function FrameEvents:BANK_OPENED(msg, ...) self:UpdateBankFrames(...) end
    function FrameEvents:BANK_CLOSED(msg, ...) self:UpdateBankFrames(...) end
    function FrameEvents:BAG_UPDATE_TYPE(msg, ...) self:UpdateSlotColor(...) end
    function FrameEvents:BAG_EMPTIED(msg, bag, prevSize)
        for f in self:GetFrames() do
            if f:GetPlayer() == mod.playerName then
                -- Remove stale items first (Regenerate won't clean them
                -- because GetBagSize(bag) returns 0 for unequipped bags,
                -- so the bag's items would remain in self.items).
                for slot = 1, prevSize do
                    f:RemoveItem(bag, slot)
                end
                f:Regenerate()
                f:RequestLayout()
            end
        end
    end

    function FrameEvents:UpdateSlotColor(...)
        for f in self:GetFrames() do
            if f:GetPlayer() == mod.playerName then f:UpdateSlotColor(...) end
        end
    end

    function FrameEvents:UpdateSlot(...)
        for f in self:GetFrames() do
            if f:GetPlayer() == mod.playerName then
                if f:UpdateSlot(...) then f:RequestLayout() end
            end
        end
    end

    function FrameEvents:RemoveItem(...)
        for f in self:GetFrames() do
            if f:GetPlayer() == mod.playerName then
                if f:RemoveItem(...) then f:RequestLayout() end
            end
        end
    end

    function FrameEvents:UpdateSlotLock(...)
        for f in self:GetFrames() do
            if f:GetPlayer() == mod.playerName then f:UpdateSlotLock(...) end
        end
    end

    function FrameEvents:UpdateSlotCooldown(...)
        for f in self:GetFrames() do
            if f:GetPlayer() == mod.playerName then f:UpdateSlotCooldown(...) end
        end
    end

    function FrameEvents:UpdateBankFrames()
        for f in self:GetFrames() do f:Regenerate() end
    end

    function FrameEvents:LayoutFrames()
        for f in self:GetFrames() do
            if f.needsLayout then
                f.needsLayout = nil
                f:Layout()
            end
        end
    end

    function FrameEvents:RequestLayout()
        self.Updater:Show()
    end

    function FrameEvents:GetFrames()
        return pairs(frames)
    end

    function FrameEvents:Register(f)
        frames[f] = true
    end

    function FrameEvents:Unregister(f)
        frames[f] = nil
    end

    -- Initialization
    do
        local f = CreateFrame("Frame")
        f:Hide()
        f:SetScript("OnEvent", function(self, event, ...)
            local method = FrameEvents[event]
            if method then method(FrameEvents, event, ...) end
        end)
        f:SetScript("OnUpdate", function(self)
            FrameEvents:LayoutFrames()
            self:Hide()
        end)
        f:RegisterEvent("ITEM_LOCK_CHANGED")
        f:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
        f:RegisterEvent("QUEST_ACCEPTED")
        FrameEvents.Updater = f

        mod("InventoryEvents"):RegisterMany(
            FrameEvents,
            "ITEM_SLOT_ADD", "ITEM_SLOT_REMOVE", "ITEM_SLOT_UPDATE",
            "ITEM_SLOT_UPDATE_COOLDOWN", "BANK_OPENED", "BANK_CLOSED", "BAG_UPDATE_TYPE",
            "BAG_EMPTIED"
        )
    end
end

-- ============================================================================
-- ITEM FRAME CLASS (grid of items)
-- ============================================================================

do
    local ItemFrame = mod:NewClass("Button")
    mod.ItemFrame = ItemFrame

    local FrameEvents = mod("ItemFrameEvents")
    local BagSlotInfo = mod.BagSlotInfo
    local ItemSlotInfo = mod.ItemSlotInfo

    local function ToIndex(bag, slot)
        return (bag < 0 and bag * 100 - slot) or (bag * 100 + slot)
    end

    function ItemFrame:New(parent)
        local f = self:Bind(CreateFrame("Button", nil, parent))
        f.items = {}
        f.bags = parent.sets.bags
        f.filter = parent.filter
        f.count = 0
        f:RegisterForClicks("anyUp")
        f:SetScript("OnShow", self.OnShow)
        f:SetScript("OnHide", self.OnHide)
        f:SetScript("OnClick", self.PlaceItem)
        return f
    end

    function ItemFrame:OnShow()
        self:UpdateUpdatable()
        self:Regenerate()
    end

    function ItemFrame:OnHide()
        self:UpdateUpdatable()
    end

    function ItemFrame:UpdateUpdatable()
        if self:IsVisible() then
            FrameEvents:Register(self)
        else
            FrameEvents:Unregister(self)
        end
    end

    function ItemFrame:SetPlayer(player)
        self.player = player
        self:ReloadAllItems()
    end

    function ItemFrame:GetPlayer()
        return self.player or mod.playerName
    end

    function ItemFrame:HasItem(bag, slot, link)
        local hasBag = false
        for _, bagID in pairs(self.bags) do
            if bag == bagID then hasBag = true; break end
        end
        if not hasBag then return false end

        local f = self.filter
        if next(f) then
            local player = self:GetPlayer()
            local bagType = self:GetBagType(bag)
            link = link or self:GetItemLink(bag, slot)

            local name, quality, level, ilvl, itemType, subType, stackCount, equipLoc
            if link then
                name, link, quality, level, ilvl, itemType, subType, stackCount, equipLoc = GetItemInfo(link)
            end

            if f.quality and f.quality > 0 and not (quality and bit.band(f.quality, mod.QualityFlags[quality] or 0) > 0) then
                return false
            elseif f.rule and not f.rule(player, bagType, name, link, quality, level, ilvl, itemType, subType, stackCount, equipLoc) then
                return false
            elseif f.subRule and not f.subRule(player, bagType, name, link, quality, level, ilvl, itemType, subType, stackCount, equipLoc) then
                return false
            elseif f.name then
                return mod.ItemSearch:Find(link, f.name)
            end
        end
        return true
    end

    function ItemFrame:AddItem(bag, slot)
        local index = ToIndex(bag, slot)
        local item = self.items[index]
        if item then
            item:Update()
            item:Highlight(self.highlightBag == bag)
        else
            item = mod.ItemSlot:New()
            item:Set(self, bag, slot)
            item:Highlight(self.highlightBag == bag)
            self.items[index] = item
            self.count = self.count + 1
            return true
        end
    end

    function ItemFrame:RemoveItem(bag, slot)
        local index = ToIndex(bag, slot)
        local item = self.items[index]
        if item then
            item:Free()
            self.items[index] = nil
            self.count = self.count - 1
            return true
        end
    end

    function ItemFrame:UpdateSlot(bag, slot, link)
        if self:HasItem(bag, slot, link) then
            return self:AddItem(bag, slot)
        end
        return self:RemoveItem(bag, slot)
    end

    function ItemFrame:UpdateSlotLock(bag, slot)
        if not slot then return end
        local item = self.items[ToIndex(bag, slot)]
        if item then item:UpdateLocked() end
    end

    function ItemFrame:UpdateSlotCooldown(bag, slot)
        local item = self.items[ToIndex(bag, slot)]
        if item then item:UpdateCooldown() end
    end

    function ItemFrame:UpdateSlotColor(bagId)
        for _, item in pairs(self.items) do
            if item:GetBag() == bagId then item:UpdateSlotColor() end
        end
    end

    function ItemFrame:Regenerate()
        if not self:IsVisible() then return end
        local changed = false
        for _, bag in pairs(self.bags) do
            for slot = 1, self:GetBagSize(bag) do
                if self:UpdateSlot(bag, slot) then changed = true end
            end
        end
        if changed then self:RequestLayout() end
    end

    function ItemFrame:RemoveAllItems()
        local changed = false
        for i, item in pairs(self.items) do
            changed = true
            item:Free()
            self.items[i] = nil
        end
        self.count = 0
        return changed
    end

    function ItemFrame:ReloadAllItems()
        if self:RemoveAllItems() and self:IsVisible() then
            self:Regenerate()
        end
    end

    function ItemFrame:RequestLayout()
        self.needsLayout = true
        self:TriggerLayout()
    end

    function ItemFrame:TriggerLayout()
        if self:IsVisible() and self.needsLayout then
            FrameEvents:RequestLayout(self)
        end
    end

    function ItemFrame:Layout(spacing)
        local width, height = self:GetWidth(), self:GetHeight()
        spacing = spacing or 2
        local count = self.count
        local size = 36 + spacing * 2
        local cols = 0
        local scale, rows
        local maxScale = mod:GetMaxItemScale()

        repeat
            cols = cols + 1
            scale = width / (size * cols)
            rows = floor(height / (size * scale))
        until (scale <= maxScale and cols * rows >= count)

        local items = self.items
        local i = 0

        for _, bag in ipairs(self.bags) do
            for slot = 1, self:GetBagSize(bag) do
                local item = items[ToIndex(bag, slot)]
                if item then
                    i = i + 1
                    local row = (i - 1) % cols
                    local col = ceil(i / cols) - 1
                    item:ClearAllPoints()
                    item:SetScale(scale)
                    item:SetPoint("TOPLEFT", self, "TOPLEFT", size * row + spacing, -(size * col + spacing))
                    item:Show()
                end
            end
        end
    end

    function ItemFrame:HighlightBag(bag)
        self.highlightBag = bag
        for _, item in pairs(self.items) do
            item:Highlight(item:GetBag() == bag)
        end
    end

    function ItemFrame:GetBagSize(bag)
        return BagSlotInfo:GetSize(self:GetPlayer(), bag)
    end

    function ItemFrame:GetBagType(bag)
        return BagSlotInfo:GetBagType(self:GetPlayer(), bag)
    end

    function ItemFrame:IsBagCached(bag)
        return BagSlotInfo:IsCached(self:GetPlayer(), bag)
    end

    function ItemFrame:GetItemLink(bag, slot)
        return select(7, ItemSlotInfo:GetItemInfo(self:GetPlayer(), bag, slot))
    end

    function ItemFrame:PlaceItem()
        if CursorHasItem() then
            for _, bag in ipairs(self.bags) do
                if not self:IsBagCached(bag) then
                    for slot = 1, self:GetBagSize(bag) do
                        if not GetContainerItemLink(bag, slot) then
                            PickupContainerItem(bag, slot)
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- BAG CLASS
-- ============================================================================

do
    local Bag = mod:NewClass("Button")
    mod.Bag = Bag

    local SIZE = 30
    local NORMAL_TEXTURE_SIZE = 64 * (SIZE / 36)
    local BagSlotInfo = mod.BagSlotInfo
    local unused = {}
    local bagId = 1

    function Bag:New()
        local bag = self:Bind(CreateFrame("Button", format("DragonUI_CombuctorBag%d", bagId)))
        local name = bag:GetName()
        bag:SetSize(SIZE, SIZE)

        -- Expand hit rect to match the visual NormalTexture size
        local inset = (SIZE - NORMAL_TEXTURE_SIZE) / 2
        bag:SetHitRectInsets(inset, inset, inset, inset)

        local icon = bag:CreateTexture(name .. "IconTexture", "BORDER")
        icon:SetAllPoints(bag)

        local count = bag:CreateFontString(name .. "Count", "OVERLAY")
        count:SetFontObject("NumberFontNormalSmall")
        count:SetJustifyH("RIGHT")
        count:SetPoint("BOTTOMRIGHT", -2, 2)

        -- Bag toggle buttons get NO NormalTexture/PushedTexture/HighlightTexture.
        -- Only the IconTexture (bag icon) is shown — clean, no background frame.
        -- Retail skinning is handled independently by bags_skin.lua if enabled.
        local nt = bag:CreateTexture(name .. "NormalTexture")
        nt:SetTexture(nil)
        nt:SetAlpha(0)
        nt:Hide()
        bag:SetNormalTexture(nt)

        local pt = bag:CreateTexture()
        pt:SetTexture(nil)
        pt:SetAlpha(0)
        pt:Hide()
        bag:SetPushedTexture(pt)

        local ht = bag:CreateTexture()
        ht:SetTexture(nil)
        ht:SetAlpha(0)
        ht:Hide()
        bag:SetHighlightTexture(ht)

        bag:RegisterForClicks("anyUp")
        bag:RegisterForDrag("LeftButton")

        bag:SetScript("OnEnter", self.OnEnter)
        bag:SetScript("OnShow", self.OnShow)
        bag:SetScript("OnLeave", self.OnLeave)
        bag:SetScript("OnClick", self.OnClick)
        bag:SetScript("OnDragStart", self.OnDrag)
        bag:SetScript("OnReceiveDrag", self.OnClick)
        bag:SetScript("OnEvent", self.OnEvent)

        bagId = bagId + 1
        return bag
    end

    function Bag:Get()
        local f = next(unused)
        if f then
            unused[f] = nil
            return f
        end
        return self:New()
    end

    function Bag:Set(parent, id)
        self:SetID(id)
        self:SetParent(parent)

        if BagSlotInfo:IsBank(id) or BagSlotInfo:IsBackpack(id) then
            SetItemButtonTexture(self, [[Interface\Buttons\Button-Backpack-Up]])
            SetItemButtonTextureVertexColor(self, 1, 1, 1)
        else
            self:Update()
            self:RegisterEvent("ITEM_LOCK_CHANGED")
            self:RegisterEvent("CURSOR_UPDATE")
            self:RegisterEvent("BAG_UPDATE")
            self:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
            if BagSlotInfo:IsBankBag(id) then
                self:RegisterEvent("BANKFRAME_OPENED")
                self:RegisterEvent("BANKFRAME_CLOSED")
                self:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
            end

            -- NOTE: Bag toggle dropdown buttons (DragonUI_CombuctorBag1-5)
            -- have blank NormalTexture by default (only icon visible).
            -- CharacterBag0-3Slot skinning is handled by bags_skin.lua.
        end
    end

    function Bag:Release()
        self:Hide()
        self:SetParent(nil)
        self:UnregisterAllEvents()
        _G[self:GetName() .. "Count"]:Hide()
        unused[self] = true
    end

    -- Helper to get the correct inventory slot
    function Bag:GetInventorySlot()
        return BagSlotInfo:ToInventorySlot(self:GetID())
    end

    function Bag:IsBagSlot()
        local id = self:GetID()
        return BagSlotInfo:IsBackpackBag(id) or BagSlotInfo:IsBankBag(id)
    end

    function Bag:IsPurchasable()
        return BagSlotInfo:IsPurchasable(mod.playerName, self:GetID())
    end

    function Bag:Update()
        if not self:IsVisible() then return end
        local id = self:GetID()
        if BagSlotInfo:IsBackpack(id) or BagSlotInfo:IsBank(id) then return end

        -- Actualizar bloqueo
        if self:IsBagSlot() then
            SetItemButtonDesaturated(self, BagSlotInfo:IsLocked(mod.playerName, id))
        end

        -- Update slot info (texture)
        if self:IsBagSlot() then
            local link, count, texture = BagSlotInfo:GetItemInfo(mod.playerName, id)
            if link then
                SetItemButtonTexture(self, texture or GetItemIcon(link))
                SetItemButtonTextureVertexColor(self, 1, 1, 1)
            else
                SetItemButtonTexture(self, [[Interface\PaperDoll\UI-PaperDoll-Slot-Bag]])
                if self:IsPurchasable() then
                    SetItemButtonTextureVertexColor(self, 1, 0.1, 0.1)
                else
                    SetItemButtonTextureVertexColor(self, 1, 1, 1)
                end
            end
        end

        -- Update cursor highlight
        if self:IsBagSlot() then
            local invSlot = self:GetInventorySlot()
            if invSlot and CursorCanGoInSlot(invSlot) then
                self:LockHighlight()
            else
                self:UnlockHighlight()
            end
        end
    end

    function Bag:OnShow()
        self:Update()
    end

    function Bag:OnEnter()
        local id = self:GetID()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if BagSlotInfo:IsBackpack(id) or BagSlotInfo:IsBank(id) then
            GameTooltip:SetText(BACKPACK_TOOLTIP)
        else
            local invSlot = self:GetInventorySlot()
            if invSlot then
                if not GameTooltip:SetInventoryItem("player", invSlot) then
                    if self:IsPurchasable() then
                        GameTooltip:SetText(BANK_BAG_PURCHASE, 1, 1, 1)
                    else
                        GameTooltip:SetText(EQUIP_CONTAINER)
                    end
                end
            else
                GameTooltip:SetText(EQUIP_CONTAINER)
            end
        end
        GameTooltip:Show()
        -- Highlight items in this bag
        local parent = self:GetParent()
        if parent and parent.itemFrame then
            parent.itemFrame:HighlightBag(id)
        end
    end

    function Bag:OnLeave()
        if GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
        local parent = self:GetParent()
        if parent and parent.itemFrame then
            parent.itemFrame:HighlightBag(nil)
        end
    end

    function Bag:OnClick(button)
        local id = self:GetID()
        if BagSlotInfo:IsBackpack(id) or BagSlotInfo:IsBank(id) then return end

        if self:IsPurchasable() then
            self:PurchaseSlot()
        elseif CursorHasItem() then
            local invSlot = self:GetInventorySlot()
            if invSlot then
                PutItemInBag(invSlot)
            end
        else
            local invSlot = self:GetInventorySlot()
            if invSlot then
                PickupBagFromSlot(invSlot)
            end
        end
    end

    function Bag:OnDrag()
        local id = self:GetID()
        if not (BagSlotInfo:IsBackpack(id) or BagSlotInfo:IsBank(id)) then
            local invSlot = self:GetInventorySlot()
            if invSlot then
                PickupBagFromSlot(invSlot)
            end
        end
    end

    function Bag:PurchaseSlot()
        if not StaticPopupDialogs["CONFIRM_BUY_BANK_SLOT_COMBUCTOR"] then
            StaticPopupDialogs["CONFIRM_BUY_BANK_SLOT_COMBUCTOR"] = {
                text = CONFIRM_BUY_BANK_SLOT,
                button1 = YES,
                button2 = NO,
                OnAccept = function()
                    PurchaseSlot()
                end,
                OnShow = function(self)
                    MoneyFrame_Update(self:GetName() .. "MoneyFrame", GetBankSlotCost(GetNumBankSlots()))
                end,
                hasMoneyFrame = 1,
                timeout = 0,
                hideOnEscape = 1
            }
        end
        PlaySound("igMainMenuOption")
        StaticPopup_Show("CONFIRM_BUY_BANK_SLOT_COMBUCTOR")
    end

    function Bag:OnEvent(event)
        self:Update()
    end
end

-- ============================================================================
-- MONEY FRAME
-- ============================================================================

do
    local MoneyFrame = mod:NewClass("Frame")
    mod.MoneyFrame = MoneyFrame

    local moneyId = 1

    function MoneyFrame:OnShow()
        self:Update()
    end

    function MoneyFrame:GetDisplayMode()
        local mc = addon.db and addon.db.profile and addon.db.profile.modules and addon.db.profile.modules.combuctor
        return (mc and mc.money_display) or "icons"
    end

    function MoneyFrame:New(parent)
        local f = self:Bind(CreateFrame("Frame", format("DragonUI_CombuctorMoney%d", moneyId), parent))
        f:SetHeight(19)
        f:SetWidth(120)
        f:SetScript("OnShow", self.OnShow)
        f:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_MONEY" then
                self:Update()
            end
        end)
        f:RegisterEvent("PLAYER_MONEY")
        f:SetFrameLevel(f:GetFrameLevel() + 4)

        -- Coin textures use DragonUI retail-style round icons (20x20 on 32x32 canvas)
        local COIN_TEXCOORD = { 0.1875, 0.8125, 0.1875, 0.8125 }

        -- Copper (ancla a la derecha)
        f.iconCopper = f:CreateTexture(nil, "OVERLAY")
        f.iconCopper:SetTexture(mod.CT.coinCopper)
        f.iconCopper:SetTexCoord(unpack(COIN_TEXCOORD))
        f.iconCopper:SetSize(13, 13)
        f.iconCopper:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        f.amtCopper = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.amtCopper:SetPoint("RIGHT", f.iconCopper, "LEFT", -2, 0)

        -- Silver
        f.iconSilver = f:CreateTexture(nil, "OVERLAY")
        f.iconSilver:SetTexture(mod.CT.coinSilver)
        f.iconSilver:SetTexCoord(unpack(COIN_TEXCOORD))
        f.iconSilver:SetSize(13, 13)
        f.iconSilver:SetPoint("RIGHT", f.amtCopper, "LEFT", -4, 0)
        f.amtSilver = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.amtSilver:SetPoint("RIGHT", f.iconSilver, "LEFT", -2, 0)

        -- Gold
        f.iconGold = f:CreateTexture(nil, "OVERLAY")
        f.iconGold:SetTexture(mod.CT.coinGold)
        f.iconGold:SetTexCoord(unpack(COIN_TEXCOORD))
        f.iconGold:SetSize(13, 13)
        f.iconGold:SetPoint("RIGHT", f.amtSilver, "LEFT", -4, 0)
        f.amtGold = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.amtGold:SetPoint("RIGHT", f.iconGold, "LEFT", -2, 0)

        local txt = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetAllPoints(f)
        txt:SetJustifyH("RIGHT")
        txt:SetJustifyV("MIDDLE")
        txt:Hide()
        f.textFull = txt

        moneyId = moneyId + 1
        f:Update()
        return f
    end

    function MoneyFrame:Update()
        local money = mod("PlayerInfo"):GetMoney(self:GetParent():GetPlayer())
        local mode = self:GetDisplayMode()

        local gold   = floor(money / 10000)
        local silver = floor((money % 10000) / 100)
        local copper = money % 100

        if mode == "text" then
            self.iconGold:Hide();  self.amtGold:Hide()
            self.iconSilver:Hide(); self.amtSilver:Hide()
            self.iconCopper:Hide(); self.amtCopper:Hide()

            self.textFull:SetText(format("|cffffd700%d %s |r|cffc7c7cf%d %s |r|cffeda55f%d %s|r",
                gold, "g", silver, "s", copper, "c"))
            self.textFull:Show()
        else
            self.textFull:Hide()

            -- Gold: solo se muestra si hay > 0
            if gold > 0 then
                self.iconGold:Show(); self.amtGold:Show()
                self.amtGold:SetText(gold)
            else
                self.iconGold:Hide(); self.amtGold:Hide()
            end

            -- Silver: se muestra si hay gold O si hay silver
            if gold > 0 or silver > 0 then
                self.iconSilver:Show(); self.amtSilver:Show()
                self.amtSilver:SetText(silver)
            else
                self.iconSilver:Hide(); self.amtSilver:Hide()
            end

            -- Copper: siempre se muestra
            self.iconCopper:Show(); self.amtCopper:Show()
            self.amtCopper:SetText(copper)
        end
    end

    function MoneyFrame:RefreshDisplay()
        if self:IsShown() then
            self:Update()
        end
    end
end

-- ============================================================================
-- TOKEN BAR (honor/emblem tracking — retail-style currency bar)
-- ============================================================================

do
    local TokenBar = mod:NewClass("Frame")
    local MAX_WATCHED_TOKENS = MAX_WATCHED_TOKENS or 20

    local TOKENBAR_HEIGHT = 19
    local TOKEN_ICON_SIZE = 14
    local TOKEN_GAP = 6

    -- Build the three-piece chrome pill background (same as bags_skin.lua ApplyPillChrome)
    local function ApplyPillChrome(bar)
        if bar._dragonuiPill then return end
        bar._dragonuiPill = true

        local left = bar:CreateTexture(nil, "BACKGROUND")
        left:SetSize(8, TOKENBAR_HEIGHT)
        left:SetPoint("LEFT", bar, "LEFT")
        left:SetTexture(mod.CT.currencybox)
        left:SetTexCoord(0.03125, 0.53125, 0.289062, 0.554688)

        local right = bar:CreateTexture(nil, "BACKGROUND")
        right:SetSize(8, TOKENBAR_HEIGHT)
        right:SetPoint("RIGHT", bar, "RIGHT")
        right:SetTexture(mod.CT.currencybox)
        right:SetTexCoord(0.03125, 0.53125, 0.570312, 0.835938)

        local middle = bar:CreateTexture(nil, "BACKGROUND")
        middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
        middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
        middle:SetTexture(mod.CT.currencybox)
        middle:SetTexCoord(0, 0.5, 0.0078125, 0.273438)
    end

    function TokenBar:New(parent)
        local bar = self:Bind(CreateFrame("Frame", nil, parent))
        bar:SetHeight(TOKENBAR_HEIGHT)
        bar.tokenButtons = {}
        bar._tokenCount = 0

        ApplyPillChrome(bar)

        bar:SetScript("OnEvent", function(self, event)
            if event == "CURRENCY_DISPLAY_UPDATE" then
                self:Refresh()
            end
        end)
        bar:RegisterEvent("CURRENCY_DISPLAY_UPDATE")

        -- Also refresh when the frame is shown (e.g., after /reload or module toggle)
        bar:SetScript("OnShow", function(self)
            self:Refresh()
        end)

        return bar
    end

    function TokenBar:Refresh()
        local numTokens = 0
        for i = 1, MAX_WATCHED_TOKENS do
            local name, count, extraCurrencyType, icon = GetBackpackCurrencyInfo(i)
            if name then
                numTokens = numTokens + 1
                local btn = self.tokenButtons[i]
                if not btn then
                    btn = self:_CreateTokenButton(i)
                    self.tokenButtons[i] = btn
                end

                -- Icon selection (matches Blizzard BackpackTokenFrame logic)
                if extraCurrencyType == 1 then
                    btn.icon:SetTexture("Interface\\PVPFrame\\PVP-ArenaPoints-Icon")
                    btn.icon:SetTexCoord(0, 1, 0, 1)
                elseif extraCurrencyType == 2 then
                    local factionGroup = UnitFactionGroup("player")
                    if factionGroup then
                        btn.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. factionGroup)
                        btn.icon:SetTexCoord(0.03125, 0.59375, 0.03125, 0.59375)
                    else
                        btn.icon:SetTexCoord(0, 1, 0, 1)
                    end
                else
                    btn.icon:SetTexture(icon)
                    btn.icon:SetTexCoord(0, 1, 0, 1)
                end

                if count <= 99999 then
                    btn.count:SetText(count)
                else
                    btn.count:SetText("*")
                end
                btn:Show()
            else
                local btn = self.tokenButtons[i]
                if btn then
                    btn:Hide()
                end
            end
        end

        -- Layout visible buttons right-to-left (bar is right-anchored)
        local wasShown = self:IsShown()
        if numTokens > 0 then
            self._tokenCount = numTokens
            local previous = nil
            for i = 1, MAX_WATCHED_TOKENS do
                local btn = self.tokenButtons[i]
                if btn and btn:IsShown() then
                    btn:ClearAllPoints()
                    if previous then
                        btn:SetPoint("RIGHT", previous, "LEFT", -TOKEN_GAP, 0)
                    else
                        btn:SetPoint("RIGHT", self, "RIGHT", -10, 1)
                    end
                    previous = btn
                end
            end
            self:Show()
        else
            self._tokenCount = 0
            self:Hide()
        end
        -- Notify parent to relayout if visibility changed
        if wasShown ~= self:IsShown() then
            local parent = self:GetParent()
            if parent and parent.UpdateItemFrameSize then
                parent:UpdateItemFrameSize()
                parent:UpdateClampInsets()
            end
        end
    end

    function TokenBar:_CreateTokenButton(index)
        local btn = CreateFrame("Button", nil, self)
        btn:SetHeight(TOKENBAR_HEIGHT - 2)

        -- Count text on the right
        btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.count:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
        btn.count:SetJustifyH("RIGHT")

        -- Icon to the left of count
        btn.icon = btn:CreateTexture(nil, "OVERLAY")
        btn.icon:SetSize(TOKEN_ICON_SIZE, TOKEN_ICON_SIZE)
        btn.icon:SetPoint("RIGHT", btn.count, "LEFT", -3, 0)

        -- Set button width based on count text width
        btn.count:SetText("99999")
        btn:SetWidth(TOKEN_ICON_SIZE + 3 + btn.count:GetStringWidth() + 2)

        -- Tooltip on enter (show currency name)
        btn:SetScript("OnEnter", function(self)
            local id = self._tokenIndex
            if not id then return end
            local name = GetBackpackCurrencyInfo(id)
            if name then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(name, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        btn._tokenIndex = index

        return btn
    end

    -- Register with module
    mod.TokenBar = TokenBar
end

-- ============================================================================
-- QUALITY FILTER
-- ============================================================================

do
    local FilterButton = mod:NewClass("CheckButton")
    local SIZE = 20
    local IsModifierKeyDown = IsModifierKeyDown

    function FilterButton:Create(parent, quality, qualityFlag)
        local button = self:Bind(CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate"))
        button:SetWidth(SIZE)
        button:SetHeight(SIZE)
        button:SetScript("OnClick", self.OnClick)
        button:SetScript("OnEnter", self.OnEnter)
        button:SetScript("OnLeave", self.OnLeave)

        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetSize(SIZE / 3, SIZE / 3)
        bg:SetPoint("CENTER")

        local r, g, b = GetItemQualityColor(quality)
        bg:SetTexture(r * 1.25, g * 1.25, b * 1.25, 0.75)

        button:SetCheckedTexture(bg)
        button:GetNormalTexture():SetVertexColor(r, g, b)

        button.quality = quality
        button.qualityFlag = qualityFlag
        return button
    end

    function FilterButton:OnClick()
        local frame = self:GetParent():GetParent()
        if bit.band(frame:GetQuality(), self.qualityFlag) > 0 then
            if IsModifierKeyDown() or frame:GetQuality() == self.qualityFlag then
                frame:RemoveQuality(self.qualityFlag)
            else
                frame:SetQuality(self.qualityFlag)
            end
        elseif IsModifierKeyDown() then
            frame:AddQuality(self.qualityFlag)
        else
            frame:SetQuality(self.qualityFlag)
        end
    end

    function FilterButton:OnEnter()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local quality = self.quality
        if quality then
            local r, g, b = GetItemQualityColor(quality)
            GameTooltip:SetText(_G[format("ITEM_QUALITY%d_DESC", quality)], r, g, b)
        else
            GameTooltip:SetText(ALL)
        end
        GameTooltip:Show()
    end

    function FilterButton:OnLeave()
        GameTooltip:Hide()
    end

    function FilterButton:UpdateHighlight(quality)
        self:SetChecked(bit.band(quality, self.qualityFlag) > 0)
    end

    local QualityFilter = mod:NewClass("Frame")
    mod.QualityFilter = QualityFilter

    function QualityFilter:New(parent)
        local f = self:Bind(CreateFrame("Frame", nil, parent))

        f:AddQualityButton(0)
        f:AddQualityButton(1)
        f:AddQualityButton(2)
        f:AddQualityButton(3)
        f:AddQualityButton(4)
        f:AddQualityButton(5, mod.QualityFlags[5] + mod.QualityFlags[6])
        f:AddQualityButton(7)

        f:SetWidth(SIZE * 6)
        f:SetHeight(SIZE)
        f:UpdateHighlight()

        return f
    end

    function QualityFilter:AddQualityButton(quality, qualityFlags)
        local button = FilterButton:Create(self, quality, qualityFlags or mod.QualityFlags[quality])
        if self.prev then
            button:SetPoint("LEFT", self.prev, "RIGHT", 1, 0)
        else
            button:SetPoint("LEFT")
        end
        self.prev = button
    end

    function QualityFilter:UpdateHighlight()
        local quality = self:GetParent():GetQuality()
        for i = 1, select("#", self:GetChildren()) do
            select(i, self:GetChildren()):UpdateHighlight(quality)
        end
    end
end

-- ============================================================================
-- SIDE FILTER (category tabs on left/right)
-- ============================================================================

do
    local SideTab = mod:NewClass("CheckButton")

    function SideTab:New(parent, id)
        local tab = self:Bind(CreateFrame("CheckButton", format("%sSideTab%d", parent:GetParent():GetName(), id), parent))
        SetupSideTabButton(tab)
        tab.border = tab._BagSkin_SideBorder
        return tab
    end

    function SideTab:Set(set)
        self.set = set
        self.tooltip = GetSetDisplayName(set.name)
        if set.icon then
            self:SetNormalTexture(set.icon)
            self:GetNormalTexture():SetTexCoord(0.06, 0.94, 0.06, 0.94)
        end
    end

    function SideTab:SetReversed(reversed)
        self.reversed = reversed and true or nil
        if self.border then
            self.border:ClearAllPoints()
            if reversed then
                self.border:SetTexCoord(1, 0, 0, 1)
                self.border:SetPoint("TOPRIGHT", 3, 11)
            else
                self.border:SetTexCoord(0, 1, 0, 1)
                self.border:SetPoint("TOPLEFT", -3, 11)
            end
        end
    end

    function SideTab:UpdateHighlight(setName)
        self:SetChecked(self.set.name == setName)
    end

    local SideFilter = mod:NewClass("Frame")
    mod.SideFilter = SideFilter

    function SideFilter:New(parent, reversed)
        local f = self:Bind(CreateFrame("Frame", parent:GetName() .. "SideFilter", parent))
        f.buttons = setmetatable({}, { __index = function(t, k)
            local tab = SideTab:New(f, k)
            if k > 1 then
                tab:SetPoint("TOP", f.buttons[k - 1], "BOTTOM", 0, -17)
            end
            tab:SetScript("OnClick", function(self)
                parent:SetCategory(self.set.name)
            end)
            t[k] = tab
            return tab
        end })
        f.reversed = reversed
        f:SetReversed(reversed)
        return f
    end

    function SideFilter:SetReversed(enable)
        self.reversed = enable
        self:UpdateAnchoring()
    end

    function SideFilter:Reversed()
        return self.reversed
    end

    function SideFilter:UpdateAnchoring()
        local parent = self:GetParent()
        if self.reversed then
            if self.buttons[1] then
                self.buttons[1]:ClearAllPoints()
                self.buttons[1]:SetPoint("TOPRIGHT", parent, "TOPLEFT", -1, -60)
            end
        else
            if self.buttons[1] then
                self.buttons[1]:ClearAllPoints()
                self.buttons[1]:SetPoint("TOPLEFT", parent, "TOPRIGHT", -1, -60)
            end
        end
        -- Update border flip and icon offset for all visible buttons
        for _, button in pairs(self.buttons) do
            if button:IsShown() and button.SetReversed then
                button:SetReversed(self.reversed)
            end
        end
    end

    function SideFilter:UpdateFilters()
        local CombuctorSet = mod("Sets")
        local parent = self:GetParent()
        local numFilters = 0

        for _, set in CombuctorSet:GetParentSets() do
            if parent:HasSet(set.name) then
                numFilters = numFilters + 1
                self.buttons[numFilters]:Set(set)
                self.buttons[numFilters]:Show()
            end
        end

        -- Hide excess buttons (important after profile reset)
        for i = numFilters + 1, #self.buttons do
            self.buttons[i]:Hide()
            self.buttons[i]:SetHeight(0.001)
        end
        -- Restore height for visible buttons
        for i = 1, numFilters do
            self.buttons[i]:SetHeight(32)
        end

        self:UpdateAnchoring()
        if numFilters > 0 then
            self:Show()
        else
            self:Hide()
        end
    end

    function SideFilter:UpdateHighlight()
        local category = self:GetParent():GetCategory()
        for _, button in pairs(self.buttons) do
            if button:IsShown() then
                button:UpdateHighlight(category)
            end
        end
    end
end

-- ============================================================================
-- BOTTOM FILTER (subcategory tabs)
-- ============================================================================

do
    local BottomTab = mod:NewClass("Button")

    function BottomTab:New(parent, id)
        local tab = self:Bind(CreateFrame("Button", parent:GetName() .. "Tab" .. id, parent, "CharacterFrameTabButtonTemplate"))
        SetupBottomTabButton(tab)
        tab:SetID(id)
        tab:SetScript("OnClick", function(self)
            parent:GetParent():SetSubCategory(self.set.name)
        end)
        return tab
    end

    function BottomTab:Set(set)
        self.set = set
        local displayName = GetSetDisplayName(set.name)
        if set.icon then
            self:SetFormattedText("|T%s:%d|t %s", set.icon, 16, displayName)
        else
            self:SetText(displayName)
        end
        PanelTemplates_TabResize(self, 0)
        self:GetHighlightTexture():SetWidth(self:GetTextWidth() + 30)
    end

    function BottomTab:UpdateHighlight(setName)
        if self.set.name == setName then
            PanelTemplates_SetTab(self:GetParent(), self:GetID())
        end
    end

    local BottomFilter = mod:NewClass("Frame")
    mod.BottomFilter = BottomFilter

    function BottomFilter:New(parent)
        local f = self:Bind(CreateFrame("Frame", parent:GetName() .. "BottomFilter", parent))
        f.buttons = setmetatable({}, { __index = function(t, k)
            local tab = BottomTab:New(f, k)
            if k > 1 then
                -- Horizontal chain only — Y comes from separate BOTTOM anchor
                tab:SetPoint("LEFT", f.buttons[k - 1], "RIGHT", -16, 0)
            else
                tab:SetPoint("LEFT", parent, "BOTTOMLEFT", 60, 0)
            end
            -- Shared vertical baseline; active tab overrides in UpdateHighlight
            tab:SetPoint("BOTTOM", parent, "BOTTOMLEFT", 0, -26)
            t[k] = tab
            return tab
        end })
        return f
    end

    function BottomFilter:UpdateFilters()
        local numFilters = 0
        local parent = self:GetParent()
        local CombuctorSet = mod("Sets")

        for _, set in CombuctorSet:GetChildSets(parent:GetCategory()) do
            if parent:HasSubSet(set.name, set.parent) then
                numFilters = numFilters + 1
                self.buttons[numFilters]:Set(set)
            end
        end

        if numFilters > 1 then
            for i = 1, numFilters do self.buttons[i]:Show() end
            for i = numFilters + 1, #self.buttons do self.buttons[i]:Hide() end
            PanelTemplates_SetNumTabs(self, numFilters)
            self:UpdateHighlight()
            self:Show()
        else
            PanelTemplates_SetNumTabs(self, 0)
            self:Hide()
        end
        self:GetParent():UpdateClampInsets()
    end

    function BottomFilter:UpdateHighlight()
        local category = self:GetParent():GetSubCategory()
        for _, button in pairs(self.buttons) do
            if button:IsShown() then
                button:UpdateHighlight(category)
                -- Only Y moves — LEFT/RIGHT chain is untouched
                local isActive = (button.set and button.set.name == category)
                button:SetPoint("BOTTOM", self:GetParent(), "BOTTOMLEFT", 0, isActive and -31 or -26)
            end
        end
    end
end

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
