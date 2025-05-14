`timescale 1ns / 1ps

module sd_controller(
    output reg cs,
    output mosi,
    input miso,
    output sclk,

    input rd,
    output reg [7:0] dout,
    output reg byte_available,

    input wr,
    input [7:0] din,
    output reg ready_for_next_byte,

    input reset,
    output ready,
    input [31:0] address,
    input clk, // 25 MHz clock
    output [4:0] status,
    output [15:0] debug_state_reached
);
    reg [15:0] debug_state_reached_internal = 0;

    parameter RST = 0;
    parameter CMD0 = 2;
    parameter CMD8 = 3;
    parameter CMD55 = 4; 
    parameter CMD41 = 5; 
    parameter POLL_CMD = 6; 
    
    parameter IDLE = 7;
    parameter READ_BLOCK = 8;
    parameter READ_BLOCK_WAIT = 9;
    parameter READ_BLOCK_DATA = 10;
    parameter READ_BLOCK_CRC = 11;
    parameter SEND_CMD = 12;
    parameter RECEIVE_BYTE_WAIT = 13;
    parameter RECEIVE_BYTE = 14;
    parameter WRITE_BLOCK_CMD = 15;
    parameter WRITE_BLOCK_INIT = 16;
    parameter WRITE_BLOCK_DATA = 17;
    parameter WRITE_BLOCK_BYTE = 18;
    parameter WRITE_BLOCK_WAIT = 19;
    parameter CMD58 = 20; 
    
    parameter WRITE_DATA_SIZE = 515;
    
    reg [4:0] state = RST;
    assign status = state;
    reg [4:0] return_state;
    reg sclk_sig = 0;
    reg [55:0] cmd_out; 
    reg [7:0] recv_data;
    reg cmd_mode = 1; 
    reg [7:0] data_sig = 8'hFF;
    
    reg [9:0] byte_counter; 
    reg [9:0] bit_counter;  
    
    reg [17:0] boot_counter_powerup = 18'd250_000; 
    reg [7:0] boot_counter_clocks = 80; 

    always @(posedge clk) begin
        if(reset == 1) begin
            state <= RST;
            sclk_sig <= 0;
            boot_counter_powerup <= 18'd250_000; // Semicolon is present
            boot_counter_clocks <= 80;
            debug_state_reached_internal <= 0;
            cs <= 1; 
        end
        else begin
            case(state)
                RST: begin 
                    cs <= 1; 
                    sclk_sig <= 0; 
                    if(boot_counter_powerup != 0) begin
                        boot_counter_powerup <= boot_counter_powerup - 1;
                    end else if (boot_counter_clocks != 0) begin 
                        sclk_sig <= ~sclk_sig; 
                        if(sclk_sig == 1'b0) begin 
                            boot_counter_clocks <= boot_counter_clocks - 1;
                        end
                    end else begin
                        byte_counter <= 0;
                        byte_available <= 0;
                        ready_for_next_byte <= 0;
                        cmd_mode <= 1;
                        cs <= 0;  
                        state <= CMD0;
                    end
                    debug_state_reached_internal[0] <= 1;
                end
                CMD0: begin 
                    cmd_out <= 56'hFF_40_00_00_00_00_95; 
                    bit_counter <= 55; 
                    return_state <= CMD8;
                    state <= SEND_CMD;
                    debug_state_reached_internal[2] <= 1;
                end
                CMD8: begin 
                    cmd_out <= 56'hFF_48_00_00_01_AA_87; 
                    bit_counter <= 55;
                    return_state <= CMD58; 
                    state <= SEND_CMD;
                    debug_state_reached_internal[3] <= 1;
                end
                CMD58: begin 
                    cmd_out <= 56'hFF_7A_00_00_00_00_FD; 
                    bit_counter <= 55;
                    return_state <= CMD55; 
                    state <= SEND_CMD;
                    debug_state_reached_internal[4] <= 1; 
                end
                CMD55: begin 
                    cmd_out <= 56'hFF_77_00_00_00_00_65; 
                    bit_counter <= 55;
                    return_state <= CMD41;
                    state <= SEND_CMD;
                    debug_state_reached_internal[5] <= 1;
                end
                CMD41: begin 
                    cmd_out <= 56'hFF_69_40_00_00_00_77; 
                    bit_counter <= 55;
                    return_state <= POLL_CMD;
                    state <= SEND_CMD;
                    debug_state_reached_internal[6] <= 1;
                end
                POLL_CMD: begin 
                    if(recv_data[0] == 0) begin 
                        state <= IDLE;
                    end else begin 
                        state <= CMD55; 
                    end
                    debug_state_reached_internal[7] <= 1;
                end
                IDLE: begin
                    if(rd == 1) begin
                        state <= READ_BLOCK;
                    end else if(wr == 1) begin
                        state <= WRITE_BLOCK_CMD;
                    end
                    debug_state_reached_internal[8] <= 1;
                end
                READ_BLOCK: begin 
                    cmd_out <= {8'hFF, 8'h51, address, 8'hFF}; 
                    bit_counter <= 55;
                    return_state <= READ_BLOCK_WAIT;
                    state <= SEND_CMD;
                    debug_state_reached_internal[9] <= 1;
                end
                READ_BLOCK_WAIT: begin 
                    if(sclk_sig == 1'b0 && miso == 0) begin 
                        recv_data <= 0; 
                        bit_counter <= 6; 
                        return_state <= READ_BLOCK_DATA; 
                        byte_counter <= 511; 
                        state <= RECEIVE_BYTE; 
                    end
                    sclk_sig <= ~sclk_sig;
                    debug_state_reached_internal[10] <= 1;
                end
                READ_BLOCK_DATA: begin
                    dout <= recv_data; 
                    byte_available <= 1;
                    if (byte_counter == 0) begin 
                        bit_counter <= 7; 
                        return_state <= READ_BLOCK_CRC;
                        state <= RECEIVE_BYTE; 
                    end else begin
                        byte_counter <= byte_counter - 1;
                        return_state <= READ_BLOCK_DATA; 
                        bit_counter <= 7; 
                        state <= RECEIVE_BYTE; 
                    end
                    debug_state_reached_internal[11] <= 1;
                end
                READ_BLOCK_CRC: begin 
                    if (return_state == IDLE) begin 
                         state <= IDLE;
                    end else begin 
                        bit_counter <= 7;
                        return_state <= IDLE; 
                        state <= RECEIVE_BYTE; 
                    end
                    debug_state_reached_internal[12] <= 1;
                end
                SEND_CMD: begin
                    if (sclk_sig == 1'b0) begin 
                        if (bit_counter == 0) begin 
                            state <= RECEIVE_BYTE_WAIT; 
                        end else begin
                            bit_counter <= bit_counter - 1;
                            cmd_out <= {cmd_out[54:0], 1'b1}; 
                        end
                    end
                    sclk_sig <= ~sclk_sig; 
                    debug_state_reached_internal[13] <= 1;
                end
                RECEIVE_BYTE_WAIT: begin 
                    byte_available <= 0; 
                    if (sclk_sig == 1'b0) begin 
                        if (miso == 0) begin 
                            recv_data <= 0;
                            bit_counter <= 6; 
                            state <= RECEIVE_BYTE;
                        end
                    end
                    sclk_sig <= ~sclk_sig;
                    debug_state_reached_internal[14] <= 1;
                end
                RECEIVE_BYTE: begin
                    byte_available <= 0; 
                    if (sclk_sig == 1'b0) begin 
                        recv_data <= {recv_data[6:0], miso}; 
                        if (bit_counter == 0) begin 
                            state <= return_state; 
                        end else begin
                            bit_counter <= bit_counter - 1;
                        end
                    end
                    sclk_sig <= ~sclk_sig;
                    debug_state_reached_internal[15] <= 1; // This might be around line 158
                end
                WRITE_BLOCK_CMD: begin
                    cmd_out <= {8'hFF, 8'h58, address, 8'hFF}; 
                    bit_counter <= 55;
                    return_state <= WRITE_BLOCK_INIT;
                    state <= SEND_CMD;
                end
                WRITE_BLOCK_INIT: begin
                    cmd_mode <= 0; 
                    byte_counter <= WRITE_DATA_SIZE; 
                    state <= WRITE_BLOCK_DATA;
                    ready_for_next_byte <= 0;
                end
                // *** Corrected WRITE_BLOCK_DATA structure ***
                WRITE_BLOCK_DATA: begin
                    if (byte_counter == 0) begin // All bytes (token, data, CRC) sent
                        cmd_mode <= 1; // Switch MOSI back to command output
                        state <= RECEIVE_BYTE_WAIT; // Wait for data response token from card
                        return_state <= WRITE_BLOCK_WAIT; // After token, wait for busy to clear
                    end else begin
                        // Determine data_sig based on byte_counter
                        if (byte_counter == WRITE_DATA_SIZE) begin 
                            data_sig <= 8'hFE; 
                        end else if (byte_counter <= 2) begin 
                            data_sig <= 8'hFF; // Dummy CRC
                        end else begin 
                            data_sig <= din; 
                            ready_for_next_byte <= 1; 
                        end
                        
                        // Common operations for this 'else' branch
                        bit_counter <= 7; 
                        state <= WRITE_BLOCK_BYTE;
                        byte_counter <= byte_counter - 1;
                    end
                    // debug_state_reached_internal for this state if needed (around line 210)
                end
                WRITE_BLOCK_BYTE: begin
                    if (sclk_sig == 1'b0) begin 
                        if (bit_counter == 0) begin 
                            state <= WRITE_BLOCK_DATA; 
                            ready_for_next_byte <= 0; 
                        end else begin
                            data_sig <= {data_sig[6:0], 1'b0}; 
                            bit_counter <= bit_counter - 1;
                        end
                    end
                    sclk_sig <= ~sclk_sig;
                end
                WRITE_BLOCK_WAIT: begin 
                    if (sclk_sig == 1'b0) begin 
                        if (miso == 1) begin 
                            state <= IDLE;
                        end
                    end
                    sclk_sig <= ~sclk_sig;
                end
                default: begin 
                    state <= RST; 
                end
            endcase
        end
    end
    
    assign sclk = sclk_sig;
    assign mosi = cmd_mode ? cmd_out[55] : data_sig[7]; 
    assign ready = (state == IDLE);
    assign debug_state_reached = debug_state_reached_internal;
endmodule