<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works
Architecture Overview:The project implements a secure QSPI SRAM Architecture as a Single-Module ASIC featuring a 128-pin Joint Connection Matrix and a 16x8-bit SRAM core.
section 1: (Control Pins, Ingestion & 8-Bit XOR Engine): Handles input signals (clks, active-low reset 'rst_n', enables 'en', and 4-bit data inputs in[3:0]), buffering them through buffer and phase tagging before passing them to an 8-bit XOR encryption engine using key to produce encrypted data 8 pins (0:7).  
Section 2: (write 5:32 Decoder & Bitlines enable): Manages write operations using a full 5:32 write decoder driven by 5 address pins (A0 to A3 on ui_in[7:4] and A4 on uio_in[0]). For the current 16-byte implementation, the host/user sets A4 = 0 (dec_wr_addr < 16), qualifying the access so that wordlines 0–15 fire and assert 128 write-enable lines across the 128-pin that bridge directly to the SRAM core via the 128-pin joint connection. If the user drives A4 = 1 (dec_wr_addr >= 16), addr_ready_flag evaluates to 0, preventing out-of-bounds writes and protecting memory from corruption. This preserves the complete 5:32 hardware decoding structure on silicon, leaving full architectural support reserved to scale to an additional 16 bytes (32 bytes total) without altering the top-level interface.
Section 3: (Read 5:32 Decoder & Bitlines enable): Manages read operations using a full 5:32 read decoder driven by 5 address pins (A0 to A3 on uio_in[6:3] and A4 on uio_in[7]). For the current 16-byte implementation, the host/user sets A4 = 0 (dec_rd_addr < 16), qualifying the access so that wordlines 0–15 fire and assert 128 read-select lines across the 128-pin that bridge directly to the SRAM core via the 128-pin joint connection. If the user drives A4 = 1 (dec_rd_addr >= 16), read access is qualified out, preventing out-of-bounds reads and returning safe default values. This preserves the complete 5:32 hardware decoding structure on silicon, leaving full architectural support reserved to scale to an additional 16 bytes (32 bytes total) without altering the top-level interface, and then passing data through an XOR decryption block to generate an 8-bit parallel output (8b1100_0011/0xC3).
Clock Timing: Write operations take 2 clock cycles, while read operations take 1 clock cycle, controlled via synchronous clock inputs and an active-low reset (rst_n). 

## How to test
Reset & Clock Setup: Initialize the system by asserting the active-low reset (rst_n) and supplying stable clock signals (clk).  
Executing a Write Cycle (2 Clock Cycles): Provide the 4-bit data  (in[3:0]) and address lines (ui[7:4]). The data is encrypted via the 8-bit XOR engine and routed through the 128-pin joint matrix into the designated SRAM storage byte (e.g., Rows 0 to 15).  
Executing a Read Cycle (1 Clock Cycle): Assert the read control signals (address lines (uio[6:3]), read enable) and target the desired memory row using the read 5:32 decoder. The retrieved bitlines are decrypted using the XOR decryption unit and verified at the 8-bit parallel output (out[7:0]).  

## External hardware


