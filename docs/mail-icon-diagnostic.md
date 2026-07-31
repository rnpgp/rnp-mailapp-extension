# Mail extension: no security icons? — diagnostic checklist

The Mail extension shows two indicators on incoming messages:

- 🔒 **Encrypted** — when the message has an OpenPGP-encrypted MIME part.
- ✅ **Signed** — when the message has an OpenPGP-signed MIME part, with the signer's identity and verification state.

Both are surfaced automatically by `MessageSecurityHandler.decodedMessage(...)` returning an `MEMessageSecurityInformation`. If the icons are not appearing, walk this list in order:

## 1. Is the extension actually loaded by Mail?

```bash
pluginkit -m -v -i com.rnpgp.RNPForMail.MailExtension
```

Look at the line. If it begins with `+`, the extension is enabled. If it begins with `-` or `?`, it's disabled or pending.

**Force-enable:**

```bash
pluginkit -e use -i com.rnpgp.RNPForMail.MailExtension
```

Or in Mail: **Settings → General → Manage Plug-ins…** → tick **RNP OpenPGP** → Mail prompts to restart.

## 2. Is Mail actually invoking our handler?

After enabling and restarting Mail, open a PGP-signed or PGP-encrypted message and watch Console:

```bash
log stream --predicate 'process == "MailPlugin" OR process == "Mail" AND eventMessage CONTAINS "RNP"' --info
```

You should see log lines from `MessageSecurityHandler.decodedMessage(...)` fire when you open a message. If nothing logs, Mail is not invoking the extension — usually means the bundle failed to load (check Console for `pkd: rejecting` lines, which indicate a code-signing or entitlement problem — see below).

## 3. Is the message actually PGP-signed/encrypted?

The icons only appear for actual PGP/MIME messages. The headers should include one of:

- `Content-Type: multipart/encrypted; protocol="application/pgp-encrypted"` (RFC 3156 encryption)
- `Content-Type: multipart/signed; protocol="application/pgp-signature"` (RFC 3156 signing)
- `Content-Type: application/pgp` (inline PGP)

Test with a known-good message: send yourself mail from `gpg --sign --armor --textmode` and read it in Mail.

## 4. Is the extension bundle code-signed correctly?

`pkd` (the PlugInKit daemon) silently rejects malformed extensions. The error in Console is usually:

```
pkd: rejecting; Ignoring mis-configured plugin at [.../MailPlugin.appex]: plug-ins must be sandboxed
```

or:

```
pkd: could not create extension point record for <private>: Error Domain=NSOSStatusErrorDomain Code=-10814
```

Verify:

```bash
# Sandbox entitlement must be present
codesign -d --entitlements - /Applications/RNP.app/Contents/PlugIns/MailPlugin.appex | grep app-sandbox
# → com.apple.security.app-sandbox

# Signature valid
codesign --verify --deep --strict --verbose=2 /Applications/RNP.app/Contents/PlugIns/MailPlugin.appex
# → valid on disk / satisfies its Designated Requirement

# Runtime version compatible with system (macOS 14.x requires ≤ 14.x)
codesign -d --verbose=4 /Applications/RNP.app/Contents/PlugIns/MailPlugin.appex | grep Runtime
# → Runtime Version=14.0.0  (NOT 15.x on a macOS 14.x system)
```

If any of these fail, you have an outdated or mis-built install. Reinstall from the latest DMG at <https://github.com/rnpgp/rnp-mailapp-extension/releases>.

## 5. Is Mail caching stale decode results?

After enabling or updating the extension, Mail may have cached the previous (extension-disabled) decode result for already-open messages. **Restart Mail** with `Cmd-Q` (not just close window), then re-open the message.

For stubborn cases:

```bash
killall Mail
# Reopen Mail, re-open the message
```

## 6. Are there multiple Mail extensions conflicting?

Other OpenPGP Mail extensions (GPGMail, etc.) can claim the same MIME types first. List them:

```bash
pluginkit -m -p com.apple.email-extension
```

If another extension is `+` enabled, disable it via **Mail → Settings → Manage Plug-ins…** and restart Mail.

## When to file a bug

If you've walked all six steps above and icons still don't appear for a known PGP/MIME message, file an issue with:

- macOS version (`sw_vers`)
- Mail version (`defaults read /System/Applications/Mail.app/Contents/Info CFBundleShortVersionString`)
- `pluginkit -m -v -i com.rnpgp.RNPForMail.MailExtension` output
- Console output from `log stream --predicate 'process == "MailPlugin"' --info` while opening the message
- The raw message source (`View → Message → Raw Source`)
