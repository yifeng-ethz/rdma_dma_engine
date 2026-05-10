`ifndef SEQ_E021_PHASE_B_SV
`define SEQ_E021_PHASE_B_SV

class seq_e021_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_e021_phase_b)

  function new(string name = "seq_e021_phase_b");
    super.new(name);
    case_id = "E021";
  endfunction
endclass

`endif
