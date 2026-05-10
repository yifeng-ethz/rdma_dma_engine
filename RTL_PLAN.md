# `opq_dma_engine` — RTL Plan

Status: **PLAN — pending review.** Part of the
[`opq_rdma_subsystem`](../opq_rdma_subsystem/ARCHITECTURE_PLAN.md). Read the
parent architecture plan first for the SQ/CQ contract context.

## 1. Role within the subsystem

Pure data mover. Knows nothing about SQ rings, CQ rings, or doorbells.
Programmed by the `opq_run_manager` with `(buf_addr, buf_len_bytes, sqe_id)`
and drains an OPQ-side data stream into that named host-DRAM region using
an Avalon-MM master. Reports back `(bytes_written, status, sqe_id)` on
completion.

Owns the high-bandwidth path. Lives between OPQ egress and the host.

## 2. Module hierarchy

```
opq_dma_engine.sv          (top — wires the three sub-modules)
├── opq_dma_packer.sv      (32b → 256b accumulator with EOE sideband)
├── opq_dma_data_fifo.sv   (256b SCFIFO + sideband bits, ~256 entries)
└── opq_dma_writer.sv      (Avalon-MM burst master, programmable per-job)
```

## 3. Top-level interface

```systemverilog
module opq_dma_engine (
    input  logic         clk,
    input  logic         reset_n,

    // OPQ egress (Avalon-ST sink, 36b)
    input  logic [35:0]  opq_data,        // {datak[3:0], data[31:0]}
    input  logic         opq_valid,
    input  logic         opq_sop,
    input  logic         opq_eop,
    output logic         opq_ready,        // tied 1 in Phase 1

    // Job interface from opq_run_manager
    input  logic         job_req,
    input  logic [63:0]  job_buf_addr,
    input  logic [31:0]  job_buf_len_bytes,
    input  logic [15:0]  job_sqe_id,
    output logic         job_done,
    output logic [31:0]  job_bytes_written,
    output logic [15:0]  job_status,        // bit 0=EOE, 1=FULL, 2=HALT
    output logic [15:0]  job_sqe_id_echo,

    // Avalon-MM master to host DRAM (write-only path used here)
    output logic [63:0]  avm_address,
    output logic         avm_write,
    output logic [255:0] avm_writedata,
    output logic [31:0]  avm_byteenable,
    output logic [3:0]   avm_burstcount,
    input  logic         avm_waitrequest,

    // Sideband counters (sampled by run_manager into CSR)
    output logic [31:0]  cnt_input_w,
    output logic [31:0]  cnt_bytes_written,
    output logic [31:0]  cnt_halt,
    output logic [31:0]  cnt_eoe_observed
);
```

## 4. Submodule specs

### 4.1 `opq_dma_packer.sv`

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
`tb_int/feb_swb_corun/sv/swb_opq_dma_packer.sv`. The IP version moves it
to `rtl/opq_dma_packer.sv`, adds `bytes_in_word` and `last_in_event`
sideband, otherwise identical.

### 4.2 `opq_dma_data_fifo.sv`

- 256b data + sideband (`last_in_event`, `bytes_in_word`).
- Depth 256 (default), parameterizable.
- Inferred SCFIFO (cross-vendor portable; standalone-syn doesn't need
  Altera primitive). Phase 2 may swap for `altera_avalon_st_fifo` for
  native Qsys integration.
- Almost-full threshold 192 (3/4) drives `i_dma_halffull` back to packer.

### 4.3 `opq_dma_writer.sv`

State machine (4 states):

```
WR_IDLE
  | job_req
  v
WR_BURST                    ← burst beats out: avm_write + burstcount=N
  | last beat done OR
  | bytes_remaining < 32  → WR_FINALIZE_PARTIAL
  | last_in_event from FIFO → WR_REPORT_DONE (status[EOE]=1)
  v
WR_FINALIZE_PARTIAL
  | one final 256b padded beat, status[FULL]=1
  v
WR_REPORT_DONE             ← raises job_done, holds (bytes_written, status)
  | run_manager observes job_done
  v
WR_IDLE
```

Burst sizing: `burstcount = min(fifo_level, MAX_BURST=16, words_remaining)`.
- `MAX_BURST=16` × 32 B = 512 B (matches Altera AVMM-to-PCIe preferred MPS).
- `words_remaining = (buf_len_bytes - bytes_emitted) / 32`.

Address arithmetic: `avm_address = job_buf_addr + bytes_emitted`. 32-byte
aligned; the writer asserts that `job_buf_addr[4:0] == 0` at job_req.

`avm_byteenable`: all-1s except the last beat of a partial event (which
zero-enables slots beyond `last_byte_in_word`).

## 5. Counters (sideband to run_manager)

- `cnt_input_w` — packer input 32b word count
- `cnt_bytes_written` — total bytes written to host (monotonic)
- `cnt_halt` — # of times packer dropped a beat due to fifo almost-full
- `cnt_eoe_observed` — # of EOE boundaries seen at packer

All counters cleared by the run_manager `CTRL.reset_counters` write
(propagated via a sideband `clear_counters` strobe).

## 6. Validation plan (unit-level cosim)

Lives at `tb/uvm/opq_dma_engine_tb_top.sv`.

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
`opq_run_manager` which surfaces them in BAR1 at `0x3C / 0x40 / 0x44 / 0x48`.

This is intentional — a single point of CSR truth at the run manager keeps
the host interface flat (no per-IP BAR aperture juggling).

## 8. Synthesis sign-off

Standalone Quartus project at `syn/quartus/opq_dma_engine_standalone.qsf`.
Sign-off corner: 1.1× target frequency. Top-level entity is
`opq_dma_engine`. AVMM master tied to a dummy slave for the standalone
fitter.

Default target: 250 MHz (SWB datapath clock). Sign-off at 275 MHz.

## 9. Files

```
opq_dma_engine/
├── README.md
├── RTL_PLAN.md                      (this file)
├── doc/
│   └── (no host-visible CSR; nothing here Phase 1)
├── rtl/
│   ├── opq_dma_engine.sv
│   ├── opq_dma_packer.sv
│   ├── opq_dma_data_fifo.sv
│   └── opq_dma_writer.sv
├── tb/uvm/
│   ├── opq_dma_engine_tb_top.sv
│   └── Makefile
├── syn/quartus/
│   └── opq_dma_engine_standalone.qsf
├── opq_dma_engine_hw.tcl            (Qsys IP)
├── Makefile                         (mu3e-ip-cores standard targets)
└── .git/                            (local Phase 1)
```

## 10. Implementation order

1. `rtl/opq_dma_packer.sv` (port from prototype, add sideband bits)
2. `rtl/opq_dma_data_fifo.sv`
3. `rtl/opq_dma_writer.sv`
4. `rtl/opq_dma_engine.sv` (top wiring)
5. `tb/uvm/opq_dma_engine_tb_top.sv` + tests 1..8
6. `opq_dma_engine_hw.tcl` for Qsys instantiability
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
