# ❌ rdma_dma_engine_dual_debug_smoke

**Kind:** `isolated` &nbsp; **Build:** `dual_debug` &nbsp; **Bucket:** `BASIC` &nbsp; **Sequence:** `make -C tb/uvm regress`

## Summary

<!-- field legend:
  case_count              = number of plan cases composed into this run
  effort                  = practical (capped per case) or extensive (full planned stress)
  iter_cap, payload_cap   = practical-mode budget caps
  txns                    = total transactions driven through the DUT in this run
  functional_cross_pct    = functional coverage against DV_CROSS.md (percent)
  queued_overlap          = transactions enqueued before the previous drained
  counter_checks_failed   = scoreboard counter mismatches observed (0 is required for pass)
  unexpected_outputs      = outputs the scoreboard did not predict
-->

| status | field | value |
|:---:|---|---|
| ℹ️ | case_count | `2` |
| ℹ️ | effort | `smoke` |
| ℹ️ | iter_cap | `1` |
| ℹ️ | payload_cap | `8` |
| ℹ️ | txns | `2` |
| ❌ | functional_cross_pct | `50.0` |
| ℹ️ | queued_overlap | `0` |
| ❌ | counter_checks_failed | `2` |
| ✅ | unexpected_outputs | `0` |

## Code coverage

<!-- merged code coverage produced by this single run (not ordered-merged into any bucket). -->

| metric | pct |
|---|---|
| stmt | 62.97 |
| branch | 30.43 |
| cond | 15.97 |
| expr | 3.94 |
| fsm_state | 0.00 |
| fsm_trans | 0.00 |
| toggle | 2.96 |

## Transaction growth curve

<!-- each row is one transaction step: which planned case fired, current functional-cross percent, -->
<!-- delta_bins = number of new cross bins hit at this step; reason = scoreboard checkpoint trigger. -->

| txn | case | seq | pct | delta_bins | reason |
|---:|---|---|---|---:|---|
| 1 | `B001` | `reset` | 50.0 | 1 | idle_defaults |
| 2 | `B002` | `single_job` | 50.0 | 0 | WDATA_mismatch |

---
_Back to [dashboard](../../DV_REPORT.md)_
