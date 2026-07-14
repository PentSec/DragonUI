# Tasks: Combuctor Monolith Refactor

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~6,955 (3,460 added + 3,475 deleted + 20 mod props) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1: Task 1 (mod promotions, ~70 lines) → PR 2: Tasks 2-8 (all extraction, ~6,900 verbatim) |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

**Why six PRs are not needed**: ~99% of the diff is verbatim cut-and-paste within `DragonUI/modules/combuctor/`. The one behavioral change is Task 1 (mod promotions — 15 local→mod.X renames). Task 2 (MoneyFrame dedup) is a confirmed dead-code deletion. The extraction tasks (3-7) are mechanical moves per the spec's exact line ranges, verifiable by line count. Stack PR 1 (the actual code change) separately, then PR 2 (all extraction in one pass).

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | Promote 15 shared locals to mod.X + dedup MoneyFrame | PR 1 | `git diff --stat` + verify no undefined `mod.X` in downstream | Load addon in WoW, check `/cbt` opens bags | Revert combuctor.lua changes |
| 2 | Extract all 5 files + update modules.xml | PR 2 | `wc -l` per file matches spec + verify 0 behavior change via S5.1–S5.12 | Full scenario test S5.1–S5.12 in WoW client | Revert new files + modules.xml, restore monolith |

## Phase 1: Foundation (mod promotion + dedup)

- [x] 1.1 **Promote 17 shared locals to `mod.X` in combuctor.lua** — Add `mod.L = L`, `mod.CT = CT`, `mod.DB = DB`, `mod.playerName = playerName`, `mod.ItemSearch = ItemSearch`, `mod.GetModuleConfig = GetModuleConfig`, `mod.IsModuleEnabled = IsModuleEnabled`, `mod.SetupDatabase = SetupDatabase`, `mod.defaults = defaults`, `mod.CombuctorModule = CombuctorModule`, `mod.CombuctorAddNineSlice = CombuctorAddNineSlice`, `mod.CombuctorRetailItemSlot = CombuctorRetailItemSlot`, `mod.CombuctorRetailBagSlot = CombuctorRetailBagSlot`, `mod.CombuctorRetailBackpackButton = CombuctorRetailBackpackButton`, `mod.CombuctorSkinFrame = CombuctorSkinFrame`, `mod.TEXTURE_ITEM_QUEST_BORDER = TEXTURE_ITEM_QUEST_BORDER`, `mod.TEXTURE_ITEM_QUEST_BANG = TEXTURE_ITEM_QUEST_BANG`. Assign before line 942.
- [x] 1.2 **Deduplicate MoneyFrame:New** — Remove first definition (2894–2918), keep second (2929–3030).

## Phase 2: File Extraction

- [ ] 2.1 **Extract combuctor_data.lua** — Move Envoy (946–999), InventoryEvents (1005–1289), BankCache (1295–1418), PlayerInfo (1424–1437), BagSlotInfo (1443–1575), ItemSlotInfo (1581–1627). Replace each `local` with `mod.` for shared references. Remove extracted lines from monolith.
- [ ] 2.2 **Extract combuctor_sets.lua** — Move Sets module + all default category registrations (1633–1809). Replace `L`→`mod.L`, `mod("Envoy")` uses `mod` from core.
- [ ] 2.3 **Extract combuctor_classes.lua** — Move ItemSlot (1815–2257), ItemFrameEvents (2263–2378), ItemFrame (2384–2626), Bag (2632–2882), MoneyFrame (deduped single, 2929–3030), TokenBar (3036–3205), FilterButton/QualityFilter (3211–3311), SideTab/SideFilter (3317–3444), BottomTab/BottomFilter (3450–3538). Replace shared refs: `L`→`mod.L`, `CT`→`mod.CT`, `playerName`→`mod.playerName`, `ItemSearch`→`mod.ItemSearch`, `BagSlotInfo`→`mod.BagSlotInfo`, `CombuctorRetailItemSlot`→`mod.CombuctorRetailItemSlot`, `TEXTURE_ITEM_QUEST_*`→`mod.TEXTURE_ITEM_QUEST_*`.
- [ ] 2.4 **Extract combuctor_frame.lua** — Move FrameEvents (3544–3591), InventoryFrame (3597–4024), skin functions `CombuctorSkinFrame`/`CombuctorSkinItems`/`CombuctorSkinBagSlots`/`CombuctorApplySkin` (4026–4162). Replace `playerName`→`mod.playerName`, `CombuctorAddNineSlice`→`mod.CombuctorAddNineSlice`, `CombuctorRetailItemSlot`→`mod.CombuctorRetailItemSlot`, `CombuctorRetailBagSlot`→`mod.CombuctorRetailBagSlot`, `CombuctorRetailBackpackButton`→`mod.CombuctorRetailBackpackButton`, `CT`→`mod.CT`, `FrameEvents`→`mod("FrameEvents")`, `CombuctorSet`→`mod("Sets")`.
- [ ] 2.5 **Extract combuctor_system.lua** — Move Apply/Restore/Refresh/OnProfileChanged/initFrame/slash/exports (4168–4420). Replace `CombuctorModule`→`mod.CombuctorModule`, `SetupDatabase`→`mod.SetupDatabase`, `DB`→`mod.DB`, `IsModuleEnabled`→`mod.IsModuleEnabled`, `CombuctorApplySkin`→`mod.CombuctorApplySkin`, `CombuctorSkinItems`→`mod.CombuctorSkinItems`, `CombuctorSkinBagSlots`→`mod.CombuctorSkinBagSlots`, `L`→`mod.L`, `OnProfileChanged`→`mod.OnProfileChanged`.

## Phase 3: Wiring

- [ ] 3.1 **Update modules.xml** — Replace `<Script file="combuctor\combuctor.lua"/>` with 6 `<Script>` lines in dependency order: combuctor.lua → combuctor_data.lua → combuctor_sets.lua → combuctor_classes.lua → combuctor_frame.lua → combuctor_system.lua.
- [ ] 3.2 **Delete monolith remnant** — After all extractions, delete remaining content in combuctor.lua (should be only lines 1–944: module guard, CT, helpers, factory, DB, L, Show/Hide/Toggle) or confirm file is empty of extracted sections.

## Phase 4: Verification

- [ ] 4.1 **Full verification** — Load in WoW with `/console scriptErrors 1`. Run all S5.1–S5.12 scenarios: open bags, bank, search, side tabs, bottom tabs, quality filters, sort, money frame, token bar, profile switch, combat. Confirm zero Lua errors, zero behavior change.
