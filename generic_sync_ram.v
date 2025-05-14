`timescale 1ns / 1ps

module generic_sync_ram #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 15  // Results in RAM_DEPTH = 2^15 = 32768
)(
    input wire                      clk,
    input wire [ADDR_WIDTH-1:0]     addr,
    input wire [DATA_WIDTH-1:0]     din,
    input wire                      we,    // Write Enable
    output reg [DATA_WIDTH-1:0]     dout   // Registered output
);
    localparam RAM_DEPTH = 1 << ADDR_WIDTH; // Calculate depth from ADDR_WIDTH
    
    // Declare the memory array
    reg [DATA_WIDTH-1:0] mem [0:RAM_DEPTH-1];

    // Optional: Initialize memory content for simulation (ignored by synthesis for BRAMs)
    // initial begin
    //     for (integer i = 0; i < RAM_DEPTH; i = i + 1) begin
    //         mem[i] = {DATA_WIDTH{1'b0}};
    //     end
    // end

    always @(posedge clk) begin
        // Write operation: if write enable is asserted, write data to memory
        if (we) begin
            mem[addr] <= din;
        end
        
        // Read operation: Output data from the addressed location.
        // The output 'dout' is registered, so data will appear on 'dout'
        // one clock cycle after the 'addr' is stable.
        // This implements "read-old-data" if writing and reading the same address in the same cycle.
        dout <= mem[addr]; 
    end

endmodule