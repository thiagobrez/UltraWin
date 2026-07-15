---
layout: page
title: Support
---

# UltraWin Support

UltraWin is a macOS app that lets you share **only part of your ultrawide
screen** in video calls — without moving any windows around.

If you have a question that isn't answered below, email
**[thiagobrez@gmail.com](mailto:thiagobrez@gmail.com)** and I'll get back to you.

## Getting started

UltraWin lives in your **menu bar**:

1. Click the menu bar icon and choose **Select Region to Share…** (or press
   **⌘⇧U** from anywhere).
2. Drag to select the part of your screen you want to share. Everything
   outside it dims, and the region gets a live highlight.
3. In Zoom, Google Meet, Teams — any app — share the screen named
   **"UltraWin Display"**. Everyone sees just your selected region.
4. Press the hotkey again (or choose **Stop Sharing**) when you're done.

While sharing, drag the frame's **edges to move it** and **corners to resize
it** — the shared output follows live.

## Frequently asked questions

### Why does UltraWin need Screen Recording permission?

macOS requires it for any app that reads screen content. UltraWin uses it for
one thing only: mirroring your selected region onto the invisible virtual
display you share in your meeting. Nothing is recorded, stored, or sent
anywhere — see the [Privacy Policy](privacy-policy). Grant it in **System
Settings → Privacy & Security → Screen Recording**, then relaunch the app.

### I don't see "UltraWin Display" in Zoom / Meet / Teams

- Make sure UltraWin is running (its icon is in the menu bar) — the virtual
  display is attached while the app runs.
- Re-open your meeting app's share dialog; some apps only enumerate screens
  when the picker opens.
- In browser-based calls (Meet in Chrome), pick the **"Entire screen"** tab —
  UltraWin Display shows up as one of the screens.

### My screen flickers when UltraWin launches or when I stop sharing

That's macOS reconfiguring displays when the virtual display attaches or
changes mode — the same brief flicker you get when plugging in a monitor.
UltraWin keeps one persistent virtual display attached to pay that cost once,
at launch, instead of on every share.

### What does "Snap to 16:9" do?

It locks your selection to a 16:9 shape and outputs a fixed **1920×1080**
display — the cleanest result in meeting apps, which expect standard screen
shapes. You can toggle it from the menu bar or in Preferences, even while a
selection is active.

### Can I change how much the rest of the screen dims?

Yes — **Dim Outside Region** in the menu bar menu (or Preferences) has three
levels: Off, Light, and Strong. Dimming is only visible on your screen, never
in what you share.

### The hotkey doesn't work

Another app may already use ⌘⇧U. Set a different combination in
**Preferences… → Region selection shortcut**.

### How do updates work?

UltraWin checks a static file on GitHub Pages and updates itself
([Sparkle](https://sparkle-project.org)). You can check manually or toggle
automatic updates in **Preferences… → About**. Homebrew installs update the
same way (`brew upgrade` skips self-updating apps unless run with `--greedy`).

### What are the system requirements?

macOS 14 (Sonoma) or later.

## Contact

**Thiago Brezinski** — [thiagobrez@gmail.com](mailto:thiagobrez@gmail.com)

Bug reports and feature requests are also welcome on
[GitHub](https://github.com/thiagobrez/UltraWin/issues).
