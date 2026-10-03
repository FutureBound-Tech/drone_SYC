# Rotorline FPV

An early solo FPV practice simulator built with Godot 4.7.2 and GDScript. The current build has a procedural practice yard, a six-gate local time trial, a rate-based quad flight model, controller setup, and local settings/profile storage.

## Run

From this folder, launch the game with:

```sh
./run
```

Open the project in the Godot editor with `./run dev`. `./run start` is equivalent to `./run`.

The project uses the Compatibility renderer and has no external asset dependencies.

## First flight

1. Connect a transmitter that Linux exposes as a USB joystick.
2. Open **Transmitter Setup**, select the device, and assign roll, pitch, yaw, and throttle.
3. Run the endpoint calibration and move every axis through its full range during the countdown.
4. Name and save the local radio profile.
5. Choose **Free Flight** or **Race**.

Keyboard practice is available without a transmitter: **A/D** roll, **W/S** pitch, **Q/E** yaw, **Space/Ctrl** throttle, **R** reset, and **Esc** pause.

Settings and profiles are saved under `user://rotorline.cfg`. Current device mappings are based on Linux joystick axis indices; changing a transmitter’s USB mode or driver may require recalibration.

## Current build boundaries

- Ubuntu Linux is the supported development target. Steam Deck has not been validated.
- The flight model is an initial rate/thrust approximation for tuning and playability. It is not yet validated against real quad telemetry or pilot feedback.
- Race gates are procedural visual checkpoints. The yard, drone, and scenery are prototype geometry.
- Master and effects volume apply to the procedural motor sound. A music bus and music-volume setting are present, but no music track is included.
- Steam achievements, cloud saves, online play, purchases, and leaderboards are not included.

For a Linux Steam build, install matching Godot 4.7.2 export templates and export the included **Linux/X11 x86_64** preset. It writes `build/rotorline.x86_64`. Steam depot configuration and store publishing remain release operations.
# drone_SYC
