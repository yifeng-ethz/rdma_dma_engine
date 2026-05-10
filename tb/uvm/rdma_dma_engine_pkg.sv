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
          opq_seq.data_base = {8'h00, sqe_id, 8'h00};
          opq_seq.sequence_no = {16'h0, sqe_id};
          opq_seq.idle_after_each = idle_after_each;
          opq_seq.mark_eoe_on_last = send_eoe;
          if (!send_eoe)
            opq_seq.word_count = opq_words;
          opq_seq.start(env.opq_agent.sequencer);
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
        end else if ((num >= 63) && (num <= 86)) begin
          if ((num == 67) || (num == 84)) begin
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
      run_dma_job(id, seg0_addr, seg0_span, seg1_addr, seg1_span, words,
                  send_eoe, zero_eoe, aw_lag, w_lag, b_lag, bresp,
                  sqe_id, (prefix == "P") ? (num % 3) : idle_after_each,
                  300000);
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
