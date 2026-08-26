-- DragonUI/modules/merchant/MerchantFrame.lua — modern (Dragonflight) chrome on the
-- client's own vendor window.
--
-- DOWNPORT of NewEra/MerchantFrame/MerchantFrame.lua (Classic 1.15), adapted for DragonUI.
-- This is a RESKIN, not a replacement: FrameXML keeps MerchantFrame_Update /
-- _UpdateMerchantInfo / _UpdateBuybackInfo and all of the buy/sell/repair behaviour;
-- we re-dress the frame it paints on and hook the updater to keep our pieces in sync.
--
-- Key 3.3.5a differences from the 1.15 source (see NewEra PORT_NOTES.md for full details):
--   * The frame is a 384x512 classic wooden panel, not ButtonFrameTemplate
--   * MERCHANT_ITEMS_PER_PAGE is 10, not 12
--   * MerchantFrameItem_UpdateQuality does not exist
--   * SetShown does not exist — Show/Hide throughout
--   * No MerchantMoneyInset — player money floats on classic bottom art
--
-- Infrastructure: uses DragonUIWorldMapHost (vendored NewEra core libs via worldmap module)
-- for PanelChrome, NineSlice, Portrait, Tex, FrameUtil.

local addon = select(2, ...)
if not addon then return end

local NE = DragonUIWorldMapHost
if not NE then return end

local L = addon.L

-- ============================================================================
-- MODULE REGISTRATION
-- ============================================================================

local MerchantModule = {
    initialized = false,
    applied = false,
    hooks = {},
    frames = {},
}

if addon.RegisterModule then
    addon:RegisterModule("merchant", MerchantModule,
        (L and L["Merchant"]) or "Merchant",
        (L and L["Retail-style vendor window chrome"]) or "Retail-style vendor window chrome")
end

-- ============================================================================
-- CONFIG HELPERS
-- ============================================================================

local function GetModuleConfig()
    return addon:GetModuleConfig("merchant")
end

local function IsModuleEnabled()
    return addon:IsModuleEnabled("merchant")
end

-- ============================================================================
-- INLINE HELPERS (replaces NewEra's NE.itembtn and NE.itemgrid)
-- ============================================================================

-- Quality text color — reads ITEM_QUALITY_COLORS (the brighter table with .hex).
-- Equivalent to NE.itembtn.TextColor in NewEra.
local function TextColor(quality)
    return quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] or nil
end

-- Quest-starter detection via tooltip scan (3.3.5a has no direct API).
-- Scans for ITEM_SPELL_STARTS_QUEST in the item's tooltip lines.
local _questScanTooltip
local function ItemStartsQuestByLink(link)
    if not link then return false end
    if not _questScanTooltip then
        _questScanTooltip = CreateFrame("GameTooltip", "DragonUI_MerchantQuestScan", nil, "GameTooltipTemplate")
        _questScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    _questScanTooltip:ClearLines()
    _questScanTooltip:SetHyperlink(link)
    for i = 1, _questScanTooltip:NumLines() do
        local text = _G["DragonUI_MerchantQuestScanTextLeft" .. i] and _G["DragonUI_MerchantQuestScanTextLeft" .. i]:GetText()
        if text and text == ITEM_SPELL_STARTS_QUEST then
            return true
        end
    end
    return false
end

-- ============================================================================
-- LOCAL UPVALUES
-- ============================================================================

local PC = NE.panelchrome
local PCKeep = PC and PC.Keep
local PCHideClassicChrome = PC and PC.HideClassicChrome
local PCApplyModernChrome = PC and PC.ApplyModernChrome
local PCEnsureTitle = PC and PC.EnsureTitle
local PCModernizeCloseButton = PC and PC.ModernizeCloseButton
local PCSetTitle = PC and PC.SetTitle

local texSetAtlas = NE.tex and NE.tex.SetAtlas
local texLocal = NE.tex and NE.tex.Local
local texAtlasEntry = NE.tex and NE.tex._atlasEntry

local ForEachRegion = NE.FrameUtil and NE.FrameUtil.ForEachRegion
local FindRegion = NE.FrameUtil and NE.FrameUtil.FindRegion

local ninesliceAttachInset = NE.nineslice and NE.nineslice.AttachInset
local ninesliceApplyLayout = NE.nineslice and NE.nineslice.ApplyLayout

local portraitApplyCutout = NE.portrait and NE.portrait.ApplyCutout

-- ============================================================================
-- LAYOUT CONSTANTS
-- ============================================================================

local ITEMS_PER_PAGE   = MERCHANT_ITEMS_PER_PAGE or 10
local BUYBACK_PER_PAGE = BUYBACK_ITEMS_PER_PAGE or 12

local EMPTY_SLOT_FDID  = 130766   -- UI-EmptySlot
local SLOT_RING_FDID   = 130841   -- UI-Quickslot2
local LABEL_PLATE_FDID = 136423   -- UI-Merchant-LabelSlots

local PANEL_W, PANEL_H = 368, 494
local GRID_X, GRID_Y   = 26, -76
local PANEL_X_NUDGE    = 6

local INSET_TL_X, INSET_TL_Y = 10, -59
local INSET_BR_X, INSET_BR_Y = -10, 101
local INSET_BR_Y_BUYBACK = 27
local ROW_GAP_MERCHANT, ROW_GAP_BUYBACK = -8, -22

local PAGENAV_Y  = 145
local PAGENAV_X  = 34

local BAND_Y     = 36
local BAND_INSET = 6
local BUTTON_Y   = 45
local BUTTON_GAP = 6
local TILE_BLEED = 4
local BAR_X      = 20
local BUYBACK_X  = 228
local MONEY_Y    = 9

-- ============================================================================
-- DIAGNOSTICS (optional /dragonui merchant slash command)
-- ============================================================================

local stats = { update = 0, merchantInfo = 0, buybackInfo = 0, repair = 0, tabClick = 0,
                onShow = 0, onHide = 0, evShow = 0, evClosed = 0, tab = 0, tabTrace = {} }

