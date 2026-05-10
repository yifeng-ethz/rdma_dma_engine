# DV Error — rdma_dma_engine

**Companion docs:** `DV_PLAN.md`, `DV_HARNESS.md`, `DV_BASIC.md`,
`DV_EDGE.md`, `DV_PROF.md`, `DV_CROSS.md`, `DV_COV.md`,
`BUG_HISTORY.md`.

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**ID Range:** X001-X128
**Total:** 128 cases (0 implemented / 0 waived)

This document collects the reset / fault / illegal / recovery cases
for `rdma_dma_engine`. Cases are derived from `DV_PLAN.md` §3.5,
§3.9, the AXI4 protocol error contract, and the OoO-datapath
DEBUG=2 lineage break section of the dv-workflow skill.

**Methodology key:**
- **D** = Directed (hand-crafted stimulus, single transaction)
- **R** = Constrained-random (UVM `rand` constraints; multiple
  transactions per case)

---

## 1. Summary

| Section | Cases | ID Range | What it Proves | Current Case |
|---------|------:|----------|----------------|--------------|
| Job-interface alignment errors (refusal path) | 15 | X001-X015 | engine refuses misaligned addresses or non-4 KB spans, status[ALIGN_ERR]=1, no AXI traffic | 0/15 |
| Reset during operation | 13 | X016-X028 | reset asserted at every FSM state; clean recovery | 0/13 |
| AXI4 BRESP error handling | 6 | X029-X034 | non-OKAY BRESP on a write; engine sets non-OKAY status bit and continues / aborts per spec | 0/6 |
| FIFO underrun protection | 3 | X035-X037 | engine must not assert wvalid without committed FIFO data; SVA passes | 0/3 |
| OPQ ingress fault simulation | 6 | X038-X043 | irregular OPQ inputs handled gracefully | 0/6 |
| Job-stream illegal sequencing | 5 | X044-X048 | illegal or unusual job submissions | 0/5 |
| Recovery sequences | 4 | X049-X052 | engine resumes operation cleanly after error | 0/4 |
| DEBUG_LEVEL=1 fault observability | 4 | X053-X056 | dbg1 taps still consistent during fault scenarios | 0/4 |
| DEBUG_LEVEL=2 lineage breaks | 5 | X057-X061 | lineage matcher correctly detects and reports lineage anomalies | 0/5 |
| Counter clear during operation | 6 | X062-X067 | clear_counters strobe behaviors and edge cases | 0/6 |
| Long-soak fault injection | 4 | X068-X071 | random fault injection over long soaks | 0/4 |
| Boundary error timing | 4 | X072-X075 | errors arriving at exact transition cycles | 0/4 |
| AXI4 protocol violation on master input | 6 | X076-X081 | non-compliant inputs from completer; engine should not propagate undefined | 0/6 |
| FIFO error simulation | 4 | X082-X085 | force-injection of FIFO inconsistency for SVA testing | 0/4 |
| Job-interface protocol violation | 3 | X086-X088 | illegal job_req sequences | 0/3 |
| ALIGN_ERR composite with halts | 3 | X089-X091 | alignment error combined with halt and reset | 0/3 |
| Counter clear race conditions | 4 | X092-X095 | clear_counters during various FSM states with concurrent activity | 0/4 |
| Watchdog scenarios | 4 | X096-X099 | engine should not hang indefinitely in any state | 0/4 |
| Multi-step error recovery | 4 | X100-X103 | error chains with multiple recovery hops | 0/4 |
| DEBUG=2 lineage error scenarios | 4 | X104-X107 | lineage matcher under various error conditions | 0/4 |
| Random fault soak | 5 | X108-X112 | random fault injection over long runs | 0/5 |
| Reset reentrancy | 4 | X113-X116 | reset asserted multiple times during single workload | 0/4 |
| Out-of-order edge: BRESP order vs AW order | 2 | X117-X118 | in-order single-id engine; out-of-order BRESP from completer is illegal | 0/2 |
| Coverage closure for ERROR | 4 | X119-X122 | supplementary cases targeting code-coverage holes specific to ERROR paths | 0/4 |
| Sustained error stress | 3 | X123-X125 | engine runs cleanly under sustained low-rate errors | 0/3 |
| Final-closure ERROR cases | 3 | X126-X128 | the final cases that close the ERROR bucket for sign-off | 0/3 |

