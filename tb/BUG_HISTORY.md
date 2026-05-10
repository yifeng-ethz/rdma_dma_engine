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
| [BUG-001-R](#bug-001-r-packer-word-order-reverses-dv-plan-msb-first-contract) | H | soft error | common (single full DMA word) | fixed | B002 dual-debug smoke | `pending` | TB scoreboard and docs expected MSB-first while RTL/prototype pack LSB-first. |

## 2026-05-10

### BUG-001-R: Packer word order reverses DV plan MSB-first contract
- First seen in:
  - `make -C rdma_dma_engine/tb/uvm regress` on `2026-05-10`
  - `B002` under `DEBUG_LEVEL=1` and `DEBUG_LEVEL=2`
- Symptom:
  - `B001` reset/idle passes in both debug modes with zero scoreboard
    residuals
  - `B002` reaches one full DMA write in both debug modes:
    `opq=8 aw=1 w=1 b=1 job_done=1`
  - the contract scoreboard reports one `WDATA` mismatch in each debug mode,
    and `scripts/cross_validate_dbg.py` rejects both scorecards with
    `summary.mismatches=1`
- Root cause:
  - `tb/DV_PLAN.md` section 3.2 and `RTL_PLAN.md` section 4.1 incorrectly
    described the 256-bit slot pack as MSB-first
  - `tb/uvm/scoreboard.sv` mirrored that stale contract by placing expected
    OPQ word N at `[255 - N*32 -: 32]`
  - `rtl/rdma_dma_packer.sv` correctly inserts `word_data` at
    `[slot_index*OPQ_DATA_W +: OPQ_DATA_W]`, which places the first accepted
    OPQ word in the least-significant 32-bit slot and matches the
    cosim-validated `tb_int/feb_swb_corun/sv/swb_rdma_dma_packer.sv`
    prototype
- Fix status:
  - state: fixed; Phase B smoke now uses the prototype-aligned LSB-first pack
    contract and keeps RTL unchanged
  - mechanism: `tb/uvm/scoreboard.sv` now packs expected slot N at
    `[N*32 +: 32]`; `RTL_PLAN.md` section 4.1 and `tb/DV_PLAN.md` section 3.2
    now document slot N at bits `[N*32+31 : N*32]`, slot 0 at LSB, slot 7 at
    MSB, with EOP partial beats zero-padding empty high-numbered slots
  - before_fix_outcome: `make -C rdma_dma_engine/tb/uvm regress` fails
    `cross_validate_dbg.py` after both `B002` scorecards report one mismatch
  - after_fix_outcome: `make -C rdma_dma_engine/tb/uvm regress` passes
    `B001` and `B002` under `DEBUG_LEVEL=1` and `DEBUG_LEVEL=2`; all four
    scorecards report `summary.mismatches=0`
  - potential_hazard: closed; remaining risk is normal Phase B coverage
    backlog, not slot-order drift
  - Claude Opus 4.7 xhigh review decision: pending / not run
- Runtime / coverage context:
  - first failing scoreboard sample is at `178 ns` in both debug modes
  - `DEBUG_LEVEL=2` emits all eight lineage sidecar entries, so the live
    blocker is functional payload ordering rather than DEBUG sidecar residual
  - fixed smoke evidence: `B002` observes `opq=8 aw=1 w=1 b=1 job_done=1`
    with `dbg1_mismatches=0` and `dbg2_mismatches=0`
- Commit:
  - pending

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
