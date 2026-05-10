# DV Basic — rdma_dma_engine

**Companion docs:** `DV_PLAN.md`, `DV_HARNESS.md`, `DV_EDGE.md`,
`DV_PROF.md`, `DV_ERROR.md`, `DV_CROSS.md`, `DV_COV.md`,
`BUG_HISTORY.md`.

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**ID Range:** B001-B128
**Total:** 128 cases (0 implemented / 0 waived)

This document expands every `DV_PLAN.md` Phase-1 standard-functional
contract for `rdma_dma_engine` into a directed test specification.
Every row pins one specific port, FSM state, counter, dbg1 tap, or
dbg2 sidecar field on the DUT as defined in `../RTL_PLAN.md` and
`DV_HARNESS.md`.

**Methodology key:**
- **D** = Directed (hand-crafted stimulus, single transaction)
- **R** = Constrained-random (UVM `rand` constraints; multiple
  transactions per case)

---

## 1. Summary

| Section | Cases | ID Range | What it Proves | Current Case |
|---------|------:|----------|----------------|--------------|
| Reset and idle defaults | 12 | B001-B012 | post-reset state of FSM, FIFO empty, AW/W/B idle, counters at 0, dbg1 taps coherent | 0/12 |
| Single-segment job DRAIN_UNTIL_EOE happy path | 16 | B013-B028 | one full single-segment job from job_req through job_done with EOE arrival | 0/16 |
| Two-segment scatter happy path | 12 | B029-B040 | two-segment jobs with seg0->seg1 transition and SEG_BOUNDARY_HIT bit | 0/12 |
| AXI4 burst-sizing baseline | 12 | B041-B052 | burst length, addr alignment, awsize, awburst all per AXI4 spec for the IP's parameters | 0/12 |
| AXI4 W-channel and B-channel contract | 10 | B053-B062 | W-beat counting, wlast placement, B handshake, BRESP=OKAY default | 0/10 |
| Counter accuracy and conservation | 10 | B063-B072 | cnt_* increment per spec; conservation invariant cnt_input_w*4 == bytes_written + halt_bytes | 0/10 |
| Per-event timestamp tracking | 6 | B073-B078 | first_event_ts, last_event_ts, event_count fields populated correctly | 0/6 |
| Status bit semantics | 8 | B079-B086 | status[EOE], status[FULL], status[SEG0_ONLY], status[SEG_BOUNDARY_HIT], status[HALT] coverage | 0/8 |
| Job-interface handshake | 6 | B087-B092 | job_req single-cycle latch; job_done single-cycle pulse; report-field hold | 0/6 |
| DEBUG_LEVEL=1 fill-level / FSM observability | 8 | B093-B100 | dbg1_* taps reflect internal state coherently and consistently | 0/8 |
| DEBUG_LEVEL=2 sidecar lineage smoke | 7 | B101-B107 | ingress sidecar arrives intact at writer-shadow port; matcher reports zero-residual | 0/7 |
| Random nominal smoke | 3 | B108-B110 | constrained-random multi-job streams under default latency profile, no errors | 0/3 |
| Per-segment bytes-written accuracy | 6 | B111-B116 | seg0_bytes_written and seg1_bytes_written report the exact useful byte count per segment | 0/6 |
| Smoke for QUEUE_MATH analytical model linkage | 6 | B117-B122 | ties the BASIC functional cases to the queue-math model in QUEUE_MATH.md | 0/6 |
| Sideband cnt_* propagation | 6 | B123-B128 | counters drive run_manager surfacing correctly across job boundaries | 0/6 |

---

