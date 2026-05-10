# DV Harness — rdma_dma_engine UVM Environment (dual DEBUG=1/2)

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**DUT:** `rdma_dma_engine` (`rtl/rdma_dma_engine.sv`)
**Simulator:** QuestaOne 2026.1 (`/data1/questaone_sim-2026.1_1`)
**Author:** Yifeng Wang (yifenwan@phys.ethz.ch)
**Date:** 2026-05-10

This document specifies the dual-UVM environment that realizes the
DEBUG_LEVEL=1 (synthesizable + observability) and DEBUG_LEVEL=2 (sim-only
sidecar lineage) sibling builds. The bucket names, interface list
(`DV_PLAN.md` §2), verification targets (`DV_PLAN.md` §3), and contract
anchors are the source of truth and are not restated here.

The dual-env contract is the **HARD REQUIREMENT** of this harness. It
follows `~/.codex/skills/dv-workflow/SKILL.md`, "Harness rules" §6 and
the OoO-datapath section: "treat payload correctness and debug lineage as
separate but correlated evidence". Both envs run as siblings in a single
regression. A single shared scoreboard cross-validates DEBUG=2 lineage
against DEBUG=1 functional payload; disagreement is a closure blocker.

The reference for the dual-monitor pattern is
`mu3e-ip-cores/ring-buffer_cam/tb/uvm/`:
`hit_monitor.sv` + `out_monitor.sv` (payload) and `debug_monitor.sv`
(internal taps) all feed one `scoreboard.sv`. We adopt the same shape.

---

## 1. Overview

```
+-----------------------------------------------------------------------+
|                  rdma_dma_engine_regression                            |
|                                                                       |
|  +---------------------------+  +-----------------------------+        |
|  | rdma_dma_engine_env_dbg1   |  | rdma_dma_engine_env_dbg2     |        |
|  | (DEBUG_LEVEL=1)           |  | (DEBUG_LEVEL=2, sim-only)   |        |
|  |                           |  |                             |        |
|  |  + opq_axis_drv           |  |  + opq_axis_drv             |        |
|  |  + job_drv                |  |  + job_drv                  |        |
|  |  + axi_completer          |  |  + axi_completer            |        |
|  |  + payload_monitor        |  |  + payload_monitor          |        |
|  |  + dbg1_taps_monitor      |  |  + dbg1_taps_monitor        |        |
|  |    (FIFO level, AW/W/B    |  |  + dbg2_lineage_monitor     |        |
|  |     in-flight, halt cnt,  |  |    (per-hit sidecar at      |        |
|  |     packer slot, FSM      |  |     ingress and writer-emit |        |
|  |     state)                |  |     shadow port)            |        |
|  +-------------+-------------+  +--------------+--------------+        |
|                |                               |                       |
|                v                               v                       |
|  +-----------------------------------------------------------------+  |
|  |          rdma_dma_engine_shared_scoreboard                       |  |
|  |  - reference packer model (32->256 MSB-first slot accumulator)  |  |
|  |  - host buffer shadow (per (seg0,seg1) span)                    |  |
|  |  - status-bit predictor (EOE, FULL, SEG_BOUNDARY_HIT, ...)      |  |
|  |  - conservation tracker (cnt_input_w*4 == bytes_written + halt) |  |
|  |  - per-event ts predictor (first/last/event_count)              |  |
|  |  - DEBUG=1 fill-level vs functional payload cross-check         |  |
|  |  - DEBUG=2 lineage cross-check (ingress sidecar == writer-emit  |  |
|  |    shadow per (lane, hit_id, source_ts, sequence_no))           |  |
|  |  - dual-build residual reporter (nominal vs lineage residuals   |  |
|  |    side by side; disagreement -> closure blocker)               |  |
|  +-----------------------------------------------------------------+  |
+-----------------------------------------------------------------------+
                                ^
                                |
                       clk (250 MHz default)
                       reset_n (sync, active low)
```

Each env is instantiated under its own `tb_top_dbg1.sv` /
`tb_top_dbg2.sv`. Both envs use the **same** UVM env class
(`rdma_dma_engine_env`) parameterized by a `cfg.debug_level` value of
`1` or `2`; the env enables/disables the lineage monitor accordingly.
A regression-level `rdma_dma_engine_dual_test` chains the two envs in
one `vsim` invocation so they share the same wallclock (separate UCDBs,
shared scoreboard analysis ports).

