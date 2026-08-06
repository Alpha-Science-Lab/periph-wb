/* Sanity check
 * Linear &&
 * Deterministic
 *
 * Sequence:
 *   Reset
 *   Program prescaler
 *   Program period
 *   Program duty cycles
 *   Enable channels
 *   Enable PWM
 *   Observe outputs
 *   Change duty cycles on-the-fly
 *   Disable a channel
 *   Test inversion
 *   Finish
 * 
 * No classes, no UVM, no randomization
*/

module spondon_wb_pwm_top;

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
    // DUT Connections
    //---------------------------------------------

    wishbone_interface wb();

    logic [15:0] pwm_out;

    spondon_wb_pwm #(
        .START_ADDRESS(32'd0),
        .DEFAULT_PRESCALER(3),
        .DEFAULT_PERIOD(99)
    ) dut (
        .clk(clk),
        .rst(rst),
        .wb(wb),
        .pwm_out(pwm_out)
    );

    //---------------------------------------------
    // Register Addresses
    //---------------------------------------------

    localparam CTRL       = 32'h00 >> 2;
    localparam PRESCALER  = 32'h04 >> 2;
    localparam PERIOD     = 32'h08 >> 2;
    localparam ENABLE     = 32'h0C >> 2;
    localparam INVERT     = 32'h10 >> 2;

    localparam DUTY_BASE  = 32'h14; /* Shifted later \
        for word addressing */

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
    // Main Test
    //---------------------------------------------

    logic [31:0] rd_data;

    initial begin

        //-----------------------------------------
        // Initialize
        //-----------------------------------------
        
        rst = 1;

        wb.adr      = 0;
        wb.sel      = 0;
        wb.dat_mosi = 0;
        wb.cyc      = 0;
        wb.stb      = 0;
        wb.we       = 0;

        repeat (10) @(posedge clk);

        rst = 0;

        $display("\033[0;33mPWM SANITY TEST START\033[0m");

        //-----------------------------------------
        // Configure PWM
        //-----------------------------------------

        $display("Programming prescaler...");
        wb_write(PRESCALER, 32'd9);

        $display("Programming period...");
        wb_write(PERIOD, 32'd99);

        //-----------------------------------------
        // Configure Duty Cycles
        //-----------------------------------------

        $display("Programming duty cycles...");

        wb_write((DUTY_BASE + 0*4) >> 2, 32'd25); // 25%
        wb_write((DUTY_BASE + 1*4) >> 2, 32'd50); // 50%
        wb_write((DUTY_BASE + 2*4) >> 2, 32'd75); // 75%
        wb_write((DUTY_BASE + 3*4) >> 2, 32'd90); // 90%

        //-----------------------------------------
        // Enable channels
        //-----------------------------------------

        $display("Enable CH0-CH3");

        wb_write(ENABLE, 32'h0000_000F);

        //-----------------------------------------
        // Start PWM
        //-----------------------------------------

        $display("Enable PWM");

        wb_write(CTRL, 32'h1);

        //-----------------------------------------
        // Let it run
        //-----------------------------------------

        repeat (3000) @(posedge clk);

        //-----------------------------------------
        // Readback
        //-----------------------------------------

        wb_read(PERIOD, rd_data);
        $display("PERIOD = %0d", rd_data);

        wb_read(PRESCALER, rd_data);
        $display("PRESCALER = %0d", rd_data);

        wb_read((DUTY_BASE + 2*4) >> 2, rd_data);
        $display("DUTY2 = %0d", rd_data);

        //-----------------------------------------
        // Dynamic Duty Update
        //-----------------------------------------

        $display("Changing CH0 duty from 25%% to 80%%");

        wb_write((DUTY_BASE + 0*4) >> 2, 32'd80);

        repeat (3000) @(posedge clk);

        //-----------------------------------------
        // Disable CH1
        //-----------------------------------------

        $display("Disabling CH1");

        wb_write(ENABLE, 32'h0000_000D);

        repeat (2000) @(posedge clk);

        //-----------------------------------------
        // Invert CH2
        //-----------------------------------------

        $display("Invert CH2");

        wb_write(INVERT, 32'h0000_0004);

        repeat (3000) @(posedge clk);

        //-----------------------------------------
        // Produce Error
        //-----------------------------------------

        $display("Invalid address");

        wb_write(32'h5F >> 2, 32'h0);

        @(posedge clk);

        //-----------------------------------------
        // Stop PWM
        //-----------------------------------------

        $display("Disable PWM");

        wb_write(CTRL, 32'h0);

        repeat (100) @(posedge clk);

        //-----------------------------------------
        // Finish
        //-----------------------------------------

        $display("\033[0;33mPWM SANITY TEST FINISH\033[0m");

        $finish;

    end

    //---------------------------------------------
    // Waveform Dump
    //---------------------------------------------

    initial begin
        $dumpfile("tb_spondon_wb_pwm.vcd");
        $dumpvars(0, tb_spondon_wb_pwm);
    end

endmodule
