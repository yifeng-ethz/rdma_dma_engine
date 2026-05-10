`ifndef SEQ_P120_PHASE_B_SV
`define SEQ_P120_PHASE_B_SV

class seq_p120_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_p120_phase_b)

  function new(string name = "seq_p120_phase_b");
    super.new(name);
    case_id = "P120";
  endfunction
endclass

`endif
