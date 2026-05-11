# DV Plan — rdma_dma_engine

**DUT:** `rdma_dma_engine` (`rtl/rdma_dma_engine.sv`)
**Submodules under DV:** `rdma_dma_packer.sv`, `rdma_dma_data_fifo.sv`,
`rdma_dma_writer.sv`
**Author:** Yifeng Wang (yifenwan@phys.ethz.ch)
**Date:** 2026-05-10
**Status:** Active plan, RTL pending. Companion bucket files (`DV_BASIC.md`,
`DV_EDGE.md`, `DV_PROF.md`, `DV_ERROR.md`, `DV_CROSS.md`) carry the
detailed case catalog. `DV_HARNESS.md` carries the dual-UVM-env
architecture (DEBUG_LEVEL=1 fill-level taps + DEBUG_LEVEL=2 sim-only
sidecar lineage). `BUG_HISTORY.md` is the live bug ledger.

This plan is the entry point. It defines the verification targets, lists
the contract sources of truth, names the dual-UVM contract, and references
the bucket files for case-level detail. It does **NOT** restate the per-
case tables — those live in the bucket files.

---

## 1. Purpose & Scope

`rdma_dma_engine` is the data-mover IP of the `rdma_subsystem` super-core.
It accepts an OPQ-side AXI4-Stream (36 bit `tdata`) and writes the packed
256-bit beats into a host-DRAM region named by a 2-segment job request
from `rdma_run_manager`. On completion it reports rich CQE-feeding fields
(per-segment `bytes_written`, `status`, `event_count`, `first_event_ts`,
`last_event_ts`).

### In-scope

- 32→256 bit packing, partial-line zero-padding at OPQ EOE
- 256-bit SCFIFO with almost-full backpressure to packer
- AXI4 (full) write-master FSM with 2-segment scatter:
  `WR_IDLE → WR_PROGRAM → WR_AW → WR_W → WR_B → {WR_AW | WR_PROGRAM | WR_REPORT_DONE}`
- Burst sizing: `MAX_BURST_BEATS = 16`, `m_axi_awsize = $clog2(DMA_DATA_W/8) = 5`
  (256 b / 8 = 32 B), `m_axi_awburst = 2'b01` (INCR), no 4 KB crossing
- Job interface from `run_manager`: `job_req` / `job_done` handshake +
  `seg{0,1}_addr`, `seg{0,1}_span`, `rqe_id`, `opcode` in;
  `bytes_written_total`, `seg0_bytes_written`, `seg1_bytes_written`,
  `status[15:0]`, `rqe_id_echo`, `event_count`, `first_event_ts`,
  `last_event_ts` out
- Status bits per ARCH §5: `EOE`, `FULL`, `HALT`, `SEG_BOUNDARY_HIT`,
  `SEG0_ONLY`, `ALIGN_ERR`
- Sideband counters: `cnt_input_w`, `cnt_bytes_written`, `cnt_halt`,
  `cnt_eoe_observed`
- Conservation invariant: `cnt_input_w * 4 == bytes_written + halt_bytes`
  (modulo the partial-line padding accounted at EOE)
- Reset behaviour and `clear_counters` strobe semantics
- AXI4 master protocol compliance (no AW deassert mid-handshake; W beats
  conform to `awlen`; B handshake; AWADDR alignment; AWLEN+1 == # of W
  beats)

### Out-of-scope (covered elsewhere)

- RQ ring fetch / CQ ring push: handled by `rdma_rq_fetcher` and
  `rdma_cq_pusher`, NOT here. Their job-request and CQE-construction
  contracts are validated in their own DV plans.
- Host-visible CSR aperture: this IP has **no** host CSR. Counters are
  sideband to `rdma_run_manager`, which surfaces them at BAR1 0x3C / 0x40
  / 0x44 / 0x48 (see ARCH §6). The CSR-side test cases live in the
  `rdma_run_manager` DV plan. **Per dv-workflow rule 15b, CSR map MUST
  NOT be duplicated in any bucket file here.**
