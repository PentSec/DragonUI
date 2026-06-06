local addon = select(2, ...)
local CoA = addon.CoA

local function InitializeCoA()
    if CoA.initialized then return end

    CoA.active = CoA:Detect()
    if not CoA.active then return end

    CoA:SetupClassColors()
    addon:Debug("|cFF00FF00[DragonUI CoA]|r Conquest of Azeroth detected. Loading compatibility layer.")

    if addon.RegisterHook then
        if addon.ModuleRegistry.modules["player"] then
            addon:RegisterHook("player", "post", function()
                if CoA.modules and CoA.modules.player then
                    CoA.modules.player:Apply()
                end
            end)
        end
    end

    if CoA.modules and CoA.modules.player then
        CoA.modules.player:Apply()
    end

    CoA.initialized = true
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function()
    InitializeCoA()
    initFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
end)
