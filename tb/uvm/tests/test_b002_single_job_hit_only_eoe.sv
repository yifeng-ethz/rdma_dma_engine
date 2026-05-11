`ifndef TEST_B002_SINGLE_JOB_HIT_ONLY_EOE_SV
`define TEST_B002_SINGLE_JOB_HIT_ONLY_EOE_SV

class test_b002_single_job_hit_only_eoe extends rdma_dma_engine_base_test;
  `uvm_component_utils(test_b002_single_job_hit_only_eoe)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string default_case_id();
    return "B002";
  endfunction

  task run_case();
    job_single_segment_sequence job_seq;
    rdma_dma_basic_smoke_sequence opq_seq;

    job_seq = job_single_segment_sequence::type_id::create("job_seq");
    opq_seq = rdma_dma_basic_smoke_sequence::type_id::create("opq_seq");
    job_seq.rqe_id = 16'hb002;
    job_seq.start(env.job_agent_h.sequencer);
    wait_cycles(2);
    opq_seq.start(env.opq_agent.sequencer);
    wait_for_done(256);

    if (vif.job_bytes_written_total !== 64'd32)
      `uvm_error("B002", $sformatf("bytes_written_total=%0d expected=32", vif.job_bytes_written_total))
    if (!vif.job_status[RDMA_DMA_ST_EOE])
      `uvm_error("B002", "EOE status bit was not set")
    if (!vif.job_status[RDMA_DMA_ST_SEG0_ONLY])
      `uvm_error("B002", "SEG0_ONLY status bit was not set")
    if (vif.job_rqe_id_echo !== 16'hb002)
      `uvm_error("B002", $sformatf("rqe_id_echo=0x%04h expected=0xb002", vif.job_rqe_id_echo))
  endtask
endclass

class test_b013_single_job_hit_only_eoe extends test_b002_single_job_hit_only_eoe;
  `uvm_component_utils(test_b013_single_job_hit_only_eoe)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string default_case_id();
    return "B013";
  endfunction
endclass

`endif

