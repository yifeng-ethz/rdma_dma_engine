# DV Profile — rdma_dma_engine

**Companion docs:** `DV_PLAN.md`, `DV_HARNESS.md`, `DV_BASIC.md`,
`DV_EDGE.md`, `DV_ERROR.md`, `DV_CROSS.md`, `DV_COV.md`,
`BUG_HISTORY.md`.

**Parent:** [DV_PLAN.md](DV_PLAN.md)
**ID Range:** P001-P128
**Total:** 128 cases (0 implemented / 0 waived)

This document collects the throughput / soak / stress / performance
cases for `rdma_dma_engine`. Cases are derived from `DV_PLAN.md` §3.7,
§3.8, the queue-math model in `../doc/QUEUE_MATH.md`, and the
checkpoint-UCDB rule in the dv-workflow skill. Random cases use the
`opq_axis_burst_random` and `axi_compl_throttle_random` sequences.

**Methodology key:**
- **D** = Directed (hand-crafted stimulus, single transaction)
- **R** = Constrained-random (UVM `rand` constraints; multiple
  transactions per case)

---

## 1. Summary

| Section | Cases | ID Range | What it Proves | Current Case |
|---------|------:|----------|----------------|--------------|
| Sustained throughput baseline | 8 | P001-P008 | 100% OPQ load with default-latency host: throughput meets queue-math model in QUEUE_MATH.md | 0/8 |
| Job-stream stress | 8 | P009-P016 | back-to-back job streams varying span and rate | 0/8 |
| Burst-sizing efficiency | 6 | P017-P022 | verify burst-sizing meets analytical model from QUEUE_MATH.md | 0/6 |
| Conservation under stress | 5 | P023-P027 | long-soak conservation invariants hold across various load profiles | 0/5 |
| Halt-rate stress | 5 | P028-P032 | FIFO almost-full -> packer halt under various rate combinations | 0/5 |
| Pipeline depth and latency | 4 | P033-P036 | end-to-end latency from job_req to job_done as a function of span / load | 0/4 |
| Resource-pressure profile | 4 | P037-P040 | long-run scenarios that exercise FIFO at varying steady-state occupancy | 0/4 |
| DEBUG_LEVEL=1 long-soak invariants | 3 | P041-P043 | dbg1 taps remain consistent over 100k+ clk soak | 0/3 |
| DEBUG_LEVEL=2 lineage long-soak | 4 | P044-P047 | lineage matcher zero-residual over long soaks; lineage curve plotted | 0/4 |
| Random profile sweeps | 8 | P048-P055 | randomized profile parameters: ready lag, valid lag, bvalid lag, halt prob | 0/8 |
| Throughput regressions | 4 | P056-P059 | watch for performance regressions: avg awlen, throughput, halt rate | 0/4 |
| Checkpoint UCDB random soak (per dv-workflow) | 3 | P060-P062 | log-spaced UCDB checkpoint emission for random long runs | 0/3 |
| Multi-job soak under throttled host | 6 | P063-P068 | long runs with realistic host latency profiles | 0/6 |
| Burst-rate diversity | 7 | P069-P075 | various input/output rate combinations to stress the queue dynamics | 0/7 |
| Throughput regression -- run-to-run consistency | 6 | P076-P081 | key throughput metrics consistent across seeds | 0/6 |
| DEBUG=2 lineage at scale | 6 | P082-P087 | lineage matcher scales to long soaks without growth in residual | 0/6 |
| Coverage closure stress | 7 | P088-P094 | additional cases targeting code-coverage gaps | 0/7 |
| Performance profiling | 6 | P095-P100 | measure and report key performance metrics | 0/6 |
| Steady-state convergence | 4 | P101-P104 | verify steady-state metrics converge after warm-up | 0/4 |
| Random profile coverage closure | 5 | P105-P109 | random sweeps with explicit coverage targets | 0/5 |
| DEBUG=2 sidecar bandwidth profile | 3 | P110-P112 | lineage carrying does not slow simulation more than 2x | 0/3 |
| Stress-Conservation cross-bucket | 4 | P113-P116 | long soaks combining stress and conservation | 0/4 |
| Long-soak full regression | 7 | P117-P123 | comprehensive long-soaks combining everything | 0/7 |
| Final closure profile | 5 | P124-P128 | the final profile cases that close the PROF bucket | 0/5 |

