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
VCOVER := $(QUESTA_HOME)/linux_x86_64/vcover
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
include $(TB_DIR)/generated_cases.mk
SMOKE_CASES := \
  test_b001_reset_idle:B001 \
  test_b002_single_job_hit_only_eoe:B002
SMOKE_CASE_IDS := B001 B002
REGRESS_CASES ?= $(PHASE_B_CASES)
REGRESS_CASE_IDS ?= $(PHASE_B_CASE_IDS)
BASIC_CASE_IDS := $(filter B%,$(REGRESS_CASE_IDS))
EDGE_CASE_IDS := $(filter E%,$(REGRESS_CASE_IDS))
PROF_CASE_IDS := $(filter P%,$(REGRESS_CASE_IDS))
ERROR_CASE_IDS := $(filter X%,$(REGRESS_CASE_IDS))

RTL_TOP := $(shell cd "$(IP_DIR)" && git ls-files rtl/rdma_dma_engine.sv)
ifeq ($(strip $(RTL_TOP)),)
DUT_SRCS := $(TB_DIR)/rdma_dma_engine_stub.sv
else
DUT_SRCS := $(wildcard $(IP_DIR)/rtl/*.sv)
endif

TB_PRE_SRCS := \
  $(UVM_PKG) \
  $(TB_DIR)/rdma_dma_engine_if.sv

TB_POST_SRCS := \
  $(TB_DIR)/opq_axis_agent/opq_axis_pkg.sv \
  $(TB_DIR)/job_agent/job_pkg.sv \
  $(TB_DIR)/axi4_write_agent/axi4_write_pkg.sv \
  $(TB_DIR)/rdma_dma_engine_pkg.sv \
  $(TB_DIR)/rdma_dma_engine_tb_top.sv

VLOG_BASE_FLAGS := -ini $(MODELSIM_INI) -sv -work work \
  +incdir+$(UVM_SRC) +incdir+$(TB_DIR) \
  +incdir+$(TB_DIR)/opq_axis_agent \
  +incdir+$(TB_DIR)/job_agent \
  +incdir+$(TB_DIR)/axi4_write_agent \
  +define+DEBUG_LEVEL=$(DEBUG_LEVEL)
ifeq ($(DEBUG_LEVEL),2)
VLOG_BASE_FLAGS += +define+RDMA_DMA_DEBUG2
endif
VLOG_COV_FLAGS := $(VLOG_BASE_FLAGS) +cover=$(COV_CODE)

VSIM_FLAGS := -ini $(MODELSIM_INI) -c -suppress 19 -suppress 3009 \
  -coverage -work work
ifneq ($(strip $(UVM_DPI_LIB)),)
VSIM_FLAGS += -sv_lib $(UVM_DPI_LIB)
endif

.PHONY: all prepare compile compile_dbg1 compile_dbg2 sim_one run_one smoke dbg1 dbg2 phase_b_dbg1 phase_b_dbg2 cross_validate regress merge_case_ucdbs merge_cov apply_cov_exclusions report clean

all: dbg1

prepare:
	mkdir -p $(BUILD_DIR) $(TB_DIR)/cov_after/dbg$(DEBUG_LEVEL) $(TB_DIR)/logs/dbg$(DEBUG_LEVEL)
	@if [ ! -f "$(MODELSIM_INI)" ]; then cp "$(QUESTA_HOME)/modelsim.ini" "$(MODELSIM_INI)"; chmod u+w "$(MODELSIM_INI)"; fi
	@if [ ! -d "$(WORK_DIR)" ]; then cd "$(BUILD_DIR)" && "$(VLIB)" work; fi
	cd "$(BUILD_DIR)" && "$(VMAP)" -modelsimini "$(MODELSIM_INI)" work "$(WORK_DIR)" >/dev/null

compile: prepare
	$(VLOG) $(VLOG_BASE_FLAGS) $(TB_PRE_SRCS)
	$(VLOG) $(VLOG_COV_FLAGS) $(DUT_SRCS)
	$(VLOG) $(VLOG_BASE_FLAGS) $(TB_POST_SRCS)

compile_dbg1:
	$(MAKE) DEBUG_LEVEL=1 compile

compile_dbg2:
	$(MAKE) DEBUG_LEVEL=2 compile

sim_one:
	$(VSIM) $(VSIM_FLAGS) $(TOP) \
	  +UVM_TESTNAME=$(TEST) +CASE_ID=$(CASE_ID) +DEBUG_LEVEL=$(DEBUG_LEVEL) \
	  +SCORECARD=$(TB_DIR)/cov_after/dbg$(DEBUG_LEVEL)/$(CASE_ID).scorecard.json \
	  -l $(TB_DIR)/logs/dbg$(DEBUG_LEVEL)/$(CASE_ID).log \
	  -do "coverage attr -name TESTNAME -value $(CASE_ID)_dbg$(DEBUG_LEVEL); coverage save -onexit $(TB_DIR)/cov_after/dbg$(DEBUG_LEVEL)/$(CASE_ID)_dbg$(DEBUG_LEVEL).ucdb; run -all; quit -f"
	@if grep -q "RDMA_DMA_ENGINE_TB_FAIL" $(TB_DIR)/logs/dbg$(DEBUG_LEVEL)/$(CASE_ID).log; then \
	  echo "simulation failed for $(CASE_ID), see $(TB_DIR)/logs/dbg$(DEBUG_LEVEL)/$(CASE_ID).log"; \
	  exit 1; \
	fi
	@if grep -Eq "(\\*\\* Error:|Errors: [1-9])" $(TB_DIR)/logs/dbg$(DEBUG_LEVEL)/$(CASE_ID).log; then \
	  echo "simulator error for $(CASE_ID), see $(TB_DIR)/logs/dbg$(DEBUG_LEVEL)/$(CASE_ID).log"; \
	  exit 1; \
	fi

run_one: compile sim_one

dbg1:
	$(MAKE) DEBUG_LEVEL=1 compile
	@for entry in $(SMOKE_CASES); do \
	  test_name=$${entry%%:*}; case_id=$${entry##*:}; \
	  $(MAKE) DEBUG_LEVEL=1 TEST=$$test_name CASE_ID=$$case_id sim_one || exit $$?; \
	done

dbg2:
	$(MAKE) DEBUG_LEVEL=2 compile
	@for entry in $(SMOKE_CASES); do \
	  test_name=$${entry%%:*}; case_id=$${entry##*:}; \
	  $(MAKE) DEBUG_LEVEL=2 TEST=$$test_name CASE_ID=$$case_id sim_one || exit $$?; \
	done

smoke:
	$(MAKE) -j2 dbg1 dbg2
	$(MAKE) cross_validate

phase_b_dbg1:
	$(MAKE) DEBUG_LEVEL=1 compile
	@for entry in $(REGRESS_CASES); do \
	  test_name=$${entry%%:*}; case_id=$${entry##*:}; \
	  $(MAKE) DEBUG_LEVEL=1 TEST=$$test_name CASE_ID=$$case_id sim_one || exit $$?; \
	done

phase_b_dbg2:
	$(MAKE) DEBUG_LEVEL=2 compile
	@for entry in $(REGRESS_CASES); do \
	  test_name=$${entry%%:*}; case_id=$${entry##*:}; \
	  $(MAKE) DEBUG_LEVEL=2 TEST=$$test_name CASE_ID=$$case_id sim_one || exit $$?; \
	done

regress:
	$(MAKE) -j2 phase_b_dbg1 phase_b_dbg2
	$(MAKE) cross_validate CASES="$(REGRESS_CASE_IDS)"
	$(MAKE) merge_cov

cross_validate:
	$(PYTHON) $(TB_DIR)/scripts/cross_validate_dbg.py --root $(TB_DIR)/cov_after --cases $(if $(CASES),$(CASES),$(SMOKE_CASE_IDS))

merge_case_ucdbs:
	@for case_id in $(REGRESS_CASE_IDS); do \
	  "$(VCOVER)" merge $(TB_DIR)/cov_after/$$case_id.ucdb \
	    $(TB_DIR)/cov_after/dbg1/$${case_id}_dbg1.ucdb \
	    $(TB_DIR)/cov_after/dbg2/$${case_id}_dbg2.ucdb || exit $$?; \
	  "$(VCOVER)" report -summary $(TB_DIR)/cov_after/$$case_id.ucdb \
	    > $(TB_DIR)/cov_after/$$case_id.rpt || exit $$?; \
	done

merge_cov: merge_case_ucdbs
	"$(VCOVER)" merge $(TB_DIR)/cov_after/BASIC_merged.ucdb $(foreach c,$(BASIC_CASE_IDS),$(TB_DIR)/cov_after/$(c).ucdb)
	"$(VCOVER)" merge $(TB_DIR)/cov_after/EDGE_merged.ucdb $(foreach c,$(EDGE_CASE_IDS),$(TB_DIR)/cov_after/$(c).ucdb)
	"$(VCOVER)" merge $(TB_DIR)/cov_after/PROF_merged.ucdb $(foreach c,$(PROF_CASE_IDS),$(TB_DIR)/cov_after/$(c).ucdb)
	"$(VCOVER)" merge $(TB_DIR)/cov_after/ERROR_merged.ucdb $(foreach c,$(ERROR_CASE_IDS),$(TB_DIR)/cov_after/$(c).ucdb)
	"$(VCOVER)" merge $(TB_DIR)/cov_after/rdma_dma_engine_all_merged.ucdb \
	  $(TB_DIR)/cov_after/BASIC_merged.ucdb \
	  $(TB_DIR)/cov_after/EDGE_merged.ucdb \
	  $(TB_DIR)/cov_after/PROF_merged.ucdb \
	  $(TB_DIR)/cov_after/ERROR_merged.ucdb
	"$(VCOVER)" report -summary $(TB_DIR)/cov_after/BASIC_merged.ucdb > $(TB_DIR)/cov_after/BASIC_merged.rpt
	"$(VCOVER)" report -summary $(TB_DIR)/cov_after/EDGE_merged.ucdb > $(TB_DIR)/cov_after/EDGE_merged.rpt
	"$(VCOVER)" report -summary $(TB_DIR)/cov_after/PROF_merged.ucdb > $(TB_DIR)/cov_after/PROF_merged.rpt
	"$(VCOVER)" report -summary $(TB_DIR)/cov_after/ERROR_merged.ucdb > $(TB_DIR)/cov_after/ERROR_merged.rpt
	"$(VCOVER)" report -summary $(TB_DIR)/cov_after/rdma_dma_engine_all_merged.ucdb > $(TB_DIR)/cov_after/rdma_dma_engine_all_merged.rpt
	$(MAKE) apply_cov_exclusions

apply_cov_exclusions:
	$(PYTHON) $(TB_DIR)/scripts/apply_phase_b_cov_exclusions.py --tb $(abspath $(TB_DIR)/..)

report:
	$(PYTHON) $(TB_DIR)/scripts/make_phase_b_report_json.py --tb $(abspath $(TB_DIR)/..)
	$(PYTHON) /home/yifeng/.codex/skills/dv-workflow/scripts/dv_report_gen.py --tb $(abspath $(TB_DIR)/..)
	$(PYTHON) /home/yifeng/.codex/skills/dv-workflow/scripts/dv_report_format_check.py $(abspath $(TB_DIR)/..)/DV_REPORT.md

clean:
	@echo "Manual cleanup required by project rule: no removal command is run by this Makefile."
