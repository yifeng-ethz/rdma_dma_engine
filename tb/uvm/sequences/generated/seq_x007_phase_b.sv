`ifndef SEQ_X007_PHASE_B_SV
`define SEQ_X007_PHASE_B_SV

class seq_x007_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_x007_phase_b)

  function new(string name = "seq_x007_phase_b");
    super.new(name);
    case_id = "X007";
  endfunction
endclass

`endif
