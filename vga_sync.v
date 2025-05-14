module vga_sync (
    input wire clk, // Should be pixel clock (e.g., 25MHz for 640x480@60Hz)
    input wire reset,
    output wire hsync, // Horizontal sync
    output wire vsync, // Vertical sync
    output wire video_on, // Active display area
    output wire p_tick,   // Pixel tick (same as clk if clk is pixel_clk)
    output wire [9:0] x,  // Horizontal pixel coordinate
    output wire [9:0] y   // Vertical pixel coordinate
);
    // VGA 640x480 @ 60Hz Timing Parameters (approx for 25MHz pixel clock)
    localparam H_DISPLAY    = 640; // Active display width
    localparam H_FP         = 16;  // Horizontal Front Porch
    localparam H_SYNC_PULSE = 96;  // Horizontal Sync Pulse Width
    localparam H_BP         = 48;  // Horizontal Back Porch
    localparam H_TOTAL      = H_DISPLAY + H_FP + H_SYNC_PULSE + H_BP; // = 800

    localparam V_DISPLAY    = 480; // Active display height
    localparam V_FP         = 10;  // Vertical Front Porch
    localparam V_SYNC_PULSE = 2;   // Vertical Sync Pulse Width
    localparam V_BP         = 33;  // Vertical Back Porch
    localparam V_TOTAL      = V_DISPLAY + V_FP + V_SYNC_PULSE + V_BP; // = 525

    reg [9:0] h_count = 0;
    reg [9:0] v_count = 0;

    assign p_tick = 1'b1; // Assuming input clk is the pixel clock

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            h_count <= 0;
            v_count <= 0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 0;
                if (v_count == V_TOTAL - 1) begin
                    v_count <= 0;
                end else begin
                    v_count <= v_count + 1;
                end
            end else begin
                h_count <= h_count + 1;
            end
        end
    end

    // HSync is active LOW during H_SYNC_PULSE period, after H_DISPLAY and H_FP
    assign hsync = ~((h_count >= H_DISPLAY + H_FP) && (h_count < H_DISPLAY + H_FP + H_SYNC_PULSE));
    // VSync is active LOW during V_SYNC_PULSE period, after V_DISPLAY and V_FP
    assign vsync = ~((v_count >= V_DISPLAY + V_FP) && (v_count < V_DISPLAY + V_FP + V_SYNC_PULSE));
    
    assign video_on = (h_count < H_DISPLAY) && (v_count < V_DISPLAY);
    
    assign x = h_count;
    assign y = v_count;
endmodule