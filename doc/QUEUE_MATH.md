# Queue / throughput / conservation math — `rdma_dma_engine`

**Author:** Yifeng Wang (yifenwan@phys.ethz.ch)
**Date:** 2026-05-10
**Parent docs:** [../RTL_PLAN.md](../RTL_PLAN.md),
[../tb/DV_PLAN.md](../tb/DV_PLAN.md)

This document is the analytical backbone of the `rdma_dma_engine` DV
contract. It quantifies steady-state throughput, FIFO sizing,
2-segment scatter overhead, conservation of bytes, and proves that the
DEBUG_LEVEL=2 sim-only sidecar widening is functionally inert
(removing it does not change DUT outputs).

The numerical bounds here back the PROF bucket (`tb/DV_PROF.md`)
threshold thresholds: every "throughput meets analytical model" or
"FIFO depth absorbs latency" assertion in PROF is anchored here.

---

## Notation

| Symbol | Meaning | Default |
|---|---|---|
| `f_clk` | datapath clock frequency | 250 MHz |
| `W_OPQ` | OPQ-side AXI4-Stream bus width | 36 b (32 b data + 4 b k-char) |
| `W_DMA` | AXI4 master data width = packer output width | 256 b |
| `W_PACK = W_DMA / 32` | OPQ words per packed beat | 8 |
| `MAX_BEATS` | AXI4 burst length cap | 16 |
| `B_BURST = MAX_BEATS * W_DMA / 8` | bytes per max burst | 512 B |
| `D_FIFO` | data FIFO depth (256-bit entries) | 256 |
| `T_AF = 192` | almost-full threshold (3/4 of D_FIFO) | 192 |
| `MPS` | host PCIe Maximum Payload Size | 256 B (assumed) |
| `T_BVALID` | host worst-case latency from `wlast` to `bvalid` | up to 1 µs |
| `Q` | seg_quantum, alignment for `seg_addr` and `seg_span` | 4096 B |

All numbers below assume `f_clk = 250 MHz` and `W_DMA = 256` unless
otherwise noted.

---

## 1. Steady-state throughput

### 1.1 Input-side bandwidth (OPQ → packer)

OPQ delivers 32 useful bits per cycle when `tvalid && tready`. With
`tready` tied 1 (Phase 1):

```
B_in_max = 32 b/clk * f_clk = 32 * 250e6 = 8.0 Gb/s = 1.0 GB/s
```

This is the analytical upper bound on data ingress.

### 1.2 Output-side bandwidth (writer → AXI4)

Each AXI4 W beat carries `W_DMA = 256 b = 32 B`. With one beat per clk
when `wvalid && wready`:

```
B_out_max = 256 b/clk * f_clk = 256 * 250e6 = 64.0 Gb/s = 8.0 GB/s
```

This is far above input. Output is **not** the bottleneck.

### 1.3 Bursting overhead

For every `MAX_BEATS = 16` W beats, the engine pays one `WR_AW`
transition cycle. Steady-state utilization is:

```
eta_burst = MAX_BEATS / (MAX_BEATS + 1) = 16 / 17 ≈ 0.941
```

Effective output bandwidth at sustained 100 % FIFO supply:

```
B_out_eff = eta_burst * B_out_max = 0.941 * 8.0 GB/s ≈ 7.53 GB/s
```

Still much greater than `B_in_max = 1 GB/s`.

### 1.4 Pack-overhead at the input boundary

Packer collects 8 OPQ 32 b words per 256 b output beat. So for every
1 output beat the input uses 8 cycles. Output beats per second when
input-bound:

```
R_out_input_bound = B_in_max / W_DMA = 1.0e9 * 8 / 256 = 31.25 Mbeat/s
```

So sustained AW issue rate is at most:

```
R_AW_max = R_out_input_bound / MAX_BEATS = 31.25e6 / 16 ≈ 1.95 MAW/s
```

i.e. ~1 AW every ~510 ns when the input is at 100 %.

### 1.5 Verdict

The pipeline is **input-bound** by a wide margin. The output AXI4
master is over 7× faster than the OPQ ingress. Any sustained throughput
test (DV_PROF.md §1) should hit `~1.0 GB/s` to host DRAM at 100 % OPQ
load with a fast host.

This anchors PROF cases:
- **P001** — 100 % OPQ, zero-latency host, expects throughput
  ≥ 1.0 GB/s. Anchor: `B_in_max`.
- **P008** — 100 % OPQ with `T_BVALID = 1 µs`, expects FIFO absorbs
  the latency without halt. Anchor: §2 below.
