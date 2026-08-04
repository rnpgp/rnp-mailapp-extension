# frozen_string_literal: true
#
# Homebrew formula for rnp CLI (NOT the GUI app — that's the Cask in
# packaging/homebrew-cask/rnp.rb). Builds the Swift executable from
# the rnp-cli/ subdirectory.
#
# Local install for testing:
#   brew install --build-from-source packaging/homebrew-formula/rnp.rb

class Rnp < Formula
  desc "OpenPGP CLI for macOS — keys, files, and Mail"
  homepage "https://github.com/rnpgp/rnp-mailapp-extension"
  url "https://github.com/rnpgp/rnp-mailapp-extension.git",
      tag:      "v0.9.7",
      revision: "TBD-on-next-release"

  # Bump on each release. CI should compute the SHA from the release tag.
  sha256 "TBD"

  head "https://github.com/rnpgp/rnp-mailapp-extension.git", branch: "main"

  depends_on xcode: ["16.4", :build]
  depends_on :macos

  def install
    cd "rnp-cli" do
      # Release build; the binary is statically linked against Swift's
      # runtime by toolchain default.
      system "swift", "build", "-c", "release", "--disable-sandbox"
      bin.install ".build/release/rnp"
    end

    # Man page (when it exists)
    # man1.install "rnp-cli/man/rnp.1"
  end

  test do
    assert_match "rnp", shell_output("#{bin}/rnp --version")
  end
end
