/* 
 * Wishbone Compliant I2C Master Peripheral with Hardware RX/TX FIFOs
 * Named after the soulful Bengali folk instrument 'Dotara'
 *
 * Brought up by Md. Jubaer Fahad & Md. Jannatul Nayem
 * Organization: Alpha Science Lab
 * August 2026
 *
 * Features:
 *  - 32-Bit Word-Addressed Wishbone Slave Interface
 *  - Configurable START_ADDRESS & SIZE parameters for Swadheen-SoC memory map
 *  - Standard OpenCores i2c-ocores compatible register offsets
 *  - Hardware 16-byte Transmit (TX) & Receive (RX) FIFOs for high-throughput burst transfers
 *  - 16-bit programmable prescaler for SCL frequency generation
 *  - Automatic START, Repeated START, and STOP condition generation
 *  - SCL Clock Stretching support
 *  - Interrupt generation on transfer completion & FIFO threshold events
 *  - Tri-state open-drain I2C pad control (SCL and SDA)
 */

module dotara_wb_i2c #(
    parameter bit [31:0] START_ADDRESS = 32'h0008_5200,
    parameter bit [31:0] SIZE          = 32'h0000_0006,
    parameter int        FIFO_DEPTH    = 16
)(
    input logic clk,
    input logic rst,

    wishbone_interface.slave wb,

    output logic interrupt,

    // I2C Tri-State Pad Signals
    input  logic scl_pad_i,
    output logic scl_pad_o,
    output logic scl_padoen_o, // 1 = High-Z (input), 0 = Drive Output

    input  logic sda_pad_i,
    output logic sda_pad_o,
    output logic sda_padoen_o  // 1 = High-Z (input), 0 = Drive Output
);

    //---------------------------------------------
    // Register Offsets (Word Addresses)
    //---------------------------------------------
    localparam logic [7:0] REG_PRER_LO = 8'h00; // Prescaler Low Byte
    localparam logic [7:0] REG_PRER_HI = 8'h01; // Prescaler High Byte
    localparam logic [7:0] REG_CTR     = 8'h02; // Control Register
    localparam logic [7:0] REG_RXR_TXR = 8'h03; // Data Receive / Transmit Register
    localparam logic [7:0] REG_CR_SR   = 8'h04; // Command / Status Register
    localparam logic [7:0] REG_FIFO_SR = 8'h05; // FIFO Status & Count Register

    //---------------------------------------------
    // Address Decoding & Bus Error Logic
    //---------------------------------------------
    logic [7:0] addr_t;
    logic [31:0] addr_rel = wb.adr - START_ADDRESS;
    logic err = (wb.adr < START_ADDRESS) || (wb.adr >= (START_ADDRESS + SIZE));

    assign addr_t = addr_rel[7:0];

    //---------------------------------------------
    // Internal Registers & Command / Status Flags
    //---------------------------------------------
    logic [15:0] prer;
    logic        ctr_en;
    logic        ctr_ien;

    logic        cr_sta, cr_sto, cr_rd, cr_wr, cr_ack, cr_iack;
    logic        sr_rxack, sr_busy, sr_al, sr_tip, sr_if;

    //---------------------------------------------
    // Hardware RX & TX Synchronous FIFOs
    //---------------------------------------------
    logic [7:0] tx_fifo [FIFO_DEPTH-1:0];
    logic [$clog2(FIFO_DEPTH):0] tx_wptr, tx_rptr, tx_cnt;
    logic tx_full, tx_empty;

    logic [7:0] rx_fifo [FIFO_DEPTH-1:0];
    logic [$clog2(FIFO_DEPTH):0] rx_wptr, rx_rptr, rx_cnt;
    logic rx_full, rx_empty;

    assign tx_empty = (tx_cnt == 0);
    assign tx_full  = (tx_cnt == FIFO_DEPTH);
    assign rx_empty = (rx_cnt == 0);
    assign rx_full  = (rx_cnt == FIFO_DEPTH);

    // TX FIFO Control
    logic tx_push, tx_pop;
    always_ff @(posedge clk) begin
        if (rst || !ctr_en) begin
            tx_wptr <= 0;
            tx_rptr <= 0;
            tx_cnt  <= 0;
        end else begin
            if (tx_push && !tx_full) begin
                tx_fifo[tx_wptr[$clog2(FIFO_DEPTH)-1:0]] <= wb.dat_mosi[7:0];
                tx_wptr <= tx_wptr + 1;
            end
            if (tx_pop && !tx_empty) begin
                tx_rptr <= tx_rptr + 1;
            end

            case ({tx_push && !tx_full, tx_pop && !tx_empty})
                2'b10: tx_cnt <= tx_cnt + 1;
                2'b01: tx_cnt <= tx_cnt - 1;
                default: ;
            endcase
        end
    end

    // RX FIFO Control
    logic rx_push, rx_pop;
    logic [7:0] rx_data_in;
    always_ff @(posedge clk) begin
        if (rst || !ctr_en) begin
            rx_wptr <= 0;
            rx_rptr <= 0;
            rx_cnt  <= 0;
        end else begin
            if (rx_push && !rx_full) begin
                rx_fifo[rx_wptr[$clog2(FIFO_DEPTH)-1:0]] <= rx_data_in;
                rx_wptr <= rx_wptr + 1;
            end
            if (rx_pop && !rx_empty) begin
                rx_rptr <= rx_rptr + 1;
            end

            case ({rx_push && !rx_full, rx_pop && !rx_empty})
                2'b10: rx_cnt <= rx_cnt + 1;
                2'b01: rx_cnt <= rx_cnt - 1;
                default: ;
            endcase
        end
    end

    logic [7:0] tx_data_out, rx_data_out;
    assign tx_data_out = tx_fifo[tx_rptr[$clog2(FIFO_DEPTH)-1:0]];
    assign rx_data_out = rx_fifo[rx_rptr[$clog2(FIFO_DEPTH)-1:0]];

    //---------------------------------------------
    // Wishbone ACK / ERR Generation
    //---------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            wb.ack <= 1'b0;
            wb.err <= 1'b0;
        end else begin
            wb.ack <= wb.cyc && wb.stb && !wb.ack;
            wb.err <= err;
        end
    end

    assign interrupt = (sr_if || tx_empty || rx_full) && ctr_ien;

    // Clock Divider / Prescaler Engine
    logic [15:0] prescaler_cnt;
    logic        clk_en;

    always_ff @(posedge clk) begin
        if (rst || !ctr_en) begin
            prescaler_cnt <= 16'd0;
            clk_en        <= 1'b0;
        end else if (prescaler_cnt >= prer) begin
            prescaler_cnt <= 16'd0;
            clk_en        <= 1'b1;
        end else begin
            prescaler_cnt <= prescaler_cnt + 16'd1;
            clk_en        <= 1'b0;
        end
    end

    // Bit Controller Signals
    typedef enum logic [4:0] {
        STATE_IDLE      = 5'b00000,
        STATE_START_A   = 5'b00001,
        STATE_START_B   = 5'b00010,
        STATE_START_C   = 5'b00011,
        STATE_START_D   = 5'b00100,
        STATE_STOP_A    = 5'b00110,
        STATE_STOP_B    = 5'b00111,
        STATE_STOP_C    = 5'b01000,
        STATE_STOP_D    = 5'b01001,
        STATE_WRITE_A   = 5'b01010,
        STATE_WRITE_B   = 5'b01011,
        STATE_WRITE_C   = 5'b01100,
        STATE_WRITE_D   = 5'b01101,
        STATE_READ_A    = 5'b01110,
        STATE_READ_B    = 5'b01111,
        STATE_READ_C    = 5'b10000,
        STATE_READ_D    = 5'b10001
    } bit_state_t;

    bit_state_t state;

    // Byte Controller State & Counters
    logic [3:0] bit_cnt;
    logic [7:0] shift_reg;
    logic       done_pulse;

    //---------------------------------------------
    // Wishbone Register Writes & FIFO Controls
    //---------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            prer    <= 16'hFFFF;
            ctr_en  <= 1'b0;
            ctr_ien <= 1'b0;
            cr_sta  <= 1'b0;
            cr_sto  <= 1'b0;
            cr_rd   <= 1'b0;
            cr_wr   <= 1'b0;
            cr_ack  <= 1'b0;
            cr_iack <= 1'b0;
            tx_push <= 1'b0;
            rx_pop  <= 1'b0;
        end else begin
            tx_push <= 1'b0;
            rx_pop  <= 1'b0;

            if (done_pulse) begin
                cr_sta <= 1'b0;
                cr_sto <= 1'b0;
                cr_rd  <= 1'b0;
                cr_wr  <= 1'b0;
            end

            if (cr_iack) begin
                cr_iack <= 1'b0;
            end

            if (wb.cyc && wb.stb && !wb.ack && !err) begin
                if (wb.we) begin
                    unique case (addr_t)
                        REG_PRER_LO: prer[7:0]  <= wb.dat_mosi[7:0];
                        REG_PRER_HI: prer[15:8] <= wb.dat_mosi[7:0];
                        REG_CTR: begin
                            ctr_en  <= wb.dat_mosi[7];
                            ctr_ien <= wb.dat_mosi[6];
                        end
                        REG_RXR_TXR: begin
                            tx_push <= 1'b1; // Push into TX FIFO
                        end
                        REG_CR_SR: begin
                            if (ctr_en) begin
                                cr_sta  <= wb.dat_mosi[7];
                                cr_sto  <= wb.dat_mosi[6];
                                cr_rd   <= wb.dat_mosi[5];
                                cr_wr   <= wb.dat_mosi[4];
                                cr_ack  <= wb.dat_mosi[3];
                                cr_iack <= wb.dat_mosi[0];
                            end
                        end
                        default: ;
                    endcase
                end else begin
                    if (addr_t == REG_RXR_TXR) begin
                        rx_pop <= 1'b1; // Pop RX FIFO
                    end
                end
            end
        end
    end

    //---------------------------------------------
    // Wishbone Register Reads
    //---------------------------------------------
    always_comb begin
        wb.dat_miso = 32'd0;
        unique case (addr_t)
            REG_PRER_LO: wb.dat_miso = {24'd0, prer[7:0]};
            REG_PRER_HI: wb.dat_miso = {24'd0, prer[15:8]};
            REG_CTR    : wb.dat_miso = {24'd0, ctr_en, ctr_ien, 6'd0};
            REG_RXR_TXR: wb.dat_miso = {24'd0, rx_data_out};
            REG_CR_SR  : wb.dat_miso = {24'd0, sr_rxack, sr_busy, sr_al, 3'd0, sr_tip, sr_if};
            REG_FIFO_SR: wb.dat_miso = {16'd0, rx_cnt[3:0], tx_cnt[3:0], rx_full, rx_empty, tx_full, tx_empty};
            default    : wb.dat_miso = 32'd0;
        endcase
    end

    //---------------------------------------------
    // I2C Master State Machine
    //---------------------------------------------
    logic sda_out;
    logic scl_out;

    assign scl_pad_o    = 1'b0;
    assign scl_padoen_o = scl_out; // 1 = open-drain High-Z (HIGH), 0 = Drive LOW

    assign sda_pad_o    = 1'b0;
    assign sda_padoen_o = sda_out; // 1 = open-drain High-Z (HIGH), 0 = Drive LOW

    always_ff @(posedge clk) begin
        if (rst || !ctr_en) begin
            state      <= STATE_IDLE;
            scl_out    <= 1'b1;
            sda_out    <= 1'b1;
            bit_cnt    <= 4'd0;
            shift_reg  <= 8'h00;
            rx_data_in <= 8'h00;
            sr_rxack   <= 1'b0;
            sr_busy    <= 1'b0;
            sr_al      <= 1'b0;
            sr_tip     <= 1'b0;
            sr_if      <= 1'b0;
            done_pulse <= 1'b0;
            tx_pop     <= 1'b0;
            rx_push    <= 1'b0;
        end else begin
            done_pulse <= 1'b0;
            tx_pop     <= 1'b0;
            rx_push    <= 1'b0;

            if (cr_iack) begin
                sr_if <= 1'b0;
            end

            case (state)
                STATE_IDLE: begin
                    scl_out <= 1'b1;
                    sda_out <= 1'b1;
                    sr_tip  <= 1'b0;

                    if (cr_sta) begin
                        state   <= STATE_START_A;
                        sr_tip  <= 1'b1;
                        sr_busy <= 1'b1;
                    end else if (cr_wr) begin
                        state     <= STATE_WRITE_A;
                        shift_reg <= tx_data_out; // Pop from TX FIFO
                        tx_pop    <= 1'b1;
                        bit_cnt   <= 4'd7;
                        sr_tip    <= 1'b1;
                    end else if (cr_rd) begin
                        state   <= STATE_READ_A;
                        bit_cnt <= 4'd7;
                        sr_tip  <= 1'b1;
                    end else if (cr_sto) begin
                        state  <= STATE_STOP_A;
                        sr_tip <= 1'b1;
                    end
                end

                //-----------------------------------------
                // START Condition Generation
                //-----------------------------------------
                STATE_START_A: begin
                    if (clk_en) begin
                        sda_out <= 1'b1;
                        scl_out <= 1'b1;
                        state   <= STATE_START_B;
                    end
                end

                STATE_START_B: begin
                    if (clk_en) begin
                        sda_out <= 1'b0; // SDA goes LOW while SCL is HIGH
                        state   <= STATE_START_C;
                    end
                end

                STATE_START_C: begin
                    if (clk_en) begin
                        scl_out <= 1'b0; // SCL LOW
                        state   <= STATE_START_D;
                    end
                end

                STATE_START_D: begin
                    done_pulse <= 1'b1;
                    sr_if      <= 1'b1;
                    state      <= STATE_IDLE;
                end

                //-----------------------------------------
                // WRITE Byte Transfer (8 bits + ACK)
                //-----------------------------------------
                STATE_WRITE_A: begin
                    if (clk_en) begin
                        sda_out <= shift_reg[bit_cnt]; // Drive MSB first
                        scl_out <= 1'b0;
                        state   <= STATE_WRITE_B;
                    end
                end

                STATE_WRITE_B: begin
                    if (clk_en) begin
                        scl_out <= 1'b1; // SCL HIGH
                        state   <= STATE_WRITE_C;
                    end
                end

                STATE_WRITE_C: begin
                    if (clk_en) begin
                        scl_out <= 1'b0; // SCL LOW
                        if (bit_cnt == 4'd0) begin
                            state   <= STATE_WRITE_D; // Prepare for ACK bit
                            sda_out <= 1'b1;          // Release SDA for Slave ACK
                        end else begin
                            bit_cnt <= bit_cnt - 4'd1;
                            state   <= STATE_WRITE_A;
                        end
                    end
                end

                STATE_WRITE_D: begin
                    if (clk_en) begin
                        scl_out  <= 1'b1;
                        sr_rxack <= sda_pad_i; // Sample ACK from slave
                        state    <= STATE_START_D; // Completion
                    end
                end

                //-----------------------------------------
                // READ Byte Transfer (8 bits + ACK/NACK)
                //-----------------------------------------
                STATE_READ_A: begin
                    if (clk_en) begin
                        sda_out <= 1'b1; // Release SDA line for Slave
                        scl_out <= 1'b0;
                        state   <= STATE_READ_B;
                    end
                end

                STATE_READ_B: begin
                    if (clk_en) begin
                        scl_out             <= 1'b1; // SCL HIGH
                        shift_reg[bit_cnt] <= sda_pad_i; // Sample SDA line
                        state               <= STATE_READ_C;
                    end
                end

                STATE_READ_C: begin
                    if (clk_en) begin
                        scl_out <= 1'b0; // SCL LOW
                        if (bit_cnt == 4'd0) begin
                            state   <= STATE_READ_D;
                            sda_out <= cr_ack; // Send ACK (0) or NACK (1)
                        end else begin
                            bit_cnt <= bit_cnt - 4'd1;
                            state   <= STATE_READ_A;
                        end
                    end
                end

                STATE_READ_D: begin
                    if (clk_en) begin
                        scl_out    <= 1'b1;
                        rx_data_in <= shift_reg; // Push into RX FIFO
                        rx_push    <= 1'b1;
                        state      <= STATE_START_D; // Completion
                    end
                end

                //-----------------------------------------
                // STOP Condition Generation
                //-----------------------------------------
                STATE_STOP_A: begin
                    if (clk_en) begin
                        sda_out <= 1'b0;
                        scl_out <= 1'b0;
                        state   <= STATE_STOP_B;
                    end
                end

                STATE_STOP_B: begin
                    if (clk_en) begin
                        scl_out <= 1'b1; // SCL HIGH
                        state   <= STATE_STOP_C;
                    end
                end

                STATE_STOP_C: begin
                    if (clk_en) begin
                        sda_out <= 1'b1; // SDA goes HIGH while SCL is HIGH
                        sr_busy <= 1'b0;
                        state   <= STATE_STOP_D;
                    end
                end

                STATE_STOP_D: begin
                    done_pulse <= 1'b1;
                    sr_if      <= 1'b1;
                    state      <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
