# frozen_string_literal: true
#
# Homebrew Cask formula for RNP — OpenPGP for your Mac.
#
# Source of truth lives in this repo at packaging/homebrew-cask/rnp.rb.
# On each release, copy this file into a PR against Homebrew/homebrew-cask
# (https://github.com/Homebrew/homebrew-cask/blob/master/Casks/r/rnp.rb)
# with the version + sha256 updated.
#
# Local install for testing:
#   brew install --cask --no-quarantine packaging/homebrew-cask/rnp.rb
#
# Naming note: if the name "rnp" collides with an existing cask, change
# `cask "rnp"` below and submit under the new name (e.g. "rnp-mailapp").
# Check first at: https://github.com/Homebrew/homebrew-cask/tree/master/Casks/r

cask "rnp" do
  version "0.9.7"
  verified_version "0.9.7"

  # Signed + notarized DMG from the project's GitHub releases. Don't
  # change this URL pattern — `brew audit` requires it to be the
  # canonical upstream URL, not a mirror.
  url "https://github.com/rnpgp/rnp-mailapp-extension/releases/download/v#{version}/RNP-#{version}.dmg",
      verified: "github.com/rnpgp/rnp-mailapp-extension/"
  appcast "https://rnpgp.org/updates/appcast.xml"
  homepage "https://github.com/rnpgp/rnp-mailapp-extension"

  # SHA256 of the released DMG. Generate with:
  #   shasum -a 256 RNP-<version>.dmg
  # Update on every release. CI's release.yml emits this in SHA256SUMS.
  sha256 "6f03047850f3febbf966fd02bca19cbfe7d5a313959bbd9686406962e2bbda7e"

  name "RNP"
  desc "OpenPGP for your Mac — keys, files, and Mail"
  long_description <<~DESC
    RNP brings OpenPGP encryption to your Mac. Manage your keyring,
    encrypt and decrypt files, and add lock icons to encrypted and
    signed email in Apple Mail. Powered by librnp, Thunderbird's
    official end-to-end encryption engine.

    Bundle ID: com.rnpgp.RNPForMail
    App Group: group.com.rnpgp.RNPForMail
  DESC

  # Sparkle handles post-install updates; tell brew not to manage them.
  auto_updates true
  conflicts_with app: ["gnupg-pkcs11-scd"]

  app "RNP.app"

  # IMPORTANT: do NOT trash the user's keyring on uninstall. RNP stores
  # keys in ~/Library/Group Containers/<app-group>/.../keyring; deleting
  # them is data loss. Only zap preferences + caches.
  zap trash: [
    "~/Library/Caches/com.rnpgp.RNPForMail",
    "~/Library/Preferences/com.rnpgp.RNPForMail.plist",
    "~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.rnpgp.rnpformail.sfl*",
    "~/Library/Saved Application State/com.rnpgp.RNPForMail.savedState",
  ]
end
