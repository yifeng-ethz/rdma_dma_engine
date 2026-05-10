`ifndef OPQ_AXIS_AGENT_SV
`define OPQ_AXIS_AGENT_SV

class opq_axis_agent extends uvm_agent;
  `uvm_component_utils(opq_axis_agent)

  opq_axis_cfg cfg;
  opq_axis_sequencer sequencer;
  opq_axis_driver driver;
  opq_axis_monitor monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(opq_axis_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("OPQ_AGENT", "Missing opq_axis_cfg")
    monitor = opq_axis_monitor::type_id::create("monitor", this);
    if (is_active == UVM_ACTIVE) begin
      sequencer = opq_axis_sequencer::type_id::create("sequencer", this);
      driver = opq_axis_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (is_active == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass

`endif

