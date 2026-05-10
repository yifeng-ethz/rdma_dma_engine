# DV Edge - rdma_dma_engine

**Companion docs:** `DV_PLAN.md`, `DV_HARNESS.md`, `DV_BASIC.md`,
`DV_PROF.md`, `DV_ERROR.md`, `DV_CROSS.md`, `DV_COV.md`,
`BUG_HISTORY.md`.

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**ID Range:** E001-E128
**Total:** 128 cases (0 implemented / 0 waived)

This document collects the corner / boundary cases for
`rdma_dma_engine`. Every row pins a specific contract or arithmetic
boundary on the DUT. Cases are derived from `DV_PLAN.md` section 3 and the
AXI4 burst-sizing arithmetic in `RTL_PLAN.md` section 4.3.

**Methodology key:**
- **D** = Directed (hand-crafted stimulus, single transaction)
- **R** = Constrained-random (UVM `rand` constraints; multiple
  transactions per case)

---

## 1. Summary

| Section | Cases | ID Range | What it Proves | Current Case |
|---------|------:|----------|----------------|--------------|
| Span boundary edges | 10 | E001-E010 | span sizes at 4 KB granularity boundaries; minimum and maximum legal values | 0/10 |
| Address boundary edges | 10 | E011-E020 | addresses at 4 KB / 64 KiB / 4 GiB / addressable-max boundaries | 0/10 |
| AXI4 burst-sizing edges | 10 | E021-E030 | edge cases of awlen / awsize / 4 KB no-cross at burst-sizing boundaries | 0/10 |
| FIFO almost-full / empty edges | 10 | E031-E040 | FIFO threshold transitions, drain on exit-from-empty, fill from empty | 0/10 |
| Packer flush edges | 12 | E041-E052 | EOE-pad behavior, slot index walks, partial line at every slot index | 0/12 |
| Segment boundary edges | 10 | E053-E062 | seg0->seg1 transition under various conditions: mid-burst, on-burst-edge, on-EOE-pad | 0/10 |
| Job-end condition edges | 8 | E063-E070 | EOE / FULL / both, with various burst alignments | 0/8 |
| Two-job back-to-back edges | 8 | E071-E078 | second job_req exactly at job_done; second job with different sqe_id | 0/8 |
| DEBUG_LEVEL=1 invariant edges | 6 | E079-E084 | dbg1 taps consistency at every FSM transition and counter event | 0/6 |
| DEBUG_LEVEL=2 sidecar edges | 6 | E085-E090 | lineage matcher edge cases: padding, halt, wraparound | 0/6 |
| Random nominal corner-case smoke | 4 | E091-E094 | random stimuli targeting boundary regions | 0/4 |
| FIFO depth corners | 8 | E095-E102 | FIFO at extreme levels and around the almost-full threshold | 0/8 |
| Writer FSM transition corners | 6 | E103-E108 | rare transitions: PROGRAM->REPORT_DONE, AW->PROGRAM, multi-step | 0/6 |
| Counter overflow corners | 3 | E109-E111 | 32-bit cnt_* near saturation; clear behavior at boundary | 0/3 |
| Job-interface concurrent activity | 5 | E112-E116 | job_req and OPQ activity overlapping at unusual moments | 0/5 |
| Mixed traffic randomization | 4 | E117-E120 | directed edge cases revisited under mild randomization | 0/4 |
| Timestamp tracking edges | 3 | E121-E123 | first/last_event_ts at boundary conditions | 0/3 |
| Continuation across multiple jobs | 5 | E124-E128 | back-to-back jobs sharing FIFO state | 0/5 |

---

