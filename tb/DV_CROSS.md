# DV Cross — rdma_dma_engine

**Companion docs:** `DV_PLAN.md`, `DV_HARNESS.md`, `DV_BASIC.md`,
`DV_EDGE.md`, `DV_PROF.md`, `DV_ERROR.md`, `DV_COV.md`,
`BUG_HISTORY.md`.

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**Status:** establishes the `bucket_frame` and `all_buckets_frame`
continuous-frame baseline runs that serve as the long-run functional-
coverage anchors. Per `dv-workflow` rule 8 these are mandatory baselines.

This document does **NOT** restate the per-case bucket tables; those
live in `DV_BASIC.md` / `DV_EDGE.md` / `DV_PROF.md` / `DV_ERROR.md`.
This document defines the continuous-frame run names, the order they
execute their constituent cases in, the harness shape they require, and
the closure expectation at the end of each frame.

---

## 1. Continuous-Frame Baselines

Per `dv-workflow` rule 9, both `bucket_frame` and `all_buckets_frame`
are mandatory baselines. They run all sign-off bucket cases inside one
continuous timeframe with no DUT restart between cases. Each is run
twice — once at DEBUG_LEVEL=1 and once at DEBUG_LEVEL=2 — for the
dual-UVM contract (per `DV_HARNESS.md` §1).

### 1.1 `bucket_frame_basic`

- **Bucket:** BASIC (B001 - B128)
- **Order:** canonical numeric (B001 → B128)
- **Build matrix:** DEBUG=1 and DEBUG=2 sibling runs
- **Reset profile:** asserted at the start; no reset between cases
- **Random cases:** execute their declared `Iter` count from
  `DV_BASIC.md`
- **Closure expectation:**
  - All directed cases pass; all random cases conserve
  - Per-bucket merged code coverage published in `DV_COV.md`
  - DEBUG=2 lineage residual == 0 across the full frame (modulo
    expected halt residuals which equal `cnt_halt`)

### 1.2 `bucket_frame_edge`

- **Bucket:** EDGE (E001 - E128)
- **Order:** canonical numeric (E001 → E128)
- Same dual-build, dual-reset semantics as 1.1.

### 1.3 `bucket_frame_prof`

- **Bucket:** PROF (P001 - P128)
- **Order:** canonical numeric (P001 → P128)
- Same dual-build, dual-reset semantics. PROF cases include long
  random runs that emit checkpoint UCDBs at log-spaced txn boundaries
  per the dv-workflow checkpoint rule.

### 1.4 `bucket_frame_error`

- **Bucket:** ERROR (X001 - X128)
- **Order:** canonical numeric (X001 → X128)
- ERROR cases that depend on a clean reset (e.g. ALIGN_ERR cases)
  embed `seq_pulse_reset` themselves rather than depending on the
  harness — this lets them participate in the continuous-frame
  baseline without breaking the no-restart contract.

### 1.5 `all_buckets_frame`

- **Order:** `BASIC → EDGE → PROF → ERROR`, each in canonical case-id
  order.
- **Build matrix:** DEBUG=1 and DEBUG=2 sibling runs
- **Closure expectation:**
  - Full sign-off coverage published in `DV_COV.md` §"Sign-off Summary"
  - Cross-build residual reporter (per `DV_HARNESS.md` §4.7) reports
    DEBUG=1 vs DEBUG=2 nominal residuals identical at every job
    boundary
  - DEBUG=2 lineage matcher residual == 0 modulo per-job halt residuals

---

## 2. Cross-Bucket / Long-Run Coverage Crosses

In addition to the per-bucket continuous frames, the regression
maintains the following cross-coverage points (sampled by the
covergroups in `coverage/`):

| Cross | Covergroup | Sample event | What it Proves |
|-------|-----------|---------------|----------------|
| EOE × FULL | `cg_status_cross` | job_done | both end-conditions can co-occur |
| EOE × SEG_BOUNDARY_HIT | `cg_status_cross` | job_done | EOE arrives during seg1 |
| SEG0_ONLY × FULL | `cg_status_cross` | job_done | single-segment fills |
| HALT × EOE | `cg_status_cross` | job_done | halt during a drain that ends in EOE |
| HALT × FULL | `cg_status_cross` | job_done | halt during a drain that fills |
| awlen × FIFO_level | `cg_axi_burst × cg_fifo` | every AW | burst sizing tracks FIFO occupancy as designed |
| reset_state × FSM_state | `cg_reset` | every reset | reset asserted at every FSM state at least once |
| dbg2_lineage(lane × sequence_no) | `cg_dbg2_lineage` | every lineage match | DEBUG=2 sidecar walks the full bin space at sign-off |

Per `dv-workflow` rule 8, the `bucket_frame` runs collect these
crosses naturally because the long-run continuous frame visits every
covergroup repeatedly; the per-cross totals are reported alongside the
bucket totals in `DV_COV.md`.

---

## 3. Dual-Build Residual Cross-Check

Per `DV_HARNESS.md` §4.7, the shared scoreboard publishes a side-by-side
residual report after every job and at the end of every continuous
frame:

| residual | DEBUG=1 build | DEBUG=2 build |
|---|---|---|
| input bytes accepted | sum of cnt_input_w * 4 | sum of cnt_input_w * 4 |
| bytes written to host | sum of W-beats * (32 - pad bytes) | same |
| halt bytes | sum of cnt_halt * 4 | same |
| ingress sidecar entries | n/a | sum |
| writer-emit sidecar entries | n/a | sum |
| lineage residual | n/a | ingress - emit (must == cnt_halt) |
| nominal residual | input - written - halt (must == 0) | same |

Closure:

- Any non-zero "must == 0" cell at the end of `bucket_frame` or
  `all_buckets_frame` is a closure blocker.
- Any disagreement between the DEBUG=1 nominal residual and the DEBUG=2
  nominal residual is a closure blocker.

These checks are sampled at every `job_done` boundary (including
inside continuous frames) so that a regression introducing a coupled
behavior between the dbg1 / dbg2 ports and the synthesizable payload is
caught at the case granularity.

---

## 4. Continuous-Frame Run Logs

Run logs land at `tb/uvm/logs/<debug_level>/<frame_name>.log`. UCDBs
land at `tb/uvm/cov_after/<debug_level>/buckets/<bucket>.ucdb` for
bucket frames and at `tb/uvm/cov_after/<debug_level>/signoff.ucdb` for
the all-buckets frame.

`dv_report_gen.py` aggregates these into the `REPORT/` tree:

- `REPORT/cross/bucket_frame_basic_dbg1.md`
- `REPORT/cross/bucket_frame_basic_dbg2.md`
- ... etc per bucket
- `REPORT/cross/all_buckets_frame_dbg1.md`
- `REPORT/cross/all_buckets_frame_dbg2.md`

Each cross-frame report carries: code coverage, functional cross
percentage, per-txn growth curve (for random cases that emit
checkpoint UCDBs), counter-check summary, and the dual-build residual
table.

---

## 5. Update Protocol

This file is hand-maintained at DV bring-up to define the baselines.
Once the harness and `dv_report_gen.py` aggregator emit the cross-frame
reports, the per-bucket and per-frame totals appear under `REPORT/`
rather than here.
