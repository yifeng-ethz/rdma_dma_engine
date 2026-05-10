`ifndef TEST_B102_PHASE_B_SV
`define TEST_B102_PHASE_B_SV

class test_b102_phase_b extends rdma_dma_engine_phase_b_test;
  `uvm_component_utils(test_b102_phase_b)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string default_case_id();
    return "B102";
  endfunction

  function rdma_dma_phase_b_case_sequence create_case_sequence();
    seq_b102_phase_b seq;
    seq = seq_b102_phase_b::type_id::create("seq_b102_phase_b");
    return seq;
  endfunction
endclass

`endif