- The OPQ itself: stimulus is injected as 36-bit AXI4-Stream beats. No
  K-char framing checks — the IP accepts whatever the OPQ produces.
- AXI4 ↔ Avalon-MM bridge (Phase 2): tested in the supercore-level
  `tb_int/feb_swb_corun_rdma/` integration TB, not here.

---

## 2. DUT Interfaces

| Interface | Type | Width | Clock | Direction | Notes |
|-----------|------|-------|-------|-----------|-------|
| `s_axis_opq` | AXI4-Stream sink | 36 b `tdata` | `clk` | in | `tdata = {datak[3:0], data[31:0]}`, `tlast = OPQ EOE`, `tuser[0] = SOP`, `tready` tied 1 in Phase 1 |
| `job_*` (req side) | conduit | 64+64+64+64+16+16 b | `clk` | in | `job_req`, `job_seg{0,1}_addr`, `job_seg{0,1}_span`, `job_rqe_id`, `job_opcode` |
| `job_*` (done side) | conduit | 64+32+32+16+16+32+64+64 b | `clk` | out | `job_done`, `job_bytes_written_total`, `job_seg{0,1}_bytes_written`, `job_status`, `job_rqe_id_echo`, `job_event_count`, `job_first_event_ts`, `job_last_event_ts` |
| `m_axi_*` (write) | AXI4 master | 64 b addr / 256 b data | `clk` | both | AW + W + B channels only, no read |
| `cnt_*` | sideband | 32 b each | `clk` | out | `cnt_input_w`, `cnt_bytes_written`, `cnt_halt`, `cnt_eoe_observed` |
| `dbg1_*` (DEBUG_LEVEL≥1) | observation | parameterized | `clk` | out | FIFO fill level, AW/W/B in-flight counts, halt counters, packer slot index — tied off in synthesizable build, exposed for sim/SignalTap |
| `dbg2_*` (DEBUG_LEVEL=2 sim-only) | sidecar | parameterized | `clk` | both | Per-hit `(lane, hit_id, source_ts, sequence_no)` flowing alongside payload through the entire datapath; tied off / zeroed in synthesizable builds |
| `clk` / `reset_n` | clock/reset | 1 b | self | in | single domain, default 250 MHz |

---

## 3. Verification Targets

The bucket files carry the per-case detail. This section lists the
high-level verification targets; the bucket files break each target down
into one or more `D` (directed) or `R` (constrained-random) cases.

### 3.1 Identity and accounting (BASIC)

- `cnt_input_w` increments exactly once per 32-bit OPQ beat accepted
- `cnt_bytes_written` increments by 32 (beat width in bytes) per AXI4 W
  beat with all `wstrb` set; partial last beat counts only the bytes
  actually carried before the EOE-pad zeros
- `cnt_eoe_observed` increments once per OPQ EOE (= `tlast`)
- `cnt_halt` increments once per dropped OPQ beat at packer (FIFO almost-
  full)

### 3.2 Pack / unpack contract (BASIC)

- 8 32-bit OPQ words → 1 256-bit AXI4 W beat, LSB-first into the slot
  pack: slot N occupies bits `[N*32+31 : N*32]`, slot 0 is at the LSB, and
  slot 7 is at the MSB. This matches `swb_rdma_dma_packer.sv` prototype
  semantics.
- On OPQ EOE with non-empty partial accumulator, emit one 256-bit beat
  with empty high-numbered slots zero-padded; `last_in_event = 1`
- `bytes_in_word[5:0]` accurately reports the # of valid 32-bit slots
  in that beat (always 32 except possibly the EOE-flush beat)

### 3.3 2-segment scatter (BASIC + EDGE)

- Single-segment job: `seg1_span = 0` → engine fills `seg0` only;
  `status[SEG0_ONLY] = 1` on completion
