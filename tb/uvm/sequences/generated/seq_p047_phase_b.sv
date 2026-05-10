`ifndef SEQ_P047_PHASE_B_SV
`define SEQ_P047_PHASE_B_SV

class seq_p047_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_p047_phase_b)

  function new(string name = "seq_p047_phase_b");
    super.new(name);
    case_id = "P047";
  endfunction
endclass

`endif