The shared scoreboard is built as a single instance under a top
`rdma_dma_engine_dual_env` that owns one DEBUG=1 sub-env and one DEBUG=2
sub-env; each sub-env's monitors connect their analysis ports to the
shared scoreboard's typed analysis-imps. This matches the rbcam
single-scoreboard / multi-monitor pattern.

---

## 2. Directory Layout

All paths are relative to `tb/uvm/`:

```
tb/uvm/
  Makefile                                  # vsim QuestaOne 2026.1 flow
  tb_top_dbg1.sv                            # DUT @ DEBUG_LEVEL=1
  tb_top_dbg2.sv                            # DUT @ DEBUG_LEVEL=2
  rdma_dma_engine_dut_wrapper.sv             # DUT instance with parameter overrides
  rdma_dma_engine_pkg.sv                     # transactions, cfg, util types
  ifs/
    opq_axis_if.sv                          # AXI4-Stream sink (36b tdata)
    opq_axis_dbg2_if.sv                     # AXI4-Stream sink + sidecar (DEBUG=2)
    axi4_master_if.sv                       # AXI4 master AW/W/B view
    axi4_master_dbg2_if.sv                  # AW/W/B + writer-shadow sidecar (DEBUG=2)
    job_if.sv                               # job_req + done + report fields
    sideband_cnt_if.sv                      # 4 x 32b cnt_* observation
    dbg1_taps_if.sv                         # FIFO level / FSM / in-flight (DEBUG=1)
  agents/
    opq_axis_agent.sv                       # active driver on AXI4-Stream sink
    opq_axis_driver.sv
    opq_axis_monitor.sv                     # payload monitor (DEBUG=0/1/2 all)
    opq_axis_dbg2_monitor.sv                # sidecar lineage monitor (DEBUG=2)
    opq_axis_sequencer.sv
    opq_axis_txn.sv                         # base txn (payload + optional sidecar)
    job_agent.sv
    job_driver.sv
    job_monitor.sv
    job_sequencer.sv
    job_txn.sv
    axi_completer_agent.sv                  # AXI4 completer (driver + monitor)
    axi_completer_driver.sv
    axi_completer_monitor.sv                # payload monitor
    axi_completer_dbg2_monitor.sv           # writer-shadow sidecar monitor (DEBUG=2)
    axi_completer_sequencer.sv
    axi_completer_txn.sv
    dbg1_taps_monitor.sv                    # observation-only monitor (DEBUG=1+)
  scoreboard/
    rdma_dma_engine_scoreboard.sv            # central scoreboard (shared by dbg1/dbg2)
    ref_packer.sv                           # 32->256 reference model
    ref_writer_fsm.sv                       # job-level FSM reference
    host_buffer_shadow.sv                   # per-job host DRAM shadow
    dbg1_invariant_checker.sv               # DEBUG=1 fill-level / in-flight invariants
    dbg2_lineage_matcher.sv                 # DEBUG=2 ingress-vs-emit lineage matcher
  coverage/
    cov_job.sv
    cov_axi_burst.sv
    cov_packer.sv
    cov_fifo.sv
    cov_status_cross.sv
    cov_throughput.sv
    cov_reset.sv
    cov_dbg2_lineage.sv                     # DEBUG=2 lineage covergroup
  sva/
    sva_axis_opq.sv
    sva_axi4_master.sv
    sva_job.sv
    sva_packer.sv
    sva_fifo.sv
    sva_writer_fsm.sv
    sva_dbg1_taps.sv                        # DEBUG=1 taps consistency
    sva_dbg2_sidecar.sv                     # DEBUG=2 sidecar conservation
  base_test/
    rdma_dma_engine_base_test.sv             # all isolated tests extend this
    rdma_dma_engine_dual_test.sv             # dual-env regression entrypoint
    rdma_dma_engine_env.sv                   # uvm_env: one debug-level instance
    rdma_dma_engine_dual_env.sv              # owns dbg1 + dbg2 sub-envs + shared scb
    rdma_dma_engine_env_cfg.sv               # cfg: debug_level, latency, sizes
    rdma_dma_engine_env_pkg.sv               # env package
  tests/
    basic/
      B001_smoke_single_job_eoe.sv
      ... (one .sv per case in DV_BASIC.md)
    edge/
      E001_*.sv ...
    prof/
      P001_*.sv ...
    error/
      X001_*.sv ...
    cross/
      bucket_frame_basic.sv
      bucket_frame_edge.sv
      bucket_frame_prof.sv
      bucket_frame_error.sv
      all_buckets_frame.sv
  sequences/
    opq_axis_sequences.sv
    job_sequences.sv
    axi_completer_sequences.sv
```