## 2. Reset and idle defaults (B001-B012)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B001 | D | Post-reset writer FSM in WR_IDLE | 1 | Hold reset_n=0 for 16 clk, release; wait 8 clk. | dbg1_writer_state == WR_IDLE; m_axi_awvalid == 0; m_axi_wvalid == 0; m_axi_bready == 0. | TBD |
| B002 | D | Post-reset packer slot index = 0 | 1 | As prior. | dbg1_packer_slot_idx == 4'h0; dbg1_packer_pending_eoe == 0. | TBD |
| B003 | D | Post-reset FIFO empty | 1 | As prior. | dbg1_fifo_level == 0; dbg1_fifo_almost_full == 0. | TBD |
| B004 | D | Post-reset cnt_input_w == 0 | 1 | As prior. | cnt_input_w == 32'h0. | TBD |
| B005 | D | Post-reset cnt_bytes_written == 0 | 1 | As prior. | cnt_bytes_written == 32'h0. | TBD |
| B006 | D | Post-reset cnt_halt == 0 | 1 | As prior. | cnt_halt == 32'h0. | TBD |
| B007 | D | Post-reset cnt_eoe_observed == 0 | 1 | As prior. | cnt_eoe_observed == 32'h0. | TBD |
| B008 | D | Post-reset job_done == 0 | 1 | As prior. | job_done == 0; all report fields stable at 0. | TBD |
| B009 | D | Post-reset s_axis_opq_tready behavior | 1 | As prior; toggle s_axis_opq_tvalid. | tready tied 1 in Phase 1; never deasserts. | TBD |
| B010 | D | Reset asserted mid-AW returns to idle | 1 | Inject job, observe FSM in WR_AW, assert reset_n=0; release. | All AW/W/B back to idle within 1 clk after reset; cnt_input_w cleared per RTL spec. | TBD |
| B011 | D | dbg1 in-flight counters at 0 post-reset | 1 | As prior. | dbg1_aw_inflight == 0; dbg1_w_beats_remaining == 0; dbg1_b_outstanding == 0. | TBD |
| B012 | D | dbg1_halt_pulse not asserted post-reset | 1 | As prior. | dbg1_halt_pulse == 0 across 64 idle clks. | TBD |

---

## 3. Single-segment job DRAIN_UNTIL_EOE happy path (B013-B028)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B013 | D | Smoke single-segment 4 KB job, 8 OPQ words, EOE arrives | 1 | seg0_addr=0x10_0000, seg0_span=0x1000, seg1_span=0; opcode=DRAIN_UNTIL_EOE; drive 8 OPQ 32 b beats with sop on first, eop on last. | job_done after one AW/W/B cycle; status[EOE]=1; status[SEG0_ONLY]=1; bytes_written_total==32; sqe_id_echo matches. | TBD |
| B014 | D | Smoke single-segment 4 KB job, 16 OPQ words | 1 | As B013 with 16 OPQ words. | Two W beats; bytes_written_total==64. | TBD |
| B015 | D | Smoke single-segment 4 KB, exactly 1 burst (16 beats) | 1 | 16 OPQ words/beat = 128 OPQ words; 16 W beats == 1 burst at MAX_BURST_BEATS=16. | One AW with awlen==15; one B; bytes_written_total==512. | TBD |
| B016 | D | Smoke single-segment 4 KB, exactly 2 bursts (32 beats) | 1 | 32 W beats = 2 bursts of 16. | Two AWs; two Bs; bytes_written_total==1024. | TBD |
| B017 | D | Smoke single-segment 8 KB exactly fills (no EOE seen) | 1 | seg0_span=0x2000; drive 2048 OPQ words without EOE. | status[FULL]=1; status[EOE]=0; bytes_written_total==8192. | TBD |
| B018 | D | Smoke single-segment 4 KB, partial-line EOE on slot 1 | 1 | drive 1 OPQ word then EOE. | Packer flushes 1-slot beat with bytes_in_word==4; bytes_written_total==4. | TBD |
| B019 | D | Smoke single-segment 4 KB, partial-line EOE on slot 4 | 1 | drive 4 OPQ words then EOE. | bytes_in_word==16; bytes_written_total==16. | TBD |
| B020 | D | Smoke single-segment 4 KB, partial-line EOE on slot 7 | 1 | 7 words then EOE. | bytes_in_word==28; bytes_written_total==28. | TBD |
| B021 | D | Smoke single-segment 4 KB, EOE on slot 8 (full beat) | 1 | 8 words then EOE. | bytes_in_word==32; bytes_written_total==32; no padding. | TBD |
| B022 | D | Smoke single-segment 4 KB, EOE alone (no data) | 1 | drive 0 data + tlast pulse. | Per spec: status[EOE]=1 with bytes_written_total==0; engine emits zero W beats. | TBD |
| B023 | D | Smoke single-segment 16 KB, multiple events | 1 | drive 4 events of 8 words each separated by tlast. | Four EOE boundaries captured; cnt_eoe_observed==4 at job_done. | TBD |
| B024 | D | Smoke single-segment with sqe_id=0xBEEF, opcode=0x0001 | 1 | Set sqe_id=0xBEEF. | sqe_id_echo==0xBEEF on completion. | TBD |
| B025 | D | Smoke single-segment with sqe_id=0x0000 | 1 | sqe_id=0x0000. | sqe_id_echo==0. | TBD |
| B026 | D | Smoke single-segment with sqe_id=0xFFFF | 1 | sqe_id=0xFFFF. | sqe_id_echo==0xFFFF. | TBD |
| B027 | D | Smoke single-segment with seg0_addr=0 | 1 | seg0_addr=0x0. | Engine accepts; first AW awaddr==0. | TBD |
| B028 | D | Smoke single-segment with high seg0_addr | 1 | seg0_addr=0xFFFF_F000 (4 KB-aligned just below 4 GiB). | Engine accepts; first AW awaddr==0xFFFF_F000. | TBD |

