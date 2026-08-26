-- DragonUI/modules/merchant/Assets.lua — texture + atlas registration for the merchant window reskin.
--
-- DOWNPORT of NewEra/MerchantFrame/Assets.lua. Same art, adapted for DragonUI:
--   * BLPs shipped in Textures/Merchant/ (copied from NewEra)
--   * Registered through DragonUIWorldMapHost.tex (vendored NewEra core libs)
--   * The two SHARED slot sheets (130766 UI-EmptySlot recess, 130841 UI-Quickslot2 ring)
--     already exist in worldmap Assets.lua — do NOT duplicate here.
--   * 3487944 (commonicons) already exists in Textures/CharacterPanel/
--   * 374155 (rock body) already exists in Textures/Common/

local NE = DragonUIWorldMapHost
if not NE or not NE.tex or not NE.tex.RegisterLocal then return end

local M = "Interface\\AddOns\\DragonUI\\Textures\\Merchant\\"
local COMMON = "Interface\\AddOns\\DragonUI\\Textures\\Common\\"

-- ============================================================================
-- 1. fdid -> shipped BLP path  (NE.tex.RegisterLocal)
-- ============================================================================

-- 5222222 — the merchant pack (256x256). Carries the four modern 72x72 spell-icon buttons
-- (SellJunk / Repair / RepairAll / RepairAllGuild) and the 332x61 modern bottom band
-- (UI-Merchant-BotFrame). Extracted from retail build 12.0.5.67451.
NE.tex.RegisterLocal(5222222, M .. "5222222-merchant-pack.blp")

-- 136423 — Interface\MerchantFrame\UI-Merchant-LabelSlots (128x64): the wide label plate behind
-- each row's name/price. Same-FDID-different-art between clients — 3.3.5a's own copy is the
-- classic wooden plate, so we ship retail's and point the row at it.
NE.tex.RegisterLocal(136423, M .. "136423-ui-merchant-labelslots-retail.blp")

-- 130822 — Interface\Buttons\UI-PageButton-Background (32x32), the plate behind the prev/next page
-- arrows. Same-FDID-different-art again: 3.3.5a serves the classic wooden ring.
NE.tex.RegisterLocal(130822, M .. "130822-ui-pagebutton-background-retail.blp")

-- Page-arrow glyphs + hover (all 32x32: Interface\Buttons\UI-SpellbookIcon-* and
-- UI-Common-MouseHilight). Retail draws the NATIVE textures at these paths; 3.3.5a's CASC serves
-- the low-res classic art at the same names, so ship retail's BLPs and retexture in place.
NE.tex.RegisterLocal(130869, M .. "130869-ui-spellbookicon-prevpage-up-retail.blp")
NE.tex.RegisterLocal(130868, M .. "130868-ui-spellbookicon-prevpage-down-retail.blp")
NE.tex.RegisterLocal(130867, M .. "130867-ui-spellbookicon-prevpage-disabled-retail.blp")
NE.tex.RegisterLocal(130866, M .. "130866-ui-spellbookicon-nextpage-up-retail.blp")
NE.tex.RegisterLocal(130865, M .. "130865-ui-spellbookicon-nextpage-down-retail.blp")
NE.tex.RegisterLocal(130864, M .. "130864-ui-spellbookicon-nextpage-disabled-retail.blp")
NE.tex.RegisterLocal(130757, M .. "130757-ui-common-mousehilight-retail.blp")

-- 3487944 — retail's common-buttons-icons sheet, home of `common-icon-undo` (the buyback undo
-- arrow). Already shipped by DragonUI at Textures/CharacterPanel/commonicons.blp — do NOT duplicate.
NE.tex.RegisterLocal(3487944, "Interface\\AddOns\\DragonUI\\Textures\\CharacterPanel\\commonicons.blp")

-- 374155 — rock body fill. Already registered by worldmap Assets.lua, but safe to re-register
-- (same path). Register defensively in case worldmap isn't loaded yet.
NE.tex.RegisterLocal(374155, COMMON .. "374155-uibackground-rock.blp")

-- ============================================================================
-- 2. Atlas-name -> texcoord rect  (NE.tex.RegisterAtlases)
--    Coords transcribed verbatim from ReferenceAddons/NewEra/Generated/AtlasData.lua.
-- ============================================================================

NE.tex.RegisterAtlases({
  -- Sheet 5222222 — the four 72x72 modern button icons + the bottom band.
  ["spellicon-256x256-selljunk"]      = { file=5222222, left=0.001953, right=0.142578, top=0.250000, bottom=0.531250, width=72,  height=72 },
  ["spellicon-256x256-repair"]        = { file=5222222, left=0.146484, right=0.287109, top=0.250000, bottom=0.531250, width=72,  height=72 },
  ["spellicon-256x256-repairall"]     = { file=5222222, left=0.001953, right=0.142578, top=0.539062, bottom=0.820312, width=72,  height=72 },
  ["spellicon-256x256-repairallguild"]= { file=5222222, left=0.146484, right=0.287109, top=0.539062, bottom=0.820312, width=72,  height=72 },
  ["ui-merchant-botframe"]            = { file=5222222, left=0.001953, right=0.650391, top=0.003906, bottom=0.242188, width=332, height=61 },

  -- Sheet 3487944 — the undo arrow drawn inside the buyback slot.
  ["common-icon-undo"]                = { file=3487944, left=0.378418, right=0.503418, top=0.252930, bottom=0.502930, width=25,  height=25 },
})
