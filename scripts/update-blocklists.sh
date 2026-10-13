#!/usr/bin/env bash
set -euo pipefail

# Regenerates the bundled WebKit content-blocker rule lists from the upstream
# EasyList and EasyPrivacy filter lists, plus the AdGuard Extra and Block
# YouTube Ads userscripts that cover ads declarative rules cannot reach.
#
# Uses AdguardTeam/SafariConverterLib (GPL-3.0) strictly as a BUILD-TIME tool:
# it is cloned and built in a cache directory, never linked into Quiper, and
# only its output — plain WebKit content-blocker JSON — is committed under
# QuiperShared/Resources/ContentBlockers/. The AdGuard userscripts (GPL-3.0)
# are redistributed unmodified apart from our runtime gating prelude; see
# ATTRIBUTION.txt and GPL-3.0.txt next to them.
#
# Usage: ./scripts/update-blocklists.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$REPO_ROOT/QuiperShared/Resources/ContentBlockers"

CONVERTER_REPO="https://github.com/AdguardTeam/SafariConverterLib"
CONVERTER_VERSION="v4.3.0"
CACHE_DIR="${QUIPER_BLOCKLIST_CACHE_DIR:-$HOME/Library/Caches/quiper-blocklists}"
CONVERTER_DIR="$CACHE_DIR/SafariConverterLib"

EASYLIST_URL="https://easylist.to/easylist/easylist.txt"
EASYPRIVACY_URL="https://easylist.to/easylist/easyprivacy.txt"
# Release channel of the AdGuard Extra userscript (GPL-3.0); the file carries
# its own upstream @version in the userscript header.
ADGUARD_EXTRA_URL="https://userscripts.adtidy.org/release/adguard-extra/1.0/adguard-extra.user.js"
# Latest release of AdGuard's Block YouTube Ads script (GPL-3.0).
YOUTUBE_ADS_URL="https://github.com/AdguardTeam/BlockYouTubeAdsShortcut/releases/latest/download/block-youtube-ads.user.js"
# Expected SHA-256 of both userscripts as last reviewed. They execute in
# every page's JS world, so an upstream change must be reviewed and these
# constants bumped — never picked up silently.
ADGUARD_EXTRA_SHA256="5e7ac8219ba8de61bbadc0973e8d7d88fce7f4c75ef02161d03047a4536efe1d"
YOUTUBE_ADS_SHA256="ab9f1d92c9cc53d9db8822ca8b9b232b00eb9725e2a6ecb10be5d2aac86b0422"

# Safari 16.4 syntax: enables the 150k-rules-per-blocker limit and :has()
# container cosmetic rules, and stays within what WebKit on our minimum
# supported macOS (14.6) understands.
SAFARI_VERSION="16.4"

mkdir -p "$CACHE_DIR" "$OUT_DIR"

verify_userscript() {
	local file="$1" expected="$2" name="$3" actual
	actual="$(shasum -a 256 "$file" | awk '{print $1}')"
	if [ "$actual" != "$expected" ]; then
		echo "ERROR: $name changed upstream (sha256 $actual, expected $expected)." >&2
		echo "Review the new version, then bump its *_SHA256 constant in $0." >&2
		exit 1
	fi
}

# Userscripts first: the pin gate runs before anything writes to the
# committed tree.
echo "==> Fetching AdGuard Extra userscript"
curl -fsSL --retry 3 -o "$CACHE_DIR/adguard-extra.user.js" "$ADGUARD_EXTRA_URL"
verify_userscript "$CACHE_DIR/adguard-extra.user.js" "$ADGUARD_EXTRA_SHA256" "adguard-extra.user.js"

echo "==> Fetching Block YouTube Ads userscript"
curl -fsSL --retry 3 -o "$CACHE_DIR/block-youtube-ads.user.js" "$YOUTUBE_ADS_URL"
verify_userscript "$CACHE_DIR/block-youtube-ads.user.js" "$YOUTUBE_ADS_SHA256" "block-youtube-ads.user.js"

echo "==> Fetching converter $CONVERTER_VERSION"
if [ ! -d "$CONVERTER_DIR/.git" ]; then
	git clone --quiet --depth 1 --branch "$CONVERTER_VERSION" "$CONVERTER_REPO" "$CONVERTER_DIR"
else
	git -C "$CONVERTER_DIR" fetch --quiet --depth 1 origin "refs/tags/$CONVERTER_VERSION" --force
	git -C "$CONVERTER_DIR" checkout --quiet -f "$CONVERTER_VERSION"
fi

# Always build: an existing binary can predate a CONVERTER_VERSION checkout
# of the persistent clone. SwiftPM is incremental, so an unchanged build
# costs nearly nothing while a stale tool would not.
TOOL_BIN="$CONVERTER_DIR/.build/release/ConverterTool"
echo "==> Building ConverterTool"
swift build -c release --package-path "$CONVERTER_DIR" --product ConverterTool

echo "==> Fetching filter lists"
curl -fsSL --retry 3 -o "$CACHE_DIR/easylist.txt" "$EASYLIST_URL"
curl -fsSL --retry 3 -o "$CACHE_DIR/easyprivacy.txt" "$EASYPRIVACY_URL"

echo "==> Converting to WebKit content-blocker JSON"
# Advanced (scriptlet / JS) blocking is off: WKContentRuleList cannot run
# scriptlets, and rules that cannot compile to plain Safari syntax would
# otherwise be silently carried as unusable advanced rules.
"$TOOL_BIN" convert \
	--input-path "$CACHE_DIR/easylist.txt" \
	--safari-version "$SAFARI_VERSION" \
	--safari-rules-json-path "$OUT_DIR/blocker-ads.json"

"$TOOL_BIN" convert \
	--input-path "$CACHE_DIR/easyprivacy.txt" \
	--safari-version "$SAFARI_VERSION" \
	--safari-rules-json-path "$OUT_DIR/blocker-privacy.json"

# Install the pin-verified userscripts only now: if conversion failed above,
# this run leaves the committed tree untouched.
echo "==> Installing verified userscripts"
cp "$CACHE_DIR/adguard-extra.user.js" "$OUT_DIR/adguard-extra.user.js"
cp "$CACHE_DIR/block-youtube-ads.user.js" "$OUT_DIR/block-youtube-ads.user.js"

echo "==> Done"
ls -lh "$OUT_DIR"
