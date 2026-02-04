# Profession Leveler

In-game addon suite that generates profession leveling plans using in-game scans and owned material snapshots.

## Quick start (recommended)

1) Go to the repo's **Releases** page
2) Click the latest version and download the `.zip`
3) Extract the zip somewhere (like your Desktop) and open the extracted folder
4) Copy the addons from the `addon/` folder into your WoW AddOns directory

### Install the in-game addons

1) Copy `FrugalForge/` into your WoW Anniversary AddOns folder, for example:
   - `...\World of Warcraft\_anniversary_\Interface\AddOns\`
2) In WoW, `/reload` so the addon initializes. Use `/frugal` to open the planner UI.

### Scan + prices

1) In-game at the Auction House: run a scan with `/frugal scan`.
2) `/reload` so SavedVariables are written.
3) FrugalForge reads the scan automatically (no import/export).

### Owned materials

1) In-game: `/frugal owned` then `/reload`.
2) FrugalForge reads owned materials automatically (per-character breakdown included).

### Build a plan

1) `/frugal` in-game.
2) Pick a profession and click **Build Targets**.
3) Run a scan at the Auction House.
4) Click **Generate Plan** in FrugalForge. Steps + shopping list use only priced or owned reagents.

## Build

`dotnet build WowAhPlanner.slnx`

## Run (local dev)

`dotnet run --project src/WowAhPlanner.WinForms`

## Test

`dotnet test`

## Sample data

- Profession + items data packs: `data/Era/items.json`, `data/Era/professions/cooking.json`
- Anniversary packs (active development): `data/Anniversary/items.json`, `data/Anniversary/professions/*.json`, `data/Anniversary/producers.json`
- Deterministic stub prices:
  - `data/Era/stub-prices.json`
  - `data/Anniversary/stub-prices.json`

## In-game workflow

- Open `/frugal` and choose a profession.
- Click **Build Targets** (writes targets into SavedVariables for the scanner).
- Scan at the Auction House, then `/reload` so the snapshot is saved.
- Use **Generate Plan** in FrugalForge.

Addon docs: `docs/addon.md`

## Phase 2

See `Phase2.md` for the plan to scale Anniversary/TBC and beyond (full recipe packs + additional price ingestion options).

## Tests included

- Planner chooses cheapest recipe: `tests/WowAhPlanner.Tests/PlannerServiceTests.cs`
- Shopping list quantity aggregation: `tests/WowAhPlanner.Tests/PlannerServiceTests.cs`
- Data pack loader validation (missing required fields): `tests/WowAhPlanner.Tests/DataPackLoaderTests.cs`
