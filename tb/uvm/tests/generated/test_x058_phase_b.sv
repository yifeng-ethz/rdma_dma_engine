`ifndef TEST_X058_PHASE_B_SV
`define TEST_X058_PHASE_B_SV

class test_x058_phase_b extends rdma_dma_engine_phase_b_test;
  `uvm_component_utils(test_x058_phase_b)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string default_case_id();
    return "X058";
  endfunction

  function rdma_dma_phase_b_case_sequence create_case_sequence();
    seq_x058_phase_b seq;
    seq = seq_x058_phase_b::type_id::create("seq_x058_phase_b");
    return seq;
  endfunction
endclass

`endif
