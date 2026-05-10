`ifndef SEQ_P110_PHASE_B_SV
`define SEQ_P110_PHASE_B_SV

class seq_p110_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_p110_phase_b)

  function new(string name = "seq_p110_phase_b");
    super.new(name);
    case_id = "P110";
  endfunction
endclass

`endif
