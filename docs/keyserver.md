# Keyservers

RNP can publish your public key so correspondents can find it, and discover
other people's keys by email address or fingerprint. Three discovery
protocols are supported — VKS, HKPS, and WKD — all over HTTPS. The default
server is [keys.openpgp.org](https://keys.openpgp.org).

## Publishing your key (VKS upload)

Upload sends your armored public key to the configured VKS server
(`POST /vks/v1/upload` on keys.openpgp.org by default).

1. Export your armored public key from the key's detail view in the RNP app.
2. Upload it to the keyserver.
3. **Confirm by email.** keys.openpgp.org sends a confirmation message to each
   email address (user ID) in the key. The key becomes discoverable by email
   address only after you click the confirmation link — this proves you
   control the address. Unconfirmed keys can still be fetched by fingerprint.

Re-upload after any change to the key — subkey rotation, extended expiry, new
user ID, or revocation — so correspondents pick up the update.

## Discovering keys

| Method | Protocol | How it works |
|---|---|---|
| By email address | VKS | `GET /vks/v1/by-email/:email` against the configured server. |
| By fingerprint | VKS | `GET /vks/v1/by-fingerprint/:fingerprint` against the configured server. |
| Web Key Directory | WKD | The key is fetched from the recipient's own domain (`openpgpkey.example.com/...` in the advanced method, or `example.com/.well-known/openpgpkey/...` in the direct method). Works for domains whose operators publish keys this way — no central server involved. |
| HKPS lookup | HKP over HTTPS | `GET /pks/lookup` by fingerprint against a known HKPS server (keys.openpgp.org, keyserver.ubuntu.com). |

Fetched keys are imported into the shared keyring like any other import: a
key for a previously unknown address is recorded as *unverified* (TOFU), and
a key that changes an existing address raises a
[conflict](trust-model.md#key-change-warnings-and-conflicts) and blocks
encryption until verified.

## Revocation checks

When a key is revoked, the revocation is part of the key material itself.
Fetching the updated key from a keyserver imports the revocation, and RNP
stops offering that key for encryption. This is why re-fetching a
correspondent's key when something looks wrong is a good habit — and why you
should re-upload your own key after revoking it.

## Trust and privacy considerations

- **A keyserver is a directory, not an authority.** Any keyserver can return
  attacker-controlled keys, and anyone can upload a key claiming any email
  address. Email-confirmation (keys.openpgp.org) proves address control, not
  identity. Always verify fingerprints out-of-band before relying on a key —
  see [Trust model](trust-model.md).
- **Lookups are visible.** Queries reveal to the keyserver (and to network
  observers between you and it, though HTTPS limits this to metadata) which
  addresses or fingerprints you are interested in. WKD queries additionally
  reveal lookup interest to the recipient's domain operator.
- **Uploaded keys are public.** Whatever you upload — user IDs, photo IDs,
  expiry dates, subkeys — is world-visible and effectively permanent on
  public keyserver networks.
- **No other network traffic.** Key upload, discovery, and revocation-check
  queries are the only network requests the app makes. There is no telemetry;
  see [Telemetry and privacy policy](TELEMETRY.md).

## Errors you may see

| Error | Meaning | What to do |
|---|---|---|
| Not found | No key for that address/fingerprint on the server. | Check the address, try another protocol (WKD, HKPS), or ask the owner to publish. |
| Network error | Connectivity problem or DNS/TLS failure. | Check the connection and try again. |
| Server error (status code) | The keyserver rejected the request. | Retry later; for uploads, confirm the key is well-formed. |
| Malformed key | The downloaded data did not parse as an OpenPGP key. | Try another source; report persistent cases. |
| Invalid email / fingerprint | The query was not well-formed. | Fix the input. |

## See also

- [Usage — publishing and finding keys](usage.md#publishing-and-finding-keys)
- [Trust model](trust-model.md)
- [Telemetry and privacy policy](TELEMETRY.md)
