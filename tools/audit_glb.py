"""Crimson Knight: Earth-RED — GLB asset auditor.

Parses every GLB directly (no Blender / Three.js needed) and writes ASSET_AUDIT.md
plus ASSET_AUDIT.json at the project root.

Usage (from project root):  python tools/audit_glb.py
"""
import json
import math
import os
import struct
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "config", "asset_manifest.json")
SCAN_DIRS = ["assets/models", "legacy_v03/models"]


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, _length = struct.unpack("<4sII", data[:12])
    if magic != b"glTF":
        raise ValueError("not a GLB")
    chunk_len, chunk_type = struct.unpack("<I4s", data[12:20])
    if chunk_type != b"JSON":
        raise ValueError("first chunk is not JSON")
    return json.loads(data[20:20 + chunk_len]), version, len(data)


# ---- minimal 4x4 matrix helpers (column-major, as glTF) ----
def mat_identity():
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def mat_mul(a, b):
    out = [0.0] * 16
    for c in range(4):
        for r in range(4):
            out[c * 4 + r] = sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4))
    return out


def mat_from_trs(node):
    if "matrix" in node:
        return list(node["matrix"])
    tx, ty, tz = node.get("translation", [0, 0, 0])
    qx, qy, qz, qw = node.get("rotation", [0, 0, 0, 1])
    sx, sy, sz = node.get("scale", [1, 1, 1])
    r = [
        1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy + qz * qw), 2 * (qx * qz - qy * qw),
        2 * (qx * qy - qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz + qx * qw),
        2 * (qx * qz + qy * qw), 2 * (qy * qz - qx * qw), 1 - 2 * (qx * qx + qy * qy),
    ]
    return [r[0] * sx, r[1] * sx, r[2] * sx, 0,
            r[3] * sy, r[4] * sy, r[5] * sy, 0,
            r[6] * sz, r[7] * sz, r[8] * sz, 0,
            tx, ty, tz, 1]


def transform_point(m, p):
    x, y, z = p
    return (m[0] * x + m[4] * y + m[8] * z + m[12],
            m[1] * x + m[5] * y + m[9] * z + m[13],
            m[2] * x + m[6] * y + m[10] * z + m[14])


def audit_file(path):
    gltf, version, size = read_glb(path)
    acc = gltf.get("accessors", [])
    meshes = gltf.get("meshes", [])
    nodes = gltf.get("nodes", [])
    tris = verts = prims = 0
    attrs = Counter()
    for mesh in meshes:
        for p in mesh["primitives"]:
            prims += 1
            for a in p["attributes"]:
                attrs[a] += 1
            pos = acc[p["attributes"]["POSITION"]]
            verts += pos["count"]
            mode = p.get("mode", 4)
            n = acc[p["indices"]]["count"] if "indices" in p else pos["count"]
            if mode == 4:
                tris += n // 3

    # world-space AABB from accessor min/max transformed through the node hierarchy
    lo = [math.inf] * 3
    hi = [-math.inf] * 3

    def visit(idx, parent):
        node = nodes[idx]
        world = mat_mul(parent, mat_from_trs(node))
        if "mesh" in node:
            for p in meshes[node["mesh"]]["primitives"]:
                a = acc[p["attributes"]["POSITION"]]
                if "min" not in a:
                    continue
                mn, mx = a["min"], a["max"]
                for cx in (mn[0], mx[0]):
                    for cy in (mn[1], mx[1]):
                        for cz in (mn[2], mx[2]):
                            q = transform_point(world, (cx, cy, cz))
                            for i in range(3):
                                lo[i] = min(lo[i], q[i])
                                hi[i] = max(hi[i], q[i])
        for c in node.get("children", []):
            visit(c, world)

    scene = gltf.get("scenes", [{}])[gltf.get("scene", 0)]
    for root in scene.get("nodes", []):
        visit(root, mat_identity())
    if lo[0] == math.inf:
        lo = hi = [0, 0, 0]
    dims = [hi[i] - lo[i] for i in range(3)]
    tallest = "XYZ"[dims.index(max(dims))]

    skins = gltf.get("skins", [])
    anims = gltf.get("animations", [])
    textures = gltf.get("textures", [])
    return {
        "file": os.path.relpath(path, ROOT).replace("\\", "/"),
        "bytes": size,
        "generator": gltf.get("asset", {}).get("generator", "?"),
        "nodes": len(nodes),
        "meshes": len(meshes),
        "primitives": prims,
        "triangles": tris,
        "vertices": verts,
        "materials": len(gltf.get("materials", [])),
        "textures": len(textures),
        "has_normals": attrs["NORMAL"] > 0,
        "has_uv": attrs["TEXCOORD_0"] > 0,
        "uv_coverage": f"{attrs['TEXCOORD_0']}/{prims}",
        "has_vertex_color": attrs["COLOR_0"] > 0,
        "rigged": len(skins) > 0,
        "joints": sum(len(s.get("joints", [])) for s in skins),
        "animation_clips": len(anims),
        "clip_names": [a.get("name", "?") for a in anims],
        "bbox_min": [round(v, 3) for v in lo],
        "bbox_max": [round(v, 3) for v in hi],
        "dims": [round(v, 3) for v in dims],
        "longest_axis": tallest,
        "node_names": [n.get("name", "") for n in nodes],
    }


