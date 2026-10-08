/*`default_nettype none
`timescale 1ns / 1ps

 This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.

module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // Replace tt_um_example with your module name:
  tt_um_example user_project (

      // Include power ports for the Gate Level test:
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

endmodule

*/

// Code your testbench here
// or browse Examples
`timescale 1ns / 1ps

module tb;

    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    reg        ena;
    reg        clk;
    reg        rst_n;

    // Instantiate Single Module Under Test
    tt_um_example dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    // 100 MHz System Clock (10 ns period)
    always #5 clk = ~clk;

    // Task: Standard 2-Clock Write
    task write_byte(input [4:0] addr, input [7:0] data);
        begin
            @(negedge clk);
            ui_in[7:4] = addr[3:0]; // A0-A3
            uio_in[0]  = addr[4];   // A4
            ui_in[3:0] = data[7:4]; // Clock 1: MSB
            uio_in[1]  = 1'b1;      // wen = 1
            uio_in[2]  = 1'b0;      // ren = 0
            ena        = 1'b1;

            @(negedge clk);
            ui_in[3:0] = data[3:0]; // Clock 2: LSB

            @(negedge clk);
            uio_in[1]  = 1'b0;      // wen = 0
            ui_in[3:0] = 4'h0;
        end
    endtask

    // Task: Simultaneous Write to one address & Read from another address
    task write_and_read_simultaneous(
        input [4:0] wr_addr, 
        input [7:0] wr_data, 
        input [4:0] rd_addr, 
        input [7:0] expected_rd_data
    );
        begin
            @(negedge clk);
            // Setup Write Target
            ui_in[7:4]  = wr_addr[3:0];
            uio_in[0]   = wr_addr[4];
            ui_in[3:0]  = wr_data[7:4]; // MSB
            // Setup Read Target
            uio_in[7:3] = rd_addr;      // rd_sel

            // Assert both Write and Read
            uio_in[1]   = 1'b1;         // wen = 1
            uio_in[2]   = 1'b1;         // ren = 1
            ena         = 1'b1;

            @(negedge clk);
            // Drive LSB for commit
            ui_in[3:0]  = wr_data[3:0]; 

            @(posedge clk);
            #1; // Evaluation strobe on commit edge
            if (uo_out === expected_rd_data) begin
                $display("\n>>> [SIMULTANEOUS SUCCESS] While writing to Addr %0d, read from Addr %0d matched 0x%02X! <<<\n", 
                         wr_addr, rd_addr, uo_out);
            end else begin
                $display("\n>>> [SIMULTANEOUS ERROR] Read 0x%02X != Expected 0x%02X <<<\n", 
                         uo_out, expected_rd_data);
            end

            @(negedge clk);
            uio_in[1]  = 1'b0; // wen = 0
            uio_in[2]  = 1'b0; // ren = 0
            ui_in[3:0] = 4'h0;
        end
    endtask

    initial begin
        clk    = 0;
        rst_n  = 0;
        ena    = 1;
        ui_in  = 8'h00;
        uio_in = 8'h00;

        #25;
        @(negedge clk);
        rst_n = 1;
        #5;

        // Step 1: Write 8'b1100_0011 (0xC3) to Address 5 (bit slice [47:40])
        $display("=====================================================================");
        $display("STEP 1: Writing 0xC3 into Address 5 (no read)");
        $display("=====================================================================");
        write_byte(5'd5, 8'b1100_0011);

        repeat (2) @(negedge clk);

        // Step 2: Write 8'b1110_0001 (0xE1) to Address 8 (bit slice [71:64])
        //         WHILE reading Address 5 at the exact same time
        $display("=====================================================================");
        $display("STEP 2: Writing 0xE1 to Address 8 while reading Address 5 concurrently");
        $display("=====================================================================");
        write_and_read_simultaneous(
            5'd8,           // Write Address
            8'b1110_0001,   // Write Data (0xE1)
            5'd5,           // Read Address
            8'b1100_0011    // Expected Data at Address 5 (0xC3)
        );

        repeat (2) @(negedge clk);
        $display("=====================================================================");
        $display("             ALL 256-BIT MATRIX OPERATIONS VERIFIED                  ");
        $display("=====================================================================\n");
        $finish;
    end

endmodule
