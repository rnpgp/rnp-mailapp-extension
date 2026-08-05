# ADR-0007: Delete safety — three-step confirm + mandatory encrypted backup

Date: 2026-08-05
Status: Accepted

## Context

The user's absolute rule: NEVER delete user keys without confirming
multiple times. If a delete happens, RNP must save a recovery archive
so misclicks don't destroy data.

## Decision

Every key delete goes through:

1. **Three-step confirmation sheet** (replaces the old single-alert):
   - Step 1: warning
   - Step 2: type-the-fingerprint (single key) or type "DELETE" (bulk)
   - Step 3: pick backup path + passphrase, final warning

2. **Mandatory encrypted backup before delete**:
   - `KeyBackupArchive` produces an OpenPGP-encrypted `.pgp` file
   - Symmetric encryption with user-provided passphrase
   - Default location: `~/Documents/RNP Backups/`
   - Filename: `rnp-keys-deleted-YYYY-MM-DD-HHMMSS.pgp`

3. **Order of operations**:
   - Backup write first
   - If backup succeeds: delete from RNP's canonical store
   - If backup fails: error shown, key NOT deleted

4. **External sources never touched**:
   - Delete only removes from RNP's canonical store
   - `~/.gnupg/`, WKD, etc. are read-only `KeyImportSource`s — they
     have no delete method (see ADR-0006)

## Why symmetric encryption for the backup

The user is deleting the key. Encrypting the backup TO the key being
deleted would be circular — if they could decrypt the backup, they
wouldn't need it.

Symmetric encryption with a fresh passphrase the user types at delete
time is the right model:
- User has to remember (or write down) the passphrase
- Standard OpenPGP symmetric encryption
- Recoverable from any OpenPGP tool (`rnp decrypt`, `gpg -d`, etc.)

## Consequences

Positive:
- Misclicks don't destroy data — three confirmations + backup
- Wrong-key deletes impossible — step 2 requires typing the fingerprint
- Recovery is portable — standard PGP format, any tool can decrypt
- External keyrings are safe — protocol-level enforcement

Negative:
- More friction for legitimate deletes. Accepted — the alternative
  (single-click delete with no backup) is too dangerous for
  irreplacable data.
- Bulk delete intentionally not supported in UI. CLI handles bulk
  (with its own backup).

## References

- PR #191 (delete safety shipped)
- docs/sync-architecture.md (delete safety section)
- TODO.complete/31-getting-started-storage-choice.md
