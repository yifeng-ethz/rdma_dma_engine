`ifndef TEST_P075_PHASE_B_SV
`define TEST_P075_PHASE_B_SV

class test_p075_phase_b extends rdma_dma_engine_phase_b_test;
  `uvm_component_utils(test_p075_phase_b)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string default_case_id();
    return "P075";
  endfunction

  function rdma_dma_phase_b_case_sequence create_case_sequence();
    seq_p075_phase_b seq;
    seq = seq_p075_phase_b::type_id::create("seq_p075_phase_b");
    return seq;
  endfunction
endclass

`endif
