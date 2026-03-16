#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path("/Users/damir00/Sandbox/verirust")
OUT_DIR = ROOT / "reports" / "yosys" / "modules_lite"


@dataclass(frozen=True)
class ModuleSpec:
    name: str
    files: tuple[str, ...]
    include_generated: bool = False


COMMON_STAGE_FILES = (
    "rtl/verirust_ctrl.v",
    "rtl/verirust_stage_embed_tok.v",
    "rtl/verirust_stage_embed_add.v",
    "rtl/verirust_stage_rmsnorm.v",
    "rtl/verirust_stage_matmul.v",
    "rtl/verirust_stage_score.v",
    "rtl/verirust_stage_softmax.v",
    "rtl/verirust_stage_ctx.v",
    "rtl/verirust_stage_resid.v",
    "rtl/verirust_stage_ffn1.v",
    "rtl/verirust_stage_relu.v",
)


MODULES = (
    ModuleSpec("verirust_stage_embed_tok", ("rtl/verirust_stage_embed_tok.v",)),
    ModuleSpec("verirust_stage_embed_add", ("rtl/verirust_stage_embed_add.v",)),
    ModuleSpec("verirust_stage_rmsnorm", ("rtl/verirust_stage_rmsnorm.v",)),
    ModuleSpec("verirust_stage_matmul", ("rtl/verirust_stage_matmul.v",)),
    ModuleSpec("verirust_stage_score", ("rtl/verirust_stage_score.v",)),
    ModuleSpec("verirust_stage_softmax", ("rtl/verirust_stage_softmax.v",)),
    ModuleSpec("verirust_stage_ctx", ("rtl/verirust_stage_ctx.v",)),
    ModuleSpec("verirust_stage_resid", ("rtl/verirust_stage_resid.v",)),
    ModuleSpec("verirust_stage_ffn1", ("rtl/verirust_stage_ffn1.v",)),
    ModuleSpec("verirust_stage_relu", ("rtl/verirust_stage_relu.v",)),
    ModuleSpec("verirust_ctrl", ("rtl/verirust_ctrl.v",)),
    ModuleSpec("verirust_flexible_store", ("rtl/verirust_flexible_store.v",)),
    ModuleSpec(
        "verirust_flexible_synth",
        COMMON_STAGE_FILES + ("rtl/verirust_flexible_store.v", "rtl/verirust_flexible_synth.v"),
    ),
    ModuleSpec(
        "verirust_frozen",
        COMMON_STAGE_FILES + ("rtl/verirust_frozen.v",),
        include_generated=True,
    ),
)


DEPTH_WEIGHTS = {
    "$not": 1,
    "$logic_not": 1,
    "$and": 1,
    "$or": 1,
    "$xor": 1,
    "$xnor": 1,
    "$reduce_and": 1,
    "$reduce_or": 1,
    "$reduce_xor": 1,
    "$eq": 1,
    "$ne": 1,
    "$lt": 1,
    "$le": 1,
    "$gt": 1,
    "$ge": 1,
    "$mux": 1,
    "$pmux": 2,
    "$add": 2,
    "$sub": 2,
    "$neg": 2,
    "$mul": 3,
    "$div": 4,
    "$mod": 4,
    "$shl": 1,
    "$shr": 1,
    "$sshl": 1,
    "$sshr": 1,
}


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=True)


def heuristic_depth_score(cell_counts: dict[str, int]) -> int:
    score = 0
    for cell_type, weight in DEPTH_WEIGHTS.items():
        if cell_counts.get(cell_type, 0) > 0:
            score += weight
    return score


def sequential_cell_count(cell_counts: dict[str, int]) -> int:
    total = 0
    for cell_type, count in cell_counts.items():
        if cell_type.startswith("$dff") or cell_type.startswith("$sdff") or cell_type.startswith("$adff"):
            total += count
    return total


def combinational_cell_count(cell_counts: dict[str, int]) -> int:
    return sum(cell_counts.values()) - sequential_cell_count(cell_counts)


