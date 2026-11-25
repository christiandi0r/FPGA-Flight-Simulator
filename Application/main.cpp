#include "chu_init.h"
#include "gpio_cores.h"
#include "spi_core.h"
#include "vga_core.h"
#include <cmath>
#include <cstdint>

// Instantiate SPI, switches, and VGA cores
SpiCore spi(get_slot_addr(BRIDGE_BASE, S9_SPI));
GpiCore sw(get_slot_addr(BRIDGE_BASE, S3_SW));

GpvCore horizon(get_sprite_addr(BRIDGE_BASE, V1_HORIZON));
GpvCore mountain(get_sprite_addr(BRIDGE_BASE, V3_MOUNTAIN));
GpvCore clouds(get_sprite_addr(BRIDGE_BASE, V4_CLOUD));

// ADXL362 registers
const uint8_t RD_CMD = 0x0B;
const uint8_t WR_CMD = 0x0A;
const uint8_t PART_ID_REG = 0x02;
const uint8_t XDATA_L_REG = 0x0E;
const uint8_t POWER_CTL_REG = 0x2D;

// VGA horizon registers
const int PITCH_REG = 0x2001;
const int ROLL_REG = 0x2002;

// VGA mountain registers
const int MOUNTAIN_FACE_BASE = 0x2001;
const int MOUNTAIN_FACE_STRIDE = 11;
const int MOUNTAIN_COMMIT_REG = 0x2109;

// VGA cloud registers
const int CLOUD0_X_REG = 0x2001;
const int CLOUD0_Y_REG = 0x2002;

const int CLOUD1_X_REG = 0x2003;
const int CLOUD1_Y_REG = 0x2004;

const int CLOUD2_X_REG = 0x2005;
const int CLOUD2_Y_REG = 0x2006;

// Mountain geometry
const int MOUNTAIN_COUNT = 3;
const int VERTICES_PER_MOUNTAIN = 9;
const int TOTAL_VERTICES = 27;
const int TOTAL_FACES = 24;

// Cloud geometry
const int CLOUD_COUNT = 3;

// Snowline starts at 70% of mountain height
const float SNOW_LINE = 0.70f;

// Flight control constants
const float PI = 3.14159265f;
const float RAD_TO_DEG = 180.0f / PI;
const float DEG_TO_RAD = PI / 180.0f;

const float FILTER_ALPHA = 0.20f;
const float MAX_PITCH = 20.0f;
const float MAX_ROLL = 35.0f;
const float DEADZONE = 1.0f;

// VGA scaling
const float PITCH_SCALE = 5.0f;
const float ROLL_SCALE = 256.0f;

// Flight simulation constants
const float DT = 0.02f;
const float GRAVITY = 9.81f;
const float KNOT_TO_MPS = 0.514444f;
const float METER_TO_FEET = 3.28084f;

const float MIN_AIRSPEED = 60.0f;
const float MAX_AIRSPEED = 180.0f;

// Initial aircraft conditions
const float START_X = -600.0f;
const float START_Z = 0.0f;
const float START_ALTITUDE = 4000.0f;
const float START_HEADING = 0.0f;

// Perspective projection
const float FOCAL_LENGTH = 360.0f;
const float MIN_DEPTH = 60.0f;

// Mountain 1 world coordinates
const float M1_X = 0.0f;
const float M1_Z = 2000.0f;
const float M1_HEIGHT = 1900.0f;
const float M1_RADIUS = 500.0f;

// Mountain 2 world coordinates
const float M2_X = -1350.0f;
const float M2_Z = 3200.0f;
const float M2_HEIGHT = 1450.0f;
const float M2_RADIUS = 450.0f;

// Mountain 3 world coordinates
const float M3_X = -100.0f;
const float M3_Z = 4000.0f;
const float M3_HEIGHT = 1700.0f;
const float M3_RADIUS = 550.0f;

// ------------------------------------------------------------
// Aircraft state
// ------------------------------------------------------------
struct AircraftState
{
    float x;
    float z;

    float pitch;
    float roll;
    float heading;

