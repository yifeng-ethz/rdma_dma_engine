`ifndef RDMA_DMA_ENGINE_STUB_SV
`define RDMA_DMA_ENGINE_STUB_SV

module rdma_dma_engine #(
  parameter int unsigned DMA_DATA_W = 256,
  parameter int unsigned MAX_BURST_BEATS = 16,
  parameter int unsigned SEG_QUANTUM_BYTES = 4096,
  parameter int unsigned DEBUG_LEVEL = 1
) (
  input  logic clk,
  input  logic reset_n,
  input  logic [35:0] s_axis_opq_tdata,
  input  logic s_axis_opq_tvalid,
  output logic s_axis_opq_tready,
  input  logic s_axis_opq_tlast,
  input  logic [1:0] s_axis_opq_tuser,
  input  logic job_req,
  input  logic [63:0] job_seg0_addr,
  input  logic [63:0] job_seg0_span,
  input  logic [63:0] job_seg1_addr,
  input  logic [63:0] job_seg1_span,
  input  logic [15:0] job_rqe_id,
  input  logic [15:0] job_opcode,
  output logic job_done,
  output logic [63:0] job_bytes_written_total,
  output logic [31:0] job_seg0_bytes_written,
  output logic [31:0] job_seg1_bytes_written,
  output logic [15:0] job_status,
  output logic [15:0] job_rqe_id_echo,
  output logic [31:0] job_event_count,
  output logic [63:0] job_first_event_ts,
  output logic [63:0] job_last_event_ts,
  output logic [3:0] m_axi_awid,
  output logic [63:0] m_axi_awaddr,
  output logic [7:0] m_axi_awlen,
  output logic [2:0] m_axi_awsize,
  output logic [1:0] m_axi_awburst,
  output logic m_axi_awvalid,
  input  logic m_axi_awready,
  output logic [DMA_DATA_W-1:0] m_axi_wdata,
  output logic [DMA_DATA_W/8-1:0] m_axi_wstrb,
  output logic m_axi_wlast,
  output logic m_axi_wvalid,
  input  logic m_axi_wready,
  input  logic [3:0] m_axi_bid,
  input  logic [1:0] m_axi_bresp,
  input  logic m_axi_bvalid,
  output logic m_axi_bready,
  output logic [31:0] cnt_input_w,
  output logic [31:0] cnt_bytes_written,
  output logic [31:0] cnt_halt,
  output logic [31:0] cnt_eoe_observed,
  input  logic clear_counters,
  output logic [8:0] dbg1_fifo_level,
  output logic dbg1_fifo_almost_full,
  output logic [3:0] dbg1_aw_inflight,
  output logic [7:0] dbg1_w_beats_remaining,
  output logic [3:0] dbg1_b_outstanding,
  output logic [3:0] dbg1_packer_slot,
  output logic dbg1_packer_pending_eoe,
  output logic [3:0] dbg1_writer_state,
  output logic dbg1_halt_pulse,
  input  logic dbg2_meta_valid,
  input  logic [135:0] dbg2_meta,
  output logic dbg2_writer_meta_valid,
  output logic [1087:0] dbg2_writer_meta,
  output logic [7:0] dbg2_writer_valid_mask
);
  localparam int unsigned DMA_BYTES = DMA_DATA_W / 8;
  localparam int unsigned OPQ_PER_DMA = DMA_DATA_W / 32;
  localparam int unsigned ST_EOE = 0;
  localparam int unsigned ST_FULL = 1;
  localparam int unsigned ST_SEG0_ONLY = 4;
  localparam int unsigned ST_ALIGN_ERR = 5;

  typedef enum logic [3:0] {
    WR_IDLE = 4'd0,
    WR_PROGRAM = 4'd1,
    WR_AW = 4'd2,
    WR_W = 4'd3,
    WR_B = 4'd4,
    WR_REPORT_DONE = 4'd5,
    WR_REPORT_ALIGN_ERR = 4'd6
  } writer_state_t;

  writer_state_t state_q;
  logic job_active_q;
  logic [63:0] cur_addr_q;
  logic [63:0] seg0_span_q;
  logic [63:0] seg1_span_q;
  logic [15:0] rqe_id_q;
  logic [15:0] status_q;
  logic [63:0] cycle_q;
  logic [3:0] slot_q;
  logic [DMA_DATA_W-1:0] pack_data_q;
  logic [OPQ_PER_DMA*4-1:0] pack_lane_q;
  logic [OPQ_PER_DMA*32-1:0] pack_hit_q;
  logic [OPQ_PER_DMA*64-1:0] pack_ts_q;
  logic [OPQ_PER_DMA*32-1:0] pack_seq_q;
  logic pending_valid_q;
  logic pending_eoe_q;
  logic [7:0] pending_slots_q;
  logic [DMA_DATA_W-1:0] pending_data_q;
  logic [DMA_BYTES-1:0] pending_wstrb_q;
  logic [OPQ_PER_DMA*4-1:0] pending_lane_q;
  logic [OPQ_PER_DMA*32-1:0] pending_hit_q;
  logic [OPQ_PER_DMA*64-1:0] pending_ts_q;
  logic [OPQ_PER_DMA*32-1:0] pending_seq_q;
  logic [31:0] current_job_bytes_q;
  logic [7:0] dbg2_writer_valid_mask_i;

  wire [3:0] dbg2_meta_lane = dbg2_meta[131:128];
  wire [31:0] dbg2_meta_hit_id = dbg2_meta[127:96];
  wire [63:0] dbg2_meta_source_ts = dbg2_meta[95:32];
  wire [31:0] dbg2_meta_sequence_no = dbg2_meta[31:0];

  function automatic logic align_error(
    input logic [63:0] seg0_addr,
    input logic [63:0] seg0_span,
    input logic [63:0] seg1_addr,
    input logic [63:0] seg1_span
  );
    logic seg0_bad;
    logic seg1_bad;
    begin
      seg0_bad = ((seg0_addr[11:0] != 12'h000) ||
                  (seg0_span == 64'h0) ||
                  (seg0_span[11:0] != 12'h000));
      seg1_bad = (seg1_span != 64'h0) &&
                 ((seg1_addr[11:0] != 12'h000) || (seg1_span[11:0] != 12'h000));
      align_error = seg0_bad || seg1_bad;
    end
  endfunction

  function automatic logic [DMA_BYTES-1:0] strobe_for_slots(input logic [7:0] slots);
    logic [DMA_BYTES-1:0] mask;
    begin
      mask = '0;
      for (int unsigned i = 0; i < DMA_BYTES; i++) begin
        if (i < (int'(slots) * 4))
          mask[i] = 1'b1;
      end
      strobe_for_slots = mask;
    end
  endfunction

  assign s_axis_opq_tready = 1'b1;
  assign m_axi_awid = 4'h0;
  assign m_axi_awaddr = cur_addr_q;
  assign m_axi_awlen = 8'h00;
  assign m_axi_awsize = 3'd5;
  assign m_axi_awburst = 2'b01;
  assign m_axi_awvalid = (state_q == WR_AW);
  assign m_axi_wdata = pending_data_q;
  assign m_axi_wstrb = pending_wstrb_q;
  assign m_axi_wlast = (state_q == WR_W);
  assign m_axi_wvalid = (state_q == WR_W);
  assign m_axi_bready = (state_q == WR_B);

  assign dbg1_fifo_level = (DEBUG_LEVEL >= 1) ? {8'h00, pending_valid_q} : 9'h000;
  assign dbg1_fifo_almost_full = 1'b0;
  assign dbg1_aw_inflight = (DEBUG_LEVEL >= 1 && state_q inside {WR_AW, WR_W, WR_B}) ? 4'd1 : 4'd0;
  assign dbg1_w_beats_remaining = (DEBUG_LEVEL >= 1 && state_q == WR_W) ? 8'd1 : 8'd0;
  assign dbg1_b_outstanding = (DEBUG_LEVEL >= 1 && state_q == WR_B) ? 4'd1 : 4'd0;
  assign dbg1_packer_slot = (DEBUG_LEVEL >= 1) ? slot_q : 4'h0;
  assign dbg1_packer_pending_eoe = (DEBUG_LEVEL >= 1) ? pending_eoe_q : 1'b0;
  assign dbg1_writer_state = (DEBUG_LEVEL >= 1) ? state_q : 4'h0;
  assign dbg1_halt_pulse = 1'b0;
  assign dbg2_writer_meta_valid = (DEBUG_LEVEL >= 2 && state_q == WR_W && m_axi_wready);
  assign dbg2_writer_valid_mask_i = (8'h01 << pending_slots_q) - 8'h01;
  assign dbg2_writer_valid_mask = (DEBUG_LEVEL >= 2) ? dbg2_writer_valid_mask_i : 8'h00;

  generate
    for (genvar dbg2_slot = 0; dbg2_slot < OPQ_PER_DMA; dbg2_slot++) begin : gen_stub_dbg2_pack
      assign dbg2_writer_meta[dbg2_slot*136 +: 136] = (DEBUG_LEVEL >= 2) ? {
        4'h0,
        pending_lane_q[dbg2_slot*4 +: 4],
        pending_hit_q[dbg2_slot*32 +: 32],
        pending_ts_q[dbg2_slot*64 +: 64],
        pending_seq_q[dbg2_slot*32 +: 32]
      } : 136'h0;
    end
  endgenerate

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q <= WR_IDLE;
      job_active_q <= 1'b0;
      cur_addr_q <= 64'h0;
      seg0_span_q <= 64'h0;
      seg1_span_q <= 64'h0;
      rqe_id_q <= 16'h0;
      status_q <= 16'h0;
      cycle_q <= 64'h0;
      slot_q <= 4'h0;
      pack_data_q <= '0;
      pack_lane_q <= '0;
      pack_hit_q <= '0;
      pack_ts_q <= '0;
      pack_seq_q <= '0;
      pending_valid_q <= 1'b0;
      pending_eoe_q <= 1'b0;
      pending_slots_q <= 8'h0;
      pending_data_q <= '0;
      pending_wstrb_q <= '0;
      pending_lane_q <= '0;
      pending_hit_q <= '0;
      pending_ts_q <= '0;
      pending_seq_q <= '0;
      current_job_bytes_q <= 32'h0;
      cnt_input_w <= 32'h0;
      cnt_bytes_written <= 32'h0;
      cnt_halt <= 32'h0;
      cnt_eoe_observed <= 32'h0;
      job_done <= 1'b0;
      job_bytes_written_total <= 64'h0;
      job_seg0_bytes_written <= 32'h0;
      job_seg1_bytes_written <= 32'h0;
      job_status <= 16'h0;
      job_rqe_id_echo <= 16'h0;
      job_event_count <= 32'h0;
      job_first_event_ts <= 64'h0;
      job_last_event_ts <= 64'h0;
    end else begin
      logic accept_opq;
      logic flush_now;
      logic [3:0] slot_next;
      logic [7:0] slots_now;
      logic [DMA_DATA_W-1:0] data_next;
      logic [OPQ_PER_DMA*4-1:0] lane_next;
      logic [OPQ_PER_DMA*32-1:0] hit_next;
      logic [OPQ_PER_DMA*64-1:0] ts_next;
      logic [OPQ_PER_DMA*32-1:0] seq_next;

      cycle_q <= cycle_q + 64'd1;
      job_done <= 1'b0;

      if (clear_counters) begin
        cnt_input_w <= 32'h0;
        cnt_bytes_written <= 32'h0;
        cnt_halt <= 32'h0;
        cnt_eoe_observed <= 32'h0;
      end

      accept_opq = s_axis_opq_tvalid && s_axis_opq_tready && job_active_q && !pending_valid_q;
      data_next = pack_data_q;
      lane_next = pack_lane_q;
      hit_next = pack_hit_q;
      ts_next = pack_ts_q;
      seq_next = pack_seq_q;
      slot_next = slot_q;
      flush_now = 1'b0;
      slots_now = 8'h0;

      if (accept_opq) begin
        data_next[DMA_DATA_W-1 - int'(slot_q)*32 -: 32] = s_axis_opq_tdata[31:0];
        lane_next[int'(slot_q)*4 +: 4] = dbg2_meta_valid ? dbg2_meta_lane : 4'h0;
        hit_next[int'(slot_q)*32 +: 32] = dbg2_meta_valid ? dbg2_meta_hit_id : 32'h0;
        ts_next[int'(slot_q)*64 +: 64] = dbg2_meta_valid ? dbg2_meta_source_ts : 64'h0;
        seq_next[int'(slot_q)*32 +: 32] = dbg2_meta_valid ? dbg2_meta_sequence_no : 32'h0;
        slot_next = slot_q + 4'd1;
        cnt_input_w <= cnt_input_w + 32'd1;
        if (s_axis_opq_tlast)
          cnt_eoe_observed <= cnt_eoe_observed + 32'd1;
        if (s_axis_opq_tlast && job_event_count == 32'h0)
          job_first_event_ts <= cycle_q;
        if (s_axis_opq_tlast)
          job_last_event_ts <= cycle_q;
        if (s_axis_opq_tlast)
          job_event_count <= job_event_count + 32'd1;
        flush_now = s_axis_opq_tlast || (slot_q == (OPQ_PER_DMA - 1));
        slots_now = {4'h0, slot_q} + 8'd1;
      end

      if (flush_now) begin
        pending_valid_q <= 1'b1;
        pending_eoe_q <= s_axis_opq_tlast;
        pending_slots_q <= slots_now;
        pending_data_q <= data_next;
        pending_wstrb_q <= strobe_for_slots(slots_now);
        pending_lane_q <= lane_next;
        pending_hit_q <= hit_next;
        pending_ts_q <= ts_next;
        pending_seq_q <= seq_next;
        pack_data_q <= '0;
        pack_lane_q <= '0;
        pack_hit_q <= '0;
        pack_ts_q <= '0;
        pack_seq_q <= '0;
        slot_q <= 4'h0;
      end else begin
        pack_data_q <= data_next;
        pack_lane_q <= lane_next;
        pack_hit_q <= hit_next;
        pack_ts_q <= ts_next;
        pack_seq_q <= seq_next;
        slot_q <= slot_next;
      end

      unique case (state_q)
        WR_IDLE: begin
          if (job_req) begin
            current_job_bytes_q <= 32'h0;
            job_bytes_written_total <= 64'h0;
            job_seg0_bytes_written <= 32'h0;
            job_seg1_bytes_written <= 32'h0;
            job_status <= 16'h0;
            job_rqe_id_echo <= job_rqe_id;
            job_event_count <= 32'h0;
            job_first_event_ts <= 64'h0;
            job_last_event_ts <= 64'h0;
            if (align_error(job_seg0_addr, job_seg0_span, job_seg1_addr, job_seg1_span)) begin
              job_status[ST_ALIGN_ERR] <= 1'b1;
              status_q <= 16'(1 << ST_ALIGN_ERR);
              rqe_id_q <= job_rqe_id;
              state_q <= WR_REPORT_ALIGN_ERR;
            end else begin
              job_active_q <= 1'b1;
              cur_addr_q <= job_seg0_addr;
              seg0_span_q <= job_seg0_span;
              seg1_span_q <= job_seg1_span;
              rqe_id_q <= job_rqe_id;
              status_q <= (job_seg1_span == 64'h0) ? 16'(1 << ST_SEG0_ONLY) : 16'h0;
              job_status <= (job_seg1_span == 64'h0) ? 16'(1 << ST_SEG0_ONLY) : 16'h0;
              state_q <= WR_PROGRAM;
            end
          end
        end
        WR_PROGRAM: begin
          if (pending_valid_q)
            state_q <= WR_AW;
        end
        WR_AW: begin
          if (m_axi_awready)
            state_q <= WR_W;
        end
        WR_W: begin
          if (m_axi_wready)
            state_q <= WR_B;
        end
        WR_B: begin
          if (m_axi_bvalid) begin
            logic [31:0] byte_count;
            byte_count = 32'(pending_slots_q) * 32'd4;
            current_job_bytes_q <= current_job_bytes_q + byte_count;
            cnt_bytes_written <= cnt_bytes_written + byte_count;
            job_bytes_written_total <= {32'h0, current_job_bytes_q + byte_count};
            job_seg0_bytes_written <= current_job_bytes_q + byte_count;
            job_seg1_bytes_written <= 32'h0;
            if (pending_eoe_q) begin
              status_q[ST_EOE] <= 1'b1;
              job_status <= status_q | 16'(1 << ST_EOE);
            end else begin
              job_status <= status_q;
            end
            pending_valid_q <= 1'b0;
            pending_eoe_q <= 1'b0;
            state_q <= WR_REPORT_DONE;
          end
        end
        WR_REPORT_DONE: begin
          job_done <= 1'b1;
          job_rqe_id_echo <= rqe_id_q;
          job_active_q <= 1'b0;
          state_q <= WR_IDLE;
        end
        WR_REPORT_ALIGN_ERR: begin
          job_done <= 1'b1;
          job_rqe_id_echo <= rqe_id_q;
          job_bytes_written_total <= 64'h0;
          job_seg0_bytes_written <= 32'h0;
          job_seg1_bytes_written <= 32'h0;
          job_active_q <= 1'b0;
          state_q <= WR_IDLE;
        end
        default: state_q <= WR_IDLE;
      endcase
    end
  end

  // TODO(RTL_PLAN.md section 5): confirm the production top-level name
  // for clear_counters once sibling RTL is committed.
  // TODO(RTL_PLAN.md section 3.11): keep the opaque 136-bit DEBUG=2 tuple
  // packing aligned with the sibling RTL and DV_HARNESS lineage contract.
endmodule

`endif
