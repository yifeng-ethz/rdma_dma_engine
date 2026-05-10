`ifndef OPQ_AXIS_DRIVER_SV
`define OPQ_AXIS_DRIVER_SV

class opq_axis_driver extends uvm_driver #(opq_axis_item);
  `uvm_component_utils(opq_axis_driver)

  opq_axis_cfg cfg;
  virtual rdma_dma_engine_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(opq_axis_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("OPQ_DRV", "Missing opq_axis_cfg")
    vif = cfg.vif;
    if (vif == null)
      `uvm_fatal("OPQ_DRV", "opq_axis_cfg.vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    opq_axis_item item;
    forever begin
      seq_item_port.get_next_item(item);
      drive_one(item);
      seq_item_port.item_done();
    end
  endtask

  task drive_one(opq_axis_item item);
    @(negedge vif.clk);
    vif.s_axis_opq_tdata <= {item.datak, item.data};
    vif.s_axis_opq_tvalid <= 1'b1;
    vif.s_axis_opq_tlast <= item.eoe;
    vif.s_axis_opq_tuser <= {1'b0, item.sop};
    if (cfg.debug_level >= 2 && cfg.drive_sidecar) begin
      vif.dbg2_meta_valid <= 1'b1;
      vif.dbg2_meta_lane <= item.lane;
      vif.dbg2_meta_hit_id <= item.hit_id;
      vif.dbg2_meta_source_ts <= item.source_ts;
      vif.dbg2_meta_sequence_no <= item.sequence_no;
    end else begin
      vif.dbg2_meta_valid <= 1'b0;
      vif.dbg2_meta_lane <= '0;
      vif.dbg2_meta_hit_id <= '0;
      vif.dbg2_meta_source_ts <= '0;
      vif.dbg2_meta_sequence_no <= '0;
    end
    do begin
      @(posedge vif.clk);
    end while (vif.s_axis_opq_tready !== 1'b1);
    @(negedge vif.clk);
    vif.s_axis_opq_tvalid <= 1'b0;
    vif.s_axis_opq_tlast <= 1'b0;
    vif.s_axis_opq_tuser <= '0;
    vif.dbg2_meta_valid <= 1'b0;
    vif.dbg2_meta_lane <= '0;
    vif.dbg2_meta_hit_id <= '0;
    vif.dbg2_meta_source_ts <= '0;
    vif.dbg2_meta_sequence_no <= '0;
    repeat (item.idle_after) @(posedge vif.clk);
  endtask
endclass

`endif

