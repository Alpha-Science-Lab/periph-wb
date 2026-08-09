# -----------------------------------------
# Brahmaputra Verilator Build
# Alpha Science Lab
# -----------------------------------------

TOP      := brahmaputra_wb_gpio_top
BUILD    := build

VERILATOR := verilator

RTL = \
	../common/wishbone_interface.sv \
	design/brahmaputra_wb_gpio.sv \
	tb/brahmaputra_wb_gpio_top.sv

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
	gtkwave tb_brahmaputra_wb_gpio.vcd &

clean:
	rm -rf $(BUILD)
	rm -f *.vcd
	rm -f *.fst

.PHONY: all build compile run wave clean