## 2. Span boundary edges (E001-E010)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E001 | D | seg0_span = 0x1000 (minimum legal 4 KB) | 1 | seg0_span=4096; drive 1024 OPQ words. | Engine accepts; status[FULL] on exhaustion. | TBD |
| E002 | D | seg0_span = 0x2000 (8 KB boundary) | 1 | seg0_span=8192. | Engine completes 2 KB worth of W beats. | TBD |
| E003 | D | seg0_span = 0x10_0000 (1 MiB boundary) | 1 | seg0_span=0x10_0000. | Engine completes 1 MiB of W. | TBD |
| E004 | D | seg0_span = 0x1_0000_0000 (4 GiB - Phase 1 max) | 1 | seg0_span=0x1_0000_0000. | Engine accepts; iteratively burst-writes 4 GiB. | TBD |
| E005 | D | seg1_span boundary identical to seg0_span boundary | 1 | Both at 4 KB. | Boundary transition at 4 KB. | TBD |
| E006 | D | seg0_span at exactly 1 burst (512 B) | 1 | seg0_span=0x200; FULL on 1 AW. | One AW awlen==15; no extra burst. | TBD |
| E007 | D | seg0_span at exactly 2 bursts (1 KB) | 1 | seg0_span=0x400. | Exactly 2 AWs at awlen==15. | TBD |
| E008 | D | seg0_span at 1 byte over 1 burst (incl. 4 KB padding) | 1 | seg0_span=0x1000 (next 4 KB up). | Engine accepts; 32-beat burst sequence. | TBD |
| E009 | D | seg1_span = 0 (single-segment override) | 1 | seg1_span=0. | SEG0_ONLY=1; seg1 not entered. | TBD |
| E010 | D | seg0_addr+seg0_span aligned to 4 GiB boundary | 1 | seg0_addr=0xFFFF_F000, seg0_span=0x1000. | Last AW at 0xFFFF_FFE0; no overflow. | TBD |

---

## 3. Address boundary edges (E011-E020)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E011 | D | seg0_addr=0 (lowest legal) | 1 | seg0_addr=0; drive job. | First AW at 0. | TBD |
| E012 | D | seg0_addr=0x1000 (smallest non-zero 4 KB) | 1 | seg0_addr=0x1000. | AW at 0x1000. | TBD |
| E013 | D | seg0_addr at 64 KiB boundary | 1 | seg0_addr=0x10000. | AW at 0x10000. | TBD |
| E014 | D | seg0_addr at 4 MiB boundary | 1 | seg0_addr=0x40_0000. | AW correctly placed. | TBD |
| E015 | D | seg0_addr at 4 GiB boundary | 1 | seg0_addr=0x1_0000_0000. | AW upper 32 b correctly driven. | TBD |
| E016 | D | seg0_addr at 64 GiB boundary (high addr) | 1 | seg0_addr=0x10_0000_0000. | AW addr correctly extended. | TBD |
| E017 | D | seg0_addr just below 64-bit max (4 KB-aligned) | 1 | seg0_addr=0xFFFF_FFFF_FFFF_F000. | AW addr propagated. | TBD |
| E018 | D | seg1_addr ahead of seg0 (descending addrs) | 1 | seg0_addr=0x100000, seg1_addr=0x80000. | Engine accepts; seg1 AW at 0x80000. | TBD |
| E019 | D | seg1_addr identical to seg0_addr+seg0_span (contiguous) | 1 | Adjacent. | Two ranges back-to-back. | TBD |
| E020 | D | seg1_addr in different DRAM channel (high bit set) | 1 | seg0_addr=0x1000, seg1_addr=0x1000_0000. | Both AWs correctly placed. | TBD |

---

