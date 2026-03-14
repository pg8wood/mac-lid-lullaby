# MacBook Lid "Bye-bye" app

Tiny menu-bar macOS proof of concept that watches the MacBook lid angle and plays a sound just before the lid closes.

## What this uses

- A polling loop that reads the lid angle from the same private HID sensor MacMonium uses.
- A private `IOPMrootDomain` clamshell-sleep override so the clip can finish playing while the lid closes.
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

- This intentionally uses private APIs and is not meant for App Store distribution.
- The lid sensor and clamshell override behavior can vary by Mac model, chip, and macOS version.
