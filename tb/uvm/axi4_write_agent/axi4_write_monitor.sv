`ifndef AXI4_WRITE_MONITOR_SV
`define AXI4_WRITE_MONITOR_SV

class axi4_write_monitor extends uvm_monitor;
  `uvm_component_utils(axi4_write_monitor)

  axi4_write_cfg cfg;
  virtual rdma_dma_engine_if vif;
  uvm_analysis_port #(axi4_write_item) ap;
  longint unsigned cycle_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cycle_count = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(axi4_write_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("AXI_WR_MON", "Missing axi4_write_cfg")
    vif = cfg.vif;
    if (vif == null)
      `uvm_fatal("AXI_WR_MON", "axi4_write_cfg.vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    axi4_write_item item;
    forever begin
      @(posedge vif.clk);
      cycle_count++;
      if (vif.reset_n !== 1'b1)
        continue;
      if (vif.m_axi_awvalid && vif.m_axi_awready) begin
        item = axi4_write_item::type_id::create("aw_item");
        item.is_aw = 1'b1;
        item.id = vif.m_axi_awid;
        item.addr = vif.m_axi_awaddr;
        item.len = vif.m_axi_awlen;
        item.size = vif.m_axi_awsize;
        item.burst = vif.m_axi_awburst;
        item.cycle = cycle_count;
        ap.write(item);
      end
      if (vif.m_axi_wvalid && vif.m_axi_wready) begin
        item = axi4_write_item::type_id::create("w_item");
        item.is_w = 1'b1;
        item.data = vif.m_axi_wdata;
        item.strb = vif.m_axi_wstrb;
        item.last = vif.m_axi_wlast;
        item.cycle = cycle_count;
        ap.write(item);
      end
      if (vif.m_axi_bvalid && vif.m_axi_bready) begin
        item = axi4_write_item::type_id::create("b_item");
        item.is_b = 1'b1;
        item.id = vif.m_axi_bid;
        item.resp = vif.m_axi_bresp;
        item.cycle = cycle_count;
        ap.write(item);
      end
    end
  endtask
endclass

`endif

