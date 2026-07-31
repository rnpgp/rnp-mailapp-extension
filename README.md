<p align="center"><img src="icon.png" width="120" alt="RNP for Mail"></p>

<h1 align="center">RNP for Mail</h1>

<p align="center">OpenPGP encryption and signing for macOS Mail — powered by <a href="https://github.com/rnpgp/rnp">librnp</a>.</p>

<p align="center">
  <a href="https://github.com/rnpgp/rnp-mailapp-extension/releases/latest"><strong>Download the latest release →</strong></a>
</p>

---

RNP for Mail is a native macOS Mail extension that brings OpenPGP
encryption and signing directly into Apple Mail. No separate app to
switch to, no browser plugin, no clunky proxy — your encrypted mail
just works inside the Mail you already use.

Built on [librnp](https://github.com/rnpgp/rnp) (the same engine
used by [Ribose's RNP CLI](https://github.com/rnpgp/rnp)) and
[swift-rnp](https://github.com/rnpgp/swift-rnp) (Swift bindings +
MailKit integration).

## Features

- **Sign and encrypt** outgoing mail from the compose window — Mail
  shows the lock icon automatically.
- **Decrypt and verify** incoming PGP/MIME mail inline — the message
  body renders as readable text, signatures show green/red in Mail's
  security banner.
- **Encrypt and decrypt files** — open **File → Encrypt & Decrypt Files…**
  (⌘⇧F) for a dedicated window. Drop any file to encrypt it for people
  in your keyring, or drop a `.pgp`/`.gpg`/`.asc` file to decrypt it.
  Same keyring Mail uses — no separate app, no GPG Suite.
- **Auto-discover keys via WKD** — when you compose to a recipient
  whose key isn't in your keyring, RNP fetches it automatically from
  Web Key Directory (WKD) or keys.openpgp.org. No manual keyserver
  lookup needed.
- **Import from existing keyrings** — auto-detects `~/.gnupg` and
  `~/.rnp`, lets you pick which keys to import. Read-only — never
  touches your source keyring.
- **Touch ID** — keyring passphrase stored in macOS Keychain with
  biometric protection. Unlock once per session; no password typing
  on every message.
- **Trust-on-first-use (TOFU)** — records the first key seen for each
  contact. If the key changes, RNP warns you before you encrypt to
  the new one.
- **Key lifecycle** — generate, rotate subkeys, extend expiry, revoke,
  archive, and migrate to a new primary key — all from the Tools hub.
- **Recovery** — export paper keys and revocation certificates for
  offline disaster recovery.
- **11 locales** — English, German, Spanish, French, Italian, Japanese,
  Korean, Portuguese, Russian, Simplified Chinese, Traditional Chinese.
- **macOS 14+** — runs on Sonoma and Sequoia. Universal binary (Apple
  Silicon + Intel).

## Install

### From the DMG (recommended)

1. Download the latest `RNP-X.Y.Z.dmg` from the
   [Releases page](https://github.com/rnpgp/rnp-mailapp-extension/releases).
2. Open the DMG and drag **RNP.app** to **Applications**.
3. Launch RNP once to complete onboarding (generate or import a key).
4. Open **Mail → Settings → General → Manage Plug-ins…** and tick
   **RNP OpenPGP**. Mail will restart.
5. Done. Encrypted mail now shows the lock icon; compose windows have
   sign/encrypt toggles.

### Verify the install

```bash
pluginkit -m -v -i com.rnpgp.RNPForMail.MailExtension
# Should show a line starting with "+" (enabled).
```

If the extension doesn't appear in Mail's plug-in list, see
[docs/mail-icon-diagnostic.md](docs/mail-icon-diagnostic.md).

## Build from source

```bash
git clone https://github.com/rnpgp/rnp-mailapp-extension.git
cd rnp-mailapp-extension
./scripts/build-rnp-framework.sh    # builds librnp xcframework (cached after first run)
open MailApp/RnpMail.xcodeproj
# In Xcode: select the "RNP" scheme, build (Cmd+B), run (Cmd+R).
```

Requires **Xcode 16.4** and **macOS 15** (Sequoia) for building.
The built app runs on macOS 14+ (Sonoma).

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   RNP.app (host)                     │
│  ┌──────────┐  ┌────────────┐  ┌─────────────────┐ │
│  │ Keyring  │  │ Tools Hub  │  │ Import from     │ │
│  │ Manager  │  │ (Health,   │  │ ~/.gnupg/~/.rnp │ │
│  │ (SwiftUI)│  │ Recovery)  │  │                 │ │
│  └────┬─────┘  └─────┬──────┘  └────────┬────────┘ │
│       │               │                   │          │
│  ┌────▼───────────────▼───────────────────▼────────┐│
│  │           swift-rnp (SPM package)               ││
│  │  ┌──────────────┐ ┌───────────┐ ┌────────────┐ ││
│  │  │ MailSecurity │ │ KeyServer │ │ TrustStore │ ││
│  │  │ Engine       │ │ Client    │ │ (TOFU)     │ ││
│  │  └──────┬───────┘ └─────┬─────┘ └────────────┘ ││
│  │         │               │                        ││
│  │  ┌──────▼───────────────▼────────────────────┐  ││
│  │  │            Rnp (FFI → librnp)              │  ││
│  │  └───────────────────────────────────────────┘  ││
│  └──────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────┐│
│  │          MailPlugin.appex (extension)            ││
│  │  MEMessageSecurityHandler → MailSecurityEngine   ││
│  └─────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
```

- **RNP.app** — the container app: keyring management, tools hub,
  onboarding. Runs as a normal macOS app.
- **MailPlugin.appex** — the Mail extension: intercepts incoming and
  outgoing mail, delegates to `MailSecurityEngine`.
- **swift-rnp** — the Swift library: everything crypto-related
  ([separate repo](https://github.com/rnpgp/swift-rnp)).

## Contributing

- **Translations**: see [TRANSLATING.md](TRANSLATING.md).
- **Bug reports**: include the diagnostics from
  [docs/mail-icon-diagnostic.md](docs/mail-icon-diagnostic.md).
- **Pull requests**: open against `main`. CI runs one job per PR
  (`ci.yml`) with build + UI tests + release dry-run.

## License

[BSD-2-Clause](LICENSE) (same as librnp). Bundled dependencies retain
their own licenses — see **About → Licenses** in the app or
[Vendor/SOURCES.md](Vendor/SOURCES.md).

## Credits

RNP for Mail is developed by [Ribose Inc.](https://www.ribose.com)
using the [librnp](https://github.com/rnpgp/rnp) OpenPGP library.