local function trace(what)
    local f = _G.MerchantFrame
    local t = stats.tabTrace
    t[#t + 1] = what .. "=" .. tostring(f and f.selectedTab)
    while #t > 12 do table.remove(t, 1) end
end

-- ============================================================================
-- CLASSIC ART DETECTION (must be defined before diagnose and hideClassicChrome)
-- ============================================================================

local CLASSIC_PATHS = { "ui%-merchant%-top", "ui%-merchant%-bot", "ui%-buyback%-" }

local function isClassicArt(r)
    local p = r.GetTexture and r:GetTexture()
    if type(p) ~= "string" then return false end
    p = p:lower()
    for _, pat in ipairs(CLASSIC_PATHS) do
        if p:find(pat) then return true end
    end
    return false
end

local function diagnose()
    local say = function(fmt, ...)
        local msg = select("#", ...) > 0 and fmt:format(...) or fmt
        DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1DragonUI Merchant|r " .. msg)
    end
    local shortPath = function(p)
        if type(p) ~= "string" then return tostring(p) end
        return p:match("([^\\/]+)$") or p
    end

    say("---- state ----")
    say("hooks fired: Update=%d MerchantInfo=%d BuybackInfo=%d Repair=%d TabClick=%d lastTab=%s",
        stats.update, stats.merchantInfo, stats.buybackInfo, stats.repair, stats.tabClick, tostring(stats.tab))
    say("window: OnShow=%d OnHide=%d evSHOW=%d evCLOSED=%d", stats.onShow, stats.onHide, stats.evShow, stats.evClosed)
    if #stats.tabTrace > 0 then
        say("trace: %s", table.concat(stats.tabTrace, "  "))
    end

    -- NE.tex diagnostics
    local NE = DragonUIWorldMapHost
    local texOk = NE and NE.tex and NE.tex.RegisterLocal
    say("NE.tex available: %s", tostring(texOk))
    if texOk then
        local rockPath = NE.tex.localFiles and NE.tex.localFiles[374155]
        say("rock (374155): %s", rockPath and shortPath(rockPath) or "|cffff4040MISSING|r")
        local merchPath = NE.tex.localFiles and NE.tex.localFiles[5222222]
        say("merchant pack (5222222): %s", merchPath and shortPath(merchPath) or "|cffff4040MISSING|r")
        -- Check atlas resolution
        local atlases = { "spellicon-256x256-repair", "spellicon-256x256-repairall",
            "spellicon-256x256-selljunk", "ui-merchant-botframe", "common-icon-undo" }
        for _, name in ipairs(atlases) do
            local entry = NE.tex._atlasEntry and NE.tex._atlasEntry(name)
            if not entry then
                say("atlas %s: |cffff4040MISSING|r", name)
            else
                local src = NE.tex.localFiles and NE.tex.localFiles[entry.file]
                say("atlas %s: %s fdid=%s", name, src and "ok" or "|cffff4040NO-LOCAL|r", tostring(entry.file))
            end
        end
    end

    -- PanelChrome diagnostics
    local pcOk = NE and NE.panelchrome and NE.panelchrome.ApplyModernChrome
    say("PanelChrome: %s", tostring(pcOk))
    local nsOk = NE and NE.nineslice and NE.nineslice.ApplyLayout
    say("NineSlice: %s", tostring(nsOk))

    local f = _G.MerchantFrame
    if f then
        say("selectedTab=%s  _neBuilt=%s  width=%.0f height=%.0f",
            tostring(f.selectedTab), tostring(f._neBuilt), f:GetWidth() or 0, f:GetHeight() or 0)
        -- f.Bg check
        local bg = f.Bg
        if bg then
            say("f.Bg: shown=%s tex=%s", tostring(bg:IsShown()), shortPath(bg:GetTexture()))
            local r, g, b = bg:GetVertexColor()
            say("  vertexcolor %.2f/%.2f/%.2f  size %.0fx%.0f", r or 0, g or 0, b or 0, bg:GetWidth() or 0, bg:GetHeight() or 0)
        else
            say("|cffff4040f.Bg: MISSING|r")
        end
        -- NineSlice check
        local ns = f.NineSlice
        if ns then
            say("NineSlice: shown=%s  level=%s", tostring(ns:IsShown()), tostring(ns:GetFrameLevel()))
        else
            say("|cffff4040f.NineSlice: MISSING|r")
        end
        -- Classic art check
        local classicCount = 0
        if ForEachRegion then
            ForEachRegion(f, "Texture", "BORDER", function(r)
                if isClassicArt(r) then classicCount = classicCount + 1 end
            end)
        end
        say("classic art on BORDER: %d remaining", classicCount)
        -- Bottom band check
        say("botFrame=%s  gridInset=%s  moneyInset=%s",
            tostring(f._neBotFrame ~= nil), tostring(f._neGridInset ~= nil), tostring(f._neMoneyInset ~= nil))
        -- Grid inset fill check
        local giBg = f._neGridInsetBg
        if giBg then
            say("gridInsetBg: shown=%s level=%s/%s tex=%s",
                tostring(giBg:IsShown()), tostring(giBg:GetDrawLayer()), tostring(giBg:GetTexture()),
                shortPath(giBg:GetTexture()))
            local r, g, b = giBg:GetVertexColor()
            say("  vertexcolor %.2f/%.2f/%.2f  w=%.0f h=%.0f", r or 0, g or 0, b or 0, giBg:GetWidth() or 0, giBg:GetHeight() or 0)
        else
            say("|cffff4040gridInsetBg: MISSING|r")
        end
        -- PanelKeep check
        local pk = f._nePanelKeep
        local pkCount = 0
        if pk then for _ in pairs(pk) do pkCount = pkCount + 1 end end
        say("panelKeep entries: %d (bg=%s giBg=%s miBg=%s)", pkCount,
            tostring(pk and pk[f.Bg]), tostring(pk and pk[f._neGridInsetBg]), tostring(pk and pk[f._neMoneyInsetBg]))
        -- Title check
        say("title=%q  nameText=%q",
            (f.Title and f.Title:GetText()) or "<none>",
            (_G.MerchantNameText and _G.MerchantNameText:GetText()) or "<none>")
    else
        say("|cffff4040MerchantFrame: MISSING|r")
    end
    say("---- end ----")
end

-- ============================================================================
-- OUTER CHROME — classic art suppression + modern chrome
-- ============================================================================

local function hideClassicChrome()
    local f = _G.MerchantFrame
    if not f then return end

    if _G.MerchantFramePortrait and PCKeep then PCKeep(f, _G.MerchantFramePortrait) end
    if PCHideClassicChrome then PCHideClassicChrome(f) end

    -- BORDER and ARTWORK layers (PanelChrome walk only covers BACKGROUND)
    if ForEachRegion then
        ForEachRegion(f, "Texture", "BORDER", function(r)
            if r ~= f._neTopTileStreaks and isClassicArt(r) then r:Hide() end
        end)
        ForEachRegion(f, "Texture", "ARTWORK", function(r)
            if r ~= f._neTopTileStreaks and isClassicArt(r) then r:Hide() end
        end)
    end

    -- BACKGROUND walk: hide everything except f.Bg and the panel-keep list
    -- (grid inset fill, money inset fill). f._nePanelKeep is populated by PC.Keep();
    -- for safety we also hard-code the two keys so the fills survive the walk.
    local keep = (f._nePanelKeep or {})
    if f.Bg then keep[f.Bg] = true end
    if f._neGridInsetBg then keep[f._neGridInsetBg] = true end
    if f._neMoneyInsetBg then keep[f._neMoneyInsetBg] = true end
    if ForEachRegion then
        ForEachRegion(f, "Texture", "BACKGROUND", function(r)
            if not keep[r] then r:Hide() end
        end)
    end

    if _G.MerchantNameText then _G.MerchantNameText:Hide() end

    for _, name in ipairs({
        "MerchantRepairText", "MerchantFrameBottomLeftBorder", "MerchantFrameBottomRightBorder",
        "BuybackFrameTopLeft", "BuybackFrameTopRight", "BuybackFrameBotLeft", "BuybackFrameBotRight",
    }) do
        local t = _G[name]
        if t and t.Hide then t:Hide() end
    end
end

-- ============================================================================
-- BODY FILL
-- ============================================================================

local ROCK_FDID = 374155

local function paintBody(f)
    local bg = f.Bg
    if not bg then
        bg = f:CreateTexture(nil, "BACKGROUND")
        f.Bg = bg
    end
    local rockPath = texLocal and texLocal(ROCK_FDID)
    bg:SetTexture(rockPath or ROCK_FDID, "REPEAT", "REPEAT")
    bg:SetHorizTile(true)
    bg:SetVertTile(true)
    bg:SetTexCoord(0, 1, 0, 1)
    bg:SetVertexColor(1, 1, 1)
    bg:ClearAllPoints()
    -- Full frame — same as every other window in the set (inspect, guild, auction house).
    -- The title band sits on top via OVERLAY; this stone runs behind it.
    bg:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, -21)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,   0)
    bg:Show()