def main():
    manifest = json.load(open(MANIFEST))
    manifest_files = Counter(a["file"] for a in manifest["assets"])
    files = []
    for d in SCAN_DIRS:
        for dirpath, _dirs, names in os.walk(os.path.join(ROOT, d)):
            files += [os.path.join(dirpath, n) for n in sorted(names) if n.lower().endswith(".glb")]
    files.sort()
    results, errors = [], []
    for f in files:
        try:
            results.append(audit_file(f))
        except Exception as e:  # noqa: BLE001 - report every unreadable file
            errors.append((os.path.relpath(f, ROOT), str(e)))

    json.dump({"results": results, "errors": errors}, open(os.path.join(ROOT, "ASSET_AUDIT.json"), "w"), indent=1)

    active = [r for r in results if r["file"].startswith("assets/")]
    legacy = [r for r in results if r["file"].startswith("legacy_v03/")]
    dupes = {k: v for k, v in manifest_files.items() if v > 1}
    unlisted = [r["file"] for r in active if r["file"] not in manifest_files]

    L = []
    L.append("# ASSET_AUDIT — Crimson Knight: Earth-RED\n")
    L.append("Generated by `python tools/audit_glb.py` (parses GLB JSON directly; regenerate after any asset change).\n")
    L.append("## Summary\n")
    L.append(f"- GLB files on disk: **{len(active)}** in `assets/models`, **{len(legacy)}** in `legacy_v03/models`; unreadable: {len(errors)}")
    L.append(f"- Manifest entries: **{len(manifest['assets'])}** (claims 257) but only **{len(manifest_files)}** unique files — "
             f"{sum(v - 1 for v in dupes.values())} duplicate entries: {', '.join(sorted(os.path.basename(k) for k in dupes)) or 'none'}")
    L.append(f"- Files on disk missing from manifest: {len(unlisted)}")
    L.append(f"- Rigged (has glTF skin): **{sum(r['rigged'] for r in results)}** · with animation clips: **{sum(r['animation_clips'] > 0 for r in results)}**")
    L.append(f"- With UVs: {sum(r['has_uv'] for r in results)} · with normals: {sum(r['has_normals'] for r in results)} · "
             f"with glTF materials: {sum(r['materials'] > 0 for r in results)} · with textures: {sum(r['textures'] > 0 for r in results)}")
    L.append(f"- Generators: {dict(Counter(r['generator'] for r in results))}")
    tall_z = sum(1 for r in active if r["longest_axis"] == "Z")
    L.append(f"- Longest axis is Z for {tall_z}/{len(active)} active files — consistent with the documented Z-up source "
             "(Three.js loads must rotate -90° about X, or re-export Y-up from Blender).")
    L.append("- Tested render in Three.js: see the M0 viewer load test (`game/`), not this static parse.\n")

    L.append("## Hero & vehicles (detail)\n")
    for r in results:
        b = os.path.basename(r["file"])
        if b.startswith(("crimson_knight", "CRX1", "CRB1", "CRA1")):
            L.append(f"### `{r['file']}`")
            L.append(f"- {r['bytes']:,} bytes · {r['meshes']} meshes · {r['triangles']:,} tris · {r['vertices']:,} verts")
            L.append(f"- materials {r['materials']} · UV {r['uv_coverage']} · normals {'Y' if r['has_normals'] else 'N'} · vertex colour {'Y' if r['has_vertex_color'] else 'N'}")
            L.append(f"- rig {'Y' if r['rigged'] else 'N'} ({r['joints']} joints) · clips {r['animation_clips']}")
            L.append(f"- bbox dims (x,y,z) = {r['dims']} m · longest axis {r['longest_axis']}")
            L.append(f"- parts: {', '.join(n for n in r['node_names'] if n)}\n")

    def table(rows, title):
        L.append(f"## {title}\n")
        L.append("| file | meshes | tris | mats | UV | normals | rig | clips | dims x,y,z (m) |")
        L.append("|---|---:|---:|---:|:-:|:-:|:-:|---:|---|")
        for r in rows:
            L.append(f"| `{r['file']}` | {r['meshes']} | {r['triangles']} | {r['materials']} | "
                     f"{'Y' if r['has_uv'] else 'N'} | {'Y' if r['has_normals'] else 'N'} | "
                     f"{'Y' if r['rigged'] else 'N'} | {r['animation_clips']} | {r['dims']} |")
        L.append("")

    table(active, "All active assets (`assets/models`)")
    table(legacy, "Legacy v0.3 assets (`legacy_v03/models`)")
    if errors:
        L.append("## Unreadable files\n")
        L += [f"- `{f}`: {e}" for f, e in errors]
    open(os.path.join(ROOT, "ASSET_AUDIT.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")
    print(f"audited {len(results)} GLBs ({len(errors)} errors) -> ASSET_AUDIT.md")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
