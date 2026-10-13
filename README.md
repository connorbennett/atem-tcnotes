# EditNotes

A macOS app for logging timecoded editorial notes during live events and studio recordings, then importing them
into Adobe Premiere Pro as markers.

- **Time-of-day timecode** from an NTP server, in GMT by default, at 25 fps or any other common frame rate.
- **Type at any time.** A note is saved at the timecode where you started typing it.
- **Shortcuts** for common notes (GFX, VFX, TAKE, MUSIC…) with assignable hotkeys.
- **OSC control**, so shortcuts can be triggered from Bitfocus Companion or anything else that sends OSC.
- **Blackmagic ATEM** integration: follow the switcher's timecode, frame rate and recording name.
- **Premiere Pro XML** marker export.

## Requirements

- macOS 14 Sonoma or later, on Apple silicon or Intel.
- [ATEM Software Control](https://www.blackmagicdesign.com/support/family/atem-live-production-switchers), only
  if you want to connect to an ATEM switcher. It installs the SDK runtime EditNotes loads.

## Install

Download `EditNotes.zip` from the [latest release](https://github.com/connorbennett/atem-tcnotes/releases/latest),
unzip it and move EditNotes to Applications. Release builds are signed and notarized.

## OSC and Bitfocus Companion

EditNotes listens on UDP port 9300 (Settings > OSC).

| Address | Arguments | Result |
| --- | --- | --- |
| `/editnotes/shortcut/GFX` | none | Adds the marker for the shortcut labelled GFX |
| `/editnotes/shortcut/2` | none | Adds the marker for the second shortcut in the list |
| `/editnotes/shortcut` | string or integer | Same, with the label or number as the argument |
| `/editnotes/note` | string text, optional string name, optional string colour | Adds a free-text marker |
| `/editnotes/undo` | none | Removes the most recently added marker |

The Companion module in [Companion/](Companion/README.md) reads your shortcuts from the app (TCP port 9301) and
creates a button for each one automatically. Companion's built-in Generic OSC connection also works with the
addresses above.

## Building

Open `EditNotes.xcodeproj` in Xcode and run. The ATEM SDK header and dispatch file are vendored in
`EditNotes/ATEM/SDK` under Blackmagic Design's licence.
