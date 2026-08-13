/* 
 * Wishbone compliant I2S wrapper
 * Organization: Alpha Science Lab
 * May 2026
 */

module bashi_wb_i2s #(
  parameter bit [15:0] CLKDIV        = 16'd4,
  parameter bit [4:0]  SAMPLE_WIDTH  = 5'd16,
  parameter bit [31:0] START_ADDRESS = 32'h0008_5300,
  parameter bit [31:0] SIZE          = 32'h0000_0004

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

  logic [7:0] addr_t;
  logic [31:0] addr = wb.adr - START_ADDRESS;
  logic err = wb.adr < START_ADDRESS 
    || wb.adr >= (START_ADDRESS + SIZE);
  
  assign addr_t = addr[7:0];

  assign wr_en = wb.cyc & wb.stb & wb.we & ~err;
  assign wb.ack = wb.cyc & wb.stb & ~err;
  assign wb.err = wb.cyc & wb.stb & err;
  assign wb.dat_miso = rdata;

  bashi_regs #(
    .SAMPLE_WIDTH(SAMPLE_WIDTH)
  ) regs (
    .clk(clk),
    .rst(rst),

    .wr_en(wr_en),
    .addr(addr_t),
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
