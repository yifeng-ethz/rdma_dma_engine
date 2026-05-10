`ifndef SEQ_X013_PHASE_B_SV
`define SEQ_X013_PHASE_B_SV

class seq_x013_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_x013_phase_b)

  function new(string name = "seq_x013_phase_b");
    super.new(name);
    case_id = "X013";
  endfunction
endclass

`endif
