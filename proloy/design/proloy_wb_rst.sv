/* File: proloy_wb_rst.sv
 * Wishbone mapped reset controller
 * Organization: Alpha Science Lab
 * October 2026
 */

 module proloy_wb_rst #(
    parameter bit [31:0] ADDRESS,
    parameter bit [31:0] SIZE = 1
) (
    input logic clk,
    input logic rst,

    wishbone_interface.slave wb,

    output logic [15:0] rst_out
);

    logic [15:0] reset_reg;

    logic wb_access;
    assign wb_access = (wb.cyc && wb.stb && wb.ack == 0 && wb.err == 0) &&
                       (wb.adr >= ADDRESS && wb.adr < ADDRESS + SIZE);

    logic [1:0] wb_write_sel;
    assign wb_write_sel = (wb_access && wb.we) ? wb.sel[1:0] : 0;

    always_ff @(posedge clk) begin
        if (rst) begin
            reset_reg <= 16'hFFFE;
        end
        else begin
            if (wb_write_sel[0]) begin 
                reset_reg[7:0] <= wb.dat_mosi[7:0]; 
            end
            if (wb_write_sel[1]) begin 
                reset_reg[15:8] <= wb.dat_mosi[15:8]; 
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            wb.ack      <= 0;
            wb.err      <= 0;
            wb.dat_miso <= 0;
        end
        else begin
            wb.ack      <= 0;
            wb.err      <= 0;
            wb.dat_miso <= 0;

            if (wb.cyc && wb.stb && wb.ack == 0 && wb.err == 0) begin
                if (wb.adr >= ADDRESS && wb.adr < ADDRESS + SIZE) begin
                    wb.ack <= 1;
                    wb.err <= 0;

                    if (wb.we == 0) begin
                        wb.dat_miso <= {16'h0, reset_reg};
                    end
                end
                else begin
                    wb.ack <= 0;
                    wb.err <= 1;
                end
            end
        end
    end

    assign rst_out = reset_reg;

endmodule