## 4. AXI4 burst-sizing edges (E021-E030)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E021 | D | awlen=0 (1-beat burst) at exact end of segment | 1 | seg0_span=0x20 (32 B = 1 beat). | First AW awlen==0; one W; B. | TBD |
| E022 | D | awlen=0 at end of segment after large initial bursts | 1 | seg0_span=0x220 (16 + 1 beats); fill gradually. | First AW awlen=15, then awlen=0 closes seg0. | TBD |
| E023 | D | awlen=15 at exact burst-aligned span (512 B) | 1 | seg0_span=0x200 (16 beats). | One AW awlen=15; no extra. | TBD |
| E024 | D | awlen smaller because fifo holds <16 beats at issue | 1 | Throttle OPQ so FIFO holds 5 beats at AW. | First AW awlen<=4. | TBD |
| E025 | D | awlen reduced because beats_left_in_seg < MAX | 1 | seg0_span=0x80 (4 beats). | First AW awlen==3. | TBD |
| E026 | D | Burst at start of 4 KB page | 1 | seg0_addr=0x1000. | First AW at 0x1000; never crosses page. | TBD |
| E027 | D | Burst at end of 4 KB page (last beat) | 1 | Address advances to 0x1FE0 (last beat in page). | Burst ends at 0x1FFF; next AW starts at 0x2000. | TBD |
| E028 | D | Burst region exactly fills a 4 KB page (16 beats) | 1 | seg0_addr=0x1000, seg0_span=0x1000. | Two bursts at awlen=15; first at 0x1000-0x11FF, second at 0x1200-0x13FF, etc. | TBD |
| E029 | D | 1 KB-aligned address with 512 B burst (no cross) | 1 | seg0_addr=0x1400, large span. | First AW at 0x1400 awlen=15; addr+512=0x1600 still in 4 KB page. | TBD |
| E030 | D | Burst sizing varies cycle-to-cycle (fifo level varies) | 1 | Random throttle. | awlen tracks min(fifo_level, MAX-1, beats_left). | TBD |

---

## 5. FIFO almost-full / empty edges (E031-E040)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E031 | D | FIFO at threshold-1 (191) then crosses to 192 | 1 | Drive 191 beats; almost_full=0. One more. | almost_full transitions 0->1. | TBD |
| E032 | D | FIFO at threshold (192) then drains to 191 | 1 | FIFO at 192; one read. | almost_full transitions 1->0. | TBD |
| E033 | D | FIFO at exact depth (256) | 1 | Throttle reads; pile to 256. | level==256; almost_full=1; packer halt asserted. | TBD |
| E034 | D | FIFO depth-1 (255) | 1 | Pile to 255. | level==255; almost_full=1. | TBD |
| E035 | D | Empty FIFO with pending OPQ data | 1 | FIFO empty, packer slot=4, OPQ valid. | Packer fills toward beat boundary; FIFO write on slot 8. | TBD |
| E036 | D | FIFO single-beat dwell (1 entry) | 1 | Push 1 beat; pop 1 beat. | level walks 0->1->0. | TBD |
| E037 | D | FIFO fill from empty under sustained OPQ | 1 | Empty FIFO; drive 100% OPQ. | level monotonically increases 0..192. | TBD |
| E038 | D | FIFO drain to empty under sustained host wready | 1 | Pre-fill FIFO to 256; host always-ready. | level decreases 256..0. | TBD |
| E039 | D | almost_full pulse triggers packer halt for exactly 1 clk | 1 | Single-cycle threshold cross. | dbg1_halt_pulse=1 only on transition. | TBD |
| E040 | D | FIFO occupancy reported via dbg1 even when empty | 1 | Reset state, FIFO empty. | dbg1_fifo_level==0. | TBD |

---