    float altitude;
    float airspeed;
    float vertical_speed;
};

// ------------------------------------------------------------
// 3D and 2D vertices
// ------------------------------------------------------------
struct Vertex3D
{
    float x;
    float y;
    float z;
};

struct Vertex2D
{
    int32_t x;
    int32_t y;
};

// ------------------------------------------------------------
// Camera transformation
// ------------------------------------------------------------
struct CameraTransform
{
    float cos_heading;
    float sin_heading;

    float cos_roll;
    float sin_roll;

    float altitude_m;
    float pitch_offset;
};

// ------------------------------------------------------------
// Mountain definition
// ------------------------------------------------------------
struct MountainDefinition
{
    float x;
    float z;
    float height;
    float radius;
};

// Three mountains
const MountainDefinition MOUNTAINS[MOUNTAIN_COUNT] =
{
    {M1_X, M1_Z, M1_HEIGHT, M1_RADIUS},
    {M2_X, M2_Z, M2_HEIGHT, M2_RADIUS},
    {M3_X, M3_Z, M3_HEIGHT, M3_RADIUS}
};

// World vertices
Vertex3D mountain_vertices[TOTAL_VERTICES];

// ------------------------------------------------------------
// Cloud world positions
//
// X = horizontal position in meters
// Y = altitude above ground in meters
// Z = distance into the world in meters
//
// These are fixed world locations.
// Their SCREEN positions change as the aircraft moves.
// ------------------------------------------------------------
const Vertex3D CLOUD_POSITIONS[CLOUD_COUNT] =
{
    {-2400.0f, 2600.0f, 3400.0f},   // Left cloud - higher
    { -300.0f, 2900.0f, 4600.0f},   // Middle cloud - highest
    { 2200.0f, 2650.0f, 3800.0f}    // Right cloud - higher
};

// ------------------------------------------------------------
// Mountain face indices
//
// Faces 0-11  = snowcaps
// Faces 12-23 = mountain bodies
// ------------------------------------------------------------
const int FACE_INDICES[TOTAL_FACES][3] =
{
    // Mountain 1 snowcap
    {5, 6, 4},
    {6, 7, 4},
    {7, 8, 4},
    {8, 5, 4},

    // Mountain 2 snowcap
    {14, 15, 13},
    {15, 16, 13},
    {16, 17, 13},
    {17, 14, 13},

    // Mountain 3 snowcap
    {23, 24, 22},
    {24, 25, 22},
    {25, 26, 22},
    {26, 23, 22},

    // Mountain 1 body
    {0, 1, 4},
    {1, 2, 4},
    {2, 3, 4},
    {3, 0, 4},

    // Mountain 2 body
    {9, 10, 13},
    {10, 11, 13},
    {11, 12, 13},
    {12, 9, 13},

    // Mountain 3 body
    {18, 19, 22},
    {19, 20, 22},
    {20, 21, 22},
    {21, 18, 22}
};

// ------------------------------------------------------------
// Mountain face colors (12-bit RGB)
// ------------------------------------------------------------
const uint16_t FACE_COLORS[TOTAL_FACES] =
{
    // Mountain 1 snowcap
    0xFFF,
    0xCCD,
    0xDDE,
    0xEEF,

    // Mountain 2 snowcap
    0xFFF,
    0xBBC,
    0xCCD,
    0xEEF,

    // Mountain 3 snowcap
    0xFFF,
    0xCCD,
    0xDDE,
    0xEEF,

    // Mountain 1 body
    0x797,
    0x465,
    0x576,
    0x8A8,

    // Mountain 2 body
    0xA87,
    0x654,
    0x765,
    0xB98,

    // Mountain 3 body
    0x8AC,
    0x467,
    0x689,
    0x9BD
};

