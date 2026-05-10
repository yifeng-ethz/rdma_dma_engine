`ifndef SEQ_B076_PHASE_B_SV
`define SEQ_B076_PHASE_B_SV

class seq_b076_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_b076_phase_b)

  function new(string name = "seq_b076_phase_b");
    super.new(name);
    case_id = "B076";
  endfunction
endclass

`endif
