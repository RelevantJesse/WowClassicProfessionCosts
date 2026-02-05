## 1.1.3 - 2026-02-05

- Essence conversions now work both ways (lesser↔greater) for planning and owned mats.
- Materials list combines lesser/greater essences into greater-equivalents with cheapest pricing.
- Enchanting: rods only added when required by planned enchants; missing-price filtering skips rods; shard scans bypass rarity filter.
- Vendor recipe handling improved (vendor overrides + recipe prices only when actually vendor-sold).

## 1.1.2 - 2026-02-05

- Selection tie-breaker now falls back to “no-owned” reagent cost when expected costs are equal, avoiding pricey recipes when owned mats zero out cost.
- Orange recipes remain 1.0 skill-up chance through the orange cutoff; decay starts at yellow.

## 1.1.1 - 2026-02-05

- Skill-up chance now decays progressively within yellow/green/pre-gray bands instead of flat rates.
- Minimap button is smaller, draggable, and can be hidden via Alt-click or `/frugal minimap` (tooltip updated).

## 1.1.0 - 2026-02-04

- Fix intermediate handling so owned base mats satisfy intermediate crafts (e.g., owned Runecloth now correctly reduces Bolt of Runecloth purchases by preferring craft when fully satisfiable from owned).
- Fix shopping list base-mat quantities when owned intermediate outputs cover part of intermediate demand (don’t expand owned bolts/settings/etc into their base reagents).
- Fix Build Targets crash caused by `buildRecipeByOutput` being nil (Lua forward-declare scoping issue).
- Shopping list now accounts for owned quantities when an item appears both as a purchased mat and as an intermediate to craft (owned reduces crafts after covering buy-needed; "need" reflects total buy+craft demand).
- Scanner cleanup: remove legacy `ProfessionLevelerScan*` bridge globals, clamp scan delay (faster by default), filter vendor/quality-disallowed items, and de-dupe/sanitize scan target IDs.
- Data pack tweaks: correct vendor prices for Coarse/Fine Thread and ensure common ore/bar item IDs are present in the Anniversary item list.
- Docs: clarify planner object model + selection-vs-shopping semantics (`AGENTS.md`) and note that FrugalScan is the single source of truth (`docs/addon-planning.md`).
- Bump addon version to 1.1.0.

## 1.0.1 - 2026-02-04

- Non-trainer recipes are de-prioritized and called out as recipe-required in the plan/shopping list.
- Plan generation now blocks when any required price is missing, with a prompt to scan first.
- Scan Missing can derive missing items directly from targets without a plan.
- Intermediate craft lines insert before first use and show total-needed with current owned.
- Improved addon version lookup and README cleanup.
