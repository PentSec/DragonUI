local addon = select(2, ...);

-- =============================================================================
-- DRAGONUI QUEST TRACKER MODULE 
-- =============================================================================

local QuestTrackerModule = {}
addon.QuestTrackerModule = QuestTrackerModule

QuestTrackerModule.questTrackerFrame = nil

-- =============================================================================
-- CONFIG SYSTEM (DragonUI style using database)
-- =============================================================================
local function GetQuestTrackerConfig()
    if not (addon.db and addon.db.profile and addon.db.profile.questtracker) then
        return -100, -37, "TOPRIGHT", true -- defaults con show_header = true
    end
    local config = addon.db.profile.questtracker
    return config.x or -100, config.y or -37, config.anchor or "TOPRIGHT", config.show_header ~= false
end

-- =============================================================================
-- REPLACE BLIZZARD FRAME 
-- =============================================================================
local function ReplaceBlizzardFrame(frame)
    local watchFrame = WatchFrame
    if not watchFrame then return end

    -- SIMPLIFICADO: Solo reposicionar, NO modificar estructura interna
    -- Esto previene romper el estado interno de WatchFrame
    watchFrame:SetMovable(true)
    watchFrame:SetUserPlaced(true)
    watchFrame:ClearAllPoints()
    watchFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
end

-- =============================================================================
-- QUEST TRACKER STYLING (simplified - no hooks)
-- =============================================================================
local function WatchFrame_Collapse(self)
    self:SetWidth(WATCHFRAME_EXPANDEDWIDTH)
end

-- Función para aplicar el styling del header de forma independiente
local function ApplyQuestTrackerStyling()
    local watchFrame = WatchFrame
    if not watchFrame or not watchFrame:IsShown() then return end
    if not WatchFrameCollapseExpandButton then return end

    -- Contar objetivos mostrados actualmente
    local totalObjectives = 0
    local success, numWatches = pcall(GetNumQuestWatches)
    if success and numWatches then
        for i = 1, numWatches do
            local questIndex = GetQuestIndexForWatch(i)
            if questIndex then
                totalObjectives = totalObjectives + 1
            end
        end
    end

    -- Crear/actualizar background
    watchFrame.background = watchFrame.background or watchFrame:CreateTexture(nil, 'BACKGROUND')
    local background = watchFrame.background
    background:SetPoint('RIGHT', WatchFrameCollapseExpandButton, 'RIGHT', 0, 0)

    pcall(SetAtlasTexture, background, 'QuestTracker-Header')
    background:SetSize(watchFrame:GetWidth(), 36)

    local _, _, _, showHeader = GetQuestTrackerConfig()
    if totalObjectives > 0 and showHeader then
        background:Show()
        background:SetAlpha(1)
    else
        background:Hide()
    end
end

local function ForceUpdateQuestTracker()
    if InCombatLockdown() then return end

    -- AÑADIR: Forzar actualización real de Blizzard
    if WatchFrame and WatchFrame:IsVisible() then
        pcall(function()
            -- Esto es seguro - solo llamamos a la función original de Blizzard
            if WatchFrame_Update then
                WatchFrame_Update() -- Sin parámetros, usa self automáticamente
            end
        end)
    end

    -- Luego aplicar nuestro styling
    pcall(ApplyQuestTrackerStyling)
end

-- =============================================================================
-- CONFIG SYSTEM (DragonUI style using database)
-- =============================================================================
local function UpdateQuestTrackerPosition()
    if InCombatLockdown() then return end

    if QuestTrackerModule.questTrackerFrame then
        local x, y, anchor = GetQuestTrackerConfig()
        QuestTrackerModule.questTrackerFrame:ClearAllPoints()
        QuestTrackerModule.questTrackerFrame:SetPoint(anchor, UIParent, anchor, x, y)
    end
end

-- =============================================================================
-- DRAGONUI REFRESH FUNCTION
-- =============================================================================
function addon.RefreshQuestTracker()
    if InCombatLockdown() then return end
    UpdateQuestTrackerPosition()

    -- Forzar actualización completa del tracker
    ForceUpdateQuestTracker()
end

