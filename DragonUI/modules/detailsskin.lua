-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.
--
-- ============================================================================
-- DETAILS! DAMAGE METER SKIN — the "DragonUI" theme
-- ============================================================================
--
-- Ported from _ref-/DragonUI_NewEra-main/modules/detailsskin/ (itself the 3.3.5a
-- backport of NewEra's Classic DetailsSkin, targeting Details! v8.3.0 build
-- 7269). Same art, geometry and typography; the hosting layer moves onto
-- DragonUI's ModuleRegistry:
--   * the "player chose this skin" flag lives in db.profile.modules.detailsskin
--     (AceDB profile) instead of a raw SavedVariables global,
--   * C_Timer.After -> addon:After, NE.IsAddOnLoaded -> IsAddOnLoaded,
--   * skin renamed "New Era" -> "DragonUI" so it reads right in Details!' own
--     dropdown; LSM media names re-prefixed to match.
-- NewEra-only baggage dropped: undoOurWindowScale (their first build wrote
-- PixelBaseScale into window_scale; DragonUI never did).
--
-- WHAT v8.3.0 DOES NOT HAVE (verified against its classe_instancia_include.lua):
-- titlebar_shown/_height/_texture/_texture_color are ABSENT, so the retail
-- header is rebuilt through the skin `callback` seam (DS.DecorateWindow below);
-- row_offsets / text_yoffset / icon_size_offset / menu_icons_alpha / no_cache
-- are ABSENT; attribute_text.show_timer is a THREE-BOOLEAN table here.
-- WHAT A SKIN MAY NOT SET (Details' instance_skin_ignored_values): menu_icons,
-- bars_grow_direction, bars_sort_direction, strata, window_scale, total_bar,
-- menu_alpha, auto_hide_menu, grab_on_top, hide_in_combat* — none are written.
--
-- ART (Textures\DetailsSkin\): sliced from retail's Blizzard_DamageMeter sheets
-- and repacked power-of-two — 3.3.5a renders a BLP it cannot sample as SOLID
-- BRIGHT GREEN. They are only ever STRETCHED to a frame, so the resample costs
-- nothing visually. Registered with LibSharedMedia as "statusbar" entries before
-- the skin table references them by name.
--
-- THE HEADER replaces Details' own four title-bar slices (ball/emenda/ball_r/
-- top_bg); their shown state is saved per window and handed back when the player
-- picks another skin (see hookChangeSkin). The toolbar icons, close button and
-- title text are separate frames and are left alone.
--
-- TIMING MATTERS: "Details" sorts before "DragonUI", so its skins table exists
-- when this file runs and the first Install() lands before Details' Start()
-- reads window skins at PLAYER_LOGIN. Registering late lets Details overwrite a
-- saved "DragonUI" skin name with the default AND WRITE IT BACK over the
-- player's choice. One expected cosmetic leftover: on the very first login after
-- applying the skin, Details may print its own "Skin DragonUI not found" line
-- while restoring a window saved before this module existed; every later session
-- finds the name, and the restore pass fixes the outcome.
--
-- DISABLE SEMANTICS: there is no way to un-apply a theme from Details' data
-- cleanly mid-session, so turning the module off hands every window back to
-- Details' own chrome, unhooks ChangeSkin, drops the skin from Details!' picker
-- and clears the recorded choice. Windows left WEARING the skin keep working
-- for the session; on a later reload Details replaces the now-unknown name with
-- its default (its own diagnostic line prints once) — that is Details forgetting
-- the name we removed, not a fault.

local addon = select(2, ...)
local L = addon.L

local DetailsSkinModule = {
	initialized = false,
	applied = false,
}

if addon.RegisterModule then
	addon:RegisterModule("detailsskin", DetailsSkinModule,
		L["Damage Meter Skin"],
		L["A retail-styled theme for the Details! Damage Meter: gold-titled header bar, class-coloured bars and abbreviated numbers."],
		{ lifecyclePrefix = "DetailsSkin" })
