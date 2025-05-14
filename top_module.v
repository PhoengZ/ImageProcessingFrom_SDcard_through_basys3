`timescale 1ns / 1ps

module top(
    input wire          clk100mhz,
    input wire          reset, // External reset button
    input wire          btn,   // Button to change image set
    input wire          miso,
    output wire         mosi,
    output wire         sclk,
    output wire         cs,
    output reg [15:0]   led,

    input wire [15:0]   sw,  // Unused in this specific animation logic
    output wire         hsync,
    output wire         vsync,
    output wire [3:0]   vga_r,
    output wire [3:0]   vga_g,
    output wire [3:0]   vga_b
);
    // Main FSM
    reg [3:0]  main_fsm_state;
    parameter  FSM_INIT_LOAD = 0;
    parameter  FSM_WAIT_SD_READY = 1;
    parameter  FSM_READ_SD_DATA = 2;
    parameter  FSM_END_SECTOR_READ = 3;
    parameter  FSM_ALL_SECTORS_LOADED = 4;
    parameter  FSM_CALC_CHECKSUM = 5;
    parameter  FSM_DISPLAY_CHECKSUM_ON_LED = 6;
    parameter  FSM_VGA_DISPLAY_ACTIVE = 7;

    // Clock and Reset
    wire       clk_25mhz;    // 25MHz clock from clock_divider_by_4
    wire       rst_internal; // Internal reset (now only from external reset)

    // Debounced Button
    wire       btn_debounced;
    reg        btn_prev_state = 0;
    reg        btn_rising_edge = 0;
    reg        change_image_set_req = 0;

    // BRAM Interface
    wire [15:0] bram_dout;
    wire [14:0] bram_addr_muxed; // Address to BRAM (ADDR_WIDTH = 15)
    reg  [15:0] bram_din;
    reg         bram_we;
    reg  [14:0] bram_addr_write_ptr = 0;
    reg  [14:0] bram_addr_read_vga_ptr;
    reg  [14:0] bram_addr_read_checksum_ptr;

    // Instantiate custom Clock Divider
    clock_divider_by_4 clock_gen_inst (
        .clk_100mhz_in(clk100mhz),
        .reset_in(reset), // Use external reset directly
        .clk_25mhz_out(clk_25mhz)
    );
    
    // Internal reset only depends on external reset now
    assign rst_internal = reset; 

    // Instantiate custom Synchronous RAM
    generic_sync_ram #(
        .DATA_WIDTH(16),
        .ADDR_WIDTH(15) // For 2^15 = 32768 words depth
    ) buffer_ram_inst (
        .clk(clk_25mhz),
        .addr(bram_addr_muxed),
        .din(bram_din),
        .we(bram_we),
        .dout(bram_dout)
    );

    assign bram_addr_muxed = (main_fsm_state == FSM_READ_SD_DATA) ? bram_addr_write_ptr :
                             (main_fsm_state == FSM_CALC_CHECKSUM) ? bram_addr_read_checksum_ptr :
                             bram_addr_read_vga_ptr;

    // SD Data Byte Pairing
    reg [7:0]  sd_byte_buffer;
    reg        sd_byte_buffered_flag = 0;

    // Checksum
    reg [31:0] checksum_accumulator = 0;
    reg [15:0] checksum_for_display = 0;
    reg [1:0]  checksum_fsm_state = 0;

    // SD Controller Interface
    reg        sd_read_trigger = 0;
    wire [7:0] sd_data_out;
    wire       sd_byte_ready_sig;
    wire       sd_ctrl_ready_sig;
    wire [4:0] sd_ctrl_fsm_status;
    wire [15:0] sd_ctrl_init_flags;

    // Sector/Image Set Logic
    reg [31:0] current_sd_block_addr = 32'd1000;
    reg [31:0] image_set_base_block_addr = 32'd1000;
    localparam TOTAL_BLOCKS_PER_IMAGE_SET = 72;
    localparam BLOCKS_PER_FRAME = 12;
    reg [9:0]  bytes_read_current_block = 0;
    reg        reading_current_block_flag = 0;
    reg [6:0]  blocks_read_current_set_count = 0;

    // VGA Display & Animation
    wire       vga_video_active_area;
    wire       vga_pixel_tick_dummy; 
    wire [9:0] vga_pixel_x_coord, vga_pixel_y_coord;
    reg [2:0]  current_vga_frame_index = 0;
    reg [23:0] animation_frame_rate_counter = 0;
    localparam ANIMATION_FRAME_RATE_DIVIDER = 24'd2_500_000; 

    localparam IMAGE_WIDTH_PX = 64;
    localparam IMAGE_HEIGHT_PX = 48;
    localparam IMAGE_WORDS_PER_FRAME = IMAGE_WIDTH_PX * IMAGE_HEIGHT_PX;
    
    // Debouncer
    debounce debouncer_inst (
        .clk     (clk_25mhz),
        .reset   (rst_internal),
        .btn_in  (btn),
        .btn_out (btn_debounced)
    );

    // VGA Sync Generator
    vga_sync vga_sync_inst (
        .clk      (clk_25mhz),
        .reset    (rst_internal),
        .hsync    (hsync),
        .vsync    (vsync),
        .video_on (vga_video_active_area),
        .p_tick   (vga_pixel_tick_dummy),
        .x        (vga_pixel_x_coord),
        .y        (vga_pixel_y_coord)
    );

    // VGA Pixel Data Logic
    wire [15:0] vga_pixel_data_raw;
    reg [12:0]  scaled_x_for_image, scaled_y_for_image;
    reg [14:0]  bram_addr_current_frame_base;

    localparam VGA_H_DISPLAY_PX = 640;
    localparam VGA_V_DISPLAY_PX = 480;

    always @* begin
        scaled_x_for_image = vga_pixel_x_coord / (VGA_H_DISPLAY_PX / IMAGE_WIDTH_PX);
        scaled_y_for_image = vga_pixel_y_coord / (VGA_V_DISPLAY_PX / IMAGE_HEIGHT_PX);
        bram_addr_current_frame_base = current_vga_frame_index * IMAGE_WORDS_PER_FRAME;

        if (scaled_x_for_image < IMAGE_WIDTH_PX && scaled_y_for_image < IMAGE_HEIGHT_PX) begin
            bram_addr_read_vga_ptr = bram_addr_current_frame_base + (scaled_y_for_image * IMAGE_WIDTH_PX) + scaled_x_for_image;
        end else begin
            bram_addr_read_vga_ptr = bram_addr_current_frame_base; 
        end
    end
    
    assign vga_pixel_data_raw = (vga_video_active_area && (main_fsm_state == FSM_VGA_DISPLAY_ACTIVE || main_fsm_state == FSM_DISPLAY_CHECKSUM_ON_LED) ) ? bram_dout : 16'h0000;

    assign vga_r = vga_video_active_area ? vga_pixel_data_raw[15:12] : 4'h0;
    assign vga_g = vga_video_active_area ? vga_pixel_data_raw[10:7]  : 4'h0;
    assign vga_b = vga_video_active_area ? vga_pixel_data_raw[4:1]   : 4'h0;

    // Animation Frame Update
    always @(posedge clk_25mhz) begin
        if (rst_internal) begin
            current_vga_frame_index <= 0;
            animation_frame_rate_counter <= 0;
        end else if (main_fsm_state == FSM_VGA_DISPLAY_ACTIVE || main_fsm_state == FSM_DISPLAY_CHECKSUM_ON_LED) begin
            if (animation_frame_rate_counter >= ANIMATION_FRAME_RATE_DIVIDER - 1) begin
                animation_frame_rate_counter <= 0;
                current_vga_frame_index <= (current_vga_frame_index == 5) ? 0 : current_vga_frame_index + 1;
            end else begin
                animation_frame_rate_counter <= animation_frame_rate_counter + 1;
            end
        end
    end

    // Button Press Detection & Image Set Change Request
    always @(posedge clk_25mhz) begin
        if (rst_internal) begin
            btn_prev_state <= 0;
            btn_rising_edge <= 0;
            change_image_set_req <= 0;
        end else begin
            btn_prev_state <= btn_debounced;
            btn_rising_edge <= ~btn_prev_state & btn_debounced; 
            
            if (btn_rising_edge && (main_fsm_state == FSM_VGA_DISPLAY_ACTIVE || main_fsm_state == FSM_DISPLAY_CHECKSUM_ON_LED)) begin
                change_image_set_req <= 1;
            end else if (main_fsm_state == FSM_INIT_LOAD && change_image_set_req) begin // Consume request when FSM acts on it
                 change_image_set_req <= 0;
            end
        end
    end

    // Main FSM Logic
    always @(posedge clk_25mhz) begin
        if (rst_internal) begin
            main_fsm_state <= FSM_INIT_LOAD;
            sd_read_trigger <= 0;
            reading_current_block_flag <= 0;
            bram_addr_write_ptr <= 0;
            bytes_read_current_block <= 0;
            sd_byte_buffered_flag <= 0;
            bram_we <= 0;
            blocks_read_current_set_count <= 0;
            image_set_base_block_addr <= 32'd1000; 
            current_sd_block_addr <= 32'd1000;
            checksum_accumulator <= 0;
            bram_addr_read_checksum_ptr <= 0;
            checksum_fsm_state <= 0;
            checksum_for_display <= 0;
           // change_image_set_req is reset in its own always block or when consumed
        end else begin
            bram_we <= 0; 

            if (change_image_set_req && (main_fsm_state == FSM_VGA_DISPLAY_ACTIVE || main_fsm_state == FSM_DISPLAY_CHECKSUM_ON_LED) ) begin
                     if (image_set_base_block_addr == 32'd1000) image_set_base_block_addr <= 32'd1072;
                else if (image_set_base_block_addr == 32'd1072) image_set_base_block_addr <= 32'd1144;
                else if (image_set_base_block_addr == 32'd1144) image_set_base_block_addr <= 32'd1216;
                else if (image_set_base_block_addr == 32'd1216) image_set_base_block_addr <= 32'd1288;
                else if (image_set_base_block_addr == 32'd1288) image_set_base_block_addr <= 32'd1360; 
                else                                            image_set_base_block_addr <= 32'd1000; 

                blocks_read_current_set_count <= 0;
                bram_addr_write_ptr <= 0;
                main_fsm_state <= FSM_INIT_LOAD;
            end else begin
                case (main_fsm_state)
                    FSM_INIT_LOAD: begin
                        current_sd_block_addr <= image_set_base_block_addr + blocks_read_current_set_count;
                        bytes_read_current_block <= 0;
                        sd_read_trigger <= 0;
                        reading_current_block_flag <= 0;
                        sd_byte_buffered_flag <= 0;
                        
                        if (blocks_read_current_set_count >= TOTAL_BLOCKS_PER_IMAGE_SET) begin
                            main_fsm_state <= FSM_ALL_SECTORS_LOADED;
                        end else begin
                            main_fsm_state <= FSM_WAIT_SD_READY;
                        end
                    end
                    
                    FSM_WAIT_SD_READY: begin
                        if (sd_ctrl_ready_sig) begin
                            main_fsm_state <= FSM_READ_SD_DATA;
                        end
                    end
                    
                    FSM_READ_SD_DATA: begin
                        if (sd_ctrl_ready_sig && !reading_current_block_flag && !sd_read_trigger) begin
                            sd_read_trigger <= 1;
                            reading_current_block_flag <= 1;
                        end else if (sd_read_trigger) begin
                            sd_read_trigger <= 0; 
                        end
                        
                        if (reading_current_block_flag && sd_byte_ready_sig) begin
                            if (!sd_byte_buffered_flag) begin
                                sd_byte_buffer <= sd_data_out;
                                sd_byte_buffered_flag <= 1;
                            end else begin
                                bram_din <= {sd_byte_buffer, sd_data_out}; 
                                bram_we <= 1;
                                bram_addr_write_ptr <= bram_addr_write_ptr + 1;
                                sd_byte_buffered_flag <= 0;
                            end
                            bytes_read_current_block <= bytes_read_current_block + 1;
                            
                            if (bytes_read_current_block == 511) begin 
                                reading_current_block_flag <= 0;
                                main_fsm_state <= FSM_END_SECTOR_READ;
                                blocks_read_current_set_count <= blocks_read_current_set_count + 1;
                            end
                        end
                    end
                    
                    FSM_END_SECTOR_READ: begin
                        if (sd_ctrl_ready_sig) begin 
                           main_fsm_state <= FSM_INIT_LOAD; 
                        end
                    end

                    FSM_ALL_SECTORS_LOADED: begin
                        checksum_accumulator <= 0;
                        bram_addr_read_checksum_ptr <= 0;
                        checksum_fsm_state <= 0;
                        main_fsm_state <= FSM_CALC_CHECKSUM;
                    end
                    
                    FSM_CALC_CHECKSUM: begin
                        case (checksum_fsm_state)
                            0: begin 
                                checksum_fsm_state <= 1; 
                            end
                            1: begin 
                                checksum_accumulator <= checksum_accumulator + bram_dout;
                                if (bram_addr_read_checksum_ptr < (TOTAL_BLOCKS_PER_IMAGE_SET * 256) - 1) begin // Max BRAM address used
                                    bram_addr_read_checksum_ptr <= bram_addr_read_checksum_ptr + 1;
                                    checksum_fsm_state <= 0; 
                                end else begin
                                    checksum_for_display <= checksum_accumulator[31:16] ^ checksum_accumulator[15:0];
                                    main_fsm_state <= FSM_DISPLAY_CHECKSUM_ON_LED;
                                end
                            end
                        endcase
                    end
                    
                    FSM_DISPLAY_CHECKSUM_ON_LED: begin
                        main_fsm_state <= FSM_VGA_DISPLAY_ACTIVE;
                    end
                    
                    FSM_VGA_DISPLAY_ACTIVE: begin
                        // Stays here, animation runs, button press handled above
                    end
                    
                    default: main_fsm_state <= FSM_INIT_LOAD;
                endcase
            end
        end
    end
    
    // SD Controller Instantiation
    sd_controller sd_controller_inst (
        .cs             (cs),
        .mosi           (mosi),
        .miso           (miso),
        .sclk           (sclk),
        .rd             (sd_read_trigger),
        .dout           (sd_data_out),
        .byte_available (sd_byte_ready_sig),
        .wr             (1'b0), 
        .din            (8'h00),
        .ready_for_next_byte(), 
        .reset          (rst_internal),
        .ready          (sd_ctrl_ready_sig),
        .address        (current_sd_block_addr),
        .clk            (clk_25mhz),
        .status         (sd_ctrl_fsm_status),
        .debug_state_reached (sd_ctrl_init_flags)
    );
    
    // LED Debug Output
    always @(posedge clk_25mhz) begin
        if (rst_internal) begin
            led <= 16'h0000;
        end else begin
            led[15] <= sd_ctrl_init_flags[8]; 
            led[14] <= sd_ctrl_init_flags[7]; 
            led[13] <= sd_ctrl_init_flags[2]; 
            led[12] <= cs;
            led[11] <= sd_read_trigger;
            led[10] <= sd_ctrl_ready_sig;
            led[9]  <= reading_current_block_flag;
            led[8:5]<= main_fsm_state;
            led[4:0]<= sd_ctrl_fsm_status;

            if (main_fsm_state == FSM_DISPLAY_CHECKSUM_ON_LED) begin
                led <= checksum_for_display;
            end else if (main_fsm_state == FSM_VGA_DISPLAY_ACTIVE) begin
                 led[15:8] <= image_set_base_block_addr[15:8]; 
                 led[7:3]  <= blocks_read_current_set_count[4:0];  
                 led[2:0]  <= current_vga_frame_index;
            end else if (main_fsm_state == FSM_CALC_CHECKSUM) begin
                led <= bram_addr_read_checksum_ptr; 
            end
        end
    end
endmodule