// ------------------------------------------------------------
// Initialize mountain and snowcap vertices
// ------------------------------------------------------------
void initialize_mountains()
{
    for (int m = 0; m < MOUNTAIN_COUNT; m++)
    {
        int base = m * VERTICES_PER_MOUNTAIN;

        float mx = MOUNTAINS[m].x;
        float mz = MOUNTAINS[m].z;
        float height = MOUNTAINS[m].height;
        float radius = MOUNTAINS[m].radius;

        // Four mountain base corners
        mountain_vertices[base + 0] =
            {mx - radius, 0.0f, mz - radius};

        mountain_vertices[base + 1] =
            {mx + radius, 0.0f, mz - radius};

        mountain_vertices[base + 2] =
            {mx + radius, 0.0f, mz + radius};

        mountain_vertices[base + 3] =
            {mx - radius, 0.0f, mz + radius};

        // Mountain summit
        mountain_vertices[base + 4] =
            {mx, height, mz};

        // Snowline vertices
        Vertex3D summit = mountain_vertices[base + 4];

        for (int i = 0; i < 4; i++)
        {
            Vertex3D corner = mountain_vertices[base + i];

            mountain_vertices[base + 5 + i].x =
                corner.x +
                (summit.x - corner.x) * SNOW_LINE;

            mountain_vertices[base + 5 + i].y =
                corner.y +
                (summit.y - corner.y) * SNOW_LINE;

            mountain_vertices[base + 5 + i].z =
                corner.z +
                (summit.z - corner.z) * SNOW_LINE;
        }
    }
}

// ------------------------------------------------------------
// Initialize ADXL362
// ------------------------------------------------------------
bool gsensor_init(SpiCore *spi_p)
{
    int id;

    spi_p->set_freq(400000);
    spi_p->set_mode(0, 0);

    // Read part ID
    spi_p->assert_ss(0);
    spi_p->transfer(RD_CMD);
    spi_p->transfer(PART_ID_REG);
    id = spi_p->transfer(0x00);
    spi_p->deassert_ss(0);

    uart.disp("ADXL362 ID: ");
    uart.disp(id, 16);
    uart.disp("\n\r");

    if (id != 0xF2)
    {
        uart.disp("Accelerometer not detected!\n\r");
        return false;
    }

    // Enable measurement mode
    spi_p->assert_ss(0);
    spi_p->transfer(WR_CMD);
    spi_p->transfer(POWER_CTL_REG);
    spi_p->transfer(0x02);
    spi_p->deassert_ss(0);

    sleep_ms(20);

    return true;
}

// ------------------------------------------------------------
// Read acceleration data
// ------------------------------------------------------------
void read_acceleration(SpiCore *spi_p,
                       float *ax, float *ay, float *az)
{
    uint8_t data[6];

    spi_p->assert_ss(0);
    spi_p->transfer(RD_CMD);
    spi_p->transfer(XDATA_L_REG);

    for (int i = 0; i < 6; i++)
    {
        data[i] = spi_p->transfer(0x00);
    }

    spi_p->deassert_ss(0);

    int16_t x = (int16_t)((data[1] << 8) | data[0]);
    int16_t y = (int16_t)((data[3] << 8) | data[2]);
    int16_t z = (int16_t)((data[5] << 8) | data[4]);

    // Convert raw acceleration to g
    *ax = x / 1000.0f;
    *ay = y / 1000.0f;
    *az = z / 1000.0f;
}

// ------------------------------------------------------------
// Calculate pitch and roll
// ------------------------------------------------------------
void calculate_orientation(float ax, float ay, float az,
                           float *pitch, float *roll)
{
    *roll = atan2(ay, -az) * RAD_TO_DEG;

    *pitch = atan2(-ax, sqrt(ay * ay + az * az))
             * RAD_TO_DEG;
}

// ------------------------------------------------------------
// Clamp value
// ------------------------------------------------------------
float clamp_value(float value,
                  float min_value,
                  float max_value)
{
    if (value < min_value)
    {
        return min_value;
    }

    if (value > max_value)
    {
        return max_value;
    }

    return value;
}

// ------------------------------------------------------------
// Apply control deadzone
// ------------------------------------------------------------
float apply_deadzone(float value)
{
    if (fabs(value) < DEADZONE)
    {
        return 0.0f;
    }

    return value;
}

