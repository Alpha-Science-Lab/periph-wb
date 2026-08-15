# -----------------------------------------
# Spondon PWM Verilator Build
# Alpha Science Lab
# -----------------------------------------

TOP      := spondon_wb_pwm_top
BUILD    := build

VERILATOR := verilator

RTL = \
	../common/wishbone_interface.sv \
	design/spondon_wb_pwm.sv \
	tb/spondon_wb_pwm_top.sv

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
	gtkwave tb_spondon_wb_pwm.vcd

clean:
	rm -rf $(BUILD)
	rm -f *.vcd
	rm -f *.fst

.PHONY: all build compile run wave clean
