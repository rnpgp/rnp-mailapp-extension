//
//  BannerView.swift
//  RNP
//
//  Tinted banner used for trust-conflict and expiry warnings, and as
//  the base for the import-error banner. Extracted from ContentView
//  in TODO.complete/22.
//

import RnpMailUI
import SwiftUI

struct BannerView: View {
    let icon: String
    let tint: Color
    let text: String
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil
    var actionIdentifier: String? = nil

    var body: some View {
        HStack(spacing: RnpSpacing.xs) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                if let actionIdentifier {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier(actionIdentifier)
                } else {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, RnpSpacing.sm)
        .padding(.vertical, RnpSpacing.xs)
        .background(
            tint.opacity(0.1),
            in: RoundedRectangle(cornerRadius: RnpRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RnpRadius.card, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}
