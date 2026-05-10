`ifndef SEQ_X064_PHASE_B_SV
`define SEQ_X064_PHASE_B_SV

class seq_x064_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_x064_phase_b)

  function new(string name = "seq_x064_phase_b");
    super.new(name);
    case_id = "X064";
  endfunction
endclass

`endif
