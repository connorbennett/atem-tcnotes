# Triggering EditNotes from Bitfocus Companion

EditNotes listens for OSC on UDP port 9300 and shares its shortcut list on TCP port 9301 (both in EditNotes >
Settings > OSC). There are two ways to drive
it from Companion.

## Option 1: the EditNotes module

`companion-module-editnotes` reads your shortcuts from EditNotes and creates a preset button for each one, with
its label and colour. The list follows the app: add, remove or reorder a shortcut and the presets update within a
couple of seconds, and buttons you have already placed pick up label and colour changes.

1. Get the module package: download `editnotes-1.1.0.tgz` from the
   [latest release](https://github.com/connorbennett/atem-tcnotes/releases/latest), or build it yourself:

   ```bash
   cd Companion/companion-module-editnotes && npm install && npm run package
   ```

2. In Companion, open **Modules**, choose **Import module package** and select the `.tgz`.
3. In EditNotes > Settings > OSC, check **Receive OSC** and **Share shortcuts with the Companion module** are on.
4. Add an **EditNotes** connection in Companion. Set the IP (127.0.0.1 when Companion runs on the same Mac) and
   the module port (9301 by default).
5. Open the **Presets** tab and drag the buttons under **EditNotes > Shortcuts** onto a page.

The module reads the shortcut list over HTTP from the module port (`GET /api/state`) and sends triggers back over
OSC, so both ports need to be reachable from the Companion machine.

## Option 2: Companion's built-in Generic OSC connection

No install needed. Add a **Generic OSC** connection pointing at the Mac running EditNotes, then use its
*Send message without arguments* or *Send string* actions with these addresses:

| Address | Arguments | Result |
| --- | --- | --- |
| `/editnotes/shortcut/GFX` | none | Adds the marker for the shortcut labelled GFX |
| `/editnotes/shortcut/2` | none | Adds the marker for the second shortcut in the list |
| `/editnotes/shortcut` | string or integer | Same, with the label or number as the argument |
| `/editnotes/note` | string text, optional string name, optional string colour | Adds a free-text marker |
| `/editnotes/undo` | none | Removes the most recently added marker |

Markers are stamped with EditNotes' timecode at the moment the message arrives.
