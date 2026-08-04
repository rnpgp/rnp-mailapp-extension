//
//  OutputFormat.swift
//  rnp-cli
//
//  --output flag for `list` and `verify`: human (default), json,
//  porcelain. Mirrors the GnuPG --with-colons pattern for scripts.
//

import ArgumentParser
import Foundation

enum OutputFormat: String, EnumerableFlag, CaseIterable {
    case human
    case json
    case porcelain
}

/// Minimal JSON encoder for CLI output. Avoids pulling in Codable
/// boilerplate for one-line value types.
enum CLIJSON {
    static func encode(_ pairs: [(String, String)]) -> String {
        let fields = pairs.map { "\"\($0.0)\":\"\(escape($0.1))\"" }.joined(separator: ",")
        return "{\(fields)}"
    }
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
    }
}
