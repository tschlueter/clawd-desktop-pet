# Clawd Desktop Pet

A tiny pixel-art companion for your Mac. Clawd lives on your Dock and your desktop, walks around,
climbs onto your windows, and keeps himself busy with all kinds of little activities — from coding
and shipping releases to flying kites and making coffee.

## What it does

- **Lives on your desktop:** Clawd walks along the Dock, the bottom of your screens and the tops of
  your windows, jumps between them and falls off when you drag a window away.
- **Has a life of his own:** calm phases alternate with activities. He gets hungry and bored, takes
  naps, and on weekends he works less and plays more.
- **Reacts to you:** pick him up, throw him, shake him, click him. Several Clawds (up to 10) meet,
  greet and team up with each other.
- **Stays out of your way:** while a video is playing he goes quiet, and when an app goes fullscreen
  he pauses and hides until the coast is clear.
- **Talks in his own voice:** all sounds are synthesized on the fly — no audio files.
- **Fits your Mac:** light and dark appearance, English and German, adjustable size, speed,
  activity level, chattiness and volume.

## Installation

1. Download `Clawd-Desktop-Pet-<version>.zip` from the [Releases](../../releases) page. It runs on
   Apple Silicon and Intel Macs.
2. Unzip it and move **Clawd Desktop Pet.app** to your Applications folder.
3. Open it. Because the app is not notarized by Apple, macOS will refuse to open it the first time
   and say it cannot verify the app. To allow it:
   - Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to
     the message about Clawd Desktop Pet, then confirm with your password.
   - Or, in Terminal: `xattr -dr com.apple.quarantine "/Applications/Clawd Desktop Pet.app"`

   You only need to do this once. If you'd rather not trust a downloaded build, build it yourself
   from source (see below).
4. Grant the Accessibility permission when asked, so Clawd can find the Dock.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9 or later (Xcode or the Command Line Tools) to build from source
- **Accessibility permission** (asked on first launch) — used only to read where the Dock and its
  icons are, so Clawd can walk on it. The app makes no network connections.

## Build & run

```bash
./build.sh            # builds "build/Clawd Desktop Pet.app"
./build.sh install    # … and copies it to ~/Applications (recommended for "Open at Login")
./build.sh release    # universal app (Apple Silicon + Intel), zipped in build/ for a GitHub release
./test.sh             # runs the test suite
```

## Menu

Clawd lives in the menu bar. Click his icon to open the menu, where you can adjust everything:

| Setting | What it does |
|---|---|
| Add / Remove Clawd | Brings another Clawd onto your desktop or sends one away. |
| Number of Clawds | Sets how many Clawds are around at once (1–10). |
| Feed Clawd 🍜 | Serves a meal to your hungry Clawds. |
| Size | Small, Medium or Large. |
| Speed | Leisurely, Normal or Brisk. |
| Activity | How busy Clawd keeps himself, from Lazybones to Hyperactive. |
| Chattiness | How much he talks on his own, from Silent to Chatterbox. |
| Appearance | Automatic (like macOS), Light or Dark. |
| Language | Automatic (like macOS), Deutsch or English. |
| Volume | Slider for his voice. A note appears above it while a video keeps him quiet. |
| Walk on Windows | Allows Clawd to climb onto the tops of your windows. |
| Magnetic Shoes | Lets him walk up and down the sides of your windows. |
| Open at Login | Starts Clawd automatically when you log in. |
| Open Accessibility Settings… | Shortcut to the permission he needs to find the Dock. |

## Animations

No spoilers — here is only how many there are in each group. Discover the rest yourself.

| Group | Animations |
|---|---:|
| Gestures & States | 8 |
| Free Time & Sports | 9 |
| Everyday | 9 |
| Crafts | 5 |
| Programming | 11 |
| Release & Ops | 8 |
| Office | 5 |
| Focus & Stress | 4 |
| Encounters (two Clawds) | 9 |
| Team Scenes (two Clawds) | 5 |
| **Total** | **73** |

## Performance

Clawd is meant to run all day without you noticing him in Activity Monitor:

| | Approx. |
|---|---|
| App size | 1.5 MB (about 0.6 MB zipped). Everything is drawn and synthesized at runtime, with no image or audio files. |
| Memory | about 15 MB |
| CPU | about 3 % of one core with one Clawd, measured on an Apple M2 Max |
| Network | none |

The window list is read twice per second and the Dock every two seconds. Only while Clawd is standing
on a window or flying through the air does he check windows more often. Every sprite is rendered once
and then cached.

## How it's built

Plain Swift with AppKit and Core Animation, packaged with Swift Package Manager — no third-party
dependencies.

| Part | What it does |
|---|---|
| `Stage` | One transparent, click-through overlay window per screen. Every Clawd and every prop is a `CALayer` on it, driven by a single 60 Hz tick. |
| `World` | Knows every surface Clawd can stand on: the Dock (via the Accessibility API), screen edges and visible window edges (via the window list). |
| `PetController` | One Clawd: a state machine for walking, idling, physics (falling, throwing, landing), mouse handling, needs and the choice of the next activity. |
| `Job` | A solo activity, written as a small script in phases (walk there → get the tool out → work → done) with its own props. |
| `Encounter` | The same idea for two Clawds that meet. |
| `ClawdSprite` | All pixel art, drawn as text grids (`"..XXEXX.."`) and rendered into cached, crisp `CGImage`s, themed for light and dark. |
| `Voice` | Procedural speech: syllables synthesized with `AVAudioEngine`, with per-event chattiness. |
| `MediaWatcher` | Detects video playback (power assertions) and fullscreen apps (window list). |
| `Playground` | An optional window with its own mini Dock and boxes instead of real windows, used for testing. |

Sources live in `Sources/Clawd` (activities in `Sources/Clawd/Jobs`), tests in `Tests/ClawdTests`.

### Developer launch options

Useful for trying things out without the menu:

```bash
"build/Clawd Desktop Pet.app/Contents/MacOS/Clawd" --demo <action>      # e.g. --demo job:deploy
"build/Clawd Desktop Pet.app/Contents/MacOS/Clawd" --drop 900,700 --force <action>
```

Further options (`--pair`, `--encounter <kind>`, `--playground`, `--weekend`, `--weekday` …) are
documented in `Sources/Clawd/LaunchOptions.swift`.

## Disclaimer

Clawd Desktop Pet is an unofficial fan project and is not affiliated with or endorsed by Anthropic.
