# Phase 2 Plan: "Full Featured" (starting with Anniversary / TBC)

This app is designed around **versioned data packs** + **pluggable, failure-tolerant price providers**. To reach "all professions / all recipes" and "real-ish time AH pricing", Phase 2 focuses on:

1) a repeatable **recipe data pipeline** for Anniversary (TBC-oriented)
2) at least one **real-ish price ingestion** path that can refresh ~hourly and safely fall back to cached data

For current capabilities and lessons learned so far, see `docs/Status.md`.

## Goals (Phase 2)

### Recipe data (Anniversary first)
- Generate complete profession recipe packs for Anniversary (TBC prepatch -> TBC).
- Keep packs versioned and reproducible: include metadata like build number/date and generator version.
- Enforce validation (no unknown reagent itemIds, no missing required fields, no duplicates).

### Auction pricing (real-ish time, hourly OK)
- Refresh prices on a schedule (hourly by default).
- Providers may fail: the app must keep running, show **stale/unavailable** status, and block planning if required item prices are missing and there is no cache.
- Support multiple providers with fallback + user selection later.

## Work breakdown

### 1) Anniversary data pack pipeline (recommended approach)
Build a `DataPackBuilder` tool (console app) that produces:
- `data/Anniversary/items.json`
- `data/Anniversary/professions/*.json`
- `data/Anniversary/producers.json` (optional: conversions like smelting / vendor transforms)

Inputs should be **client-derived exports** for the target build (preferred because it is complete and consistent). The tool should accept exported tables (CSV/JSON) and perform mapping:
- recipes/spells -> profession
- spell reagents -> reagent itemIds/qty
- required skill and difficulty thresholds
- output item (creates itemId/qty)
- cooldown seconds (where applicable)
- output quality (for excluding blue+ skill-up recipes)

Deliverables:
- `tools/WowAhPlanner.DataPackBuilder` (new project)
- `docs/datapacks.md` describing: required inputs, how to run the builder, and how packs map to Classic/TBC builds
- CI validation: builder can validate packs without needing the game installed

### 2) Real-ish time pricing ingestion
Keep all pricing paths behind `IPriceProvider`.

Option A (recommended for reliability): **User-uploaded snapshots** (implemented)
- Upload JSON snapshots per realm and aggregate multiple uploads to reduce outliers.
- Add stronger abuse prevention for public hosting (rate limits, moderation, signed uploads).

Option B: External APIs (optional, behind config)
- Implement as optional provider with explicit configuration and clear failure modes.
- Keep `StubJson` available for deterministic/dev use.

### 3) Planner + UX upgrades
- Better Intermediates UX (grouping, "how many crafts/smelts" details).
- Better recipe acquisition hints (trainer vs drop/vendor/quest).
- Pricing heuristics options (min vs median vs percentile / nth-cheapest).