end

local function applyModernChrome()
    local f = _G.MerchantFrame
    if not f then return end
    if PCApplyModernChrome then PCApplyModernChrome(f) end
    paintBody(f)
end

-- ============================================================================
-- BOTTOM BAND
-- ============================================================================

local function buildBottomBand()
    local f = _G.MerchantFrame
    if not f or f._neBotFrame then return end
    local t = f:CreateTexture(nil, "OVERLAY")
    if not texSetAtlas or not texSetAtlas(t, "ui-merchant-botframe", false) then return end
    t:SetHeight(61)
    t:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",   BAND_INSET, BAND_Y)
    t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -BAND_INSET, BAND_Y)
    f._neBotFrame = t
end

-- ============================================================================
-- ROWS — slot reskin, quest bang, name clamping
-- ============================================================================

local function localTex(fdid)
    return texLocal and texLocal(fdid) or nil
end

local function rowTexture(row, prefix, suffix, pathPattern)
    local t = _G[prefix .. suffix]
    if t then return t end
    if not row then return nil end
    if not FindRegion then return nil end
    return FindRegion(row, "Texture", function(r)
        local p = r.GetTexture and r:GetTexture()
        return type(p) == "string" and p:lower():find(pathPattern) ~= nil
    end)
end

local function reskinSlot(prefix, showLabel)
    local row = _G[prefix]
    local slot = rowTexture(row, prefix, "SlotTexture", "ui%-emptyslot")
    local recess = localTex(EMPTY_SLOT_FDID)
    if slot then
        if recess then slot:SetTexture(recess) end
        slot:Show()
    end

    local ib  = _G[prefix .. "ItemButton"]
    local nrm = (ib and ib.GetNormalTexture and ib:GetNormalTexture())
                or _G[prefix .. "ItemButtonNormalTexture"]
    local ring = localTex(SLOT_RING_FDID)
    if nrm and ring then
        nrm:SetTexture(ring)
        nrm:ClearAllPoints()
        nrm:SetSize(64, 64)
        nrm:SetPoint("CENTER", ib, "CENTER", 0, -1)
    end

    local nameFrame = rowTexture(row, prefix, "NameFrame", "ui%-merchant%-labelslots")
    if nameFrame then
        if showLabel then
            local plate = localTex(LABEL_PLATE_FDID)
            if plate then nameFrame:SetTexture(plate) end
            nameFrame:SetVertexColor(0.5, 0.5, 0.5, 1)
            nameFrame:Show()
        else
            nameFrame:Hide()
        end
    end
end

local function fitBuybackIcon()
    local ib = _G.MerchantBuyBackItemItemButton
    if not ib then return end
    local icon = _G.MerchantBuyBackItemItemButtonIconTexture or ib.icon
    if not icon then return end
    icon:ClearAllPoints()
    icon:SetAllPoints(ib)
end

local function fitBuybackQualityGlow()
    local ib = _G.MerchantBuyBackItemItemButton
    local glow = ib and ib.__DragonUI_QualityOverlay
    if not glow then return end
    local n = (ib:GetWidth() or 37) * 1.7
    if math.abs((glow:GetWidth() or 0) - n) < 0.5 then return end
    glow:SetSize(n, n)
end

local BUYBACK_BTN = 37
local BUYBACK_Y   = 44

local function fitBuybackToBar()
    local ib = _G.MerchantBuyBackItemItemButton
    if not ib then return end
    ib:SetSize(BUYBACK_BTN, BUYBACK_BTN)
    local row = _G.MerchantBuyBackItem
    if row then row:SetSize(BUYBACK_BTN, BUYBACK_BTN) end
    fitBuybackIcon()
    local slot = _G.MerchantBuyBackItemSlotTexture
    if slot then slot:Show() end
    local nrm = ib.GetNormalTexture and ib:GetNormalTexture()
    if nrm then nrm:Show() end