## 6. Packer flush edges (E041-E052)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E041 | D | EOE on slot 1 (1 word in beat) | 1 | 1 OPQ word + tlast. | 1-slot beat; bytes_in_word=4; padding=0xCDCD... | TBD |
| E042 | D | EOE on slot 2 | 1 | 2 words + tlast. | 2-slot beat; bytes_in_word=8. | TBD |
| E043 | D | EOE on slot 3 | 1 | 3 + tlast. | 3-slot; bytes_in_word=12. | TBD |
| E044 | D | EOE on slot 4 | 1 | 4 + tlast. | 4-slot; bytes_in_word=16. | TBD |
| E045 | D | EOE on slot 5 | 1 | 5 + tlast. | 5-slot; bytes_in_word=20. | TBD |
| E046 | D | EOE on slot 6 | 1 | 6 + tlast. | 6-slot; bytes_in_word=24. | TBD |
| E047 | D | EOE on slot 7 | 1 | 7 + tlast. | 7-slot; bytes_in_word=28. | TBD |
| E048 | D | EOE on slot 8 (full beat) | 1 | 8 + tlast. | Full beat; bytes_in_word=32; no padding. | TBD |
| E049 | D | EOE on slot 1 of next beat after full beat (boundary) | 1 | 8 + 1 + tlast. | First full beat then 1-slot flush. | TBD |
| E050 | D | Two EOEs back-to-back (zero-byte event between) | 1 | tlast tlast. | Two flushes; cnt_eoe_observed==2. | TBD |
| E051 | D | EOE arrives same cycle slot reaches 8 | 1 | Drive 8 with last beat carrying tlast. | Single full beat with last_in_event=1. | TBD |
| E052 | D | EOE arrives at idle (slot=0) after a fresh job | 1 | 0 data + tlast immediately after job_req. | 0-slot zero-byte event; bytes_written_total=0; status[EOE]=1. | TBD |

---

## 7. Segment boundary edges (E053-E062)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E053 | D | seg0 fills exactly on burst boundary, seg1 starts | 1 | seg0_span=0x200 (1 burst); fill. | seg0 closes with 1 AW; seg1 opens with new AW at seg1_addr. | TBD |
| E054 | D | seg0 fills on partial burst (4 beats), seg1 starts | 1 | seg0_span=0x80 (4 beats). | Seg0 closes with awlen=3; seg1 starts fresh. | TBD |
| E055 | D | seg0 fills on EOE-pad mid-burst, transitions to seg1 | 1 | seg0_span=0x100; EOE on slot 5 of beat 7 (within seg0). | EOE wins; status[EOE]=1; seg1 not entered. | TBD |
| E056 | D | seg0 fills exactly at FIFO-empty moment | 1 | seg0_span=0x40 (2 beats); host fast. | FIFO drains to 0 at boundary; seg1 stalls until refill. | TBD |
| E057 | D | seg0 fills with FIFO half full at boundary | 1 | seg0_span=0x100; FIFO at 128 entries. | Seg1 first AW immediately. | TBD |
| E058 | D | seg1 fills on partial burst (FULL bit) | 1 | seg0_span=0x40, seg1_span=0x80; drive 12 beats. | FULL on seg1; SEG_BOUNDARY_HIT=1. | TBD |
| E059 | D | seg0=4KB, seg1=4KB, EOE arrives during seg1 | 1 | Drive 1024+512 words then tlast. | EOE; SEG_BOUNDARY_HIT=1; seg0=4096; seg1=2048. | TBD |
| E060 | D | seg0 ends, seg1 starts within same FSM cycle | 1 | Tight transition. | FSM: WR_B(seg0) -> WR_PROGRAM (seg1) -> WR_AW seg1 in 2 clk. | TBD |
| E061 | D | Seg-boundary AW issued without W underrun | 1 | Throttle OPQ at boundary. | Engine awaits enough FIFO before issuing seg1 AW. | TBD |
| E062 | D | Seg-boundary at high address (4 GiB) | 1 | seg0_addr=0xFFFF_F000, seg1_addr=0x1_0000_0000. | Boundary across 4 GiB; addresses correctly emitted. | TBD |

---

