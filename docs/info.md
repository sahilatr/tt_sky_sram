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

Ingestion Buffering & Phase Tagging: Samples the incoming 4-bit nibble into an internal buffer register (msb_buf) on Clock 1 and uses a phase tracker (nibble_phase) to concatenate the full 8-bit byte upon arrival of       the lower nibble on Clock 2.

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

<img width="789" height="884" alt="Screenshot 2026-10-13 at 2 41 31 PM" src="https://github.com/user-attachments/assets/32da50fc-cc7c-42cc-a116-2c32d7571f76" />


Transition 1: IDLE / RESET $\rightarrow$  WRITE_MSB

Trigger Condition: cs and wen and !nibble_phase

Hardware Behavior: When chip select (cs / ena) and write enable (wen / uio_in[1]) are active while the controller is not in a write sequence (!nibble_phase), the rising clock edge latches the upper 4 bits from the data bus (ui_in[3:0]) into the internal register msb_buf.

Phase Flag Update: The controller asserts the sequential phase flag (nibble_phase <= 1) to mark that the high nibble is buffered and the system is ready for the second half.

Transition 2: WRITE_MSB $\rightarrow$  WRITE_COMMIT

Trigger Condition: addr_ready_flag and nibble_phase

Hardware Behavior: On the following clock cycle, the lower 4 bits arrive on ui_in[3:0]. The 5:32 write decoder evaluates the address, validating access through addr_ready_flag = |wr_wordline and (dec_wr_addr < 16).

Cipher and Memory Write: The buffered msb_buf and incoming lower nibble concatenate into a full 8-bit byte ({msb_buf, data_in}), which is instantly encrypted in parallel using key 0xAA and stored into the targeted byte slice of mem_cells via the joint connection matrix.

Phase Flag Reset: The phase register resets to zero (nibble_phase <= 0), completing the 2-cycle write operation.

Transition 3: WRITE_COMMIT $\rightarrow$  s_standby

Trigger Condition: !wen or commit_done

Hardware Behavior: Once write enable is de-asserted (!wen) or the write commit cycle finishes, the system moves directly into the s_standby state.

Data Isolation: All wordline write enables drop low across the joint matrix, isolating the internal flip-flops from the external inputs and ensuring the stored ciphertext is securely held without risk of overwrite.

Transition 4: s_standby $\rightarrow$  PARALLEL READ

Trigger Condition: cs and ren

Hardware Behavior: While holding data in standby, asserting read enable (ren / uio_in[2]) along with chip select (cs) immediately triggers the read path.

Decoder Line Selection: The 5:32 read decoder evaluates dec_rd_addr (uio_in[7:3]). As long as access is valid (dec_rd_addr < 16), it asserts 8 read-select lines across the joint matrix to route the stored byte directly onto the shared 8-bit read bitlines (rd_bitline).

Deterministic 1-Clock Readout: The encrypted byte passes directly into the parallel XOR decryption block, restoring the plaintext data onto output pins uo_out[7:0] in exactly 1 single clock cycle.

Return to Default / Idle

Trigger Condition: !cs or !ren

Hardware Behavior: If chip select is dropped (!cs) or read enable goes low (!ren), the output bus safely resets to zero (uo_out <= 0x00), returning the module to IDLE or retaining state in s_standby.


## How to test
Phase 1: Reset and Clock Setup:
            Start the free-running system clock (clk).
            Assert rst_n = 0 with ena = 1 for 2 to 10 cycles to clear internal registers (msb_buf, nibble_phase, uo_out).
            Release reset by setting rst_n = 1 on a falling clock edge.
Phase 2: Write Cycle (2 Clock Cycles):
            Clock 1: Set wen = 1 (uio_in[1] = 1), drive write address on ui_in[7:4] ($A_3:A_0$) and uio_in[0] = 0 ($A_4$), and provide the MSB data nibble on ui_in[3:0]. The core buffers this into msb_buf.   
            Clock 2: Provide the LSB data nibble on ui_in[3:0]. The core assembles both nibbles, encrypts the byte with key 0xAA, and commits it through the 128-pin joint matrix into the target SRAM row.   
            Clear wen = 0 after Clock 2 to return to standby.   
Phase 3: Read Cycle (1 Clock Cycle)
            Set ren = 1 (uio_in[2] = 1), drive read address on uio_in[6:3] ($A_3:A_0$) and uio_in[7] = 0 ($A_4$).   
            The 5:32 read decoder activates the target wordline, routes the encrypted byte through the 128-pin joint matrix onto the read bitlines, and decrypts it with key 0xAA.   
            Sample uo_out[7:0] on the next clock edge and verify it matches the original plaintext byte (e.g., 0xC3).
            Clear ren = 0 to return the output bus to 0x00.
Phase 4: Simultaneous Write and Read Test
            Assert both wen = 1 and ren = 1 together.   
            Write a new byte to a target address (e.g., Address 8) while reading back previously stored data from another address (e.g., Address 5).   
            Verify that uo_out[7:0] outputs the correct decrypted byte on the write-commit clock edge without data contention.  

## External hardware