// ------------------------------------------------------------
// Calibrate accelerometer
// ------------------------------------------------------------
void calibrate_controls(SpiCore *spi_p,
                        float *pitch_offset,
                        float *roll_offset)
{
    float ax, ay, az;
    float pitch, roll;

    float pitch_sum = 0.0f;
    float roll_sum = 0.0f;

    uart.disp("Keep the FPGA board level...\n\r");
    sleep_ms(1000);

    for (int i = 0; i < 50; i++)
    {
        read_acceleration(spi_p, &ax, &ay, &az);
        calculate_orientation(ax, ay, az, &pitch, &roll);

        pitch_sum += pitch;
        roll_sum += roll;

        sleep_ms(20);
    }

    *pitch_offset = pitch_sum / 50.0f;
    *roll_offset = roll_sum / 50.0f;

    uart.disp("Calibration complete!\n\r");
}

// ------------------------------------------------------------
// Read SW0-SW3 for airspeed
// ------------------------------------------------------------
float read_airspeed(GpiCore *sw_p)
{
    int switch_value = 0;

    for (int i = 0; i < 4; i++)
    {
        if (sw_p->read(i))
        {
            switch_value += (1 << i);
        }
    }

    // Map switch value 0-15 to 60-180 knots
    float airspeed =
        MIN_AIRSPEED +
        switch_value *
        (MAX_AIRSPEED - MIN_AIRSPEED) / 15.0f;

    return airspeed;
}

// ------------------------------------------------------------
// Update flight dynamics
// ------------------------------------------------------------
void update_flight_dynamics(AircraftState *aircraft)
{
    float pitch_rad =
        aircraft->pitch * DEG_TO_RAD;

    float roll_rad =
        aircraft->roll * DEG_TO_RAD;

    float heading_rad =
        aircraft->heading * DEG_TO_RAD;

    float velocity =
        aircraft->airspeed * KNOT_TO_MPS;

    // Simplified coordinated turn
    float turn_rate =
        GRAVITY * tan(roll_rad) / velocity;

    heading_rad += turn_rate * DT;

    // Normalize heading
    aircraft->heading = heading_rad * RAD_TO_DEG;

    while (aircraft->heading >= 360.0f)
    {
        aircraft->heading -= 360.0f;
    }

    while (aircraft->heading < 0.0f)
    {
        aircraft->heading += 360.0f;
    }

    // Vertical movement
    float climb_rate = velocity * sin(pitch_rad);

    aircraft->altitude +=
        climb_rate * DT * METER_TO_FEET;

    aircraft->vertical_speed =
        climb_rate * METER_TO_FEET * 60.0f;

    if (aircraft->altitude < 0.0f)
    {
        aircraft->altitude = 0.0f;
        aircraft->vertical_speed = 0.0f;
    }

    // Horizontal movement
    float horizontal_velocity =
        velocity * cos(pitch_rad);

    aircraft->x +=
        horizontal_velocity *
        sin(heading_rad) * DT;

    aircraft->z +=
        horizontal_velocity *
        cos(heading_rad) * DT;
}

// ------------------------------------------------------------
// Update artificial horizon and HUD attitude
// ------------------------------------------------------------
void update_horizon(float pitch, float roll)
{
    int32_t pitch_pixels;
    int32_t roll_slope;

    pitch_pixels =
        (int32_t)(-pitch * PITCH_SCALE);

    roll_slope =
        (int32_t)(-tan(roll * DEG_TO_RAD)
                  * ROLL_SCALE);

    horizon.wr_mem(PITCH_REG, (uint32_t)pitch_pixels);
    horizon.wr_mem(ROLL_REG, (uint32_t)roll_slope);
}

// ------------------------------------------------------------
// Calculate camera transform
//
// Called once per scenery update.
// Shared between mountains and clouds.
// ------------------------------------------------------------
void calculate_camera_transform(
    AircraftState *aircraft,
    CameraTransform *camera)
{
    float heading_rad =
        aircraft->heading * DEG_TO_RAD;

    float roll_rad =
        aircraft->roll * DEG_TO_RAD;

    camera->cos_heading = cos(heading_rad);
    camera->sin_heading = sin(heading_rad);

    camera->cos_roll = cos(roll_rad);
    camera->sin_roll = sin(roll_rad);

    camera->altitude_m =
        aircraft->altitude / METER_TO_FEET;

    camera->pitch_offset =
        -aircraft->pitch * PITCH_SCALE;
}

