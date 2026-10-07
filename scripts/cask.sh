#!/usr/bin/env bash
# Prints the Homebrew cask for an Otter release (T13), for the tap at
# github.com/elizabeth-ling/homebrew-tap (Casks/otter.rb):
#
#   scripts/cask.sh 0.1.1 <sha256 of Otter-0.1.1.dmg> > ../homebrew-tap/Casks/otter.rb
#
# The release workflow runs this after publishing the GitHub release.
set -euo pipefail

VERSION="${1:?usage: scripts/cask.sh <version> <sha256>}"
SHA256="${2:?usage: scripts/cask.sh <version> <sha256>}"

cat <<CASK
cask "otter" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/elizabeth-ling/otter/releases/download/v#{version}/Otter-#{version}.dmg"
  name "Otter"
  desc "Menu bar quick capture into Obsidian or any folder"
  homepage "https://github.com/elizabeth-ling/otter"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Sparkle updates the app in place.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Otter.app"

  uninstall quit: "io.github.elizabeth-ling.otter"

  # The outbox under Application Support may hold notes not yet delivered.
  zap trash: [
    "~/Library/Application Support/Otter",
    "~/Library/Caches/io.github.elizabeth-ling.otter",
    "~/Library/HTTPStorages/io.github.elizabeth-ling.otter",
    "~/Library/Preferences/io.github.elizabeth-ling.otter.plist",
  ]
end
CASK
