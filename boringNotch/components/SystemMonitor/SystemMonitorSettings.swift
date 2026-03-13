//
//  SystemMonitorSettings.swift
//  boringNotch
//
//  Settings panel for the System Monitor feature.
//

import Defaults
import SwiftUI

struct SystemMonitorSettings: View {
    @Default(.enableSystemMonitor) var enabled
    @Default(.sysMonSlot1) var slot1
    @Default(.sysMonSlot2) var slot2
    @Default(.sysMonSlot3) var slot3

    private var availableWidgets: [SystemMonitorWidgetKind] {
        SystemMonitorWidgetKind.allCases.filter { $0 != .batteryHealth }
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableSystemMonitor) {
                    Text("Enable System Monitor")
                }
            }

            Section {
                Picker("Slot 1", selection: $slot1) {
                    ForEach(availableWidgets, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }

                Picker("Slot 2", selection: $slot2) {
                    ForEach(availableWidgets, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }

                Picker("Slot 3", selection: $slot3) {
                    ForEach(availableWidgets, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
            } header: {
                Text("Widget Slots")
            }
        }
        .formStyle(.grouped)
    }
}