// ------------------------------------------------------------
// Project 3D world vertex onto VGA
//
// Used by both mountains and clouds.
// ------------------------------------------------------------
bool project_vertex(
    Vertex3D vertex,
    AircraftState *aircraft,
    CameraTransform *camera,
    Vertex2D *screen)
{
    // Vertex relative to aircraft
    float dx = vertex.x - aircraft->x;
    float dy = vertex.y - camera->altitude_m;
    float dz = vertex.z - aircraft->z;

    // Rotate into camera coordinates
    float camera_x =
        camera->cos_heading * dx -
        camera->sin_heading * dz;

    float camera_z =
        camera->sin_heading * dx +
        camera->cos_heading * dz;

    // Reject vertices behind aircraft
    if (camera_z <= MIN_DEPTH)
    {
        return false;
    }

    // Perspective projection
    float projected_x =
        FOCAL_LENGTH * camera_x / camera_z;

    float projected_y =
        -FOCAL_LENGTH * dy / camera_z;

    // Aircraft roll
    float rotated_x =
        camera->cos_roll * projected_x +
        camera->sin_roll * projected_y;

    float rotated_y =
        -camera->sin_roll * projected_x +
        camera->cos_roll * projected_y;

    // VGA coordinates
    float screen_x =
        320.0f + rotated_x;

    float screen_y =
        240.0f +
        camera->pitch_offset +
        rotated_y;

    screen_x =
        clamp_value(screen_x, -2048.0f, 2048.0f);

    screen_y =
        clamp_value(screen_y, -2048.0f, 2048.0f);

    screen->x = (int32_t)screen_x;
    screen->y = (int32_t)screen_y;

    return true;
}

// ------------------------------------------------------------
// Write one mountain triangle to FPGA
// ------------------------------------------------------------
void write_mountain_face(
    int face,
    Vertex2D *v,
    uint16_t color)
{
    int addr =
        MOUNTAIN_FACE_BASE +
        face * MOUNTAIN_FACE_STRIDE;

    for (int e = 0; e < 3; e++)
    {
        int next = (e + 1) % 3;

        int32_t A =
            v[e].y - v[next].y;

        int32_t B =
            v[next].x - v[e].x;

        int64_t C =
            (int64_t)v[e].x * v[next].y -
            (int64_t)v[next].x * v[e].y;

        mountain.wr_mem(
            addr + e * 3 + 0,
            (uint32_t)A);

        mountain.wr_mem(
            addr + e * 3 + 1,
            (uint32_t)B);

        mountain.wr_mem(
            addr + e * 3 + 2,
            (uint32_t)(int32_t)C);
    }

    // Set face color
    mountain.wr_mem(addr + 9, color);

    // Enable face
    mountain.wr_mem(addr + 10, 1);
}

// ------------------------------------------------------------
// Disable a mountain/snowcap face
// ------------------------------------------------------------
void disable_mountain_face(int face)
{
    int addr =
        MOUNTAIN_FACE_BASE +
        face * MOUNTAIN_FACE_STRIDE;

    mountain.wr_mem(addr + 10, 0);
}

