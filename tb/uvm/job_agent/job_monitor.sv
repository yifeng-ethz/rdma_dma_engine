`ifndef JOB_MONITOR_SV
`define JOB_MONITOR_SV

class job_monitor extends uvm_monitor;
  `uvm_component_utils(job_monitor)

  job_cfg cfg;
  virtual rdma_dma_engine_if vif;
  uvm_analysis_port #(job_item) ap;
  longint unsigned cycle_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cycle_count = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(job_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("JOB_MON", "Missing job_cfg")
    vif = cfg.vif;
    if (vif == null)
      `uvm_fatal("JOB_MON", "job_cfg.vif is null")
  endfunction

  task run_phase(uvm_phase phase);
    job_item item;
    forever begin
      @(posedge vif.clk);
      cycle_count++;
      if (vif.reset_n !== 1'b1)
        continue;
      if (vif.job_done) begin
        item = job_item::type_id::create("job_done_item");
        item.done_observed = 1'b1;
        item.bytes_written_total = vif.job_bytes_written_total;
        item.seg0_bytes_written = vif.job_seg0_bytes_written;
        item.seg1_bytes_written = vif.job_seg1_bytes_written;
        item.status = vif.job_status;
        item.rqe_id_echo = vif.job_rqe_id_echo;
        item.event_count = vif.job_event_count;
        item.first_event_ts = vif.job_first_event_ts;
        item.last_event_ts = vif.job_last_event_ts;
        item.cycle = cycle_count;
        ap.write(item);
      end
    end
  endtask
endclass

`endif

