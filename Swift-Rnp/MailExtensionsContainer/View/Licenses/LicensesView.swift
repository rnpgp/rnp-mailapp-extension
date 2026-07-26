//
//  LicensesView.swift
//  RNP
//
//  About → Licenses view rendering the vendored dependency summary and any
//  bundled license texts.
//

import SwiftUI

extension Notification.Name {
    /// Posted by the Help menu to present the Licenses sheet.
    static let showLicenses = Notification.Name("com.rnpgp.RNPForMail.showLicenses")
}

/// One bundled license entry. The `filename` is looked up in the
/// app bundle's `Resources/Licenses/` directory.
struct BundledLicense: Identifiable, Hashable {
    let id = UUID()
    let displayName: String
    let filename: String
}

/// Renders the dependency attribution and license texts bundled with the app.
struct LicensesView: View {
    /// Contents of `Vendor/SOURCES.md` bundled in the app.
    let sourcesMarkdown: String

    /// All bundled license texts, loaded lazily on first display.
    @State private var licenses: [BundledLicense: String] = [:]
    @State private var selectedLicense: BundledLicense?

    private static let bundledLicenses: [BundledLicense] = [
        BundledLicense(displayName: "rnp (BSD-2-Clause)", filename: "LICENSE.rnp.txt"),
        BundledLicense(displayName: "Botan (BSD-2-Clause)", filename: "LICENSE.botan.txt"),
        BundledLicense(displayName: "json-c (MIT)", filename: "LICENSE.json-c.txt"),
        BundledLicense(displayName: "sexpp (BSD-2-Clause)", filename: "LICENSE.sexpp.txt"),
        BundledLicense(displayName: "zlib (zlib)", filename: "LICENSE.zlib.txt"),
        BundledLicense(displayName: "bzip2 (BSD-style)", filename: "LICENSE.bzip2.txt"),
    ]

    var body: some View {
        HSplitView {
            // Left: summary + per-license list
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selectedLicense) {
                    Section(header: Text("Summary")) {
                        Text("Dependencies")
                            .font(.headline)
                            .accessibilityIdentifier("licenses.summary-row")
                    }
                    Section(header: Text("Full license texts")) {
                        ForEach(Self.bundledLicenses) { license in
                            Text(license.displayName)
                                .tag(license)
                                .accessibilityIdentifier("licenses.row.\(license.filename)")
                        }
                    }
                }
            }
            .frame(minWidth: 220)

            // Right: selected content
            ScrollView {
                Text(selectedContent)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("licenses.text")
            }
            .frame(minWidth: 360)
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { loadLicensesIfNeeded() }
    }

    private var selectedContent: String {
        if let selectedLicense, let text = licenses[selectedLicense] {
            return text
        }
        return sourcesMarkdown
    }

    private mutating func loadLicensesIfNeeded() {
        guard licenses.isEmpty else { return }
        for license in Self.bundledLicenses {
            if let url = Bundle.main.url(forResource: license.filename, withExtension: nil, subdirectory: "Licenses")
                ?? Bundle.main.url(forResource: license.filename, withExtension: nil),
               let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8),
               !text.isEmpty
            {
                licenses[license] = text
            }
        }
    }
}

extension LicensesView {
    /// Loads the dependency summary bundled with the app (copied from `Vendor/SOURCES.md`).
    static func loadSources() -> String {
        let candidates: [URL] = [
            Bundle.main.url(forResource: "SOURCES", withExtension: "md"),
            Bundle.main.url(forResource: "Vendor/SOURCES", withExtension: "md")
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
