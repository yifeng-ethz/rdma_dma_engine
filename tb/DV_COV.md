# DV Coverage — rdma_dma_engine

**Companion docs:** `DV_PLAN.md`, `DV_HARNESS.md`, `DV_BASIC.md`,
`DV_EDGE.md`, `DV_PROF.md`, `DV_ERROR.md`, `DV_CROSS.md`,
`BUG_HISTORY.md`.

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**Status:** established empty at DV bring-up. Tables populate as the
regression runs and `dv_report_gen.py` aggregates per-case UCDBs.

This file is the per-bucket coverage tracking ledger. It carries the
strict per-bucket testcase tables (5 columns per
`dv-workflow` rule 4), the running ordered-isolated merged totals, and
the separate continuous-frame `bucket_frame` / `all_buckets_frame`
totals, **for both DEBUG=1 and DEBUG=2 builds** (per the dual-UVM
contract in `DV_PLAN.md` §3.11).

---

## Coverage Targets

| Category | Target | Notes |
|----------|-------:|-------|
| Statement | ≥ 95 % | per `dv-workflow` skill defaults |
| Branch | ≥ 90 % | |
| Condition | ≥ 90 % | |
| Expression | ≥ 90 % | |
| FSM state / transition | ≥ 90 % | |
| Toggle | ≥ 80 % | |
| Functional (per cg_*) | ≥ 95 % | per covergroup defined in `DV_HARNESS.md` §6 |

Coverage is split per debug-level (DEBUG=1 vs DEBUG=2) build and not
merged across levels (per the dual-UVM contract). Both builds must hit
the targets independently.

---

## Execution-Mode Baselines

Per `dv-workflow` rule 12, coverage evidence is published in three
ordered baselines:

1. **isolated**: every case run with a fresh DUT reset; UCDB per case
   under `tb/uvm/cov_after/<debug_level>/<case_name>.ucdb`.
2. **`bucket_frame`**: per-bucket continuous-frame run; UCDB at
   `tb/uvm/cov_after/<debug_level>/buckets/<bucket>.ucdb`.
3. **`all_buckets_frame`**: full sign-off frame; UCDB at
   `tb/uvm/cov_after/<debug_level>/signoff.ucdb`.

Case ordering for `bucket_frame` is canonical (`B001 → B128`,
`E001 → E128`, etc.). `all_buckets_frame` order is `BASIC → EDGE → PROF
→ ERROR`.

---

## Per-Bucket Tables (DEBUG_LEVEL=1)

### BASIC (B001 - B128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated by dv_report_gen.py from per-case UCDBs_ | | | | |

Running ordered-isolated merged total (DEBUG=1 BASIC): _pending_

`bucket_frame_basic` continuous-frame merged total (DEBUG=1): _pending_

### EDGE (E001 - E128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=1 EDGE): _pending_

`bucket_frame_edge` continuous-frame merged total (DEBUG=1): _pending_

### PROF (P001 - P128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=1 PROF): _pending_

`bucket_frame_prof` continuous-frame merged total (DEBUG=1): _pending_

### ERROR (X001 - X128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=1 ERROR): _pending_

`bucket_frame_error` continuous-frame merged total (DEBUG=1): _pending_

---

## Per-Bucket Tables (DEBUG_LEVEL=2)

### BASIC (B001 - B128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=2 BASIC): _pending_

`bucket_frame_basic` continuous-frame merged total (DEBUG=2): _pending_

### EDGE (E001 - E128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=2 EDGE): _pending_

`bucket_frame_edge` continuous-frame merged total (DEBUG=2): _pending_

### PROF (P001 - P128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=2 PROF): _pending_

`bucket_frame_prof` continuous-frame merged total (DEBUG=2): _pending_

### ERROR (X001 - X128)

| case_id | type (d/r) | coverage_by_this_case | executed random txn | coverage_incr_per_txn |
|---------|------------|-----------------------|---------------------|-----------------------|
| _to be populated_ | | | | |

Running ordered-isolated merged total (DEBUG=2 ERROR): _pending_

`bucket_frame_error` continuous-frame merged total (DEBUG=2): _pending_

---

## Sign-off Summary

| Build | Bucket | isolated merged total | bucket_frame total | all_buckets_frame total |
|-------|--------|-----------------------|--------------------|--------------------------|
| DEBUG=1 | BASIC | _pending_ | _pending_ | _pending_ |
| DEBUG=1 | EDGE | _pending_ | _pending_ | _pending_ |
| DEBUG=1 | PROF | _pending_ | _pending_ | _pending_ |
| DEBUG=1 | ERROR | _pending_ | _pending_ | _pending_ |
| DEBUG=2 | BASIC | _pending_ | _pending_ | _pending_ |
| DEBUG=2 | EDGE | _pending_ | _pending_ | _pending_ |
| DEBUG=2 | PROF | _pending_ | _pending_ | _pending_ |
| DEBUG=2 | ERROR | _pending_ | _pending_ | _pending_ |

---

## Functional Coverage Groups

Per `DV_HARNESS.md` §6, eight covergroups are defined:

| Covergroup | Source file | Sample event | Bin notes |
|-----------|-------------|---------------|-----------|
| `cg_job` | `coverage/cov_job.sv` | job_done | seg0_span bin, seg1_span bin, seg1_used bool, opcode, sqe_id bin, status bit set |
| `cg_axi_burst` | `coverage/cov_axi_burst.sv` | every AW handshake | awlen (0..15), awaddr[11:0] aligned-bin, # of beats per burst, bresp, time-to-first-bready-after-bvalid |
| `cg_packer` | `coverage/cov_packer.sv` | every flush | slot index at flush (1..8), last_in_event, bytes_in_word, pending_eoe & ~accept |
| `cg_fifo` | `coverage/cov_fifo.sv` | every level update | level bin (empty / quarter / half / 3-quarter / almost-full), halt, one-beat-after-fill drain |
| `cg_status_cross` | `coverage/cov_status_cross.sv` | job_done | EOE × FULL, EOE × SEG_BOUNDARY_HIT, SEG0_ONLY × FULL, ... |
| `cg_throughput` | `coverage/cov_throughput.sv` | every W beat | sustained input rate band, sustained output rate band, job-end-to-end latency |
| `cg_reset` | `coverage/cov_reset.sv` | every reset | reset-during-state crosses |
| `cg_dbg2_lineage` | `coverage/cov_dbg2_lineage.sv` (DEBUG=2 only) | every lineage match | per-hit (lane, hit_id, source_ts, sequence_no) match between ingress and writer-emit |

Functional coverage is reported per-covergroup at sign-off; closure
target ≥ 95 % across all hit bins.

---

## Update Protocol

This file is regenerated by `dv_report_gen.py` after every regression.
Hand edits below this line are the only persistent surface; everything
above is generated.

**Hand-edit notes:**

- _none yet_
