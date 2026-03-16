# OpenROAD Flow

This document describes how to run Verirust through the OpenROAD toolchain and
what repo-local glue is still needed for a complete RTL-to-GDS flow.

The intended use here is:

- use the repo's own Yosys scripts for flexible-vs-frozen structural comparison
- use OpenROAD / OpenROAD-flow-scripts (ORFS) for full physical design work:
  synthesis, floorplan, placement, CTS, routing, and final GDS generation

## What OpenROAD should own

For full RTL-to-GDS, OpenROAD-flow-scripts should own the complete flow:

1. RTL ingest
2. logic synthesis
3. floorplan
4. pin placement
5. power grid generation
6. placement
7. clock tree synthesis
8. global routing
9. detailed routing
10. fill / finalization
11. GDS generation
12. signoff reports

The repo-local Yosys wrappers remain useful for fast experiments and
flexible-vs-frozen comparison, but they are not a replacement for the ORFS
physical flow.

## Recommended first platform

For first end-to-end bring-up, use `nangate45` in ORFS.

Reason:

- smallest friction for an initial full flow
- public platform in ORFS
- good for validating the OpenROAD install and repo glue

For a more realistic open PDK flow, use `sky130hd` after the `nangate45`
bring-up works.

## Validate the OpenROAD install first

Before touching Verirust, confirm ORFS itself works with a stock example.

From the OpenROAD-flow-scripts checkout:

```bash
cd /path/to/OpenROAD-flow-scripts/flow
make DESIGN_CONFIG=./designs/nangate45/gcd/config.mk
```

Expected result:

- the flow completes
- final GDS lands under `flow/results/nangate45/gcd/6_final.gds`

If that does not work, the Verirust-specific flow will not be trustworthy.

## Current repo status

Verirust is not yet fully wired into ORFS.

The repo currently has:

- plain-Verilog RTL tops
- bundled liberty files for Yosys mapping experiments
- synthesis-oriented Yosys wrappers

The repo does not yet have ORFS-specific design collateral such as:

- ORFS `config.mk` files
- OpenROAD constraint files (`.sdc`)
- pin-order constraints
- floorplan / PDN Tcl
- export scripts for mapped netlists into an STA/PnR handoff

So the OpenROAD flow is documented here as the intended integration path, but a
small amount of repo glue still needs to be added before `make DESIGN_CONFIG=...`
will work directly for Verirust.

## Recommended Verirust OpenROAD integration layout

Keep the Verirust-specific ORFS collateral in this repo, not only inside the
OpenROAD-flow-scripts checkout.

Recommended layout:

```text
verirust/
  openroad/
    designs/
      nangate45/
        verirust_frozen/
          config.mk
        verirust_flexible/
          config.mk
      sky130hd/
        verirust_frozen/
          config.mk
        verirust_flexible/
          config.mk
    constraints/
      verirust_frozen.sdc
      verirust_flexible.sdc
    pins/
      verirust_frozen.pin_order.cfg
      verirust_flexible.pin_order.cfg
    floorplan/
      verirust_frozen.tcl
      verirust_flexible.tcl
    pdn/
      verirust_frozen.tcl
      verirust_flexible.tcl
```

This keeps Verirust flow control under version control in the design repo.

## Design-entry strategy

There are two viable approaches.

### Approach A: Let ORFS synthesize the RTL

This is the preferred approach for full physical design.

Use:

- source RTL from [`rtl/`](/Users/damir00/Sandbox/verirust/rtl)
- top module:
  - `verirust_frozen`
  - or `verirust_flexible_synth`
- repo-local ORFS `config.mk`
- repo-local `.sdc`

Advantages:

- synthesis, timing assumptions, and physical flow stay consistent
- fewer handoff artifacts
- easier STA and PnR correlation

### Approach B: Export a mapped netlist from the repo-local Yosys flow

This is useful for experiments, but is not the preferred long-term path for
full RTL-to-GDS.

Use this only if you need:

- direct reuse of the repo-local `full` Yosys flow
- fixed mapping to a chosen liberty before handoff

Drawback:

- more glue and more opportunity for flow mismatch

## Minimum files needed before ORFS can run Verirust

For each top/platform pair, the minimum useful set is:

1. `config.mk`
2. `SDC_FILE`
3. a list of RTL files
4. top module name
5. a clock definition
6. rough die/core utilization guidance

