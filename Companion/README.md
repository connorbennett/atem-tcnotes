# Triggering EditNotes from Bitfocus Companion

EditNotes listens for OSC on UDP port 9300 (change it in EditNotes > Settings > OSC). There are two ways to drive
it from Companion.

## Option 1: the EditNotes module

`companion-module-editnotes` adds a connection with *Trigger shortcut*, *Add note* and *Remove last marker*
actions, plus ready-made button presets for the default shortcuts.

1. Install its dependency:

   ```bash
   cd Companion/companion-module-editnotes && yarn install
   ```

2. In the Companion launcher, open the settings (cog icon), set **Developer modules path** to this `Companion`
   folder, and restart Companion.
3. Add an **EditNotes** connection and set the target IP (127.0.0.1 when Companion runs on the same Mac) and port.

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
