"""
Parse fighter1_bsp.h into a Swift literal of [FighterPolygon].
Each Bsp_Node in the file is a BSP_POLY (optionally with BSP_BACK_VIEW),
4 vertices, references a bvXX array.
"""
import re, sys, pathlib

src = pathlib.Path(sys.argv[1]).read_text()

# Map color symbols → palette index used by DStarColor.
COLOR = {
    "BLACK":0, "DARK_GRAY":1, "DARKGRAY":1, "DGREY":1, "DGRAY":1,
    "GRAY":2, "GREY":2, "MED_GRAY":2, "MED_GREY":2,
    "LIGHT_GRAY":3, "LIGHTGRAY":3, "LGREY":3, "LGRAY":3,
    "WHITE":4, "RED":5, "GREEN":6, "BLUE":7, "YELLOW":8,
}

# Pull every Pt3d array: name + four (x,y,z) triples.
arr_re = re.compile(
    r"static\s+Pt3d\s+(bv\d+)\s*\[\]\s*=\s*\{(.+?)\}\s*;",
    re.S,
)
def parse_pt3d(body):
    pts = re.findall(r"\{\s*(-?\d*\.?\d+(?:[eE][-+]?\d+)?)\s*,\s*"
                     r"(-?\d*\.?\d+(?:[eE][-+]?\d+)?)\s*,\s*"
                     r"(-?\d*\.?\d+(?:[eE][-+]?\d+)?)\s*\}", body)
    return [(float(a),float(b),float(c)) for a,b,c in pts]

arrays = {}
for m in arr_re.finditer(src):
    arrays[m.group(1)] = parse_pt3d(m.group(2))

# Pull every Bsp_Node block.
node_re = re.compile(
    r"static\s+Bsp_Node\s+(bn\d+)\s*=\s*\{(.+?)\}\s*;",
    re.S,
)
polys = []
for m in node_re.finditer(src):
    body = m.group(2)
    # Flags
    flags_line = body.splitlines()[1].strip().rstrip(",")
    back_view = "BSP_BACK_VIEW" in flags_line
    # Normal
    n = re.search(r"\{\s*(-?\d*\.?\d+(?:[eE][-+]?\d+)?)\s*,\s*"
                  r"(-?\d*\.?\d+(?:[eE][-+]?\d+)?)\s*,\s*"
                  r"(-?\d*\.?\d+(?:[eE][-+]?\d+)?)\s*\}", body)
    normal = (float(n.group(1)), float(n.group(2)), float(n.group(3)))
    # Color (line after normal)
    color_match = re.search(r"\},\s*\n\s*([A-Z_]+)\s*,", body)
    color = COLOR.get(color_match.group(1), 4) if color_match else 4
    # Vertex array name
    av = re.search(r"\b(bv\d+)\b", body)
    verts = arrays[av.group(1)]
    polys.append((color, normal, verts, back_view, m.group(1)))

# Emit Swift
out = []
out.append("// Auto-generated from dstar-1.0/fighter1_bsp.h — do not hand-edit.")
out.append("// Regenerate with tools/parse_fighter.py if the legacy header changes.")
out.append("")
out.append("import simd")
out.append("")
out.append("struct FighterPolygon {")
out.append("    let color: Int16")
out.append("    let normal: SIMD3<Float>")
out.append("    let vertices: [SIMD3<Float>]")
out.append("    /// BSP_BACK_VIEW — render even when viewed from the back side.")
out.append("    let doubleSided: Bool")
out.append("}")
out.append("")
out.append("enum FighterMesh {")
out.append(f"    /// {len(polys)} polygons ported from the legacy fighter1_bsp.h.")
out.append("    static let fighter1: [FighterPolygon] = [")
for color, normal, verts, back_view, name in polys:
    nx, ny, nz = normal
    out.append(f"        // {name}")
    out.append(f"        FighterPolygon(")
    out.append(f"            color: {color},")
    out.append(f"            normal: SIMD3<Float>({nx:g}, {ny:g}, {nz:g}),")
    out.append(f"            vertices: [")
    for vx, vy, vz in verts:
        out.append(f"                SIMD3<Float>({vx:g}, {vy:g}, {vz:g}),")
    out.append(f"            ],")
    out.append(f"            doubleSided: {'true' if back_view else 'false'}")
    out.append(f"        ),")
out.append("    ]")
out.append("}")
print("\n".join(out))
