# rdma_dma_engine - OPQ to host DRAM DMA writer

OPQ-egress to host DRAM DMA writer for the Mu3e SWB. Packs 32-bit hits into 256-bit AXI4 bursts and drains under RQE-driven host control.

## 2. Architectural map

```
Data flow is left -> right. Control and status are vertical.

                                  Host/JTAG access
                                       |
                                       v
                         rdma_run_manager BAR1 CSR
                         (outside this IP; CSR owner)
                                       |
                 job_req, clear_counters, counter/status sidebands
                                       |
        +------------------------------+------------------------------+
        |                              |                              |
        v                              v                              v
+---------------+     +----------------------+     +----------------------+
| OPQ AXIS sink | --> | rdma_dma_packer      | --> | rdma_dma_data_fifo   |
| 36b tdata     |     | 32b words -> 256b    |     | 256b data + EOE sb   |
+---------------+     +----------------------+     +----------+-----------+
                                                                  |
                                                                  v
                                                       +----------+----------+
                                                       | rdma_dma_writer    |
                                                       | AXI4 AW/W/B master |
                                                       +----------+----------+
                                                                  |
                                                                  v
                                                       Host DRAM AXI4 writes
```

| Boundary | Type | Direction | Owner / consumer |
|---|---|---|---|
| `s_axis_opq_*` | AXI4-Stream sink | OPQ -> `rdma_dma_engine` | Consumed by `rdma_dma_packer`. |
| `job_*`, `clear_counters`, `cnt_*` | Control/status conduit | `rdma_run_manager` <-> `rdma_dma_engine` | Programs a drain job and reports CQE-feeding results. |
| `m_axi_*` | AXI4 full write master | `rdma_dma_engine` -> host-memory fabric | Driven by `rdma_dma_writer`; AW/W/B only. |
| AXI4-Lite CSR slave | none | n/a | Intentionally absent. `rdma_run_manager` owns BAR1 CSR and JTAG-visible aliases. |
| AVST | none | n/a | This IP does not expose Avalon-ST; the OPQ boundary is AXI4-Stream. |

## 3. Contract - databus format

### 3.1 OPQ AXI4-Stream sink

| Signal | Width | Role | Notes |
|---|---:|---|---|
| `s_axis_opq_tdata[31:0]` | 32 | sink payload | OPQ data word, packed LSB-first into the 256-bit DMA word. |
| `s_axis_opq_tdata[35:32]` | 4 | sink sideband | OPQ K-symbol bits. The packer receives these as `opq_datak` but does not interpret or filter them. |
| `s_axis_opq_tvalid` | 1 | sink valid | Accepted when `writer_accepting_input` is high and FIFO is below almost-full. |
| `s_axis_opq_tready` | 1 | sink ready | Driven high in Phase 1. If the internal FIFO is almost full, a valid beat is dropped and `cnt_halt` increments. |
| `s_axis_opq_tlast` | 1 | sink sideband | OPQ end-of-event. Flushes a partial 256-bit word and sets EOE status/reporting. |
| `s_axis_opq_tuser[0]` | 1 | sink sideband | SOP marker passed into the packer boundary; no frame-format check is done here. |
| `s_axis_opq_tuser[1]` | 1 | sink sideband | Reserved by the subsystem contract; ignored by this IP. |

There is no `tkeep`, `tstrb`, `tid`, `tdest`, or AXIS error channel on this boundary. OPQ `terror` is not an input to this IP.

### 3.2 Packed internal data path

