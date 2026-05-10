# DV Coverage Summary — `rdma_dma_engine Phase B UVM smoke`

This page is the coverage summary only. Per-case incremental coverage lives under
[`REPORT/cases/`](REPORT/cases/); per-bucket ordered-merge traces live under
[`REPORT/buckets/`](REPORT/buckets/).

## Legend

✅ pass / closed &middot; ⚠️ partial / below target &middot; ❌ failed / missing evidence &middot; ❓ pending &middot; ℹ️ informational

## Targets vs merged totals

<!-- merged_pct = merge across all evidenced isolated-mode UCDBs across all buckets. -->

| status | metric | merged_pct | target |
|:---:|---|---|---|
| ⚠️ | stmt | 62.97 | 95.0 |
| ⚠️ | branch | 30.43 | 90.0 |
| ℹ️ | cond | 15.97 | - |
| ℹ️ | expr | 3.94 | - |
| ⚠️ | fsm_state | 0.00 | 95.0 |
| ⚠️ | fsm_trans | 0.00 | 90.0 |
| ⚠️ | toggle | 2.96 | 80.0 |

## Per-bucket merged totals

| status | bucket | stmt | branch | cond | expr | fsm_state | fsm_trans | toggle |
|:---:|---|---|---|---|---|---|---|---|
| ⚠️ | [`BASIC`](REPORT/buckets/BASIC.md) | 62.97 | 30.43 | 15.97 | 3.94 | 0.00 | 0.00 | 2.96 |
| ⚠️ | [`EDGE`](REPORT/buckets/EDGE.md) | n/a | n/a | n/a | n/a | n/a | n/a | n/a |
| ⚠️ | [`PROF`](REPORT/buckets/PROF.md) | n/a | n/a | n/a | n/a | n/a | n/a | n/a |
| ⚠️ | [`ERROR`](REPORT/buckets/ERROR.md) | n/a | n/a | n/a | n/a | n/a | n/a | n/a |

## Continuous-frame baselines by build

<!-- one row per bucket_frame / all_buckets_frame signoff run (see REPORT/cross/ for curves). -->

| status | run_id | kind | build | bucket | case_count | stmt | branch | toggle | functional_cross_pct | txns |
|:---:|---|---|---|---|---:|---|---|---|---:|---:|
| ❌ | [`rdma_dma_engine_dual_debug_smoke`](REPORT/cross/rdma_dma_engine_dual_debug_smoke.md) | isolated | dual_debug | BASIC | 2 | 62.97 | 30.43 | 2.96 | 50.0 | 2 |

_Regenerate with `python3 ~/.codex/skills/dv-workflow/scripts/dv_report_gen.py <tb>`._
