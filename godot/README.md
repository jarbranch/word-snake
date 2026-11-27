# Word Snake (Godot version)

The native version of Word Snake, built with [Godot 4](https://godotengine.org).
The original browser version is still in `index.html` at the top of this repository.

## Run it on your computer

1. Download **Godot 4.5 or newer** (the standard version, not .NET) from https://godotengine.org/download.
   It's a single program, so there's nothing to install: just unzip it and open it.
2. In the Project Manager choose **Import**, browse to this `godot` folder and select `project.godot`.
3. Press **F5** (or the ▶ button, top right) to play.

To see the phone arrow buttons on a computer, open **Debug → Customize Run Instances**,
tick **Enable Multiple Instances**, and put `--touch` in **Main Run Args**.

## Controls

- Arrow keys or WASD to steer, Space or P to pause, Enter to play again.
- On phones: swipe anywhere, or use the arrow buttons under the board.
  The Android back button pauses the game.

## Where things are

| File | What it does |
| --- | --- |
| `scripts/game.gd` | All the rules: board layout, obstacles, letters, scoring, levels. Tuning values are at the top. |
| `scripts/board.gd` | Draws the board, obstacles, letter tiles and the gliding snake. |
| `scripts/main.gd` | Screen layout, menus, input, timing, effects and saving the best score. |
| `scripts/words.gd` | The word lists (5 and 6 letters). Add words freely. |
| `scripts/palette.gd` | Colours and fonts. |
| `tests/bot_test.gd` | Plays 20 games x 8 levels automatically to check every level can be completed. |

Run the test from this folder with:

```
godot --headless --path . -s tests/bot_test.gd
```

## Putting it on an Android phone

1. In Godot: **Editor → Manage Export Templates → Download and Install**.
2. Install **Android Studio** (it brings the Android SDK) and **OpenJDK 17**.
3. In Godot: **Editor → Editor Settings → Export → Android**, set the Java SDK and Android SDK paths.
4. **Project → Export → Add… → Android**, then **Export Project** to make an `.apk` file.
5. Copy the `.apk` to your phone and open it (allow installing from unknown sources when asked),
   or plug your phone in with USB debugging on and use the Android button in Godot's top bar.

Publishing to Google Play or the App Store comes later, once the game is ready.

## Fonts

Inter by The Inter Project Authors, under the SIL Open Font License (see `fonts/LICENSE-Inter.txt`).