end

local DS = {}
addon.DetailsSkin = DS

local SKIN_NAME = "DragonUI"

local ART     = (addon._dir or [[Interface\AddOns\DragonUI\Textures\]]) .. [[DetailsSkin\]]
local HEADER  = ART .. "7499559-dm-header"
local PANEL   = ART .. "7499559-dm-panel-bg"
local BAR     = ART .. "6704514-dm-bar-fill"
local BAR_BG  = ART .. "7499559-dm-bar-shadowbg"

local MEDIA_HEADER = "DragonUI Meter Header"
local MEDIA_PANEL  = "DragonUI Meter Panel"
local MEDIA_BAR    = "DragonUI Meter Bar"
local MEDIA_BAR_BG = "DragonUI Meter Bar BG"

-- The header band sits directly ABOVE the bars frame: every piece of v8.3.0's own
-- title bar anchors its BOTTOM to baseframe's TOP, and the interactive toolbar
-- strip behind spans ~22px. 24 covers it with a pixel to spare.
local HEADER_H = 24

-- The art is NOT a plain band: over its 32 rows the painted bar occupies rows
-- 1..26 and rows 27..31 are the soft shadow under it, so once stretched the
-- bar's centre sits ~1.5px above the band centre — anything centred on
-- HEADER_H/2 reads low. Everything hangs off BAR_CENTRE_Y instead.
-- CONTENT_NUDGE_Y drops the contents 3.5px below that midpoint (measured in
-- game); change it to move the whole title bar contents together.
local ART_ROWS, ART_BAR_TOP, ART_BAR_END = 32, 1, 27          -- ART_BAR_END is exclusive
local BAR_CENTRE_Y = HEADER_H * (ART_BAR_TOP + ART_BAR_END) / 2 / ART_ROWS
local CONTENT_NUDGE_Y = 3.5
BAR_CENTRE_Y = BAR_CENTRE_Y + CONTENT_NUDGE_Y                 -- 14 at HEADER_H = 24

-- The bar's ends fade out over ~14 of its 256 columns (retail's own authoring),
-- so the painted band stops short of wherever it is stretched to. Hanging the
-- texture this far over each edge puts the ramp outside the frame, and the band
-- reads as reaching it.
local HEADER_OVERHANG = 4

-- Contents of the bar hang off the ROW geometry rather than the window: a row
-- spans [left + space.left, right], so its class icon starts at left+4 and the
-- title has to start there too or the two read as misaligned.
local ROW_INSET_X    = 4                     -- row_info.space.left, below
local BALL_INNER_X   = 21                    -- ball's bottom-right lands: left + 128 - 107
local BALL_R_INNER_X = 32                    -- ball_r's bottom-left lands: right - 32
local ICON_SIZE      = 16                    -- one toolbar button at menu_icons_size = 1.0
local TITLE_SIZE     = 13
local floor = math.floor

-- Details is `_detalhes` internally and `Details` as of boot.lua. v8.3.0 has no
-- IsLoaded(); test for the two things actually used: the installer, and the
-- table it writes into.
local function details()
	local D = _G._detalhes or _G.Details
	if D and type(D.InstallSkin) == "function" and type(D.skins) == "table" then return D end
	return nil
end

function DS.IsDetailsLoaded()
	return IsAddOnLoaded("Details") and details() ~= nil
end

