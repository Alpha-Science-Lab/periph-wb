VERILATOR = verilator
VERILATOR_FLAGS = --binary -j 0 -Wall -Wno-fatal --trace

SRC_DIR = design
TB_DIR  = tb
COMMON_DIR = ../common
BUILD_DIR = build

TOP_MODULE = karnaphuli_wb_spi_top

RTL_SRCS = $(COMMON_DIR)/wishbone_interface.sv \
           $(SRC_DIR)/karnaphuli_wb_spi.sv \
           $(TB_DIR)/$(TOP_MODULE).sv

.PHONY: all compile run clean

all: compile

compile:
	@mkdir -p $(BUILD_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) --Mdir $(BUILD_DIR) $(RTL_SRCS) --top-module $(TOP_MODULE)

run: compile
	./$(BUILD_DIR)/V$(TOP_MODULE)

clean:
	rm -rf $(BUILD_DIR)
	rm -f *.vcd
	rm -f *.fst
