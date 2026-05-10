`ifndef SEQ_P037_PHASE_B_SV
`define SEQ_P037_PHASE_B_SV

class seq_p037_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_p037_phase_b)

  function new(string name = "seq_p037_phase_b");
    super.new(name);
    case_id = "P037";
  endfunction
endclass

`endif
