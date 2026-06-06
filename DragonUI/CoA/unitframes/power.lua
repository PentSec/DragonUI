local addon = select(2, ...)
local CoA = addon.CoA

local ADDITIONAL_POWER_BAR_INDEX = 0

function CoA:HasAdditionalPowerForPlayer()
    local primaryPowerType = UnitPowerType("player")
    local manaMax = UnitPowerMax("player", ADDITIONAL_POWER_BAR_INDEX)
    return primaryPowerType ~= 0 and manaMax > 0
end

function CoA:GetPrimaryPowerToken()
    local _, powerToken = UnitPowerType("player")
    return powerToken
end

function CoA:GetCoAPowerType()
    local powerType = UnitPowerType("player")
    if powerType == 0 then
        return "MANA"
    elseif powerType == 1 then
        return "RAGE"
    elseif powerType == 2 then
        return "FOCUS"
    elseif powerType == 3 then
        return "ENERGY"
    end
    return "MANA"
end

function CoA:GetPowerColorFromConfig(powerToken)
    local config = addon.db and addon.db.profile and addon.db.profile.unitframe and addon.db.profile.unitframe.player
    if config and config.power_colors and config.power_colors[powerToken] then
        return config.power_colors[powerToken]
    end
    local DF_POWER_COLORS = {
        MANA        = { r = 0.02, g = 0.32, b = 0.71 },
        RAGE        = { r = 1.00, g = 0.00, b = 0.00 },
        FOCUS       = { r = 1.00, g = 0.50, b = 0.25 },
        ENERGY      = { r = 1.00, g = 1.00, b = 0.00 },
        HAPPINESS   = { r = 0.00, g = 1.00, b = 1.00 },
        RUNES       = { r = 0.50, g = 0.50, b = 0.50 },
        RUNIC_POWER = { r = 0.00, g = 0.82, b = 1.00 },
    }
    return DF_POWER_COLORS[powerToken] or DF_POWER_COLORS.MANA
end

function CoA:CreateAdditionalPowerBar(parentFrame)
    local name = parentFrame:GetName() or "DragonUI"
    local bar = CreateFrame("StatusBar", name .. "AdditionalPowerBar", parentFrame)
    bar:SetSize(120, 8)
    bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")

    local heroColor = CoA.herocolor or { r = 0.02, g = 0.32, b = 0.71 }
    bar:SetStatusBarColor(heroColor.r, heroColor.g, heroColor.b, 1)

    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:Hide()

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.6)

    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    text:SetText("")
    bar.text = text

    bar:RegisterEvent("UNIT_POWER_UPDATE")
    bar:RegisterEvent("UNIT_POWER_BAR_UPDATE")
    bar:RegisterEvent("UNIT_MAXPOWER")
    bar:RegisterEvent("UNIT_DISPLAYPOWER")

    bar:SetScript("OnEvent", function(self, event, unit, powerType)
        if unit ~= "player" then return end
        CoA:UpdateAdditionalPowerBar(self)
    end)

    return bar
end

function CoA:UpdateAdditionalPowerBar(bar)
    if not bar or not CoA.active then
        return
    end

    if not CoA:HasAdditionalPowerForPlayer() then
        if bar:IsShown() then
            bar:Hide()
        end
        return
    end

    local cur = UnitPower("player", ADDITIONAL_POWER_BAR_INDEX)
    local max = UnitPowerMax("player", ADDITIONAL_POWER_BAR_INDEX)
    if max <= 0 then
        bar:Hide()
        return
    end

    bar:SetMinMaxValues(0, max)
    bar:SetValue(cur)
    bar:Show()

    if bar.text then
        bar.text:SetText(math.floor(cur) .. " / " .. math.floor(max))
    end
end