-- ============================================================================
-- "THE PLAYER CHOSE THIS SKIN", in our own profile (db.profile.modules.detailsskin).
--
-- Details cannot be relied on to remember it. Its own record is per-window
-- `skin`, and two things happen to that on a reload: a name it cannot find when
-- restoring a window is replaced by the default AND WRITTEN BACK, and when the
-- name IS found it takes the just_updating path that re-applies nothing. Either
-- way the theme does not come back on its own. So the choice is recorded here,
-- and DS.Restore re-asserts it after Details has built its windows. It is set
-- when the skin is applied (from the options button, /duidetails, or by picking
-- it in Details' own dropdown — the ChangeSkin hook sees both) and cleared the
-- moment they pick a different skin, so it follows their intent.
-- ============================================================================

local function GetConfig()
	if not addon.GetModuleConfig then return nil end
	local cfg = addon:GetModuleConfig("detailsskin")
	if type(cfg) ~= "table" then return nil end
	return cfg
end

local function SetChosen(v)
	local cfg = GetConfig()
	if cfg then cfg.chosen = v and true or nil end
end

local function IsChosen()
	local cfg = GetConfig()
	return (cfg and cfg.chosen) == true
end

-- LSM registration: Details drives bar/backdrop textures by MEDIA NAME (a
-- registered "statusbar"), and the names must exist before the skin table
-- references them. LibSharedMedia is not ours — it comes in with Details, which
-- fetches it unguarded, hence the lazy lookup rather than an embedded copy.
local function registerMedia()
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if not (LSM and LSM.Register) then return false end
	pcall(LSM.Register, LSM, "statusbar", MEDIA_HEADER, HEADER .. ".blp")
	pcall(LSM.Register, LSM, "statusbar", MEDIA_PANEL,  PANEL  .. ".blp")
	pcall(LSM.Register, LSM, "statusbar", MEDIA_BAR,    BAR    .. ".blp")
	pcall(LSM.Register, LSM, "statusbar", MEDIA_BAR_BG, BAR_BG .. ".blp")
	return true
end

-- ============================================================================
-- THE HEADER — what titlebar_* would have done.
--
-- v8.3.0 builds its title bar out of four texcoord slices of the skin `file`,
-- and they DO NOT stop at the window's edges (ball 128 wide hangs 107px past the
-- left edge, ball_r 128 wide 96px past the right). Retail's header is exactly
-- the window's width, which is why ours REPLACES those four instead of covering
-- them; their previous shown state is saved per instance so the ChangeSkin hook
-- can hand them back when the player picks another skin.
-- ============================================================================
local HEADER_PIECES = { "ball", "emenda", "ball_r", "top_bg" }

-- Hide Details' own title-bar art (remembering what was shown), or put it back
-- exactly as it was.
local function detailsHeaderShown(inst, shown)
	local cab = inst and inst.baseframe and inst.baseframe.cabecalho
	if not cab then return end
	local saved = inst._duiSavedHeader
	if shown then
		if not saved then return end            -- we never hid it; nothing of ours to undo
		for _, key in ipairs(HEADER_PIECES) do
			local piece = cab[key]
			if piece and saved[key] ~= nil then
				if saved[key] then piece:Show() else piece:Hide() end
			end
		end
		inst._duiSavedHeader = nil
	else
		if saved then return end                -- already ours; don't overwrite the saved state
		saved = {}
		for _, key in ipairs(HEADER_PIECES) do
			local piece = cab[key]
			if piece then
				saved[key] = (piece.IsShown and piece:IsShown()) and true or false
				piece:Hide()
			end
		end
		inst._duiSavedHeader = saved
	end
end

function DS.DecorateWindow(inst)
	local base = inst and inst.baseframe
	if not (base and base.CreateTexture) then return end
	local hdr = base._duiMeterHeader
	if not hdr then
		hdr = base:CreateTexture(nil, "OVERLAY")
		base._duiMeterHeader = hdr
	end
	hdr:SetTexture(HEADER .. ".blp")
	hdr:ClearAllPoints()
	hdr:SetPoint("BOTTOMLEFT",  base, "TOPLEFT",  -HEADER_OVERHANG, 0)
	hdr:SetPoint("BOTTOMRIGHT", base, "TOPRIGHT",  HEADER_OVERHANG, 0)
	hdr:SetHeight(HEADER_H)
	hdr:Show()
	detailsHeaderShown(inst, false)
end

