/*
 * Wishbone Compliant PWM Peripheral
 * Organization: Alpha Science Lab
 * May 2026
 *
 * Features:
 *  - 16 programmable PWM channels
 *  - Common programmable period
 *  - Independent duty cycle per channel
 *  - Per-channel enable
 *  - Per-channel polarity inversion
 *  - Single-cycle Wishbone accesses
 */

module spondon_wb_pwm #(
    parameter bit [31:0] START_ADDRESS     = 32'h0008_5100,
    parameter bit [31:0] SIZE              = 32'h0000_0015,
    parameter bit [15:0] DEFAULT_PRESCALER = 16'd7,
    parameter bit [15:0] DEFAULT_PERIOD    = 16'd999
)(
    input  logic clk,
    input  logic rst,

    wishbone_interface.slave wb,

    output logic [15:0] pwm_out
);

    //---------------------------------------------
    // Register Addresses
    //---------------------------------------------

    localparam logic [7:0] REG_CTRL       = 8'h00;
    localparam logic [7:0] REG_PRESCALER  = 8'h01;
    localparam logic [7:0] REG_PERIOD     = 8'h02;
    localparam logic [7:0] REG_ENABLE     = 8'h03;
    localparam logic [7:0] REG_INVERT     = 8'h04;
    localparam logic [7:0] REG_DUTY_BASE  = 8'h05;

    //---------------------------------------------
    // Registers
    //---------------------------------------------

    logic ctrl_enable;

    logic [15:0] prescaler_reg;
    logic [15:0] period_reg;

    logic [15:0] enable_reg;
    logic [15:0] invert_reg;

    (* ram_style = "distributed" *)
    logic [31:0] duty_reg [15:0];

    //---------------------------------------------
    // PWM Engine
    //---------------------------------------------

    logic [31:0] prescaler_cnt;
    logic [31:0] pwm_counter;

    logic pwm_tick;

    //---------------------------------------------
    // Address Decode
    //---------------------------------------------

    logic [7:0] addr_t;
    logic [31:0] addr;
    logic err;

    assign addr = wb.adr - START_ADDRESS;
    assign err = wb.adr < START_ADDRESS 
      || wb.adr >= (START_ADDRESS + SIZE);
    assign addr_t = addr[7:0];

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
    // Register Writes
    //---------------------------------------------

    // integer i;

    always_ff @(posedge clk) begin

      if (rst) begin
        ctrl_enable  <= 1'b0;

        prescaler_reg <= DEFAULT_PRESCALER;
        period_reg    <= DEFAULT_PERIOD;

        enable_reg <= '0;
        invert_reg <= '0;

        // for (i = 0; i < 16; i++) begin
        //     duty_reg[i] <= 32'd0;
        // end
      
      end
      else begin

        if (wb.cyc && wb.stb && wb.we && !err) begin
          unique case (addr_t)
            REG_CTRL:
                ctrl_enable <= wb.dat_mosi[0];

            REG_PRESCALER:
                prescaler_reg <= wb.dat_mosi[15:0];

            REG_PERIOD:
                period_reg <= wb.dat_mosi[15:0];

            REG_ENABLE:
                enable_reg <= wb.dat_mosi[15:0];

            REG_INVERT:
                invert_reg <= wb.dat_mosi[15:0];

            default: begin

                if ((addr_t >= REG_DUTY_BASE) &&
                    (addr_t < REG_DUTY_BASE + 8'd16)) begin

                    duty_reg[addr_t - REG_DUTY_BASE]
                        <= wb.dat_mosi;
                end
              
            end

          endcase
        end

      end
    end

    //---------------------------------------------
    // Register Reads
    //---------------------------------------------

    always_comb begin

      wb.dat_miso = 32'd0;

      unique case (addr_t)

        REG_CTRL:
            wb.dat_miso = {31'd0, ctrl_enable};

        REG_PRESCALER:
            wb.dat_miso = prescaler_reg;

        REG_PERIOD:
            wb.dat_miso = period_reg;

        REG_ENABLE:
            wb.dat_miso = {16'b0, enable_reg};

        REG_INVERT:
            wb.dat_miso = {16'b0, invert_reg};

        default: begin
          if ((addr_t >= REG_DUTY_BASE) && (addr_t < REG_DUTY_BASE + 8'd16))
            wb.dat_miso = duty_reg[addr_t - REG_DUTY_BASE];
        end

      endcase

    end

    //---------------------------------------------
    // Prescaler
    //---------------------------------------------

    always_ff @(posedge clk) begin

      if (rst) begin

        prescaler_cnt <= 32'd0;
        pwm_tick      <= 1'b0;
      end
      else begin

        pwm_tick <= 1'b0;

        if (ctrl_enable) begin

          if (prescaler_cnt >= prescaler_reg) begin

            prescaler_cnt <= 32'd0;
            pwm_tick      <= 1'b1;
          end

          else begin
            prescaler_cnt <= prescaler_cnt + 32'd1;
            // pwm_tick      <= 1'b0;
          end

        end

        else prescaler_cnt <= 32'd0;            

      end

    end

    //---------------------------------------------
    // PWM Counter
    //---------------------------------------------

    always_ff @(posedge clk) begin

        if (rst) pwm_counter <= 32'd0;

        else if (ctrl_enable && pwm_tick) begin

          if (pwm_counter >= period_reg)
            pwm_counter <= 32'd0;
          else
            pwm_counter <= pwm_counter + 32'd1;
          
        end
        
        else if (!ctrl_enable) 
          pwm_counter <= 32'd0;
    end

    //---------------------------------------------
    // PWM Outputs
    //---------------------------------------------

    generate

      for (genvar ch = 0; ch < 16; ch++) begin : gen_pwm

        logic pwm_raw;

        always_comb begin

          pwm_raw = (pwm_counter < duty_reg[ch]);

          if (!ctrl_enable)
            pwm_out[ch] = 1'b0;

          else if (!enable_reg[ch])
            pwm_out[ch] = 1'b0;

          else if (invert_reg[ch])
            pwm_out[ch] = ~pwm_raw;

          else
            pwm_out[ch] = pwm_raw;

        end

      end

    endgenerate

endmodule

/* Memorty mapped peripherals for Swadheen-SoC*/