| Field | Width | Producer | Consumer | Notes |
|---|---:|---|---|---|
| `packed_data` / `fifo_data` | 256 | packer | FIFO / writer | Eight 32-bit OPQ words per beat. Slot N maps to bits `[N*32+31:N*32]`. |
| `last_in_event` | 1 | packer | writer | Marks the packed beat that contains the OPQ EOE. |
| `bytes_in_word` | 6 | packer | writer | `32` for a full 256-bit beat; `4, 8, ..., 28` for an EOE partial beat. |
| `event_ts` | 64 | packer | writer | Packer cycle counter captured at EOE. |
| `dbg2_meta` | `8*DBG2_META_W` | packer | FIFO / writer | Simulation-only per-slot lineage when `DEBUG_LEVEL >= 2`; tied to zero otherwise. |
| `dbg2_valid_mask` | 8 | packer | FIFO / writer | One bit per 32-bit slot for DEBUG2 lineage. |

### 3.3 AXI4 full write master

Standard AXI4 channel fields are not restated. This master uses only AW, W, and B; AR/R are not present.

| Constraint | Value |
|---|---|
| Address width | 64 bits. |
| Data width | `DMA_DATA_W`, default 256 bits. |
| Write strobe width | `DMA_DATA_W/8`, default 32 bits. |
| AXI ID width | 4 bits; `m_axi_awid` is fixed to `4'h0`. |
| Max outstanding writes | 1 AW burst awaiting 1 B response. The writer waits in `WR_WAITING_B` before issuing the next AW. |
| Burst type | `m_axi_awburst = 2'b01` (INCR). |
| Burst length | `m_axi_awlen = beats_in_burst - 1`; capped at `MAX_BURST_BEATS - 1`, default 15. |
| Beat size | `m_axi_awsize = $clog2(DMA_DATA_W/8)`, default `3'b101` for 32-byte beats. |
| Address alignment | Job segment addresses must be 4 KB-aligned. AW addresses are 32-byte beat-aligned for the default width. |
| 4 KB boundary | A burst is capped by page offset and never crosses a 4 KB boundary. |
| Byte strobes | All ones for full beats. On an EOE partial beat, only the low `bytes_in_word` bytes are strobed. |
| Ordering | Single-ID, in-order write stream. W beats are delivered only for an AW burst that has handshaked. |
| BRESP handling | `bresp != OKAY` sets `job_status[6]` (`AXI_ERR`). |

### 3.4 Job and result conduit

| Signal | Width | Role | Notes |
|---|---:|---|---|
| `job_req` | 1 | sink control | Starts one drain job. |
| `job_seg0_addr` | 64 | sink control | Segment 0 host address; must be 4 KB-aligned. |
| `job_seg0_span` | 64 | sink control | Segment 0 span in bytes; must be nonzero and a 4 KB multiple. |
| `job_seg1_addr` | 64 | sink control | Segment 1 host address; must be 4 KB-aligned if `job_seg1_span != 0`. |
| `job_seg1_span` | 64 | sink control | Segment 1 span in bytes; zero disables the second segment. |
| `job_rqe_id` | 16 | sink control | RQE identifier echoed on completion. |
| `job_opcode` | 16 | sink control | Latched for job provenance; drain behavior is owned by the run-manager contract. |
| `job_done` | 1 | source status | Pulses when the writer reports completion or an alignment refusal. |
| `job_bytes_written_total` | 64 | source status | Useful bytes written across both segments. |
| `job_seg0_bytes_written` | 32 | source status | Useful bytes written into segment 0. |
| `job_seg1_bytes_written` | 32 | source status | Useful bytes written into segment 1. |
| `job_status` | 16 | source status | Status bit map below. |
| `job_rqe_id_echo` | 16 | source status | Echo of `job_rqe_id`. |
| `job_event_count` | 32 | source status | Number of OPQ EOE boundaries observed during this drain. |
| `job_first_event_ts` | 64 | source status | Packer timestamp at first EOE. |
| `job_last_event_ts` | 64 | source status | Packer timestamp at last EOE. |

