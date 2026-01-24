import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, Iterator, List, Optional, Tuple


@dataclass(frozen=True)
class SpellCooldownInfo:
    spell_id: int
    creates_item_id: int
    cooldown_seconds: int
    source_path: Path


def _strip_html(text: str) -> str:
    text = re.sub(r"<[^>]+>", " ", text)
    text = text.replace("&nbsp;", " ")
    return re.sub(r"\s+", " ", text).strip()


def _parse_duration_to_seconds(text: str) -> Optional[int]:
    normalized = _strip_html(text).lower()
    if not normalized:
        return None
    if "n/a" in normalized or normalized == "na":
        return None
    if normalized == "none":
        return None

    unit_seconds = {
        "sec": 1,
        "secs": 1,
        "second": 1,
        "seconds": 1,
        "min": 60,
        "mins": 60,
        "minute": 60,
        "minutes": 60,
        "hour": 3600,
        "hours": 3600,
        "day": 86400,
        "days": 86400,
    }

    total = 0.0
    found = False
    for m in re.finditer(r"(\d+(?:\.\d+)?)\s*(sec|secs|second|seconds|min|mins|minute|minutes|hour|hours|day|days)\b", normalized):
        found = True
        n = float(m.group(1))
        unit = m.group(2)
        total += n * unit_seconds[unit]

    if not found:
        return None

    # Prefer integer seconds for data packs.
    return int(round(total))


def _extract_cooldown_cell(html: str) -> Optional[str]:
    # Examples:
    # <tr><th>Cooldown</th><td><span class="q0">n/a</span></td></tr>
    # <tr><th>Cooldown</th><td>4 days</td></tr>
    m = re.search(r"<th>\s*Cooldown\s*</th>\s*<td[^>]*>(.*?)</td>", html, flags=re.IGNORECASE | re.DOTALL)
    if not m:
        return None
    return m.group(1)


def _extract_creates_item_id(html: str) -> Optional[int]:
    # Wowhead embeds spell data like: "creates":[2996,1,1]
    m = re.search(r'"creates"\s*:\s*\[\s*(\d+)\s*,', html)
    if m:
        return int(m.group(1))

    # Fallback: Create Item table contains /item=NNN links.
    m = re.search(r"/item=(\d+)", html)
    if m:
        return int(m.group(1))

    return None


def _iter_spell_pages(cache_roots: Iterable[Path]) -> Iterator[Tuple[int, Path]]:
    patterns = [
        re.compile(r"^spell_(\d+)\.html$", re.IGNORECASE),
        re.compile(r"^wowhead_spell_(\d+)\.html$", re.IGNORECASE),
    ]

    seen: set[Path] = set()
    for root in cache_roots:
        if not root.exists() or not root.is_dir():
            continue
        for path in root.glob("*.html"):
            if path in seen:
                continue
            seen.add(path)

            for pat in patterns:
                m = pat.match(path.name)
                if m:
                    yield int(m.group(1)), path
                    break


def _load_spell_cooldowns(cache_roots: List[Path]) -> List[SpellCooldownInfo]:
    out: List[SpellCooldownInfo] = []

    for spell_id, path in _iter_spell_pages(cache_roots):
        try:
            html = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        cooldown_cell = _extract_cooldown_cell(html)
        if cooldown_cell is None:
            continue

        cooldown_seconds = _parse_duration_to_seconds(cooldown_cell)
        if not cooldown_seconds or cooldown_seconds <= 0:
            continue

        creates_item_id = _extract_creates_item_id(html)
        if not creates_item_id or creates_item_id <= 0:
            continue

        out.append(
            SpellCooldownInfo(
                spell_id=spell_id,
                creates_item_id=creates_item_id,
                cooldown_seconds=cooldown_seconds,
                source_path=path,
            )
        )

    return out


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _dump_json(obj: dict) -> str:
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def _backfill_profession_file(path: Path, cooldown_by_item_id: Dict[int, int], *, overwrite: bool) -> Tuple[int, int]:
    data = _load_json(path)
    recipes = data.get("recipes")
    if not isinstance(recipes, list):
        return 0, 0

    updated = 0
    skipped = 0

    for r in recipes:
        if not isinstance(r, dict):
            continue
        creates_item_id = r.get("createsItemId")
        if not isinstance(creates_item_id, int) or creates_item_id <= 0:
            continue

        cooldown = cooldown_by_item_id.get(creates_item_id)
        if not cooldown:
            continue

        if (not overwrite) and ("cooldownSeconds" in r):
            skipped += 1
            continue

        r["cooldownSeconds"] = cooldown
        updated += 1

    if updated > 0:
        path.write_text(_dump_json(data), encoding="utf-8")

    return updated, skipped


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Backfill recipe cooldownSeconds by parsing cached Wowhead spell pages under .wago-cache."
    )
    parser.add_argument(
        "--data-root",
        type=Path,
        default=Path("data"),
        help="Repo data/ directory (contains version folders).",
    )
    parser.add_argument(
        "--version",
        default="Anniversary",
        help="Game version folder under data/ (e.g. Anniversary, Era).",
    )
    parser.add_argument(
        "--cache-root",
        type=Path,
        default=Path(".wago-cache"),
        help="Cache root containing wowhead spell pages.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing cooldownSeconds in profession JSON (default: only fill missing).",
    )
    args = parser.parse_args()

    version_dir = args.data_root / args.version
    professions_dir = version_dir / "professions"
    if not professions_dir.exists():
        raise SystemExit(f"Professions folder not found: {professions_dir}")

    cache_roots = [
        args.cache_root / "wowhead",
        args.cache_root,
    ]

    infos = _load_spell_cooldowns(cache_roots)

    cooldown_by_item_id: Dict[int, int] = {}
    collisions: Dict[int, List[SpellCooldownInfo]] = {}
    for info in infos:
        if info.creates_item_id in cooldown_by_item_id and cooldown_by_item_id[info.creates_item_id] != info.cooldown_seconds:
            collisions.setdefault(info.creates_item_id, []).append(info)
            continue
        cooldown_by_item_id[info.creates_item_id] = info.cooldown_seconds

    updated_total = 0
    skipped_total = 0
    for profession_file in sorted(professions_dir.glob("*.json")):
        updated, skipped = _backfill_profession_file(profession_file, cooldown_by_item_id, overwrite=args.overwrite)
        updated_total += updated
        skipped_total += skipped

    print(f"Loaded {len(infos)} cooldown spell pages.")
    print(f"Cooldown items mapped: {len(cooldown_by_item_id)}")
    if collisions:
        print(f"WARNING: {len(collisions)} itemId collisions with differing cooldowns (kept first): {sorted(collisions.keys())[:10]}")
    print(f"Updated {updated_total} recipes with cooldownSeconds.")
    if not args.overwrite:
        print(f"Skipped {skipped_total} recipes that already had cooldownSeconds.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