---

## 2. Sustained throughput baseline (P001-P008)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P001 | D | 100% OPQ, zero-latency host, 100 events | 1 | Sustained tvalid=1 for 100 events of 64 OPQ words; zero-latency completer. | Sustained throughput >= 1.0 GB/s @ 250 MHz; conservation. | TBD |
| P002 | D | 100% OPQ, 1us BVALID latency, 100 events | 1 | axi_completer T_BVALID=250 (=1us @ 250 MHz). | FIFO absorbs latency; no halt; conservation. | TBD |
| P003 | D | 100% OPQ, 4us BVALID latency, 100 events | 1 | T_BVALID=1000. | FIFO at 192 then halt expected; cnt_halt>0. | TBD |
| P004 | D | 100% OPQ for 10000 events single drain | 1 | Long drain. | Conservation; FIFO saturation tracked via dbg1. | TBD |
| P005 | D | 50% OPQ load, 100 events | 1 | tvalid=1 every other clk. | No halt; conservation. | TBD |
| P006 | D | 75% OPQ load, 100 events | 1 | tvalid=1 3/4 of clks. | No halt; conservation. | TBD |
| P007 | D | 10% OPQ load, 100 events | 1 | Sparse. | No backpressure; conservation. | TBD |
| P008 | D | 100% OPQ with throttled wready (1/2 ready) | 1 | wready alternating. | FIFO fills toward almost_full; halt may trigger. | TBD |

---

## 3. Job-stream stress (P009-P016)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P009 | D | 100 single-segment 4 KB jobs back-to-back | 1 | Continuous queue. | All complete in order; conservation across run. | TBD |
| P010 | D | 100 single-segment 16 KB jobs back-to-back | 1 | Larger spans. | All complete; conservation. | TBD |
| P011 | D | 100 two-segment jobs back-to-back | 1 | Mixed span sizes. | All complete; per-job SEG_BOUNDARY_HIT correctly set. | TBD |
| P012 | D | 1000 jobs of mixed spans (long-soak) | 1 | Mixed. | Conservation across full soak; bug history empty. | TBD |
| P013 | D | 100 jobs with random rqe_id | 1 | Walk rqe_id space. | Echos correct on each job. | TBD |
| P014 | D | Job stream with continuous OPQ ingest (no idle) | 1 | OPQ never idles; jobs queue. | No drops between jobs; conservation per job. | TBD |
| P015 | D | Job stream with intermittent OPQ idle | 1 | OPQ idles 100 clk between events. | All complete. | TBD |
| P016 | D | Job stream of 50 jobs with varying lag profile | 1 | Each job has different host latency. | All complete. | TBD |

---

## 4. Burst-sizing efficiency (P017-P022)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P017 | D | Sustained 100% OPQ -> avg awlen near 15 | 1 | 100% OPQ with fast host. | Avg awlen across 1000 bursts >= 14. | TBD |
| P018 | D | 50% OPQ -> avg awlen drops to ~7-8 | 1 | 50% OPQ. | Avg awlen ~7-8. | TBD |
| P019 | D | 10% OPQ -> avg awlen near 0-2 | 1 | Sparse OPQ. | Avg awlen <=2. | TBD |
| P020 | D | Throttled host extends FIFO occupancy time | 1 | Slow host wready. | FIFO at high occupancy for long stretch. | TBD |
| P021 | D | Burst utilization metric > 80% under nominal | 1 | Default lag. | Sigma (W beats) / Sigma (16 * AWs) > 0.8. | TBD |
| P022 | D | Throughput model match: measured ~ predicted | 1 | Long run. | Throughput within 5% of QUEUE_MATH.md prediction. | TBD |

---