| Bit | Name | Meaning |
|---:|---|---|
| 0 | `EOE` | OPQ asserted `tlast` during the drain. |
| 1 | `FULL` | The programmed segment capacity was exhausted. |
| 2 | `HALT` | Internal FIFO almost-full caused dropped OPQ data. |
| 3 | `SEG_BOUNDARY_HIT` | Drain crossed from segment 0 into segment 1. |
| 4 | `SEG0_ONLY` | Segment 1 was disabled for this job. |
| 5 | `ALIGN_ERR` | Job was refused because an address/span violated the 4 KB contract. |
| 6 | `AXI_ERR` | AXI4 B response was not OKAY. |
| 15:7 | reserved | Reserved; reset to zero. |

### 3.5 Counter and debug sidebands

| Signal | Width | Role | Notes |
|---|---:|---|---|
| `clear_counters` | 1 | sink control | Clears the four visible counters on the next clock. |
| `cnt_input_w` | 32 | source status | Saturating count of OPQ 32-bit words presented while enabled. |
| `cnt_bytes_written` | 32 | source status | Saturating count of useful bytes accepted on AXI4 W beats. |
| `cnt_halt` | 32 | source status | Saturating count of packer drop events caused by halt/almost-full. |
| `cnt_eoe_observed` | 32 | source status | Saturating count of OPQ EOE observations. |
| `dbg1_*` | mixed | source observation | FIFO level, packer slot, AW/W/B state, and writer FSM taps when `DEBUG_LEVEL >= 1`; zero otherwise. |
| `dbg2_*` | mixed | sim-only sidecar | Per-hit lineage sideband when `DEBUG_LEVEL >= 2`; zero/pruned for synthesizable builds. |

Supercore-only contracts are not external interfaces of this IP. The readyless 9-bit one-hot run-control AVST word is handled by `run-control_mgmt` and the FEB/SWB integration, while 64-byte RQE/CQE payload layouts are owned by `rdma_subsystem/ARCHITECTURE_PLAN.md` and decoded/assembled by `rdma_run_manager`.

## 4. How to start

### 4.1 Clone + initialize

```sh
git clone https://github.com/yifeng-ethz/rdma_dma_engine.git
cd rdma_dma_engine
# or as a submodule of mu3e-ip-cores:
git submodule update --init --recursive rdma_dma_engine
```

### 4.2 Standalone simulation

The canonical UVM entry point is `tb/uvm/Makefile`. The smoke target builds both DEBUG_LEVEL=1 and DEBUG_LEVEL=2, runs B001/B002 in both builds, and then cross-validates the DEBUG scorecards.

```sh
cd tb/uvm
make smoke
```

For a single directed run:

```sh
cd tb/uvm
make DEBUG_LEVEL=1 TEST=test_b001_reset_idle CASE_ID=B001 run_one
```

The underlying simulator is QuestaOne from `/data1/questaone_sim-2026.1_1/questasim`; the Makefile expands `sim_one` to a noninteractive `vsim -c` run of `rdma_dma_engine_tb_top` with `+UVM_TESTNAME`, `+CASE_ID`, `+DEBUG_LEVEL`, scorecard, UCDB, and log paths.

### 4.3 Standalone synthesis

The standalone Quartus revision is `rdma_dma_engine_standalone` in `syn/quartus/`.

```sh
cd syn/quartus
quartus_sh --flow compile rdma_dma_engine_standalone -c rdma_dma_engine_standalone
```

The checked report in `syn/SYN_REPORT.md` records an Arria 10 standalone 275 MHz compile with positive setup/hold slack and resources inside the RTL-plan acceptance band.

## 5. CSR snapshot

This IP intentionally has no host-visible CSR aperture, no local AXI4-Lite slave, no local Avalon-MM slave, no SVD file, and no JTAG-master alias. The complete local CSR map is therefore empty; `rdma_run_manager` owns BAR1 CSR exposure and mirrors this IP's counters at the subsystem level.

| Offset | Name | Access | Width | Default | Description |
|-------:|------|:------:|-------|:--------:|-------------|
| n/a | no local CSR registers | n/a | n/a | n/a | No software-readable or software-writable registers are implemented in `rdma_dma_engine`. |

