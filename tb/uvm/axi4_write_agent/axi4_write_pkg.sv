`ifndef AXI4_WRITE_PKG_SV
`define AXI4_WRITE_PKG_SV

package axi4_write_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam bit [1:0] AXI_RESP_OKAY = 2'b00;
  localparam bit [1:0] AXI_RESP_SLVERR = 2'b10;

  class axi4_write_item extends uvm_sequence_item;
    `uvm_object_utils(axi4_write_item)

    bit is_aw;
    bit is_w;
    bit is_b;
    bit [3:0] id;
    bit [63:0] addr;
    bit [7:0] len;
    bit [2:0] size;
    bit [1:0] burst;
    bit [255:0] data;
    bit [31:0] strb;
    bit last;
    bit [1:0] resp;
    longint unsigned cycle;

    function new(string name = "axi4_write_item");
      super.new(name);
      is_aw = 1'b0;
      is_w = 1'b0;
      is_b = 1'b0;
      id = '0;
      addr = '0;
      len = '0;
      size = '0;
      burst = '0;
      data = '0;
      strb = '0;
      last = 1'b0;
      resp = AXI_RESP_OKAY;
      cycle = 0;
    endfunction
  endclass

  class axi4_write_cfg extends uvm_object;
    `uvm_object_utils(axi4_write_cfg)

    virtual rdma_dma_engine_if vif;
    int unsigned awready_lag;
    int unsigned wready_lag;
    int unsigned bvalid_lag;
    bit [1:0] bresp;
    int signed bresp_error_index;
    bit [1:0] bresp_default;

    function new(string name = "axi4_write_cfg");
      super.new(name);
      awready_lag = 0;
      wready_lag = 0;
      bvalid_lag = 1;
      bresp = AXI_RESP_OKAY;
      bresp_error_index = -1;
      bresp_default = AXI_RESP_OKAY;
    endfunction
  endclass

  `include "axi4_write_driver.sv"
  `include "axi4_write_monitor.sv"
  `include "axi4_write_agent.sv"
endpackage

`endif