`tb/uvm/Makefile` provides the standard targets (per Mu3e house Makefile
template):

- `make compile-dbg1` / `make compile-dbg2` — `vlog`/`vcom` of DUT +
  harness with `+define+DUT_DEBUG_LEVEL=1` or `=2`
- `make run-dbg1 TEST=B001_smoke_single_job_eoe` — one isolated case @ DEBUG=1
- `make run-dbg2 TEST=B001_smoke_single_job_eoe` — same case @ DEBUG=2
- `make regress-dual` — both DEBUG=1 and DEBUG=2 envs in one `vsim` via
  `rdma_dma_engine_dual_test`, sharing the scoreboard and reporting
  cross-build residuals
- `make bucket_frame BUCKET=BASIC DEBUG=1` — all BASIC cases @ DEBUG=1
- `make bucket_frame BUCKET=BASIC DEBUG=2` — same @ DEBUG=2
- `make all_buckets_frame DEBUG=1` / `DEBUG=2`
- `make cov_merge` — merge per-case UCDBs into per-bucket UCDBs and
  per-debug-level signoff UCDBs

---

## 3. Agents

### 3.1 `opq_axis_agent` (AXI4-Stream source on OPQ side)

**Role:** drives `s_axis_opq.tdata`, `tvalid`, `tlast`, `tuser`. Monitors
`tready`. Phase 1 expects `tready` tied 1; Phase 2 may add backpressure.

**DEBUG=2 extension:** when the env cfg requests DEBUG=2, the agent
additionally drives a `dbg2_meta_*` sidecar conduit carrying
`(lane, hit_id, source_ts, sequence_no)` per accepted 32 b OPQ beat.
The driver deterministically generates `hit_id` (monotone per agent),
`sequence_no` (monotone per drain), `source_ts` (running cycle counter
captured at the OPQ-bus interface), and `lane` (deterministic round-
robin across a configurable lane count, default 1). The driver guarantees
the sidecar is **inert** when DEBUG=1 (driven to `'0`).

**Sequences:**

- `seq_opq_axis_event_clean` — directed: emits a single OPQ event of
  `N` 32-bit beats with proper SOP/EOP framing
- `seq_opq_axis_burst_random` — random: bursts of `N` events, each of
  size in [1, 256] beats, with random gap between events
- `seq_opq_axis_full_load` — sustained 100 % `tvalid` rate, used by
  PROF cases
- `seq_opq_axis_idle_for` — drives `tvalid = 0` for `M` cycles
- `seq_opq_axis_lineage_walk` — DEBUG=2 only: emits a known
  `(lane, hit_id, source_ts, sequence_no)` walk pattern that the
  scoreboard expects to see emerge byte-for-byte at the writer-shadow
  port

### 3.2 `job_agent` (run_manager-side stimulus + done consumer)

**Role:** drives `job_req` plus all `job_seg{0,1}_*`, `job_sqe_id`,
`job_opcode` inputs. Monitors `job_done` and the report-back fields,
forwards each completion as a UVM transaction to the scoreboard. Holds
`job_req` for one cycle (per the simple req/done handshake; the engine
must latch the parameters when it sees the rising edge).

**Sequences:**

- `seq_job_single_segment_drain` — directed: `seg0_addr/span` non-zero,
  `seg1 = 0`, opcode `DRAIN_UNTIL_EOE`
- `seq_job_two_segment_drain` — directed: both segments programmed
- `seq_job_align_err_seg0_addr` — directed: `seg0_addr & 0xFFF != 0`
- `seq_job_align_err_seg0_span` — directed: `seg0_span & 0xFFF != 0`
- `seq_job_back_to_back` — random: 100 jobs queued one after another
- `seq_job_concurrent_with_opq` — random: jobs and OPQ traffic
  interleaved with random gaps

### 3.3 `axi_completer_agent` (AXI4 master completer)

