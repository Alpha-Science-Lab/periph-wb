# -----------------------------------------
# Bashi I2S Verilator Build
# Alpha Science Lab
# -----------------------------------------

TOP      := bashi_wb_i2s_top
BUILD    := build

VERILATOR := verilator

RTL = \
	../common/wishbone_interface.sv \
	design/bashi_pkg.sv \
	design/bashi_regs.sv \
	design/bashi_i2s_tx.sv \
	design/bashi_wb_i2s.sv \
	tb/bashi_wb_i2s_top.sv

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
	gtkwave tb_bashi_wb_i2s.vcd &

clean:
	rm -rf $(BUILD)
	rm -f *.vcd
	rm -f *.fst

.PHONY: all build compile run wave clean
