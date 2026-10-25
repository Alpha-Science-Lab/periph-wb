/* Sanity check
 * Linear &&
 * Deterministic
 *
 * Sequence:
 *   Reset
 *   Program samples
 *   Enable
 *   
 *   Finish
 * 
 * No classes, no UVM, no randomization
*/

module bashi_wb_i2s_top;

    localparam int CLKDIV       = 10;
    localparam int SAMPLE_WIDTH = 16;
    localparam int FIFO_DEPTH   = 16;

    localparam logic [31:0] REG_CTRL_ADDR  = (32'h00 >> 2);
    localparam logic [31:0] REG_LEFT_ADDR  = (32'h04 >> 2);
    localparam logic [31:0] REG_RIGHT_ADDR = (32'h08 >> 2);
    localparam logic [31:0] REG_STAT_ADDR  = (32'h0C >> 2);

    logic clk;
    logic rst;

    wishbone_interface wb();

    logic i2s_bclk;
    logic i2s_lrclk;
    logic i2s_sdout;
    logic intr;

    bashi_wb_i2s #(
        .START_ADDRESS(32'd0),
        .CLKDIV(CLKDIV),
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),

        .wb(wb),

        .intr(intr),

        .i2s_bclk(i2s_bclk),
        .i2s_lrclk(i2s_lrclk),
        .i2s_sdout(i2s_sdout)
    );

    //----------------------------------------
    // Clock
    //----------------------------------------

    initial begin
        clk = 0;
        forever #20 clk = ~clk; // 25 MHz
    end

    //----------------------------------------
    // Reset
    //----------------------------------------

    initial begin
        rst = 1;

        wb.cyc      = 0;
        wb.stb      = 0;
        wb.we       = 0;
        wb.adr      = 0;
        wb.sel      = 4'hF;
        wb.dat_mosi = 0;

        repeat (10) @(posedge clk);

        rst = 0;
    end

    //----------------------------------------
    // Wishbone Write Task
    //----------------------------------------

    task automatic wb_write(
        input logic [31:0] addr,
        input logic [31:0] data
    );
    begin

        @(posedge clk);

        wb.adr      = addr;
        wb.dat_mosi = data;

        wb.we  = 1'b1;
        wb.cyc = 1'b1;
        wb.stb = 1'b1;

        wait (wb.ack);

        @(posedge clk);

        wb.cyc = 1'b0;
        wb.stb = 1'b0;
        wb.we  = 1'b0;

    end
    endtask

    //----------------------------------------
    // Wishbone Read Task
    //----------------------------------------

    task automatic wb_read(
        input  logic [31:0] addr,
        output logic [31:0] data
    );
    begin

        @(posedge clk);

        wb.adr = addr;
        wb.we  = 1'b0;
        wb.cyc = 1'b1;
        wb.stb = 1'b1;

        wait (wb.ack);
        data = wb.dat_miso;

        @(posedge clk);

        wb.cyc = 1'b0;
        wb.stb = 1'b0;

    end
    endtask

    //----------------------------------------
    // I2S Frame Capture Task
    //----------------------------------------

    task automatic capture_one_frame(
        output logic [SAMPLE_WIDTH-1:0] left_rx,
        output logic [SAMPLE_WIDTH-1:0] right_rx
    );
    begin
        int i;

        left_rx  = '0;
        right_rx = '0;

        for(i = 0; i < SAMPLE_WIDTH; i++) begin
            @(posedge i2s_bclk);
            left_rx = {left_rx[SAMPLE_WIDTH-2:0], i2s_sdout};
        end

        for(i = 0; i < SAMPLE_WIDTH; i++) begin
            @(posedge i2s_bclk);
            right_rx = {right_rx[SAMPLE_WIDTH-2:0], i2s_sdout};
        end
    end
    endtask

    //----------------------------------------
    // Stimulus
    //----------------------------------------

    initial begin
        logic [31:0] status;
        int i;
        logic [SAMPLE_WIDTH-1:0] left_rx;
        logic [SAMPLE_WIDTH-1:0] right_rx;
        logic [SAMPLE_WIDTH-1:0] left_pattern [0:FIFO_DEPTH-1];
        logic [SAMPLE_WIDTH-1:0] right_pattern [0:FIFO_DEPTH-1];

        wait(!rst);

        wb_write(REG_CTRL_ADDR, 32'h0000_0040); // intr_en=1, enable=0

        for(i = 0; i < FIFO_DEPTH; i++) begin
            left_pattern[i]  = 16'h1234 + i;
            right_pattern[i] = 16'hCAFE + i;

            wb_write(REG_LEFT_ADDR, {16'h0000, left_pattern[i]});
            wb_write(REG_RIGHT_ADDR, {16'h0000, right_pattern[i]});
        end

        wb_read(REG_STAT_ADDR, status);

        if(status[8] !== 1'b1) begin
            $error("Expected TX full after FIFO fill (status=%h)", status);
        end

        wb_write(REG_CTRL_ADDR, 32'h0000_0041); // intr_en=1, enable=1

        if(intr !== 1'b0) begin
            $error("Interrupt shouldn't be raised on TX full");
        end

        wait(intr === 1'b0);

        wait(dut.tx.busy); // Let I2S transmission to start

        // Skip startup partial frame; align to a full LRCLK frame boundary
        @(posedge i2s_lrclk);
        @(negedge i2s_lrclk);

        for(i = 0; i < FIFO_DEPTH; i++) begin
            capture_one_frame(left_rx, right_rx);

            if(left_rx !== left_pattern[i]) begin
                $error(
                    "FIFO drain mismatch LEFT at index %0d. Expected %h Got %h",
                    i,
                    left_pattern[i],
                    left_rx
                );
            end

            if(right_rx !== right_pattern[i]) begin
                $error(
                    "FIFO drain mismatch RIGHT at index %0d. Expected %h Got %h",
                    i,
                    right_pattern[i],
                    right_rx
                );
            end
        end

        wait(intr === 1'b1);

        wb_read(REG_STAT_ADDR, status);

        if(status[7] !== 1'b1) begin
            $error("Expected TX empty after draining FIFO (status=%h)", status);
        end

        // Interrupt goes high when FIFO has been popped empty
        // One frame may still be in-flight from shift_reg, so capture two frames
        capture_one_frame(left_rx, right_rx);
        $display(
            "[%0t] Post-empty frame #1 (in-flight): LEFT=%h RIGHT=%h",
            $time,
            left_rx,
            right_rx
        );

        capture_one_frame(left_rx, right_rx);
        $display(
            "[%0t] Post-empty frame #2 (true empty behavior): LEFT=%h RIGHT=%h",
            $time,
            left_rx,
            right_rx
        );

        repeat (100) @(posedge clk);

        $finish;

    end


    initial begin
        $dumpfile("tb_bashi_wb_i2s.vcd");
        $dumpvars(0, bashi_wb_i2s_top);
    end
    

    //----------------------------------------
    // I2S Monitor
    //----------------------------------------

    integer bit_counter;

    initial bit_counter = 0;

    always @(negedge i2s_bclk) begin

        bit_counter++;

        $display(
            "[%0t] LRCLK=%0b SD=%0b Bit=%0d",
            $time,
            i2s_lrclk,
            i2s_sdout,
            bit_counter
        );

        if(bit_counter == (2*SAMPLE_WIDTH))
            bit_counter = 0;

    end

endmodule