end

local function reskinAllSlots()
    for i = 1, BUYBACK_PER_PAGE do
        if _G["MerchantItem" .. i] then reskinSlot("MerchantItem" .. i, true) end
    end
    if _G.MerchantBuyBackItem then reskinSlot("MerchantBuyBackItem", false) end
end

local QUEST_BANG_TEX = TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\QuestBang"
local function addQuestBang(prefix)
    local ib = _G[prefix .. "ItemButton"]
    if not ib or ib.IconQuestTexture then return end
    local t = ib:CreateTexture(nil, "OVERLAY")
    t:SetTexture(QUEST_BANG_TEX)
    t:SetSize(37, 38)
    t:SetPoint("TOP", ib, "TOP", 0, 0)
    t:Hide()
    ib.IconQuestTexture = t
end

local function addQuestBangs()
    for i = 1, BUYBACK_PER_PAGE do
        if _G["MerchantItem" .. i] then addQuestBang("MerchantItem" .. i) end
    end
end

local function clampName(nm, width)
    if not nm then return end
    if nm.SetWordWrap then nm:SetWordWrap(false) end
    if nm.SetMaxLines then nm:SetMaxLines(1) end
    if width then nm:SetWidth(width) end
end

-- ============================================================================
-- REPAIR ICONS
-- ============================================================================

local REPAIR_ICONS = {
    { button = "MerchantRepairAllButton",       icon = "MerchantRepairAllIcon",            atlas = "spellicon-256x256-repairall"      },
    { button = "MerchantRepairItemButton",      icon = nil,                                atlas = "spellicon-256x256-repair"         },
    { button = "MerchantGuildBankRepairButton", icon = "MerchantGuildBankRepairButtonIcon", atlas = "spellicon-256x256-repairallguild", size = 36 },
}

local function repairIconRegion(btn, globalName)
    if globalName and _G[globalName] then return _G[globalName] end
    if not FindRegion then return nil end
    return FindRegion(btn, "Texture", function(r)
        local p = r.GetTexture and r:GetTexture()
        return type(p) == "string" and p:lower():find("ui%-merchant%-repairicons") ~= nil
    end)
end

local function reskinRepairIcons()
    for _, spec in ipairs(REPAIR_ICONS) do
        local btn = _G[spec.button]
        if btn and spec.size then btn:SetSize(spec.size, spec.size) end
        local icon = btn and repairIconRegion(btn, spec.icon)
        if icon and texSetAtlas and texSetAtlas(icon, spec.atlas, false) then
            icon:ClearAllPoints()
            icon:SetAllPoints(btn)
            btn._neIcon = icon
        end
    end
end

local function addRetailSlotBg(buttonName)
    local btn = _G[buttonName]
    if not btn or btn._neSlotBg then return end
    local path = localTex(EMPTY_SLOT_FDID)
    if not path then return end
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(path)
    bg:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -TILE_BLEED,  TILE_BLEED)
    bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  TILE_BLEED, -TILE_BLEED)
    btn._neSlotBg = bg
end

local function addRetailSlotBgs()
    addRetailSlotBg("MerchantRepairAllButton")
    addRetailSlotBg("MerchantRepairItemButton")
    addRetailSlotBg("MerchantGuildBankRepairButton")
    addRetailSlotBg("DragonUI_MerchantSellAllJunkButton")
end

-- ============================================================================
-- BOTTOM BUTTON CLUSTER
-- ============================================================================

local function postRepairButtons()
    local f = _G.MerchantFrame
    if not f or f.selectedTab ~= 1 then return end
    stats.repair = stats.repair + 1

    local sell    = _G.DragonUI_MerchantSellAllJunkButton
    local buyback = _G.MerchantBuyBackItem

    if buyback then
        buyback:ClearAllPoints()
        buyback:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", BUYBACK_X, BUYBACK_Y)
    end

    local last
    if CanMerchantRepair and CanMerchantRepair() then
        local repAll  = _G.MerchantRepairAllButton
        local repItem = _G.MerchantRepairItemButton
        if not (repAll and repItem) then return end
        local guild = CanGuildBankRepair and CanGuildBankRepair()

        local w = (repItem:GetWidth() or 36) + BUTTON_GAP
        repAll:ClearAllPoints()
        repAll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", BAR_X + w, BUTTON_Y)
        repItem:ClearAllPoints()
        repItem:SetPoint("RIGHT", repAll, "LEFT", -BUTTON_GAP, 0)
        last = repAll

        if guild then
            local gb = _G.MerchantGuildBankRepairButton
            if gb then
                gb:ClearAllPoints()
                gb:SetPoint("LEFT", repAll, "RIGHT", BUTTON_GAP, 0)
                last = gb
            end
        end

        if sell then
            sell:ClearAllPoints()
            sell:SetPoint("LEFT", last, "RIGHT", BUTTON_GAP, 0)
            last = sell
        end
    elseif sell then
        sell:ClearAllPoints()
        sell:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", BAR_X, BUTTON_Y)
        last = sell
    end
end

-- ============================================================================
-- INSETS, PAGE NAV, CLOSE BUTTON
-- ============================================================================

local INSET_TONE          = { 0.22, 0.22, 0.23 }
local INSET_TONE_BUYBACK  = { 0.85, 0.85, 0.87 }

local function insetFill(f, key, rect, tone)
    if f[key] then return f[key] end
    local t = f:CreateTexture(nil, "ARTWORK", nil, -8)
    t:SetPoint("TOPLEFT",     rect, "TOPLEFT",     0, 0)
    t:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", 0, 0)
    local rockPath = texLocal and texLocal(ROCK_FDID)
    if rockPath then
        t:SetTexture(rockPath, "REPEAT", "REPEAT")
        t:SetHorizTile(true)
        t:SetVertTile(true)
        t:SetVertexColor(tone[1], tone[2], tone[3])
    else
        t:SetTexture(0.05, 0.05, 0.06, 0.92)
    end
    if PCKeep then PCKeep(f, t) end
    f[key] = t
    return t
