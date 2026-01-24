import argparse
import csv
import json
import re
import urllib.request
from pathlib import Path
from typing import Dict, List, Tuple


WAGO_BUILD = "2.5.4.44833"
WAGO_ITEM_SEARCH_NAME_CSV = f"https://wago.tools/db2/ItemSearchName/csv?build={WAGO_BUILD}"

DEFAULT_PROFESSION_ID = 197
DEFAULT_PROFESSION_NAME = "Tailoring"
DEFAULT_WOWHEAD_SKILL_URL = "https://www.wowhead.com/tbc/skill=197/tailoring"


def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "recipe"


def _http_get_text(url: str, *, user_agent: str, timeout_seconds: int = 45) -> str:
    req = urllib.request.Request(url)
    req.add_header("User-Agent", user_agent)
    req.add_header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
    req.add_header("Accept-Language", "en-US,en;q=0.9")
    req.add_header("Cache-Control", "no-cache")
    with urllib.request.urlopen(req, timeout=timeout_seconds) as resp:
        return resp.read().decode("utf-8", errors="replace")


def _find_matching_bracket(text: str, start_index: int, open_char: str, close_char: str) -> int:
    if text[start_index] != open_char:
        raise ValueError(f"Expected '{open_char}' at index {start_index}")

    depth = 0
    in_string = False
    escape = False

    for idx in range(start_index, len(text)):
        ch = text[idx]

        if in_string:
            if escape:
                escape = False
                continue
            if ch == "\\":
                escape = True
                continue
            if ch == '"':
                in_string = False
            continue

        if ch == '"':
            in_string = True
            continue

        if ch == open_char:
            depth += 1
            continue
        if ch == close_char:
            depth -= 1
            if depth == 0:
                return idx

    raise ValueError(f"No matching '{close_char}' found for '{open_char}' at {start_index}")


def _extract_wowhead_spell_listview_data(html: str) -> List[dict]:
    marker = "template: 'spell'"
    pos = 0
    candidates: List[List[dict]] = []

    while True:
        idx = html.find(marker, pos)
        if idx < 0:
            break

        data_idx = html.find("data:", idx)
        if data_idx < 0:
            pos = idx + len(marker)
            continue

        array_start = html.find("[", data_idx)
        if array_start < 0:
            pos = idx + len(marker)
            continue

        array_end = _find_matching_bracket(html, array_start, "[", "]")
        raw = html[array_start : array_end + 1]
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            pos = array_end + 1
            continue

        if isinstance(data, list) and any(isinstance(x, dict) and "reagents" in x for x in data):
            candidates.append(data)

        pos = array_end + 1

    if not candidates:
        raise ValueError("Unable to find a spell listview with reagents[] in the Tailoring skill page.")

    candidates.sort(key=len, reverse=True)
    return candidates[0]


def _extract_wowhead_item_names(html: str) -> Dict[int, str]:
    key = "WH.Gatherer.addData(3, 5, "
    pos = 0
    best: dict | None = None
    while True:
        idx = html.find(key, pos)
        if idx < 0:
            break

        obj_start = html.find("{", idx)
        if obj_start < 0:
            pos = idx + len(key)
            continue

        obj_end = _find_matching_bracket(html, obj_start, "{", "}")
        raw = html[obj_start : obj_end + 1]
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            pos = obj_end + 1
            continue

        if isinstance(data, dict) and (best is None or len(data) > len(best)):
            best = data

        pos = obj_end + 1

    if best is None:
        raise ValueError("Unable to find parseable WH.Gatherer.addData(3, 5, ...) in page.")
    data = best

    names: Dict[int, str] = {}
    for item_id_str, item_obj in data.items():
        try:
            item_id = int(item_id_str)
        except ValueError:
            continue
        if isinstance(item_obj, dict) and "name_enus" in item_obj and isinstance(item_obj["name_enus"], str):
            names[item_id] = item_obj["name_enus"]

    return names


