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
  localparam int unsigned RDMA_DMA_MAX_BURST_BEATS = 16;

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
      opq_cfg.drive_sidecar = 1'b1;
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
    int unsigned next_lineage_id;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      case_id = "BASE";
      scorecard_path = "";
      next_lineage_id = 0;
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
      next_lineage_id = 0;
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

    function void check_u32_equal(
      input string tag,
      input string field,
      input bit [31:0] got,
      input bit [31:0] expected
    );
      if (got !== expected)
        `uvm_error(tag, $sformatf("%s got=%0d expected=%0d", field, got, expected))
    endfunction

    function void check_u64_equal(
      input string tag,
      input string field,
      input bit [63:0] got,
      input bit [63:0] expected
    );
      if (got !== expected)
        `uvm_error(tag, $sformatf("%s got=%0d expected=%0d", field, got, expected))
    endfunction

    function void check_status_bit(
      input string tag,
      input string field,
      input int unsigned bit_idx,
      input bit expected
    );
      if (vif.job_status[bit_idx] !== expected)
        `uvm_error(tag, $sformatf("%s got=%0d expected=%0d",
                                  field, vif.job_status[bit_idx], expected))
    endfunction

    function void check_conservation(input string tag);
      bit [63:0] input_bytes;
      bit [63:0] accounted_bytes;
      input_bytes = {32'h0000_0000, vif.cnt_input_w} * 64'd4;
      accounted_bytes = {32'h0000_0000, vif.cnt_bytes_written} +
                        ({32'h0000_0000, vif.cnt_halt} * 64'd4);
      if (input_bytes !== accounted_bytes)
        `uvm_error(tag, $sformatf("conservation got input_bytes=%0d accounted=%0d",
                                  input_bytes, accounted_bytes))
    endfunction

    function void expect_simple_status_job(
      input bit [63:0] total_bytes,
      input bit [31:0] seg0_bytes,
      input bit [31:0] seg1_bytes,
      input bit [15:0] status_value,
      input bit [15:0] status_mask,
      input bit [15:0] sqe_id
    );
      env.scb.expect_job(total_bytes, seg0_bytes, seg1_bytes,
                         status_value, status_mask, sqe_id);
    endfunction

    function bit [15:0] single_seg_eoe_status();
      bit [15:0] status;
      status = 16'h0000;
      status[RDMA_DMA_ST_EOE] = 1'b1;
      status[RDMA_DMA_ST_SEG0_ONLY] = 1'b1;
      return status;
    endfunction

    function bit [15:0] single_seg_status_mask();
      bit [15:0] mask;
      mask = 16'h0000;
      mask[RDMA_DMA_ST_EOE] = 1'b1;
      mask[RDMA_DMA_ST_FULL] = 1'b1;
      mask[RDMA_DMA_ST_HALT] = 1'b1;
      mask[RDMA_DMA_ST_SEG_BOUNDARY_HIT] = 1'b1;
      mask[RDMA_DMA_ST_SEG0_ONLY] = 1'b1;
      mask[RDMA_DMA_ST_ALIGN_ERR] = 1'b1;
      mask[6] = 1'b1;
      return mask;
    endfunction

    function int unsigned phase_b_case_num(input string id);
      string digits;
      if (id.len() < 2)
        return 0;
      digits = id.substr(1, id.len() - 1);
      return digits.atoi();
    endfunction

    function byte phase_b_case_prefix(input string id);
      if (id.len() == 0)
        return "B";
      return id.getc(0);
    endfunction

    task check_reset_defaults(input string tag);
      wait_cycles(4);
      if (vif.m_axi_awvalid !== 1'b0)
        `uvm_error(tag, "m_axi_awvalid not idle after reset")
      if (vif.m_axi_wvalid !== 1'b0)
        `uvm_error(tag, "m_axi_wvalid not idle after reset")
      if (vif.m_axi_bready !== 1'b0)
        `uvm_error(tag, "m_axi_bready not idle after reset")
      if (vif.job_done !== 1'b0)
        `uvm_error(tag, "job_done asserted after reset")
      if (vif.cnt_input_w !== 32'h0 ||
          vif.cnt_bytes_written !== 32'h0 ||
          vif.cnt_halt !== 32'h0 ||
          vif.cnt_eoe_observed !== 32'h0)
        `uvm_error(tag, "sideband counters not zero after reset")
      if (env.debug_level >= 1) begin
        if (vif.dbg1_writer_state !== 4'h0)
          `uvm_error(tag, "dbg1_writer_state is not WR_IDLE after reset")
        if (vif.dbg1_fifo_level !== 9'h0)
          `uvm_error(tag, "dbg1_fifo_level is not zero after reset")
        if (vif.dbg1_packer_slot_idx !== 4'h0)
          `uvm_error(tag, "dbg1_packer_slot_idx is not zero after reset")
        if (vif.dbg1_halt_pulse !== 1'b0)
          `uvm_error(tag, "dbg1_halt_pulse asserted after reset")
      end
      if (env.debug_level >= 2 && vif.dbg2_writer_meta_valid !== 1'b0)
        `uvm_error(tag, "dbg2 writer sidecar valid after reset")
    endtask

    task pulse_clear_counters();
      @(negedge vif.clk);
      vif.clear_counters <= 1'b1;
      @(negedge vif.clk);
      vif.clear_counters <= 1'b0;
      @(posedge vif.clk);
    endtask

    task pulse_zero_eoe();
      @(negedge vif.clk);
      vif.s_axis_opq_tvalid <= 1'b0;
      vif.s_axis_opq_tlast <= 1'b1;
      vif.s_axis_opq_tuser <= 2'b00;
      @(negedge vif.clk);
      vif.s_axis_opq_tlast <= 1'b0;
    endtask

    task apply_midrun_reset(input int unsigned low_cycles = 4);
      @(negedge vif.clk);
      vif.reset_n <= 1'b0;
      repeat (low_cycles) @(posedge vif.clk);
      @(negedge vif.clk);
      vif.reset_n <= 1'b1;
      repeat (8) @(posedge vif.clk);
      env.scb.reset_model();
      env.scb.configure_case(case_id, scorecard_path, env.debug_level);
    endtask

    task run_dma_job(
      input string tag,
      input bit [63:0] seg0_addr = 64'h0000_0000_0010_0000,
      input bit [63:0] seg0_span = 64'h0000_0000_0000_1000,
      input bit [63:0] seg1_addr = 64'h0000_0000_0020_0000,
      input bit [63:0] seg1_span = 64'h0000_0000_0000_0000,
      input int unsigned opq_words = 8,
      input bit send_eoe = 1'b1,
      input bit zero_eoe = 1'b0,
      input int unsigned awready_lag = 0,
      input int unsigned wready_lag = 0,
      input int unsigned bvalid_lag = 1,
      input bit [1:0] bresp = axi4_write_pkg::AXI_RESP_OKAY,
      input bit [15:0] sqe_id = 16'h0100,
      input bit [31:0] sequence_no = 32'd1,
      input int unsigned idle_after_each = 0,
      input int unsigned timeout_cycles = 200000
    );
      job_single_segment_sequence job_seq;
      opq_axis_event_sequence opq_seq;
      bit align_error;
      bit [63:0] total_span;
      bit [63:0] expected_total;
      bit [63:0] expected_seg1_wide;
      bit [31:0] expected_seg0;
      bit [31:0] expected_seg1;
      bit [15:0] expected_status;
      bit [15:0] status_mask;

      total_span = seg0_span + seg1_span;
      align_error =
        (seg0_addr[11:0] != 12'h000) ||
        (seg0_span[11:0] != 12'h000) ||
        (seg0_span == 64'h0) ||
        ((seg1_span != 64'h0) &&
         ((seg1_addr[11:0] != 12'h000) || (seg1_span[11:0] != 12'h000)));

      expected_total = zero_eoe ? 64'd0 : (64'(opq_words) * 64'd4);
      if (!send_eoe && !zero_eoe && expected_total > total_span)
        expected_total = total_span;
      if (align_error)
        expected_total = 64'd0;

      expected_seg1_wide = (expected_total > seg0_span) ? (expected_total - seg0_span) : 64'h0;
      expected_seg0 = (expected_total > seg0_span) ? seg0_span[31:0] : expected_total[31:0];
      expected_seg1 = expected_seg1_wide[31:0];
      expected_status = 16'h0000;
      status_mask = 16'h0000;
      status_mask[RDMA_DMA_ST_SEG0_ONLY] = 1'b1;
      expected_status[RDMA_DMA_ST_SEG0_ONLY] = (seg1_span == 64'h0);
      if (align_error) begin
        status_mask[RDMA_DMA_ST_ALIGN_ERR] = 1'b1;
        expected_status[RDMA_DMA_ST_ALIGN_ERR] = 1'b1;
      end else begin
        status_mask[RDMA_DMA_ST_EOE] = 1'b1;
        status_mask[RDMA_DMA_ST_FULL] = 1'b1;
        status_mask[RDMA_DMA_ST_SEG_BOUNDARY_HIT] = 1'b1;
        expected_status[RDMA_DMA_ST_EOE] = send_eoe || zero_eoe;
        expected_status[RDMA_DMA_ST_FULL] = (expected_total == total_span) && !zero_eoe;
        expected_status[RDMA_DMA_ST_SEG_BOUNDARY_HIT] =
          (seg1_span != 64'h0) && (expected_total > seg0_span);
        if (bresp != axi4_write_pkg::AXI_RESP_OKAY) begin
          status_mask[6] = 1'b1;
          expected_status[6] = 1'b1;
        end
      end

      env.axi_cfg.awready_lag = awready_lag;
      env.axi_cfg.wready_lag = wready_lag;
      env.axi_cfg.bvalid_lag = bvalid_lag;
      env.axi_cfg.bresp = bresp;
      env.scb.set_allow_non_okay_bresp(bresp != axi4_write_pkg::AXI_RESP_OKAY);
      env.scb.expect_job(expected_total, expected_seg0, expected_seg1,
                         expected_status, status_mask, sqe_id);

      job_seq = job_single_segment_sequence::type_id::create({tag, "_job_seq"});
      job_seq.seg0_addr = seg0_addr;
      job_seq.seg0_span = seg0_span;
      job_seq.seg1_addr = seg1_addr;
      job_seq.seg1_span = seg1_span;
      job_seq.sqe_id = sqe_id;
      job_seq.opcode = 16'h0001;
      job_seq.start(env.job_agent_h.sequencer);

      if (!align_error) begin
        wait_cycles(2);
        if (zero_eoe) begin
          pulse_zero_eoe();
        end else begin
          opq_seq = opq_axis_event_sequence::type_id::create({tag, "_opq_seq"});
          opq_seq.word_count = opq_words;
          opq_seq.data_base = {8'h00, sequence_no[15:0], 8'h00};
          opq_seq.sequence_no = sequence_no;
          opq_seq.hit_id_base = next_lineage_id;
          opq_seq.idle_after_each = idle_after_each;
          opq_seq.mark_eoe_on_last = send_eoe;
          if (!send_eoe)
            opq_seq.word_count = opq_words;
          opq_seq.start(env.opq_agent.sequencer);
          next_lineage_id += opq_seq.word_count;
        end
      end

      wait_for_done(timeout_cycles);
      wait_cycles(2);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      env.axi_cfg.bresp = axi4_write_pkg::AXI_RESP_OKAY;
      env.axi_cfg.bresp_error_index = -1;
      env.axi_cfg.bresp_default = axi4_write_pkg::AXI_RESP_OKAY;
      env.axi_cfg.bid_value = 4'h0;
      env.axi_cfg.spurious_b_idle_cycles = 0;
      env.axi_cfg.spurious_b_during_w_cycles = 0;
      env.axi_cfg.duplicate_b_response_count = 0;
      env.axi_cfg.duplicate_b_delay_cycles = 0;
      env.scb.set_allow_non_okay_bresp(1'b0);
    endtask

    task run_dma_multi_event_job(
      input string tag,
      input int unsigned event_count = 2,
      input int unsigned words_per_event = 8,
      input int unsigned gap_cycles = 0,
      input bit [63:0] seg0_addr = 64'h0000_0000_0010_0000,
      input bit [63:0] seg0_span = 64'h0000_0000_0000_1000,
      input bit [63:0] seg1_addr = 64'h0000_0000_0020_0000,
      input bit [63:0] seg1_span = 64'h0000_0000_0000_0000,
      input bit [15:0] sqe_id = 16'h0100,
      input bit [31:0] sequence_no = 32'd1,
      input int unsigned awready_lag = 0,
      input int unsigned wready_lag = 0,
      input int unsigned bvalid_lag = 1,
      input int unsigned timeout_cycles = 300000
    );
      job_single_segment_sequence job_seq;
      opq_axis_event_sequence opq_seq;
      bit [63:0] expected_total;
      bit [63:0] expected_seg1_wide;
      bit [31:0] expected_seg0;
      bit [31:0] expected_seg1;
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      bit [31:0] ev_sequence_no;

      expected_total = 64'(event_count) * 64'(words_per_event) * 64'd4;
      if (expected_total > (seg0_span + seg1_span))
        expected_total = seg0_span + seg1_span;
      expected_seg1_wide = (expected_total > seg0_span) ?
        (expected_total - seg0_span) : 64'h0;
      expected_seg0 = (expected_total > seg0_span) ?
        seg0_span[31:0] : expected_total[31:0];
      expected_seg1 = expected_seg1_wide[31:0];
      expected_status = 16'h0000;
      status_mask = 16'h0000;
      status_mask[RDMA_DMA_ST_EOE] = 1'b1;
      status_mask[RDMA_DMA_ST_FULL] = 1'b1;
      status_mask[RDMA_DMA_ST_SEG_BOUNDARY_HIT] = 1'b1;
      status_mask[RDMA_DMA_ST_SEG0_ONLY] = 1'b1;
      expected_status[RDMA_DMA_ST_EOE] = 1'b1;
      expected_status[RDMA_DMA_ST_FULL] =
        (expected_total == (seg0_span + seg1_span));
      expected_status[RDMA_DMA_ST_SEG_BOUNDARY_HIT] =
        (seg1_span != 64'h0) && (expected_total > seg0_span);
      expected_status[RDMA_DMA_ST_SEG0_ONLY] = (seg1_span == 64'h0);
      env.axi_cfg.awready_lag = awready_lag;
      env.axi_cfg.wready_lag = wready_lag;
      env.axi_cfg.bvalid_lag = bvalid_lag;
      env.axi_cfg.bresp = axi4_write_pkg::AXI_RESP_OKAY;
      env.scb.expect_job(expected_total, expected_seg0, expected_seg1,
                         expected_status, status_mask, sqe_id);

      job_seq = job_single_segment_sequence::type_id::create({tag, "_job_seq"});
      job_seq.seg0_addr = seg0_addr;
      job_seq.seg0_span = seg0_span;
      job_seq.seg1_addr = seg1_addr;
      job_seq.seg1_span = seg1_span;
      job_seq.sqe_id = sqe_id;
      job_seq.opcode = 16'h0001;
      job_seq.start(env.job_agent_h.sequencer);
      wait_cycles(2);

      for (int unsigned ev_idx = 0; ev_idx < event_count; ev_idx++) begin
        ev_sequence_no = sequence_no + ev_idx;
        opq_seq = opq_axis_event_sequence::type_id::create(
          $sformatf("%s_opq_seq_%0d", tag, ev_idx));
        opq_seq.word_count = words_per_event;
        opq_seq.data_base = {8'h00, ev_sequence_no[15:0], 8'h00};
        opq_seq.sequence_no = ev_sequence_no;
        opq_seq.hit_id_base = next_lineage_id;
        opq_seq.mark_eoe_on_last = 1'b1;
        opq_seq.start(env.opq_agent.sequencer);
        next_lineage_id += opq_seq.word_count;
        if (gap_cycles != 0)
          wait_cycles(gap_cycles);
      end

      wait_for_done(timeout_cycles);
      wait_cycles(2);
      check_u32_equal(tag, "job_event_count", vif.job_event_count,
                      event_count[31:0]);
      check_u32_equal(tag, "cnt_eoe_observed", vif.cnt_eoe_observed,
                      event_count[31:0]);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
    endtask

    task drive_direct_opq_word(
      input bit [31:0] data,
      input bit eoe,
      input bit [31:0] sequence_no,
      input bit [31:0] hit_id
    );
      @(negedge vif.clk);
      vif.s_axis_opq_tdata <= {4'h0, data};
      vif.s_axis_opq_tvalid <= 1'b1;
      vif.s_axis_opq_tlast <= eoe;
      vif.s_axis_opq_tuser <= {1'b0, (hit_id == 32'd1)};
      vif.dbg2_meta_valid <= 1'b1;
      vif.dbg2_meta_lane <= 4'h0;
      vif.dbg2_meta_hit_id <= hit_id;
      vif.dbg2_meta_source_ts <= hit_id;
      vif.dbg2_meta_sequence_no <= sequence_no;
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
    endtask

    task drive_direct_job_req(
      input bit [63:0] seg0_addr,
      input bit [63:0] seg0_span,
      input bit [63:0] seg1_addr,
      input bit [63:0] seg1_span,
      input bit [15:0] sqe_id,
      input bit [15:0] opcode,
      input int unsigned hold_cycles = 1
    );
      @(negedge vif.clk);
      vif.job_seg0_addr <= seg0_addr;
      vif.job_seg0_span <= seg0_span;
      vif.job_seg1_addr <= seg1_addr;
      vif.job_seg1_span <= seg1_span;
      vif.job_sqe_id <= sqe_id;
      vif.job_opcode <= opcode;
      vif.job_req <= 1'b1;
      repeat (hold_cycles) @(negedge vif.clk);
      vif.job_req <= 1'b0;
    endtask

    task drive_direct_words(
      input int unsigned word_count,
      input bit send_eoe,
      input bit [31:0] sequence_no,
      input int unsigned hit_id_base = 0
    );
      for (int unsigned idx = 0; idx < word_count; idx++) begin
        drive_direct_opq_word({8'h00, sequence_no[15:0], idx[7:0]},
                              send_eoe && (idx + 1 == word_count),
                              sequence_no, hit_id_base + idx + 1);
      end
      next_lineage_id += word_count;
    endtask

    task run_direct_req_job(
      input string tag,
      input int unsigned hold_cycles,
      input bit [15:0] sqe_id,
      input bit check_state_after_capture = 1'b0
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd32, 32'd32, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, hold_cycles);
      if (check_state_after_capture && (vif.dbg1_writer_state == 4'd0))
        `uvm_error(tag, "job_req pulse did not move writer out of IDLE")
      wait_cycles(2);
      drive_direct_words(8, 1'b1, {16'h0000, sqe_id}, next_lineage_id);
      wait_for_done(300000);
      wait_cycles(2);
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count, 32'd1);
      check_u32_equal(tag, "job_bytes_written_total",
                      vif.job_bytes_written_total[31:0], 32'd32);
      if (vif.job_sqe_id_echo !== sqe_id)
        `uvm_error(tag, $sformatf("sqe_id_echo got=0x%04h expected=0x%04h",
                                  vif.job_sqe_id_echo, sqe_id))
    endtask

    task run_done_pulse_report_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit check_report_hold,
      input bit check_req_overlap
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      bit [63:0] bytes_at_done;
      bit [31:0] seg0_at_done;
      bit [31:0] seg1_at_done;
      bit [15:0] status_at_done;
      bit [15:0] sqe_at_done;
      bit [31:0] event_count_at_done;
      bit [63:0] first_ts_at_done;
      bit [63:0] last_ts_at_done;
      int unsigned done_cycles;
      bit seen_done;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd32, 32'd32, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(8, 1'b1, {16'h0000, sqe_id}, next_lineage_id);

      done_cycles = 0;
      seen_done = 1'b0;
      for (int unsigned cycle = 0; cycle < 300000; cycle++) begin
        @(posedge vif.clk);
        if (vif.job_done) begin
          done_cycles++;
          if (!seen_done) begin
            seen_done = 1'b1;
            bytes_at_done = vif.job_bytes_written_total;
            seg0_at_done = vif.job_seg0_bytes_written;
            seg1_at_done = vif.job_seg1_bytes_written;
            status_at_done = vif.job_status;
            sqe_at_done = vif.job_sqe_id_echo;
            event_count_at_done = vif.job_event_count;
            first_ts_at_done = vif.job_first_event_ts;
            last_ts_at_done = vif.job_last_event_ts;
            if (check_req_overlap) begin
              @(negedge vif.clk);
              vif.job_seg0_addr <= 64'h0000_0000_0030_0000;
              vif.job_seg0_span <= 64'h0000_0000_0000_1000;
              vif.job_seg1_addr <= 64'h0000_0000_0000_0000;
              vif.job_seg1_span <= 64'h0000_0000_0000_0000;
              vif.job_sqe_id <= sqe_id + 16'd1;
              vif.job_opcode <= 16'h0001;
              vif.job_req <= 1'b1;
            end
          end
        end else if (seen_done) begin
          break;
        end
      end
      if (!seen_done)
        `uvm_fatal(tag, "job_done was not observed")
      if (done_cycles != 1)
        `uvm_error(tag, $sformatf("job_done width got=%0d expected=1",
                                  done_cycles))

      @(posedge vif.clk);
      if (check_report_hold) begin
        if ((vif.job_bytes_written_total !== bytes_at_done) ||
            (vif.job_seg0_bytes_written !== seg0_at_done) ||
            (vif.job_seg1_bytes_written !== seg1_at_done) ||
            (vif.job_status !== status_at_done) ||
            (vif.job_sqe_id_echo !== sqe_at_done) ||
            (vif.job_event_count !== event_count_at_done) ||
            (vif.job_first_event_ts !== first_ts_at_done) ||
            (vif.job_last_event_ts !== last_ts_at_done))
          `uvm_error(tag, "report fields did not hold after job_done")
      end

      if (check_req_overlap) begin
        if (vif.job_done)
          `uvm_error(tag, "job_done overlapped the post-done accepted request")
        expect_simple_status_job(64'd32, 32'd32, 32'd0,
                                 expected_status, status_mask, sqe_id + 16'd1);
        @(negedge vif.clk);
        vif.job_req <= 1'b0;
        wait_cycles(2);
        drive_direct_words(8, 1'b1, {16'h0000, sqe_id + 16'd1},
                           next_lineage_id);
        wait_for_done(300000);
      end

      wait_cycles(2);
    endtask

    task run_fifo_level_probe_case(input string tag, input bit [15:0] sqe_id);
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd128, 32'd128, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 5000;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(32, 1'b1, {16'h0000, sqe_id}, next_lineage_id);
      wait_cycles(4);
      if (vif.dbg1_fifo_level !== 9'd4)
        `uvm_error(tag, $sformatf("dbg1_fifo_level got=%0d expected=4",
                                  vif.dbg1_fifo_level))
      env.axi_cfg.wready_lag = 0;
      wait_for_done(300000);
      wait_cycles(2);
    endtask

    task run_packer_slot_probe_case(input string tag, input bit [15:0] sqe_id);
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      int unsigned expected_slot;
      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd64, 32'd64, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 5000;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      for (int unsigned idx = 0; idx < 16; idx++) begin
        drive_direct_opq_word({8'h00, sqe_id, idx[7:0]},
                              (idx == 15), {16'h0000, sqe_id},
                              next_lineage_id + idx + 1);
        expected_slot = (idx + 1) % RDMA_DMA_OPQ_PER_BEAT;
        if (vif.dbg1_packer_slot_idx !== expected_slot[3:0])
          `uvm_error(tag, $sformatf(
            "dbg1_packer_slot_idx after word %0d got=%0d expected=%0d",
            idx + 1, vif.dbg1_packer_slot_idx, expected_slot))
      end
      next_lineage_id += 16;
      env.axi_cfg.wready_lag = 0;
      wait_for_done(300000);
      wait_cycles(2);
    endtask

    task wait_for_dbg1_state(
      input string tag,
      input bit [3:0] state,
      input int unsigned timeout_cycles = 300000
    );
      for (int unsigned cycle = 0; cycle < timeout_cycles; cycle++) begin
        @(posedge vif.clk);
        if (vif.dbg1_writer_state === state)
          return;
      end
      `uvm_fatal(tag, $sformatf("dbg1_writer_state %0d not observed", state))
    endtask

    task run_writer_state_probe_case(input string tag, input bit [15:0] sqe_id);
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd64, 32'd64, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 20;
      env.axi_cfg.wready_lag = 6;
      env.axi_cfg.bvalid_lag = 20;
      if (vif.dbg1_writer_state !== 4'd0)
        `uvm_error(tag, "writer did not start in IDLE")
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      if (vif.dbg1_writer_state !== 4'd1)
        `uvm_error(tag, $sformatf("PROGRAMMING state not observed, got=%0d",
                                  vif.dbg1_writer_state))
      wait_for_dbg1_state(tag, 4'd2);
      drive_direct_words(16, 1'b1, {16'h0000, sqe_id}, next_lineage_id);
      wait_for_dbg1_state(tag, 4'd3);
      wait_for_dbg1_state(tag, 4'd4);
      wait_for_dbg1_state(tag, 4'd5);
      wait_for_dbg1_state(tag, 4'd0);
      wait_cycles(2);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
    endtask

    task run_dbg1_aw_inflight_case(input string tag, input bit [15:0] sqe_id);
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      bit stop_monitor;
      bit prev_inflight;
      int unsigned high_edges;
      int unsigned high_falls;
      int unsigned high_samples;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd2560, 32'd2560, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 20;
      stop_monitor = 1'b0;
      prev_inflight = 1'b0;
      high_edges = 0;
      high_falls = 0;
      high_samples = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n !== 1'b1)
              continue;
            if (vif.dbg1_aw_inflight != 4'd0) begin
              high_samples++;
              if (!prev_inflight)
                high_edges++;
              prev_inflight = 1'b1;
            end else begin
              if (prev_inflight)
                high_falls++;
              prev_inflight = 1'b0;
            end
          end
        end
      join_none
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(640, 1'b1, {16'h0000, sqe_id}, next_lineage_id);
      wait_for_done(300000);
      wait_cycles(2);
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (high_edges < 5)
        `uvm_error(tag, $sformatf("dbg1_aw_inflight high_edges=%0d expected>=5",
                                  high_edges))
      if (high_falls < 5)
        `uvm_error(tag, $sformatf("dbg1_aw_inflight high_falls=%0d expected>=5",
                                  high_falls))
      if (high_samples == 0)
        `uvm_error(tag, "dbg1_aw_inflight never asserted")
      env.axi_cfg.bvalid_lag = 1;
    endtask

    task run_dbg1_w_remaining_case(input string tag, input bit [15:0] sqe_id);
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      bit stop_monitor;
      bit loaded;
      bit saw_zero_after_load;
      int unsigned max_remaining;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd512, 32'd512, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 2;
      env.axi_cfg.bvalid_lag = 12;
      stop_monitor = 1'b0;
      loaded = 1'b0;
      saw_zero_after_load = 1'b0;
      max_remaining = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n !== 1'b1)
              continue;
            if (vif.dbg1_w_beats_remaining > max_remaining)
              max_remaining = vif.dbg1_w_beats_remaining;
            if (vif.dbg1_w_beats_remaining == 8'd16)
              loaded = 1'b1;
            if (loaded && (vif.dbg1_w_beats_remaining == 8'd0))
              saw_zero_after_load = 1'b1;
          end
        end
      join_none
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(128, 1'b1, {16'h0000, sqe_id}, next_lineage_id);
      wait_for_done(300000);
      wait_cycles(2);
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (max_remaining != 16)
        `uvm_error(tag, $sformatf("dbg1_w_beats_remaining max=%0d expected=16",
                                  max_remaining))
      if (!saw_zero_after_load)
        `uvm_error(tag, "dbg1_w_beats_remaining did not return to zero")
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
    endtask

    task run_dbg1_b_outstanding_case(input string tag, input bit [15:0] sqe_id);
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      bit stop_monitor;
      int unsigned b_outstanding_samples;
      int unsigned delayed_wait_samples;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd512, 32'd512, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 100;
      stop_monitor = 1'b0;
      b_outstanding_samples = 0;
      delayed_wait_samples = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n !== 1'b1)
              continue;
            if (vif.dbg1_b_outstanding != 4'd0) begin
              b_outstanding_samples++;
              if (!vif.m_axi_bvalid)
                delayed_wait_samples++;
            end
          end
        end
      join_none
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(128, 1'b1, {16'h0000, sqe_id}, next_lineage_id);
      wait_for_done(300000);
      wait_cycles(2);
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (b_outstanding_samples == 0)
        `uvm_error(tag, "dbg1_b_outstanding never asserted")
      if (delayed_wait_samples < 32)
        `uvm_error(tag, $sformatf(
          "dbg1_b_outstanding delayed samples=%0d expected>=32",
          delayed_wait_samples))
      env.axi_cfg.bvalid_lag = 1;
    endtask

    task run_multi_event_var_job(
      input string tag,
      input int unsigned event_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no,
      input int unsigned timeout_cycles = 300000
    );
      job_single_segment_sequence job_seq;
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      int unsigned total_words;
      int unsigned words_this_event;

      total_words = 0;
      for (int unsigned ev_idx = 0; ev_idx < event_count; ev_idx++) begin
        words_this_event = 1 + ((ev_idx * 37 + 11) % 256);
        total_words += words_this_event;
      end
      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'(total_words) * 64'd4,
                               (total_words * 4), 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 24;
      job_seq = job_single_segment_sequence::type_id::create({tag, "_job_seq"});
      job_seq.seg0_addr = 64'h0000_0000_0010_0000;
      job_seq.seg0_span = 64'h0000_0000_0001_0000;
      job_seq.seg1_addr = 64'h0000_0000_0000_0000;
      job_seq.seg1_span = 64'h0000_0000_0000_0000;
      job_seq.sqe_id = sqe_id;
      job_seq.opcode = 16'h0001;
      job_seq.start(env.job_agent_h.sequencer);
      wait_cycles(2);
      for (int unsigned ev_idx = 0; ev_idx < event_count; ev_idx++) begin
        words_this_event = 1 + ((ev_idx * 37 + 11) % 256);
        drive_direct_words(words_this_event, 1'b1, sequence_no + ev_idx,
                           next_lineage_id);
        wait_cycles(ev_idx % 4);
      end
      wait_for_done(timeout_cycles);
      wait_cycles(2);
      check_u32_equal(tag, "job_event_count", vif.job_event_count,
                      event_count[31:0]);
      check_u32_equal(tag, "cnt_eoe_observed", vif.cnt_eoe_observed,
                      event_count[31:0]);
      env.axi_cfg.bvalid_lag = 1;
    endtask

    task run_random_idle_job(input string tag, input bit [15:0] sqe_id);
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd400, 32'd400, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      for (int unsigned idx = 0; idx < 100; idx++) begin
        drive_direct_opq_word({8'h00, sqe_id, idx[7:0]}, (idx == 99),
                              {16'h0000, sqe_id}, next_lineage_id + idx + 1);
        wait_cycles((idx * 17 + 3) % 4);
      end
      next_lineage_id += 100;
      wait_for_done(300000);
      wait_cycles(2);
      check_conservation(tag);
    endtask

    task run_random_mixed_jobs(input string tag, input bit [15:0] sqe_id);
      bit [63:0] spans [3];
      spans[0] = 64'h0000_0000_0000_1000;
      spans[1] = 64'h0000_0000_0000_2000;
      spans[2] = 64'h0000_0000_0000_4000;
      for (int unsigned idx = 0; idx < 8; idx++) begin
        bit two_seg;
        bit [63:0] seg0_span_v;
        bit [63:0] seg1_span_v;
        int unsigned words_v;
        two_seg = ((idx % 2) == 1);
        seg0_span_v = spans[(idx * 5 + 1) % 3];
        seg1_span_v = two_seg ? spans[(idx * 3 + 2) % 3] : 64'h0;
        words_v = two_seg ? (1024 + ((idx * 73) % 512)) :
                  (64 + ((idx * 29) % 512));
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .seg0_span(seg0_span_v),
                    .seg1_span(seg1_span_v),
                    .opq_words(words_v),
                    .send_eoe(1'b1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(32'(idx + 1)),
                    .idle_after_each(idx % 3),
                    .timeout_cycles(300000));
      end
      check_conservation(tag);
    endtask

    task run_queue_single_burst_case(input string tag, input bit [15:0] sqe_id);
      bit stop_monitor;
      int unsigned cycle_count;
      int unsigned w_count_local;
      int unsigned first_w_cycle;
      int unsigned last_w_cycle;

      stop_monitor = 1'b0;
      cycle_count = 0;
      w_count_local = 0;
      first_w_cycle = 0;
      last_w_cycle = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            cycle_count++;
            if (vif.reset_n !== 1'b1)
              continue;
            if (vif.m_axi_wvalid && vif.m_axi_wready) begin
              w_count_local++;
              if (first_w_cycle == 0)
                first_w_cycle = cycle_count;
              last_w_cycle = cycle_count;
            end
          end
        end
      join_none
      run_dma_job(.tag(tag), .seg0_span(64'h1000), .opq_words(128),
                  .send_eoe(1'b1), .sqe_id(sqe_id), .sequence_no(32'd117),
                  .timeout_cycles(300000));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (w_count_local != 16)
        `uvm_error(tag, $sformatf("W beat count got=%0d expected=16",
                                  w_count_local))
      if ((last_w_cycle - first_w_cycle + 1) != 16)
        `uvm_error(tag, $sformatf(
          "single-burst W cadence got=%0d cycles expected=16",
          last_w_cycle - first_w_cycle + 1))
    endtask

    task run_queue_burst_model_case(input string tag, input bit [15:0] sqe_id);
      int unsigned aw_before;
      int unsigned w_before;
      int unsigned aw_delta;
      int unsigned w_delta;
      int unsigned util_milli;

      aw_before = env.scb.aw_count;
      w_before = env.scb.w_count;
      run_dma_job(.tag(tag), .seg0_span(64'h2000), .opq_words(2048),
                  .send_eoe(1'b0), .sqe_id(sqe_id), .sequence_no(32'd118),
                  .timeout_cycles(500000));
      aw_delta = env.scb.aw_count - aw_before;
      w_delta = env.scb.w_count - w_before;
      if (aw_delta != 16)
        `uvm_error(tag, $sformatf("AW count got=%0d expected=16", aw_delta))
      if (w_delta != 256)
        `uvm_error(tag, $sformatf("W count got=%0d expected=256", w_delta))
      util_milli = (w_delta * 1000) / (w_delta + aw_delta);
      if ((util_milli < 940) || (util_milli > 942))
        `uvm_error(tag, $sformatf(
          "burst model utilization got=%0d/1000 expected about 941/1000",
          util_milli))
    endtask

    task run_fifo_residency_case(input string tag, input bit [15:0] sqe_id);
      bit stop_monitor;
      int unsigned sample_count;
      int unsigned max_level;
      longint unsigned sum_level;
      int unsigned avg_level;

      stop_monitor = 1'b0;
      sample_count = 0;
      max_level = 0;
      sum_level = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n !== 1'b1)
              continue;
            sample_count++;
            sum_level += vif.dbg1_fifo_level;
            if (vif.dbg1_fifo_level > max_level)
              max_level = vif.dbg1_fifo_level;
          end
        end
      join_none
      run_dma_job(.tag(tag), .seg0_span(64'h4000), .opq_words(1024),
                  .send_eoe(1'b1), .bvalid_lag(100), .sqe_id(sqe_id),
                  .sequence_no(32'd119), .timeout_cycles(500000));
      stop_monitor = 1'b1;
      wait_cycles(1);
      avg_level = (sample_count == 0) ? 0 : int'(sum_level / sample_count);
      if (max_level == 0)
        `uvm_error(tag, "dbg1_fifo_level never accumulated residency")
      if (max_level >= 192)
        `uvm_error(tag, $sformatf("fifo max_level=%0d expected below 192",
                                  max_level))
      if (avg_level == 0)
        `uvm_error(tag, "average FIFO residency was zero")
      check_status_bit(tag, "status[HALT]", RDMA_DMA_ST_HALT, 1'b0);
    endtask

    task run_segment_latency_case(input string tag, input bit [15:0] sqe_id);
      bit stop_monitor;
      bit prev_programming;
      int unsigned programming_edges;

      stop_monitor = 1'b0;
      prev_programming = 1'b0;
      programming_edges = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n !== 1'b1)
              continue;
            if (vif.dbg1_writer_state == 4'd1) begin
              if (!prev_programming)
                programming_edges++;
              prev_programming = 1'b1;
            end else begin
              prev_programming = 1'b0;
            end
          end
        end
      join_none
      run_dma_job(.tag(tag), .seg0_span(64'h1000), .seg1_span(64'h1000),
                  .opq_words(2048), .send_eoe(1'b0), .sqe_id(sqe_id),
                  .sequence_no(32'd121), .timeout_cycles(500000));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (programming_edges < 2)
        `uvm_error(tag, $sformatf(
          "segment transition programming edges=%0d expected>=2",
          programming_edges))
      check_status_bit(tag, "status[SEG_BOUNDARY_HIT]",
                       RDMA_DMA_ST_SEG_BOUNDARY_HIT, 1'b1);
    endtask

    task run_aw_observed_job(
      input string tag,
      input bit [63:0] obs_seg0_addr = 64'h0000_0000_0010_0000,
      input bit [63:0] obs_seg0_span = 64'h0000_0000_0000_1000,
      input bit [63:0] obs_seg1_addr = 64'h0000_0000_0020_0000,
      input bit [63:0] obs_seg1_span = 64'h0000_0000_0000_0000,
      input int unsigned obs_words = 8,
      input bit obs_send_eoe = 1'b1,
      input int unsigned expected_aw_count = 0,
      input bit check_first_aw = 1'b1,
      input bit [63:0] expected_first_aw = 64'h0000_0000_0010_0000,
      input bit check_last_aw = 1'b0,
      input bit [63:0] expected_last_aw = 64'h0000_0000_0010_0000,
      input bit check_first_awlen = 1'b0,
      input int unsigned expected_first_awlen = 0,
      input bit check_last_awlen = 1'b0,
      input int unsigned expected_last_awlen = 0,
      input bit check_seg1_aw = 1'b0,
      input bit [63:0] expected_seg1_aw = 64'h0000_0000_0020_0000,
      input bit [15:0] sqe_id = 16'h0100,
      input bit [31:0] sequence_no = 32'd1,
      input int unsigned obs_idle_after_each = 0,
      input int unsigned obs_awready_lag = 0,
      input int unsigned obs_wready_lag = 0,
      input int unsigned obs_bvalid_lag = 1,
      input int unsigned timeout_cycles = 500000
    );
      bit stop_monitor;
      bit saw_first_aw;
      bit saw_seg1_aw;
      int unsigned aw_count_local;
      int unsigned max_awlen;
      int unsigned first_awlen;
      int unsigned last_awlen;
      bit [63:0] first_aw;
      bit [63:0] last_aw;

      stop_monitor = 1'b0;
      saw_first_aw = 1'b0;
      saw_seg1_aw = 1'b0;
      aw_count_local = 0;
      max_awlen = 0;
      first_awlen = 0;
      last_awlen = 0;
      first_aw = 64'h0;
      last_aw = 64'h0;

      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n !== 1'b1)
              continue;
            if (vif.m_axi_awvalid && vif.m_axi_awready) begin
              aw_count_local++;
              if (!saw_first_aw) begin
                first_aw = vif.m_axi_awaddr;
                first_awlen = vif.m_axi_awlen;
                saw_first_aw = 1'b1;
              end
              last_aw = vif.m_axi_awaddr;
              last_awlen = vif.m_axi_awlen;
              if (vif.m_axi_awlen > max_awlen)
                max_awlen = vif.m_axi_awlen;
              if (vif.m_axi_awaddr == expected_seg1_aw)
                saw_seg1_aw = 1'b1;
              if (vif.m_axi_awsize !== 3'd5)
                `uvm_error(tag, $sformatf("AWSIZE got=%0d expected=5",
                                          vif.m_axi_awsize))
              if (vif.m_axi_awlen > 8'd15)
                `uvm_error(tag, $sformatf("AWLEN got=%0d expected<=15",
                                          vif.m_axi_awlen))
              if ((int'(vif.m_axi_awaddr[11:0]) +
                   ((int'(vif.m_axi_awlen) + 1) * RDMA_DMA_BYTES)) > 4096)
                `uvm_error(tag, $sformatf("AW crossed 4KB page addr=0x%016h len=%0d",
                                          vif.m_axi_awaddr, vif.m_axi_awlen))
            end
          end
        end
      join_none

      run_dma_job(.tag(tag), .seg0_addr(obs_seg0_addr),
                  .seg0_span(obs_seg0_span), .seg1_addr(obs_seg1_addr),
                  .seg1_span(obs_seg1_span), .opq_words(obs_words),
                  .send_eoe(obs_send_eoe), .sqe_id(sqe_id),
                  .sequence_no(sequence_no),
                  .idle_after_each(obs_idle_after_each),
                  .awready_lag(obs_awready_lag),
                  .wready_lag(obs_wready_lag),
                  .bvalid_lag(obs_bvalid_lag),
                  .timeout_cycles(timeout_cycles));
      stop_monitor = 1'b1;
      wait_cycles(1);

      if (expected_aw_count != 0 && aw_count_local != expected_aw_count)
        `uvm_error(tag, $sformatf("AW count got=%0d expected=%0d",
                                  aw_count_local, expected_aw_count))
      if (check_first_aw && first_aw !== expected_first_aw)
        `uvm_error(tag, $sformatf("first AW got=0x%016h expected=0x%016h",
                                  first_aw, expected_first_aw))
      if (check_last_aw && last_aw !== expected_last_aw)
        `uvm_error(tag, $sformatf("last AW got=0x%016h expected=0x%016h",
                                  last_aw, expected_last_aw))
      if (check_first_awlen && first_awlen != expected_first_awlen)
        `uvm_error(tag, $sformatf("first AWLEN got=%0d expected=%0d",
                                  first_awlen, expected_first_awlen))
      if (check_last_awlen && last_awlen != expected_last_awlen)
        `uvm_error(tag, $sformatf("last AWLEN got=%0d expected=%0d",
                                  last_awlen, expected_last_awlen))
      if (check_seg1_aw && !saw_seg1_aw)
        `uvm_error(tag, $sformatf("seg1 AW addr 0x%016h was not observed",
                                  expected_seg1_aw))
      if (max_awlen > 15)
        `uvm_error(tag, $sformatf("max AWLEN got=%0d expected<=15", max_awlen))
    endtask

    task run_fifo_threshold_edge_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit check_crossing,
      input bit check_drain,
      input bit [31:0] sequence_no = 32'd31
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      int unsigned accepted_words;
      int unsigned lineage_id;
      bit saw_drain_to_191;

      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 5000;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0040_0000,
                           64'h0000_0000_0001_0000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);

      accepted_words = 0;
      lineage_id = next_lineage_id;
      for (int unsigned beat_idx = 0; beat_idx < 191; beat_idx++) begin
        for (int unsigned slot_idx = 0; slot_idx < RDMA_DMA_OPQ_PER_BEAT;
             slot_idx++) begin
          accepted_words++;
          lineage_id++;
          drive_direct_opq_word({8'h00, sequence_no[15:0],
                                accepted_words[7:0]},
                                1'b0, sequence_no, lineage_id);
        end
      end
      wait_cycles(2);
      if (vif.dbg1_fifo_level !== 9'd191)
        `uvm_error(tag, $sformatf("fifo level got=%0d expected=191",
                                  vif.dbg1_fifo_level))
      if (vif.dbg1_fifo_almost_full !== 1'b0)
        `uvm_error(tag, "fifo_almost_full asserted at threshold-1")

      for (int unsigned slot_idx = 0; slot_idx < RDMA_DMA_OPQ_PER_BEAT;
           slot_idx++) begin
        accepted_words++;
        lineage_id++;
        drive_direct_opq_word({8'h00, sequence_no[15:0],
                              accepted_words[7:0]},
                              1'b0, sequence_no, lineage_id);
      end
      wait_cycles(2);
      if (check_crossing) begin
        if (vif.dbg1_fifo_level !== 9'd192)
          `uvm_error(tag, $sformatf("fifo level got=%0d expected=192",
                                    vif.dbg1_fifo_level))
        if (vif.dbg1_fifo_almost_full !== 1'b1)
          `uvm_error(tag, "fifo_almost_full did not assert at threshold")
      end

      env.axi_cfg.wready_lag = 0;
      saw_drain_to_191 = 1'b0;
      for (int unsigned cycle = 0; cycle < 20000; cycle++) begin
        @(posedge vif.clk);
        if ((vif.dbg1_fifo_level <= 9'd191) &&
            (vif.dbg1_fifo_almost_full === 1'b0)) begin
          saw_drain_to_191 = 1'b1;
          break;
        end
      end
      if (check_drain && !saw_drain_to_191)
        `uvm_error(tag, "fifo_almost_full did not clear when draining to 191")

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      accepted_words++;
      lineage_id++;
      expect_simple_status_job(64'(accepted_words) * 64'd4,
                               accepted_words[31:0] * 32'd4, 32'd0,
                               expected_status, status_mask, sqe_id);
      drive_direct_opq_word({8'h00, sequence_no[15:0], accepted_words[7:0]},
                            1'b1, sequence_no, lineage_id);
      wait_for_done(500000);
      wait_cycles(2);
      check_status_bit(tag, "status[HALT]", RDMA_DMA_ST_HALT, 1'b0);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      next_lineage_id = lineage_id;
    endtask

    task run_fifo_partial_fill_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd32, 32'd32, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 5000;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0040_0000,
                           64'h0000_0000_0001_0000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(4, 1'b0, sequence_no, next_lineage_id);
      wait_cycles(2);
      if (vif.dbg1_fifo_level !== 9'd0)
        `uvm_error(tag, $sformatf("fifo level got=%0d expected=0 before beat",
                                  vif.dbg1_fifo_level))
      if (vif.dbg1_packer_slot_idx !== 4'd4)
        `uvm_error(tag, $sformatf("packer slot got=%0d expected=4",
                                  vif.dbg1_packer_slot_idx))
      drive_direct_words(4, 1'b1, sequence_no, next_lineage_id);
      wait_cycles(2);
      if (vif.dbg1_fifo_level !== 9'd1)
        `uvm_error(tag, $sformatf("fifo level got=%0d expected=1 after beat",
                                  vif.dbg1_fifo_level))
      env.axi_cfg.wready_lag = 0;
      wait_for_done(300000);
      wait_cycles(2);
      env.axi_cfg.bvalid_lag = 1;
    endtask

    task run_fifo_single_beat_dwell_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd32, 32'd32, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 5000;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0040_0000,
                           64'h0000_0000_0001_0000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(8, 1'b1, sequence_no, next_lineage_id);
      wait_cycles(2);
      if (vif.dbg1_fifo_level !== 9'd1)
        `uvm_error(tag, $sformatf("fifo dwell level got=%0d expected=1",
                                  vif.dbg1_fifo_level))
      env.axi_cfg.wready_lag = 0;
      wait_for_done(300000);
      wait_cycles(2);
      if (vif.dbg1_fifo_level !== 9'd0)
        `uvm_error(tag, $sformatf("fifo level got=%0d expected=0 after drain",
                                  vif.dbg1_fifo_level))
      env.axi_cfg.bvalid_lag = 1;
    endtask

    task run_fifo_fill_drain_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit check_fill,
      input bit check_empty_after_done,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      int unsigned accepted_words;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      accepted_words = 192 * RDMA_DMA_OPQ_PER_BEAT;
      expect_simple_status_job(64'(accepted_words + 1) * 64'd4,
                               32'(accepted_words + 1) * 32'd4,
                               32'd0, expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 50000;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0040_0000,
                           64'h0000_0000_0001_0000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);

      for (int unsigned beat_idx = 0; beat_idx < 191; beat_idx++) begin
        drive_direct_words(RDMA_DMA_OPQ_PER_BEAT, 1'b0, sequence_no,
                           next_lineage_id);
      end
      wait_cycles(2);
      if (check_fill && (vif.dbg1_fifo_level !== 9'd191))
        `uvm_error(tag, $sformatf("fifo level got=%0d expected=191",
                                  vif.dbg1_fifo_level))
      drive_direct_words(RDMA_DMA_OPQ_PER_BEAT, 1'b0, sequence_no,
                         next_lineage_id);
      wait_cycles(2);
      if (check_fill) begin
        if (vif.dbg1_fifo_level !== 9'd192)
          `uvm_error(tag, $sformatf("fifo level got=%0d expected=192",
                                    vif.dbg1_fifo_level))
        if (vif.dbg1_fifo_almost_full !== 1'b1)
          `uvm_error(tag, "fifo_almost_full did not assert after fill")
      end

      env.axi_cfg.wready_lag = 0;
      for (int unsigned cycle = 0; cycle < 20000; cycle++) begin
        @(posedge vif.clk);
        if (vif.dbg1_fifo_almost_full === 1'b0)
          break;
      end
      drive_direct_words(1, 1'b1, sequence_no, next_lineage_id);
      wait_for_done(500000);
      wait_cycles(2);
      if (check_empty_after_done && (vif.dbg1_fifo_level !== 9'd0))
        `uvm_error(tag, $sformatf("fifo level got=%0d expected=0 after drain",
                                  vif.dbg1_fifo_level))
      env.axi_cfg.bvalid_lag = 1;
    endtask

    task run_packer_flush_slot_case(
      input string tag,
      input int unsigned slot_words,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit saw_w;
      bit [31:0] first_wstrb;
      bit first_wlast;
      int unsigned w_count_local;
      bit [31:0] expected_strb;

      stop_monitor = 1'b0;
      saw_w = 1'b0;
      first_wstrb = 32'h0000_0000;
      first_wlast = 1'b0;
      w_count_local = 0;
      expected_strb = (slot_words == RDMA_DMA_OPQ_PER_BEAT) ?
        32'hffff_ffff : ((32'h0000_0001 << (slot_words * 4)) - 32'd1);

      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n !== 1'b1)
              continue;
            if (vif.m_axi_wvalid && vif.m_axi_wready) begin
              w_count_local++;
              if (!saw_w) begin
                first_wstrb = vif.m_axi_wstrb;
                first_wlast = vif.m_axi_wlast;
                saw_w = 1'b1;
              end
            end
          end
        end
      join_none

      run_dma_job(.tag(tag), .opq_words(slot_words), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (!saw_w)
        `uvm_error(tag, "no W beat observed for packer flush")
      if (w_count_local != 1)
        `uvm_error(tag, $sformatf("W count got=%0d expected=1",
                                  w_count_local))
      if (first_wstrb !== expected_strb)
        `uvm_error(tag, $sformatf("WSTRB got=0x%08h expected=0x%08h",
                                  first_wstrb, expected_strb))
      if (first_wlast !== 1'b1)
        `uvm_error(tag, "single flush beat did not assert WLAST")
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w,
                      slot_words[31:0]);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'(slot_words * 4));
    endtask

    task run_packer_full_then_slot1_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned w_count_local;
      bit [31:0] first_wstrb;
      bit [31:0] second_wstrb;
      bit first_wlast;
      bit second_wlast;

      stop_monitor = 1'b0;
      w_count_local = 0;
      first_wstrb = 32'h0000_0000;
      second_wstrb = 32'h0000_0000;
      first_wlast = 1'b0;
      second_wlast = 1'b0;

      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n !== 1'b1)
              continue;
            if (vif.m_axi_wvalid && vif.m_axi_wready) begin
              w_count_local++;
              if (w_count_local == 1) begin
                first_wstrb = vif.m_axi_wstrb;
                first_wlast = vif.m_axi_wlast;
              end else if (w_count_local == 2) begin
                second_wstrb = vif.m_axi_wstrb;
                second_wlast = vif.m_axi_wlast;
              end
            end
          end
        end
      join_none

      run_dma_job(.tag(tag), .opq_words(9), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (w_count_local != 2)
        `uvm_error(tag, $sformatf("W count got=%0d expected=2",
                                  w_count_local))
      if (first_wstrb !== 32'hffff_ffff)
        `uvm_error(tag, $sformatf("first WSTRB got=0x%08h expected=0xffffffff",
                                  first_wstrb))
      if (first_wlast !== 1'b0)
        `uvm_error(tag, "first full beat unexpectedly asserted WLAST")
      if (second_wstrb !== 32'h0000_000f)
        `uvm_error(tag, $sformatf("second WSTRB got=0x%08h expected=0x0000000f",
                                  second_wstrb))
      if (second_wlast !== 1'b1)
        `uvm_error(tag, "slot1 EOE flush did not assert WLAST")
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd9);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd36);
      check_u32_equal(tag, "cnt_eoe_observed", vif.cnt_eoe_observed,
                      32'd1);
    endtask

    task run_double_eoe_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd4, 32'd4, 32'd0, expected_status,
                               status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 100;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0040_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(1, 1'b1, sequence_no, next_lineage_id);
      wait_cycles(2);
      pulse_zero_eoe();
      env.axi_cfg.wready_lag = 0;
      wait_for_done(300000);
      wait_cycles(2);
      check_u32_equal(tag, "job_event_count", vif.job_event_count, 32'd2);
      check_u32_equal(tag, "cnt_eoe_observed", vif.cnt_eoe_observed,
                      32'd2);
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd1);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd4);
      env.axi_cfg.bvalid_lag = 1;
    endtask

    task run_zero_byte_eoe_idle_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag(tag), .opq_words(0), .send_eoe(1'b0),
                  .zero_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      check_u32_equal(tag, "job_event_count", vif.job_event_count, 32'd1);
      check_u32_equal(tag, "cnt_eoe_observed", vif.cnt_eoe_observed,
                      32'd1);
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd0);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd0);
    endtask

    task run_segment_boundary_edge_case(
      input string tag,
      input bit [63:0] seg0_addr,
      input bit [63:0] seg0_span,
      input bit [63:0] seg1_addr,
      input bit [63:0] seg1_span,
      input int unsigned opq_words,
      input bit send_eoe,
      input bit [31:0] expected_seg0,
      input bit [31:0] expected_seg1,
      input int unsigned expected_aw_count,
      input bit check_seg1_aw,
      input bit [63:0] expected_seg1_aw,
      input bit check_last_aw,
      input bit [63:0] expected_last_aw,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no,
      input int unsigned idle_after_each = 0,
      input int unsigned wready_lag = 0
    );
      run_aw_observed_job(.tag(tag), .obs_seg0_addr(seg0_addr),
                          .obs_seg0_span(seg0_span),
                          .obs_seg1_addr(seg1_addr),
                          .obs_seg1_span(seg1_span),
                          .obs_words(opq_words),
                          .obs_send_eoe(send_eoe),
                          .expected_aw_count(expected_aw_count),
                          .expected_first_aw(seg0_addr),
                          .check_seg1_aw(check_seg1_aw),
                          .expected_seg1_aw(expected_seg1_aw),
                          .check_last_aw(check_last_aw),
                          .expected_last_aw(expected_last_aw),
                          .obs_idle_after_each(idle_after_each),
                          .obs_wready_lag(wready_lag),
                          .sqe_id(sqe_id), .sequence_no(sequence_no),
                          .timeout_cycles(500000));
      check_u32_equal(tag, "job_seg0_bytes_written",
                      vif.job_seg0_bytes_written, expected_seg0);
      check_u32_equal(tag, "job_seg1_bytes_written",
                      vif.job_seg1_bytes_written, expected_seg1);
      check_status_bit(tag, "status[SEG_BOUNDARY_HIT]",
                       RDMA_DMA_ST_SEG_BOUNDARY_HIT,
                       expected_seg1 != 32'd0);
      check_status_bit(tag, "status[EOE]", RDMA_DMA_ST_EOE, send_eoe);
      check_status_bit(tag, "status[FULL]", RDMA_DMA_ST_FULL, !send_eoe);
    endtask

    task run_exact_full_burst_eoe_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_aw_observed_job(.tag(tag), .obs_words(128),
                          .obs_send_eoe(1'b1),
                          .expected_aw_count(1),
                          .expected_first_aw(64'h0000_0000_0010_0000),
                          .check_first_awlen(1'b1),
                          .expected_first_awlen(15),
                          .sqe_id(sqe_id), .sequence_no(sequence_no));
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd128);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd512);
      check_status_bit(tag, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
      check_status_bit(tag, "status[FULL]", RDMA_DMA_ST_FULL, 1'b0);
    endtask

    task run_eoe_after_full_burst_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_aw_observed_job(.tag(tag), .obs_words(129),
                          .obs_send_eoe(1'b1),
                          .expected_aw_count(2),
                          .expected_first_aw(64'h0000_0000_0010_0000),
                          .check_first_awlen(1'b1),
                          .expected_first_awlen(15),
                          .check_last_awlen(1'b1),
                          .expected_last_awlen(0),
                          .sqe_id(sqe_id), .sequence_no(sequence_no));
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd129);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd516);
      check_status_bit(tag, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
      check_status_bit(tag, "status[FULL]", RDMA_DMA_ST_FULL, 1'b0);
    endtask

    task run_eoe_during_aw_phase_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_aw_observed_job(.tag(tag), .obs_words(5),
                          .obs_send_eoe(1'b1),
                          .expected_aw_count(1),
                          .expected_first_aw(64'h0000_0000_0010_0000),
                          .check_first_awlen(1'b1),
                          .expected_first_awlen(0),
                          .obs_awready_lag(100),
                          .sqe_id(sqe_id), .sequence_no(sequence_no));
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd5);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd20);
      check_status_bit(tag, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
      check_status_bit(tag, "status[FULL]", RDMA_DMA_ST_FULL, 1'b0);
    endtask

    task run_program_phase_eoe_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;

      expected_status = 16'h0000;
      status_mask = single_seg_status_mask();
      expected_status[RDMA_DMA_ST_EOE] = 1'b1;
      expected_status[RDMA_DMA_ST_SEG_BOUNDARY_HIT] = 1'b1;
      expect_simple_status_job(64'd4096, 32'd4096, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0020_0000,
                           64'h0000_0000_0000_1000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(1024, 1'b0, sequence_no, next_lineage_id);
      for (int unsigned cycle = 0; cycle < 300000; cycle++) begin
        @(posedge vif.clk);
        if ((vif.dbg1_writer_state === 4'd1) &&
            (vif.job_seg0_bytes_written === 32'd4096))
          break;
        if (cycle == 299999)
          `uvm_fatal(tag, "seg1 PROGRAM state was not observed")
      end
      pulse_zero_eoe();
      wait_for_done(300000);
      wait_cycles(2);
      check_u32_equal(tag, "job_event_count", vif.job_event_count, 32'd1);
      check_u32_equal(tag, "cnt_eoe_observed", vif.cnt_eoe_observed,
                      32'd1);
      check_u32_equal(tag, "job_seg0_bytes_written",
                      vif.job_seg0_bytes_written, 32'd4096);
      check_u32_equal(tag, "job_seg1_bytes_written",
                      vif.job_seg1_bytes_written, 32'd0);
    endtask

    task run_full_boundary_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no,
      input bit send_eoe_at_full
    );
      run_aw_observed_job(.tag(tag), .obs_words(1024),
                          .obs_send_eoe(send_eoe_at_full),
                          .expected_aw_count(8),
                          .expected_first_aw(64'h0000_0000_0010_0000),
                          .check_first_awlen(1'b1),
                          .expected_first_awlen(15),
                          .check_last_awlen(1'b1),
                          .expected_last_awlen(15),
                          .sqe_id(sqe_id), .sequence_no(sequence_no));
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd1024);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd4096);
      check_status_bit(tag, "status[EOE]", RDMA_DMA_ST_EOE,
                       send_eoe_at_full);
      check_status_bit(tag, "status[FULL]", RDMA_DMA_ST_FULL, 1'b1);
    endtask

    task run_align_error_no_write_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag(tag), .seg0_span(64'h0), .opq_words(0),
                  .send_eoe(1'b0), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      check_status_bit(tag, "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR,
                       1'b1);
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd0);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd0);
      if ((env.scb.aw_count != 0) || (env.scb.w_count != 0))
        `uvm_error(tag, "ALIGN_ERR job unexpectedly issued AXI writes")
    endtask

    task run_two_job_one_cycle_after_done_case(
      input string tag,
      input bit [15:0] first_sqe_id,
      input bit [15:0] second_sqe_id,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      bit seen_done;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd32, 32'd32, 32'd0,
                               expected_status, status_mask, first_sqe_id);
      expect_simple_status_job(64'd32, 32'd32, 32'd0,
                               expected_status, status_mask, second_sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           first_sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(8, 1'b1, sequence_no, next_lineage_id);
      seen_done = 1'b0;
      for (int unsigned cycle = 0; cycle < 300000; cycle++) begin
        @(posedge vif.clk);
        if (vif.job_done) begin
          seen_done = 1'b1;
          break;
        end
      end
      if (!seen_done)
        `uvm_fatal(tag, "first job_done was not observed")
      @(posedge vif.clk);
      drive_direct_job_req(64'h0000_0000_0030_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           second_sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(8, 1'b1, sequence_no + 32'd100, next_lineage_id);
      wait_for_done(300000);
      wait_cycles(2);
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'd2);
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd16);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd64);
    endtask

    task run_two_jobs_with_gap_case(
      input string tag,
      input int unsigned gap_cycles,
      input bit [15:0] first_sqe_id,
      input bit [15:0] second_sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag({tag, "_job0"}), .opq_words(8), .send_eoe(1'b1),
                  .sqe_id(first_sqe_id), .sequence_no(sequence_no));
      if (vif.dbg1_writer_state !== 4'd0)
        `uvm_error(tag, "writer was not idle after first job")
      wait_cycles(gap_cycles);
      if (vif.dbg1_writer_state !== 4'd0)
        `uvm_error(tag, "writer did not remain idle through the gap")
      run_dma_job(.tag({tag, "_job1"}), .opq_words(8), .send_eoe(1'b1),
                  .sqe_id(second_sqe_id), .sequence_no(sequence_no + 32'd100));
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'd2);
    endtask

    task run_mixed_span_two_job_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag({tag, "_job0"}), .seg0_span(64'h1000),
                  .opq_words(1024), .send_eoe(1'b0),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      run_dma_job(.tag({tag, "_job1"}), .seg0_span(64'h4000),
                  .opq_words(4096), .send_eoe(1'b0),
                  .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd100),
                  .timeout_cycles(700000));
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'd2);
      check_status_bit(tag, "status[FULL]", RDMA_DMA_ST_FULL, 1'b1);
    endtask

    task run_dbg1_idle_aw_inflight_case(input string tag);
      for (int unsigned cycle = 0; cycle < 96; cycle++) begin
        @(posedge vif.clk);
        if (vif.dbg1_writer_state !== 4'd0)
          `uvm_error(tag, $sformatf("writer left IDLE during idle probe, state=%0d",
                                    vif.dbg1_writer_state))
        if (vif.dbg1_aw_inflight !== 4'd0)
          `uvm_error(tag, $sformatf("dbg1_aw_inflight got=%0d expected=0",
                                    vif.dbg1_aw_inflight))
      end
    endtask

    task run_packer_pending_eoe_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit saw_pending;
      bit saw_clear_after_pending;

      stop_monitor = 1'b0;
      saw_pending = 1'b0;
      saw_clear_after_pending = 1'b0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n !== 1'b1)
              continue;
            if (vif.dbg1_packer_pending_eoe)
              saw_pending = 1'b1;
            if (saw_pending && !vif.dbg1_packer_pending_eoe)
              saw_clear_after_pending = 1'b1;
          end
        end
      join_none

      run_dma_job(.tag(tag), .opq_words(5), .send_eoe(1'b1),
                  .wready_lag(200), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (!saw_pending)
        `uvm_error(tag, "dbg1_packer_pending_eoe never asserted")
      if (!saw_clear_after_pending)
        `uvm_error(tag, "dbg1_packer_pending_eoe did not clear after flush")
    endtask

    task run_writer_state_cycle_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit [3:0] prev_state;
      bit saw_program;
      bit saw_aw;
      bit saw_w;
      bit saw_b;
      bit saw_report;

      stop_monitor = 1'b0;
      prev_state = vif.dbg1_writer_state;
      saw_program = 1'b0;
      saw_aw = 1'b0;
      saw_w = 1'b0;
      saw_b = 1'b0;
      saw_report = 1'b0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n !== 1'b1)
              continue;
            case (vif.dbg1_writer_state)
              4'd1: saw_program = 1'b1;
              4'd2: saw_aw = 1'b1;
              4'd3: saw_w = 1'b1;
              4'd4: saw_b = 1'b1;
              4'd5: saw_report = 1'b1;
              default: begin end
            endcase
            if (vif.dbg1_writer_state !== prev_state) begin
              if (!(((prev_state == 4'd0) && (vif.dbg1_writer_state == 4'd1)) ||
                    ((prev_state == 4'd1) && (vif.dbg1_writer_state == 4'd2)) ||
                    ((prev_state == 4'd2) && (vif.dbg1_writer_state == 4'd3)) ||
                    ((prev_state == 4'd3) && (vif.dbg1_writer_state == 4'd4)) ||
                    ((prev_state == 4'd4) && (vif.dbg1_writer_state == 4'd2)) ||
                    ((prev_state == 4'd4) && (vif.dbg1_writer_state == 4'd5)) ||
                    ((prev_state == 4'd5) && (vif.dbg1_writer_state == 4'd0))))
                `uvm_error(tag, $sformatf("illegal writer state hop %0d->%0d",
                                          prev_state, vif.dbg1_writer_state))
              prev_state = vif.dbg1_writer_state;
            end
          end
        end
      join_none

      run_dma_job(.tag(tag), .seg0_span(64'h1000), .opq_words(1024),
                  .send_eoe(1'b0), .awready_lag(8), .wready_lag(2),
                  .bvalid_lag(12), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(500000));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (!(saw_program && saw_aw && saw_w && saw_b && saw_report))
        `uvm_error(tag, "writer FSM did not visit all expected states")
    endtask

    task run_dbg2_slot5_padding_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit saw_mask;

      stop_monitor = 1'b0;
      saw_mask = 1'b0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if ((env.debug_level >= 2) && vif.dbg2_writer_meta_valid) begin
              if (vif.dbg2_writer_meta_valid_mask !== 8'h1f)
                `uvm_error(tag, $sformatf("dbg2 valid mask got=0x%02h expected=0x1f",
                                          vif.dbg2_writer_meta_valid_mask))
              saw_mask = 1'b1;
            end
          end
        end
      join_none

      run_packer_flush_slot_case(.tag(tag), .slot_words(5),
                                 .sqe_id(sqe_id),
                                 .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if ((env.debug_level >= 2) && !saw_mask)
        `uvm_error(tag, "DEBUG2 slot-5 mask was not observed")
    endtask

    task run_dbg2_halt_residual_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_halt_count_job(.tag(tag), .dropped_words(4),
                         .sqe_id(sqe_id), .sequence_no(sequence_no));
      if (env.debug_level >= 2) begin
        if (env.scb.ignored_opq_count != vif.cnt_halt)
          `uvm_error(tag, $sformatf("ignored OPQ got=%0d expected cnt_halt=%0d",
                                    env.scb.ignored_opq_count, vif.cnt_halt))
        if ((env.scb.opq_count - env.scb.dbg2_emit_count) != vif.cnt_halt)
          `uvm_error(tag, $sformatf("dbg2 residual got=%0d expected cnt_halt=%0d",
                                    env.scb.opq_count - env.scb.dbg2_emit_count,
                                    vif.cnt_halt))
      end
    endtask

    task run_dbg2_hit_id_wrap_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      next_lineage_id = 32'h0000_fffc;
      run_dma_job(.tag(tag), .opq_words(16), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      if (next_lineage_id <= 32'h0001_0000)
        `uvm_error(tag, "hit_id stream did not cross the 16-bit wrap point")
      if ((env.debug_level >= 2) && (env.scb.dbg2_emit_count != 16))
        `uvm_error(tag, $sformatf("dbg2 emit count got=%0d expected=16",
                                  env.scb.dbg2_emit_count))
    endtask

    task run_dbg2_monotonic_sequence_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit seen_first;
      bit [31:0] prev_seq;
      int unsigned seen_count;

      stop_monitor = 1'b0;
      seen_first = 1'b0;
      prev_seq = 32'h0;
      seen_count = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if ((env.debug_level >= 2) && vif.dbg2_writer_meta_valid) begin
              for (int unsigned slot = 0; slot < RDMA_DMA_OPQ_PER_BEAT; slot++) begin
                if (vif.dbg2_writer_meta_valid_mask[slot]) begin
                  bit [31:0] cur_seq;
                  cur_seq = vif.dbg2_writer_meta_sequence_no[slot*32 +: 32];
                  if (seen_first && (cur_seq <= prev_seq))
                    `uvm_error(tag, $sformatf("sequence_no not monotonic got=%0d prev=%0d",
                                              cur_seq, prev_seq))
                  prev_seq = cur_seq;
                  seen_first = 1'b1;
                  seen_count++;
                end
              end
            end
          end
        end
      join_none

      expect_simple_status_job(64'd128, 32'd128, 32'd0,
                               single_seg_eoe_status(),
                               single_seg_status_mask(), sqe_id);
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      for (int unsigned idx = 0; idx < 32; idx++) begin
        drive_direct_opq_word({8'h00, sequence_no[15:0], idx[7:0]},
                              idx == 31, sequence_no + idx,
                              next_lineage_id + idx + 1);
      end
      next_lineage_id += 32;
      wait_for_done(300000);
      wait_cycles(2);
      stop_monitor = 1'b1;
      wait_cycles(1);
      if ((env.debug_level >= 2) && (seen_count != 32))
        `uvm_error(tag, $sformatf("monotonic sequence samples got=%0d expected=32",
                                  seen_count))
    endtask

    task run_dbg2_monotonic_source_ts_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit seen_first;
      bit [63:0] prev_ts;
      int unsigned seen_count;

      stop_monitor = 1'b0;
      seen_first = 1'b0;
      prev_ts = 64'h0;
      seen_count = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if ((env.debug_level >= 2) && vif.dbg2_writer_meta_valid) begin
              for (int unsigned slot = 0; slot < RDMA_DMA_OPQ_PER_BEAT; slot++) begin
                if (vif.dbg2_writer_meta_valid_mask[slot]) begin
                  bit [63:0] cur_ts;
                  cur_ts = vif.dbg2_writer_meta_source_ts[slot*64 +: 64];
                  if (seen_first && (cur_ts <= prev_ts))
                    `uvm_error(tag, $sformatf("source_ts not monotonic got=%0d prev=%0d",
                                              cur_ts, prev_ts))
                  prev_ts = cur_ts;
                  seen_first = 1'b1;
                  seen_count++;
                end
              end
            end
          end
        end
      join_none

      next_lineage_id = 32'h0000_2000;
      run_dma_job(.tag(tag), .opq_words(32), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if ((env.debug_level >= 2) && (seen_count != 32))
        `uvm_error(tag, $sformatf("monotonic source_ts samples got=%0d expected=32",
                                  seen_count))
    endtask

    task run_dbg2_inert_dbg1_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit saw_dbg2_sidecar;

      stop_monitor = 1'b0;
      saw_dbg2_sidecar = 1'b0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if ((vif.dbg2_writer_meta_valid !== 1'b0) ||
                (vif.dbg2_writer_meta_valid_mask !== '0))
              saw_dbg2_sidecar = 1'b1;
          end
        end
      join_none

      run_dma_job(.tag(tag), .opq_words(32), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if ((env.debug_level == 1) && saw_dbg2_sidecar)
        `uvm_error(tag, "DEBUG2 sidecar was not inert in DEBUG1")
      if ((env.debug_level >= 2) && (env.scb.dbg2_emit_count == 0))
        `uvm_error(tag, "DEBUG2 sidecar did not emit in DEBUG2")
    endtask

    task run_random_span_grid_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [63:0] span_grid [5];
      span_grid[0] = 64'h0000_0000_0000_1000;
      span_grid[1] = 64'h0000_0000_0000_2000;
      span_grid[2] = 64'h0000_0000_0000_4000;
      span_grid[3] = 64'h0000_0000_0000_8000;
      span_grid[4] = 64'h0000_0000_0001_0000;
      for (int unsigned idx = 0; idx < 32; idx++) begin
        bit two_seg_v;
        two_seg_v = (idx % 3) == 1;
        run_dma_job(.tag($sformatf("%s_iter%0d", tag, idx)),
                    .seg0_span(span_grid[(idx * 7) % 5]),
                    .seg1_span(two_seg_v ? span_grid[(idx * 11 + 2) % 5] :
                                           64'h0),
                    .opq_words(64 + ((idx * 37) % 512)),
                    .send_eoe(1'b1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .idle_after_each(idx % 3),
                    .timeout_cycles(400000));
      end
      check_conservation(tag);
    endtask

    task run_random_eoe_slot_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < 16; idx++) begin
        int unsigned slot_words;
        pulse_clear_counters();
        slot_words = 1 + ((idx * 5) % RDMA_DMA_OPQ_PER_BEAT);
        run_packer_flush_slot_case(.tag($sformatf("%s_slot%0d", tag, idx)),
                                   .slot_words(slot_words),
                                   .sqe_id(sqe_id + idx[15:0]),
                                   .sequence_no(sequence_no + idx));
      end
    endtask

    task run_random_two_segment_transition_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < 16; idx++) begin
        run_dma_job(.tag($sformatf("%s_iter%0d", tag, idx)),
                    .seg0_span(64'h1000), .seg1_span(64'h1000),
                    .opq_words(1025 + ((idx * 37) % 512)),
                    .send_eoe(1'b1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .idle_after_each(idx % 4),
                    .timeout_cycles(500000));
        check_status_bit(tag, "status[SEG_BOUNDARY_HIT]",
                         RDMA_DMA_ST_SEG_BOUNDARY_HIT, 1'b1);
      end
      check_conservation(tag);
    endtask

    task run_random_burst_size_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < 32; idx++) begin
        run_aw_observed_job(.tag($sformatf("%s_iter%0d", tag, idx)),
                            .obs_seg0_addr(64'h0000_0000_0010_0000 +
                                           (64'(idx % 8) << 12)),
                            .obs_seg0_span(64'h0000_0000_0000_4000),
                            .obs_words(16 + ((idx * 29) % 768)),
                            .obs_send_eoe(1'b1),
                            .expected_aw_count(0),
                            .check_first_aw(1'b0),
                            .obs_idle_after_each(idx % 5),
                            .obs_wready_lag((idx % 4) == 0 ? 3 : 0),
                            .obs_bvalid_lag((idx % 5) == 0 ? 24 : 1),
                            .sqe_id(sqe_id + idx[15:0]),
                            .sequence_no(sequence_no + idx),
                            .timeout_cycles(500000));
      end
      check_conservation(tag);
    endtask

    task run_fifo_above_threshold_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned max_level;

      stop_monitor = 1'b0;
      max_level = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.dbg1_fifo_level > max_level)
              max_level = vif.dbg1_fifo_level;
          end
        end
      join_none
      run_halt_count_job(.tag(tag), .dropped_words(8),
                         .sqe_id(sqe_id), .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (max_level != 192)
        `uvm_error(tag, $sformatf("fifo max_level got=%0d expected clamp at 192",
                                  max_level))
      if (vif.cnt_halt < 8)
        `uvm_error(tag, $sformatf("cnt_halt got=%0d expected at least 8",
                                  vif.cnt_halt))
    endtask

    task run_fifo_overfill_guard_case(
      input string tag,
      input int unsigned attempted_entries,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned max_level;
      int unsigned dropped_words;

      stop_monitor = 1'b0;
      max_level = 0;
      dropped_words = attempted_entries * RDMA_DMA_OPQ_PER_BEAT;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.dbg1_fifo_level > max_level)
              max_level = vif.dbg1_fifo_level;
          end
        end
      join_none

      run_halt_count_job(.tag(tag), .dropped_words(dropped_words),
                         .sqe_id(sqe_id), .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (max_level != 192)
        `uvm_error(tag, $sformatf("fifo max_level got=%0d expected guard at 192",
                                  max_level))
      if (vif.cnt_halt < dropped_words[31:0])
        `uvm_error(tag, $sformatf("cnt_halt got=%0d expected at least %0d",
                                  vif.cnt_halt, dropped_words))
    endtask

    task run_fifo_recovery_after_halt_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [31:0] halt_after_inject;

      run_halt_count_job(.tag({tag, "_halt"}), .dropped_words(16),
                         .sqe_id(sqe_id), .sequence_no(sequence_no));
      halt_after_inject = vif.cnt_halt;
      run_dma_job(.tag({tag, "_clean"}), .opq_words(16), .send_eoe(1'b1),
                  .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd1),
                  .timeout_cycles(300000));
      check_u32_equal(tag, "cnt_halt after recovery job",
                      vif.cnt_halt, halt_after_inject);
      if (env.scb.job_done_count < 2)
        `uvm_error(tag, "recovery job did not complete after halt drain")
    endtask

    task run_fifo_simultaneous_rw_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit [8:0] prev_level;
      int unsigned steady_samples;
      int unsigned max_level;

      stop_monitor = 1'b0;
      prev_level = vif.dbg1_fifo_level;
      steady_samples = 0;
      max_level = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n !== 1'b1)
              continue;
            if (vif.dbg1_fifo_level > max_level)
              max_level = vif.dbg1_fifo_level;
            if (vif.m_axi_wvalid && vif.m_axi_wready &&
                vif.s_axis_opq_tvalid && vif.s_axis_opq_tready &&
                (vif.dbg1_fifo_level == prev_level))
              steady_samples++;
            prev_level = vif.dbg1_fifo_level;
          end
        end
      join_none

      run_dma_job(.tag(tag), .opq_words(512), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(500000));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (steady_samples == 0)
        `uvm_error(tag, "no steady FIFO level sample observed during simultaneous traffic")
      if (max_level >= 192)
        `uvm_error(tag, $sformatf("steady-state fifo max_level got=%0d expected below halt threshold",
                                  max_level))
      if (vif.cnt_halt != 32'd0)
        `uvm_error(tag, $sformatf("cnt_halt got=%0d expected no halt during ready-side traffic",
                                  vif.cnt_halt))
    endtask

    task run_fifo_single_write_burst_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit seen_level [0:16];
      int unsigned accepted_words;
      int unsigned lineage_id;
      bit [15:0] expected_status;
      bit [15:0] status_mask;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      accepted_words = 0;
      lineage_id = next_lineage_id;
      env.axi_cfg.awready_lag = 5000;
      env.axi_cfg.wready_lag = 5000;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0040_0000,
                           64'h0000_0000_0001_0000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);

      for (int unsigned beat_idx = 0; beat_idx < 16; beat_idx++) begin
        for (int unsigned slot_idx = 0; slot_idx < RDMA_DMA_OPQ_PER_BEAT;
             slot_idx++) begin
          accepted_words++;
          lineage_id++;
          drive_direct_opq_word({8'h00, sequence_no[15:0],
                                accepted_words[7:0]},
                                1'b0, sequence_no, lineage_id);
        end
        wait_cycles(1);
        if (vif.dbg1_fifo_level <= 9'd16)
          seen_level[vif.dbg1_fifo_level] = 1'b1;
      end
      for (int unsigned sample = 0; sample < 4; sample++) begin
        wait_cycles(1);
        if (vif.dbg1_fifo_level <= 9'd16)
          seen_level[vif.dbg1_fifo_level] = 1'b1;
      end
      for (int unsigned level = 1; level <= 16; level++) begin
        if (!seen_level[level])
          `uvm_error(tag, $sformatf("fifo write-only level %0d was not observed",
                                    level))
      end

      accepted_words++;
      lineage_id++;
      expect_simple_status_job(64'(accepted_words) * 64'd4,
                               accepted_words[31:0] * 32'd4, 32'd0,
                               expected_status, status_mask, sqe_id);
      drive_direct_opq_word({8'h00, sequence_no[15:0], accepted_words[7:0]},
                            1'b1, sequence_no, lineage_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      wait_for_done(500000);
      wait_cycles(2);
      next_lineage_id = lineage_id;
      env.axi_cfg.bvalid_lag = 1;
    endtask

    task run_fifo_single_read_burst_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit seen_level [0:16];
      int unsigned accepted_words;
      int unsigned lineage_id;
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      bit drained_empty;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      accepted_words = 0;
      lineage_id = next_lineage_id;
      env.axi_cfg.awready_lag = 5000;
      env.axi_cfg.wready_lag = 5000;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0040_0000,
                           64'h0000_0000_0001_0000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);

      for (int unsigned beat_idx = 0; beat_idx < 16; beat_idx++) begin
        for (int unsigned slot_idx = 0; slot_idx < RDMA_DMA_OPQ_PER_BEAT;
             slot_idx++) begin
          accepted_words++;
          lineage_id++;
          drive_direct_opq_word({8'h00, sequence_no[15:0],
                                accepted_words[7:0]},
                                1'b0, sequence_no, lineage_id);
        end
      end
      wait_cycles(2);
      if (vif.dbg1_fifo_level !== 9'd16)
        `uvm_error(tag, $sformatf("prefill level got=%0d expected=16",
                                  vif.dbg1_fifo_level))

      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      drained_empty = 1'b0;
      for (int unsigned cycle = 0; cycle < 20000; cycle++) begin
        @(posedge vif.clk);
        if (vif.dbg1_fifo_level <= 9'd16)
          seen_level[vif.dbg1_fifo_level] = 1'b1;
        if (vif.dbg1_fifo_level == 9'd0) begin
          drained_empty = 1'b1;
          break;
        end
      end
      if (!drained_empty)
        `uvm_error(tag, "fifo did not drain to empty during read-only burst")
      for (int unsigned level = 0; level <= 16; level++) begin
        if (!seen_level[level])
          `uvm_error(tag, $sformatf("fifo read-only level %0d was not observed",
                                    level))
      end

      accepted_words++;
      lineage_id++;
      expect_simple_status_job(64'(accepted_words) * 64'd4,
                               accepted_words[31:0] * 32'd4, 32'd0,
                               expected_status, status_mask, sqe_id);
      drive_direct_opq_word({8'h00, sequence_no[15:0], accepted_words[7:0]},
                            1'b1, sequence_no, lineage_id);
      wait_for_done(500000);
      wait_cycles(2);
      next_lineage_id = lineage_id;
      env.axi_cfg.bvalid_lag = 1;
    endtask

    task preload_counter_input_near_max();
      vif.preload_counter_input_near_max();
    endtask

    task preload_counter_bytes_near_max();
      vif.preload_counter_bytes_near_max();
    endtask

    task preload_counter_bank_max();
      vif.preload_counter_bank_max();
    endtask

    task run_counter_input_saturation_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      preload_counter_input_near_max();
      run_dma_job(.tag(tag), .opq_words(2), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'hffff_ffff);
    endtask

    task run_counter_bytes_saturation_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      preload_counter_bytes_near_max();
      run_dma_job(.tag(tag), .opq_words(16), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'hffff_ffff);
    endtask

    task run_counter_clear_max_case(input string tag);
      preload_counter_bank_max();
      pulse_clear_counters();
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'h0000_0000);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'h0000_0000);
      check_u32_equal(tag, "cnt_halt", vif.cnt_halt, 32'h0000_0000);
      check_u32_equal(tag, "cnt_eoe_observed", vif.cnt_eoe_observed,
                      32'h0000_0000);
    endtask

    task run_writer_align_err_transition_case(
      input string tag,
      input bit [15:0] sqe_id
    );
      bit saw_report;
      saw_report = 1'b0;
      fork
        begin
          for (int unsigned cycle = 0; cycle < 64; cycle++) begin
            @(posedge vif.clk);
            if (vif.dbg1_writer_state === 4'd5)
              saw_report = 1'b1;
          end
        end
      join_none
      run_dma_job(.tag(tag), .seg0_addr(64'h0000_0000_0010_0001),
                  .opq_words(0), .send_eoe(1'b0), .sqe_id(sqe_id),
                  .timeout_cycles(300000));
      wait_cycles(2);
      if (!saw_report)
        `uvm_error(tag, "ALIGN_ERR report state was not observed")
      check_status_bit(tag, "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR,
                       1'b1);
    endtask

    task run_writer_two_segment_program_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned program_visits;

      stop_monitor = 1'b0;
      program_visits = 0;
      fork
        begin
          bit prev_program;
          prev_program = 1'b0;
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if ((vif.dbg1_writer_state === 4'd1) && !prev_program)
              program_visits++;
            prev_program = (vif.dbg1_writer_state === 4'd1);
          end
        end
      join_none

      run_dma_job(.tag(tag), .seg0_span(64'h0000_0000_0000_1000),
                  .seg1_span(64'h0000_0000_0000_1000),
                  .opq_words(2048), .send_eoe(1'b0),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(500000));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (program_visits < 2)
        `uvm_error(tag, $sformatf("PROGRAM visits got=%0d expected>=2",
                                  program_visits))
      check_status_bit(tag, "status[SEG_BOUNDARY_HIT]",
                       RDMA_DMA_ST_SEG_BOUNDARY_HIT, 1'b1);
    endtask

    task run_writer_b_to_aw_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit [3:0] prev_state;
      int unsigned b_to_aw_count;

      stop_monitor = 1'b0;
      prev_state = vif.dbg1_writer_state;
      b_to_aw_count = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if ((prev_state == 4'd4) && (vif.dbg1_writer_state == 4'd2))
              b_to_aw_count++;
            prev_state = vif.dbg1_writer_state;
          end
        end
      join_none

      run_dma_job(.tag(tag), .seg0_span(64'h0000_0000_0000_2000),
                  .opq_words(2048), .send_eoe(1'b0),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(500000));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (b_to_aw_count == 0)
        `uvm_error(tag, "WR_B to WR_AW transition was not observed")
    endtask

    task run_writer_stall_case(
      input string tag,
      input bit [3:0] state,
      input int unsigned aw_lag,
      input int unsigned w_lag,
      input int unsigned b_lag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned hold_count;
      int unsigned max_hold;

      stop_monitor = 1'b0;
      hold_count = 0;
      max_hold = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.dbg1_writer_state === state) begin
              hold_count++;
              if (hold_count > max_hold)
                max_hold = hold_count;
            end else begin
              hold_count = 0;
            end
          end
        end
      join_none

      run_dma_job(.tag(tag), .opq_words(128), .send_eoe(1'b1),
                  .awready_lag(aw_lag), .wready_lag(w_lag),
                  .bvalid_lag(b_lag), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(500000));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (max_hold < 64)
        `uvm_error(tag, $sformatf("state %0d max hold got=%0d expected>=64",
                                  state, max_hold))
    endtask

    task run_job_req_opq_idle_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stayed_waiting;
      bit [15:0] expected_status;
      bit [15:0] status_mask;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd32, 32'd32, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_for_dbg1_state(tag, 4'd2);
      stayed_waiting = 1'b1;
      for (int unsigned cycle = 0; cycle < 128; cycle++) begin
        @(posedge vif.clk);
        if ((vif.dbg1_writer_state !== 4'd2) ||
            vif.m_axi_awvalid || vif.m_axi_wvalid || vif.job_done)
          stayed_waiting = 1'b0;
      end
      if (!stayed_waiting)
        `uvm_error(tag, "idle OPQ job did not wait in WR_ISSUING_AW")
      check_u32_equal(tag, "cnt_input_w before OPQ", vif.cnt_input_w,
                      32'h0000_0000);
      drive_direct_words(8, 1'b1, sequence_no, next_lineage_id);
      wait_for_done(300000);
      wait_cycles(2);
    endtask

    task drive_opq_attempts_without_wait(
      input int unsigned word_count,
      input bit mark_eoe_on_last,
      input bit [31:0] sequence_no,
      input int unsigned hit_id_base = 0
    );
      for (int unsigned idx = 0; idx < word_count; idx++) begin
        @(negedge vif.clk);
        vif.s_axis_opq_tdata <= {4'h0, 8'h00, sequence_no[15:0], idx[7:0]};
        vif.s_axis_opq_tvalid <= 1'b1;
        vif.s_axis_opq_tlast <= mark_eoe_on_last && (idx + 1 == word_count);
        vif.s_axis_opq_tuser <= {1'b0, (idx == 0)};
        vif.dbg2_meta_valid <= 1'b1;
        vif.dbg2_meta_lane <= 4'h0;
        vif.dbg2_meta_hit_id <= hit_id_base + idx + 1;
        vif.dbg2_meta_source_ts <= hit_id_base + idx + 1;
        vif.dbg2_meta_sequence_no <= sequence_no;
        @(posedge vif.clk);
      end
      @(negedge vif.clk);
      vif.s_axis_opq_tvalid <= 1'b0;
      vif.s_axis_opq_tlast <= 1'b0;
      vif.s_axis_opq_tuser <= '0;
      vif.dbg2_meta_valid <= 1'b0;
      vif.dbg2_meta_lane <= '0;
      vif.dbg2_meta_hit_id <= '0;
      vif.dbg2_meta_source_ts <= '0;
      vif.dbg2_meta_sequence_no <= '0;
      next_lineage_id += word_count;
    endtask

    task run_job_req_immediate_opq_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit seen_req;
      bit saw_first_aw;
      int unsigned latency_cycles;
      int unsigned cycle_count;
      bit [15:0] expected_status;
      bit [15:0] status_mask;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd32, 32'd32, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      stop_monitor = 1'b0;
      seen_req = 1'b0;
      saw_first_aw = 1'b0;
      latency_cycles = 0;
      cycle_count = 0;

      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.job_req) begin
              seen_req = 1'b1;
              cycle_count = 0;
            end else if (seen_req && !saw_first_aw) begin
              cycle_count++;
            end
            if (seen_req && !saw_first_aw &&
                vif.m_axi_awvalid && vif.m_axi_awready) begin
              saw_first_aw = 1'b1;
              latency_cycles = cycle_count;
            end
          end
        end
      join_none

      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      drive_direct_words(8, 1'b1, sequence_no, next_lineage_id);

      wait_for_done(300000);
      wait_cycles(2);
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (!saw_first_aw)
        `uvm_error(tag, "first AW was not observed after immediate OPQ burst")
      if (latency_cycles > 64)
        `uvm_error(tag, $sformatf(
          "first AW latency got=%0d cycles expected<=64", latency_cycles))
    endtask

    task run_opq_before_job_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [31:0] input_before;
      bit [31:0] eoe_before;
      bit [31:0] bytes_before;

      input_before = vif.cnt_input_w;
      eoe_before = vif.cnt_eoe_observed;
      bytes_before = vif.cnt_bytes_written;
      env.scb.ignore_next_opq(100);
      drive_opq_attempts_without_wait(100, 1'b1, sequence_no,
                                      next_lineage_id);
      wait_cycles(4);
      check_u32_equal(tag, "cnt_input_w before job", vif.cnt_input_w,
                      input_before);
      check_u32_equal(tag, "cnt_eoe_observed before job",
                      vif.cnt_eoe_observed, eoe_before);
      check_u32_equal(tag, "cnt_bytes_written before job",
                      vif.cnt_bytes_written, bytes_before);
      if (env.scb.aw_count != 0 || env.scb.w_count != 0 ||
          env.scb.job_done_count != 0)
        `uvm_error(tag, "pre-job OPQ attempts produced AXI or job activity")

      run_dma_job(.tag({tag, "_late_job"}), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no + 32'd100),
                  .timeout_cycles(300000));
    endtask

    task run_high_half_address_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_aw_observed_job(.tag(tag),
                          .obs_seg0_addr(64'hffff_ffff_0000_0000),
                          .obs_seg0_span(64'h0000_0000_0000_1000),
                          .obs_words(8),
                          .obs_send_eoe(1'b1),
                          .expected_first_aw(64'hffff_ffff_0000_0000),
                          .sqe_id(sqe_id),
                          .sequence_no(sequence_no),
                          .timeout_cycles(300000));
    endtask

    task run_opq_after_done_ignored_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [31:0] input_after_done;
      bit [31:0] eoe_after_done;
      bit [31:0] bytes_after_done;

      run_dma_job(.tag({tag, "_job0"}), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      input_after_done = vif.cnt_input_w;
      eoe_after_done = vif.cnt_eoe_observed;
      bytes_after_done = vif.cnt_bytes_written;
      env.scb.ignore_next_opq(16);
      drive_opq_attempts_without_wait(16, 1'b1, sequence_no + 32'd50,
                                      next_lineage_id);
      wait_cycles(4);
      check_u32_equal(tag, "cnt_input_w after ignored tail",
                      vif.cnt_input_w, input_after_done);
      check_u32_equal(tag, "cnt_eoe_observed after ignored tail",
                      vif.cnt_eoe_observed, eoe_after_done);
      check_u32_equal(tag, "cnt_bytes_written after ignored tail",
                      vif.cnt_bytes_written, bytes_after_done);
      check_u32_equal(tag, "job_done_count before next job",
                      env.scb.job_done_count, 32'd1);

      run_dma_job(.tag({tag, "_job1"}), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd100),
                  .timeout_cycles(300000));
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count, 32'd2);
    endtask

    task run_random_eoe_throttled_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < 16; idx++) begin
        run_dma_job(.tag($sformatf("%s_iter%0d", tag, idx)),
                    .opq_words(1 + ((idx * 17) % 96)),
                    .send_eoe(1'b1),
                    .wready_lag((idx % 4) == 0 ? 9 : 2),
                    .bvalid_lag((idx % 3) == 0 ? 48 : 7),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .idle_after_each(idx % 5),
                    .timeout_cycles(500000));
      end
      check_conservation(tag);
    endtask

    task run_random_alignment_mix_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < 32; idx++) begin
        bit invalid_alignment;
        invalid_alignment = (idx % 2) == 0;
        run_dma_job(.tag($sformatf("%s_iter%0d", tag, idx)),
                    .seg0_addr(invalid_alignment ?
                               (64'h0000_0000_0010_0001 + idx) :
                               (64'h0000_0000_0030_0000 +
                                (64'(idx) << 12))),
                    .opq_words(invalid_alignment ? 0 :
                               (8 + ((idx * 3) % 24))),
                    .send_eoe(!invalid_alignment),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(300000));
        check_status_bit($sformatf("%s_iter%0d", tag, idx),
                         "status[ALIGN_ERR]",
                         RDMA_DMA_ST_ALIGN_ERR, invalid_alignment);
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count, 32'd32);
    endtask

    task run_random_multi_event_drains_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < 16; idx++) begin
        int unsigned event_count;
        event_count = 1 + ((idx * 5) % 8);
        pulse_clear_counters();
        run_dma_multi_event_job(.tag($sformatf("%s_iter%0d", tag, idx)),
                                .event_count(event_count),
                                .words_per_event(2 + (idx % 7)),
                                .gap_cycles(idx % 3),
                                .sqe_id(sqe_id + idx[15:0]),
                                .sequence_no(sequence_no + idx),
                                .bvalid_lag(200),
                                .timeout_cycles(700000));
        check_u32_equal($sformatf("%s_iter%0d", tag, idx),
                        "cnt_eoe_observed",
                        vif.cnt_eoe_observed, event_count[31:0]);
      end
    endtask

    task run_random_span_eoe_throttle_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < 16; idx++) begin
        bit two_seg_v;
        bit send_eoe_v;
        bit [63:0] seg0_span_v;
        bit [63:0] seg1_span_v;
        int unsigned opq_words_v;
        two_seg_v = (idx % 4) == 1;
        send_eoe_v = (idx % 5) != 0;
        seg0_span_v = (idx % 3) == 0 ? 64'h2000 : 64'h1000;
        seg1_span_v = two_seg_v ? 64'h1000 : 64'h0;
        opq_words_v = send_eoe_v ? (8 + ((idx * 53) % 256)) :
                      int'((seg0_span_v + seg1_span_v) >> 2);
        run_dma_job(.tag($sformatf("%s_iter%0d", tag, idx)),
                    .seg0_span(seg0_span_v),
                    .seg1_span(seg1_span_v),
                    .opq_words(opq_words_v),
                    .send_eoe(send_eoe_v),
                    .awready_lag((idx % 6) == 0 ? 17 : 0),
                    .wready_lag((idx % 4) == 0 ? 5 : 0),
                    .bvalid_lag((idx % 7) == 0 ? 64 : 1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .idle_after_each(idx % 4),
                    .timeout_cycles(600000));
      end
      check_conservation(tag);
    endtask

    task run_first_event_ts_capture_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit captured_eoe;
      bit [63:0] expected_first_ts;
      bit [15:0] expected_status;
      bit [15:0] status_mask;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd16, 32'd16, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      stop_monitor = 1'b0;
      captured_eoe = 1'b0;
      expected_first_ts = 64'h0;

      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (!captured_eoe && vif.s_axis_opq_tvalid &&
                vif.s_axis_opq_tready && vif.s_axis_opq_tlast) begin
              captured_eoe = 1'b1;
              expected_first_ts = vif.packer_cycle_count() + 64'd1;
            end
          end
        end
      join_none

      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(4, 1'b1, sequence_no, next_lineage_id);
      wait_for_done(300000);
      wait_cycles(2);
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (!captured_eoe)
        `uvm_error(tag, "first OPQ tlast cycle was not captured")
      check_u64_equal(tag, "job_first_event_ts",
                      vif.job_first_event_ts, expected_first_ts);
      check_u64_equal(tag, "job_last_event_ts",
                      vif.job_last_event_ts, expected_first_ts);
    endtask

    task run_first_last_ts_equal_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag(tag), .opq_words(8), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      check_u64_equal(tag, "job_first_event_ts", vif.job_first_event_ts,
                      vif.job_last_event_ts);
    endtask

    task run_last_ts_later_event_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_multi_event_job(.tag(tag), .event_count(3),
                              .words_per_event(4), .gap_cycles(6),
                              .sqe_id(sqe_id), .sequence_no(sequence_no),
                              .bvalid_lag(200),
                              .timeout_cycles(500000));
      if (vif.job_last_event_ts <= vif.job_first_event_ts)
        `uvm_error(tag, "last_event_ts did not advance past first_event_ts")
    endtask

    task run_two_jobs_clean_fifo_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag({tag, "_job0"}), .opq_words(64),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      check_u32_equal(tag, "fifo level after job0", vif.dbg1_fifo_level,
                      32'd0);
      if (vif.dbg1_packer_slot_idx !== 4'h0 ||
          vif.dbg1_packer_pending_eoe !== 1'b0)
        `uvm_error(tag, "packer was not empty after job0 completion")
      run_dma_job(.tag({tag, "_job1"}), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd100),
                  .timeout_cycles(300000));
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count, 32'd2);
    endtask

    task run_three_back_to_back_jobs_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag({tag, "_job0"}), .seg0_span(64'h1000),
                  .opq_words(8), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      run_dma_job(.tag({tag, "_job1"}), .seg0_span(64'h1000),
                  .seg1_span(64'h1000), .opq_words(1032),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd100),
                  .timeout_cycles(500000));
      run_dma_job(.tag({tag, "_job2"}), .seg0_span(64'h1000),
                  .opq_words(1024), .send_eoe(1'b0),
                  .sqe_id(sqe_id + 16'd2),
                  .sequence_no(sequence_no + 32'd200),
                  .timeout_cycles(500000));
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count, 32'd3);
      check_conservation(tag);
    endtask

    task run_two_segment_then_single_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag({tag, "_job0"}), .seg0_span(64'h1000),
                  .seg1_span(64'h1000), .opq_words(1032),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no),
                  .timeout_cycles(500000));
      check_status_bit({tag, "_job0"}, "status[SEG_BOUNDARY_HIT]",
                       RDMA_DMA_ST_SEG_BOUNDARY_HIT, 1'b1);
      run_dma_job(.tag({tag, "_job1"}), .seg0_span(64'h1000),
                  .opq_words(16), .send_eoe(1'b1),
                  .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd100),
                  .timeout_cycles(300000));
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count, 32'd2);
      check_conservation(tag);
    endtask

    task run_align_error_then_clean_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag({tag, "_align"}), .seg0_addr(64'h0000_0000_0010_0001),
                  .opq_words(0), .send_eoe(1'b0),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      check_status_bit({tag, "_align"}, "status[ALIGN_ERR]",
                       RDMA_DMA_ST_ALIGN_ERR, 1'b1);
      run_dma_job(.tag({tag, "_clean"}), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd100),
                  .timeout_cycles(300000));
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count, 32'd2);
      check_status_bit({tag, "_clean"}, "status[ALIGN_ERR]",
                       RDMA_DMA_ST_ALIGN_ERR, 1'b0);
      check_status_bit({tag, "_clean"}, "status[EOE]",
                       RDMA_DMA_ST_EOE, 1'b1);
    endtask

    task run_error_align_refusal_case(
      input string tag,
      input bit [63:0] seg0_addr,
      input bit [63:0] seg0_span,
      input bit [63:0] seg1_addr,
      input bit [63:0] seg1_span,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned aw_before;
      int unsigned w_before;

      aw_before = env.scb.aw_count;
      w_before = env.scb.w_count;
      run_dma_job(.tag(tag), .seg0_addr(seg0_addr), .seg0_span(seg0_span),
                  .seg1_addr(seg1_addr), .seg1_span(seg1_span),
                  .opq_words(0), .send_eoe(1'b0), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      check_status_bit(tag, "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR,
                       1'b1);
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd0);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd0);
      if ((env.scb.aw_count != aw_before) || (env.scb.w_count != w_before))
        `uvm_error(tag, "ALIGN_ERR job unexpectedly issued AXI writes")
    endtask

    task run_error_single_segment_legal_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag(tag), .seg1_span(64'h0), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      check_status_bit(tag, "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR,
                       1'b0);
      check_status_bit(tag, "status[SEG0_ONLY]", RDMA_DMA_ST_SEG0_ONLY,
                       1'b1);
      check_status_bit(tag, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd8);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd32);
    endtask

    task run_error_align_after_valid_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [31:0] cnt_input_before;
      bit [31:0] cnt_bytes_before;
      int unsigned aw_before;
      int unsigned w_before;

      run_dma_job(.tag({tag, "_valid"}), .opq_words(16), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      cnt_input_before = vif.cnt_input_w;
      cnt_bytes_before = vif.cnt_bytes_written;
      aw_before = env.scb.aw_count;
      w_before = env.scb.w_count;
      run_dma_job(.tag({tag, "_align"}), .seg0_addr(64'h0000_0000_0010_0001),
                  .opq_words(0), .send_eoe(1'b0),
                  .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd100),
                  .timeout_cycles(300000));
      check_status_bit({tag, "_align"}, "status[ALIGN_ERR]",
                       RDMA_DMA_ST_ALIGN_ERR, 1'b1);
      check_u32_equal(tag, "cnt_input_w after ALIGN_ERR", vif.cnt_input_w,
                      cnt_input_before);
      check_u32_equal(tag, "cnt_bytes_written after ALIGN_ERR",
                      vif.cnt_bytes_written, cnt_bytes_before);
      if ((env.scb.aw_count != aw_before) || (env.scb.w_count != w_before))
        `uvm_error(tag, "post-valid ALIGN_ERR job changed AXI counts")
    endtask

    task run_error_consecutive_align_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < 5; idx++) begin
        run_dma_job(.tag($sformatf("%s_align%0d", tag, idx)),
                    .seg0_addr(64'h0000_0000_0010_0001 + idx),
                    .opq_words(0), .send_eoe(1'b0),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx[31:0]),
                    .timeout_cycles(300000));
        check_status_bit($sformatf("%s_align%0d", tag, idx),
                         "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR, 1'b1);
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count, 32'd5);
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd0);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd0);
      if ((env.scb.aw_count != 0) || (env.scb.w_count != 0))
        `uvm_error(tag, "consecutive ALIGN_ERR jobs issued AXI writes")
    endtask

    task run_error_idle_reset_case(input string tag);
      apply_midrun_reset();
      check_reset_defaults(tag);
    endtask

    task run_error_wait_awvalid(input string tag);
      bit saw_awvalid;
      saw_awvalid = 1'b0;
      for (int unsigned cycle = 0; cycle < 512; cycle++) begin
        @(posedge vif.clk);
        if (vif.m_axi_awvalid) begin
          saw_awvalid = 1'b1;
          break;
        end
      end
      if (!saw_awvalid)
        `uvm_error(tag, "m_axi_awvalid was not observed before reset")
    endtask

    task run_error_reset_writer_state_case(
      input string tag,
      input bit [3:0] target_state,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no,
      input bit require_awvalid = 1'b0
    );
      env.axi_cfg.awready_lag = (target_state == 4'd2) ? 64 : 0;
      env.axi_cfg.wready_lag = (target_state == 4'd3) ? 64 : 0;
      env.axi_cfg.bvalid_lag = (target_state == 4'd4) ? 64 : 1;
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      if (target_state == 4'd1) begin
        if (vif.dbg1_writer_state !== 4'd1)
          `uvm_error(tag, $sformatf("WR_PROGRAMMING not observed, got=%0d",
                                    vif.dbg1_writer_state))
      end else begin
        wait_cycles(2);
        drive_direct_words(64, 1'b1, sequence_no, next_lineage_id);
        wait_for_dbg1_state(tag, target_state);
        if (require_awvalid)
          run_error_wait_awvalid(tag);
      end
      apply_midrun_reset();
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      check_reset_defaults(tag);
    endtask

    task run_error_reset_on_job_req_case(input string tag);
      @(negedge vif.clk);
      vif.job_seg0_addr <= 64'h0000_0000_0010_0000;
      vif.job_seg0_span <= 64'h0000_0000_0000_1000;
      vif.job_seg1_addr <= 64'h0000_0000_0000_0000;
      vif.job_seg1_span <= 64'h0000_0000_0000_0000;
      vif.job_sqe_id <= 16'h0222;
      vif.job_opcode <= 16'h0001;
      vif.job_req <= 1'b1;
      vif.reset_n <= 1'b0;
      repeat (4) @(posedge vif.clk);
      @(negedge vif.clk);
      vif.job_req <= 1'b0;
      vif.reset_n <= 1'b1;
      repeat (8) @(posedge vif.clk);
      env.scb.reset_model();
      env.scb.configure_case(case_id, scorecard_path, env.debug_level);
      check_reset_defaults(tag);
    endtask

    task run_error_reset_on_job_done_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd32, 32'd32, 32'd0,
                               expected_status, status_mask, sqe_id);
      vif.preload_counter_input_near_max();
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(8, 1'b1, sequence_no, next_lineage_id);
      wait_for_done(300000);
      @(negedge vif.clk);
      vif.reset_n <= 1'b0;
      repeat (4) @(posedge vif.clk);
      @(negedge vif.clk);
      vif.reset_n <= 1'b1;
      repeat (8) @(posedge vif.clk);
      env.scb.reset_model();
      env.scb.configure_case(case_id, scorecard_path, env.debug_level);
      check_reset_defaults(tag);
    endtask

    task run_error_reset_pulse_train_case(input string tag);
      for (int unsigned idx = 0; idx < 10; idx++) begin
        @(negedge vif.clk);
        vif.reset_n <= 1'b0;
        repeat (2) @(posedge vif.clk);
        @(negedge vif.clk);
        vif.reset_n <= 1'b1;
        repeat (2) @(posedge vif.clk);
      end
      env.scb.reset_model();
      env.scb.configure_case(case_id, scorecard_path, env.debug_level);
      check_reset_defaults(tag);
    endtask

    task run_error_long_reset_case(input string tag);
      @(negedge vif.clk);
      vif.reset_n <= 1'b0;
      repeat (1000) @(posedge vif.clk);
      @(negedge vif.clk);
      vif.reset_n <= 1'b1;
      repeat (8) @(posedge vif.clk);
      env.scb.reset_model();
      env.scb.configure_case(case_id, scorecard_path, env.debug_level);
      check_reset_defaults(tag);
    endtask

    task run_error_reset_then_job_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      apply_midrun_reset();
      wait_cycles(1);
      run_dma_job(.tag({tag, "_post_reset"}), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      check_status_bit(tag, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
      check_status_bit(tag, "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR,
                       1'b0);
    endtask

    task run_error_reset_clears_counters_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag({tag, "_pre_reset"}), .opq_words(32),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      if ((vif.cnt_input_w == 32'd0) || (vif.cnt_bytes_written == 32'd0))
        `uvm_error(tag, "pre-reset counters did not accumulate")
      apply_midrun_reset();
      check_reset_defaults(tag);
    endtask

    task run_error_bresp_case(
      input string tag,
      input bit [1:0] bresp,
      input int signed error_index,
      input int unsigned opq_words,
      input bit [63:0] seg0_span = 64'h0000_0000_0000_1000,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      env.axi_cfg.bresp_error_index = error_index;
      env.axi_cfg.bresp_default = axi4_write_pkg::AXI_RESP_OKAY;
      run_dma_job(.tag(tag), .seg0_span(seg0_span), .opq_words(opq_words),
                  .send_eoe(1'b1), .bresp(bresp), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(500000));
      check_status_bit(tag, "status[AXI_ERR]", 6, 1'b1);
      check_status_bit(tag, "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR,
                       1'b0);
    endtask

    task run_error_burst_size_five_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_aw_observed_job(.tag(tag), .obs_words(40), .obs_send_eoe(1'b1),
                          .expected_aw_count(1),
                          .check_first_awlen(1'b1),
                          .expected_first_awlen(4),
                          .sqe_id(sqe_id),
                          .sequence_no(sequence_no),
                          .timeout_cycles(300000));
    endtask

    task run_error_tlast_without_tvalid_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [31:0] input_before;
      input_before = vif.cnt_input_w;
      pulse_zero_eoe();
      wait_cycles(4);
      check_u32_equal(tag, "cnt_input_w after ignored tlast",
                      vif.cnt_input_w, input_before);
      if (env.scb.aw_count != 0 || env.scb.w_count != 0)
        `uvm_error(tag, "tlast without tvalid produced AXI traffic")
      run_dma_job(.tag({tag, "_clean"}), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
    endtask

    task run_error_sop_mid_event_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd12, 32'd12, 32'd0,
                               expected_status, status_mask, sqe_id);
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_opq_word({8'h00, sequence_no[15:0], 8'h00},
                            1'b0, sequence_no, next_lineage_id + 1);
      @(negedge vif.clk);
      vif.s_axis_opq_tdata <= {4'h0, 8'h00, sequence_no[15:0], 8'h01};
      vif.s_axis_opq_tvalid <= 1'b1;
      vif.s_axis_opq_tlast <= 1'b0;
      vif.s_axis_opq_tuser <= 2'b01;
      vif.dbg2_meta_valid <= 1'b1;
      vif.dbg2_meta_lane <= 4'h0;
      vif.dbg2_meta_hit_id <= next_lineage_id + 2;
      vif.dbg2_meta_source_ts <= next_lineage_id + 2;
      vif.dbg2_meta_sequence_no <= sequence_no;
      do begin
        @(posedge vif.clk);
      end while (vif.s_axis_opq_tready !== 1'b1);
      @(negedge vif.clk);
      vif.s_axis_opq_tvalid <= 1'b0;
      vif.s_axis_opq_tuser <= '0;
      vif.dbg2_meta_valid <= 1'b0;
      drive_direct_opq_word({8'h00, sequence_no[15:0], 8'h02},
                            1'b1, sequence_no, next_lineage_id + 3);
      next_lineage_id += 3;
      wait_for_done(300000);
      wait_cycles(2);
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd3);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd12);
    endtask

    task run_error_ignored_xdata_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [31:0] input_before;
      input_before = vif.cnt_input_w;
      @(negedge vif.clk);
      vif.s_axis_opq_tdata <= 'x;
      vif.s_axis_opq_tvalid <= 1'b0;
      vif.s_axis_opq_tlast <= 1'b1;
      vif.s_axis_opq_tuser <= 2'b01;
      @(posedge vif.clk);
      @(negedge vif.clk);
      vif.s_axis_opq_tvalid <= 1'b0;
      vif.s_axis_opq_tlast <= 1'b0;
      vif.s_axis_opq_tuser <= '0;
      vif.s_axis_opq_tdata <= '0;
      wait_cycles(4);
      check_u32_equal(tag, "cnt_input_w after ignored X data",
                      vif.cnt_input_w, input_before);
      run_dma_job(.tag({tag, "_clean"}), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
    endtask

    task run_error_single_beat_event_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag(tag), .opq_words(1), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd1);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd4);
      check_status_bit(tag, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
    endtask

    task run_error_overlap_job_req_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd256, 32'd256, 32'd0,
                               expected_status, status_mask, sqe_id);
      env.axi_cfg.wready_lag = 64;
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(64, 1'b1, sequence_no, next_lineage_id);
      wait_for_dbg1_state(tag, 4'd3);
      drive_direct_job_req(64'h0000_0000_0030_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id + 16'd1, 16'h0001, 1);
      env.axi_cfg.wready_lag = 0;
      wait_for_done(300000);
      wait_cycles(2);
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count, 32'd1);
      env.axi_cfg.bvalid_lag = 1;
    endtask

    task run_error_invalid_opcode_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd32, 32'd32, 32'd0,
                               expected_status, status_mask, sqe_id);
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'hdead, 1);
      wait_cycles(2);
      drive_direct_words(8, 1'b1, sequence_no, next_lineage_id);
      wait_for_done(300000);
      wait_cycles(2);
      check_status_bit(tag, "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR,
                       1'b0);
      check_status_bit(tag, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
    endtask

    task run_error_ten_align_then_valid_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < 10; idx++) begin
        run_dma_job(.tag($sformatf("%s_align%0d", tag, idx)),
                    .seg0_addr(64'h0000_0000_0010_0001 + idx),
                    .opq_words(0), .send_eoe(1'b0),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(300000));
      end
      run_dma_job(.tag({tag, "_valid"}), .opq_words(8), .send_eoe(1'b1),
                  .sqe_id(sqe_id + 16'd10),
                  .sequence_no(sequence_no + 32'd10),
                  .timeout_cycles(300000));
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count, 32'd11);
      check_status_bit(tag, "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR,
                       1'b0);
    endtask

    task run_error_large_span_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_aw_observed_job(.tag(tag),
                          .obs_seg0_addr(64'h0000_0000_8000_0000),
                          .obs_seg0_span(64'h0000_0000_ffff_f000),
                          .obs_words(64),
                          .obs_send_eoe(1'b1),
                          .expected_aw_count(1),
                          .expected_first_aw(64'h0000_0000_8000_0000),
                          .sqe_id(sqe_id),
                          .sequence_no(sequence_no),
                          .timeout_cycles(300000));
      check_status_bit(tag, "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR,
                       1'b0);
    endtask

    task run_error_bresp_recovery_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_bresp_case(.tag({tag, "_slverr"}),
                           .bresp(axi4_write_pkg::AXI_RESP_SLVERR),
                           .error_index(-1),
                           .opq_words(64),
                           .sqe_id(sqe_id),
                           .sequence_no(sequence_no));
      run_dma_job(.tag({tag, "_clean"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd1),
                  .timeout_cycles(300000));
      check_status_bit({tag, "_clean"}, "status[AXI_ERR]", 6, 1'b0);
      check_status_bit({tag, "_clean"}, "status[EOE]", RDMA_DMA_ST_EOE,
                       1'b1);
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count, 32'd2);
    endtask

    task run_error_reset_mid_job_recovery_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_reset_writer_state_case(.tag({tag, "_reset"}),
                                        .target_state(4'd3),
                                        .sqe_id(sqe_id),
                                        .sequence_no(sequence_no));
      run_dma_job(.tag({tag, "_fresh"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd1),
                  .timeout_cycles(300000));
      check_status_bit({tag, "_fresh"}, "status[EOE]", RDMA_DMA_ST_EOE,
                       1'b1);
      check_status_bit({tag, "_fresh"}, "status[ALIGN_ERR]",
                       RDMA_DMA_ST_ALIGN_ERR, 1'b0);
    endtask

    task run_error_dbg1_bresp_observability_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit saw_waiting_b;

      stop_monitor = 1'b0;
      saw_waiting_b = 1'b0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.dbg1_writer_state == 4'd4)
              saw_waiting_b = 1'b1;
          end
        end
      join_none
      run_error_bresp_case(.tag(tag),
                           .bresp(axi4_write_pkg::AXI_RESP_SLVERR),
                           .error_index(-1),
                           .opq_words(64),
                           .sqe_id(sqe_id),
                           .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (env.debug_level >= 1) begin
        if (!saw_waiting_b)
          `uvm_error(tag, "dbg1_writer_state did not observe WR_WAITING_B")
        check_u32_equal(tag, "dbg1_writer_state idle",
                        vif.dbg1_writer_state, 32'd0);
        check_u32_equal(tag, "dbg1_aw_inflight idle",
                        vif.dbg1_aw_inflight, 32'd0);
        check_u32_equal(tag, "dbg1_b_outstanding idle",
                        vif.dbg1_b_outstanding, 32'd0);
      end
    endtask

    task run_error_dbg2_reordered_lineage_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit saw_reordered;

      saw_reordered = 1'b0;
      expect_simple_status_job(64'd8, 32'd8, 32'd0,
                               single_seg_eoe_status(),
                               single_seg_status_mask(), sqe_id);
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_opq_word({8'h00, sequence_no[15:0], 8'h00},
                            1'b0, sequence_no, next_lineage_id + 2);
      drive_direct_opq_word({8'h00, sequence_no[15:0], 8'h01},
                            1'b1, sequence_no, next_lineage_id + 1);
      next_lineage_id += 2;
      wait_for_done(300000);
      wait_cycles(2);
      if (env.debug_level >= 2) begin
        saw_reordered = (env.scb.dbg2_emit_count == 2);
        if (!saw_reordered)
          `uvm_error(tag, "DEBUG2 reordered lineage pair was not emitted")
      end
    endtask

    task run_error_dbg2_duplicate_lineage_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      expect_simple_status_job(64'd8, 32'd8, 32'd0,
                               single_seg_eoe_status(),
                               single_seg_status_mask(), sqe_id);
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_opq_word({8'h00, sequence_no[15:0], 8'h00},
                            1'b0, sequence_no, next_lineage_id + 1);
      drive_direct_opq_word({8'h00, sequence_no[15:0], 8'h01},
                            1'b1, sequence_no, next_lineage_id + 1);
      next_lineage_id += 2;
      wait_for_done(300000);
      wait_cycles(2);
      if ((env.debug_level >= 2) && (env.scb.dbg2_emit_count != 2))
        `uvm_error(tag, "DEBUG2 duplicate lineage pair was not emitted")
    endtask

    task run_error_dbg2_reset_residual_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_reset_writer_state_case(.tag({tag, "_reset"}),
                                        .target_state(4'd3),
                                        .sqe_id(sqe_id),
                                        .sequence_no(sequence_no));
      run_dma_job(.tag({tag, "_fresh"}), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd1),
                  .timeout_cycles(300000));
      if ((env.debug_level >= 2) && (env.scb.dbg2_emit_count != 8))
        `uvm_error(tag, "DEBUG2 lineage did not restart cleanly after reset")
    endtask

    task run_error_clear_idle_case(input string tag);
      pulse_clear_counters();
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, 32'd0);
      check_u32_equal(tag, "cnt_bytes_written", vif.cnt_bytes_written,
                      32'd0);
      check_u32_equal(tag, "cnt_halt", vif.cnt_halt, 32'd0);
      check_u32_equal(tag, "cnt_eoe_observed", vif.cnt_eoe_observed, 32'd0);
    endtask

    task run_error_clear_during_writer_state_case(
      input string tag,
      input bit [3:0] target_state,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit clear_done;

      clear_done = 1'b0;
      fork
        begin
          wait_for_dbg1_state(tag, target_state);
          pulse_clear_counters();
          clear_done = 1'b1;
          check_u32_equal(tag, "cnt_input_w after clear", vif.cnt_input_w,
                          32'd0);
          check_u32_equal(tag, "cnt_bytes_written after clear",
                          vif.cnt_bytes_written, 32'd0);
        end
        begin
          run_dma_job(.tag({tag, "_job"}), .opq_words(128),
                      .send_eoe(1'b1),
                      .wready_lag((target_state == 4'd3) ? 64 : 0),
                      .bvalid_lag((target_state == 4'd4) ? 64 : 1),
                      .sqe_id(sqe_id), .sequence_no(sequence_no),
                      .timeout_cycles(500000));
        end
      join
      if (!clear_done)
        `uvm_error(tag, "clear_counters was not issued in target state")
      check_status_bit({tag, "_job"}, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
    endtask

    task run_error_clear_back_to_back_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag({tag, "_pre"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      for (int unsigned idx = 0; idx < 5; idx++) begin
        pulse_clear_counters();
        check_u32_equal($sformatf("%s_clear%0d", tag, idx),
                        "cnt_input_w", vif.cnt_input_w, 32'd0);
        check_u32_equal($sformatf("%s_clear%0d", tag, idx),
                        "cnt_bytes_written", vif.cnt_bytes_written, 32'd0);
        check_u32_equal($sformatf("%s_clear%0d", tag, idx),
                        "cnt_halt", vif.cnt_halt, 32'd0);
      end
    endtask

    task run_error_clear_at_job_done_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit clear_issued;

      clear_issued = 1'b0;
      fork
        begin
          for (int unsigned cycle = 0; cycle < 300000; cycle++) begin
            @(posedge vif.clk);
            if (vif.m_axi_bvalid && vif.m_axi_bready) begin
              @(negedge vif.clk);
              vif.clear_counters <= 1'b1;
              clear_issued = 1'b1;
              @(negedge vif.clk);
              vif.clear_counters <= 1'b0;
              break;
            end
          end
        end
        begin
          run_dma_job(.tag({tag, "_job"}), .opq_words(64),
                      .send_eoe(1'b1), .bvalid_lag(8),
                      .sqe_id(sqe_id), .sequence_no(sequence_no),
                      .timeout_cycles(500000));
        end
      join
      if (!clear_issued)
        `uvm_error(tag, "clear_counters was not issued near job_done")
      check_status_bit({tag, "_job"}, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
    endtask

    task run_error_clear_during_halt_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_halt_count_job(.tag(tag), .dropped_words(8),
                         .sqe_id(sqe_id), .sequence_no(sequence_no),
                         .clear_after_first_halt(1'b1));
      if (vif.cnt_halt == 32'd0)
        `uvm_error(tag, "cnt_halt did not resume counting after clear")
    endtask

    task run_error_bresp_fault_loop_case(
      input string tag,
      input int unsigned job_count,
      input int unsigned error_period,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned error_jobs;

      error_jobs = 0;
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        bit inject_error;
        inject_error = ((idx % error_period) == 0);
        if (inject_error)
          error_jobs++;
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(4 + (idx % 8)),
                    .send_eoe(1'b1),
                    .bresp(inject_error ? axi4_write_pkg::AXI_RESP_SLVERR :
                           axi4_write_pkg::AXI_RESP_OKAY),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(300000));
        check_status_bit($sformatf("%s_job%0d", tag, idx),
                         "status[AXI_ERR]", 6, inject_error);
      end
      if (error_jobs == 0)
        `uvm_error(tag, "fault loop injected no BRESP errors")
    endtask

    task run_error_periodic_reset_loop_case(
      input string tag,
      input int unsigned job_count,
      input int unsigned reset_period,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        if ((idx % reset_period) == 0) begin
          apply_midrun_reset();
          check_reset_defaults($sformatf("%s_reset%0d", tag, idx));
        end
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(4 + (idx % 8)), .send_eoe(1'b1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(300000));
      end
    endtask

    task run_error_combined_fault_loop_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned align_jobs;
      int unsigned bresp_jobs;
      int unsigned reset_events;

      align_jobs = 0;
      bresp_jobs = 0;
      reset_events = 0;
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        if ((idx % 25) == 0) begin
          reset_events++;
          apply_midrun_reset();
          check_reset_defaults($sformatf("%s_reset%0d", tag, idx));
        end
        if ((idx % 10) == 0) begin
          align_jobs++;
          run_dma_job(.tag($sformatf("%s_align%0d", tag, idx)),
                      .seg0_addr(64'h0000_0000_0010_0001),
                      .opq_words(0), .send_eoe(1'b0),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(300000));
          check_status_bit($sformatf("%s_align%0d", tag, idx),
                           "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR, 1'b1);
        end else begin
          bit inject_bresp;
          inject_bresp = ((idx % 33) == 0);
          if (inject_bresp)
            bresp_jobs++;
          run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                      .opq_words(4 + (idx % 8)), .send_eoe(1'b1),
                      .bresp(inject_bresp ?
                             axi4_write_pkg::AXI_RESP_SLVERR :
                             axi4_write_pkg::AXI_RESP_OKAY),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(300000));
          check_status_bit($sformatf("%s_job%0d", tag, idx),
                           "status[AXI_ERR]", 6, inject_bresp);
        end
      end
      if ((align_jobs == 0) || (bresp_jobs == 0) || (reset_events == 0))
        `uvm_error(tag, "combined fault loop missed a fault class")
    endtask

    task run_error_bresp_ignored_after_reset_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      env.axi_cfg.bresp = axi4_write_pkg::AXI_RESP_SLVERR;
      run_error_reset_writer_state_case(.tag(tag),
                                        .target_state(4'd4),
                                        .sqe_id(sqe_id),
                                        .sequence_no(sequence_no));
      env.axi_cfg.bresp = axi4_write_pkg::AXI_RESP_OKAY;
      check_reset_defaults(tag);
    endtask

    task run_error_awready_delay_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_aw_observed_job(.tag(tag), .obs_words(64),
                          .obs_send_eoe(1'b1),
                          .expected_aw_count(1),
                          .obs_awready_lag(64),
                          .sqe_id(sqe_id),
                          .sequence_no(sequence_no),
                          .timeout_cycles(400000));
      check_status_bit(tag, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
    endtask

    task run_error_wready_delay_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag(tag), .opq_words(64), .send_eoe(1'b1),
                  .wready_lag(64), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(400000));
      check_status_bit(tag, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
    endtask

    task inject_spurious_b_idle();
      env.axi_cfg.spurious_b_idle_cycles = 1;
      wait_cycles(4);
      env.axi_cfg.spurious_b_idle_cycles = 0;
    endtask

    task run_error_spurious_b_idle_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned b_count_before;

      b_count_before = env.scb.b_count;
      inject_spurious_b_idle();
      if (env.scb.b_count != b_count_before)
        `uvm_error(tag, "idle spurious B was accepted by the monitor path")
      run_dma_job(.tag({tag, "_clean"}), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
    endtask

    task run_error_spurious_b_during_w_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      env.axi_cfg.spurious_b_during_w_cycles = 1;
      run_dma_job(.tag({tag, "_job"}), .opq_words(128),
                  .send_eoe(1'b1), .wready_lag(64),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(500000));
      check_status_bit({tag, "_job"}, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
    endtask

    task run_error_bid_mismatch_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit saw_bid_mismatch;

      stop_monitor = 1'b0;
      saw_bid_mismatch = 1'b0;
      env.axi_cfg.bid_value = 4'h5;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.m_axi_bvalid && vif.m_axi_bready &&
                (vif.m_axi_bid == 4'h5))
              saw_bid_mismatch = 1'b1;
          end
        end
      join_none
      run_dma_job(.tag(tag), .opq_words(64), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (!saw_bid_mismatch)
        `uvm_error(tag, "BID mismatch response was not observed")
    endtask

    task run_error_duplicate_bvalid_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned b_count_before;

      b_count_before = env.scb.b_count;
      env.axi_cfg.duplicate_b_response_count = 1;
      env.axi_cfg.duplicate_b_delay_cycles = 0;
      run_dma_job(.tag(tag), .opq_words(64), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      if (env.scb.b_count != (b_count_before + 1))
        `uvm_error(tag, "duplicate B response completed an extra handshake")
    endtask

    task run_error_fifo_level_inconsistency_case(input string tag);
      bit detected;

      vif.poke_fifo_level_inconsistency(detected);
      if (!detected)
        `uvm_error(tag, "FIFO level inconsistency poke was not observed")
      apply_midrun_reset();
      check_reset_defaults(tag);
    endtask

    task run_error_fifo_full_guard_case(input string tag);
      bit detected;

      vif.poke_fifo_full_guard(detected);
      if (!detected)
        `uvm_error(tag, "FIFO full guard poke was not observed")
      apply_midrun_reset();
      check_reset_defaults(tag);
    endtask

    task run_error_fifo_empty_guard_case(input string tag);
      bit detected;

      vif.poke_fifo_empty_read_guard(detected);
      if (!detected)
        `uvm_error(tag, "FIFO empty read guard poke was not observed")
      apply_midrun_reset();
      check_reset_defaults(tag);
    endtask

    task run_error_fifo_almost_full_disagreement_case(input string tag);
      bit detected;

      vif.poke_fifo_almost_full_disagreement(detected);
      if (!detected)
        `uvm_error(tag, "FIFO almost_full disagreement poke was not observed")
      apply_midrun_reset();
      check_reset_defaults(tag);
    endtask

    task run_error_job_req_held_high_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      bit saw_done_while_req;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd32, 32'd32, 32'd0,
                               expected_status, status_mask, sqe_id);
      saw_done_while_req = 1'b0;
      @(negedge vif.clk);
      vif.job_seg0_addr <= 64'h0000_0000_0010_0000;
      vif.job_seg0_span <= 64'h0000_0000_0000_1000;
      vif.job_seg1_addr <= 64'h0000_0000_0000_0000;
      vif.job_seg1_span <= 64'h0000_0000_0000_0000;
      vif.job_sqe_id <= sqe_id;
      vif.job_opcode <= 16'h0001;
      vif.job_req <= 1'b1;
      wait_cycles(2);
      drive_direct_words(8, 1'b1, sequence_no, next_lineage_id);
      wait_for_done(300000);
      saw_done_while_req = vif.job_req && vif.job_done;
      @(negedge vif.clk);
      vif.job_req <= 1'b0;
      wait_cycles(4);
      if (!saw_done_while_req)
        `uvm_error(tag, "job_done was not observed while job_req was held high")
      if (env.scb.job_done_count != 1)
        `uvm_error(tag, $sformatf("job_done_count got=%0d expected=1",
                                  env.scb.job_done_count))
    endtask

    task run_error_job_req_mutating_inputs_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd32, 32'd32, 32'd0,
                               expected_status, status_mask, sqe_id);
      @(negedge vif.clk);
      vif.job_seg0_addr <= 64'h0000_0000_0010_0000;
      vif.job_seg0_span <= 64'h0000_0000_0000_1000;
      vif.job_seg1_addr <= 64'h0000_0000_0000_0000;
      vif.job_seg1_span <= 64'h0000_0000_0000_0000;
      vif.job_sqe_id <= sqe_id;
      vif.job_opcode <= 16'h0001;
      vif.job_req <= 1'b1;
      @(negedge vif.clk);
      vif.job_seg0_addr <= 64'h0000_0000_0010_0001;
      vif.job_seg0_span <= 64'h0000_0000_0000_0000;
      vif.job_sqe_id <= sqe_id + 16'd1;
      wait_cycles(1);
      drive_direct_words(8, 1'b1, sequence_no, next_lineage_id);
      wait_for_done(300000);
      @(negedge vif.clk);
      vif.job_req <= 1'b0;
      wait_cycles(2);
      check_u32_equal(tag, "job_seg0_bytes_written",
                      vif.job_seg0_bytes_written, 32'd32);
      check_u32_equal(tag, "job_sqe_id_echo",
                      {16'h0000, vif.job_sqe_id_echo}, {16'h0000, sqe_id});
    endtask

    task run_error_job_done_req_overlap_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_job_req_held_high_case(.tag(tag), .sqe_id(sqe_id),
                                       .sequence_no(sequence_no));
    endtask

    task run_error_align_then_halt_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_align_refusal_case(.tag({tag, "_align"}),
                                   .seg0_addr(64'h0000_0000_0010_0001),
                                   .seg0_span(64'h1000),
                                   .seg1_addr(64'h0000_0000_0000_0000),
                                   .seg1_span(64'h0),
                                   .sqe_id(sqe_id),
                                   .sequence_no(sequence_no));
      run_halt_count_job(.tag({tag, "_halt"}), .dropped_words(4),
                         .sqe_id(sqe_id + 16'd1),
                         .sequence_no(sequence_no + 32'd1));
    endtask

    task run_error_align_with_bresp_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned b_count_before;

      b_count_before = env.scb.b_count;
      run_dma_job(.tag(tag), .seg0_addr(64'h0000_0000_0010_0001),
                  .seg0_span(64'h1000), .opq_words(0), .send_eoe(1'b0),
                  .bresp(axi4_write_pkg::AXI_RESP_SLVERR),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      check_status_bit(tag, "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR, 1'b1);
      check_status_bit(tag, "status[AXI_ERR]", 6, 1'b0);
      if (env.scb.b_count != b_count_before)
        `uvm_error(tag, "ALIGN_ERR job unexpectedly completed a B handshake")
    endtask

    task run_error_align_reset_clean_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_align_refusal_case(.tag({tag, "_align"}),
                                   .seg0_addr(64'h0000_0000_0010_0001),
                                   .seg0_span(64'h1000),
                                   .seg1_addr(64'h0000_0000_0000_0000),
                                   .seg1_span(64'h0),
                                   .sqe_id(sqe_id),
                                   .sequence_no(sequence_no));
      apply_midrun_reset();
      check_reset_defaults({tag, "_reset"});
      run_dma_job(.tag({tag, "_clean"}), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd1),
                  .timeout_cycles(300000));
    endtask

    task run_error_clear_during_aw_handshake_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit clear_done;

      clear_done = 1'b0;
      fork
        begin
          for (int unsigned cycle = 0; cycle < 300000; cycle++) begin
            @(posedge vif.clk);
            if (vif.m_axi_awvalid) begin
              pulse_clear_counters();
              clear_done = 1'b1;
              break;
            end
          end
        end
        begin
          run_dma_job(.tag({tag, "_job"}), .opq_words(64),
                      .send_eoe(1'b1), .awready_lag(64),
                      .sqe_id(sqe_id), .sequence_no(sequence_no),
                      .timeout_cycles(500000));
        end
      join
      if (!clear_done)
        `uvm_error(tag, "clear_counters was not issued during AWVALID")
      check_status_bit({tag, "_job"}, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
    endtask

    task drive_clear_and_opq_word(
      input bit [31:0] data,
      input bit eoe,
      input bit [31:0] sequence_no,
      input bit [31:0] hit_id
    );
      @(negedge vif.clk);
      vif.clear_counters <= 1'b1;
      vif.s_axis_opq_tdata <= {4'h0, data};
      vif.s_axis_opq_tvalid <= 1'b1;
      vif.s_axis_opq_tlast <= eoe;
      vif.s_axis_opq_tuser <= {1'b0, 1'b1};
      vif.dbg2_meta_valid <= 1'b1;
      vif.dbg2_meta_lane <= 4'h0;
      vif.dbg2_meta_hit_id <= hit_id;
      vif.dbg2_meta_source_ts <= hit_id;
      vif.dbg2_meta_sequence_no <= sequence_no;
      do begin
        @(posedge vif.clk);
      end while (vif.s_axis_opq_tready !== 1'b1);
      @(negedge vif.clk);
      vif.clear_counters <= 1'b0;
      vif.s_axis_opq_tvalid <= 1'b0;
      vif.s_axis_opq_tlast <= 1'b0;
      vif.s_axis_opq_tuser <= '0;
      vif.dbg2_meta_valid <= 1'b0;
      vif.dbg2_meta_lane <= '0;
      vif.dbg2_meta_hit_id <= '0;
      vif.dbg2_meta_source_ts <= '0;
      vif.dbg2_meta_sequence_no <= '0;
    endtask

    task run_error_clear_input_increment_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      int unsigned lineage_id;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      expect_simple_status_job(64'd32, 32'd32, 32'd0,
                               expected_status, status_mask, sqe_id);
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      lineage_id = next_lineage_id + 1;
      drive_clear_and_opq_word({8'h00, sequence_no[15:0], 8'h00},
                               1'b0, sequence_no, lineage_id);
      for (int unsigned idx = 1; idx < 8; idx++) begin
        drive_direct_opq_word({8'h00, sequence_no[15:0], idx[7:0]},
                              (idx == 7), sequence_no, lineage_id + idx);
      end
      next_lineage_id += 8;
      wait_for_done(300000);
      wait_cycles(2);
      check_u32_equal(tag, "cnt_input_w after clear/input race",
                      vif.cnt_input_w, 32'd8);
    endtask

    task run_error_clear_halt_race_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_halt_count_job(.tag(tag), .dropped_words(4),
                         .sqe_id(sqe_id), .sequence_no(sequence_no),
                         .clear_after_first_halt(1'b1));
    endtask

    task run_error_opq_stuck_wr_w_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned aw_before;
      int unsigned w_before;
      int unsigned b_before;
      bit aw_seen;
      bit w_stall_seen;

      aw_before = env.scb.aw_count;
      w_before = env.scb.w_count;
      b_before = env.scb.b_count;
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_for_dbg1_state(tag, 4'd2);
      vif.poke_fifo_underrun_after_aw(aw_seen, w_stall_seen);
      wait_cycles(2);
      if (!aw_seen || (env.scb.aw_count <= aw_before))
        `uvm_error(tag, "FIFO underrun injection did not issue an AW")
      if (!w_stall_seen)
        `uvm_error(tag, "WR_W stall with no FIFO read_valid was not observed")
      if (env.scb.w_count != w_before)
        `uvm_error(tag, "FIFO underrun injection emitted a W beat")
      if (env.scb.b_count != b_before)
        `uvm_error(tag, "FIFO underrun injection completed a B response")
      @(negedge vif.clk);
      vif.reset_n <= 1'b0;
      vif.release_fifo_underrun_poke();
      repeat (4) @(posedge vif.clk);
      @(negedge vif.clk);
      vif.reset_n <= 1'b1;
      repeat (8) @(posedge vif.clk);
      env.scb.reset_model();
      env.scb.configure_case(case_id, scorecard_path, env.debug_level);
      check_reset_defaults(tag);
    endtask

    task run_error_wready_stuck_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_writer_stall_case(.tag(tag), .state(4'd3),
                            .aw_lag(0), .w_lag(512), .b_lag(1),
                            .sqe_id(sqe_id), .sequence_no(sequence_no));
    endtask

    task run_error_bvalid_stuck_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_writer_stall_case(.tag(tag), .state(4'd4),
                            .aw_lag(0), .w_lag(0), .b_lag(512),
                            .sqe_id(sqe_id), .sequence_no(sequence_no));
    endtask

    task run_error_long_idle_no_job_case(input string tag);
      bit bad_seen;

      bad_seen = 1'b0;
      for (int unsigned cycle = 0; cycle < 1000000; cycle++) begin
        @(posedge vif.clk);
        if ((vif.dbg1_writer_state !== 4'd0) ||
            vif.m_axi_awvalid || vif.m_axi_wvalid || vif.m_axi_bready ||
            vif.job_done)
          bad_seen = 1'b1;
      end
      if (bad_seen)
        `uvm_error(tag, "idle watchdog observed non-idle writer activity")
      check_reset_defaults(tag);
    endtask

    task run_error_bresp_reset_align_valid_chain(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_bresp_case(.tag({tag, "_bresp"}),
                           .bresp(axi4_write_pkg::AXI_RESP_SLVERR),
                           .error_index(-1),
                           .opq_words(32),
                           .sqe_id(sqe_id),
                           .sequence_no(sequence_no));
      apply_midrun_reset();
      check_reset_defaults({tag, "_reset"});
      run_error_align_refusal_case(.tag({tag, "_align"}),
                                   .seg0_addr(64'h0000_0000_0010_0001),
                                   .seg0_span(64'h1000),
                                   .seg1_addr(64'h0000_0000_0000_0000),
                                   .seg1_span(64'h0),
                                   .sqe_id(sqe_id + 16'd1),
                                   .sequence_no(sequence_no + 32'd1));
      run_dma_job(.tag({tag, "_valid"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd2),
                  .sequence_no(sequence_no + 32'd2),
                  .timeout_cycles(300000));
      check_status_bit({tag, "_valid"}, "status[EOE]", RDMA_DMA_ST_EOE,
                       1'b1);
    endtask

    task run_error_bresp_halt_eoe_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_halt_count_job(.tag(tag), .dropped_words(8),
                         .sqe_id(sqe_id), .sequence_no(sequence_no),
                         .bresp(axi4_write_pkg::AXI_RESP_SLVERR));
      check_status_bit(tag, "status[HALT]", RDMA_DMA_ST_HALT, 1'b1);
      check_status_bit(tag, "status[AXI_ERR]", 6, 1'b1);
      check_status_bit(tag, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
    endtask

    task run_error_triple_reset_valid_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < 3; idx++) begin
        apply_midrun_reset();
        check_reset_defaults($sformatf("%s_reset%0d", tag, idx));
      end
      run_dma_job(.tag({tag, "_valid"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      check_status_bit({tag, "_valid"}, "status[EOE]", RDMA_DMA_ST_EOE,
                       1'b1);
    endtask

    task run_error_halt_reset_reentry_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_halt_count_job(.tag({tag, "_halt0"}), .dropped_words(4),
                         .sqe_id(sqe_id), .sequence_no(sequence_no));
      apply_midrun_reset();
      check_reset_defaults({tag, "_reset0"});
      run_halt_count_job(.tag({tag, "_halt1"}), .dropped_words(4),
                         .sqe_id(sqe_id + 16'd1),
                         .sequence_no(sequence_no + 32'd1));
      apply_midrun_reset();
      check_reset_defaults({tag, "_reset1"});
      run_dma_job(.tag({tag, "_valid"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd2),
                  .sequence_no(sequence_no + 32'd2),
                  .timeout_cycles(300000));
      check_status_bit({tag, "_valid"}, "status[EOE]", RDMA_DMA_ST_EOE,
                       1'b1);
    endtask

    task run_error_dbg2_lineage_reset_residual_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned ingress_before_reset;

      env.axi_cfg.wready_lag = 5000;
      expect_simple_status_job(64'd128, 32'd128, 32'd0,
                               single_seg_eoe_status(),
                               single_seg_status_mask(), sqe_id);
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(32, 1'b0, sequence_no, next_lineage_id);
      wait_cycles(4);
      ingress_before_reset = env.scb.opq_count;
      if ((env.debug_level >= 2) && (ingress_before_reset == 0))
        `uvm_error(tag, "DEBUG2 reset residual case saw no ingress")
      apply_midrun_reset();
      env.axi_cfg.wready_lag = 0;
      check_reset_defaults({tag, "_reset"});
      run_dma_job(.tag({tag, "_fresh"}), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd1),
                  .timeout_cycles(300000));
      if ((env.debug_level >= 2) && (env.scb.dbg2_emit_count != 8))
        `uvm_error(tag, "DEBUG2 lineage did not restart after reset residual")
    endtask

    task run_error_dbg2_bresp_lineage_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_bresp_case(.tag(tag),
                           .bresp(axi4_write_pkg::AXI_RESP_SLVERR),
                           .error_index(-1),
                           .opq_words(64),
                           .sqe_id(sqe_id),
                           .sequence_no(sequence_no));
      if ((env.debug_level >= 2) && (env.scb.dbg2_emit_count != 64))
        `uvm_error(tag, "DEBUG2 lineage did not close under BRESP error")
    endtask

    task run_error_dbg2_align_no_traffic_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_align_refusal_case(.tag(tag),
                                   .seg0_addr(64'h0000_0000_0010_0001),
                                   .seg0_span(64'h1000),
                                   .seg1_addr(64'h0000_0000_0000_0000),
                                   .seg1_span(64'h0),
                                   .sqe_id(sqe_id),
                                   .sequence_no(sequence_no));
      if (env.scb.opq_count != 0)
        `uvm_error(tag, "ALIGN_ERR lineage case accepted ingress")
      if ((env.debug_level >= 2) && (env.scb.dbg2_emit_count != 0))
        `uvm_error(tag, "ALIGN_ERR lineage case emitted DEBUG2 entries")
    endtask

    task run_error_random_fault_profile_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < 100; idx++) begin
        if ((idx % 25) == 0) begin
          apply_midrun_reset();
          check_reset_defaults($sformatf("%s_reset%0d", tag, idx));
        end else if ((idx % 10) == 0) begin
          run_halt_count_job(.tag($sformatf("%s_halt%0d", tag, idx)),
                             .dropped_words(4),
                             .sqe_id(sqe_id + idx[15:0]),
                             .sequence_no(sequence_no + idx));
        end else if ((idx % 5) == 0) begin
          run_dma_job(.tag($sformatf("%s_bresp%0d", tag, idx)),
                      .opq_words(16), .send_eoe(1'b1),
                      .bresp(axi4_write_pkg::AXI_RESP_SLVERR),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(300000));
        end else begin
          run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                      .opq_words(8 + ((idx * 7) % 32)),
                      .send_eoe(1'b1),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(300000));
        end
      end
      run_dma_job(.tag({tag, "_final"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd100),
                  .sequence_no(sequence_no + 32'd100),
                  .timeout_cycles(300000));
      check_conservation(tag);
    endtask

    task run_error_random_align_valid_mix_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned align_jobs;

      align_jobs = 0;
      for (int unsigned idx = 0; idx < 100; idx++) begin
        if ((idx % 2) == 0) begin
          align_jobs++;
          run_dma_job(.tag($sformatf("%s_align%0d", tag, idx)),
                      .seg0_addr(64'h0000_0000_0010_0001),
                      .opq_words(0), .send_eoe(1'b0),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(300000));
          check_status_bit(tag, "status[ALIGN_ERR]",
                           RDMA_DMA_ST_ALIGN_ERR, 1'b1);
        end else begin
          run_dma_job(.tag($sformatf("%s_valid%0d", tag, idx)),
                      .opq_words(8 + ((idx * 5) % 32)),
                      .send_eoe(1'b1),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(300000));
        end
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'd100);
      if (align_jobs != 50)
        `uvm_error(tag, "ALIGN_ERR mix did not execute 50 align jobs")
      check_conservation(tag);
    endtask

    task run_error_random_reset_every_n_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned global_idx;

      global_idx = 0;
      for (int unsigned reset_idx = 0; reset_idx < 20; reset_idx++) begin
        int unsigned jobs_this_group;
        jobs_this_group = 5 + ((reset_idx * 7 + 3) % 16);
        for (int unsigned job_idx = 0; job_idx < jobs_this_group; job_idx++) begin
          run_dma_job(.tag($sformatf("%s_r%0d_j%0d", tag, reset_idx, job_idx)),
                      .opq_words(8 + ((global_idx * 3) % 24)),
                      .send_eoe(1'b1),
                      .sqe_id(sqe_id + global_idx[15:0]),
                      .sequence_no(sequence_no + global_idx),
                      .timeout_cycles(300000));
          global_idx++;
        end
        check_u32_equal(tag, "group job_done_count",
                        env.scb.job_done_count, jobs_this_group[31:0]);
        check_conservation(tag);
        apply_midrun_reset();
        check_reset_defaults($sformatf("%s_reset%0d", tag, reset_idx));
      end
      run_dma_job(.tag({tag, "_final"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id + global_idx[15:0]),
                  .sequence_no(sequence_no + global_idx),
                  .timeout_cycles(300000));
      check_status_bit({tag, "_final"}, "status[EOE]", RDMA_DMA_ST_EOE,
                       1'b1);
    endtask

    task run_error_random_bresp_rate_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned error_jobs;

      error_jobs = 0;
      for (int unsigned idx = 0; idx < 1000; idx++) begin
        bit inject_error;
        inject_error = ((idx % 20) == 0);
        if (inject_error)
          error_jobs++;
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(4 + ((idx * 3) % 16)),
                    .send_eoe(1'b1),
                    .bresp(inject_error ? axi4_write_pkg::AXI_RESP_SLVERR :
                                           axi4_write_pkg::AXI_RESP_OKAY),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(300000));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'd1000);
      if (error_jobs != 50)
        `uvm_error(tag, "BRESP error rate did not hit 5 percent")
      check_conservation(tag);
    endtask

    task run_error_random_combined_fault_rate_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned fault_ops;
      int unsigned jobs_since_reset;

      fault_ops = 0;
      jobs_since_reset = 0;
      for (int unsigned idx = 0; idx < 1000; idx++) begin
        if ((idx % 10) == 0) begin
          fault_ops++;
          if ((idx % 100) == 0) begin
            if (jobs_since_reset != 0)
              check_conservation($sformatf("%s_pre_reset%0d", tag, idx));
            apply_midrun_reset();
            check_reset_defaults($sformatf("%s_reset%0d", tag, idx));
            jobs_since_reset = 0;
          end else if ((idx % 50) == 0) begin
            run_halt_count_job(.tag($sformatf("%s_halt%0d", tag, idx)),
                               .dropped_words(4),
                               .sqe_id(sqe_id + idx[15:0]),
                               .sequence_no(sequence_no + idx));
            jobs_since_reset++;
          end else begin
            run_dma_job(.tag($sformatf("%s_bresp%0d", tag, idx)),
                        .opq_words(8), .send_eoe(1'b1),
                        .bresp(axi4_write_pkg::AXI_RESP_SLVERR),
                        .sqe_id(sqe_id + idx[15:0]),
                        .sequence_no(sequence_no + idx),
                        .timeout_cycles(300000));
            jobs_since_reset++;
          end
        end else begin
          run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                      .opq_words(4 + ((idx * 5) % 16)),
                      .send_eoe(1'b1),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(300000));
          jobs_since_reset++;
        end
      end
      check_conservation(tag);
      if (fault_ops != 100)
        `uvm_error(tag, "combined fault rate did not hit 10 percent")
    endtask

    task run_error_reset_every_50_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit bad_during_reset;

      bad_during_reset = 1'b0;
      for (int unsigned reset_idx = 0; reset_idx < 20; reset_idx++) begin
        wait_cycles(46);
        @(negedge vif.clk);
        vif.reset_n <= 1'b0;
        repeat (4) begin
          @(posedge vif.clk);
          if ((vif.dbg1_writer_state !== 4'd0) ||
              vif.m_axi_awvalid || vif.m_axi_wvalid || vif.m_axi_bready ||
              vif.job_done)
            bad_during_reset = 1'b1;
        end
        @(negedge vif.clk);
        vif.reset_n <= 1'b1;
        repeat (4) @(posedge vif.clk);
        env.scb.reset_model();
        env.scb.configure_case(case_id, scorecard_path, env.debug_level);
        check_reset_defaults($sformatf("%s_reset%0d", tag, reset_idx));
      end
      if (bad_during_reset)
        `uvm_error(tag, "aggressive reset window observed non-idle activity")
      run_dma_job(.tag({tag, "_recovery"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      check_status_bit({tag, "_recovery"}, "status[EOE]", RDMA_DMA_ST_EOE,
                       1'b1);
    endtask

    task run_error_reset_wait_bvalid_no_host_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 50000;
      drive_direct_job_req(64'h0000_0000_0010_0000,
                           64'h0000_0000_0000_1000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      drive_direct_words(64, 1'b1, sequence_no, next_lineage_id);
      wait_for_dbg1_state(tag, 4'd4);
      if (vif.m_axi_bready !== 1'b1)
        `uvm_error(tag, "writer did not wait for B while host withheld bvalid")
      apply_midrun_reset();
      env.axi_cfg.bvalid_lag = 1;
      check_reset_defaults(tag);
      run_dma_job(.tag({tag, "_fresh"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd1),
                  .timeout_cycles(300000));
    endtask

    task run_error_reset_high_fifo_fill_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned lineage_id;

      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 50000;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0040_0000,
                           64'h0000_0000_0001_0000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);
      lineage_id = next_lineage_id;
      for (int unsigned beat_idx = 0; beat_idx < 192; beat_idx++) begin
        for (int unsigned slot_idx = 0; slot_idx < RDMA_DMA_OPQ_PER_BEAT;
             slot_idx++) begin
          lineage_id++;
          drive_direct_opq_word({8'h00, sequence_no[15:0], beat_idx[7:0]},
                                1'b0, sequence_no, lineage_id);
        end
      end
      next_lineage_id = lineage_id;
      wait_cycles(2);
      if (vif.dbg1_fifo_level !== 9'd192)
        `uvm_error(tag, $sformatf("fifo level got=%0d expected high fill 192",
                                  vif.dbg1_fifo_level))
      if (vif.dbg1_fifo_almost_full !== 1'b1)
        `uvm_error(tag, "fifo_almost_full did not assert before reset")
      apply_midrun_reset();
      env.axi_cfg.wready_lag = 0;
      check_reset_defaults(tag);
      run_dma_job(.tag({tag, "_fresh"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd1),
                  .timeout_cycles(300000));
    endtask

    task run_error_reset_clear_same_cycle_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag({tag, "_pre"}), .opq_words(32),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      if ((vif.cnt_input_w == 32'd0) || (vif.cnt_bytes_written == 32'd0))
        `uvm_error(tag, "pre-race counters did not accumulate")
      @(negedge vif.clk);
      vif.clear_counters <= 1'b1;
      vif.reset_n <= 1'b0;
      repeat (4) @(posedge vif.clk);
      @(negedge vif.clk);
      vif.clear_counters <= 1'b0;
      vif.reset_n <= 1'b1;
      repeat (8) @(posedge vif.clk);
      env.scb.reset_model();
      env.scb.configure_case(case_id, scorecard_path, env.debug_level);
      check_reset_defaults(tag);
      run_dma_job(.tag({tag, "_fresh"}), .opq_words(8),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd1),
                  .timeout_cycles(300000));
    endtask

    task run_error_out_of_order_b_edge_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned aw_seen;
      int unsigned b_before;
      bit injected_illegal_b;

      stop_monitor = 1'b0;
      aw_seen = 0;
      b_before = env.scb.b_count;
      injected_illegal_b = 1'b0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.m_axi_awvalid && vif.m_axi_awready) begin
              aw_seen++;
              if ((aw_seen == 2) && !injected_illegal_b) begin
                env.axi_cfg.spurious_b_during_w_cycles = 1;
                injected_illegal_b = 1'b1;
              end
            end
          end
        end
      join_none

      run_dma_job(.tag(tag), .seg0_span(64'h0000_0000_0000_4000),
                  .opq_words(2048), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(700000));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (aw_seen < 2)
        `uvm_error(tag, "out-of-order B edge did not issue two AWs")
      if (!injected_illegal_b)
        `uvm_error(tag, "out-of-order B edge did not inject illegal B")
      if ((env.scb.b_count - b_before) != aw_seen)
        `uvm_error(tag, "illegal early B produced an extra B handshake")
    endtask

    task run_error_report_align_state_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit saw_reporting;

      stop_monitor = 1'b0;
      saw_reporting = 1'b0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.dbg1_writer_state == 4'd5)
              saw_reporting = 1'b1;
          end
        end
      join_none
      run_error_align_refusal_case(.tag(tag),
                                   .seg0_addr(64'h0000_0000_0010_0001),
                                   .seg0_span(64'h1000),
                                   .seg1_addr(64'h0000_0000_0000_0000),
                                   .seg1_span(64'h0),
                                   .sqe_id(sqe_id),
                                   .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (!saw_reporting)
        `uvm_error(tag, "ALIGN_ERR did not hit WR_REPORTING coverage state")
    endtask

    task run_error_status_align_coverage_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_align_refusal_case(.tag(tag),
                                   .seg0_addr(64'h0000_0000_0010_0001),
                                   .seg0_span(64'h1000),
                                   .seg1_addr(64'h0000_0000_0000_0000),
                                   .seg1_span(64'h0),
                                   .sqe_id(sqe_id),
                                   .sequence_no(sequence_no));
      check_status_bit(tag, "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR, 1'b1);
    endtask

    task run_error_bresp_branch_coverage_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_bresp_case(.tag(tag),
                           .bresp(axi4_write_pkg::AXI_RESP_SLVERR),
                           .error_index(-1),
                           .opq_words(64),
                           .sqe_id(sqe_id),
                           .sequence_no(sequence_no));
    endtask

    task run_error_reset_all_writer_states_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      apply_midrun_reset();
      check_reset_defaults({tag, "_idle"});
      run_error_reset_writer_state_case(.tag({tag, "_programming"}),
                                        .target_state(4'd1),
                                        .sqe_id(sqe_id),
                                        .sequence_no(sequence_no));
      run_error_reset_writer_state_case(.tag({tag, "_aw"}),
                                        .target_state(4'd2),
                                        .sqe_id(sqe_id + 16'd1),
                                        .sequence_no(sequence_no + 32'd1));
      run_error_reset_writer_state_case(.tag({tag, "_w"}),
                                        .target_state(4'd3),
                                        .sqe_id(sqe_id + 16'd2),
                                        .sequence_no(sequence_no + 32'd2));
      run_error_reset_writer_state_case(.tag({tag, "_b"}),
                                        .target_state(4'd4),
                                        .sqe_id(sqe_id + 16'd3),
                                        .sequence_no(sequence_no + 32'd3));
      run_error_reset_on_job_done_case(.tag({tag, "_reporting"}),
                                       .sqe_id(sqe_id + 16'd4),
                                       .sequence_no(sequence_no + 32'd4));
      run_dma_job(.tag({tag, "_fresh"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd5),
                  .sequence_no(sequence_no + 32'd5),
                  .timeout_cycles(300000));
    endtask

    task run_error_sustained_bresp_one_percent_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_bresp_fault_loop_case(.tag(tag), .job_count(100),
                                      .error_period(100),
                                      .sqe_id(sqe_id),
                                      .sequence_no(sequence_no));
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'd100);
      check_conservation(tag);
    endtask

    task run_error_sustained_reset_one_percent_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned jobs_since_reset;

      jobs_since_reset = 0;
      for (int unsigned idx = 0; idx < 100; idx++) begin
        if (idx == 50) begin
          apply_midrun_reset();
          check_reset_defaults({tag, "_reset"});
          jobs_since_reset = 0;
        end
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(4 + (idx % 8)), .send_eoe(1'b1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(300000));
        jobs_since_reset++;
      end
      check_u32_equal(tag, "jobs since reset", env.scb.job_done_count,
                      jobs_since_reset[31:0]);
      check_conservation(tag);
    endtask

    task run_error_sustained_align_one_percent_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned align_jobs;

      align_jobs = 0;
      for (int unsigned idx = 0; idx < 100; idx++) begin
        if (idx == 50) begin
          align_jobs++;
          run_dma_job(.tag($sformatf("%s_align%0d", tag, idx)),
                      .seg0_addr(64'h0000_0000_0010_0001),
                      .opq_words(0), .send_eoe(1'b0),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(300000));
          check_status_bit($sformatf("%s_align%0d", tag, idx),
                           "status[ALIGN_ERR]",
                           RDMA_DMA_ST_ALIGN_ERR, 1'b1);
        end else begin
          run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                      .opq_words(4 + (idx % 8)), .send_eoe(1'b1),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(300000));
        end
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'd100);
      if (align_jobs != 1)
        `uvm_error(tag, "ALIGN_ERR sustained case did not hit 1 percent")
      check_conservation(tag);
    endtask

    task run_error_final_composite_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_status_align_coverage_case(.tag({tag, "_align"}),
                                           .sqe_id(sqe_id),
                                           .sequence_no(sequence_no));
      run_error_bresp_branch_coverage_case(.tag({tag, "_bresp"}),
                                           .sqe_id(sqe_id + 16'd1),
                                           .sequence_no(sequence_no + 32'd1));
      run_halt_count_job(.tag({tag, "_halt"}), .dropped_words(4),
                         .sqe_id(sqe_id + 16'd2),
                         .sequence_no(sequence_no + 32'd2));
      run_error_reset_wait_bvalid_no_host_case(.tag({tag, "_reset_b"}),
                                               .sqe_id(sqe_id + 16'd3),
                                               .sequence_no(sequence_no + 32'd3));
      run_error_duplicate_bvalid_case(.tag({tag, "_dup_b"}),
                                      .sqe_id(sqe_id + 16'd4),
                                      .sequence_no(sequence_no + 32'd4));
      run_dma_job(.tag({tag, "_closure"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd5),
                  .sequence_no(sequence_no + 32'd5),
                  .timeout_cycles(300000));
    endtask

    task run_error_final_dbg1_lineage_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_error_dbg1_bresp_observability_case(.tag({tag, "_dbg1_bresp"}),
                                              .sqe_id(sqe_id),
                                              .sequence_no(sequence_no));
      run_halt_count_job(.tag({tag, "_dbg1_halt"}), .dropped_words(8),
                         .sqe_id(sqe_id + 16'd1),
                         .sequence_no(sequence_no + 32'd1));
      if ((env.debug_level == 1) && (env.scb.dbg2_emit_count != 0))
        `uvm_error(tag, "DEBUG=1 lineage case observed DEBUG2 emissions")
    endtask

    task run_error_final_dbg2_lineage_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      apply_midrun_reset();
      run_error_dbg2_bresp_lineage_case(.tag({tag, "_bresp"}),
                                        .sqe_id(sqe_id),
                                        .sequence_no(sequence_no));
      apply_midrun_reset();
      run_error_dbg2_lineage_reset_residual_case(.tag({tag, "_reset"}),
                                                 .sqe_id(sqe_id + 16'd1),
                                                 .sequence_no(sequence_no + 32'd1));
      apply_midrun_reset();
      run_error_dbg2_align_no_traffic_case(.tag({tag, "_align"}),
                                           .sqe_id(sqe_id + 16'd2),
                                           .sequence_no(sequence_no + 32'd2));
      run_dma_job(.tag({tag, "_fresh"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd3),
                  .sequence_no(sequence_no + 32'd3),
                  .timeout_cycles(300000));
    endtask

    task run_profile_multi_event_case(
      input string tag,
      input int unsigned event_count,
      input int unsigned words_per_event,
      input int unsigned gap_cycles,
      input int unsigned bvalid_lag,
      input int unsigned wready_lag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no,
      input bit expect_halt = 1'b0
    );
      bit [31:0] expected_input;
      bit [63:0] span_bytes;

      expected_input = event_count[31:0] * words_per_event[31:0];
      span_bytes = 64'(event_count) * 64'(words_per_event) * 64'd4 +
                   64'h0000_0000_0000_1000;
      span_bytes = (span_bytes + 64'hfff) & ~64'hfff;
      run_dma_multi_event_job(.tag(tag),
                              .event_count(event_count),
                              .words_per_event(words_per_event),
                              .gap_cycles(gap_cycles),
                              .seg0_span(span_bytes),
                              .sqe_id(sqe_id),
                              .sequence_no(sequence_no),
                              .wready_lag(wready_lag),
                              .bvalid_lag(bvalid_lag),
                              .timeout_cycles(1500000));
      check_u32_equal(tag, "cnt_input_w", vif.cnt_input_w, expected_input);
      if (!expect_halt && (vif.cnt_halt != 32'h0))
        `uvm_error(tag, $sformatf("cnt_halt got=%0d expected=0",
                                  vif.cnt_halt))
      if (expect_halt && (vif.cnt_halt == 32'h0))
        `uvm_error(tag, "cnt_halt did not increment under halt profile")
      check_conservation(tag);
    endtask

    task run_profile_single_load_case(
      input string tag,
      input int unsigned opq_words,
      input int unsigned idle_after_each,
      input int unsigned wready_lag,
      input int unsigned bvalid_lag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no,
      input bit expect_halt = 1'b0
    );
      bit [63:0] span_bytes;

      span_bytes = 64'(opq_words) * 64'd4 + 64'h1000;
      span_bytes = (span_bytes + 64'hfff) & ~64'hfff;
      run_dma_job(.tag(tag), .seg0_span(span_bytes),
                  .opq_words(opq_words), .send_eoe(1'b1),
                  .wready_lag(wready_lag), .bvalid_lag(bvalid_lag),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .idle_after_each(idle_after_each),
                  .timeout_cycles(1500000));
      if (!expect_halt && (vif.cnt_halt != 32'h0))
        `uvm_error(tag, $sformatf("cnt_halt got=%0d expected=0",
                                  vif.cnt_halt))
      if (expect_halt && (vif.cnt_halt == 32'h0))
        `uvm_error(tag, "cnt_halt did not increment under throttled load")
      check_conservation(tag);
    endtask

    task run_profile_job_stream_case(
      input string tag,
      input int unsigned job_count,
      input int unsigned words_per_job,
      input bit two_segment,
      input bit mixed_span,
      input bit random_sqe,
      input int unsigned gap_cycles,
      input bit variable_lag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        bit [63:0] seg0_span_v;
        bit [63:0] seg1_span_v;
        int unsigned words_v;
        int unsigned bvalid_v;
        int unsigned idle_v;
        bit [15:0] sqe_v;

        words_v = words_per_job;
        seg0_span_v = 64'h1000;
        seg1_span_v = 64'h0;
        if (mixed_span) begin
          case (idx % 4)
            0: begin
              seg0_span_v = 64'h1000;
              words_v = 64;
            end
            1: begin
              seg0_span_v = 64'h2000;
              words_v = 512;
            end
            2: begin
              seg0_span_v = 64'h4000;
              words_v = 1024;
            end
            default: begin
              seg0_span_v = 64'h1000;
              seg1_span_v = 64'h1000;
              words_v = 1032;
            end
          endcase
        end else if (two_segment) begin
          seg0_span_v = 64'h1000;
          seg1_span_v = 64'h1000;
          words_v = (words_per_job < 1025) ? 1032 : words_per_job;
        end else begin
          seg0_span_v = 64'(words_per_job) * 64'd4;
          seg0_span_v = (seg0_span_v + 64'hfff) & ~64'hfff;
          if (seg0_span_v == 64'h0)
            seg0_span_v = 64'h1000;
        end

        bvalid_v = variable_lag ? (1 + ((idx * 37) % 250)) : 1;
        idle_v = (gap_cycles == 0) ? 0 : (idx % 3);
        sqe_v = random_sqe ? (16'h4000 ^ (idx[15:0] * 16'h0123)) :
                (sqe_id + idx[15:0]);
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .seg0_span(seg0_span_v),
                    .seg1_span(seg1_span_v),
                    .opq_words(words_v),
                    .send_eoe(1'b1),
                    .bvalid_lag(bvalid_v),
                    .sqe_id(sqe_v),
                    .sequence_no(sequence_no + idx),
                    .idle_after_each(idle_v),
                    .timeout_cycles(700000));
        if (gap_cycles != 0)
          wait_cycles(gap_cycles);
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      job_count[31:0]);
      check_conservation(tag);
    endtask

    task run_profile_awlen_metric_case(
      input string tag,
      input int unsigned opq_words,
      input int unsigned idle_after_each,
      input int unsigned wready_lag,
      input int unsigned bvalid_lag,
      input int unsigned min_avg_awlen_milli,
      input int unsigned max_avg_awlen_milli,
      input int unsigned min_util_milli,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned aw_count_local;
      int unsigned awlen_sum;
      int unsigned avg_awlen_milli;
      int unsigned util_milli;
      int unsigned w_before;
      int unsigned w_delta;
      bit [63:0] span_bytes;

      stop_monitor = 1'b0;
      aw_count_local = 0;
      awlen_sum = 0;
      w_before = env.scb.w_count;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.m_axi_awvalid && vif.m_axi_awready) begin
              aw_count_local++;
              awlen_sum += vif.m_axi_awlen;
            end
          end
        end
      join_none

      span_bytes = 64'(opq_words) * 64'd4 + 64'h1000;
      span_bytes = (span_bytes + 64'hfff) & ~64'hfff;
      run_dma_job(.tag(tag), .seg0_span(span_bytes),
                  .opq_words(opq_words), .send_eoe(1'b1),
                  .wready_lag(wready_lag), .bvalid_lag(bvalid_lag),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .idle_after_each(idle_after_each),
                  .timeout_cycles(900000));
      stop_monitor = 1'b1;
      wait_cycles(1);

      if (aw_count_local == 0) begin
        `uvm_error(tag, "no AW handshakes observed")
      end else begin
        avg_awlen_milli = (awlen_sum * 1000) / aw_count_local;
        if ((avg_awlen_milli < min_avg_awlen_milli) ||
            (avg_awlen_milli > max_avg_awlen_milli))
          `uvm_error(tag, $sformatf(
            "avg AWLEN got=%0d/1000 expected in [%0d,%0d]",
            avg_awlen_milli, min_avg_awlen_milli, max_avg_awlen_milli))
        w_delta = env.scb.w_count - w_before;
        util_milli = (w_delta * 1000) / (aw_count_local * RDMA_DMA_MAX_BURST_BEATS);
        if (util_milli < min_util_milli)
          `uvm_error(tag, $sformatf("burst util got=%0d/1000 expected >=%0d/1000",
                                    util_milli, min_util_milli))
      end
      check_conservation(tag);
    endtask

    task run_profile_fifo_pressure_case(
      input string tag,
      input int unsigned opq_words,
      input int unsigned wready_lag,
      input int unsigned bvalid_lag,
      input int unsigned min_max_level,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned max_level;
      int unsigned high_samples;
      bit [63:0] span_bytes;

      stop_monitor = 1'b0;
      max_level = 0;
      high_samples = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.dbg1_fifo_level > max_level)
              max_level = vif.dbg1_fifo_level;
            if (vif.dbg1_fifo_level >= min_max_level[8:0])
              high_samples++;
          end
        end
      join_none

      span_bytes = 64'(opq_words) * 64'd4 + 64'h1000;
      span_bytes = (span_bytes + 64'hfff) & ~64'hfff;
      run_dma_job(.tag(tag), .seg0_span(span_bytes),
                  .opq_words(opq_words), .send_eoe(1'b1),
                  .wready_lag(wready_lag), .bvalid_lag(bvalid_lag),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(900000));
      stop_monitor = 1'b1;
      wait_cycles(1);

      if (max_level < min_max_level)
        `uvm_error(tag, $sformatf("fifo max_level got=%0d expected >=%0d",
                                  max_level, min_max_level))
      if (high_samples == 0)
        `uvm_error(tag, "fifo pressure monitor saw no high-occupancy samples")
      check_conservation(tag);
    endtask

    task run_profile_counter_clear_conservation_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag({tag, "_pre_clear"}), .opq_words(64),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      if ((vif.cnt_input_w == 32'd0) || (vif.cnt_bytes_written == 32'd0))
        `uvm_error(tag, "pre-clear counters did not accumulate")
      pulse_clear_counters();
      check_u32_equal(tag, "cnt_input_w after clear", vif.cnt_input_w, 32'd0);
      check_u32_equal(tag, "cnt_bytes_written after clear",
                      vif.cnt_bytes_written, 32'd0);
      check_u32_equal(tag, "cnt_halt after clear", vif.cnt_halt, 32'd0);
      check_u32_equal(tag, "cnt_eoe_observed after clear",
                      vif.cnt_eoe_observed, 32'd0);
      run_dma_job(.tag({tag, "_post_clear"}), .opq_words(64),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd1),
                  .timeout_cycles(300000));
      check_conservation(tag);
    endtask

    task run_profile_halt_one_of_five_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [31:0] halt_before;
      bit [31:0] halt_after;

      for (int unsigned idx = 0; idx < 2; idx++) begin
        run_dma_job(.tag($sformatf("%s_clean%0d", tag, idx)),
                    .opq_words(16), .send_eoe(1'b1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(300000));
      end
      halt_before = vif.cnt_halt;
      run_halt_count_job(.tag({tag, "_halt"}), .dropped_words(16),
                         .sqe_id(sqe_id + 16'd2),
                         .sequence_no(sequence_no + 32'd2));
      halt_after = vif.cnt_halt;
      if (halt_after <= halt_before)
        `uvm_error(tag, "halt job did not increment cnt_halt")
      for (int unsigned idx = 3; idx < 5; idx++) begin
        run_dma_job(.tag($sformatf("%s_clean%0d", tag, idx)),
                    .opq_words(16), .send_eoe(1'b1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(300000));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count, 32'd5);
      check_conservation(tag);
    endtask

    task run_profile_latency_case(
      input string tag,
      input int unsigned opq_words,
      input int unsigned wready_lag,
      input int unsigned bvalid_lag,
      input int unsigned min_cycles,
      input int unsigned max_cycles,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned cycle_count;

      stop_monitor = 1'b0;
      cycle_count = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n === 1'b1)
              cycle_count++;
          end
        end
      join_none

      run_profile_single_load_case(.tag(tag), .opq_words(opq_words),
                                   .idle_after_each(0),
                                   .wready_lag(wready_lag),
                                   .bvalid_lag(bvalid_lag),
                                   .sqe_id(sqe_id),
                                   .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);

      if (cycle_count < min_cycles)
        `uvm_error(tag, $sformatf("latency cycles got=%0d expected >=%0d",
                                  cycle_count, min_cycles))
      if ((max_cycles != 0) && (cycle_count > max_cycles))
        `uvm_error(tag, $sformatf("latency cycles got=%0d expected <=%0d",
                                  cycle_count, max_cycles))
    endtask

    task run_profile_average_latency_case(
      input string tag,
      input int unsigned job_count,
      input int unsigned words_per_job,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned cycle_count;
      int unsigned avg_cycles;

      stop_monitor = 1'b0;
      cycle_count = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n === 1'b1)
              cycle_count++;
          end
        end
      join_none

      run_profile_job_stream_case(.tag(tag), .job_count(job_count),
                                  .words_per_job(words_per_job),
                                  .two_segment(1'b0),
                                  .mixed_span(1'b0),
                                  .random_sqe(1'b0),
                                  .gap_cycles(0),
                                  .variable_lag(1'b0),
                                  .sqe_id(sqe_id),
                                  .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);
      avg_cycles = (job_count == 0) ? 0 : (cycle_count / job_count);
      if (avg_cycles == 0)
        `uvm_error(tag, "average latency did not accumulate")
    endtask

    task run_profile_halt_latency_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned clean_cycles;
      int unsigned halt_cycles;
      bit stop_monitor;

      stop_monitor = 1'b0;
      clean_cycles = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n === 1'b1)
              clean_cycles++;
          end
        end
      join_none
      run_dma_job(.tag({tag, "_clean"}), .opq_words(128),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      stop_monitor = 1'b1;
      wait_cycles(1);

      stop_monitor = 1'b0;
      halt_cycles = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n === 1'b1)
              halt_cycles++;
          end
        end
      join_none
      run_halt_count_job(.tag({tag, "_halt"}), .dropped_words(32),
                         .sqe_id(sqe_id + 16'd1),
                         .sequence_no(sequence_no + 32'd1));
      stop_monitor = 1'b1;
      wait_cycles(1);

      if (halt_cycles <= clean_cycles)
        `uvm_error(tag, $sformatf("halt latency got=%0d clean=%0d",
                                  halt_cycles, clean_cycles))
    endtask

    task run_profile_fifo_hold_case(
      input string tag,
      input int unsigned target_level,
      input int unsigned hold_cycles,
      input bit expect_almost_full,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      int unsigned accepted_words;
      int unsigned lineage_id;
      longint unsigned sum_level;
      int unsigned avg_level;
      bit level_bad;

      expected_status = single_seg_eoe_status();
      status_mask = single_seg_status_mask();
      accepted_words = target_level * RDMA_DMA_OPQ_PER_BEAT;
      expect_simple_status_job(64'(accepted_words + 1) * 64'd4,
                               32'(accepted_words + 1) * 32'd4,
                               32'd0, expected_status, status_mask, sqe_id);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 50000;
      env.axi_cfg.bvalid_lag = 1;
      drive_direct_job_req(64'h0000_0000_0040_0000,
                           64'h0000_0000_0001_0000,
                           64'h0000_0000_0000_0000,
                           64'h0000_0000_0000_0000,
                           sqe_id, 16'h0001, 1);
      wait_cycles(2);

      lineage_id = next_lineage_id;
      for (int unsigned word_idx = 0; word_idx < accepted_words; word_idx++) begin
        lineage_id++;
        drive_direct_opq_word({8'h00, sequence_no[15:0], word_idx[7:0]},
                              1'b0, sequence_no, lineage_id);
      end
      wait_cycles(2);
      if (vif.dbg1_fifo_level !== target_level[8:0])
        `uvm_error(tag, $sformatf("fifo level got=%0d expected=%0d",
                                  vif.dbg1_fifo_level, target_level))
      if (expect_almost_full &&
          (vif.dbg1_fifo_almost_full !== 1'b1))
        `uvm_error(tag, "fifo_almost_full did not assert during hold")

      sum_level = 0;
      level_bad = 1'b0;
      for (int unsigned cycle = 0; cycle < hold_cycles; cycle++) begin
        @(posedge vif.clk);
        sum_level += vif.dbg1_fifo_level;
        if (vif.dbg1_fifo_level !== target_level[8:0])
          level_bad = 1'b1;
      end
      avg_level = (hold_cycles == 0) ? 0 : int'(sum_level / hold_cycles);
      if (avg_level != target_level)
        `uvm_error(tag, $sformatf("fifo avg got=%0d expected=%0d",
                                  avg_level, target_level))
      if (level_bad)
        `uvm_error(tag, "fifo level changed during host-stalled hold window")

      env.axi_cfg.wready_lag = 0;
      for (int unsigned cycle = 0; cycle < 20000; cycle++) begin
        @(posedge vif.clk);
        if (!vif.dbg1_fifo_almost_full)
          break;
      end
      accepted_words++;
      lineage_id++;
      drive_direct_opq_word({8'h00, sequence_no[15:0], accepted_words[7:0]},
                            1'b1, sequence_no, lineage_id);
      wait_for_done(500000);
      wait_cycles(2);
      next_lineage_id = lineage_id;
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      check_status_bit(tag, "status[HALT]", RDMA_DMA_ST_HALT, 1'b0);
    endtask

    task run_profile_fifo_oscillation_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_fifo_fill_drain_case(.tag({tag, "_cycle0"}), .sqe_id(sqe_id),
                               .check_fill(1'b1),
                               .check_empty_after_done(1'b1),
                               .sequence_no(sequence_no));
      run_fifo_fill_drain_case(.tag({tag, "_cycle1"}), .sqe_id(sqe_id + 16'd1),
                               .check_fill(1'b1),
                               .check_empty_after_done(1'b1),
                               .sequence_no(sequence_no + 32'd1));
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count, 32'd2);
    endtask

    task run_profile_dbg1_invariant_soak_case(
      input string tag,
      input int unsigned soak_cycles,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit invariant_bad;
      int unsigned max_level;

      invariant_bad = 1'b0;
      max_level = 0;
      fork
        begin
          run_profile_job_stream_case(.tag({tag, "_jobs"}), .job_count(32),
                                      .words_per_job(128),
                                      .two_segment(1'b0),
                                      .mixed_span(1'b1),
                                      .random_sqe(1'b1),
                                      .gap_cycles(1),
                                      .variable_lag(1'b1),
                                      .sqe_id(sqe_id),
                                      .sequence_no(sequence_no));
        end
        begin
          for (int unsigned cycle = 0; cycle < soak_cycles; cycle++) begin
            @(posedge vif.clk);
            if (vif.dbg1_fifo_level > max_level)
              max_level = vif.dbg1_fifo_level;
            if (vif.dbg1_fifo_level > 9'd192)
              invariant_bad = 1'b1;
            if (vif.dbg1_packer_slot_idx >= RDMA_DMA_OPQ_PER_BEAT[3:0])
              invariant_bad = 1'b1;
            if (vif.dbg1_writer_state > 4'd5)
              invariant_bad = 1'b1;
          end
        end
      join
      if (invariant_bad)
        `uvm_error(tag, "dbg1 invariant monitor detected an illegal state")
      if (max_level == 0)
        `uvm_error(tag, "dbg1 soak did not observe FIFO residency")
    endtask

    task run_profile_halt_accounting_soak_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [31:0] halt_before;
      bit [31:0] halt_after;

      halt_before = vif.cnt_halt;
      run_halt_count_job(.tag(tag), .dropped_words(64),
                         .sqe_id(sqe_id), .sequence_no(sequence_no));
      halt_after = vif.cnt_halt;
      if ((halt_after - halt_before) < 32'd64)
        `uvm_error(tag, $sformatf("cnt_halt delta got=%0d expected >=64",
                                  halt_after - halt_before))
      wait_cycles(10000);
      check_u32_equal(tag, "cnt_halt after idle soak", vif.cnt_halt,
                      halt_after);
    endtask

    task run_profile_fifo_histogram_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit saw_empty;
      bit saw_active;
      bit saw_burst_level;

      stop_monitor = 1'b0;
      saw_empty = 1'b0;
      saw_active = 1'b0;
      saw_burst_level = 1'b0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.dbg1_fifo_level == 9'd0)
              saw_empty = 1'b1;
            if ((vif.dbg1_fifo_level > 9'd0) &&
                (vif.dbg1_fifo_level < RDMA_DMA_MAX_BURST_BEATS[8:0]))
              saw_active = 1'b1;
            if (vif.dbg1_fifo_level >= RDMA_DMA_MAX_BURST_BEATS[8:0])
              saw_burst_level = 1'b1;
          end
        end
      join_none
      run_profile_single_load_case(.tag(tag), .opq_words(4096),
                                   .idle_after_each(0),
                                   .wready_lag(8),
                                   .bvalid_lag(32),
                                   .sqe_id(sqe_id),
                                   .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (!saw_empty || !saw_active || !saw_burst_level)
        `uvm_error(tag, "fifo histogram did not populate empty, active, and burst bins")
    endtask

    task run_profile_random_host_lag_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        int unsigned lag_v;
        lag_v = (idx * 37 + 11) % 101;
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(32 + ((idx * 19) % 96)),
                    .send_eoe(1'b1),
                    .wready_lag(lag_v),
                    .bvalid_lag(1 + ((idx * 23) % 100)),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(700000));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      job_count[31:0]);
      check_conservation(tag);
    endtask

    task run_profile_random_bvalid_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned max_level;

      stop_monitor = 1'b0;
      max_level = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.dbg1_fifo_level > max_level)
              max_level = vif.dbg1_fifo_level;
          end
        end
      join_none

      for (int unsigned idx = 0; idx < job_count; idx++) begin
        int unsigned bvalid_v;
        bvalid_v = (idx * 73 + 19) % 1001;
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(32 + ((idx * 11) % 96)),
                    .send_eoe(1'b1),
                    .bvalid_lag(bvalid_v),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(900000));
      end
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (max_level > 192)
        `uvm_error(tag, $sformatf("fifo max_level got=%0d expected <=192",
                                  max_level))
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      job_count[31:0]);
      check_conservation(tag);
    endtask

    task run_profile_random_idle_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        int unsigned idle_v;
        idle_v = (idx * 17 + 5) % 51;
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(16 + ((idx * 13) % 80)),
                    .send_eoe(1'b1),
                    .idle_after_each(idle_v),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(900000));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      job_count[31:0]);
      check_conservation(tag);
    endtask

    task run_profile_random_combo_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        int unsigned idle_v;
        int unsigned wready_v;
        int unsigned bvalid_v;

        idle_v = (idx * 19 + 3) % 51;
        wready_v = (idx * 29 + 7) % 101;
        bvalid_v = (idx * 31 + 13) % 1001;
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(24 + ((idx * 23) % 104)),
                    .send_eoe(1'b1),
                    .idle_after_each(idle_v),
                    .wready_lag(wready_v),
                    .bvalid_lag(bvalid_v),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(900000));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      job_count[31:0]);
      check_conservation(tag);
    endtask

    task run_profile_fixed_host_lag_jobs(
      input string tag,
      input int unsigned job_count,
      input int unsigned wready_lag,
      input int unsigned words_per_job,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(words_per_job),
                    .send_eoe(1'b1),
                    .wready_lag(wready_lag),
                    .bvalid_lag(1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(1500000));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      job_count[31:0]);
      check_conservation(tag);
    endtask

    task run_profile_variable_host_lag_case(
      input string tag,
      input int unsigned job_count,
      input int unsigned max_lag,
      input int unsigned words_per_job,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        int unsigned lag_v;

        lag_v = (idx * 97 + 23) % (max_lag + 1);
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(words_per_job + ((idx * 7) % 16)),
                    .send_eoe(1'b1),
                    .wready_lag(lag_v),
                    .bvalid_lag(1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(1600000));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      job_count[31:0]);
      check_conservation(tag);
    endtask

    task run_profile_fixed_bvalid_jobs(
      input string tag,
      input int unsigned job_count,
      input int unsigned bvalid_lag,
      input int unsigned words_per_job,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(words_per_job),
                    .send_eoe(1'b1),
                    .wready_lag(0),
                    .bvalid_lag(bvalid_lag),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(1600000));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      job_count[31:0]);
      check_conservation(tag);
    endtask

    task run_profile_sustained_input_load_case(
      input string tag,
      input int unsigned job_count,
      input int unsigned idle_after_each,
      input int unsigned words_per_job,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [31:0] halt_before;

      halt_before = vif.cnt_halt;
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(words_per_job),
                    .send_eoe(1'b1),
                    .idle_after_each(idle_after_each),
                    .wready_lag(0),
                    .bvalid_lag(1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(500000));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      job_count[31:0]);
      check_u32_equal(tag, "cnt_halt delta", vif.cnt_halt - halt_before,
                      32'd0);
      check_conservation(tag);
    endtask

    task run_profile_bursty_input_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned max_level;
      bit saw_active;

      stop_monitor = 1'b0;
      max_level = 0;
      saw_active = 1'b0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.dbg1_fifo_level > max_level)
              max_level = vif.dbg1_fifo_level;
            if (vif.dbg1_fifo_level != 9'd0)
              saw_active = 1'b1;
          end
        end
      join_none

      for (int unsigned idx = 0; idx < job_count; idx++) begin
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(64),
                    .send_eoe(1'b1),
                    .idle_after_each((idx % 2) == 0 ? 0 : 9),
                    .wready_lag(1),
                    .bvalid_lag(1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(700000));
      end
      stop_monitor = 1'b1;
      wait_cycles(1);
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      job_count[31:0]);
      if (!saw_active || (max_level == 0))
        `uvm_error(tag, "bursty input case did not observe FIFO residency")
      check_conservation(tag);
    endtask

    task run_profile_output_bursty_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned max_level;
      int unsigned high_samples;

      stop_monitor = 1'b0;
      max_level = 0;
      high_samples = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.dbg1_fifo_level > max_level)
              max_level = vif.dbg1_fifo_level;
            if (vif.dbg1_fifo_level >= RDMA_DMA_MAX_BURST_BEATS[8:0])
              high_samples++;
          end
        end
      join_none

      for (int unsigned idx = 0; idx < job_count; idx++) begin
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(128),
                    .send_eoe(1'b1),
                    .wready_lag((idx % 4) == 0 ? 200 : 0),
                    .bvalid_lag(1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(900000));
      end
      stop_monitor = 1'b1;
      wait_cycles(1);
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      job_count[31:0]);
      if ((max_level == 0) || (high_samples == 0))
        `uvm_error(tag, "bursty output case did not create FIFO oscillation")
      check_conservation(tag);
    endtask

    task run_profile_random_rate_bound_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned max_level;

      stop_monitor = 1'b0;
      max_level = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.dbg1_fifo_level > max_level)
              max_level = vif.dbg1_fifo_level;
          end
        end
      join_none

      for (int unsigned idx = 0; idx < job_count; idx++) begin
        int unsigned idle_v;
        int unsigned wready_v;
        int unsigned bvalid_v;

        idle_v = (idx * 41 + 7) % 17;
        wready_v = (idx * 61 + 5) % 129;
        bvalid_v = 1 + ((idx * 53 + 11) % 257);
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(32 + ((idx * 17) % 96)),
                    .send_eoe(1'b1),
                    .idle_after_each(idle_v),
                    .wready_lag(wready_v),
                    .bvalid_lag(bvalid_v),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(1200000));
      end
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (max_level > 192)
        `uvm_error(tag, $sformatf("fifo max_level got=%0d expected <=192",
                                  max_level))
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      job_count[31:0]);
      check_conservation(tag);
    endtask

    task run_profile_seeded_tput_batch(
      input string tag,
      input int unsigned seed,
      input int unsigned job_count,
      input int unsigned words_per_job,
      input int unsigned idle_after_each,
      input int unsigned wready_lag,
      output int unsigned cycle_count,
      output bit [31:0] byte_delta,
      output bit [31:0] halt_delta
    );
      bit stop_monitor;
      bit [31:0] bytes_before;
      bit [31:0] halt_before;

      stop_monitor = 1'b0;
      cycle_count = 0;
      bytes_before = vif.cnt_bytes_written;
      halt_before = vif.cnt_halt;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n === 1'b1)
              cycle_count++;
          end
        end
      join_none

      for (int unsigned idx = 0; idx < job_count; idx++) begin
        run_dma_job(.tag($sformatf("%s_seed%0d_job%0d", tag, seed, idx)),
                    .opq_words(words_per_job),
                    .send_eoe(1'b1),
                    .idle_after_each(idle_after_each),
                    .wready_lag(wready_lag),
                    .bvalid_lag(1),
                    .sqe_id(16'(16'h6000 ^ seed[15:0] ^ idx[15:0])),
                    .sequence_no(32'(seed * 1000 + idx)),
                    .timeout_cycles(500000));
      end
      stop_monitor = 1'b1;
      wait_cycles(1);
      byte_delta = vif.cnt_bytes_written - bytes_before;
      halt_delta = vif.cnt_halt - halt_before;
    endtask

    task run_profile_throughput_consistency_case(
      input string tag,
      input int unsigned seed_a,
      input int unsigned seed_b,
      input int unsigned job_count,
      input int unsigned words_per_job,
      input int unsigned idle_after_each,
      input int unsigned wready_lag
    );
      int unsigned cycles_a;
      int unsigned cycles_b;
      int unsigned diff_cycles;
      int unsigned max_diff;
      bit [31:0] bytes_a;
      bit [31:0] bytes_b;
      bit [31:0] halt_a;
      bit [31:0] halt_b;

      run_profile_seeded_tput_batch(.tag({tag, "_a"}), .seed(seed_a),
                                    .job_count(job_count),
                                    .words_per_job(words_per_job),
                                    .idle_after_each(idle_after_each),
                                    .wready_lag(wready_lag),
                                    .cycle_count(cycles_a),
                                    .byte_delta(bytes_a),
                                    .halt_delta(halt_a));
      run_profile_seeded_tput_batch(.tag({tag, "_b"}), .seed(seed_b),
                                    .job_count(job_count),
                                    .words_per_job(words_per_job),
                                    .idle_after_each(idle_after_each),
                                    .wready_lag(wready_lag),
                                    .cycle_count(cycles_b),
                                    .byte_delta(bytes_b),
                                    .halt_delta(halt_b));
      if ((bytes_a == 32'd0) || (bytes_b == 32'd0))
        `uvm_error(tag, "throughput consistency batch wrote no bytes")
      if (bytes_a != bytes_b)
        `uvm_error(tag, $sformatf("byte deltas differ seed-to-seed a=%0d b=%0d",
                                  bytes_a, bytes_b))
      if ((halt_a != 32'd0) || (halt_b != 32'd0))
        `uvm_error(tag, $sformatf("halt occurred during throughput check a=%0d b=%0d",
                                  halt_a, halt_b))
      diff_cycles = (cycles_a > cycles_b) ? (cycles_a - cycles_b) :
                    (cycles_b - cycles_a);
      max_diff = (cycles_a / 20) + 1;
      if (diff_cycles > max_diff)
        `uvm_error(tag, $sformatf("cycle delta got=%0d allowed=%0d a=%0d b=%0d",
                                  diff_cycles, max_diff, cycles_a, cycles_b))
      check_conservation(tag);
    endtask

    task run_profile_halt_rate_consistency_case(
      input string tag,
      input int unsigned seed_a,
      input int unsigned seed_b,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [31:0] halt_before;
      bit [31:0] halt_a;
      bit [31:0] halt_b;
      bit [31:0] diff_halt;
      bit [31:0] max_diff;

      halt_before = vif.cnt_halt;
      run_halt_count_job(.tag({tag, "_seed_a"}),
                         .dropped_words(32),
                         .sqe_id(16'(sqe_id ^ seed_a[15:0])),
                         .sequence_no(sequence_no + seed_a));
      halt_a = vif.cnt_halt - halt_before;
      halt_before = vif.cnt_halt;
      run_halt_count_job(.tag({tag, "_seed_b"}),
                         .dropped_words(32),
                         .sqe_id(16'(sqe_id ^ seed_b[15:0])),
                         .sequence_no(sequence_no + seed_b));
      halt_b = vif.cnt_halt - halt_before;
      if ((halt_a == 32'd0) || (halt_b == 32'd0))
        `uvm_error(tag, "halt-rate consistency saw zero halt delta")
      diff_halt = (halt_a > halt_b) ? (halt_a - halt_b) :
                  (halt_b - halt_a);
      max_diff = (halt_a / 100) + 1;
      if (diff_halt > max_diff)
        `uvm_error(tag, $sformatf("halt delta got=%0d allowed=%0d a=%0d b=%0d",
                                  diff_halt, max_diff, halt_a, halt_b))
      check_conservation(tag);
    endtask

    task run_profile_seeded_latency_batch(
      input string tag,
      input int unsigned seed,
      input int unsigned job_count,
      output int unsigned p50_cycles
    );
      int unsigned samples [128];
      int unsigned cycle_count;
      bit stop_monitor;

      for (int unsigned idx = 0; idx < job_count; idx++) begin
        stop_monitor = 1'b0;
        cycle_count = 0;
        fork
          begin
            while (!stop_monitor) begin
              @(posedge vif.clk);
              if (vif.reset_n === 1'b1)
                cycle_count++;
            end
          end
        join_none
        run_dma_job(.tag($sformatf("%s_seed%0d_job%0d", tag, seed, idx)),
                    .opq_words(16),
                    .send_eoe(1'b1),
                    .idle_after_each((idx + seed) % 3),
                    .wready_lag(0),
                    .bvalid_lag(1),
                    .sqe_id(16'(16'h7000 ^ seed[15:0] ^ idx[15:0])),
                    .sequence_no(32'(seed * 1000 + idx)),
                    .timeout_cycles(300000));
        stop_monitor = 1'b1;
        wait_cycles(1);
        samples[idx] = cycle_count;
      end

      for (int unsigned outer = 0; outer < job_count; outer++) begin
        for (int unsigned inner = outer + 1; inner < job_count; inner++) begin
          if (samples[inner] < samples[outer]) begin
            int unsigned tmp;
            tmp = samples[outer];
            samples[outer] = samples[inner];
            samples[inner] = tmp;
          end
        end
      end
      p50_cycles = samples[job_count / 2];
    endtask

    task run_profile_latency_p50_consistency_case(
      input string tag,
      input int unsigned seed_a,
      input int unsigned seed_b,
      input int unsigned job_count
    );
      int unsigned p50_a;
      int unsigned p50_b;
      int unsigned diff_cycles;
      int unsigned max_diff;

      run_profile_seeded_latency_batch(.tag({tag, "_a"}), .seed(seed_a),
                                       .job_count(job_count),
                                       .p50_cycles(p50_a));
      run_profile_seeded_latency_batch(.tag({tag, "_b"}), .seed(seed_b),
                                       .job_count(job_count),
                                       .p50_cycles(p50_b));
      if ((p50_a == 0) || (p50_b == 0))
        `uvm_error(tag, "latency p50 did not accumulate")
      diff_cycles = (p50_a > p50_b) ? (p50_a - p50_b) :
                    (p50_b - p50_a);
      max_diff = (p50_a / 20) + 1;
      if (diff_cycles > max_diff)
        `uvm_error(tag, $sformatf("p50 latency delta got=%0d allowed=%0d a=%0d b=%0d",
                                  diff_cycles, max_diff, p50_a, p50_b))
      check_conservation(tag);
    endtask

    task run_profile_debug2_residual_bound_case(
      input string tag,
      input int unsigned opq_words,
      input int unsigned max_residual,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned max_seen_residual;

      stop_monitor = 1'b0;
      max_seen_residual = 0;
      fork
        begin
          while (!stop_monitor) begin
            int unsigned residual;

            @(posedge vif.clk);
            if (env.debug_level >= 2) begin
              residual = env.scb.opq_count - env.scb.dbg2_emit_count;
              if (residual > max_seen_residual)
                max_seen_residual = residual;
              if (residual > max_residual)
                `uvm_error(tag, $sformatf("DEBUG2 residual got=%0d expected <=%0d",
                                          residual, max_residual))
            end
          end
        end
      join_none
      run_profile_single_load_case(.tag(tag), .opq_words(opq_words),
                                   .idle_after_each(0),
                                   .wready_lag(0), .bvalid_lag(1),
                                   .sqe_id(sqe_id),
                                   .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if ((env.debug_level >= 2) && (max_seen_residual == 0))
        `uvm_error(tag, "DEBUG2 residual monitor saw no active lineage")
    endtask

    task run_profile_debug2_halt_scale_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_profile_single_load_case(.tag({tag, "_load"}), .opq_words(100000),
                                   .idle_after_each(0),
                                   .wready_lag(0), .bvalid_lag(1),
                                   .sqe_id(sqe_id),
                                   .sequence_no(sequence_no));
      run_dbg2_halt_residual_case(.tag({tag, "_halt"}),
                                  .sqe_id(sqe_id + 16'd1),
                                  .sequence_no(sequence_no + 32'd1));
    endtask

    task run_profile_counter_clear_replay_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag({tag, "_pre"}), .opq_words(64), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      if ((vif.cnt_input_w == 32'd0) || (vif.cnt_bytes_written == 32'd0))
        `uvm_error(tag, "pre-clear counters did not accumulate")
      pulse_clear_counters();
      check_u32_equal(tag, "cnt_input_w after clear", vif.cnt_input_w, 32'd0);
      check_u32_equal(tag, "cnt_bytes_written after clear",
                      vif.cnt_bytes_written, 32'd0);
      check_u32_equal(tag, "cnt_halt after clear", vif.cnt_halt, 32'd0);
      run_dma_job(.tag({tag, "_post"}), .opq_words(64), .send_eoe(1'b1),
                  .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd1),
                  .timeout_cycles(300000));
      if ((env.debug_level >= 2) && (env.scb.dbg2_emit_count == 0))
        `uvm_error(tag, "DEBUG2 lineage did not replay after counter clear")
      check_conservation(tag);
    endtask

    task run_profile_checkpoint_residual_case(
      input string tag,
      input int unsigned checkpoint_count,
      input int unsigned words_per_checkpoint,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < checkpoint_count; idx++) begin
        run_profile_single_load_case(.tag($sformatf("%s_chk%0d", tag, idx)),
                                     .opq_words(words_per_checkpoint),
                                     .idle_after_each(0),
                                     .wready_lag(0), .bvalid_lag(1),
                                     .sqe_id(sqe_id + idx[15:0]),
                                     .sequence_no(sequence_no + idx));
        if ((env.debug_level >= 2) &&
            (env.scb.opq_count != env.scb.dbg2_emit_count))
          `uvm_error(tag, $sformatf("checkpoint %0d residual got=%0d expected=0",
                                    idx,
                                    env.scb.opq_count - env.scb.dbg2_emit_count))
      end
      check_conservation(tag);
    endtask

    task run_profile_exact_awlen_case(
      input string tag,
      input int unsigned opq_words,
      input bit [7:0] expected_awlen,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned aw_count_local;
      bit saw_expected;

      stop_monitor = 1'b0;
      aw_count_local = 0;
      saw_expected = 1'b0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.m_axi_awvalid && vif.m_axi_awready) begin
              aw_count_local++;
              if (vif.m_axi_awlen === expected_awlen)
                saw_expected = 1'b1;
            end
          end
        end
      join_none
      run_profile_single_load_case(.tag(tag), .opq_words(opq_words),
                                   .idle_after_each(0),
                                   .wready_lag(0), .bvalid_lag(1),
                                   .sqe_id(sqe_id),
                                   .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (aw_count_local == 0)
        `uvm_error(tag, "no AW handshakes observed")
      if (!saw_expected)
        `uvm_error(tag, $sformatf("AWLEN %0d was not observed",
                                  expected_awlen))
    endtask

    task run_profile_fifo_threshold_hammer_case(
      input string tag,
      input int unsigned iteration_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < iteration_count; idx++) begin
        run_fifo_fill_drain_case(.tag($sformatf("%s_iter%0d", tag, idx)),
                                 .sqe_id(sqe_id + idx[15:0]),
                                 .check_fill(1'b1),
                                 .check_empty_after_done(1'b1),
                                 .sequence_no(sequence_no + idx));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      iteration_count[31:0]);
    endtask

    task run_profile_halt_status_combo_case(
      input string tag,
      input bit [63:0] seg0_span,
      input bit [63:0] seg1_span,
      input int unsigned total_words,
      input bit expect_full,
      input bit expect_boundary,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      job_single_segment_sequence job_seq;
      int unsigned accepted_words;
      int unsigned lineage_id;
      bit reached_almost_full;
      bit drained_below_almost_full;
      bit [31:0] halt_before;
      bit [31:0] expected_halt;
      int unsigned modeled_slot;
      int unsigned actual_slot;
      bit [63:0] expected_total;
      bit [63:0] expected_seg1_wide;
      bit [31:0] expected_seg0;
      bit [31:0] expected_seg1;
      bit [15:0] expected_status;
      bit [15:0] status_mask;

      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 5000;
      env.axi_cfg.bvalid_lag = 1;
      env.axi_cfg.bresp = axi4_write_pkg::AXI_RESP_OKAY;

      job_seq = job_single_segment_sequence::type_id::create({tag, "_job_seq"});
      job_seq.seg0_addr = 64'h0000_0000_0040_0000;
      job_seq.seg0_span = seg0_span;
      job_seq.seg1_addr = 64'h0000_0000_0041_0000;
      job_seq.seg1_span = seg1_span;
      job_seq.sqe_id = sqe_id;
      job_seq.opcode = 16'h0001;
      job_seq.start(env.job_agent_h.sequencer);
      wait_cycles(2);

      accepted_words = 0;
      lineage_id = next_lineage_id;
      reached_almost_full = 1'b0;
      for (int unsigned word_idx = 0; word_idx < total_words; word_idx++) begin
        if (vif.dbg1_fifo_almost_full) begin
          reached_almost_full = 1'b1;
          break;
        end
        accepted_words++;
        lineage_id++;
        drive_direct_opq_word({8'h00, sequence_no[15:0], accepted_words[7:0]},
                              1'b0, sequence_no, lineage_id);
      end
      if (!reached_almost_full)
        `uvm_fatal(tag, "fifo_almost_full did not assert before status-combo halt")

      wait_cycles(2);
      modeled_slot = accepted_words % RDMA_DMA_OPQ_PER_BEAT;
      actual_slot = vif.dbg1_packer_slot_idx;
      while (modeled_slot != actual_slot) begin
        if (!env.scb.drop_last_partial_opq())
          `uvm_fatal(tag, "could not reconcile status-combo boundary word")
        accepted_words--;
        modeled_slot = accepted_words % RDMA_DMA_OPQ_PER_BEAT;
      end

      halt_before = vif.cnt_halt;
      env.scb.ignore_next_opq(16);
      for (int unsigned drop_idx = 0; drop_idx < 16; drop_idx++) begin
        lineage_id++;
        drive_direct_opq_word({8'h00, sequence_no[15:0], drop_idx[7:0]},
                              1'b0, sequence_no, lineage_id);
      end
      wait_cycles(4);
      if ((vif.cnt_halt - halt_before) < 32'd16)
        `uvm_error(tag, "status-combo halt delta was smaller than drop count")
      expected_halt = vif.cnt_halt;

      env.axi_cfg.wready_lag = 0;
      drained_below_almost_full = 1'b0;
      for (int unsigned cycle = 0; cycle < 20000; cycle++) begin
        @(posedge vif.clk);
        if (!vif.dbg1_fifo_almost_full) begin
          drained_below_almost_full = 1'b1;
          break;
        end
      end
      if (!drained_below_almost_full)
        `uvm_fatal(tag, "fifo_almost_full did not clear after status-combo drain")

      expected_total = 64'(total_words) * 64'd4;
      expected_seg1_wide = (expected_total > seg0_span) ?
        (expected_total - seg0_span) : 64'h0;
      expected_seg0 = (expected_total > seg0_span) ?
        seg0_span[31:0] : expected_total[31:0];
      expected_seg1 = expected_seg1_wide[31:0];
      expected_status = 16'h0000;
      status_mask = 16'h0000;
      status_mask[RDMA_DMA_ST_EOE] = 1'b1;
      status_mask[RDMA_DMA_ST_FULL] = 1'b1;
      status_mask[RDMA_DMA_ST_HALT] = 1'b1;
      status_mask[RDMA_DMA_ST_SEG_BOUNDARY_HIT] = 1'b1;
      status_mask[RDMA_DMA_ST_SEG0_ONLY] = 1'b1;
      expected_status[RDMA_DMA_ST_EOE] = 1'b1;
      expected_status[RDMA_DMA_ST_FULL] = expect_full;
      expected_status[RDMA_DMA_ST_HALT] = 1'b1;
      expected_status[RDMA_DMA_ST_SEG_BOUNDARY_HIT] = expect_boundary;
      expected_status[RDMA_DMA_ST_SEG0_ONLY] = (seg1_span == 64'h0);
      env.scb.expect_job(expected_total, expected_seg0, expected_seg1,
                         expected_status, status_mask, sqe_id);

      while (accepted_words < total_words) begin
        accepted_words++;
        lineage_id++;
        drive_direct_opq_word({8'h00, sequence_no[15:0], accepted_words[7:0]},
                              accepted_words == total_words,
                              sequence_no, lineage_id);
      end

      wait_for_done(500000);
      wait_cycles(2);
      check_u32_equal(tag, "cnt_halt", vif.cnt_halt, expected_halt);
      check_status_bit(tag, "status[HALT]", RDMA_DMA_ST_HALT, 1'b1);
      check_status_bit(tag, "status[FULL]", RDMA_DMA_ST_FULL, expect_full);
      check_status_bit(tag, "status[SEG_BOUNDARY_HIT]",
                       RDMA_DMA_ST_SEG_BOUNDARY_HIT, expect_boundary);
      check_conservation(tag);
      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      next_lineage_id = lineage_id;
    endtask

    task run_profile_clear_during_reset_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_dma_job(.tag({tag, "_pre"}), .opq_words(64), .send_eoe(1'b1),
                  .sqe_id(sqe_id), .sequence_no(sequence_no),
                  .timeout_cycles(300000));
      if ((vif.cnt_input_w == 32'd0) || (vif.cnt_bytes_written == 32'd0))
        `uvm_error(tag, "pre-reset counters did not accumulate")
      @(negedge vif.clk);
      vif.clear_counters <= 1'b1;
      vif.reset_n <= 1'b0;
      repeat (4) @(posedge vif.clk);
      @(negedge vif.clk);
      vif.reset_n <= 1'b1;
      vif.clear_counters <= 1'b0;
      repeat (8) @(posedge vif.clk);
      env.scb.reset_model();
      env.scb.configure_case(case_id, scorecard_path, env.debug_level);
      check_u32_equal(tag, "cnt_input_w after reset clear", vif.cnt_input_w,
                      32'd0);
      check_u32_equal(tag, "cnt_bytes_written after reset clear",
                      vif.cnt_bytes_written, 32'd0);
      check_u32_equal(tag, "cnt_halt after reset clear", vif.cnt_halt, 32'd0);
      run_dma_job(.tag({tag, "_post"}), .opq_words(32), .send_eoe(1'b1),
                  .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd1),
                  .timeout_cycles(300000));
      check_conservation(tag);
    endtask

    task run_profile_aw_to_w_latency_metric_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit pending_aw;
      int unsigned cycle_count;
      int unsigned sample_count;
      int unsigned sum_cycles;

      stop_monitor = 1'b0;
      pending_aw = 1'b0;
      cycle_count = 0;
      sample_count = 0;
      sum_cycles = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.m_axi_awvalid && vif.m_axi_awready) begin
              pending_aw = 1'b1;
              cycle_count = 0;
            end else if (pending_aw) begin
              cycle_count++;
            end
            if (pending_aw && vif.m_axi_wvalid && vif.m_axi_wready) begin
              sum_cycles += cycle_count;
              sample_count++;
              pending_aw = 1'b0;
            end
          end
        end
      join_none
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(8),
                    .send_eoe(1'b1),
                    .wready_lag(0),
                    .bvalid_lag(1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(300000));
      end
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (sample_count < job_count)
        `uvm_error(tag, $sformatf("AW-to-W samples got=%0d expected>=%0d",
                                  sample_count, job_count))
      if (sample_count == 0 || sum_cycles == 0)
        `uvm_error(tag, "AW-to-W latency metric did not accumulate")
      check_conservation(tag);
    endtask

    task run_profile_wlast_to_bvalid_metric_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit pending_wlast;
      int unsigned cycle_count;
      int unsigned sample_count;
      int unsigned sum_cycles;

      stop_monitor = 1'b0;
      pending_wlast = 1'b0;
      cycle_count = 0;
      sample_count = 0;
      sum_cycles = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.m_axi_wvalid && vif.m_axi_wready && vif.m_axi_wlast) begin
              pending_wlast = 1'b1;
              cycle_count = 0;
            end else if (pending_wlast) begin
              cycle_count++;
            end
            if (pending_wlast && vif.m_axi_bvalid) begin
              sum_cycles += cycle_count;
              sample_count++;
              pending_wlast = 1'b0;
            end
          end
        end
      join_none
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(8),
                    .send_eoe(1'b1),
                    .wready_lag(0),
                    .bvalid_lag(8),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(300000));
      end
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (sample_count < job_count)
        `uvm_error(tag, $sformatf("WLAST-to-BVALID samples got=%0d expected>=%0d",
                                  sample_count, job_count))
      if (sample_count == 0 || sum_cycles == 0)
        `uvm_error(tag, "WLAST-to-BVALID latency metric did not accumulate")
      check_conservation(tag);
    endtask

    task run_profile_job_req_to_aw_metric_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit pending_req;
      int unsigned cycle_count;
      int unsigned sample_count;
      int unsigned sum_cycles;

      stop_monitor = 1'b0;
      pending_req = 1'b0;
      cycle_count = 0;
      sample_count = 0;
      sum_cycles = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.job_req) begin
              pending_req = 1'b1;
              cycle_count = 0;
            end else if (pending_req) begin
              cycle_count++;
            end
            if (pending_req && vif.m_axi_awvalid && vif.m_axi_awready) begin
              sum_cycles += cycle_count;
              sample_count++;
              pending_req = 1'b0;
            end
          end
        end
      join_none
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(8),
                    .send_eoe(1'b1),
                    .wready_lag(0),
                    .bvalid_lag(1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(300000));
      end
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (sample_count < job_count)
        `uvm_error(tag, $sformatf("job_req-to-AW samples got=%0d expected>=%0d",
                                  sample_count, job_count))
      if (sample_count == 0)
        `uvm_error(tag, "job_req-to-AW latency metric did not accumulate")
      check_conservation(tag);
    endtask

    task run_profile_b_to_done_metric_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit pending_b;
      int unsigned cycle_count;
      int unsigned sample_count;
      int unsigned sum_cycles;

      stop_monitor = 1'b0;
      pending_b = 1'b0;
      cycle_count = 0;
      sample_count = 0;
      sum_cycles = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.m_axi_bvalid && vif.m_axi_bready) begin
              pending_b = 1'b1;
              cycle_count = 0;
            end else if (pending_b) begin
              cycle_count++;
            end
            if (pending_b && vif.job_done) begin
              sum_cycles += cycle_count;
              sample_count++;
              pending_b = 1'b0;
            end
          end
        end
      join_none
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(8),
                    .send_eoe(1'b1),
                    .wready_lag(0),
                    .bvalid_lag(2),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(300000));
      end
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (sample_count < job_count)
        `uvm_error(tag, $sformatf("B-to-done samples got=%0d expected>=%0d",
                                  sample_count, job_count))
      check_conservation(tag);
    endtask

    task run_profile_awlen_distribution_case(
      input string tag,
      input int unsigned min_bursts,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned aw_count_local;
      bit saw_single;
      bit saw_mid;
      bit saw_max;

      stop_monitor = 1'b0;
      aw_count_local = 0;
      saw_single = 1'b0;
      saw_mid = 1'b0;
      saw_max = 1'b0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.m_axi_awvalid && vif.m_axi_awready) begin
              aw_count_local++;
              if (vif.m_axi_awlen == 8'd0)
                saw_single = 1'b1;
              if (vif.m_axi_awlen inside {[8'd1:8'd14]})
                saw_mid = 1'b1;
              if (vif.m_axi_awlen == 8'd15)
                saw_max = 1'b1;
            end
          end
        end
      join_none
      run_profile_single_load_case(.tag({tag, "_max"}), .opq_words(128000),
                                   .idle_after_each(0),
                                   .wready_lag(0), .bvalid_lag(1),
                                   .sqe_id(sqe_id),
                                   .sequence_no(sequence_no));
      for (int unsigned idx = 0; idx < 8; idx++) begin
        run_dma_job(.tag($sformatf("%s_short%0d", tag, idx)),
                    .opq_words(8),
                    .send_eoe(1'b1),
                    .sqe_id(sqe_id + 16'd1 + idx[15:0]),
                    .sequence_no(sequence_no + 32'd1 + idx),
                    .timeout_cycles(300000));
        run_dma_job(.tag($sformatf("%s_mid%0d", tag, idx)),
                    .opq_words(64),
                    .send_eoe(1'b1),
                    .sqe_id(sqe_id + 16'd16 + idx[15:0]),
                    .sequence_no(sequence_no + 32'd16 + idx),
                    .timeout_cycles(300000));
      end
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (aw_count_local < min_bursts)
        `uvm_error(tag, $sformatf("AW burst histogram got=%0d expected>=%0d",
                                  aw_count_local, min_bursts))
      if (!saw_single || !saw_mid || !saw_max)
        `uvm_error(tag, "AWLEN histogram missed single, mid, or max bins")
      check_conservation(tag);
    endtask

    task run_profile_fifo_occupancy_histogram_case(
      input string tag,
      input int unsigned opq_words,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit saw_empty;
      bit saw_low;
      bit saw_mid;
      bit saw_high;
      int unsigned max_level;

      stop_monitor = 1'b0;
      saw_empty = 1'b0;
      saw_low = 1'b0;
      saw_mid = 1'b0;
      saw_high = 1'b0;
      max_level = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.dbg1_fifo_level > max_level)
              max_level = vif.dbg1_fifo_level;
            if (vif.dbg1_fifo_level == 9'd0)
              saw_empty = 1'b1;
            if ((vif.dbg1_fifo_level > 9'd0) &&
                (vif.dbg1_fifo_level < 9'd8))
              saw_low = 1'b1;
            if ((vif.dbg1_fifo_level >= 9'd8) &&
                (vif.dbg1_fifo_level < 9'd16))
              saw_mid = 1'b1;
            if (vif.dbg1_fifo_level >= 9'd16)
              saw_high = 1'b1;
          end
      end
      join_none
      run_profile_single_load_case(.tag(tag), .opq_words(opq_words),
                                   .idle_after_each(0),
                                   .wready_lag(8), .bvalid_lag(8),
                                   .sqe_id(sqe_id),
                                   .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (!saw_empty || !saw_low || !saw_mid || !saw_high)
        `uvm_error(tag, "FIFO occupancy histogram missed an expected bin")
      if (max_level < 16)
        `uvm_error(tag, $sformatf("fifo max_level got=%0d expected >=16",
                                  max_level))
      check_conservation(tag);
    endtask

    task run_profile_fifo_convergence_case(
      input string tag,
      input int unsigned opq_words,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      longint unsigned early_sum;
      longint unsigned late_sum;
      int unsigned early_avg;
      int unsigned late_avg;
      int unsigned diff_avg;

      stop_monitor = 1'b0;
      early_sum = 0;
      late_sum = 0;
      fork
        begin
          for (int unsigned cycle = 0; cycle < 3000; cycle++) begin
            @(posedge vif.clk);
            if ((cycle >= 100) && (cycle < 1100))
              early_sum += vif.dbg1_fifo_level;
            if ((cycle >= 1900) && (cycle < 2900))
              late_sum += vif.dbg1_fifo_level;
          end
          stop_monitor = 1'b1;
        end
        begin
          run_profile_single_load_case(.tag(tag), .opq_words(opq_words),
                                       .idle_after_each(0),
                                       .wready_lag(8), .bvalid_lag(8),
                                       .sqe_id(sqe_id),
                                       .sequence_no(sequence_no));
        end
      join
      early_avg = int'(early_sum / 1000);
      late_avg = int'(late_sum / 1000);
      diff_avg = (early_avg > late_avg) ? (early_avg - late_avg) :
                 (late_avg - early_avg);
      if ((early_avg == 0) || (late_avg == 0))
        `uvm_error(tag, "FIFO convergence averages did not accumulate")
      if (diff_avg > 16)
        `uvm_error(tag, $sformatf("FIFO convergence delta got=%0d expected<=16",
                                  diff_avg))
      if (!stop_monitor)
        `uvm_error(tag, "FIFO convergence monitor did not finish")
      check_conservation(tag);
    endtask

    task run_profile_halt_rate_convergence_case(
      input string tag,
      input int unsigned sample_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit [31:0] deltas [64];

      for (int unsigned idx = 0; idx < sample_count; idx++) begin
        bit [31:0] before_halt;
        before_halt = vif.cnt_halt;
        run_halt_count_job(.tag($sformatf("%s_halt%0d", tag, idx)),
                           .dropped_words(16),
                           .sqe_id(sqe_id + idx[15:0]),
                           .sequence_no(sequence_no + idx));
        deltas[idx] = vif.cnt_halt - before_halt;
        if (deltas[idx] == 32'd0)
          `uvm_error(tag, $sformatf("halt sample %0d had zero delta", idx))
      end
      for (int unsigned idx = 1; idx < sample_count; idx++) begin
        bit [31:0] diff_delta;
        diff_delta = (deltas[idx] > deltas[0]) ?
                     (deltas[idx] - deltas[0]) :
                     (deltas[0] - deltas[idx]);
        if (diff_delta > 32'd1)
          `uvm_error(tag, $sformatf("halt-rate delta sample %0d got=%0d base=%0d",
                                    idx, deltas[idx], deltas[0]))
      end
      check_conservation(tag);
    endtask

    task run_profile_latency_p99_stability_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned early_samples [512];
      int unsigned late_samples [512];
      int unsigned early_count;
      int unsigned late_count;
      int unsigned p99_early;
      int unsigned p99_late;
      int unsigned diff_cycles;
      int unsigned allowed_cycles;

      early_count = 0;
      late_count = 0;
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        bit stop_monitor;
        int unsigned cycle_count;
        stop_monitor = 1'b0;
        cycle_count = 0;
        fork
          begin
            while (!stop_monitor) begin
              @(posedge vif.clk);
              if (vif.reset_n === 1'b1)
                cycle_count++;
            end
          end
        join_none
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(8),
                    .send_eoe(1'b1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(300000));
        stop_monitor = 1'b1;
        wait_cycles(1);
        if (idx < (job_count / 4)) begin
          early_samples[early_count] = cycle_count;
          early_count++;
        end else if (idx >= ((job_count * 3) / 4)) begin
          late_samples[late_count] = cycle_count;
          late_count++;
        end
      end
      for (int unsigned outer = 0; outer < early_count; outer++) begin
        for (int unsigned inner = outer + 1; inner < early_count; inner++) begin
          if (early_samples[inner] < early_samples[outer]) begin
            int unsigned tmp;
            tmp = early_samples[outer];
            early_samples[outer] = early_samples[inner];
            early_samples[inner] = tmp;
          end
        end
      end
      for (int unsigned outer = 0; outer < late_count; outer++) begin
        for (int unsigned inner = outer + 1; inner < late_count; inner++) begin
          if (late_samples[inner] < late_samples[outer]) begin
            int unsigned tmp;
            tmp = late_samples[outer];
            late_samples[outer] = late_samples[inner];
            late_samples[inner] = tmp;
          end
        end
      end
      p99_early = early_samples[(early_count * 99) / 100];
      p99_late = late_samples[(late_count * 99) / 100];
      diff_cycles = (p99_early > p99_late) ? (p99_early - p99_late) :
                    (p99_late - p99_early);
      allowed_cycles = (p99_early / 20) + 2;
      if ((early_count == 0) || (late_count == 0))
        `uvm_error(tag, "latency p99 windows did not accumulate")
      if (diff_cycles > allowed_cycles)
        `uvm_error(tag, $sformatf("p99 latency delta got=%0d allowed=%0d early=%0d late=%0d",
                                  diff_cycles, allowed_cycles,
                                  p99_early, p99_late))
      check_conservation(tag);
    endtask

    task run_profile_random_aw_burst_sweep_case(
      input string tag,
      input int unsigned iteration_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit saw_len0;
      bit saw_len_mid;
      bit saw_len15;

      stop_monitor = 1'b0;
      saw_len0 = 1'b0;
      saw_len_mid = 1'b0;
      saw_len15 = 1'b0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.m_axi_awvalid && vif.m_axi_awready) begin
              if (vif.m_axi_awlen == 8'd0)
                saw_len0 = 1'b1;
              if (vif.m_axi_awlen inside {[8'd1:8'd14]})
                saw_len_mid = 1'b1;
              if (vif.m_axi_awlen == 8'd15)
                saw_len15 = 1'b1;
            end
          end
        end
      join_none
      for (int unsigned idx = 0; idx < iteration_count; idx++) begin
        int unsigned words_v;
        case (idx % 4)
          0: words_v = 8;
          1: words_v = 64;
          2: words_v = 128;
          default: words_v = 8 + ((idx * 17) % 192);
        endcase
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(words_v),
                    .send_eoe(1'b1),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(400000));
      end
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (!saw_len0 || !saw_len_mid || !saw_len15)
        `uvm_error(tag, "random AW burst sweep missed required AWLEN bins")
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      iteration_count[31:0]);
      check_conservation(tag);
    endtask

    task run_profile_random_packer_sweep_case(
      input string tag,
      input int unsigned iteration_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit seen_slot [8];

      for (int unsigned slot = 0; slot < RDMA_DMA_OPQ_PER_BEAT; slot++)
        seen_slot[slot] = 1'b0;
      for (int unsigned idx = 0; idx < iteration_count; idx++) begin
        int unsigned words_v;
        int unsigned slot_v;
        words_v = 1 + ((idx * 37) % 96);
        slot_v = words_v % RDMA_DMA_OPQ_PER_BEAT;
        if (slot_v == 0)
          slot_v = RDMA_DMA_OPQ_PER_BEAT;
        seen_slot[slot_v - 1] = 1'b1;
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(words_v),
                    .send_eoe(1'b1),
                    .idle_after_each(idx % 3),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(400000));
      end
      for (int unsigned slot = 0; slot < RDMA_DMA_OPQ_PER_BEAT; slot++) begin
        if (!seen_slot[slot])
          `uvm_error(tag, $sformatf("packer EOE slot %0d not covered", slot))
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      iteration_count[31:0]);
      check_conservation(tag);
    endtask

    task run_profile_random_fifo_sweep_case(
      input string tag,
      input int unsigned iteration_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      bit saw_empty;
      bit saw_low;
      bit saw_mid;
      bit saw_high;

      stop_monitor = 1'b0;
      saw_empty = 1'b0;
      saw_low = 1'b0;
      saw_mid = 1'b0;
      saw_high = 1'b0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.dbg1_fifo_level == 9'd0)
              saw_empty = 1'b1;
            if ((vif.dbg1_fifo_level > 9'd0) &&
                (vif.dbg1_fifo_level < 9'd16))
              saw_low = 1'b1;
            if ((vif.dbg1_fifo_level >= 9'd16) &&
                (vif.dbg1_fifo_level < 9'd96))
              saw_mid = 1'b1;
            if (vif.dbg1_fifo_level >= 9'd96)
              saw_high = 1'b1;
          end
      end
      join_none
      for (int unsigned idx = 0; idx < iteration_count; idx++) begin
        if ((idx % 64) == 0) begin
          int unsigned target_level_v;
          case (idx / 64)
            0: target_level_v = 1;
            1: target_level_v = 32;
            2: target_level_v = 128;
            default: target_level_v = 192;
          endcase
          run_profile_fifo_hold_case(.tag($sformatf("%s_hold%0d", tag, idx)),
                                     .target_level(target_level_v),
                                     .hold_cycles(8),
                                     .expect_almost_full(target_level_v >= 192),
                                     .sqe_id(sqe_id + idx[15:0]),
                                     .sequence_no(sequence_no + idx));
        end else begin
          run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                      .opq_words(64 + ((idx * 29) % 192)),
                      .send_eoe(1'b1),
                      .wready_lag((idx % 5) == 0 ? 128 : (idx % 17)),
                      .bvalid_lag(1 + ((idx * 13) % 31)),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(700000));
        end
      end
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (!saw_empty || !saw_low || !saw_mid || !saw_high)
        `uvm_error(tag, "random FIFO sweep missed expected occupancy bins")
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      iteration_count[31:0]);
      check_conservation(tag);
    endtask

    task run_profile_status_cross_sweep_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit saw_clean;
      bit saw_align;
      bit saw_full;
      bit saw_boundary;
      bit saw_halt;

      saw_clean = 1'b0;
      saw_align = 1'b0;
      saw_full = 1'b0;
      saw_boundary = 1'b0;
      saw_halt = 1'b0;
      run_dma_job(.tag({tag, "_clean"}), .opq_words(16),
                  .send_eoe(1'b1), .sqe_id(sqe_id),
                  .sequence_no(sequence_no), .timeout_cycles(300000));
      saw_clean = (vif.job_status[RDMA_DMA_ST_EOE] &&
                   vif.job_status[RDMA_DMA_ST_SEG0_ONLY]);
      run_dma_job(.tag({tag, "_align"}), .seg0_addr(64'h0000_0000_0010_0001),
                  .opq_words(0), .send_eoe(1'b0),
                  .sqe_id(sqe_id + 16'd1),
                  .sequence_no(sequence_no + 32'd1),
                  .timeout_cycles(300000));
      saw_align = vif.job_status[RDMA_DMA_ST_ALIGN_ERR];
      run_dma_job(.tag({tag, "_full"}), .seg0_span(64'h1000),
                  .opq_words(1024), .send_eoe(1'b0),
                  .sqe_id(sqe_id + 16'd2),
                  .sequence_no(sequence_no + 32'd2),
                  .timeout_cycles(300000));
      saw_full = vif.job_status[RDMA_DMA_ST_FULL];
      run_dma_job(.tag({tag, "_boundary"}), .seg0_span(64'h1000),
                  .seg1_span(64'h1000), .opq_words(1032),
                  .send_eoe(1'b1), .sqe_id(sqe_id + 16'd3),
                  .sequence_no(sequence_no + 32'd3),
                  .timeout_cycles(300000));
      saw_boundary = vif.job_status[RDMA_DMA_ST_SEG_BOUNDARY_HIT];
      run_halt_count_job(.tag({tag, "_halt"}), .dropped_words(16),
                         .sqe_id(sqe_id + 16'd4),
                         .sequence_no(sequence_no + 32'd4));
      saw_halt = vif.job_status[RDMA_DMA_ST_HALT];
      if (!saw_clean || !saw_align || !saw_full ||
          !saw_boundary || !saw_halt)
        `uvm_error(tag, "status cross sweep missed an expected status class")
      check_conservation(tag);
    endtask

    task run_profile_dbg2_lineage_sweep_case(
      input string tag,
      input int unsigned iteration_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned idx = 0; idx < iteration_count; idx++) begin
        run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                    .opq_words(1 + ((idx * 31) % 96)),
                    .send_eoe(1'b1),
                    .idle_after_each(idx % 5),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(400000));
      end
      if (env.debug_level >= 2) begin
        if (env.scb.dbg2_emit_count == 0)
          `uvm_error(tag, "DEBUG2 lineage sweep emitted no sidecar records")
        if (env.scb.dbg2_emit_count != env.scb.opq_count)
          `uvm_error(tag, $sformatf("DEBUG2 lineage count got=%0d opq=%0d",
                                    env.scb.dbg2_emit_count,
                                    env.scb.opq_count))
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      iteration_count[31:0]);
      check_conservation(tag);
    endtask

    task run_profile_sidecar_wallclock_case(
      input string tag,
      input int unsigned opq_words,
      input int unsigned max_cycles,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      bit stop_monitor;
      int unsigned cycle_count;

      stop_monitor = 1'b0;
      cycle_count = 0;
      fork
        begin
          while (!stop_monitor) begin
            @(posedge vif.clk);
            if (vif.reset_n === 1'b1)
              cycle_count++;
          end
        end
      join_none
      run_profile_single_load_case(.tag(tag), .opq_words(opq_words),
                                   .idle_after_each(0),
                                   .wready_lag(0), .bvalid_lag(1),
                                   .sqe_id(sqe_id),
                                   .sequence_no(sequence_no));
      stop_monitor = 1'b1;
      wait_cycles(1);
      if (cycle_count == 0)
        `uvm_error(tag, "sidecar wallclock monitor did not accumulate")
      if (cycle_count > max_cycles)
        `uvm_error(tag, $sformatf("sidecar wallclock cycles got=%0d max=%0d",
                                  cycle_count, max_cycles))
      if ((env.debug_level >= 2) &&
          (env.scb.dbg2_emit_count != env.scb.opq_count))
        `uvm_error(tag, $sformatf("sidecar emit count got=%0d opq=%0d",
                                  env.scb.dbg2_emit_count,
                                  env.scb.opq_count))
      check_conservation(tag);
    endtask

    task run_profile_sidecar_overhead_case(
      input string tag,
      input int unsigned opq_words,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned dbg1_before;
      int unsigned dbg2_before;
      int unsigned dbg1_delta;
      int unsigned dbg2_delta;

      dbg1_before = env.scb.dbg1_sample_count;
      dbg2_before = env.scb.dbg2_emit_count;
      run_profile_sidecar_wallclock_case(.tag(tag), .opq_words(opq_words),
                                         .max_cycles(200000),
                                         .sqe_id(sqe_id),
                                         .sequence_no(sequence_no));
      dbg1_delta = env.scb.dbg1_sample_count - dbg1_before;
      dbg2_delta = env.scb.dbg2_emit_count - dbg2_before;
      if (dbg1_delta == 0)
        `uvm_error(tag, "DEBUG1 tap monitor did not sample")
      if ((env.debug_level >= 2) && (dbg2_delta != opq_words))
        `uvm_error(tag, $sformatf("DEBUG2 overhead count got=%0d expected=%0d",
                                  dbg2_delta, opq_words))
    endtask

    task run_profile_stress_halt_rate_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned done_before;
      bit [31:0] halt_before;
      int unsigned halt_jobs;

      done_before = env.scb.job_done_count;
      halt_before = vif.cnt_halt;
      halt_jobs = 0;
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        if ((idx % 20) == 0) begin
          halt_jobs++;
          run_halt_count_job(.tag($sformatf("%s_halt%0d", tag, idx)),
                             .dropped_words(8),
                             .sqe_id(sqe_id + idx[15:0]),
                             .sequence_no(sequence_no + idx));
        end else begin
          run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                      .opq_words(16 + ((idx * 7) % 64)),
                      .send_eoe(1'b1),
                      .idle_after_each(idx % 3),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(400000));
        end
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'(done_before + job_count));
      if (halt_jobs != ((job_count + 19) / 20))
        `uvm_error(tag, $sformatf("halt job count got=%0d expected=%0d",
                                  halt_jobs, (job_count + 19) / 20))
      if ((vif.cnt_halt - halt_before) < (halt_jobs * 8))
        `uvm_error(tag, $sformatf("halt delta got=%0d expected>=%0d",
                                  vif.cnt_halt - halt_before, halt_jobs * 8))
      check_conservation(tag);
    endtask

    task run_profile_periodic_reset_stress_case(
      input string tag,
      input int unsigned reset_count,
      input int unsigned jobs_per_reset,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      for (int unsigned reset_idx = 0; reset_idx < reset_count; reset_idx++) begin
        for (int unsigned job_idx = 0; job_idx < jobs_per_reset; job_idx++) begin
          int unsigned idx;
          idx = reset_idx * jobs_per_reset + job_idx;
          run_dma_job(.tag($sformatf("%s_r%0d_j%0d", tag, reset_idx, job_idx)),
                      .opq_words(8 + ((idx * 5) % 32)),
                      .send_eoe(1'b1),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(300000));
        end
        check_u32_equal(tag, "group job_done_count", env.scb.job_done_count,
                        jobs_per_reset[31:0]);
        if ((vif.cnt_input_w == 32'd0) || (vif.cnt_bytes_written == 32'd0))
          `uvm_error(tag, "periodic reset group did not accumulate counters")
        check_conservation(tag);
        apply_midrun_reset();
        check_reset_defaults(tag);
      end
    endtask

    task run_profile_random_align_stress_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned done_before;
      int unsigned align_jobs;

      done_before = env.scb.job_done_count;
      align_jobs = 0;
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        if ((idx % 10) == 0) begin
          align_jobs++;
          run_dma_job(.tag($sformatf("%s_align%0d", tag, idx)),
                      .seg0_addr(64'h0000_0000_0010_0001),
                      .opq_words(0),
                      .send_eoe(1'b0),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(300000));
          check_status_bit(tag, "status[ALIGN_ERR]", RDMA_DMA_ST_ALIGN_ERR,
                           1'b1);
        end else begin
          run_dma_job(.tag($sformatf("%s_job%0d", tag, idx)),
                      .opq_words(8 + ((idx * 11) % 64)),
                      .send_eoe(1'b1),
                      .sqe_id(sqe_id + idx[15:0]),
                      .sequence_no(sequence_no + idx),
                      .timeout_cycles(300000));
        end
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'(done_before + job_count));
      if (align_jobs != ((job_count + 9) / 10))
        `uvm_error(tag, $sformatf("align injection count got=%0d expected=%0d",
                                  align_jobs, (job_count + 9) / 10))
      check_conservation(tag);
    endtask

    task run_profile_random_opcode_stress_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned done_before;
      int unsigned opcode_0001_count;

      done_before = env.scb.job_done_count;
      opcode_0001_count = 0;
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        opcode_0001_count++;
        run_dma_job(.tag($sformatf("%s_opcode%0d", tag, idx)),
                    .opq_words(4 + ((idx * 17) % 96)),
                    .send_eoe(1'b1),
                    .idle_after_each(idx % 4),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(400000));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'(done_before + job_count));
      if (opcode_0001_count != job_count)
        `uvm_error(tag, "Phase 1 opcode filter generated a non-0x0001 job")
      check_conservation(tag);
    endtask

    task run_profile_basic_bucket_frame_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned done_before;

      done_before = env.scb.job_done_count;
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        run_dma_job(.tag($sformatf("%s_basic%0d", tag, idx)),
                    .opq_words(1 + ((idx * 13) % 128)),
                    .send_eoe(1'b1),
                    .idle_after_each(idx % 5),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(400000));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'(done_before + job_count));
      if (env.scb.opq_count == 0)
        `uvm_error(tag, "basic bucket frame produced no OPQ traffic")
      check_conservation(tag);
    endtask

    task run_profile_edge_bucket_frame_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned done_before;
      bit saw_align;
      bit saw_boundary;
      bit saw_full;
      bit saw_clean;

      done_before = env.scb.job_done_count;
      saw_align = 1'b0;
      saw_boundary = 1'b0;
      saw_full = 1'b0;
      saw_clean = 1'b0;
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        case (idx % 4)
          0: begin
            saw_clean = 1'b1;
            run_dma_job(.tag($sformatf("%s_clean%0d", tag, idx)),
                        .opq_words(16 + idx),
                        .send_eoe(1'b1),
                        .sqe_id(sqe_id + idx[15:0]),
                        .sequence_no(sequence_no + idx),
                        .timeout_cycles(300000));
          end
          1: begin
            saw_align = 1'b1;
            run_dma_job(.tag($sformatf("%s_align%0d", tag, idx)),
                        .seg0_addr(64'h0000_0000_0010_0001),
                        .opq_words(0),
                        .send_eoe(1'b0),
                        .sqe_id(sqe_id + idx[15:0]),
                        .sequence_no(sequence_no + idx),
                        .timeout_cycles(300000));
            check_status_bit(tag, "status[ALIGN_ERR]",
                             RDMA_DMA_ST_ALIGN_ERR, 1'b1);
          end
          2: begin
            saw_boundary = 1'b1;
            run_dma_job(.tag($sformatf("%s_boundary%0d", tag, idx)),
                        .seg0_span(64'h0000_0000_0000_1000),
                        .seg1_span(64'h0000_0000_0000_1000),
                        .opq_words(1032),
                        .send_eoe(1'b1),
                        .sqe_id(sqe_id + idx[15:0]),
                        .sequence_no(sequence_no + idx),
                        .timeout_cycles(600000));
            check_status_bit(tag, "status[SEG_BOUNDARY_HIT]",
                             RDMA_DMA_ST_SEG_BOUNDARY_HIT, 1'b1);
          end
          default: begin
            saw_full = 1'b1;
            run_dma_job(.tag($sformatf("%s_full%0d", tag, idx)),
                        .seg0_span(64'h0000_0000_0000_1000),
                        .opq_words(1024),
                        .send_eoe(1'b0),
                        .sqe_id(sqe_id + idx[15:0]),
                        .sequence_no(sequence_no + idx),
                        .timeout_cycles(600000));
            check_status_bit(tag, "status[FULL]", RDMA_DMA_ST_FULL, 1'b1);
          end
        endcase
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'(done_before + job_count));
      if (!saw_align || !saw_boundary || !saw_full || !saw_clean)
        `uvm_error(tag, "edge bucket frame missed an edge class")
      check_conservation(tag);
    endtask

    task run_profile_all_buckets_frame_case(
      input string tag,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned done_before;

      done_before = env.scb.job_done_count;
      run_profile_basic_bucket_frame_case(.tag({tag, "_basic"}),
                                          .job_count(16),
                                          .sqe_id(sqe_id),
                                          .sequence_no(sequence_no));
      run_profile_edge_bucket_frame_case(.tag({tag, "_edge"}),
                                         .job_count(16),
                                         .sqe_id(sqe_id + 16'd64),
                                         .sequence_no(sequence_no + 32'd64));
      for (int unsigned idx = 0; idx < 16; idx++) begin
        run_dma_job(.tag($sformatf("%s_prof%0d", tag, idx)),
                    .opq_words(32 + ((idx * 19) % 128)),
                    .send_eoe(1'b1),
                    .wready_lag(idx % 7),
                    .bvalid_lag(1 + (idx % 5)),
                    .sqe_id(sqe_id + 16'd128 + idx[15:0]),
                    .sequence_no(sequence_no + 32'd128 + idx),
                    .timeout_cycles(500000));
      end
      for (int unsigned idx = 0; idx < 8; idx++) begin
        run_dma_job(.tag($sformatf("%s_error%0d", tag, idx)),
                    .opq_words(16 + idx),
                    .send_eoe(1'b1),
                    .bresp((idx % 2) == 0 ? axi4_write_pkg::AXI_RESP_OKAY :
                                             axi4_write_pkg::AXI_RESP_SLVERR),
                    .sqe_id(sqe_id + 16'd192 + idx[15:0]),
                    .sequence_no(sequence_no + 32'd192 + idx),
                    .timeout_cycles(400000));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'(done_before + 56));
      if ((env.debug_level >= 2) &&
          (env.scb.dbg2_emit_count > env.scb.opq_count))
        `uvm_error(tag, "DEBUG2 sidecar count exceeded OPQ count")
      check_conservation(tag);
    endtask

    task run_profile_random_long_soak_case(
      input string tag,
      input int unsigned soak_cycles,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned done_before;
      int unsigned interval_cycles;
      int unsigned checkpoint_count;

      done_before = env.scb.job_done_count;
      interval_cycles = (job_count == 0) ? soak_cycles :
                        (soak_cycles / job_count);
      if (interval_cycles == 0)
        interval_cycles = 1;
      checkpoint_count = 0;
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        wait_cycles(interval_cycles);
        run_dma_job(.tag($sformatf("%s_soak%0d", tag, idx)),
                    .opq_words(8 + ((idx * 23) % 96)),
                    .send_eoe(1'b1),
                    .idle_after_each(idx % 7),
                    .wready_lag(idx % 11),
                    .bvalid_lag(1 + (idx % 13)),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(500000));
        if ((idx == 0) || (idx == 9) || (idx == 49) ||
            (idx == (job_count - 1))) begin
          checkpoint_count++;
          check_conservation(tag);
          if ((env.debug_level >= 2) &&
              (env.scb.dbg2_emit_count > env.scb.opq_count))
            `uvm_error(tag, "DEBUG2 checkpoint sidecar count exceeded OPQ count")
        end
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'(done_before + job_count));
      if (checkpoint_count < 4)
        `uvm_error(tag, "long soak did not visit all checkpoint intervals")
      check_conservation(tag);
    endtask

    task run_profile_final_throughput_report_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_profile_throughput_consistency_case(.tag({tag, "_throughput"}),
                                              .seed_a(11),
                                              .seed_b(12),
                                              .job_count(job_count),
                                              .words_per_job(64),
                                              .idle_after_each(0),
                                              .wready_lag(0));
      if ((env.scb.aw_count == 0) || (env.scb.w_count == 0))
        `uvm_error(tag, "final throughput report saw no AXI traffic")
      check_conservation(tag);
    endtask

    task run_profile_final_latency_report_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_profile_latency_p99_stability_case(.tag({tag, "_p99"}),
                                             .job_count(job_count),
                                             .sqe_id(sqe_id),
                                             .sequence_no(sequence_no));
      if (env.scb.job_done_count != job_count[31:0])
        `uvm_error(tag, $sformatf("final latency jobs got=%0d expected=%0d",
                                  env.scb.job_done_count, job_count))
    endtask

    task run_profile_final_halt_rate_report_case(
      input string tag,
      input int unsigned sample_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_profile_halt_rate_convergence_case(.tag({tag, "_halt_rate"}),
                                             .sample_count(sample_count),
                                             .sqe_id(sqe_id),
                                             .sequence_no(sequence_no));
      if (vif.cnt_halt == 32'd0)
        `uvm_error(tag, "final halt-rate report saw no halted words")
      check_conservation(tag);
    endtask

    task run_profile_final_lineage_residual_report_case(
      input string tag,
      input int unsigned iteration_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      run_profile_dbg2_lineage_sweep_case(.tag({tag, "_lineage"}),
                                          .iteration_count(iteration_count),
                                          .sqe_id(sqe_id),
                                          .sequence_no(sequence_no));
      if (env.debug_level >= 2) begin
        if (env.scb.dbg2_emit_count != env.scb.opq_count)
          `uvm_error(tag, $sformatf("final lineage residual got=%0d",
                                    env.scb.opq_count - env.scb.dbg2_emit_count))
      end
    endtask

    task run_profile_dual_build_comparison_case(
      input string tag,
      input int unsigned job_count,
      input bit [15:0] sqe_id,
      input bit [31:0] sequence_no
    );
      int unsigned done_before;
      int unsigned opq_before;
      int unsigned expected_opq;

      done_before = env.scb.job_done_count;
      opq_before = env.scb.opq_count;
      expected_opq = 0;
      for (int unsigned idx = 0; idx < job_count; idx++) begin
        int unsigned words_v;
        words_v = 8 + ((idx * 29) % 96);
        expected_opq += words_v;
        run_dma_job(.tag($sformatf("%s_dual%0d", tag, idx)),
                    .opq_words(words_v),
                    .send_eoe(1'b1),
                    .idle_after_each(idx % 3),
                    .sqe_id(sqe_id + idx[15:0]),
                    .sequence_no(sequence_no + idx),
                    .timeout_cycles(400000));
      end
      check_u32_equal(tag, "job_done_count", env.scb.job_done_count,
                      32'(done_before + job_count));
      if ((env.scb.opq_count - opq_before) != expected_opq)
        `uvm_error(tag, $sformatf("dual-build OPQ count got=%0d expected=%0d",
                                  env.scb.opq_count - opq_before,
                                  expected_opq))
      if ((env.debug_level >= 2) &&
          ((env.scb.dbg2_emit_count - opq_before) != expected_opq))
        `uvm_error(tag, $sformatf("dual-build DEBUG2 count got=%0d expected=%0d",
                                  env.scb.dbg2_emit_count - opq_before,
                                  expected_opq))
      check_conservation(tag);
    endtask

    task run_halt_count_job(
      input string tag,
      input int unsigned dropped_words = 10,
      input bit [15:0] sqe_id = 16'h0100,
      input bit [31:0] sequence_no = 32'd1,
      input bit clear_after_first_halt = 1'b0,
      input bit [1:0] bresp = axi4_write_pkg::AXI_RESP_OKAY
    );
      job_single_segment_sequence job_seq;
      int unsigned accepted_words;
      bit [31:0] halt_before;
      bit [31:0] expected_halt;
      bit [63:0] expected_total;
      bit [15:0] expected_status;
      bit [15:0] status_mask;
      bit reached_almost_full;
      bit drained_below_almost_full;
      int unsigned modeled_slot;
      int unsigned actual_slot;
      bit [31:0] halt_delta;
      int unsigned halt_pulse_count;
      int unsigned lineage_id;
      int unsigned expected_halt_min;

      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 5000;
      env.axi_cfg.bvalid_lag = 1;
      env.axi_cfg.bresp = bresp;
      env.scb.set_allow_non_okay_bresp(bresp != axi4_write_pkg::AXI_RESP_OKAY);

      job_seq = job_single_segment_sequence::type_id::create({tag, "_job_seq"});
      job_seq.seg0_addr = 64'h0000_0000_0040_0000;
      job_seq.seg0_span = 64'h0000_0000_0001_0000;
      job_seq.seg1_addr = 64'h0000_0000_0000_0000;
      job_seq.seg1_span = 64'h0000_0000_0000_0000;
      job_seq.sqe_id = sqe_id;
      job_seq.opcode = 16'h0001;
      job_seq.start(env.job_agent_h.sequencer);
      wait_cycles(2);

      accepted_words = 0;
      lineage_id = next_lineage_id;
      reached_almost_full = 1'b0;
      for (int unsigned word_idx = 0; word_idx < 4096; word_idx++) begin
        if (vif.dbg1_fifo_almost_full) begin
          reached_almost_full = 1'b1;
          break;
        end
        accepted_words++;
        lineage_id++;
        drive_direct_opq_word({8'h00, sequence_no[15:0], accepted_words[7:0]},
                              1'b0, sequence_no, lineage_id);
      end
      if (!reached_almost_full)
        `uvm_fatal(tag, "fifo_almost_full did not assert before halt injection")

      wait_cycles(2);
      modeled_slot = accepted_words % RDMA_DMA_OPQ_PER_BEAT;
      actual_slot = vif.dbg1_packer_slot_idx;
      while (modeled_slot != actual_slot) begin
        if (!env.scb.drop_last_partial_opq())
          `uvm_fatal(tag, "could not reconcile dropped almost-full boundary word")
        accepted_words--;
        modeled_slot = accepted_words % RDMA_DMA_OPQ_PER_BEAT;
      end

      halt_before = vif.cnt_halt;
      halt_pulse_count = 0;
      env.scb.ignore_next_opq(dropped_words);
      for (int unsigned drop_idx = 0; drop_idx < dropped_words; drop_idx++) begin
        lineage_id++;
        drive_direct_opq_word({8'h00, sequence_no[15:0], drop_idx[7:0]},
                              1'b0, sequence_no, lineage_id);
        if (vif.dbg1_halt_pulse)
          halt_pulse_count++;
        if (clear_after_first_halt && (drop_idx == 0)) begin
          pulse_clear_counters();
          halt_before = 32'd0;
        end
      end
      wait_cycles(4);
      halt_delta = vif.cnt_halt - halt_before;
      expected_halt_min = clear_after_first_halt ?
                          (dropped_words - 1) : dropped_words;
      if (halt_delta < expected_halt_min[31:0])
        `uvm_error(tag, $sformatf("cnt_halt delta got=%0d expected at least %0d",
                                  halt_delta, expected_halt_min))
      if (halt_pulse_count != dropped_words)
        `uvm_error(tag, $sformatf("dbg1_halt_pulse count got=%0d expected=%0d",
                                  halt_pulse_count, dropped_words))
      expected_halt = vif.cnt_halt;

      env.axi_cfg.wready_lag = 0;
      drained_below_almost_full = 1'b0;
      for (int unsigned cycle = 0; cycle < 20000; cycle++) begin
        @(posedge vif.clk);
        if (!vif.dbg1_fifo_almost_full) begin
          drained_below_almost_full = 1'b1;
          break;
        end
      end
      if (!drained_below_almost_full)
        `uvm_fatal(tag, "fifo_almost_full did not clear after host drain resumed")

      accepted_words++;
      lineage_id++;
      expected_total = 64'(accepted_words) * 64'd4;
      expected_status = 16'h0000;
      status_mask = 16'h0000;
      status_mask[RDMA_DMA_ST_EOE] = 1'b1;
      status_mask[RDMA_DMA_ST_FULL] = 1'b1;
      status_mask[RDMA_DMA_ST_HALT] = 1'b1;
      status_mask[RDMA_DMA_ST_SEG0_ONLY] = 1'b1;
      expected_status[RDMA_DMA_ST_EOE] = 1'b1;
      expected_status[RDMA_DMA_ST_HALT] = 1'b1;
      expected_status[RDMA_DMA_ST_SEG0_ONLY] = 1'b1;
      if (bresp != axi4_write_pkg::AXI_RESP_OKAY) begin
        status_mask[6] = 1'b1;
        expected_status[6] = 1'b1;
      end
      env.scb.expect_job(expected_total, expected_total[31:0], 32'h0000_0000,
                         expected_status, status_mask, sqe_id);
      drive_direct_opq_word({8'h00, sequence_no[15:0], accepted_words[7:0]},
                            1'b1, sequence_no, lineage_id);

      wait_for_done(300000);
      wait_cycles(2);
      check_u32_equal(tag, "cnt_halt", vif.cnt_halt, expected_halt);
      check_status_bit(tag, "status[HALT]", RDMA_DMA_ST_HALT, 1'b1);
      // A mid-stream clear intentionally breaks absolute counter conservation.
      if (!clear_after_first_halt)
        check_conservation(tag);

      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
      env.axi_cfg.bresp = axi4_write_pkg::AXI_RESP_OKAY;
      env.scb.set_allow_non_okay_bresp(1'b0);
      next_lineage_id = lineage_id;
    endtask

    task run_reset_mid_aw_case(input string tag);
      job_single_segment_sequence job_seq;
      opq_axis_event_sequence opq_seq;
      env.axi_cfg.awready_lag = 64;
      job_seq = job_single_segment_sequence::type_id::create({tag, "_job_seq"});
      opq_seq = opq_axis_event_sequence::type_id::create({tag, "_opq_seq"});
      opq_seq.word_count = 64;
      job_seq.start(env.job_agent_h.sequencer);
      wait_cycles(2);
      opq_seq.start(env.opq_agent.sequencer);
      for (int unsigned cycle = 0; cycle < 200; cycle++) begin
        @(posedge vif.clk);
        if (vif.m_axi_awvalid)
          break;
      end
      if (!vif.m_axi_awvalid)
        `uvm_error(tag, "AW did not assert before mid-AW reset")
      apply_midrun_reset();
      env.axi_cfg.awready_lag = 0;
      check_reset_defaults(tag);
    endtask

    task run_phase_b_case(input string id);
      int unsigned num;
      byte prefix;
      int unsigned words;
      bit two_seg;
      bit send_eoe;
      bit zero_eoe;
      bit [63:0] seg0_span;
      bit [63:0] seg1_span;
      bit [63:0] seg0_addr;
      bit [63:0] seg1_addr;
      int unsigned aw_lag;
      int unsigned w_lag;
      int unsigned b_lag;
      int unsigned idle_after_each;
      bit [1:0] bresp;
      bit [15:0] sqe_id;

      num = phase_b_case_num(id);
      prefix = phase_b_case_prefix(id);
      words = 8 + (num % 9);
      two_seg = 1'b0;
      send_eoe = 1'b1;
      zero_eoe = 1'b0;
      seg0_span = 64'h1000;
      seg1_span = 64'h0;
      seg0_addr = 64'h0000_0000_0010_0000 + (64'(num % 16) << 12);
      seg1_addr = 64'h0000_0000_0020_0000 + (64'(num % 16) << 12);
      aw_lag = 0;
      w_lag = 0;
      b_lag = 1;
      idle_after_each = 0;
      bresp = axi4_write_pkg::AXI_RESP_OKAY;
      sqe_id = {8'h00, prefix, num[7:0]};

      if ((prefix == "B") && (num <= 12)) begin
        if (num == 10)
          run_reset_mid_aw_case(id);
        else
          check_reset_defaults(id);
        return;
      end

      if (prefix == "B") begin
        if ((num >= 13) && (num <= 28)) begin
          case (num)
            13: words = 8;
            14: words = 16;
            15: words = 128;
            16: words = 256;
            17: begin
              seg0_span = 64'h2000;
              words = 2048;
              send_eoe = 1'b0;
            end
            18: words = 1;
            19: words = 4;
            20: words = 7;
            21: words = 8;
            22: begin
              words = 0;
              zero_eoe = 1'b1;
            end
            23: words = 32;
            24: begin
              words = 8;
              sqe_id = 16'hbeef;
            end
            25: begin
              words = 8;
              sqe_id = 16'h0000;
            end
            26: begin
              words = 8;
              sqe_id = 16'hffff;
            end
            27: begin
              words = 8;
              seg0_addr = 64'h0000_0000_0000_0000;
            end
            28: begin
              words = 8;
              seg0_addr = 64'h0000_0000_ffff_f000;
            end
            default: words = 8;
          endcase
        end else if ((num >= 29) && (num <= 40)) begin
          two_seg = 1'b1;
          seg1_span = 64'h1000;
          case (num)
            29: begin
              words = 2048;
              send_eoe = 1'b0;
            end
            30: begin
              seg0_span = 64'h2000;
              words = 1024;
              send_eoe = 1'b1;
            end
            31: begin
              seg1_span = 64'h2000;
              words = 1536;
              send_eoe = 1'b1;
            end
            32: begin
              words = 1024;
              send_eoe = 1'b1;
            end
            33: begin
              words = 2048;
              send_eoe = 1'b0;
            end
            34: begin
              words = 2048;
              send_eoe = 1'b0;
              seg1_addr = 64'h0000_0000_00a0_0000;
            end
            35: begin
              words = 2048;
              send_eoe = 1'b0;
            end
            36: begin
              seg0_span = 64'h0010_0000;
              seg1_span = 64'h0010_0000;
              words = 4096;
              send_eoe = 1'b1;
            end
            37: begin
              words = 2048;
              send_eoe = 1'b0;
              sqe_id = 16'hcafe;
            end
            38: begin
              words = 2048;
              send_eoe = 1'b0;
            end
            39: begin
              words = 2048;
              send_eoe = 1'b0;
              seg1_addr = seg0_addr;
            end
            40: begin
              words = 2048;
              send_eoe = 1'b1;
            end
            default: begin
              words = 2048;
              send_eoe = 1'b0;
            end
          endcase
        end else if ((num >= 41) && (num <= 62)) begin
          case (num)
            41: words = 8;
            42: words = 128;
            43, 44, 45, 46, 49, 50, 53, 54, 55, 57, 58, 59, 61, 62: words = 512;
            47: begin
              words = 32;
              idle_after_each = 2;
            end
            48: begin
              words = 128;
              seg0_span = 64'h1000;
            end
            51: words = 32;
            52: words = 32;
            56: words = 4;
            60: words = 128;
            default: words = 64;
          endcase
          aw_lag = ((num == 42) || (num == 46) || (num == 52)) ? 80 : 0;
          w_lag = (num == 51) ? 4 : 0;
          b_lag = ((num == 59) || (num == 60)) ? ((num == 60) ? 100 : 0) : 1;
        end else if ((num >= 65) && (num <= 80)) begin
          case (num)
            65: begin
              run_dma_job(.tag(id), .opq_words(5), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num),
                          .timeout_cycles(300000));
              check_u32_equal(id, "cnt_bytes_written", vif.cnt_bytes_written,
                              32'd20);
            end
            66: begin
              run_dma_multi_event_job(.tag(id), .event_count(5),
                                      .words_per_event(8), .gap_cycles(0),
                                      .sqe_id(sqe_id), .sequence_no(num),
                                      .bvalid_lag(120));
            end
            67: begin
              run_halt_count_job(.tag(id), .dropped_words(10),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            68: begin
              run_halt_count_job(.tag(id), .dropped_words(7),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            69: begin
              run_dma_job(.tag({id, "_job0"}), .opq_words(128),
                          .send_eoe(1'b1), .sqe_id(sqe_id),
                          .sequence_no(num));
              run_dma_job(.tag({id, "_job1"}), .opq_words(256),
                          .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                          .sequence_no(num + 32'd100));
              check_conservation(id);
            end
            70: begin
              run_dma_job(.tag({id, "_job0"}), .seg0_span(64'h1000),
                          .opq_words(128), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num));
              run_dma_job(.tag({id, "_job1"}), .seg0_span(64'h2000),
                          .opq_words(256), .send_eoe(1'b1),
                          .sqe_id(sqe_id + 16'd1),
                          .sequence_no(num + 32'd100));
              run_dma_job(.tag({id, "_job2"}), .seg0_span(64'h4000),
                          .opq_words(512), .send_eoe(1'b1),
                          .sqe_id(sqe_id + 16'd2),
                          .sequence_no(num + 32'd200));
              check_conservation(id);
            end
            71: begin
              run_dma_job(.tag({id, "_job0"}), .opq_words(64),
                          .send_eoe(1'b1), .sqe_id(sqe_id),
                          .sequence_no(num));
              if (vif.cnt_input_w < 32'd64)
                `uvm_error(id, "cnt_input_w did not increment after job0")
              run_dma_job(.tag({id, "_job1"}), .opq_words(64),
                          .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                          .sequence_no(num + 32'd100));
              check_u32_equal(id, "cnt_input_w", vif.cnt_input_w, 32'd128);
            end
            72: begin
              run_dma_job(.tag(id), .opq_words(100), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num));
              pulse_clear_counters();
              check_u32_equal(id, "cnt_input_w", vif.cnt_input_w, 32'd0);
              check_u32_equal(id, "cnt_bytes_written", vif.cnt_bytes_written,
                              32'd0);
              check_u32_equal(id, "cnt_halt", vif.cnt_halt, 32'd0);
              check_u32_equal(id, "cnt_eoe_observed", vif.cnt_eoe_observed,
                              32'd0);
            end
            73: begin
              run_dma_job(.tag(id), .opq_words(8), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num));
              check_u32_equal(id, "job_event_count", vif.job_event_count,
                              32'd1);
              check_u64_equal(id, "job_first_event_ts", vif.job_first_event_ts,
                              vif.job_last_event_ts);
            end
            74: begin
              run_dma_multi_event_job(.tag(id), .event_count(3),
                                      .words_per_event(8), .gap_cycles(100),
                                      .sqe_id(sqe_id), .sequence_no(num),
                                      .bvalid_lag(300));
              if (vif.job_first_event_ts >= vif.job_last_event_ts)
                `uvm_error(id, "first_event_ts did not precede last_event_ts")
            end
            75: begin
              run_dma_job(.tag(id), .opq_words(8), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num));
              if (vif.job_first_event_ts == 64'h0)
                `uvm_error(id, "first_event_ts did not capture a nonzero EOE cycle")
            end
            76: begin
              run_dma_multi_event_job(.tag(id), .event_count(5),
                                      .words_per_event(8), .gap_cycles(20),
                                      .sqe_id(sqe_id), .sequence_no(num),
                                      .bvalid_lag(120));
              if (vif.job_last_event_ts <= vif.job_first_event_ts)
                `uvm_error(id, "last_event_ts did not advance on later EOE")
            end
            77: begin
              run_dma_job(.tag(id), .seg0_span(64'h1000), .opq_words(1024),
                          .send_eoe(1'b0), .sqe_id(sqe_id),
                          .sequence_no(num), .timeout_cycles(300000));
              check_u32_equal(id, "job_event_count", vif.job_event_count,
                              32'd0);
              check_status_bit(id, "status[EOE]", RDMA_DMA_ST_EOE, 1'b0);
              check_status_bit(id, "status[FULL]", RDMA_DMA_ST_FULL, 1'b1);
            end
            78: begin
              run_dma_multi_event_job(.tag(id), .event_count(100),
                                      .words_per_event(1), .gap_cycles(0),
                                      .sqe_id(sqe_id), .sequence_no(num),
                                      .bvalid_lag(800), .timeout_cycles(600000));
            end
            79: begin
              run_dma_job(.tag(id), .opq_words(8), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num));
              check_status_bit(id, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
              check_status_bit(id, "status[FULL]", RDMA_DMA_ST_FULL, 1'b0);
            end
            80: begin
              run_dma_job(.tag(id), .seg0_span(64'h1000), .opq_words(1024),
                          .send_eoe(1'b0), .sqe_id(sqe_id),
                          .sequence_no(num), .timeout_cycles(300000));
              check_status_bit(id, "status[EOE]", RDMA_DMA_ST_EOE, 1'b0);
              check_status_bit(id, "status[FULL]", RDMA_DMA_ST_FULL, 1'b1);
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end else if ((num >= 81) && (num <= 96)) begin
          case (num)
            81: begin
              run_dma_job(.tag(id), .seg0_span(64'h1000), .opq_words(1024),
                          .send_eoe(1'b1), .sqe_id(sqe_id),
                          .sequence_no(num), .timeout_cycles(300000));
              check_status_bit(id, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
              check_status_bit(id, "status[FULL]", RDMA_DMA_ST_FULL, 1'b1);
            end
            82: begin
              run_dma_job(.tag(id), .opq_words(8), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num));
              check_status_bit(id, "status[SEG0_ONLY]",
                               RDMA_DMA_ST_SEG0_ONLY, 1'b1);
            end
            83: begin
              run_dma_job(.tag(id), .seg0_span(64'h1000),
                          .seg1_span(64'h1000), .opq_words(1025),
                          .send_eoe(1'b1), .sqe_id(sqe_id),
                          .sequence_no(num), .timeout_cycles(300000));
              check_status_bit(id, "status[SEG_BOUNDARY_HIT]",
                               RDMA_DMA_ST_SEG_BOUNDARY_HIT, 1'b1);
            end
            84: begin
              run_halt_count_job(.tag(id), .dropped_words(3),
                                 .sqe_id(sqe_id), .sequence_no(num));
              check_status_bit(id, "status[HALT]", RDMA_DMA_ST_HALT, 1'b1);
            end
            85: begin
              run_dma_job(.tag(id), .opq_words(16), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num));
              check_status_bit(id, "status[HALT]", RDMA_DMA_ST_HALT, 1'b0);
              check_u32_equal(id, "cnt_halt", vif.cnt_halt, 32'd0);
            end
            86: begin
              run_dma_job(.tag(id), .opq_words(16), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num));
              if (vif.job_status[15:6] !== 10'h000)
                `uvm_error(id, $sformatf(
                  "reserved status bits [15:6] got=0x%03h expected=0",
                  vif.job_status[15:6]))
            end
            87: begin
              run_direct_req_job(.tag(id), .hold_cycles(1), .sqe_id(sqe_id),
                                 .check_state_after_capture(1'b1));
            end
            88: begin
              run_direct_req_job(.tag(id), .hold_cycles(3), .sqe_id(sqe_id),
                                 .check_state_after_capture(1'b1));
            end
            89: begin
              run_done_pulse_report_case(.tag(id), .sqe_id(sqe_id),
                                         .check_report_hold(1'b0),
                                         .check_req_overlap(1'b0));
            end
            90: begin
              run_done_pulse_report_case(.tag(id), .sqe_id(sqe_id),
                                         .check_report_hold(1'b0),
                                         .check_req_overlap(1'b1));
            end
            91: begin
              run_done_pulse_report_case(.tag(id), .sqe_id(sqe_id),
                                         .check_report_hold(1'b1),
                                         .check_req_overlap(1'b0));
            end
            92: begin
              run_dma_job(.tag(id), .opq_words(8), .send_eoe(1'b1),
                          .sqe_id(16'habcd), .sequence_no(num));
              if (vif.job_sqe_id_echo !== 16'habcd)
                `uvm_error(id, $sformatf(
                  "sqe_id_echo got=0x%04h expected=0xabcd",
                  vif.job_sqe_id_echo))
            end
            93: begin
              run_fifo_level_probe_case(.tag(id), .sqe_id(sqe_id));
            end
            94: begin
              run_halt_count_job(.tag(id), .dropped_words(1),
                                 .sqe_id(sqe_id), .sequence_no(num));
              if (!vif.job_status[RDMA_DMA_ST_HALT])
                `uvm_error(id, "HALT status was not set after almost-full")
            end
            95: begin
              run_packer_slot_probe_case(.tag(id), .sqe_id(sqe_id));
            end
            96: begin
              run_writer_state_probe_case(.tag(id), .sqe_id(sqe_id));
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end else if ((num >= 97) && (num <= 112)) begin
          case (num)
            97: begin
              run_dbg1_aw_inflight_case(.tag(id), .sqe_id(sqe_id));
            end
            98: begin
              run_dbg1_w_remaining_case(.tag(id), .sqe_id(sqe_id));
            end
            99: begin
              run_halt_count_job(.tag(id), .dropped_words(5),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            100: begin
              run_dbg1_b_outstanding_case(.tag(id), .sqe_id(sqe_id));
            end
            101: begin
              run_dma_job(.tag(id), .opq_words(8), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num));
            end
            102: begin
              run_dma_job(.tag(id), .opq_words(32), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num));
            end
            103: begin
              run_random_idle_job(.tag(id), .sqe_id(sqe_id));
            end
            104: begin
              run_dma_job(.tag(id), .opq_words(4), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num));
            end
            105: begin
              run_dma_job(.tag(id), .seg0_span(64'h1000),
                          .seg1_span(64'h1000), .opq_words(2048),
                          .send_eoe(1'b0), .sqe_id(sqe_id),
                          .sequence_no(num), .timeout_cycles(500000));
            end
            106: begin
              run_dma_multi_event_job(.tag(id), .event_count(4),
                                      .words_per_event(8), .gap_cycles(8),
                                      .sqe_id(sqe_id), .sequence_no(num),
                                      .bvalid_lag(80));
            end
            107: begin
              run_dma_job(.tag(id), .opq_words(8), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num));
              if ((env.debug_level == 1) &&
                  ((vif.dbg2_writer_meta_valid !== 1'b0) ||
                   (vif.dbg2_writer_meta_valid_mask !== '0)))
                `uvm_error(id, "DEBUG2 writer metadata was not inert in DEBUG1")
            end
            108: begin
              run_random_mixed_jobs(.tag(id), .sqe_id(sqe_id));
            end
            109: begin
              run_multi_event_var_job(.tag(id), .event_count(16),
                                      .sqe_id(sqe_id), .sequence_no(num),
                                      .timeout_cycles(700000));
            end
            110: begin
              run_random_idle_job(.tag(id), .sqe_id(sqe_id));
            end
            111: begin
              run_dma_job(.tag(id), .seg0_span(64'h2000), .opq_words(1024),
                          .send_eoe(1'b1), .sqe_id(sqe_id),
                          .sequence_no(num), .timeout_cycles(300000));
              check_u32_equal(id, "job_seg0_bytes_written",
                              vif.job_seg0_bytes_written, 32'd4096);
              check_u32_equal(id, "job_seg1_bytes_written",
                              vif.job_seg1_bytes_written, 32'd0);
              check_u32_equal(id, "job_bytes_written_total",
                              vif.job_bytes_written_total[31:0], 32'd4096);
            end
            112: begin
              run_dma_job(.tag(id), .seg0_span(64'h1000),
                          .seg1_span(64'h1000), .opq_words(2048),
                          .send_eoe(1'b0), .sqe_id(sqe_id),
                          .sequence_no(num), .timeout_cycles(500000));
              check_u32_equal(id, "job_seg0_bytes_written",
                              vif.job_seg0_bytes_written, 32'd4096);
              check_u32_equal(id, "job_seg1_bytes_written",
                              vif.job_seg1_bytes_written, 32'd4096);
              check_u32_equal(id, "job_bytes_written_total",
                              vif.job_bytes_written_total[31:0], 32'd8192);
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end else if ((num >= 113) && (num <= 128)) begin
          case (num)
            113: begin
              run_dma_job(.tag(id), .seg0_span(64'h1000),
                          .seg1_span(64'h1000), .opq_words(1056),
                          .send_eoe(1'b1), .sqe_id(sqe_id),
                          .sequence_no(num), .timeout_cycles(300000));
              check_u32_equal(id, "job_seg0_bytes_written",
                              vif.job_seg0_bytes_written, 32'd4096);
              check_u32_equal(id, "job_seg1_bytes_written",
                              vif.job_seg1_bytes_written, 32'd128);
              check_u32_equal(id, "job_bytes_written_total",
                              vif.job_bytes_written_total[31:0], 32'd4224);
            end
            114: begin
              run_dma_job(.tag(id), .seg0_span(64'h1000),
                          .seg1_span(64'h1000), .opq_words(512),
                          .send_eoe(1'b1), .sqe_id(sqe_id),
                          .sequence_no(num), .timeout_cycles(300000));
              check_u32_equal(id, "job_seg0_bytes_written",
                              vif.job_seg0_bytes_written, 32'd2048);
              check_u32_equal(id, "job_seg1_bytes_written",
                              vif.job_seg1_bytes_written, 32'd0);
            end
            115: begin
              run_dma_job(.tag(id), .seg0_span(64'h1000),
                          .seg1_span(64'h1000), .opq_words(1536),
                          .send_eoe(1'b1), .sqe_id(sqe_id),
                          .sequence_no(num), .timeout_cycles(300000));
              if ({32'h0000_0000, vif.job_seg0_bytes_written} +
                  {32'h0000_0000, vif.job_seg1_bytes_written} !==
                  vif.job_bytes_written_total)
                `uvm_error(id, "seg0+seg1 bytes did not equal total bytes")
            end
            116: begin
              run_dma_job(.tag(id), .seg0_addr(64'h0000_0000_0010_0001),
                          .seg0_span(64'h1000), .opq_words(0),
                          .send_eoe(1'b0), .sqe_id(sqe_id),
                          .sequence_no(num), .timeout_cycles(300000));
              check_u32_equal(id, "job_seg0_bytes_written",
                              vif.job_seg0_bytes_written, 32'd0);
              check_u32_equal(id, "job_seg1_bytes_written",
                              vif.job_seg1_bytes_written, 32'd0);
              check_u32_equal(id, "job_bytes_written_total",
                              vif.job_bytes_written_total[31:0], 32'd0);
              check_status_bit(id, "status[ALIGN_ERR]",
                               RDMA_DMA_ST_ALIGN_ERR, 1'b1);
            end
            117: begin
              run_queue_single_burst_case(.tag(id), .sqe_id(sqe_id));
            end
            118: begin
              run_queue_burst_model_case(.tag(id), .sqe_id(sqe_id));
            end
            119: begin
              run_fifo_residency_case(.tag(id), .sqe_id(sqe_id));
            end
            120: begin
              run_halt_count_job(.tag(id), .dropped_words(12),
                                 .sqe_id(sqe_id), .sequence_no(num));
              if (vif.cnt_halt == 32'd0)
                `uvm_error(id, "cnt_halt did not record halt onset")
            end
            121: begin
              run_segment_latency_case(.tag(id), .sqe_id(sqe_id));
            end
            122: begin
              run_fifo_residency_case(.tag(id), .sqe_id(sqe_id));
              check_conservation(id);
            end
            123: begin
              run_dma_job(.tag({id, "_job0"}), .opq_words(8),
                          .send_eoe(1'b1), .sqe_id(sqe_id),
                          .sequence_no(num));
              check_u32_equal(id, "cnt_input_w after job0",
                              vif.cnt_input_w, 32'd8);
              run_dma_job(.tag({id, "_job1"}), .opq_words(8),
                          .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                          .sequence_no(num + 32'd100));
              check_u32_equal(id, "cnt_input_w after job1",
                              vif.cnt_input_w, 32'd16);
            end
            124: begin
              run_dma_job(.tag({id, "_job0"}), .opq_words(8),
                          .send_eoe(1'b1), .sqe_id(sqe_id),
                          .sequence_no(num));
              check_u32_equal(id, "cnt_bytes_written after job0",
                              vif.cnt_bytes_written, 32'd32);
              run_dma_job(.tag({id, "_job1"}), .opq_words(16),
                          .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                          .sequence_no(num + 32'd100));
              check_u32_equal(id, "cnt_bytes_written after job1",
                              vif.cnt_bytes_written, 32'd96);
            end
            125: begin
              bit [31:0] halt_after_clean;
              bit [31:0] halt_after_inject;
              run_dma_job(.tag({id, "_job0"}), .opq_words(8),
                          .send_eoe(1'b1), .sqe_id(sqe_id),
                          .sequence_no(num));
              halt_after_clean = vif.cnt_halt;
              run_halt_count_job(.tag({id, "_halt"}), .dropped_words(4),
                                 .sqe_id(sqe_id + 16'd1),
                                 .sequence_no(num + 32'd100));
              halt_after_inject = vif.cnt_halt;
              run_dma_job(.tag({id, "_job2"}), .opq_words(8),
                          .send_eoe(1'b1), .sqe_id(sqe_id + 16'd2),
                          .sequence_no(num + 32'd200));
              if (halt_after_clean != 32'd0)
                `uvm_error(id, "cnt_halt incremented during clean job")
              if (halt_after_inject <= halt_after_clean)
                `uvm_error(id, "cnt_halt did not increment during halt job")
              check_u32_equal(id, "cnt_halt after clean tail",
                              vif.cnt_halt, halt_after_inject);
            end
            126: begin
              for (int unsigned idx = 0; idx < 5; idx++) begin
                run_dma_job(.tag($sformatf("%s_job%0d", id, idx)),
                            .opq_words(8), .send_eoe(1'b1),
                            .sqe_id(sqe_id + idx[15:0]),
                            .sequence_no(num + idx));
              end
              check_u32_equal(id, "cnt_eoe_observed",
                              vif.cnt_eoe_observed, 32'd5);
            end
            127: begin
              run_dma_job(.tag({id, "_job0"}), .opq_words(8),
                          .send_eoe(1'b1), .sqe_id(sqe_id),
                          .sequence_no(num));
              if ((vif.cnt_input_w == 32'd0) ||
                  (vif.cnt_bytes_written == 32'd0))
                `uvm_error(id, "counters did not update before job boundary")
              run_dma_job(.tag({id, "_job1"}), .opq_words(8),
                          .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                          .sequence_no(num + 32'd100));
              check_u32_equal(id, "cnt_input_w", vif.cnt_input_w, 32'd16);
              check_u32_equal(id, "cnt_bytes_written",
                              vif.cnt_bytes_written, 32'd64);
            end
            128: begin
              run_dma_job(.tag(id), .opq_words(8), .send_eoe(1'b1),
                          .sqe_id(sqe_id), .sequence_no(num));
              if (env.scb.dbg1_sample_count == 0)
                `uvm_error(id, "dbg1 monitor did not sample counter window")
              check_u32_equal(id, "cnt_input_w", vif.cnt_input_w, 32'd8);
              check_u32_equal(id, "cnt_bytes_written",
                              vif.cnt_bytes_written, 32'd32);
              check_u32_equal(id, "cnt_eoe_observed",
                              vif.cnt_eoe_observed, 32'd1);
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end else if ((num >= 63) && (num <= 86)) begin
          if (num == 63) begin
            words = 100;
          end else if ((num == 67) || (num == 84)) begin
            words = 2048;
            send_eoe = 1'b0;
          end else begin
            words = 32 + (num % 32);
          end
        end else if ((num >= 87) && (num <= 107)) begin
          words = 16 + (num % 16);
          aw_lag = (num == 100) ? 32 : 0;
        end else if (num >= 108) begin
          words = 32 + (num % 64);
          two_seg = ((num % 3) == 0);
          seg1_span = two_seg ? 64'h1000 : 64'h0;
        end
      end else if (prefix == "E") begin
        if (num <= 16) begin
          case (num)
            1: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_seg0_span(64'h1000),
                                  .obs_words(1024), .obs_send_eoe(1'b0),
                                  .expected_aw_count(8),
                                  .expected_first_aw(seg0_addr),
                                  .check_last_aw(1'b1),
                                  .expected_last_aw(seg0_addr + 64'h0e00),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(15),
                                  .sqe_id(sqe_id), .sequence_no(num));
              check_status_bit(id, "status[FULL]", RDMA_DMA_ST_FULL, 1'b1);
            end
            2: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_seg0_span(64'h2000),
                                  .obs_words(512), .obs_send_eoe(1'b1),
                                  .expected_aw_count(4),
                                  .expected_first_aw(seg0_addr),
                                  .check_last_aw(1'b1),
                                  .expected_last_aw(seg0_addr + 64'h0600),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(15),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            3: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_seg0_span(64'h0010_0000),
                                  .obs_words(1024), .obs_send_eoe(1'b1),
                                  .expected_aw_count(8),
                                  .expected_first_aw(seg0_addr),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            4: begin
              run_aw_observed_job(.tag(id),
                                  .obs_seg0_addr(seg0_addr),
                                  .obs_seg0_span(64'h0000_0001_0000_0000),
                                  .obs_words(256), .obs_send_eoe(1'b1),
                                  .expected_aw_count(2),
                                  .expected_first_aw(seg0_addr),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            5: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_seg0_span(64'h1000),
                                  .obs_seg1_addr(seg1_addr),
                                  .obs_seg1_span(64'h1000),
                                  .obs_words(2048), .obs_send_eoe(1'b0),
                                  .expected_aw_count(16),
                                  .expected_first_aw(seg0_addr),
                                  .check_seg1_aw(1'b1),
                                  .expected_seg1_aw(seg1_addr),
                                  .sqe_id(sqe_id), .sequence_no(num),
                                  .timeout_cycles(500000));
              check_status_bit(id, "status[SEG_BOUNDARY_HIT]",
                               RDMA_DMA_ST_SEG_BOUNDARY_HIT, 1'b1);
            end
            6: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_seg0_span(64'h1000),
                                  .obs_words(128), .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(seg0_addr),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(15),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            7: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_seg0_span(64'h1000),
                                  .obs_words(256), .obs_send_eoe(1'b1),
                                  .expected_aw_count(2),
                                  .expected_first_aw(seg0_addr),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(15),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            8: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_seg0_span(64'h1000),
                                  .obs_words(1024), .obs_send_eoe(1'b0),
                                  .expected_aw_count(8),
                                  .expected_first_aw(seg0_addr),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(15),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            9: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_seg0_span(64'h1000),
                                  .obs_seg1_span(64'h0),
                                  .obs_words(128), .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(seg0_addr),
                                  .sqe_id(sqe_id), .sequence_no(num));
              check_status_bit(id, "status[SEG0_ONLY]",
                               RDMA_DMA_ST_SEG0_ONLY, 1'b1);
              check_u32_equal(id, "job_seg1_bytes_written",
                              vif.job_seg1_bytes_written, 32'd0);
            end
            10: begin
              run_aw_observed_job(.tag(id),
                                  .obs_seg0_addr(64'h0000_0000_ffff_f000),
                                  .obs_seg0_span(64'h1000),
                                  .obs_words(1024), .obs_send_eoe(1'b0),
                                  .expected_aw_count(8),
                                  .expected_first_aw(64'h0000_0000_ffff_f000),
                                  .check_last_aw(1'b1),
                                  .expected_last_aw(64'h0000_0000_ffff_fe00),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(15),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            11: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(64'h0),
                                  .obs_words(8), .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(64'h0),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            12: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(64'h1000),
                                  .obs_words(8), .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(64'h1000),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            13: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(64'h0001_0000),
                                  .obs_words(8), .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(64'h0001_0000),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            14: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(64'h0040_0000),
                                  .obs_words(8), .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(64'h0040_0000),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            15: begin
              run_aw_observed_job(.tag(id),
                                  .obs_seg0_addr(64'h0000_0001_0000_0000),
                                  .obs_words(8), .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(64'h0000_0001_0000_0000),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            16: begin
              run_aw_observed_job(.tag(id),
                                  .obs_seg0_addr(64'h0000_0010_0000_0000),
                                  .obs_words(8), .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(64'h0000_0010_0000_0000),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end
        if (num <= 32) begin
          case (num)
            17: begin
              run_aw_observed_job(.tag(id),
                                  .obs_seg0_addr(64'hffff_ffff_ffff_f000),
                                  .obs_words(8), .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(64'hffff_ffff_ffff_f000),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            18: begin
              run_aw_observed_job(.tag(id),
                                  .obs_seg0_addr(64'h0000_0000_0010_0000),
                                  .obs_seg0_span(64'h1000),
                                  .obs_seg1_addr(64'h0000_0000_0008_0000),
                                  .obs_seg1_span(64'h1000),
                                  .obs_words(2048), .obs_send_eoe(1'b0),
                                  .expected_aw_count(16),
                                  .expected_first_aw(64'h0000_0000_0010_0000),
                                  .check_last_aw(1'b1),
                                  .expected_last_aw(64'h0000_0000_0008_0e00),
                                  .check_seg1_aw(1'b1),
                                  .expected_seg1_aw(64'h0000_0000_0008_0000),
                                  .sqe_id(sqe_id), .sequence_no(num),
                                  .timeout_cycles(500000));
              check_status_bit(id, "status[SEG_BOUNDARY_HIT]",
                               RDMA_DMA_ST_SEG_BOUNDARY_HIT, 1'b1);
            end
            19: begin
              run_aw_observed_job(.tag(id),
                                  .obs_seg0_addr(64'h0000_0000_0010_0000),
                                  .obs_seg0_span(64'h1000),
                                  .obs_seg1_addr(64'h0000_0000_0010_1000),
                                  .obs_seg1_span(64'h1000),
                                  .obs_words(2048), .obs_send_eoe(1'b0),
                                  .expected_aw_count(16),
                                  .expected_first_aw(64'h0000_0000_0010_0000),
                                  .check_last_aw(1'b1),
                                  .expected_last_aw(64'h0000_0000_0010_1e00),
                                  .check_seg1_aw(1'b1),
                                  .expected_seg1_aw(64'h0000_0000_0010_1000),
                                  .sqe_id(sqe_id), .sequence_no(num),
                                  .timeout_cycles(500000));
              check_status_bit(id, "status[SEG_BOUNDARY_HIT]",
                               RDMA_DMA_ST_SEG_BOUNDARY_HIT, 1'b1);
            end
            20: begin
              run_aw_observed_job(.tag(id),
                                  .obs_seg0_addr(64'h0000_0000_0000_1000),
                                  .obs_seg0_span(64'h1000),
                                  .obs_seg1_addr(64'h0000_0000_1000_0000),
                                  .obs_seg1_span(64'h1000),
                                  .obs_words(2048), .obs_send_eoe(1'b0),
                                  .expected_aw_count(16),
                                  .expected_first_aw(64'h0000_0000_0000_1000),
                                  .check_last_aw(1'b1),
                                  .expected_last_aw(64'h0000_0000_1000_0e00),
                                  .check_seg1_aw(1'b1),
                                  .expected_seg1_aw(64'h0000_0000_1000_0000),
                                  .sqe_id(sqe_id), .sequence_no(num),
                                  .timeout_cycles(500000));
              check_status_bit(id, "status[SEG_BOUNDARY_HIT]",
                               RDMA_DMA_ST_SEG_BOUNDARY_HIT, 1'b1);
            end
            21: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_words(8),
                                  .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(seg0_addr),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(0),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            22: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_words(136),
                                  .obs_send_eoe(1'b1),
                                  .expected_aw_count(2),
                                  .expected_first_aw(seg0_addr),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(15),
                                  .check_last_awlen(1'b1),
                                  .expected_last_awlen(0),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            23: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_words(128),
                                  .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(seg0_addr),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(15),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            24: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_words(40),
                                  .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(seg0_addr),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(4),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            25: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_words(32),
                                  .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(seg0_addr),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(3),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            26: begin
              run_aw_observed_job(.tag(id),
                                  .obs_seg0_addr(64'h0000_0000_0000_1000),
                                  .obs_words(128), .obs_send_eoe(1'b1),
                                  .expected_aw_count(1),
                                  .expected_first_aw(64'h0000_0000_0000_1000),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(15),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            27: begin
              run_aw_observed_job(.tag(id),
                                  .obs_seg0_addr(64'h0000_0000_0000_1000),
                                  .obs_seg0_span(64'h1000),
                                  .obs_words(1024), .obs_send_eoe(1'b0),
                                  .expected_aw_count(8),
                                  .expected_first_aw(64'h0000_0000_0000_1000),
                                  .check_last_aw(1'b1),
                                  .expected_last_aw(64'h0000_0000_0000_1e00),
                                  .check_last_awlen(1'b1),
                                  .expected_last_awlen(15),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            28: begin
              run_aw_observed_job(.tag(id),
                                  .obs_seg0_addr(64'h0000_0000_0000_1000),
                                  .obs_seg0_span(64'h1000),
                                  .obs_words(1024), .obs_send_eoe(1'b0),
                                  .expected_aw_count(8),
                                  .expected_first_aw(64'h0000_0000_0000_1000),
                                  .check_last_aw(1'b1),
                                  .expected_last_aw(64'h0000_0000_0000_1e00),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(15),
                                  .check_last_awlen(1'b1),
                                  .expected_last_awlen(15),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            29: begin
              run_aw_observed_job(.tag(id),
                                  .obs_seg0_addr(64'h0000_0000_0000_1000),
                                  .obs_words(384), .obs_send_eoe(1'b1),
                                  .expected_aw_count(3),
                                  .expected_first_aw(64'h0000_0000_0000_1000),
                                  .check_last_aw(1'b1),
                                  .expected_last_aw(64'h0000_0000_0000_1400),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(15),
                                  .check_last_awlen(1'b1),
                                  .expected_last_awlen(15),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            30: begin
              run_aw_observed_job(.tag(id), .obs_seg0_addr(seg0_addr),
                                  .obs_words(160),
                                  .obs_send_eoe(1'b1),
                                  .expected_aw_count(2),
                                  .expected_first_aw(seg0_addr),
                                  .check_first_awlen(1'b1),
                                  .expected_first_awlen(15),
                                  .check_last_awlen(1'b1),
                                  .expected_last_awlen(3),
                                  .obs_idle_after_each(1),
                                  .sqe_id(sqe_id), .sequence_no(num));
            end
            31: begin
              run_fifo_threshold_edge_case(.tag(id), .sqe_id(sqe_id),
                                           .check_crossing(1'b1),
                                           .check_drain(1'b0),
                                           .sequence_no(num));
            end
            32: begin
              run_fifo_threshold_edge_case(.tag(id), .sqe_id(sqe_id),
                                           .check_crossing(1'b0),
                                           .check_drain(1'b1),
                                           .sequence_no(num));
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end
        if (num <= 48) begin
          case (num)
            33: begin
              run_halt_count_job(.tag(id), .dropped_words(16),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            34: begin
              run_halt_count_job(.tag(id), .dropped_words(1),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            35: begin
              run_fifo_partial_fill_case(.tag(id), .sqe_id(sqe_id),
                                         .sequence_no(num));
            end
            36: begin
              run_fifo_single_beat_dwell_case(.tag(id), .sqe_id(sqe_id),
                                              .sequence_no(num));
            end
            37: begin
              run_fifo_fill_drain_case(.tag(id), .sqe_id(sqe_id),
                                       .check_fill(1'b1),
                                       .check_empty_after_done(1'b0),
                                       .sequence_no(num));
            end
            38: begin
              run_fifo_fill_drain_case(.tag(id), .sqe_id(sqe_id),
                                       .check_fill(1'b0),
                                       .check_empty_after_done(1'b1),
                                       .sequence_no(num));
            end
            39: begin
              run_halt_count_job(.tag(id), .dropped_words(1),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            40: begin
              check_reset_defaults(id);
            end
            default: begin
              run_packer_flush_slot_case(.tag(id), .slot_words(num - 40),
                                         .sqe_id(sqe_id),
                                         .sequence_no(num));
            end
          endcase
          return;
        end
        if (num <= 64) begin
          case (num)
            49: begin
              run_packer_full_then_slot1_case(.tag(id), .sqe_id(sqe_id),
                                              .sequence_no(num));
            end
            50: begin
              run_double_eoe_case(.tag(id), .sqe_id(sqe_id),
                                  .sequence_no(num));
            end
            51: begin
              run_packer_flush_slot_case(.tag(id),
                                         .slot_words(RDMA_DMA_OPQ_PER_BEAT),
                                         .sqe_id(sqe_id),
                                         .sequence_no(num));
              check_u32_equal(id, "job_event_count", vif.job_event_count,
                              32'd1);
            end
            52: begin
              run_zero_byte_eoe_idle_case(.tag(id), .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            53: begin
              run_segment_boundary_edge_case(.tag(id),
                .seg0_addr(64'h0000_0000_0010_0000),
                .seg0_span(64'h0000_0000_0000_1000),
                .seg1_addr(64'h0000_0000_0020_0000),
                .seg1_span(64'h0000_0000_0000_1000),
                .opq_words(2048), .send_eoe(1'b0),
                .expected_seg0(32'd4096), .expected_seg1(32'd4096),
                .expected_aw_count(16), .check_seg1_aw(1'b1),
                .expected_seg1_aw(64'h0000_0000_0020_0000),
                .check_last_aw(1'b1),
                .expected_last_aw(64'h0000_0000_0020_0e00),
                .sqe_id(sqe_id), .sequence_no(num));
            end
            54: begin
              run_segment_boundary_edge_case(.tag(id),
                .seg0_addr(64'h0000_0000_0010_0000),
                .seg0_span(64'h0000_0000_0000_1000),
                .seg1_addr(64'h0000_0000_0020_0000),
                .seg1_span(64'h0000_0000_0000_1000),
                .opq_words(2048), .send_eoe(1'b0),
                .expected_seg0(32'd4096), .expected_seg1(32'd4096),
                .expected_aw_count(16), .check_seg1_aw(1'b1),
                .expected_seg1_aw(64'h0000_0000_0020_0000),
                .check_last_aw(1'b1),
                .expected_last_aw(64'h0000_0000_0020_0e00),
                .sqe_id(sqe_id), .sequence_no(num),
                .idle_after_each(1));
            end
            55: begin
              run_segment_boundary_edge_case(.tag(id),
                .seg0_addr(64'h0000_0000_0010_0000),
                .seg0_span(64'h0000_0000_0000_1000),
                .seg1_addr(64'h0000_0000_0020_0000),
                .seg1_span(64'h0000_0000_0000_1000),
                .opq_words(53), .send_eoe(1'b1),
                .expected_seg0(32'd212), .expected_seg1(32'd0),
                .expected_aw_count(1), .check_seg1_aw(1'b0),
                .expected_seg1_aw(64'h0000_0000_0020_0000),
                .check_last_aw(1'b0),
                .expected_last_aw(64'h0000_0000_0010_0000),
                .sqe_id(sqe_id), .sequence_no(num));
            end
            56: begin
              run_segment_boundary_edge_case(.tag(id),
                .seg0_addr(64'h0000_0000_0010_0000),
                .seg0_span(64'h0000_0000_0000_1000),
                .seg1_addr(64'h0000_0000_0020_0000),
                .seg1_span(64'h0000_0000_0000_1000),
                .opq_words(1032), .send_eoe(1'b1),
                .expected_seg0(32'd4096), .expected_seg1(32'd32),
                .expected_aw_count(9), .check_seg1_aw(1'b1),
                .expected_seg1_aw(64'h0000_0000_0020_0000),
                .check_last_aw(1'b1),
                .expected_last_aw(64'h0000_0000_0020_0000),
                .sqe_id(sqe_id), .sequence_no(num));
            end
            57: begin
              run_segment_boundary_edge_case(.tag(id),
                .seg0_addr(64'h0000_0000_0010_0000),
                .seg0_span(64'h0000_0000_0000_1000),
                .seg1_addr(64'h0000_0000_0020_0000),
                .seg1_span(64'h0000_0000_0000_1000),
                .opq_words(2048), .send_eoe(1'b0),
                .expected_seg0(32'd4096), .expected_seg1(32'd4096),
                .expected_aw_count(16), .check_seg1_aw(1'b1),
                .expected_seg1_aw(64'h0000_0000_0020_0000),
                .check_last_aw(1'b1),
                .expected_last_aw(64'h0000_0000_0020_0e00),
                .sqe_id(sqe_id), .sequence_no(num),
                .wready_lag(4));
            end
            58: begin
              run_segment_boundary_edge_case(.tag(id),
                .seg0_addr(64'h0000_0000_0010_0000),
                .seg0_span(64'h0000_0000_0000_1000),
                .seg1_addr(64'h0000_0000_0020_0000),
                .seg1_span(64'h0000_0000_0000_1000),
                .opq_words(2048), .send_eoe(1'b0),
                .expected_seg0(32'd4096), .expected_seg1(32'd4096),
                .expected_aw_count(16), .check_seg1_aw(1'b1),
                .expected_seg1_aw(64'h0000_0000_0020_0000),
                .check_last_aw(1'b1),
                .expected_last_aw(64'h0000_0000_0020_0e00),
                .sqe_id(sqe_id), .sequence_no(num));
            end
            59: begin
              run_segment_boundary_edge_case(.tag(id),
                .seg0_addr(64'h0000_0000_0010_0000),
                .seg0_span(64'h0000_0000_0000_1000),
                .seg1_addr(64'h0000_0000_0020_0000),
                .seg1_span(64'h0000_0000_0000_1000),
                .opq_words(1536), .send_eoe(1'b1),
                .expected_seg0(32'd4096), .expected_seg1(32'd2048),
                .expected_aw_count(12), .check_seg1_aw(1'b1),
                .expected_seg1_aw(64'h0000_0000_0020_0000),
                .check_last_aw(1'b1),
                .expected_last_aw(64'h0000_0000_0020_0600),
                .sqe_id(sqe_id), .sequence_no(num));
            end
            60: begin
              run_segment_latency_case(.tag(id), .sqe_id(sqe_id));
            end
            61: begin
              run_segment_boundary_edge_case(.tag(id),
                .seg0_addr(64'h0000_0000_0010_0000),
                .seg0_span(64'h0000_0000_0000_1000),
                .seg1_addr(64'h0000_0000_0020_0000),
                .seg1_span(64'h0000_0000_0000_1000),
                .opq_words(2048), .send_eoe(1'b0),
                .expected_seg0(32'd4096), .expected_seg1(32'd4096),
                .expected_aw_count(16), .check_seg1_aw(1'b1),
                .expected_seg1_aw(64'h0000_0000_0020_0000),
                .check_last_aw(1'b1),
                .expected_last_aw(64'h0000_0000_0020_0e00),
                .sqe_id(sqe_id), .sequence_no(num),
                .idle_after_each(2));
            end
            62: begin
              run_segment_boundary_edge_case(.tag(id),
                .seg0_addr(64'h0000_0000_ffff_f000),
                .seg0_span(64'h0000_0000_0000_1000),
                .seg1_addr(64'h0000_0001_0000_0000),
                .seg1_span(64'h0000_0000_0000_1000),
                .opq_words(2048), .send_eoe(1'b0),
                .expected_seg0(32'd4096), .expected_seg1(32'd4096),
                .expected_aw_count(16), .check_seg1_aw(1'b1),
                .expected_seg1_aw(64'h0000_0001_0000_0000),
                .check_last_aw(1'b1),
                .expected_last_aw(64'h0000_0001_0000_0e00),
                .sqe_id(sqe_id), .sequence_no(num));
            end
            63: begin
              run_exact_full_burst_eoe_case(.tag(id), .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            64: begin
              run_eoe_after_full_burst_case(.tag(id), .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end
        if (num <= 80) begin
          case (num)
            65: begin
              run_eoe_during_aw_phase_case(.tag(id), .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            66: begin
              run_program_phase_eoe_case(.tag(id), .sqe_id(sqe_id),
                                         .sequence_no(num));
            end
            67: begin
              run_full_boundary_case(.tag(id), .sqe_id(sqe_id),
                                     .sequence_no(num),
                                     .send_eoe_at_full(1'b0));
            end
            68: begin
              run_align_error_no_write_case(.tag(id), .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            69: begin
              run_full_boundary_case(.tag(id), .sqe_id(sqe_id),
                                     .sequence_no(num),
                                     .send_eoe_at_full(1'b0));
            end
            70: begin
              run_full_boundary_case(.tag(id), .sqe_id(sqe_id),
                                     .sequence_no(num),
                                     .send_eoe_at_full(1'b1));
            end
            71: begin
              run_two_job_one_cycle_after_done_case(
                .tag(id), .first_sqe_id(sqe_id),
                .second_sqe_id(sqe_id + 16'd1), .sequence_no(num));
            end
            72: begin
              run_done_pulse_report_case(.tag(id), .sqe_id(sqe_id),
                                         .check_report_hold(1'b0),
                                         .check_req_overlap(1'b1));
            end
            73: begin
              run_two_jobs_with_gap_case(.tag(id), .gap_cycles(0),
                                         .first_sqe_id(16'h1234),
                                         .second_sqe_id(16'h1234),
                                         .sequence_no(num));
            end
            74: begin
              run_two_jobs_with_gap_case(.tag(id), .gap_cycles(0),
                                         .first_sqe_id(16'h0000),
                                         .second_sqe_id(16'hffff),
                                         .sequence_no(num));
            end
            75: begin
              run_dma_job(.tag({id, "_job0"}), .opq_words(8),
                          .send_eoe(1'b1), .sqe_id(sqe_id),
                          .sequence_no(num));
              run_dma_job(.tag({id, "_job1"}), .opq_words(8),
                          .send_eoe(1'b1), .sqe_id(sqe_id + 16'd1),
                          .sequence_no(num + 32'd100));
              run_dma_job(.tag({id, "_job2"}), .opq_words(8),
                          .send_eoe(1'b1), .sqe_id(sqe_id + 16'd2),
                          .sequence_no(num + 32'd200));
              check_u32_equal(id, "job_done_count", env.scb.job_done_count,
                              32'd3);
            end
            76: begin
              run_two_jobs_with_gap_case(.tag(id), .gap_cycles(1000),
                                         .first_sqe_id(sqe_id),
                                         .second_sqe_id(sqe_id + 16'd1),
                                         .sequence_no(num));
            end
            77: begin
              run_two_jobs_with_gap_case(.tag(id), .gap_cycles(0),
                                         .first_sqe_id(sqe_id),
                                         .second_sqe_id(sqe_id + 16'd1),
                                         .sequence_no(num));
            end
            78: begin
              run_mixed_span_two_job_case(.tag(id), .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            79: begin
              run_dbg1_w_remaining_case(.tag(id), .sqe_id(sqe_id));
            end
            80: begin
              run_dbg1_aw_inflight_case(.tag(id), .sqe_id(sqe_id));
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end
        if (num <= 96) begin
          case (num)
            81: begin
              run_dbg1_idle_aw_inflight_case(.tag(id));
            end
            82: begin
              run_packer_pending_eoe_case(.tag(id), .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            83: begin
              run_writer_state_cycle_case(.tag(id), .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            84: begin
              run_halt_count_job(.tag(id), .dropped_words(4),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            85: begin
              run_dbg2_slot5_padding_case(.tag(id), .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            86: begin
              run_dbg2_halt_residual_case(.tag(id), .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            87: begin
              run_dbg2_hit_id_wrap_case(.tag(id), .sqe_id(sqe_id),
                                        .sequence_no(num));
            end
            88: begin
              run_dbg2_monotonic_sequence_case(.tag(id), .sqe_id(sqe_id),
                                               .sequence_no(num));
            end
            89: begin
              run_dbg2_monotonic_source_ts_case(.tag(id), .sqe_id(sqe_id),
                                                .sequence_no(num));
            end
            90: begin
              run_dbg2_inert_dbg1_case(.tag(id), .sqe_id(sqe_id),
                                       .sequence_no(num));
            end
            91: begin
              run_random_span_grid_case(.tag(id), .sqe_id(sqe_id),
                                        .sequence_no(num));
            end
            92: begin
              run_random_eoe_slot_case(.tag(id), .sqe_id(sqe_id),
                                       .sequence_no(num));
            end
            93: begin
              run_random_two_segment_transition_case(.tag(id),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            end
            94: begin
              run_random_burst_size_case(.tag(id), .sqe_id(sqe_id),
                                         .sequence_no(num));
            end
            95: begin
              run_fifo_threshold_edge_case(.tag(id), .sqe_id(sqe_id),
                                           .check_crossing(1'b1),
                                           .check_drain(1'b0),
                                           .sequence_no(num));
            end
            96: begin
              run_fifo_above_threshold_case(.tag(id), .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end
        if (num <= 128) begin
          case (num)
            97: begin
              run_fifo_overfill_guard_case(.tag(id), .attempted_entries(63),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            98: begin
              run_fifo_overfill_guard_case(.tag(id), .attempted_entries(64),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            99: begin
              run_fifo_recovery_after_halt_case(.tag(id), .sqe_id(sqe_id),
                                                .sequence_no(num));
            end
            100: begin
              run_fifo_simultaneous_rw_case(.tag(id), .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            101: begin
              run_fifo_single_write_burst_case(.tag(id), .sqe_id(sqe_id),
                                               .sequence_no(num));
            end
            102: begin
              run_fifo_single_read_burst_case(.tag(id), .sqe_id(sqe_id),
                                              .sequence_no(num));
            end
            103: begin
              run_writer_align_err_transition_case(.tag(id),
                                                   .sqe_id(sqe_id));
            end
            104: begin
              run_writer_two_segment_program_case(.tag(id), .sqe_id(sqe_id),
                                                  .sequence_no(num));
            end
            105: begin
              run_writer_b_to_aw_case(.tag(id), .sqe_id(sqe_id),
                                      .sequence_no(num));
            end
            106: begin
              run_writer_stall_case(.tag(id), .state(4'd2), .aw_lag(64),
                                    .w_lag(0), .b_lag(1), .sqe_id(sqe_id),
                                    .sequence_no(num));
            end
            107: begin
              run_writer_stall_case(.tag(id), .state(4'd3), .aw_lag(0),
                                    .w_lag(64), .b_lag(1), .sqe_id(sqe_id),
                                    .sequence_no(num));
            end
            108: begin
              run_writer_stall_case(.tag(id), .state(4'd4), .aw_lag(0),
                                    .w_lag(0), .b_lag(64), .sqe_id(sqe_id),
                                    .sequence_no(num));
            end
            109: begin
              run_counter_input_saturation_case(.tag(id), .sqe_id(sqe_id),
                                                .sequence_no(num));
            end
            110: begin
              run_counter_bytes_saturation_case(.tag(id), .sqe_id(sqe_id),
                                                .sequence_no(num));
            end
            111: begin
              run_counter_clear_max_case(.tag(id));
            end
            112: begin
              run_job_req_opq_idle_case(.tag(id), .sqe_id(sqe_id),
                                        .sequence_no(num));
            end
            113: begin
              run_job_req_immediate_opq_case(.tag(id), .sqe_id(sqe_id),
                                             .sequence_no(num));
            end
            114: begin
              run_opq_before_job_case(.tag(id), .sqe_id(sqe_id),
                                      .sequence_no(num));
            end
            115: begin
              run_high_half_address_case(.tag(id), .sqe_id(sqe_id),
                                         .sequence_no(num));
            end
            116: begin
              run_opq_after_done_ignored_case(.tag(id), .sqe_id(sqe_id),
                                              .sequence_no(num));
            end
            117: begin
              run_random_eoe_throttled_case(.tag(id), .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            118: begin
              run_random_alignment_mix_case(.tag(id), .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            119: begin
              run_random_multi_event_drains_case(.tag(id), .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            120: begin
              run_random_span_eoe_throttle_case(.tag(id), .sqe_id(sqe_id),
                                                .sequence_no(num));
            end
            121: begin
              run_first_last_ts_equal_case(.tag(id), .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            122: begin
              run_first_event_ts_capture_case(.tag(id), .sqe_id(sqe_id),
                                              .sequence_no(num));
            end
            123: begin
              run_last_ts_later_event_case(.tag(id), .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            124: begin
              run_two_jobs_clean_fifo_case(.tag(id), .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            125: begin
              run_two_job_one_cycle_after_done_case(
                .tag(id), .first_sqe_id(sqe_id),
                .second_sqe_id(sqe_id + 16'd1), .sequence_no(num));
            end
            126: begin
              run_three_back_to_back_jobs_case(.tag(id), .sqe_id(sqe_id),
                                               .sequence_no(num));
            end
            127: begin
              run_two_segment_then_single_case(.tag(id), .sqe_id(sqe_id),
                                               .sequence_no(num));
            end
            128: begin
              run_align_error_then_clean_case(.tag(id), .sqe_id(sqe_id),
                                              .sequence_no(num));
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end
        if (num <= 30) begin
          words = (num % 5 == 0) ? 128 : (16 + (num % 32));
          aw_lag = (num >= 21 && num <= 30) ? 48 : 0;
          if (num >= 11 && num <= 20)
            seg0_addr = 64'h0000_0000_0100_0000 + (64'(num) << 12);
        end else if (num <= 52) begin
          words = ((num - 40) % 8);
          if (words == 0)
            words = 8;
          zero_eoe = (num == 52);
        end else if (num <= 78) begin
          two_seg = 1'b1;
          seg1_span = 64'h1000;
          send_eoe = (num % 2) == 0;
          words = send_eoe ? 1024 : 2048;
        end else begin
          words = 16 + (num % 96);
          aw_lag = (num == 106) ? 64 : 0;
          w_lag = (num == 107) ? 64 : 0;
          b_lag = (num == 108) ? 64 : 1;
        end
      end else if (prefix == "P") begin
        if (num <= 16) begin
          case (num)
            1: begin
              run_profile_multi_event_case(.tag(id), .event_count(100),
                                           .words_per_event(64),
                                           .gap_cycles(0), .bvalid_lag(1),
                                           .wready_lag(0), .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            2: begin
              run_profile_multi_event_case(.tag(id), .event_count(100),
                                           .words_per_event(64),
                                           .gap_cycles(0), .bvalid_lag(250),
                                           .wready_lag(0), .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            3: begin
              run_halt_count_job(.tag(id), .dropped_words(100),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            4: begin
              run_profile_multi_event_case(.tag(id), .event_count(256),
                                           .words_per_event(64),
                                           .gap_cycles(0), .bvalid_lag(1),
                                           .wready_lag(0), .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            5: begin
              run_profile_single_load_case(.tag(id), .opq_words(6400),
                                           .idle_after_each(1),
                                           .wready_lag(0), .bvalid_lag(1),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            6: begin
              run_profile_single_load_case(.tag(id), .opq_words(6400),
                                           .idle_after_each(0),
                                           .wready_lag(1), .bvalid_lag(1),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            7: begin
              run_profile_single_load_case(.tag(id), .opq_words(800),
                                           .idle_after_each(9),
                                           .wready_lag(0), .bvalid_lag(1),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            8: begin
              run_halt_count_job(.tag(id), .dropped_words(32),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            9: begin
              run_profile_job_stream_case(.tag(id), .job_count(32),
                                          .words_per_job(1024),
                                          .two_segment(1'b0),
                                          .mixed_span(1'b0),
                                          .random_sqe(1'b0),
                                          .gap_cycles(0),
                                          .variable_lag(1'b0),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            10: begin
              run_profile_job_stream_case(.tag(id), .job_count(16),
                                          .words_per_job(4096),
                                          .two_segment(1'b0),
                                          .mixed_span(1'b0),
                                          .random_sqe(1'b0),
                                          .gap_cycles(0),
                                          .variable_lag(1'b0),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            11: begin
              run_profile_job_stream_case(.tag(id), .job_count(16),
                                          .words_per_job(1032),
                                          .two_segment(1'b1),
                                          .mixed_span(1'b0),
                                          .random_sqe(1'b0),
                                          .gap_cycles(0),
                                          .variable_lag(1'b0),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            12: begin
              run_profile_job_stream_case(.tag(id), .job_count(64),
                                          .words_per_job(512),
                                          .two_segment(1'b0),
                                          .mixed_span(1'b1),
                                          .random_sqe(1'b0),
                                          .gap_cycles(0),
                                          .variable_lag(1'b1),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            13: begin
              run_profile_job_stream_case(.tag(id), .job_count(32),
                                          .words_per_job(64),
                                          .two_segment(1'b0),
                                          .mixed_span(1'b0),
                                          .random_sqe(1'b1),
                                          .gap_cycles(0),
                                          .variable_lag(1'b0),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            14: begin
              run_profile_job_stream_case(.tag(id), .job_count(24),
                                          .words_per_job(128),
                                          .two_segment(1'b0),
                                          .mixed_span(1'b0),
                                          .random_sqe(1'b0),
                                          .gap_cycles(0),
                                          .variable_lag(1'b0),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            15: begin
              run_profile_job_stream_case(.tag(id), .job_count(16),
                                          .words_per_job(64),
                                          .two_segment(1'b0),
                                          .mixed_span(1'b0),
                                          .random_sqe(1'b0),
                                          .gap_cycles(100),
                                          .variable_lag(1'b0),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            16: begin
              run_profile_job_stream_case(.tag(id), .job_count(16),
                                          .words_per_job(128),
                                          .two_segment(1'b0),
                                          .mixed_span(1'b1),
                                          .random_sqe(1'b0),
                                          .gap_cycles(0),
                                          .variable_lag(1'b1),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end
        if (num <= 32) begin
          case (num)
            17: begin
              run_profile_awlen_metric_case(.tag(id), .opq_words(4096),
                                            .idle_after_each(0),
                                            .wready_lag(0), .bvalid_lag(1),
                                            .min_avg_awlen_milli(14000),
                                            .max_avg_awlen_milli(15000),
                                            .min_util_milli(900),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            18: begin
              run_profile_awlen_metric_case(.tag(id), .opq_words(64),
                                            .idle_after_each(1),
                                            .wready_lag(0), .bvalid_lag(1),
                                            .min_avg_awlen_milli(7000),
                                            .max_avg_awlen_milli(8000),
                                            .min_util_milli(500),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            19: begin
              run_profile_awlen_metric_case(.tag(id), .opq_words(8),
                                            .idle_after_each(9),
                                            .wready_lag(0), .bvalid_lag(1),
                                            .min_avg_awlen_milli(0),
                                            .max_avg_awlen_milli(2000),
                                            .min_util_milli(60),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            20: begin
              run_profile_fifo_pressure_case(.tag(id), .opq_words(4096),
                                             .wready_lag(8),
                                             .bvalid_lag(32),
                                             .min_max_level(RDMA_DMA_MAX_BURST_BEATS),
                                             .sqe_id(sqe_id),
                                             .sequence_no(num));
            end
            21: begin
              run_profile_awlen_metric_case(.tag(id), .opq_words(2048),
                                            .idle_after_each(0),
                                            .wready_lag(0), .bvalid_lag(1),
                                            .min_avg_awlen_milli(14000),
                                            .max_avg_awlen_milli(15000),
                                            .min_util_milli(800),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            22: begin
              run_profile_awlen_metric_case(.tag(id), .opq_words(4096),
                                            .idle_after_each(0),
                                            .wready_lag(0), .bvalid_lag(1),
                                            .min_avg_awlen_milli(14000),
                                            .max_avg_awlen_milli(15000),
                                            .min_util_milli(900),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            23: begin
              run_profile_single_load_case(.tag(id), .opq_words(4096),
                                           .idle_after_each(1),
                                           .wready_lag(0), .bvalid_lag(1),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            24: begin
              run_profile_multi_event_case(.tag(id), .event_count(512),
                                           .words_per_event(8),
                                           .gap_cycles(0), .bvalid_lag(1),
                                           .wready_lag(0), .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            25: begin
              run_profile_job_stream_case(.tag(id), .job_count(64),
                                          .words_per_job(128),
                                          .two_segment(1'b0),
                                          .mixed_span(1'b1),
                                          .random_sqe(1'b0),
                                          .gap_cycles(0),
                                          .variable_lag(1'b1),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            26: begin
              run_halt_count_job(.tag(id), .dropped_words(32),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            27: begin
              run_profile_counter_clear_conservation_case(.tag(id),
                                                          .sqe_id(sqe_id),
                                                          .sequence_no(num));
            end
            28: begin
              run_halt_count_job(.tag(id), .dropped_words(100),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            29: begin
              run_halt_count_job(.tag(id), .dropped_words(16),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            30: begin
              run_halt_count_job(.tag(id), .dropped_words(64),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            31: begin
              run_fifo_recovery_after_halt_case(.tag(id), .sqe_id(sqe_id),
                                                .sequence_no(num));
            end
            32: begin
              run_profile_halt_one_of_five_case(.tag(id), .sqe_id(sqe_id),
                                                .sequence_no(num));
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end
        if (num <= 48) begin
          case (num)
            33: begin
              run_profile_latency_case(.tag(id), .opq_words(1024),
                                       .wready_lag(0), .bvalid_lag(1),
                                       .min_cycles(1), .max_cycles(100000),
                                       .sqe_id(sqe_id), .sequence_no(num));
            end
            34: begin
              run_profile_latency_case(.tag(id), .opq_words(4096),
                                       .wready_lag(12), .bvalid_lag(32),
                                       .min_cycles(4096), .max_cycles(0),
                                       .sqe_id(sqe_id), .sequence_no(num));
            end
            35: begin
              run_profile_average_latency_case(.tag(id), .job_count(100),
                                               .words_per_job(16),
                                               .sqe_id(sqe_id),
                                               .sequence_no(num));
            end
            36: begin
              run_profile_halt_latency_case(.tag(id), .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            37: begin
              run_profile_fifo_hold_case(.tag(id), .target_level(128),
                                         .hold_cycles(10000),
                                         .expect_almost_full(1'b0),
                                         .sqe_id(sqe_id),
                                         .sequence_no(num));
            end
            38: begin
              run_profile_fifo_hold_case(.tag(id), .target_level(192),
                                         .hold_cycles(2048),
                                         .expect_almost_full(1'b1),
                                         .sqe_id(sqe_id),
                                         .sequence_no(num));
            end
            39: begin
              run_profile_fifo_oscillation_case(.tag(id), .sqe_id(sqe_id),
                                                .sequence_no(num));
            end
            40: begin
              run_profile_fifo_hold_case(.tag(id), .target_level(192),
                                         .hold_cycles(1000),
                                         .expect_almost_full(1'b1),
                                         .sqe_id(sqe_id),
                                         .sequence_no(num));
            end
            41: begin
              run_profile_dbg1_invariant_soak_case(.tag(id),
                                                   .soak_cycles(100000),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            end
            42: begin
              run_profile_halt_accounting_soak_case(.tag(id),
                                                    .sqe_id(sqe_id),
                                                    .sequence_no(num));
            end
            43: begin
              run_profile_fifo_histogram_case(.tag(id), .sqe_id(sqe_id),
                                              .sequence_no(num));
            end
            44: begin
              run_profile_single_load_case(.tag(id), .opq_words(100000),
                                           .idle_after_each(0),
                                           .wready_lag(0), .bvalid_lag(1),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            45: begin
              run_profile_job_stream_case(.tag(id), .job_count(100),
                                          .words_per_job(32),
                                          .two_segment(1'b0),
                                          .mixed_span(1'b0),
                                          .random_sqe(1'b0),
                                          .gap_cycles(0),
                                          .variable_lag(1'b0),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            46: begin
              run_profile_job_stream_case(.tag(id), .job_count(32),
                                          .words_per_job(128),
                                          .two_segment(1'b0),
                                          .mixed_span(1'b1),
                                          .random_sqe(1'b1),
                                          .gap_cycles(1),
                                          .variable_lag(1'b1),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            47: begin
              run_halt_count_job(.tag(id), .dropped_words(32),
                                 .sqe_id(sqe_id), .sequence_no(num));
            end
            48: begin
              run_profile_random_host_lag_case(.tag(id), .job_count(32),
                                               .sqe_id(sqe_id),
                                               .sequence_no(num));
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end
        if (num <= 64) begin
          case (num)
            49: begin
              run_profile_random_bvalid_case(.tag(id), .job_count(32),
                                             .sqe_id(sqe_id),
                                             .sequence_no(num));
            end
            50: begin
              run_profile_random_idle_case(.tag(id), .job_count(32),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            51: begin
              run_profile_random_combo_case(.tag(id), .job_count(32),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            52: begin
              run_profile_job_stream_case(.tag(id), .job_count(100),
                                          .words_per_job(128),
                                          .two_segment(1'b0),
                                          .mixed_span(1'b1),
                                          .random_sqe(1'b1),
                                          .gap_cycles(0),
                                          .variable_lag(1'b1),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            53: begin
              run_profile_job_stream_case(.tag(id), .job_count(50),
                                          .words_per_job(1032),
                                          .two_segment(1'b1),
                                          .mixed_span(1'b1),
                                          .random_sqe(1'b1),
                                          .gap_cycles(0),
                                          .variable_lag(1'b1),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            54: begin
              run_profile_job_stream_case(.tag(id), .job_count(200),
                                          .words_per_job(64),
                                          .two_segment(1'b0),
                                          .mixed_span(1'b1),
                                          .random_sqe(1'b1),
                                          .gap_cycles(1),
                                          .variable_lag(1'b1),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            55: begin
              run_profile_multi_event_case(.tag(id), .event_count(1000),
                                           .words_per_event(8),
                                           .gap_cycles(0), .bvalid_lag(1),
                                           .wready_lag(0), .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            56: begin
              run_profile_awlen_metric_case(.tag(id), .opq_words(6400),
                                            .idle_after_each(0),
                                            .wready_lag(0), .bvalid_lag(1),
                                            .min_avg_awlen_milli(14000),
                                            .max_avg_awlen_milli(15000),
                                            .min_util_milli(900),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            57: begin
              run_profile_latency_case(.tag(id), .opq_words(6400),
                                       .wready_lag(0), .bvalid_lag(1),
                                       .min_cycles(1), .max_cycles(120000),
                                       .sqe_id(sqe_id), .sequence_no(num));
            end
            58: begin
              run_profile_multi_event_case(.tag(id), .event_count(100),
                                           .words_per_event(64),
                                           .gap_cycles(0), .bvalid_lag(1),
                                           .wready_lag(0), .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            59: begin
              run_profile_latency_case(.tag(id), .opq_words(1024),
                                       .wready_lag(0), .bvalid_lag(1),
                                       .min_cycles(1), .max_cycles(100000),
                                       .sqe_id(sqe_id), .sequence_no(num));
            end
            60: begin
              run_profile_single_load_case(.tag(id), .opq_words(100000),
                                           .idle_after_each(1),
                                           .wready_lag(0), .bvalid_lag(1),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            61: begin
              run_profile_single_load_case(.tag(id), .opq_words(100000),
                                           .idle_after_each(0),
                                           .wready_lag(0), .bvalid_lag(1),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            62: begin
              run_profile_job_stream_case(.tag(id), .job_count(1000),
                                          .words_per_job(8),
                                          .two_segment(1'b0),
                                          .mixed_span(1'b0),
                                          .random_sqe(1'b0),
                                          .gap_cycles(0),
                                          .variable_lag(1'b0),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            end
            63: begin
              run_profile_fixed_host_lag_jobs(.tag(id), .job_count(100),
                                              .wready_lag(100),
                                              .words_per_job(16),
                                              .sqe_id(sqe_id),
                                              .sequence_no(num));
            end
            64: begin
              run_profile_fixed_host_lag_jobs(.tag(id), .job_count(100),
                                              .wready_lag(500),
                                              .words_per_job(16),
                                              .sqe_id(sqe_id),
                                              .sequence_no(num));
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end
        if (num <= 80) begin
          case (num)
            65: begin
              run_profile_variable_host_lag_case(.tag(id), .job_count(100),
                                                 .max_lag(500),
                                                 .words_per_job(16),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            66: begin
              run_profile_fixed_bvalid_jobs(.tag(id), .job_count(1000),
                                            .bvalid_lag(250),
                                            .words_per_job(8),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            67: begin
              run_profile_sustained_input_load_case(.tag(id),
                                                    .job_count(5000),
                                                    .idle_after_each(1),
                                                    .words_per_job(8),
                                                    .sqe_id(sqe_id),
                                                    .sequence_no(num));
            end
            68: begin
              run_profile_multi_event_case(.tag(id), .event_count(10000),
                                           .words_per_event(1),
                                           .gap_cycles(0), .bvalid_lag(1),
                                           .wready_lag(0), .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            69: begin
              run_fifo_overfill_guard_case(.tag(id), .attempted_entries(2),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            70: begin
              run_profile_single_load_case(.tag(id), .opq_words(4096),
                                           .idle_after_each(1),
                                           .wready_lag(0), .bvalid_lag(1),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            71: begin
              run_profile_single_load_case(.tag(id), .opq_words(2048),
                                           .idle_after_each(3),
                                           .wready_lag(0), .bvalid_lag(1),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            72: begin
              run_fifo_overfill_guard_case(.tag(id), .attempted_entries(8),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            73: begin
              run_profile_bursty_input_case(.tag(id), .job_count(32),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            end
            74: begin
              run_profile_output_bursty_case(.tag(id), .job_count(64),
                                             .sqe_id(sqe_id),
                                             .sequence_no(num));
            end
            75: begin
              run_profile_random_rate_bound_case(.tag(id), .job_count(48),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            76: begin
              run_profile_throughput_consistency_case(.tag(id),
                                                      .seed_a(1),
                                                      .seed_b(2),
                                                      .job_count(32),
                                                      .words_per_job(64),
                                                      .idle_after_each(0),
                                                      .wready_lag(0));
            end
            77: begin
              run_profile_throughput_consistency_case(.tag(id),
                                                      .seed_a(100),
                                                      .seed_b(200),
                                                      .job_count(32),
                                                      .words_per_job(64),
                                                      .idle_after_each(1),
                                                      .wready_lag(0));
            end
            78: begin
              run_profile_throughput_consistency_case(.tag(id),
                                                      .seed_a(8),
                                                      .seed_b(18),
                                                      .job_count(64),
                                                      .words_per_job(32),
                                                      .idle_after_each(0),
                                                      .wready_lag(0));
            end
            79: begin
              run_profile_throughput_consistency_case(.tag(id),
                                                      .seed_a(9),
                                                      .seed_b(19),
                                                      .job_count(64),
                                                      .words_per_job(32),
                                                      .idle_after_each(0),
                                                      .wready_lag(0));
            end
            80: begin
              run_profile_halt_rate_consistency_case(.tag(id),
                                                     .seed_a(100),
                                                     .seed_b(200),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end
        if (num <= 128) begin
          case (num)
            81: begin
              run_profile_latency_p50_consistency_case(.tag(id),
                                                       .seed_a(1),
                                                       .seed_b(2),
                                                       .job_count(100));
            end
            82: begin
              run_profile_single_load_case(.tag(id), .opq_words(100000),
                                           .idle_after_each(0),
                                           .wready_lag(0), .bvalid_lag(1),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            83: begin
              run_profile_debug2_halt_scale_case(.tag(id),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            84: begin
              run_profile_debug2_residual_bound_case(.tag(id),
                                                     .opq_words(4096),
                                                     .max_residual(260),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            end
            85: begin
              run_profile_counter_clear_replay_case(.tag(id),
                                                    .sqe_id(sqe_id),
                                                    .sequence_no(num));
            end
            86: begin
              run_profile_checkpoint_residual_case(.tag(id),
                                                   .checkpoint_count(8),
                                                   .words_per_checkpoint(12500),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            end
            87: begin
              run_profile_throughput_consistency_case(.tag(id),
                                                      .seed_a(1),
                                                      .seed_b(2),
                                                      .job_count(64),
                                                      .words_per_job(64),
                                                      .idle_after_each(0),
                                                      .wready_lag(0));
            end
            88: begin
              run_align_error_then_clean_case(.tag(id), .sqe_id(sqe_id),
                                              .sequence_no(num));
            end
            89: begin
              run_profile_exact_awlen_case(.tag(id), .opq_words(120),
                                           .expected_awlen(8'd14),
                                           .sqe_id(sqe_id),
                                           .sequence_no(num));
            end
            90: begin
              run_profile_fifo_threshold_hammer_case(.tag(id),
                                                     .iteration_count(100),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            end
            91: begin
              run_halt_count_job(.tag(id), .dropped_words(16),
                                 .sqe_id(sqe_id), .sequence_no(num));
              check_status_bit(id, "status[HALT]", RDMA_DMA_ST_HALT, 1'b1);
              check_status_bit(id, "status[EOE]", RDMA_DMA_ST_EOE, 1'b1);
            end
            92: begin
              run_profile_halt_status_combo_case(.tag(id),
                                                 .seg0_span(64'h2000),
                                                 .seg1_span(64'h0),
                                                 .total_words(2048),
                                                 .expect_full(1'b1),
                                                 .expect_boundary(1'b0),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            93: begin
              run_profile_halt_status_combo_case(.tag(id),
                                                 .seg0_span(64'h1000),
                                                 .seg1_span(64'h2000),
                                                 .total_words(2048),
                                                 .expect_full(1'b0),
                                                 .expect_boundary(1'b1),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            94: begin
              run_profile_clear_during_reset_case(.tag(id),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            end
            95: begin
              run_profile_aw_to_w_latency_metric_case(.tag(id),
                                                      .job_count(100),
                                                      .sqe_id(sqe_id),
                                                      .sequence_no(num));
            end
            96: begin
              run_profile_wlast_to_bvalid_metric_case(.tag(id),
                                                      .job_count(100),
                                                      .sqe_id(sqe_id),
                                                      .sequence_no(num));
            end
            97: begin
              run_profile_job_req_to_aw_metric_case(.tag(id),
                                                    .job_count(100),
                                                    .sqe_id(sqe_id),
                                                    .sequence_no(num));
            end
            98: begin
              run_profile_b_to_done_metric_case(.tag(id),
                                                .job_count(100),
                                                .sqe_id(sqe_id),
                                                .sequence_no(num));
            end
            99: begin
              run_profile_awlen_distribution_case(.tag(id),
                                                 .min_bursts(1000),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            100: begin
              run_profile_fifo_occupancy_histogram_case(.tag(id),
                                                       .opq_words(4096),
                                                       .sqe_id(sqe_id),
                                                       .sequence_no(num));
            end
            101: begin
              run_profile_throughput_consistency_case(.tag(id),
                                                      .seed_a(3),
                                                      .seed_b(4),
                                                      .job_count(100),
                                                      .words_per_job(64),
                                                      .idle_after_each(0),
                                                      .wready_lag(0));
            end
            102: begin
              run_profile_fifo_convergence_case(.tag(id),
                                                .opq_words(32768),
                                                .sqe_id(sqe_id),
                                                .sequence_no(num));
            end
            103: begin
              run_profile_halt_rate_convergence_case(.tag(id),
                                                     .sample_count(16),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            end
            104: begin
              run_profile_latency_p99_stability_case(.tag(id),
                                                     .job_count(1000),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            end
            105: begin
              run_profile_random_aw_burst_sweep_case(.tag(id),
                                                     .iteration_count(256),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            end
            106: begin
              run_profile_random_packer_sweep_case(.tag(id),
                                                   .iteration_count(256),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            end
            107: begin
              run_profile_random_fifo_sweep_case(.tag(id),
                                                 .iteration_count(256),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            108: begin
              run_profile_status_cross_sweep_case(.tag(id),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            end
            109: begin
              run_profile_dbg2_lineage_sweep_case(.tag(id),
                                                  .iteration_count(128),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            end
            110: begin
              run_profile_sidecar_wallclock_case(.tag(id),
                                                 .opq_words(100),
                                                 .max_cycles(50000),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            111: begin
              run_profile_sidecar_wallclock_case(.tag(id),
                                                 .opq_words(10000),
                                                 .max_cycles(250000),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            112: begin
              run_profile_sidecar_overhead_case(.tag(id),
                                                .opq_words(1024),
                                                .sqe_id(sqe_id),
                                                .sequence_no(num));
            end
            113: begin
              run_profile_stress_halt_rate_case(.tag(id),
                                                .job_count(100),
                                                .sqe_id(sqe_id),
                                                .sequence_no(num));
            end
            114: begin
              run_profile_periodic_reset_stress_case(.tag(id),
                                                     .reset_count(10),
                                                     .jobs_per_reset(100),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            end
            115: begin
              run_profile_random_align_stress_case(.tag(id),
                                                   .job_count(100),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            end
            116: begin
              run_profile_random_opcode_stress_case(.tag(id),
                                                    .job_count(100),
                                                    .sqe_id(sqe_id),
                                                    .sequence_no(num));
            end
            117: begin
              run_profile_basic_bucket_frame_case(.tag(id),
                                                  .job_count(128),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            end
            118: begin
              run_profile_basic_bucket_frame_case(.tag(id),
                                                  .job_count(128),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            end
            119: begin
              run_profile_edge_bucket_frame_case(.tag(id),
                                                 .job_count(64),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            120: begin
              run_profile_edge_bucket_frame_case(.tag(id),
                                                 .job_count(64),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            121: begin
              run_profile_all_buckets_frame_case(.tag(id),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            122: begin
              run_profile_all_buckets_frame_case(.tag(id),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            end
            123: begin
              run_profile_random_long_soak_case(.tag(id),
                                                .soak_cycles(10000000),
                                                .job_count(100),
                                                .sqe_id(sqe_id),
                                                .sequence_no(num));
            end
            124: begin
              run_profile_final_throughput_report_case(.tag(id),
                                                       .job_count(128),
                                                       .sqe_id(sqe_id),
                                                       .sequence_no(num));
            end
            125: begin
              run_profile_final_latency_report_case(.tag(id),
                                                    .job_count(512),
                                                    .sqe_id(sqe_id),
                                                    .sequence_no(num));
            end
            126: begin
              run_profile_final_halt_rate_report_case(.tag(id),
                                                      .sample_count(16),
                                                      .sqe_id(sqe_id),
                                                      .sequence_no(num));
            end
            127: begin
              run_profile_final_lineage_residual_report_case(.tag(id),
                                                             .iteration_count(256),
                                                             .sqe_id(sqe_id),
                                                             .sequence_no(num));
            end
            128: begin
              run_profile_dual_build_comparison_case(.tag(id),
                                                     .job_count(128),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            end
            default: begin
              run_dma_job(.tag(id), .sqe_id(sqe_id), .sequence_no(num));
            end
          endcase
          return;
        end
        words = 64 + (num % 192);
        aw_lag = (num % 7 == 0) ? 64 : 0;
        w_lag = (num % 11 == 0) ? 3 : 0;
        b_lag = (num % 13 == 0) ? 32 : 1;
        two_seg = (num % 5 == 0);
        seg1_span = two_seg ? 64'h1000 : 64'h0;
        if (num >= 117)
          words = 256;
      end else if (prefix == "X") begin
        if (num <= 16) begin
          case (num)
            1: run_error_align_refusal_case(
                 .tag(id), .seg0_addr(64'h0000_0000_0010_0001),
                 .seg0_span(64'h1000), .seg1_addr(64'h0000_0000_0020_0000),
                 .seg1_span(64'h0), .sqe_id(sqe_id), .sequence_no(num));
            2: run_error_align_refusal_case(
                 .tag(id), .seg0_addr(64'h0000_0000_0010_0800),
                 .seg0_span(64'h1000), .seg1_addr(64'h0000_0000_0020_0000),
                 .seg1_span(64'h0), .sqe_id(sqe_id), .sequence_no(num));
            3: run_error_align_refusal_case(
                 .tag(id), .seg0_addr(64'h0000_0000_0010_0fff),
                 .seg0_span(64'h1000), .seg1_addr(64'h0000_0000_0020_0000),
                 .seg1_span(64'h0), .sqe_id(sqe_id), .sequence_no(num));
            4: run_error_align_refusal_case(
                 .tag(id), .seg0_addr(64'h0000_0000_0010_0000),
                 .seg0_span(64'h1001), .seg1_addr(64'h0000_0000_0020_0000),
                 .seg1_span(64'h0), .sqe_id(sqe_id), .sequence_no(num));
            5: run_error_align_refusal_case(
                 .tag(id), .seg0_addr(64'h0000_0000_0010_0000),
                 .seg0_span(64'h1100), .seg1_addr(64'h0000_0000_0020_0000),
                 .seg1_span(64'h0), .sqe_id(sqe_id), .sequence_no(num));
            6: run_error_align_refusal_case(
                 .tag(id), .seg0_addr(64'h0000_0000_0010_0000),
                 .seg0_span(64'h0), .seg1_addr(64'h0000_0000_0020_0000),
                 .seg1_span(64'h0), .sqe_id(sqe_id), .sequence_no(num));
            7: run_error_align_refusal_case(
                 .tag(id), .seg0_addr(64'h0000_0000_0010_0000),
                 .seg0_span(64'h1000), .seg1_addr(64'h0000_0000_0020_0001),
                 .seg1_span(64'h1000), .sqe_id(sqe_id), .sequence_no(num));
            8: run_error_align_refusal_case(
                 .tag(id), .seg0_addr(64'h0000_0000_0010_0000),
                 .seg0_span(64'h1000), .seg1_addr(64'h0000_0000_0020_0000),
                 .seg1_span(64'h1001), .sqe_id(sqe_id), .sequence_no(num));
            9: run_error_align_refusal_case(
                 .tag(id), .seg0_addr(64'h0000_0000_0010_0001),
                 .seg0_span(64'h1000), .seg1_addr(64'h0000_0000_0020_0001),
                 .seg1_span(64'h1000), .sqe_id(sqe_id), .sequence_no(num));
            10: run_error_align_refusal_case(
                  .tag(id), .seg0_addr(64'h0000_0000_0010_0000),
                  .seg0_span(64'h1000), .seg1_addr(64'h0000_0000_0020_0001),
                  .seg1_span(64'h1000), .sqe_id(sqe_id), .sequence_no(num));
            11: run_error_align_refusal_case(
                  .tag(id), .seg0_addr(64'h0000_0000_0010_0000),
                  .seg0_span(64'h0), .seg1_addr(64'h0000_0000_0020_0000),
                  .seg1_span(64'h1000), .sqe_id(sqe_id), .sequence_no(num));
            12: run_error_single_segment_legal_case(.tag(id),
                                                    .sqe_id(sqe_id),
                                                    .sequence_no(num));
            13: run_error_align_after_valid_case(.tag(id),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            14: run_error_consecutive_align_case(.tag(id),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            15: run_align_error_then_clean_case(.tag(id),
                                                .sqe_id(sqe_id),
                                                .sequence_no(num));
            16: run_error_idle_reset_case(id);
            default: run_error_align_refusal_case(
                       .tag(id), .seg0_addr(64'h0000_0000_0010_0001),
                       .seg0_span(64'h1000),
                       .seg1_addr(64'h0000_0000_0020_0000),
                       .seg1_span(64'h0), .sqe_id(sqe_id),
                       .sequence_no(num));
          endcase
          return;
        end else if (num <= 32) begin
          case (num)
            17: run_error_reset_writer_state_case(.tag(id),
                                                  .target_state(4'd1),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            18: run_error_reset_writer_state_case(.tag(id),
                                                  .target_state(4'd2),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num),
                                                  .require_awvalid(1'b1));
            19: run_error_reset_writer_state_case(.tag(id),
                                                  .target_state(4'd3),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            20: run_error_reset_writer_state_case(.tag(id),
                                                  .target_state(4'd4),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            21: run_error_reset_writer_state_case(.tag(id),
                                                  .target_state(4'd5),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            22: run_error_reset_on_job_req_case(id);
            23: run_error_reset_on_job_done_case(.tag(id),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            24: run_error_reset_pulse_train_case(id);
            25: run_error_long_reset_case(id);
            26: run_error_reset_then_job_case(.tag(id),
                                              .sqe_id(sqe_id),
                                              .sequence_no(num));
            27: run_error_reset_clears_counters_case(.tag(id),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            28: run_error_reset_writer_state_case(.tag(id),
                                                  .target_state(4'd3),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            29: run_error_bresp_case(.tag(id),
                                     .bresp(axi4_write_pkg::AXI_RESP_SLVERR),
                                     .error_index(-1),
                                     .opq_words(64),
                                     .sqe_id(sqe_id),
                                     .sequence_no(num));
            30: run_error_bresp_case(.tag(id), .bresp(2'b11),
                                     .error_index(-1),
                                     .opq_words(64),
                                     .sqe_id(sqe_id),
                                     .sequence_no(num));
            31: run_error_bresp_case(.tag(id),
                                     .bresp(axi4_write_pkg::AXI_RESP_SLVERR),
                                     .error_index(0),
                                     .opq_words(256),
                                     .sqe_id(sqe_id),
                                     .sequence_no(num));
            32: run_error_bresp_case(.tag(id),
                                     .bresp(axi4_write_pkg::AXI_RESP_SLVERR),
                                     .error_index(1),
                                     .opq_words(256),
                                     .sqe_id(sqe_id),
                                     .sequence_no(num));
            default: run_error_idle_reset_case(id);
          endcase
          return;
        end else if (num <= 48) begin
          case (num)
            33: run_error_bresp_case(.tag(id),
                                     .bresp(axi4_write_pkg::AXI_RESP_SLVERR),
                                     .error_index(-1),
                                     .opq_words(1280),
                                     .seg0_span(64'h0000_0000_0000_2000),
                                     .sqe_id(sqe_id),
                                     .sequence_no(num));
            34: run_error_bresp_case(.tag(id), .bresp(2'b11),
                                     .error_index(0),
                                     .opq_words(256),
                                     .sqe_id(sqe_id),
                                     .sequence_no(num));
            35: run_job_req_opq_idle_case(.tag(id),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            36: run_error_burst_size_five_case(.tag(id),
                                               .sqe_id(sqe_id),
                                               .sequence_no(num));
            37: run_fifo_single_read_burst_case(.tag(id),
                                                .sqe_id(sqe_id),
                                                .sequence_no(num));
            38: run_error_tlast_without_tvalid_case(.tag(id),
                                                    .sqe_id(sqe_id),
                                                    .sequence_no(num));
            39: run_error_sop_mid_event_case(.tag(id),
                                             .sqe_id(sqe_id),
                                             .sequence_no(num));
            40: run_dma_job(.tag(id), .opq_words(64),
                            .send_eoe(1'b1), .sqe_id(sqe_id),
                            .sequence_no(num), .idle_after_each(0),
                            .timeout_cycles(300000));
            41: run_job_req_opq_idle_case(.tag(id),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            42: run_error_ignored_xdata_case(.tag(id),
                                             .sqe_id(sqe_id),
                                             .sequence_no(num));
            43: run_error_single_beat_event_case(.tag(id),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            44: run_error_overlap_job_req_case(.tag(id),
                                               .sqe_id(sqe_id),
                                               .sequence_no(num));
            45: run_error_reset_on_job_req_case(id);
            46: run_error_invalid_opcode_case(.tag(id),
                                              .sqe_id(sqe_id),
                                              .sequence_no(num));
            47: run_error_ten_align_then_valid_case(.tag(id),
                                                    .sqe_id(sqe_id),
                                                    .sequence_no(num));
            48: run_error_large_span_case(.tag(id),
                                          .sqe_id(sqe_id),
                                          .sequence_no(num));
            default: run_error_idle_reset_case(id);
          endcase
          return;
        end else if (num <= 64) begin
          case (num)
            49: run_error_bresp_recovery_case(.tag(id),
                                               .sqe_id(sqe_id),
                                               .sequence_no(num));
            50: run_align_error_then_clean_case(.tag(id),
                                                .sqe_id(sqe_id),
                                                .sequence_no(num));
            51: run_error_reset_mid_job_recovery_case(.tag(id),
                                                      .sqe_id(sqe_id),
                                                      .sequence_no(num));
            52: run_fifo_recovery_after_halt_case(.tag(id),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            53: run_error_dbg1_bresp_observability_case(.tag(id),
                                                        .sqe_id(sqe_id),
                                                        .sequence_no(num));
            54: run_error_reset_writer_state_case(.tag(id),
                                                  .target_state(4'd3),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            55: run_writer_align_err_transition_case(.tag(id),
                                                     .sqe_id(sqe_id));
            56: run_halt_count_job(.tag(id), .dropped_words(8),
                                   .sqe_id(sqe_id),
                                   .sequence_no(num));
            57: run_dbg2_halt_residual_case(.tag(id),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            58: run_error_dbg2_reordered_lineage_case(.tag(id),
                                                      .sqe_id(sqe_id),
                                                      .sequence_no(num));
            59: run_error_dbg2_duplicate_lineage_case(.tag(id),
                                                      .sqe_id(sqe_id),
                                                      .sequence_no(num));
            60: run_error_dbg2_reset_residual_case(.tag(id),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            61: run_dbg2_halt_residual_case(.tag(id),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            62: run_error_clear_idle_case(id);
            63: run_error_clear_during_writer_state_case(.tag(id),
                                                         .target_state(4'd3),
                                                         .sqe_id(sqe_id),
                                                         .sequence_no(num));
            64: run_error_clear_during_writer_state_case(.tag(id),
                                                         .target_state(4'd4),
                                                         .sqe_id(sqe_id),
                                                         .sequence_no(num));
            default: run_error_idle_reset_case(id);
          endcase
          return;
        end else if (num <= 80) begin
          case (num)
            65: run_error_clear_back_to_back_case(.tag(id),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            66: run_error_clear_at_job_done_case(.tag(id),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            67: run_error_clear_during_halt_case(.tag(id),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            68: run_error_bresp_fault_loop_case(.tag(id),
                                                .job_count(100),
                                                .error_period(100),
                                                .sqe_id(sqe_id),
                                                .sequence_no(num));
            69: run_error_periodic_reset_loop_case(.tag(id),
                                                   .job_count(20),
                                                   .reset_period(5),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            70: run_profile_random_align_stress_case(.tag(id),
                                                     .job_count(100),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            71: run_error_combined_fault_loop_case(.tag(id),
                                                   .job_count(100),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            72: run_error_reset_writer_state_case(.tag(id),
                                                  .target_state(4'd2),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num),
                                                  .require_awvalid(1'b1));
            73: run_error_reset_writer_state_case(.tag(id),
                                                  .target_state(4'd3),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            74: run_error_reset_writer_state_case(.tag(id),
                                                  .target_state(4'd4),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            75: run_error_bresp_ignored_after_reset_case(.tag(id),
                                                        .sqe_id(sqe_id),
                                                        .sequence_no(num));
            76: run_error_awready_delay_case(.tag(id),
                                             .sqe_id(sqe_id),
                                             .sequence_no(num));
            77: run_error_wready_delay_case(.tag(id),
                                             .sqe_id(sqe_id),
                                             .sequence_no(num));
            78: run_error_spurious_b_idle_case(.tag(id),
                                               .sqe_id(sqe_id),
                                               .sequence_no(num));
            79: run_error_spurious_b_during_w_case(.tag(id),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            80: run_error_bid_mismatch_case(.tag(id),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            default: run_error_idle_reset_case(id);
          endcase
          return;
        end else if (num <= 96) begin
          case (num)
            81: run_error_duplicate_bvalid_case(.tag(id),
                                                .sqe_id(sqe_id),
                                                .sequence_no(num));
            82: run_error_fifo_level_inconsistency_case(id);
            83: run_error_fifo_full_guard_case(id);
            84: run_error_fifo_empty_guard_case(id);
            85: run_error_fifo_almost_full_disagreement_case(id);
            86: run_error_job_req_held_high_case(.tag(id),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            87: run_error_job_req_mutating_inputs_case(.tag(id),
                                                       .sqe_id(sqe_id),
                                                       .sequence_no(num));
            88: run_error_job_done_req_overlap_case(.tag(id),
                                                    .sqe_id(sqe_id),
                                                    .sequence_no(num));
            89: run_error_align_then_halt_case(.tag(id),
                                               .sqe_id(sqe_id),
                                               .sequence_no(num));
            90: run_error_align_with_bresp_case(.tag(id),
                                                .sqe_id(sqe_id),
                                                .sequence_no(num));
            91: run_error_align_reset_clean_case(.tag(id),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            92: run_error_clear_during_aw_handshake_case(.tag(id),
                                                        .sqe_id(sqe_id),
                                                        .sequence_no(num));
            93: run_error_clear_input_increment_case(.tag(id),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            94: run_error_clear_halt_race_case(.tag(id),
                                               .sqe_id(sqe_id),
                                               .sequence_no(num));
            95: run_error_clear_at_job_done_case(.tag(id),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            96: run_error_opq_stuck_wr_w_case(.tag(id),
                                              .sqe_id(sqe_id),
                                              .sequence_no(num));
            default: run_error_idle_reset_case(id);
          endcase
          return;
        end else if (num <= 112) begin
          case (num)
            97: run_error_wready_stuck_case(.tag(id),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            98: run_error_bvalid_stuck_case(.tag(id),
                                            .sqe_id(sqe_id),
                                            .sequence_no(num));
            99: run_error_long_idle_no_job_case(id);
            100: run_error_bresp_reset_align_valid_chain(.tag(id),
                                                         .sqe_id(sqe_id),
                                                         .sequence_no(num));
            101: run_error_bresp_halt_eoe_case(.tag(id),
                                               .sqe_id(sqe_id),
                                               .sequence_no(num));
            102: run_error_triple_reset_valid_case(.tag(id),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            103: run_error_halt_reset_reentry_case(.tag(id),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            104: run_dbg2_halt_residual_case(.tag(id),
                                             .sqe_id(sqe_id),
                                             .sequence_no(num));
            105: run_error_dbg2_lineage_reset_residual_case(.tag(id),
                                                            .sqe_id(sqe_id),
                                                            .sequence_no(num));
            106: run_error_dbg2_bresp_lineage_case(.tag(id),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            107: run_error_dbg2_align_no_traffic_case(.tag(id),
                                                      .sqe_id(sqe_id),
                                                      .sequence_no(num));
            108: run_error_random_fault_profile_case(.tag(id),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            109: run_error_random_align_valid_mix_case(.tag(id),
                                                       .sqe_id(sqe_id),
                                                       .sequence_no(num));
            110: run_error_random_reset_every_n_case(.tag(id),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            111: run_error_random_bresp_rate_case(.tag(id),
                                                  .sqe_id(sqe_id),
                                                  .sequence_no(num));
            112: run_error_random_combined_fault_rate_case(.tag(id),
                                                           .sqe_id(sqe_id),
                                                           .sequence_no(num));
            default: run_error_idle_reset_case(id);
          endcase
          return;
        end else if (num <= 128) begin
          case (num)
            113: run_error_reset_every_50_case(.tag(id),
                                               .sqe_id(sqe_id),
                                               .sequence_no(num));
            114: run_error_reset_wait_bvalid_no_host_case(.tag(id),
                                                          .sqe_id(sqe_id),
                                                          .sequence_no(num));
            115: run_error_reset_high_fifo_fill_case(.tag(id),
                                                     .sqe_id(sqe_id),
                                                     .sequence_no(num));
            116: run_error_reset_clear_same_cycle_case(.tag(id),
                                                       .sqe_id(sqe_id),
                                                       .sequence_no(num));
            117: run_error_out_of_order_b_edge_case(.tag(id),
                                                    .sqe_id(sqe_id),
                                                    .sequence_no(num));
            118: run_error_duplicate_bvalid_case(.tag(id),
                                                 .sqe_id(sqe_id),
                                                 .sequence_no(num));
            119: run_error_report_align_state_case(.tag(id),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            120: run_error_status_align_coverage_case(.tag(id),
                                                      .sqe_id(sqe_id),
                                                      .sequence_no(num));
            121: run_error_bresp_branch_coverage_case(.tag(id),
                                                      .sqe_id(sqe_id),
                                                      .sequence_no(num));
            122: run_error_reset_all_writer_states_case(.tag(id),
                                                        .sqe_id(sqe_id),
                                                        .sequence_no(num));
            123: run_error_sustained_bresp_one_percent_case(.tag(id),
                                                            .sqe_id(sqe_id),
                                                            .sequence_no(num));
            124: run_error_sustained_reset_one_percent_case(.tag(id),
                                                            .sqe_id(sqe_id),
                                                            .sequence_no(num));
            125: run_error_sustained_align_one_percent_case(.tag(id),
                                                            .sqe_id(sqe_id),
                                                            .sequence_no(num));
            126: run_error_final_composite_case(.tag(id),
                                                .sqe_id(sqe_id),
                                                .sequence_no(num));
            127: run_error_final_dbg1_lineage_case(.tag(id),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            128: run_error_final_dbg2_lineage_case(.tag(id),
                                                   .sqe_id(sqe_id),
                                                   .sequence_no(num));
            default: run_error_idle_reset_case(id);
          endcase
          return;
        end else begin
          words = 32 + (num % 96);
          aw_lag = (num % 3 == 0) ? 48 : 0;
          b_lag = (num % 5 == 0) ? 48 : 1;
        end
      end

      if (two_seg)
        seg1_span = (seg1_span == 64'h0) ? 64'h1000 : seg1_span;
      run_dma_job(.tag(id),
                  .seg0_addr(seg0_addr),
                  .seg0_span(seg0_span),
                  .seg1_addr(seg1_addr),
                  .seg1_span(seg1_span),
                  .opq_words(words),
                  .send_eoe(send_eoe),
                  .zero_eoe(zero_eoe),
                  .awready_lag(aw_lag),
                  .wready_lag(w_lag),
                  .bvalid_lag(b_lag),
                  .bresp(bresp),
                  .sqe_id(sqe_id),
                  .idle_after_each((prefix == "P") ? (num % 3) : idle_after_each),
                  .timeout_cycles(300000));
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

  `include "sequences/rdma_dma_engine_phase_b_sequences.sv"

  class rdma_dma_engine_phase_b_test extends rdma_dma_engine_base_test;
    `uvm_component_utils(rdma_dma_engine_phase_b_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function rdma_dma_phase_b_case_sequence create_case_sequence();
      rdma_dma_phase_b_case_sequence seq;
      seq = rdma_dma_phase_b_case_sequence::type_id::create("phase_b_seq");
      return seq;
    endfunction

    task run_case();
      rdma_dma_phase_b_case_sequence seq;
      seq = create_case_sequence();
      if (seq.case_id == "BASE")
        seq.case_id = case_id;
      seq.start(this);
    endtask
  endclass

  `include "tests/generated/rdma_dma_phase_b_tests.svh"

  `include "tests/test_b001_reset_idle.sv"
  `include "tests/test_b002_single_job_hit_only_eoe.sv"
endpackage

`endif
