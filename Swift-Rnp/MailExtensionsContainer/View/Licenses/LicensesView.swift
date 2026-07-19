//
//  LicensesView.swift
//  Ribose container
//
//  About → Licenses view rendering the vendored dependency summary and any
//  bundled license texts.
//

import SwiftUI

extension Notification.Name {
    /// Posted by the Help menu to present the Licenses sheet.
    static let showLicenses = Notification.Name("com.rnpgp.RnpMail.showLicenses")
}

/// Renders the dependency attribution and license texts bundled with the app.
struct LicensesView: View {
    /// Contents of `Vendor/SOURCES.md` bundled in the app.
    let sourcesMarkdown: String

    var body: some View {
        ScrollView {
            Text(sourcesMarkdown)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("licenses.text")
        }
        .frame(minWidth: 520, minHeight: 400)
    }
}

extension LicensesView {
    /// Loads the dependency summary shipped at `Vendor/SOURCES.md`.
    static func loadSources() -> String {
        let candidates: [URL] = [
            Bundle.main.url(forResource: "SOURCES", withExtension: "md"),
            Bundle.main.url(forResource: "Vendor/SOURCES", withExtension: "md"),
            URL(fileURLWithPath: "Vendor/SOURCES.md")
        ].compactMap { $0 }

        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8),
               !text.isEmpty {
                return text
            }
        }

        return "License information is not available."
    }
}

#if DEBUG
struct LicensesView_Previews: PreviewProvider {
    static var previews: some View {
        LicensesView(sourcesMarkdown: LicensesView.loadSources())
    }
}
#endif
