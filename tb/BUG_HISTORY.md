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
| [BUG-002-R](#bug-002-r-aw-burst-metadata-could-drift-and-underfill-streaming-bursts) | R | soft error | common (streaming DMA with AW backpressure or max-burst checks) | fixed | Phase B B015/B052 expansion | `eb0ce24` | AW fields were not fully transaction-latched and the writer latched bursts before the FIFO could reach max-burst depth. |
| [BUG-003-H](#bug-003-h-dual-debug-lineage-scorecards-used-different-sequence-number-canonicals) | H | non-datapath-refactor | directed-only (dual-debug scorecard comparison for generated cases) | fixed | Phase B B013-B016 cross-validate | `eb0ce24` | DEBUG_LEVEL=1 scorecards synthesized sequence_no=1 while DEBUG_LEVEL=2 carried the generated case SQE-derived sequence number. |
| [BUG-004-H](#bug-004-h-generated-phase-b-lineage-harness-coupled-independent-fields) | H | non-datapath-refactor | directed-only (long dual-debug generated-case comparison) | fixed | Phase B B017-B032 expansion | `pending` | Generated Phase B sequence metadata was coupled to SQE IDs and payload byte rollover, breaking long-case dual-debug evidence. |

## 2026-05-10

### BUG-004-H: Generated Phase B lineage harness coupled independent fields
- First seen in:
  - `make -C tb/uvm -j2 phase_b_dbg1 phase_b_dbg2 REGRESS_CASES="test_b017_phase_b:B017 ... test_b032_phase_b:B032"` on `2026-05-10`
  - `make -C tb/uvm cross_validate CASES="B017 ... B032"` after the
    first clean B017-B032 simulation pass
- Symptom:
  - `B025` under DEBUG_LEVEL=2 reported lineage differences when the case
    used `sqe_id=0x0000`
  - after adding an independent `sequence_no` argument, the positional
    `run_dma_job` call accidentally shifted `300000` into `idle_after_each`,
    making `B017` run for an impractical number of cycles until the job was
    stopped
  - after the argument binding fix, long cases such as `B017` and `B032`
    simulated cleanly but cross-validation rejected entries after payload byte
    255 because DEBUG_LEVEL=1 reconstructed `sequence_no=2+` while
    DEBUG_LEVEL=2 correctly retained `sequence_no=1`
- Root cause:
  - generated tests had tied DEBUG lineage `sequence_no` to `sqe_id`, even
    though the DV cases only require `sqe_id_echo` and do not make SQE ID the
    lineage sequence source
  - the new `sequence_no` task argument was added ahead of
    `idle_after_each`, and the call site still used positional arguments
  - `opq_axis_event_sequence` used `item.data = data_base + idx`; after 256
    words the low-byte counter carried into payload bits `[23:8]`, which are
    the DEBUG_LEVEL=1 fallback sequence-number field
- Fix status:
  - state: fixed; B017-B032 now simulate, cross-validate, and merge
  - mechanism: `run_dma_job` now carries an explicit `sequence_no`, the
    generated-case call uses named arguments, and OPQ payload generation keeps
    payload bits `[31:8]` stable while varying only the low byte
  - before_fix_outcome: `B025` failed with DEBUG_LEVEL=2 lineage mismatches,
    `B017` stalled after the positional argument shift, and long-case
    cross-validation reported sequence-number differences starting at
    lineage index 256
  - after_fix_outcome: `make -C tb/uvm cross_validate CASES="B017 ... B032"`
    reports zero residual mismatch across all 16 cases; `make -C tb/uvm
    merge_case_ucdbs REGRESS_CASE_IDS="B017 ... B032"` writes
    `tb/uvm/cov_after/B017.ucdb` through `B032.ucdb` with `Errors: 0`
  - potential_hazard: closed for the generated Phase B sequence encoding;
    later cases that intentionally vary lineage sequence numbers must pass
    them through the explicit `sequence_no` argument
  - Claude Opus 4.7 xhigh review decision: pending / not run
- Runtime / coverage context:
  - after-fix `B017` observes `opq=2048 aw=16 w=256 b=16 job_done=1`
  - after-fix `B032` observes `opq=1024 aw=8 w=128 b=8 job_done=1`
  - all cited runs saved per-debug UCDBs under `tb/uvm/cov_after/dbg{1,2}/`
    and per-case merged UCDBs under `tb/uvm/cov_after/`
- Commit:
  - `pending`

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
  - `eb0ce24` (`[NEW] Add Phase B B001-B016 evidence harness`)

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
  - `eb0ce24` (`[NEW] Add Phase B B001-B016 evidence harness`)

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
