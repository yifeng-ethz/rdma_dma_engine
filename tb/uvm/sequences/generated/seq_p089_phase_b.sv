`ifndef SEQ_P089_PHASE_B_SV
`define SEQ_P089_PHASE_B_SV

class seq_p089_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_p089_phase_b)

  function new(string name = "seq_p089_phase_b");
    super.new(name);
    case_id = "P089";
  endfunction
endclass

`endif
