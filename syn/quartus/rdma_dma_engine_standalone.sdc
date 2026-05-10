# Standalone timing signoff for rdma_dma_engine.
# Target: 250 MHz (4.000 ns) with 10% margin -> 275 MHz (3.636 ns).

create_clock -name clk -period 3.636 [get_ports {clk}]

set_false_path -from [remove_from_collection [all_inputs] [get_ports {clk}]]
set_false_path -to [all_outputs]
