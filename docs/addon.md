# WowAhPlannerScan addon (legacy AH API)

Your client reports:
- `C_AuctionHouse=no`
- `QueryAuctionItems=yes`

So this addon uses the legacy Auction House query API (`QueryAuctionItems`) and scans a **target list of itemIds** (recipe reagents) instead of scanning the entire AH.

## Install

1) Copy `addon/WowAhPlannerScan` into your WoW AddOns folder:
- `_classic_/Interface/AddOns/WowAhPlannerScan`

2) Ensure the `Interface` number in `addon/WowAhPlannerScan/WowAhPlannerScan.toc` matches your client build if needed.

## Load scan targets (recommended: recipe targets)

The web app can generate a Lua file containing all recipes for a profession (minSkill/grayAt + reagent itemIds). The addon then automatically limits the scan to your current skill up to `maxSkillDelta` higher (default 100), clamped to your profession max skill.

- `GET /api/scans/recipeTargets.lua?version=Anniversary&professionId=185`

Save the response as:
- `_classic_/Interface/AddOns/WowAhPlannerScan/WowAhPlannerScan_Targets.lua`

If you’re running the web app on the same machine as WoW, you can use the app’s `/targets` page and click **Install targets** to write this file automatically.

It should define:
- `WowAhPlannerScan_TargetProfessionId = 185`
- `WowAhPlannerScan_TargetProfessionName = "Tailoring"` (used if your client’s profession IDs differ)
- `WowAhPlannerScan_TargetItemIds = { ... }` (full pack reagent list, used as fallback)
- `WowAhPlannerScan_RecipeTargets = { ... }`

## Configure scan window + performance

In-game:
- `/wahpscan options`

Then set **Max skill delta** (default 100).
Also consider reducing **Max pages per item** for speed (default 10).

Important: the scan upper bound is clamped to **Expansion cap skill** (default 350). This is intentionally not your currently-trained cap (e.g. 75), because you may plan ahead for training.

## Scan + export

1) Go to an Auction House and open the AH window.
2) Run: `/wahpscan start`
3) When it finishes: `/wahpscan export`
4) Copy the JSON and paste it into the app at `/upload`.

Troubleshooting:
- `/wahpscan debug` prints the profession IDs/names the addon sees.
- If `GetProfessions()` is all `nil`, the addon falls back to reading the Skills list (`GetSkillLineInfo`).

## Notes / limitations

- Scanning is throttled and can be slow for large target lists (thousands of items).
- This is “min unit buyout” only for now; median/percentiles can be added later.
- For best results, keep the AH window open while scanning.

## Legacy fallback (direct itemId list)

If you don’t want recipe targets, you can still generate a direct itemId list:
- `GET /api/scans/targets.lua?version=Anniversary&professionId=185&currentSkill=150&maxSkillDelta=100`
