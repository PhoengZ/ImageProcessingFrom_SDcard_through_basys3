module debounce (
    input      clk,
    input      reset,
    input      btn_in,
    output reg btn_out
);
    parameter DEBOUNCE_PERIOD = 250000; // 10ms at 25MHz
    
    reg [(clog2(DEBOUNCE_PERIOD))-1:0] counter = 0;
    reg        btn_state_internal = 0;
    
    function integer clog2;
        input integer value;
        begin
            value = value-1;
            for (clog2=0; value>0; clog2=clog2+1)
                value = value>>1;
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            counter <= 0;
            // Initialize btn_state_internal and btn_out to current btn_in state
            // to avoid a glitch if btn_in is active low and starts pressed.
            btn_state_internal <= btn_in; 
            btn_out <= btn_in;      
        end else begin
            if (btn_in != btn_state_internal) begin
                counter <= 0; // Reset counter if button state changes
                btn_state_internal <= btn_in;
            end else if (counter < DEBOUNCE_PERIOD -1) begin
                counter <= counter + 1; // Increment counter if state is stable
            end else begin
                btn_out <= btn_state_internal; // Update output after debounce period
            end
        end
    end
endmodule