// Single source of truth for links, install commands, and metadata used across
// the site. Update these in one place rather than hunting through components.

export const site = {
  name: "Forge",
  tagline: "The essentials, without the bloat.",
  repo: "https://github.com/Varun-Chinthoju/forge",
  url: "https://varun-chinthoju.github.io/forge",
  // Shown only until the build-time release lookup resolves, and if it fails.
  fallbackVersion: "v0.9.7",
  platform: "macOS 26+",
  license: "AGPL-3.0",
  licenseUrl: "https://github.com/Varun-Chinthoju/forge/blob/main/LICENSE",
  community: {
    github: "https://github.com/Varun-Chinthoju/forge",
  },
  support: "https://github.com/Varun-Chinthoju/forge",
} as const;

// The hero, in as few words as possible — headline plus one punchy line.
export const hero = {
  // One entry per line: the break falls between the two sentences at every width.
  headlineLines: ["Everything on your Mac.", "One keystroke away."],
  sub: "A tiny, native launcher. No Electron. No account. No telemetry. No bullshit.",
  // The mono line under the buttons. Each fact is stated in the docs.
  facts: ["Under 100 MB of memory", "Zero dependencies", "Free & open source"],
} as const;

export const nav = [
  { label: "Features", href: "/#features" },
  { label: "Privacy", href: "/#privacy" },
  { label: "Docs", href: "/docs" },
] as const;

// Homebrew install channels. Each is a separate app that runs side by side,
// with its own settings, permissions and login item. Descriptions follow
// docs/install.md.
export const brewTrustCommand = "brew install --cask forge";

export const channels = [
  {
    id: "stable",
    label: "Stable",
    cask: "forge",
    description:
      "Recommended. The smaller build, for Apple silicon on macOS 26.",
  },
  {
    id: "universal",
    label: "Intel",
    cask: "forge-universal",
    description:
      "The universal build, for Intel Macs on macOS 26. Runs on Apple silicon too.",
  },
  {
    id: "beta",
    label: "Beta",
    cask: "forge@beta",
    description:
      "Installs Forge Beta, with its own settings, right beside stable.",
  },
  {
    id: "sequoia",
    label: "Sequoia",
    cask: "forge-sequoia",
    description: "For macOS 15 Sequoia. New features reach macOS 26 first.",
  },
] as const;

export function brewInstallCommand(cask: string): string {
  return `brew install --cask ${cask}`;
}

// Only for a direct DMG download. Homebrew clears quarantine on every install
// and update, so the Homebrew path needs no manual step at all.
export const quarantineCommand =
  'xattr -dr com.apple.quarantine "/Applications/Forge.app"';
