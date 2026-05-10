# rdma_dma_engine Standalone Synthesis Report

Date: 2026-05-10
Revision: `rdma_dma_engine_standalone`
Top: `rdma_dma_engine_standalone_top`

## Status

Phase D standalone synthesis closure is PASS for timing and resources.

The standalone project uses a synthesizable harness that drives OPQ input,
issues aligned two-segment jobs, completes AXI4 writes, and reduces DUT
outputs into a `signature[31:0]` output. This keeps the IP logic live without
charging thousands of virtual-pin adapters to the IP resource budget.

Gate-level DV was not run in this RTL-only handoff. The UVM environment is
owned by the sibling DV task, so this report closes standalone synthesis,
static screen, timing, and resources only.

## Target

| Item | Value |
|---|---|
| Quartus project | `syn/quartus/rdma_dma_engine_standalone.qsf` |
| Family | Arria 10 |
| QSF device assignment | `set_global_assignment -name DEVICE 10AX115N2F45E1SG` |
| Quartus version | 18.1.0 Build 625 Standard Edition |
| Production target | 250 MHz |
| Standalone sign-off clock | 275 MHz |
| Standalone period | 3.636 ns |
| Required setup margin | 0.364 ns |
| Fitter effort | Standard Fit |
| Seed policy | Single fixed seed, no seed scan |

## Pre-Fit Model

Expected resource owners:

| Block | Expected implementation |
|---|---|
| `rdma_dma_packer.sv` | Registers for 8x32b packing, byte count, EOE state, and DEBUG2 mask tie-off |
| `rdma_dma_data_fifo.sv` | One 256-deep FIFO storing payload plus sideband, expected to map to M20K blocks |
| `rdma_dma_writer.sv` | FSM state, two segment descriptors, address and byte counters, burst sizing, WSTRB generation, and completion status |
| `rdma_dma_engine.sv` | Top-level handshake, flush glue, counters, and debug tap muxing |

Predicted timing bottleneck: writer-side segment arithmetic and AXI burst
sizing, because AW issue used FIFO level, remaining segment bytes, and max
burst constraints in the same cycle.

## Iteration Notes

The first successful all-port wrapper build overcounted resources and missed
the required margin:

| Iteration | ALMs | M20K | DSP | Worst setup slack | Result |
|---|---:|---:|---:|---:|---|
| All-port virtual-pin wrapper | 2,391 | 9 | 0 | 0.205 ns | FAIL margin and ALM band |
| Synthesizable harness plus burst-size fix | 1,277 | 9 | 0 | 0.496 ns | PASS |

Root cause of the first timing shortfall was the same-cycle 64-bit
`(bytes_left + 31) >> 5` burst-sizing cone feeding `aw_beats` and
`beats_remaining`. The writer now caps bursts with a 512-byte threshold and
low-bit segment count, preserving the 4 KB-aligned, 4 KB-multiple segment
contract while removing the wide add from AW issue.

Root cause of the first resource overcount was the standalone wrapper, not the
IP datapath. Thousands of AXI/DEBUG interface bits were preserved as
top-level virtual-pin adapters, and the replacement harness keeps the DUT live
with a small source, sink, and signature reducer.

## Static Screen

Command:

```sh
python3 ~/.codex/skills/rtl-linter-and-checker/scripts/questa_static_screen.py \
  --top rdma_dma_engine_standalone_top \
  --filelist syn/quartus/rdma_dma_engine_standalone_static.f
```

Evidence:

| Check | Result | Evidence path |
|---|---:|---|
| Lint errors | 0 | `.questa_static_screen/timing_patch/qv_timing_patch/qverify_db/lint.rpt` |
| CDC violations | 0 | `.questa_static_screen/timing_patch/qv_timing_patch/reports/cdc.rpt` |
| RDC violations | 0 | `.questa_static_screen/timing_patch/qv_timing_patch/qverify_db/rdc.rpt` |

## Quartus Evidence

Command:

```sh
quartus_sh --flow compile rdma_dma_engine_standalone -c rdma_dma_engine_standalone
```

Evidence paths:

| Artifact | Path |
|---|---|
| Flow report | `syn/quartus/output_files/rdma_dma_engine_standalone/rdma_dma_engine_standalone.flow.rpt` |
| Fitter summary | `syn/quartus/output_files/rdma_dma_engine_standalone/rdma_dma_engine_standalone.fit.summary` |
| STA report | `syn/quartus/output_files/rdma_dma_engine_standalone/rdma_dma_engine_standalone.sta.rpt` |

Fitter status: Successful, 2026-05-10 17:25:31.

## Resources

Acceptance uses the stricter user-brief band from `RTL_PLAN.md`:
`[-20%, +50%]` around the estimate.

| Resource | Estimate | Acceptance band | Actual | Status |
|---|---:|---:|---:|---|
| ALMs | 1,100 | 880 to 1,650 | 1,277 | PASS |
| M20K blocks | 7 | 6 to 11 | 9 | PASS |
| DSP blocks | 0 | 0 only | 0 | PASS |

Additional fitter totals:

| Resource | Actual |
|---|---:|
| Registers | 2,667 |
| Block memory bits | 83,712 |
| Virtual pins | 34 |
| Pins | 0 |

## Timing

The standalone clock is constrained at 3.636 ns for 275 MHz. Required setup
margin is at least 10% of that period: 0.364 ns.

| Corner | Setup slack | Hold slack | TNS | Status |
|---|---:|---:|---:|---|
| Slow 900mV 100C | 0.496 ns | 0.050 ns | 0.000 ns | PASS |
| Slow 900mV 0C | 0.502 ns | 0.047 ns | 0.000 ns | PASS |
| Fast 900mV 100C | 1.465 ns | 0.021 ns | 0.000 ns | PASS |
| Fast 900mV 0C | 1.748 ns | 0.018 ns | 0.000 ns | PASS |
| Multicorner worst case | 0.496 ns | 0.018 ns | 0.000 ns | PASS |

Margin check:

```text
Worst setup slack = 0.496 ns
Required margin   = 0.364 ns
Excess margin     = 0.132 ns
Worst hold slack  = 0.018 ns
```

No timing relax, resource-band relax, or seed scan was used.