## 8. Job-end condition edges (E063-E070)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E063 | D | EOE between bursts (FIFO empty exactly) | 1 | EOE arrives with 0 FIFO entries pending. | No additional W; status[EOE]=1; bytes_written reflects already-flushed. | TBD |
| E064 | D | EOE during last W-beat of burst (wlast same cycle) | 1 | EOE arrives at the cycle of wlast. | Burst closes; EOE pad is next beat; status[EOE]=1. | TBD |
| E065 | D | EOE during AW phase (no W issued yet) | 1 | EOE arrives while engine in WR_AW. | Engine completes the AW it just issued; flushes; EOE on next idle. | TBD |
| E066 | D | EOE during PROGRAM phase (between segments) | 1 | EOE arrives in WR_PROGRAM. | Engine programs seg1, then EOE flushes. | TBD |
| E067 | D | FULL exactly on burst boundary | 1 | Span exactly fills up at burst end. | Last W beat in burst; B; status[FULL]=1. | TBD |
| E068 | D | FULL before any W issued (zero-span legal? error) | 1 | seg0_span=0 with seg1_span=0 (both zero -- ALIGN_ERR). | ALIGN_ERR (covered in ERROR bucket). | TBD |
| E069 | D | FULL on partial burst (4 beats) | 1 | seg0_span=0x80 (4 beats). | One AW awlen==3; B; FULL. | TBD |
| E070 | D | EOE same cycle FULL | 1 | EOE arrives at exact byte count of seg. | Both bits set. | TBD |

---

## 9. Two-job back-to-back edges (E071-E078)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E071 | D | Second job_req exactly 1 clk after job_done | 1 | Issue job_req on the cycle after job_done. | Engine accepts; second job runs cleanly. | TBD |
| E072 | D | Second job_req same cycle as job_done (overlap) | 1 | Issue job_req on the same cycle as job_done. | Engine accepts (per SVA); next IDLE entry sees the new req. | TBD |
| E073 | D | Two jobs with same sqe_id (legal) | 1 | Both with sqe_id=0x1234. | Both echo back same id; engine accepts. | TBD |
| E074 | D | Two jobs with sqe_id=0 then 0xFFFF | 1 | Walk extremes. | Echos correct. | TBD |
| E075 | D | Three jobs back-to-back | 1 | 3 single-segment 4 KB jobs. | All 3 complete in order; counters monotonic. | TBD |
| E076 | D | Two jobs separated by 1000 idle clks | 1 | Idle gap. | Both complete; engine returns to WR_IDLE between. | TBD |
| E077 | D | Two jobs with different opcodes | 1 | Both opcode=0x0001 (only legal Phase 1). | Both run. | TBD |
| E078 | D | Two jobs differing in seg sizes (4 KB vs 16 KB) | 1 | Mixed. | Both complete. | TBD |

---

## 10. DEBUG_LEVEL=1 invariant edges (E079-E084)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E079 | D | dbg1_w_beats_remaining reaches 0 exactly at wlast | 1 | Long burst. | Reaches 0 on wlast cycle. | TBD |
| E080 | D | dbg1_aw_inflight delta == 1 per AW handshake | 1 | 10 bursts. | Each AW raises by 1; each B drops by 1. | TBD |
| E081 | D | dbg1_aw_inflight stays 0 in IDLE | 1 | Idle period. | 0 throughout. | TBD |
| E082 | D | dbg1_packer_pending_eoe asserts on tlast latched | 1 | tlast latched mid-FIFO-pause. | Asserts; clears on flush. | TBD |
| E083 | D | dbg1_writer_state hops match cycle-by-cycle FSM | 1 | Long job. | All transitions captured cycle-precise. | TBD |
| E084 | D | dbg1_halt_pulse asserts iff packer drops a beat | 1 | Halt event. | Asserted exactly on the dropped clk. | TBD |

---

