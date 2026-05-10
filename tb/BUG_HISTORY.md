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
| [BUG-001-R](#bug-001-r-packer-word-order-reverses-dv-plan-msb-first-contract) | H | soft error | common (single full DMA word) | fixed | B002 dual-debug smoke | `3d2ba7f` | TB scoreboard and docs expected MSB-first while RTL/prototype pack LSB-first. |
| [BUG-002-R](#bug-002-r-aw-burst-metadata-could-drift-and-underfill-streaming-bursts) | R | soft error | common (streaming DMA with AW backpressure or max-burst checks) | fixed | Phase B B015/B052 expansion | `pending` | AW fields were not fully transaction-latched and the writer latched bursts before the FIFO could reach max-burst depth. |
| [BUG-003-H](#bug-003-h-dual-debug-lineage-scorecards-used-different-sequence-number-canonicals) | H | non-datapath-refactor | directed-only (dual-debug scorecard comparison for generated cases) | fixed | Phase B B013-B016 cross-validate | `pending` | DEBUG_LEVEL=1 scorecards synthesized sequence_no=1 while DEBUG_LEVEL=2 carried the generated case SQE-derived sequence number. |

## 2026-05-10

### BUG-003-H: Dual-debug lineage scorecards used different sequence-number canonicals
- First seen in:
  - `make -C tb/uvm cross_validate CASES="B001 ... B016"` on
    `2026-05-10`
  - generated Phase B cases `B013` through `B016`
- Symptom:
  - `DEBUG_LEVEL=1` and `DEBUG_LEVEL=2` simulations both passed with
    `summary.mismatches=0`
  - `scripts/cross_validate_dbg.py` rejected the scorecards because the first
    three lineage fields matched, but `sequence_no` was `1` in DEBUG_LEVEL=1
    and the generated case SQE-derived value in DEBUG_LEVEL=2
- Root cause:
  - DEBUG_LEVEL=1 intentionally ties off the DEBUG2 sideband wires
  - the scoreboard canonicalized missing DEBUG2 metadata by setting
    `sequence_no=1`, which was only valid for the original B002 smoke
  - generated Phase B OPQ data encodes the SQE-derived sequence number in the
    payload, so the DEBUG_LEVEL=1 functional lineage had enough information to
    reconstruct the same canonical sequence number as DEBUG_LEVEL=2
- Fix status:
  - state: fixed; first Phase B transaction batch cross-validates cleanly
  - mechanism: `tb/uvm/scoreboard.sv` now reconstructs the generated-case
    sequence number from the OPQ payload when DEBUG2 sidebands are absent and
    falls back to `1` for legacy smoke payloads
  - before_fix_outcome: cross-validation failed for `B013` through `B016`
    with per-entry `sequence_no` differences
  - after_fix_outcome: `make -C tb/uvm cross_validate CASES="B013 B014 B015
    B016"` reports zero residual mismatch across all four cases
  - potential_hazard: closed for generated Phase B cases; future payload
    encodings must keep a deterministic DEBUG_LEVEL=1 canonical source if the
    dual-debug comparator is expected to compare full lineage tuples
  - Claude Opus 4.7 xhigh review decision: pending / not run
- Runtime / coverage context:
  - after-fix `B013` observes `opq=8 aw=1 w=1 b=1 job_done=1`
  - after-fix `B015` observes `opq=128 aw=1 w=16 b=1 job_done=1`
  - all cited runs saved per-debug UCDBs under `tb/uvm/cov_after/dbg{1,2}/`
- Commit:
  - `pending`

### BUG-002-R: AW burst metadata could drift and underfill streaming bursts
- First seen in:
  - Phase B burst and stall expansion on `2026-05-10`
  - `B015` / `B042` max-burst intent and `B052` AW-stall intent
- Symptom:
  - with AW backpressure, `m_axi_awlen` was derived from live FIFO level while
    `m_axi_awvalid` could remain asserted
  - under streaming input, the writer latched an AW as soon as FIFO level was
    non-zero, so max-burst scenarios could produce short bursts instead of
    the intended `awlen==15`
- Root cause:
  - `rdma_dma_writer.sv` did not fully latch the chosen burst length before
    asserting AW valid
  - the AW latch condition used the first available FIFO beat instead of
    waiting for a full burst, segment-tail condition, or EOE-tail condition
- Fix status:
  - state: fixed; burst and AW-stall Phase B cases now have stable AW metadata
    and can produce full bursts
  - mechanism: the writer now latches `beats_in_burst` and
    `beats_remaining` before AW issue, drives `m_axi_awlen` from that latched
    value, and only latches a new AW when the FIFO can provide a full burst,
    the segment tail is available, or EOE has made a short tail legal
  - before_fix_outcome: max-burst generated cases underfilled bursts and the
    AW hold assertion could fail when FIFO level changed during an AW stall
  - after_fix_outcome: `B015` reports `opq=128 aw=1 w=16 b=1 job_done=1`;
    `B016` reports `opq=256 aw=2 w=32 b=2 job_done=1`; both pass under
    DEBUG_LEVEL=1 and DEBUG_LEVEL=2 with zero mismatches
  - potential_hazard: closed for the RTL contract now covered by the Phase B
    burst and AW-stall cases; long PROF runs still need full regression
    coverage
  - Claude Opus 4.7 xhigh review decision: pending / not run
- Runtime / coverage context:
  - the verifying runs save per-case UCDBs at
    `tb/uvm/cov_after/dbg{1,2}/B015_dbg{1,2}.ucdb` and
    `B016_dbg{1,2}.ucdb`
  - the dual-debug cross-check for `B013 B014 B015 B016` reports zero
    residual mismatch after the fix
- Commit:
  - `pending`

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
  - `3d2ba7f` (`[FIX] Resolve BUG-001-R: TB scoreboard slot order`)

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
