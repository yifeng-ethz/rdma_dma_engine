// File name: rdma_dma_packer.sv
// Author  : Yifeng Wang (yifenwan@phys.ethz.ch)
// Version : 26.1.0
// Date    : 20260510
// Change  : port OPQ DMA packer with byte-count and DEBUG sidebands

`default_nettype none

module rdma_dma_packer #(
    parameter int unsigned DMA_DATA_W    = 256,
    parameter int unsigned OPQ_DATA_W    = 32,
    parameter int unsigned SLOTS_PER_DMA = DMA_DATA_W / OPQ_DATA_W,
    parameter int unsigned DBG2_META_W   = 136,
    parameter int unsigned DEBUG_LEVEL   = 0
) (
    input  wire logic                                      clk,
    input  wire logic                                      reset_n,

    input  wire logic                                      enable,
    input  wire logic                                      flush,

    input  wire logic [OPQ_DATA_W-1:0]                     opq_data,
    input  wire logic [OPQ_DATA_W/8-1:0]                   opq_datak,
    input  wire logic                                      opq_valid,
    output logic                                           opq_ready,
    input  wire logic                                      opq_sop,
    input  wire logic                                      opq_eop,

    input  wire logic                                      fifo_almost_full,
    input  wire logic                                      packed_ready,

    output logic [DMA_DATA_W-1:0]                          packed_data,
    output logic                                           packed_valid,
    output logic                                           packed_last_in_event,
    output logic [5:0]                                     packed_bytes_in_word,
    output logic [63:0]                                    packed_event_ts,

    output logic                                           input_word_pulse,
    output logic                                           eoe_pulse,
    output logic [63:0]                                    eoe_ts,
    output logic                                           halt_pulse,
    output logic                                           packer_empty,

    output logic [3:0]                                     dbg1_slot_index,
    output logic                                           dbg1_pending_eoe,

    input  wire logic                                      dbg2_meta_valid,
    input  wire logic [DBG2_META_W-1:0]                    dbg2_meta,
    output logic [SLOTS_PER_DMA*DBG2_META_W-1:0]           packed_dbg2_meta,
    output logic [SLOTS_PER_DMA-1:0]                       packed_dbg2_valid_mask
);

    localparam int unsigned OPQ_BYTES_CONST    = OPQ_DATA_W / 8;
    localparam int unsigned SLOT_COUNT_W_CONST = $clog2(SLOTS_PER_DMA + 1);
    localparam logic [SLOT_COUNT_W_CONST-1:0] SLOTS_PER_DMA_COUNT_CONST =
        SLOTS_PER_DMA;
    localparam logic [5:0] DMA_BYTES_PER_WORD_CONST = (DMA_DATA_W / 8);
    localparam logic [5:0] OPQ_BYTES_PER_WORD_CONST = OPQ_BYTES_CONST;

    typedef struct packed {
        logic [DMA_DATA_W-1:0]                data;
        logic [SLOTS_PER_DMA*DBG2_META_W-1:0] dbg2_meta;
        logic [SLOTS_PER_DMA-1:0]             dbg2_valid_mask;
        logic [SLOT_COUNT_W_CONST-1:0]        slot_count;
        logic                                 pending_eoe;
        logic [63:0]                          pending_eoe_ts;
        logic [63:0]                          cycle_count;
    } packer_state_t;

    packer_state_t packer;

    logic                                can_emit;
    logic                                accept_word;
    logic                                drop_word;
    logic                                zero_byte_eoe;
    logic [DMA_DATA_W-1:0]               data_with_word;
    logic [SLOTS_PER_DMA*DBG2_META_W-1:0] dbg2_meta_with_word;
    logic [SLOTS_PER_DMA-1:0]            dbg2_mask_with_word;
    logic [SLOT_COUNT_W_CONST-1:0]       next_slot_count;

    function automatic logic [DMA_DATA_W-1:0] insert_word(
        input logic [DMA_DATA_W-1:0]            base_data,
        input logic [SLOT_COUNT_W_CONST-1:0]    slot_index,
        input logic [OPQ_DATA_W-1:0]            word_data
    );
        logic [DMA_DATA_W-1:0] insert_word_v_result;
        begin
            insert_word_v_result = base_data;
            insert_word_v_result[slot_index*OPQ_DATA_W +: OPQ_DATA_W] = word_data;
            return insert_word_v_result;
        end
    endfunction

    function automatic logic [SLOTS_PER_DMA*DBG2_META_W-1:0] insert_meta(
        input logic [SLOTS_PER_DMA*DBG2_META_W-1:0] base_meta,
        input logic [SLOT_COUNT_W_CONST-1:0]        slot_index,
        input logic [DBG2_META_W-1:0]               meta_data
    );
        logic [SLOTS_PER_DMA*DBG2_META_W-1:0] insert_meta_v_result;
        begin
            insert_meta_v_result = base_meta;
            insert_meta_v_result[slot_index*DBG2_META_W +: DBG2_META_W] = meta_data;
            return insert_meta_v_result;
        end
    endfunction

    assign opq_ready           = 1'b1;
    assign can_emit            = !packed_valid || packed_ready;
    assign drop_word           = enable && opq_valid && (fifo_almost_full || !can_emit);
    assign accept_word         = enable && opq_valid && !fifo_almost_full && can_emit;
    assign zero_byte_eoe       = enable && !opq_valid && opq_eop && can_emit;
    assign data_with_word      = insert_word(packer.data, packer.slot_count, opq_data);
    assign dbg2_meta_with_word = insert_meta(packer.dbg2_meta, packer.slot_count, dbg2_meta);
    assign dbg2_mask_with_word = packer.dbg2_valid_mask |
                                 ({{(SLOTS_PER_DMA-1){1'b0}}, dbg2_meta_valid} <<
                                  packer.slot_count);
    assign next_slot_count     = packer.slot_count + {{(SLOT_COUNT_W_CONST-1){1'b0}}, 1'b1};
    assign eoe_ts              = packer.cycle_count;
    assign packer_empty        = !packed_valid && !packer.pending_eoe &&
                                 (packer.slot_count == '0);

    always_ff @(posedge clk or negedge reset_n) begin : opq_packer
        if (!reset_n) begin
            packer.data            <= '0;
            packer.dbg2_meta       <= '0;
            packer.dbg2_valid_mask <= '0;
            packer.slot_count      <= '0;
            packer.pending_eoe     <= 1'b0;
            packer.pending_eoe_ts  <= 64'h0000_0000_0000_0000;
            packer.cycle_count     <= 64'h0000_0000_0000_0000;
            packed_data           <= '0;
            packed_valid          <= 1'b0;
            packed_last_in_event  <= 1'b0;
            packed_bytes_in_word  <= 6'h00;
            packed_event_ts       <= 64'h0000_0000_0000_0000;
            packed_dbg2_meta      <= '0;
            packed_dbg2_valid_mask <= '0;
            input_word_pulse      <= 1'b0;
            eoe_pulse             <= 1'b0;
            halt_pulse            <= 1'b0;
        end else begin
            packer.cycle_count <= packer.cycle_count + 64'd1;
            input_word_pulse   <= enable && opq_valid;
            eoe_pulse          <= enable && opq_eop;
            halt_pulse         <= drop_word;

            if (packed_valid && packed_ready) begin
                packed_valid <= 1'b0;
            end

            if (flush || !enable) begin
                packer.data            <= '0;
                packer.dbg2_meta       <= '0;
                packer.dbg2_valid_mask <= '0;
                packer.slot_count      <= '0;
                packer.pending_eoe     <= 1'b0;
                packer.pending_eoe_ts  <= 64'h0000_0000_0000_0000;
                packed_valid           <= 1'b0;
                packed_data            <= '0;
                packed_last_in_event   <= 1'b0;
                packed_bytes_in_word   <= 6'h00;
                packed_event_ts        <= 64'h0000_0000_0000_0000;
                packed_dbg2_meta       <= '0;
                packed_dbg2_valid_mask <= '0;
            end else if (accept_word) begin
                if ((next_slot_count == SLOTS_PER_DMA_COUNT_CONST)) begin
                    packed_data            <= data_with_word;
                    packed_valid           <= 1'b1;
                    packed_last_in_event   <= packer.pending_eoe || opq_eop;
                    packed_bytes_in_word   <= DMA_BYTES_PER_WORD_CONST;
                    packed_event_ts        <= opq_eop ? packer.cycle_count :
                                             packer.pending_eoe_ts;
                    packed_dbg2_meta       <= (DEBUG_LEVEL >= 2) ? dbg2_meta_with_word : '0;
                    packed_dbg2_valid_mask <= (DEBUG_LEVEL >= 2) ? dbg2_mask_with_word : '0;
                    packer.data            <= '0;
                    packer.dbg2_meta       <= '0;
                    packer.dbg2_valid_mask <= '0;
                    packer.slot_count      <= '0;
                    packer.pending_eoe     <= 1'b0;
                    packer.pending_eoe_ts  <= 64'h0000_0000_0000_0000;
                end else begin
                    packer.data            <= data_with_word;
                    packer.dbg2_meta       <= (DEBUG_LEVEL >= 2) ? dbg2_meta_with_word : '0;
                    packer.dbg2_valid_mask <= (DEBUG_LEVEL >= 2) ? dbg2_mask_with_word : '0;
                    packer.slot_count      <= next_slot_count;
                    packer.pending_eoe     <= packer.pending_eoe || opq_eop;
                    if (opq_eop) begin
                        packer.pending_eoe_ts <= packer.cycle_count;
                    end
                end
            end else if (packer.pending_eoe && (packer.slot_count != '0) && can_emit) begin
                packed_data            <= packer.data;
                packed_valid           <= 1'b1;
                packed_last_in_event   <= 1'b1;
                packed_bytes_in_word   <=
                    {2'b00, packer.slot_count} * OPQ_BYTES_PER_WORD_CONST;
                packed_event_ts        <= packer.pending_eoe_ts;
                packed_dbg2_meta       <= (DEBUG_LEVEL >= 2) ? packer.dbg2_meta : '0;
                packed_dbg2_valid_mask <= (DEBUG_LEVEL >= 2) ? packer.dbg2_valid_mask : '0;
                packer.data            <= '0;
                packer.dbg2_meta       <= '0;
                packer.dbg2_valid_mask <= '0;
                packer.slot_count      <= '0;
                packer.pending_eoe     <= 1'b0;
                packer.pending_eoe_ts  <= 64'h0000_0000_0000_0000;
            end else if (zero_byte_eoe) begin
                packer.pending_eoe    <= 1'b0;
                packer.pending_eoe_ts <= 64'h0000_0000_0000_0000;
            end
        end
    end

    generate
        if (DEBUG_LEVEL >= 1) begin : g_debug1
            assign dbg1_slot_index  = 4'(packer.slot_count);
            assign dbg1_pending_eoe = packer.pending_eoe;
        end else begin : g_no_debug1
            assign dbg1_slot_index  = 4'h0;
            assign dbg1_pending_eoe = 1'b0;
        end
    endgenerate

endmodule

`default_nettype wire
