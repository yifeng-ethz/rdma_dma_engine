`ifndef SEQ_B122_PHASE_B_SV
`define SEQ_B122_PHASE_B_SV

class seq_b122_phase_b extends rdma_dma_phase_b_case_sequence;
  `uvm_object_utils(seq_b122_phase_b)

  function new(string name = "seq_b122_phase_b");
    super.new(name);
    case_id = "B122";
  endfunction
endclass

`endif