// ------------------------------------------------------------
// Update all three mountains and snowcaps
// ------------------------------------------------------------
void update_mountain(
    AircraftState *aircraft,
    CameraTransform *camera)
{
    Vertex2D projected[TOTAL_VERTICES];
    bool visible[TOTAL_VERTICES];

    // Project 27 world vertices
    for (int i = 0; i < TOTAL_VERTICES; i++)
    {
        visible[i] = project_vertex(
            mountain_vertices[i],
            aircraft,
            camera,
            &projected[i]);
    }

    // Update all 24 triangle faces
    for (int f = 0; f < TOTAL_FACES; f++)
    {
        int i0 = FACE_INDICES[f][0];
        int i1 = FACE_INDICES[f][1];
        int i2 = FACE_INDICES[f][2];

        if (!visible[i0] ||
            !visible[i1] ||
            !visible[i2])
        {
            disable_mountain_face(f);
            continue;
        }

        Vertex2D v[3] =
        {
            projected[i0],
            projected[i1],
            projected[i2]
        };

        // Signed projected triangle area
        int64_t area =
            (int64_t)(v[1].x - v[0].x) *
                      (v[2].y - v[0].y) -
            (int64_t)(v[1].y - v[0].y) *
                      (v[2].x - v[0].x);

        // Back-face culling
        if (area >= 0)
        {
            disable_mountain_face(f);
            continue;
        }

        write_mountain_face(f, v, FACE_COLORS[f]);
    }

    // Commit all 24 faces
    mountain.wr_mem(MOUNTAIN_COMMIT_REG, 1);

    // Enable renderer
    mountain.bypass(0);
}

// ------------------------------------------------------------
// Write one cloud center to FPGA
// ------------------------------------------------------------
void write_cloud_position(
    int cloud_num,
    int32_t screen_x,
    int32_t screen_y)
{
    int addr =
        CLOUD0_X_REG + cloud_num * 2;

    clouds.wr_mem(
        addr,
        (uint32_t)screen_x);

    clouds.wr_mem(
        addr + 1,
        (uint32_t)screen_y);
}

// ------------------------------------------------------------
// Update cloud screen positions
//
// Each cloud has a fixed world position.
//
// When aircraft heading/pitch/roll changes, the
// perspective projection moves its screen position.
//
// Clouds behind the camera are moved off-screen.
// ------------------------------------------------------------
void update_clouds(
    AircraftState *aircraft,
    CameraTransform *camera)
{
    Vertex2D projected;

    for (int i = 0; i < CLOUD_COUNT; i++)
    {
        bool visible = project_vertex(
            CLOUD_POSITIONS[i],
            aircraft,
            camera,
            &projected);

        if (visible)
        {
            write_cloud_position(
                i,
                projected.x,
                projected.y);
        }
        else
        {
            // Hide cloud behind camera
            write_cloud_position(
                i,
                -1000,
                -1000);
        }
    }

    // Enable cloud renderer
    clouds.bypass(0);
}

// ------------------------------------------------------------
// Update all scenery using one camera transform
// ------------------------------------------------------------
void update_scenery(AircraftState *aircraft)
{
    CameraTransform camera;

    calculate_camera_transform(
        aircraft,
        &camera);

    // Update mountains and snowcaps
    update_mountain(
        aircraft,
        &camera);

    // Update cloud positions
    update_clouds(
        aircraft,
        &camera);
}

// ------------------------------------------------------------
// Reset aircraft
// ------------------------------------------------------------
void reset_flight(AircraftState *aircraft)
{
    aircraft->x = START_X;
    aircraft->z = START_Z;

    aircraft->pitch = 0.0f;
    aircraft->roll = 0.0f;
    aircraft->heading = START_HEADING;

    aircraft->altitude = START_ALTITUDE;
    aircraft->airspeed = MIN_AIRSPEED;
    aircraft->vertical_speed = 0.0f;

    // Restore horizon, mountains, and clouds
    update_horizon(0.0f, 0.0f);
    update_scenery(aircraft);

    uart.disp("\n\rFlight simulation reset!\n\r");
}

