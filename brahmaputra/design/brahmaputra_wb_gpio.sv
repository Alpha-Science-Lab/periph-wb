/*
 * Wishbone Compliant GPIO Peripheral
 * Organization: Alpha Science Lab
 *
 * Features:
 *   - 3 GPIO ports
 *   - 16 pins per port
 *   - Programmable GPIO mode
 *   - Per-pin alternate function selection
 *   - UART, I2C, SPI, I2S, PWM and ADC functions
 *   - Single-cycle Wishbone accesses
 *
 * GPIO assignment:
 *
 * GPIOA:
 *   A[1:0]   UART
 *   A[3:2]   I2C
 *   A[7:4]   PWM
 *   A[15:12] SPI0
 *
 * GPIOB:
 *   B[3:0]   SPI1
 *   B[7:4]   PWM
 *   B[11:8]  GPIO
 *   B[15:12] PWM
 *
 * GPIOC:
 *   C[2:0]   I2S
 *   C[7:4]   PWM
 *   C[11:8]  ADC
 *   C[15:12] GPIO
 *
 * Function encoding:
 *
 *   4'h0 ----> GPIO
 *   4'h1 ----> UART
 *   4'h2 ----> I2C
 *   4'h3 ----> SPI
 *   4'h4 ----> I2S
 *   4'h5 ----> PWM
 *   4'h6 ----> ADC
 *
 * GPIO mode encoding:
 *
 *   2'b00 ----> Input
 *   2'b01 ----> Push-pull output
 *   2'b10 ----> Open-drain output
 *   2'b11 ----> Reserved
 *
 * Note:
 *   The physical GPIO ports are exposed as inout signals.
 *   Alternate functions take ownership of a pin whenever
 *   the corresponding function is selected.
 */

