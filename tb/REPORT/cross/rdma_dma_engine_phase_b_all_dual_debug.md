# ✅ rdma_dma_engine_phase_b_all_dual_debug

**Kind:** `isolated` &nbsp; **Build:** `dual_debug` &nbsp; **Bucket:** `ALL` &nbsp; **Sequence:** `make -C tb/uvm regress`

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
| ℹ️ | case_count | `512` |
| ℹ️ | effort | `phase_b` |
| ℹ️ | iter_cap | `None` |
| ℹ️ | payload_cap | `None` |
| ℹ️ | txns | `36353` |
| ✅ | functional_cross_pct | `100.0` |
| ℹ️ | queued_overlap | `0` |
| ✅ | counter_checks_failed | `0` |
| ✅ | unexpected_outputs | `0` |

## Code coverage

<!-- merged code coverage produced by this single run (not ordered-merged into any bucket). -->

| metric | pct |
|---|---|
| stmt | 99.60 |
| branch | 100.00 |
| cond | 85.29 |
| expr | 85.71 |
| fsm_state | 100.00 |
| fsm_trans | 100.00 |
| toggle | 99.06 |

## Transaction growth curve

<!-- each row is one transaction step: which planned case fired, current functional-cross percent, -->
<!-- delta_bins = number of new cross bins hit at this step; reason = scoreboard checkpoint trigger. -->

| txn | case | seq | pct | delta_bins | reason |
|---:|---|---|---|---:|---|
| 512 | `X128` | `phase_b` | 100.0 | 512 | all_cases_evidenced |

---
_Back to [dashboard](../../DV_REPORT.md)_
