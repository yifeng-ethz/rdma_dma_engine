`ifndef RDMA_DMA_ENGINE_PKG_SV
`define RDMA_DMA_ENGINE_PKG_SV

package rdma_dma_engine_pkg;
  import uvm_pkg::*;
  import opq_axis_pkg::*;
  import job_pkg::*;
  import axi4_write_pkg::*;
  `include "uvm_macros.svh"

  localparam int unsigned RDMA_DMA_DATA_W = 256;
  localparam int unsigned RDMA_DMA_BYTES = RDMA_DMA_DATA_W / 8;
  localparam int unsigned RDMA_DMA_OPQ_PER_BEAT = RDMA_DMA_DATA_W / 32;

  localparam int unsigned RDMA_DMA_ST_EOE = 0;
  localparam int unsigned RDMA_DMA_ST_FULL = 1;
  localparam int unsigned RDMA_DMA_ST_HALT = 2;
  localparam int unsigned RDMA_DMA_ST_SEG_BOUNDARY_HIT = 3;
  localparam int unsigned RDMA_DMA_ST_SEG0_ONLY = 4;
  localparam int unsigned RDMA_DMA_ST_ALIGN_ERR = 5;

  class rdma_dma_engine_env extends uvm_env;
    `uvm_component_utils(rdma_dma_engine_env)

    virtual rdma_dma_engine_if vif;
    int unsigned debug_level;
    opq_axis_cfg opq_cfg;
    job_cfg job_cfg_h;
    axi4_write_cfg axi_cfg;
    opq_axis_agent opq_agent;
    job_agent job_agent_h;
    axi4_write_agent axi_agent;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      debug_level = 1;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rdma_dma_engine_if)::get(this, "", "vif", vif))
        `uvm_fatal("ENV", "Missing rdma_dma_engine_if")
      void'($value$plusargs("DEBUG_LEVEL=%0d", debug_level));
`ifdef RDMA_DMA_DEBUG2
      debug_level = 2;
`endif

      opq_cfg = opq_axis_cfg::type_id::create("opq_cfg");
      job_cfg_h = job_cfg::type_id::create("job_cfg_h");
      axi_cfg = axi4_write_cfg::type_id::create("axi_cfg");
      opq_cfg.vif = vif;
      opq_cfg.debug_level = debug_level;
      opq_cfg.drive_sidecar = (debug_level >= 2);
      job_cfg_h.vif = vif;
      axi_cfg.vif = vif;

      uvm_config_db#(opq_axis_cfg)::set(this, "opq_agent*", "cfg", opq_cfg);
      uvm_config_db#(job_cfg)::set(this, "job_agent*", "cfg", job_cfg_h);
      uvm_config_db#(axi4_write_cfg)::set(this, "axi_agent*", "cfg", axi_cfg);

      opq_agent = opq_axis_agent::type_id::create("opq_agent", this);
      job_agent_h = job_agent::type_id::create("job_agent_h", this);
      axi_agent = axi4_write_agent::type_id::create("axi_agent", this);
    endfunction
  endclass

  class rdma_dma_engine_base_test extends uvm_test;
    `uvm_component_utils(rdma_dma_engine_base_test)

    rdma_dma_engine_env env;
    virtual rdma_dma_engine_if vif;
    string case_id;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      case_id = "BASE";
    endfunction

    function string default_case_id();
      return "BASE";
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = rdma_dma_engine_env::type_id::create("env", this);
      if (!uvm_config_db#(virtual rdma_dma_engine_if)::get(this, "", "vif", vif))
        `uvm_fatal("BASE", "Missing rdma_dma_engine_if")
      if (!$value$plusargs("CASE_ID=%s", case_id))
        case_id = default_case_id();
    endfunction

    task apply_reset();
      vif.drive_idle();
      vif.reset_n <= 1'b0;
      repeat (16) @(posedge vif.clk);
      vif.reset_n <= 1'b1;
      repeat (8) @(posedge vif.clk);
    endtask

    task wait_cycles(input int unsigned cycles);
      repeat (cycles) @(posedge vif.clk);
    endtask

    virtual task run_case();
      wait_cycles(8);
    endtask

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      apply_reset();
      `uvm_info("BASE", $sformatf("Starting case %s", case_id), UVM_LOW)
      run_case();
      wait_cycles(8);
      phase.drop_objection(this);
    endtask
  endclass
endpackage

`endif
