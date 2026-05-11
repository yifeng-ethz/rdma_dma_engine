// File name: rdma_dma_engine.sv
// Author  : Yifeng Wang (yifenwan@phys.ethz.ch)
// Version : 26.1.0
// Date    : 20260510
// Change  : wire rdma_dma_engine packer FIFO and AXI4 writer top

`default_nettype none

module rdma_dma_engine #(
    parameter int unsigned DMA_DATA_W                = 256,
    parameter int unsigned MAX_BURST_BEATS           = 16,
    parameter int unsigned SEG_QUANTUM_BYTES         = 4096,
    parameter int unsigned FIFO_DEPTH                = 256,
    parameter int unsigned FIFO_ALMOST_FULL_THRESHOLD = 192,
    parameter int unsigned DBG2_META_W               = 136,
    parameter int unsigned DEBUG_LEVEL               = 0
) (
    input  wire logic                                clk,
    input  wire logic                                reset_n,

    input  wire logic [35:0]                         s_axis_opq_tdata,
    input  wire logic                                s_axis_opq_tvalid,
    output logic                                     s_axis_opq_tready,
    input  wire logic                                s_axis_opq_tlast,
    input  wire logic [1:0]                          s_axis_opq_tuser,

    input  wire logic                                job_req,
    input  wire logic [63:0]                         job_seg0_addr,
    input  wire logic [63:0]                         job_seg0_span,
    input  wire logic [63:0]                         job_seg1_addr,
    input  wire logic [63:0]                         job_seg1_span,
    input  wire logic [15:0]                         job_rqe_id,
    input  wire logic [15:0]                         job_opcode,
    output logic                                     job_done,
    output logic [63:0]                              job_bytes_written_total,
    output logic [31:0]                              job_seg0_bytes_written,
    output logic [31:0]                              job_seg1_bytes_written,
    output logic [15:0]                              job_status,
    output logic [15:0]                              job_rqe_id_echo,
    output logic [31:0]                              job_event_count,
    output logic [63:0]                              job_first_event_ts,
    output logic [63:0]                              job_last_event_ts,

    output logic [3:0]                               m_axi_awid,
    output logic [63:0]                              m_axi_awaddr,
    output logic [7:0]                               m_axi_awlen,
    output logic [2:0]                               m_axi_awsize,
    output logic [1:0]                               m_axi_awburst,
    output logic                                     m_axi_awvalid,
    input  wire logic                                m_axi_awready,
    output logic [DMA_DATA_W-1:0]                    m_axi_wdata,
    output logic [DMA_DATA_W/8-1:0]                  m_axi_wstrb,
    output logic                                     m_axi_wlast,
    output logic                                     m_axi_wvalid,
    input  wire logic                                m_axi_wready,
    input  wire logic [3:0]                          m_axi_bid,
    input  wire logic [1:0]                          m_axi_bresp,
    input  wire logic                                m_axi_bvalid,
    output logic                                     m_axi_bready,

    input  wire logic                                clear_counters,
    output logic [31:0]                              cnt_input_w,
    output logic [31:0]                              cnt_bytes_written,
    output logic [31:0]                              cnt_halt,
    output logic [31:0]                              cnt_eoe_observed,

    output logic [$clog2(FIFO_DEPTH+1)-1:0]          dbg1_fifo_level,
    output logic                                     dbg1_fifo_almost_full,
    output logic [3:0]                               dbg1_packer_slot,
    output logic                                     dbg1_packer_pending_eoe,
    output logic [3:0]                               dbg1_aw_inflight,
    output logic [7:0]                               dbg1_w_beats_remaining,
    output logic [3:0]                               dbg1_b_outstanding,
    output logic                                     dbg1_halt_pulse,
    output logic [3:0]                               dbg1_writer_state,

    input  wire logic                                dbg2_meta_valid,
    input  wire logic [DBG2_META_W-1:0]              dbg2_meta,
    output logic                                     dbg2_writer_meta_valid,
    output logic [8*DBG2_META_W-1:0]                 dbg2_writer_meta,
    output logic [7:0]                               dbg2_writer_valid_mask
);

    localparam int unsigned OPQ_DATA_W_CONST     = 32;
    localparam int unsigned DBG2_SLOTS_CONST     = DMA_DATA_W / OPQ_DATA_W_CONST;
    localparam int unsigned FIFO_LEVEL_W_CONST   = $clog2(FIFO_DEPTH + 1);
    localparam logic [31:0] COUNTER_MAX_CONST    = 32'hffff_ffff;

    logic [DMA_DATA_W-1:0]                       packed_data;
    logic                                        packed_valid;
    logic                                        packed_ready;
    logic                                        packed_last_in_event;
    logic [5:0]                                  packed_bytes_in_word;
    logic [63:0]                                 packed_event_ts;
    logic [DBG2_SLOTS_CONST*DBG2_META_W-1:0]     packed_dbg2_meta;
    logic [DBG2_SLOTS_CONST-1:0]                 packed_dbg2_valid_mask;
    logic                                        packer_input_word_pulse;
    logic                                        packer_eoe_pulse;
    logic [63:0]                                 packer_eoe_ts;
    logic                                        packer_halt_pulse;
    logic                                        packer_empty;

    logic [DMA_DATA_W-1:0]                       fifo_read_data;
    logic                                        fifo_read_valid;
    logic                                        fifo_read_ready;
    logic                                        fifo_read_last_in_event;
    logic [5:0]                                  fifo_read_bytes_in_word;
    logic [63:0]                                 fifo_read_event_ts;
    logic [DBG2_SLOTS_CONST*DBG2_META_W-1:0]     fifo_read_dbg2_meta;
    logic [DBG2_SLOTS_CONST-1:0]                 fifo_read_dbg2_valid_mask;
    logic [FIFO_LEVEL_W_CONST-1:0]               fifo_level;
    logic                                        fifo_almost_full;
    logic                                        fifo_empty;
    logic                                        fifo_full;

    logic                                        writer_accepting_input;
    logic                                        writer_flush_datapath;
    logic                                        writer_write_bytes_valid;
    logic [5:0]                                  writer_write_bytes;
    logic [FIFO_LEVEL_W_CONST-1:0]               writer_dbg1_fifo_level;

    function automatic logic [31:0] sat_inc32(
        input logic [31:0] value
    );
        begin
            if (value == COUNTER_MAX_CONST) begin
                return value;
            end
            return value + 32'd1;
        end
    endfunction

    function automatic logic [31:0] sat_add_bytes32(
        input logic [31:0] value,
        input logic [5:0]  byte_count
    );
        logic [32:0] sat_add_v_sum;
        begin
            sat_add_v_sum = {1'b0, value} + {27'h000_0000, byte_count};
            if (sat_add_v_sum[32]) begin
                return COUNTER_MAX_CONST;
            end
            return sat_add_v_sum[31:0];
        end
    endfunction

    rdma_dma_packer #(
        .DMA_DATA_W   (DMA_DATA_W),
        .OPQ_DATA_W   (OPQ_DATA_W_CONST),
        .SLOTS_PER_DMA(DBG2_SLOTS_CONST),
        .DBG2_META_W  (DBG2_META_W),
        .DEBUG_LEVEL  (DEBUG_LEVEL)
    ) packer_i (
        .clk                   (clk),
        .reset_n               (reset_n),
        .enable                (writer_accepting_input),
        .flush                 (writer_flush_datapath),
        .opq_data              (s_axis_opq_tdata[31:0]),
        .opq_datak             (s_axis_opq_tdata[35:32]),
        .opq_valid             (s_axis_opq_tvalid),
        .opq_ready             (s_axis_opq_tready),
        .opq_sop               (s_axis_opq_tuser[0]),
        .opq_eop               (s_axis_opq_tlast),
        .fifo_almost_full      (fifo_almost_full),
        .packed_ready          (packed_ready),
        .packed_data           (packed_data),
        .packed_valid          (packed_valid),
        .packed_last_in_event  (packed_last_in_event),
        .packed_bytes_in_word  (packed_bytes_in_word),
        .packed_event_ts       (packed_event_ts),
        .input_word_pulse      (packer_input_word_pulse),
        .eoe_pulse             (packer_eoe_pulse),
        .eoe_ts                (packer_eoe_ts),
        .halt_pulse            (packer_halt_pulse),
        .packer_empty          (packer_empty),
        .dbg1_slot_index       (dbg1_packer_slot),
        .dbg1_pending_eoe      (dbg1_packer_pending_eoe),
        .dbg2_meta_valid       (dbg2_meta_valid),
        .dbg2_meta             (dbg2_meta),
        .packed_dbg2_meta      (packed_dbg2_meta),
        .packed_dbg2_valid_mask(packed_dbg2_valid_mask)
    );

    rdma_dma_data_fifo #(
        .DATA_W               (DMA_DATA_W),
        .DEPTH                (FIFO_DEPTH),
        .ALMOST_FULL_THRESHOLD(FIFO_ALMOST_FULL_THRESHOLD),
        .DBG2_META_W          (DBG2_META_W),
        .DBG2_SLOTS           (DBG2_SLOTS_CONST),
        .DEBUG_LEVEL          (DEBUG_LEVEL)
    ) data_fifo_i (
        .clk                  (clk),
        .reset_n              (reset_n),
        .flush                (writer_flush_datapath),
        .write_data           (packed_data),
        .write_valid          (packed_valid),
        .write_ready          (packed_ready),
        .write_last_in_event  (packed_last_in_event),
        .write_bytes_in_word  (packed_bytes_in_word),
        .write_event_ts       (packed_event_ts),
        .write_dbg2_meta      (packed_dbg2_meta),
        .write_dbg2_valid_mask(packed_dbg2_valid_mask),
        .read_data            (fifo_read_data),
        .read_valid           (fifo_read_valid),
        .read_ready           (fifo_read_ready),
        .read_last_in_event   (fifo_read_last_in_event),
        .read_bytes_in_word   (fifo_read_bytes_in_word),
        .read_event_ts        (fifo_read_event_ts),
        .read_dbg2_meta       (fifo_read_dbg2_meta),
        .read_dbg2_valid_mask (fifo_read_dbg2_valid_mask),
        .fifo_level           (fifo_level),
        .fifo_almost_full     (fifo_almost_full),
        .fifo_empty           (fifo_empty),
        .fifo_full            (fifo_full)
    );

    rdma_dma_writer #(
        .DMA_DATA_W      (DMA_DATA_W),
        .MAX_BURST_BEATS (MAX_BURST_BEATS),
        .SEG_QUANTUM_BYTES(SEG_QUANTUM_BYTES),
        .FIFO_LEVEL_W    (FIFO_LEVEL_W_CONST),
        .DBG2_META_W     (DBG2_META_W),
        .DBG2_SLOTS      (DBG2_SLOTS_CONST),
        .DEBUG_LEVEL     (DEBUG_LEVEL)
    ) writer_i (
        .clk                    (clk),
        .reset_n                (reset_n),
        .job_req                (job_req),
        .job_seg0_addr          (job_seg0_addr),
        .job_seg0_span          (job_seg0_span),
        .job_seg1_addr          (job_seg1_addr),
        .job_seg1_span          (job_seg1_span),
        .job_rqe_id             (job_rqe_id),
        .job_opcode             (job_opcode),
        .job_done               (job_done),
        .job_bytes_written_total(job_bytes_written_total),
        .job_seg0_bytes_written (job_seg0_bytes_written),
        .job_seg1_bytes_written (job_seg1_bytes_written),
        .job_status             (job_status),
        .job_rqe_id_echo        (job_rqe_id_echo),
        .job_event_count        (job_event_count),
        .job_first_event_ts     (job_first_event_ts),
        .job_last_event_ts      (job_last_event_ts),
        .fifo_data              (fifo_read_data),
        .fifo_valid             (fifo_read_valid),
        .fifo_ready             (fifo_read_ready),
        .fifo_last_in_event     (fifo_read_last_in_event),
        .fifo_bytes_in_word     (fifo_read_bytes_in_word),
        .fifo_event_ts          (fifo_read_event_ts),
        .fifo_dbg2_meta         (fifo_read_dbg2_meta),
        .fifo_dbg2_valid_mask   (fifo_read_dbg2_valid_mask),
        .fifo_level             (fifo_level),
        .packer_empty           (packer_empty),
        .eoe_seen_pulse         (packer_eoe_pulse),
        .eoe_seen_ts            (packer_eoe_ts),
        .halt_pulse             (packer_halt_pulse),
        .accepting_input        (writer_accepting_input),
        .flush_datapath         (writer_flush_datapath),
        .write_bytes_valid      (writer_write_bytes_valid),
        .write_bytes            (writer_write_bytes),
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
        .dbg1_fifo_level        (writer_dbg1_fifo_level),
        .dbg1_aw_inflight       (dbg1_aw_inflight),
        .dbg1_w_beats_remaining(dbg1_w_beats_remaining),
        .dbg1_b_outstanding     (dbg1_b_outstanding),
        .dbg1_halt_pulse        (dbg1_halt_pulse),
        .dbg1_writer_state      (dbg1_writer_state),
        .dbg2_writer_meta_valid (dbg2_writer_meta_valid),
        .dbg2_writer_meta       (dbg2_writer_meta),
        .dbg2_writer_valid_mask (dbg2_writer_valid_mask)
    );

    assign dbg1_fifo_level       = writer_dbg1_fifo_level;
    assign dbg1_fifo_almost_full = (DEBUG_LEVEL >= 1) ? fifo_almost_full : 1'b0;

    always_ff @(posedge clk or negedge reset_n) begin : sideband_counter_bank
        if (!reset_n) begin
            cnt_input_w       <= 32'h0000_0000;
            cnt_bytes_written <= 32'h0000_0000;
            cnt_halt          <= 32'h0000_0000;
            cnt_eoe_observed  <= 32'h0000_0000;
        end else if (clear_counters) begin
            cnt_input_w       <= 32'h0000_0000;
            cnt_bytes_written <= 32'h0000_0000;
            cnt_halt          <= 32'h0000_0000;
            cnt_eoe_observed  <= 32'h0000_0000;
        end else begin
            if (packer_input_word_pulse) begin
                cnt_input_w <= sat_inc32(cnt_input_w);
            end

            if (writer_write_bytes_valid) begin
                cnt_bytes_written <= sat_add_bytes32(cnt_bytes_written, writer_write_bytes);
            end

            if (packer_halt_pulse) begin
                cnt_halt <= sat_inc32(cnt_halt);
            end

            if (packer_eoe_pulse) begin
                cnt_eoe_observed <= sat_inc32(cnt_eoe_observed);
            end
        end
    end

endmodule

`default_nettype wire
