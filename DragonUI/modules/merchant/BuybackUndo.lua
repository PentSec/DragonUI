-- DragonUI/modules/merchant/BuybackUndo.lua — retail's buyback undo arrow.
--
-- DOWNPORT of NewEra/MerchantFrame/BuybackUndo.lua, adapted for DragonUI.
-- Retail nests an UndoFrame inside the merchant tab's buyback slot with a
-- `common-icon-undo` arrow at CENTER, desaturated while GetNumBuybackItems() == 0.

local addon = select(2, ...)
if not addon then return end

local arrowTex

local function refreshDesaturation()
    if not arrowTex then return end
    SetDesaturation(arrowTex, ((GetNumBuybackItems and GetNumBuybackItems()) or 0) == 0)
end

function addon.MerchantBuybackUndoBuild()
    local itemBtn = _G.MerchantBuyBackItemItemButton
    if not itemBtn or itemBtn._duiUndoBuilt then return end

    local undo = CreateFrame("Frame", nil, itemBtn)
    undo:SetAllPoints(itemBtn)
    undo:SetFrameLevel((itemBtn:GetFrameLevel() or 0) + 2)

    local NE = DragonUIWorldMapHost
    local tex = undo:CreateTexture(nil, "ARTWORK")
    if NE and NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(tex, "common-icon-undo", false) then
        tex:SetSize(20, 20)
        tex:SetPoint("CENTER", 0, -1)
        arrowTex = tex
        undo.Arrow = tex
        itemBtn.UndoFrame = undo
        itemBtn._duiUndoBuilt = true
        refreshDesaturation()

        if _G.MerchantFrame_Update then
            hooksecurefunc("MerchantFrame_Update", refreshDesaturation)
        end
    else
        undo:Hide()
    end
end