---

## 4. Two-segment scatter happy path (B029-B040)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B029 | D | Two-segment 4 KB+4 KB, fills both | 1 | seg0_span=0x1000, seg1_span=0x1000; drive 2048 OPQ words. | status[SEG_BOUNDARY_HIT]=1; status[FULL]=1; seg0_bytes_written==4096; seg1_bytes_written==4096. | TBD |
| B030 | D | Two-segment 8 KB+4 KB, fills only seg0 then EOE | 1 | seg0_span=0x2000, seg1_span=0x1000; drive 1024 words then EOE. | status[EOE]=1; status[SEG_BOUNDARY_HIT]=0; seg0_bytes_written==4096; seg1_bytes_written==0. | TBD |
| B031 | D | Two-segment 4 KB+8 KB, fills seg0 + half seg1, EOE | 1 | seg0_span=0x1000, seg1_span=0x2000; drive 1536 words then EOE. | SEG_BOUNDARY_HIT=1; EOE=1; seg0=4096; seg1=2048. | TBD |
| B032 | D | Two-segment seg0=4KB, exact fill of seg0 then EOE | 1 | seg0_span=0x1000, seg1_span=0x1000; 1024 words then EOE. | EOE=1; SEG_BOUNDARY_HIT=0; seg0=4096; seg1=0. | TBD |
| B033 | D | Two-segment seg0=4KB exact fill no EOE (continues to seg1) | 1 | seg0_span=0x1000, seg1_span=0x1000; 1025 words no EOE. | SEG_BOUNDARY_HIT=1; first beat of seg1 at seg1_addr. | TBD |
| B034 | D | Two-segment seg1_addr at distant address | 1 | seg0_addr=0x10_0000, seg1_addr=0xA0_0000; small spans. | First AW after boundary uses seg1_addr. | TBD |
| B035 | D | Two-segment minimum spans (4 KB each) | 1 | seg0_span=0x1000, seg1_span=0x1000. | Engine accepts; correctly transitions. | TBD |
| B036 | D | Two-segment large spans (1 MiB each) | 1 | seg0_span=0x10_0000, seg1_span=0x10_0000. | Engine completes; FILL on exhaustion. | TBD |
| B037 | D | Two-segment with non-zero sqe_id and opcode | 1 | sqe_id=0xCAFE, opcode=0x0001. | sqe_id_echo==0xCAFE. | TBD |
| B038 | D | Two-segment with seg0=4KB filled exactly mid-burst | 1 | seg0_span=0x1000 = 32 W-beats = 2 full bursts of 16; check seg0->seg1 at burst boundary. | seg0 closes with one B; seg1 opens with new AW at seg1_addr. | TBD |
| B039 | D | Two-segment seg0_addr identical seg1_addr (degenerate) | 1 | seg0_addr==seg1_addr (legal, same buffer). | Writer respects spans; transitions to fresh seg1_addr arithmetic. | TBD |
| B040 | D | Two-segment with EOE exactly at end of seg1 | 1 | seg0_span=0x1000, seg1_span=0x1000; drive 2048 words then EOE same beat. | EOE=1 AND FULL=1; both bits set. | TBD |

---

