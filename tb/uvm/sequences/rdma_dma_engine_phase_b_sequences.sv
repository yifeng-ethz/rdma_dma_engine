`ifndef RDMA_DMA_ENGINE_PHASE_B_SEQUENCES_SV
`define RDMA_DMA_ENGINE_PHASE_B_SEQUENCES_SV

class rdma_dma_phase_b_case_sequence extends uvm_object;
  `uvm_object_utils(rdma_dma_phase_b_case_sequence)

  string case_id;

  function new(string name = "rdma_dma_phase_b_case_sequence");
    super.new(name);
    case_id = "BASE";
  endfunction

  task start(rdma_dma_engine_base_test test);
    test.run_phase_b_case(case_id);
  endtask
endclass

`include "sequences/generated/rdma_dma_phase_b_sequences.svh"

`endif
