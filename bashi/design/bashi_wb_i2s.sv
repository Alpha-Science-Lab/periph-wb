/* 
 * Wishbone compliant I2S wrapper
 * Organization: Alpha Science Lab
 * May 2026
 */

module bashi_wb_i2s #(
  parameter bit [15:0] CLKDIV        = 16'd4,
  parameter bit [4:0]  SAMPLE_WIDTH  = 5'd16,
  parameter int unsigned FIFO_DEPTH  = 16,
  parameter bit [31:0] START_ADDRESS = 32'h0008_5300,
  parameter bit [31:0] SIZE          = 32'h0000_0004

)(
  input logic              clk,
  input logic              rst,

  wishbone_interface.slave wb,

  output logic             intr,

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
  logic fifo_pop;

  logic [7:0] addr_t;
  logic [31:0] addr = wb.adr - START_ADDRESS;
  logic err = wb.adr < START_ADDRESS 
    || wb.adr >= (START_ADDRESS + SIZE);
  
  assign addr_t = addr[7:0];

  assign wr_en = wb.cyc & wb.stb & wb.we & ~err;
  assign wb.dat_miso = rdata;

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

  bashi_regs #(
    .SAMPLE_WIDTH(SAMPLE_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH)
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
    .fifo_pop(fifo_pop),
    .intr(intr),

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

    .busy(busy),
    .fifo_pop(fifo_pop)
  );

endmodule

/* Named after the Bengali instrument 'bashi' the side-blown bamboo flute */

/* Just as a flute carries melodies through breath and timing,
 * 'bashi' streams digital audio through clean synchronization,
 * minimal control overhead, and graceful interoperability
 * between digital companions on the bus */

module bashi_regs #(
  parameter int unsigned SAMPLE_WIDTH = 16,
  parameter int unsigned FIFO_DEPTH   = 16
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
  input  logic                    fifo_pop,

  output logic                    intr,

  output logic [31:0]             rdata
);

  localparam logic [7:0] REG_CTRL      = 8'h0;
  localparam logic [7:0] REG_LEFT_CHN  = 8'h1;
  localparam logic [7:0] REG_RIGHT_CHN = 8'h2;
  localparam logic [7:0] REG_STATUS    = 8'h3;

  localparam int FIFO_PTR_W = (FIFO_DEPTH > 1) ? $clog2(FIFO_DEPTH) : 1;

  logic [2*SAMPLE_WIDTH-1:0] tx_fifo [0:FIFO_DEPTH-1];
  logic [FIFO_PTR_W-1:0] tx_wptr;
  logic [FIFO_PTR_W-1:0] tx_rptr;
  logic [FIFO_PTR_W:0] tx_cnt;
  logic [SAMPLE_WIDTH-1:0] left_shadow;

  logic tx_push;
  logic tx_empty;
  logic tx_full;
  logic intr_en;

  assign tx_empty = (tx_cnt == 0);
  assign tx_full  = (tx_cnt == (FIFO_PTR_W+1)'(FIFO_DEPTH));

  assign tx_push = wr_en
    && (addr == REG_RIGHT_CHN)
    && !tx_full;

  assign intr = tx_empty && intr_en;

  always_ff @(posedge clk) begin

    if(rst) begin
      enable       <= 1'b0;
      intr_en      <= 1'b0;
      left_sample  <= '0;
      right_sample <= '0;
      left_shadow  <= '0;
      tx_wptr      <= '0;
      tx_rptr      <= '0;
      tx_cnt       <= '0;
    end
    else begin

      if(wr_en) begin

        case(addr)

          REG_CTRL:
            begin
              enable  <= wdata[0];
              intr_en <= wdata[6];
            end

          REG_LEFT_CHN: begin
            left_shadow <= wdata[SAMPLE_WIDTH-1:0];
            if(tx_empty)
              left_sample <= wdata[SAMPLE_WIDTH-1:0];
          end

          REG_RIGHT_CHN: begin
            if(tx_empty)
              right_sample <= wdata[SAMPLE_WIDTH-1:0];
          end

          default: ;

        endcase

      end

      if(tx_push) begin
        tx_fifo[tx_wptr] <= {left_shadow, wdata[SAMPLE_WIDTH-1:0]};
        tx_wptr <= tx_wptr + 1'b1;
      end

      if(fifo_pop && !tx_empty) begin
        tx_rptr <= tx_rptr + 1'b1;
      end

      case ({tx_push, (fifo_pop && !tx_empty)})
        2'b10: tx_cnt <= tx_cnt + 1'b1;
        2'b01: tx_cnt <= tx_cnt - 1'b1;
        default: ;
      endcase

      if(fifo_pop && !tx_empty) begin
        left_sample  <= tx_fifo[tx_rptr][2*SAMPLE_WIDTH-1:SAMPLE_WIDTH];
        right_sample <= tx_fifo[tx_rptr][SAMPLE_WIDTH-1:0];
      end

    end
  end

  always_comb begin

    rdata = 32'h0;

    case(addr)

      REG_CTRL:
        rdata = {25'd0, intr_en, 5'd0, enable};

      REG_LEFT_CHN:
        rdata = {{(32-SAMPLE_WIDTH){1'b0}}, left_sample};

      REG_RIGHT_CHN:
        rdata = {{(32-SAMPLE_WIDTH){1'b0}}, right_sample};

      REG_STATUS:
        rdata = {
            {(32-(FIFO_PTR_W+10)){1'b0}},
          tx_cnt,
          tx_full,
          tx_empty,
          6'd0,
          busy
        };

    endcase

  end

endmodule

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

  output logic                    busy,
  output logic                    fifo_pop
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
      fifo_pop <= 1'b0;

    end
    else begin

      fifo_pop <= 1'b0;

      if(enable && bclk_tick && ~bclk) begin

        if(bit_cnt == 0) begin

          sdout <= left_sample[SAMPLE_WIDTH-1];
          shift_reg <= {
            left_sample[SAMPLE_WIDTH-2:0],
            right_sample,
            1'b0
          };

          bit_cnt <= FRAME_BITS - 1;

          busy <= 1'b1;
          fifo_pop <= 1'b1;

          lrclk <= 1'b0;

        end
        else begin

          sdout <= shift_reg[FRAME_BITS-1];

          shift_reg <= {
            shift_reg[FRAME_BITS-2:0],
            1'b0
          };

          bit_cnt <= bit_cnt - 1'b1;

          if(bit_cnt == (SAMPLE_WIDTH + 1))
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

  end

endmodule
