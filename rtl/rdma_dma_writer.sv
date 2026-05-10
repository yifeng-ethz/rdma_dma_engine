// File name: rdma_dma_writer.sv
// Author  : Yifeng Wang (yifenwan@phys.ethz.ch)
// Version : 26.1.0
// Date    : 20260510
// Change  : implement AXI4 burst writer with two-segment scatter

`default_nettype none

module rdma_dma_writer #(
    parameter int unsigned DMA_DATA_W       = 256,
    parameter int unsigned MAX_BURST_BEATS  = 16,
    parameter int unsigned SEG_QUANTUM_BYTES = 4096,
    parameter int unsigned FIFO_LEVEL_W     = 9,
    parameter int unsigned DBG2_META_W      = 136,
    parameter int unsigned DBG2_SLOTS       = 8,
    parameter int unsigned DEBUG_LEVEL      = 0
) (
    input  wire logic                           clk,
    input  wire logic                           reset_n,

    input  wire logic                           job_req,
    input  wire logic [63:0]                    job_seg0_addr,
    input  wire logic [63:0]                    job_seg0_span,
    input  wire logic [63:0]                    job_seg1_addr,
    input  wire logic [63:0]                    job_seg1_span,
    input  wire logic [15:0]                    job_sqe_id,
    input  wire logic [15:0]                    job_opcode,
    output logic                                job_done,
    output logic [63:0]                         job_bytes_written_total,
    output logic [31:0]                         job_seg0_bytes_written,
    output logic [31:0]                         job_seg1_bytes_written,
    output logic [15:0]                         job_status,
    output logic [15:0]                         job_sqe_id_echo,
    output logic [31:0]                         job_event_count,
    output logic [63:0]                         job_first_event_ts,
    output logic [63:0]                         job_last_event_ts,

    input  wire logic [DMA_DATA_W-1:0]          fifo_data,
    input  wire logic                           fifo_valid,
    output logic                                fifo_ready,
    input  wire logic                           fifo_last_in_event,
    input  wire logic [5:0]                     fifo_bytes_in_word,
    input  wire logic [63:0]                    fifo_event_ts,
    input  wire logic [DBG2_SLOTS*DBG2_META_W-1:0] fifo_dbg2_meta,
    input  wire logic [DBG2_SLOTS-1:0]          fifo_dbg2_valid_mask,
    input  wire logic [FIFO_LEVEL_W-1:0]        fifo_level,
    input  wire logic                           packer_empty,
    input  wire logic                           eoe_seen_pulse,
    input  wire logic [63:0]                    eoe_seen_ts,
    input  wire logic                           halt_pulse,

    output logic                                accepting_input,
    output logic                                flush_datapath,
    output logic                                write_bytes_valid,
    output logic [5:0]                          write_bytes,

    output logic [3:0]                          m_axi_awid,
    output logic [63:0]                         m_axi_awaddr,
    output logic [7:0]                          m_axi_awlen,
    output logic [2:0]                          m_axi_awsize,
    output logic [1:0]                          m_axi_awburst,
    output logic                                m_axi_awvalid,
    input  wire logic                           m_axi_awready,
    output logic [DMA_DATA_W-1:0]               m_axi_wdata,
    output logic [DMA_DATA_W/8-1:0]             m_axi_wstrb,
    output logic                                m_axi_wlast,
    output logic                                m_axi_wvalid,
    input  wire logic                           m_axi_wready,
    input  wire logic [3:0]                     m_axi_bid,
    input  wire logic [1:0]                     m_axi_bresp,
    input  wire logic                           m_axi_bvalid,
    output logic                                m_axi_bready,

    output logic [FIFO_LEVEL_W-1:0]             dbg1_fifo_level,
    output logic [3:0]                          dbg1_aw_inflight,
    output logic [7:0]                          dbg1_w_beats_remaining,
    output logic [3:0]                          dbg1_b_outstanding,
    output logic                                dbg1_halt_pulse,
    output logic [3:0]                          dbg1_writer_state,

    output logic                                dbg2_writer_meta_valid,
    output logic [DBG2_SLOTS*DBG2_META_W-1:0]   dbg2_writer_meta,
    output logic [DBG2_SLOTS-1:0]               dbg2_writer_valid_mask
);

    localparam int unsigned DMA_BYTES_CONST       = DMA_DATA_W / 8;
    localparam int unsigned AXI_SIZE_CONST        = $clog2(DMA_BYTES_CONST);
    localparam logic [1:0] AXI_BURST_INCR_CONST   = 2'b01;
    localparam logic [1:0] AXI_RESP_OKAY_CONST    = 2'b00;
    localparam logic [5:0] DMA_BYTES_6_CONST      = DMA_BYTES_CONST;
    localparam logic [7:0] MAX_BURST_BEATS_CONST  = MAX_BURST_BEATS;
    localparam logic [FIFO_LEVEL_W-1:0] MAX_BURST_LEVEL_CONST = MAX_BURST_BEATS;

    localparam int unsigned STATUS_EOE_CONST              = 0;
    localparam int unsigned STATUS_FULL_CONST             = 1;
    localparam int unsigned STATUS_HALT_CONST             = 2;
    localparam int unsigned STATUS_SEG_BOUNDARY_HIT_CONST = 3;
    localparam int unsigned STATUS_SEG0_ONLY_CONST        = 4;
    localparam int unsigned STATUS_ALIGN_ERR_CONST        = 5;
    localparam int unsigned STATUS_AXI_ERR_CONST          = 6;

    typedef enum logic [3:0] {
        WR_IDLING       = 4'd0,
        WR_PROGRAMMING  = 4'd1,
        WR_ISSUING_AW   = 4'd2,
        WR_WRITING      = 4'd3,
        WR_WAITING_B    = 4'd4,
        WR_REPORTING    = 4'd5
    } writer_fsm_state_t;

    typedef struct packed {
        writer_fsm_state_t state;
        logic [63:0]       seg0_addr;
        logic [63:0]       seg0_span;
        logic [63:0]       seg1_addr;
        logic [63:0]       seg1_span;
        logic [63:0]       cur_addr;
        logic [63:0]       bytes_left_seg;
        logic              cur_seg;
        logic [15:0]       sqe_id;
        logic [15:0]       opcode;
        logic [15:0]       status;
        logic [63:0]       total_bytes;
        logic [31:0]       seg0_bytes;
        logic [31:0]       seg1_bytes;
        logic [31:0]       event_count;
        logic [63:0]       first_event_ts;
        logic [63:0]       last_event_ts;
        logic              eoe_seen;
        logic              aw_latched;
        logic [7:0]        beats_in_burst;
        logic [7:0]        beats_remaining;
        logic [3:0]        last_bid;
    } writer_state_t;

    localparam writer_state_t WRITER_RESET_CONST = '{
        state           : WR_IDLING,
        seg0_addr       : 64'h0000_0000_0000_0000,
        seg0_span       : 64'h0000_0000_0000_0000,
        seg1_addr       : 64'h0000_0000_0000_0000,
        seg1_span       : 64'h0000_0000_0000_0000,
        cur_addr        : 64'h0000_0000_0000_0000,
        bytes_left_seg  : 64'h0000_0000_0000_0000,
        cur_seg         : 1'b0,
        sqe_id          : 16'h0000,
        opcode          : 16'h0000,
        status          : 16'h0000,
        total_bytes     : 64'h0000_0000_0000_0000,
        seg0_bytes      : 32'h0000_0000,
        seg1_bytes      : 32'h0000_0000,
        event_count     : 32'h0000_0000,
        first_event_ts  : 64'h0000_0000_0000_0000,
        last_event_ts   : 64'h0000_0000_0000_0000,
        eoe_seen        : 1'b0,
        aw_latched      : 1'b0,
        beats_in_burst  : 8'h00,
        beats_remaining : 8'h00,
        last_bid        : 4'h0
    };

    writer_state_t writer;

    logic       align_error;
    logic [7:0] aw_beats;
    logic       aw_can_issue;
    logic       aw_latch_ready;
    logic       aw_fire;
    logic       w_fire;
    logic       b_fire;
    logic       eoe_fifo_tail_ready;
    logic [5:0] useful_bytes;
    logic       final_beat_exhausts_seg;
    logic       eoe_report_ready;

    function automatic logic [7:0] choose_aw_beats(
        input logic [FIFO_LEVEL_W-1:0] level,
        input logic [63:0]             bytes_left
    );
        logic [7:0]  choose_v_segment_cap;
        logic [7:0]  choose_v_candidate;
        begin
            if (bytes_left[63:9] != '0) begin
                choose_v_segment_cap = MAX_BURST_BEATS_CONST;
            end else begin
                choose_v_segment_cap = {4'h0, bytes_left[8:5]};
            end

            choose_v_candidate = MAX_BURST_BEATS_CONST;
            if (level < MAX_BURST_LEVEL_CONST) begin
                choose_v_candidate = level[7:0];
            end
            if (choose_v_segment_cap < choose_v_candidate) begin
                choose_v_candidate = choose_v_segment_cap;
            end
            return choose_v_candidate;
        end
    endfunction

    function automatic logic [DMA_BYTES_CONST-1:0] make_wstrb(
        input logic [5:0] byte_count
    );
        logic [DMA_BYTES_CONST-1:0] make_wstrb_v_mask;
        int unsigned                make_wstrb_v_idx;
        begin
            make_wstrb_v_mask = '0;
            for (make_wstrb_v_idx = 0; make_wstrb_v_idx < DMA_BYTES_CONST;
                 make_wstrb_v_idx = make_wstrb_v_idx + 1) begin
                if (make_wstrb_v_idx < byte_count) begin
                    make_wstrb_v_mask[make_wstrb_v_idx] = 1'b1;
                end
            end
            return make_wstrb_v_mask;
        end
    endfunction

    assign align_error =
        (job_seg0_addr[11:0] != 12'h000) ||
        (job_seg0_span[11:0] != 12'h000) ||
        (job_seg0_span == 64'h0000_0000_0000_0000) ||
        ((job_seg1_span != 64'h0000_0000_0000_0000) &&
         ((job_seg1_addr[11:0] != 12'h000) || (job_seg1_span[11:0] != 12'h000)));

    assign aw_beats               = choose_aw_beats(fifo_level, writer.bytes_left_seg);
    assign aw_can_issue           = (writer.state == WR_ISSUING_AW) && writer.aw_latched;
    assign eoe_fifo_tail_ready    = writer.eoe_seen &&
                                    (packer_empty ||
                                     (fifo_level >= MAX_BURST_LEVEL_CONST));
    assign aw_latch_ready         = (writer.state == WR_ISSUING_AW) &&
                                    (aw_beats != 8'h00) &&
                                    (eoe_fifo_tail_ready ||
                                     (fifo_level >= MAX_BURST_LEVEL_CONST) ||
                                     ((64'(fifo_level) << AXI_SIZE_CONST) >=
                                      writer.bytes_left_seg));
    assign aw_fire                = aw_can_issue && m_axi_awready;
    assign w_fire                 = (writer.state == WR_WRITING) && fifo_valid && m_axi_wready;
    assign b_fire                 = (writer.state == WR_WAITING_B) && m_axi_bvalid;
    assign useful_bytes           =
        (fifo_bytes_in_word > DMA_BYTES_6_CONST) ? DMA_BYTES_6_CONST : fifo_bytes_in_word;
    assign final_beat_exhausts_seg =
        ({58'h00_0000_0000_0000, useful_bytes} >= writer.bytes_left_seg);
    assign eoe_report_ready       = writer.eoe_seen && (fifo_level == '0) && packer_empty;

    assign m_axi_awid             = 4'h0;
    assign m_axi_awaddr           = writer.cur_addr;
    assign m_axi_awlen            = writer.beats_in_burst - 8'd1;
    assign m_axi_awsize           = AXI_SIZE_CONST[2:0];
    assign m_axi_awburst          = AXI_BURST_INCR_CONST;
    assign m_axi_awvalid          = aw_can_issue;

    assign m_axi_wdata            = fifo_data;
    assign m_axi_wstrb            = make_wstrb(useful_bytes);
    assign m_axi_wlast            = (writer.beats_remaining == 8'd1);
    assign m_axi_wvalid           = (writer.state == WR_WRITING) && fifo_valid;
    assign fifo_ready             = (writer.state == WR_WRITING) && m_axi_wready;

    assign m_axi_bready           = (writer.state == WR_WAITING_B);

    assign accepting_input        = (writer.state != WR_IDLING) &&
                                    (writer.state != WR_REPORTING) &&
                                    !writer.eoe_seen &&
                                    !writer.status[STATUS_FULL_CONST] &&
                                    !writer.status[STATUS_ALIGN_ERR_CONST];
    assign flush_datapath         = (writer.state == WR_REPORTING);
    assign write_bytes_valid      = w_fire;
    assign write_bytes            = useful_bytes;

    assign job_done                = (writer.state == WR_REPORTING);
    assign job_bytes_written_total = writer.total_bytes;
    assign job_seg0_bytes_written  = writer.seg0_bytes;
    assign job_seg1_bytes_written  = writer.seg1_bytes;
    assign job_status              = writer.status;
    assign job_sqe_id_echo         = writer.sqe_id;
    assign job_event_count         = writer.event_count;
    assign job_first_event_ts      = writer.first_event_ts;
    assign job_last_event_ts       = writer.last_event_ts;

    always_ff @(posedge clk or negedge reset_n) begin : axi_write_engine
        if (!reset_n) begin
            writer <= WRITER_RESET_CONST;
        end else begin
            if (halt_pulse && accepting_input) begin
                writer.status[STATUS_HALT_CONST] <= 1'b1;
            end

            if (eoe_seen_pulse && accepting_input && !writer.eoe_seen) begin
                writer.eoe_seen                  <= 1'b1;
                writer.status[STATUS_EOE_CONST] <= 1'b1;
                writer.event_count               <= writer.event_count + 32'd1;
                writer.last_event_ts             <= eoe_seen_ts;
                if (writer.event_count == 32'h0000_0000) begin
                    writer.first_event_ts <= eoe_seen_ts;
                end
            end

            unique case (writer.state)
                WR_IDLING: begin
                    if (job_req) begin
                        writer                 <= WRITER_RESET_CONST;
                        writer.seg0_addr       <= job_seg0_addr;
                        writer.seg0_span       <= job_seg0_span;
                        writer.seg1_addr       <= job_seg1_addr;
                        writer.seg1_span       <= job_seg1_span;
                        writer.sqe_id          <= job_sqe_id;
                        writer.opcode          <= job_opcode;
                        writer.status[STATUS_SEG0_ONLY_CONST] <=
                            (job_seg1_span == 64'h0000_0000_0000_0000);
                        if (align_error) begin
                            writer.status[STATUS_ALIGN_ERR_CONST] <= 1'b1;
                            writer.state                          <= WR_REPORTING;
                        end else begin
                            writer.state <= WR_PROGRAMMING;
                        end
                    end
                end

                WR_PROGRAMMING: begin
                    if (writer.cur_seg == 1'b0) begin
                        writer.cur_addr       <= writer.seg0_addr;
                        writer.bytes_left_seg <= writer.seg0_span;
                    end else begin
                        writer.cur_addr       <= writer.seg1_addr;
                        writer.bytes_left_seg <= writer.seg1_span;
                    end
                    writer.aw_latched      <= 1'b0;
                    writer.beats_in_burst  <= 8'h00;
                    writer.beats_remaining <= 8'h00;
                    writer.state <= WR_ISSUING_AW;
                end

                WR_ISSUING_AW: begin
                    if (eoe_report_ready) begin
                        writer.state <= WR_REPORTING;
                    end else if (writer.bytes_left_seg == 64'h0000_0000_0000_0000) begin
                        if ((writer.cur_seg == 1'b0) &&
                            (writer.seg1_span != 64'h0000_0000_0000_0000) &&
                            !writer.eoe_seen) begin
                            writer.cur_seg <= 1'b1;
                            writer.status[STATUS_SEG_BOUNDARY_HIT_CONST] <= 1'b1;
                            writer.state   <= WR_PROGRAMMING;
                        end else begin
                            writer.status[STATUS_FULL_CONST] <= 1'b1;
                            writer.state                     <= WR_REPORTING;
                        end
                    end else if (!writer.aw_latched && aw_latch_ready) begin
                        writer.aw_latched      <= 1'b1;
                        writer.beats_in_burst  <= aw_beats;
                        writer.beats_remaining <= aw_beats;
                    end else if (aw_fire) begin
                        writer.aw_latched <= 1'b0;
                        writer.state           <= WR_WRITING;
                    end
                end

                WR_WRITING: begin
                    if (w_fire) begin
                        writer.cur_addr       <= writer.cur_addr + DMA_BYTES_CONST;
                        writer.total_bytes    <= writer.total_bytes + {58'h00_0000_0000_0000, useful_bytes};
                        writer.bytes_left_seg <= writer.bytes_left_seg -
                                                 {58'h00_0000_0000_0000, useful_bytes};
                        if (writer.cur_seg == 1'b0) begin
                            writer.seg0_bytes <= writer.seg0_bytes +
                                                 {26'h000_0000, useful_bytes};
                        end else begin
                            writer.seg1_bytes <= writer.seg1_bytes +
                                                 {26'h000_0000, useful_bytes};
                        end

                        if (fifo_last_in_event && !writer.eoe_seen) begin
                            writer.eoe_seen                  <= 1'b1;
                            writer.status[STATUS_EOE_CONST] <= 1'b1;
                            writer.event_count               <= writer.event_count + 32'd1;
                            writer.last_event_ts             <= fifo_event_ts;
                            if (writer.event_count == 32'h0000_0000) begin
                                writer.first_event_ts <= fifo_event_ts;
                            end
                        end

                        if (final_beat_exhausts_seg) begin
                            writer.status[STATUS_FULL_CONST] <=
                                (writer.cur_seg == 1'b1) ||
                                (writer.seg1_span == 64'h0000_0000_0000_0000);
                        end

                        if (writer.beats_remaining == 8'd1) begin
                            writer.beats_remaining <= 8'h00;
                            writer.state           <= WR_WAITING_B;
                        end else begin
                            writer.beats_remaining <= writer.beats_remaining - 8'd1;
                        end
                    end
                end

                WR_WAITING_B: begin
                    if (b_fire) begin
                        writer.last_bid <= m_axi_bid;
                        if (m_axi_bresp != AXI_RESP_OKAY_CONST) begin
                            writer.status[STATUS_AXI_ERR_CONST] <= 1'b1;
                        end

                        if (writer.eoe_seen) begin
                            writer.state <= WR_REPORTING;
                        end else if (writer.bytes_left_seg == 64'h0000_0000_0000_0000) begin
                            if ((writer.cur_seg == 1'b0) &&
                                (writer.seg1_span != 64'h0000_0000_0000_0000)) begin
                                writer.cur_seg <= 1'b1;
                                writer.status[STATUS_SEG_BOUNDARY_HIT_CONST] <= 1'b1;
                                writer.state   <= WR_PROGRAMMING;
                            end else begin
                                writer.status[STATUS_FULL_CONST] <= 1'b1;
                                writer.state                     <= WR_REPORTING;
                            end
                        end else begin
                            writer.aw_latched      <= 1'b0;
                            writer.beats_in_burst  <= 8'h00;
                            writer.beats_remaining <= 8'h00;
                            writer.state <= WR_ISSUING_AW;
                        end
                    end
                end

                WR_REPORTING: begin
                    writer.state <= WR_IDLING;
                end

                default: begin
                    writer.state <= WR_IDLING;
                end
            endcase
        end
    end

    generate
        if (DEBUG_LEVEL >= 1) begin : g_debug1
            assign dbg1_fifo_level        = fifo_level;
            assign dbg1_aw_inflight       =
                ((writer.state == WR_WRITING) || (writer.state == WR_WAITING_B)) ? 4'd1 : 4'd0;
            assign dbg1_w_beats_remaining = writer.beats_remaining;
            assign dbg1_b_outstanding     = (writer.state == WR_WAITING_B) ? 4'd1 : 4'd0;
            assign dbg1_halt_pulse        = halt_pulse;
            assign dbg1_writer_state      = writer.state;
        end else begin : g_no_debug1
            assign dbg1_fifo_level        = '0;
            assign dbg1_aw_inflight       = 4'h0;
            assign dbg1_w_beats_remaining = 8'h00;
            assign dbg1_b_outstanding     = 4'h0;
            assign dbg1_halt_pulse        = 1'b0;
            assign dbg1_writer_state      = 4'h0;
        end
    endgenerate

    generate
        if (DEBUG_LEVEL >= 2) begin : g_debug2
            assign dbg2_writer_meta_valid = w_fire;
            assign dbg2_writer_meta       = fifo_dbg2_meta;
            assign dbg2_writer_valid_mask = fifo_dbg2_valid_mask;
        end else begin : g_no_debug2
            assign dbg2_writer_meta_valid = 1'b0;
            assign dbg2_writer_meta       = '0;
            assign dbg2_writer_valid_mask = '0;
        end
    endgenerate

endmodule

`default_nettype wire