- Two-segment job: when seg0 fills exactly and seg1_span > 0, engine
  programs seg1's first AW with `cur_addr = seg1_addr` and sets
  `status[SEG_BOUNDARY_HIT] = 1`
- Address arithmetic stays 4 KB-aligned because spans are 4 KB
  multiples; AXI4 INCR bursts (≤ 512 B) never cross a 4 KB page

### 3.4 Job-end conditions (BASIC)

- OPQ `tlast` arrives before either segment is full → `status[EOE] = 1`,
  drain ends after the EOE-pad beat is acked on B
- `seg0_span + seg1_span` exhausted before any `tlast` → `status[FULL] = 1`,
  engine stops accepting OPQ data, raises `job_done` after the final B
- Both happen on the same beat: `status[EOE] = 1` AND `status[FULL] = 1`
  (EOE wins the priority for the report; both bits must be set)

### 3.5 Job-interface alignment errors (ERROR)

- `seg0_addr & 0xFFF != 0` → engine refuses, raises `job_done` immediately,
  `status[ALIGN_ERR] = 1`, NO AXI traffic emitted
- `seg0_span & 0xFFF != 0` (incl. `seg0_span = 0`) → same
- `seg1_span > 0 && seg1_addr & 0xFFF != 0` → same
- `seg1_span > 0 && seg1_span & 0xFFF != 0` → same

### 3.6 AXI4 master protocol compliance (BASIC + EDGE + ERROR)

- `m_axi_awvalid` does not deassert before `m_axi_awready`
- `m_axi_wvalid` does not deassert before `m_axi_wready` for any beat
- # of `m_axi_w*` beats with `wvalid && wready` per AW transaction ==
  `awlen + 1`
- `m_axi_wlast` asserted on the last beat of every burst, and only there
- `m_axi_awlen` ≤ 15 (cap == `MAX_BURST_BEATS - 1 = 15`)
- `m_axi_awsize == 3'b101` (32 B per beat for `DMA_DATA_W = 256`)
- `m_axi_awburst == 2'b01` (INCR)
- `m_axi_awaddr` ≡ 0 mod 32 (beat-aligned), and the burst region
  `[awaddr, awaddr + (awlen+1)*32 - 1]` does NOT cross a 4 KB boundary
- AW handshake-first then W: engine must assert `awvalid` before driving
  the first W beat (or at the same cycle, but never deliver W beats for
  an AW that has not handshaked)
- B-channel: engine accepts a `bvalid` with `bready = 1`; on `bresp != OKAY`
  the engine sets a non-OKAY status bit and continues / aborts per spec
- No interleaved bursts (AXI4 forbids interleaving for a single ID)

### 3.7 Backpressure and flow (PROF + EDGE)

- Throttled host (slow `m_axi_wready` / late `bvalid`) → bursts pause
  but do not lose data; FIFO absorbs the back-pressure up to its depth
- FIFO almost-full triggers packer halt → `cnt_halt` counts dropped OPQ
  beats; conservation invariant still holds modulo `halt_bytes`
- 100 % link-load OPQ ingest with realistic AXI4 host latency (~1 µs to
  first BVALID) — sustained throughput meets analytical model

### 3.8 Multi-job back-to-back (BASIC + PROF)

- Two consecutive jobs completing in order, distinct `rqe_id`s echo back
  in order
- Job stream of 100 jobs → conservation across all jobs:
  `Σ cnt_input_w * 4 == Σ bytes_written + Σ halt_bytes`

### 3.9 Reset and counter clear (ERROR)

- Active reset during any FSM state → engine returns to `WR_IDLE`,
  in-flight AXI4 burst abandons cleanly (no stuck AW/W), all counters
  cleared per RTL spec
- `clear_counters` strobe (sideband from run_manager) → all four
  `cnt_*` zero on next cycle
- Reset asserted during `WR_W` mid-burst: AXI4 contract requires the
  burst to complete (W beats and a B reply); engine SHALL NOT abort
  mid-burst silently; instead, RTL contract is "drain the burst, then
  flush" — DV proves this with a directed case

