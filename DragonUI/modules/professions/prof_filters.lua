-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)

local P = addon.Professions
local L = addon.L
local F = { skillUpOnly = false }
P.Filters = F

-- Server-side filters go through the stock calls and Blizzard's own rules; only Skill-up only is client-side.
local function afterFilterChange()
    TradeSkillListScrollFrameScrollBar:SetValue(0)
    FauxScrollFrame_SetOffset(TradeSkillListScrollFrame, 0)
    TradeSkillFrame_Update()
    P.Fire("FiltersChanged")
end

function F.HaveMaterials()
    return TradeSkillFrameAvailableFilterCheckButton:GetChecked() and true or false
end

-- Clicking the stock checkbox runs Blizzard's OnClick and keeps the state Blizzard re-applies on every open.
function F.ToggleHaveMaterials()
    local box = TradeSkillFrameAvailableFilterCheckButton
    local before = box:GetChecked() and true or false
    box:Click()
    if (box:GetChecked() and true or false) == before then
        box:SetChecked(not before)
        TradeSkillOnlyShowMakeable(not before)
    end
    P.Fire("FiltersChanged")
end

local function selectedIndex(getter, count)
    if getter(0) then return 0 end
    for i = 1, count do
        if getter(i) then return i end
    end
    return 0
end

function F.SubClasses()
    return { GetTradeSkillSubClasses() }
end

function F.SubClassIndex()
    return selectedIndex(GetTradeSkillSubClassFilter, #F.SubClasses())
end

function F.Slots()
    return { GetTradeSkillInvSlots() }
end

function F.SlotIndex()
    return selectedIndex(GetTradeSkillInvSlotFilter, #F.Slots())
end

-- Same rule as TradeSkillSubClassDropDownButton_OnClick: a slot that no longer applies falls back to all slots.
function F.SetSubClass(i)
    SetTradeSkillSubClassFilter(i, 1, 1)
    local list = F.SubClasses()
    TradeSkillSubClassDropDownText:SetText(i == 0 and ALL_SUBCLASSES or list[i] or ALL_SUBCLASSES)
    if i ~= 0 and TradeSkillFilterFrame_InvSlotName(GetTradeSkillInvSlots()) ~= F.slotName then
        SetTradeSkillInvSlotFilter(0, 1, 1)
        TradeSkillInvSlotDropDownText:SetText(ALL_INVENTORY_SLOTS)
    end
    afterFilterChange()
end

-- Mirrors TradeSkillInvSlotDropDownButton_OnClick, including what it records as the selected slot.
function F.SetSlot(i)
    SetTradeSkillInvSlotFilter(i, 1, 1)
    local list = F.Slots()
    TradeSkillInvSlotDropDownText:SetText(i == 0 and ALL_INVENTORY_SLOTS or list[i] or ALL_INVENTORY_SLOTS)
    F.slotName = TradeSkillFilterFrame_InvSlotName(GetTradeSkillInvSlots())
    afterFilterChange()
end

function F.SetSkillUpOnly(on)
    F.skillUpOnly = on and true or false
    P.Fire("FiltersChanged")
end

function F.IsActive()
    return F.skillUpOnly or F.HaveMaterials() or F.SubClassIndex() ~= 0 or F.SlotIndex() ~= 0
end

function F.Reset()
    F.skillUpOnly = false
    if F.HaveMaterials() then F.ToggleHaveMaterials() end
    if F.SubClassIndex() ~= 0 then F.SetSubClass(0) end
    if F.SlotIndex() ~= 0 then F.SetSlot(0) end
    P.Fire("FiltersChanged")
end

local function listMenu(list, current, allText, setter)
    local entries = { { text = allText, checked = function() return current() == 0 end, func = function() setter(0) end } }
    for i, name in ipairs(list) do
        entries[#entries + 1] = { text = name, checked = function() return current() == i end, func = function() setter(i) end }
    end
    return entries
end

-- Entries for addon.Menu (never UIDropDownMenu: it taints the world map).
function F.MenuEntries()
    return {
        { text = CRAFT_IS_MAKEABLE, keepShown = true, checked = F.HaveMaterials, func = F.ToggleHaveMaterials,
          tooltip = function(tip) tip:SetText(CRAFT_IS_MAKEABLE_TOOLTIP, 1, 1, 1, 1, true) end },
        { text = L["Skill-up recipes only"], keepShown = true,
          checked = function() return F.skillUpOnly end, func = function() F.SetSkillUpOnly(not F.skillUpOnly) end },
        { isDivider = true },
        { text = L["Categories"], menu = function() return listMenu(F.SubClasses(), F.SubClassIndex, ALL_SUBCLASSES, F.SetSubClass) end },
        { text = L["Slots"], menu = function() return listMenu(F.Slots(), F.SlotIndex, ALL_INVENTORY_SLOTS, F.SetSlot) end },
        { isDivider = true },
        { text = P.Model.AllCollapsed() and L["Expand All"] or L["Collapse All"], func = P.Model.ToggleAll },
        { text = L["Reset filters"], disabled = not F.IsActive(), func = F.Reset },
    }
end
