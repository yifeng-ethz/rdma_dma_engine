`ifndef SEQ_E033_PHASE_B_SV
`define SEQ_E033_PHASE_B_SV

class seq_e033_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_e033_phase_b)

  function new(string name = "seq_e033_phase_b");
    super.new(name);
    case_id = "E033";
  endfunction
endclass

`endif
