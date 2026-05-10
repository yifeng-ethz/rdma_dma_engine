`ifndef SEQ_E023_PHASE_B_SV
`define SEQ_E023_PHASE_B_SV

class seq_e023_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_e023_phase_b)

  function new(string name = "seq_e023_phase_b");
    super.new(name);
    case_id = "E023";
  endfunction
endclass

`endif
