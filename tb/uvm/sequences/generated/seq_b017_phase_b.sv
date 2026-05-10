`ifndef SEQ_B017_PHASE_B_SV
`define SEQ_B017_PHASE_B_SV

class seq_b017_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_b017_phase_b)

  function new(string name = "seq_b017_phase_b");
    super.new(name);
    case_id = "B017";
  endfunction
endclass

`endif