end

local function buildGridInset()
    local f = _G.MerchantFrame
    if not f or f._neGridInset then return end
    local inset = ninesliceAttachInset(f, INSET_TL_X, INSET_TL_Y, INSET_BR_X, INSET_BR_Y)
    if not inset then return end
    inset:SetFrameLevel((f:GetFrameLevel() or 1) + 1)
    f._neGridInset = inset
    insetFill(f, "_neGridInsetBg", inset, INSET_TONE)
end

-- DOWNPORT: there is no MerchantMoneyInset on this client (that is an Era/retail frame) — the
-- player's money simply floats on the classic bottom art. Build retail's recess for it instead.
local function buildMoneyInset()
    local f = _G.MerchantFrame
    local money = _G.MerchantMoneyFrame
    if not (f and money) or f._neMoneyInset then return end
    local inset = CreateFrame("Frame", nil, f)
    inset:SetPoint("TOPLEFT",     money, "TOPLEFT",     -8, 6)
    inset:SetPoint("BOTTOMRIGHT", money, "BOTTOMRIGHT",   6, -6)
    inset:EnableMouse(false)
    ninesliceApplyLayout(inset, "InsetFrameTemplate")
    inset:SetFrameLevel((f:GetFrameLevel() or 1) + 1)
    f._neMoneyInset = inset
    -- Fill as a child of the INSET frame (not f) so it renders above the
    -- bottom band (which lives on f's OVERLAY layer).
    local t = inset:CreateTexture(nil, "BACKGROUND", nil, -1)
    t:SetAllPoints()
    local rockPath = texLocal and texLocal(ROCK_FDID)
    if rockPath then
        t:SetTexture(rockPath, "REPEAT", "REPEAT")
        t:SetHorizTile(true)
        t:SetVertTile(true)
        t:SetVertexColor(INSET_TONE[1], INSET_TONE[2], INSET_TONE[3])
    else
        t:SetTexture(0.05, 0.05, 0.06, 0.92)
    end
    if PCKeep then PCKeep(f, t) end
    f._neMoneyInsetBg = t
end

local function applyPanelLayout(f)
    if not f.SetAttribute then return end
    if f:GetAttribute("UIPanelLayout-xoffset") == PANEL_X_NUDGE then return end
    f:SetAttribute("UIPanelLayout-area",     "left")
    f:SetAttribute("UIPanelLayout-pushable", 0)
    f:SetAttribute("UIPanelLayout-xoffset",  PANEL_X_NUDGE)
    f:SetAttribute("UIPanelLayout-enabled",  true)
    f:SetAttribute("UIPanelLayout-defined",  true)
    if f:IsShown() and UpdateUIPanelPositions then UpdateUIPanelPositions(f) end
end

local function applyLayout()
    local f = _G.MerchantFrame
    if not f then return end

    f:SetSize(PANEL_W, PANEL_H)
    applyPanelLayout(f)
    if f.SetHitRectInsets then f:SetHitRectInsets(0, 0, 0, 0) end

    local row1 = _G.MerchantItem1
    if row1 then
        row1:ClearAllPoints()
        row1:SetPoint("TOPLEFT", f, "TOPLEFT", GRID_X, GRID_Y)
    end

    local prev, nxt = _G.MerchantPrevPageButton, _G.MerchantNextPageButton
    if prev then
        prev:ClearAllPoints()
        prev:SetPoint("CENTER", f, "BOTTOMLEFT", PAGENAV_X, PAGENAV_Y)
    end
    if nxt then
        nxt:ClearAllPoints()
        nxt:SetPoint("CENTER", f, "BOTTOMRIGHT", -PAGENAV_X, PAGENAV_Y)
    end
    local pageText = _G.MerchantPageText
    if pageText then
        pageText:ClearAllPoints()
        pageText:SetPoint("CENTER", f, "BOTTOMLEFT", PANEL_W / 2, PAGENAV_Y)
        pageText:SetWidth(140)
        pageText:SetJustifyH("CENTER")
    end

    local money = _G.MerchantMoneyFrame
    if money then
        money:ClearAllPoints()
        money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, MONEY_Y)
    end

    local sellJunk = _G.MerchantFrameSellJunkFrame
    if sellJunk then
        sellJunk:ClearAllPoints()
        sellJunk:SetPoint("BOTTOMRIGHT", money, "BOTTOMLEFT", -4, 0)
    end

    local repairSettings = _G.MerchantRepairSettingsButton
    if repairSettings then
        repairSettings:ClearAllPoints()
        repairSettings:SetPoint("BOTTOMRIGHT", sellJunk, "BOTTOMLEFT", -4, 0)
    end

    local above = (f:GetFrameLevel() or 1) + 4
    for i = 1, BUYBACK_PER_PAGE do
        local row = _G["MerchantItem" .. i]
        if row then row:SetFrameLevel(above) end
    end
    if _G.MerchantBuyBackItem then _G.MerchantBuyBackItem:SetFrameLevel(above) end
    if prev then prev:SetFrameLevel(above) end
    if nxt  then nxt:SetFrameLevel(above)  end
    if money then money:SetFrameLevel(above) end
end

-- Page nav textures
local PAGE_BTN_TEX = {
    MerchantPrevPageButton = { up = 130869, down = 130868, disabled = 130867 },
    MerchantNextPageButton = { up = 130866, down = 130865, disabled = 130864 },
}
local PAGE_BG_FDID     = 130822
local PAGE_HILITE_FDID = 130757

local function reskinPageNav(btnName)
    local btn = _G[btnName]
    local set = PAGE_BTN_TEX[btnName]
    if not (btn and set) then return end

    local function retexture(getter, fdid, blend)
        local path = localTex(fdid)
        local t = path and btn[getter] and btn[getter](btn)
        if not t then return end
        t:SetTexture(path)
        if blend then t:SetBlendMode(blend) end
    end

    retexture("GetNormalTexture",    set.up)
    retexture("GetPushedTexture",    set.down)
    retexture("GetDisabledTexture",  set.disabled)
    retexture("GetHighlightTexture", PAGE_HILITE_FDID, "ADD")

    local bgPath = localTex(PAGE_BG_FDID)
    if bgPath and ForEachRegion then
        ForEachRegion(btn, "Texture", "BACKGROUND", function(r)
            r:SetTexture(bgPath)
            r:Show()
        end)
    end