## 5. AXI4 burst-sizing baseline (B041-B052)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B041 | D | Burst awlen=0 (1-beat AW), 1 W beat | 1 | Drive enough OPQ to flush 1 W beat then EOE; FIFO contains 1 beat at AW issuance. | First AW awlen==0; one W beat with wlast=1; B. | TBD |
| B042 | D | Burst awlen=15 (16-beat AW), 16 W beats | 1 | Fill FIFO with 16 beats; observe one AW awlen==15. | awlen==15; 16 W handshakes; wlast asserted on beat 16. | TBD |
| B043 | D | awsize == 3'b101 (32 B per beat) on every AW | 1 | Default DMA_DATA_W=256. | awsize==3'b101 across 64 issued AWs. | TBD |
| B044 | D | awburst == 2'b01 (INCR) on every AW | 1 | Default. | awburst==2'b01 across 64 issued AWs. | TBD |
| B045 | D | awaddr beat-aligned (low 5 bits zero) | 1 | Default. | awaddr[4:0]==5'h0 across 64 issued AWs. | TBD |
| B046 | D | Burst awlen capped at MAX_BURST_BEATS-1 | 1 | Stuff FIFO past 16 beats. | No AW with awlen>15. | TBD |
| B047 | D | Burst sizing reduces when fifo_level < MAX_BURST_BEATS | 1 | Hold OPQ at slow rate so FIFO has 4 beats when AW issues. | First AW awlen<=3. | TBD |
| B048 | D | Burst sizing reduces near segment end (beats_left_in_seg < MAX) | 1 | Set seg0_span=0x80 (128 B = 4 beats); fill FIFO. | First AW awlen==3 (4 beats). | TBD |
| B049 | D | Burst region never crosses 4 KB page | 1 | Long drain. | For every AW: ((awaddr+(awlen+1)*32) & ~12'hFFF) == (awaddr & ~12'hFFF). | TBD |
| B050 | D | AW handshake before first W beat | 1 | Default; capture order. | wvalid never asserted before awvalid&&awready (or same-cycle but never earlier). | TBD |
| B051 | D | wvalid stable until wready | 1 | Set axi_completer wready_lag=4. | wvalid+wdata+wstrb stable for 4 clk until wready=1. | TBD |
| B052 | D | awvalid stable until awready | 1 | axi_completer awready_lag=8. | awvalid+awaddr+awlen stable for 8 clk. | TBD |

---

## 6. AXI4 W-channel and B-channel contract (B053-B062)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B053 | D | Per-AW W-beat count == awlen+1 | 1 | 100 jobs. | For every AW: # of (wvalid&&wready) handshakes == awlen+1. | TBD |
| B054 | D | wlast on last W beat only | 1 | Long burst. | wlast==1 only on the awlen-th beat. | TBD |
| B055 | D | wstrb all 1s on full beats | 1 | Default no-EOE drain. | wstrb==32'hFFFF_FFFF on all but EOE-pad beats. | TBD |
| B056 | D | wstrb partial on EOE-pad beat | 1 | EOE on slot 4 of next beat. | Last W beat wstrb has only first 16 bits set (4 slots * 4 bytes). | TBD |
| B057 | D | B accepted with bready=1 on bvalid | 1 | Default. | bready asserted while bvalid; B handshake completes. | TBD |
| B058 | D | BRESP==OKAY default | 1 | axi_completer issues bresp=2'b00. | Engine completes job; status non-error. | TBD |
| B059 | D | B may arrive same cycle as wlast | 1 | axi_completer schedules bvalid same cycle. | Engine accepts; FSM transitions B->AW. | TBD |
| B060 | D | B may arrive late (delayed by 100 clk) | 1 | axi_completer T_BVALID=100. | Engine waits in WR_B; no spurious AW. | TBD |
| B061 | D | Multi-burst job: each AW gets one matching B | 1 | Drive 8 bursts. | 8 AW handshakes; 8 B handshakes; FSM walks AW->W->B 8x. | TBD |
| B062 | D | B order matches AW order (in-order completion) | 1 | Default single-ID engine. | bid sequence matches awid sequence. | TBD |

---