- **P019** — sustained 100 % OPQ → avg `awlen` near 15. Anchor: §1.3.

---

## 2. FIFO depth sizing

The FIFO buffers between the input rate `R_in` (256 b beats/s, packed)
and the output rate (W beats/s drained by the AXI4 master). It must
absorb host latency without forcing packer halts.

### 2.1 Worst-case host latency model

Worst-case host returns first `bvalid` after `T_BVALID = 1 µs` from
`wlast`. The engine cannot start the next AW for that segment until
the B handshake completes (single-id, in-order). So the writer is
stalled in `WR_B` for up to `T_BVALID` per burst.

During this stall, the input continues at `R_in_beats = R_out_input_bound
= 31.25 M packed beats/s`.

Beats accumulated per stall:

```
N_beats_per_stall = R_in_beats * T_BVALID
                  = 31.25e6 * 1e-6
                  = 31.25 ≈ 32 beats
```

### 2.2 FIFO occupancy bound

After one full burst of 16 beats is drained, the FIFO is potentially
empty. Then it fills for at most `N_beats_per_stall + MAX_BEATS = 48`
beats during the next stall (the +16 is to refill the next AW
trigger). So worst-case occupancy with `T_BVALID = 1 µs`:

```
N_max_T1us = N_beats_per_stall + MAX_BEATS = 31.25 + 16 ≈ 48 beats
```

`D_FIFO = 256` is **5× safety margin** over this case. Even with
`T_BVALID` extended to 4 µs (P003 case):

```
N_max_T4us = 4 * 31.25 + 16 ≈ 141 beats
```

Still under `T_AF = 192`. So `T_BVALID` up to ~5 µs is absorbed
without halt. For `T_BVALID` larger than that, halt becomes expected.

### 2.3 Verdict

`D_FIFO = 256` is correctly sized for `T_BVALID ≤ 5 µs`. PROF cases
asserting "no halt under 1 µs T_BVALID" (P002) are valid; cases at
4 µs (P003) are at the boundary; cases at higher `T_BVALID` should
expect halt and test it as a feature (cnt_halt > 0).

This anchors PROF cases:
- **P002** — no halt at `T_BVALID = 1 µs`. Anchor: §2.2 (N=48 << 192).
- **P003** — halt expected at `T_BVALID = 4 µs`. Anchor: §2.2 (N=141 ~ 192).
- **P008** — sustained 100 % OPQ with fully-throttled host →
  intermittent halt expected.

---

## 3. 2-segment scatter overhead

When `seg0` ends mid-burst-stream and the engine transitions to
`seg1`, the writer pays one extra cycle in `WR_PROGRAM` and one extra
`WR_AW` issuance for the start of seg1's first burst.

### 3.1 Per-crossing latency overhead

Worst case from `bvalid` of last seg0 burst to `awvalid` of first seg1
burst:

```
T_seg_xfer = T_WR_B (1 clk to accept B)
           + T_WR_PROGRAM (1 clk to latch new seg ptr)
           + T_WR_AW (1 clk to assert awvalid)
           = 3 clks @ f_clk = 12 ns
```

Compared to a single-burst latency of `MAX_BEATS + 1 = 17 clks ≈ 68 ns`,
this is a 17 % overhead per segment crossing. For a typical job that
crosses 0 or 1 segment boundaries, this overhead is negligible.

### 3.2 Cumulative throughput impact

A job with `N_xfer` segment crossings pays `3 * N_xfer` extra clks.
For a `seg0_span = 4 KB, seg1_span = 4 KB` job (1 crossing), total
write cycles:

```
T_total = (8192 / W_DMA_bytes) * (1 + 1/MAX_BEATS) + 3
        = 256 * 17/16 + 3
        = 272 + 3 = 275 clks ≈ 1.10 µs
```

vs. single-segment `8 KB`:

```
T_total_1seg = 256 * 17/16 = 272 clks ≈ 1.09 µs
```

Overhead ≈ 1 % per crossing. **Negligible for the Phase 1 maximum 1
crossing per job.**

### 3.3 Verdict

2-segment scatter overhead is not a throughput concern. PROF cases
that compare 1-seg vs 2-seg throughput (P010-P011) should observe
~1 % delta. This anchors:

- **P010** — 100 single-segment 4 KB jobs back-to-back
- **P011** — 100 two-segment jobs (1 crossing each)

Both should report similar throughput (within 5 %).

---

## 4. Conservation invariant

### 4.1 The invariant

The contract from `RTL_PLAN.md` §6 case 7 is:

```
sum(cnt_input_w) * 4 == sum(bytes_written) + sum(halt_bytes)
```