end

local function reskinPageNavButtons()
    reskinPageNav("MerchantPrevPageButton")
    reskinPageNav("MerchantNextPageButton")
end

local function findCloseButton(f)
    if _G.MerchantFrameCloseButton then return _G.MerchantFrameCloseButton end
    for _, child in ipairs({ f:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "Button" and child.GetNormalTexture then
            local t = child:GetNormalTexture()
            local p = t and t.GetTexture and t:GetTexture()
            if type(p) == "string" and p:lower():find("ui%-panel%-minimizebutton") then return child end
        end
    end
    return nil
end

local function modernizeCloseButton()
    local f = _G.MerchantFrame
    if not f then return end
    f.CloseButton = f.CloseButton or findCloseButton(f)
    if not f.CloseButton then return end
    if PCModernizeCloseButton then PCModernizeCloseButton(f, { frameLevelBump = 20 }) end
end

-- ============================================================================
-- PER-UPDATE SYNC
-- ============================================================================

local function setRowPitch(gap)
    local prev = _G.MerchantItem1
    for _, i in ipairs({ 3, 5, 7, 9 }) do
        local row = _G["MerchantItem" .. i]
        if not (row and prev) then return end
        row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, gap)
        prev = row
    end
    local row11, row9 = _G.MerchantItem11, _G.MerchantItem9
    if row11 and row9 then
        row11:ClearAllPoints()
        row11:SetPoint("TOPLEFT", row9, "BOTTOMLEFT", 0, gap)
    end
end

local function setInsetForTab(f)
    local inset = f._neGridInset
    if not inset then return end
    local buyback = (f.selectedTab == 2)
    local y = buyback and INSET_BR_Y_BUYBACK or INSET_BR_Y
    if inset._neBottom == y then return end
    inset._neBottom = y
    inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", INSET_BR_X, y)
    local tone = buyback and INSET_TONE_BUYBACK or INSET_TONE
    local bg = f._neGridInsetBg
    if bg then bg:SetVertexColor(tone[1], tone[2], tone[3]) end
end

local function postMerchantUpdate()
    local f = _G.MerchantFrame
    if not f or not f._neBuilt then return end
    stats.update = stats.update + 1
    stats.tab = f.selectedTab

    hideClassicChrome()
    setInsetForTab(f)
    if f.Bg then f.Bg:Show() end

    if f.Title and _G.MerchantNameText then
        f.Title:SetText(_G.MerchantNameText:GetText() or "")
    end

    local p = _G.MerchantFramePortrait
    if p then
        p:Show()
        if f.selectedTab == 2 then
            p:SetTexture("Interface\\MerchantFrame\\UI-BuyBack-Icon")
            p:SetTexCoord(0, 1, 0, 1)
        elseif SetPortraitTexture then
            SetPortraitTexture(p, "NPC")
        end
    end

    local onMerchant = (f.selectedTab == 1)

    if f._neBotFrame then
        if onMerchant then f._neBotFrame:Show() else f._neBotFrame:Hide() end
    end
    local sell = _G.DragonUI_MerchantSellAllJunkButton
    if sell then
        if onMerchant then sell:Show() else sell:Hide() end
    end

    local buyback = _G.MerchantBuyBackItem
    if buyback then
        if onMerchant then buyback:Show() else buyback:Hide() end
    end
    if not onMerchant then
        for _, name in ipairs({
            "MerchantGuildBankRepairButton", "MerchantRepairAllButton", "MerchantRepairItemButton",
        }) do
            local b = _G[name]
            if b then b:Hide() end
        end
    end

    for i = 1, BUYBACK_PER_PAGE do
        clampName(_G["MerchantItem" .. i .. "Name"], 84)
    end
    if _G.MerchantBuyBackItemName then _G.MerchantBuyBackItemName:Hide() end
    if _G.MerchantBuyBackItemMoneyFrame then _G.MerchantBuyBackItemMoneyFrame:Hide() end
    fitBuybackIcon()
    fitBuybackToBar()
    fitBuybackQualityGlow()

    postRepairButtons()
end

local function colourRow(prefix, link)
    if not _G[prefix] then return end
    local quality = link and select(3, GetItemInfo(link)) or nil

    local nm = _G[prefix .. "Name"]
    if nm then
        local c = TextColor(quality)
        if c then
            nm:SetTextColor(c.r, c.g, c.b)
        else
            nm:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
        end
    end

    local ib = _G[prefix .. "ItemButton"]
    local bang = ib and ib.IconQuestTexture
    if bang then
        if link and ItemStartsQuestByLink(link) then bang:Show() else bang:Hide() end
    end
end

local function postUpdateMerchantInfo()
    local f = _G.MerchantFrame
    if not f or not f._neBuilt then return end
    stats.merchantInfo = stats.merchantInfo + 1
    stats.tab = f.selectedTab
    setRowPitch(ROW_GAP_MERCHANT)
    local page = f.page or 1
    for i = 1, ITEMS_PER_PAGE do
        local index = ((page - 1) * ITEMS_PER_PAGE) + i
        colourRow("MerchantItem" .. i, GetMerchantItemLink and GetMerchantItemLink(index))
    end
    local n = (GetNumBuybackItems and GetNumBuybackItems()) or 0
    colourRow("MerchantBuyBackItem",
              (n > 0 and GetBuybackItemLink) and GetBuybackItemLink(n) or nil)
end

local function postUpdateBuybackInfo()
    local f = _G.MerchantFrame
    if not f or not f._neBuilt then return end
    stats.buybackInfo = stats.buybackInfo + 1
    stats.tab = f.selectedTab
    setRowPitch(ROW_GAP_BUYBACK)
    for i = 1, BUYBACK_PER_PAGE do
        colourRow("MerchantItem" .. i, GetBuybackItemLink and GetBuybackItemLink(i))
        local ib = _G["MerchantItem" .. i .. "ItemButton"]
        if ib and ib.IconQuestTexture then ib.IconQuestTexture:Hide() end
    end
end

-- Timer-based sync (safe even if FrameXML updaters throw)
-- On first MERCHANT_SHOW, build the modern chrome before syncing.
-- ============================================================================
-- TAB RESKIN — inline version of NE.tabs.ReskinClassicTab + SizeAndAnchorTabs
-- Replaces classic wooden tabs with retail atlas art and repositions them below
-- the frame edge (inside the nineslice border).
-- ============================================================================

local TAB_ATLAS = {
    Left           = "uiframe-tab-left",
    Right          = "uiframe-tab-right",
    Middle         = "_uiframe-tab-center",
    LeftDisabled   = "uiframe-activetab-left",
    RightDisabled  = "uiframe-activetab-right",
    MiddleDisabled = "_uiframe-activetab-center",
}
local TAB_SIZE = {
    Left           = { w = 35, h = 36 },
    Right          = { w = 37, h = 36 },
    Middle         = { h = 36 },
    LeftDisabled   = { w = 35, h = 42 },
    RightDisabled  = { w = 37, h = 42 },
    MiddleDisabled = { h = 42 },
}

local function reskinSingleTab(tabName)
    local tab = _G[tabName]
    if not tab or tab._duiTabReskinned then return end

    local texSet = texSetAtlas
    if not texSet then return end

    -- Replace the 6 texture pieces with retail atlas art
    for suffix, atlas in pairs(TAB_ATLAS) do
        local tex = _G[tabName .. suffix]
        if tex then
            texSet(tex, atlas, false)
            local sz = TAB_SIZE[suffix]
            if sz then
                if sz.w then tex:SetWidth(sz.w) end
                if sz.h then tex:SetHeight(sz.h) end
            end
        end
    end

    -- Reposition the pieces relative to the tab button
    local left   = _G[tabName .. "Left"]
    local right  = _G[tabName .. "Right"]
    local middle = _G[tabName .. "Middle"]
    local leftD  = _G[tabName .. "LeftDisabled"]
    local rightD = _G[tabName .. "RightDisabled"]
    local midD   = _G[tabName .. "MiddleDisabled"]

    if left   then left:ClearAllPoints();   left:SetPoint("TOPLEFT",  tab, "TOPLEFT",  0, 0) end
    if right  then right:ClearAllPoints();  right:SetPoint("TOPRIGHT", tab, "TOPRIGHT",  0, 0) end
    if leftD  then leftD:ClearAllPoints();  leftD:SetPoint("TOPLEFT",  tab, "TOPLEFT",  0, 0) end
    if rightD then rightD:ClearAllPoints(); rightD:SetPoint("TOPRIGHT", tab, "TOPRIGHT",  0, 0) end

    if middle and left and right then
        middle:ClearAllPoints()
        middle:SetPoint("TOPLEFT",  left,  "TOPRIGHT", 0, 0)
        middle:SetPoint("TOPRIGHT", right, "TOPLEFT",  0, 0)
        middle:SetHorizTile(true)
    end
    if midD and leftD and rightD then
        midD:ClearAllPoints()
        midD:SetPoint("TOPLEFT",  leftD,  "TOPRIGHT", 0, 0)
        midD:SetPoint("TOPRIGHT", rightD, "TOPLEFT",  0, 0)
        midD:SetHorizTile(true)
    end

    -- Font and selection offsets
    tab:SetNormalFontObject(GameFontNormalSmall)
    tab:SetHighlightFontObject(GameFontHighlightSmall)
    tab:SetDisabledFontObject(GameFontNormalSmall)
    tab.selectedTextY   = -3
    tab.deselectedTextY =  2

    tab._duiTabReskinned = true
end

local function reskinMerchantTabs(f)
    reskinSingleTab("MerchantFrameTab1")
    reskinSingleTab("MerchantFrameTab2")

    -- Position tabs along the frame's BOTTOMLEFT edge, inside the nineslice border.
    -- Retail hangs them off the bottom; classic sits them at BOTTOMLEFT+(11,46) which
    -- is inside the nineslice overlay layer and reads as crowded.
    local prev
    for _, name in ipairs({ "MerchantFrameTab1", "MerchantFrameTab2" }) do
        local tab = _G[name]
        if tab and tab:IsShown() then
            tab:ClearAllPoints()
            if prev then
                tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", -10, 0)
            else
                tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2)
            end
            prev = tab
        end
    end
