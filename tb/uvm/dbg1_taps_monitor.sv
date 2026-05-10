`ifndef RDMA_DMA_DBG1_TAPS_MONITOR_SV
`define RDMA_DMA_DBG1_TAPS_MONITOR_SV

class dbg1_taps_monitor extends uvm_monitor;
  `uvm_component_utils(dbg1_taps_monitor)

  virtual rdma_dma_engine_if vif;
  uvm_analysis_port #(dbg1_taps_item) ap;
  longint unsigned cycle_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cycle_count = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual rdma_dma_engine_if)::get(this, "", "vif", vif))
      `uvm_fatal("DBG1_MON", "Missing rdma_dma_engine_if")
  endfunction

  task run_phase(uvm_phase phase);
    dbg1_taps_item item;
    forever begin
      @(posedge vif.clk);
      cycle_count++;
      if (vif.reset_n !== 1'b1)
        continue;
      if ($isunknown({
            vif.dbg1_fifo_level,
            vif.dbg1_fifo_almost_full,
            vif.dbg1_aw_inflight,
            vif.dbg1_w_beats_remaining,
            vif.dbg1_b_outstanding,
            vif.dbg1_packer_slot_idx,
            vif.dbg1_packer_pending_eoe,
            vif.dbg1_writer_state,
            vif.dbg1_halt_pulse
          })) begin
        `uvm_error("DBG1_MON", "DEBUG=1 tap vector contains X/Z")
      end
      if (vif.m_axi_awvalid || vif.m_axi_wvalid || vif.m_axi_bvalid || vif.job_done) begin
        item = dbg1_taps_item::type_id::create("dbg1_taps_item");
        item.fifo_level = vif.dbg1_fifo_level;
        item.fifo_almost_full = vif.dbg1_fifo_almost_full;
        item.aw_inflight = vif.dbg1_aw_inflight;
        item.w_beats_remaining = vif.dbg1_w_beats_remaining;
        item.b_outstanding = vif.dbg1_b_outstanding;
        item.packer_slot_idx = vif.dbg1_packer_slot_idx;
        item.packer_pending_eoe = vif.dbg1_packer_pending_eoe;
        item.writer_state = vif.dbg1_writer_state;
        item.halt_pulse = vif.dbg1_halt_pulse;
        item.cycle = cycle_count;
        ap.write(item);
      end
    end
  endtask
endclass

`endif