## 5. Conservation under stress (P023-P027)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P023 | D | Conservation 1000 OPQ events at 50% load | 1 | Long soak. | Sigma input*4 == Sigma written + Sigma halt*4. | TBD |
| P024 | D | Conservation 5000 OPQ events at 100% load | 1 | Long soak. | Same invariant; halt may be non-zero. | TBD |
| P025 | D | Conservation across 100 jobs | 1 | Job stream. | Per-IP totals match sum-per-job. | TBD |
| P026 | D | Conservation with random halt injection | 1 | Random FIFO almost-full. | halt_bytes accounted in invariant. | TBD |
| P027 | D | Conservation across reset_counters strobe | 1 | Mid-run clear. | Invariant restarts after clear; pre-clear totals lost (expected). | TBD |

---

## 6. Halt-rate stress (P028-P032)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P028 | D | Forced halt 100 dropped beats | 1 | Force FIFO almost-full; drive 100 OPQ beats while almost-full. | cnt_halt==100; conservation. | TBD |
| P029 | D | Halt rate 10% (1 in 10 OPQ beats dropped) | 1 | Tuned host throttle. | Steady halt rate; conservation. | TBD |
| P030 | D | Halt rate 50% under sustained OPQ | 1 | Aggressive throttle. | halt~50% of input; conservation. | TBD |
| P031 | D | Halt cleared by host wready burst | 1 | Halt then host accepts. | Halt drops; FIFO drains. | TBD |
| P032 | D | Halt accounting per-job (status[HALT]) | 1 | Halt during one of 5 jobs. | Only that job's status[HALT]=1. | TBD |

---

## 7. Pipeline depth and latency (P033-P036)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P033 | D | Latency: 4 KB single-segment, fast host, no halt | 1 | Best case. | End-to-end latency <= analytical lower bound (QUEUE_MATH). | TBD |
| P034 | D | Latency: 16 KB single-segment, throttled host | 1 | Throttle. | Latency tracks throttle; SVA passes. | TBD |
| P035 | D | Latency: 100 jobs averaged | 1 | Soak. | Mean latency reported; matches model. | TBD |
| P036 | D | Latency under halt stress (4 KB) | 1 | Forced halt. | Latency increases by FIFO drain time. | TBD |

---

## 8. Resource-pressure profile (P037-P040)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P037 | D | FIFO steady at 50% occupancy | 1 | Tuned throttle. | Avg dbg1_fifo_level ~128 across 10000 clks. | TBD |
| P038 | D | FIFO steady at 90% occupancy | 1 | Tighter throttle. | Avg ~230; intermittent halt. | TBD |
| P039 | D | FIFO oscillates: empty <-> almost-full repeatedly | 1 | Periodic throttle. | FIFO oscillation captured in dbg1. | TBD |
| P040 | D | FIFO at almost-full for 1000 clks straight | 1 | Sustained near-full. | halt_pulse intermittent; conservation. | TBD |

---

## 9. DEBUG_LEVEL=1 long-soak invariants (P041-P043)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P041 | D | 100k clk soak DEBUG=1 invariants hold | 1 | Long random run. | All dbg1 invariants from dbg1_invariant_checker pass throughout. | TBD |
| P042 | D | 100k clk soak halt accounting (dbg1_halt_pulse vs cnt_halt) | 1 | Long. | Sigma dbg1_halt_pulse == cnt_halt delta. | TBD |
| P043 | D | Long-soak FIFO level histogram captured | 1 | Long random. | Histogram bins populated as expected; no anomalies. | TBD |

---

## 10. DEBUG_LEVEL=2 lineage long-soak (P044-P047)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P044 | D | 100k OPQ-beat DEBUG=2 lineage soak | 1 | DEBUG=2; long random. | Matcher zero-residual at every job boundary. | TBD |
| P045 | D | 100 jobs DEBUG=2 lineage | 1 | DEBUG=2; job stream. | Per-job lineage closure. | TBD |
| P046 | D | Cross-build residual report dual run | 1 | Run dual_test on long soak. | DEBUG=1 vs DEBUG=2 nominal residuals identical. | TBD |
| P047 | D | DEBUG=2 lineage with random halt | 1 | DEBUG=2; halt induced. | Matcher residual == cnt_halt at every job_done. | TBD |

---