-- Our header belongs to our skin only. The skin callback fires when a window
-- ENTERS a skin, never when it leaves, so switching to someone else's skin would
-- otherwise leave our band sitting on it. ChangeSkin is plain insecure addon
-- code, so replacing it with a wrapper is enough; it touches nothing but our own
-- texture, and instances inherit it through `_detalhes.__index`.
local function hookChangeSkin(D)
	if DS._ourChangeSkin or type(D.ChangeSkin) ~= "function" then return end
	local orig = D.ChangeSkin
	DS._origChangeSkin = orig
	DS._ourChangeSkin = function(self, skinName, ...)
		local asked = skinName or (type(self) == "table" and self.skin) or nil
		local installed = (D.skins and D.skins[SKIN_NAME] ~= nil) and true or false
		local a, b, c = orig(self, skinName, ...)
		if type(self) ~= "table" then return a, b, c end

		local wearingOurs = (self.skin == SKIN_NAME)
		local base = self.baseframe
		local hdr = base and base._duiMeterHeader
		if hdr and not wearingOurs then hdr:Hide() end
		if not wearingOurs then detailsHeaderShown(self, true) end   -- give Details its title bar back

		-- Remember the player's choice so a reload can put it back (see DS.Restore).
		-- Only trust this when our skin was actually installed at the time: the
		-- "skin not found" path also comes through here asking for OUR name and
		-- landing on the default, and that is Details forgetting rather than the
		-- player choosing.
		if installed then
			if wearingOurs then
				SetChosen(true)
			elseif asked ~= SKIN_NAME then
				SetChosen(false)
			end
		end
		return a, b, c
	end
	D.ChangeSkin = DS._ourChangeSkin
end

local function unhookChangeSkin(D)
	if not DS._ourChangeSkin then return end
	if D and D.ChangeSkin == DS._ourChangeSkin then
		D.ChangeSkin = DS._origChangeSkin
	end
	DS._ourChangeSkin, DS._origChangeSkin = nil, nil
end