## 7. Counter accuracy and conservation (B063-B072)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B063 | D | cnt_input_w increments per accepted OPQ beat (no halt) | 1 | Drive 100 OPQ beats with halt clear. | cnt_input_w==100. | TBD |
| B064 | D | cnt_bytes_written increments by 32 per full W beat | 1 | Drive 4 full W beats. | cnt_bytes_written delta == 128. | TBD |
| B065 | D | cnt_bytes_written counts only useful bytes on EOE-pad | 1 | EOE on slot 5 of last beat. | Last beat contributes 20 bytes (5*4), not 32. | TBD |
| B066 | D | cnt_eoe_observed increments per OPQ tlast | 1 | Drive 5 events. | cnt_eoe_observed==5 at job_done. | TBD |
| B067 | D | cnt_halt increments per dropped OPQ beat | 1 | Force fifo almost-full + drive 10 OPQ beats; expect packer halt. | cnt_halt delta matches dropped count. | TBD |
| B068 | D | Conservation single job: input*4 == written + halt | 1 | Drive 200 OPQ beats with random halt. | cnt_input_w*4 == cnt_bytes_written + cnt_halt*4 (modulo EOE pad). | TBD |
| B069 | D | Conservation 2 back-to-back jobs | 1 | Two single-segment 4 KB jobs. | Sigma input*4 == sigma written + sigma halt. | TBD |
| B070 | D | Conservation 5 back-to-back jobs varying spans | 1 | Mix of 4/8/16 KB spans. | Sigma input*4 == sigma written + sigma halt. | TBD |
| B071 | D | Counters survive across job boundaries (non-clearing) | 1 | Run two jobs back to back without clear_counters. | Counters monotonic non-decreasing. | TBD |
| B072 | D | clear_counters strobe clears all four cnt_* in 1 clk | 1 | Pulse clear_counters after 100 OPQ beats. | All cnt_* read 0 next clk. | TBD |

---

## 8. Per-event timestamp tracking (B073-B078)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B073 | D | Single event: first_ts == last_ts | 1 | Drive one event of 8 words then EOE. | first_event_ts == last_event_ts; event_count==1. | TBD |
| B074 | D | Multi-event drain: first_ts < last_ts | 1 | Drive 3 events spaced 100 clks apart. | first_event_ts < last_event_ts; event_count==3. | TBD |
| B075 | D | first_event_ts captures cycle of first tlast | 1 | Inject tlast at known cycle T. | first_event_ts == T. | TBD |
| B076 | D | last_event_ts captures cycle of last tlast | 1 | Inject 5 tlasts; record last cycle T_last. | last_event_ts == T_last. | TBD |
| B077 | D | event_count == 0 if no tlast in drain | 1 | Drive only data, no EOE; FULL terminates. | event_count == 0; status[FULL]=1. | TBD |
| B078 | D | event_count overflow guard (32 b counter) | 1 | Drive 100 events. | event_count==100; no wraparound. | TBD |

---

## 9. Status bit semantics (B079-B086)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B079 | D | status[EOE]=1 on EOE before FULL | 1 | EOE before span exhausted. | status[EOE]=1; FULL=0. | TBD |
| B080 | D | status[FULL]=1 on span exhausted before EOE | 1 | FULL before EOE. | FULL=1; EOE=0. | TBD |
| B081 | D | status[FULL]=1 AND status[EOE]=1 same beat | 1 | EOE arrives exactly at last byte of span. | Both bits set in completion report. | TBD |
| B082 | D | status[SEG0_ONLY]=1 when seg1_span==0 | 1 | Single-segment job. | SEG0_ONLY=1. | TBD |
| B083 | D | status[SEG_BOUNDARY_HIT]=1 on seg0->seg1 transition | 1 | Two-segment with seg0 fill. | SEG_BOUNDARY_HIT=1. | TBD |
| B084 | D | status[HALT]=1 if any cnt_halt during this job | 1 | Force halt with FIFO almost-full. | status[HALT]=1; cnt_halt>0. | TBD |
| B085 | D | status[HALT]=0 in clean drain | 1 | No halt induced. | status[HALT]=0; cnt_halt unchanged. | TBD |
| B086 | D | status reserved bits [6:15] always 0 | 1 | Default. | Top 10 bits of status read 0. | TBD |

---