### 3.10 Per-event timestamp tracking (BASIC + EDGE)

- `first_event_ts` captures the OPQ-side cycle counter at the first EOE
  seen in the drain
- `last_event_ts` captures the OPQ-side cycle counter at the last EOE
  seen in the drain
- `event_count` reports the number of EOE boundaries observed
  (independent of whether the engine is running — counts across all OPQ
  EOE beats received during this drain)

### 3.11 DEBUG_LEVEL contract (DUAL UVM ENV — HARD REQUIREMENT)

Per dv-workflow OoO-datapath rule (skill rule §6 of "Harness rules"):
treat payload correctness and debug lineage as separate but correlated
evidence. Two cumulative debug levels are defined:

- **DEBUG_LEVEL=0 (synth default)**: no observability ports beyond
  `cnt_*`. RTL must build cleanly with all `dbg1_*` / `dbg2_*` tied off
  to `'0`. The synthesizable build PASSES if and only if removing
  `dbg1_*` and `dbg2_*` does not change any payload signal.
- **DEBUG_LEVEL=1 (synthesizable + observability)**: exposes FIFO fill
  level, AW/W/B in-flight counts, halt counters, packer slot index, and
  writer FSM state encoding via `dbg1_*` ports. **No functional
  change** — these are pure observation taps wired off internal flops.
  Same RTL passes synthesis when DEBUG_LEVEL=1; the ports become useful
  in sim and SignalTap.
- **DEBUG_LEVEL=2 (simulation-only widening)**: in addition to DEBUG=1,
  the AXI4-Stream input gains a per-hit metadata sidecar `dbg2_meta_*`
  carrying `(lane, hit_id, source_ts, sequence_no)`. This sidecar
  flows through the packer (one entry per accepted 32 b OPQ beat),
  the FIFO (alongside the 256 b payload), and the writer (emitted on a
  shadow `dbg2_writer_*` analysis-port for the TB). DEBUG=2 is **sim-
  only** — the synthesizable build must tie `dbg2_*` to `'0` and treat
  the ports as inputs/outputs that synthesis prunes.

The dual UVM env runs both DEBUG=1 and DEBUG=2 builds **as siblings in a
single regression**. Both contribute their own UCDB. A single shared
scoreboard cross-validates DEBUG=2 per-hit lineage against DEBUG=1
functional payload; disagreement is a closure blocker. See
`DV_HARNESS.md` for the env wiring, monitor split, and cross-validation
contract.

---

## 4. Bucket Files (References)

| Bucket | File | ID range | Total cases | What it covers |
|--------|------|----------|-------------|----------------|
| BASIC | [DV_BASIC.md](DV_BASIC.md) | B001-B128 | 128 | Standard functional contracts: identity, packing, AXI4 protocol baseline, single-segment / two-segment job, status bits, counter semantics, DEBUG=1 fill-level + DEBUG=2 lineage smoke |
| EDGE | [DV_EDGE.md](DV_EDGE.md) | E001-E128 | 128 | Boundary / corner cases: alignment boundaries, span boundaries, AXI4 burst sizing edges, FIFO almost-full / empty boundaries, partial-line padding, EOE-on-burst-boundary, segment-boundary-on-EOE |
| PROF | [DV_PROF.md](DV_PROF.md) | P001-P128 | 128 | Throughput / soak / stress: 100 jobs back-to-back, throttled host, sustained 100 % OPQ rate, conservation under load, burst-sizing throughput vs queue-math model |
| ERROR | [DV_ERROR.md](DV_ERROR.md) | X001-X128 | 128 | Reset / fault / illegal / recovery: alignment errors, mid-burst reset, AXI4 BRESP errors, illegal job parameters, FIFO underrun protection, DEBUG=2 lineage breaks |
| CROSS | [DV_CROSS.md](DV_CROSS.md) | -- | -- | `bucket_frame` and `all_buckets_frame` continuous-frame baselines for long-run sign-off; named DEBUG=1 and DEBUG=2 baselines |
| COV | [DV_COV.md](DV_COV.md) | -- | -- | Per-bucket coverage tracking tables; established at bring-up, populated as tests run |

