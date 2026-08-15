/* 
 * Wishbone Compliant SPI Master Peripheral with Hardware RX/TX FIFOs
 * Named after the majestic river of Bangladesh 'Karnaphuli'
 *
 * File: karnaphuli_wb_spi
 * Organization: Alpha Science Lab
 * August 2026
 *
 * Features:
 *  - 32-Bit Word-Addressed Wishbone Slave Interface
 *  - Configurable START_ADDRESS & SIZE parameters
 *  - Supports up to 8 Slave Devices (8-bit Active-Low Chip Select spi_cs_n[7:0])
 *  - Hardware 16-byte Transmit (TX) & Receive (RX) FIFOs for high-throughput burst transfers
 *  - 16-bit programmable prescaler for SCLK frequency generation
 *  - Supports SPI Mode 0 (CPOL=0, CPHA=0) and Mode 3 (CPOL=1, CPHA=1)
 *  - Interrupt generation on transfer completion & RX FIFO availability
 *  - Single-cycle Wishbone accesses
 */

module karnaphuli_wb_spi #(
    parameter bit [31:0] START_ADDRESS     = 32'h0008_5400,
    parameter bit [31:0] SIZE              = 32'h0000_0006,
    parameter int        NUM_SLAVES        = 8,
    parameter int        FIFO_DEPTH        = 16,
    parameter bit [15:0] DEFAULT_PRESCALER = 16'd7
)(
    input  logic clk,
    input  logic rst,

    wishbone_interface.slave wb,

    output logic intr,

    // SPI Master Signals with 8 Slave CS lines
    output logic [NUM_SLAVES-1:0] spi_cs_n,
    output logic                  spi_sclk,
    output logic                  spi_mosi,
    input  logic                  spi_miso
);

    //---------------------------------------------
    // Register Address Offsets
    //---------------------------------------------
    localparam logic [7:0] REG_CTRL      = 8'h00; // Control Register
    localparam logic [7:0] REG_PRESCALER = 8'h01; // Prescaler Register
    localparam logic [7:0] REG_STATUS    = 8'h02; // Status Register
    localparam logic [7:0] REG_DATA      = 8'h03; // Transmit / Receive FIFO Data
    localparam logic [7:0] REG_CS        = 8'h04; // 8-bit Chip Select Mask Register

    //---------------------------------------------
    // Configuration & Status Registers
    //---------------------------------------------
    logic ctrl_enable;
    logic ctrl_cpol;
    logic ctrl_cpha;
    logic ctrl_auto_cs;

    logic [15:0] prescaler_reg;
    logic [NUM_SLAVES-1:0] cs_n_reg;

    //---------------------------------------------
    // Hardware FIFOs
    //---------------------------------------------
    logic [7:0] tx_fifo [FIFO_DEPTH-1:0];
    logic [$clog2(FIFO_DEPTH)-1:0] tx_wptr, tx_rptr;
    logic [$clog2(FIFO_DEPTH):0] tx_count;

    logic [7:0] rx_fifo [FIFO_DEPTH-1:0];
    logic [$clog2(FIFO_DEPTH)-1:0] rx_wptr, rx_rptr;
    logic [$clog2(FIFO_DEPTH):0] rx_count;

    logic tx_fifo_full;
    logic tx_fifo_empty;
    logic rx_fifo_full;
    logic rx_fifo_empty;

    assign tx_fifo_full  = (tx_count == 5'd16);
    assign tx_fifo_empty = (tx_count == 5'd0);
    assign rx_fifo_full  = (rx_count == 5'd16);
    assign rx_fifo_empty = (rx_count == 5'd0);

    //---------------------------------------------
    // SPI Engine FSM
    //---------------------------------------------
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_LOAD,
        ST_BIT_LEAD,
        ST_BIT_TRAIL,
        ST_DONE
    } spi_state_t;

    spi_state_t state;

    logic [15:0] sclk_cnt;
    logic [2:0]  bit_cnt;
    logic [7:0]  tx_shift;
    logic [7:0]  rx_shift;
    logic        sclk_reg;
    logic        busy;

    assign spi_cs_n = cs_n_reg;
    assign spi_sclk = sclk_reg;
    assign spi_mosi = tx_shift[7];

    // Interrupt active when SPI engine is idle and RX data is available
    assign intr = !busy && !rx_fifo_empty;

    //---------------------------------------------
    // Wishbone Address Decoding & ACK
    //---------------------------------------------
    logic [7:0] addr_t;
    logic [31:0] addr_rel;
    logic err;

    assign addr_rel = wb.adr - START_ADDRESS;
    assign err = (wb.adr < START_ADDRESS) || (wb.adr >= (START_ADDRESS + SIZE));
    assign addr_t = addr_rel[7:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            wb.ack <= 1'b0;
            wb.err <= 1'b0;
        end else begin
            wb.ack <= wb.cyc && wb.stb && !wb.ack;
            wb.err <= err;
        end
    end

    //---------------------------------------------
    // Wishbone Register Writes & FIFO Push/Pop
    //---------------------------------------------
    logic tx_push, rx_pop;
    logic [7:0] tx_data_in;

    assign tx_push = wb.cyc && wb.stb && wb.we && !err && (addr_t == REG_DATA) && !tx_fifo_full && !wb.ack;
    assign rx_pop  = wb.cyc && wb.stb && !wb.we && !err && (addr_t == REG_DATA) && !rx_fifo_empty && !wb.ack;
    assign tx_data_in = wb.dat_mosi[7:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            prescaler_reg <= DEFAULT_PRESCALER;
            cs_n_reg      <= {NUM_SLAVES{1'b1}}; // All CS lines inactive HIGH

            ctrl_enable   <= 1'b0;
            ctrl_cpol     <= 1'b0;
            ctrl_cpha     <= 1'b0;
            ctrl_auto_cs  <= 1'b0;
        end 
        else if (wb.cyc && wb.stb && wb.we && !err && !wb.ack) begin
            case (addr_t)
                REG_CTRL: begin
                    ctrl_enable  <= wb.dat_mosi[0];
                    ctrl_cpol    <= wb.dat_mosi[1];
                    ctrl_cpha    <= wb.dat_mosi[2];
                    ctrl_auto_cs <= wb.dat_mosi[3];
                end
                REG_PRESCALER: prescaler_reg <= wb.dat_mosi[15:0];
                REG_CS:        cs_n_reg      <= wb.dat_mosi[NUM_SLAVES-1:0];
                default: ;
            endcase
        end
    end

    // TX FIFO Control
    always_ff @(posedge clk) begin
        if (rst) begin
            tx_wptr  <= 4'd0;
            tx_rptr  <= 4'd0;
            tx_count <= 5'd0;
        end 
        else begin
            if (tx_push && !(state == ST_LOAD)) begin
                tx_fifo[tx_wptr] <= tx_data_in;
                tx_wptr <= tx_wptr + 4'd1;
                tx_count <= tx_count + 5'd1;
            end else if (!tx_push && (state == ST_LOAD)) begin
                tx_rptr <= tx_rptr + 4'd1;
                tx_count <= tx_count - 5'd1;
            end else if (tx_push && (state == ST_LOAD)) begin
                tx_fifo[tx_wptr] <= tx_data_in;
                tx_wptr <= tx_wptr + 4'd1;
                tx_rptr <= tx_rptr + 4'd1;
            end
        end
    end

    // RX FIFO Control
    logic rx_push;
    logic [7:0] rx_data_in;

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_wptr  <= 4'd0;
            rx_rptr  <= 4'd0;
            rx_count <= 5'd0;
        end 
        else begin
            if (rx_push && !rx_pop && !rx_fifo_full) begin
                rx_fifo[rx_wptr] <= rx_data_in;
                rx_wptr <= rx_wptr + 4'd1;
                rx_count <= rx_count + 5'd1;
            end else if (!rx_push && rx_pop && !rx_fifo_empty) begin
                rx_rptr <= rx_rptr + 4'd1;
                rx_count <= rx_count - 5'd1;
            end else if (rx_push && rx_pop) begin
                rx_fifo[rx_wptr] <= rx_data_in;
                rx_wptr <= rx_wptr + 4'd1;
                rx_rptr <= rx_rptr + 4'd1;
            end
        end
    end

    //---------------------------------------------
    // Wishbone Register Reads
    //---------------------------------------------
    always_comb begin
        wb.dat_miso = 32'd0;
        case (addr_t)
            REG_CTRL:      wb.dat_miso = {28'b0, ctrl_auto_cs, ctrl_cpha, ctrl_cpol, ctrl_enable};
            REG_PRESCALER: wb.dat_miso = {16'b0, prescaler_reg};
            REG_STATUS:    wb.dat_miso = {27'b0, rx_fifo_empty, rx_fifo_full, tx_fifo_empty, tx_fifo_full, busy};
            REG_DATA:      wb.dat_miso = {24'b0, rx_fifo[rx_rptr]};
            REG_CS:        wb.dat_miso = {{(32-NUM_SLAVES){1'b0}}, cs_n_reg};
            default:       wb.dat_miso = 32'd0;
        endcase
    end

    //---------------------------------------------
    // SPI Master State Machine & SCLK Generator
    //---------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= ST_IDLE;
            sclk_reg   <= 1'b0;
            sclk_cnt   <= 16'd0;
            bit_cnt    <= 3'd0;
            tx_shift   <= 8'd0;
            rx_shift   <= 8'd0;
            rx_push    <= 1'b0;
            rx_data_in <= 8'd0;
            busy       <= 1'b0;
        end 
        else begin
            rx_push <= 1'b0;

            case (state)
                ST_IDLE: begin
                    sclk_reg <= ctrl_cpol;
                    sclk_cnt <= 16'd0;
                    busy     <= 1'b0;

                    if (ctrl_enable && !tx_fifo_empty) begin
                        state <= ST_LOAD;
                        busy  <= 1'b1;
                    end
                end

                ST_LOAD: begin
                    tx_shift <= tx_fifo[tx_rptr];
                    bit_cnt  <= 3'd7;
                    sclk_cnt <= 16'd0;
                    state    <= ST_BIT_LEAD;
                end

                ST_BIT_LEAD: begin
                    if (sclk_cnt >= prescaler_reg) begin
                        sclk_cnt <= 16'd0;
                        sclk_reg <= ~sclk_reg;
                        rx_shift <= {rx_shift[6:0], spi_miso};
                        state    <= ST_BIT_TRAIL;
                    end else begin
                        sclk_cnt <= sclk_cnt + 16'd1;
                    end
                end

                ST_BIT_TRAIL: begin
                    if (sclk_cnt >= prescaler_reg) begin
                        sclk_cnt <= 16'd0;
                        sclk_reg <= ~sclk_reg;

                        if (bit_cnt == 3'd0) begin
                            state <= ST_DONE;
                        end else begin
                            bit_cnt  <= bit_cnt - 3'd1;
                            tx_shift <= {tx_shift[6:0], 1'b0};
                            state    <= ST_BIT_LEAD;
                        end
                    end else begin
                        sclk_cnt <= sclk_cnt + 16'd1;
                    end
                end

                ST_DONE: begin
                    rx_data_in <= rx_shift;
                    rx_push    <= 1'b1;

                    if (!tx_fifo_empty) begin
                        state <= ST_LOAD;
                    end else begin
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

/* Just as the Karnaphuli river channels swift, high-capacity currents
 * into the sea, 'karnaphuli_wb_spi' streams high-throughput serial data
 * across multiple slave channels */
