#!/bin/bash
# Local test script for the bash-based PKGBUILD generation workflow
# This simulates what the GitHub Actions workflow does without committing anything

set -euo pipefail

echo "🧪 Testing bash-based PKGBUILD generation workflow"
echo "=================================================="
echo ""

# Check dependencies
echo "📦 Checking dependencies..."
for cmd in curl jq bsdtar sha512sum sed grep awk; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ Missing: $cmd"
        exit 1
    fi
done
echo "✓ All dependencies available"
echo ""

# Check if PKGBUILD.sed exists
if [ ! -f PKGBUILD.sed ]; then
    echo "❌ PKGBUILD.sed not found!"
    exit 1
fi

TMP_DEB="$(mktemp /tmp/cursor_test.XXXXXX.deb)"
cleanup() {
    rm -f "$TMP_DEB"
}
trap cleanup EXIT

# Get current version from PKGBUILD if it exists
if [ -f PKGBUILD ]; then
    CURRENT_PKGVER=$(grep -E '^pkgver=' PKGBUILD | cut -d'=' -f2)
    CURRENT_COMMIT=$(grep -E '^_commit=' PKGBUILD | cut -d'=' -f2 | sed 's/ #.*//')
else
    CURRENT_PKGVER=""
    CURRENT_COMMIT=""
fi

echo ""
echo "🔍 Checking for updates..."

echo "Current version: ${CURRENT_PKGVER:-none}"
echo "Current commit: ${CURRENT_COMMIT:-none}"

extract_commit() { echo "$1" | sed -n 's|.*/production/\([^/]*\).*|\1|p'; }
version_lt() {
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ] && [ "$1" != "$2" ]
}
CURSOR_UPDATE_API="https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable"
echo "🌐 Querying Cursor update API..."
API_RESPONSE=$(curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused --connect-timeout 10 --max-time 30 "$CURSOR_UPDATE_API")

if [ -z "$API_RESPONSE" ]; then
    echo "❌ ERROR: Failed to get response from update API"
    exit 1
fi

NEW_PKGVER=$(echo "$API_RESPONSE" | jq -r '.version // empty')
NEW_COMMIT=$(echo "$API_RESPONSE" | jq -r '.commitSha // empty')
DEB_URL=$(echo "$API_RESPONSE" | jq -r '.debUrl // empty')
if [ -z "$NEW_COMMIT" ] && [ -n "$DEB_URL" ]; then
    NEW_COMMIT=$(extract_commit "$DEB_URL")
fi
echo "Latest version found: ${NEW_PKGVER:-unknown}"

if [ -z "$NEW_PKGVER" ] || [ -z "$NEW_COMMIT" ] || [ -z "$DEB_URL" ]; then
    echo "❌ ERROR: Failed to extract version/commit/debUrl from update API response"
    exit 1
