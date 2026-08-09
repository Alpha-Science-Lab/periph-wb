/*
 * GPIO Sanity Check
 *
 * Linear &&
 * Deterministic
 *
 * Sequence:
 *   - Reset
 *   - Configure GPIOA
 *   - Drive GPIOA
 *   - Read GPIOA
 *   - Configure GPIOB
 *   - Test input
 *   - Test alternate functions
 *   - Test PWM routing
 *   - Test UART routing
 *   - Test ADC input
 *   - Readback registers
 *   - Finish
 *
 * No classes, no UVM, no randomization
 */

module brahmaputra_wb_gpio_top;

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
    // DUT / Wishbone
    //---------------------------------------------

    wishbone_interface wb();

    //---------------------------------------------
    // Physical GPIO
    //---------------------------------------------

    tri [15:0] gpioa;
    tri [15:0] gpiob;
    tri [15:0] gpioc;

    //---------------------------------------------
    // External GPIO drivers
    //---------------------------------------------

    logic [15:0] gpioa_ext;
    logic [15:0] gpiob_ext;
    logic [15:0] gpioc_ext;

    logic [15:0] gpioa_ext_oe;
    logic [15:0] gpiob_ext_oe;
    logic [15:0] gpioc_ext_oe;

    assign gpioa = gpioa_ext_oe ?
        gpioa_ext : 16'bz;
    assign gpiob = gpiob_ext_oe ? 
        gpiob_ext : 16'bz;
    assign gpioc = gpioc_ext_oe ? 
        gpioc_ext : 16'bz;

    //---------------------------------------------
    // Alternate function signals
    //---------------------------------------------

    logic        uart_tx;
    logic        uart_rx;

    logic        i2c_sda_o;
    logic        i2c_sda_oe;
    logic        i2c_sda_i;

    logic        i2c_scl_o;
    logic        i2c_scl_oe;
    logic        i2c_scl_i;

    logic        spi_mosi_o;
    logic        spi_sck_o;
    logic        spi_cs_o;
    logic        spi_miso_i;

    logic        i2s_sck_o;
    logic        i2s_ws_o;
    logic        i2s_sd_o;
    logic        i2s_sd_oe;
    logic        i2s_sd_i;

    logic [15:0] pwm_out;

    logic [3:0] adc_in;

    //---------------------------------------------
    // DUT
    //---------------------------------------------

    brahmaputra_wb_gpio #(
        .START_ADDRESS(32'd0)
    ) dut (
        .clk(clk),
        .rst(rst),
        .wb(wb),

        .gpioa(gpioa),
        .gpiob(gpiob),
        .gpioc(gpioc),

        .uart_tx(uart_tx),
        .uart_rx(uart_rx),

        .i2c_sda_o(i2c_sda_o),
        .i2c_sda_oe(i2c_sda_oe),
        .i2c_sda_i(i2c_sda_i),

        .i2c_scl_o(i2c_scl_o),
        .i2c_scl_oe(i2c_scl_oe),
        .i2c_scl_i(i2c_scl_i),

        .spi_mosi_o(spi_mosi_o),
        .spi_sck_o(spi_sck_o),
        .spi_cs_o(spi_cs_o),
        .spi_miso_i(spi_miso_i),

        .i2s_sck_o(i2s_sck_o),
        .i2s_ws_o(i2s_ws_o),
        .i2s_sd_o(i2s_sd_o),
        .i2s_sd_oe(i2s_sd_oe),
        .i2s_sd_i(i2s_sd_i),

        .pwm_out(pwm_out),

        .adc_in(adc_in)
    );

    //---------------------------------------------
    // Register Addresses
    //---------------------------------------------

    localparam GPIOA_DATA   = 32'h00;
    localparam GPIOA_OUTPUT = 32'h01;
    localparam GPIOA_MODE   = 32'h02;
    localparam GPIOA_FUNC0  = 32'h03;
    localparam GPIOA_FUNC1  = 32'h04;
    localparam GPIOA_FUNC2  = 32'h05;
    localparam GPIOA_FUNC3  = 32'h06;

    localparam GPIOB_DATA   = 32'h08;
    localparam GPIOB_OUTPUT = 32'h09;
    localparam GPIOB_MODE   = 32'h0A;
    localparam GPIOB_FUNC0  = 32'h0B;
    localparam GPIOB_FUNC1  = 32'h0C;
    localparam GPIOB_FUNC2  = 32'h0D;
    localparam GPIOB_FUNC3  = 32'h0E;

    localparam GPIOC_DATA   = 32'h10;
    localparam GPIOC_OUTPUT = 32'h11;
    localparam GPIOC_MODE   = 32'h12;
    localparam GPIOC_FUNC0  = 32'h13;
    localparam GPIOC_FUNC1  = 32'h14;
    localparam GPIOC_FUNC2  = 32'h15;
    localparam GPIOC_FUNC3  = 32'h16;

    //---------------------------------------------
    // Function encoding
    //---------------------------------------------

    localparam FUNC_GPIO = 4'h0;
    localparam FUNC_UART = 4'h1;
    localparam FUNC_I2C  = 4'h2;
    localparam FUNC_SPI  = 4'h3;
    localparam FUNC_I2S  = 4'h4;
    localparam FUNC_PWM  = 4'h5;
    localparam FUNC_ADC  = 4'h6;

    //---------------------------------------------
    // GPIO mode encoding
    //---------------------------------------------

    localparam MODE_INPUT  = 2'b00;
    localparam MODE_OUTPUT = 2'b01;
    localparam MODE_OD     = 2'b10;

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

        gpioa_ext    = 16'h0000;
        gpiob_ext    = 16'h0000;
        gpioc_ext    = 16'h0000;

        gpioa_ext_oe = 16'h0000;
        gpiob_ext_oe = 16'h0000;
        gpioc_ext_oe = 16'h0000;

        uart_tx = 1'b0;

        i2c_sda_o  = 1'b0;
        i2c_sda_oe = 1'b0;

        i2c_scl_o  = 1'b0;
        i2c_scl_oe = 1'b0;

        spi_mosi_o = 1'b0;
        spi_sck_o  = 1'b0;
        spi_cs_o   = 1'b0;

        i2s_sck_o = 1'b0;
        i2s_ws_o  = 1'b0;
        i2s_sd_o  = 1'b0;
        i2s_sd_oe = 1'b0;

        pwm_out = 16'h0000;

        repeat (10) @(posedge clk);

        rst = 0;

        $display("\033[0;33mGPIO SANITY TEST START\033[0m");

        //-----------------------------------------
        // GPIOA Output Test
        //-----------------------------------------

        $display("Configuring GPIOA as outputs...");

        wb_write(GPIOA_MODE, {16{MODE_OUTPUT}});

        $display("Driving GPIOA = 0xA5A5");

        wb_write(GPIOA_OUTPUT, 32'h0000_A5A5);

        repeat (5) @(posedge clk);

        assert (gpioa === 16'hA5A5)
            else $error("GPIOA output mismatch: expected A5A5, got %h", gpioa);

        //-----------------------------------------
        // GPIOA output change
        //-----------------------------------------

        $display("Driving GPIOA = 0x5A5A");

        wb_write(GPIOA_OUTPUT, 32'h0000_5A5A);

        repeat (5) @(posedge clk);

        assert (gpioa === 16'h5A5A)
            else $error("GPIOA output mismatch: expected 5A5A, got %h", gpioa);

        //-----------------------------------------
        // GPIOA Input Test
        //-----------------------------------------

        $display("Configuring GPIOA as inputs...");

        wb_write(GPIOA_MODE, {16{MODE_INPUT}});

        gpioa_ext    = 16'h3CC3;
        gpioa_ext_oe = 16'hFFFF;

        repeat (5) @(posedge clk);

        wb_read(GPIOA_DATA, rd_data);

        assert (rd_data[15:0] === 16'h3CC3)
            else $error("GPIOA input mismatch: expected 3CC3, got %h",
                        rd_data[15:0]);

        gpioa_ext_oe = 16'h0000;

        //-----------------------------------------
        // UART Alternate Function
        //-----------------------------------------

        $display("Testing UART alternate function...");

        /*
         * GPIOA[0] = UART_TX
         * GPIOA[1] = UART_RX
         */

        wb_write(GPIOA_FUNC0,
                 (FUNC_UART << 4) |
                 FUNC_UART);

        uart_tx = 1'b1;

        repeat (5) @(posedge clk);

        assert (gpioa[0] === 1'b1)
            else $error("UART TX mux failed");

        gpioa_ext    = 16'h0002;
        gpioa_ext_oe = 16'h0002;

        #1;

        assert (uart_rx === 1'b1)
            else $error("UART RX mux failed");

        gpioa_ext_oe = 16'h0000;

        //-----------------------------------------
        // I2C Alternate Function
        //-----------------------------------------

        $display("Testing I2C alternate function...");

        /*
         * GPIOA[2] = SDA
         * GPIOA[3] = SCL
         */

        wb_write(GPIOA_FUNC0,
                 (FUNC_I2C << 12) |
                 (FUNC_I2C << 8)  |
                 (FUNC_UART << 4) |
                 FUNC_UART);

        i2c_sda_o  = 1'b0;
        i2c_sda_oe = 1'b1;

        i2c_scl_o  = 1'b0;
        i2c_scl_oe = 1'b1;

        repeat (5) @(posedge clk);

        assert (gpioa[2] === 1'b0)
            else $error("I2C SDA mux failed");

        assert (gpioa[3] === 1'b0)
            else $error("I2C SCL mux failed");
        
        gpioa_ext    = 16'h000C;
        gpioa_ext_oe = 16'h000C;

        #1;

        assert (i2c_sda_i === 1'b1)
            else $error("I2C SDA input mux failed");

        assert (i2c_scl_i === 1'b1)
            else $error("I2C SCL input mux failed");        

        //-----------------------------------------
        // PWM Alternate Function
        //-----------------------------------------

        $display("Testing PWM alternate function...");

        /*
         * GPIOA[7:4] = PWM[3:0]
         */

        wb_write(GPIOA_FUNC1,
                 (FUNC_PWM << 12) |
                 (FUNC_PWM << 8)  |
                 (FUNC_PWM << 4)  |
                 FUNC_PWM);

        pwm_out[3:0] = 4'b1010;

        repeat (5) @(posedge clk);

        assert (gpioa[7:4] === 4'b1010)
            else $error("PWM mux failed: expected 1010, got %b",
                        gpioa[7:4]);

        //-----------------------------------------
        // SPI Alternate Function
        //-----------------------------------------

        $display("Testing SPI alternate function...");

        /*
         * GPIOB[3:0] = SPI
         */

        wb_write(GPIOB_FUNC0,
                 (FUNC_SPI << 12) |
                 (FUNC_SPI << 8)  |
                 (FUNC_SPI << 4)  |
                 FUNC_SPI);

        spi_mosi_o = 1'b1;
        spi_sck_o  = 1'b0;
        spi_cs_o   = 1'b1;

        gpiob_ext    = 16'h0008;
        gpiob_ext_oe = 16'h0008;

        #1;

        assert (gpiob[0] === spi_mosi_o)
            else $error("SPI MOSI mux failed");

        assert (gpiob[1] === spi_sck_o)
            else $error("SPI SCK mux failed");

        assert (gpiob[2] === spi_cs_o)
            else $error("SPI CS mux failed");

        assert (spi_miso_i === 1'b1)
            else $error("SPI MISO mux failed");

        gpiob_ext_oe = 16'h0000;

        //-----------------------------------------
        // ADC Alternate Function
        //-----------------------------------------

        $display("Testing ADC alternate function...");

        /*
         * GPIOC[11:8] = ADC[3:0]
         */

        wb_write(GPIOC_FUNC2,
                 (FUNC_ADC << 12) |
                 (FUNC_ADC << 8)  |
                 (FUNC_ADC << 4)  |
                 FUNC_ADC);

        gpioc_ext    = 16'h0F00;
        gpioc_ext_oe = 16'h0F00;

        #1;

        assert (adc_in === 4'b1111)
            else $error("ADC mux failed: expected 1111, got %b", adc_in);

        gpioc_ext_oe = 16'h0000;

        //-----------------------------------------
        // Readback
        //-----------------------------------------

        $display("Reading GPIO registers...");

        wb_read(GPIOA_OUTPUT, rd_data);

        assert (rd_data[15:0] === 16'h5A5A)
            else $error(
                "GPIOA_OUTPUT readback failed: expected 0x5A5A, got 0x%04h",
                rd_data[15:0]
            );

        wb_read(GPIOA_MODE, rd_data);

        assert (rd_data === 32'h0)
            else $error(
                "GPIOA_MODE readback failed: expected 0x0, got 0x%08h",
                rd_data
            );

        wb_read(GPIOA_FUNC0, rd_data);

        assert (rd_data[15:0] === {
            FUNC_I2C,
            FUNC_I2C,
            FUNC_UART,
            FUNC_UART
        }) else $error (
                "GPIOA_FUNC0 readback failed: got 0x%08h",
                rd_data
            );

        wb_read(GPIOB_FUNC0, rd_data);

        assert (rd_data[15:0] === {
            FUNC_SPI,
            FUNC_SPI,
            FUNC_SPI,
            FUNC_SPI
        }) else $error (
                "GPIOB_FUNC0 readback failed: got 0x%08h",
                rd_data
            );

        wb_read(GPIOC_FUNC2, rd_data);

        assert (rd_data[15:0] === {
            FUNC_ADC,
            FUNC_ADC,
            FUNC_ADC,
            FUNC_ADC
        }) else $error (
                "GPIOC_FUNC2 readback failed: got 0x%08h",
                rd_data
            );

        //-----------------------------------------
        // Invalid address
        //-----------------------------------------

        $display("Testing invalid address...");

        wb_write(32'h5F, 32'hDEAD_BEEF);

        assert (wb.err)
            else $error("Invalid address did not generate WB ERR");

        //-----------------------------------------
        // Finish
        //-----------------------------------------

        repeat (20) @(posedge clk);

        $display("\033[0;33mGPIO SANITY TEST FINISH\033[0m");

        $finish;

    end

    //---------------------------------------------
    // Waveform Dump
    //---------------------------------------------

    initial begin
        $dumpfile("tb_brahmaputra_wb_gpio.vcd");
        $dumpvars(0, brahmaputra_wb_gpio_top);
    end

endmodule
