<p align="center"><img src="Icon/preview-512.png" width="160" alt="openHue icon"></p>

# openHue

A native macOS app that controls Philips Hue **Bluetooth** bulbs directly over BLE — no Hue Bridge, no cloud, no phone. Swift / SwiftUI / CoreBluetooth, macOS 14+.

## What it is

Hue bulbs sold in the last few years contain a Bluetooth radio that Signify uses for the "Hue Bluetooth" phone app. openHue talks the same GATT protocol from your Mac: it discovers bulbs, pairs with them, reads and writes their state, and runs schedules on the Mac's clock. Everything stays local.

## Features

- Discover and pair bulbs, remember them across launches, keep them connected for instant commands.
- Per-light power, brightness, colour temperature, xy colour and the bulb's built-in effects (candle, fireplace, …).
- "All lights" controls, plus a menu-bar extra for quick access.
- Scenes: Hue's stock scenes (Bright, Relax, Energize, Savanna Sunset, …) and your own snapshots ("Save current as scene…").
- Schedules: weekly or one-off, turn on/off, **wake-up fade-in** and **go-to-sleep fade-out**, targeting all lights or a subset.
- Launch at login, keep-the-Mac-awake assertion, and an optional `pmset` scheduled wake so a laptop can run a morning schedule.
- Diagnostics view: raw characteristic dump, raw read/write, power-on default, live log.

## Limits

