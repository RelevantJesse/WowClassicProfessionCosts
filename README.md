# WoW Classic Auction House Profession Planner (MVP)

Blazor Server app that loads versioned profession recipe data packs, fetches item prices from a pluggable provider (stub JSON for MVP), caches price summaries in SQLite, and generates a cheapest-expected-cost profession leveling plan + shopping list.

## Build

`dotnet build`

## Run

`dotnet run --project src/WowAhPlanner.Web`

Then open the printed URL (default `https://localhost:5001`).

## Test

`dotnet test`

## Sample data

- Profession + items data packs: `data/Era/items.json`, `data/Era/professions/cooking.json`
- Anniversary sample pack (placeholder for Phase 2): `data/Anniversary/items.json`, `data/Anniversary/professions/cooking.json`
- Deterministic stub prices: `data/Era/stub-prices.json`
  - Anniversary stub prices: `data/Anniversary/stub-prices.json`

## Uploading real-ish prices (snapshot workflow)

- Target itemId list endpoints:
  - `GET /api/scans/targets?version=Anniversary`
  - `GET /api/scans/targets.lua?version=Anniversary`
  - Optional filters: `&professionId=185&currentSkill=150&maxSkillDelta=100`
- Recommended recipe-target endpoint (addon filters by your skill + configurable delta):
  - `GET /api/scans/recipeTargets.lua?version=Anniversary&professionId=185`
  - Note: this also includes `WowAhPlannerScan_TargetItemIds` as a fallback list
- UI helper: `/targets` (download or install targets into your WoW AddOns folder)
- Upload UI: `/upload` (stores prices as provider `UploadedSnapshot` in SQLite)
- Addon skeleton + instructions: `addon/WowAhPlannerScan/WowAhPlannerScan.lua`, `docs/addon.md`

## Phase 2

See `Phase2.md` for the plan to scale to Anniversary/TBC and beyond (full recipe packs + real-ish time auction pricing).

## Tests included

- Planner chooses cheapest recipe: `tests/WowAhPlanner.Tests/PlannerServiceTests.cs`
- Shopping list quantity aggregation: `tests/WowAhPlanner.Tests/PlannerServiceTests.cs`
- Data pack loader validation (missing required fields): `tests/WowAhPlanner.Tests/DataPackLoaderTests.cs`
