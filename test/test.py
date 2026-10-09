# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start Secure QSPI SRAM Cocotb Testbench")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset Sequence
    dut._log.info("Resetting DUT")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    dut._log.info("Test project behavior")

    # -------------------------------------------------------------------------
    # TEST 1: Write 8'b1100_0011 (0xC3) to Address 5 (No Read)
    # wr_addr = 5 -> wr_addr[3:0] = 5 (ui_in[7:4]), wr_addr[4] = 0 (uio_in[0])
    # Data = 0xC3 -> MSB = 0xC (ui_in[3:0]), LSB = 0x3 (ui_in[3:0])
    # wen = 1 (uio_in[1]), ren = 0 (uio_in[2])
    # -------------------------------------------------------------------------
    dut._log.info("STEP 1: Writing 0xC3 into Address 5 (no read)")

    # Clock 1: Send MSB (4'b1100 = 0xC)
    # ui_in  = {wr_addr[3:0], data[7:4]} = {4'h5, 4'hC} = 0x5C = 92
    # uio_in = {rd_sel[4:0], ren, wen, wr_addr[4]} = {5'd0, 1'b0, 1'b1, 1'b0} = 0x02 = 2
    dut.ui_in.value = (5 << 4) | 0xC
    dut.uio_in.value = (0 << 3) | (0 << 2) | (1 << 1) | 0
    await ClockCycles(dut.clk, 1)

    # Clock 2: Send LSB (4'b0011 = 0x3) & Commit Write
    # ui_in  = {wr_addr[3:0], data[3:0]} = {4'h5, 4'h3} = 0x53 = 83
    dut.ui_in.value = (5 << 4) | 0x3
    await ClockCycles(dut.clk, 1)

    # De-assert Write Enable
    dut.uio_in.value = 0
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 2)

    # -------------------------------------------------------------------------
    # TEST 2: Write 8'b1110_0001 (0xE1) to Address 8
    #         WHILE SIMULTANEOUSLY READING Address 5 (wen=1, ren=1)
    # wr_addr = 8 -> wr_addr[3:0] = 8, wr_addr[4] = 0
    # wr_data = 0xE1 -> MSB = 0xE, LSB = 0x1
    # rd_sel  = 5 -> uio_in[7:3] = 5
    # wen = 1 (uio_in[1]), ren = 1 (uio_in[2])
    # -------------------------------------------------------------------------
    dut._log.info("STEP 2: Writing 0xE1 to Addr 8 while reading Addr 5 concurrently")

    # Clock 1: Send MSB (0xE) to Addr 8, rd_sel = 5, wen = 1, ren = 1
    # ui_in  = {4'h8, 4'hE} = 0x8E = 142
    # uio_in = {rd_sel=5 (5'b00101), ren=1, wen=1, wr_addr[4]=0}
    #        = (5 << 3) | (1 << 2) | (1 << 1) | 0 = 40 | 4 | 2 = 46 (0x2E)
    dut.ui_in.value = (8 << 4) | 0xE
    dut.uio_in.value = (5 << 3) | (1 << 2) | (1 << 1) | 0
    await ClockCycles(dut.clk, 1)

    # Clock 2: Send LSB (0x1) to Addr 8 & Commit Write
    # ui_in  = {4'h8, 4'h1} = 0x81 = 129
    dut.ui_in.value = (8 << 4) | 0x1
    await ClockCycles(dut.clk, 1)

    # Check that Address 5 output is read back and decrypted in 1 cycle
    read_data = int(dut.uo_out.value)
    dut._log.info(f"Readout from Address 5: {hex(read_data)} (Expected: 0xC3)")
    assert read_data == 0xC3, f"Read mismatch: Got {hex(read_data)}, Expected 0xC3"

    # De-assert control signals
    dut.uio_in.value = 0
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 2)

    dut._log.info("All Cocotb tests passed successfully!")
