
/*
 * Wishbone Compliant Spinlock Peripheral
 * Organization: Alpha Science Lab
 * May 2026
 *
 * Features:
 *  - Single-cycle Wishbone accesses
 *  - 32 spinlocks
 *  - Set on read
 *  - Release via write
 */

module shikol_wb_spinlock #(
    parameter bit [31:0] ADDRESS = 32'h0012_0200,
    parameter bit [31:0] SIZE    = 32'h0000_0020
)(
    input  logic clk,
    input  logic rst,

    wishbone_interface.slave wb
);

    //---------------------------------------------
    // Register Addresses
    //---------------------------------------------

    localparam logic [7:0] REG_LOCK_BASE = 8'h00;

    //---------------------------------------------
    // Registers
    //---------------------------------------------

    logic [31:0] lock_reg;

    //---------------------------------------------
    // Address Decode
    //---------------------------------------------

    logic [7:0] addr_t;
    logic [31:0] addr;
    logic err;

    assign addr = wb.adr - ADDRESS;
    assign err = wb.adr < ADDRESS
      || wb.adr >= (ADDRESS + SIZE);
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
        wb.err <= wb.cyc && wb.stb && err
          && !wb.err;
      end
    end

    //---------------------------------------------
    // Register Writes / Atomic Acquire
    //---------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            lock_reg <= 32'd0;
        end
        else begin
            if (wb.cyc && wb.stb && !err) begin
                if ((addr_t >= REG_LOCK_BASE) &&
                    (addr_t < REG_LOCK_BASE + 8'd32)) begin
                    if (wb.we)
                        lock_reg[addr_t - REG_LOCK_BASE] <= wb.dat_mosi[0]; // Write 0 to release
                    else
                        lock_reg[addr_t - REG_LOCK_BASE] <= 1'b1;
                end
            end
        end
    end

    //---------------------------------------------
    // Register Reads
    //---------------------------------------------

    always_comb begin

        wb.dat_miso = 32'd0;
        if ((addr_t >= REG_LOCK_BASE) && (addr_t < REG_LOCK_BASE + 8'd32))
            wb.dat_miso = {31'd0, lock_reg[addr_t - REG_LOCK_BASE]}; // Return 1 if acquired
    end

endmodule