## 10. Job-interface handshake (B087-B092)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B087 | D | job_req captured on rising edge | 1 | Pulse job_req for exactly 1 clk. | Engine latches seg/sqe/opcode same clk. | TBD |
| B088 | D | job_req multi-cycle hold (3 clks) latches once | 1 | Drive job_req high for 3 clk. | Engine sees one job; second pulse ignored until next IDLE entry. | TBD |
| B089 | D | job_done asserted exactly 1 clk | 1 | Run a single job. | job_done high for 1 clk; falls to 0 next clk. | TBD |
| B090 | D | job_done does not overlap job_req | 1 | Drive new job_req same cycle as job_done. | Engine accepts new job after job_done falls; SVA passes. | TBD |
| B091 | D | Report fields hold valid >=1 clk after job_done | 1 | Capture report fields 1 clk after done. | All bytes_written/status/sqe_id_echo/event_count/ts fields stable. | TBD |
| B092 | D | sqe_id_echo matches sqe_id input | 1 | Run with sqe_id=0xABCD. | sqe_id_echo==0xABCD on done. | TBD |

---

## 11. DEBUG_LEVEL=1 fill-level / FSM observability (B093-B100)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B093 | D | dbg1_fifo_level matches internal write/read counter | 1 | Drive 32 OPQ words, throttle host so FIFO holds 4 beats. | dbg1_fifo_level==4 at the throttle point. | TBD |
| B094 | D | dbg1_fifo_almost_full asserts at threshold | 1 | Fill FIFO to ALMOST_FULL_TH (=192). | dbg1_fifo_almost_full=1 when level>=192; 0 otherwise. | TBD |
| B095 | D | dbg1_packer_slot_idx walks 0->7 then wraps | 1 | Drive 16 OPQ beats. | dbg1_packer_slot_idx walks 0->7->0->7. | TBD |
| B096 | D | dbg1_writer_state transitions match FSM | 1 | One full job. | IDLE->PROGRAM->AW->W->B->REPORT_DONE->IDLE observed in dbg1_writer_state. | TBD |
| B097 | D | dbg1_aw_inflight increments on AW handshake, decrements on B | 1 | 5 burst job. | dbg1_aw_inflight oscillates 0/1 across the 5 bursts. | TBD |
| B098 | D | dbg1_w_beats_remaining loaded at AW, decremented per W | 1 | awlen=15 burst. | Loaded to 16 at AW handshake; reaches 0 at wlast. | TBD |
| B099 | D | dbg1_halt_pulse pulses once per dropped beat | 1 | Force halt with 5 dropped beats. | 5 dbg1_halt_pulse rises observed. | TBD |
| B100 | D | dbg1_b_outstanding tracks Bs awaited | 1 | Throttle B to delay completion. | dbg1_b_outstanding>0 while waiting for bvalid. | TBD |

---

## 12. DEBUG_LEVEL=2 sidecar lineage smoke (B101-B107)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B101 | D | DEBUG=2 single 8-word event lineage match | 1 | DEBUG=2 build, drive 8 OPQ beats with deterministic (lane=0, hit_id=1..8, source_ts=t..t+7, sequence_no=1). | Writer-shadow emits the same 8 entries in the same order; matcher residual == 0. | TBD |
| B102 | D | DEBUG=2 multi-burst lineage (32 hits) | 1 | DEBUG=2; 32 hits across 4 bursts. | All 32 entries traced ingress->emit; residual==0. | TBD |
| B103 | D | DEBUG=2 ingress sidecar carries deterministic walk | 1 | DEBUG=2; lineage_walk seq. | Ingress monitor captures exact (lane, hit_id, source_ts, sequence_no) walk. | TBD |
| B104 | D | DEBUG=2 EOE-pad slots reported as padding sentinel | 1 | DEBUG=2; EOE on slot 4. | Slots 5-8 of the last beat carry sentinel meta; matcher does not consume them. | TBD |
| B105 | D | DEBUG=2 across two-segment job | 1 | DEBUG=2; two-segment fill. | Lineage walk preserved across SEG_BOUNDARY_HIT. | TBD |
| B106 | D | DEBUG=2 across multi-event drain | 1 | DEBUG=2; 4 events. | Each event's lineage walk preserved end-to-end. | TBD |
| B107 | D | DEBUG=2 sidecar inert when DEBUG=1 build runs | 1 | Run same test under DEBUG=1. | dbg2_meta_* tied 0; payload identical to DEBUG=2 functional output. | TBD |

