# WoW Classic Auction House Profession Planner (Blazor Server, .NET 10)

## 1) Problem statement

Build a web app that:

* Pulls Auction House prices for a selected WoW Classic realm (Era, Hardcore, Anniversary, MoP Classic, etc.).
* Calculates the cheapest expected path to level a profession from current skill to target skill.
* Produces a shopping list (aggregated reagent totals) and an estimated total cost.

Primary user outcome: “Tell me what to craft at each skill point and what to buy to do it as cheaply as possible.”

## 2) Key constraints and risks (read first)

### 2.1 Auction House data availability is not guaranteed

Classic AH data via official APIs has had long-running outages / missing data issues at times. The app must not assume a single always-on provider.

Design requirement: **pluggable price providers** with graceful fallbacks.

### 2.2 Supporting “all Classic versions” is mostly a data problem

The UI and algorithm can be shared, but recipes / skill ranges / reagent requirements change by expansion and sometimes by season.

Design requirement: **versioned data packs** (recipes, items, profession rules) and a clean way to add/patch them.

## 3) Scope

### 3.1 MVP (first shippable version)

* Realm selector: region + game version + realm.
* Profession selector + current skill + target skill.
* Price provider integration (start with one, keep interface open for others).
* Profession planner engine (expected-cost path).
* Shopping list + total cost breakdown.
* Persist user settings (selected realm, professions).

### 3.2 V2

* Multiple price providers (automatic fallback, user override).
* Price history charts and “volatility” warnings.
* Alternative objectives:

  * minimize gold spent
  * minimize total crafts
  * minimize vendor-only travel (optional)
  * prefer crafts that can be resold (expected resale value)
* Multiple professions / batch planning.

### 3.3 Non-goals (for now)

* Automated in-game buying/selling.
* Full crafting simulator for every edge case.
* Perfect prediction of recipe acquisition rarity / availability.

## 4) Data sources (conceptual)

### 4.1 Auction pricing data

Implement an interface like:

* GetAuctionHouseSnapshot(realm, faction?) -> list of (itemId, unitPrice, quantity, timestamp)
* GetItemPriceSummary(realm, itemId) -> min/avg/percentiles

Providers:

* Provider A: Official Blizzard API (when available)
* Provider B: TradeSkillMaster public API (requires user API key)
* Provider C (fallback): user-uploaded scans from an in-game addon / saved variables

### 4.2 Profession recipe data

Represent recipes as versioned records:

* ProfessionId
* RecipeId
* CraftedItemId (optional)
* Reagents: (itemId, quantity)
* Skill requirements:

  * minSkill to learn / use
  * difficulty thresholds: orange/yellow/green/gray
* Source flags: trainer, vendor, drop, quest, reputation, etc.

Store as JSON data packs per game version, loaded at startup and cached.

## 5) Core planning algorithm

### 5.1 Expected cost per skill point

For a given skill level s and recipe r:

* p = skillUpChance(r, s) (derived from difficulty color)
* craftCost = sum(reagentQty * reagentUnitPrice)
* expectedCostForOneSkill = craftCost / p

At each skill point, choose the recipe with the lowest expectedCostForOneSkill among recipes usable at that skill.

### 5.2 Shopping list computation

For each selected recipe at skill s:

* expectedCrafts = 1 / p
* add reagents * expectedCrafts into a running total

At the end:

* aggregate by reagent item
* compute total cost and optionally show per-recipe breakdown

### 5.3 Notes

* Skill-up chance model should be configurable (defaults per game version), because different sources disagree and patches can change behavior.
* Handle p = 0 (gray) by excluding those recipes at that skill.

## 6) System architecture

### 6.1 App layout

* Blazor Server UI
* Internal Web API endpoints (same app) for:

  * realm list
  * item search
  * prices
  * profession plan

### 6.2 Services

* PriceService

  * fetches and caches snapshots
  * normalizes to (itemId -> price summary)
* RecipeDataService

  * loads versioned data packs
  * provides recipe search / filtering
* PlannerService

  * builds plan and shopping list
* Background refresh worker

  * refreshes prices on a schedule

### 6.3 Storage

* SQLite for MVP (easy local dev + deployment)
* Tables:

  * CachedAuctionSnapshots (provider, realm, timestamp, rawCompressed)
  * ItemPriceSummary (realm, itemId, min, p25, median, p75, lastUpdated)
  * UserProfiles (optional, if you add auth)
  * SavedPlans

## 7) UX flows

### 7.1 Main flow

1. Choose game version, region, realm (and optionally faction).
2. Choose profession + current skill + target skill.
3. App shows:

   * chosen recipes per skill bracket
   * expected total crafts
   * shopping list
   * total gold estimate
4. User can export shopping list (CSV / text).

### 7.2 Power features

* “I already have some mats” input: subtract from shopping list.
* “Buy price cap” warnings (if unit price > threshold).
* Alternative plan toggle: “safer” (avoid recipes that go green too early).

## 8) Implementation plan (practical)

### Phase 1: Foundations

* Create Blazor Server (.NET 10) solution
* Define domain models: Item, Recipe, Reagent, Realm, PriceQuote
* Implement price provider interface with stubbed data
* Implement planner engine with deterministic sample data

### Phase 2: Real pricing integration

* Integrate first provider end-to-end
* Normalize pricing + caching
* Build realm selection UX

### Phase 3: Real recipe data

* Add data pack loader
* Implement at least 1 profession fully for 1 game version

### Phase 4: Expand coverage

* Add additional professions
* Add additional game versions (Era/Hardcore/Anniversary vs MoP Classic)
* Add additional price providers + fallback logic

## 9) Open decisions

* Which provider is your primary source of AH prices?
* Do you want anonymous use, or accounts (to store saved plans)?
* Do you want to support faction-specific AH differences where relevant?

