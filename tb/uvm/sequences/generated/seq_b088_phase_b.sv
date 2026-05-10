`ifndef SEQ_B088_PHASE_B_SV
`define SEQ_B088_PHASE_B_SV

class seq_b088_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_b088_phase_b)

  function new(string name = "seq_b088_phase_b");
    super.new(name);
    case_id = "B088";
  endfunction
endclass

`endif