fi
if ! [[ "$NEW_PKGVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ ERROR: Invalid version format from update API: $NEW_PKGVER"
    exit 1
fi
if ! [[ "$NEW_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "❌ ERROR: Invalid commit format from update API: $NEW_COMMIT"
    exit 1
fi

echo "New version: ${NEW_PKGVER}"
echo "New commit: ${NEW_COMMIT}"
echo ""

if [ -n "$CURRENT_PKGVER" ] && version_lt "$NEW_PKGVER" "$CURRENT_PKGVER"; then
    echo "⚠️  Stable API returned an older version (${NEW_PKGVER}) than local PKGBUILD (${CURRENT_PKGVER})."
    echo "⚠️  Refusing downgrade in local test run."
    exit 0
fi

# Check if update is needed
if [ "$CURRENT_PKGVER" = "$NEW_PKGVER" ] && [ "$CURRENT_COMMIT" = "$NEW_COMMIT" ]; then
    echo "ℹ️  No update needed. Current version matches latest."
    echo ""
    echo "💡 To force a test, you can temporarily modify PKGBUILD version"
    exit 0
fi

echo "📥 Update needed! Generating PKGBUILD..."
echo ""

# Download .deb file
echo "⬇️  Downloading .deb file..."
curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused --connect-timeout 15 --max-time 300 "$DEB_URL" -o "$TMP_DEB"
if [ ! -s "$TMP_DEB" ]; then
    echo "❌ ERROR: Downloaded .deb is empty"
    exit 1
fi

# Calculate SHA512
echo "🔐 Calculating SHA512 checksum..."
NEW_SHA=$(sha512sum "$TMP_DEB" | cut -d ' ' -f 1)
echo "SHA512: ${NEW_SHA:0:20}..."

echo "⚡ Using upstream bundled runtime (no system Electron dependency)..."
echo ""

# Generate PKGBUILD from template
echo "📝 Generating PKGBUILD from template..."
# Use awk for sha512sum replacement as sed has issues with brackets
awk -v pkgver="$NEW_PKGVER" \
    -v commit="$NEW_COMMIT" \
    -v sha="$NEW_SHA" \
    'BEGIN {OFS=""}
     /^pkgver=/ {print "pkgver=" pkgver; next}
     /^_commit=/ {print "_commit=" commit " # sed'\''ded at GitHub WF"; next}
     /^sha512sums\[0\]=/ {print "sha512sums[0]=" sha; next}
     {print}' PKGBUILD.sed > PKGBUILD.test || {
    echo "❌ ERROR: Failed to generate PKGBUILD"
    exit 1
}

echo ""
echo "✅ Validation checks..."
# Temporarily disable exit on error for validation
set +e
VALIDATION_FAILED=0

# Basic validation
if ! grep -q "^pkgver=${NEW_PKGVER}$" PKGBUILD.test; then
    echo "❌ ERROR: pkgver not set correctly"
    VALIDATION_FAILED=1
else
    echo "✓ pkgver is correct"
fi

if ! grep -q "^_commit=${NEW_COMMIT}" PKGBUILD.test; then
    echo "❌ ERROR: _commit not set correctly"
    VALIDATION_FAILED=1
else
    echo "✓ _commit is correct"
fi

if ! grep -q "^sha512sums\[0\]=${NEW_SHA}" PKGBUILD.test; then
    echo "❌ ERROR: sha512sum not set correctly"
    echo "   Expected: sha512sum[0]=${NEW_SHA:0:20}..."
    echo "   Got: $(grep '^sha512sums\[0\]=' PKGBUILD.test || echo 'not found')"
    VALIDATION_FAILED=1
else
    echo "✓ sha512sum is correct"
fi

if ! grep -q "^install=cursor-ai-bin.install$" PKGBUILD.test; then
    echo "❌ ERROR: install script not wired in PKGBUILD!"
    VALIDATION_FAILED=1
else
    echo "✓ install script hook is present"
fi

# Check for ripgrep dependency
if ! grep -q "ripgrep" PKGBUILD.test; then
    echo "❌ ERROR: ripgrep dependency missing!"
    VALIDATION_FAILED=1
else
    echo "✓ ripgrep dependency present"
fi

echo ""

set -e
if [ $VALIDATION_FAILED -eq 1 ]; then
    echo "❌ Validation failed!"
    echo ""
    echo "Generated PKGBUILD content (for debugging):"
    echo "============================================"
    if [ -f PKGBUILD.test ]; then
        cat PKGBUILD.test
    else
        echo "PKGBUILD.test was not created!"
    fi
    exit 1
fi

echo "✅ All validations passed!"
echo ""
echo "📄 Generated PKGBUILD:"
echo "========================"
cat PKGBUILD.test
echo ""

# Optionally test with makepkg (if on Arch Linux)
if command -v makepkg &> /dev/null; then
    read -p "🧪 Test with makepkg? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "🧪 Testing PKGBUILD with makepkg (dry run)..."
        # Backup original PKGBUILD only when needed for makepkg test
        if [ -f PKGBUILD ]; then
            cp PKGBUILD PKGBUILD.backup
        fi
        cp PKGBUILD.test PKGBUILD
        makepkg --verifysource --noconfirm || echo "⚠️  makepkg test had issues (this is expected if source files aren't available)"
        # Restore original PKGBUILD
        if [ -f PKGBUILD.backup ]; then
            mv PKGBUILD.backup PKGBUILD
            echo "✓ Restored original PKGBUILD"
        fi
    fi
fi

echo ""
echo "📋 Summary:"
echo "==========="
echo "Generated PKGBUILD saved as: PKGBUILD.test"
if [ -f PKGBUILD.backup ]; then
    echo "Original PKGBUILD preserved as: PKGBUILD.backup (from makepkg test)"
fi
echo ""
echo "To review the generated PKGBUILD:"
echo "  cat PKGBUILD.test"
echo ""
echo "To compare with current PKGBUILD:"
echo "  diff PKGBUILD PKGBUILD.test"
echo ""
echo "To use the generated PKGBUILD:"
echo "  mv PKGBUILD.test PKGBUILD"
echo ""

