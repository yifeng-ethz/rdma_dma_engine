`ifndef TEST_X086_PHASE_B_SV
`define TEST_X086_PHASE_B_SV

class test_x086_phase_b extends rdma_dma_engine_phase_b_test;
  `uvm_component_utils(test_x086_phase_b)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string default_case_id();
    return "X086";
  endfunction

  function rdma_dma_phase_b_case_sequence create_case_sequence();
    seq_x086_phase_b seq;
    seq = seq_x086_phase_b::type_id::create("seq_x086_phase_b");
    return seq;
  endfunction
endclass

`endif
