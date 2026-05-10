`ifndef SEQ_E038_PHASE_B_SV
`define SEQ_E038_PHASE_B_SV

class seq_e038_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_e038_phase_b)

  function new(string name = "seq_e038_phase_b");
    super.new(name);
    case_id = "E038";
  endfunction
endclass

`endif
