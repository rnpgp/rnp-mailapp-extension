//
//  FileToolsView.swift
//  RNP for Mail
//
//  Standalone window for encrypting and decrypting files with the
//  shared OpenPGP keyring. Branding: this is part of "RNP for Mail" —
//  the product — not a separate app. Window title and copy use that
//  name consistently.
//

import AppKit
import MailSecurityEngine
import RnpMailUI
import SwiftUI
import UniformTypeIdentifiers

/// File encrypt / decrypt workspace. Opens as its own WindowGroup so
/// the user can keep the key manager and file tools side by side.
struct FileToolsView: View {
    @ObservedObject var model: ContentViewModel
    @StateObject private var tools = FileToolsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear { tools.attach(model: model) }
        .alert(
            "error.operation.title",
            isPresented: Binding(
                get: { tools.errorMessage != nil },
                set: { if !$0 { tools.errorMessage = nil } }
            )
        ) {
            Button("button.ok") { tools.errorMessage = nil }
        } message: {
            Text(tools.errorMessage ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: RnpSpacing.md) {
            Image(systemName: "lock.doc")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("fileTools.title")
                    .font(.title2.weight(.semibold))
                Text("fileTools.subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, RnpSpacing.xl)
        .padding(.vertical, RnpSpacing.md)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch tools.mode {
        case .idle:
            dropZone
        case .encrypt(let file):
            encryptPanel(file: file)
        case .decrypt(let file, let result):
            decryptPanel(file: file, result: result)
        case .working:
            VStack(spacing: RnpSpacing.md) {
                ProgressView()
                Text("fileTools.working")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var dropZone: some View {
        VStack(spacing: RnpSpacing.lg) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: RnpRadius.panel, style: .continuous)
                    .strokeBorder(
                        tools.isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                        style: StrokeStyle(lineWidth: tools.isDropTargeted ? 2 : 1, dash: [6, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: RnpRadius.panel, style: .continuous)
                            .fill(tools.isDropTargeted
                                  ? Color.accentColor.opacity(0.06)
                                  : Color(nsColor: .controlBackgroundColor))
                    )
                VStack(spacing: RnpSpacing.sm) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 36, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                    Text("fileTools.dropPrompt")
                        .font(.title3.weight(.medium))
                    Text("fileTools.dropHint")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Button("fileTools.browse") {
                        tools.browse()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.top, RnpSpacing.xs)
                    .accessibilityIdentifier("filetools.browse")
                }
                .padding(RnpSpacing.xxl)
            }
            .frame(maxWidth: 480, maxHeight: 280)
            .onDrop(of: [.fileURL], isTargeted: $tools.isDropTargeted) { providers in
                tools.handleDrop(providers)
            }
            Spacer()
        }
        .padding(RnpSpacing.xl)
    }

    private func encryptPanel(file: FileToolsViewModel.LoadedFile) -> some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            fileBanner(file: file, kind: .plain)
            Text("fileTools.encryptTo")
                .font(.headline)
            recipientList
            HStack {
                Button("button.cancel") { tools.reset() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("filetools.encrypt.cancel")
                Spacer()
                Button("fileTools.encryptButton") {
                    tools.encrypt()
                }
                .buttonStyle(.borderedProminent)
                .disabled(tools.selectedRecipientIDs.isEmpty || tools.isWorking)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("filetools.encrypt.run")
            }
        }
        .padding(RnpSpacing.xl)
    }

    private func decryptPanel(file: FileToolsViewModel.LoadedFile, result: FileToolsViewModel.DecryptResult?) -> some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            fileBanner(file: file, kind: .encrypted)
            if let result {
                resultBanner(result)
                HStack {
                    Button("button.cancel") { tools.reset() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("fileTools.saveDecrypted") {
                        tools.saveDecrypted(result)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("filetools.decrypt.save")
                }
            } else {
                HStack {
                    Button("button.cancel") { tools.reset() }
                    Spacer()
                    Button("fileTools.decryptButton") {
                        tools.decrypt()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("filetools.decrypt.run")
                }
            }
        }
        .padding(RnpSpacing.xl)
    }

    private enum FileKind { case plain, encrypted }

    private func fileBanner(file: FileToolsViewModel.LoadedFile, kind: FileKind) -> some View {
        HStack(spacing: RnpSpacing.md) {
            Image(systemName: kind == .encrypted ? "lock.doc.fill" : "doc")
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                tools.reset()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("filetools.clear")
        }
        .padding(RnpSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: RnpRadius.panel, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: RnpRadius.panel, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func resultBanner(_ result: FileToolsViewModel.DecryptResult) -> some View {
        HStack(spacing: RnpSpacing.sm) {
            Image(systemName: result.signatureValid == true
                  ? "checkmark.seal.fill"
                  : (result.signatureValid == false ? "xmark.seal.fill" : "lock.open.fill"))
                .foregroundStyle(result.signatureValid == true
                                 ? Color.green
                                 : (result.signatureValid == false ? Color.red : Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(result.statusTitle)
                    .font(.callout.weight(.medium))
                Text(result.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(RnpSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: RnpRadius.panel, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    private var recipientList: some View {
        let candidates = model.manager.keys
        return ScrollView {
            VStack(alignment: .leading, spacing: RnpSpacing.xxs) {
                if candidates.isEmpty {
                    Text("fileTools.noKeys")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(candidates) { key in
                        Toggle(isOn: Binding(
                            get: { tools.selectedRecipientIDs.contains(key.fingerprint) },
                            set: { on in
                                if on {
                                    tools.selectedRecipientIDs.insert(key.fingerprint)
                                } else {
                                    tools.selectedRecipientIDs.remove(key.fingerprint)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(key.primaryUserID)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(key.fingerprint.groupedFingerprintBlocks)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 2)
                        .accessibilityIdentifier("filetools.recipient.\(key.fingerprint.prefix(8))")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 220)
        .padding(RnpSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: RnpRadius.panel, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

// MARK: - View model

@MainActor
final class FileToolsViewModel: ObservableObject {
    enum Mode {
        case idle
        case encrypt(LoadedFile)
        case decrypt(LoadedFile, DecryptResult?)
        case working
    }

    struct LoadedFile {
        let url: URL
        let data: Data
    }

    struct DecryptResult {
        let plaintext: Data
        /// nil = no signature found; true/false = verified/failed
        let signatureValid: Bool?
        let suggestedFilename: String

        var statusTitle: String {
            if signatureValid == true {
                return "fileTools.result.decryptedAndVerified".localized
            } else if signatureValid == false {
                return "fileTools.result.decryptedBadSignature".localized
            } else {
                return "fileTools.result.decrypted".localized
            }
        }

        var statusDetail: String {
            ByteCountFormatter.string(fromByteCount: Int64(plaintext.count), countStyle: .file)
        }
    }

    @Published var mode: Mode = .idle
    @Published var isDropTargeted = false
    @Published var selectedRecipientIDs: Set<String> = []
    @Published var errorMessage: String?
    @Published var isWorking = false

    private weak var model: ContentViewModel?

    func attach(model: ContentViewModel) {
        self.model = model
    }

    func reset() {
        mode = .idle
        selectedRecipientIDs = []
        isWorking = false
        errorMessage = nil
    }

    func browse() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "fileTools.browseMessage".localized
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                self.load(url: url)
            }
        }
        return true
    }

    private func load(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let file = LoadedFile(url: url, data: data)
            if Self.looksEncrypted(data: data, filename: url.lastPathComponent) {
                mode = .decrypt(file, nil)
            } else {
                // Pre-select all public keys of contacts + own keys.
                if let model {
                    selectedRecipientIDs = Set(model.manager.keys.map(\.fingerprint))
                }
                mode = .encrypt(file)
            }
        } catch {
            errorMessage = FileToolsError.readFailed(url.path).errorDescription
        }
    }

    func encrypt() {
        guard case .encrypt(let file) = mode, let model else { return }
        isWorking = true
        mode = .working
        let recipients = Array(selectedRecipientIDs)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let ciphertext = try model.manager.encryptFile(file.data, for: recipients)
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.saveEncrypted(ciphertext, original: file.url)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.mode = .encrypt(file)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func decrypt() {
        guard case .decrypt(let file, _) = mode, let model else { return }
        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Try decrypt first; if that fails, try verify (cleartext-signed).
                let plaintext: Data
                var signatureValid: Bool? = nil
                if let decrypted = try? model.manager.decryptFile(file.data) {
                    plaintext = decrypted
                } else {
                    let verified = try model.manager.verifyFile(file.data)
                    plaintext = verified.payload
                    signatureValid = verified.valid
                }
                let suggested = Self.suggestDecryptedFilename(from: file.url.lastPathComponent)
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.mode = .decrypt(file, DecryptResult(
                        plaintext: plaintext,
                        signatureValid: signatureValid,
                        suggestedFilename: suggested
                    ))
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func saveDecrypted(_ result: DecryptResult) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = result.suggestedFilename
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try result.plaintext.write(to: url, options: .atomic)
            reset()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            errorMessage = FileToolsError.writeFailed(url.path).errorDescription
        }
    }

    private func saveEncrypted(_ ciphertext: Data, original: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = original.lastPathComponent + ".pgp"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            // User cancelled — go back to encrypt panel with the same file.
            if let data = try? Data(contentsOf: original) {
                mode = .encrypt(LoadedFile(url: original, data: data))
            } else {
                reset()
            }
            return
        }
        do {
            try ciphertext.write(to: url, options: .atomic)
            reset()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            errorMessage = FileToolsError.writeFailed(url.path).errorDescription
            if let data = try? Data(contentsOf: original) {
                mode = .encrypt(LoadedFile(url: original, data: data))
            }
        }
    }

    private static func looksEncrypted(data: Data, filename: String) -> Bool {
        let lower = filename.lowercased()
        if lower.hasSuffix(".pgp") || lower.hasSuffix(".gpg") || lower.hasSuffix(".asc") {
            return true
        }
        if let prefix = String(data: data.prefix(40), encoding: .utf8) {
            if prefix.contains("BEGIN PGP MESSAGE") || prefix.contains("BEGIN PGP SIGNED MESSAGE") {
                return true
            }
        }
        return false
    }

    private static func suggestDecryptedFilename(from filename: String) -> String {
        let lower = filename.lowercased()
        for ext in [".pgp", ".gpg", ".asc"] {
            if lower.hasSuffix(ext) {
                return String(filename.dropLast(ext.count))
            }
        }
        return filename + ".decrypted"
    }
}
