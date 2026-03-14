# Mac Lid Lullaby

<p align="center">
  <img src="docs/mario.png" alt="Mario from Super Mario 64 DS" width="260" />
</p>

Bring back the feeling of Mario sending you off to bed on your Nintendo DS. Mac Lid Lullaby is a tiny menu bar app that plays a custom sound as you close your Mac’s lid.

## Demo

https://github.com/user-attachments/assets/7630a1f2-2d79-4eef-88dd-472709bad3fa

## Features

- Plays a sound right before your MacBook lid closes
- Choose your own audio file

## Download
See the releases page.

## Build Yourself
Open [`Mac Lid Lullaby.xcodeproj`](/Users/patrickgatewood/Developer/macbook-lid/Mac%20Lid%20Lullaby.xcodeproj) in Xcode and build, or use:

```zsh
./scripts/build-app.sh
```

That creates `dist/Mac Lid Lullaby.app`, which runs in the menu bar with a waving hand icon.

## How It Works

At a high level, the app polls the MacBook lid angle sensor, watches for the lid moving downward, and starts the selected audio at the right moment.

Because macOS normally wants to sleep as the lid closes, the app also temporarily disables clamshell sleep just long enough for the sound to finish, then restores normal behavior right after.

## Attribution
Shoutout to the awesome [Hingemonium](https://github.com/Rocktopus101/Hingemonium) repo for introducing me to the Mac’s hinge sensor.
