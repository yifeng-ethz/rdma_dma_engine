# ⚠️ BASIC bucket

**Planned:** `128` &nbsp; **Evidenced:** `2` &nbsp; **Status:** ⚠️

## Merged code coverage (this bucket)

<!-- column legend:
  metric          = code-coverage category (stmt/branch/cond/expr/fsm_state/fsm_trans/toggle)
  merged_pct      = bucket-local ordered-merge percentage across all evidenced cases
  target          = workflow coverage target (blank = no hard target for that category)
  status          = target check vs merged_pct
-->

| status | metric | merged_pct | target |
|:---:|---|---|---|
| ⚠️ | stmt | 62.97 | 95.0 |
| ⚠️ | branch | 30.43 | 90.0 |
| ℹ️ | cond | 15.97 | - |
| ℹ️ | expr | 3.94 | - |
| ⚠️ | fsm_state | 0.00 | 95.0 |
| ⚠️ | fsm_trans | 0.00 | 90.0 |
| ⚠️ | toggle | 2.96 | 80.0 |

## Ordered merge trace

<!-- each row is the merged coverage total after that case was added to the bucket in case-id order. -->

| status | step | case_id | merged_total (stmt/branch/cond/expr/fsm_state/fsm_trans/toggle) | detail |
|:---:|---:|---|---|---|
| ✅ | 1 | `B001` | stmt=38.17, branch=20.42, cond=6.62, expr=1.47, fsm_state=0.00, fsm_trans=0.00, toggle=0.30 | [case](../cases/B001.md) |
| ❌ | 2 | `B002` | stmt=62.97, branch=30.43, cond=15.97, expr=3.94, fsm_state=0.00, fsm_trans=0.00, toggle=2.96 | [case](../cases/B002.md) |

---
_Back to [dashboard](../../DV_REPORT.md)_
