`ifndef JOB_AGENT_SV
`define JOB_AGENT_SV

class job_agent extends uvm_agent;
  `uvm_component_utils(job_agent)

  job_cfg cfg;
  job_sequencer sequencer;
  job_driver driver;
  job_monitor monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(job_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("JOB_AGENT", "Missing job_cfg")
    monitor = job_monitor::type_id::create("monitor", this);
    if (is_active == UVM_ACTIVE) begin
      sequencer = job_sequencer::type_id::create("sequencer", this);
      driver = job_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (is_active == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass

`endif

