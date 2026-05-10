`ifndef SEQ_E058_PHASE_B_SV
`define SEQ_E058_PHASE_B_SV

class seq_e058_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_e058_phase_b)

  function new(string name = "seq_e058_phase_b");
    super.new(name);
    case_id = "E058";
  endfunction
endclass

`endif