## 10) Definition of done (MVP)

* Pick realm + profession + skill range
* Generate a plan with a clear shopping list
* Uses live-ish prices from at least one provider
* Handles provider outages gracefully (clear messaging + cached data)

## 11) Solution and project structure

### 11.1 Solution layout

Recommended multi-project layout:

* src/WowAhPlanner.Web

  * Blazor Server UI
  * Minimal API endpoints (or Controllers)
  * Auth optional (later)
* src/WowAhPlanner.Core

  * Domain models
  * Planner algorithm
  * Interfaces (ports)
* src/WowAhPlanner.Infrastructure

  * EF Core DbContext (SQLite)
  * Price provider implementations
  * Data pack loader (recipes, items)
  * Background refresh worker
* tests/WowAhPlanner.Tests

  * Unit tests for planner and data parsing

### 11.2 Deployment targets

* Local desktop machine: runs as a single web app with SQLite file
* Optional later: containerize for home server

## 12) Domain model (minimal but future-proof)

### 12.1 Identifiers and keys

* GameVersion (Era, Hardcore, Anniversary, TBC, Wrath, Cata, MoP, etc.)
* Region (US, EU, KR, TW)
* RealmKey (Region, GameVersion, RealmSlug)
* ProfessionKey (GameVersion, ProfessionId)

### 12.2 Pricing

* Money (long Copper)
* PriceSummary

  * ItemId
  * MinBuyoutCopper
  * MedianCopper (optional)
  * SnapshotTimestampUtc
  * SourceProvider

### 12.3 Recipes and skill logic

* Recipe

  * RecipeId (string or int)
  * ProfessionId
  * Name
  * Reagents: list of Reagent
  * Difficulty thresholds: OrangeUntil, YellowUntil, GreenUntil, GrayAt
  * MinSkill
  * LearnedFrom flags
* Reagent

  * ItemId
  * Quantity

### 12.4 Planner output

* PlanStep

  * SkillFrom
  * SkillTo
  * RecipeId
  * ExpectedCrafts
  * ExpectedCostCopper
* ShoppingListLine

  * ItemId
  * Quantity
  * UnitPriceCopper
  * LineCostCopper
* PlanResult

  * Steps
  * ShoppingList
  * TotalCostCopper
  * GeneratedAtUtc

## 13) APIs and DTOs (MVP)

### 13.1 Minimal endpoints

* GET /api/meta/gameversions
* GET /api/meta/regions
* GET /api/realms?region=US&version=Era
* GET /api/professions?version=Era
* POST /api/plan

### 13.2 Plan request payload

* RealmKey
* ProfessionId
* CurrentSkill
* TargetSkill
* PriceMode (Min, Median)
* OwnedMats (optional map itemId -> quantity)

## 14) First 5 vertical slices (build in this order)

### Slice 1: Shell app and navigation

Goal: You can load the site, pick a game version and realm, and persist selection.
Deliverables:

* Blazor Server app boots
* Version selector, region selector, realm selector
* Store selection in local storage (client) or server session
* Minimal API returns hardcoded realm list for now

### Slice 2: Data packs for professions and recipes

Goal: App can load recipe data for one profession in one version.
Deliverables:

* Data folder structure: data/{version}/items.json and data/{version}/professions/{profession}.json
* RecipeDataService loads and validates JSON on startup
* UI can show list of recipes for the chosen profession

### Slice 3: Price provider interface + stub provider + caching

Goal: Planner can ask for prices and get stable answers.
Deliverables:

* IPriceProvider interface
* StubPriceProvider returns deterministic prices from a JSON file
* PriceService caches PriceSummary by (RealmKey, ItemId)
* SQLite schema and EF Core wiring for cached summaries

### Slice 4: Planner engine end-to-end with stub prices

Goal: Generate a leveling plan and a shopping list.
Deliverables:

* PlannerService implements expected cost per skill point logic
* Handles difficulty thresholds and excludes gray recipes
* Produces PlanResult with Steps and ShoppingList
* UI page shows plan and totals

### Slice 5: Real price integration (first real provider)

Goal: Replace stub prices with live-ish prices.
Deliverables:

* Add Provider implementation (TSM or other)
* Background worker refreshes realm snapshot on schedule
* UI shows snapshot age and provider name
* Fallback: if provider fails, use last cached snapshot

## 15) Practical implementation details

### 15.1 Price selection rules (MVP)

* Default to MinBuyout
* Option to use Median if provider supports it
* Use a floor price for missing items (or mark as missing and block plan)

### 15.2 Skill-up chance function (MVP default)

* Orange: 1.00
* Yellow: 0.75
* Green: 0.25
* Gray: 0.00

Make it configurable per game version later.

### 15.3 Testing plan (start early)

* Planner unit tests:

  * chooses cheapest recipe at a skill level
  * aggregates shopping list correctly
  * respects thresholds and stops at target skill
* Data pack tests:

  * JSON schema validation
  * itemId existence checks

## 16) Next file set to create (minimum skeleton)

* src/WowAhPlanner.Core/Domain/*.cs
* src/WowAhPlanner.Core/Ports/IPriceProvider.cs
* src/WowAhPlanner.Core/Ports/IRecipeRepository.cs
* src/WowAhPlanner.Core/Services/PlannerService.cs
* src/WowAhPlanner.Infrastructure/Data/RecipeDataService.cs
* src/WowAhPlanner.Infrastructure/Pricing/StubPriceProvider.cs
* src/WowAhPlanner.Infrastructure/Persistence/AppDbContext.cs
* src/WowAhPlanner.Web/Pages/Plan.razor
* src/WowAhPlanner.Web/Api/PlanEndpoints.cs
