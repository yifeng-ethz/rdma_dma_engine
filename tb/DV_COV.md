# DV Coverage Summary — `rdma_dma_engine Phase B UVM closure`

This page is the coverage summary only. Per-case incremental coverage lives under
[`REPORT/cases/`](REPORT/cases/); per-bucket ordered-merge traces live under
[`REPORT/buckets/`](REPORT/buckets/).

## Legend

✅ pass / closed &middot; ⚠️ partial / below target &middot; ❌ failed / missing evidence &middot; ❓ pending &middot; ℹ️ informational

## Targets vs merged totals

<!-- merged_pct = merge across all evidenced isolated-mode UCDBs across all buckets. -->

| status | metric | merged_pct | target |
|:---:|---|---|---|
| ✅ | stmt | 99.60 | 95.0 |
| ✅ | branch | 100.00 | 90.0 |
| ℹ️ | cond | 85.29 | - |
| ℹ️ | expr | 85.71 | - |
| ✅ | fsm_state | 100.00 | 95.0 |
| ✅ | fsm_trans | 100.00 | 90.0 |
| ✅ | toggle | 99.06 | 80.0 |

## Per-bucket merged totals

| status | bucket | stmt | branch | cond | expr | fsm_state | fsm_trans | toggle |
|:---:|---|---|---|---|---|---|---|---|
| ✅ | [`BASIC`](REPORT/buckets/BASIC.md) | 98.80 | 98.09 | 82.35 | 74.28 | 100.00 | 100.00 | 99.28 |
| ✅ | [`EDGE`](REPORT/buckets/EDGE.md) | 99.20 | 99.04 | 82.35 | 74.28 | 100.00 | 100.00 | 99.61 |
| ✅ | [`PROF`](REPORT/buckets/PROF.md) | 98.01 | 98.09 | 85.29 | 70.00 | 100.00 | 100.00 | 99.75 |
| ✅ | [`ERROR`](REPORT/buckets/ERROR.md) | 98.01 | 97.14 | 79.41 | 80.00 | 100.00 | 100.00 | 99.01 |

## Continuous-frame baselines by build

<!-- one row per bucket_frame / all_buckets_frame signoff run (see REPORT/cross/ for curves). -->

| status | run_id | kind | build | bucket | case_count | stmt | branch | toggle | functional_cross_pct | txns |
|:---:|---|---|---|---|---:|---|---|---|---:|---:|
| ✅ | [`rdma_dma_engine_phase_b_all_dual_debug`](REPORT/cross/rdma_dma_engine_phase_b_all_dual_debug.md) | isolated | dual_debug | ALL | 512 | 99.60 | 100.00 | 99.06 | 100.0 | 36353 |

_Regenerate with `python3 ~/.codex/skills/dv-workflow/scripts/dv_report_gen.py <tb>`._
