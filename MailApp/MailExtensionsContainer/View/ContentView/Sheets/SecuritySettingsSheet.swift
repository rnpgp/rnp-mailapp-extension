//
//  SecuritySettingsSheet.swift
//  RNP
//
//  Security settings sheet: the opt-in per-operation verification
//  toggle ("require Touch ID for each sign/encrypt/decrypt operation")
//  and its session timeout. Both are stored in the app-group defaults,
//  so the Mail extension picks changes up without a restart.
//  Extracted from ContentView in TODO.complete/22.
//

import RnpMailUI
import SwiftUI

struct SecuritySettingsSheet: View {
    @ObservedObject var model: ContentViewModel
    @Environment(\.dismiss) private var dismiss

    private static let timeoutPresets: [TimeInterval] = [15, 30, 60, 300]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("security.title")
                .font(.headline)
            Text("security.message")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: Binding(
                get: { model.requireTouchIDPerOperation },
                set: { model.requireTouchIDPerOperation = $0 }
            )) {
                Text("security.requireTouchID")
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("security.requireTouchID")
            if model.requireTouchIDPerOperation {
                Picker(selection: Binding(
                    get: { model.operationVerificationTimeout },
                    set: { model.operationVerificationTimeout = $0 }
                )) {
                    ForEach(Self.timeoutPresets, id: \.self) { seconds in
                        Text(timeoutLabel(for: seconds)).tag(seconds)
                    }
                } label: {
                    Text("security.timeout")
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("security.timeout")
            }
            HStack {
                Spacer()
                Button("button.done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("security.done")
            }
        }
        .padding(20)
        .frame(width: 460)
        .accessibilityIdentifier("security")
    }

    private func timeoutLabel(for seconds: TimeInterval) -> String {
        switch seconds {
        case 15:  return "security.timeout.15".localized
        case 60:  return "security.timeout.60".localized
        case 300: return "security.timeout.300".localized
        default:  return "security.timeout.30".localized
        }
    }
}
