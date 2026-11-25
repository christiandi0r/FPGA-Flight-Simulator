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

// Constant declaration
localparam KEY_COLOR = 0;

// Video data stream
logic [CD-1:0] frame_rgb8;
logic [CD-1:0] bar_rgb7;
logic [CD-1:0] gray_rgb6;
logic [CD-1:0] user5_rgb5;
logic [CD-1:0] user4_rgb4;
logic [CD-1:0] cloud_rgb3;
logic [CD-1:0] hud_rgb;
logic [CD-1:0] osd_rgb2;

// HUD attitude signals
logic signed [15:0] hud_pitch_offset;
logic signed [15:0] hud_roll_slope;

// VGA synchronization input
logic [CD:0] line_data_in;

// Frame counter
logic inc, frame_start;
logic [10:0] x, y;

// Video synchronization delay
logic [13:1] frame_start_d_reg;
logic [13:1] inc_d_reg;

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
// Delay frame-start and valid signals
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
// RGB-to-grayscale core - V5_GRAY
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
// Three snowcapped mountains - V3_MOUNTAIN
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
// Three moving clouds - V4_CLOUD
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

    .x(x),
    .y(y),

    .cs(slot_cs_array[`V2_OSD]),
    .write(slot_mem_wr_array[`V2_OSD]),
    .addr(slot_reg_addr_array[`V2_OSD]),
    .wr_data(slot_wr_data_array[`V2_OSD]),

    .si_rgb(hud_rgb),
    .so_rgb(osd_rgb2)
);

// ------------------------------------------------------------
// VGA synchronization - V0_SYNC
// ------------------------------------------------------------
assign line_data_in =
    {osd_rgb2, frame_start_d_reg[13]};

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
