import SwiftUI
import UIKit

@MainActor
struct DashboardView: View {
    @EnvironmentObject private var server: PortalServer
    @StateObject private var updates = UpdateChecker()
    @AppStorage("keepAwake") private var keepAwake = false
    var body: some View {
        NavigationStack {
            List {
                Section("SERVER STATUS") {
                    Label(server.state, systemImage: server.state == "Online" ? "checkmark.circle.fill" : "circle.slash")
                    if let url = server.address { LabeledContent("Local URL", value: url); ShareLink(item: url) { Label("Share / Copy Address", systemImage: "square.and.arrow.up") } }
                    LabeledContent("Port", value: "8080")
                    Text("A running server does not guarantee that another device can reach it.").font(.footnote).foregroundStyle(.secondary)
                    if let error = server.error { Text(error).foregroundStyle(.red) }
                    HStack {
                        Button("Start Server", systemImage: "play.fill") { server.start() }.disabled(server.state == "Online")
                        Button("Stop", systemImage: "stop.fill", role: .destructive) { server.stop(); keepAwake = false; UIApplication.shared.isIdleTimerDisabled = false }.disabled(server.state == "Offline")
                    }
                }
                Section("CONNECTION HELP") {
                    Text("Enable Personal Hotspot and connect the Chromebook, or connect both devices to the same Wi-Fi. Open the local URL shown above. Keep HotspotHub open while using the desktop.")
                    Text("Hotspot reachability is unverified until tested on your iPhone and Chromebook.").font(.footnote)
                }
                Section("SYSTEM") {
                    Toggle("Keep Screen Awake", isOn: $keepAwake).onChange(of: keepAwake) { value in UIApplication.shared.isIdleTimerDisabled = value }
                    Text("Keeping the display awake uses more battery. Normal screen behavior resumes when this setting is off.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("UPDATES") {
                    LabeledContent("Current version", value: updates.currentVersion)
                    if let release = updates.latest, updates.hasUpdate {
                        LabeledContent("Available", value: release.version)
                        if let notes = release.body, !notes.isEmpty { Text(notes).font(.footnote).lineLimit(6) }
                        Link("UPDATE NOW — Open Release", destination: release.htmlURL)
                        Text("Updates are downloaded from GitHub and must be installed through a supported sideloading/signing flow.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(updates.isChecking ? "Checking…" : "Check for Updates") { Task { await updates.checkNow() } }.disabled(updates.isChecking)
                    if let message = updates.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("APPS") {
                    Label("Browser", systemImage: "safari"); Label("Files", systemImage: "folder")
                    Label("iPhone Mirroring", systemImage: "iphone"); Text("Mirroring, proxying, and file sharing are not enabled in this build.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("ABOUT") {
                    Text("HotspotHub is an educational, open-source networking project designed to demonstrate local web hosting, HTTP communication, web proxy architecture, and screen streaming. It is intended for authorized browsing and testing. Users are responsible for following applicable network policies and website terms.").font(.footnote)
                }
            }.navigationTitle("HotspotHub")
                .task { await updates.checkIfDue() }
        }
    }
}
