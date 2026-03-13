# MacBook Lid "Bye-bye" app

Tiny menu-bar macOS app that monitors lid state and plays a short "Bye-bye" cue when the lid gets near closed.

## What this uses

- Tries to read a `LidAngle` value from `ioreg` (if your Mac exposes it).
- Falls back to `AppleClamshellState` (closed/open) if angle is unavailable.
- Triggers once when angle drops below 4° (default), then re-arms when opened above 12°.

## Build & run

```bash
swift build
swift run
```

You should see a menu-bar item named `👋 Lid`.

## Audio behavior

- If `mario-bye-bye.wav` exists next to the executable (or in `Resources/` in development), it will play that.
- Otherwise, it uses macOS speech synthesis and says: "Bye-bye!"

## Adding the Mario sound clip yourself

I did **not** bundle a Nintendo-owned clip in this repository.

To add one locally:

1. Acquire your own short `.wav` file named `mario-bye-bye.wav`.
2. Put it next to the built executable, or in `Resources/mario-bye-bye.wav` during development.

## Notes

- Lid-angle access appears to rely on undocumented/private hardware properties and can vary by Mac model/chip/OS version.
- If your machine does not expose `LidAngle`, behavior falls back to simple closed/open detection.
