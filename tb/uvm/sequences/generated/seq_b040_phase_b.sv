`ifndef SEQ_B040_PHASE_B_SV
`define SEQ_B040_PHASE_B_SV

class seq_b040_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_b040_phase_b)

  function new(string name = "seq_b040_phase_b");
    super.new(name);
    case_id = "B040";
  endfunction
endclass

`endif
