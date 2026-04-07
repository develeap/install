#!/usr/bin/env bash
# DarkTitan Linux Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/develeap/install/main/darktitan.sh | GITHUB_TOKEN=ghp_xxx bash
#
# Requires: curl, tar, and either jq or python3

set -euo pipefail

REPO="develeap/darktitan"
BINARY="darktitan"

# --- Validate token ---
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "Error: GITHUB_TOKEN is not set."
  echo ""                                                                                                                       echo "Usage:"
  echo "  curl -fsSL https://raw.githubusercontent.com/develeap/install/main/darktitan.sh | GITHUB_TOKEN=ghp_xxx bash"
  echo ""
  echo "Your token needs 'repo' read access to develeap/darktitan."
  exit 1
fi
                                                                                                                              # --- Detect OS ---
OS="$(uname -s)"                                                                                                              if [ "$OS" != "Linux" ]; then
  echo "Error: This installer is for Linux only."                                                                               echo ""
  echo "macOS users, install via Homebrew:"                                                                                     echo "  HOMEBREW_GITHUB_API_TOKEN=ghp_xxx brew install develeap/tap/darktitan"
  exit 1
fi

# --- Detect arch ---
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)        ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "Error: Unsupported architecture: $ARCH (supported: x86_64, aarch64)"
    exit 1
    ;;
esac

echo "Platform: linux/${ARCH}"

# --- JSON helper (jq preferred, python3 fallback) ---
_jq() {
  local expr="$1" input="$2"
  if command -v jq &>/dev/null; then
    echo "$input" | jq -r "$expr"
  elif command -v python3 &>/dev/null; then
    echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print($expr)" 2>/dev/null
  else
    echo "Error: jq or python3 is required. Install one and retry." >&2
    exit 1
  fi
}

# --- Fetch latest release ---
echo "Fetching latest release..."
RELEASE=$(curl -fsSL \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/releases/latest")

if command -v jq &>/dev/null; then
  VERSION=$(echo "$RELEASE" | jq -r '.tag_name')
else
  VERSION=$(echo "$RELEASE" | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
fi

if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then                                                                           echo "Error: Could not determine latest release version. Check that your token has repo read access."
  exit 1
fi

echo "Version: ${VERSION}"

# Strip leading 'v' for filename (goreleaser uses bare version numbers)
VERSION_NUM="${VERSION#v}"
ASSET_NAME="${BINARY}_${VERSION_NUM}_linux_${ARCH}.tar.gz"
# --- Find matching asset ID ---
if command -v jq &>/dev/null; then
  ASSET_ID=$(echo "$RELEASE" | jq -r ".assets[] | select(.name == \"${ASSET_NAME}\") | .id")
else
  ASSET_ID=$(echo "$RELEASE" | python3 -c "
import sys, json
assets = json.load(sys.stdin)['assets']
match = next((a['id'] for a in assets if a['name'] == '${ASSET_NAME}'), None)
print(match if match is not None else '')
")
fi
if [ -z "$ASSET_ID" ] || [ "$ASSET_ID" = "null" ]; then
  echo "Error: Asset '${ASSET_NAME}' not found in release ${VERSION}."
  exit 1
fi

# --- Download ---
echo "Downloading ${ASSET_NAME}..."                                                                                           TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
                                                                                                                              curl -fsSL \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/octet-stream" \
  "https://api.github.com/repos/${REPO}/releases/assets/${ASSET_ID}" \
  -o "${TMPDIR}/${ASSET_NAME}"

# --- Extract ---
tar -xzf "${TMPDIR}/${ASSET_NAME}" -C "${TMPDIR}"

# --- Install ---
if [ -w "/usr/local/bin" ]; then
  INSTALL_DIR="/usr/local/bin"
else
  INSTALL_DIR="${HOME}/.local/bin"
  mkdir -p "$INSTALL_DIR"
fi

mv "${TMPDIR}/${BINARY}" "${INSTALL_DIR}/${BINARY}"                                                                           chmod +x "${INSTALL_DIR}/${BINARY}"

echo "Installed: ${INSTALL_DIR}/${BINARY}"

# --- PATH hint if needed ---
if [ "$INSTALL_DIR" = "${HOME}/.local/bin" ]; then
  echo ""
  echo "Note: /usr/local/bin was not writable; installed to ~/.local/bin instead."
  echo "Add it to your PATH if not already present:"
  echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
fi

# --- Verify ---
echo ""
"${INSTALL_DIR}/${BINARY}" version
echo ""                                                                                                                       echo "DarkTitan installed successfully!"
echo "Run 'darktitan init' to get started."
