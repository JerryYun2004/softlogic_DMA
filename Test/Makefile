FAB_PROJ_ROOT    ?= ..
BUILD_DIR        ?= build
USER_DESIGN_DIR  ?= $(FAB_PROJ_ROOT)/user_design

AGU_MODULE       ?= conv3x3_hwc_channel_dma_agu
DMA_WRAPPER      ?= dma_a
TESTBENCH        ?= dma_address_mapper_tb
TOP_WRAPPER      ?= top_wrapper

AGU_RTL          ?= $(USER_DESIGN_DIR)/$(AGU_MODULE).sv
DMA_WRAPPER_RTL  ?= $(USER_DESIGN_DIR)/$(DMA_WRAPPER).v
TESTBENCH_RTL    ?= $(TESTBENCH).v
TOP_WRAPPER_RTL  ?= $(USER_DESIGN_DIR)/$(TOP_WRAPPER).v
IMAGE_MEM        ?= yolo_image_3x3.mem
RTL_SOURCES       = $(AGU_RTL) $(DMA_WRAPPER_RTL)

IVERILOG         ?= iverilog
VVP              ?= vvp
YOSYS            ?= $(or $(FAB_YOSYS_PATH),yosys)
NEXTPNR          ?= $(or $(FAB_NEXTPNR_PATH),nextpnr-generic)
MAX_BITBYTES     ?= 16384

FABRIC_FILES_DIR := $(BUILD_DIR)/fabric_files
NETLIST_JSON     := $(BUILD_DIR)/$(AGU_MODULE).json
FASM_FILE        := $(BUILD_DIR)/$(AGU_MODULE).fasm
BITSTREAM_BIN    := $(BUILD_DIR)/$(AGU_MODULE).bin
BITSTREAM_HEX    := $(BUILD_DIR)/$(AGU_MODULE).hex

ifneq ($(wildcard $(USER_DESIGN_DIR)/custom_prims.v),)
CUSTOM_PRIMS := -extra-plib $(USER_DESIGN_DIR)/custom_prims.v
endif

.PHONY: all sim rtl_sim wave clean build_test_design run_yosys \
	run_nextpnr run_bitgen copy_files mkdir_build check_rtl_files

all: rtl_sim

# Direct RTL verification of the AXI wrapper and fixed-function HWC halo AGU.
sim: rtl_sim

rtl_sim: check_rtl_files mkdir_build
	$(IVERILOG) -g2012 -Wall -s $(TESTBENCH) \
		-o "$(BUILD_DIR)/$(TESTBENCH).vvp" \
		"$(AGU_RTL)" "$(DMA_WRAPPER_RTL)" "$(TESTBENCH_RTL)"
	$(VVP) "$(BUILD_DIR)/$(TESTBENCH).vvp" \
		"+IMAGE_MEM=$(abspath $(IMAGE_MEM))"

check_rtl_files:
	@test -f "$(AGU_RTL)" || { echo "Missing AGU RTL: $(AGU_RTL)"; exit 1; }
	@test -f "$(DMA_WRAPPER_RTL)" || { echo "Missing AXI wrapper RTL: $(DMA_WRAPPER_RTL)"; exit 1; }
	@test -f "$(TESTBENCH_RTL)" || { echo "Missing testbench: $(TESTBENCH_RTL)"; exit 1; }
	@test -f "$(IMAGE_MEM)" || { echo "Missing image memory file: $(IMAGE_MEM)"; exit 1; }

wave:
	gtkwave $(BUILD_DIR)/$(TESTBENCH).vcd

# Optional FABulous synthesis/P&R/bitstream build after RTL verification.
# This requires top_wrapper.v, custom_prims.v, and the generated fabric files
# in the parent FABulous project.  top_wrapper must match the revised dma_a
# map interface (9-bit buffer address plus zero-fill and last flags).
build_test_design: run_yosys run_nextpnr run_bitgen copy_files

run_yosys: mkdir_build
	$(YOSYS) -p "synth_fabulous -top $(TOP_WRAPPER) -json $(NETLIST_JSON) $(CUSTOM_PRIMS)" \
		"$(AGU_RTL)" "$(DMA_WRAPPER_RTL)" "$(TOP_WRAPPER_RTL)"

run_nextpnr: mkdir_build
	FAB_ROOT=$(FAB_PROJ_ROOT) $(NEXTPNR) --uarch fabulous \
		--json $(NETLIST_JSON) \
		-o fasm=$(FASM_FILE)

run_bitgen: mkdir_build
	bit_gen -genBitstream $(FASM_FILE) \
		$(FAB_PROJ_ROOT)/.FABulous/bitStreamSpec.bin \
		$(BITSTREAM_BIN)
	python3 makehex.py $(BITSTREAM_BIN) \
		$(MAX_BITBYTES) $(BITSTREAM_HEX)

copy_files: mkdir_build
	find $(FAB_PROJ_ROOT)/Tile -name '*.v' -type f \
		-exec cp {} "$(FABRIC_FILES_DIR)/" \;
	find $(FAB_PROJ_ROOT)/Fabric -name '*.v' -type f \
		-exec cp {} "$(FABRIC_FILES_DIR)/" \;

mkdir_build:
	mkdir -p "$(BUILD_DIR)" "$(FABRIC_FILES_DIR)"

clean:
	@test -n "$(BUILD_DIR)" && test "$(BUILD_DIR)" != "/"
	rm -rf -- "$(BUILD_DIR)"
