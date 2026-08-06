// File: bashi_pkg.sv
// Organization: Alpha Science Lab

package bashi_pkg;

    /* address map*/
    localparam logic [7:0] REG_CTRL       = 8'h00;
    localparam logic [7:0] REG_LEFT_CHN   = 8'h04;
    localparam logic [7:0] REG_RIGHT_CHN  = 8'h08;
    localparam logic [7:0] REG_STATUS     = 8'h0C;

endpackage
