`ifndef JOB_DRIVER_SV
`define JOB_DRIVER_SV

class job_driver extends uvm_driver #(job_item);
  `uvm_component_utils(job_driver)

  job_cfg cfg;
  virtual rdma_dma_engine_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(job_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("JOB_DRV", "Missing job_cfg")
    vif = cfg.vif;
    if (vif == null)
      `uvm_fatal("JOB_DRV", "job_cfg.vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    job_item item;
    forever begin
      seq_item_port.get_next_item(item);
      drive_one(item);
      seq_item_port.item_done();
    end
  endtask

  task drive_one(job_item item);
    @(negedge vif.clk);
    vif.job_seg0_addr <= item.seg0_addr;
    vif.job_seg0_span <= item.seg0_span;
    vif.job_seg1_addr <= item.seg1_addr;
    vif.job_seg1_span <= item.seg1_span;
    vif.job_rqe_id <= item.rqe_id;
    vif.job_opcode <= item.opcode;
    vif.job_req <= 1'b1;
    @(negedge vif.clk);
    vif.job_req <= 1'b0;
  endtask
endclass

`endif