## 11. DEBUG_LEVEL=2 sidecar edges (E085-E090)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E085 | D | DEBUG=2 lineage with EOE-pad on slot 5 | 1 | DEBUG=2; EOE on slot 5. | Matcher consumes 5 ingress entries; remaining 3 slots reported as padding. | TBD |
| E086 | D | DEBUG=2 lineage across halt event | 1 | DEBUG=2; force 4-beat halt. | Halted beats appear in ingress queue; matcher residual == cnt_halt at job_done. | TBD |
| E087 | D | DEBUG=2 lineage hit_id wraparound (>65535) | 1 | DEBUG=2; long drain to wrap 16-bit hit_id. | Wraparound handled; matcher does not double-consume. | TBD |
| E088 | D | DEBUG=2 sequence_no monotonic across drain | 1 | DEBUG=2; multi-event drain. | sequence_no never repeats inside a drain. | TBD |
| E089 | D | DEBUG=2 source_ts monotonic per lane | 1 | DEBUG=2; one lane. | source_ts monotonic across events. | TBD |
| E090 | D | DEBUG=2 sidecar inert in DEBUG=1 build (regression) | 1 | DEBUG=1; same stim. | dbg2_meta_* always 0; payload bit-identical to DEBUG=2 payload. | TBD |

---

## 12. Random nominal corner-case smoke (E091-E094)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E091 | R | Random spans on 4 KB grid {4,8,16,32,64} KB | 32 | rand seg0_span and seg1_span on 4 KB grid. | Per-job conservation; lineage zero residual. | TBD |
| E092 | R | Random EOE positions in last beat (slot 1..8) | 16 | rand EOE-pad position. | bytes_in_word matches expected; status[EOE]=1. | TBD |
| E093 | R | Random 2-segment with random transition point | 16 | rand transition. | SEG_BOUNDARY_HIT correctly set; per-job conservation. | TBD |
| E094 | R | Random burst sizes across 32-job stream | 32 | Mixed FIFO levels. | All bursts <=15; no 4 KB cross. | TBD |

---

## 13. FIFO depth corners (E095-E102)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E095 | D | FIFO at 191 (one below threshold) | 1 | Carefully drive level to 191. | almost_full=0; one more entry triggers almost_full=1. | TBD |
| E096 | D | FIFO clamps at threshold while one above-threshold ingress beat is dropped | 1 | Drive to level 192, then continue OPQ ingress while almost_full=1. | max dbg1_fifo_level==192; cnt_halt increments for dropped OPQ words. | TBD |
| E097 | D | FIFO depth-1 guard is unreachable through legal ingress | 1 | Drive to level 192, then attempt 63 more 256-bit entries while host is stalled. | max dbg1_fifo_level==192; cnt_halt counts the suppressed OPQ words. | TBD |
| E098 | D | FIFO depth guard suppresses full-depth overfill attempts | 1 | Drive to level 192, then attempt 64 more 256-bit entries while host is stalled. | max dbg1_fifo_level==192; no stored level 256 is observed. | TBD |
| E099 | D | FIFO recovery from almost-full halt | 1 | Halt at threshold -> drain -> normal. | After drain, a new job accepts and writes normally. | TBD |
| E100 | D | FIFO 1-cycle write-read with simultaneous | 1 | Sustained ingress with host always ready. | At least one steady-state write/read cycle leaves level unchanged. | TBD |
| E101 | D | FIFO single-write-only burst | 1 | Write 16 entries fast. | Level walks 0->16 in 16 clks. | TBD |
| E102 | D | FIFO single-read-only burst | 1 | Read 16 entries fast. | Level walks 16->0. | TBD |

---

## 14. Writer FSM transition corners (E103-E108)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E103 | D | WR_PROGRAM directly to WR_REPORT_DONE on ALIGN_ERR | 1 | ALIGN_ERR job_req. | FSM: IDLE->PROGRAM->REPORT_ALIGN_ERR (or REPORT_DONE)->IDLE. | TBD |
| E104 | D | WR_AW->WR_W->WR_B->WR_PROGRAM (seg0 done, seg1 valid) | 1 | Two-seg with exact seg0 fill. | FSM walks PROGRAM stage twice in one job. | TBD |
| E105 | D | WR_B->WR_AW (same segment, multi-burst) | 1 | Long single-segment. | B->AW transition observed many times. | TBD |
| E106 | D | WR_AW stalled until awready (long lag) | 1 | Lag=64. | FSM holds in WR_AW. | TBD |
| E107 | D | WR_W stalled until wready (long lag) | 1 | Lag=64. | FSM holds in WR_W; wvalid stable. | TBD |
| E108 | D | WR_B stalled until bvalid (long lag) | 1 | Lag=64. | FSM holds in WR_B. | TBD |

