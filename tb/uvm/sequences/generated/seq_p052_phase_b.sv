`ifndef SEQ_P052_PHASE_B_SV
`define SEQ_P052_PHASE_B_SV

class seq_p052_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_p052_phase_b)

  function new(string name = "seq_p052_phase_b");
    super.new(name);
    case_id = "P052";
  endfunction
endclass

`endif
