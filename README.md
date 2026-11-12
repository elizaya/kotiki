# Kotiki

A cat that lives on your Mac screen. It walks along window edges and the Dock, plays, naps and reacts to your cursor while snow falls around it.

Two cats are built in: Tom (grey, sturdy, permanently judging you) and Pirozhok (black, small, round, saucer eyes).

![Kotiki: two cats and a snowman on the screen](docs/preview.png)

## Install

You need a Mac with macOS 12 or later.

**Ready-made app.** Download `Kotiki.zip` from the [latest release](https://github.com/elizaya/kotiki/releases/latest), unzip it, move `Kotiki.app` to Applications and open it.

**Build it yourself.**

```bash
xcode-select --install
git clone https://github.com/elizaya/kotiki.git
cd kotiki
bash build.sh
open build/Kotiki.app
```

`xcode-select --install` is needed once; skip it if the Command Line Tools are already installed. The build takes about a minute and downloads nothing else.

To keep the app, copy it to Applications:

```bash
cp -R build/Kotiki.app /Applications/
```

## First launch

- The cats drop in from the top of the screen and a cat-head icon appears in the menu bar. There is no Dock icon and no window.
- No permissions are needed. The app does not ask for screen recording, accessibility or anything else.
- If macOS refuses to open the app: System Settings → Privacy & Security → Open Anyway.
- To start it at login: System Settings → General → Login Items → add Kotiki.

## How to use

Everything is controlled from the cat-head icon in the menu bar. The menu is in Russian for now; the items below are listed in the order they appear.

**The cats**

- Click a cat to pet it.
- Hold the cursor over a cat to scratch it: it squints and purrs.
- Press and drag to carry a cat. Drop it over a window and it sits there; miss and it falls to whatever is below.
- Wiggle the cursor quickly near a cat and it hunts it.
- Leave the Mac idle for five minutes and the cats curl up and get snowed on.
- Now and then a cat sharpens its claws: on the floor, or standing up against a wall (the edge of the screen or the side of a window it is sitting in).
- The cats sit on the Dock. If the Dock hides automatically, they hop onto it when it slides out and drop back down when it goes away.
- With both cats on, they keep to their own side and do not walk through each other.

**Snow**

- Snow piles up on the top and bottom edges of windows, on the Dock and at the bottom of the screen.
- Clicks pass through the snow to whatever is underneath.
- Sweep the cursor quickly across a drift to brush it off.

**Snowballs and snowmen**

- Hold ⌥ and press the mouse button on a drift to make a snowball. Roll it over the snow to make it bigger.
- Let go while moving to throw it. Cats chase it, bat it back and sometimes catch it mid-air. They also start games on their own.
- Let go while still to leave the ball standing. Put a smaller ball on it, then a third, and you get a snowman.
- A snowman stands until the cats take it apart: after a minute or two they walk over and knock the balls off one by one.
- ⌥ + click on a snowman takes its top ball off.

While ⌥ is held, clicks do not reach the windows underneath.

**Menu**

- Pause, Hide for an hour
- Cats: Tom, Pirozhok or both
- Style: illustration or pixel art
- Snow: off, light, normal, blizzard; clear the drifts
- Wind: direction and strength
- Antics: how often the cats act up
- Snow play: on/off, how to play, the key (⌥, ⇧ or ⌘), whether cats break snowmen
- Cursor trap: a cat lying belly-up grabs the cursor if you hover over its belly
- Judging stare at night: between 1:00 and 5:00 a big cat face rises in the corner
- Show a scene: trigger any scene by hand
- Updates: current version, automatic updates on/off, check now
- Quit

## If something is off

- **No snow on windows.** A maximised window has no room above it. Make a window smaller and snow starts to collect on its top edge.
- **Can't click something under a cat.** A click on a cat goes to the cat. Drag it away, or use Hide for an hour.
- **Snowballs don't work.** Hold the key first, then press the mouse button on a drift that already has some snow. Check that Snow play is on in the menu.
- **⌥ + click stopped working in other apps.** While the key is held the app takes the mouse. Pick another key in Snow play or turn the game off.
- **Cats are missing.** They are hidden in full-screen apps and while paused. They only appear on the main display.

## Update and remove

The app updates itself. A few times a day it looks at the [latest release](https://github.com/elizaya/kotiki/releases/latest), downloads the new version and restarts into it once the Mac has been idle for five minutes. If you do not want to wait, the menu shows "Обновить до … и перезапустить" as soon as the download is ready. Turn this off in the menu under Обновления.

If the app cannot replace itself (for example, it was opened straight from Downloads), the menu offers a link to the release page instead. Move `Kotiki.app` to Applications to get automatic updates.

If you built it yourself:

```bash
git pull && bash build.sh
```

**Publishing a release.** Bump `VERSION` in `build.sh`, run `bash build.sh`, create a release tagged `v` + that version and attach `build/Kotiki.zip`. Installed copies pick it up on their own.

Remove: quit from the menu, then delete `Kotiki.app`. Settings are removed with:

```bash
defaults delete local.kotiki.tom-i-pirozhok
```

## Roadmap

- Cats interacting with each other (for now they only keep apart): greeting, grooming, chasing, sleeping side by side
- Windows version
- Set up your own cat
- Season selection
- Useful nudges: take a break after working too long, go to sleep at night
