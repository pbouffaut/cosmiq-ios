# CosmiQ Companion

An unofficial iPhone app for the **Deepblu COSMIQ+ / Cosmiq 5** dive computer,
built to keep the device fully usable after Deepblu shut down its app and
servers. Everything runs on-device over Bluetooth Low Energy — no account, no
server, nothing to shut down.

## Features

- **Device settings** — everything the official app could change: default mode,
  units, date display, screen timeout, backlight & eco mode, environment
  (altitude/salinity), safety factor, nitrox air mix, max PPO₂, scuba depth &
  time alarms, freedive max time and all six freedive depth alarms, plus
  one-tap clock sync.
- **Dive log download** — pulls dives straight off the computer, shows the
  depth/temperature profile, and keeps a local logbook (JSON in the Files app).
- **Export** — per-dive CSV, and UDDF for import into Subsurface, MacDive or
  divelogs.de.
- **Diagnostics** — raw packet log, handy for protocol debugging.

## Protocol credits

The BLE protocol was reverse-engineered by the community:

- Settings commands: [cosmiq5-web](https://github.com/blue-notes-robot/cosmiq5-web)
  (`technical_documentation.md`)
- Dive log commands: [libdivecomputer](https://github.com/subsurface/libdc)
  `deepblu_cosmiq.c` (Linus Torvalds, Jef Driesen)

The device speaks hex-encoded ASCII lines over the Nordic UART Service:
`#[CMD][CHECKSUM][LENGTH][PAYLOAD]\n`, where the checksum is the two's
complement of the byte sum. `CosmiqKit` implements the codec, the settings
model and the dive parser, with unit tests validated against known-good
packets from both sources.

## Project layout

```
CosmiqKit/         Swift package: protocol codec, settings, dive parser, exporters
  Tests/           swift test — runs on macOS, no device needed
App/Sources/       SwiftUI app
  BLE/             CoreBluetooth transport + high-level session
  Store/           local logbook persistence
  Views/           Connect, Settings, Logbook, Dive detail, Diagnostics
project.yml        XcodeGen spec (the .xcodeproj is generated, not committed)
```

## Building

Requirements: Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`), an Apple Developer account for device installs.

```bash
xcodegen generate          # creates CosmiqCompanion.xcodeproj
open CosmiqCompanion.xcodeproj
```

In Xcode: select the *CosmiqCompanion* target → Signing & Capabilities → pick
your team, then build & run on your iPhone (BLE does not work in the
simulator). Wake the COSMIQ+ and tap **Scan**.

Run the protocol tests without any hardware:

```bash
cd CosmiqKit && swift test
```

## Safety

This software is unofficial and experimental. **Always verify settings on the
device screen before diving**, and never rely on a single instrument for
life-safety decisions.
