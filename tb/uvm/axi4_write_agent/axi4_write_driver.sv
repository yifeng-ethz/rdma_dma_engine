`ifndef AXI4_WRITE_DRIVER_SV
`define AXI4_WRITE_DRIVER_SV

class axi4_write_driver extends uvm_component;
  `uvm_component_utils(axi4_write_driver)

  axi4_write_cfg cfg;
  virtual rdma_dma_engine_if vif;
  int unsigned awready_countdown;
  int unsigned wready_countdown;
  int unsigned pending_b_countdown;
  bit aw_waiting;
  bit w_waiting;
  bit scheduled_wlast;
  bit b_clear_pending;
  bit pending_b;
  int unsigned b_response_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    awready_countdown = 0;
    wready_countdown = 0;
    pending_b_countdown = 0;
    aw_waiting = 1'b0;
    w_waiting = 1'b0;
    scheduled_wlast = 1'b0;
    b_clear_pending = 1'b0;
    pending_b = 1'b0;
    b_response_count = 0;
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
        aw_waiting = 1'b0;
        w_waiting = 1'b0;
        scheduled_wlast = 1'b0;
        b_clear_pending = 1'b0;
        awready_countdown = 0;
        wready_countdown = 0;
        pending_b = 1'b0;
        pending_b_countdown = 0;
        b_response_count = 0;
        continue;
      end

      scheduled_wlast = 1'b0;

      if (vif.m_axi_awvalid && !aw_waiting && !vif.m_axi_awready) begin
        aw_waiting = 1'b1;
        awready_countdown = cfg.awready_lag;
      end

      if (aw_waiting) begin
        if (awready_countdown == 0) begin
          vif.m_axi_awready <= 1'b1;
          if (vif.m_axi_awvalid)
            aw_waiting = 1'b0;
        end else begin
          awready_countdown--;
          vif.m_axi_awready <= 1'b0;
        end
      end else begin
        vif.m_axi_awready <= 1'b0;
      end

      if (cfg.wready_lag == 0) begin
        vif.m_axi_wready <= vif.m_axi_wvalid;
        if (vif.m_axi_wvalid && vif.m_axi_wlast)
          scheduled_wlast = 1'b1;
        w_waiting = 1'b0;
        wready_countdown = 0;
      end else begin
        if (vif.m_axi_wvalid && !w_waiting && !vif.m_axi_wready) begin
          w_waiting = 1'b1;
          wready_countdown = cfg.wready_lag;
        end

        if (w_waiting) begin
          if (wready_countdown == 0) begin
            vif.m_axi_wready <= 1'b1;
            if (vif.m_axi_wvalid && vif.m_axi_wlast)
              scheduled_wlast = 1'b1;
            if (vif.m_axi_wvalid)
              w_waiting = 1'b0;
          end else begin
            wready_countdown--;
            vif.m_axi_wready <= 1'b0;
          end
        end else begin
          vif.m_axi_wready <= 1'b0;
        end
      end

      if ((vif.m_axi_wvalid && vif.m_axi_wready && vif.m_axi_wlast) || scheduled_wlast) begin
        pending_b = 1'b1;
        pending_b_countdown = cfg.bvalid_lag;
      end

      if (b_clear_pending) begin
        vif.m_axi_bvalid <= 1'b0;
        b_clear_pending = 1'b0;
      end else if (vif.m_axi_bvalid && vif.m_axi_bready) begin
        b_clear_pending = 1'b1;
      end else if (pending_b) begin
        if (pending_b_countdown == 0) begin
          vif.m_axi_bid <= 4'h0;
          if ((cfg.bresp_error_index >= 0) &&
              (int'(b_response_count) == cfg.bresp_error_index)) begin
            vif.m_axi_bresp <= cfg.bresp;
          end else if (cfg.bresp_error_index >= 0) begin
            vif.m_axi_bresp <= cfg.bresp_default;
          end else begin
            vif.m_axi_bresp <= cfg.bresp;
          end
          b_response_count++;
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
