# CosmiQ Companion — project context for AI assistants

Unofficial iPhone companion for the Deepblu COSMIQ+ / Cosmiq 5 dive computer,
built after Deepblu shut down its app and servers. Native SwiftUI +
CoreBluetooth, no server, no account: everything is phone ↔ device over BLE.
Shipped on the App Store (bundle id `com.pbouffaut.cosmiq`).

## Layout

- `CosmiqKit/` — Swift package holding everything testable without hardware:
  packet codec, settings model + write builders, dive header/profile parser,
  UDDF importer, CSV/UDDF exporters. `cd CosmiqKit && swift test` runs on
  macOS (35+ tests). **Protocol changes go here, with a test.**
- `App/Sources/` — SwiftUI app: `BLE/` (CoreBluetooth transport + session),
  `Store/` (logbook persistence, iCloud, tip jar), `Views/`.
- `project.yml` — XcodeGen spec. The `.xcodeproj` is generated, never
  committed: run `xcodegen generate` after adding/removing files.
- `docs/` — GitHub Pages site (marketing/support/privacy pages required by the
  App Store) + `appstore-metadata.md` (all App Store Connect copy).
- `scripts/generate_icon.swift` — regenerates the app icon PNG.

## Protocol (reverse-engineered by the community)

Nordic UART Service (`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`), ASCII hex lines:
`#[CMD][CSUM][LEN][PAYLOAD]\n` out, `$…` back. CSUM = two's complement of
(cmd + len + payload bytes); LEN counts payload *hex chars* (2× bytes).
Sources of truth:

- Settings commands: https://github.com/blue-notes-robot/cosmiq5-web
  (`technical_documentation.md`, and `logbook.js` since v69)
- Dive log commands (0x40–0x44): libdivecomputer `deepblu_cosmiq.c`
- Header layout/units: the official Deepblu app (`CosmiqLogHeader.java`),
  as documented by cosmiq5-web v69 — this overrides libdivecomputer where
  they disagree (salt flag, 0x80B4 sentinel, hard-coded sample intervals).

### Device quirks (learned the hard way — do not regress)

- The device wedges on back-to-back commands: keep **~300 ms between
  commands** (`CosmiqSession.interCommandGap`).
- Replies are **not reliably newline-terminated**: frame by the length field
  in the packet header, never by waiting for `\n`.
- All device operations must be serialized (`CosmiqBLEManager.exclusive`) —
  two interleaved conversations both time out.
- `$60` (freedive alarms 3–6) **never answers on the original COSMIQ+**
  (Gen 5 only). Treat as optional; probe once with a short timeout.
- Command `0x26` (freedive max time) **also carries freedive depth alarm 3**
  in its first byte — always round-trip the current value.
- Freedive depth alarms write in pairs; never send a guessed partner value.
- **Sector-wrap firmware bug**: profiles are written to `startSector % 256`
  but read from the full sector. Downloads must remap through
  `DiveParser.profileSlot` or dives past the wrap import garbage
  ("645 m" profiles, subsurface#3548).
- Gen 5 units may advertise without a name in the first packet: scan with
  duplicates allowed, accept NUS-advertising devices regardless of name.

## Apple / release

- Development team: `Q9AA7ZL33M` (the paid one — pinned in `project.yml`; the
  personal team `ZHSLWWC6P2` cannot use iCloud). Bundle id
  `com.pbouffaut.cosmiq` (`com.pbouffaut.CosmiqCompanion` is burned on the
  free team). iCloud Drive container: `iCloud.com.pbouffaut.cosmiq`.
- Release: bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in
  `project.yml` (builds are immutable once uploaded), `xcodegen generate`,
  then headless with the Mac's Xcode account:
  `xcodebuild archive -project CosmiqCompanion.xcodeproj -scheme CosmiqCompanion -destination 'generic/platform=iOS' -archivePath <path> -allowProvisioningUpdates`
  and `xcodebuild -exportArchive` with an ExportOptions.plist of
  `method: app-store-connect`, `destination: upload`, `teamID: Q9AA7ZL33M`.
- BLE does not work in the simulator; device testing needs a real iPhone and
  a real COSMIQ. The Diagnostics tab logs raw TX/RX packets.

## Invariants

- `Dive` is Codable and stored as JSON (locally + user's iCloud Drive): new
  stored properties must be **optional** so old logbooks keep decoding.
- If `DiveParser` output changes for the same raw bytes, bump
  `Logbook.parserVersion` so existing logbooks re-parse once (raw device
  bytes are kept in `Dive.rawData` for exactly this).
- The environment this project was developed in had the home directory itself
  inside an unrelated git repository — always check `git remote -v` before
  committing, and work in a clean clone if in doubt.
- Safety wording matters: this is life-support-adjacent software. Keep the
  "verify settings on the device screen" warnings; writes always read back
  the affected config packet for verification.
