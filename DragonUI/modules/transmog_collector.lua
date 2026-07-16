-- =============================================================================
-- Transmog Collector Module
-- Automatically collects transmog appearances when looting new items.
-- Uses C_AppearanceCollection.CollectItemAppearance(guid) (Ascension API).
-- =============================================================================

local addon = select(2, ...)
local L = addon.L

local TransmogCollector = {
    applied = false,
}

if addon.RegisterModule then
    addon:RegisterModule("transmog_collector", TransmogCollector,
        "Transmog Collector",
        "Automatically collect new transmog appearances when looting items.",
        {
            lifecycle = {
                apply   = "ApplyTransmogCollectorSystem",
                restore = "RestoreTransmogCollectorSystem",
                refresh = "RefreshTransmogCollectorSystem",
            },
        })
end

-- =============================================================================
-- MODULE STATE
-- =============================================================================

local function IsModuleEnabled()
    return addon:IsModuleEnabled("transmog_collector")
end

-- =============================================================================
-- SELF-INITIALIZATION
-- =============================================================================

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "DragonUI" then
        if not IsModuleEnabled() then return end

        addon:After(0.5, function()
            if addon.db and addon.db.RegisterCallback then
                addon.db.RegisterCallback(addon, "OnProfileChanged", function()
                    addon.RefreshTransmogCollectorSystem()
                end)
            end
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not IsModuleEnabled() then return end
        addon.ApplyTransmogCollectorSystem()
    end
end)

-- =============================================================================
-- INTERNAL STATE
-- =============================================================================

local eventFrame          -- BAG_UPDATE listener
local scanQueue     = {} -- {bag, slot} entries pending scan
local isScanning    = false
local knownCache    = {} -- { [guid] = true } GUIDs already collected this session
local lastBagScan   = 0  -- timestamp of last ScanBags to throttle rapid BAG_UPDATE

-- =============================================================================
-- BAG SCANNER
-- =============================================================================

--- Check if an item can be transmog-collected (matches Ascension macro filter).
--- Class IDs < 5 cover Weapon, Armor, Container, and Consumable (macro uses < 5).
--- If item info isn't cached yet, still try collection.
local function IsCollectableItem(itemID)
    if not itemID then return false end
    local _, _, classID = GetItemInfo(itemID)
    if not classID then return true end  -- not cached, try anyway
    return classID < 5
end

--- Check if the Ascension collection API is available.
local function IsCollectionAvailable()
    return C_AppearanceCollection
        and type(C_AppearanceCollection.CollectItemAppearance) == "function"
end

local function ScanQueueProcessor()
    if not TransmogCollector.applied then return end
    if #scanQueue == 0 then
        isScanning = false
        return
    end

    local entry = tremove(scanQueue, 1)
    local bag = entry.bag
    local slot = entry.slot
    local guid = GetContainerItemGUID(bag, slot)

    -- Skip if no GUID or already collected this session
    if not guid or knownCache[guid] then
        addon:After(0, ScanQueueProcessor)
        return
    end

    local itemID = GetContainerItemID(bag, slot)
    if IsCollectableItem(itemID) and IsCollectionAvailable() then
        -- Mark BEFORE calling to prevent re-entry; API is server-idempotent
        knownCache[guid] = true
        C_AppearanceCollection.CollectItemAppearance(guid)
    end

    -- Throttle: 0.2s between API calls to avoid freezing during bulk crafts
    addon:After(0.2, ScanQueueProcessor)
end

--- Scan all bag slots for new items and queue them for processing.
--- Uses a cooldown to prevent rapid re-scans during profession crafting.
local function ScanBags()
    if not TransmogCollector.applied then return end
    if isScanning then return end

    -- 1-second cooldown between scans to prevent thrashing during bulk crafts
    local now = GetTime()
    if now - lastBagScan < 1.0 then return end
    lastBagScan = now

    isScanning = true

    for bag = 0, NUM_BAG_SLOTS or 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots then
            for slot = 1, numSlots do
                local itemID = GetContainerItemID(bag, slot)
                if itemID then
                    local guid = GetContainerItemGUID(bag, slot)
                    -- Skip items already collected this session
                    if not knownCache[guid] then
                        tinsert(scanQueue, {bag = bag, slot = slot})
                    end
                end
            end
        end
    end

    if #scanQueue > 0 then
        addon:After(0.1, ScanQueueProcessor)
    else
        isScanning = false
    end
end

-- =============================================================================
-- EVENT HANDLER
-- =============================================================================

local function OnEvent(self, event, ...)
    if not IsModuleEnabled() then return end
    if event == "BAG_UPDATE" then
        -- Delay slightly to let bag settle after loot
        addon:After(0.3, ScanBags)
    end
end

-- =============================================================================
-- LIFECYCLE
-- =============================================================================

function addon.ApplyTransmogCollectorSystem()
    if TransmogCollector.applied then return end
    TransmogCollector.applied = true

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnEvent)
    end
    eventFrame:RegisterEvent("BAG_UPDATE")

    -- Initial scan: process all items in bags
    if IsCollectionAvailable() then
        addon:After(0.5, ScanBags)
    end
end

function addon.RestoreTransmogCollectorSystem()
    TransmogCollector.applied = false

    if eventFrame then
        eventFrame:UnregisterEvent("BAG_UPDATE")
    end

    wipe(scanQueue)
    wipe(knownCache)
    isScanning = false
    lastBagScan = 0
end

function addon.RefreshTransmogCollectorSystem()
    if TransmogCollector.applied then
        addon.RestoreTransmogCollectorSystem()
        addon.ApplyTransmogCollectorSystem()
    elseif IsModuleEnabled() then
        addon.ApplyTransmogCollectorSystem()
    end
end
