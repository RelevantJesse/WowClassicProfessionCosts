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
- Deterministic stub prices: `data/Era/stub-prices.json`

## Tests included

- Planner chooses cheapest recipe: `tests/WowAhPlanner.Tests/PlannerServiceTests.cs`
- Shopping list quantity aggregation: `tests/WowAhPlanner.Tests/PlannerServiceTests.cs`
- Data pack loader validation (missing required fields): `tests/WowAhPlanner.Tests/DataPackLoaderTests.cs`

