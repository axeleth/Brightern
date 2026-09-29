import SwiftUI

/// Line the monitor up with the MacBook by eye at a few brightness levels.
struct CalibrationView: View {
    static let windowID = "calibrate"

    let engine: SyncEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Make the monitor match your MacBook").font(.headline)
                Label("Set the MacBook's brightness with the brightness keys.", systemImage: "1.circle")
                Label("Drag the slider until the monitor looks the same.", systemImage: "2.circle")
                Label("Click Save This Level. Repeat at a few different levels.", systemImage: "3.circle")
            }
            .foregroundStyle(.secondary)

            GroupBox {
                VStack(spacing: 10) {
                    LabeledContent("MacBook") {
                        Text(engine.laptopLevel.map(percent) ?? "Lid closed").monospacedDigit()
                    }
                    LabeledContent("Monitor") {
                        HStack {
                            Slider(value: monitorBinding, in: 0...100, step: 1)
                            Text("\(engine.calibrationLevel)%")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                .padding(6)
            }

            HStack {
                Button("Reset to 1:1") { engine.resetCalibration() }
                    .disabled(engine.curve.points.isEmpty)
                Spacer()
                Button("Save This Level") { engine.saveCalibrationLevel() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(engine.laptopLevel == nil || !engine.monitorConnected)
            }

            if !engine.curve.points.isEmpty {
                GroupBox("Saved levels") {
                    VStack(spacing: 6) {
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
                    .padding(6)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { engine.beginCalibration() }
        .onDisappear { engine.endCalibration() }
    }

    private var monitorBinding: Binding<Double> {
        Binding(
            get: { Double(engine.calibrationLevel) },
            set: { engine.previewCalibrationLevel(Int($0.rounded())) }
        )
    }

    private func percent(_ level: Double) -> String {
        "\(Int((level * 100).rounded()))%"
    }
}