where `halt_bytes = sum(cnt_halt) * 4`.

### 4.2 Per-job decomposition

Inside a single job:

```
cnt_input_w * 4 = bytes_packed + halt_bytes
bytes_packed   = bytes_written + bytes_padding
bytes_padding  = sum over EOE-flushes of (32 - bytes_in_word)
```

So:

```
cnt_input_w * 4 = bytes_written + bytes_padding + halt_bytes
```

Or equivalently:

```
bytes_written = cnt_input_w * 4 - bytes_padding - halt_bytes
```

`bytes_padding` is **zero** unless EOE arrives mid-beat. The DV
scoreboard predicts `bytes_padding` from the OPQ stimulus stream and
adds it to the conservation check.

### 4.3 Edge case: status[FULL] vs status[EOE]

When the engine fills both segments before EOE arrives:
- `bytes_written = seg0_span + seg1_span`
- `bytes_padding = 0` (no EOE-pad emitted; engine just stops)
- `cnt_eoe_observed = 0` for that drain

When EOE arrives at exact byte boundary (status[EOE]=1 AND
status[FULL]=1 simultaneously):
- `bytes_written = seg0_span + seg1_span` (FULL)
- `bytes_padding = 0` (EOE arrived at exact 32 B boundary)
- `cnt_eoe_observed = 1`

When EOE arrives mid-beat (typical):
- `bytes_written = some N <= seg0_span + seg1_span`
- `bytes_padding = (32 - bytes_in_word) > 0` for the EOE-pad beat
- engine emits one extra W beat with masked wstrb

The DV scoreboard tracks all three cases. The conservation check uses
`cnt_input_w * 4 == bytes_written + bytes_padding + halt_bytes`.

### 4.4 Verdict

Conservation is well-defined per job and per-IP-soak. The DV
scoreboard implements it as a summation; PROF cases (P024-P028)
exercise it across long soaks.

---

## 5. DEBUG_LEVEL=2 sidecar inertness proof

The DEBUG_LEVEL=2 sim-only widening adds a per-hit metadata sidecar
`(lane, hit_id, source_ts, sequence_no)` flowing alongside the payload
through the entire datapath. The proof obligation is: **removing the
sidecar must not change any payload signal of the DUT**.

### 5.1 The argument

The sidecar is structurally:

1. driven by the TB driver alongside the payload at the DUT's input
   pins (parametrized port group)
2. flowed through the packer in lockstep with payload (one sidecar
   entry per accepted 32 b OPQ beat, packed into the same FIFO entry)
3. flowed through the FIFO (sideband bits)
4. flowed through the writer (per-W-beat sidecar emitted on a shadow
   port for the TB monitor)

For the inertness proof:

- **No combinational fan-in from sidecar to payload.** The packer's
  payload accumulator (`accum[slot_idx*32 +: 32]`) is a function of
  payload `data` only — not of the sidecar fields. The slot index,
  pending-EOE flag, and `last_in_event` are functions of payload
  control (`tvalid`, `tlast`) only.
- **No combinational fan-in from sidecar to AXI4 master outputs.**
  `awaddr`, `awlen`, `awsize`, `awburst`, `awvalid`, `wdata`, `wstrb`,
  `wlast`, `wvalid`, `bready` all derive from the payload domain only.
- **No combinational fan-in from sidecar to counters.** `cnt_input_w`,
  `cnt_bytes_written`, `cnt_halt`, `cnt_eoe_observed` count payload
  events.
- **No combinational fan-in from sidecar to job-status report
  fields.** Status bits derive from payload state (FSM, FIFO, EOE
  detection).

The sidecar is a **pure passenger** of the payload pipeline.

### 5.2 The synthesis-build behavior

When `DEBUG_LEVEL = 0` (synth corner):

- The sidecar input ports are **tied to `'0`** at the DUT boundary
  (per the parameter-controlled port-mux RTL pattern that codex2 will
  implement in `rdma_dma_engine.sv`).
- The sidecar carrying through the packer / FIFO / writer is **0**.
- The sidecar output ports are `'0` and synthesis prunes the unused
  flop chain.

When `DEBUG_LEVEL = 1`:

- Sidecar still tied to `'0` at the DUT boundary (DEBUG=1 only adds
  the `dbg1_*` observation taps; it does **not** add the sidecar).
- Same as DEBUG=0 for sidecar; only `dbg1_*` taps are exposed.

When `DEBUG_LEVEL = 2`:

- Sidecar input ports become live; carry the per-hit meta from the TB.
- Sidecar flop chain in the packer / FIFO / writer becomes live.
- Sidecar output ports expose the per-W-beat lineage to the TB.

