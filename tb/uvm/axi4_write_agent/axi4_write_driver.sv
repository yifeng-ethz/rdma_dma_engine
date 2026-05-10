`ifndef AXI4_WRITE_DRIVER_SV
`define AXI4_WRITE_DRIVER_SV

class axi4_write_driver extends uvm_component;
  `uvm_component_utils(axi4_write_driver)

  axi4_write_cfg cfg;
  virtual rdma_dma_engine_if vif;
  int unsigned pending_b_countdown;
  bit pending_b;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    pending_b_countdown = 0;
    pending_b = 1'b0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi4_write_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("AXI_WR_DRV", "Missing axi4_write_cfg")
    vif = cfg.vif;
    if (vif == null)
      `uvm_fatal("AXI_WR_DRV", "axi4_write_cfg.vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(negedge vif.clk);
      if (vif.reset_n !== 1'b1) begin
        vif.m_axi_awready <= 1'b0;
        vif.m_axi_wready <= 1'b0;
        vif.m_axi_bvalid <= 1'b0;
        vif.m_axi_bresp <= AXI_RESP_OKAY;
        vif.m_axi_bid <= 4'h0;
        pending_b = 1'b0;
        pending_b_countdown = 0;
        continue;
      end

      vif.m_axi_awready <= (cfg.awready_lag == 0);
      vif.m_axi_wready <= (cfg.wready_lag == 0);

      if (vif.m_axi_wvalid && vif.m_axi_wready && vif.m_axi_wlast) begin
        pending_b = 1'b1;
        pending_b_countdown = cfg.bvalid_lag;
      end

      if (vif.m_axi_bvalid && vif.m_axi_bready) begin
        vif.m_axi_bvalid <= 1'b0;
      end else if (pending_b) begin
        if (pending_b_countdown == 0) begin
          vif.m_axi_bid <= 4'h0;
          vif.m_axi_bresp <= cfg.bresp;
          vif.m_axi_bvalid <= 1'b1;
          pending_b = 1'b0;
        end else begin
          pending_b_countdown--;
          vif.m_axi_bvalid <= 1'b0;
        end
      end
    end
  endtask
endclass

`endif

