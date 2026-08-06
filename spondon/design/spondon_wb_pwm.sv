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
    parameter int CHANNELS = 16,
    parameter logic [31:0] DEFAULT_PRESCALER = 32'd49,
    parameter logic [31:0] DEFAULT_PERIOD    = 32'd999
)(
    input  logic clk,
    input  logic rst,

    wishbone_interface.slave wb,

    output logic [CHANNELS-1:0] pwm_out
);

    //---------------------------------------------
    // Register Addresses
    //---------------------------------------------

    localparam logic [7:0] REG_CTRL       = 8'h00;
    localparam logic [7:0] REG_PRESCALER  = 8'h04;
    localparam logic [7:0] REG_PERIOD     = 8'h08;
    localparam logic [7:0] REG_ENABLE     = 8'h0C;
    localparam logic [7:0] REG_INVERT     = 8'h10;
    localparam logic [7:0] REG_DUTY_BASE  = 8'h14;

    //---------------------------------------------
    // Registers
    //---------------------------------------------

    logic ctrl_enable;

    logic [31:0] prescaler_reg;
    logic [31:0] period_reg;

    logic [CHANNELS-1:0] enable_reg;
    logic [CHANNELS-1:0] invert_reg;

    (* ram_style = "distributed" *)
    logic [31:0] duty_reg [CHANNELS-1:0];

    //---------------------------------------------
    // PWM Engine
    //---------------------------------------------

    logic [31:0] prescaler_cnt;
    logic [31:0] pwm_counter;

    logic pwm_tick;

    //---------------------------------------------
    // Address Decode
    //---------------------------------------------

    logic [7:0] addr;

    assign addr = wb.adr[7:0];

    //---------------------------------------------
    // Wishbone ACK
    //---------------------------------------------

    always_ff @(posedge clk) begin
      if (rst)
        wb.ack <= 1'b0;
      else
        wb.ack <= wb.cyc && wb.stb && !wb.ack;
    end

    assign wb.err = 1'b0;

    //---------------------------------------------
    // Register Writes
    //---------------------------------------------

    integer i;

    always_ff @(posedge clk) begin

      if (rst) begin
        ctrl_enable  <= 1'b0;

        prescaler_reg <= DEFAULT_PRESCALER;
        period_reg    <= DEFAULT_PERIOD;

        enable_reg <= '0;
        invert_reg <= '0;

        // for (i = 0; i < CHANNELS; i++) begin
        //     duty_reg[i] <= 32'd0;
        // end
      
      end
      else begin

        if (wb.cyc && wb.stb && wb.we && !wb.ack) begin
          unique case (addr)
            REG_CTRL:
                ctrl_enable <= wb.dat_mosi[0];

            REG_PRESCALER:
                prescaler_reg <= wb.dat_mosi;

            REG_PERIOD:
                period_reg <= wb.dat_mosi;

            REG_ENABLE:
                enable_reg <= wb.dat_mosi[CHANNELS-1:0];

            REG_INVERT:
                invert_reg <= wb.dat_mosi[CHANNELS-1:0];

            default: begin

                if ((addr >= REG_DUTY_BASE) &&
                    (addr < (REG_DUTY_BASE + CHANNELS*4))) begin

                    duty_reg[(addr - REG_DUTY_BASE) >> 2]
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

      unique case (addr)

        REG_CTRL:
            wb.dat_miso = {31'd0, ctrl_enable};

        REG_PRESCALER:
            wb.dat_miso = prescaler_reg;

        REG_PERIOD:
            wb.dat_miso = period_reg;

        REG_ENABLE:
            wb.dat_miso = {{(32-CHANNELS){1'b0}}, enable_reg};

        REG_INVERT:
            wb.dat_miso = {{(32-CHANNELS){1'b0}}, invert_reg};

        default: begin
          if ((addr >= REG_DUTY_BASE) && (addr < (REG_DUTY_BASE + CHANNELS*4)))
            wb.dat_miso = duty_reg[(addr - REG_DUTY_BASE) >> 2];
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

      for (genvar ch = 0; ch < CHANNELS; ch++) begin : gen_pwm

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
