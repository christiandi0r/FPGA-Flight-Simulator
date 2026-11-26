`include "chu_io_map.svh"

module video_sys_daisy
#(
    parameter CD = 12,
    parameter VRAM_DATA_WIDTH = 9
)
(
    input logic clk_sys,
    input logic clk_25M,
    input logic reset_sys,

    // FPro bus
    input logic video_cs,
    input logic video_wr,
    input logic [20:0] video_addr,
    input logic [31:0] video_wr_data,

    // VGA monitor
    output logic vsync, hsync,
    output logic [11:0] rgb
);

// ------------------------------------------------------------
// Constants
// ------------------------------------------------------------
localparam [CD-1:0] KEY_COLOR = 12'hF0F;
localparam [CD-1:0] BORDER_COLOR = 12'h0FF;
localparam [CD-1:0] BLACK = 12'h000;
localparam [CD-1:0] WHITE = 12'hFFF;


 // ------------------------------------------------------------
 // Telemetry panel dimensions
 // ------------------------------------------------------------

 // Top telemetry text adjustment
localparam [10:0] TOP_TEXT_OFFSET = 11'd5;

// Top panels - both 112 x 24 pixels
localparam [10:0] PITCH_RIGHT = 11'd111;
localparam [10:0] ROLL_LEFT = 11'd528;
localparam [10:0] TOP_BOTTOM = 11'd23;

// Bottom panels - both 120 x 36 pixels
localparam [10:0] BOTTOM_LEFT_RIGHT = 11'd119;
localparam [10:0] BOTTOM_RIGHT_LEFT = 11'd520;

localparam [10:0] BOTTOM_TOP = 11'd444;
localparam [10:0] BOTTOM_DIVIDER = 11'd463;
localparam [10:0] BOTTOM_BOTTOM = 11'd479;

// ------------------------------------------------------------
// Video signals
// ------------------------------------------------------------
logic [CD-1:0] frame_rgb8;
logic [CD-1:0] bar_rgb7;
logic [CD-1:0] gray_rgb6;
logic [CD-1:0] user5_rgb5;
logic [CD-1:0] user4_rgb4;
logic [CD-1:0] cloud_rgb3;
logic [CD-1:0] hud_rgb;
logic [CD-1:0] osd_rgb2;
logic [CD-1:0] panel_rgb;
logic [CD-1:0] osd_background_rgb;

// HUD attitude signals
logic signed [15:0] hud_pitch_offset;
logic signed [15:0] hud_roll_slope;

// VGA synchronization
logic [CD:0] line_data_in;
logic inc, frame_start;
logic [10:0] x, y;

logic [13:1] frame_start_d_reg;
logic [13:1] inc_d_reg;

// ------------------------------------------------------------
// OSD coordinate alignment
// ------------------------------------------------------------
logic [10:0] osd_x_pipe [0:12];
logic [10:0] osd_y_pipe [0:12];

// Adjusted OSD coordinates
logic [10:0] osd_y_adjusted;
logic top_text_region;
logic top_text_clip;

// Panel coordinates
logic [10:0] panel_x;
logic [10:0] panel_y;

// Panel signals
logic panel_region;
logic panel_border;
logic degree_pixel;

logic top_left_border;
logic top_right_border;
logic bottom_left_border;
logic bottom_right_border;

// Frame buffer interface
logic frame_wr, frame_cs;
logic [19:0] frame_addr;
logic [31:0] frame_wr_data;

// Video slot interface
logic [7:0] slot_cs_array;
logic [7:0] slot_mem_wr_array;
logic [13:0] slot_reg_addr_array [7:0];
logic [31:0] slot_wr_data_array [7:0];

// ------------------------------------------------------------
// VGA synchronization delay
// ------------------------------------------------------------
always_ff @(posedge clk_sys, posedge reset_sys)
begin
    if (reset_sys)
    begin
        frame_start_d_reg <= 0;
        inc_d_reg <= 0;
    end
    else
    begin
        frame_start_d_reg[1] <= frame_start;
        inc_d_reg[1] <= inc;

        for (integer i = 2; i <= 13; i++)
        begin
            frame_start_d_reg[i] <=
                frame_start_d_reg[i-1];

            inc_d_reg[i] <=
                inc_d_reg[i-1];
        end
    end
end

// ------------------------------------------------------------
// OSD coordinate delay
// ------------------------------------------------------------
always_ff @(posedge clk_sys, posedge reset_sys)
begin
    if (reset_sys)
    begin
        for (integer i = 0; i < 13; i++)
        begin
            osd_x_pipe[i] <= 0;
            osd_y_pipe[i] <= 0;
        end
    end
    else
    begin
        osd_x_pipe[0] <= x;
        osd_y_pipe[0] <= y;

        for (integer i = 1; i < 13; i++)
        begin
            osd_x_pipe[i] <= osd_x_pipe[i-1];
            osd_y_pipe[i] <= osd_y_pipe[i-1];
        end
    end
end

// ------------------------------------------------------------
// Frame counter
// ------------------------------------------------------------
frame_counter
#(
    .HMAX(640),
    .VMAX(480)
)
frame_counter_unit
(
    .clk(clk_sys),
    .reset(reset_sys),

    .sync_clr(1'b0),
    .inc(inc),

    .hcount(x),
    .vcount(y),

    .frame_start(frame_start),
    .frame_end()
);

// ------------------------------------------------------------
// Video address decoder
// ------------------------------------------------------------
chu_video_controller ctrl_unit
(
    .video_cs(video_cs),
    .video_wr(video_wr),
    .video_addr(video_addr),
    .video_wr_data(video_wr_data),

    .frame_cs(frame_cs),
    .frame_wr(frame_wr),
    .frame_addr(frame_addr),
    .frame_wr_data(frame_wr_data),

    .slot_cs_array(slot_cs_array),
    .slot_mem_wr_array(slot_mem_wr_array),
    .slot_reg_addr_array(slot_reg_addr_array),
    .slot_wr_data_array(slot_wr_data_array)
);

// ------------------------------------------------------------
// Frame buffer
// ------------------------------------------------------------
chu_frame_buffer_core
#(
    .CD(CD),
    .DW(VRAM_DATA_WIDTH)
)
buf_unit
(
    .clk(clk_sys),
    .reset(reset_sys),

    .x(x),
    .y(y),

    .cs(frame_cs),
    .write(frame_wr),
    .addr(frame_addr),
    .wr_data(video_wr_data),

    .si_rgb(12'h008),
    .so_rgb(frame_rgb8)
);

// ------------------------------------------------------------
// VGA bar generator - V6_BAR
// ------------------------------------------------------------
chu_vga_bar_core v6_bar_unit
(
    .clk(clk_sys),
    .reset(reset_sys),

    .x(x),
    .y(y),

    .cs(slot_cs_array[`V6_BAR]),
    .write(slot_mem_wr_array[`V6_BAR]),
    .addr(slot_reg_addr_array[`V6_BAR]),
    .wr_data(slot_wr_data_array[`V6_BAR]),

    .si_rgb(frame_rgb8),
    .so_rgb(bar_rgb7)
);

// ------------------------------------------------------------
// Grayscale core - V5_GRAY
// ------------------------------------------------------------
chu_rgb2gray_core v5_gray_unit
(
    .clk(clk_sys),
    .reset(reset_sys),

    .cs(slot_cs_array[`V5_GRAY]),
    .write(slot_mem_wr_array[`V5_GRAY]),
    .addr(slot_reg_addr_array[`V5_GRAY]),
    .wr_data(slot_wr_data_array[`V5_GRAY]),

    .si_rgb(bar_rgb7),
    .so_rgb(gray_rgb6)
);

// ------------------------------------------------------------
// Artificial horizon - V1_HORIZON
// ------------------------------------------------------------
flight_horizon_core v1_horizon_unit
(
    .clk(clk_sys),
    .reset(reset_sys),

    .x(x),
    .y(y),

    .cs(slot_cs_array[`V1_HORIZON]),
    .write(slot_mem_wr_array[`V1_HORIZON]),
    .addr(slot_reg_addr_array[`V1_HORIZON]),
    .wr_data(slot_wr_data_array[`V1_HORIZON]),

    .si_rgb(gray_rgb6),
    .so_rgb(user5_rgb5),

    .hud_pitch_offset(hud_pitch_offset),
    .hud_roll_slope(hud_roll_slope)
);

// ------------------------------------------------------------
// Snowcapped mountains - V3_MOUNTAIN
// ------------------------------------------------------------
flight_mountain_core v3_mountain_unit
(
    .clk(clk_sys),
    .reset(reset_sys),

    .x(x),
    .y(y),

    .cs(slot_cs_array[`V3_MOUNTAIN]),
    .write(slot_mem_wr_array[`V3_MOUNTAIN]),
    .addr(slot_reg_addr_array[`V3_MOUNTAIN]),
    .wr_data(slot_wr_data_array[`V3_MOUNTAIN]),

    .si_rgb(user5_rgb5),
    .so_rgb(user4_rgb4)
);

// ------------------------------------------------------------
// Moving clouds - V4_CLOUD
// ------------------------------------------------------------
flight_cloud_core v4_cloud_unit
(
    .clk(clk_sys),
    .reset(reset_sys),

    .x(x),
    .y(y),

    .cs(slot_cs_array[`V4_CLOUD]),
    .write(slot_mem_wr_array[`V4_CLOUD]),
    .addr(slot_reg_addr_array[`V4_CLOUD]),
    .wr_data(slot_wr_data_array[`V4_CLOUD]),

    .si_rgb(user4_rgb4),
    .so_rgb(cloud_rgb3)
);

// ------------------------------------------------------------
// Attitude indicator HUD
// ------------------------------------------------------------
flight_hud_core hud_unit
(
    .clk(clk_sys),
    .reset(reset_sys),

    .x(x),
    .y(y),

    .pitch_offset(hud_pitch_offset),
    .roll_slope(hud_roll_slope),

    .si_rgb(cloud_rgb3),
    .so_rgb(hud_rgb)
);

// ============================================================
// TELEMETRY PANELS
//
// Black backgrounds, cyan borders, white text
//
// Top-left:       112 x 24
// Top-right:      114 x 24
// Bottom-left:    124 x 40
// Bottom-right:   120 x 40
// ============================================================

// Coordinates aligned with OSD rendering
assign panel_x = osd_x_pipe[12];
assign panel_y = osd_y_pipe[12];

// ------------------------------------------------------------
// Panel background regions
// ------------------------------------------------------------
assign panel_region =

    // Top-left PITCH
    ((panel_x <= PITCH_RIGHT) &&
     (panel_y <= TOP_BOTTOM)) ||

    // Top-right ROLL
    ((panel_x >= ROLL_LEFT) &&
     (panel_x <= 639) &&
     (panel_y <= TOP_BOTTOM)) ||

    // Bottom-left HDG / ALT
    ((panel_x <= BOTTOM_LEFT_RIGHT) &&
     (panel_y >= BOTTOM_TOP) &&
     (panel_y <= BOTTOM_BOTTOM)) ||

    // Bottom-right SPD / VS
    ((panel_x >= BOTTOM_RIGHT_LEFT) &&
     (panel_x <= 639) &&
     (panel_y >= BOTTOM_TOP) &&
     (panel_y <= BOTTOM_BOTTOM));

// ------------------------------------------------------------
// Draw black background BEFORE the OSD
// ------------------------------------------------------------
assign osd_background_rgb =
    panel_region ? BLACK : hud_rgb;

// ============================================================
// TOP TELEMETRY TEXT ALIGNMENT
//
// PITCH and ROLL are shifted down by 3 pixels.
// Bottom telemetry remains unchanged.
// ============================================================

assign top_text_region =
    (osd_y_pipe[10] <= TOP_BOTTOM) &&
    (
        (osd_x_pipe[10] <= PITCH_RIGHT) ||
        ((osd_x_pipe[10] >= ROLL_LEFT) &&
         (osd_x_pipe[10] <= 11'd639))
    );

// Shift OSD character lookup down 3 pixels
assign osd_y_adjusted =
    top_text_region
        ? (
            (osd_y_pipe[10] >= TOP_TEXT_OFFSET)
                ? osd_y_pipe[10] - TOP_TEXT_OFFSET
                : 11'd480
          )
        : osd_y_pipe[10];

// Clip the first three rows to prevent wrapping
assign top_text_clip =
    (panel_y < TOP_TEXT_OFFSET) &&
    (
        (panel_x <= PITCH_RIGHT) ||
        ((panel_x >= ROLL_LEFT) &&
         (panel_x <= 11'd639))
    );

// ------------------------------------------------------------
// On-screen display - V2_OSD
// ------------------------------------------------------------
chu_vga_osd_core
#(
    .CD(CD),
    .KEY_COLOR(KEY_COLOR)
)
v2_osd_unit
(
    .clk(clk_sys),
    .reset(reset_sys),

    .x(osd_x_pipe[10]),
    .y(osd_y_adjusted),

    .cs(slot_cs_array[`V2_OSD]),
    .write(slot_mem_wr_array[`V2_OSD]),
    .addr(slot_reg_addr_array[`V2_OSD]),
    .wr_data(slot_wr_data_array[`V2_OSD]),

    .si_rgb(osd_background_rgb),
    .so_rgb(osd_rgb2)
);

// ============================================================
// CYAN PANEL BORDERS
//
// Border thickness: 2 pixels
// Bottom panel divider: 1 pixel
// ============================================================

// ------------------------------------------------------------
// Top-left PITCH border
// ------------------------------------------------------------
assign top_left_border =
    (panel_x <= PITCH_RIGHT) &&
    (panel_y <= TOP_BOTTOM) &&
    (
        (panel_x <= 1) ||
        (panel_x >= PITCH_RIGHT - 1) ||
        (panel_y <= 1) ||
        (panel_y >= TOP_BOTTOM - 1)
    );

// ------------------------------------------------------------
// Top-right ROLL border
// ------------------------------------------------------------
assign top_right_border =
    (panel_x >= ROLL_LEFT) &&
    (panel_x <= 639) &&
    (panel_y <= TOP_BOTTOM) &&
    (
        (panel_x <= ROLL_LEFT + 1) ||
        (panel_x >= 638) ||
        (panel_y <= 1) ||
        (panel_y >= TOP_BOTTOM - 1)
    );

// ------------------------------------------------------------
// Bottom-left HDG / ALT border - narrower
// ------------------------------------------------------------
assign bottom_left_border =
    (panel_x <= BOTTOM_LEFT_RIGHT) &&
    (panel_y >= BOTTOM_TOP) &&
    (panel_y <= BOTTOM_BOTTOM) &&
    (
        (panel_x <= 1) ||
        (panel_x >= BOTTOM_LEFT_RIGHT - 1) ||
        (panel_y <= BOTTOM_TOP + 1) ||
        (panel_y >= BOTTOM_BOTTOM - 1) ||
        (panel_y == BOTTOM_DIVIDER)
    );

// ------------------------------------------------------------
// Bottom-right SPD / VS border - narrower
// ------------------------------------------------------------
assign bottom_right_border =
    (panel_x >= BOTTOM_RIGHT_LEFT) &&
    (panel_x <= 639) &&
    (panel_y >= BOTTOM_TOP) &&
    (panel_y <= BOTTOM_BOTTOM) &&
    (
        (panel_x <= BOTTOM_RIGHT_LEFT + 1) ||
        (panel_x >= 638) ||
        (panel_y <= BOTTOM_TOP + 1) ||
        (panel_y >= BOTTOM_BOTTOM - 1) ||
        (panel_y == BOTTOM_DIVIDER)
    );

// ------------------------------------------------------------
// Combine cyan borders
// ------------------------------------------------------------
assign panel_border =
    top_left_border ||
    top_right_border ||
    bottom_left_border ||
    bottom_right_border;

// ============================================================
// DEGREE SYMBOLS
// ============================================================

// ------------------------------------------------------------
// 5x5 degree symbol
// ------------------------------------------------------------
function automatic logic degree_symbol
(
    input logic [10:0] px,
    input logic [10:0] py,
    input logic [10:0] cx,
    input logic [10:0] cy
);
begin
    degree_symbol =
        (
            ((px == cx + 1) ||
             (px == cx + 2) ||
             (px == cx + 3)) &&
            ((py == cy) ||
             (py == cy + 4))
        ) ||
        (
            ((px == cx) ||
             (px == cx + 4)) &&
            (py >= cy + 1) &&
            (py <= cy + 3)
        );
end
endfunction

// ------------------------------------------------------------
// Degree symbol positions
//
// PITCH: moved up 2 pixels, Y 8 -> 6
// ROLL:  moved up 2 pixels, Y 8 -> 6
// HDG:   unchanged
// ------------------------------------------------------------
assign degree_pixel =
    degree_symbol(
        panel_x, panel_y,
        11'd100, 11'd6
    ) ||
    degree_symbol(
        panel_x, panel_y,
        11'd628, 11'd6
    ) ||
    degree_symbol(
        panel_x, panel_y,
        11'd68, 11'd451
    );

// ------------------------------------------------------------
// Final RGB priority
//
// 1. Cyan panel borders
// 2. White degree symbols
// 3. Black clipping for top text
// 4. OSD / black panels / scenery
// ------------------------------------------------------------
assign panel_rgb =
    panel_border ? BORDER_COLOR :
    degree_pixel ? WHITE :
    top_text_clip ? BLACK :
    osd_rgb2;

// ------------------------------------------------------------
// VGA synchronization - V0_SYNC
// ------------------------------------------------------------
assign line_data_in =
    {panel_rgb, frame_start_d_reg[13]};

chu_vga_sync_core
#(
    .CD(CD)
)
v0_vga_sync_unit
(
    .clk_sys(clk_sys),
    .clk_25M(clk_25M),
    .reset(reset_sys),

    .cs(slot_cs_array[`V0_SYNC]),
    .write(slot_mem_wr_array[`V0_SYNC]),
    .addr(slot_reg_addr_array[`V0_SYNC]),
    .wr_data(slot_wr_data_array[`V0_SYNC]),

    .si_data(line_data_in),
    .si_valid(inc_d_reg[13]),
    .si_ready(inc),

    .hsync(hsync),
    .vsync(vsync),
    .rgb(rgb)
);

endmodule
