<p align="center">
  <img src="assets/icon.png" width="120" alt="Boogie's warm ivory and terracotta icon">
</p>

<h1 align="center">boogie.</h1>
<p align="center">A little company for your desktop.</p>

Boogie puts a dancing companion on your Mac's Dock. Choose **Sophia** or
**Manuel**, two realistic, scanned 3D people rendered with soft studio lighting
and motion-captured movement. They live in transparent windows, follow you
across Spaces, and work entirely offline.

<p align="center">
  <img src="assets/panel.png" width="380" alt="Boogie's ivory control panel with Sophia, companion selection, tempo, size, and playback controls">
</p>

## Make yourself at home

- **Click** a companion for a little jump and hearts.
- **Drag and drop** them anywhere. Gravity brings them back to the Dock.
- **Right-click** a person, or use the menu-bar icon, to open the controls.
- Choose an **Easy**, **Groove**, **Upbeat**, or **Party** pace.
- Pick a size and bring a **solo, duo, or trio**. A trio repeats the first person.
- **Pause**, **hide**, or **return to Dock** from the main panel.
- Open **Preferences** to enable launch at login and sensor reactions.

The panel uses warm paper colors, a terracotta accent, and a quiet live preview.
The original Boogie, Bruce, and Jazz sprites are still available under **Pixel
classics**, with their eleven moves. Boogie's outfit and skin controls live in
Preferences. The scanned people keep their original clothes and share one
motion-captured dance loop; they do not use the pixel cast's move selector.

## Responds to your Mac

On supported MacBooks, tilt makes companions slide and lean, lowering the lid
makes them crouch, and low light adds an evening glow. Each reaction can be
configured independently. Missing sensors disable the corresponding controls;
lighting can also be enabled manually. Tilt calibration lives in Preferences.

## Build and run

Requires macOS 13+ and Xcode command line tools. No Xcode project, Swift packages,
or runtime downloads are needed.

```sh
./build.sh
open build/Boogie.app
```

To replace the copy in your Applications folder:

```sh
./build.sh --install
open ~/Applications/Boogie.app
```

Builds are signed locally. `build.sh` recreates `build/`, bundles character
artwork, and regenerates the app icon.

## Development and validation

```sh
./tools/test.sh
build/Boogie.app/Contents/MacOS/Boogie --render-panel build/panel.png
build/Boogie.app/Contents/MacOS/Boogie --render-panel build/preferences.png --preferences
build/Boogie.app/Contents/MacOS/Boogie --render-panel build/manuel.png --character manuel
```

Snapshot options also include `--paused` and `--hidden`. To exercise sensors
without moving your Mac, launch the binary directly:

```sh
BOOGIE_FAKE_LID=30 BOOGIE_FAKE_LUX=0 BOOGIE_DEBUG_SENSORS=1 \
  build/Boogie.app/Contents/MacOS/Boogie
```

Tilt uses `BOOGIE_FAKE_TILT="0.2,0,-0.98"` and
`BOOGIE_FAKE_TILT_AFTER=2` to allow initial zeroing.

`Sources/Panel.swift` contains the SwiftUI interface. `Companions.swift` loads
rendered animation frames through a bounded atlas cache; `Dancer.swift` draws
them using native layers. Both the preview and Dock use the same beat clock,
including pause and tempo changes. Transparent margins pass clicks through.
`Sprite.swift` remains the renderer for the pixel classics.

## Character credits

Sophia and Manuel are by [Renderpeople](https://renderpeople.com/free-3d-people/).
Their models are licensed, not public-domain assets. This repository includes
rendered animation artwork; it does not include the source meshes, textures, or
rigs. See [character sources, usage terms, and rendering instructions](assets/CHARACTERS.md).

Ordinary builds use the bundled renders. Regenerating them requires Blender 4.5
and Pillow as development tools. No networking, analytics, or telemetry runs in
the app.