For realistic physical convergence, you will also want:

7. pin order constraints
8. floorplan overrides
9. PDN configuration

## Minimal first-pass constraints

The first-pass SDC can be intentionally simple.

At minimum:

- define `clk`
- define a rough clock period
- optionally define conservative input and output delays

Example shape:

```tcl
create_clock -name clk -period 20 [get_ports clk]
set_input_delay 2 -clock clk [all_inputs]
set_output_delay 2 -clock clk [all_outputs]
```

This is only a starting point. Since Verirust is a multi-cycle accelerator-like
design, proper timing and exception modeling will need refinement later.

## Suggested ORFS bring-up order

Bring the flow up in this order.

### 1. Frozen top on `nangate45`

Start with:

- top: `verirust_frozen`
- platform: `nangate45`
- simple SDC
- no custom floorplan Tcl initially unless required

Reason:

- smallest flow surface
- no mutable parameter store block
- easiest candidate for first PnR success

### 2. Frozen top on `sky130hd`

After `nangate45` works:

- switch to `sky130hd`
- refine floorplan, utilization, and pin placement as needed

### 3. Flexible top

Only after the frozen top is stable:

- top: `verirust_flexible_synth`
- same platform bring-up sequence

Reason:

- flexible is structurally much heavier
- it will stress synthesis and physical design harder

## ORFS run commands

The official ORFS pattern is:

```bash
cd /path/to/OpenROAD-flow-scripts/flow
make DESIGN_CONFIG=/absolute/path/to/config.mk
```

For Verirust, once the repo-local ORFS collateral exists, the intended form is:

```bash
cd /path/to/OpenROAD-flow-scripts/flow
make DESIGN_CONFIG=/absolute/path/to/verirust/openroad/designs/nangate45/verirust_frozen/config.mk
```

or:

```bash
cd /path/to/OpenROAD-flow-scripts/flow
make DESIGN_CONFIG=/absolute/path/to/verirust/openroad/designs/sky130hd/verirust_frozen/config.mk
```

Final results from ORFS should land under:

```text
flow/results/<platform>/<design_name>/
```

In particular:

- `6_final.gds`
- DEF / routed database artifacts
- timing and QoR reports

## Stage-by-stage interpretation of the RTL-to-GDS flow

Once the ORFS design config exists, the expected stage progression is:

1. **Synthesis**
   ORFS runs Yosys on the chosen RTL top using the platform library.

2. **Floorplan**
   Define die/core bounds, placement region, rows, and macro-free regioning.

3. **Pin placement**
   Place IO pins. This may need explicit constraints if congestion or long
   routes become a problem.

4. **PDN**
   Generate power and ground grid.

5. **Global placement**
   Place standard cells.

6. **Detailed placement / legalization**
   Clean up placement.

7. **Clock tree synthesis**
   Buffer and distribute `clk`.

8. **Global route**
   Estimate routing resources and congestion.

9. **Detailed route**
   Produce detailed routed geometry.

10. **Final**
   Generate final DEF/GDS and signoff reports.

## Expected first blockers

The most likely Verirust-specific issues during ORFS bring-up are:

- missing or weak SDC
- too-high utilization defaults
- poor IO pin placement
- congestion around the large flexible storage fabric
- clock tree pressure if the control/datapath fanout is high

For the flexible top specifically, expect more work in:

- floorplan tuning
- utilization reduction
- routing congestion cleanup

## What to add next in this repo

The next repo changes needed for OpenROAD are:

1. repo-local ORFS `config.mk` files
2. initial `verirust_frozen.sdc`
3. initial `verirust_flexible.sdc`
4. optional pin-order files
5. optional floorplan / PDN overrides
6. netlist export and OpenSTA handoff scripts

## References

The run model above follows the official OpenROAD/OpenROAD-flow-scripts docs:

- [OpenROAD-flow-scripts getting started](https://openroad-flow-scripts.readthedocs.io/en/latest/index2.html)
- [OpenROAD-flow-scripts variables](https://openroad-flow-scripts.readthedocs.io/en/latest/user/FlowVariables.html)
- [OpenROAD-flow-scripts tutorial](https://openroad-flow-scripts.readthedocs.io/en/latest/tutorials/FlowTutorial.html)
