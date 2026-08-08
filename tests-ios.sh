#!/bin/bash
set -euo pipefail

PROJECT="Quiper.xcodeproj"
SCHEME="QuiperiOS"
DERIVED_DATA_PATH="${IOS_DERIVED_DATA_PATH:-build/DerivedData-iOS}"
RESULT_BUNDLE="$DERIVED_DATA_PATH/TestResult.xcresult"
COVERAGE_PATH="${IOS_COVERAGE_PATH:-coverage-ios.lcov}"

rm -rf "$RESULT_BUNDLE"

destination="${IOS_TEST_DESTINATION:-}"
if [[ -z "$destination" ]]; then
    preferred_id=$(xcrun simctl list devices available --json \
        | jq -r '[.devices | to_entries[] | .value[]
            | select(.isAvailable == true and (.name | startswith("iPhone 17")))]
            | .[0].udid // empty')
    fallback_id=$(xcrun simctl list devices available --json \
        | jq -r '[.devices | to_entries[] | .value[]
            | select(.isAvailable == true and (.name | startswith("iPhone")))]
            | .[0].udid // empty')
    simulator_id="${preferred_id:-$fallback_id}"
    if [[ -z "$simulator_id" ]]; then
        echo "No available iPhone simulator was found." >&2
        exit 1
    fi
    destination="platform=iOS Simulator,id=$simulator_id"
fi

echo "Running iOS tests on: $destination"
xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$destination" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -resultBundlePath "$RESULT_BUNDLE" \
    -enableCodeCoverage YES \
    -parallel-testing-enabled NO \
    "$@"

if [[ ! -d "$RESULT_BUNDLE" ]]; then
    echo "Result bundle not found at $RESULT_BUNDLE" >&2
    exit 1
fi

profdata=$(find "$DERIVED_DATA_PATH" -name Coverage.profdata -print -quit)
if [[ -z "$profdata" ]]; then
    echo "Coverage.profdata not found in $DERIVED_DATA_PATH" >&2
    exit 1
fi

app_binary=$(find "$DERIVED_DATA_PATH/Build/Products" \
    -path "*/QuiperiOS.app/QuiperiOS" -type f -print -quit)
if [[ -z "$app_binary" ]]; then
    echo "Instrumented QuiperiOS binary not found in $DERIVED_DATA_PATH" >&2
    exit 1
fi

xcrun llvm-cov export \
    -format=lcov \
    -instr-profile "$profdata" \
    -object "$app_binary" \
    -path-equivalence "$(pwd)/,." \
    -ignore-filename-regex=".build|Tests" > "$COVERAGE_PATH"

echo "iOS coverage written to $COVERAGE_PATH"
