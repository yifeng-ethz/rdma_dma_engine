TB_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
IP_DIR := $(abspath $(TB_DIR)/../..)

QUESTA_HOME ?= /data1/questaone_sim-2026.1_1/questasim
ETH_LIC_SERVER := 8161@lic-mentor.ethz.ch
export LM_LICENSE_FILE := $(ETH_LIC_SERVER)
export MGLS_LICENSE_FILE := $(LM_LICENSE_FILE)
export SALT_LICENSE_SERVER := $(LM_LICENSE_FILE)
export QSIM_INI := $(QUESTA_HOME)/modelsim.ini

VLIB := $(QUESTA_HOME)/linux_x86_64/vlib
VMAP := $(QUESTA_HOME)/linux_x86_64/vmap
VLOG := $(QUESTA_HOME)/linux_x86_64/vlog
VSIM := $(QUESTA_HOME)/linux_x86_64/vsim
PYTHON ?= python3

UVM_PKG := $(firstword $(wildcard \
  $(QUESTA_HOME)/verilog_src/questa_uvm_pkg-1.2/src/uvm_pkg.sv \
  $(QUESTA_HOME)/verilog_src/uvm-1.2/src/uvm_pkg.sv))
UVM_SRC := $(dir $(UVM_PKG))
UVM_DPI_SO := $(firstword $(wildcard \
  $(QUESTA_HOME)/uvm-1.2/linux_x86_64/uvm_dpi.so \
  $(QUESTA_HOME)/verilog_src/uvm-1.2/linux_x86_64/uvm_dpi.so))
UVM_DPI_LIB := $(basename $(UVM_DPI_SO))

DEBUG_LEVEL ?= 1
BUILD_DIR ?= $(TB_DIR)/build/dbg$(DEBUG_LEVEL)
WORK_DIR := $(BUILD_DIR)/work
MODELSIM_INI := $(BUILD_DIR)/modelsim.ini
TOP := rdma_dma_engine_tb_top
TEST ?= rdma_dma_engine_base_test
CASE_ID ?= BASE
COV_CODE ?= sbecft

RTL_TOP := $(shell cd "$(IP_DIR)" && git ls-files rtl/rdma_dma_engine.sv)
ifeq ($(strip $(RTL_TOP)),)
DUT_SRCS := $(TB_DIR)/rdma_dma_engine_stub.sv
else
DUT_SRCS := $(wildcard $(IP_DIR)/rtl/*.sv)
endif

SV_SRCS := \
  $(UVM_PKG) \
  $(TB_DIR)/rdma_dma_engine_if.sv \
  $(DUT_SRCS) \
  $(TB_DIR)/opq_axis_agent/opq_axis_pkg.sv \
  $(TB_DIR)/job_agent/job_pkg.sv \
  $(TB_DIR)/axi4_write_agent/axi4_write_pkg.sv \
  $(TB_DIR)/rdma_dma_engine_pkg.sv \
  $(TB_DIR)/rdma_dma_engine_tb_top.sv

VLOG_FLAGS := -ini $(MODELSIM_INI) -sv -work work \
  +incdir+$(UVM_SRC) +incdir+$(TB_DIR) \
  +incdir+$(TB_DIR)/opq_axis_agent \
  +incdir+$(TB_DIR)/job_agent \
  +incdir+$(TB_DIR)/axi4_write_agent \
  +define+DEBUG_LEVEL=$(DEBUG_LEVEL) +cover=$(COV_CODE)
ifeq ($(DEBUG_LEVEL),2)
VLOG_FLAGS += +define+RDMA_DMA_DEBUG2
endif

VSIM_FLAGS := -ini $(MODELSIM_INI) -c -suppress 19 -suppress 3009 \
  -coverage -work work
ifneq ($(strip $(UVM_DPI_LIB)),)
VSIM_FLAGS += -sv_lib $(UVM_DPI_LIB)
endif

.PHONY: all prepare compile compile_dbg1 compile_dbg2 run_one dbg1 dbg2 regress clean

all: dbg1

prepare:
	mkdir -p $(BUILD_DIR) $(TB_DIR)/cov_after/dbg$(DEBUG_LEVEL) $(TB_DIR)/logs/dbg$(DEBUG_LEVEL)
	@if [ ! -f "$(MODELSIM_INI)" ]; then cp "$(QUESTA_HOME)/modelsim.ini" "$(MODELSIM_INI)"; chmod u+w "$(MODELSIM_INI)"; fi
	@if [ ! -d "$(WORK_DIR)" ]; then cd "$(BUILD_DIR)" && "$(VLIB)" work; fi
	cd "$(BUILD_DIR)" && "$(VMAP)" -modelsimini "$(MODELSIM_INI)" work "$(WORK_DIR)" >/dev/null

compile: prepare
	$(VLOG) $(VLOG_FLAGS) $(SV_SRCS)

compile_dbg1:
	$(MAKE) DEBUG_LEVEL=1 compile

compile_dbg2:
	$(MAKE) DEBUG_LEVEL=2 compile

run_one: compile
	$(VSIM) $(VSIM_FLAGS) $(TOP) \
	  +UVM_TESTNAME=$(TEST) +CASE_ID=$(CASE_ID) +DEBUG_LEVEL=$(DEBUG_LEVEL) \
	  +SCORECARD=$(TB_DIR)/cov_after/dbg$(DEBUG_LEVEL)/$(CASE_ID).scorecard.json \
	  -l $(TB_DIR)/logs/dbg$(DEBUG_LEVEL)/$(CASE_ID).log \
	  -do "coverage save -onexit $(TB_DIR)/cov_after/dbg$(DEBUG_LEVEL)/$(CASE_ID).ucdb; run -all; quit -f"

dbg1:
	$(MAKE) DEBUG_LEVEL=1 run_one

dbg2:
	$(MAKE) DEBUG_LEVEL=2 run_one

regress:
	$(MAKE) -j2 dbg1 dbg2

clean:
	@echo "Manual cleanup required by project rule: no removal command is run by this Makefile."
