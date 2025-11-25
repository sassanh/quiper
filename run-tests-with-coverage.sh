#!/bin/bash
set -euo pipefail

echo "🧪 Running tests with coverage..."
swift test --configuration debug --enable-code-coverage

echo ""
echo "📊 Generating coverage report..."

# Find the profile data and test binary
PROFILE=$(find .build -path "*/codecov/default.profdata" | head -n1)
if [ -z "$PROFILE" ]; then
    echo "❌ Error: No default.profdata found under .build/**/codecov"
    exit 1
fi

TEST_BIN=$(find .build -type f -path "*.xctest/Contents/MacOS/*" | head -n1)
if [ -z "$TEST_BIN" ]; then
    echo "❌ Error: No test binary found under .build"
    exit 1
fi

ROOT=$(pwd)

echo ""
echo "📈 Coverage Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
xcrun llvm-cov report \
    "$TEST_BIN" \
    -instr-profile="$PROFILE" \
    -path-equivalence "$ROOT","." \
    "$ROOT/Sources"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "📁 Generating HTML coverage report..."
xcrun llvm-cov show \
    "$TEST_BIN" \
    -instr-profile "$PROFILE" \
    -path-equivalence "$ROOT","." \
    -format=html \
    -output-dir coverage-html \
    "$ROOT/Sources"

echo ""
echo "✅ Coverage report generated!"
echo "   HTML report: coverage-html/index.html"
echo ""
echo "To view the HTML report, run:"
echo "   open coverage-html/index.html"
