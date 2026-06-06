local addon = select(2, ...)

local CoA = {
    active = false,
}

addon.CoA = CoA

function CoA:Detect()
    local hasCPlayer = rawget(_G, "C_Player") ~= nil
    if not hasCPlayer then return false end

    local class = select(2, UnitClass("player"))
    if class ~= "HERO" then
        return true
    end
    return false
end

function CoA:HasAscensionUI()
    return rawget(_G, "CUSTOM_CLASS_COLORS") ~= nil
end

function CoA:SetupClassColors()
    local class = select(2, UnitClass("player"))

    if self:HasAscensionUI() then
        local colors = _G.CUSTOM_CLASS_COLORS
        for cls, color in pairs(colors) do
            if not _G.RAID_CLASS_COLORS[cls] then
                _G.RAID_CLASS_COLORS[cls] = { r = color.r, g = color.g, b = color.b }
            end
        end
    end

    local pc = _G.RAID_CLASS_COLORS[class]
    if pc then
        CoA.herocolor = { r = pc.r, g = pc.g, b = pc.b }
    else
        CoA.herocolor = { r = 1, g = 1, b = 1 }
    end
end