---

## 15. Counter overflow corners (E109-E111)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E109 | D | cnt_input_w near 0xFFFF_FFFF (manual preload) | 1 | Force preload via TB; drive accepted OPQ beats. | cnt_input_w saturates at 0xFFFF_FFFF. | TBD |
| E110 | D | cnt_bytes_written near 0xFFFF_FFFF (preload) | 1 | Preload + W beats. | cnt_bytes_written saturates at 0xFFFF_FFFF. | TBD |
| E111 | D | Counter clear with values at max | 1 | Preload max; pulse clear. | All zero. | TBD |

---

## 16. Job-interface concurrent activity (E112-E116)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E112 | D | job_req while OPQ idle | 1 | OPQ tvalid=0 throughout the probe window. | Engine accepts; sits in WR_ISSUING_AW waiting for FIFO data. | TBD |
| E113 | D | job_req then immediate OPQ burst | 1 | Tight timing. | First burst latency tracks model. | TBD |
| E114 | D | OPQ burst then late job_req | 1 | Drive 100 OPQ beats with no job (FIFO accumulates? no -- packer stays idle until job). | Engine ignores OPQ until job_req per RTL spec; cnt_input_w may or may not advance per RTL. | TBD |
| E115 | D | job_req with seg0_addr=0xFFFF_FFFF_0000_0000 (high half) | 1 | High half. | Address propagated correctly. | TBD |
| E116 | D | job_done while OPQ continues to drive | 1 | OPQ still bursting after engine done. | Engine ignores extra OPQ until next job_req. | TBD |

---

## 17. Mixed traffic randomization (E117-E120)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E117 | R | Random EOE position with throttled host | 16 | rand EOE + throttle. | Conservation. | TBD |
| E118 | R | Random alignment (50% misaligned, 50% aligned) | 32 | Mix. | ALIGN_ERR captured per misaligned; valid jobs run. | TBD |
| E119 | R | Random multi-event drains (1..8 events) per job | 16 | rand event count. | cnt_eoe_observed matches. | TBD |
| E120 | R | Random combination span+EOE+throttle | 16 | joint rand. | All complete; SVA passes. | TBD |

---

## 18. Timestamp tracking edges (E121-E123)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E121 | D | first_event_ts and last_event_ts identical | 1 | Single event drain. | first_event_ts == last_event_ts. | TBD |
| E122 | D | first_event_ts captured on first cycle of job | 1 | EOE arrives mid-job. | first_event_ts == cycle of first tlast. | TBD |
| E123 | D | last_event_ts overrides first_event_ts on later EOE | 1 | Multi-event. | last_event_ts > first_event_ts. | TBD |

---

## 19. Continuation across multiple jobs (E124-E128)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| E124 | D | Two jobs with FIFO non-empty at job_done of first | 1 | Engineering edge. | Per-spec: FIFO drains before job_done; second job starts clean. | TBD |
| E125 | D | Job_req with engine in just-completed state | 1 | Tight back-to-back. | Engine completes seamlessly. | TBD |
| E126 | D | Three back-to-back jobs varying spans | 1 | Mixed. | All complete; conservation. | TBD |
| E127 | D | Two-segment job back-to-back single-segment job | 1 | Mixed. | All complete. | TBD |
| E128 | D | Two-job sequence with first ALIGN_ERR | 1 | First refused. | Second job runs cleanly. | TBD |

---
