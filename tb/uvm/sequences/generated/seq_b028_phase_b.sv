`ifndef SEQ_B028_PHASE_B_SV
`define SEQ_B028_PHASE_B_SV

class seq_b028_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_b028_phase_b)

  function new(string name = "seq_b028_phase_b");
    super.new(name);
    case_id = "B028";
  endfunction
endclass

`endif
