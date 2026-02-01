# ProfessionLevelerScan addon (legacy AH API)

Your client reports:
- `C_AuctionHouse=no`
- `QueryAuctionItems=yes`

So the addon uses the legacy browse query API (`QueryAuctionItems`) and/or the browse UI search, and scans a **target list** of reagent itemIds (not the entire AH).

## Install

1) Copy `addon/ProfessionLevelerScan` into your WoW AddOns folder:
- `_anniversary_/Interface/AddOns/ProfessionLevelerScan`

2) Ensure the `Interface` number in `addon/ProfessionLevelerScan/ProfessionLevelerScan.toc` matches your client build if needed.

## Load scan targets (recommended: recipe targets)

The web app generates a Lua file containing all recipes for a profession (minSkill/grayAt + reagent itemIds). The addon then automatically limits the scan to your current skill up to `maxSkillDelta` higher (default 100), clamped to **Expansion cap skill** (default 350).

- `GET /api/scans/recipeTargets.lua?version=Anniversary&professionId=197&region=US&realmSlug=dreamscythe`

Save the response as:
- `_anniversary_/Interface/AddOns/ProfessionLevelerScan/ProfessionLevelerScan_Targets.lua`

If you're running the web app on the same machine as WoW, use `/targets` and click **Install targets** to write this file automatically.

The file defines (among other things):
- `ProfessionLevelerScan_TargetGameVersion`
- `ProfessionLevelerScan_TargetRegion`
- `ProfessionLevelerScan_TargetRealmSlug`
- `ProfessionLevelerScan_TargetProfessionId`
- `ProfessionLevelerScan_TargetProfessionName`
- `ProfessionLevelerScan_VendorItemIds`
- `ProfessionLevelerScan_TargetItemIds` (fallback list)
- `ProfessionLevelerScan_RecipeTargets` (preferred list with recipe metadata)

## In-game UI + options

In-game:
- `/wahpscan options` opens Settings for the addon
- `/wahpscan panel` shows/hides the AH scan panel

Options include:
- Show scan panel when Auction House opens
- Max skill delta (default 100)
- Expansion cap skill (default 350)
- Max pages per item
- Min query interval (seconds)
- Query timeout (seconds)
- Max timeout retries (per page)
- Price rank (nth-cheapest listing; default 3)
- Verbose debug output

## Scan commands

- Full scan from targets: `/wahpscan start`
- Stop: `/wahpscan stop`
- Export scan JSON (shows a copyable UI): `/wahpscan export`
- Quick single-item scan: `/wahpscan item <itemId|itemLink>` (example: `/wahpscan item 14048`)
- Export owned materials JSON: `/wahpscan owned`
- Owned diagnostics: `/wahpscan owneddebug`

Notes:
- Searches use **quoted names** (`"Item Name"`) to force exact name searches.
- Pricing uses **buyout only** (bid-only auctions are ignored).

## SavedVariables workflow (no copy/paste)

The addon stores the last exports as:
- `ProfessionLevelerScanDB.lastSnapshotJson`
- `ProfessionLevelerScanDB.lastOwnedJson`

WoW only writes SavedVariables to disk on:
- `/reload`
- logout
- exiting the game

Web app flow (prices):
1) scan in-game
2) `/reload`
3) go to `/upload` and use **Import from SavedVariables**

Web app flow (owned):
1) install targets (recommended) so the addon knows which items matter
2) `/wahpscan owned`
3) `/reload`
4) go to `/owned` and use **Import from SavedVariables**

## Owned materials notes

- Owned export reads your bag/bank/mail/alt inventory from the Bagnon/BagBrother database (`BrotherBags`).
- It only exports counts for the "wanted" itemIds:
  - `ProfessionLevelerScan_TargetItemIds` (when present), otherwise reagent ids from `ProfessionLevelerScan_RecipeTargets`
  - plus `ProfessionLevelerScan_VendorItemIds` (so vendor mats can be excluded from scanning but still counted as owned)

## Troubleshooting

- `/wahpscan debug` prints what the addon sees (profession info + settings).
- If you see repeated `Query timeout ... Retrying`, try:
  - staying on the Browse tab
  - increasing Min query interval (e.g. 4-6 seconds)
  - lowering Max pages per item (e.g. 1-3)
  - lowering Max timeout retries
- If owned export says it can't find your bag DB:
  - run `/wahpscan owneddebug`
  - confirm `BagBrother` is enabled and then `/reload`
