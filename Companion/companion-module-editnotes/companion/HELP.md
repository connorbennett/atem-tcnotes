## EditNotes

Adds a button for every marker shortcut in the EditNotes Mac app, and keeps them in sync with the app.

### Setup

1. In EditNotes, open **Settings > OSC** and make sure **Receive OSC** and **Share shortcuts with the Companion
   module** are both on.
2. Set **EditNotes IP** to the Mac running EditNotes (127.0.0.1 if Companion is on the same Mac) and **Module
   port** to the module port shown in EditNotes (9301 by default).

### Buttons

Open the **Presets** tab and drag buttons from **EditNotes > Shortcuts** onto your pages. There is one per
shortcut, plus an undo button. Adding, removing or reordering shortcuts in EditNotes updates the preset list
within a couple of seconds. A button you have already placed follows its shortcut's label and colour when you
change them in EditNotes.

### Actions

- **Add shortcut marker** – pick a shortcut from the list, or type a label (`GFX`) or list position (`2`).
- **Add note** – add a free-text marker, with an optional marker name and colour.
- **Remove last marker** – undo the most recently added marker.

### Variables

- `$(editnotes:project_name)` – the current project name.
- `$(editnotes:label_<id>)` – the label of each shortcut.
