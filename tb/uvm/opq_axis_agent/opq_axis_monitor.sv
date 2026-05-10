`ifndef OPQ_AXIS_MONITOR_SV
`define OPQ_AXIS_MONITOR_SV

class opq_axis_monitor extends uvm_monitor;
  `uvm_component_utils(opq_axis_monitor)

  opq_axis_cfg cfg;
  virtual rdma_dma_engine_if vif;
  uvm_analysis_port #(opq_axis_item) ap;
  longint unsigned cycle_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cycle_count = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(opq_axis_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("OPQ_MON", "Missing opq_axis_cfg")
    vif = cfg.vif;
    if (vif == null)
      `uvm_fatal("OPQ_MON", "opq_axis_cfg.vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    opq_axis_item item;
    forever begin
      @(posedge vif.clk);
      cycle_count++;
      if (vif.reset_n !== 1'b1)
        continue;
      if (vif.s_axis_opq_tvalid && vif.s_axis_opq_tready) begin
        item = opq_axis_item::type_id::create("opq_axis_item");
        item.datak = vif.s_axis_opq_tdata[35:32];
        item.data = vif.s_axis_opq_tdata[31:0];
        item.sop = vif.s_axis_opq_tuser[0];
        item.eoe = vif.s_axis_opq_tlast;
        item.lane = vif.dbg2_meta_lane;
        item.hit_id = vif.dbg2_meta_hit_id;
        item.source_ts = vif.dbg2_meta_source_ts;
        item.sequence_no = vif.dbg2_meta_sequence_no;
        item.cycle = cycle_count;
        ap.write(item);
      end
    end
  endtask
endclass

`endif

