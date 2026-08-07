# -----------------------------------------
# Dotara I2C Verilator Build Makefile
# Alpha Science Lab
# -----------------------------------------

TOP       := dotara_wb_i2c_top
BUILD     := build
VERILATOR := verilator

RTL = \
	../common/wishbone_interface.sv \
	design/dotara_wb_i2c.sv \
	tb/dotara_wb_i2c_top.sv

VERILATOR_FLAGS = \
	--sv \
	--binary \
	--trace \
	--timing \
	-Wall \
	-Wno-fatal \
	-Wno-TIMESCALEMOD \
	--assert \
	--top-module $(TOP)

all: run

build:
	mkdir -p $(BUILD)

compile: build
	$(VERILATOR) \
		$(VERILATOR_FLAGS) \
		$(RTL) \
		-Mdir $(BUILD)

run: compile
	./$(BUILD)/V$(TOP)

clean:
	rm -rf $(BUILD)
	rm -f *.vcd
	rm -f *.fst

.PHONY: all build compile run clean
