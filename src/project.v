/*
 * Copyright (c) 2026 Sahil Sexsena
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // [3:0]=data_in, [7:4]=dec_wr_addr[3:0]
    output wire [7:0] uo_out,   // [7:0]=data_out[7:0]
    input  wire [7:0] uio_in,   // [0]=dec_wr_addr[4], [1]=wen, [2]=ren, [7:3]=dec_rd_addr[4:0]
    output wire [7:0] uio_out,  // Tied to 0
    output wire [7:0] uio_oe,   // Direction control: 0 = all inputs
    input  wire       ena,      // Chip Select (cs) - active-high
    input  wire       clk,      // System clock
    input  wire       rst_n     // Reset pin from TT pad (active-low pad inverted to active-high rst)
);

    // Fixed 8-Bit Secret Key for Parallel XOR Encryption & Decryption
    localparam [7:0] CIPHER_KEY = 8'b1010_1010; // 0xAA

    // ----------------------------------------------------------------
    // 1. Explicit Wire Mappings & Named Variables
    // ----------------------------------------------------------------
    wire       rst         = ~rst_n;
    wire       cs          = ena;

    wire [3:0] data_in     = ui_in[3:0];
    wire [4:0] dec_wr_addr = {uio_in[0], ui_in[7:4]}; // {A4, A3, A2, A1, A0}
    wire       wen         = uio_in[1];
    wire       ren         = uio_in[2];
    wire [4:0] dec_rd_addr = uio_in[7:3];

    reg  [7:0] data_out;
    assign uo_out = data_out;

    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    // ----------------------------------------------------------------
    // 2. Physical 128-Bit Memory Array & Registers (16 bytes x 8 bits)
    // ----------------------------------------------------------------
    reg [3:0]   msb_buf;       // Buffer to hold upper nibble across Clock 1
    reg         nibble_phase;  // 0 = Waiting for MSB, 1 = Waiting for LSB
    reg [127:0] mem_cells;     // 128 physical bit storage cells (16 bytes x 8 bits)

    // ----------------------------------------------------------------
    // 3. Write 4:16 Decoder -> 128 Write Enable Lines (16 slots)
    // ----------------------------------------------------------------
    wire [15:0] wr_wordline     = (cs && wen) ? (16'b1 << dec_wr_addr[3:0]) : 16'b0;
    wire        addr_ready_flag = |wr_wordline && (dec_wr_addr < 5'd16);

    // Expand 16 wordlines to 128 parallel bit enables (8 lines per slice)
    wire [127:0] wr_bit_enables;
    genvar w;
    generate
        for (w = 0; w < 16; w = w + 1) begin : gen_wr_enables
            assign wr_bit_enables[w*8 +: 8] = {8{wr_wordline[w]}};
        end
    endgenerate

    // ----------------------------------------------------------------
    // 4. Read 4:16 Decoder -> 128 Read Gating -> 8-Bit Read Bitline Bus
    // ----------------------------------------------------------------
    wire [15:0] rd_wordline     = (cs && ren) ? (16'b1 << dec_rd_addr[3:0]) : 16'b0;

    // Expand 16 wordlines to 128 parallel read selects (8 lines per slice)
    wire [127:0] rd_bit_selects;
    genvar r;
    generate
        for (r = 0; r < 16; r = r + 1) begin : gen_rd_selects
            assign rd_bit_selects[r*8 +: 8] = {8{rd_wordline[r]}};
        end
    endgenerate

    // Gate each of the 128 bit-cells with its read select line
    wire [127:0] gated_mem_cells = mem_cells & rd_bit_selects;

    // Combine all 16 slices onto the shared 8-bit read bitlines (Blocking = for combinational loop)
    reg [7:0] rd_bitline;
    integer b;
    always @(*) begin
        rd_bitline = 8'h00;
        for (b = 0; b < 16; b = b + 1) begin
            rd_bitline = rd_bitline | gated_mem_cells[b*8 +: 8];
        end
    end

    // ----------------------------------------------------------------
    // 5. Synchronous Execution Core
    // ----------------------------------------------------------------
    reg [7:0] full_assembled_byte;
    reg [7:0] full_encrypted_byte;
    integer bit_idx;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            msb_buf      <= 4'b0000;
            nibble_phase <= 1'b0;
            data_out     <= 8'h00;
            mem_cells    <= 128'b0;
        end else if (!cs) begin
            nibble_phase <= 1'b0;
            data_out     <= 8'h00;
        end else begin
            // --- Write Path: 2 Consecutive Clocks ---
            if (!wen) begin
                nibble_phase <= 1'b0;
            end else begin
                if (!nibble_phase) begin
                    // Clock 1: Latch 4-bit MSB into msb_buf
                    msb_buf      <= data_in;
                    nibble_phase <= 1'b1;

                    $display("\n[WRITE CYCLE 1: MSB]");
                    $display("  Incoming data_in[3:0] : 4'b%04b", data_in);
                    $display("  Target dec_wr_addr    : %0d", dec_wr_addr);
                end else begin
                    // Clock 2: Assemble MSB + LSB into full 8-bit byte and encrypt instantly
                    full_assembled_byte = {msb_buf, data_in};
                    full_encrypted_byte = full_assembled_byte ^ CIPHER_KEY;
                    nibble_phase        = 1'b0;

                    $display("\n[WRITE CYCLE 2: LSB & write_commit]");
                    $display("  Incoming data_in[3:0] : 4'b%04b", data_in);
                    $display("  Buffered MSB          : 4'b%04b", msb_buf);
                    $display("  Assembled 8-Bit Data  : 8'b%08b (0x%02X)", full_assembled_byte, full_assembled_byte);
                    $display("  XOR Encrypted Byte    : 8'b%08b (0x%02X)", full_encrypted_byte, full_encrypted_byte);

                    if (addr_ready_flag) begin
                        for (bit_idx = 0; bit_idx < 128; bit_idx = bit_idx + 1) begin
                            if (wr_bit_enables[bit_idx]) begin
                                mem_cells[bit_idx] <= full_encrypted_byte[bit_idx % 8];
                            end
                        end
                        $display("  [SUCCESS] Written into bit-slice [%0d:%0d] of 128-bit memory", 
                                 dec_wr_addr*8 + 7, dec_wr_addr*8);
                    end
                end
            end

            // --- Read Path: 1-Clock Parallel Decrypted Readout ---
            if (!ren) begin
                data_out <= 8'h00;
            end else begin
                // Decrypt from the 8-bit read bitlines onto data_out
                data_out <= rd_bitline ^ CIPHER_KEY;

                $display("\n[DECODER-DRIVEN READOUT]");
                $display("  Read Target dec_rd_addr: %0d", dec_rd_addr);
                $display("  Bit-Slice Selected     : [%0d:%0d]", dec_rd_addr*8 + 7, dec_rd_addr*8);
                $display("  Read Bitline Encrypted : 8'b%08b (0x%02X)", rd_bitline, rd_bitline);
                $display("  Decrypted data_out Bus : 8'b%08b (0x%02X)", rd_bitline ^ CIPHER_KEY, rd_bitline ^ CIPHER_KEY);
            end
        end
    end

endmodule
