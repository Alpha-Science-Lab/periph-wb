
module proloy_wb_rst_top;

    //---------------------------------------------
    // Clock / Reset
    //---------------------------------------------

    logic clk;
    logic rst;

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end 

    //---------------------------------------------
    // DUT Connections
    //---------------------------------------------

    wishbone_interface wb();

    logic [15:0] rst_out;

    proloy_wb_rst #(
        .ADDRESS(32'd0),
        .SIZE(32'd1)
    ) rst_dut (
        .clk(clk),
        .rst(rst),
        .wb(wb),
        .rst_out(rst_out)
    );

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

        wb_read(32'd0, rd_data);
        $display("Read data: %h", rd_data);
        
        assert(rd_data == 32'hFFFE) 
            else $fatal("Read data mismatch: expected 32'hFFFE, got %h", rd_data);

        //-----------------------------------------
        // Example write to reset register
        //-----------------------------------------

        wb_write(32'd0, 32'hFFF8);

        //-----------------------------------------
        // Example read from reset register
        //-----------------------------------------

        wb_read(32'd0, rd_data);
        $display("Read data: %h", rd_data);

        assert(rd_data == 32'hFFF8) 
            else $fatal("Read data mismatch: expected 32'hFFF8, got %h", rd_data);
        
        #100; $finish;

    end

    //---------------------------------------------
    // Waveform Dump
    //---------------------------------------------

    initial begin
        $dumpfile("tb_proloy_wb_rst.vcd");
        $dumpvars(0, proloy_wb_rst_top);
    end

endmodule