---

## 5. Coverage Intent

Functional coverage groups (defined in `DV_HARNESS.md` and bucket files;
established empty in `DV_COV.md` at bring-up, populated as tests run):

- `cg_job` — `seg0_span` bin, `seg1_span` bin, `seg1_used` bool, `opcode`,
  `rqe_id` bin, `status` bit set
- `cg_axi_burst` — `awlen` (0..15), `awaddr[11:0]` aligned-bin, # of beats
  per burst, `bresp`, time-to-first-`bready`-after-`bvalid`
- `cg_packer` — slot index at flush (1..8), `last_in_event`, `bytes_in_word`,
  `pending_eoe & ~accept` (the EOE-pad path)
- `cg_fifo` — `level` bin (empty / quarter / half / 3-quarter / almost-
  full), `halt` (almost-full → drop), one-beat-after-fill drain
- `cg_status_cross` — `EOE × FULL`, `EOE × SEG_BOUNDARY_HIT`,
  `SEG0_ONLY × FULL`, etc.
- `cg_throughput` — sustained input rate band, sustained output rate band,
  job-end-to-end latency
- `cg_reset` — reset-during-state crosses
- `cg_dbg2_lineage` — per-hit `(lane, hit_id, source_ts, sequence_no)`
  match between DEBUG=2 ingress sidecar and DEBUG=2 writer-emit shadow

Code coverage targets (per `dv-workflow` skill defaults):
- Statement: ≥ 95 %
- Branch / FSM transition: ≥ 90 %
- Toggle: ≥ 80 %

---

## 6. Execution-Mode Ordering

Per `dv-workflow` rules 8 and 9 (mandatory baselines):

1. **Isolated:** default mode. Each case runs with a fresh DUT reset.
   This is the per-case UCDB baseline used for the `coverage_by_this_case`
   and `coverage_incr_per_txn` columns of `DV_COV.md`.
2. **`bucket_frame`:** all cases inside one bucket run in case-id order
   inside one continuous frame, no DUT restart between cases. Order is
   the canonical numeric order of the case IDs (B001 → B128 for BASIC,
   etc.). Directed cases run one transaction; random cases run their
   declared iteration count.
3. **`all_buckets_frame`:** all sign-off buckets run in
   `BASIC → EDGE → PROF → ERROR` order, with case-id order inside each
   bucket. Same continuous-frame semantics. ERROR cases that cannot
   legally run in a no-restart frame (e.g. alignment-error cases that
   expect the engine to stay in `WR_IDLE` permanently) MUST be repaired
   or split rather than silently skipped (per skill rule 9).

Both `bucket_frame` and `all_buckets_frame` are published twice — once
under the DEBUG=1 build, once under the DEBUG=2 build. `DV_CROSS.md`
names these baselines and cross-references the harness shape.

---

## 7. Validation Surface

| Surface | Sim runtime | Filelist | Notes |
|---------|-------------|----------|-------|
| Per-IP UVM tb | QuestaOne 2026.1 (`/data1/questaone_sim-2026.1_1`) | `tb/uvm/Makefile` | Default `vsim` flow; UVM 1.2 from bundled `verilog_src/questa_uvm_pkg-1.2`, full DPI / `rand` / `covergroup` available (no FSE workarounds needed). Two `make`-targets per build: `make run-debug1`, `make run-debug2`. `make regress-dual` runs both. |
| Standalone Quartus syn | Quartus Pro 23.1 | `syn/quartus/rdma_dma_engine_standalone.qsf` | 1.1× target frequency = 275 MHz (target 250 MHz × 1.1). DEBUG_LEVEL parameter forced to 0 for the synth corner; secondary check at DEBUG_LEVEL=1 to confirm fill-level taps still close timing. |
| Static screen | Questa Static Formal 2024.1_2 (`qverify`) | run via `~/.codex/skills/rtl-linter-and-checker/scripts/questa_static_screen.py` | Lint / CDC / RDC must show 0 violations on each `.sv`; formal closure on FSM safety bits. Run for both DEBUG=0 (synth) and DEBUG=1 builds. DEBUG=2 is sim-only and exempt from synth-related lint paths. |

