//
//  SnapshotHarness.swift
//  RNP
//
//  Minimal snapshot testing harness built on SwiftUI's ImageRenderer.
//  No external SPM dep — uses ImageRenderer (macOS 13+) to render a
//  SwiftUI view to a PNG, then compares PNG bytes (or saves them as
//  a baseline on first run).
//
//  This isn't a full replacement for Pointfree's swift-snapshot-testing
//  (which has better diff tooling, view-image strategies, etc.), but
//  it covers the 80% case: catching unintended visual regressions on
//  the high-traffic sheets. See TODO.complete/23-snapshot-testing.md
//  for the migration path to the full library.
//

import AppKit
import SwiftUI
#if canImport(XCTest)
import XCTest

enum SnapshotHarness {

    /// Snapshot directory lives in the source tree so baselines are
    /// version-controlled and reviewers can see diffs in PRs.
    static var snapshotsDir: URL {
        URL(fileURLWithPath: #file).deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
    }

    /// Renders `view` at `size` and compares against the baseline. On
    /// first run (no baseline), writes the baseline and fails (so CI
    /// flags the new file).
    @MainActor
    static func assertSnapshot(
        of view: some View,
        named name: String,
        size: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        let png = try render(view: view, size: size)
        let baselineURL = snapshotsDir.appendingPathComponent("\(name).png")

        guard FileManager.default.fileExists(atPath: baselineURL.path) else {
            try png.write(to: baselineURL)
            XCTFail(
                "No baseline for '\(name)'. Wrote one to \(baselineURL.path). Re-run to verify.",
                file: file, line: line
            )
            return
        }

        let baseline = try Data(contentsOf: baselineURL)
        if baseline != png {
            let failedURL = snapshotsDir.appendingPathComponent("\(name).failed.png")
            try png.write(to: failedURL)
            XCTFail(
                "Snapshot '\(name)' changed. Diff written to \(failedURL.path). "
                + "If intentional, replace the baseline at \(baselineURL.path).",
                file: file, line: line
            )
        }
    }

    @MainActor
    private static func render(view: some View, size: CGSize) throws -> Data {
        let framed = view.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2.0  // Match @2x retina
        renderer.proposedSize = .init(width: size.width, height: size.height)
        guard let image = renderer.nsImage else {
            throw NSError(domain: "SnapshotHarness", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "ImageRenderer produced nil for view"
            ])
        }
        guard let tiff = image.tiffRepresentation as Data?,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SnapshotHarness", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode PNG"
            ])
        }
        return png
    }
}

#endif  // canImport(XCTest)