// ------------------------------------------------------------
// Main flight simulator
// ------------------------------------------------------------
void flight_simulator(
    SpiCore *spi_p,
    GpiCore *sw_p)
{
    AircraftState aircraft = {};

    // Initial aircraft conditions
    aircraft.x = START_X;
    aircraft.z = START_Z;

    aircraft.pitch = 0.0f;
    aircraft.roll = 0.0f;
    aircraft.heading = START_HEADING;

    aircraft.altitude = START_ALTITUDE;
    aircraft.airspeed = MIN_AIRSPEED;
    aircraft.vertical_speed = 0.0f;

    float ax, ay, az;
    float pitch, roll;
    float pitch_offset, roll_offset;
    float target_pitch, target_roll;

    int print_counter = 0;

    // SW15 reset switch
    int reset_switch;
    int previous_reset = 0;

    // Build mountain geometry
    initialize_mountains();

    // Calibrate accelerometer
    calibrate_controls(
        spi_p,
        &pitch_offset,
        &roll_offset);

    // Enable artificial horizon
    update_horizon(0.0f, 0.0f);
    horizon.bypass(0);

    // Initialize mountains, snowcaps, and clouds
    update_scenery(&aircraft);

    uart.disp("Flight simulator active!\n\r");
    uart.disp("Three snowcapped mountains enabled!\n\r");
    uart.disp("Moving clouds enabled!\n\r");
    uart.disp("Attitude HUD enabled!\n\r");

    uart.disp("SW0-SW3 = Airspeed (60-180 knots)\n\r");
    uart.disp("SW15 ON = Reset and Hold\n\r");
    uart.disp("SW15 OFF = Resume Flight\n\r");

    while (1)
    {
        // Check SW15 reset switch
        reset_switch = sw_p->read(15);

        // Reset and hold while SW15 is ON
        if (reset_switch == 1)
        {
            if (previous_reset == 0)
            {
                reset_flight(&aircraft);
                print_counter = 0;
            }

            previous_reset = 1;

            sleep_ms(20);
            continue;
        }

        // Resume flight when SW15 is OFF
        previous_reset = 0;

        // Read accelerometer
        read_acceleration(
            spi_p,
            &ax, &ay, &az);

        // Calculate board orientation
        calculate_orientation(
            ax, ay, az,
            &pitch, &roll);

        // Remove calibration offsets
        target_pitch =
            pitch - pitch_offset;

        target_roll =
            -(roll - roll_offset);

        // Limit control angles
        target_pitch = clamp_value(
            target_pitch,
            -MAX_PITCH,
            MAX_PITCH);

        target_roll = clamp_value(
            target_roll,
            -MAX_ROLL,
            MAX_ROLL);

        // Smooth aircraft controls
        aircraft.pitch +=
            FILTER_ALPHA *
            (target_pitch - aircraft.pitch);

        aircraft.roll +=
            FILTER_ALPHA *
            (target_roll - aircraft.roll);

        // Apply deadzone
        aircraft.pitch =
            apply_deadzone(aircraft.pitch);

        aircraft.roll =
            apply_deadzone(aircraft.roll);

        // Read airspeed
        aircraft.airspeed =
            read_airspeed(sw_p);

        // Update flight dynamics
        update_flight_dynamics(&aircraft);

        // Update artificial horizon and HUD
        update_horizon(
            aircraft.pitch,
            aircraft.roll);

        // Update mountains, snowcaps, and clouds
        update_scenery(&aircraft);

        // Print UART telemetry
        if (print_counter >= 5)
        {
            uart.disp("Pitch: ");
            uart.disp((double)aircraft.pitch, 2);

            uart.disp(" | Roll: ");
            uart.disp((double)aircraft.roll, 2);

            uart.disp(" | Heading: ");
            uart.disp((double)aircraft.heading, 1);

            uart.disp(" | Alt: ");
            uart.disp((double)aircraft.altitude, 1);

            uart.disp(" | Speed: ");
            uart.disp((double)aircraft.airspeed, 0);

            uart.disp(" | VS: ");
            uart.disp((double)aircraft.vertical_speed, 0);

            uart.disp("\n\r");

            print_counter = 0;
        }

        print_counter++;

        sleep_ms(20);
    }
}

// ------------------------------------------------------------
// Main
// ------------------------------------------------------------
int main()
{
    uart.disp("\n\rFPGA Flight Simulator\n\r");
    uart.disp("Initializing flight simulation...\n\r");

    if (!gsensor_init(&spi))
    {
        while (1) {}
    }

    flight_simulator(&spi, &sw);

    return 0;
}