-- ============================================================================
-- THE SKIN TABLE. Only keys this Details version reads, and none it refuses
-- from a skin.
-- ============================================================================
local function skinTable()
	return {
		-- Details' own chrome-less sheet: the window frame art we are NOT using
		-- (the retail meter has no frame). Our header is drawn over the flat
		-- band it leaves behind.
		file    = [[Interface\AddOns\Details\images\skins\flat_skin.blp]],
		author  = "DragonUI",
		version = "1.0",
		site    = "https://github.com/NeticSoul/DragonUI",
		desc    = "DragonUI — retail damage-meter look, with art from retail's Blizzard_DamageMeter. "
		       .. "Skin-key structure adapted from Details_TWW (MIT, Karl-Heinz Schneider).",

		micro_frames = { color = { 1, 1, 1, 1 }, font = "Arial Narrow", size = 10, textymod = 1 },
		can_change_alpha_head = true,
		icon_anchor_main    = { -1, -5 },
		icon_anchor_plugins = { -7, -13 },
		icon_plugins_size   = { 19, 18 },
		icon_point_anchor        = { -37, 0 },
		left_corner_anchor       = { -107, 0 },
		right_corner_anchor      = { 96, 0 },
		icon_point_anchor_bottom  = { -37, 12 },
		left_corner_anchor_bottom = { -107, 0 },
		right_corner_anchor_bottom = { 96, 0 },
		icon_on_top      = true,
		icon_ignore_alpha = true,
		icon_titletext_position = { 3, 3 },

		instance_cprops = {
			-- ── OPACITY: retail reads as floating bars — panel ~invisible, no
			--    bottom status bar. ──
			color = { 0.094, 0.094, 0.094, 0 },
			bg_r = 0.094, bg_g = 0.094, bg_b = 0.094, bg_alpha = 0,
			backdrop_texture = MEDIA_PANEL,
			show_statusbar = false,
			statusbar_info = { alpha = 0, overlay = { 0.094, 0.094, 0.094 } },
			show_sidebars = false,
			wallpaper = { enabled = false },
			hide_icon = true,          -- retail has no instance icon at the window's top-left
			-- NOT SET, and deliberately: strata / bars_grow_direction / menu_icons
			-- are on Details' instance_skin_ignored_values, so a skin writing them
			-- changes nothing.

			-- ── TOOLBAR + TITLE: v8.3.0 geometry (its own flat skin's numbers). ──
			toolbar_side = 1,
			-- The icon row anchors TOPLEFT to ball_r's BOTTOMLEFT with (x, y + 16),
			-- so it occupies top+y .. top+y+16, and with side = 2 the first
			-- (rightmost) button lands there and the rest chain leftwards. y
			-- centres the 16px row on the BAR (see BAR_CENTRE_Y) — centring it on
			-- the band instead is what left the icons sitting low. ball_r's
			-- bottom-left is at right - 32 and the rightmost button is 16 wide, so
			-- x below leaves the same 4px margin the title has on the left.
			menu_anchor = { BALL_R_INNER_X - ICON_SIZE - ROW_INSET_X, floor(BAR_CENTRE_Y - ICON_SIZE / 2),
			                side = 2 },
			-- Plugin icons chain off the menu row. Details' default grow direction
			-- 2 = rightwards walks them straight off the window: its own skins have
			-- 96px of ball_r art out there to sit on, ours stops at the edge.
			-- 1 = leftwards keeps them on it.
			plugins_grow_direction = 1,
			instance_button_anchor = { -27, 1 },
			menu_icons_size = 1.0,
			desaturated_menu = false,
			color_buttons = { 1, 1, 1, 1 },
			-- Gold title text, anchored bottom-left of the header band. The anchor
			-- is measured off the left ball's bottom-right corner, which lands ~3px
			-- inside baseframe's left edge; x puts the text's left edge exactly on
			-- the row's (i.e. on the class icon's), y centres it on the bar art.
			attribute_text = {
				enabled = true, side = 1, shadow = true,
				show_timer = { true, true, true },   -- raid encounter / battleground / arena
				text_size = TITLE_SIZE, text_face = "Friz Quadrata TT",
				text_color = { 1, 0.82, 0, 1 },
				custom_text = "{name}", enable_custom_text = false,
				anchor = { ROW_INSET_X - BALL_INNER_X, floor(BAR_CENTRE_Y - TITLE_SIZE / 2) },
			},

			row_info = {
				texture      = MEDIA_BAR,
				texture_file = BAR .. ".blp",
				texture_class_colors = true,            -- class-vertex-coloured, like retail
				texture_background      = MEDIA_BAR_BG,
				texture_background_file = BAR_BG .. ".blp",
				texture_background_class_color = false,
				fixed_texture_color = { 0, 0, 0 },
				fixed_texture_background_color = { 1, 1, 1, 1 },   -- show the shadow art as authored
				texture_highlight = "Interface\\FriendsFrame\\UI-FriendsList-Highlight",
				-- Retail row is ~25px; the source's transparent inset has no key
				-- here, so the gap under the header and at the margins comes out
				-- of `space` instead.
				height = 25,
				space = { left = ROW_INSET_X, right = -4, between = 4 },
				alpha = 1,
				-- Icons: Details' class discs on the left, the retail-ish arrangement.
				no_icon = false,
				icon_file = "Interface\\AddOns\\Details\\images\\classes_small",
				icon_offset = { 0, 0 },
				start_after_icon = true,
				-- Spec icons OFF: this client has no specialisations for Details to
				-- read, so the spec sheet has nothing to select and class icons are
				-- the honest answer.
				use_spec_icons = false,
				-- Text: ARIALN 14 outlined white; "1. Name" left, retail-style
				-- "value (per second)" right.
				font_face = "Arial Narrow",
				font_face_file = "Fonts\\ARIALN.TTF",
				font_size = 14,
				textL_show_number = true,
				textL_outline = true,
				textL_class_colors = false,
				textL_enable_custom_text = false,
				textR_outline = true,
				textR_class_colors = false,
				textR_enable_custom_text = true,
				textR_custom_text = "{data1} ({data2})",
				textR_separator = ",",
				percent_type = 1,
			},
		},

		-- Runs when a window enters this skin. Details calls it through setfenv
		-- with a filtered environment, so it does nothing itself but hand the
		-- window to us.
		callback = function(skin, instance, just_updating)
			local dui = _G.DragonUI
			if dui and dui.DetailsSkin and dui.DetailsSkin.DecorateWindow then
				dui.DetailsSkin.DecorateWindow(instance)
			end
		end,
	}
