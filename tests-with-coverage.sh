#!/bin/bash
set -euo pipefail

PROJECT="Quiper.xcodeproj"
SCHEME="Quiper"
DERIVED_DATA_PATH="build/DerivedData"

echo "🧪 Running tests with coverage..."

# Define explicit result bundle path to avoid ambiguity
RESULT_BUNDLE="$DERIVED_DATA_PATH/TestResult.xcresult"
rm -rf "$RESULT_BUNDLE"

echo "� Running tests with coverage..."
echo "   (This may take a moment to build if incremental changes are detected)"

# Run tests (handles building and testing in one command for correctness)
xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -resultBundlePath "$RESULT_BUNDLE" \
    -enableCodeCoverage YES \
    CLANG_COVERAGE_MAPPING=YES \
    COPY_PHASE_STRIP=NO \
    -parallel-testing-enabled NO \
    "$@"

echo ""
echo "📊 Generating coverage report..."

XCRESULT="$RESULT_BUNDLE"
if [ ! -d "$XCRESULT" ]; then
    echo "❌ Error: Result bundle not found at $XCRESULT"
    exit 1
fi

# Locate Profile Data
PROFDATA=$(find "$DERIVED_DATA_PATH" -name "Coverage.profdata" -print -quit)
if [ -z "$PROFDATA" ]; then
    echo "❌ Error: Coverage.profdata not found in $DERIVED_DATA_PATH"
    exit 1
fi

# Find instrumented binaries
BINARIES=()

BUILD_PATH="$DERIVED_DATA_PATH/Build/Products/Debug"

# Check main app binary
APP_BINARY="$BUILD_PATH/Quiper.app/Contents/MacOS/Quiper"
if [ -f "$APP_BINARY" ]; then
    if otool -l "$APP_BINARY" | grep -q "__llvm_covmap"; then
        echo "✅ Found instrumented app binary: $APP_BINARY"
        BINARIES+=("-object" "$APP_BINARY")
    else
        echo "⚠️  App binary exists but missing coverage map (skipping): $APP_BINARY"
    fi
fi

# Check frameworks
if [ -d "$BUILD_PATH/PackageFrameworks" ]; then
    for f in "$BUILD_PATH/PackageFrameworks/"*.framework/*; do
        # Use simple basename check to avoid checking resources/symlinks if possible, 
        # but otool check is robust enough.
        if [ -f "$f" ] && [ ! -L "$f" ]; then
             if otool -l "$f" 2>/dev/null | grep -q "__llvm_covmap"; then
                 echo "✅ Found instrumented framework: $f"
                 BINARIES+=("-object" "$f")
             fi
        fi
    done
fi

# Check for standalone object files (products)
for f in "$BUILD_PATH/"*.o; do
    if [ -f "$f" ]; then
         if otool -l "$f" 2>/dev/null | grep -q "__llvm_covmap"; then
             echo "✅ Found instrumented object file: $f"
             BINARIES+=("-object" "$f")
         fi
    fi
done

# Check for intermediate object files (App source objects)
# This handles cases where the main binary is stripped but individual objects retain coverage.
INTERMEDIATES_PATH="$DERIVED_DATA_PATH/Build/Intermediates.noindex/Quiper.build/Debug/Quiper.build/Objects-normal"
if [ -d "$INTERMEDIATES_PATH" ]; then
    echo "🔍 Searching for intermediate object files in $INTERMEDIATES_PATH..."
    # recursively find .o files
    while IFS= read -r f; do
         if otool -l "$f" 2>/dev/null | grep -q "__llvm_covmap"; then
             # Only show first few to avoid spamming log
             # echo "✅ Found instrumented intermediate: $(basename "$f")" 
             BINARIES+=("-object" "$f")
         fi
    done < <(find "$INTERMEDIATES_PATH" -name "*.o")
    echo "✅ Added $(find "$INTERMEDIATES_PATH" -name "*.o" | wc -l | xargs) intermediate object files."
fi

if [ ${#BINARIES[@]} -eq 0 ]; then
    echo "❌ Error: No instrumented binaries found. Cannot generate report."
    exit 1
fi

echo "📊 Generating textual summary..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
xcrun llvm-cov report \
    -instr-profile "$PROFDATA" \
    "${BINARIES[@]}" \
    -ignore-filename-regex=".build|Tests" \
    -use-color

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "📊 Generating LCOV report for Codecov..."
xcrun llvm-cov export \
    -format="lcov" \
    -instr-profile "$PROFDATA" \
    "${BINARIES[@]}" \
    -path-equivalence "$(pwd)/","." \
    -ignore-filename-regex=".build|Tests" > coverage.lcov

echo "✅ LCOV report generated at coverage.lcov"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "📊 Generating HTML report..."

OUTPUT_DIR="coverage-html"
rm -rf "$OUTPUT_DIR"

xcrun llvm-cov show \
    -format=html \
    -output-dir "$OUTPUT_DIR" \
    -instr-profile "$PROFDATA" \
    "${BINARIES[@]}" \
    -ignore-filename-regex=".build|Tests"

echo "✅ HTML report generated at $OUTPUT_DIR/index.html"

echo ""
echo "✅ Coverage reports generated!"
echo "   📄 LCOV report: coverage.lcov"
echo "   🌐 HTML report: coverage-html/index.html"
echo ""
echo "To open HTML report:"
echo "   open coverage-html/index.html"
echo ""
echo "To view detailed coverage in Xcode:"
echo "   Product → Show Code Coverage"

