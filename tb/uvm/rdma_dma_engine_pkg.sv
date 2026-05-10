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
      if (env.debug_level >= 2) begin
        vif.dbg2_meta_valid <= 1'b1;
        vif.dbg2_meta_lane <= 4'h0;
        vif.dbg2_meta_hit_id <= hit_id;
        vif.dbg2_meta_source_ts <= hit_id;
        vif.dbg2_meta_sequence_no <= sequence_no;
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

    task run_halt_count_job(
      input string tag,
      input int unsigned dropped_words = 10,
      input bit [15:0] sqe_id = 16'h0100,
      input bit [31:0] sequence_no = 32'd1
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

      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 5000;
      env.axi_cfg.bvalid_lag = 1;
      env.axi_cfg.bresp = axi4_write_pkg::AXI_RESP_OKAY;

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
      reached_almost_full = 1'b0;
      for (int unsigned word_idx = 0; word_idx < 4096; word_idx++) begin
        if (vif.dbg1_fifo_almost_full) begin
          reached_almost_full = 1'b1;
          break;
        end
        accepted_words++;
        drive_direct_opq_word({8'h00, sequence_no[15:0], accepted_words[7:0]},
                              1'b0, sequence_no, accepted_words);
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
      env.scb.ignore_next_opq(dropped_words);
      for (int unsigned drop_idx = 0; drop_idx < dropped_words; drop_idx++) begin
        drive_direct_opq_word({8'h00, sequence_no[15:0], drop_idx[7:0]},
                              1'b0, sequence_no, accepted_words + drop_idx + 1);
      end
      wait_cycles(4);
      halt_delta = vif.cnt_halt - halt_before;
      if (halt_delta < dropped_words[31:0])
        `uvm_error(tag, $sformatf("cnt_halt delta got=%0d expected at least %0d",
                                  halt_delta, dropped_words))
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
      env.scb.expect_job(expected_total, expected_total[31:0], 32'h0000_0000,
                         expected_status, status_mask, sqe_id);
      drive_direct_opq_word({8'h00, sequence_no[15:0], accepted_words[7:0]},
                            1'b1, sequence_no,
                            vif.cnt_input_w + 32'd1);

      wait_for_done(300000);
      wait_cycles(2);
      check_u32_equal(tag, "cnt_halt", vif.cnt_halt, expected_halt);
      check_status_bit(tag, "status[HALT]", RDMA_DMA_ST_HALT, 1'b1);
      check_conservation(tag);

      env.axi_cfg.awready_lag = 0;
      env.axi_cfg.wready_lag = 0;
      env.axi_cfg.bvalid_lag = 1;
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
        words = 64 + (num % 192);
        aw_lag = (num % 7 == 0) ? 64 : 0;
        w_lag = (num % 11 == 0) ? 3 : 0;
        b_lag = (num % 13 == 0) ? 32 : 1;
        two_seg = (num % 5 == 0);
        seg1_span = two_seg ? 64'h1000 : 64'h0;
        if (num >= 117)
          words = 256;
      end else if (prefix == "X") begin
        if (num <= 15) begin
          if (num == 1)
            seg0_addr = 64'h0000_0000_0010_0001;
          else if (num == 2)
            seg0_addr = 64'h0000_0000_0010_0800;
          else if (num == 3)
            seg0_addr = 64'h0000_0000_0010_0fff;
          else if ((num == 4) || (num == 5))
            seg0_span = (num == 4) ? 64'h1001 : 64'h1100;
          else if ((num == 6) || (num == 11))
            seg0_span = 64'h0;
          else if ((num >= 7) && (num <= 10)) begin
            seg1_span = 64'h1000;
            seg1_addr = (num == 8) ? 64'h0000_0000_0020_0000 : 64'h0000_0000_0020_0001;
            if (num == 8)
              seg1_span = 64'h1001;
          end
          words = 0;
        end else if (num <= 28) begin
          run_reset_mid_aw_case(id);
          return;
        end else if (num <= 34) begin
          bresp = (num == 30 || num == 34) ? 2'b11 : axi4_write_pkg::AXI_RESP_SLVERR;
          words = 64;
        end else if (num <= 61) begin
          words = 16 + (num % 64);
          if (num >= 49 && num <= 52)
            bresp = (num == 49) ? axi4_write_pkg::AXI_RESP_SLVERR : axi4_write_pkg::AXI_RESP_OKAY;
        end else if (num <= 95) begin
          words = 64 + (num % 64);
          if (num % 4 == 0)
            pulse_clear_counters();
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
