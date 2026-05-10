`ifndef SEQ_P127_PHASE_B_SV
`define SEQ_P127_PHASE_B_SV

class seq_p127_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_p127_phase_b)

  function new(string name = "seq_p127_phase_b");
    super.new(name);
    case_id = "P127";
  endfunction
endclass

`endif