---

## 8. Acceptance for DV closure

Per `dv-workflow` rules 10-15 and the "Closure" section of the skill:

1. All 4 sign-off bucket files (BASIC, EDGE, PROF, ERROR) implemented at
   the planned case count. Each bucket file lints clean under
   `python3 ~/.codex/skills/dv-workflow/scripts/dv_bucket_format_check.py
   tb/`.
2. Per-bucket `DV_COV.md` table populated; ordered isolated merged total
   per bucket reported, separately for DEBUG=1 and DEBUG=2 builds.
3. `bucket_frame` and `all_buckets_frame` baselines run cleanly under
   both DEBUG=1 and DEBUG=2; their continuous-frame merged totals
   reported separately from isolated merge.
4. DEBUG=1 vs DEBUG=2 cross-validation: scoreboard reports zero
   payload-vs-lineage disagreement across the full regression. Any
   disagreement is a closure blocker.
5. `BUG_HISTORY.md` lints clean under
   `python3 ~/.codex/skills/dv-workflow/scripts/bug_history_format_check.py
   tb/BUG_HISTORY.md`. Every found bug recorded with first-seen test,
   commit hash of fix, and "Claude Opus 4.7 xhigh review decision"
   field.
6. Coverage targets met or every gap explicitly justified in `DV_COV.md`.
7. Static screen PASS (lint 0 violations, CDC 0 violations, RDC 0
   violations) on every produced `.sv` file via the `rtl-linter-and-checker`
   skill's `questa_static_screen.py`, for both DEBUG=0 (synth) and
   DEBUG=1 (synth + taps) parameter selections.
8. Standalone Quartus signoff: timing met at 1.1× target (275 MHz) with
   DEBUG_LEVEL=0; supplementary timing check at DEBUG_LEVEL=1 to confirm
   fill-level taps do not pull the cone past the corner.
9. `DV_REPORT.md` and the `REPORT/` tree generated and committed via
   `dv_report_gen.py`.

---

## 9. Pointers

- Subsystem architecture: `../rdma_subsystem/ARCHITECTURE_PLAN.md`
- This IP's RTL plan: `../RTL_PLAN.md`
- Math/queueing analysis: `../doc/QUEUE_MATH.md`
- Cosim-validated packer prototype:
  `tb_int/feb_swb_corun/sv/swb_rdma_dma_packer.sv`
- Reference DV layouts:
  - `mu3e-ip-cores/ring-buffer_cam/tb/` (dual-monitor pattern, payload
    `out_monitor` + internal `debug_monitor`, single scoreboard cross-
    validating)
  - `mu3e-ip-cores/packet_scheduler/tb/` (long-form DV evidence,
    bug-ledger style, bucket_frame / all_buckets_frame baselines)
- Skills owning this workflow:
  - DV: `~/.codex/skills/dv-workflow/SKILL.md` (especially OoO-datapath
    DEBUG=0/1/2 contract and dual-monitor cross-validation rules)
  - RTL: `~/.codex/skills/rtl-writing/SKILL.md`,
    `~/.codex/skills/rtl-file-structure-organization/SKILL.md`
  - Static screen: `~/.codex/skills/rtl-linter-and-checker/SKILL.md`
  - IP packaging: `~/.codex/skills/ip-packaging/SKILL.md`
  - Simulator setup: `~/.codex/skills/verification-tools/SKILL.md`
