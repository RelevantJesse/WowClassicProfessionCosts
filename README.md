# FrugalForge (Anniversary) — In-Game Profession Leveling Planner

FrugalForge is a single-addon solution for Classic/Anniversary that scans Auction House prices, tracks owned
materials, and generates a full profession leveling plan entirely in-game. No web app, no import/export.

---

## Key Features

- All-in-game planning  
  Build targets, scan prices, capture owned mats, and generate a plan without leaving WoW.
- Auction House scanner  
  Uses the legacy AH browse API (QueryAuctionItems) with exact-name searches for reliable pricing.
- Owned materials support  
  Pulls inventory from BagBrother (Bagnon) and subtracts what you already own.
- Crafting intermediates  
  Automatically expands craftable reagents (e.g., settings, bolts, wire) so you don’t buy things you can make.
- Clear shopping list  
  Shows item names, quantities needed, owned counts, and total costs.
- Minimap button  
  Left-click opens FrugalForge, Ctrl-click starts an AH scan.
- Planning options  
  Ignore owned mats for selection, limit to current character only, and tune owned value factor.

---

## How It Works

1. Build Targets  
   Open `/frugal`, pick your profession, set skill range, click **Build Targets**.
2. Scan Auction House  
   Go to the AH and run `/frugalscan start` (or click **Scan AH**).
3. Capture Owned Mats  
   Run `/frugalscan owned` to record your inventory (requires BagBrother).
4. Generate Plan  
   Click **Generate Plan** to get:
   - Step-by-step recipe plan
   - Intermediate crafts (if any)
   - Shopping list with prices

---

## Requirements

- WoW Classic Anniversary
- BagBrother (Bagnon) for owned material tracking  
  (Addon still works without it, but owned counts will be “unknown”.)

---

## Commands

Main UI

- `/frugal` — Open FrugalForge UI
- `/frugal build` — Build targets
- `/frugal debug` — Open debug modal

Scanner

- `/frugalscan start` — Full scan
- `/frugalscan stop` — Stop scan
- `/frugalscan status` — Scan status
- `/frugalscan item <itemId|link>` — Scan one item
- `/frugalscan owned` — Export owned mats
- `/frugalscan owneddebug` — Owned diagnostics
- `/frugalscan log` — Show scan log

---

## Notes

- Legacy AH API can be slow or rate-limited.
- Exact-match searches are used to avoid bad pricing.
- Bid-only auctions are ignored (buyout only).
- No reload required to use scans/owned for the planner.

---

## Status

- Stable for Anniversary (single-version for now)
- Actively developed
  Feedback welcome.

---

## Links

- Issues / feedback: https://github.com/RelevantJesse/FrugalForge

---
