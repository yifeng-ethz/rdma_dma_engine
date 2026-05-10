`ifndef SEQ_E110_PHASE_B_SV
`define SEQ_E110_PHASE_B_SV

class seq_e110_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_e110_phase_b)

  function new(string name = "seq_e110_phase_b");
    super.new(name);
    case_id = "E110";
  endfunction
endclass

`endif
