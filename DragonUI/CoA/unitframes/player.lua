local addon = select(2, ...)
local CoA = addon.CoA

CoA.modules = CoA.modules or {}
CoA.modules.player = {
    Apply = function()
        if CoA._playerAPHooked then return end

        local additionalPowerBar

        local function CreateCoAAdditionalPowerBar()
            if additionalPowerBar then
                return
            end
            additionalPowerBar = CoA:CreateAdditionalPowerBar(PlayerFrame)
            additionalPowerBar:SetPoint("BOTTOM", PlayerFrame, "BOTTOM", 0, -25)
            additionalPowerBar:SetWidth(PlayerFrame:GetWidth() or 200)
            additionalPowerBar:SetHeight(8)

            local manaBar = _G.PlayerFrameManaBar
            if manaBar and CoA:HasAdditionalPowerForPlayer() then
                CoA:UpdateAdditionalPowerBar(additionalPowerBar)
            end
        end

        local pewFrame = CreateFrame("Frame")
        pewFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        pewFrame:SetScript("OnEvent", function()
            if CoA.active then
                CreateCoAAdditionalPowerBar()
            end
            pewFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end)

        CoA._playerAPHooked = true
    end,
}
