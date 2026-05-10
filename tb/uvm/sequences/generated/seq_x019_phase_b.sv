`ifndef SEQ_X019_PHASE_B_SV
`define SEQ_X019_PHASE_B_SV

class seq_x019_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_x019_phase_b)

  function new(string name = "seq_x019_phase_b");
    super.new(name);
    case_id = "X019";
  endfunction
endclass

`endif
