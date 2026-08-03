//
//  FileToolsView.swift
//  RNP
//
//  Second window of the RNP app: encrypt and decrypt any file with
//  the shared OpenPGP keyring. Part of RNP — the Mail extension is
//  "RNP for Mail", this is the file-side of the same product.
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
        case .sign(let file):
            signPanel(file: file)
        case .verify(let file, let result):
            verifyPanel(file: file, result: result)
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

    private func signPanel(file: FileToolsViewModel.LoadedFile) -> some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            fileBanner(file: file, kind: .plain)
            Text("fileTools.signWith")
                .font(.headline)
            signingKeyPicker
            Toggle(isOn: $tools.signDetached) {
                Text("fileTools.signDetached")
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("filetools.sign.detached")
            HStack {
                Button("button.cancel") { tools.reset() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("filetools.sign.cancel")
                Spacer()
                Button("fileTools.signButton") {
                    tools.sign()
                }
                .buttonStyle(.borderedProminent)
                .disabled(tools.signingKeyFingerprint == nil || tools.isWorking)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("filetools.sign.run")
            }
        }
        .padding(RnpSpacing.xl)
    }

    private func verifyPanel(file: FileToolsViewModel.LoadedFile, result: FileToolsViewModel.VerifyResult?) -> some View {
        VStack(alignment: .leading, spacing: RnpSpacing.md) {
            fileBanner(file: file, kind: .signed)
            if let result {
                verificationBanner(result)
                if case .verification(_, let payload?) = result.kind {
                    HStack {
                        Text("fileTools.verify.payloadSize")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(payload.count), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("fileTools.saveVerifiedPayload") {
                            tools.saveVerifiedPayload(payload, original: file.url)
                        }
                        .accessibilityIdentifier("filetools.verify.save")
                    }
                }
                HStack {
                    Button("button.cancel") { tools.reset() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("button.done") { tools.reset() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("filetools.verify.done")
                }
            } else {
                HStack {
                    Button("button.cancel") { tools.reset() }
                    Spacer()
                    Button("fileTools.verifyButton") {
                        tools.verify()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("filetools.verify.run")
                }
            }
        }
        .padding(RnpSpacing.xl)
    }

    private var signingKeyPicker: some View {
        let signers = model.manager.keys.filter { $0.hasSecret }
        return ScrollView {
            signingKeyList(signers: signers)
        }
        .frame(maxHeight: 180)
        .padding(RnpSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: RnpRadius.panel, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func signingKeyList(signers: [KeyInfo]) -> some View {
        VStack(alignment: .leading, spacing: RnpSpacing.xxs) {
            if signers.isEmpty {
                Text("fileTools.noSigningKey")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                Picker(selection: Binding(
                    get: { tools.signingKeyFingerprint ?? signers.first?.fingerprint ?? "" },
                    set: { tools.signingKeyFingerprint = $0 }
                )) {
                    ForEach(signers) { key in
                        signingKeyLabel(key: key).tag(key.fingerprint)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func signingKeyLabel(key: KeyInfo) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(key.primaryUserID)
                .font(.body)
                .lineLimit(1)
            Text(key.fingerprint.groupedFingerprintBlocks)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func verificationBanner(_ result: FileToolsViewModel.VerifyResult) -> some View {
        let isValid = result.verification.isValid
        let signerLabel: String = {
            if let fpr = result.verification.signerFingerprint {
                let known = model.manager.keys.first { $0.fingerprint == fpr }?.primaryUserID
                return known ?? String(fpr.prefix(16))
            }
            return "fileTools.verify.unknownSigner".localized
        }()
        return HStack(spacing: RnpSpacing.sm) {
            Image(systemName: isValid ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isValid ? Color.green : Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(isValid ? "fileTools.verify.valid" : "fileTools.verify.invalid")
                    .font(.callout.weight(.medium))
                Text(signerLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(RnpSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: RnpRadius.panel, style: .continuous)
                .fill((isValid ? Color.green : Color.red).opacity(0.08))
        )
    }

    private enum FileKind { case plain, encrypted, signed }

    private func fileBanner(file: FileToolsViewModel.LoadedFile, kind: FileKind) -> some View {
        HStack(spacing: RnpSpacing.md) {
            Image(systemName: kind == .encrypted ? "lock.doc.fill" : (kind == .signed ? "signature" : "doc"))
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
        case sign(LoadedFile)
        case verify(LoadedFile, VerifyResult?)
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

    /// Wraps the engine's `FileSecurityResult` for the verify panel. The
    /// `.verification` case carries the signature check; `.plaintext`
    /// covers the decrypt-with-signature path; other kinds aren't
    /// reachable from this panel.
    struct VerifyResult {
        let kind: FileSecurityResult.Kind
        var verification: SignatureVerification {
            if case .verification(let v, _) = kind { return v }
            return SignatureVerification(isValid: false, signerFingerprint: nil, signerUserID: nil, signedAt: nil)
        }
    }

    @Published var mode: Mode = .idle
    @Published var isDropTargeted = false
    @Published var selectedRecipientIDs: Set<String> = []
    @Published var signingKeyFingerprint: String?
    @Published var signDetached = false
    @Published var errorMessage: String?
    @Published var isWorking = false

    private weak var model: ContentViewModel?

    func attach(model: ContentViewModel) {
        self.model = model
        // Default the signer picker to the user's first secret key.
        if signingKeyFingerprint == nil {
            signingKeyFingerprint = model.manager.keys.first(where: { $0.hasSecret })?.fingerprint
        }
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
            switch Self.classify(data: data, filename: url.lastPathComponent) {
            case .encrypted:
                mode = .decrypt(file, nil)
            case .signed, .detachedSignature:
                mode = .verify(file, nil)
            case .plain:
                if let model {
                    selectedRecipientIDs = Set(model.manager.keys.map(\.fingerprint))
                    signingKeyFingerprint = model.manager.keys.first(where: { $0.hasSecret })?.fingerprint
                }
                mode = .encrypt(file)
            }
        } catch {
            errorMessage = FileToolsError.readFailed(url.path).errorDescription
        }
    }

    func sign() {
        guard case .sign(let file) = mode, let model else { return }
        guard let fpr = signingKeyFingerprint else {
            errorMessage = "error.fileSecurity.noSigningKeyConfigured".localized
            return
        }
        isWorking = true
        mode = .working
        let detached = signDetached
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let signed = detached
                    ? try model.manager.signFileDetached(file.data, withKeyFingerprint: fpr)
                    : try model.manager.signFile(file.data, withKeyFingerprint: fpr)
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.saveSigned(signed, original: file.url, detached: detached)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.mode = .sign(file)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func verify() {
        guard case .verify(let file, _) = mode, let model else { return }
        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result: FileSecurityResult
                if Self.looksLikeDetachedSignature(data: file.data) {
                    // Detached signature file dropped alone: we have the
                    // signature but not the payload. Ask the user.
                    DispatchQueue.main.async {
                        self.isWorking = false
                        self.promptForDetachedPayload(signature: file)
                    }
                    return
                }
                let verified = try model.manager.verifyFile(file.data)
                result = .plaintext(verified.payload, signatureValidity: verified.valid ? true : false)
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.mode = .verify(file, VerifyResult(kind: result.kind))
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Detached-signature workflow: user dropped `signature`, now we
    /// ask for the matching payload file and verify the pair.
    private func promptForDetachedPayload(signature: LoadedFile) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "fileTools.verify.pickPayload".localized
        guard panel.runModal() == .OK, let payloadURL = panel.url,
              let payloadData = try? Data(contentsOf: payloadURL) else {
            mode = .verify(signature, nil)
            return
        }
        guard let model else { return }
        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let v = try model.manager.verifyDetachedSignature(signature.data, forPayload: payloadData)
                let result = FileSecurityResult.verification(v, payload: payloadData)
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.mode = .verify(signature, VerifyResult(kind: result.kind))
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func saveVerifiedPayload(_ payload: Data, original: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = original.lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try payload.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            errorMessage = FileToolsError.writeFailed(url.path).errorDescription
        }
    }

    private func saveSigned(_ signed: Data, original: URL, detached: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = detached
            ? original.lastPathComponent + ".sig"
            : original.lastPathComponent + ".pgp"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            if let data = try? Data(contentsOf: original) {
                mode = .sign(LoadedFile(url: original, data: data))
            } else {
                reset()
            }
            return
        }
        do {
            try signed.write(to: url, options: .atomic)
            reset()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            errorMessage = FileToolsError.writeFailed(url.path).errorDescription
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

    private enum FileClass {
        case plain
        case encrypted
        case signed
        case detachedSignature
    }

    /// Classifies a dropped file by extension + content sniff. Each
    /// branch is the minimal signal needed — order matters: detached
    /// `.sig` before inline `.pgp`, and content sniff only when the
    /// extension doesn't already tell us.
    private static func classify(data: Data, filename: String) -> FileClass {
        let lower = filename.lowercased()
        if lower.hasSuffix(".sig") || lower.hasSuffix(".asc") && !looksLikeInlineMessage(data: data) {
            return .detachedSignature
        }
        if lower.hasSuffix(".pgp") || lower.hasSuffix(".gpg") {
            return .encrypted
        }
        if lower.hasSuffix(".asc") {
            // .asc can be either; we already handled detached above.
            return .encrypted
        }
        guard let prefix = String(data: data.prefix(64), encoding: .utf8) else { return .plain }
        if prefix.contains("BEGIN PGP MESSAGE") { return .encrypted }
        if prefix.contains("BEGIN PGP SIGNED MESSAGE") { return .signed }
        if prefix.contains("BEGIN PGP SIGNATURE") { return .detachedSignature }
        return .plain
    }

    private static func looksLikeInlineMessage(data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(64), encoding: .utf8) else { return false }
        return prefix.contains("BEGIN PGP MESSAGE") || prefix.contains("BEGIN PGP SIGNED MESSAGE")
    }

    private static func looksLikeDetachedSignature(data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(64), encoding: .utf8) else { return false }
        return prefix.contains("BEGIN PGP SIGNATURE") && !prefix.contains("BEGIN PGP SIGNED MESSAGE")
    }

    private static func looksEncrypted(data: Data, filename: String) -> Bool {
        switch classify(data: data, filename: filename) {
        case .encrypted, .signed, .detachedSignature: return true
        case .plain: return false
        }
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