### 5.3 Inertness check (DV-side proof)

The DV scoreboard cross-validates: for the **same OPQ stimulus**, the
DEBUG=1 build and the DEBUG=2 build must produce **bit-identical**
payload signals on:

- `m_axi_awaddr`, `m_axi_awlen`, `m_axi_awsize`, `m_axi_awburst`,
  `m_axi_awvalid`, `m_axi_wdata`, `m_axi_wstrb`, `m_axi_wlast`,
  `m_axi_wvalid`, `m_axi_bready`
- `s_axis_opq_tready`
- `cnt_input_w`, `cnt_bytes_written`, `cnt_halt`, `cnt_eoe_observed`
- `job_done`, `job_status`, `job_bytes_written_*`, `job_event_count`,
  `job_first_event_ts`, `job_last_event_ts`, `job_sqe_id_echo`

If they differ, the sidecar has leaked into a payload-affecting cone
and the inertness proof fails. This is enforced by the cross-build
residual reporter in `DV_HARNESS.md` §4.7 and the dual-env regression
in `DV_PLAN.md` §3.11.

### 5.4 Verdict

The DEBUG=2 sidecar is structurally inert by design (pure passenger,
no fan-in into payload). The DV scoreboard's bit-identity check
enforces this at every job boundary. **Any disagreement is a closure
blocker** per the dv-workflow OoO-datapath rule.

This anchors:
- **P099** — DEBUG=1 vs DEBUG=2 cross-build residual report
- **P100** — DEBUG=2 lineage with random halt
- **B093-B099** — DEBUG=2 lineage smoke (validates the per-hit
  sidecar carries through correctly)
- **B100** — DEBUG=2 sidecar inert when DEBUG=1 build runs (validates
  the inertness proof end-to-end)

---

## 6. Synthesis cost

For reference (not formally bound here; details land in
`syn/quartus/` standalone signoff):

- DEBUG=0 build: lowest area; FIFO depth 256 × 256 b ≈ 8 KB; +
  control flops.
- DEBUG=1 build: same area + ~30 observation flops (FIFO level
  counter, FSM state, AW/W/B inflight counters); negligible.
- DEBUG=2 build: not built for synthesis. Sim-only; ports prune.

Standalone Quartus 1.1× sign-off corner is `275 MHz` (250 × 1.1).
DEBUG=0 build target. DEBUG=1 secondary check.

---

## 7. Linkage to DV bucket cases

Bucket cases that depend on this analysis:

| Case | Anchor |
|------|--------|
| P001 (zero-latency throughput) | §1.5 (input-bound 1 GB/s) |
| P002 (no halt at 1 µs T_BVALID) | §2.3 (FIFO 5x margin) |
| P003 (halt at 4 µs T_BVALID) | §2.3 (boundary) |
| P008 (100 % OPQ throttled host) | §2 |
| P010 / P011 (1-seg vs 2-seg) | §3.3 (~1 % overhead) |
| P019 (avg awlen near 15) | §1.3 (eta_burst=16/17) |
| P020 (50 % OPQ → awlen ~7-8) | §1.3 (eta_burst tracks load) |
| P021 (10 % OPQ → awlen near 0-2) | §1.3 |
| P024 (conservation 1000 events 50 % load) | §4 |
| P025 (conservation 5000 events 100 % load) | §4 |
| P026 / P027 / P028 | §4 |
| P099 (cross-build residual) | §5.3 (inertness) |
| B093-B100 (DEBUG=2 smoke) | §5.4 (inertness proof) |

This document is the analytical anchor for these cases. When a PROF
case fails, the failing residual must be reconciled against the
prediction here before declaring an RTL bug.

---

## 8. Open items

- §1 assumes `tready` tied 1 (Phase 1). When Phase 2 adds a real
  backpressure path from FIFO almost-full to OPQ, the input-bound
  bandwidth becomes a conditional `B_in_eff = (1 - p_halt) * B_in_max`.
  Re-derive when that happens.
- §2 assumes single-ID AXI4 master with in-order completion. If
  Phase 2 widens to multi-ID, the FIFO sizing becomes an M/M/1 → M/M/c
  problem. Re-derive.
- §3 assumes Phase 1 maximum 1 crossing per job. Phase 2 may extend
  to multi-segment jobs (>2 segments); re-derive for the larger
  crossing count.
- §5 inertness proof relies on the codex2 RTL author respecting the
  parameter-controlled port-mux pattern. The DV cross-build check is
  the safety net — it catches leaks if the proof obligation is
  violated.
