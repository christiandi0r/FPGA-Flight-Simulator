# FPGA Flight Simulator

**ECE 4305/L — Advanced Digital Design Using SystemVerilog**  
**Cal Poly Pomona**  
**Team:** Christian Ruelas and Jonathan Kwon  
**Hardware:** Digilent Nexys A7-100T (Artix-7 FPGA)  
**Tools:** Vivado, Vitis  
**Languages:** SystemVerilog, C++

## Table of contents

- [Overview](#overview)
- [System architecture](#system-architecture)
  - [Architecture summary](#architecture-summary)
  - [What runs in C++?](#what-runs-in-c)
  - [What runs in SystemVerilog?](#what-runs-in-systemverilog)
  - [Custom video core and FPro](#custom-video-core-and-fpro)
- [Implemented features](#implemented-features)
- [Flight simulation and terrain collision](#flight-simulation-and-terrain-collision)
  - [Collision model](#collision-model)
  - [Crash and automatic restart](#crash-and-automatic-restart)
- [3D rendering pipeline](#3d-rendering-pipeline)
- [Technical challenges and solutions](#technical-challenges-and-solutions)
  - [Current limitations](#current-limitations)
- [Requirements and status](#requirements-and-status)
- [Planned integration](#planned-integration)
- [Development workflow](#development-workflow)
- [Demo checklist](#demo-checklist)
- [Team](#team)

## Overview

This project is an interactive FPGA-based flight display and simulator built around the course **FPro** system. Tilting the Nexys A7 board changes the attitude shown on an external VGA monitor. The display includes an artificial horizon, a bright-green pitch ladder and roll indicator, three snowcapped mountains, moving clouds, and live on-screen flight telemetry. A MicroBlaze soft processor reads the onboard ADXL362 accelerometer over SPI, estimates pitch and roll, maintains additional simulated flight variables, and writes display parameters to memory-mapped FPGA registers.

Custom SystemVerilog video cores generate the flight scene directly from pixel coordinates and registered control values. The C++ application also projects mountain vertices and cloud positions from simulated 3D world coordinates into VGA screen coordinates. This separates software-based sensor processing, flight-state updates, collision detection, and scene geometry from continuous hardware-based video rendering. The simulator now supports altitude-dependent terrain collisions, a crash screen with automatic restart, near-plane clipping, and depth-based mountain rendering priority.

> **Project status:** The accelerometer-driven VGA flight display, snowcapped mountains, moving clouds, green attitude HUD, and live VGA telemetry have been demonstrated on the Nexys A7. Terrain collision and automatic restart are implemented; close-range rendering and depth priority have been refined through interactive hardware testing. PS/2 keyboard input remains **planned / in progress**. See [Requirements and status](#requirements-and-status).

## System architecture

<p align="center">
  <img src="fpga_flight_simulator_architecture.png" alt="FPGA Flight Simulator System Architecture" width="900">
</p>

### Architecture summary

1. **ADXL362 measures acceleration.** The onboard accelerometer senses changes in the gravity vector as the Nexys A7 board is tilted.
2. **C++ reads sensor data using SPI.** MicroBlaze receives X, Y, and Z acceleration values through the FPro SPI core.
3. **C++ calculates pitch and roll.** The firmware applies calibration, converts measurements into attitude angles, and updates simulated flight variables.
4. **C++ checks for terrain collisions.** The firmware tests the aircraft's forward path against altitude-dependent mountain cross-sections and restarts the simulation after a detected collision.
5. **C++ prepares the 3D scene.** The firmware transforms vertices into camera space, clips mountain faces at the near plane, projects them into screen coordinates, and assigns triangle priority by mountain depth.
6. **C++ writes display parameters to FPro registers.** The hardware stores values such as pitch offset, roll slope, mountain triangle edges/colors, and cloud screen positions.
7. **C++ updates the on-screen telemetry.** MicroBlaze formats the simulated flight values and writes characters to the memory-mapped OSD core.
8. **SystemVerilog evaluates each pixel using those values.** The rendering pipeline checks whether the current pixel belongs to the sky, ground, mountain faces and snowcaps, clouds, pitch ladder, roll scale, aircraft marker, or telemetry overlay.
9. **The VGA pipeline outputs the selected RGB color.** The monitor receives the completed pixel stream and displays the updated flight scene.

### What runs in C++?

MicroBlaze executes the C++ application to:

1. Configure the SPI interface and verify the ADXL362 device ID (`0xF2`).
2. Collect and calibrate the three-axis accelerometer measurements.
3. Estimate the board's pitch and roll relative to its initial level orientation, with filtering to reduce jitter.
4. Update the **simulated** heading, altitude, airspeed, and vertical speed. These are **not** independent measurements from the accelerometer.
5. Calculate the aircraft's movement through a simple 3D world.
6. Check for terrain collisions using the aircraft's altitude, heading, and a forward lookahead; manage the crash countdown and flight reset.
7. Transform mountain vertices into camera space, apply near-plane clipping and perspective projection, and project cloud positions onto the VGA display.
8. Cull back-facing triangles, calculate triangle edge coefficients, and dynamically assign hardware triangle slots according to mountain depth.
9. Convert attitude estimates and projected scenery into integer/fixed-point display parameters and write them to video cores through FPro memory-mapped I/O.
10. Read onboard switches to adjust simulated airspeed (SW0–SW3) and reset/hold the simulation (SW15).
11. Format and write live `PITCH`, `ROLL`, `HDG`, `ALT`, `SPD`, and `VS` values to the VGA character-based OSD.
12. Print flight-state information to the UART terminal for debugging.

The accelerometer supports tilt estimation under steady or slow movement. It is **not** a complete inertial-navigation system or an absolute heading sensor.

### What runs in SystemVerilog?

The FPGA video logic processes the current pixel coordinate `(x, y)` and determines its RGB output. The horizon core uses stored pitch and roll display parameters to calculate the position of the sky-ground boundary:

```text
horizon_y(x) = 240 + pitch_offset + (((x - 320) * roll_slope) >>> 8)
```

The arithmetic uses signed, fixed-point values: the right shift rescales the roll-related product. The mountain core rasterizes triangular faces using edge equations, including snowcap faces with separate colors. The mountain core evaluates up to 24 registered triangles and resolves overlapping pixels using slot priority. MicroBlaze assigns those slots so that nearer mountains take precedence over farther mountains while each snowcap retains priority over its own mountain body. The cloud core draws three cloud shapes at screen positions provided by MicroBlaze, preserving the existing mountain graphics by drawing clouds only over sky-colored pixels. The HUD overlays the bright-green (`12'h0F0`) pitch ladder, roll scale, downward-pointing roll marker, and fixed aircraft reference. The OSD uses character RAM and a font ROM initialized from `font.mem` to render live white text. Additional pixel-based logic draws four black telemetry panels with cyan borders, divider lines, and degree symbols.

Unlike C++, which executes instructions on MicroBlaze, these video circuits exist independently in FPGA fabric. The pixel stream continues while the processor reads the accelerometer and updates registers.

### Custom video core and FPro

The design integrates several custom SystemVerilog video cores into the course FPro video system:

| Video slot | Core | Purpose |
| --- | --- | --- |
| `V0_SYNC` | VGA synchronization | Sends pixels to the VGA monitor |
| `V1_HORIZON` | Artificial horizon | Renders sky and ground; provides attitude data |
| `V2_OSD` | On-screen display | Renders live telemetry text |
| `V3_MOUNTAIN` | Mountain renderer | Renders three snowcapped mountains |
| `V4_CLOUD` | Cloud renderer | Renders three moving clouds |
| `V5_GRAY` | Grayscale filter | Provides grayscale video processing |
| `V6_BAR` | Color bar generator | Provides test-color patterns |
| `V7_UNUSED` | Unused slot | Reserved for future expansion |

Each custom renderer receives:

- Pixel coordinates (`x`, `y`) and an incoming RGB stream (`si_rgb`)
- FPro-derived register signals (`cs`, `write`, `addr`, `wr_data`)
- An outgoing RGB stream (`so_rgb`) for subsequent video stages

The slot numbers select **memory-mapped control addresses**, not the order in which pixels are rendered. The actual RGB pipeline is:

```text
Frame Buffer → Color Bar → Grayscale → Horizon → Mountains → Clouds → HUD → Telemetry Background → OSD → Cyan Borders / Degree Symbols → VGA
```

## Implemented features

- Accelerometer-driven pitch and roll on the VGA flight display
- ADXL362 communication over the FPro SPI core
- Startup level calibration and smoothed attitude response
- Artificial horizon with sky and ground
- Moving/rotating bright-green (`12'h0F0`) pitch ladder and roll reference
- Bright-green downward-pointing triangle roll marker and fixed aircraft reference
- Three snowcapped mountains with multiple colored triangular faces
- Perspective-projected mountain scenery that moves with simulated flight and aircraft orientation
- Near-plane clipping for all three mountains and their snowcaps
- Back-face culling and dynamic mountain depth sorting to improve terrain occlusion
- Altitude-dependent terrain collision detection using square-pyramid geometry
- Forward collision lookahead and individually tuned mountain clearance margins
- VGA crash notification, UART collision message, two-second countdown, and automatic restart
- Three moving clouds with world positions projected into VGA screen coordinates
- Cloud rendering behind the HUD and in front of sky pixels, without covering mountain faces
- Simulated heading, altitude, airspeed, and vertical speed
- Switch-controlled airspeed (SW0–SW3) and simulation reset/hold (SW15)
- UART flight telemetry for debugging
- Live VGA telemetry for pitch, roll, heading, altitude, airspeed, and vertical speed
- Four screen-edge black telemetry panels with cyan borders and white text
- Degree symbols for pitch, roll, and heading, plus dividers in the bottom panels
- Character-based VGA text rendering using `V2_OSD`, `font.mem`, and an aligned OSD pixel pipeline
- Custom SystemVerilog rendering integrated with the FPro video pipeline

## Flight simulation and terrain collision

The aircraft moves through a simplified 3D world rather than scrolling a fixed background image. The C++ application integrates heading, altitude, and horizontal position using simulated airspeed, pitch, and roll. A simplified coordinated-turn model updates heading from bank angle, while pitch determines the climb or descent rate. The simulation uses a nominal 20 ms integration step; the actual loop period also includes sensor reads, rendering calculations, register writes, and a 20 ms delay.

| Control | Function |
| --- | --- |
| Tilt the Nexys A7 forward/backward | Control pitch and simulated climb/descent |
| Tilt the board left/right | Control roll and simulated heading changes |
| SW0–SW3 | Select airspeed from 60 to 180 knots |
| SW15 ON | Reset and hold the simulation |
| SW15 OFF | Resume flight |

### Collision model

Each mountain is a square pyramid in world coordinates, so its horizontal cross-section becomes narrower toward the summit. A fixed-radius collision boundary would not accurately represent the sloping terrain. The implemented collision function (`check_mountain_collision`) converts aircraft altitude from feet to meters and calculates the collision half-width at the effective altitude:

```text
h_eff = altitude_ft / 3.28084 - vertical_margin
fraction = clamp(1 - h_eff / mountain_height, 0, 1)
collision_half_width = mountain_radius * fraction + lateral_margin
```

If the effective altitude is above the summit, that mountain is skipped. Otherwise, the application samples 11 points, including the aircraft's current position, along the forward heading:

```text
future_x = aircraft_x + sin(heading_rad) * distance
future_z = aircraft_z + cos(heading_rad) * distance
```

A collision is triggered when both horizontal offsets from the mountain center fall within its collision half-width at any sample. This checks the mountain body as well as the snow-covered region, using the same underlying pyramid geometry.

**Current tuned parameters** (distances in meters):

| Parameter | Mountain 1 | Mountain 2 | Mountain 3 |
| --- | ---: | ---: | ---: |
| Mountain height | 1900 | 1450 | 1700 |
| Base half-width | 500 | 450 | 550 |
| Forward lookahead | 200 | 200 | 200 |
| Lateral margin | 50 | 50 | 15 |
| Vertical margin | 80 | 80 | 80 |
| Lookahead intervals | 10 | 10 | 10 |

Mountain 3 uses a smaller lateral margin to allow closer flybys. The 200 m lookahead was selected through interactive testing after near-plane clipping was implemented; it improves the perceived timing of a crash, rather than representing exact physical contact with terrain.

### Crash and automatic restart

When a collision is detected, the application freezes normal flight updates, displays a red `CRASHED` / `TERRAIN COLLISION` message using the existing OSD core, prints a collision message to UART, and runs a two-second countdown. It then restores the starting aircraft state and redraws the horizon, terrain, clouds, and telemetry. This reuses the existing hardware interfaces without introducing a dedicated crash-screen core.

## 3D rendering pipeline

The simulator uses a lightweight hybrid software/hardware graphics pipeline. MicroBlaze prepares geometry once per scenery update, while the FPGA evaluates the resulting edge equations continuously for the VGA pixel stream.

```text
3D world vertices (27 mountain vertices)
    -> Camera-space transformation
    -> Near-plane clipping (60 m)
    -> Perspective projection and roll transformation
    -> Triangle generation and back-face culling
    -> Depth-priority slot assignment and edge coefficients
    -> FPro MMIO / scenery commit
    -> SystemVerilog triangle rasterization (24 hardware slots)
    -> VGA pixel stream
```

The implementation caches camera-space vertices and sorts the three mountains by their center depth along the camera's forward axis (using the summit's X/Z position). Each mountain receives eight consecutive hardware triangle slots: four for snowcaps followed by four for body faces. Nearer mountains receive higher pixel priority, while snowcaps remain above their own body faces. The ordering changes with aircraft movement and heading.

Near-plane clipping retains the visible portion of a face when some of its vertices pass behind the near plane. Intersections are calculated in camera space before perspective division. A clipped triangle can become a triangle or a quadrilateral; the latter is split into two triangles. Unused slots within the corresponding four-face group are reused where available, preserving the existing 24-slot hardware interface.

## Technical challenges and solutions

Development involved iterative debugging on the Nexys A7 and VGA monitor, including both firmware and HDL issues. Several visual artifacts initially appeared to be flight-dynamics or collision problems but were ultimately related to geometry processing or rendering priority.

| Challenge | Investigation and solution |
| --- | --- |
| Reversed pitch response and climb/descent direction | Corrected sign conventions so board movement, horizon motion, HUD pitch, and simulated vertical movement behave intuitively. |
| Right-edge VGA artifact during roll | Corrected the horizon rendering issue that produced a thin strip near the right edge of the screen. |
| Crowded HUD and unclear roll indication | Refined pitch-ladder range, line thickness, and the placement/orientation of the green roll marker. |
| Fragmented OSD characters | Aligned the character/font-ROM output with the video pipeline and refined the black-and-cyan telemetry panels. |
| Inconsistent terrain collision sensitivity | Replaced fixed horizontal thresholds with altitude-dependent square-pyramid cross-sections; tuned the lookahead and clearance margins to cover mountain bodies and snowcaps. |
| False or overly sensitive collisions near Mountain 3 | Reduced Mountain 3's lateral clearance from 50 m to 15 m to allow closer flybys while retaining forward collision checks. |
| Mountain 1 appeared to disappear before impact | Increasing collision lookahead alone did not resolve the issue. The renderer discarded entire triangles when a single vertex crossed the near plane. Implemented camera-space near-plane clipping for Mountain 1, then extended it to all three mountains. |
| Distant snowcap appeared through a nearer mountain | Identified a fixed slot-priority problem: all snowcaps previously had priority over all mountain bodies. Grouped snowcaps and bodies by mountain and dynamically ordered those groups by camera-space depth. |

**Engineering outcome:** The project progressed from an accelerometer-controlled attitude display to an interactive flight simulator with projected 3D scenery, terrain collision handling, and an automatic restart mechanism. The close-range rendering improvements and depth-priority fix were tested interactively and produced more natural visuals. These changes reuse the existing mountain hardware registers, demonstrating how software geometry processing can complement a dedicated FPGA rasterizer without requiring a new video core.

### Current limitations

- Flight dynamics are simplified; this is an educational simulator, not a high-fidelity aerodynamic or navigation model.
- Terrain collision uses a straight, constant-altitude lookahead with clearance margins rather than exact swept 3D aircraft geometry. A predicted collision can occur before physical contact.
- Mountain ordering is object-level depth sorting, not per-pixel depth testing (a Z-buffer). Complex overlap cases may still produce artifacts.
- The fixed triangle-slot budget and screen-coordinate clamping can limit rendering accuracy at extreme viewing angles.
- Sorting, clipping, projection, and triangle setup remain in C++; pixel rasterization runs in FPGA fabric. Offloading the three-mountain sort to HDL was considered but not implemented because the software sort requires only three comparisons per update. No quantitative performance benchmark has been performed.

## Requirements and status

| Course requirement | Current status | How this project addresses it |
| --- | --- | --- |
| Meaningful FPro-based task | **Implemented** | Interactive flight simulator with custom graphics, terrain collisions, and automatic restart using FPro cores |
| At least one SPI, I2C, XADC, or audio I/O core | **Implemented** | SPI communication with ADXL362 |
| VGA moving sprite **or object** | **Implemented** | Moving artificial horizon, pitch ladder, snowcapped mountains, and clouds |
| VGA on-screen text | **Implemented** | Live `PITCH`, `ROLL`, `HDG`, `ALT`, `SPD`, and `VS` readouts in four VGA instrument panels |
| New video-core functionality (extra credit) | **Implemented** | Custom `flight_horizon_core`, `flight_mountain_core`, and `flight_cloud_core` |
| PS/2 keyboard or PS/2 mouse | **Planned / in progress** | Keyboard controls for simulator interaction |

## Planned integration

### PS/2 input

Add a PS/2 keyboard interface through the FPro system. Proposed controls include resetting the simulation, pausing/resuming, adjusting simulated speed, and showing/hiding display elements. Final key bindings will be documented after implementation.

### Integration and testing

Integrate PS/2 controls into the working simulator and verify that keyboard events do not interfere with accelerometer readings, FPro register writes, VGA text updates, frame timing, mountain/cloud motion, or the existing HUD. Continue regression testing terrain collisions, close flybys, summit clearance, near-plane clipping, and mountain overlap at different airspeeds and headings.

## Development workflow

1. Open the team's **Vivado** project and use the board constraints and existing FPro hardware configuration.
2. Review the custom video cores, video-system integration, and FPro address definitions before modifying the register map.
3. Synthesize and implement the design; generate the FPGA bitstream.
4. Export the hardware platform to **Vitis** and build the MicroBlaze C++ application against the matching hardware design.
5. Program the Nexys A7 and run the application.
6. Connect a VGA monitor and a UART terminal. Follow the level-calibration prompt before tilting the board.
7. Verify pitch/roll response, green HUD symbology, snowcapped mountains, moving clouds, VGA instrument panels, and UART telemetry. Test terrain collisions, the automatic restart, and overlapping/close-range mountain rendering. Test PS/2 controls once integrated.

**Version note:** Exact Vivado/Vitis project paths, file layout, clock configuration, and programming steps depend on the committed project. Consult the actual Vivado/Vitis sources and constraints; do not assume that generated build files or exported hardware files are included in this repository.

## Demo checklist

- [x] Build and run the FPGA flight display
- [x] Identify ADXL362 over SPI
- [x] Calibrate the initial level orientation
- [x] Demonstrate pitch/roll changes on VGA
- [x] Show artificial horizon, pitch ladder, and moving mountain terrain
- [x] Display three snowcapped mountains
- [x] Display three moving clouds
- [x] Verify updated FPro video slot assignments
- [x] Show simulated flight-state values in the UART terminal
- [x] Display live flight telemetry on VGA
- [x] Show black telemetry boxes with cyan borders, divider lines, and degree symbols
- [x] Show bright-green pitch ladder, roll scale, triangle marker, and center dot
- [x] Implement terrain collision detection and automatic crash restart
- [x] Test near-plane clipping and the tuned collision lookahead during close approaches
- [x] Correct distant snowcap visibility using dynamic mountain depth priority
- [ ] Complete regression testing for all mountains, summit clearance, close flybys, and speed settings
- [ ] Demonstrate PS/2 keyboard or mouse input
- [ ] Record the final video demonstration
- [ ] Verify and submit all created/modified HDL, C/C++ drivers, and C/C++ application files

## Team

| Team member | Primary work area |
| --- | --- |
| **Christian Ruelas** | Flight-display HDL, ADXL362 SPI integration, MicroBlaze C++ simulation |
| **Jonathan Kwon** | VGA telemetry / HUD integration, PS/2 keyboard input integration (in progress) |
| **Both** | System integration, validation, documentation, and final demo |
