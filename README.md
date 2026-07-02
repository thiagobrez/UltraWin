# UltraWin

Share part of your ultrawide screen in meetings — through an **invisible virtual monitor**.

Drag-select a region of your screen and UltraWin creates a virtual display
("UltraWin Display") that continuously mirrors whatever is inside that region.
In Zoom/Meet/Teams, share that display. Unlike DeskPad-style tools there is no
window to interact with: your apps stay where they are, the shared region is
highlighted on your real screen (everything outside it is dimmed), and the
frame can be moved and resized live while sharing.

## Usage

1. Click the UltraWin menu bar icon → **Select Region to Share…**
2. Drag over the part of the screen you want to share (Esc cancels).
3. In your meeting app, share the display called **UltraWin Display**.
4. Drag the frame's edges to move it, corners to resize. **Stop Sharing** removes the virtual display.

Options: **Snap to 16:9** locks the selection to 16:9 and outputs a fixed
1920×1080 display; **Dim Outside Region** controls how strongly the
non-shared area is dimmed on your screen.

## Build

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project UltraWin.xcodeproj -scheme UltraWin -configuration Release -derivedDataPath build build
open build/Build/Products/Release/UltraWin.app
```

Grant Screen Recording permission on first use (System Settings → Privacy &
Security → Screen Recording), then relaunch the app.

## Notes

- Uses the private `CGVirtualDisplay` CoreGraphics API (same as DeskPad,
  BetterDisplay, …). Works on current macOS but is not App Store material.
- The virtual display participates in your display arrangement, so the mouse
  can wander onto it along one edge. It shows nothing on your physical
  screens, so if the cursor "disappears", drag it back.
