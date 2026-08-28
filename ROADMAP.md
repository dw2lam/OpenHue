# OpenHue roadmap

## Where this is going: bulbs as first-class devices on your home server

Today OpenHue is a Mac app: the Mac holds the Bluetooth bond and talks to the bulbs directly. The next step is to make these Bluetooth-only Hue bulbs **natively usable from services like Homebridge / HomeKit, Home Assistant, or any automation server** — as long as that server is physically close to the bulbs and has a Bluetooth radio (built-in or a USB dongle). No Hue Bridge, ever.

### Why this works
Everything OpenHue does is plain BLE GATT (see the protocol table in the README). Nothing is Mac-specific except the CoreBluetooth transport and the SwiftUI shell. The same characteristic reads/writes run on Linux over BlueZ, so a small headless "OpenHue bridge" on the server can own the bulbs and publish them to whatever ecosystem you use.

### Constraints that shape the design
- **One connected central per bulb.** Whoever holds the link (Mac, server, phone) is the only controller at that moment. The bridge must be the single owner and everything else talks *to the bridge*, not to the bulb.
- **Bonds are per adapter.** The server pairs once (bulb made discoverable from the Hue app → Make Discoverable, exactly as with the Mac); the phone app keeps working.
- **BLE range.** The server must be within a room or two. A cheap USB BLE dongle or a Raspberry Pi acting as a satellite bridge covers other rooms.
- **Bulb schedules are one-shot.** The bulb stores schedules and fires them on its own clock (OpenHue can create them — the create packet's "MAC" is a UUID v4), but disarms each one after it fires. The bridge re-arms daily ones whenever it connects, exactly as the app does.

## Phases

### 1. Extract a transport-agnostic core (in progress by design)
`HueProtocol.swift`, `ColorMath.swift`, the TLV codec and the state model are already pure Swift with no CoreBluetooth dependency. Formalise this as an `OpenHueCore` package with a small `LightTransport` protocol (`read`, `write`, `subscribe`) so the same logic drives CoreBluetooth on the Mac and BlueZ on Linux.

### 2. Headless bridge daemon — `openhued`
A command-line daemon (Swift on Linux via BlueZ D-Bus, or a thin Python/Node service reusing the community `HueBLE` library if that ships faster) that:
- scans, pairs, remembers and keeps bulbs connected with the same reconnect/keepalive logic as the app;
- exposes a **local HTTP + WebSocket API** (`GET /lights`, `PUT /lights/{id}/state`, `POST /scenes/{id}/apply`, `PUT /lights/{id}/effect`) and an **MQTT** topic tree (`openhue/<light>/state`, `openhue/<light>/set`) with Home Assistant MQTT discovery payloads;
- runs the scheduler (wake-up / go-to-sleep fades, Police and other Mac-driven effects) server-side so nothing depends on a laptop being awake.
- First target: the ZimaCube (Docker, host Bluetooth passthrough, Tailscale-reachable).

### 3. Homebridge plugin — `homebridge-openhue`
A Homebridge platform plugin that discovers bulbs through `openhued`'s API and publishes each as a HomeKit **Lightbulb** service (On, Brightness, Hue/Saturation, ColorTemperature), plus scenes as switches and effects as an optional selector. Result: Siri, Home app, HomeKit automations and Control Centre all work with the Bluetooth bulbs. Home Assistant gets the same via MQTT discovery for free.

### 4. OpenHue app as a client
When a bridge is present on the network, the Mac app switches from "I own the bulbs" to "I control them through the bridge" (same UI, transport swapped), so the laptop can leave the house while the server keeps the lights on schedule. Direct BLE stays as the fallback when no bridge is reachable.

### 5. Nice-to-haves
- Multiple bridges / satellites for range, with the app picking the nearest.
- Matter bridge (matter.js) as an alternative to Homebridge once Matter-over-bridge support is stable.
- Expose bulb-stored schedules through the bridge API (create / arm / disarm / delete) so HomeKit automations can survive the server being down.
- Figure out the remaining alarm fields: trailer types other than `00`/`03` (weekday repeat mask?), the countdown "simple" action codes, and effect `09` (sunrise) as a directly writable effect.
- Light groups and entertainment-style synced effects across many bulbs.

## Near-term app items
- Wake-up schedule field test (2-minute fade → morning time).
- Learn and display each bulb's mireds range from the capabilities characteristic (`0001`) instead of assuming 153–500.
- Menu-bar scene picker polish; keyboard shortcuts for All Lights on/off.
- Notarized builds once a Developer ID is available.