**Role:** sits on the host-DRAM side. Asserts `m_axi_awready`,
`m_axi_wready` on a programmable latency profile. Issues `m_axi_bvalid`
with a programmable BRESP (default OKAY) at a programmable delay after
the last W beat of each burst. Captures every W beat into a host
buffer shadow keyed by `m_axi_awaddr` (latched per AW handshake) and
forwards it to the scoreboard.

**DEBUG=2 extension:** the AXI completer monitor additionally taps the
DUT's writer-shadow sidecar port (`dbg2_writer_meta_*`) which exposes,
per accepted W beat, the per-32 b-slot `(lane, hit_id, source_ts,
sequence_no)` that the writer is emitting. This is forwarded to the
scoreboard's `dbg2_lineage_matcher`. The shadow port is a synthesizable-
build no-op; in DEBUG=2 it carries the live sidecar.

**Sequences:**

- `seq_axi_compl_zero_latency` — `awready` and `wready` always 1, B
  one cycle after `wlast`
- `seq_axi_compl_throttle_uniform` — constant N-cycle ready gaps
- `seq_axi_compl_throttle_random` — random ready gaps, used by PROF
- `seq_axi_compl_bvalid_late` — late BVALID (up to `T_BVALID_MAX` cycles
  after wlast); used by EDGE cases that test FIFO-backpressure absorb
- `seq_axi_compl_slverr_on_bresp` — issue `bresp = 2'b10` (SLVERR) on
  the next B; used by ERROR cases

### 3.4 `dbg1_taps_monitor` (DEBUG=1+ observation only)

**Role:** passive monitor. Samples `dbg1_*` taps on every cycle:

- `dbg1_fifo_level[$clog2(FIFO_DEPTH+1)-1:0]`
- `dbg1_fifo_almost_full`
- `dbg1_aw_inflight[3:0]`, `dbg1_w_beats_remaining[7:0]`,
  `dbg1_b_outstanding[3:0]`
- `dbg1_packer_slot_idx[3:0]`, `dbg1_packer_pending_eoe`
- `dbg1_writer_state[2:0]`
- `dbg1_halt_pulse`

Forwards a per-cycle observation transaction (sampled on the rising
edge of `clk` after reset deasserts) to the scoreboard's
`dbg1_invariant_checker`.

### 3.5 `opq_axis_dbg2_monitor` and `axi_completer_dbg2_monitor` (DEBUG=2 only)

**Role:** passive monitors that capture the DEBUG=2 lineage sidecar at
the **ingress** of the DUT (per accepted OPQ beat) and at the
**egress** writer-shadow port (per emitted W-beat slot). The lineage
matcher in the scoreboard pairs every ingress entry with exactly one
egress entry by `(sequence_no, hit_id)` key and asserts identity on the
remaining sidecar fields. Drops, duplicates, and reorders are flagged
immediately.

---

## 4. Reference Models

### 4.1 `ref_packer` — 32→256 reference

Mirrors `swb_rdma_dma_packer.sv` semantics. State: 256-bit accumulator,
4-bit slot index, pending-EOE flag. On each accepted OPQ beat, shifts
data into `accum[slot_idx*32 +: 32]`, increments slot. When slot reaches
8, emits one 256-bit beat with `last_in_event = pending_eoe | this_eop`,
`bytes_in_word = 32`. On EOE with non-zero slot but no accept this
cycle, flushes a partial line with zero-padded empty slots and
`bytes_in_word = slot_idx * 4`.

The scoreboard uses this to predict the exact 256-bit beats the writer
will see.

### 4.2 `ref_writer_fsm` — job-level FSM reference

Mirrors `WR_IDLE → WR_PROGRAM → WR_AW → WR_W → WR_B → ...` with the
2-segment scatter logic. Drives:

- predicted `awaddr`, `awlen`, `awsize`, `awburst` per AW
- predicted W-beat sequence (matches `ref_packer` output)
- predicted `bytes_written` per segment, total
- predicted status bits at job_done

### 4.3 `host_buffer_shadow` — per-job DRAM model

Two byte arrays sized `seg0_span` and `seg1_span`. Initialized to a
distinguishable poison pattern (e.g. `0xCD`) per reset. On each AXI4 W
beat captured by the `axi_completer_monitor`, writes the 32 B (256 b)
word at `awaddr_running + beat_offset` into the byte array, applying
`wstrb` masking. After job_done, the shadow is compared byte-by-byte
against the `ref_packer` predicted byte stream truncated at the
predicted `bytes_written`.

