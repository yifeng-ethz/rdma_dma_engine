# BUG_HISTORY.md - rdma_dma_engine DV bug ledger

Class legend:
- `R` = RTL / DUT bug
- `H` = harness / testcase / reporting bug

Severity legend:
- `soft error` = the bad packet/data flushes through the stream and does not leave the later datapath stuck
- `hard stuck error` = the bug poisons later packet handling and typically needs a functional reset / fresh restart to recover
- `non-datapath-refactor` = observability, reporting, harness, or naming/accounting consistency work with no direct packet-contract effect

Encounterability legend:
- practical severity is `severity x encounterability`, so the index must say how likely a reader is to hit the bug in normal use rather than only when it first appeared in one simulation log
- nominal datapath operation = legal traffic, about `50%` link load, iid per-lane behavior, and no forced error injection or artificially pathological stalls
- nominal control-path operation = routine bring-up / CSR program / readback / clear-counter sequences
- `common (...)` = readily hit in nominal operation
- `occasional (...)` = hit in nominal operation without heroic setup, but not in every short run
- `rare (...)` = legal in nominal operation, but usually needs long runtime or unlucky alignment
- `corner-only (...)` = requires a legal but non-nominal stress or corner profile
- `directed-only (...)` = requires targeted error injection, formal/probe flow, reporting-only flow, or another non-operational stimulus

Fix status detail contract for active entries and future updates:
- `state` = fixed / open / partial plus the current verification gate
- `mechanism` = how the implemented repair changes the RTL or harness behavior
- `before_fix_outcome` and `after_fix_outcome` = concise evidence showing what changed
- `potential_hazard` = whether the fix looks permanent or is still provisional / profile-limited
- `Claude Opus 4.7 xhigh review decision` = explicit review state; use `pending / not run` until that review has actually happened

Historical formal note:
- This ledger seeds with `BUG-000-H` as a placeholder so it lints clean
  on day 1 of DV bring-up. Real RTL/harness bugs found during the first
  bucket runs will replace the placeholder convention with `BUG-001-R` /
  `BUG-001-H` style entries per the canonical packet_scheduler format.
- The supported simulator runtime for this IP is `QuestaOne 2026.1`
  at `/data1/questaone_sim-2026.1_1`. The supported formal direction
  is `qverify` / `znformal`.

## Index

| bug_id | class | severity | encounterability | status | first seen | commit | summary |
|---|---|---|---|---|---|---|---|
| [BUG-000-H](#bug-000-h-bug-history-seeded-empty-at-dv-bring-up) | H | non-datapath-refactor | directed-only (DV bring-up bookkeeping) | fixed | DV bring-up | `pending` | BUG_HISTORY.md seeded empty at DV bring-up so the ledger lints clean before any real RTL/harness bug surfaces. |

## 2026-05-10

### BUG-000-H: BUG_HISTORY.md seeded empty at DV bring-up
- First seen in:
  - DV bring-up commit for `rdma_dma_engine/tb/`
- Symptom:
  - the ledger needs to lint clean under
    `python3 ~/.codex/skills/dv-workflow/scripts/bug_history_format_check.py
    rdma_dma_engine/tb/BUG_HISTORY.md` before any real bug has surfaced
- Root cause:
  - none -- bookkeeping seed entry only
- Fix status:
  - state: fixed
  - mechanism: this seed entry adds one canonical-format index row + one
    canonical-format detailed section so the lint passes
  - before_fix_outcome: lint failed with "BUG_HISTORY index must contain
    at least one bug row"
  - after_fix_outcome: lint clean
  - potential_hazard: none; this entry will be replaced by `BUG-001-*`
    once the first real bug is logged from the bring-up runs
  - Claude Opus 4.7 xhigh review decision: pending / not run