def _load_wago_item_names(cache_dir: Path, *, user_agent: str) -> Dict[int, str]:
    cache_path = cache_dir / f"ItemSearchName.{WAGO_BUILD}.csv"
    if not cache_path.exists():
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(_http_get_text(WAGO_ITEM_SEARCH_NAME_CSV, user_agent=user_agent), encoding="utf-8")

    names: Dict[int, str] = {}
    with cache_path.open("r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                item_id = int(row.get("ID") or row.get("Id") or row.get("id") or "0")
            except ValueError:
                continue
            display = row.get("Display_lang") or row.get("Display") or row.get("Name_lang") or row.get("Name") or ""
            if item_id > 0 and display:
                names[item_id] = display
    return names


def _colors_to_thresholds(colors: List[int]) -> Tuple[int, int, int, int, int]:
    if len(colors) != 4:
        raise ValueError(f"Expected 4 colors values, got {len(colors)}")
    o, y, g, gr = (int(colors[0]), int(colors[1]), int(colors[2]), int(colors[3]))
    if o < 0 or y < 0 or g < 0 or gr < 0:
        raise ValueError("Invalid negative skill threshold")
    min_skill = o
    orange_until = max(min_skill, y - 1)
    yellow_until = max(orange_until, g - 1)
    green_until = max(yellow_until, gr - 1)
    gray_at = max(green_until + 1, gr)
    return min_skill, orange_until, yellow_until, green_until, gray_at


def build_tailoring_pack_from_skill_page(
    html: str, *, profession_id: int, profession_name: str, item_names: Dict[int, str]
) -> Tuple[Dict[str, object], Dict[int, str]]:
    data = _extract_wowhead_spell_listview_data(html)

    used_recipe_ids: Dict[str, int] = {}
    recipes: List[dict] = []
    reagent_item_names: Dict[int, str] = {}

    for entry in data:
        if not isinstance(entry, dict):
            continue
        if entry.get("skill") != [profession_id]:
            continue
        if "reagents" not in entry:
            continue

        spell_id = int(entry["id"])
        name = str(entry["name"])
        colors = entry.get("colors")
        if not isinstance(colors, list) or len(colors) != 4:
            learned_at = int(entry.get("learnedat") or 0)
            if learned_at <= 0:
                continue
            colors = [learned_at, learned_at, learned_at, learned_at]

        min_skill, orange_until, yellow_until, green_until, gray_at = _colors_to_thresholds(colors)

        recipe_id = _slugify(name)
        if recipe_id in used_recipe_ids:
            recipe_id = f"{recipe_id}-{spell_id}"
        used_recipe_ids[recipe_id] = spell_id

        reagents_raw = entry.get("reagents") or []
        reagents: List[dict] = []
        for reagent in reagents_raw:
            if not isinstance(reagent, list) or len(reagent) < 2:
                continue
            item_id = int(reagent[0])
            qty = int(reagent[1])
            if item_id <= 0 or qty <= 0:
                continue
            reagents.append({"itemId": item_id, "qty": qty})
            if item_id in item_names:
                reagent_item_names[item_id] = item_names[item_id]

        if not reagents:
            continue

        recipes.append(
            {
                "recipeId": recipe_id,
                "professionId": profession_id,
                "name": name,
                "minSkill": min_skill,
                "orangeUntil": orange_until,
                "yellowUntil": yellow_until,
                "greenUntil": green_until,
                "grayAt": gray_at,
                "reagents": reagents,
            }
        )

    if not recipes:
        raise ValueError("Parsed 0 recipes from listview.")

    pack = {
        "professionId": profession_id,
        "professionName": profession_name,
        "recipes": sorted(recipes, key=lambda r: (r["minSkill"], r["name"])),
    }

    return pack, reagent_item_names


def _load_items_json(path: Path) -> Dict[int, str]:
    if not path.exists():
        return {}
    items = json.loads(path.read_text(encoding="utf-8"))
    return {int(it["itemId"]): it["name"] for it in items}


def _write_items_json(path: Path, items: Dict[int, str]) -> None:
    data = [{"itemId": item_id, "name": items[item_id]} for item_id in sorted(items)]
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Export TBC Classic profession recipes into Anniversary datapack JSON.")
    parser.add_argument("--profession-id", type=int, default=DEFAULT_PROFESSION_ID)
    parser.add_argument("--profession-name", default=DEFAULT_PROFESSION_NAME)
    parser.add_argument("--out-profession-json", type=Path, default=Path("data/Anniversary/professions/tailoring.json"))
    parser.add_argument("--out-items-json", type=Path, default=Path("data/Anniversary/items.json"))
    parser.add_argument("--cache-dir", type=Path, default=Path(".wago-cache"))
    parser.add_argument(
        "--user-agent",
        default="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    )
    parser.add_argument("--wowhead-skill-url", default=DEFAULT_WOWHEAD_SKILL_URL)
    args = parser.parse_args()

    if args.profession_id <= 0:
        raise SystemExit("--profession-id must be > 0")
    if not args.profession_name.strip():
        raise SystemExit("--profession-name must be non-empty")

    html_cache_path = args.cache_dir / f"wowhead_tbc_skill_{args.profession_id}.html"
    if html_cache_path.exists():
        html = html_cache_path.read_text(encoding="utf-8", errors="replace")
    else:
        html = _http_get_text(args.wowhead_skill_url, user_agent=args.user_agent)
        html_cache_path.parent.mkdir(parents=True, exist_ok=True)
        html_cache_path.write_text(html, encoding="utf-8")

    item_names = _extract_wowhead_item_names(html)
    pack, reagent_item_names = build_tailoring_pack_from_skill_page(
        html,
        profession_id=args.profession_id,
        profession_name=args.profession_name,
        item_names=item_names,
    )

    if not pack["recipes"]:
        raise SystemExit("No recipes were parsed; aborting.")

    args.out_profession_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_profession_json.write_text(json.dumps(pack, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    items = _load_items_json(args.out_items_json)
    missing = 0
    for recipe in pack["recipes"]:
        for reagent in recipe["reagents"]:
            item_id = int(reagent["itemId"])
            if item_id in items:
                continue
            name = reagent_item_names.get(item_id)
            if not name:
                missing += 1
                continue
            items[item_id] = name

    if missing:
        wago_names = _load_wago_item_names(args.cache_dir, user_agent=args.user_agent)
        for recipe in pack["recipes"]:
            for reagent in recipe["reagents"]:
                item_id = int(reagent["itemId"])
                if item_id in items:
                    continue
                name = wago_names.get(item_id)
                if not name:
                    continue
                items[item_id] = name

        still_missing = []
        for recipe in pack["recipes"]:
            for reagent in recipe["reagents"]:
                item_id = int(reagent["itemId"])
                if item_id not in items:
                    still_missing.append(item_id)
        if still_missing:
            still_missing = sorted(set(still_missing))
            raise SystemExit(f"Missing {len(still_missing)} reagent item names (e.g. {still_missing[:20]}).")

    _write_items_json(args.out_items_json, items)

    print(f"Wrote {args.out_profession_json} ({args.profession_name}, {len(pack['recipes'])} recipes)")
    print(f"Wrote {args.out_items_json} ({len(items)} items)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