---

## 13. Random nominal smoke (B108-B110)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B108 | R | Random 8 jobs of mixed spans (4-16 KB) | 8 | rand seg0_span in {4,8,16} KB; rand seg1 used 50%; default lag. | Per-job conservation; per-build lineage zero residual; zero SVA fails. | TBD |
| B109 | R | Random 16 events per job, mixed sizes | 16 | rand event size 1..256 OPQ beats; default lag. | Per-job conservation; cnt_eoe_observed increments per event. | TBD |
| B110 | R | Random 100 OPQ beat patterns single job | 100 | rand interleave with 0..3 idle clks per beat. | Per-job conservation; bytes_written matches packer-predicted output. | TBD |

---

## 14. Per-segment bytes-written accuracy (B111-B116)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B111 | D | Single-segment bytes_written matches drained data | 1 | seg0=8 KB; drive 1024 OPQ words then EOE. | seg0_bytes_written==4096; seg1_bytes_written==0; bytes_written_total==4096. | TBD |
| B112 | D | Two-seg fill exactly: seg0=4096, seg1=4096 | 1 | Drive 2048 OPQ words. | seg0=4096, seg1=4096, total=8192. | TBD |
| B113 | D | Two-seg partial seg1: seg0=4096, seg1=128 | 1 | Drive 1056 OPQ words then EOE. | seg0=4096, seg1=128, total=4224. | TBD |
| B114 | D | Two-seg seg0 only used (EOE in seg0): seg0=2048, seg1=0 | 1 | Drive 512 OPQ words then EOE. | seg0=2048, seg1=0. | TBD |
| B115 | D | bytes_written sum equals total | 1 | Multi-seg job. | seg0_bytes + seg1_bytes == bytes_written_total. | TBD |
| B116 | D | bytes_written 0 on ALIGN_ERR refusal | 1 | Misaligned addr. | All bytes_written fields == 0 on completion. | TBD |

---

## 15. Smoke for QUEUE_MATH analytical model linkage (B117-B122)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B117 | D | Single-burst job: throughput == DMA_DATA_W bits/clk in steady state | 1 | 1 burst at zero-latency host. | 16 W beats handshake in 16 clks. | TBD |
| B118 | D | Burst-bound throughput matches model: T = MAX_BEATS / (MAX_BEATS + 1) * f_clk * DMA_DATA_W | 1 | Long sustained drain. | Measured throughput within 2% of T. | TBD |
| B119 | D | FIFO occupancy converges to predicted steady state | 1 | Sustained inputs at known rate. | Avg dbg1_fifo_level matches Little's-law-derived prediction. | TBD |
| B120 | D | Halt onset rate matches threshold prediction | 1 | Throttle at 50% wready. | halt onset frequency matches model | TBD |
| B121 | D | Per-segment latency overhead == 1 AW cycle | 1 | Two-seg with seg0 fully drained. | Latency of seg0->seg1 transition observed as 1 cycle (per QUEUE_MATH §2). | TBD |
| B122 | D | Queue math invariant holds at all coverage bins | 1 | Coverage sweep. | Per-bin average residency tracks model. | TBD |

---

## 16. Sideband cnt_* propagation (B123-B128)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| B123 | D | cnt_input_w monotonic across jobs | 1 | Two jobs of 8 OPQ words each. | cnt_input_w increments by 8 then by 8. | TBD |
| B124 | D | cnt_bytes_written monotonic across jobs | 1 | Two single-segment jobs. | Increments by per-job bytes. | TBD |
| B125 | D | cnt_halt monotonic across jobs | 1 | Halt during one of 5 jobs. | Increments only during the halt-injection job. | TBD |
| B126 | D | cnt_eoe_observed monotonic across jobs | 1 | 5 jobs each ending in EOE. | cnt_eoe_observed==5 at end of run. | TBD |
| B127 | D | Counters survive disable + enable | 1 | Reset between jobs vs uninterrupted. | Counters preserved across job boundaries. | TBD |
| B128 | D | All counters readable via dbg1 tap mirror | 1 | Inspect dbg1. | dbg1 mirrors cnt_* (subject to RTL routing). | TBD |

---

