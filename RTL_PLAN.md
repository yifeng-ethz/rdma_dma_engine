# `rdma_dma_engine` — RTL Plan

Status: **PLAN — pending review.** Part of the
[`rdma_subsystem`](../rdma_subsystem/ARCHITECTURE_PLAN.md). Read the
parent architecture plan first for the SQ/CQ contract context.

## 1. Role within the subsystem

Pure data mover. Knows nothing about SQ rings, CQ rings, or doorbells.
Programmed by the `rdma_run_manager` with `(buf_addr, buf_len_bytes, sqe_id)`
and drains an OPQ-side data stream into that named host-DRAM region using
an Avalon-MM master. Reports back `(bytes_written, status, sqe_id)` on
completion.

Owns the high-bandwidth path. Lives between OPQ egress and the host.

## 2. Module hierarchy

```
rdma_dma_engine.sv          (top — wires the three sub-modules)
├── rdma_dma_packer.sv      (32b → 256b accumulator with EOE sideband)
├── rdma_dma_data_fifo.sv   (256b SCFIFO + sideband bits, ~256 entries)
└── rdma_dma_writer.sv      (Avalon-MM burst master, programmable per-job)
```

## 3. Top-level interface

All host-DRAM access is **AXI4 (full)** so the supercore can be assembled
on a non-Merlin / pure-RTL fabric. The OPQ side is **AXI4-Stream**.

```systemverilog
module rdma_dma_engine #(
    parameter int unsigned DMA_DATA_W       = 256,   // AXI4 write data width
    parameter int unsigned MAX_BURST_BEATS  = 16,    // AXI4 AWLEN cap
    parameter int unsigned SEG_QUANTUM_BYTES= 4096   // 4 KB span granularity
) (
    input  logic                 clk,
    input  logic                 reset_n,

    // OPQ egress (AXI4-Stream sink, 36b TDATA)
    input  logic [35:0]          s_axis_opq_tdata,    // {datak[3:0], data[31:0]}
    input  logic                 s_axis_opq_tvalid,
    output logic                 s_axis_opq_tready,
    input  logic                 s_axis_opq_tlast,    // = OPQ eop
    input  logic [1:0]           s_axis_opq_tuser,    // [0]=sop

    // Two-segment job interface from rdma_run_manager
    input  logic                 job_req,
    input  logic [63:0]          job_seg0_addr,
    input  logic [63:0]          job_seg0_span,
    input  logic [63:0]          job_seg1_addr,       // 0 if unused
    input  logic [63:0]          job_seg1_span,       // 0 if unused
    input  logic [15:0]          job_sqe_id,
    input  logic [15:0]          job_opcode,
    output logic                 job_done,
    output logic [63:0]          job_bytes_written_total,
    output logic [31:0]          job_seg0_bytes_written,
    output logic [31:0]          job_seg1_bytes_written,
    output logic [15:0]          job_status,           // see ARCH §5 status bits
    output logic [15:0]          job_sqe_id_echo,
    output logic [31:0]          job_event_count,
    output logic [63:0]          job_first_event_ts,
    output logic [63:0]          job_last_event_ts,

    // AXI4 (full) master, write channel only used by this engine
    output logic [3:0]           m_axi_awid,
    output logic [63:0]          m_axi_awaddr,
    output logic [7:0]           m_axi_awlen,
    output logic [2:0]           m_axi_awsize,        // = $clog2(DMA_DATA_W/8)
    output logic [1:0]           m_axi_awburst,       // INCR
    output logic                 m_axi_awvalid,
    input  logic                 m_axi_awready,
    output logic [DMA_DATA_W-1:0]    m_axi_wdata,
    output logic [DMA_DATA_W/8-1:0]  m_axi_wstrb,
    output logic                 m_axi_wlast,
    output logic                 m_axi_wvalid,
    input  logic                 m_axi_wready,
    input  logic [3:0]           m_axi_bid,
    input  logic [1:0]           m_axi_bresp,
    input  logic                 m_axi_bvalid,
    output logic                 m_axi_bready,

    // Sideband counters
    output logic [31:0]          cnt_input_w,
    output logic [31:0]          cnt_bytes_written,
    output logic [31:0]          cnt_halt,
    output logic [31:0]          cnt_eoe_observed
);
```

