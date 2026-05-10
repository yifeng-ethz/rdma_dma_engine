`ifndef SEQ_X024_PHASE_B_SV
`define SEQ_X024_PHASE_B_SV

class seq_x024_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_x024_phase_b)

  function new(string name = "seq_x024_phase_b");
    super.new(name);
    case_id = "X024";
  endfunction
endclass

`endif
