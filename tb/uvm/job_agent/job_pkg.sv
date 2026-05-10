`ifndef JOB_PKG_SV
`define JOB_PKG_SV

package job_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class job_item extends uvm_sequence_item;
    `uvm_object_utils(job_item)

    rand bit [63:0] seg0_addr;
    rand bit [63:0] seg0_span;
    rand bit [63:0] seg1_addr;
    rand bit [63:0] seg1_span;
    rand bit [15:0] sqe_id;
    rand bit [15:0] opcode;
    bit done_observed;
    bit [63:0] bytes_written_total;
    bit [31:0] seg0_bytes_written;
    bit [31:0] seg1_bytes_written;
    bit [15:0] status;
    bit [15:0] sqe_id_echo;
    bit [31:0] event_count;
    bit [63:0] first_event_ts;
    bit [63:0] last_event_ts;
    longint unsigned cycle;

    function new(string name = "job_item");
      super.new(name);
      seg0_addr = 64'h0010_0000;
      seg0_span = 64'h0000_1000;
      seg1_addr = 64'h0;
      seg1_span = 64'h0;
      sqe_id = 16'h0;
      opcode = 16'h0001;
      done_observed = 1'b0;
      bytes_written_total = '0;
      seg0_bytes_written = '0;
      seg1_bytes_written = '0;
      status = '0;
      sqe_id_echo = '0;
      event_count = '0;
      first_event_ts = '0;
      last_event_ts = '0;
      cycle = 0;
    endfunction
  endclass

  class job_cfg extends uvm_object;
    `uvm_object_utils(job_cfg)

    virtual rdma_dma_engine_if vif;

    function new(string name = "job_cfg");
      super.new(name);
    endfunction
  endclass

  class job_sequencer extends uvm_sequencer #(job_item);
    `uvm_component_utils(job_sequencer)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  `include "job_driver.sv"
  `include "job_monitor.sv"
  `include "job_agent.sv"
endpackage

`endif

