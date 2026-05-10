`ifndef SEQ_B002_PHASE_B_SV
`define SEQ_B002_PHASE_B_SV

class seq_b002_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_b002_phase_b)

  function new(string name = "seq_b002_phase_b");
    super.new(name);
    case_id = "B002";
  endfunction
endclass

`endif
