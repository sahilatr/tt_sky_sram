<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works
==>> Pinout Grouping & Bus Summary:
1. Dedicated Inputs (ui_in[7:0]):

ui_in[3:0]: 4-bit data bus (data_in[3:0]) for sequential nibble ingestion (Clock 1: MSB nibble, Clock 2: LSB nibble).

ui_in[7:4]: Write Address bus bits A3 down to A0 (dec_wr_addr[3:0]).

2. Bidirectional IOs configured as Inputs (uio_in[7:0]):

uio_in[0]: Write Address MSB bit A4 (dec_wr_addr[4]).

uio_in[2:1]: Bus control strobes (uio_in[1] = wen write enable, uio_in[2] = ren read enable).

uio_in[6:3]: Read Address bus bits A3 down to A0 (dec_rd_addr[3:0]).

uio_in[7]: Read Address MSB bit A4 (dec_rd_addr[4]).

3. Dedicated Outputs (uo_out[7:0]):

uo_out[7:0]: 8-bit parallel decrypted data output bus (data_out[7:0]).

4. Global Control & Unused Pins:

clk, rst_n, ena: System clock, active-low reset, and active-high chip select (cs).

uio_out[7:0], uio_oe[7:0]: Tied to 0x00 (bidirectional ports configured strictly as inputs).

==>> Architecture & Functional Specification:
<img width="1622" height="647" alt="Screenshot 2026-10-13 at 2 19 59 PM" src="https://github.com/user-attachments/assets/9c7e6b54-5a18-489f-876f-b29dd55055e1" />

Section 1: Control Pins, Ingestion & 8-Bit XOR Engine
Input Signal Interfacing: Handles primary control inputs (clk, rst_n, ena/cs) and the 4-bit data bus (ui_in[3:0]/data_in[3:0]).

Ingestion Buffering & Phase Tagging: Samples the incoming 4-bit nibble into an internal buffer register (msb_buf) on Clock 1 and uses a phase tracker (nibble_phase) to concatenate the full 8-bit byte upon arrival of the lower nibble on Clock 2.

Parallel XOR Encryption: Passes the assembled 8-bit vector into an 8-bit parallel XOR encryption engine keyed with the symmetric secret key 0xAA (8'b1010_1010).

Encrypted Bus Driving: Emits the encrypted 8-bit payload onto a dedicated parallel internal data bus (pins [7:0]) directed to the memory matrix.

Section 2: Write [5:32] Decoder & Bitline Enables
Full 5-Bit Address Decoding: Manages memory write operations using a physical [5:32] write decoder driven by the combined 5-bit address bus {uio_in[0], ui_in[7:4]} (A4 down to A0).

Valid Range Operation (MSB = 0): For the 16-byte memory implementation, the host sets the MSB bit A4 = 0 (dec_wr_addr < 16), which asserts decoded wordlines 0 through 15.

128-Pin Write Joint Connection: The 16 active wordlines expand into 128 parallel write-enable lines across the 128-pin joint matrix that bridges directly into the SRAM core.

Out-of-Bounds Memory Protection (MSB = 1): If the user sets the MSB bit A4 = 1 (dec_wr_addr >= 16), the hardware address qualification check sets addr_ready_flag to 0, gating all write wordlines and preventing memory corruption.

Silicon Scalability Reservation: Retains the complete 5:32 physical decoder structure on silicon, leaving full architectural capability reserved to scale to 32 bytes without altering top-level pinout mappings.

Section 3: Read [5:32] Decoder & Bitline Enables
Decoder-Driven Read Architecture: Controls read operations using a symmetric [5:32] read decoder—without multiplexer trees—driven by the combined 5-bit address bus {uio_in[7], uio_in[6:3]} (A4 down to A0).

Valid Read Operation (MSB = 0): When the host sets the MSB bit A4 = 0 (dec_rd_addr < 16), the decoder asserts 1 of 16 wordlines, driving 8 dedicated read-select lines across the 128-pin joint connection matrix for the target byte.

Direct Encrypted Data Collection: Gated bit-cells route the 8-bit encrypted data directly from the 128-pin joint matrix onto the read bitline bus in parallel.

Out-of-Bounds Safe Readout (MSB = 1): If the user sets the MSB bit A4 = 1 (dec_rd_addr >= 16), read access is invalidated, returning safe default zero values (0x00) and preventing unmapped reads.

Symmetric Scalability Reservation: Retains the complete 5:32 read decoder structure in hardware, maintaining architectural capability for expanding to 32 bytes without interface changes.

Parallel XOR Decryption Output: Directs the collected 8-bit encrypted data through the parallel XOR decryption block using key 0xAA, driving valid plaintext (e.g., 8'b1100_0011 / 0xC3) on the output bus uo_out[7:0].

==>> Clock Timing & Synchronization:
Write Cycle Timing: Write operations take 2 clock cycles (Clock 1 buffers the MSB nibble; Clock 2 receives the LSB nibble, encrypts the byte, and commits it to memory).

Read Cycle Timing: Read operations execute in 1 clock cycle, reading and decrypting the data in parallel without pipeline latency.

Synchronous & Reset Control: All sequential logic updates synchronously on the rising edge of clk, with clean initialization governed by the active-low reset rst_n.

==>> Condition-Driven Finite State Machine(FSM):
<img width="767" height="789" alt="Screenshot 2026-10-13 at 2 23 13 PM" src="https://github.com/user-attachments/assets/e5d5ec4f-ead0-4059-8cdf-f2e91050156e" />


## How to test
Reset & Clock Setup: Initialize the system by asserting the active-low reset (rst_n) and supplying stable clock signals (clk).  
Executing a Write Cycle (2 Clock Cycles): Provide the 4-bit data  (in[3:0]) and address lines (ui[7:4]). The data is encrypted via the 8-bit XOR engine and routed through the 128-pin joint matrix into the designated SRAM storage byte (e.g., Rows 0 to 15).  
Executing a Read Cycle (1 Clock Cycle): Assert the read control signals (address lines (uio[6:3]), read enable) and target the desired memory row using the read 5:32 decoder. The retrieved bitlines are decrypted using the XOR decryption unit and verified at the 8-bit parallel output (out[7:0]).  

## External hardware


