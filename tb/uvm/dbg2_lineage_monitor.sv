`ifndef RDMA_DMA_DBG2_LINEAGE_MONITOR_SV
`define RDMA_DMA_DBG2_LINEAGE_MONITOR_SV

class dbg2_lineage_monitor extends uvm_monitor;
  `uvm_component_utils(dbg2_lineage_monitor)

  virtual rdma_dma_engine_if vif;
  uvm_analysis_port #(dbg2_writer_item) ap;
  longint unsigned cycle_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cycle_count = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual rdma_dma_engine_if)::get(this, "", "vif", vif))
      `uvm_fatal("DBG2_MON", "Missing rdma_dma_engine_if")
  endfunction

  task run_phase(uvm_phase phase);
    dbg2_writer_item item;
    forever begin
      @(posedge vif.clk);
      cycle_count++;
      if (vif.reset_n !== 1'b1)
        continue;
      if (vif.dbg2_writer_meta_valid) begin
        for (int unsigned slot = 0; slot < RDMA_DMA_OPQ_PER_BEAT; slot++) begin
          if (vif.dbg2_writer_meta_valid_mask[slot]) begin
            item = dbg2_writer_item::type_id::create("dbg2_writer_item");
            item.slot = slot;
            item.lane = vif.dbg2_writer_meta_lane[slot*4 +: 4];
            item.hit_id = vif.dbg2_writer_meta_hit_id[slot*32 +: 32];
            item.source_ts = vif.dbg2_writer_meta_source_ts[slot*64 +: 64];
            item.sequence_no = vif.dbg2_writer_meta_sequence_no[slot*32 +: 32];
            item.cycle = cycle_count;
            ap.write(item);
          end
        end
      end
    end
  endtask
endclass

`endif

