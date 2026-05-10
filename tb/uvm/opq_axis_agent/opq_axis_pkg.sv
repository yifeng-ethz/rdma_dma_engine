`ifndef OPQ_AXIS_PKG_SV
`define OPQ_AXIS_PKG_SV

package opq_axis_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class opq_axis_item extends uvm_sequence_item;
    `uvm_object_utils(opq_axis_item)

    rand bit [31:0] data;
    rand bit [3:0]  datak;
    rand bit        sop;
    rand bit        eoe;
    rand bit [3:0]  lane;
    rand bit [31:0] hit_id;
    rand bit [63:0] source_ts;
    rand bit [31:0] sequence_no;
    int unsigned    idle_after;
    longint unsigned cycle;

    function new(string name = "opq_axis_item");
      super.new(name);
      data = '0;
      datak = '0;
      sop = 1'b0;
      eoe = 1'b0;
      lane = '0;
      hit_id = '0;
      source_ts = '0;
      sequence_no = '0;
      idle_after = 0;
      cycle = 0;
    endfunction
  endclass

  class opq_axis_cfg extends uvm_object;
    `uvm_object_utils(opq_axis_cfg)

    virtual rdma_dma_engine_if vif;
    int unsigned debug_level;
    bit drive_sidecar;

    function new(string name = "opq_axis_cfg");
      super.new(name);
      debug_level = 1;
      drive_sidecar = 1'b0;
    endfunction
  endclass

  class opq_axis_sequencer extends uvm_sequencer #(opq_axis_item);
    `uvm_component_utils(opq_axis_sequencer)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  `include "opq_axis_driver.sv"
  `include "opq_axis_monitor.sv"
  `include "opq_axis_agent.sv"
endpackage

`endif