Counter reset/default values visible at the IP boundary:

| Signal | Width | Reset value | Description |
|---|---:|:---:|---|
| `cnt_input_w` | 32 | `0x00000000` | Cleared by reset or `clear_counters`. |
| `cnt_bytes_written` | 32 | `0x00000000` | Cleared by reset or `clear_counters`. |
| `cnt_halt` | 32 | `0x00000000` | Cleared by reset or `clear_counters`. |
| `cnt_eoe_observed` | 32 | `0x00000000` | Cleared by reset or `clear_counters`. |

There are no RW registers with non-trivial bitfields in this IP. The job/status bitfield is a control conduit, documented in section 3.4, and is converted into software-visible CQE/CSR state by the run manager.

## 6. Versions + phase status

No `rdma_dma_engine_hw.tcl`, `rdma_dma_engine.svd`, or IP-local `PHASE_STATUS.md` is present in this repository. The nearest supercore snapshot is `../rdma_subsystem/PHASE_STATUS.md` dated 2026-05-10; it is older than this repo's 2026-05-11 DV dashboard, so the table below uses the current in-repo evidence for this IP.

| Item | Value | Source |
|---|---|---|
| Top RTL header version | `26.1.0` | `rtl/rdma_dma_engine.sv` |
| Newest maintained RTL header version | `26.1.1` | `rtl/rdma_dma_writer.sv` |
| Package version | n/a | No `_hw.tcl` or SVD version tag is present. |
| Phase A | DONE all artifact buckets | `../rdma_subsystem/PHASE_STATUS.md` snapshot plus current repo file set. |
| Phase B | DONE: 512 promoted cases, 512 evidenced, 0 failed, 100.0% promoted functional coverage | `tb/DV_REPORT.md` dated 2026-05-11. |
| Phase C | DONE: queue/throughput/conservation math documented | `doc/QUEUE_MATH.md`. |
| Phase D | DONE: standalone synthesis, static screen, timing, and resources pass | `syn/SYN_REPORT.md`. |
| Per-case unique-coverage audit | DONE in current local evidence: BASIC/EDGE/PROF/ERROR each 128/128 promoted and evidenced; merged totals meet targets | `tb/DV_REPORT.md` and `tb/REPORT/cases/`. |

Important evidence commands:

```sh
make -C tb/uvm smoke
make -C tb/uvm regress
(cd syn/quartus && quartus_sh --flow compile rdma_dma_engine_standalone -c rdma_dma_engine_standalone)
```

## 7. Cross-references

| Reference | Path |
|---|---|
| Parent supercore README | `../rdma_subsystem/README.md` |
| Parent architecture, RQE/CQE layout, BAR1 CSR ownership | `../rdma_subsystem/ARCHITECTURE_PLAN.md` |
| Supercore phase dashboard | `../rdma_subsystem/PHASE_STATUS.md` |
| RQE descriptor puller sibling | `../rdma_rq_fetcher/` |
| Completion writer sibling | `../rdma_cq_pusher/` |
| Coordinator and BAR1 CSR sibling | `../rdma_run_manager/` |
| FEB SciFi documentation style reference | `/home/yifeng/packages/online_dpv2/online/fe_board/fe_scifi/README.md` |
| SWB RDMA integration notes | `/home/yifeng/packages/online_sc/online/switching_pc/a10_board/doc/RDMA_SUBSYSTEM_INTEGRATION_20260511.md` |
| mu3e-ip-cores parent IP table | `../README.md` |
| Historical SWB datapath memory | `/home/yifeng/.claude/projects/-home-yifeng-packages-mu3e-ip-dev/memory/feedback_swb_datapath_legacy_broken.md` |

The repository sources above are authoritative for RTL, DV, and synthesis contracts. The Claude memory file is historical context for why the SWB post-OPQ path is being replaced; it is not an interface source of truth.
