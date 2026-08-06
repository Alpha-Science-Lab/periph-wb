// File: bashi_i2s_tx.sv
// Organization: Alpha Science Lab
// I2S transmitter engine

module bashi_i2s_tx #(
    parameter int unsigned CLKDIV = 4,
    parameter int unsigned SAMPLE_WIDTH = 16
)(
    input  logic                    clk,
    input  logic                    rst,

    input  logic                    enable,
    input  logic [SAMPLE_WIDTH-1:0] left_sample,
    input  logic [SAMPLE_WIDTH-1:0] right_sample,

    output logic                    bclk,
    output logic                    lrclk,
    output logic                    sdout,

    output logic                    busy
);

    localparam int DIV_WIDTH = $clog2(CLKDIV + 1);
    localparam int FRAME_BITS = 2 * SAMPLE_WIDTH;
    localparam int BIT_CNT_WIDTH = $clog2(FRAME_BITS + 1);

    logic [DIV_WIDTH-1:0] divcnt;
    logic [2*SAMPLE_WIDTH-1:0] shift_reg;
    logic [BIT_CNT_WIDTH-1:0] bit_cnt;

    logic bclk_tick;

    always_ff @(posedge clk) begin

        if(rst) begin

            divcnt    <= '0;
            bclk      <= 1'b0;
            bclk_tick <= 1'b0;

        end else begin

            bclk_tick     <= 1'b0;

            if(divcnt == CLKDIV) begin
                divcnt    <= 0;
                bclk      <= ~bclk;
                bclk_tick <= 1'b1;
            
            end else begin 
                divcnt <= divcnt + 1'b1;
            end

        end

    end

    always_ff @(posedge clk) begin

        if(rst) begin

            shift_reg <= '0;
            bit_cnt   <= '0;

            lrclk <= 1'b0;
            sdout <= 1'b0;
            busy  <= 1'b0;

        end
        else if(enable && bclk_tick && ~bclk) begin

            if(bit_cnt == 0) begin

                shift_reg <= {left_sample,right_sample};

                bit_cnt <= FRAME_BITS;

                busy <= 1'b1;

                lrclk <= 1'b0;

            end
            else begin

                sdout <= shift_reg[FRAME_BITS-1];

                shift_reg <= {
                    shift_reg[FRAME_BITS-2:0],
                    1'b0
                };

                bit_cnt <= bit_cnt - 1'b1;

                if(bit_cnt == SAMPLE_WIDTH)
                    lrclk <= 1'b1;

                if(bit_cnt == 1)
                    busy <= 1'b0;

            end

        end
        else if(!enable) begin

            busy <= 1'b0;
            bit_cnt <= '0;
            lrclk <= 1'b0;
        end
        
    end

endmodule
