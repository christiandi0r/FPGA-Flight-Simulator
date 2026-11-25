module flight_cloud_core
(
    input logic clk, reset,
    input logic [10:0] x, y,

    // FPro video slot interface
    input logic cs,
    input logic write,
    input logic [13:0] addr,
    input logic [31:0] wr_data,

    // Video interface
    input logic [11:0] si_rgb,
    output logic [11:0] so_rgb
);

// Register addresses
localparam BYPASS_REG = 14'h2000;

localparam CLOUD0_X_REG = 14'h2001;
localparam CLOUD0_Y_REG = 14'h2002;

localparam CLOUD1_X_REG = 14'h2003;
localparam CLOUD1_Y_REG = 14'h2004;

localparam CLOUD2_X_REG = 14'h2005;
localparam CLOUD2_Y_REG = 14'h2006;

// Colors
localparam SKY_COLOR   = 12'h49C;
localparam CLOUD_COLOR = 12'hEEF;

// Cloud position registers
logic signed [15:0] cloud_x [0:2];
logic signed [15:0] cloud_y [0:2];

logic bypass_reg;

// VGA coordinate delay
// Align cloud coordinates with the incoming
// mountain RGB stream.
logic [10:0] x_pipe [0:8];
logic [10:0] y_pipe [0:8];

// Relative pixel coordinates
logic signed [16:0] dx [0:2];
logic signed [16:0] dy [0:2];

// Cloud drawing signals
logic cloud_pixel [0:2];
logic draw_cloud;

logic [11:0] rgb_next;

// ------------------------------------------------------------
// Register interface
// ------------------------------------------------------------
always_ff @(posedge clk, posedge reset)
begin
    if (reset)
    begin
        bypass_reg <= 1'b0;

        // Initial static cloud positions
        cloud_x[0] <= 16'sd110;
        cloud_y[0] <= 16'sd100;

        cloud_x[1] <= 16'sd320;
        cloud_y[1] <= 16'sd80;

        cloud_x[2] <= 16'sd525;
        cloud_y[2] <= 16'sd115;
    end
    else if (cs && write)
    begin
        case (addr)
            BYPASS_REG:
                bypass_reg <= wr_data[0];

            CLOUD0_X_REG:
                cloud_x[0] <= $signed(wr_data[15:0]);

            CLOUD0_Y_REG:
                cloud_y[0] <= $signed(wr_data[15:0]);

            CLOUD1_X_REG:
                cloud_x[1] <= $signed(wr_data[15:0]);

            CLOUD1_Y_REG:
                cloud_y[1] <= $signed(wr_data[15:0]);

            CLOUD2_X_REG:
                cloud_x[2] <= $signed(wr_data[15:0]);

            CLOUD2_Y_REG:
                cloud_y[2] <= $signed(wr_data[15:0]);

            default: ;
        endcase
    end
end

// ------------------------------------------------------------
// VGA coordinate alignment
// ------------------------------------------------------------
always_ff @(posedge clk, posedge reset)
begin
    if (reset)
    begin
        for (integer i = 0; i < 9; i++)
        begin
            x_pipe[i] <= 0;
            y_pipe[i] <= 0;
        end
    end
    else
    begin
        x_pipe[0] <= x;
        y_pipe[0] <= y;

        for (integer i = 1; i < 9; i++)
        begin
            x_pipe[i] <= x_pipe[i-1];
            y_pipe[i] <= y_pipe[i-1];
        end
    end
end

// ------------------------------------------------------------
// Relative cloud coordinates
// ------------------------------------------------------------
always_comb
begin
    for (integer i = 0; i < 3; i++)
    begin
        dx[i] =
            $signed({1'b0, x_pipe[8]}) -
            $signed(cloud_x[i]);

        dy[i] =
            $signed({1'b0, y_pipe[8]}) -
            $signed(cloud_y[i]);
    end
end

// ------------------------------------------------------------
// Cloud shape
//
// Built from three overlapping rectangular sections:
// lower cloud body and two upper puffs.
//
// The shape is intentionally simple to minimize LUT usage.
// ------------------------------------------------------------
function automatic logic inside_cloud
(
    input logic signed [16:0] px,
    input logic signed [16:0] py
);
begin
    inside_cloud = 1'b0;

    // Main lower cloud body
    if ((px >= -17'sd36) &&
        (px <=  17'sd36) &&
        (py >= -17'sd4) &&
        (py <=  17'sd12))
    begin
        inside_cloud = 1'b1;
    end

    // Upper-left puff
    if ((px >= -17'sd24) &&
        (px <=  17'sd2) &&
        (py >= -17'sd16) &&
        (py <=  17'sd5))
    begin
        inside_cloud = 1'b1;
    end

    // Upper-right puff
    if ((px >= -17'sd2) &&
        (px <=  17'sd25) &&
        (py >= -17'sd23) &&
        (py <=  17'sd5))
    begin
        inside_cloud = 1'b1;
    end
end
endfunction

// ------------------------------------------------------------
// Draw three clouds
// ------------------------------------------------------------
always_comb
begin
    cloud_pixel[0] = inside_cloud(dx[0], dy[0]);
    cloud_pixel[1] = inside_cloud(dx[1], dy[1]);
    cloud_pixel[2] = inside_cloud(dx[2], dy[2]);

    draw_cloud =
        cloud_pixel[0] ||
        cloud_pixel[1] ||
        cloud_pixel[2];

    // Transparent by default
    rgb_next = si_rgb;

    // Clouds only render over sky pixels.
    // Mountains, ground, and other colors pass through.
    if (!bypass_reg &&
        (si_rgb == SKY_COLOR) &&
        draw_cloud)
    begin
        rgb_next = CLOUD_COLOR;
    end
end

// ------------------------------------------------------------
// One-stage registered video output
// ------------------------------------------------------------
always_ff @(posedge clk, posedge reset)
begin
    if (reset)
        so_rgb <= 12'h000;
    else
        so_rgb <= rgb_next;
end

endmodule
