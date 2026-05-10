# rdma_dma_engine Phase B UVM smoke — REPORT index

**DUT:** `rdma_dma_engine` &nbsp; **Date:** `2026-05-10` &nbsp;
**RTL variant:** `DEBUG_LEVEL=1/2 dual-env smoke` &nbsp; **Seed:** `1`

## Legend

✅ pass / closed / target met &middot; ⚠️ partial / below target / known limitation &middot; ❌ failed / missing evidence &middot; ❓ pending &middot; ℹ️ informational

## Buckets

<!-- click a bucket row to open its ordered-merge trace and linked per-case pages. -->

| status | bucket | planned | evidenced | merged (stmt/branch/cond/expr/fsm_state/fsm_trans/toggle) |
|:---:|---|---:|---:|---|
| ⚠️ | [`BASIC`](buckets/BASIC.md) | 128 | 2 | stmt=62.97, branch=30.43, cond=15.97, expr=3.94, fsm_state=0.00, fsm_trans=0.00, toggle=2.96 |
| ⚠️ | [`EDGE`](buckets/EDGE.md) | 128 | 0 | stmt=n/a, branch=n/a, cond=n/a, expr=n/a, fsm_state=n/a, fsm_trans=n/a, toggle=n/a |
| ⚠️ | [`PROF`](buckets/PROF.md) | 128 | 0 | stmt=n/a, branch=n/a, cond=n/a, expr=n/a, fsm_state=n/a, fsm_trans=n/a, toggle=n/a |
| ⚠️ | [`ERROR`](buckets/ERROR.md) | 128 | 0 | stmt=n/a, branch=n/a, cond=n/a, expr=n/a, fsm_state=n/a, fsm_trans=n/a, toggle=n/a |

## Cross / continuous-frame runs

| status | run_id | kind | build | bucket | seq | txns | cross_pct |
|:---:|---|---|---|---|---|---:|---:|
| ❌ | [`rdma_dma_engine_dual_debug_smoke`](cross/rdma_dma_engine_dual_debug_smoke.md) | isolated | dual_debug | BASIC | make -C tb/uvm regress | 2 | 50.0 |

## Random long-run cases

<!-- each random case has a txn_growth page; pages are pending until checkpoint UCDBs exist. -->

| status | case_id | bucket | observed_txn | growth_page |
|:---:|---|---|---:|---|

## Totals

<!-- merged_total_code_coverage is the merge across all evidenced cases in all buckets. -->

- planned_cases = `512`
- evidenced_cases = `2`
- excluded_cases = `0`
- merged total code coverage: `stmt=62.97, branch=30.43, cond=15.97, expr=3.94, fsm_state=0.00, fsm_trans=0.00, toggle=2.96`
- functional coverage: `0.39% (2/512)`

---
_[Dashboard](../DV_REPORT.md) &middot; [Coverage](../DV_COV.md)_