---

## 2. Job-interface alignment errors (refusal path) (X001-X015)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X001 | D | seg0_addr & 0xFFF != 0 (off by 1 byte) | 1 | seg0_addr=0x10_0001. | ALIGN_ERR=1; no AXI; immediate job_done. | TBD |
| X002 | D | seg0_addr & 0xFFF != 0 (off by 0x800) | 1 | seg0_addr=0x10_0800. | Same. | TBD |
| X003 | D | seg0_addr & 0xFFF != 0 (off by 0xFFF) | 1 | seg0_addr=0x10_0FFF. | Same. | TBD |
| X004 | D | seg0_span & 0xFFF != 0 (1 byte over) | 1 | seg0_span=0x1001. | ALIGN_ERR=1; no AXI. | TBD |
| X005 | D | seg0_span & 0xFFF != 0 (0x100 over 4 KB) | 1 | seg0_span=0x1100. | Same. | TBD |
| X006 | D | seg0_span = 0 | 1 | seg0_span=0. | ALIGN_ERR=1 per spec (zero span illegal). | TBD |
| X007 | D | seg1_addr & 0xFFF != 0 with seg1_span > 0 | 1 | seg1_addr=0x80_0001, seg1_span=0x1000. | ALIGN_ERR=1. | TBD |
| X008 | D | seg1_span & 0xFFF != 0 with seg1_span > 0 | 1 | seg1_span=0x1001. | ALIGN_ERR=1. | TBD |
| X009 | D | seg0 and seg1 both misaligned | 1 | Both errors. | ALIGN_ERR=1; refused. | TBD |
| X010 | D | seg0 ok, seg1 misaligned (seg1 used) | 1 | seg0 valid, seg1 invalid. | ALIGN_ERR=1; engine does not start seg0. | TBD |
| X011 | D | seg0_span = 0 with seg1_span > 0 and aligned | 1 | Edge: seg0_span=0. | ALIGN_ERR=1 (spec: seg0_span must be >=4 KB). | TBD |
| X012 | D | seg1_span = 0 (legal: single-segment) | 1 | seg1_span=0. | ALIGN_ERR=0; SEG0_ONLY=1. | TBD |
| X013 | D | Misaligned addr with cnt_input_w != 0 (mid-burst) | 1 | Run a job, then submit misaligned new job. | Second job ALIGN_ERR; first job unaffected. | TBD |
| X014 | D | Multiple consecutive ALIGN_ERR jobs | 1 | 5 misaligned jobs in a row. | All 5 refused; counters unchanged across them. | TBD |
| X015 | D | ALIGN_ERR job followed by valid job | 1 | Mix. | Valid job runs cleanly. | TBD |

---

## 3. Reset during operation (X016-X028)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X016 | D | Reset during WR_IDLE | 1 | Idle; assert reset. | Returns to IDLE after deassert. | TBD |
| X017 | D | Reset during WR_PROGRAM | 1 | Force into WR_PROGRAM; reset. | Returns to IDLE. | TBD |
| X018 | D | Reset during WR_AW | 1 | Force into WR_AW (awvalid pending); reset. | Returns to IDLE; AXI signals deasserted. | TBD |
| X019 | D | Reset during WR_W mid-burst | 1 | Force into mid-burst; reset. | Returns to IDLE; B handshake abandoned. | TBD |
| X020 | D | Reset during WR_B (waiting bvalid) | 1 | WR_B; reset. | Returns to IDLE. | TBD |
| X021 | D | Reset during WR_REPORT_DONE | 1 | REPORT_DONE; reset. | Returns to IDLE. | TBD |
| X022 | D | Reset on the cycle of job_req | 1 | Race condition. | Job not entered; engine in IDLE post-reset. | TBD |
| X023 | D | Reset on the cycle of job_done | 1 | Race condition. | Done not visible; engine in IDLE post-reset. | TBD |
| X024 | D | Multiple reset pulses (10 in succession) | 1 | Toggle reset. | Stable IDLE after final deassert. | TBD |
| X025 | D | Long reset (1000 clks) | 1 | Hold reset 1000 clks. | IDLE on deassert. | TBD |
| X026 | D | Reset followed immediately by job_req | 1 | 1 clk gap. | Engine accepts new job. | TBD |
| X027 | D | Reset clears all cnt_* counters | 1 | Run job; reset; check counters. | All cnt_* == 0. | TBD |
| X028 | D | Reset clears dbg1_* taps to defaults | 1 | Mid-burst; reset. | All dbg1_* at default values. | TBD |