end

-- Install (or re-install) the skin. v8.3.0's InstallSkin refuses a name that
-- already exists and has no `no_cache`, so `force` clears the slot first — that
-- is how an edited table takes effect without a full client restart, and it is
-- immediately followed by the install so nothing sees an empty slot.
function DS.Install(force)
	local D = details()
	if not D then return false end
	registerMedia()
	hookChangeSkin(D)
	if D.skins[SKIN_NAME] and not force then return true end
	if force then D.skins[SKIN_NAME] = nil end
	local ok, installed = pcall(D.InstallSkin, D, SKIN_NAME, skinTable())
	return (ok and installed) and true or false
end

-- Full push: install, switch every window to the skin, and write the profile
-- variables a skin cannot express. NEVER called automatically — a Details!
-- profile is the player's own data, and this overwrites part of it. Re-run it
-- after they customise something in Details! and want the theme back.
-- Returns true if at least one window was switched.
function DS.Apply()
	local D = details()
	if not D then return false end
	DS.Install(true)
	SetChosen(true)   -- so a reload can put it back (Details will not; see DS.Restore)

	-- Retail's K/M abbreviation. Value 2 is the "305.500 -> 305.5K" formatter,
	-- and v8.3.0 caches the chosen formatter per attribute, so the change does
	-- not show until UpdateToKFunctions re-selects it.
	D.ps_abbreviation, D.total_abbreviation = 2, 2
	if type(D.UpdateToKFunctions) == "function" then pcall(D.UpdateToKFunctions, D) end

	local applied = 0
	for i = 1, ((type(D.GetNumInstancesAmount) == "function" and D:GetNumInstancesAmount()) or 0) do
		local inst = D.GetInstance and D:GetInstance(i)
		if inst and inst.ChangeSkin then
			pcall(inst.ChangeSkin, inst, SKIN_NAME)
			-- ChangeSkin skips the skin callback when the window is ALREADY on
			-- this skin, so the header is (re)built from here too — otherwise a
			-- second Apply, or Apply on a window already wearing the skin, gets
			-- no header at all.
			DS.DecorateWindow(inst)
			applied = applied + 1
		end
	end
	return applied > 0
end

-- Put the theme back after a reload, once Details has built its windows.
--
-- Two cases, and the difference matters: a window that still NAMES our skin only
-- needs its header (Details' restore takes the just_updating path and runs no
-- callback, so nothing of ours is drawn), while a window whose name Details
-- replaced with the default has to be switched back — and only if the player's
-- recorded choice says so. A window on someone else's skin, chosen by them, is
-- never touched.
--
-- Idempotent: safe to call repeatedly, which is what the staggered login passes
-- at the bottom do.
function DS.Restore()
	local D = details()
	if not D then return false end
	DS.Install(false)
	local chosen = IsChosen()
	local restored = 0
	for i = 1, ((type(D.GetNumInstancesAmount) == "function" and D:GetNumInstancesAmount()) or 0) do
		local inst = D.GetInstance and D:GetInstance(i)
		if inst and inst.baseframe then
			if inst.skin == SKIN_NAME then
				DS.DecorateWindow(inst)
				restored = restored + 1
			elseif chosen and inst.ChangeSkin then
				pcall(inst.ChangeSkin, inst, SKIN_NAME)
				DS.DecorateWindow(inst)
				restored = restored + 1
			end
		end
	end
	return restored > 0
