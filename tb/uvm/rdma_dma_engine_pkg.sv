`ifndef RDMA_DMA_ENGINE_PKG_SV
`define RDMA_DMA_ENGINE_PKG_SV

package rdma_dma_engine_pkg;
  import uvm_pkg::*;
  import opq_axis_pkg::*;
  import job_pkg::*;
  import axi4_write_pkg::*;
  `include "uvm_macros.svh"
  `uvm_analysis_imp_decl(_opq)
  `uvm_analysis_imp_decl(_axi)
  `uvm_analysis_imp_decl(_job)
  `uvm_analysis_imp_decl(_dbg1)
  `uvm_analysis_imp_decl(_dbg2)

  localparam int unsigned RDMA_DMA_DATA_W = 256;
  localparam int unsigned RDMA_DMA_BYTES = RDMA_DMA_DATA_W / 8;
  localparam int unsigned RDMA_DMA_OPQ_PER_BEAT = RDMA_DMA_DATA_W / 32;

  localparam int unsigned RDMA_DMA_ST_EOE = 0;
  localparam int unsigned RDMA_DMA_ST_FULL = 1;
  localparam int unsigned RDMA_DMA_ST_HALT = 2;
  localparam int unsigned RDMA_DMA_ST_SEG_BOUNDARY_HIT = 3;
  localparam int unsigned RDMA_DMA_ST_SEG0_ONLY = 4;
  localparam int unsigned RDMA_DMA_ST_ALIGN_ERR = 5;

  class dbg1_taps_item extends uvm_sequence_item;
    `uvm_object_utils(dbg1_taps_item)

    bit [8:0] fifo_level;
    bit fifo_almost_full;
    bit [3:0] aw_inflight;
    bit [7:0] w_beats_remaining;
    bit [3:0] b_outstanding;
    bit [3:0] packer_slot_idx;
    bit packer_pending_eoe;
    bit [3:0] writer_state;
    bit halt_pulse;
    longint unsigned cycle;

    function new(string name = "dbg1_taps_item");
      super.new(name);
      fifo_level = '0;
      fifo_almost_full = 1'b0;
      aw_inflight = '0;
      w_beats_remaining = '0;
      b_outstanding = '0;
      packer_slot_idx = '0;
      packer_pending_eoe = 1'b0;
      writer_state = '0;
      halt_pulse = 1'b0;
      cycle = 0;
    endfunction
  endclass

  class dbg2_writer_item extends uvm_sequence_item;
    `uvm_object_utils(dbg2_writer_item)

    int unsigned slot;
    bit [3:0] lane;
    bit [31:0] hit_id;
    bit [63:0] source_ts;
    bit [31:0] sequence_no;
    longint unsigned cycle;

    function new(string name = "dbg2_writer_item");
      super.new(name);
      slot = 0;
      lane = '0;
      hit_id = '0;
      source_ts = '0;
      sequence_no = '0;
      cycle = 0;
    endfunction
  endclass

  `include "dbg1_taps_monitor.sv"
  `include "dbg2_lineage_monitor.sv"
  `include "scoreboard.sv"
  `include "coverage.sv"
  `include "sequences/rdma_dma_engine_sequences.sv"

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
    dbg1_taps_monitor dbg1_mon;
    dbg2_lineage_monitor dbg2_mon;
    rdma_dma_engine_scoreboard scb;
    rdma_dma_engine_coverage cov;

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
      dbg1_mon = dbg1_taps_monitor::type_id::create("dbg1_mon", this);
      if (debug_level >= 2)
        dbg2_mon = dbg2_lineage_monitor::type_id::create("dbg2_mon", this);
      scb = rdma_dma_engine_scoreboard::type_id::create("scb", this);
      cov = rdma_dma_engine_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      opq_agent.monitor.ap.connect(scb.opq_imp);
      axi_agent.monitor.ap.connect(scb.axi_imp);
      job_agent_h.monitor.ap.connect(scb.job_imp);
      job_agent_h.monitor.ap.connect(cov.analysis_export);
      dbg1_mon.ap.connect(scb.dbg1_imp);
      if (debug_level >= 2 && dbg2_mon != null)
        dbg2_mon.ap.connect(scb.dbg2_imp);
    endfunction
  endclass

  class rdma_dma_engine_base_test extends uvm_test;
    `uvm_component_utils(rdma_dma_engine_base_test)

    rdma_dma_engine_env env;
    virtual rdma_dma_engine_if vif;
    string case_id;
    string scorecard_path;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      case_id = "BASE";
      scorecard_path = "";
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
      void'($value$plusargs("SCORECARD=%s", scorecard_path));
    endfunction

    task apply_reset();
      vif.drive_idle();
      vif.reset_n <= 1'b0;
      repeat (16) @(posedge vif.clk);
      vif.reset_n <= 1'b1;
      repeat (8) @(posedge vif.clk);
      env.scb.reset_model();
      env.scb.configure_case(case_id, scorecard_path, env.debug_level);
    endtask

    task wait_cycles(input int unsigned cycles);
      repeat (cycles) @(posedge vif.clk);
    endtask

    task wait_for_done(input int unsigned timeout_cycles = 1000);
      for (int unsigned cycle = 0; cycle < timeout_cycles; cycle++) begin
        @(posedge vif.clk);
        if (vif.job_done)
          return;
      end
      `uvm_fatal("TIMEOUT", $sformatf("%s timed out waiting for job_done", case_id))
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

  `include "tests/test_b001_reset_idle.sv"
  `include "tests/test_b002_single_job_hit_only_eoe.sv"
endpackage

`endif