### 4.4 `event_ts_predictor`

Captures the simulation cycle counter at every observed `s_axis_opq.tlast`.
Predicts `first_event_ts = ts of first tlast`, `last_event_ts = ts of
last tlast in this drain`, `event_count = # of tlast in drain`. The
RTL is expected to use the same OPQ-side cycle counter (passed via
packer sideband to writer); scoreboard checks the report field equality.

### 4.5 `dbg1_invariant_checker` (DEBUG=1+)

Per-cycle invariants on the observation taps:

- `dbg1_fifo_level <= FIFO_DEPTH`
- `dbg1_fifo_almost_full == (dbg1_fifo_level >= ALMOST_FULL_TH)`
- `dbg1_aw_inflight == (# of AW handshakes - # of B handshakes)` and
  `dbg1_b_outstanding == # of completed AWs awaiting B`
- `dbg1_w_beats_remaining` decrements 1 per W handshake and reloads
  to `awlen+1` on each AW handshake
- `dbg1_writer_state` consistent with the FSM transition rules
- `dbg1_halt_pulse` pulses iff packer drops a beat (cross-checked
  against `cnt_halt` delta)

### 4.6 `dbg2_lineage_matcher` (DEBUG=2 only)

Maintains an in-order queue of `(sequence_no, hit_id)` keys captured at
the ingress sidecar monitor. For each writer-shadow emit, pops the
expected key (head of queue) and asserts:

- `(lane, source_ts)` match
- `sequence_no` and `hit_id` match
- emit-order matches ingress-order (no reorder; engine is FIFO by
  construction)
- after EOE-pad zero-padded slots, the lineage queue is allowed to
  carry "padding" sentinel entries so the matcher can verify that
  zero-padded slots map to padding rather than to swallowed data
- the residual count (ingress - emit) equals 0 at job_done unless
  `cnt_halt > 0`, in which case the residual equals `cnt_halt` and is
  recorded as the dropped-beats lineage (witnessed by `dbg1_halt_pulse`
  cross-checks)

This matcher is the closure-blocker source for the dual-env regression.

### 4.7 Cross-build residual reporter

The shared scoreboard publishes, per job and per regression, a side-by-
side residual table:

| residual | DEBUG=1 build | DEBUG=2 build |
|---|---|---|
| input bytes accepted | sum of cnt_input_w * 4 | sum of cnt_input_w * 4 |
| bytes written to host | sum of W-beats * (32 - pad bytes) | same |
| halt bytes | sum of cnt_halt * 4 | same |
| ingress sidecar entries | n/a | sum |
| writer-emit sidecar entries | n/a | sum |
| lineage residual | n/a | ingress - emit (must == cnt_halt) |
| nominal residual | input - written - halt (must == 0) | same |

Any non-zero "must == 0" cell is a closure blocker and is recorded as
a `BUG_HISTORY.md` entry with full context.

---

## 5. Assertions (SVA)

Each binding is a separate `bind` to keep modular control. All
assertions are checked on every cycle of every test.

### 5.1 `sva_axis_opq`

- `tvalid` once asserted holds with `tdata` stable until `tready`
- `tlast` asserted only when `tvalid`
- `tuser[0]` (SOP) asserted on first beat of an event; not asserted
  mid-event

### 5.2 `sva_axi4_master`

- `awvalid` once asserted holds `awaddr/awlen/awsize/awburst/awid`
  stable until `awready`
- `wvalid` once asserted holds `wdata/wstrb/wlast` stable until `wready`
- # of W beats with `wvalid && wready` per AW transaction == `awlen + 1`
- `wlast` asserted on the last W beat and only on the last
- `awlen ≤ 4'h0F` (15)
- `awburst == 2'b01`
- `awsize == 3'b101` (32 B per beat)
- `awaddr[4:0] == 5'b0` (beat-aligned)
- AW handshake before the first W beat OR same cycle (AXI4 allows
  same-cycle but the engine must never push W without an in-flight AW)
- `bready` asserted whenever `bvalid`; `bid` matches `awid` of the
  oldest in-flight AW
- 4 KB no-cross: `((awaddr + (awlen+1) * 32) & ~12'hFFF) ==
  (awaddr & ~12'hFFF)` — burst region stays in one 4 KB page