end

-- Module-disable path: hand every window back to Details' own chrome, forget the
-- recorded choice and drop the skin from Details!' picker. See DISABLE SEMANTICS
-- in the file header for what happens to windows that were wearing it.
function DS.Uninstall()
	SetChosen(false)
	local D = details()
	unhookChangeSkin(D)
	if not D then return end
	for i = 1, ((type(D.GetNumInstancesAmount) == "function" and D:GetNumInstancesAmount()) or 0) do
		local inst = D.GetInstance and D:GetInstance(i)
		if inst and inst.baseframe then
			local hdr = inst.baseframe._duiMeterHeader
			if hdr then hdr:Hide() end
			detailsHeaderShown(inst, true)
		end
	end
	D.skins[SKIN_NAME] = nil
end

-- ============================================================================
-- LIFECYCLE (ModuleRegistry resolves these via lifecyclePrefix "DetailsSkin")
-- ============================================================================

-- Enable path: register the skin and put any previously chosen decoration back.
-- Registering only LISTS the skin in Details!' own dropdown; nothing about the
-- meter changes until the player asks for it (button/slash) or had already done
-- so (chosen flag).
local function ApplyDetailsSkin()
	if not DS.IsDetailsLoaded() then return end
	DS.Install(false)
	DetailsSkinModule.initialized = true
	DS.Restore()
	DetailsSkinModule.applied = true
end

-- Disable path: give Details its chrome back and forget the choice.
local function RestoreDetailsSkin()
	DetailsSkinModule.applied = false
	DS.Uninstall()
end

local function RefreshDetailsSkin()
	if DetailsSkinModule.applied then
		RestoreDetailsSkin()
	end
	if addon:IsModuleEnabled("detailsskin") then
		ApplyDetailsSkin()
	end
end

addon.ApplyDetailsSkinSystem = ApplyDetailsSkin
addon.RestoreDetailsSkinSystem = RestoreDetailsSkin
addon.RefreshDetailsSkinSystem = RefreshDetailsSkin

-- ============================================================================
-- SLASH COMMAND — same action as the options button, reachable without opening
-- the panel.
-- ============================================================================

SLASH_DUIDETAILS1 = "/duidetails"
SlashCmdList["DUIDETAILS"] = function()
	if not DS.IsDetailsLoaded() then
		addon:Print("|cff1784d1DragonUI|r: " .. L["Details! is not installed."])
		return
	end
	if DS.Apply() then
		addon:Print("|cff1784d1DragonUI|r: " .. L["Details! skin applied."])
	else
		addon:Print("|cff1784d1DragonUI|r: " .. L["Could not apply the skin - Details! is not ready yet."])
	end
end

-- ============================================================================
-- BOOT — install EARLY (see TIMING MATTERS), then restore once Details has its
-- windows up.
--
-- RESTORE AFTER is the other half of surviving a reload: when Details DOES find
-- our skin name on a window, ChangeSkin takes its just_updating path and
-- re-applies nothing at all — no cprops, and no skin callback — so our header
-- never gets drawn. Nothing about that is observable from the skin table, so the
-- module re-asserts it itself.
--
-- The passes are staggered because Details builds its windows in Details:Start()
-- on ITS PLAYER_LOGIN handler, registered when Details loaded — i.e. normally
-- already done by the time we run. The later passes cover the cases where it is
-- not (a slow load, or its own deferred startup work). Both passes respect the
-- module toggle: disabled means uninstall, not restore.
-- ============================================================================
pcall(DS.Install)

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name ~= "Details" then return end
	DS.Install(false)
	if event ~= "PLAYER_LOGIN" then return end
	local function pass()
		if addon:IsModuleEnabled("detailsskin") then
			DS.Restore()
		else
			DS.Uninstall()
		end
	end
	pass()
	addon:After(1, pass)
	addon:After(5, pass)   -- last word, after Details' own deferred startup work
end)
