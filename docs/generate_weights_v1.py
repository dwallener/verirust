#!/usr/bin/env python3
"""
Deterministic weights generator for the verirust transformer_v1 spec.

Outputs:
  - weights_v1.bin  (int16 little-endian, row-major)
  - optional weights_v1_manifest.json

Initialization rule:
  raw(i) = ((i * 17 + 23) mod 251) - 125
  stored_value = int16(raw(i))
  real_value = stored_value / 256.0   # Q8.8 interpretation
"""

from __future__ import annotations
import argparse
import json
import os
import struct
from typing import List, Dict, Any

TENSORS: List[Dict[str, Any]] = [
    {"name": "tok_embedding", "shape": [256, 32]},
    {"name": "pos_embedding", "shape": [16, 32]},
    {"name": "norm1_weight", "shape": [32]},
    {"name": "w_q", "shape": [32, 32]},
    {"name": "w_k", "shape": [32, 32]},
    {"name": "w_v", "shape": [32, 32]},
    {"name": "w_o", "shape": [32, 32]},
    {"name": "norm2_weight", "shape": [32]},
    {"name": "w1", "shape": [32, 64]},
    {"name": "w2", "shape": [64, 32]},
    {"name": "lm_head", "shape": [32, 256]},
]

def numel(shape: List[int]) -> int:
    n = 1
    for d in shape:
        n *= d
    return n

def init_value(global_index: int) -> int:
    # int16 stored value for Q8.8
    return ((global_index * 17 + 23) % 251) - 125

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--outdir", default=".", help="Output directory")
    parser.add_argument("--weights-name", default="weights_v1.bin")
    parser.add_argument("--manifest-name", default="weights_v1_manifest.json")
    parser.add_argument("--no-manifest", action="store_true")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    weights_path = os.path.join(args.outdir, args.weights_name)
    manifest_path = os.path.join(args.outdir, args.manifest_name)

    manifest: Dict[str, Any] = {
        "version": "transformer_v1",
        "binary_dtype": "int16_le",
        "layout": "row_major",
        "frac_bits": 8,
        "tensors": []
    }

    global_index = 0
    byte_offset = 0

    with open(weights_path, "wb") as wf:
        for order, t in enumerate(TENSORS):
            count = numel(t["shape"])
            start = global_index

            for _ in range(count):
                v = init_value(global_index)
                wf.write(struct.pack("<h", v))
                global_index += 1

            end = global_index

            tensor_bytes = count * 2
            manifest["tensors"].append({
                "order": order,
                "name": t["name"],
                "shape": t["shape"],
                "numel": count,
                "byte_offset": byte_offset,
                "byte_length": tensor_bytes,
                "global_index_start": start,
                "global_index_end_exclusive": end
            })
            byte_offset += tensor_bytes

    if not args.no_manifest:
        with open(manifest_path, "w") as mf:
            json.dump(manifest, mf, indent=2)

    print(f"Wrote {weights_path}")
    if not args.no_manifest:
        print(f"Wrote {manifest_path}")

if __name__ == "__main__":
    main()
