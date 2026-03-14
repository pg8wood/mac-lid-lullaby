# MacBook Lid "Bye-bye" app

Tiny menu-bar macOS proof of concept that watches hidden lid-state values and plays a sound when the lid gets near closed.

## What this uses

- A polling loop that reads `LidAngle` from `ioreg` when available.
- A fallback to `AppleClamshellState` when angle data is unavailable.
- A bundled `mario-64-bye-bye.mp3` clip as the default sound.
- A menu-bar UI for choosing a different local audio file.

## Build & run

```bash
swift build --disable-sandbox
swift run --disable-sandbox
```

You should see a menu-bar item with a waving hand icon.

## Audio behavior

- If you choose a custom file from the menu, the app copies it into Application Support using the original filename and reuses it on future launches.
- If you have not chosen a custom file, the app uses the bundled `mario-64-bye-bye.mp3`.
- `Play Preview` lets you verify the current clip on demand.

## Notes

- This intentionally uses undocumented lid-state values and is not meant for App Store distribution.
- Hidden properties like `LidAngle` can vary by Mac model, chip, and macOS version.
