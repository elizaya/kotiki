# Kotiki

Your cat lives on your Mac screen: it walks along the top and bottom edges of windows and the Dock, plays, naps and reacts to your cursor. The weather around it follows the season — right now it is winter and snow; more seasons are planned.

Two cats are built in today:

- **Tom** — grey, sturdy, permanently judging you.
- **Pirozhok** — black, small, round, saucer eyes.

Setting up your own cat is planned.

Clicks pass through the snow to the windows underneath. You can pet a cat (click), scratch it (hover) or carry it with the mouse: drop it over a window and it sits there, miss and it falls to whatever is below.

## Run

Requires macOS 12 or later.

```bash
xcode-select --install   # once, if not installed yet
bash build.sh
open build/Kotiki.app
```

The app is not signed with an Apple certificate. If you downloaded a ready build and macOS refuses to open it: System Settings → Privacy & Security → Open Anyway.

## Playing with snow

- Sweep the cursor quickly across a snowdrift to brush the snow off.
- Hold ⌥ and press the mouse button on a drift to make a snowball. Roll it over the snow to make it grow.
- Release while moving to throw it. Cats chase it, bat it back and sometimes catch it mid-air. They also start games on their own.
- Release while still to leave the ball standing. Put a smaller ball on top, then a third one, and you get a snowman.
- A snowman stands until the cats take it apart: after a minute or two they walk over and knock the balls off one by one.

While ⌥ is held, clicks do not reach the windows underneath. You can change the key or turn the game off in the menu.

## Settings

The cat icon in the menu bar:

- **Cats** — Tom, Pirozhok or both
- **Style** — illustration or pixel art
- **Snow** and **Wind** — snowfall strength, direction, clear the drifts
- **Antics** — how often the cats act up
- **Snow play** — on/off, the key, whether cats break snowmen
- **Cursor trap** — a cat lying belly-up grabs the cursor if you hover over its belly
- **Judging stare at night** — between 1:00 and 5:00
- **Show a scene** — trigger any scene by hand
- **Pause**, **Hide for an hour**

The menu is currently in Russian.

## Limitations

- Main display only.
- The Dock width is estimated.
- Cats are hidden in full-screen apps.

## Roadmap

- Windows version
- Set up your own cat
- Season selection
- Useful nudges: take a break after working too long, go to sleep at night