-- =============================================================================
-- INITIALIZATION 
-- =============================================================================
function QuestTrackerModule:Initialize()

    self.questTrackerFrame = CreateFrame('Frame', 'DragonUI_QuestTrackerFrame', UIParent)
    self.questTrackerFrame:SetSize(230, 500)

    -- Position the frame
    UpdateQuestTrackerPosition()

    -- Replace Blizzard frame 
    ReplaceBlizzardFrame(self.questTrackerFrame)

    -- NO instalar hooks aquí - esperar a PLAYER_ENTERING_WORLD
    -- para asegurar que WatchFrame esté completamente inicializado
end

-- Función separada para instalar hooks de forma segura
local function InstallQuestTrackerHooks()
    -- Verificar que WatchFrame existe y está completamente inicializado
    if not WatchFrame then
        return
    end

    -- SOLO hook de WatchFrame_Collapse para el ancho
    -- NO hookear WatchFrame_Update porque causa errores en Blizzard
    hooksecurefunc('WatchFrame_Collapse', WatchFrame_Collapse)

    -- Hook adicionales para asegurar que las quests se muestren
    hooksecurefunc('AddQuestWatch', function()
        if not InCombatLockdown() then
            ForceUpdateQuestTracker()
        end
    end)

    hooksecurefunc('RemoveQuestWatch', function()
        if not InCombatLockdown() then
            ForceUpdateQuestTracker()
        end
    end)
end

-- =============================================================================
-- EDITOR MODE FUNCTIONS
-- =============================================================================
function QuestTrackerModule:ShowEditorTest()
    if self.questTrackerFrame then
        self.questTrackerFrame:SetMovable(true)
        self.questTrackerFrame:EnableMouse(true)
        self.questTrackerFrame:RegisterForDrag("LeftButton")

        self.questTrackerFrame:SetScript("OnDragStart", function(frame)
            frame:StartMoving()
        end)

        self.questTrackerFrame:SetScript("OnDragStop", function(frame)
            frame:StopMovingOrSizing()
            -- Save position to DragonUI database
            local point, _, relativePoint, x, y = frame:GetPoint()
            if addon.db and addon.db.profile then
                -- Initialize questtracker config if not exists
                if not addon.db.profile.questtracker then
                    addon.db.profile.questtracker = {}
                end
                addon.db.profile.questtracker.anchor = point
                addon.db.profile.questtracker.x = x
                addon.db.profile.questtracker.y = y
            end
        end)
    end
end

function QuestTrackerModule:HideEditorTest(savePosition)
    if self.questTrackerFrame then
        self.questTrackerFrame:SetMovable(false)
        self.questTrackerFrame:EnableMouse(false)
        self.questTrackerFrame:SetScript("OnDragStart", nil)
        self.questTrackerFrame:SetScript("OnDragStop", nil)

        if savePosition then
            UpdateQuestTrackerPosition()
        end
    end
end

-- =============================================================================
-- EVENT SYSTEM 
-- =============================================================================
local hooksInstalled = false

local function OnPlayerEnteringWorld()
    if QuestTrackerModule.questTrackerFrame then
        ReplaceBlizzardFrame(QuestTrackerModule.questTrackerFrame)

        -- Instalar hooks SOLO UNA VEZ, después de que WatchFrame esté completamente listo
        if not hooksInstalled then
            InstallQuestTrackerHooks()
            hooksInstalled = true
        end

        -- Forzar actualización al entrar al mundo
        ForceUpdateQuestTracker()
    end
end

-- Agregar eventos adicionales para actualizar el tracker
local lastUpdate = 0
local function OnQuestLogUpdate()
    local now = GetTime()
    if now - lastUpdate < 0.1 then return end -- Max 10 updates/seg
    lastUpdate = now

    if not InCombatLockdown() then
        ForceUpdateQuestTracker()
    end
end

-- Initialize module
addon.package:RegisterEvents(function()
    QuestTrackerModule:Initialize()
end, 'PLAYER_LOGIN')

-- Register PLAYER_ENTERING_WORLD 
addon.package:RegisterEvents(OnPlayerEnteringWorld, 'PLAYER_ENTERING_WORLD')

-- Registrar evento de actualización del log de quests
addon.package:RegisterEvents(OnQuestLogUpdate, 'QUEST_LOG_UPDATE')

-- Profile change handler
if addon.core and addon.core.RegisterMessage then
    addon.core.RegisterMessage(addon, "DRAGONUI_PROFILE_CHANGED", function()
        addon.RefreshQuestTracker()
    end)
end
