/* Sanity check
 * Linear & Deterministic
 * Core: karnaphuli_wb_spi
 *
 * Sequence:
 *   Reset
 *   Program prescaler & control
 *   Assert CS_N (Active Low)
 *   Transmit JEDEC ID command (0x9F) + dummy bytes
 *   Simulate SPI Flash response (0x85 0x60 0x16)
 *   Readback received bytes from RX FIFO via Wishbone
 *   Deassert CS_N
 *   Finish
 * 
 * No classes, no UVM, no randomization
 */

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
    // DUT & Signals
    //---------------------------------------------

    wishbone_interface wb();

    logic spi_cs_n;
    logic spi_sclk;
    logic spi_mosi;
    logic spi_miso;

    karnaphuli_wb_spi #(
        .START_ADDRESS(32'd0),
        .SIZE(32'h0000_0006),
        .DEFAULT_PRESCALER(3)
    ) dut (
        .clk(clk),
        .rst(rst),
        .wb(wb.slave),
        .spi_cs_n(spi_cs_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );

    //---------------------------------------------
    // Register Address Offsets (Word Addressed)
    //---------------------------------------------

    localparam CTRL      = 32'h00 >> 2;
    localparam PRESCALER = 32'h04 >> 2;
    localparam STATUS    = 32'h08 >> 2;
    localparam DATA      = 32'h0C >> 2;
    localparam CS        = 32'h10 >> 2;

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
    // Behavioral Model of Puya P25Q32H SPI Flash
    //---------------------------------------------

    logic [7:0] flash_shift;
    integer     flash_bit_idx;

    initial begin
        spi_miso = 1'b1;
        flash_shift = 8'h85; // Puya Manufacturer ID
        flash_bit_idx = 7;

        forever begin
            @(negedge spi_sclk);
            if (!spi_cs_n) begin
                spi_miso = flash_shift[flash_bit_idx];
                if (flash_bit_idx == 0) begin
                    flash_bit_idx = 7;
                    if (flash_shift == 8'h85) flash_shift = 8'h60;      // Memory Type
                    else if (flash_shift == 8'h60) flash_shift = 8'h16; // Capacity (32Mbit)
                    else flash_shift = 8'hFF;
                end else begin
                    flash_bit_idx = flash_bit_idx - 1;
                end
            end
        end
    end

    //---------------------------------------------
    // Main Sanity Test
    //---------------------------------------------

    logic [31:0] rd_data;

    initial begin
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

        $display("\033[0;33mKARNAPHULI SPI SANITY TEST START\033[0m");

        // 1. Program Prescaler
        $display("Programming prescaler...");
        wb_write(PRESCALER, 32'd3);

        // 2. Program Control Reg (Enable SPI, Mode 0)
        $display("Enabling SPI Core...");
        wb_write(CTRL, 32'h1);

        // 3. Assert Chip Select
        $display("Asserting CS_N (Low)...");
        wb_write(CS, 32'h0);

        // 4. Send JEDEC ID Command 0x9F + 3 Dummy Bytes
        $display("Sending Read JEDEC ID Command (0x9F) and 3 Dummy Bytes...");
        wb_write(DATA, 32'h9F);
        wb_write(DATA, 32'h00);
        wb_write(DATA, 32'h00);
        wb_write(DATA, 32'h00);

        // Wait for SPI transaction to complete
        do begin
            wb_read(STATUS, rd_data);
            #100;
        end while (rd_data[0] == 1'b1); // Busy check

        repeat (100) @(posedge clk);

        // 5. Readback RX FIFO values
        $display("Reading received bytes from RX FIFO via Wishbone...");

        wb_read(DATA, rd_data);
        $display("RX Byte 0 (Command Echo) = 0x%02X", rd_data[7:0]);

        wb_read(DATA, rd_data);
        $display("RX Byte 1 (Manufacturer ID) = 0x%02X (Expected: 0x85)", rd_data[7:0]);

        wb_read(DATA, rd_data);
        $display("RX Byte 2 (Memory Type)     = 0x%02X (Expected: 0x60)", rd_data[7:0]);

        wb_read(DATA, rd_data);
        $display("RX Byte 3 (Capacity ID)     = 0x%02X (Expected: 0x16)", rd_data[7:0]);

        // 6. Deassert Chip Select
        $display("Deasserting CS_N (High)...");
        wb_write(CS, 32'h1);

        repeat (100) @(posedge clk);

        $display("\033[0;33mKARNAPHULI SPI SANITY TEST FINISH\033[0m");
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