end

-- ============================================================================
-- BUILD — deferred from login to first MERCHANT_SHOW
-- ============================================================================

local built = false

local function buildModernChrome()
    if built then return end
    local f = _G.MerchantFrame
    if not f then return end
    built = true

    applyModernChrome()

    if PCEnsureTitle then
        PCEnsureTitle(f, (_G.MerchantNameText and _G.MerchantNameText:GetText()) or "")
    end

    if _G.MerchantFramePortrait and portraitApplyCutout then
        portraitApplyCutout(_G.MerchantFramePortrait, f)
    end

    buildGridInset()
    buildBottomBand()
    reskinAllSlots()
    fitBuybackToBar()
    addQuestBangs()
    reskinRepairIcons()
    buildMoneyInset()
    modernizeCloseButton()
    reskinPageNavButtons()

    -- Tab reskinning: replace classic wooden tabs with retail atlas art
    reskinMerchantTabs(f)

    for i = 1, BUYBACK_PER_PAGE do clampName(_G["MerchantItem" .. i .. "Name"], 84) end

    -- Sibling modules (SellAllJunk, BuybackUndo) build their buttons here
    if addon.MerchantSellAllJunkBuild then addon.MerchantSellAllJunkBuild() end
    if addon.MerchantBuybackUndoBuild then addon.MerchantBuybackUndoBuild() end

    addRetailSlotBgs()

    f._neBuilt = true

    if f:IsShown() and _G.MerchantFrame_Update then
        MerchantFrame_Update()
    else
        postMerchantUpdate()
    end
end

-- Timer-based sync (safe even if FrameXML updaters throw)
-- On first MERCHANT_SHOW, build the modern chrome before syncing.
local syncPending
local function syncSoon()
    local f = _G.MerchantFrame
    if not f or syncPending then return end
    syncPending = true
    C_Timer.After(0, function()
        syncPending = false
        local frame = _G.MerchantFrame
        if not frame or not frame:IsShown() then return end
        -- First show: build the modern chrome (deferred from login to MERCHANT_SHOW).
        if not built then
            buildModernChrome()
        end
        if not frame._neBuilt then return end
        postMerchantUpdate()
        if frame.selectedTab == 2 then postUpdateBuybackInfo() else postUpdateMerchantInfo() end
    end)
