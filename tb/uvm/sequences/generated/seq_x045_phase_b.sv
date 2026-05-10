`ifndef SEQ_X045_PHASE_B_SV
`define SEQ_X045_PHASE_B_SV

class seq_x045_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_x045_phase_b)

  function new(string name = "seq_x045_phase_b");
    super.new(name);
    case_id = "X045";
  endfunction
endclass

`endif
