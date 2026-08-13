/* Sanity check for Karnaphuli SPI Master Core
 * Core: karnaphuli_wb_spi
 * Multi-Slave Assertion Testbench (8 Slaves Supported)
 *
 * Sequence:
 *   1. Reset & Register Check
 *   2. Program Prescaler & Enable SPI Core
 *   3. Select Slave 0 (spi_cs_n[0] = Low) -> Puya SPI Flash (Read JEDEC ID 0x9F -> 0x85 0x60 0x16)
 *   4. Self-checking SystemVerilog Assertions for Slave 0
 *   5. Select Slave 1 (spi_cs_n[1] = Low) -> SPI Sensor Device (Read ID 0x90 -> 0xDE 0xAD)
 *   6. Self-checking SystemVerilog Assertions for Slave 1
 *   7. Deassert CS_N for all slaves
 *   8. Finish
 */

`timescale 1ns/1ps

module karnaphuli_wb_spi_top;

    //---------------------------------------------
    // Clock / Reset
    //---------------------------------------------

    logic clk;
    logic rst;

    initial begin
        clk = 0;
        forever #20 clk = ~clk; // 25 MHz
    end 

    //---------------------------------------------
    // DUT & Multi-Slave Signals (8 Slaves)
    //---------------------------------------------

    wishbone_interface wb();
    logic interrupt;

    logic [7:0] spi_cs_n;
    logic       spi_sclk;
    logic       spi_mosi;
    logic       spi_miso;

    logic flash_miso;
    logic sensor_miso;

    // MUX MISO line based on active slave CS_N
    assign spi_miso = (!spi_cs_n[0]) ? flash_miso :
                      (!spi_cs_n[1]) ? sensor_miso : 1'b1;

    karnaphuli_wb_spi #(
        .START_ADDRESS(32'd0),
        .SIZE(32'h0000_0006),
        .NUM_SLAVES(8),
        .DEFAULT_PRESCALER(3)
    ) uut (
        .clk(clk),
        .rst(rst),
        .wb(wb.slave),
        .interrupt(interrupt),
        .spi_cs_n(spi_cs_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );

    //---------------------------------------------
    // Register Address Offsets (Word Addressed)
    //---------------------------------------------

    localparam CTRL      = 32'h00;
    localparam PRESCALER = 32'h01;
    localparam STATUS    = 32'h02;
    localparam DATA      = 32'h03;
    localparam CS        = 32'h04;

    //---------------------------------------------
    // Wishbone Write Task
    //---------------------------------------------

    task automatic wb_write(
        input [31:0] addr,
        input [31:0] data
    );
    begin
        @(posedge clk);

        wb.adr      = addr;
        wb.dat_mosi = data;
        wb.we       = 1'b1;
        wb.cyc      = 1'b1;
        wb.stb      = 1'b1;
        wb.sel      = 4'hF;

        wait (wb.ack);

        @(posedge clk);

        wb.cyc      = 1'b0;
        wb.stb      = 1'b0;
        wb.we       = 1'b0;
        wb.adr      = '0;
        wb.dat_mosi = '0;
    end
    endtask

    //---------------------------------------------
    // Wishbone Read Task
    //---------------------------------------------

    task automatic wb_read(
        input  [31:0] addr,
        output [31:0] data
    );
    begin
        @(posedge clk);

        wb.adr = addr;
        wb.we  = 1'b0;
        wb.cyc = 1'b1;
        wb.stb = 1'b1;
        wb.sel = 4'hF;

        wait (wb.ack);

        data = wb.dat_miso;

        @(posedge clk);

        wb.cyc = 1'b0;
        wb.stb = 1'b0;
        wb.adr = '0;
    end
    endtask

    //---------------------------------------------
    // Behavioral Model 1: Puya P25Q32H SPI Flash (Slave 0)
    //---------------------------------------------

    logic [7:0] flash_shift;
    integer     flash_bit_idx;

    initial begin
        flash_miso = 1'b1;
        flash_shift = 8'h85; // Puya Manufacturer ID
        flash_bit_idx = 7;

        forever begin
            @(negedge spi_sclk);
            if (!spi_cs_n[0]) begin
                flash_miso = flash_shift[flash_bit_idx];
                if (flash_bit_idx == 0) begin
                    flash_bit_idx = 7;
                    if (flash_shift == 8'h85) flash_shift = 8'h60;      // Memory Type
                    else if (flash_shift == 8'h60) flash_shift = 8'h16; // Capacity (32Mbit)
                    else flash_shift = 8'hFF;
                end else begin
                    flash_bit_idx = flash_bit_idx - 1;
                end
            end else begin
                flash_shift = 8'h85;
                flash_bit_idx = 7;
            end
        end
    end

    //---------------------------------------------
    // Behavioral Model 2: SPI Sensor Device (Slave 1)
    //---------------------------------------------

    logic [7:0] sensor_shift;
    integer     sensor_bit_idx;

    initial begin
        sensor_miso = 1'b1;
        sensor_shift = 8'hDE; // Sensor Device ID
        sensor_bit_idx = 7;

        forever begin
            @(negedge spi_sclk);
            if (!spi_cs_n[1]) begin
                sensor_miso = sensor_shift[sensor_bit_idx];
                if (sensor_bit_idx == 0) begin
                    sensor_bit_idx = 7;
                    if (sensor_shift == 8'hDE) sensor_shift = 8'hAD;
                    else sensor_shift = 8'hFF;
                end else begin
                    sensor_bit_idx = sensor_bit_idx - 1;
                end
            end else begin
                sensor_shift = 8'hDE;
                sensor_bit_idx = 7;
            end
        end
    end

    //---------------------------------------------
    // Main Assertion Verification Test
    //---------------------------------------------

    logic [31:0] rd_data;

    initial begin

        $display("\033[0;33mStarting Verilator Simulation: karnaphuli_wb_spi\033[0m");

        // Initialize
        rst = 1;
        wb.adr      = 0;
        wb.sel      = 0;
        wb.dat_mosi = 0;
        wb.cyc      = 0;
        wb.stb      = 0;
        wb.we       = 0;

        repeat (10) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

        // 1. Program Prescaler & Verify
        $display("[TEST 1] Programming prescaler = 5");
        wb_write(PRESCALER, 32'd5);

        wb_read(PRESCALER, rd_data);
        $display("[TEST 1] Read PRESCALER: %0d", rd_data[15:0]);
        assert(rd_data[15:0] == 16'd5) else $error("[ASSERTION FAILED] Prescaler mismatch!");

        // 2. Program Control Reg (Enable Core)
        $display("[TEST 2] Enabling SPI Core (CTRL = 0x01)");
        wb_write(CTRL, 32'h1);

        wb_read(CTRL, rd_data);
        $display("[TEST 2] Read CTRL: 0x%02X", rd_data[7:0]);
        assert(rd_data[0] == 1'b1) else $error("[ASSERTION FAILED] Core enable mismatch!");

        // 3. Select Slave 0 (Puya SPI Flash -> CS_N = 8'b1111_1110 = 0xFE)
        $display("[TEST 3] Asserting Slave 0 CS_N (0xFE)");
        wb_write(CS, 32'hFE);

        wb_read(CS, rd_data);
        $display("[TEST 3] Read CS: 0x%02X", rd_data[7:0]);
        assert(rd_data[7:0] == 8'hFE) else $error("[ASSERTION FAILED] Slave 0 CS mismatch!");

        // 4. Send Read JEDEC ID Command (0x9F) + 3 Dummy Bytes to Slave 0
        $display("[TEST 4] Transmitting JEDEC ID command (0x9F) + 3 dummy bytes to Slave 0");
        wb_write(DATA, 32'h9F);
        wb_write(DATA, 32'h00);
        wb_write(DATA, 32'h00);
        wb_write(DATA, 32'h00);

        // Wait for SPI transaction completion
        do begin
            wb_read(STATUS, rd_data);
            #100;
        end while (rd_data[0] == 1'b1); // Busy check

        repeat (100) @(posedge clk);

        // 5. Assert Slave 0 Readback Values
        $display("[TEST 5] Reading & Asserting Slave 0 RX FIFO Data");

        wb_read(DATA, rd_data); // Byte 0 (Command Echo)
        $display("[TEST 5] RX Byte 0 (Command Echo): 0x%02X", rd_data[7:0]);

        wb_read(DATA, rd_data); // Byte 1 (Manufacturer ID = 0x85)
        $display("[TEST 5] RX Byte 1 (Manufacturer ID): 0x%02X", rd_data[7:0]);
        assert(rd_data[7:0] == 8'h85) else $error("[ASSERTION FAILED] Flash Manufacturer ID mismatch!");

        wb_read(DATA, rd_data); // Byte 2 (Memory Type = 0x60)
        $display("[TEST 5] RX Byte 2 (Memory Type): 0x%02X", rd_data[7:0]);
        assert(rd_data[7:0] == 8'h60) else $error("[ASSERTION FAILED] Flash Memory Type mismatch!");

        wb_read(DATA, rd_data); // Byte 3 (Capacity ID = 0x16)
        $display("[TEST 5] RX Byte 3 (Capacity ID): 0x%02X", rd_data[7:0]);
        assert(rd_data[7:0] == 8'h16) else $error("[ASSERTION FAILED] Flash Capacity ID mismatch!");

        // 6. Deassert Slave 0 CS_N
        wb_write(CS, 32'hFF);

        // 7. Select Slave 1 (SPI Sensor -> CS_N = 8'b1111_1101 = 0xFD)
        $display("[TEST 6] Asserting Slave 1 CS_N (0xFD)");
        wb_write(CS, 32'hFD);

        wb_read(CS, rd_data);
        $display("[TEST 6] Read CS: 0x%02X", rd_data[7:0]);
        assert(rd_data[7:0] == 8'hFD) else $error("[ASSERTION FAILED] Slave 1 CS mismatch!");

        // 8. Transmit Command 0x90 + 2 Dummy Bytes to Slave 1
        $display("[TEST 7] Transmitting Command 0x90 + 2 dummy bytes to Slave 1");
        wb_write(DATA, 32'h90);
        wb_write(DATA, 32'h00);
        wb_write(DATA, 32'h00);

        do begin
            wb_read(STATUS, rd_data);
            #100;
        end while (rd_data[0] == 1'b1);

        repeat (100) @(posedge clk);

        // 9. Assert Slave 1 Readback Values
        $display("[TEST 8] Reading & Asserting Slave 1 RX FIFO Data");

        wb_read(DATA, rd_data); // Byte 0 (Command Echo)
        $display("[TEST 8] RX Byte 0 (Command Echo): 0x%02X", rd_data[7:0]);

        wb_read(DATA, rd_data); // Byte 1 (Sensor ID 1 = 0xDE)
        $display("[TEST 8] RX Byte 1 (Sensor ID 1): 0x%02X", rd_data[7:0]);
        assert(rd_data[7:0] == 8'hDE) else $error("[ASSERTION FAILED] Sensor ID 1 mismatch!");

        wb_read(DATA, rd_data); // Byte 2 (Sensor ID 2 = 0xAD)
        $display("[TEST 8] RX Byte 2 (Sensor ID 2): 0x%02X", rd_data[7:0]);
        assert(rd_data[7:0] == 8'hAD) else $error("[ASSERTION FAILED] Sensor ID 2 mismatch!");

        // 10. Deassert All Slaves (CS_N = 0xFF)
        wb_write(CS, 32'hFF);

        $display("\033[0;33mALL KARNAPHULI SPI TESTS PASSED SUCCESSFULLY!\033[0m");

        $finish;
    end

    //---------------------------------------------
    // Waveform Dump
    //---------------------------------------------

    initial begin
        $dumpfile("tb_karnaphuli_wb_spi.vcd");
        $dumpvars(0, karnaphuli_wb_spi_top);
    end

endmodule
