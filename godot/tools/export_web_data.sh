#!/bin/sh
# Re-export the web build's UI data for Godot (run from the repo root after changing game/src/ui).
# items.json comes from game/src/ui/inventoryData.ts via the web build's own esbuild.
set -e
out="$(pwd)/godot/data"
tmp="$(mktemp -d)"
(cd game && ./node_modules/.bin/esbuild src/ui/inventoryData.ts --bundle --format=esm --platform=node --outfile="$tmp/inv.mjs" --log-level=warning)
node -e "import('file:///$tmp/inv.mjs').then(m=>require('fs').writeFileSync('$out/items.json',JSON.stringify({items:m.ITEMS,categoryLabel:m.CATEGORY_LABEL,categoryOrder:m.CATEGORY_ORDER,defaultHotbar:m.DEFAULT_HOTBAR},null,1)))"
cp game/src/ui/data/icon_manifest.json game/src/ui/data/hotbar_layout.json game/src/ui/data/menu_spec.json "$out/"
rm -rf "$tmp"
