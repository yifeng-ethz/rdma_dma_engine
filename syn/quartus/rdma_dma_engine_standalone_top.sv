// File name: rdma_dma_engine_standalone_top.sv
// Author  : Yifeng Wang (yifenwan@phys.ethz.ch)
// Version : 26.1.0
// Date    : 20260510
// Change  : standalone synthesis harness for rdma_dma_engine sign-off

`default_nettype none

module rdma_dma_engine_standalone_top #(
    parameter int unsigned DMA_DATA_W  = 256,
    parameter int unsigned DBG2_META_W = 136
) (
    input  wire logic        clk,
    input  wire logic        reset_n,
    output logic [31:0]      signature
);

    logic [31:0]               stim_counter;
    logic [35:0]               s_axis_opq_tdata;
    logic                      s_axis_opq_tvalid;
    logic                      s_axis_opq_tready;
    logic                      s_axis_opq_tlast;
    logic [1:0]                s_axis_opq_tuser;
    logic                      job_req;
    logic [63:0]               job_seg0_addr;
    logic [63:0]               job_seg0_span;
    logic [63:0]               job_seg1_addr;
    logic [63:0]               job_seg1_span;
    logic [15:0]               job_sqe_id;
    logic [15:0]               job_opcode;
    logic                      job_done;
    logic [63:0]               job_bytes_written_total;
    logic [31:0]               job_seg0_bytes_written;
    logic [31:0]               job_seg1_bytes_written;
    logic [15:0]               job_status;
    logic [15:0]               job_sqe_id_echo;
    logic [31:0]               job_event_count;
    logic [63:0]               job_first_event_ts;
    logic [63:0]               job_last_event_ts;
    logic [3:0]                m_axi_awid;
    logic [63:0]               m_axi_awaddr;
    logic [7:0]                m_axi_awlen;
    logic [2:0]                m_axi_awsize;
    logic [1:0]                m_axi_awburst;
    logic                      m_axi_awvalid;
    logic                      m_axi_awready;
    logic [DMA_DATA_W-1:0]     m_axi_wdata;
    logic [DMA_DATA_W/8-1:0]   m_axi_wstrb;
    logic                      m_axi_wlast;
    logic                      m_axi_wvalid;
    logic                      m_axi_wready;
    logic [3:0]                m_axi_bid;
    logic [1:0]                m_axi_bresp;
    logic                      m_axi_bvalid;
    logic                      m_axi_bready;
    logic                      clear_counters;
    logic [31:0]               cnt_input_w;
    logic [31:0]               cnt_bytes_written;
    logic [31:0]               cnt_halt;
    logic [31:0]               cnt_eoe_observed;
    logic [8:0]                dbg1_fifo_level;
    logic                      dbg1_fifo_almost_full;
    logic [3:0]                dbg1_packer_slot;
    logic                      dbg1_packer_pending_eoe;
    logic [3:0]                dbg1_aw_inflight;
    logic [7:0]                dbg1_w_beats_remaining;
    logic [3:0]                dbg1_b_outstanding;
    logic                      dbg1_halt_pulse;
    logic [3:0]                dbg1_writer_state;
    logic                      dbg2_writer_meta_valid;
    logic [8*DBG2_META_W-1:0]  dbg2_writer_meta;
    logic [7:0]                dbg2_writer_valid_mask;

    always_ff @(posedge clk or negedge reset_n) begin : harness_stimulus
        if (!reset_n) begin
            stim_counter <= 32'h0000_0000;
        end else begin
            stim_counter <= stim_counter + 32'd1;
        end
    end

    assign s_axis_opq_tdata  = {stim_counter[3:0], stim_counter};
    assign s_axis_opq_tvalid = stim_counter[0] || stim_counter[3];
    assign s_axis_opq_tlast  = (stim_counter[7:0] == 8'h7f);
    assign s_axis_opq_tuser  = {1'b0, (stim_counter[4:0] == 5'h00)};

    assign job_req       = (stim_counter[11:0] == 12'h040);
    assign job_seg0_addr = {24'h00_0001, stim_counter[27:12], 12'h000};
    assign job_seg0_span = stim_counter[10] ? 64'h0000_0000_0000_2000 :
                                             64'h0000_0000_0000_1000;
    assign job_seg1_addr = {24'h00_0002, stim_counter[27:12], 12'h000};
    assign job_seg1_span = stim_counter[11] ? 64'h0000_0000_0000_1000 :
                                             64'h0000_0000_0000_0000;
    assign job_sqe_id    = stim_counter[15:0];
    assign job_opcode    = 16'h0001;

    assign m_axi_awready = stim_counter[1] || stim_counter[2];
    assign m_axi_wready  = stim_counter[2] || stim_counter[5];
    assign m_axi_bid     = 4'h0;
    assign m_axi_bresp   = 2'b00;
    assign m_axi_bvalid  = stim_counter[4] || stim_counter[6];
    assign clear_counters = (stim_counter[15:0] == 16'h8000);

    rdma_dma_engine #(
        .DMA_DATA_W                (DMA_DATA_W),
        .MAX_BURST_BEATS           (16),
        .SEG_QUANTUM_BYTES         (4096),
        .FIFO_DEPTH                (256),
        .FIFO_ALMOST_FULL_THRESHOLD(192),
        .DBG2_META_W               (DBG2_META_W),
        .DEBUG_LEVEL               (0)
    ) dut_i (
        .clk                    (clk),
        .reset_n                (reset_n),
        .s_axis_opq_tdata       (s_axis_opq_tdata),
        .s_axis_opq_tvalid      (s_axis_opq_tvalid),
        .s_axis_opq_tready      (s_axis_opq_tready),
        .s_axis_opq_tlast       (s_axis_opq_tlast),
        .s_axis_opq_tuser       (s_axis_opq_tuser),
        .job_req                (job_req),
        .job_seg0_addr          (job_seg0_addr),
        .job_seg0_span          (job_seg0_span),
        .job_seg1_addr          (job_seg1_addr),
        .job_seg1_span          (job_seg1_span),
        .job_sqe_id             (job_sqe_id),
        .job_opcode             (job_opcode),
        .job_done               (job_done),
        .job_bytes_written_total(job_bytes_written_total),
        .job_seg0_bytes_written (job_seg0_bytes_written),
        .job_seg1_bytes_written (job_seg1_bytes_written),
        .job_status             (job_status),
        .job_sqe_id_echo        (job_sqe_id_echo),
        .job_event_count        (job_event_count),
        .job_first_event_ts     (job_first_event_ts),
        .job_last_event_ts      (job_last_event_ts),
        .m_axi_awid             (m_axi_awid),
        .m_axi_awaddr           (m_axi_awaddr),
        .m_axi_awlen            (m_axi_awlen),
        .m_axi_awsize           (m_axi_awsize),
        .m_axi_awburst          (m_axi_awburst),
        .m_axi_awvalid          (m_axi_awvalid),
        .m_axi_awready          (m_axi_awready),
        .m_axi_wdata            (m_axi_wdata),
        .m_axi_wstrb            (m_axi_wstrb),
        .m_axi_wlast            (m_axi_wlast),
        .m_axi_wvalid           (m_axi_wvalid),
        .m_axi_wready           (m_axi_wready),
        .m_axi_bid              (m_axi_bid),
        .m_axi_bresp            (m_axi_bresp),
        .m_axi_bvalid           (m_axi_bvalid),
        .m_axi_bready           (m_axi_bready),
        .clear_counters         (clear_counters),
        .cnt_input_w            (cnt_input_w),
        .cnt_bytes_written      (cnt_bytes_written),
        .cnt_halt               (cnt_halt),
        .cnt_eoe_observed       (cnt_eoe_observed),
        .dbg1_fifo_level        (dbg1_fifo_level),
        .dbg1_fifo_almost_full  (dbg1_fifo_almost_full),
        .dbg1_packer_slot       (dbg1_packer_slot),
        .dbg1_packer_pending_eoe(dbg1_packer_pending_eoe),
        .dbg1_aw_inflight       (dbg1_aw_inflight),
        .dbg1_w_beats_remaining(dbg1_w_beats_remaining),
        .dbg1_b_outstanding     (dbg1_b_outstanding),
        .dbg1_halt_pulse        (dbg1_halt_pulse),
        .dbg1_writer_state      (dbg1_writer_state),
        .dbg2_meta_valid        (1'b0),
        .dbg2_meta              ('0),
        .dbg2_writer_meta_valid (dbg2_writer_meta_valid),
        .dbg2_writer_meta       (dbg2_writer_meta),
        .dbg2_writer_valid_mask (dbg2_writer_valid_mask)
    );

    assign signature = {
        ^m_axi_wdata[255:192] ^ ^job_bytes_written_total,
        ^m_axi_wdata[191:128] ^ ^job_first_event_ts,
        ^m_axi_wdata[127:64] ^ ^job_last_event_ts,
        ^m_axi_wdata[63:0] ^ ^m_axi_awaddr,
        ^m_axi_wstrb,
        m_axi_awvalid,
        m_axi_wvalid,
        m_axi_bready,
        job_done,
        s_axis_opq_tready,
        ^m_axi_awlen,
        ^job_status,
        ^job_sqe_id_echo,
        ^job_event_count,
        ^job_seg0_bytes_written,
        ^job_seg1_bytes_written,
        ^cnt_input_w,
        ^cnt_bytes_written,
        ^cnt_halt,
        ^cnt_eoe_observed,
        ^dbg1_fifo_level,
        dbg1_fifo_almost_full,
        ^dbg1_packer_slot,
        dbg1_packer_pending_eoe,
        ^dbg1_aw_inflight,
        ^dbg1_w_beats_remaining,
        ^dbg1_b_outstanding,
        dbg1_halt_pulse,
        ^dbg1_writer_state,
        dbg2_writer_meta_valid,
        ^dbg2_writer_valid_mask,
        ^dbg2_writer_meta
    };

endmodule

`default_nettype wire