## 11. Random profile sweeps (P048-P055)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P048 | R | Random host_lag in [0, 100] clks per beat | 32 | Sweep. | All transactions complete; conservation. | TBD |
| P049 | R | Random T_BVALID in [0, 1000] clks | 32 | Sweep. | All complete; FIFO behavior bounded. | TBD |
| P050 | R | Random opq_idle in [0, 50] clks between beats | 32 | Sweep. | All complete. | TBD |
| P051 | R | Random combination: lag + bvalid + idle | 32 | Joint sweep. | All complete; per-job conservation; per-build lineage closure. | TBD |
| P052 | R | Random 100 jobs with varying span (4 KB to 64 KB) | 100 | Span sweep. | All complete; conservation; lineage. | TBD |
| P053 | R | Random 50 two-segment jobs with random seg sizes | 50 | Two-seg sweep. | All complete; SEG_BOUNDARY_HIT correctly set per case. | TBD |
| P054 | R | Random 200 jobs long-soak mixed | 200 | Heavy sweep. | Conservation at end; lineage; bug history empty. | TBD |
| P055 | R | Random 1000 OPQ events (8-256 beats each) one drain | 1000 | Single-drain stress. | All conserved; bytes_written matches packer prediction. | TBD |

---

## 12. Throughput regressions (P056-P059)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P056 | D | Avg awlen >= 14 under nominal load (regression check) | 1 | Default profile, 100 events. | Avg awlen captured; >= 14 baseline. | TBD |
| P057 | D | Sustained throughput >= 0.95 GB/s under nominal | 1 | 100 events. | Throughput captured; baseline check. | TBD |
| P058 | D | Halt rate <= 1% under nominal load | 1 | Default profile. | halt/(input+halt) <= 0.01. | TBD |
| P059 | D | Mean latency report (single-job 4 KB) | 1 | Single job. | Latency captured; baseline. | TBD |

---

## 13. Checkpoint UCDB random soak (per dv-workflow) (P060-P062)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P060 | R | Checkpoint UCDB at 1/2/4/8/.../N for 100k random OPQ | 100000 | DEBUG=1 long random. | UCDB snapshots saved at log-spaced txn boundaries; coverage curve plottable. | TBD |
| P061 | R | Same checkpoint scheme for DEBUG=2 | 100000 | DEBUG=2 long random. | UCDB checkpoints; lineage residual=0 at every checkpoint. | TBD |
| P062 | R | Checkpoint per-job 100/200/.../1000 jobs | 1000 | Job stream. | UCDB at every 100 jobs. | TBD |

---

## 14. Multi-job soak under throttled host (P063-P068)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P063 | D | 100 jobs at host_lag=100 clk | 1 | Throttled. | All complete; conservation. | TBD |
| P064 | D | 100 jobs at host_lag=500 clk | 1 | Heavily throttled. | All complete; halt may be non-zero. | TBD |
| P065 | D | 100 jobs at variable host_lag (rand 0..500) | 1 | Random throttle. | Conservation. | TBD |
| P066 | D | Soak: 1000 jobs with 250 clk T_BVALID | 1 | Long. | Conservation; lineage closure per dual-build. | TBD |
| P067 | D | Soak: 5000 jobs sustained 50% load | 1 | Very long. | Conservation; bug history empty. | TBD |
| P068 | D | Soak: 10000 events single drain | 1 | Single mega-drain. | Conservation. | TBD |

---

## 15. Burst-rate diversity (P069-P075)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P069 | D | Input rate 100% / Output rate 50% | 1 | FIFO fills. | halt expected. | TBD |
| P070 | D | Input rate 50% / Output rate 100% | 1 | FIFO drains. | no halt. | TBD |
| P071 | D | Input rate 25% / Output rate 100% | 1 | Sparse. | no halt. | TBD |
| P072 | D | Input rate 100% / Output rate 25% | 1 | Severe FIFO fill. | halt; conservation. | TBD |
| P073 | D | Input bursty 0%/100% alternating, Output 50% | 1 | Pulsed input. | FIFO smooths; conservation. | TBD |
| P074 | D | Output bursty (host wready bursty) | 1 | Pulsed output. | FIFO oscillates; conservation. | TBD |
| P075 | D | Both rates random | 1 | Random in/out. | Conservation; FIFO bounded. | TBD |

---