- **Bluetooth range.** Bulbs must be within BLE range of the Mac (a room or two; walls hurt).
- **One connected device per bulb.** While this app is connected the Hue phone app can't reach the bulb, and vice versa. Use *Disconnect All* (Settings → Data, or the menu bar) to hand a bulb over.
- **No on-bulb schedules.** Hue bulbs only accept schedules created by the official app (the request is MAC-protected). Schedules in openHue run on the Mac — see [Schedules](#schedules).
- **Bridge-joined bulbs are unsupported.** Once a bulb has joined a Hue Bridge (Zigbee) its Bluetooth control is disabled. Remove it from the Bridge or factory-reset it.
- **Renaming is best effort.** The name is stored locally and also written to the bulb's name characteristic, which some firmware ignores.

## Install

Grab `openHue.zip` (or the `.dmg`) from the [latest release](https://github.com/dw2lam/openHue/releases/latest), unzip, and drag **openHue.app** to `/Applications`.

The build is signed with an Apple *Development* certificate, not a notarized Developer ID, so on first launch Gatekeeper will refuse it. Either **right-click → Open → Open**, or clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/openHue.app
```

Then follow [First launch](#first-launch). To build from source instead, see [Build & run](#build--run).

## Build & run

Requirements: Xcode 26 (Swift 6 toolchain, Swift 5 language mode), macOS 14 or later.

```sh
./make-app.sh          # builds build/openHue.app (release), signs with your Apple Development identity if one is present
open "build/openHue.app"
swift test             # protocol / colour-math / scheduler tests
```

Do **not** run the bare binary with `swift run`. The Bluetooth permission is attributed to the process that owns the TCC prompt — for a bare binary that is Terminal, not the app — and the executable has no `Info.plist` with the required `NSBluetoothAlwaysUsageDescription`, so CoreBluetooth reports `unauthorized`. Always launch the `.app` that `make-app.sh` produces.

## First launch

1. macOS asks *"openHue would like to use Bluetooth"* — click **Allow**.
   If you denied it (or it never appeared), enable the app under **System Settings → Privacy & Security → Bluetooth**, then relaunch.
2. Click **Add Light**. Power the bulb on and keep it within a couple of metres; it appears in the list with a signal indicator.
3. Click **Add**. The first command to the bulb triggers pairing — see below.

## Pairing

Hue bulbs pair implicitly: the first encrypted read makes macOS show a **Connection Request** dialog for the bulb. Click **Connect** (or **Pair**). After that the Mac remembers the bond and reconnects silently.

If the dialog never appears or pairing fails, the bulb is still bonded to your phone and is refusing new pairings. Bulbs only accept a new pairing while **discoverable**:

1. **Make the bulb discoverable from the phone — no Bridge needed, and the phone app keeps working.** In the Hue app go to **Settings → Voice Assistants → Amazon Alexa** (or **Google Home**) **→ Make Discoverable**. This is the same window Echo/Nest speakers use to pair with Bluetooth-only bulbs, and it's what openHue needs. Then, within a minute or two, click **Retry** in openHue (or add the light). If the phone app is still holding the connection, background it right after tapping Make Discoverable.
2. **Last resort — factory reset.** Switch the bulb off and on **5 times** (about a second apart), ending **on**; it blinks on the last cycle. This unpairs the phone app too and gives the bulb a **new Bluetooth address**, so it appears as a fresh "Hue Lamp": use **Add Light → "Add as replacement for…"** and pick the old entry (name, scenes and schedules carry over), then click **Connect** on the macOS Connection Request.
3. If macOS still refuses, forget any stale **"Hue Lamp"** entry in **System Settings → Bluetooth** (hover → ⓘ → Forget) and retry.
4. **Bulb joined to a Hue Bridge?** It cannot be controlled over Bluetooth at all. Delete it from the Bridge first.

The same steps are shown inside the app (Add Light → Pairing help, and in a light's detail view when pairing stalls).

## Schedules

Third-party apps can't store schedules on the bulb, so openHue runs them **on this Mac**. For a schedule to fire:

- the Mac must be **awake** (not sleeping; the display may be off),
- **openHue must be running** — turn on **Launch at login** (Settings → General),
- the bulbs must be **within Bluetooth range**.

Helpers in **Settings → Schedules / Wake Mac**:

- **Keep this Mac awake while openHue is running** holds a `PreventUserIdleSystemSleep` assertion. Reliable on a desktop or a plugged-in laptop; on battery it costs power.
- **Wake this Mac** writes a `pmset repeat wakeorpoweron <days> <time>` entry (macOS asks for your administrator password once). The app suggests the union of your weekly schedule days at 2 minutes before the earliest one. A MacBook with the **lid closed** only wakes for this if it is on power **and** connected to an external display; otherwise open the lid. `pmset repeat cancel` removes *all* repeating pmset events, so check `pmset -g sched` if you use others.
- **Missed schedules.** If the Mac was asleep at the trigger time, an *on* schedule still runs when the Mac wakes within the grace window (default 30 min — a wake-up fade resumes mid-ramp), and an *off* schedule within its own window (default 6 h). Set either to 0 to disable.

Each row in the Schedules view shows the next fire time and the last outcome ("Ran 07:00", "Skipped — Mac was asleep 45 min", …).

## Data location

Everything lives in `~/Library/Application Support/openHue/` as plain JSON (`lights.json`, `scenes.json`, `schedules.json`, `settings.json`), written atomically. Settings → Data → **Open folder** reveals it. Deleting the folder resets the app; the Bluetooth bonds themselves live in macOS (System Settings → Bluetooth).

## Troubleshooting

- **Diagnostics view** (sidebar) shows the Bluetooth state, each bulb's connection state, RSSI, firmware, decoded state, every characteristic with its last raw value, and a raw read/write box. The log panel at the bottom mirrors the app's unified log; **Copy** puts it on the clipboard.
- Same log from Terminal:
  ```sh
  log stream --predicate 'subsystem == "com.davidlam.openhue"'
  ```
- **Bulb shows "Not found — rescan"**: it isn't advertising. It is off, out of range, or connected to another device (the phone app). Power-cycle it once and click Rescan.
- **"Pairing failed"** or the Connection Request never appears: follow [Pairing](#pairing) — make the bulb discoverable from the phone app, or factory-reset and re-add it as a replacement.
- **Stale bond**: after a factory reset macOS may still hold the old pairing. Forget "Hue Lamp" in System Settings → Bluetooth, then add the bulb again.
- **Commands feel slow**: enable *Keep lights connected* (Settings → General). Otherwise the app connects on demand (a few seconds).
- **Schedule didn't run**: check the row's last outcome, then Settings → Schedules (keep awake / grace windows) and Wake Mac (`pmset -g sched`).

## Protocol notes

Bulbs advertise the Signify 16-bit service UUID `FE0F` (in `serviceUUIDs` or `serviceData`). Once connected, the light service is `932c32bd-0000-47a2-835a-a8d455b859dd`; characteristics share that base and differ in the second group:

| Characteristic | UUID (`932c32bd-XXXX-47a2-835a-a8d455b859dd`) | Format |
|---|---|---|
| Capabilities | `0001` | 15 bytes, read-only (likely TLV with mireds range — dump it in Diagnostics) |
| Power | `0002` | 1 byte, `00`/`01`; R/W/Notify. Reading it is what triggers the pairing dialog |
| Brightness | `0003` | 1 byte, `1…254` (never write `0`); R/W/Notify |
| Colour temperature | `0004` | `uint16` little-endian mireds `153…500` (454 on some models); reads `FFFF` while in xy mode |
| Colour xy | `0005` | 2 × `uint16` LE = `round(x·65535)`, `round(y·65535)`; reads `FFFFFFFF` while in CT mode |
| Alert | `0006` | write-only: `00` none, `01` flash once, `02` flash repeatedly |
| Combined state | `0007` | TLV `[tag][len][value]…`: `01` on, `02` brightness, `03` mireds, `04` xy, `06` effect, `08` effect speed; R/W/Notify — the one read that returns the whole state |
| Power-on default | `1005` | same TLV as `0007` followed by `FF FF FF FF`; R/W |

Other services:

| Service / characteristic | UUID | Notes |
|---|---|---|
| Device configuration | `FE0F` | name `97fe6561-0003-4f62-86e9-b71ee2da3d22` (ASCII, R/W best effort), Zigbee address `97fe6561-0001-…` (8 bytes), pairing control `97fe6561-2001-…` |
| Device Information | `180A` | manufacturer `2A29`, model `2A24`, firmware `2A28` |
| On-bulb alarms | `9da2ddf1-0001-44d0-909c-3f3d3cb34a7b` | list / enable / disable / delete only; creation is MAC-protected |

Effects (tag `06`): `01` candle, `02` fireplace, `03` prism, `0A` sparkle, `0B` opal, `0C` glisten, `0E` underwater, `0F` cosmos, `10` sunbeam, `11` enchant.

Credit: the protocol was reverse-engineered by the community — chiefly [flip-dots/HueBLE](https://github.com/flip-dots/HueBLE) and [glyphack/huec](https://github.com/glyphack/huec), with macOS pairing notes from ai212983/blemacd. This project is not affiliated with Signify / Philips Hue.
