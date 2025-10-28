#!/usr/bin/env python3
"""
Simple OBJ post-processor that adds face normals.

Gazebo (particularly the DART engine) requires meshes to provide normals.
OSM2World does not emit them when exporting OBJ, so we synthesise one
normal per triangular face and rewrite the OBJ indices accordingly.
"""

import math
import sys
from pathlib import Path


def normalize(vec):
    x, y, z = vec
    length = math.sqrt(x * x + y * y + z * z)
    if length == 0.0:
        return (0.0, 1.0, 0.0)
    return (x / length, y / length, z / length)


def face_normal(v1, v2, v3):
    ax, ay, az = v2[0] - v1[0], v2[1] - v1[1], v2[2] - v1[2]
    bx, by, bz = v3[0] - v1[0], v3[1] - v1[1], v3[2] - v1[2]
    nx = ay * bz - az * by
    ny = az * bx - ax * bz
    nz = ax * by - ay * bx
    return normalize((nx, ny, nz))


def parse_vertex_index(token, total_vertices):
    idx = int(token)
    if idx < 0:
        idx = total_vertices + 1 + idx
    return idx - 1


def process(input_path, output_path):
    vertices = []
    normals_written = 0

    with open(input_path, "r", encoding="utf-8") as src, open(output_path, "w", encoding="utf-8") as dst:
        for raw_line in src:
            line = raw_line.rstrip("\n")

            if line.startswith("v "):
                parts = line.split()
                vertices.append(tuple(float(v) for v in parts[1:4]))
                dst.write(raw_line)
                continue

            if line.startswith("f "):
                parts = line.split()
                if len(parts) != 4:
                    raise ValueError(f"Only triangular faces are supported (got: {line})")

                vertex_indices = [
                    parse_vertex_index(token.split("/")[0], len(vertices))
                    for token in parts[1:4]
                ]
                v1, v2, v3 = [vertices[idx] for idx in vertex_indices]
                nx, ny, nz = face_normal(v1, v2, v3)
                normals_written += 1
                dst.write(f"vn {nx:.6f} {ny:.6f} {nz:.6f}\n")

                rewritten_tokens = []
                for token in parts[1:4]:
                    components = token.split("/")
                    v_comp = components[0] if components and components[0] else ""
                    vt_comp = ""
                    if len(components) > 1 and components[1]:
                        vt_comp = f"/{components[1]}"
                    rewritten_tokens.append(f"{v_comp}{vt_comp}/{normals_written}")

                dst.write("f " + " ".join(rewritten_tokens) + "\n")
                continue

            dst.write(raw_line)

    return normals_written


def main():
    if len(sys.argv) != 3:
        print("Usage: add_obj_normals.py <input.obj> <output.obj>")
        return 1

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    if not input_path.exists():
        print(f"Input file not found: {input_path}", file=sys.stderr)
        return 1

    normals = process(input_path, output_path)
    print(f"Generated {normals} normals for {input_path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
