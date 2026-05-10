`ifndef RDMA_DMA_ENGINE_COVERAGE_SV
`define RDMA_DMA_ENGINE_COVERAGE_SV

class rdma_dma_engine_coverage extends uvm_subscriber #(job_pkg::job_item);
  `uvm_component_utils(rdma_dma_engine_coverage)

  bit saw_eoe;
  bit saw_seg0_only;
  bit [15:0] last_status;
  int unsigned done_count;

  covergroup cg_job_done;
    option.per_instance = 1;
    cp_eoe: coverpoint saw_eoe;
    cp_seg0_only: coverpoint saw_seg0_only;
    cp_status: coverpoint last_status {
      bins zero = {16'h0000};
      bins eoe = {[16'h0001:16'h0001]};
      bins seg0_only = {[16'h0010:16'h0010]};
      bins eoe_seg0_only = {[16'h0011:16'h0011]};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    saw_eoe = 1'b0;
    saw_seg0_only = 1'b0;
    last_status = 16'h0;
    done_count = 0;
    cg_job_done = new();
  endfunction

  function void write(job_pkg::job_item t);
    done_count++;
    last_status = t.status;
    saw_eoe = t.status[RDMA_DMA_ST_EOE];
    saw_seg0_only = t.status[RDMA_DMA_ST_SEG0_ONLY];
    cg_job_done.sample();
  endfunction
endclass

`endif

