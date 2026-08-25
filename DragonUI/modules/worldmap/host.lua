-- DragonUI/modules/worldmap/host.lua — compatibility shim for the NewEra worldmap port.
--
-- Builds the `DragonUIWorldMapHost` global (= the `NE` surface that ported files expect)
-- and wires it to DragonUI equivalents. Each vendored lib in lib/ self-assigns its
-- sub-table onto this global when loaded (e.g. lib/Texture.lua sets DragonUIWorldMapHost.tex).
--
-- Load order in worldmap.xml: this file FIRST, then lib/*.lua, then the module files.

local addon = select(2, ...)
if not addon then return end

-- ============================================================================
-- 1. THE HOST TABLE — every ported file's `local NE = DragonUIWorldMapHost` resolves here.
-- ============================================================================

_G.DragonUIWorldMapHost = _G.DragonUIWorldMapHost or {}
local NE = _G.DragonUIWorldMapHost

-- ============================================================================
-- 2. BASIC SURFACE — what most files check before doing anything.
-- ============================================================================

NE.disabled = false
NE.IsAddOnLoaded = IsAddOnLoaded  -- global on 3.3.5a

-- L is set lazily on first access so the locales have time to load.
-- At file load (modules/worldmap/*.lua runs during DragonUI.xml include), addon.L already
-- exists (Locales/Load_Locales.xml is first in the TOC). But defensive: fallback to {}.
setmetatable(NE, {
	__index = function(_, key)
		if key == "L" then return addon.L or {} end
		return nil
	end,
})

-- ============================================================================
-- 3. DATABASE — NE.db.worldmap backed by DragonUI's AceDB profile.
--
-- Ported files read/write NE.db.worldmap.* (canvasW, fog, overlays, maximized,
-- wheelZoom, poiFilters) and NE.db.windowPos.* / NE.db.lastRes for position.
-- We proxy into addon.db.profile so DragonUI's profile system owns the data.
-- ============================================================================

local function getModules()
	return addon.db and addon.db.profile and addon.db.profile.modules
end

local function getWM()
	local m = getModules()
	if m and m.worldmap then return m.worldmap end
	return nil
end

-- Public db proxy table — NE.db.worldmap, NE.db.windowPos, NE.db.lastRes read/write
-- through this metatable into DragonUI's profile.
NE.db = {}
setmetatable(NE.db, {
	__index = function(_, key)
		if key == "worldmap" then
			return getWM()
		end
		-- windowPos and lastRes live at profile root (shared across modules)
		if key == "windowPos" then
			local db = addon.db and addon.db.profile
			if db then
				db.windowPos = db.windowPos or {}
				return db.windowPos
			end
			return nil
		end
		if key == "lastRes" then
			return addon.db and addon.db.profile and addon.db.profile.lastRes
		end
		return nil
	end,
	__newindex = function(_, key, value)
		if key == "worldmap" then
			-- NE.db.worldmap = {}; ensure the subtable exists
			local m = getModules()
			if m then m.worldmap = value end
		elseif key == "windowPos" then
			local db = addon.db and addon.db.profile
			if db then db.windowPos = value end
		elseif key == "lastRes" then
			local db = addon.db and addon.db.profile
			if db then db.lastRes = value end
		end
	end,
})

-- ============================================================================
-- 4. WORLDMAP NAMESPACE — the module populates this itself via `NE.worldmap = {}`.
--    Initialize it now so the first file (Assets.lua) can write into it.
-- ============================================================================

NE.worldmap = NE.worldmap or {}

-- ============================================================================
-- 5. LOGGING — NE.Log is guarded; a thin wrapper over addon:Debug.
-- ============================================================================

function NE.Log(tag, ...)
	if addon.Debug then
		addon:Debug("[WM:" .. tostring(tag) .. "]", ...)
	end
end

-- ============================================================================
-- 6. MODULE REGISTRATION — maps to DragonUI's ModuleRegistry.
-- ============================================================================

NE.modules = NE.modules or {}
NE.modules.Register = function(opts)
	if not opts or not opts.name then return end
	-- Record rivals for conflict checking
	if opts.conflictsWith then
		NE.modules._rivals = NE.modules._rivals or {}
		for _, name in ipairs(opts.conflictsWith) do
			NE.modules._rivals[name:lower()] = true
		end
	end
end

NE.modules.IsBooted = function(name) return true end

NE.modules.RIVALS = NE.modules.RIVALS or {}
NE.modules.RIVALS.WORLDMAP = {
	"Mapster", "Carbonite", "Leatrix_Maps", "MetaMap", "Cartographer", "Cartographer3",
}

-- ============================================================================
-- 7. PANEL CHROME — minimal stub for the constant the map body uses.
-- ============================================================================

NE.panelchrome = NE.panelchrome or {
	BODY_TINT = 1.0,    -- full brightness (retail standard for self-painted bodies)
}

-- ============================================================================
-- 8. PANEL MANAGER — stubs for guarded calls.
--    Without these the window doesn't join a shared row, but all guarded calls
--    (Register, Promote, Reflow) safely no-op.
-- ============================================================================

NE.panelmgr = NE.panelmgr or {}
function NE.panelmgr.Register() end
function NE.panelmgr.Promote() end
function NE.panelmgr.Reflow() end
function NE.panelmgr.NoteDragStart() end
function NE.panelmgr.MarkUserPlaced() end
function NE.panelmgr.ClearUserPlaced() end
NE.panelmgr.DragMoved = function(f)
	if not f or not f.GetLeft then return false end
	local x = f:GetLeft() or 0
	local y = f:GetTop() or 0
	-- 2-pixel dead zone (same as FrameUtil threshold)
	local db = addon.db and addon.db.profile and addon.db.profile.modules
	return (x > 2 or x < -2 or y > 2 or y < -2)
end

-- ============================================================================
-- 9. SCROLLBAR — BuildCustomPixel is guarded by pcall in the module.
--    A simple implementation that skins the scroll thumb track.
-- ============================================================================

NE.scrollbar = NE.scrollbar or {}
function NE.scrollbar.BuildCustomPixel(scrollFrame, opts)
	if not scrollFrame then return end
	local ok, bar = pcall(function() return scrollFrame:GetScrollBar() end)
	local bg = ok and bar
	if not bg then return end
	local offset = opts and opts.x or -4
	if bg.SetBackdropColor then
		bg:SetBackdropColor(0, 0, 0, 0.3)
	end
end

-- ============================================================================
-- 10. QA HARNESS — stub. NE.qa.modules is populated if present; nil is fine.
-- ============================================================================

NE.qa = NE.qa or {}

-- ============================================================================
-- 11. MONEY TEXT — used in QuestLogDetail.lua (unguarded). Simple copper→text.
-- ============================================================================

-- Note: FrameUtil.lua (vendored) sets NE.money.Text. This is a fallback only.
if not NE.money then
	NE.money = {}
	function NE.money.Text(copper, empty)
		if not copper or copper == 0 then return empty or "" end
		local g = math.floor(copper / 10000)
		local s = math.floor((copper % 10000) / 100)
		local c = copper % 100
		if g > 0 then
			return ("%d|cffffd100g|r %d|cffc0c0c0s|r %d|cffb87333c|r"):format(g, s, c)
		elseif s > 0 then
			return ("%d|cffc0c0c0s|r %d|cffb87333c|r"):format(s, c)
		else
			return ("%d|cffb87333c|r"):format(c)
		end
	end
end

-- ============================================================================
-- 12. NINESLICE — the real implementation is vendored at lib/NineSlice.lua +
--     lib/NineSliceLayouts.lua (loaded right after lib/Texture.lua in
--     worldmap.xml). Nothing to stub here; the table is created by the lib.
-- ============================================================================

-- ============================================================================
-- 13. PORTRAIT — real implementation vendored at lib/Portrait.lua.
-- ============================================================================

-- ============================================================================
-- 14. MENU — used in QuestLogPanel.lua:810 for cog dropdown. Provides the
--     NewEra menu interface built on EasyMenu/UIDropDownMenu.
-- ============================================================================

NE.menu = NE.menu or {}
function NE.menu.Open(menuTable, anchor, xOffset, yOffset)
	if not menuTable or #menuTable == 0 then return end
	-- Build a simple EasyMenu-compatible table and show it
	local f = _G.WorldMapFrame
	if not f then return end
	EasyMenu(menuTable, _G.UIDropDownMenu_Create("WorldMapCogMenu"),
		anchor or f, xOffset or 0, yOffset or 0, "MENU")
end

-- ============================================================================
-- 15. DIFFICULTY TIER — returns a color string for content difficulty.
--     3.3.5a has GetDungeonDifficultyID / GetRaidDifficultyID.
-- ============================================================================

if not NE.difficultyTier then
	NE.difficultyTier = function(difficultyID)
		-- 1=normal 5, 2=heroic 5, 3=10normal, 4=25normal, 5=10heroic, 6=25heroic
		local colors = {
			[1] = "|cff808080", -- normal (grey)
			[2] = "|cffff0000", -- heroic (red)
			[3] = "|cffffff00", -- 10N (yellow)
			[4] = "|cffff0000", -- 25N (red)
			[5] = "|cffff8000", -- 10H (orange)
			[6] = "|cffff0000", -- 25H (red)
		}
		return colors[difficultyID] or "|cffffffff"
	end
end
