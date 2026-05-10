# rdma_dma_engine Phase B UVM closure — REPORT index

**DUT:** `rdma_dma_engine` &nbsp; **Date:** `2026-05-11` &nbsp;
**RTL variant:** `DEBUG_LEVEL=1/2 Phase B dual-debug` &nbsp; **Seed:** `1`

## Legend

✅ pass / closed / target met &middot; ⚠️ partial / below target / known limitation &middot; ❌ failed / missing evidence &middot; ❓ pending &middot; ℹ️ informational

## Buckets

<!-- click a bucket row to open its ordered-merge trace and linked per-case pages. -->

| status | bucket | planned | evidenced | merged (stmt/branch/cond/expr/fsm_state/fsm_trans/toggle) |
|:---:|---|---:|---:|---|
| ✅ | [`BASIC`](buckets/BASIC.md) | 128 | 128 | stmt=98.80, branch=98.09, cond=82.35, expr=74.28, fsm_state=100.00, fsm_trans=100.00, toggle=99.28 |
| ✅ | [`EDGE`](buckets/EDGE.md) | 128 | 128 | stmt=99.20, branch=99.04, cond=82.35, expr=74.28, fsm_state=100.00, fsm_trans=100.00, toggle=99.61 |
| ✅ | [`PROF`](buckets/PROF.md) | 128 | 128 | stmt=98.01, branch=98.09, cond=85.29, expr=70.00, fsm_state=100.00, fsm_trans=100.00, toggle=99.75 |
| ✅ | [`ERROR`](buckets/ERROR.md) | 128 | 128 | stmt=98.01, branch=97.14, cond=79.41, expr=80.00, fsm_state=100.00, fsm_trans=100.00, toggle=99.01 |

## Cross / continuous-frame runs

| status | run_id | kind | build | bucket | seq | txns | cross_pct |
|:---:|---|---|---|---|---|---:|---:|
| ✅ | [`rdma_dma_engine_phase_b_all_dual_debug`](cross/rdma_dma_engine_phase_b_all_dual_debug.md) | isolated | dual_debug | ALL | make -C tb/uvm regress | 36353 | 100.0 |

## Random long-run cases

<!-- each random case has a txn_growth page; pages are pending until checkpoint UCDBs exist. -->

| status | case_id | bucket | observed_txn | growth_page |
|:---:|---|---|---:|---|

## Totals

<!-- merged_total_code_coverage is the merge across all evidenced cases in all buckets. -->

- planned_cases = `512`
- evidenced_cases = `512`
- excluded_cases = `0`
- merged total code coverage: `stmt=99.60, branch=100.00, cond=85.29, expr=85.71, fsm_state=100.00, fsm_trans=100.00, toggle=99.06`
- functional coverage: `100.0% (512/512)`

---
_[Dashboard](../DV_REPORT.md) &middot; [Coverage](../DV_COV.md)_
