import SwiftUI

/// The settings window, laid out like System Settings: panes in a sidebar, grouped forms on the right.
/// New features get a new `Pane`.
struct SettingsView: View {
    let engine: SyncEngine
    @State private var pane: Pane? = .general

    enum Pane: String, CaseIterable, Identifiable {
        case general = "General"
        case calibration = "Calibration"
        case about = "About"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .general: "gearshape.fill"
            case .calibration: "slider.horizontal.3"
            case .about: "info"
            }
        }

        var color: Color {
            switch self {
            case .general: .gray
            case .calibration: .orange
            case .about: .blue
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label {
                    Text(pane.rawValue)
                } icon: {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(pane.color.gradient, in: .rect(cornerRadius: 5))
                }
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralPane(engine: engine)
                case .calibration: CalibrationPane(engine: engine)
                case .about: AboutPane(engine: engine)
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane ?? .general).rawValue)
        }
        .frame(minWidth: 640, minHeight: 440)
    }
}

private func percent(_ level: Double) -> String {
    "\(Int((level * 100).rounded()))%"
}

// MARK: General

private struct GeneralPane: View {
    let engine: SyncEngine

    var body: some View {
        Form {
            Section {
                LabeledContent("MacBook", value: engine.laptopLevel.map(percent) ?? "Lid closed")
                LabeledContent("Monitor") {
                    if !engine.isSupported {
                        Text("Not available on this version of macOS")
                    } else if engine.monitorConnected {
                        Text(engine.monitorLevel.map { "\($0)%" } ?? "…")
                    } else {
                        Text("Not connected")
                    }
                }
            } header: {
                Text("Brightness")
            }
            .monospacedDigit()

            Section {
                Toggle("Match monitor to MacBook", isOn: Binding(get: { !engine.isPaused }, set: { engine.setPaused(!$0) }))
                    .disabled(!engine.isSupported)
            } footer: {
                Text("When this is off, the monitor keeps its current brightness and its own buttons work as usual.")
            }

            Section {
                Toggle("Open at login", isOn: Binding(get: { engine.opensAtLogin }, set: engine.setOpensAtLogin))
                Toggle("Show in menu bar", isOn: Binding(get: { engine.showsMenuBarIcon }, set: engine.setShowsMenuBarIcon))
            } footer: {
                Text("If the menu bar icon is hidden, open Brightern from Applications to get back to these settings.")
            }
        }
    }
}

// MARK: Calibration

/// Line the monitor up with the MacBook by eye at a few brightness levels.
private struct CalibrationPane: View {
    let engine: SyncEngine

    var body: some View {
        Form {
            Section {
                LabeledContent("MacBook", value: engine.laptopLevel.map(percent) ?? "Lid closed")
                LabeledContent("Monitor") {
                    HStack {
                        Slider(value: monitorBinding, in: 0...100)
                        Text("\(engine.calibrationLevel)%").frame(width: 40, alignment: .trailing)
                    }
                }
                HStack {
                    Button("Reset to 1:1") { engine.resetCalibration() }
                        .disabled(engine.curve.points.isEmpty)
                    Spacer()
                    Button("Save This Level") { engine.saveCalibrationLevel() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(engine.laptopLevel == nil || !engine.monitorConnected)
                }
            } header: {
                Text("Match the screens")
            } footer: {
                Text("The MacBook and the monitor use different screens, so the same percentage may not look equally bright. Set the MacBook's brightness with the brightness keys, drag the slider until the monitor looks the same, then click Save This Level. Repeat at a few levels, such as dim, medium and bright.")
            }
            .monospacedDigit()

            Section("Saved levels") {
                if engine.curve.points.isEmpty {
                    Text("None yet. The monitor uses the same percentage as the MacBook.")
                        .foregroundStyle(.secondary)
                }
                ForEach(engine.curve.points, id: \.self) { point in
                    HStack {
                        Text("MacBook \(percent(point.laptop)) → Monitor \(point.monitor)%").monospacedDigit()
                        Spacer()
                        Button {
                            engine.removeCalibrationPoint(point)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this level")
                    }
                }
            }
        }
        .onAppear { engine.beginCalibration() }
        .onDisappear { engine.endCalibration() }
    }

    private var monitorBinding: Binding<Double> {
        Binding(
            get: { Double(engine.calibrationLevel) },
            set: { engine.previewCalibrationLevel(Int($0.rounded())) }
        )
    }
}

// MARK: About

private struct AboutPane: View {
    let engine: SyncEngine

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("Brightern").font(.title2.bold())
                    Text("Version \(version)").foregroundStyle(.secondary)
                    Text("Keeps an external monitor's brightness in step with the MacBook's.")
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                LabeledContent("Monitor", value: "Tern Setups OLED")
                LabeledContent("Status", value: engine.monitorConnected ? "Connected" : "Not connected")
                LabeledContent("Source code") {
                    Link("github.com/axeleth/Brightern", destination: URL(string: "https://github.com/axeleth/Brightern")!)
                }
            }
        }
    }
}