---

## 4. AXI4 BRESP error handling (X029-X034)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X029 | D | BRESP=SLVERR (2'b10) on a single burst | 1 | axi_completer issues SLVERR. | Engine captures error in status; continues to next burst per spec. | TBD |
| X030 | D | BRESP=DECERR (2'b11) on a single burst | 1 | DECERR. | Same; status reflects error. | TBD |
| X031 | D | BRESP=SLVERR on first burst of multi-burst job | 1 | First B is SLVERR. | Status bit asserted; remaining bursts continue. | TBD |
| X032 | D | BRESP=SLVERR on last burst | 1 | Last B is SLVERR. | Status reflects. | TBD |
| X033 | D | BRESP=SLVERR on every burst (10 bursts) | 1 | All errors. | All errors captured; no engine hang. | TBD |
| X034 | D | BRESP=DECERR followed by OKAY | 1 | Mixed. | Status reflects worst error. | TBD |

---

## 5. FIFO underrun protection (X035-X037)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X035 | D | wvalid never asserted with empty FIFO | 1 | Force FIFO empty mid-burst (SVA). | wvalid==0 when FIFO empty; SVA passes. | TBD |
| X036 | D | Burst-sizing reads only what FIFO contains | 1 | FIFO has 5 beats; AW issued. | awlen<=4. | TBD |
| X037 | D | Engine waits for FIFO refill mid-burst (legal pause) | 1 | FIFO drains mid-burst. | wvalid de-asserts (legal pause); resumes when refill. | TBD |

---

## 6. OPQ ingress fault simulation (X038-X043)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X038 | D | OPQ tlast without tvalid (illegal) | 1 | tlast=1, tvalid=0. | Engine ignores; SVA flags. | TBD |
| X039 | D | OPQ sop mid-event (illegal) | 1 | sop=1 mid-event. | SVA flags; engine continues current event accumulation. | TBD |
| X040 | D | OPQ tvalid stuck at 1 with no actual change | 1 | Stuck. | Engine accepts beats per tvalid&&tready handshake. | TBD |
| X041 | D | OPQ tvalid stuck at 0 (no data forever) | 1 | No OPQ data. | Engine waits in WR_W for FIFO; no spurious AW. | TBD |
| X042 | D | OPQ tdata X (X-injection sim) | 1 | Inject X on tdata. | Engine still functions; SVA may flag X. | TBD |
| X043 | D | OPQ tlast at SOP (single-beat event) | 1 | sop=1, eop=1 same beat. | Single-beat event; bytes_in_word=4; status[EOE]=1. | TBD |

---

## 7. Job-stream illegal sequencing (X044-X048)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X044 | D | job_req asserted while engine is mid-job (overlap) | 1 | Drive new job_req while WR_W. | Per SVA, illegal; engine should not double-latch. | TBD |
| X045 | D | job_req asserted simultaneously with reset | 1 | Race. | Reset wins; job not latched. | TBD |
| X046 | D | job_req with invalid opcode (non 0x0001) | 1 | opcode=0xDEAD. | Engine treats as DRAIN_UNTIL_EOE per spec; or ALIGN_ERR if defensive. | TBD |
| X047 | D | Many ALIGN_ERR jobs followed by valid job | 1 | 10 errors then valid. | Valid job runs. | TBD |
| X048 | D | Valid job with wraparound seg sizes | 1 | Span at 4 GiB max. | Engine accepts. | TBD |

---

## 8. Recovery sequences (X049-X052)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X049 | D | Recover from BRESP=SLVERR job | 1 | Run errored job; submit clean job. | Clean job runs without error. | TBD |
| X050 | D | Recover from ALIGN_ERR job | 1 | Run aligned-err; submit clean. | Clean job runs. | TBD |
| X051 | D | Recover from reset mid-job | 1 | Reset mid-job; submit fresh. | Fresh job runs. | TBD |
| X052 | D | Recover from halt event (cnt_halt > 0) mid-job | 1 | Halt mid-job; complete; new job. | Both jobs complete; conservation. | TBD |

---

## 9. DEBUG_LEVEL=1 fault observability (X053-X056)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X053 | D | dbg1 taps during BRESP=SLVERR | 1 | Errored burst. | dbg1_writer_state correctly transitions; dbg1_aw_inflight returns to 0. | TBD |
| X054 | D | dbg1 taps during reset mid-burst | 1 | Reset. | dbg1 returns to default after reset deassert. | TBD |
| X055 | D | dbg1 taps during ALIGN_ERR job | 1 | Aligned err. | dbg1_writer_state shows REPORT_ALIGN_ERR -> IDLE; no AW/W. | TBD |
| X056 | D | dbg1_halt_pulse counted correctly under burst halts | 1 | Halt stress. | dbg1_halt_pulse rises = cnt_halt delta. | TBD |

---

## 10. DEBUG_LEVEL=2 lineage breaks (X057-X061)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X057 | D | Force lineage drop (corrupt 1 sidecar entry) | 1 | DEBUG=2; force-corrupt one beat's sidecar via TB injection. | Matcher reports mismatch; flagged as expected-anomaly. | TBD |
| X058 | D | Force lineage reorder (TB swaps two beats) | 1 | DEBUG=2; reorder. | Matcher reports out-of-order; flagged. | TBD |
| X059 | D | Force lineage duplicate (TB resubmits a hit_id) | 1 | DEBUG=2; duplicate. | Matcher reports duplicate; flagged. | TBD |
| X060 | D | Lineage residual under reset | 1 | DEBUG=2; reset mid-job. | Residual reported but matcher restarts cleanly post-reset. | TBD |
| X061 | D | Lineage residual under halt (== cnt_halt) | 1 | DEBUG=2; halt event. | Residual == cnt_halt at job_done. | TBD |

---

## 11. Counter clear during operation (X062-X067)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X062 | D | clear_counters during WR_IDLE | 1 | Pulse clear. | Counters zero next clk. | TBD |
| X063 | D | clear_counters during WR_W | 1 | Mid-burst clear. | Counters zero; in-flight burst completes. | TBD |
| X064 | D | clear_counters during WR_B | 1 | Wait B clear. | Counters zero. | TBD |
| X065 | D | clear_counters multiple back-to-back | 1 | 5 pulses. | Counters zero after first; idempotent. | TBD |
| X066 | D | clear_counters same cycle as job_done | 1 | Race. | Counters cleared after done capture (TB uses pre-clear values). | TBD |
| X067 | D | clear_counters during halt event | 1 | Mid-halt. | Counters cleared; halt continues to be tracked from 0. | TBD |

---

## 12. Long-soak fault injection (X068-X071)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X068 | R | Random BRESP injection (1% rate) over 100 jobs | 100 | 1% bursts get SLVERR. | All errors captured; no hang; conservation modulo error semantics. | TBD |
| X069 | R | Random reset injection (per N jobs) | 20 | Reset every 5 jobs. | Engine recovers each time; counters cleared. | TBD |
| X070 | R | Random ALIGN_ERR injection (10% jobs) | 100 | 10% misaligned. | All errors refused; valid jobs complete. | TBD |
| X071 | R | Random combined faults | 100 | Mix. | All errors captured; no hang. | TBD |

---

## 13. Boundary error timing (X072-X075)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X072 | D | Reset on the cycle of awvalid handshake | 1 | Race. | AW abandoned; B not expected; engine to IDLE. | TBD |
| X073 | D | Reset on the cycle of wlast handshake | 1 | Race. | B may or may not arrive; engine to IDLE. | TBD |
| X074 | D | Reset on the cycle of bvalid | 1 | Race. | Engine to IDLE. | TBD |
| X075 | D | BRESP error on bvalid arriving after reset | 1 | Race. | BRESP ignored post-reset. | TBD |

---

## 14. AXI4 protocol violation on master input (X076-X081)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X076 | D | awready dropped after assertion (illegal) | 1 | axi_completer drops awready before AW handshake. | SVA flags; engine retains AW state. | TBD |
| X077 | D | wready dropped after assertion (illegal) | 1 | Drop wready. | SVA; engine waits. | TBD |
| X078 | D | bvalid pulsed without preceding wlast | 1 | Spurious B. | SVA flags; engine ignores or asserts on a phantom B. | TBD |
| X079 | D | bvalid arrives before wlast (race) | 1 | Race. | SVA may flag; engine waits for wlast. | TBD |
| X080 | D | bid mismatch with awid (no-id-mode) | 1 | bid != awid. | Engine accepts (single-id design) or flags. | TBD |
| X081 | D | Multiple bvalid for one AW (illegal) | 1 | Two Bs. | SVA flags; engine ignores second. | TBD |

---

## 15. FIFO error simulation (X082-X085)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X082 | D | Force FIFO level inconsistency (TB poke) | 1 | TB pokes wrong level. | SVA flags fifo level mismatch. | TBD |
| X083 | D | Force FIFO write while full (illegal RTL state) | 1 | TB poke. | SVA flags. | TBD |
| X084 | D | Force FIFO read while empty (illegal) | 1 | TB poke. | SVA flags. | TBD |
| X085 | D | Force almost_full disagreement with level | 1 | Inconsistency. | SVA flags. | TBD |

---

## 16. Job-interface protocol violation (X086-X088)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X086 | D | job_req held high for >1 clk straddling job_done | 1 | Long held req. | Engine sees one job; second pulse handled per spec. | TBD |
| X087 | D | job_req with inputs changing mid-pulse | 1 | Force seg_addr to flip during req high. | SVA flags; engine latches first value. | TBD |
| X088 | D | job_done while job_req still high (race) | 1 | Race. | SVA flags overlap. | TBD |

---

## 17. ALIGN_ERR composite with halts (X089-X091)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X089 | D | ALIGN_ERR job followed by halt event in next valid job | 1 | Mix. | Errors handled separately; conservation. | TBD |
| X090 | D | ALIGN_ERR while host signals BRESP error (unrelated) | 1 | Both. | Engine refuses ALIGN_ERR; BRESP irrelevant for that job. | TBD |
| X091 | D | ALIGN_ERR followed by reset | 1 | Mix. | Engine clean post-reset. | TBD |

---

## 18. Counter clear race conditions (X092-X095)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X092 | D | clear_counters during AW handshake | 1 | Race. | Counters cleared; AW continues. | TBD |
| X093 | D | clear_counters with cnt_input_w about to increment | 1 | Race. | Clear wins; new input counted from 0. | TBD |
| X094 | D | clear_counters with cnt_halt about to pulse | 1 | Race. | Clear; halt accounted from 0. | TBD |
| X095 | D | clear_counters during job_done | 1 | Race. | Counters cleared after report capture. | TBD |

---

## 19. Watchdog scenarios (X096-X099)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X096 | D | OPQ stuck low during WR_W (no W beats forever) | 1 | FIFO underrun-like. | Engine waits indefinitely; watchdog SVA optional. | TBD |
| X097 | D | host stuck wready=0 indefinitely | 1 | Stuck. | Engine stuck in WR_W (legal pause); SVA optional watchdog. | TBD |
| X098 | D | host stuck bvalid=0 indefinitely | 1 | Stuck. | Engine stuck in WR_B; SVA optional watchdog. | TBD |
| X099 | D | Long idle with no job_req (1M clks) | 1 | Idle. | Engine in IDLE; no spurious AW. | TBD |

---

## 20. Multi-step error recovery (X100-X103)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X100 | D | BRESP-SLVERR -> reset -> ALIGN_ERR -> valid | 1 | Chain. | Each step cleanly handled; final job runs. | TBD |
| X101 | D | BRESP -> halt -> EOE -> done | 1 | Mid-job error and halt. | Done with status reflecting both. | TBD |
| X102 | D | Reset -> reset -> reset -> valid | 1 | Triple reset. | Final job runs. | TBD |
| X103 | D | Halt -> reset -> halt -> reset -> valid | 1 | Stress. | Engine stable. | TBD |

---

## 21. DEBUG=2 lineage error scenarios (X104-X107)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X104 | D | Lineage matcher reports residual==cnt_halt under halt | 1 | DEBUG=2 + halt. | Residual matches cnt_halt at job_done. | TBD |
| X105 | D | Lineage matcher reports residual==input on reset | 1 | DEBUG=2 + reset. | Residual==# of un-emitted ingress entries; matcher restarts. | TBD |
| X106 | D | Lineage matcher under BRESP error | 1 | DEBUG=2 + BRESP. | Lineage closure; error captured separately. | TBD |
| X107 | D | Lineage matcher under ALIGN_ERR (no traffic) | 1 | DEBUG=2 + ALIGN_ERR. | No ingress, no emit; residual==0. | TBD |

---

## 22. Random fault soak (X108-X112)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X108 | R | Random fault profile (mixed BRESP, halt, reset) | 100 | Mixed faults. | Engine recovers; closure on conservation. | TBD |
| X109 | R | Random ALIGN_ERR + valid mix at 50/50 | 100 | Half misaligned. | All errors refused; valid jobs run. | TBD |
| X110 | R | Random reset every N jobs (N rand 5..20) | 20 | Random reset. | Each reset clean; subsequent jobs run. | TBD |
| X111 | R | Random BRESP at 5% rate over 1000 jobs | 1000 | Long. | All errors captured; no hang. | TBD |
| X112 | R | Random combined fault at 10% rate over 1000 jobs | 1000 | Long mixed. | Conservation modulo errors. | TBD |

---

## 23. Reset reentrancy (X113-X116)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X113 | D | Reset every 50 clks for 1000 clks | 1 | Aggressive reset. | Engine remains in IDLE when reset asserted. | TBD |
| X114 | D | Reset asserted while waiting on bvalid (no host) | 1 | Stuck in WR_B; reset. | Returns to IDLE. | TBD |
| X115 | D | Reset asserted with FIFO at 95% fill | 1 | Mid-load reset. | FIFO cleared on reset (per RTL spec). | TBD |
| X116 | D | Reset on cycle of clear_counters | 1 | Race. | Counters cleared via either path; no inconsistent state. | TBD |

---

## 24. Out-of-order edge: BRESP order vs AW order (X117-X118)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X117 | D | Two AWs, B for second arrives first (illegal) | 1 | Out-of-order B. | SVA flags; engine may misbehave. | TBD |
| X118 | D | Two AWs, B for first arrives twice (illegal) | 1 | Duplicated B. | SVA flags. | TBD |

---

## 25. Coverage closure for ERROR (X119-X122)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X119 | D | Engine FSM REPORT_ALIGN_ERR state hit | 1 | Misaligned job. | FSM transition coverage hit. | TBD |
| X120 | D | Status[ALIGN_ERR] coverage | 1 | Misaligned job. | Bin hit. | TBD |
| X121 | D | BRESP error path branch in writer FSM | 1 | BRESP=SLVERR. | Branch covered. | TBD |
| X122 | D | Reset branch in every FSM state | 1 | Reset injected at all states. | Reset branch covered for each state. | TBD |

---

## 26. Sustained error stress (X123-X125)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X123 | D | 100 jobs with 1% BRESP error rate sustained | 1 | Long. | Conservation modulo errors. | TBD |
| X124 | D | 100 jobs with 1% reset rate sustained | 1 | Long. | Engine recovers each time. | TBD |
| X125 | D | 100 jobs with 1% ALIGN_ERR rate sustained | 1 | Long. | Refusals counted; valid jobs continue. | TBD |

---

## 27. Final-closure ERROR cases (X126-X128)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| X126 | D | Final-closure ERROR composite | 1 | Run all error scenarios in one frame. | All cases pass; closure. | TBD |
| X127 | D | Final-closure ERROR DEBUG=1 lineage check | 1 | Composite at DEBUG=1. | Lineage closure. | TBD |
| X128 | D | Final-closure ERROR DEBUG=2 lineage check | 1 | Composite at DEBUG=2. | Lineage residual matches expected. | TBD |

---

