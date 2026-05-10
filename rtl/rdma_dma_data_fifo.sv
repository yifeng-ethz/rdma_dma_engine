// File name: rdma_dma_data_fifo.sv
// Author  : Yifeng Wang (yifenwan@phys.ethz.ch)
// Version : 26.1.0
// Date    : 20260510
// Change  : implement 256-bit DMA data FIFO with EOE sidebands

`default_nettype none

module rdma_dma_data_fifo #(
    parameter int unsigned DATA_W               = 256,
    parameter int unsigned DEPTH                = 256,
    parameter int unsigned ALMOST_FULL_THRESHOLD = 192,
    parameter int unsigned DBG2_META_W          = 136,
    parameter int unsigned DBG2_SLOTS           = 8,
    parameter int unsigned DEBUG_LEVEL          = 0
) (
    input  wire logic                            clk,
    input  wire logic                            reset_n,
    input  wire logic                            flush,

    input  wire logic [DATA_W-1:0]               write_data,
    input  wire logic                            write_valid,
    output logic                                 write_ready,
    input  wire logic                            write_last_in_event,
    input  wire logic [5:0]                      write_bytes_in_word,
    input  wire logic [63:0]                     write_event_ts,
    input  wire logic [DBG2_SLOTS*DBG2_META_W-1:0] write_dbg2_meta,
    input  wire logic [DBG2_SLOTS-1:0]           write_dbg2_valid_mask,

    output logic [DATA_W-1:0]                    read_data,
    output logic                                 read_valid,
    input  wire logic                            read_ready,
    output logic                                 read_last_in_event,
    output logic [5:0]                           read_bytes_in_word,
    output logic [63:0]                          read_event_ts,
    output logic [DBG2_SLOTS*DBG2_META_W-1:0]    read_dbg2_meta,
    output logic [DBG2_SLOTS-1:0]                read_dbg2_valid_mask,

    output logic [$clog2(DEPTH+1)-1:0]           fifo_level,
    output logic                                 fifo_almost_full,
    output logic                                 fifo_empty,
    output logic                                 fifo_full
);

    localparam int unsigned PTR_W_CONST   = $clog2(DEPTH);
    localparam int unsigned LEVEL_W_CONST = $clog2(DEPTH + 1);
    localparam int unsigned ENTRY_W_CONST = DATA_W + 1 + 6 + 64;
    localparam logic [LEVEL_W_CONST-1:0] DEPTH_LEVEL_CONST = DEPTH;
    localparam logic [LEVEL_W_CONST-1:0] ALMOST_FULL_LEVEL_CONST =
        ALMOST_FULL_THRESHOLD;

    typedef struct packed {
        logic [DATA_W-1:0] data;
        logic              last_in_event;
        logic [5:0]        bytes_in_word;
        logic [63:0]       event_ts;
    } fifo_entry_t;

    localparam fifo_entry_t FIFO_ENTRY_RESET_CONST = '{
        data          : '0,
        last_in_event : 1'b0,
        bytes_in_word : 6'h00,
        event_ts      : 64'h0000_0000_0000_0000
    };

    (* ramstyle = "M20K" *) logic [ENTRY_W_CONST-1:0] entry_mem [0:DEPTH-1];

    fifo_entry_t output_entry;
    logic [PTR_W_CONST-1:0]   write_ptr;
    logic [PTR_W_CONST-1:0]   read_ptr;
    logic [LEVEL_W_CONST-1:0] stored_level;
    logic                     output_valid;
    logic                     write_fire;
    logic                     read_fire;
    logic                     load_output;
    logic [LEVEL_W_CONST-1:0] total_level;

    assign write_fire       = write_valid && write_ready;
    assign read_fire        = output_valid && read_ready;
    assign load_output      = !output_valid || read_fire;
    assign total_level      = stored_level + {{(LEVEL_W_CONST-1){1'b0}}, output_valid};
    assign write_ready      = (total_level < DEPTH_LEVEL_CONST);
    assign fifo_level       = total_level;
    assign fifo_almost_full = (total_level >= ALMOST_FULL_LEVEL_CONST);
    assign fifo_empty       = (total_level == '0);
    assign fifo_full        = (total_level == DEPTH_LEVEL_CONST);
    assign read_valid       = output_valid;
    assign read_data        = output_entry.data;
    assign read_last_in_event = output_entry.last_in_event;
    assign read_bytes_in_word = output_entry.bytes_in_word;
    assign read_event_ts      = output_entry.event_ts;

    always_ff @(posedge clk or negedge reset_n) begin : fifo_storage
        if (!reset_n) begin
            write_ptr     <= '0;
            read_ptr      <= '0;
            stored_level  <= '0;
            output_valid  <= 1'b0;
            output_entry  <= FIFO_ENTRY_RESET_CONST;
        end else if (flush) begin
            write_ptr     <= '0;
            read_ptr      <= '0;
            stored_level  <= '0;
            output_valid  <= 1'b0;
            output_entry  <= FIFO_ENTRY_RESET_CONST;
        end else begin
            if (write_fire) begin
                entry_mem[write_ptr] <= {
                    write_data,
                    write_last_in_event,
                    write_bytes_in_word,
                    write_event_ts
                };
                write_ptr <= write_ptr + {{(PTR_W_CONST-1){1'b0}}, 1'b1};
            end

            if (load_output && (stored_level != '0)) begin
                output_entry <= entry_mem[read_ptr];
                read_ptr     <= read_ptr + {{(PTR_W_CONST-1){1'b0}}, 1'b1};
                output_valid <= 1'b1;
            end else if (read_fire) begin
                output_valid <= 1'b0;
                output_entry <= FIFO_ENTRY_RESET_CONST;
            end

            unique case ({write_fire, (load_output && (stored_level != '0))})
                2'b10: stored_level <= stored_level + {{(LEVEL_W_CONST-1){1'b0}}, 1'b1};
                2'b01: stored_level <= stored_level - {{(LEVEL_W_CONST-1){1'b0}}, 1'b1};
                default: stored_level <= stored_level;
            endcase
        end
    end

    generate
        if (DEBUG_LEVEL >= 2) begin : g_debug2_fifo
            (* ramstyle = "M20K" *)
            logic [DBG2_SLOTS*DBG2_META_W-1:0] dbg2_meta_mem [0:DEPTH-1];
            logic [DBG2_SLOTS*DBG2_META_W-1:0] dbg2_meta_output;
            logic [DBG2_SLOTS-1:0]             dbg2_mask_mem [0:DEPTH-1];
            logic [DBG2_SLOTS-1:0]             dbg2_mask_output;

            always_ff @(posedge clk or negedge reset_n) begin : dbg2_fifo_storage
                if (!reset_n) begin
                    dbg2_meta_output <= '0;
                    dbg2_mask_output <= '0;
                end else if (flush) begin
                    dbg2_meta_output <= '0;
                    dbg2_mask_output <= '0;
                end else begin
                    if (write_fire) begin
                        dbg2_meta_mem[write_ptr] <= write_dbg2_meta;
                        dbg2_mask_mem[write_ptr] <= write_dbg2_valid_mask;
                    end

                    if (load_output && (stored_level != '0)) begin
                        dbg2_meta_output <= dbg2_meta_mem[read_ptr];
                        dbg2_mask_output <= dbg2_mask_mem[read_ptr];
                    end else if (read_fire) begin
                        dbg2_meta_output <= '0;
                        dbg2_mask_output <= '0;
                    end
                end
            end

            assign read_dbg2_meta       = dbg2_meta_output;
            assign read_dbg2_valid_mask = dbg2_mask_output;
        end else begin : g_no_debug2_fifo
            assign read_dbg2_meta       = '0;
            assign read_dbg2_valid_mask = '0;
        end
    endgenerate

endmodule

`default_nettype wire
