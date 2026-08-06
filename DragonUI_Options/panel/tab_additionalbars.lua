--[[
================================================================================
DragonUI Options Panel - Additional Bars Tab
================================================================================
Stance Bar, Pet Bar, Vehicle Bar, Totem Bar settings.
================================================================================
]]

local addon = DragonUI
if not addon then return end

local LO = addon.LO
local C = addon.PanelControls
local Panel = addon.OptionsPanel

local function RefreshAdditionalBarHotkeys()
    if addon.RefreshAdditionalBarHotkeys then
        addon.RefreshAdditionalBarHotkeys()
    elseif addon.RefreshAllHotkeys then
        addon.RefreshAllHotkeys()
    elseif addon.RefreshButtons then
        addon.RefreshButtons()
    end
end

-- ============================================================================
-- ADDITIONAL BARS TAB BUILDER
-- ============================================================================

local function BuildAdditionalBarsTab(scroll)
    C:AddDescription(scroll, LO["Bars that appear based on your class and situation."])

    -- ====================================================================
    -- STANCE BAR
    -- ====================================================================
    local stance = C:AddSection(scroll, LO["Stance Bar"])

    C:AddToggle(stance, {
        label = LO["Show Stance Bar"],
        dbPath = "additional.stance.show",
        callback = function()
            if addon.RefreshStance then addon.RefreshStance() end
        end,
    })

    C:AddToggle(stance, {
        label = LO["Show Hotkey Text"],
        dbPath = "additional.stance.show_hotkey",
        callback = RefreshAdditionalBarHotkeys,
    })

    C:AddSlider(stance, {
        label = LO["Button Size"],
        dbPath = "additional.stance.button_size",
        min = 16, max = 64, step = 1,
        width = 200,
        callback = function()
            if addon.RefreshStance then addon.RefreshStance() end
        end,
    })

    C:AddSlider(stance, {
        label = LO["Button Spacing"],
        dbPath = "additional.stance.button_spacing",
        min = 0, max = 20, step = 1,
        width = 200,
        callback = function()
            if addon.RefreshStance then addon.RefreshStance() end
        end,
    })

    C:AddSlider(stance, {
        label = LO["X Position"],
        desc = LO["Horizontal position of stance bar from screen center. Negative values move left, positive values move right."],
        dbPath = "additional.stance.x_position",
        min = -600, max = 600, step = 1,
        width = 200,
        callback = function()
            if addon.UpdateStanceBarPosition then addon.UpdateStanceBarPosition() end
        end,
    })

    C:AddSlider(stance, {
        label = LO["Y Offset"],
        dbPath = "additional.stance.y_offset",
        min = -200, max = 200, step = 1,
        width = 200,
        callback = function()
            if addon.UpdateStanceBarPosition then addon.UpdateStanceBarPosition() end
        end,
    })

    C:AddHeading(stance, LO["Visibility"])
    C:AddVisibilityFadeToggles(stance, {
        dbPrefix = "additional.stance",
        hoverDesc = LO["Fade the stance bar until you hover over it."],
        combatDesc = LO["Fade the stance bar until you enter combat."],
        callback = function()
            if addon.RefreshStance then addon.RefreshStance() end
        end,
    })

    -- ====================================================================
    -- PET BAR
    -- ====================================================================
    local pet = C:AddSection(scroll, LO["Pet Bar"])

    C:AddToggle(pet, {
        label = LO["Show Hotkey Text"],
        dbPath = "additional.pet.show_hotkey",
        callback = RefreshAdditionalBarHotkeys,
    })

    C:AddSlider(pet, {
        label = LO["Scale"],
        dbPath = "additional.pet.scale",
        min = 0.5, max = 2.0, step = 0.05,
        width = 200,
        callback = function()
            if addon.RefreshPetbarFrame then addon.RefreshPetbarFrame() end
        end,
    })

    -- ---- Pet Bar Layout (grid: columns/buttons) ----
    local petLayout = C:AddSection(scroll, LO["Pet Bar Layout"])
    C:AddSlider(petLayout, {
        dbPath = "additional.pet.columns",
        label = LO["Columns"],
        min = 1, max = 10, step = 1,
        width = 200,
        callback = function()
            if addon.RefreshPetbarFrame then addon.RefreshPetbarFrame() end
        end,
    })
    
    C:AddToggle(pet, {
        label = LO["Show Empty Slots"],
        desc = LO["Show the button frame on pet slots with no ability assigned."],
        dbPath = "additional.pet.grid",
        callback = function()
            if addon.RefreshPetbarGrid then addon.RefreshPetbarGrid() end
        end,
    })

    C:AddHeading(pet, LO["Visibility"])
    C:AddVisibilityFadeToggles(pet, {
        dbPrefix = "additional.pet",
        hoverDesc = LO["Fade the pet bar until you hover over it."],
        combatDesc = LO["Fade the pet bar until you enter combat."],
        callback = function()
            if addon.RefreshPetbarFrame then addon.RefreshPetbarFrame() end
        end,
    })

    C:AddSlider(petLayout, {
        dbPath = "additional.pet.buttons_shown",
        label = LO["Buttons Shown"],
        min = 1, max = 10, step = 1,
        width = 200,
        callback = function()
            if addon.RefreshPetbarFrame then addon.RefreshPetbarFrame() end
        end,
    })

    local petPresetRow = C:AddRow(petLayout)

    C:AddButton(petPresetRow, {
        label = "1x10",
        width = 60,
        callback = function()
            C:SetDBValue("additional.pet.columns", 10)
            C:SetDBValue("additional.pet.buttons_shown", 10)
            if addon.RefreshPetbarFrame then addon.RefreshPetbarFrame() end
            Panel:SelectTab("additionalbars")
        end,
    })

    C:AddButton(petPresetRow, {
        label = "2x5",
        width = 60,
        callback = function()
            C:SetDBValue("additional.pet.columns", 5)
            C:SetDBValue("additional.pet.buttons_shown", 10)
            if addon.RefreshPetbarFrame then addon.RefreshPetbarFrame() end
            Panel:SelectTab("additionalbars")
        end,
    })

    C:AddButton(petPresetRow, {
        label = "5x2",
        width = 60,
        callback = function()
            C:SetDBValue("additional.pet.columns", 2)
            C:SetDBValue("additional.pet.buttons_shown", 10)
            if addon.RefreshPetbarFrame then addon.RefreshPetbarFrame() end
            Panel:SelectTab("additionalbars")
        end,
    })

    C:AddButton(petPresetRow, {
        label = "10x1",
        width = 60,
        callback = function()
            C:SetDBValue("additional.pet.columns", 1)
            C:SetDBValue("additional.pet.buttons_shown", 10)
            if addon.RefreshPetbarFrame then addon.RefreshPetbarFrame() end
            Panel:SelectTab("additionalbars")
        end,
    })

    -- ====================================================================
    -- VEHICLE BAR
    -- ====================================================================
    local vehicle = C:AddSection(scroll, LO["Vehicle Bar"])

    C:AddToggle(vehicle, {
        label = LO["Blizzard Art Style"],
        desc = LO["Use Blizzard vehicle bar art with health/power display. Requires reload."],
        dbPath = "additional.vehicle.artstyle",
        requiresReload = true,
    })

    -- ====================================================================
    -- TOTEM BAR
    -- ====================================================================
    local totem = C:AddSection(scroll, LO["Totem Bar (Shaman)"])

    C:AddToggle(totem, {
        label = LO["Show Totem Bar"],
        dbPath = "additional.totem.show",
        callback = function()
            if addon.RefreshMulticast then addon.RefreshMulticast(true) end
        end,
    })

    C:AddToggle(totem, {
        label = LO["Show Hotkey Text"],
        dbPath = "additional.totem.show_hotkey",
        callback = RefreshAdditionalBarHotkeys,
    })

    C:AddSlider(totem, {
        label = LO["Button Size"],
        getFunc = function()
            local cfg = addon.db.profile.additional.totem
            if cfg and cfg.button_size then return cfg.button_size end
            return addon.db.profile.additional.size or 31
        end,
        setFunc = function(val)
            if not addon.db.profile.additional.totem then
                addon.db.profile.additional.totem = {}
            end
            addon.db.profile.additional.totem.button_size = val
            if addon.RefreshMulticast then addon.RefreshMulticast(true) end
        end,
        min = 16, max = 64, step = 1,
        width = 200,
    })

    C:AddSlider(totem, {
        label = LO["Button Spacing"],
        getFunc = function()
            local cfg = addon.db.profile.additional.totem
            if cfg and cfg.button_spacing then return cfg.button_spacing end
            return addon.db.profile.additional.spacing or 6
        end,
        setFunc = function(val)
            if not addon.db.profile.additional.totem then
                addon.db.profile.additional.totem = {}
            end
            addon.db.profile.additional.totem.button_spacing = val
            if addon.RefreshMulticast then addon.RefreshMulticast(true) end
        end,
        min = 0, max = 20, step = 1,
        width = 200,
    })

    C:AddHeading(totem, LO["Visibility"])
    C:AddVisibilityFadeToggles(totem, {
        dbPrefix = "additional.totem",
        hoverDesc = LO["Fade the totem bar until you hover over it."],
        combatDesc = LO["Fade the totem bar until you enter combat."],
        callback = function()
            if addon.RefreshMulticast then addon.RefreshMulticast(true) end
        end,
    })
    -- Extra Bar (#330) is under Action Bars — general-purpose, not class-conditional like the bars above.
end

-- Register the tab (order 4 = right after Action Bars)
Panel:RegisterTab("additionalbars", LO["Additional Bars"], BuildAdditionalBarsTab, 4)
