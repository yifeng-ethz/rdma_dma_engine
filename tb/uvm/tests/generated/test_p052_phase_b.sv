`ifndef TEST_P052_PHASE_B_SV
`define TEST_P052_PHASE_B_SV

class test_p052_phase_b extends rdma_dma_engine_phase_b_test;
  `uvm_component_utils(test_p052_phase_b)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string default_case_id();
    return "P052";
  endfunction

  function rdma_dma_phase_b_case_sequence create_case_sequence();
    seq_p052_phase_b seq;
    seq = seq_p052_phase_b::type_id::create("seq_p052_phase_b");
    return seq;
  endfunction
endclass

`endif
