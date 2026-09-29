import SwiftUI
import NetworkExtension

@main
struct GoodbyeDPIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class TunnelModel: ObservableObject {
    @Published var status: NEVPNStatus = .invalid
    @Published var config: DPIConfig = DPIConfig.load()
    @Published var errorText: String = ""
    private var mgr: NETunnelProviderManager?

    init() {
        NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] note in
            if let s = (note.object as? NEVPNConnection)?.status {
                self?.status = s
            }
        }
        loadManager()
    }

    func loadManager() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] list, _ in
            self?.mgr = list?.first
            self?.status = list?.first?.connection.status ?? .disconnected
        }
    }

    func toggle() {
        if status == .connected || status == .connecting {
            mgr?.connection.stopVPNTunnel()
            return
        }
        installAndStart()
    }

    func saveConfig() {
        config.save()
    }

    private func tunnelBundleId() -> String {
        let app = Bundle.main.bundleIdentifier ?? "com.goodbye.dpi"
        return app + ".tunnel"
    }

    private func installAndStart() {
        config.save()
        let pluginId = tunnelBundleId()
        NETunnelProviderManager.loadAllFromPreferences { [weak self] list, err in
            if let err {
                DispatchQueue.main.async { self?.errorText = err.localizedDescription }
                return
            }
            let m = list?.first ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = pluginId
            proto.serverAddress = "GoodbyeDPI"
            proto.excludeLocalNetworks = true
            m.protocolConfiguration = proto
            m.localizedDescription = "GoodbyeDPI"
            m.isEnabled = true
            m.saveToPreferences { error in
                DispatchQueue.main.async {
                    if let error {
                        self?.errorText = error.localizedDescription + " (need paid Apple Developer or TrollStore for VPN)"
                        return
                    }
                    m.loadFromPreferences { loadErr in
                        if let loadErr {
                            self?.errorText = loadErr.localizedDescription
                            return
                        }
                        m.isEnabled = true
                        m.saveToPreferences { _ in
                            do {
                                try m.connection.startVPNTunnel()
                                self?.mgr = m
                                self?.errorText = ""
                            } catch {
                                self?.errorText = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject var model = TunnelModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()
                Button(action: { model.toggle() }) {
                    ZStack {
                        Circle()
                            .fill(on ? Color(red: 0.12, green: 0.55, blue: 0.38) : Color(red: 0.18, green: 0.20, blue: 0.24))
                            .frame(width: 168, height: 168)
                        VStack(spacing: 8) {
                            Text(on ? "ON" : "OFF")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text(label)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                .buttonStyle(.plain)
                Text("Splits TLS ClientHello and sends DNS over HTTPS so ISP DPI cannot reset Discord.")
                    .font(.system(size: 15))
                    .foregroundColor(Color(red: 0.55, green: 0.58, blue: 0.62))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if !model.errorText.isEmpty {
                    Text(model.errorText)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                Spacer()
                NavigationLink("Settings") {
                    SettingsView(model: model)
                }
                .font(.system(size: 16, weight: .semibold))
                .padding(.bottom, 28)
            }
            .background(Color(red: 0.07, green: 0.08, blue: 0.10).ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }

    var on: Bool { model.status == .connected }
    var label: String {
        switch model.status {
        case .connected: return "connected"
        case .connecting: return "connecting…"
        case .disconnecting: return "stopping…"
        default: return "tap to connect"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: TunnelModel
    @State private var hostText: String = ""

    var body: some View {
        Form {
            Section(header: Text("Mode")) {
                Picker("Mode", selection: $model.config.mode) {
                    ForEach(DPIMode.allCases, id: \.self) { m in
                        Text(m.title).tag(m)
                    }
                }
            }
            Section(header: Text("DoH")) {
                TextField("https://1.1.1.1/dns-query", text: $model.config.dohURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
            }
            Section(header: Text("Hosts (one per line)")) {
                TextEditor(text: $hostText)
                    .frame(minHeight: 160)
                    .font(.system(.body, design: .monospaced))
            }
            Section {
                Toggle("HTTP Host tricks", isOn: $model.config.httpTricks)
            }
        }
        .onAppear {
            hostText = model.config.hosts.joined(separator: "\n")
        }
        .onDisappear {
            model.config.hosts = hostText.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            model.saveConfig()
        }
        .navigationTitle("Settings")
    }
}