### Job-interface contract

- `job_seg{0,1}_addr` MUST be 4 KB-aligned. `job_seg{0,1}_span` MUST be a
  4 KB multiple. If violated, engine refuses with `status[ALIGN_ERR]=1`
  (no AXI traffic, immediate `job_done`).
- If `job_seg1_span == 0`, this is a single-segment job; engine sets
  `status[SEG0_ONLY]=1` on completion.
- If drain fills `seg0_span` AND `seg1_span > 0`, engine continues into
  `seg1` at `seg1_addr`, sets `status[SEG_BOUNDARY_HIT]=1` when crossed.
- Drain ends on:
  - `s_axis_opq_tlast` (OPQ EOE) → `status[EOE]=1`
  - `seg0_span+seg1_span` exhausted → `status[FULL]=1`

## 4. Submodule specs

### 4.1 `rdma_dma_packer.sv`

- Input: 32b `opq_data`, `opq_valid`, `opq_sop`, `opq_eop`.
- Output: 256b `data`, `valid`, `last_in_event`, `bytes_in_word[5:0]` (always
  32 except possibly the last beat of an event).
- Behavior: latches 8 incoming 32b words MSB-first, emits one 256b beat
  every 8 valid inputs. On `opq_eop`, immediately emit the partial 256b
  with zero-padding for empty slots and `last_in_event=1`.
- No frame-format requirements. No skipping. Pure store-and-forward.

Conservation invariant (proven by unit TB):
```
sum(opq_valid 32b words accepted) == sum(non-zero 32b slots emitted)
```

This module is the cosim-validated prototype already at
`tb_int/feb_swb_corun/sv/swb_rdma_dma_packer.sv`. The IP version moves it
to `rtl/rdma_dma_packer.sv`, adds `bytes_in_word` and `last_in_event`
sideband, otherwise identical.

### 4.2 `rdma_dma_data_fifo.sv`

- 256b data + sideband (`last_in_event`, `bytes_in_word`).
- Depth 256 (default), parameterizable.
- Inferred SCFIFO (cross-vendor portable; standalone-syn doesn't need
  Altera primitive). Phase 2 may swap for `altera_avalon_st_fifo` for
  native Qsys integration.
- Almost-full threshold 192 (3/4) drives `i_dma_halffull` back to packer.

### 4.3 `rdma_dma_writer.sv` (AXI4 master with two-segment scatter)

Programmable per-job state machine. Issues AXI4 INCR bursts of `DMA_DATA_W`
(256 b) beats. Tracks per-segment progress and switches segments when
seg0 fills.

States (6):
```
WR_IDLE
  | job_req
  | (alignment check) seg{0,1}_addr & 0xFFF != 0 OR
  |                   seg{0,1}_span & 0xFFF != 0 → WR_REPORT_ALIGN_ERR
  | else → WR_PROGRAM
  v
WR_PROGRAM       ← latch seg0/seg1, set cur_seg=0, cur_addr=seg0_addr,
                   bytes_left_seg=seg0_span
  v
WR_AW            ← drive m_axi_aw{addr,len,size,burst,valid}; awlen sized to
                    min(fifo_level, MAX_BURST_BEATS-1, beats_left_in_seg-1)
  | awvalid && awready → latch beats_in_burst
  v
WR_W             ← drive m_axi_w{data,strb,last,valid} N beats from FIFO
  | wlast && wvalid && wready
  v
WR_B             ← await m_axi_bvalid; if BRESP != OKAY → status |= AXI_ERR
  | bvalid && bready
  v
[WR_AW]   if more bytes in current segment AND no EOE
[WR_PROGRAM] if seg0 just exhausted AND seg1_span > 0  ← status[SEG_BOUNDARY_HIT]=1
[WR_REPORT_DONE] if EOE OR all segments exhausted
  v
WR_REPORT_DONE   ← raise job_done, hold (bytes_written, status, ts)
                   for one cycle until run_manager samples
  v
WR_IDLE
```

