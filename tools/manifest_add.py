"""Register generated assets from a build config (npc_assets.json / gadget_assets.json) in config/asset_manifest.json.

    python tools/manifest_add.py config/npc_assets.json npcs characters_npc "1.6 (Claude): ..."
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
cfg_path, key, category, note = sys.argv[1:5]
cfg = json.load(open(os.path.join(ROOT, cfg_path), encoding="utf-8"))
man_path = os.path.join(ROOT, "config", "asset_manifest.json")
man = json.load(open(man_path, encoding="utf-8"))
by_id = {a["id"]: i for i, a in enumerate(man["assets"])}
for item in cfg[key]:
    rigged = item.get("rigged", True) if "bones" in item or item.get("rigged") else False
    entry = {
        "id": item["id"], "category": category, "file": item["file"], "format": "glb", "stage": "prototype",
        "rigged": rigged, "animation_clips": len(item.get("clips", [])), "collision": item.get("collision", "none (visual)"),
        "units": "meters", "origin": item.get("origin", "ground_center"), "up_axis": "Y", "forward": "+Z",
        "source": cfg["source"], "triangles": item["triangles"],
    }
    for extra in ("label", "role", "clips", "sockets", "pivots", "scale", "attach", "inventory_id"):
        if extra in item:
            entry[extra] = item[extra]
    if item["id"] in by_id:
        man["assets"][by_id[item["id"]]] = entry
    else:
        man["assets"].append(entry)
man["asset_count"] = len(man["assets"])
if note not in man["changelog"]:
    man["changelog"].append(note)
with open(man_path, "w", encoding="utf-8") as fh:
    json.dump(man, fh, indent=2, ensure_ascii=False)
print("manifest:", man["asset_count"], "assets")
