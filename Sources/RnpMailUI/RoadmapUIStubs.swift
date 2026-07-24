//
//  RoadmapUIStubs.swift
//  RnpMailUI
//
//  Lightweight placeholder for the mailbox-scan consent flow. The other
//  originally-stubbed views (KeyHealthView, ComposeRecipientDiagnosticsView,
//  RecoverySheetWizard) are now real implementations in their own files.
//

import SwiftUI

/// Placeholder for the mailbox-scan consent gate described in
/// TODO.roadmap/08-mailbox-key-scan.md. The engine-layer scan service
/// is gated on MailKit API investigation.
public struct MailboxScanConsentView: View {
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find keys for your contacts")
                .font(.title2.bold())
            Text("Engine-layer service pending (TODO.roadmap/08).")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
}