Burst sizing per AW request:
```
beats_left_in_seg = (bytes_left_in_seg + DMA_DATA_W/8 - 1) / (DMA_DATA_W/8)
beats_in_burst    = min(fifo_level, MAX_BURST_BEATS, beats_left_in_seg)
m_axi_awlen       = beats_in_burst - 1   // AXI4 convention: AWLEN = beats-1
m_axi_awsize      = $clog2(DMA_DATA_W/8)
m_axi_awburst     = 2'b01                 // INCR
```

Address arithmetic: `m_axi_awaddr = cur_seg_base + bytes_emitted_in_seg`,
which stays 4 KB-aligned since spans are 4 KB-multiple. AXI4 `INCR` bursts
**must not cross 4 KB boundaries** — by construction here, `bytes_in_burst
≤ 4 KB` since `MAX_BURST_BEATS × DMA_DATA_W/8 = 16 × 32 = 512 B`, so a
single INCR is always within one 4 KB page.

`m_axi_wstrb`: all-1s except the last beat of an EOE-triggered partial
write (which zero-strobes slots beyond `last_byte_in_word`).

Per-event timestamp tracking: writer captures the OPQ-side cycle counter
(passed via packer sideband) at the first and last EOE seen, exposes
them as `job_first_event_ts` / `job_last_event_ts` for the CQE.

## 5. Counters (sideband to run_manager)

- `cnt_input_w` — packer input 32b word count
- `cnt_bytes_written` — total bytes written to host (monotonic)
- `cnt_halt` — # of times packer dropped a beat due to fifo almost-full
- `cnt_eoe_observed` — # of EOE boundaries seen at packer

All counters cleared by the run_manager `CTRL.reset_counters` write
(propagated via a sideband `clear_counters` strobe).

## 6. Validation plan (unit-level cosim)

Lives at `tb/uvm/rdma_dma_engine_tb_top.sv`.

| # | Test                                  | Pass criterion |
|---|---------------------------------------|----------------|
| 1 | Single job, hits-only, EOE arrives    | job_done; bytes_written = N×4 + padding alignment; status[EOE]=1 |
| 2 | Single job, buf too small             | status[FULL]=1; bytes_written == buf_len_bytes |
| 3 | Two back-to-back jobs                 | both complete in order; sqe_id echo correct |
| 4 | OPQ idle while job_req asserted       | engine waits, no spurious done |
| 5 | Throttled host (avm_waitrequest)      | bursts pause, then resume; bytes lossless |
| 6 | FIFO almost-full → halt               | cnt_halt > 0; engine still conserves bytes that DID enter packer |
| 7 | Conservation over 100 jobs            | `Σ cnt_input_w * 4 == Σ cnt_bytes_written + halt_bytes` |
| 8 | reset_counters strobe                 | all counters zero after pulse |

## 7. CSR exposure

This IP has **no host-visible CSR**. Counters are sideband to the
`rdma_run_manager` which surfaces them in BAR1 at `0x3C / 0x40 / 0x44 / 0x48`.

This is intentional — a single point of CSR truth at the run manager keeps
the host interface flat (no per-IP BAR aperture juggling).

## 8. Synthesis sign-off

Standalone Quartus project at `syn/quartus/rdma_dma_engine_standalone.qsf`.
Sign-off corner: 1.1× target frequency. Top-level entity is
`rdma_dma_engine`. AVMM master tied to a dummy slave for the standalone
fitter.

Default target: 250 MHz (SWB datapath clock). Sign-off at 275 MHz.

### 8.1 Resource estimation (pre-fit)

Pre-fit budget for the DEBUG_LEVEL=0 build, derived from the submodule
list and the AXI4 / FIFO widths in §3 / §4. The acceptance band is
`[-20%, +50%]` of these estimates; an actual outside this band requires
a `[PATCH]` to this section with a written root cause, never a silent
re-fit.

Submodule contributions:

