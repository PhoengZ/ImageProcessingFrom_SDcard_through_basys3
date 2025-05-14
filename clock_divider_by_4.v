`timescale 1ns / 1ps

module clock_divider_by_4 (
    input wire clk_100mhz_in,
    input wire reset_in,      // Active high reset
    output reg clk_25mhz_out   // Output is a register driven by this module
);
    reg [1:0] count = 2'b00; // Counter for division

    always @(posedge clk_100mhz_in or posedge reset_in) begin
        if (reset_in) begin
            count <= 2'b00;
            clk_25mhz_out <= 1'b0; // Initialize clock output to low
        end else begin
            count <= count + 1; // Increment counter on each 100MHz clock edge
                                // Counter sequence: 00, 01, 10, 11, 00 ...

            // To generate a 25MHz clock (period of 4 x 100MHz cycles)
            // with 50% duty cycle (high for 2 cycles, low for 2 cycles of 100MHz):
            // We can toggle clk_25mhz_out at specific points in the count.
            // If clk_25mhz_out starts at 0:
            // After count becomes 1 (00 -> 01): toggle clk_25mhz_out (0 -> 1)
            // After count becomes 3 (10 -> 11): toggle clk_25mhz_out (1 -> 0)
            
            if (count == 2'b01) begin // count has just transitioned from 00 to 01
                clk_25mhz_out <= ~clk_25mhz_out; 
            end else if (count == 2'b11) begin // count has just transitioned from 10 to 11
                clk_25mhz_out <= ~clk_25mhz_out;
            end
            // No other assignments to clk_25mhz_out in this always block
        end
    end

endmodule