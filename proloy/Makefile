# -----------------------------------------
# Proloy Verilator Build
# Alpha Science Lab
# -----------------------------------------

TOP      := proloy_wb_rst_top
BUILD    := build

VERILATOR := verilator

RTL = \
	../common/wishbone_interface.sv \
	design/proloy_wb_rst.sv \
	tb/proloy_wb_rst_top.sv

VERILATOR_FLAGS = \
	--sv \
	--binary \
	--trace \
	--timing \
	-Wall \
	-Wno-fatal \
	--assert \
	--top-module $(TOP)

# -----------------------------------------

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

wave: run
	gtkwave tb_proloy_wb_rst.vcd

clean:
	rm -rf $(BUILD)
	rm -f *.vcd
	rm -f *.fst

.PHONY: all build compile run wave clean
