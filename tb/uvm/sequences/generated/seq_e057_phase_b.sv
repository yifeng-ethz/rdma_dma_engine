`ifndef SEQ_E057_PHASE_B_SV
`define SEQ_E057_PHASE_B_SV

class seq_e057_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_e057_phase_b)

  function new(string name = "seq_e057_phase_b");
    super.new(name);
    case_id = "E057";
  endfunction
endclass

`endif
