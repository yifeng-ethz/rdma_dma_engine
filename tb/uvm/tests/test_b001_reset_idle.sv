`ifndef TEST_B001_RESET_IDLE_SV
`define TEST_B001_RESET_IDLE_SV

class test_b001_reset_idle extends rdma_dma_engine_base_test;
  `uvm_component_utils(test_b001_reset_idle)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function string default_case_id();
    return "B001";
  endfunction

  task run_case();
    wait_cycles(4);
    if (vif.m_axi_awvalid !== 1'b0)
      `uvm_error("B001", "m_axi_awvalid not idle after reset")
    if (vif.m_axi_wvalid !== 1'b0)
      `uvm_error("B001", "m_axi_wvalid not idle after reset")
    if (vif.m_axi_bready !== 1'b0)
      `uvm_error("B001", "m_axi_bready not idle after reset")
    if (vif.job_done !== 1'b0)
      `uvm_error("B001", "job_done asserted after reset")
    if (vif.cnt_input_w !== 32'h0 ||
        vif.cnt_bytes_written !== 32'h0 ||
        vif.cnt_halt !== 32'h0 ||
        vif.cnt_eoe_observed !== 32'h0) begin
      `uvm_error("B001", "sideband counters not zero after reset")
    end
    if (env.debug_level >= 1) begin
      if (vif.dbg1_writer_state !== 4'h0)
        `uvm_error("B001", "dbg1_writer_state is not WR_IDLE after reset")
      if (vif.dbg1_fifo_level !== 9'h0)
        `uvm_error("B001", "dbg1_fifo_level is not zero after reset")
      if (vif.dbg1_packer_slot_idx !== 4'h0)
        `uvm_error("B001", "dbg1_packer_slot_idx is not zero after reset")
    end
    if (env.debug_level >= 2) begin
      if (vif.dbg2_writer_meta_valid !== 1'b0)
        `uvm_error("B001", "dbg2 writer sidecar valid after reset")
    end
  endtask
endclass

`endif

