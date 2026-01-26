# WoW Classic Auction House Profession Planner

Blazor Server app that loads versioned profession recipe data packs, ingests auction pricing snapshots, caches price summaries in SQLite, and generates a cheapest-expected-cost profession leveling plan + shopping list.

## Build

`dotnet build WowAhPlanner.slnx`

## Run

`dotnet run --project src/WowAhPlanner.Web`

Then open the printed URL (default `https://localhost:5001`).

## Download + run (no .NET install)

GitHub Releases include a self-contained Windows build. Download the zip, extract it somewhere writable, then double-click `WowAhPlanner.Web.exe` (it auto-opens your browser to `http://localhost:5000`).

The in-game addon is included in the zip at `addon/WowAhPlannerScan`.

## Test

`dotnet test`

## Sample data

- Profession + items data packs: `data/Era/items.json`, `data/Era/professions/cooking.json`
- Anniversary packs (active development): `data/Anniversary/items.json`, `data/Anniversary/professions/*.json`, `data/Anniversary/producers.json`
- Deterministic stub prices:
  - `data/Era/stub-prices.json`
  - `data/Anniversary/stub-prices.json`

## In-game scanning + upload workflow

- Generate/install targets (recommended):
  - Web UI: `/targets` -> **Install targets**
  - Writes `WowAhPlannerScan_Targets.lua` into `...\World of Warcraft\_anniversary_\Interface\AddOns\WowAhPlannerScan\`
- In-game (at the Auction House):
  - Scan: `/wahpscan start` (or use the AH panel)
  - Optional one-off: `/wahpscan item <itemId|itemLink>`
  - Export UI: `/wahpscan export`
  - Then `/reload` so SavedVariables are written
- Upload to the app:
  - `/upload` -> **Import from SavedVariables** (no copy/paste)

Addon docs: `docs/addon.md`

## Owned materials workflow

- In-game:
  - `/wahpscan owned`
  - `/reload`
- In the web app:
  - `/owned` -> **Import from SavedVariables**

Owned mats are saved per user and per realm and can be subtracted from the plan shopping list.

## Phase 2

See `Phase2.md` for the plan to scale Anniversary/TBC and beyond (full recipe packs + additional price ingestion options).

## Status / notes

See `docs/Status.md` for current capabilities, lessons learned, and enhancement ideas.

## Tests included

- Planner chooses cheapest recipe: `tests/WowAhPlanner.Tests/PlannerServiceTests.cs`
- Shopping list quantity aggregation: `tests/WowAhPlanner.Tests/PlannerServiceTests.cs`
- Data pack loader validation (missing required fields): `tests/WowAhPlanner.Tests/DataPackLoaderTests.cs`
