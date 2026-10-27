# HotspotHub

HotspotHub is an educational iOS-hosted desktop portal prototype. It contains a browser-based desktop and an iOS SwiftUI host backed by SwiftNIO's HTTP/1 implementation. It does **not** claim a generic web proxy or iPhone screen mirroring: those require separate security and capture work and real-device validation.

## Current status

- The portal is plain HTML/CSS/JavaScript and works offline after it is served. It includes movable/resizable app windows, taskbar, launcher, notes, tasks, calculator, text editor, drawing canvas, JSON formatter, clock, and a same-origin browser shell.
- The iOS target source starts/stops a SwiftNIO HTTP server, serves bundled portal files, provides `/health`, checks stable GitHub releases, and displays status/URL. It restricts methods, bounds request bodies and static file sizes, rejects traversal paths, and serves fixed app-bundle content.
- `/health` reports app version, server state, and uptime only.
- File sharing, remote proxying, streaming, USB transport, automatic IPA delivery, and arbitrary iOS remote control are not implemented.

## Network feasibility and device check

iOS can host TCP listeners, and SwiftNIO supplies the HTTP/1 parser/server pipeline here. Whether a Chromebook can reach a listener over Personal Hotspot depends on the iOS release, active interface/address, hotspot routing, and client isolation. This Windows workspace has no iPhone or Chromebook attached, so hotspot reachability is **unverified**. Do not treat a displayed local URL as proof of reachability. Test on the actual devices using the checklist below. Same-Wi-Fi is a fallback: put both devices on the same trusted Wi-Fi network and try the address shown by the app.

Keep HotspotHub open while serving. iOS may suspend it in the background or when locked. The app does not use unsupported background execution.

## Build

The GitHub Actions workflow installs XcodeGen on a macOS runner, generates `HotspotHub.xcodeproj`, and builds an unsigned device app. Tagged builds package an unsigned IPA, upload it as a workflow artifact, and publish a GitHub Release plus Pages-hosted AltStore source after a successful build. Unsigned IPAs require supported signing during installation. Bundle identifier: `org.hotspothub.ios`. The web portal is copied into the app bundle by the project resource reference. The current local environment is Windows and does not provide Xcode, so a physical-device build remains dependent on GitHub Actions.

## Browser and security limits

The portal's Browser opens ordinary destinations in a separate browser tab. It is not a proxy: websites may block embedding, and their requests do not pass through the iPhone. No arbitrary URL fetching or file sharing endpoint is exposed. The local HTTP portal is unauthenticated and should only be used on a trusted network; ordinary HTTP traffic is not encrypted. A proxy must add authenticated sessions, strict public-destination validation, DNS/redirect rebinding defenses, and request/response limits before it is enabled.

## Mirroring and USB

No capture extension or stream is included. iOS screen broadcasting requires the user-initiated ReplayKit broadcast flow and an Upload Extension; system-wide control of other apps is not available through public iOS APIs. USB-C alone does not create a Chromebook-to-iPhone IP network, and this project has not verified a supported ChromeOS transport. The iPhone app therefore makes no mirroring or wired-transport claims.

## Real-device checklist

1. Build and install on iPhone 17.
2. Open HotspotHub and keep it foregrounded.
3. Enable Personal Hotspot, connect Chromebook, start server.
4. Try the shown URL and `/health`; record the actual result and interface address.
5. If unreachable, connect both devices to the same Wi-Fi and retry.
6. Test locking/backgrounding and observe suspension/recovery.

## Distribution

The workflow publishes release assets and an AltStore-compatible source at the GitHub Pages root only after a successful version tag build. SideStore accepts compatible AltStore sources. LiveContainer source URL-scheme import is supported by its current releases, but this project makes no claim of device-side installation testing. No signing credentials are included; the generated IPA is unsigned.

Create stable releases by pushing a semantic version tag such as `v0.1.0`. Release publishing is gated on a successful iOS device build. The update checker reads the latest GitHub Release and only links to its page; it never installs an IPA silently. The project uses bundle identifier `org.hotspothub.ios` and versioned tags as the marketing version.

## Disclaimer

HotspotHub is an educational, open-source networking project designed to demonstrate local web hosting, HTTP communication, web proxy architecture, and screen streaming. It is intended for authorized browsing and testing. Users are responsible for following applicable network policies and website terms.

## License

MIT; see `LICENSE`.
