`ifndef SEQ_E061_PHASE_B_SV
`define SEQ_E061_PHASE_B_SV

class seq_e061_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_e061_phase_b)

  function new(string name = "seq_e061_phase_b");
    super.new(name);
    case_id = "E061";
  endfunction
endclass

`endif
