// File: bashi_regs.sv
// Organization: Alpha Science Lab
// I2S registers

module bashi_regs #(
    parameter int unsigned SAMPLE_WIDTH = 16
)(
    input  logic                    clk,
    input  logic                    rst,

    input  logic                    wr_en,
    input  logic [7:0]              addr,
    input  logic [31:0]             wdata,

    input  logic                    busy,

    output logic                    enable,
    output logic [SAMPLE_WIDTH-1:0] left_sample,
    output logic [SAMPLE_WIDTH-1:0] right_sample,

    output logic [31:0]             rdata
);

    import bashi_pkg::*;

    always_ff @(posedge clk) begin

        if(rst) begin
            enable       <= 1'b0;
            left_sample  <= '0;            
            right_sample <= '0;
        end
        else if(wr_en) begin

            case(addr)

                REG_CTRL:
                    enable <= wdata[0];

                REG_LEFT_CHN:
                    left_sample <= wdata[SAMPLE_WIDTH-1:0];

                REG_RIGHT_CHN:
                    right_sample <= wdata[SAMPLE_WIDTH-1:0];

            endcase

        end
    end

    always_comb begin

        rdata = 32'h0;

        case(addr)

            REG_CTRL:
                rdata = {31'd0, enable};

            REG_LEFT_CHN:
                rdata = {{(32-SAMPLE_WIDTH){1'b0}}, left_sample};

            REG_RIGHT_CHN:
                rdata = {{(32-SAMPLE_WIDTH){1'b0}}, right_sample};

            REG_STATUS:
                rdata = {31'd0, busy};

        endcase

    end

endmodule
