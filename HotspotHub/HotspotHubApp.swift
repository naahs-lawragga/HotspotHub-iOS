import SwiftUI

@main
struct HotspotHubApp: App {
    @StateObject private var server = PortalServer()
    var body: some Scene { WindowGroup { DashboardView().environmentObject(server) } }
}