## 16. Throughput regression -- run-to-run consistency (P076-P081)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P076 | D | Throughput consistency seed 1 vs seed 2 (P008 baseline) | 1 | Same scenario, different seed. | Throughput within 5%. | TBD |
| P077 | D | Throughput consistency seed 100 vs seed 200 | 1 | Different seeds. | Same. | TBD |
| P078 | D | Throughput consistency on bucket_frame (DEBUG=1) | 1 | Continuous BASIC frame. | Total throughput within 5% of single-run sum. | TBD |
| P079 | D | Throughput consistency on bucket_frame (DEBUG=2) | 1 | Same DEBUG=2. | Same. | TBD |
| P080 | D | Halt-rate consistency seed-to-seed | 1 | 100 jobs each. | Halt rate within 1%. | TBD |
| P081 | D | Latency p50 consistency seed-to-seed | 1 | 100 jobs. | p50 latency within 5%. | TBD |

---

## 17. DEBUG=2 lineage at scale (P082-P087)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P082 | D | DEBUG=2 lineage 100k beats no halt | 1 | DEBUG=2 long. | Residual=0 throughout. | TBD |
| P083 | D | DEBUG=2 lineage 100k beats with random halt | 1 | DEBUG=2 + halt. | Residual==cnt_halt at each job_done. | TBD |
| P084 | D | DEBUG=2 lineage memory bounded | 1 | Long soak; track matcher queue depth. | Matcher queue depth bounded by FIFO depth + a few. | TBD |
| P085 | D | DEBUG=2 lineage replays under reset_counters | 1 | Mid-run clear. | Lineage matcher correctly restarts. | TBD |
| P086 | D | Cross-build dual residual report at every checkpoint | 1 | 100k checkpointed. | DEBUG=1 vs DEBUG=2 nominal residuals identical at every checkpoint. | TBD |
| P087 | D | DEBUG=2 throughput within 10% of DEBUG=1 throughput | 1 | Compare wallclock. | DEBUG=2 sim slowdown <=2x; functional throughput identical. | TBD |

---

## 18. Coverage closure stress (P088-P094)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P088 | D | FSM transition rarely-hit: PROGRAM->REPORT_ALIGN_ERR via late-arriving misalignment check | 1 | Late check. | Transition observed; coverage covers branch. | TBD |
| P089 | D | Burst sizing edge: AWLEN computed at exact MAX-1 (15 minus 1) | 1 | Targeted. | Branch covered. | TBD |
| P090 | D | FIFO threshold transition repeatedly | 1 | Hammer threshold. | Transition covered ~100 times. | TBD |
| P091 | D | Status bit set: HALT and EOE simultaneously | 1 | Halt + EOE. | Both bits set; cross-coverage hit. | TBD |
| P092 | D | Status bit set: HALT and FULL simultaneously | 1 | Halt + FULL. | Cross hit. | TBD |
| P093 | D | Status bit set: HALT and SEG_BOUNDARY_HIT | 1 | Halt at boundary. | Cross hit. | TBD |
| P094 | D | Counter clear during reset (combined) | 1 | Reset + clear. | Counters cleared via both paths. | TBD |

---

## 19. Performance profiling (P095-P100)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P095 | D | Avg time-to-first-W after AW measured | 1 | 100 bursts. | Reported; baseline. | TBD |
| P096 | D | Avg time-from-wlast-to-bvalid measured | 1 | 100 bursts. | Reported. | TBD |
| P097 | D | Avg time-from-job_req-to-first-AW measured | 1 | 100 jobs. | Reported. | TBD |
| P098 | D | Avg time-from-last-B-to-job_done measured | 1 | 100 jobs. | Reported. | TBD |
| P099 | D | Avg awlen distribution histogram | 1 | 1000 bursts. | Histogram captured. | TBD |
| P100 | D | FIFO occupancy histogram | 1 | Long run. | Histogram captured; bins covered. | TBD |

---

## 20. Steady-state convergence (P101-P104)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P101 | D | Throughput converges within 100 bursts | 1 | Long run. | Throughput stabilizes within 5% of asymptote. | TBD |
| P102 | D | FIFO occupancy converges within 1000 clks | 1 | Long run. | Avg level stabilizes. | TBD |
| P103 | D | Halt rate converges within 1000 jobs | 1 | Long run. | Stable halt rate. | TBD |
| P104 | D | Latency p99 stabilizes after 1000 jobs | 1 | Long run. | p99 latency stabilizes. | TBD |