end

-- ============================================================================
-- ARM — called once at login to set up hooks and suppression
-- ============================================================================

local function ArmMerchant()
    if MerchantModule.applied then return end

    hideClassicChrome()
    applyLayout()

    -- Hook FrameXML updaters
    if _G.MerchantFrame_Update and not MerchantModule.hooks["MerchantFrame_Update"] then
        hooksecurefunc("MerchantFrame_Update", postMerchantUpdate)
        MerchantModule.hooks["MerchantFrame_Update"] = true
    end
    if _G.MerchantFrame_UpdateMerchantInfo and not MerchantModule.hooks["MerchantFrame_UpdateMerchantInfo"] then
        hooksecurefunc("MerchantFrame_UpdateMerchantInfo", postUpdateMerchantInfo)
        MerchantModule.hooks["MerchantFrame_UpdateMerchantInfo"] = true
    end
    if _G.MerchantFrame_UpdateBuybackInfo and not MerchantModule.hooks["MerchantFrame_UpdateBuybackInfo"] then
        hooksecurefunc("MerchantFrame_UpdateBuybackInfo", postUpdateBuybackInfo)
        MerchantModule.hooks["MerchantFrame_UpdateBuybackInfo"] = true
    end
    if _G.MerchantFrame_UpdateRepairButtons and not MerchantModule.hooks["MerchantFrame_UpdateRepairButtons"] then
        hooksecurefunc("MerchantFrame_UpdateRepairButtons", postRepairButtons)
        MerchantModule.hooks["MerchantFrame_UpdateRepairButtons"] = true
    end

    -- Tab button click hooks (belt on top of FrameXML hooks)
    for _, tabName in ipairs({ "MerchantFrameTab1", "MerchantFrameTab2" }) do
        local tab = _G[tabName]
        if tab and tab.HookScript and not MerchantModule.hooks["tab_" .. tabName] then
            tab:HookScript("OnClick", function()
                stats.tabClick = stats.tabClick + 1
                syncSoon()
            end)
            MerchantModule.hooks["tab_" .. tabName] = true
        end
    end

    -- Event-driven sync
    local syncFrame = CreateFrame("Frame")
    syncFrame:RegisterEvent("MERCHANT_SHOW")
    syncFrame:RegisterEvent("MERCHANT_UPDATE")
    syncFrame:RegisterEvent("MERCHANT_CLOSED")
    syncFrame:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_SHOW" then
            stats.evShow = stats.evShow + 1;  trace("evSHOW")
        elseif event == "MERCHANT_CLOSED" then
            stats.evClosed = stats.evClosed + 1;  trace("evCLOSED")
        end
        syncSoon()
    end)
    MerchantModule.frames.syncFrame = syncFrame

    -- OnShow/OnHide trace hooks
    local mf = _G.MerchantFrame
    if mf and mf.HookScript then
        mf:HookScript("OnShow", function() stats.onShow = stats.onShow + 1; trace("OnShow") end)
        mf:HookScript("OnHide", function() stats.onHide = stats.onHide + 1; trace("OnHide") end)
    end

    -- GET_ITEM_INFO_RECEIVED for uncached item quality + quest bang
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    watcher:SetScript("OnEvent", function()
        local f = _G.MerchantFrame
        if not (f and f._neBuilt and f:IsShown()) then return end
        if f.selectedTab == 2 then postUpdateBuybackInfo() else postUpdateMerchantInfo() end
    end)
    MerchantModule.frames.watcher = watcher

    MerchantModule.applied = true
end

-- ============================================================================
-- LIFECYCLE: Apply / Restore / Refresh
-- ============================================================================

local function ApplyMerchant(force)
    if MerchantModule.applied and not force then return end
    if not IsModuleEnabled() then return end
    if MerchantModule.applied then
        RestoreMerchant(false)
        MerchantModule.applied = false
    end
    ArmMerchant()
end

local function RestoreMerchant(resetDeps)
    if not MerchantModule.applied then return end
    -- NOTE: hooksecurefunc are permanent for the session — we cannot un-hook them.
    -- This module is effectively load-once. Restore just tears down the visual chrome.
    MerchantModule.applied = false
end

local function RefreshMerchant(forceSync)
    if MerchantModule.applied then
        RestoreMerchant(false)
    end
    if IsModuleEnabled() then
        ApplyMerchant(forceSync == true)
    end
end

-- ============================================================================
-- EXPOSE ON ADDON NAMESPACE
-- ============================================================================

function addon.ApplyMerchantSystem() ApplyMerchant() end
function addon.RestoreMerchantSystem() RestoreMerchant() end
function addon.RefreshMerchantSystem() RefreshMerchant() end

-- ============================================================================
-- PROFILE CHANGE HANDLER
-- ============================================================================

local function OnProfileChanged()
    if IsModuleEnabled() then
        RefreshMerchant()
    else
        if (addon.ShouldDeferModuleDisable and addon:ShouldDeferModuleDisable("merchant", MerchantModule)) then
            return
        end
        RestoreMerchant()
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
        addon:After(0.5, function()
            if addon.db and addon.db.RegisterCallback then
                addon.db.RegisterCallback(addon, "OnProfileChanged", OnProfileChanged)
                addon.db.RegisterCallback(addon, "OnProfileCopied", OnProfileChanged)
                addon.db.RegisterCallback(addon, "OnProfileReset", OnProfileChanged)
            end
        end)
        MerchantModule.initialized = true
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not IsModuleEnabled() then return end
        ApplyMerchant()
        addon:After(0.5, function()
            if not IsModuleEnabled() then return end
            -- First MERCHANT_SHOW builds the chrome; arm hooks early so they exist
            -- before the first MerchantFrame_Update.
            ArmMerchant()
        end)
    end
end)

-- ============================================================================
-- SLASH COMMAND — /dragonui merchant
-- ============================================================================

SLASH_DRAGONUI_MERCHANT1 = "/dragonui-merchant"
SlashCmdList["DRAGONUI_MERCHANT"] = function() diagnose() end
