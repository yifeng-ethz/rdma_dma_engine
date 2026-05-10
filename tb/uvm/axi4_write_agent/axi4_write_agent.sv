`ifndef AXI4_WRITE_AGENT_SV
`define AXI4_WRITE_AGENT_SV

class axi4_write_agent extends uvm_agent;
  `uvm_component_utils(axi4_write_agent)

  axi4_write_cfg cfg;
  axi4_write_driver driver;
  axi4_write_monitor monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi4_write_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("AXI_WR_AGENT", "Missing axi4_write_cfg")
    monitor = axi4_write_monitor::type_id::create("monitor", this);
    if (is_active == UVM_ACTIVE)
      driver = axi4_write_driver::type_id::create("driver", this);
  endfunction
endclass

`endif