| Submodule | ALMs | M20K | DSP | Justification |
|---|---:|---:|---:|---|
| `rdma_dma_packer.sv` | ~120 | 0 | 0 | 256-b accumulator (8 × 32-b slots), 3-bit slot index, EOE/last_in_event flop, `bytes_in_word` adder. ~256 flops + a small adder cone. |
| `rdma_dma_data_fifo.sv` | ~60 | 4 | 0 | 256-b SCFIFO depth 256 + 8-bit sideband (`last_in_event`, `bytes_in_word[5:0]`, spare). 256×264 b ≈ 67 kbit ≈ 4 × M20K (each 20 kbit, 4 deep × 264 wide cascade). Read/write pointer + occupancy logic ~60 ALMs. |
| `rdma_dma_writer.sv` | ~250 | 0 | 0 | 6-state FSM, two 64-bit segment-base registers, two 64-bit `bytes_left_seg` counters, 8-bit `awlen` sizer, `min(fifo_level, MAX_BURST_BEATS, beats_left_in_seg)` comparator (small), AW/W/B in-flight counters, byte-strobe generator. Plus first/last-event TS capture (2 × 64 b = 128 flops). |
| `rdma_dma_engine.sv` | ~70 | 0 | 0 | Counter aggregation (`cnt_input_w`, `cnt_bytes_written`, `cnt_halt`, `cnt_eoe_observed` — four 32-b counters = 128 flops + adders), DEBUG_LEVEL=1 status taps, sidecar tie-off cone at DEBUG=0. |
| **Sum (pre-fit)** | **~500** | **4** | **0** | |

Add ~10 % budget for routing/control glue: **~550 ALMs**.

`ALM_estimate = 550`
`M20K_estimate = 4`
`DSP_estimate = 0`

Acceptance band:

| Metric | Lower (-20 %) | Upper (+50 %) |
|---|---:|---:|
| ALMs  | 440 | 825 |
| M20K  | 3   | 6   |
| DSP   | 0   | 0   |

Notes:
- DSP_estimate = 0: all arithmetic in this IP is small adders /
  comparators, no multiplies. Quartus must not infer DSP blocks.
- M20K_estimate = 4 assumes the inferred SCFIFO. If Phase 2 swaps to
  `altera_avalon_st_fifo`, the count may drop to 3 (the IP catalog FIFO
  packs the sideband more tightly); update this section accordingly.
- The DEBUG=1 build adds ~30 observation flops (per `doc/QUEUE_MATH.md`
  §6). DEBUG=2 build is sim-only and does not count for synthesis.

## 9. Files

```
rdma_dma_engine/
├── README.md
├── RTL_PLAN.md                      (this file)
├── doc/
│   └── (no host-visible CSR; nothing here Phase 1)
├── rtl/
│   ├── rdma_dma_engine.sv
│   ├── rdma_dma_packer.sv
│   ├── rdma_dma_data_fifo.sv
│   └── rdma_dma_writer.sv
├── tb/uvm/
│   ├── rdma_dma_engine_tb_top.sv
│   └── Makefile
├── syn/quartus/
│   └── rdma_dma_engine_standalone.qsf
├── rdma_dma_engine_hw.tcl            (Qsys IP)
├── Makefile                         (mu3e-ip-cores standard targets)
└── .git/                            (local Phase 1)
```

## 10. Implementation order

1. `rtl/rdma_dma_packer.sv` (port from prototype, add sideband bits)
2. `rtl/rdma_dma_data_fifo.sv`
3. `rtl/rdma_dma_writer.sv`
4. `rtl/rdma_dma_engine.sv` (top wiring)
5. `tb/uvm/rdma_dma_engine_tb_top.sv` + tests 1..8
6. `rdma_dma_engine_hw.tcl` for Qsys instantiability
7. `syn/quartus/` standalone signoff

## 11. Risks specific to this IP

- **AVMM burst semantics**: must not deassert `avm_write` mid-burst.
  Once `burstcount` is committed, all N beats must be driven (with
  `waitrequest` insertion). FIFO must have enough data — burst sizing
  must read from the FIFO occupancy, not optimistic.
- **Partial-line padding at EOE**: byteenable must be set per-byte
  for the last beat. If host treats unmasked bytes as garbage, that's
  fine; bytes_written reports the true useful count.
- **OPQ ready**: Phase 1 ties `opq_ready=1` always. If FIFO almost-full,
  packer drops the beat and increments `cnt_halt`. This is intentional
  for Phase 1 (no flow control upstream of OPQ); Phase 2 may add a
  proper backpressure path if hardware shows halts.

## 12. Acceptance

Tests 1-8 PASS in cosim. Standalone Quartus syn closes at 275 MHz.
Then ready for subsystem-level cosim with the other three IPs.
