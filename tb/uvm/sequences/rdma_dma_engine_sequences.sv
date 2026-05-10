`ifndef RDMA_DMA_ENGINE_SEQUENCES_SV
`define RDMA_DMA_ENGINE_SEQUENCES_SV

class opq_axis_event_sequence extends uvm_sequence #(opq_axis_pkg::opq_axis_item);
  `uvm_object_utils(opq_axis_event_sequence)

  int unsigned word_count;
  bit [31:0] data_base;
  bit [31:0] sequence_no;
  bit mark_eoe_on_last;
  int unsigned idle_after_each;

  function new(string name = "opq_axis_event_sequence");
    super.new(name);
    word_count = 8;
    data_base = 32'hd00d_0000;
    sequence_no = 32'd1;
    mark_eoe_on_last = 1'b1;
    idle_after_each = 0;
  endfunction

  task body();
    opq_axis_pkg::opq_axis_item item;
    for (int unsigned idx = 0; idx < word_count; idx++) begin
      item = opq_axis_pkg::opq_axis_item::type_id::create($sformatf("opq_word_%0d", idx));
      item.data = data_base;
      item.data[7:0] = data_base[7:0] + idx[7:0];
      item.datak = 4'h0;
      item.sop = (idx == 0);
      item.eoe = mark_eoe_on_last && (idx + 1 == word_count);
      item.lane = 4'h0;
      item.hit_id = idx + 1;
      item.source_ts = idx + 1;
      item.sequence_no = sequence_no;
      item.idle_after = idle_after_each;
      start_item(item);
      finish_item(item);
    end
  endtask
endclass

class job_single_segment_sequence extends uvm_sequence #(job_pkg::job_item);
  `uvm_object_utils(job_single_segment_sequence)

  bit [63:0] seg0_addr;
  bit [63:0] seg0_span;
  bit [63:0] seg1_addr;
  bit [63:0] seg1_span;
  bit [15:0] sqe_id;
  bit [15:0] opcode;

  function new(string name = "job_single_segment_sequence");
    super.new(name);
    seg0_addr = 64'h0000_0000_0010_0000;
    seg0_span = 64'h0000_0000_0000_1000;
    seg1_addr = 64'h0000_0000_0000_0000;
    seg1_span = 64'h0000_0000_0000_0000;
    sqe_id = 16'h00b2;
    opcode = 16'h0001;
  endfunction

  task body();
    job_pkg::job_item item;
    item = job_pkg::job_item::type_id::create("single_segment_job");
    item.seg0_addr = seg0_addr;
    item.seg0_span = seg0_span;
    item.seg1_addr = seg1_addr;
    item.seg1_span = seg1_span;
    item.sqe_id = sqe_id;
    item.opcode = opcode;
    start_item(item);
    finish_item(item);
  endtask
endclass

class rdma_dma_basic_smoke_sequence extends opq_axis_event_sequence;
  `uvm_object_utils(rdma_dma_basic_smoke_sequence)

  function new(string name = "rdma_dma_basic_smoke_sequence");
    super.new(name);
    word_count = 8;
    data_base = 32'hb002_0000;
  endfunction
endclass

class rdma_dma_edge_template_sequence extends opq_axis_event_sequence;
  `uvm_object_utils(rdma_dma_edge_template_sequence)

  function new(string name = "rdma_dma_edge_template_sequence");
    super.new(name);
    word_count = 1;
    data_base = 32'he001_0000;
  endfunction
endclass

class rdma_dma_prof_template_sequence extends opq_axis_event_sequence;
  `uvm_object_utils(rdma_dma_prof_template_sequence)

  function new(string name = "rdma_dma_prof_template_sequence");
    super.new(name);
    word_count = 64;
    data_base = 32'hf001_0000;
  endfunction
endclass

class rdma_dma_error_template_sequence extends opq_axis_event_sequence;
  `uvm_object_utils(rdma_dma_error_template_sequence)

  function new(string name = "rdma_dma_error_template_sequence");
    super.new(name);
    word_count = 0;
    data_base = 32'hbad0_0000;
  endfunction
endclass

`endif