### 5.3 `sva_job`

- `job_req` is one cycle wide (engine must latch on rising edge)
- `job_done` is one cycle wide (run_manager samples on rising edge)
- `job_done` does not assert while `job_req` is asserted (no overlap)
- After `job_done`, all report fields hold valid for at least one cycle
- `status[ALIGN_ERR]` implies no AXI traffic was emitted for this job

### 5.4 `sva_packer`

- Slot accumulator never advances without `tvalid && ~halt`
- `last_in_event` asserted on the same beat as the EOE-pad emission
- `bytes_in_word ∈ {4, 8, 12, 16, 20, 24, 28, 32}` (multiple of 4)
- Conservation at the packer boundary:
  `cnt_input_w == # of accepted OPQ beats since reset` (verified at
  every cycle by counting accepted vs reported)

### 5.5 `sva_fifo`

- `level <= depth` at all times
- `level == depth` implies `wr_en = 0` next cycle (full)
- Almost-full threshold (192 / 256) drives `i_dma_halffull` back to
  packer; when `i_dma_halffull = 1`, packer must not emit a new 256-bit
  beat into the FIFO

### 5.6 `sva_writer_fsm`

- FSM state ∈ {IDLE, PROGRAM, AW, W, B, REPORT_DONE} (and the alignment-
  error state)
- IDLE → PROGRAM on `job_req` and (alignment OK)
- IDLE → REPORT_ALIGN_ERR on `job_req` and (alignment NOT OK)
- AW → W only after `awvalid && awready`
- W → B only after `wlast && wvalid && wready`
- B → AW (same segment) OR PROGRAM (next segment) OR REPORT_DONE
- REPORT_DONE asserts `job_done` for exactly one cycle then returns to
  IDLE

### 5.7 `sva_dbg1_taps` (DEBUG=1+)

- `dbg1_fifo_level` is consistent with internal FIFO write/read counter
- `dbg1_aw_inflight` and `dbg1_b_outstanding` consistent with AW/B
  counters
- `dbg1_writer_state` matches the FSM enum

### 5.8 `sva_dbg2_sidecar` (DEBUG=2 only)

- Each ingress 32 b OPQ beat carries a non-zero `dbg2_meta_*` (driver
  contract guarantees this in DEBUG=2)
- The sidecar travels through the packer in MSB-first slot order
  (matches payload order)
- The FIFO carries the sidecar alongside payload; `last_in_event`
  applies to both
- Per W-beat, the writer-shadow sidecar enumerates the 8 slots' meta
  in the same order as the payload words

---

## 6. Coverage Hooks

Per `dv-workflow` rule 6 (mandatory) and `DV_PLAN.md` §5, the harness
implements eight coverage groups. Each `.sv` file under
`tb/uvm/coverage/` defines one covergroup with its bins. The scoreboard
samples them at the canonical event (job_done for `cg_job` and
`cg_status_cross`, every AW handshake for `cg_axi_burst`, every AXI4
W beat for `cg_throughput`, every flush for `cg_packer`, every level
update for `cg_fifo`, every reset for `cg_reset`, every lineage match
for `cg_dbg2_lineage`).

UCDBs:

- per-test isolated UCDB → `cov_after/<debug_level>/<test_name>.ucdb`
- per-bucket merged UCDB → `cov_after/<debug_level>/buckets/<bucket>.ucdb`
- per-debug-level signoff UCDB → `cov_after/<debug_level>/signoff.ucdb`
- random / soak checkpoint UCDBs → `cov_after/<debug_level>/txn_growth/<case>_txn<N>.ucdb`
  (per skill rule "Checkpoint UCDBs (random long runs)")

DEBUG=1 and DEBUG=2 UCDBs are **kept separate**, not merged across
levels. The closure dashboard reports each level's signoff UCDB
independently to make build-coupling regressions visible.

---

## 7. Reset and Continuous-Frame Support

Per `dv-workflow` rule 8, the harness MUST support:

1. **`isolated`:** every test runs with a fresh DUT reset. `tb_top`
   asserts `reset_n = 0` for `>= 16` cycles and deasserts at test
   start. The default `run_phase` enters this mode.
2. **`bucket_frame`:** one continuous frame. `tb_top.bucket_frame_run_phase`
   asserts reset once at the very start and never again. Tests in the
   bucket are sequenced via a top-level virtual sequence
   `bucket_frame_<bucket>_seq` that calls each test's `body()` in
   case-id order with no reset in between.