---

## 21. Random profile coverage closure (P105-P109)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P105 | R | Random profile sweep targeting cg_axi_burst | 256 | rand awlen, rand awaddr. | All bins of cg_axi_burst covered. | TBD |
| P106 | R | Random profile sweep targeting cg_packer | 256 | rand EOE positions. | All cg_packer bins covered. | TBD |
| P107 | R | Random profile sweep targeting cg_fifo | 256 | rand FIFO levels. | All cg_fifo bins covered. | TBD |
| P108 | R | Random profile sweep targeting cg_status_cross | 128 | rand status bit combinations. | All cross bins covered. | TBD |
| P109 | R | Random profile sweep targeting cg_dbg2_lineage | 128 | DEBUG=2 random. | All cg_dbg2_lineage bins covered. | TBD |

---

## 22. DEBUG=2 sidecar bandwidth profile (P110-P112)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P110 | D | Wallclock comparison DEBUG=1 vs DEBUG=2 same scenario | 1 | 100 events. | DEBUG=2 wallclock <=2x DEBUG=1 wallclock. | TBD |
| P111 | D | Wallclock comparison long soak | 1 | 10000 events. | Same. | TBD |
| P112 | D | Sidecar capture overhead reported | 1 | TB profiling. | Per-beat overhead captured; <10% of total cycle time. | TBD |

---

## 23. Stress-Conservation cross-bucket (P113-P116)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P113 | R | Stress with halt at 5% | 100 | 5% halt rate. | Conservation; halt accounted. | TBD |
| P114 | R | Stress with reset every 100 jobs | 10 | Mid-run resets. | Counters cleared per reset; per-segment conservation. | TBD |
| P115 | R | Stress with random ALIGN_ERR injection | 100 | 10% misaligned. | Refused jobs do not affect counters; valid jobs accounted. | TBD |
| P116 | R | Stress with random opcode (Phase 1: only 0x0001) | 100 | rand opcode. | Engine ignores or handles per spec; conservation. | TBD |

---

## 24. Long-soak full regression (P117-P123)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P117 | D | Bucket_frame BASIC long soak DEBUG=1 | 1 | Continuous BASIC frame at DEBUG=1. | All cases pass; coverage rolls up; lineage closure. | TBD |
| P118 | D | Bucket_frame BASIC long soak DEBUG=2 | 1 | Continuous BASIC frame at DEBUG=2. | Same. | TBD |
| P119 | D | Bucket_frame EDGE long soak DEBUG=1 | 1 | Continuous EDGE frame at DEBUG=1. | Same. | TBD |
| P120 | D | Bucket_frame EDGE long soak DEBUG=2 | 1 | Continuous EDGE frame at DEBUG=2. | Same. | TBD |
| P121 | D | all_buckets_frame DEBUG=1 | 1 | BASIC->EDGE->PROF->ERROR at DEBUG=1. | Coverage closure. | TBD |
| P122 | D | all_buckets_frame DEBUG=2 | 1 | BASIC->EDGE->PROF->ERROR at DEBUG=2. | Coverage closure; lineage residual report. | TBD |
| P123 | R | Random 24-hour-equivalent soak (10M clk) | 10000000 | Long random soak. | Conservation throughout; checkpoint UCDBs at log-spaced intervals. | TBD |

---

## 25. Final closure profile (P124-P128)

| ID | Method | Scenario | Iter | Stimulus | Pass Criteria | Function Reference |
|----|--------|----------|------|----------|---------------|--------------------|
| P124 | D | Final-closure throughput report | 1 | Composite report. | All targets met or annotated. | TBD |
| P125 | D | Final-closure latency report | 1 | Composite. | Same. | TBD |
| P126 | D | Final-closure halt-rate report | 1 | Composite. | Same. | TBD |
| P127 | D | Final-closure lineage residual report (DEBUG=2) | 1 | Composite. | Residual==0 across whole regression. | TBD |
| P128 | D | Final-closure dual-build comparison report | 1 | DEBUG=1 vs DEBUG=2. | Identical functional results. | TBD |

---

