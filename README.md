# Verirust

Verirust is an experiment in building the same small transformer inference core
twice:

- a Rust reference implementation
- a plain-Verilog RTL implementation

The current RTL focus is synthesis structure and flexible-vs-frozen comparison:

- `flexible`: weights and LUTs live in RAM-like mutable storage
- `frozen`: weights and LUTs are compiled into ROM-like constant logic

Both RTL tops are intended to share the same controller, stage structure, and
math. The conceptual difference is storage, not algorithm.

## Repo layout

- [`docs/OVERVIEW.md`](/Users/damir00/Sandbox/verirust/docs/OVERVIEW.md): main project overview and synthesis flow
- [`docs/MICROARCHITECTURE.md`](/Users/damir00/Sandbox/verirust/docs/MICROARCHITECTURE.md): RTL architecture notes
- [`docs/OPENROAD.md`](/Users/damir00/Sandbox/verirust/docs/OPENROAD.md): OpenROAD / ORFS runbook and RTL-to-GDS integration plan
- [`spec/model_spec.json`](/Users/damir00/Sandbox/verirust/spec/model_spec.json): machine-readable model spec
- [`src/`](/Users/damir00/Sandbox/verirust/src): Rust reference and generators
- [`rtl/`](/Users/damir00/Sandbox/verirust/rtl): synthesizable Verilog
- [`scripts/`](/Users/damir00/Sandbox/verirust/scripts): elaboration and synthesis entry points
- [`synth/lib/`](/Users/damir00/Sandbox/verirust/synth/lib): bundled liberty files for mapped runs

## Prerequisites

Expected tools:

- `cargo`
- `yosys`

Optional but useful:

- `verilator`
- `opensta` (not wired yet)
- full OpenROAD / OpenROAD-flow-scripts install for RTL-to-GDS work

## Rust reference

Build and run the canonical reference dump:

```bash
cargo check
cargo run --bin dump_reference
```

This generates canonical test input and checkpoints under:

- [`tests/input_000.bin`](/Users/damir00/Sandbox/verirust/tests/input_000.bin)
- [`tests/checkpoints_000/`](/Users/damir00/Sandbox/verirust/tests/checkpoints_000)

Generate frozen RTL constants from canonical weights and LUTs:

```bash
cargo run --bin generate_frozen_rtl
```

## RTL tops

Main synthesizable tops:

- `verirust_flexible_synth`
- `verirust_frozen`

Both are plain Verilog multi-cycle designs. They do not attempt single-cycle
whole-model evaluation.

## First commands to run

If you just pulled the repo on a fresh machine, start here:

```bash
./scripts/elab_flexible.sh
./scripts/elab_frozen.sh
./scripts/synth_frozen.sh lite
./scripts/synth_flexible.sh lite
```

That gives you:

- elaboration sanity for both tops
- a fast synthesis-side reduction sanity check

## Synthesis entry points

Per-design:

```bash
./scripts/synth_flexible.sh [lite|quick|full] [nangate|sky130|plain]
./scripts/synth_frozen.sh [lite|quick|full] [nangate|sky130|plain]
```

Comparison:

```bash
./scripts/compare_synth.sh [lite|quick|full] [nangate|sky130|plain]
```

Modes:

- `lite`: fastest rough reduction pass
- `quick`: heavier structural lowering
- `full`: includes `abc` mapping; can use a bundled liberty

Libraries for `full`:

- `nangate`
- `sky130`
- `plain` for `abc` without a liberty

Bundled liberty files:

- [`NangateOpenCellLibrary_typical.lib`](/Users/damir00/Sandbox/verirust/synth/lib/NangateOpenCellLibrary_typical.lib)
- [`sky130_fd_sc_hd__tt_025C_1v80.lib`](/Users/damir00/Sandbox/verirust/synth/lib/sky130_fd_sc_hd__tt_025C_1v80.lib)

Examples:

```bash
./scripts/synth_frozen.sh quick
./scripts/synth_flexible.sh full nangate
./scripts/synth_frozen.sh full sky130
./scripts/compare_synth.sh quick
```

## Reports and logs

Yosys outputs land under:

- [`reports/yosys/`](/Users/damir00/Sandbox/verirust/reports/yosys)

Useful files:

- `*_lite.log`
- `*_quick.log`
- `*_full.log`
- `reports/yosys/modules_lite/summary.json`

Per-module rough analysis:

```bash
./scripts/analyze_modules_lite.sh
```

This produces a bottom-up JSON summary of leaf modules, storage/control, and
tops.

## OpenROAD / RTL-to-GDS

If you are using a machine with the full OpenROAD package, read:

- [`docs/OPENROAD.md`](/Users/damir00/Sandbox/verirust/docs/OPENROAD.md)

That document covers:

- validating the OpenROAD install
- how to run logic synthesis under ORFS
- the intended Verirust RTL-to-GDS bring-up order
- the repo-local glue files still needed for a complete ORFS integration

## Current status

- Rust reference exists
- frozen-constant generation exists
- flexible and frozen RTL elaborate in Yosys
- `lite`, `quick`, and `full` synthesis flows exist
- bundled Nangate and Sky130 liberties are available for mapped `full` runs

Still pending:

- RTL-vs-Rust functional comparison
- proper STA flow

## More detail

For the actual architectural and spec details, read:

- [`docs/OVERVIEW.md`](/Users/damir00/Sandbox/verirust/docs/OVERVIEW.md)
- [`docs/MICROARCHITECTURE.md`](/Users/damir00/Sandbox/verirust/docs/MICROARCHITECTURE.md)
- [`docs/OPENROAD.md`](/Users/damir00/Sandbox/verirust/docs/OPENROAD.md)