3. **`all_buckets_frame`:** same shape, the top-level
   `all_buckets_frame_seq` chains the four bucket sequences in order
   `BASIC → EDGE → PROF → ERROR`.

Tests that rely on a clean reset (typically reset/recovery cases under
DV_ERROR) run `seq_pulse_reset` themselves rather than depending on the
harness — this lets them participate in the continuous-frame baseline
without breaking the no-restart contract.

Both DEBUG=1 and DEBUG=2 builds run `bucket_frame` and `all_buckets_frame`
independently; the dual-env scoreboard cross-checks per-job lineage at
each completion boundary, even inside a continuous frame.

---

## 8. Debug Hooks

- All FSM state taps (`packer_state`, `writer_state`, `fifo_level`)
  exposed through `tb_top` for waveform dump.
- `tb_top.do_dump = 1` enables `vcd dump` of a curated signal list
  (per case; signature cases get a checked-in `.gtkw`).
- DEBUG=2 dumps include the sidecar conduits at ingress, FIFO write,
  FIFO read, and writer-shadow ports — one analog overlay per signal
  group when a `.gtkw` is provided.
- Test banner format: `TEST PASS:` / `TEST FAIL:` plus a `Time:` line,
  per skill "Waveform And Debug Handoff" rule 3.

---

## 9. Sim runtime contract (QuestaOne 2026.1)

Per the global CLAUDE.md "Questa One License and Toolchain Setup":

- Use `/data1/questaone_sim-2026.1_1/questasim` as the only supported
  simulation runtime.
- `LM_LICENSE_FILE = MGLS_LICENSE_FILE = SALT_LICENSE_SERVER =
  8161@lic-mentor.ethz.ch`.
- UVM 1.2 from `$QUESTA_HOME/verilog_src/questa_uvm_pkg-1.2`.
- `rand` / `covergroup` / DPI all native — no FSE workarounds.

Vlog flags: `+define+UVM_NO_DPI` is **NOT** used. Vsim flags:
`-c -suppress 19 -suppress 3009`. Standard Mu3e Makefile pattern
(see CLAUDE.md "Makefile pattern (Questa One)").

Build matrix:

| Build | `+define+DUT_DEBUG_LEVEL=` | Synthesizable? | Carries lineage sidecar? |
|---|---|---|---|
| dbg0 (synth corner) | 0 | yes | no |
| dbg1 (sim + observability) | 1 | yes | no |
| dbg2 (sim-only widening) | 2 | NO (sim-only) | yes |

dbg0 is exercised by the standalone Quartus syn flow in `syn/quartus/`,
not by the UVM TB. dbg1 and dbg2 are the sibling UVM builds.

---

## 10. Static screen contract

Per `~/.codex/skills/rtl-linter-and-checker/SKILL.md` (HARD GATE), every
`.sv` produced under `rtl/` must pass:

```
python3 ~/.codex/skills/rtl-linter-and-checker/scripts/questa_static_screen.py \
    --top rdma_dma_engine \
    --filelist <rdma_dma_engine.qsf-or-.f> \
    rtl/rdma_dma_engine.sv rtl/rdma_dma_packer.sv \
    rtl/rdma_dma_data_fifo.sv rtl/rdma_dma_writer.sv
```

Acceptance: Lint `Error (0)`, CDC `Violations (0)`, RDC `Violation (0)`.
Run for both `DEBUG_LEVEL=0` (synth corner) and `DEBUG_LEVEL=1` (synth
corner + taps) parameter selections. `DEBUG_LEVEL=2` is sim-only and
exempt from synth-related lint paths but must still pass lint.

Formal closure on the writer FSM safety bits will be added once the
writer RTL is stable.

---

## 11. Open items

- Phase 2 may add a backpressure path from FIFO almost-full all the way
  back to OPQ; harness would need to extend `opq_axis_agent` to honor
  `tready`.
- Phase 2 may swap inferred SCFIFO for `altera_avalon_st_fifo`;
  harness `cg_fifo` bin definitions would need a recheck for the
  almost-full threshold semantics of the Altera primitive.
- DEBUG=2 lineage covergroup `cg_dbg2_lineage` may grow additional
  bins once the sidecar field widths are finalized in RTL.
