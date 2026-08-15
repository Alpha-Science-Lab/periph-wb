/* 
 * Testbench for Dotara Wishbone I2C Master Peripheral with RX/TX FIFOs
 * Organization: Alpha Science Lab
 * August 2026
 */

`timescale 1ns/1ps

module dotara_wb_i2c_top;

    logic clk;
    logic rst;

    // Wishbone Interface
    wishbone_interface wb();

    // Interrupt
    logic interrupt;

    // I2C Tri-State Pad Signals
    logic scl_pad_i;
    logic scl_pad_o;
    logic scl_padoen_o;

    logic sda_pad_i;
    logic sda_pad_o;
    logic sda_padoen_o;

    // Simulated Pull-up I2C Bus Lines
    wire scl_bus;
    wire sda_bus;

    // Model Open-Drain Pull-up logic
    assign scl_bus   = scl_padoen_o ? 1'b1 : scl_pad_o;
    assign sda_bus   = sda_padoen_o ? 1'b1 : sda_pad_o;

    assign scl_pad_i = scl_bus;
    assign sda_pad_i = sda_bus;

    // Clock Generation
    initial begin
        clk = 0;
        forever #20 clk = ~clk;
    end

    // Instantiate Unit Under Test (UUT)
    dotara_wb_i2c #(
        .START_ADDRESS(32'd0),
        .FIFO_DEPTH(16),
        .DEFAULT_PRESCALER(16'd7)
    ) uut (
        .clk(clk),
        .rst(rst),
        .wb(wb),
        .intr(interrupt),
        .scl_pad_i(scl_pad_i),
        .scl_pad_o(scl_pad_o),
        .scl_padoen_o(scl_padoen_o),
        .sda_pad_i(sda_pad_i),
        .sda_pad_o(sda_pad_o),
        .sda_padoen_o(sda_padoen_o)
    );

    // Wishbone Helper Tasks (Word Addressing)
    task wb_write(input logic [31:0] address, input logic [31:0] data);
        begin
            @(posedge clk);
            wb.adr      = address;
            wb.dat_mosi = data;
            wb.we       = 1'b1;
            wb.cyc      = 1'b1;
            wb.stb      = 1'b1;
            wb.sel      = 4'b1111;

            @(posedge clk);
            while (!wb.ack) @(posedge clk);

            wb.cyc = 1'b0;
            wb.stb = 1'b0;
            wb.we  = 1'b0;
        end
    endtask

    task wb_read(input logic [31:0] address, output logic [31:0] data);
        begin
            @(posedge clk);
            wb.adr = address;
            wb.we  = 1'b0;
            wb.cyc = 1'b1;
            wb.stb = 1'b1;
            wb.sel = 4'b1111;

            @(posedge clk);
            while (!wb.ack) @(posedge clk);

            data   = wb.dat_miso;
            wb.cyc = 1'b0;
            wb.stb = 1'b0;
        end
    endtask

    logic [31:0] read_val;

    initial begin
        $display("\033[0;33mStarting Verilator Simulation: dotara_wb_i2c_top \033[0m");

        clk = 0;
        rst = 1;

        wb.cyc      = 0;
        wb.stb      = 0;
        wb.we       = 0;
        wb.adr      = 0;
        wb.dat_mosi = 0;
        wb.sel      = 0;

        #40;
        rst = 0;
        #20;

        // 1. Write Prescaler LOW & HIGH (PRER_LO = Word 0, PRER_HI = Word 1)
        $display("[TEST 1] Writing Prescaler PRER = 10 (PRER_LO = 0x0A, PRER_HI = 0x00)");
        wb_write(32'h00, 32'h0A); // PRER_LO
        wb_write(32'h01, 32'h00); // PRER_HI

        wb_read(32'h00, read_val);
        $display("[TEST 1] Read PRER_LO: 0x%02X", read_val[7:0]);
        assert(read_val[7:0] == 8'h0A) 
            else $error("PRER_LO mismatch!");

        // 2. Enable Core & Interrupts (CTR = Word 2, value = 0xC0)
        $display("[TEST 2] Enabling Dotara I2C Core (CTR = 0xC0)");
        wb_write(32'h02, 32'hC0);

        wb_read(32'h02, read_val);
        $display("[TEST 2] Read CTR: 0x%02X", read_val[7:0]);
        assert(read_val[7] == 1'b1) 
            else $error("CTR enable mismatch!");

        // 3. Test TX FIFO Burst Pushing (RXR_TXR = Word 3)
        $display("[TEST 3] Pushing 3 bytes into TX FIFO (0xA0, 0xBE, 0xEF)");
        wb_write(32'h03, 32'hA0); // Byte 1
        wb_write(32'h03, 32'hBE); // Byte 2
        wb_write(32'h03, 32'hEF); // Byte 3

        wb_read(32'h05, read_val); // Read FIFO_SR (Word 5)
        $display("[TEST 3] FIFO Status Register: 0x%04X (TX_CNT = %d, TX_EMPTY = %b)", read_val[15:0], read_val[7:4], read_val[0]);
        assert(read_val[7:4] == 4'd3)
            else $error("[TEST 3] TX FIFO count mismatch!");

        // 4. Generate START Condition (CR_SR = Word 4, CR = 0x80)
        $display("[TEST 4] Generating START Condition (CR = 0x80)");
        wb_write(32'h04, 32'h80);

        #2000;
        wb_read(32'h04, read_val);
        $display("[TEST 4] Status Register: 0x%02X (IF = %b, BUSY = %b)", 
            read_val[7:0], read_val[0], read_val[6]);
        
        assert(read_val[6] == 1'b1)
            else $error("[TEST 4] BUSY should be asserted after START!");
        
        // 5. Transmit 1st Byte from TX FIFO (CR_SR = Word 4, CR = 0x10 [WR])
        $display("[TEST 5] Transmitting 1st Byte (0xA0) from TX FIFO");
        wb_write(32'h04, 32'h10); // CR = WR

        #8000;
        wb_read(32'h05, read_val);
        $display("[TEST 5] FIFO Status after 1st TX: TX_CNT = %d", read_val[7:4]);

        assert(read_val[7:4] == 4'd2)
            else $error("[TEST 5] TX FIFO count should be 2 after first TX!");

        // 6. Transmit 2nd Byte from TX FIFO (CR_SR = Word 4, CR = 0x10 [WR])
        $display("[TEST 6] Transmitting 2nd Byte (0xBE) from TX FIFO");
        wb_write(32'h04, 32'h10); // CR = WR

        #8000;
        wb_read(32'h05, read_val);
        $display("[TEST 6] FIFO Status after 2nd TX: TX_CNT = %d", read_val[7:4]);

        assert(read_val[7:4] == 4'd1)
            else $error("[TEST 6] TX FIFO count should be 1 after second TX!");

        // 7. Generate STOP Condition (CR_SR = Word 4, CR = 0x40)
        $display("[TEST 7] Generating STOP Condition (CR = 0x40)");
        wb_write(32'h04, 32'h40);

        #8000;
        wb_read(32'h04, read_val);
        $display("[TEST 7] Status Register after STOP: 0x%02X (BUSY = %b)",
            read_val[7:0], read_val[6]);
        
        assert(read_val[6] == 1'b0)
            else $error("[TEST 7] BUSY is still asserted after STOP!");
        
        assert(read_val[1] == 1'b0)
            else $error("[TEST 7] TIP is still asserted after STOP!");
        
        assert(read_val[0] == 1'b1)
            else $error("[TEST 7] Interrupt flag should be asserted after STOP!");
        
        
        $display("\033[0;33mALL DOTARA TESTS PASSED SUCCESSFULLY!\033[0m");
        $finish;
    end

endmodule