def classify_cell_types(cell_counts: dict[str, int], module_keys: set[str]) -> tuple[dict[str, int], dict[str, int]]:
    internal: dict[str, int] = {}
    submodules: dict[str, int] = {}
    for cell_type, count in cell_counts.items():
        if cell_type in module_keys or f"\\{cell_type}" in module_keys:
            submodules[cell_type] = count
        else:
            internal[cell_type] = count
    return internal, submodules


def module_rank(summary: dict) -> tuple[int, str]:
    module = summary["module"]
    if module.startswith("verirust_stage_"):
        group = 0
    elif module in {"verirust_ctrl", "verirust_flexible_store"}:
        group = 1
    else:
        group = 2
    return (group, module)


def yosys_command(spec: ModuleSpec, stat_path: Path) -> str:
    include_args = ["-Irtl"]
    if spec.include_generated:
        include_args.append("-Irtl/generated")
    read_cmd = "read_verilog " + " ".join(include_args + list(spec.files))
    return "; ".join(
        [
            read_cmd,
            f"hierarchy -check -top {spec.name}",
            "check -assert",
            "proc",
            "opt",
            "opt_clean",
            f"tee -q -o {stat_path} stat -json -top {spec.name}",
        ]
    )


def parse_warning_count(text: str) -> int:
    warnings = re.findall(r"\bWarning:", text)
    return len(warnings)


def parse_removed_mux_ports(text: str) -> int:
    total = 0
    for match in re.finditer(r"Removed (\d+) multiplexer ports\.", text):
        total += int(match.group(1))
    return total


def parse_removed_cells(text: str) -> int:
    total = 0
    for match in re.finditer(r"Removed a total of (\d+) cells\.", text):
        total += int(match.group(1))
    return total


def analyze_module(spec: ModuleSpec) -> dict:
    stat_path = OUT_DIR / f"{spec.name}.stat.json"
    log_path = OUT_DIR / f"{spec.name}.log"
    cmd = ["yosys", "-p", yosys_command(spec, stat_path)]
    proc = run(cmd)
    log_path.write_text(proc.stdout)

    stat_data = json.loads(stat_path.read_text())
    module_key = f"\\{spec.name}"
    module_stats = stat_data["modules"][module_key]
    cell_counts = module_stats.get("num_cells_by_type", {})
    module_keys = set(stat_data["modules"].keys())
    internal_cells, submodule_cells = classify_cell_types(cell_counts, module_keys)

    summary = {
        "module": spec.name,
        "files": list(spec.files),
        "log": str(log_path),
        "stat_json": str(stat_path),
        "stats": module_stats,
        "derived": {
            "internal_sequential_cells": sequential_cell_count(internal_cells),
            "internal_combinational_cells": combinational_cell_count(internal_cells),
            "internal_rough_depth_score": heuristic_depth_score(internal_cells),
            "warnings": parse_warning_count(proc.stdout),
            "removed_mux_ports": parse_removed_mux_ports(proc.stdout),
            "removed_cells": parse_removed_cells(proc.stdout),
        },
        "internal_cells_by_type": internal_cells,
        "submodule_instances_by_type": submodule_cells,
    }
    return summary


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    run(["cargo", "run", "--bin", "generate_frozen_rtl"])

    summaries = []
    for spec in MODULES:
        summaries.append(analyze_module(spec))
    summaries.sort(key=module_rank)

    combined = {
        "analysis": "lite",
        "note": "internal_rough_depth_score is a heuristic based on reduced Yosys builtin cell types after proc/opt/opt_clean; it is not a timing report",
        "ordering": "bottom-up: leaf stage modules first, then storage/control, then tops",
        "modules": summaries,
    }

    summary_path = OUT_DIR / "summary.json"
    summary_path.write_text(json.dumps(combined, indent=2))

    print(f"Wrote {summary_path}")
    print()
    print("Module summary:")
    for item in summaries:
        stats = item["stats"]
        derived = item["derived"]
        print(
            f"{item['module']}: cells={stats['num_cells']}, "
            f"internal_comb={derived['internal_combinational_cells']}, "
            f"internal_seq={derived['internal_sequential_cells']}, "
            f"depth~={derived['internal_rough_depth_score']}, "
            f"submods={stats['num_submodules']}, mux_ports_removed={derived['removed_mux_ports']}"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
