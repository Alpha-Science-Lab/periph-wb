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

    logic clk;
    logic rst;

    wishbone_interface wb();

    logic i2s_bclk;
    logic i2s_lrclk;
    logic i2s_sdout;

    bashi_wb_i2s #(
        .START_ADDRESS(32'd0),
        .CLKDIV(CLKDIV),
        .SAMPLE_WIDTH(SAMPLE_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),

        .wb(wb),

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
    // Stimulus
    //----------------------------------------

    initial begin

        wait(!rst);

        $display("[%0t] Programming samples", $time);

        wb_write(32'h04 >> 2, 32'h0000_A55A); // LEFT
        wb_write(32'h08 >> 2, 32'h0000_3CC3); // RIGHT

        wb_write(32'h00 >> 2, 32'h0000_0001); // ENABLE

        repeat (1000) @(posedge clk);

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

    //----------------------------------------
    // Frame checker
    //----------------------------------------


    logic [2*SAMPLE_WIDTH-1:0] frame_rx;
    integer bit_count;

    localparam logic [SAMPLE_WIDTH-1:0] LEFT_EXPECTED  = 16'hA55A;
    localparam logic [SAMPLE_WIDTH-1:0] RIGHT_EXPECTED = 16'h3CC3;

    initial begin
        frame_rx  = '0;
        bit_count = 0;
    end

    always @(posedge i2s_bclk) begin

        frame_rx = {
            frame_rx[2*SAMPLE_WIDTH-2:0],
            i2s_sdout
        };

        bit_count = bit_count + 1;

        if(bit_count == (2*SAMPLE_WIDTH-1)) begin

            logic [SAMPLE_WIDTH-1:0] left_rx;
            logic [SAMPLE_WIDTH-1:0] right_rx;

            left_rx  = frame_rx[2*SAMPLE_WIDTH-1:SAMPLE_WIDTH];
            right_rx = frame_rx[SAMPLE_WIDTH-1:0];

            $display(
                "[%0t] Frame Received: LEFT=%h RIGHT=%h",
                $time,
                left_rx,
                right_rx
            );

            if(left_rx !== LEFT_EXPECTED) begin
                $error(
                    "LEFT mismatch. Expected %h Got %h",
                    LEFT_EXPECTED,
                    left_rx
                );
            end

            if(right_rx !== RIGHT_EXPECTED) begin
                $error(
                    "RIGHT mismatch. Expected %h Got %h",
                    RIGHT_EXPECTED,
                    right_rx
                );
            end

            bit_count = 0;

        end

    end        

endmodule
