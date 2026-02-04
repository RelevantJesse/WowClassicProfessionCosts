# FrugalForge addon (scanner + planner)

Your client reports:
- `C_AuctionHouse=no`
- `QueryAuctionItems=yes`

So the addon uses the legacy browse query API (`QueryAuctionItems`) and/or the browse UI search, and scans a **target list** of reagent itemIds (not the entire AH).

## Install

1) Copy `FrugalForge` into your WoW AddOns folder:
   - `_anniversary_/Interface/AddOns/FrugalForge`

2) Ensure the `Interface` number in both `.toc` files matches your client build if needed.

## Build scan targets (in-game)

FrugalForge builds the recipe target list in-game. Pick your profession, choose **Skill +**, then click **Build Targets**. The scan will automatically limit to your current skill up to `maxSkillDelta` higher (default 100), clamped to **Expansion cap skill** (default 350).

Targets are stored as:
- `FrugalScan_TargetProfessionId`
- `FrugalScan_TargetProfessionName`
- `FrugalScan_TargetItemIds`
- `FrugalScan_RecipeTargets` (includes reagent quantities)

## In-game UI + options

In-game:
- `/frugalscan options` opens Settings for the addon
- `/frugalscan panel` shows/hides the AH scan panel

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

- Full scan from targets: `/frugalscan start`
- Stop: `/frugalscan stop`
- Export scan JSON (shows a copyable UI): `/frugalscan export`
- Quick single-item scan: `/frugalscan item <itemId|itemLink>` (example: `/frugalscan item 14048`)
- Export owned materials JSON: `/frugalscan owned`
- Owned diagnostics: `/frugalscan owneddebug`

Notes:
- Searches use **quoted names** (`"Item Name"`) to force exact name searches.
- Pricing uses **buyout only** (bid-only auctions are ignored).

## SavedVariables notes

WoW only writes SavedVariables to disk on `/reload`, logout, or exit. FrugalForge reads the latest snapshots directly from memory, so no reload is needed for the planner UI.

## Owned materials notes

- Owned export reads your bag/bank/mail/alt inventory from the Bagnon/BagBrother database (`BrotherBags`).
- It only exports counts for the "wanted" itemIds:
- `FrugalScan_TargetItemIds` (when present), otherwise reagent ids from `FrugalScan_RecipeTargets`
- plus `FrugalScan_VendorItemIds` (so vendor mats can be excluded from scanning but still counted as owned)

## Troubleshooting

- `/frugalscan debug` prints what the addon sees (profession info + settings).
- If you see repeated `Query timeout ... Retrying`, try:
  - staying on the Browse tab
  - increasing Min query interval (e.g. 4-6 seconds)
  - lowering Max pages per item (e.g. 1-3)
  - lowering Max timeout retries
- If owned export says it can't find your bag DB:
  - run `/frugalscan owneddebug`
  - confirm `BagBrother` is enabled and then `/reload`
