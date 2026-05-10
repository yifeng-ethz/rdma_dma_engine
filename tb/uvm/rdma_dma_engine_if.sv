`ifndef RDMA_DMA_ENGINE_IF_SV
`define RDMA_DMA_ENGINE_IF_SV

interface rdma_dma_engine_if #(
  parameter int unsigned DMA_DATA_W = 256,
  parameter int unsigned DBG2_SLOTS = 8
);
  logic clk;
  logic reset_n;

  logic [35:0] s_axis_opq_tdata;
  logic        s_axis_opq_tvalid;
  logic        s_axis_opq_tready;
  logic        s_axis_opq_tlast;
  logic [1:0]  s_axis_opq_tuser;

  logic        job_req;
  logic [63:0] job_seg0_addr;
  logic [63:0] job_seg0_span;
  logic [63:0] job_seg1_addr;
  logic [63:0] job_seg1_span;
  logic [15:0] job_sqe_id;
  logic [15:0] job_opcode;
  logic        job_done;
  logic [63:0] job_bytes_written_total;
  logic [31:0] job_seg0_bytes_written;
  logic [31:0] job_seg1_bytes_written;
  logic [15:0] job_status;
  logic [15:0] job_sqe_id_echo;
  logic [31:0] job_event_count;
  logic [63:0] job_first_event_ts;
  logic [63:0] job_last_event_ts;

  logic [3:0]            m_axi_awid;
  logic [63:0]           m_axi_awaddr;
  logic [7:0]            m_axi_awlen;
  logic [2:0]            m_axi_awsize;
  logic [1:0]            m_axi_awburst;
  logic                  m_axi_awvalid;
  logic                  m_axi_awready;
  logic [DMA_DATA_W-1:0] m_axi_wdata;
  logic [DMA_DATA_W/8-1:0] m_axi_wstrb;
  logic                  m_axi_wlast;
  logic                  m_axi_wvalid;
  logic                  m_axi_wready;
  logic [3:0]            m_axi_bid;
  logic [1:0]            m_axi_bresp;
  logic                  m_axi_bvalid;
  logic                  m_axi_bready;

  logic [31:0] cnt_input_w;
  logic [31:0] cnt_bytes_written;
  logic [31:0] cnt_halt;
  logic [31:0] cnt_eoe_observed;
  logic        clear_counters;

  logic [8:0]  dbg1_fifo_level;
  logic        dbg1_fifo_almost_full;
  logic [3:0]  dbg1_aw_inflight;
  logic [7:0]  dbg1_w_beats_remaining;
  logic [3:0]  dbg1_b_outstanding;
  logic [3:0]  dbg1_packer_slot_idx;
  logic        dbg1_packer_pending_eoe;
  logic [3:0]  dbg1_writer_state;
  logic        dbg1_halt_pulse;

  logic        dbg2_meta_valid;
  logic [3:0]  dbg2_meta_lane;
  logic [31:0] dbg2_meta_hit_id;
  logic [63:0] dbg2_meta_source_ts;
  logic [31:0] dbg2_meta_sequence_no;
  logic        dbg2_writer_meta_valid;
  logic [DBG2_SLOTS-1:0] dbg2_writer_meta_valid_mask;
  logic [DBG2_SLOTS*4-1:0]  dbg2_writer_meta_lane;
  logic [DBG2_SLOTS*32-1:0] dbg2_writer_meta_hit_id;
  logic [DBG2_SLOTS*64-1:0] dbg2_writer_meta_source_ts;
  logic [DBG2_SLOTS*32-1:0] dbg2_writer_meta_sequence_no;

  task automatic drive_idle();
    s_axis_opq_tdata <= '0;
    s_axis_opq_tvalid <= 1'b0;
    s_axis_opq_tlast <= 1'b0;
    s_axis_opq_tuser <= '0;
    job_req <= 1'b0;
    job_seg0_addr <= '0;
    job_seg0_span <= '0;
    job_seg1_addr <= '0;
    job_seg1_span <= '0;
    job_sqe_id <= '0;
    job_opcode <= '0;
    m_axi_awready <= 1'b0;
    m_axi_wready <= 1'b0;
    m_axi_bid <= '0;
    m_axi_bresp <= 2'b00;
    m_axi_bvalid <= 1'b0;
    clear_counters <= 1'b0;
    dbg2_meta_valid <= 1'b0;
    dbg2_meta_lane <= '0;
    dbg2_meta_hit_id <= '0;
    dbg2_meta_source_ts <= '0;
    dbg2_meta_sequence_no <= '0;
  endtask

  task automatic preload_counter_input_near_max();
    @(negedge clk);
    force rdma_dma_engine_tb_top.dut.cnt_input_w = 32'hffff_fffe;
    force rdma_dma_engine_tb_top.dut.cnt_bytes_written = 32'h0000_0000;
    force rdma_dma_engine_tb_top.dut.cnt_halt = 32'h0000_0000;
    force rdma_dma_engine_tb_top.dut.cnt_eoe_observed = 32'h0000_0000;
    @(negedge clk);
    release rdma_dma_engine_tb_top.dut.cnt_input_w;
    release rdma_dma_engine_tb_top.dut.cnt_bytes_written;
    release rdma_dma_engine_tb_top.dut.cnt_halt;
    release rdma_dma_engine_tb_top.dut.cnt_eoe_observed;
    @(posedge clk);
  endtask

  task automatic preload_counter_bytes_near_max();
    @(negedge clk);
    force rdma_dma_engine_tb_top.dut.cnt_input_w = 32'h0000_0000;
    force rdma_dma_engine_tb_top.dut.cnt_bytes_written = 32'hffff_ffe0;
    force rdma_dma_engine_tb_top.dut.cnt_halt = 32'h0000_0000;
    force rdma_dma_engine_tb_top.dut.cnt_eoe_observed = 32'h0000_0000;
    @(negedge clk);
    release rdma_dma_engine_tb_top.dut.cnt_input_w;
    release rdma_dma_engine_tb_top.dut.cnt_bytes_written;
    release rdma_dma_engine_tb_top.dut.cnt_halt;
    release rdma_dma_engine_tb_top.dut.cnt_eoe_observed;
    @(posedge clk);
  endtask

  task automatic preload_counter_bank_max();
    @(negedge clk);
    force rdma_dma_engine_tb_top.dut.cnt_input_w = 32'hffff_ffff;
    force rdma_dma_engine_tb_top.dut.cnt_bytes_written = 32'hffff_ffff;
    force rdma_dma_engine_tb_top.dut.cnt_halt = 32'hffff_ffff;
    force rdma_dma_engine_tb_top.dut.cnt_eoe_observed = 32'hffff_ffff;
    @(negedge clk);
    release rdma_dma_engine_tb_top.dut.cnt_input_w;
    release rdma_dma_engine_tb_top.dut.cnt_bytes_written;
    release rdma_dma_engine_tb_top.dut.cnt_halt;
    release rdma_dma_engine_tb_top.dut.cnt_eoe_observed;
    @(posedge clk);
  endtask

  function automatic logic [63:0] packer_cycle_count();
    return rdma_dma_engine_tb_top.dut.packer_i.packer.cycle_count;
  endfunction
endinterface

`endif
