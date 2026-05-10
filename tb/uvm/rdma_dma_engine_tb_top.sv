`ifndef DEBUG_LEVEL
`define DEBUG_LEVEL 1
`endif

module rdma_dma_engine_tb_top;
  import uvm_pkg::*;
  import rdma_dma_engine_pkg::*;
  `include "uvm_macros.svh"

  localparam int unsigned DMA_DATA_W = 256;
  localparam int unsigned DBG2_META_W = 136;
  localparam int unsigned DEBUG = `DEBUG_LEVEL;

  rdma_dma_engine_if #(.DMA_DATA_W(DMA_DATA_W)) dut_if();
  logic [DBG2_META_W-1:0] dbg2_meta_packed;
  logic [8*DBG2_META_W-1:0] dbg2_writer_meta_packed;
  logic [7:0] dbg2_writer_valid_mask;

  assign dbg2_meta_packed = {
    4'h0,
    dut_if.dbg2_meta_lane,
    dut_if.dbg2_meta_hit_id,
    dut_if.dbg2_meta_source_ts,
    dut_if.dbg2_meta_sequence_no
  };

  assign dut_if.dbg2_writer_meta_valid_mask = dbg2_writer_valid_mask;
  generate
    for (genvar dbg2_slot = 0; dbg2_slot < 8; dbg2_slot++) begin : gen_dbg2_unpack
      localparam int unsigned META_BASE = dbg2_slot * DBG2_META_W;
      assign dut_if.dbg2_writer_meta_lane[dbg2_slot*4 +: 4] =
        dbg2_writer_meta_packed[META_BASE + 128 +: 4];
      assign dut_if.dbg2_writer_meta_hit_id[dbg2_slot*32 +: 32] =
        dbg2_writer_meta_packed[META_BASE + 96 +: 32];
      assign dut_if.dbg2_writer_meta_source_ts[dbg2_slot*64 +: 64] =
        dbg2_writer_meta_packed[META_BASE + 32 +: 64];
      assign dut_if.dbg2_writer_meta_sequence_no[dbg2_slot*32 +: 32] =
        dbg2_writer_meta_packed[META_BASE +: 32];
    end
  endgenerate

  initial begin
    dut_if.clk = 1'b0;
    forever #2 dut_if.clk = ~dut_if.clk;
  end

  rdma_dma_engine #(
    .DMA_DATA_W(DMA_DATA_W),
    .MAX_BURST_BEATS(16),
    .SEG_QUANTUM_BYTES(4096),
    .DEBUG_LEVEL(DEBUG)
  ) dut (
    .clk(dut_if.clk),
    .reset_n(dut_if.reset_n),
    .s_axis_opq_tdata(dut_if.s_axis_opq_tdata),
    .s_axis_opq_tvalid(dut_if.s_axis_opq_tvalid),
    .s_axis_opq_tready(dut_if.s_axis_opq_tready),
    .s_axis_opq_tlast(dut_if.s_axis_opq_tlast),
    .s_axis_opq_tuser(dut_if.s_axis_opq_tuser),
    .job_req(dut_if.job_req),
    .job_seg0_addr(dut_if.job_seg0_addr),
    .job_seg0_span(dut_if.job_seg0_span),
    .job_seg1_addr(dut_if.job_seg1_addr),
    .job_seg1_span(dut_if.job_seg1_span),
    .job_sqe_id(dut_if.job_sqe_id),
    .job_opcode(dut_if.job_opcode),
    .job_done(dut_if.job_done),
    .job_bytes_written_total(dut_if.job_bytes_written_total),
    .job_seg0_bytes_written(dut_if.job_seg0_bytes_written),
    .job_seg1_bytes_written(dut_if.job_seg1_bytes_written),
    .job_status(dut_if.job_status),
    .job_sqe_id_echo(dut_if.job_sqe_id_echo),
    .job_event_count(dut_if.job_event_count),
    .job_first_event_ts(dut_if.job_first_event_ts),
    .job_last_event_ts(dut_if.job_last_event_ts),
    .m_axi_awid(dut_if.m_axi_awid),
    .m_axi_awaddr(dut_if.m_axi_awaddr),
    .m_axi_awlen(dut_if.m_axi_awlen),
    .m_axi_awsize(dut_if.m_axi_awsize),
    .m_axi_awburst(dut_if.m_axi_awburst),
    .m_axi_awvalid(dut_if.m_axi_awvalid),
    .m_axi_awready(dut_if.m_axi_awready),
    .m_axi_wdata(dut_if.m_axi_wdata),
    .m_axi_wstrb(dut_if.m_axi_wstrb),
    .m_axi_wlast(dut_if.m_axi_wlast),
    .m_axi_wvalid(dut_if.m_axi_wvalid),
    .m_axi_wready(dut_if.m_axi_wready),
    .m_axi_bid(dut_if.m_axi_bid),
    .m_axi_bresp(dut_if.m_axi_bresp),
    .m_axi_bvalid(dut_if.m_axi_bvalid),
    .m_axi_bready(dut_if.m_axi_bready),
    .cnt_input_w(dut_if.cnt_input_w),
    .cnt_bytes_written(dut_if.cnt_bytes_written),
    .cnt_halt(dut_if.cnt_halt),
    .cnt_eoe_observed(dut_if.cnt_eoe_observed),
    .clear_counters(dut_if.clear_counters),
    .dbg1_fifo_level(dut_if.dbg1_fifo_level),
    .dbg1_fifo_almost_full(dut_if.dbg1_fifo_almost_full),
    .dbg1_aw_inflight(dut_if.dbg1_aw_inflight),
    .dbg1_w_beats_remaining(dut_if.dbg1_w_beats_remaining),
    .dbg1_b_outstanding(dut_if.dbg1_b_outstanding),
    .dbg1_packer_slot(dut_if.dbg1_packer_slot_idx),
    .dbg1_packer_pending_eoe(dut_if.dbg1_packer_pending_eoe),
    .dbg1_writer_state(dut_if.dbg1_writer_state),
    .dbg1_halt_pulse(dut_if.dbg1_halt_pulse),
    .dbg2_meta_valid(dut_if.dbg2_meta_valid),
    .dbg2_meta(dbg2_meta_packed),
    .dbg2_writer_meta_valid(dut_if.dbg2_writer_meta_valid),
    .dbg2_writer_meta(dbg2_writer_meta_packed),
    .dbg2_writer_valid_mask(dbg2_writer_valid_mask)
  );

  default clocking cb @(posedge dut_if.clk); endclocking
  default disable iff (!dut_if.reset_n);

  ap_aw_hold: assert property (
    dut_if.m_axi_awvalid && !dut_if.m_axi_awready |=>
      dut_if.m_axi_awvalid && $stable(dut_if.m_axi_awaddr) &&
      $stable(dut_if.m_axi_awlen) && $stable(dut_if.m_axi_awsize) &&
      $stable(dut_if.m_axi_awburst)
  );

  ap_w_hold: assert property (
    dut_if.m_axi_wvalid && !dut_if.m_axi_wready |=>
      dut_if.m_axi_wvalid && $stable(dut_if.m_axi_wdata) &&
      $stable(dut_if.m_axi_wstrb) && $stable(dut_if.m_axi_wlast)
  );

  ap_aw_aligned: assert property (
    dut_if.m_axi_awvalid |-> ((dut_if.m_axi_awaddr & 64'h1f) == 64'h0)
  );

  ap_aw_baseline: assert property (
    dut_if.m_axi_awvalid |-> (dut_if.m_axi_awsize == 3'd5 && dut_if.m_axi_awburst == 2'b01)
  );

  initial begin
    uvm_config_db#(virtual rdma_dma_engine_if)::set(null, "*", "vif", dut_if);
    run_test();
  end

  final begin
    uvm_report_server svr;
    int error_count;
    int fatal_count;
    svr = uvm_report_server::get_server();
    error_count = svr.get_severity_count(UVM_ERROR);
    fatal_count = svr.get_severity_count(UVM_FATAL);
    if ((error_count + fatal_count) != 0) begin
      $display("RDMA_DMA_ENGINE_TB_FAIL errors=%0d fatals=%0d", error_count, fatal_count);
      $fatal(1, "UVM reported errors or fatals");
    end
  end
endmodule
