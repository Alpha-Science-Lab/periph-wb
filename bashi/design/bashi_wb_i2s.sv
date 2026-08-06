/* 
 * Wishbone compliant I2S wrapper
 * Organization: Alpha Science Lab
 * May 2026
 */

module bashi_wb_i2s #(
  parameter int unsigned CLKDIV = 4,
  parameter int unsigned SAMPLE_WIDTH = 16
)(
  input logic              clk,
  input logic              rst,

  wishbone_interface.slave wb,

  output logic             i2s_bclk,
  output logic             i2s_lrclk,
  output logic             i2s_sdout
);
    
  logic wr_en; /* derive from wb*/
  logic [31:0] rdata;

  logic enable; /* get from CTRL reg*/
  logic busy;
  logic [SAMPLE_WIDTH-1:0] left_sample;
  logic [SAMPLE_WIDTH-1:0] right_sample;

  assign wr_en = wb.cyc & wb.stb & wb.we;
  assign wb.ack = wb.cyc & wb.stb;
  assign wb.err = 1'b0;
  assign wb.dat_miso = rdata;

  bashi_regs #(
    .SAMPLE_WIDTH(SAMPLE_WIDTH)
  ) regs (
    .clk(clk),
    .rst(rst),

    .wr_en(wr_en),
    .addr(wb.adr[7:0]),
    .wdata(wb.dat_mosi),

    .busy(busy),

    .enable(enable),
    .left_sample(left_sample),
    .right_sample(right_sample),

    .rdata(rdata)
  );

  bashi_i2s_tx #(
    .CLKDIV(CLKDIV),
    .SAMPLE_WIDTH(SAMPLE_WIDTH)
  ) tx (
    .clk(clk),
    .rst(rst),

    .enable(enable),
    .left_sample(left_sample),
    .right_sample(right_sample),

    .bclk(i2s_bclk),
    .lrclk(i2s_lrclk),
    .sdout(i2s_sdout),

    .busy(busy)
  );

endmodule

/* Named after the Bengali instrument 'bashi' the side-blown bamboo flute */

/* Just as a flute carries melodies through breath and timing,
 * 'bashi' streams digital audio through clean synchronization,
 * minimal control overhead, and graceful interoperability
 * between digital companions on the bus */
