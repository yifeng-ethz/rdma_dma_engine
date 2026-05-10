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
| [BUG-004-H](#bug-004-h-generated-phase-b-lineage-harness-coupled-independent-fields) | H | non-datapath-refactor | directed-only (long dual-debug generated-case comparison) | fixed | Phase B B017-B032 expansion | `2dd9507` | Generated Phase B sequence metadata was coupled to SQE IDs and payload byte rollover, breaking long-case dual-debug evidence. |
| [BUG-005-H](#bug-005-h-axi-completer-dropped-same-cycle-bvalid-before-clocked-handshake) | H | non-datapath-refactor | directed-only (same-cycle BVALID stress) | fixed | Phase B B059 | `21aca89` | The AXI completer deasserted BVALID before the DUT could sample a same-cycle B-channel handshake. |
| [BUG-006-R](#bug-006-r-eoe-tail-could-remain-behind-short-final-aw) | R | soft error | common (EOE after full FIFO beats but before a 16-beat burst is available) | fixed | Phase B B063 | `21aca89` | The writer could latch a short final AW before the packer had pushed the EOE partial tail into the FIFO. |
| [BUG-007-R](#bug-007-r-eoe-reporting-could-close-before-later-event-beats-drained) | R | soft error | occasional (multi-event EOE jobs under host B-channel latency) | fixed | Phase B B066 | `c884e45` | The writer stopped accepting later event beats and reported after the first EOE/B response instead of draining all accepted multi-event data. |

## 2026-05-10

### BUG-007-R: EOE reporting could close before later event beats drained
- First seen in:
  - generated Phase B case `B066` while expanding `B065-B080` on
    `2026-05-10`
  - isolated dual-debug reruns of
    `make -C tb/uvm -j2 phase_b_dbg1 phase_b_dbg2 REGRESS_CASES="test_b066_phase_b:B066"`
- Symptom:
  - the targeted B066 multi-event job drove five 8-word EOE events with
    B-channel latency
  - before the RTL repair, B066 reported only the first event:
    `job bytes mismatch got=32 expected=160`,
    `seg0 bytes mismatch got=32 expected=160`, and then timed out once the
    harness waited for the documented full multi-event completion
  - after accepting input beyond the first EOE but still reporting from
    `WR_WAITING_B` on `writer.eoe_seen`, DEBUG_LEVEL=2 showed a residual
    `got=8 expected=40`
- Root cause:
  - `rdma_dma_writer` used `writer.eoe_seen` as both the sticky status bit
    and the job-closing condition
  - once the first EOE was observed, `accepting_input` went low, so later
    legal event words from the same job were dropped from the data path
  - after input acceptance was reopened, `WR_WAITING_B` still reported as
    soon as the first B response arrived with `writer.eoe_seen=1`, even when
    later event beats remained queued in the packer/FIFO
- Fix status:
  - state: fixed; multi-event EOE jobs now drain all accepted event beats
    before report
  - mechanism: the writer keeps accepting legal input after the first EOE,
    counts every accepted EOE pulse, and uses `eoe_report_ready` rather than
    raw `writer.eoe_seen` to leave `WR_WAITING_B`
  - before_fix_outcome: B066 reported 32 bytes against a 160-byte
    expectation, and the intermediate RTL change still left DEBUG_LEVEL=2
    lineage residual `got=8 expected=40`
  - after_fix_outcome: `B065-B080` passed under DEBUG_LEVEL=1 and
    DEBUG_LEVEL=2; `make -C tb/uvm cross_validate CASES="B065 ... B080"`
    reported zero residual mismatch across all 16 cases; `make -C tb/uvm
    merge_case_ucdbs REGRESS_CASE_IDS="B065 ... B080"` wrote `B065.ucdb`
    through `B080.ucdb` with `Errors: 0`
  - potential_hazard: closed for legal multi-event EOE jobs covered by
    B066, B074, B076, and B078; longer PROF multi-event soaks remain part of
    the later Phase B expansion
  - Claude Opus 4.7 xhigh review decision: pending / not run
- Runtime / coverage context:
  - after-fix B066 observes `opq=40 aw=2 w=5 b=2 done=1 mismatches=0`
    in both debug lanes
  - after-fix B078 observes `opq=100 aw=7 w=100 b=7 done=1 mismatches=0`
    in both debug lanes
- Commit:
  - `c884e45`

### BUG-006-R: EOE tail could remain behind short final AW
- First seen in:
  - `make -C tb/uvm -j2 phase_b_dbg1 phase_b_dbg2 REGRESS_CASES="test_b049_phase_b:B049 ... test_b064_phase_b:B064"` on `2026-05-10`
  - generated Phase B case `B063` under DEBUG_LEVEL=1 and DEBUG_LEVEL=2
- Symptom:
  - `B063` completed instead of timing out, but the report showed only the
    full FIFO beats that had reached the writer before the EOE tail
  - DEBUG_LEVEL=1 reported `job bytes mismatch got=224 expected=252` and
    `seg0 bytes mismatch got=224 expected=252`
  - DEBUG_LEVEL=2 additionally reported `DEBUG=2 lineage residual got=56
    expected=63`
- Root cause:
  - `rdma_dma_packer` raises `eoe_pulse` when the last OPQ word is accepted,
    before a non-full final packed beat has necessarily been emitted into the
    data FIFO
  - `rdma_dma_writer` treated `writer.eoe_seen` alone as permission to latch
    a short final AW, so an event with seven full DMA beats already in the
    FIFO and a partial EOE tail still inside the packer issued a seven-beat
    AW and then reported completion after the B response
  - the generated B063 stimulus also diverged from `tb/DV_BASIC.md` by driving
    63 OPQ words instead of the documented 100-word counter case, which made
    the same tail-drain bug visible with a 7-word residue
- Fix status:
  - state: fixed; short final EOE bursts now wait for the packer tail when
    fewer than `MAX_BURST_BEATS` FIFO entries are available
  - mechanism: the writer gates the EOE-driven AW latch on `packer_empty`
    unless the FIFO already holds at least a full max burst; B063 stimulus now
    drives the documented 100 OPQ words
  - before_fix_outcome: `B063` reported 224 useful bytes and 56 DEBUG=2
    lineage emissions against a 252-byte / 63-lineage expectation
  - after_fix_outcome: isolated `B063` rerun passed in both debug lanes with
    `opq=100 aw=1 w=13 b=1 done=1 mismatches=0`, and the full `B049-B064`
    slice then passed in both debug lanes; `make -C tb/uvm cross_validate
    CASES="B049 ... B064"` reported zero residual mismatch, and `make -C
    tb/uvm merge_case_ucdbs REGRESS_CASE_IDS="B049 ... B064"` wrote
    `B049.ucdb` through `B064.ucdb` with `Errors: 0`
  - potential_hazard: closed for legal partial EOE tails that trail fewer than
    16 full FIFO beats; full-FIFO tail backpressure remains allowed to drain a
    max burst first
  - Claude Opus 4.7 xhigh review decision: pending / not run
- Runtime / coverage context:
  - failing logs were captured at `tb/uvm/logs/dbg1/B063.log` and
    `tb/uvm/logs/dbg2/B063.log`
- Commit:
  - `21aca89`

### BUG-005-H: AXI completer dropped same-cycle BVALID before clocked handshake
- First seen in:
  - `make -C tb/uvm -j2 phase_b_dbg1 phase_b_dbg2 REGRESS_CASES="test_b049_phase_b:B049 ... test_b064_phase_b:B064"` on `2026-05-10`
  - generated Phase B case `B059` under DEBUG_LEVEL=1 and DEBUG_LEVEL=2
- Symptom:
  - `B049` through `B058` passed in both debug lanes
  - `B059` timed out waiting for `job_done` after the completer scheduled
    `bvalid_lag=0`
  - the DUT stayed in the B wait path because it never sampled a valid
    B-channel handshake
- Root cause:
  - `axi4_write_driver.sv` asserted `m_axi_bvalid` on a negedge when the
    WLAST beat completed
  - when the DUT entered `WR_WAITING_B`, `m_axi_bready` became high
    combinationally, and the driver deasserted `m_axi_bvalid` on the next
    negedge before the DUT could sample `m_axi_bvalid && m_axi_bready` on a
    clock edge
  - AXI VALID must remain asserted until a clocked READY/VALID handshake is
    observed, so the testbench completer was under-driving the same-cycle B
    response stress
- Fix status:
  - state: fixed; same-cycle BVALID stress now completes
  - mechanism: the AXI completer now marks a B clear pending when it first
    observes `m_axi_bvalid && m_axi_bready` and only drops BVALID on the
    following negedge, after the DUT has had a positive edge to sample the
    handshake
  - before_fix_outcome: `B059` timed out at `1204198 ns` in both debug lanes
  - after_fix_outcome: isolated `B059` rerun passed in both debug lanes with
    `opq=512 aw=4 w=64 b=4 done=1 mismatches=0`, and the full `B049-B064`
    slice then passed in both debug lanes; `make -C tb/uvm cross_validate
    CASES="B049 ... B064"` reported zero residual mismatch, and `make -C
    tb/uvm merge_case_ucdbs REGRESS_CASE_IDS="B049 ... B064"` wrote
    `B049.ucdb` through `B064.ucdb` with `Errors: 0`
  - potential_hazard: closed for the UVM completer; this does not change RTL
    B-channel behavior
  - Claude Opus 4.7 xhigh review decision: pending / not run
- Runtime / coverage context:
  - failing logs were captured at `tb/uvm/logs/dbg1/B059.log` and
    `tb/uvm/logs/dbg2/B059.log`
- Commit:
  - `21aca89`

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
