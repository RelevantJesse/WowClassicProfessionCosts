# WoW Classic Auction House Profession Planner

Blazor Server app that loads versioned profession recipe data packs, ingests auction pricing snapshots, caches price summaries in SQLite, and generates a cheapest-expected-cost profession leveling plan + shopping list.

## Quick start (recommended)

1) Go to the repo’s **Releases** page
2) Click the latest version and download the `.zip`
3) Extract the zip somewhere (like your Desktop) and open the extracted folder

### Install the in-game addon

1) Copy `addon/WowAhPlannerScan/` into your WoW Anniversary AddOns folder, for example:
   - `...\World of Warcraft\_anniversary_\Interface\AddOns\`
2) This installs the addon, but it isn’t useful until you install targets from the web app (next step).

### Run the web app

1) Double-click `WowAhPlanner.Web.exe` (or `run.cmd`)
2) Your browser should open to `http://localhost:5000`
3) On the Home page:
   - Select **Anniversary**
   - Enter your server (example: `dreamscythe`)

### Generate scan targets

1) Go to **Targets**
2) Select the profession you want to level
3) Click **Install**
4) Back in WoW, run `/reload` (or reload UI) so the addon picks up the targets

### Scan + upload prices

1) Open the Auction House (use the default Blizzard AH UI; TSM isn’t supported yet)
2) Find the addon widget and click **Scan**
   - By default it scans the next 100 profession skill points; you can change this in options
3) When the scan finishes, click **Export** and copy all the text
4) In the web app, go to **Upload**, paste what you copied, and click **Upload**

### Build a plan

1) Go to **Plan**
2) Choose your profession, current skill, and target skill
   - Don’t set a target higher than what you scanned, or you won’t have pricing data yet
3) Click **Generate plan**

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
