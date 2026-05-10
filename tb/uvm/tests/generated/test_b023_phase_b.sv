`ifndef TEST_B023_PHASE_B_SV
`define TEST_B023_PHASE_B_SV

class test_b023_phase_b extends rdma_dma_engine_phase_b_test;
  `uvm_component_utils(test_b023_phase_b)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string default_case_id();
    return "B023";
  endfunction

  function rdma_dma_phase_b_case_sequence create_case_sequence();
    seq_b023_phase_b seq;
    seq = seq_b023_phase_b::type_id::create("seq_b023_phase_b");
    return seq;
  endfunction
endclass

`endif