module brahmaputra_wb_gpio #(
    parameter bit [31:0] START_ADDRESS = 32'h0008_5600,
    parameter bit [31:0] SIZE          = 32'h0000_0017
)(
    input  logic clk,
    input  logic rst,

    wishbone_interface.slave wb,

    //---------------------------------------------
    // Physical GPIO
    //---------------------------------------------

    inout wire [15:0] gpioa,
    inout wire [15:0] gpiob,
    inout wire [15:0] gpioc,

    //---------------------------------------------
    // UART
    //---------------------------------------------

    input  logic uart_tx,
    output logic uart_rx,

    //---------------------------------------------
    // I2C
    //---------------------------------------------

    input  logic i2c_sda_o,
    input  logic i2c_sda_oe,
    output logic i2c_sda_i,

    input  logic i2c_scl_o,
    input  logic i2c_scl_oe,
    output logic i2c_scl_i,

    //---------------------------------------------
    // SPI0
    //---------------------------------------------

    input  logic spi0_mosi_o,
    input  logic spi0_sck_o,
    input  logic spi0_cs_o,
    output logic spi0_miso_i,

    //---------------------------------------------
    // SPI1
    //---------------------------------------------

    input  logic spi1_mosi_o,
    input  logic spi1_sck_o,
    input  logic spi1_cs_o,
    output logic spi1_miso_i,

    //---------------------------------------------
    // I2S
    //---------------------------------------------

    input  logic i2s_sck_o,
    input  logic i2s_ws_o,
    input  logic i2s_sd_o,
    output logic i2s_sd_i,

    //---------------------------------------------
    // PWM
    //---------------------------------------------

    input logic [15:0] pwm_out,

    //---------------------------------------------
    // ADC
    //---------------------------------------------

    output logic [3:0] adc_in
);

    //---------------------------------------------
    // Function encoding
    //---------------------------------------------

    localparam logic [3:0] FUNC_GPIO = 4'h0;
    localparam logic [3:0] FUNC_UART = 4'h1;
    localparam logic [3:0] FUNC_I2C  = 4'h2;
    localparam logic [3:0] FUNC_SPI  = 4'h3;
    localparam logic [3:0] FUNC_I2S  = 4'h4;
    localparam logic [3:0] FUNC_PWM  = 4'h5;
    localparam logic [3:0] FUNC_ADC  = 4'h6;

    //---------------------------------------------
    // GPIO mode encoding
    //---------------------------------------------

    localparam logic [1:0] MODE_INPUT  = 2'b00;
    localparam logic [1:0] MODE_OUTPUT = 2'b01;
    localparam logic [1:0] MODE_OD     = 2'b10;

    //---------------------------------------------
    // Register addresses
    //---------------------------------------------

    localparam logic [7:0] REGA_DATA   = 8'h00;
    localparam logic [7:0] REGA_OUTPUT = 8'h01;
    localparam logic [7:0] REGA_MODE   = 8'h02;
    localparam logic [7:0] REGA_FUNC0  = 8'h03;
    localparam logic [7:0] REGA_FUNC1  = 8'h04;
    localparam logic [7:0] REGA_FUNC2  = 8'h05;
    localparam logic [7:0] REGA_FUNC3  = 8'h06;

    localparam logic [7:0] REGB_DATA   = 8'h08;
    localparam logic [7:0] REGB_OUTPUT = 8'h09;
    localparam logic [7:0] REGB_MODE   = 8'h0A;
    localparam logic [7:0] REGB_FUNC0  = 8'h0B;
    localparam logic [7:0] REGB_FUNC1  = 8'h0C;
    localparam logic [7:0] REGB_FUNC2  = 8'h0D;
    localparam logic [7:0] REGB_FUNC3  = 8'h0E;

    localparam logic [7:0] REGC_DATA   = 8'h10;
    localparam logic [7:0] REGC_OUTPUT = 8'h11;
    localparam logic [7:0] REGC_MODE   = 8'h12;
    localparam logic [7:0] REGC_FUNC0  = 8'h13;
    localparam logic [7:0] REGC_FUNC1  = 8'h14;
    localparam logic [7:0] REGC_FUNC2  = 8'h15;
    localparam logic [7:0] REGC_FUNC3  = 8'h16;

    //---------------------------------------------
    // Registers
    //---------------------------------------------

    logic [15:0] gpioa_output;
    logic [15:0] gpiob_output;
    logic [15:0] gpioc_output;

    /*
     * Two bits per GPIO pin
     *
     * mode[1:0]   = pin 0
     * mode[3:2]   = pin 1
     * ...
     * mode[31:30] = pin 15
     */
    logic [31:0] gpioa_mode;
    logic [31:0] gpiob_mode;
    logic [31:0] gpioc_mode;

    /*
     * Four bits per GPIO pin
     *
     * func[3:0]   = pin 0
     * func[7:4]   = pin 1
     * ...
     * func[63:60] = pin 15
     */
    logic [63:0] gpioa_func;
    logic [63:0] gpiob_func;
    logic [63:0] gpioc_func;

    //---------------------------------------------
    // Physical input signals
    //---------------------------------------------

    logic [15:0] gpioa_i;
    logic [15:0] gpiob_i;
    logic [15:0] gpioc_i;

    logic [15:0] gpioa_o;
    logic [15:0] gpiob_o;
    logic [15:0] gpioc_o;

    logic [15:0] gpioa_oe;
    logic [15:0] gpiob_oe;
    logic [15:0] gpioc_oe;

    //---------------------------------------------
    // Wishbone address decode
    //---------------------------------------------

    logic [31:0] addr;
    logic [7:0]  addr_t;
    logic        err;

    assign addr  = wb.adr - START_ADDRESS;
    assign addr_t = addr[7:0];

    assign err = (wb.adr < START_ADDRESS) ||
        (wb.adr >= (START_ADDRESS + SIZE));

    //---------------------------------------------
    // Wishbone ACK / ERR
    //---------------------------------------------

    always_ff @(posedge clk) begin

        if (rst) begin
            wb.ack <= 1'b0;
            wb.err <= 1'b0;
        end

        else begin
            wb.ack <= wb.cyc && wb.stb && !wb.ack;
            wb.err <= err;
        end

    end

    //---------------------------------------------
    // Register writes
    //---------------------------------------------

    always_ff @(posedge clk) begin

        if (rst) begin

            gpioa_output <= 16'd0;
            gpiob_output <= 16'd0;
            gpioc_output <= 16'd0;

            gpioa_mode <= {16{MODE_INPUT}};
            gpiob_mode <= {16{MODE_INPUT}};
            gpioc_mode <= {16{MODE_INPUT}};

            gpioa_func <= '0;
            gpiob_func <= '0;
            gpioc_func <= '0;

        end

        else begin

            if (wb.cyc && wb.stb && wb.we && !err) begin

                unique case (addr_t)

                    //---------------------------------
                    // GPIOA
                    //---------------------------------

                    REGA_OUTPUT:
                        gpioa_output <= wb.dat_mosi[15:0];

                    REGA_MODE:
                        gpioa_mode <= wb.dat_mosi;

                    REGA_FUNC0:
                        gpioa_func[15:0] <= wb.dat_mosi;

                    REGA_FUNC1:
                        gpioa_func[31:16] <= wb.dat_mosi;

                    REGA_FUNC2:
                        gpioa_func[47:32] <= wb.dat_mosi;

                    REGA_FUNC3:
                        gpioa_func[63:48] <= wb.dat_mosi;

                    //---------------------------------
                    // GPIOB
                    //---------------------------------

                    REGB_OUTPUT:
                        gpiob_output <= wb.dat_mosi[15:0];

                    REGB_MODE:
                        gpiob_mode <= wb.dat_mosi;

                    REGB_FUNC0:
                        gpiob_func[15:0] <= wb.dat_mosi;

                    REGB_FUNC1:
                        gpiob_func[31:16] <= wb.dat_mosi;

                    REGB_FUNC2:
                        gpiob_func[47:32] <= wb.dat_mosi;

                    REGB_FUNC3:
                        gpiob_func[63:48] <= wb.dat_mosi;

                    //---------------------------------
                    // GPIOC
                    //---------------------------------

                    REGC_OUTPUT:
                        gpioc_output <= wb.dat_mosi[15:0];

                    REGC_MODE:
                        gpioc_mode <= wb.dat_mosi;

                    REGC_FUNC0:
                        gpioc_func[15:0] <= wb.dat_mosi;

                    REGC_FUNC1:
                        gpioc_func[31:16] <= wb.dat_mosi;

                    REGC_FUNC2:
                        gpioc_func[47:32] <= wb.dat_mosi;

                    REGC_FUNC3:
                        gpioc_func[63:48] <= wb.dat_mosi;

                    default: ;

                endcase

            end

        end

    end

    //---------------------------------------------
    // Register reads
    //---------------------------------------------

    always_comb begin

        wb.dat_miso = 32'd0;

        unique case (addr_t)

            //-------------------------------------
            // GPIOA
            //-------------------------------------

            REGA_DATA:
                wb.dat_miso = {16'd0, gpioa_i};

            REGA_OUTPUT:
                wb.dat_miso = {16'd0, gpioa_output};

            REGA_MODE:
                wb.dat_miso = gpioa_mode;

            REGA_FUNC0:
                wb.dat_miso = gpioa_func[15:0];

            REGA_FUNC1:
                wb.dat_miso = gpioa_func[31:16];

            REGA_FUNC2:
                wb.dat_miso = gpioa_func[47:32];

            REGA_FUNC3:
                wb.dat_miso = gpioa_func[63:48];

            //-------------------------------------
            // GPIOB
            //-------------------------------------

            REGB_DATA:
                wb.dat_miso = {16'd0, gpiob_i};

            REGB_OUTPUT:
                wb.dat_miso = {16'd0, gpiob_output};

            REGB_MODE:
                wb.dat_miso = gpiob_mode;

            REGB_FUNC0:
                wb.dat_miso = gpiob_func[15:0];

            REGB_FUNC1:
                wb.dat_miso = gpiob_func[31:16];

            REGB_FUNC2:
                wb.dat_miso = gpiob_func[47:32];

            REGB_FUNC3:
                wb.dat_miso = gpiob_func[63:48];

            //-------------------------------------
            // GPIOC
            //-------------------------------------

            REGC_DATA:
                wb.dat_miso = {16'd0, gpioc_i};

            REGC_OUTPUT:
                wb.dat_miso = {16'd0, gpioc_output};

            REGC_MODE:
                wb.dat_miso = gpioc_mode;

            REGC_FUNC0:
                wb.dat_miso = gpioc_func[15:0];

            REGC_FUNC1:
                wb.dat_miso = gpioc_func[31:16];

            REGC_FUNC2:
                wb.dat_miso = gpioc_func[47:32];

            REGC_FUNC3:
                wb.dat_miso = gpioc_func[63:48];

            default:
                wb.dat_miso = 32'd0;

        endcase

    end

    //---------------------------------------------
    // Physical GPIO inputs
    //---------------------------------------------

    assign gpioa_i = gpioa;
    assign gpiob_i = gpiob;
    assign gpioc_i = gpioc;
    
    //---------------------------------------------
    // GPIOA output / OE mux
    //---------------------------------------------

    always_comb begin

        gpioa_o  = gpioa_output;
        gpioa_oe = 16'd0;

        uart_rx  = 1'b0;

        i2c_sda_i   = 1'b0;
        i2c_scl_i   = 1'b0;
        spi0_miso_i = 1'b0;

        for (int i = 0; i < 16; i++) begin

            case (gpioa_func[i*4 +: 4])

                FUNC_GPIO: begin

                    gpioa_o[i] = gpioa_output[i];

                    case (gpioa_mode[i*2 +: 2])

                        MODE_INPUT: begin
                            gpioa_oe[i] = 1'b0;
                        end

                        MODE_OUTPUT: begin
                            gpioa_oe[i] = 1'b1;
                        end

                        MODE_OD: begin
                            gpioa_oe[i] = gpioa_output[i];
                            gpioa_o[i]  = 1'b0;
                        end

                        default: begin
                            gpioa_oe[i] = 1'b0;
                        end

                    endcase

                end

                //---------------------------------
                // UART
                //---------------------------------

                FUNC_UART: begin

                    if (i == 0) begin
                        gpioa_o[i]  = uart_tx;
                        gpioa_oe[i] = 1'b1;
                    end

                    else if (i == 1) begin
                        gpioa_oe[i] = 1'b0;
                        uart_rx     = gpioa_i[i];
                    end

                    else begin
                        gpioa_oe[i] = 1'b0;
                    end

                end

                //---------------------------------
                // I2C
                //---------------------------------

                FUNC_I2C: begin

                    if (i == 2) begin

                        gpioa_o[i]  = i2c_sda_o;
                        gpioa_oe[i] = i2c_sda_oe;
                        i2c_sda_i   = gpioa_i[i];

                    end

                    else if (i == 3) begin

                        gpioa_o[i]  = i2c_scl_o;
                        gpioa_oe[i] = i2c_scl_oe;
                        i2c_scl_i   = gpioa_i[i];

                    end

                    else begin
                        gpioa_oe[i] = 1'b0;
                    end

                end

                //---------------------------------
                // PWM
                //---------------------------------

                FUNC_PWM: begin

                    if ((i >= 4) && (i <= 7)) begin
                        gpioa_o[i]  = pwm_out[i-4];
                        gpioa_oe[i] = 1'b1;
                    end

                    else begin
                        gpioa_oe[i] = 1'b0;
                    end

                end

                //---------------------------------
                // SPI0
                //---------------------------------

                FUNC_SPI: begin

                    case (i)

                        12: begin
                            gpioa_o[i]  = spi0_mosi_o;
                            gpioa_oe[i] = 1'b1;
                        end

                        13: begin
                            gpioa_o[i]  = spi0_sck_o;
                            gpioa_oe[i] = 1'b1;
                        end

                        14: begin
                            gpioa_o[i]  = spi0_cs_o;
                            gpioa_oe[i] = 1'b1;
                        end

                        15: begin
                            gpioa_oe[i] = 1'b0;
                            spi0_miso_i  = gpioa_i[i];
                        end

                        default: begin
                            gpioa_oe[i] = 1'b0;
                        end

                    endcase

                end

                default: begin
                    gpioa_oe[i] = 1'b0;
                end

            endcase

        end

    end

    //---------------------------------------------
    // GPIOB output / OE mux
    //---------------------------------------------

    always_comb begin

        gpiob_o  = gpiob_output;
        gpiob_oe = 16'd0;

        spi1_miso_i = 1'b0;

        for (int i = 0; i < 16; i++) begin

            case (gpiob_func[i*4 +: 4])

                FUNC_GPIO: begin

                    gpiob_o[i] = gpiob_output[i];

                    case (gpiob_mode[i*2 +: 2])

                        MODE_INPUT:
                            gpiob_oe[i] = 1'b0;

                        MODE_OUTPUT:
                            gpiob_oe[i] = 1'b1;

                        MODE_OD: begin
                            gpiob_oe[i] = gpiob_output[i];
                            gpiob_o[i]  = 1'b0;
                        end

                        default:
                            gpiob_oe[i] = 1'b0;

                    endcase

                end

                //---------------------------------
                // SPI1
                //---------------------------------

                FUNC_SPI: begin

                    case (i)

                        0: begin
                            gpiob_o[i]  = spi1_mosi_o;
                            gpiob_oe[i] = 1'b1;
                        end

                        1: begin
                            gpiob_o[i]  = spi1_sck_o;
                            gpiob_oe[i] = 1'b1;
                        end

                        2: begin
                            gpiob_o[i]  = spi1_cs_o;
                            gpiob_oe[i] = 1'b1;
                        end

                        3: begin
                            gpiob_oe[i] = 1'b0;
                            spi1_miso_i   = gpiob_i[i];
                        end

                        default:
                            gpiob_oe[i] = 1'b0;

                    endcase

                end

                //---------------------------------
                // PWM
                //---------------------------------

                FUNC_PWM: begin

                    if ((i >= 4) && (i <= 7)) begin
                        gpiob_o[i]  = pwm_out[i];
                        gpiob_oe[i] = 1'b1;
                    end

                    else if ((i >= 12) && (i <= 15)) begin
                        gpiob_o[i]  = pwm_out[i-4];
                        gpiob_oe[i] = 1'b1;
                    end

                    else begin
                        gpiob_oe[i] = 1'b0;
                    end

                end

                default: begin
                    gpiob_oe[i] = 1'b0;
                end

            endcase

        end

    end

    //---------------------------------------------
    // GPIOC output / OE mux
    //---------------------------------------------

    always_comb begin

        gpioc_o  = gpioc_output;
        gpioc_oe = 16'd0;

        i2s_sd_i = 1'b0;
        adc_in   = 4'd0;

        for (int i = 0; i < 16; i++) begin

            case (gpioc_func[i*4 +: 4])

                FUNC_GPIO: begin

                    gpioc_o[i] = gpioc_output[i];

                    case (gpioc_mode[i*2 +: 2])

                        MODE_INPUT:
                            gpioc_oe[i] = 1'b0;

                        MODE_OUTPUT:
                            gpioc_oe[i] = 1'b1;

                        MODE_OD: begin
                            gpioc_oe[i] = gpioc_output[i];
                            gpioc_o[i]  = 1'b0;
                        end

                        default:
                            gpioc_oe[i] = 1'b0;

                    endcase

                end

                //---------------------------------
                // I2S
                //---------------------------------

                FUNC_I2S: begin

                    case (i)

                        0: begin
                            gpioc_o[i]  = i2s_sck_o;
                            gpioc_oe[i] = 1'b1;
                        end

                        1: begin
                            gpioc_o[i]  = i2s_ws_o;
                            gpioc_oe[i] = 1'b1;
                        end

                        2: begin
                            gpioc_o[i]  = i2s_sd_o;
                            gpioc_oe[i] = 1'b1;
                            i2s_sd_i    = gpioc_i[i];
                        end

                        default:
                            gpioc_oe[i] = 1'b0;

                    endcase

                end

                //---------------------------------
                // PWM
                //---------------------------------

                FUNC_PWM: begin

                    if ((i >= 4) && (i <= 7)) begin
                        gpioc_o[i]  = pwm_out[i+8];
                        gpioc_oe[i] = 1'b1;
                    end

                    else begin
                        gpioc_oe[i] = 1'b0;
                    end

                end

                //---------------------------------
                // ADC
                //---------------------------------

                FUNC_ADC: begin

                    gpioc_oe[i] = 1'b0;

                    if ((i >= 8) && (i <= 11))
                        adc_in[i-8] = gpioc_i[i];

                end

                default: begin
                    gpioc_oe[i] = 1'b0;
                end

            endcase

        end

    end

    //---------------------------------------------
    // Physical tri-state drivers
    //---------------------------------------------

    genvar pin;

    generate

        for (pin = 0; pin < 16; pin++) begin : gen_gpio_pins

            assign gpioa[pin] =
                gpioa_oe[pin] ? gpioa_o[pin] : 1'bz;

            assign gpiob[pin] =
                gpiob_oe[pin] ? gpiob_o[pin] : 1'bz;

            assign gpioc[pin] =
                gpioc_oe[pin] ? gpioc_o[pin] : 1'bz;

        end

    endgenerate

endmodule
