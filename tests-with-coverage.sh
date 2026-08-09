#!/bin/bash
set -euo pipefail

project="Quiper.xcodeproj"
category="${1:-macos-all}"

case "$category" in
    macos-unit|macos-ui|ios-unit|macos-all)
        shift
        ;;
    *)
        # Preserve the original no-category interface for local full-suite runs.
        category="macos-all"
        ;;
esac

scheme=""
test_target=""
app_name=""
destination=""
derived_data_path=""
coverage_path=""
coverage_html_path=""

case "$category" in
    macos-unit)
        scheme="Quiper"
        test_target="QuiperTests"
        app_name="Quiper"
        destination="${MACOS_TEST_DESTINATION:-platform=macOS}"
        derived_data_path="${MACOS_UNIT_DERIVED_DATA_PATH:-build/DerivedData-macos-unit}"
        coverage_path="${MACOS_UNIT_COVERAGE_PATH:-coverage-macos-unit.lcov}"
        coverage_html_path="${MACOS_UNIT_COVERAGE_HTML_PATH:-coverage-html-macos-unit}"
        ;;
    macos-ui)
        scheme="Quiper"
        test_target="QuiperUITests"
        app_name="Quiper"
        destination="${MACOS_TEST_DESTINATION:-platform=macOS}"
        derived_data_path="${MACOS_UI_DERIVED_DATA_PATH:-build/DerivedData-macos-ui}"
        coverage_path="${MACOS_UI_COVERAGE_PATH:-coverage-macos-ui.lcov}"
        coverage_html_path="${MACOS_UI_COVERAGE_HTML_PATH:-coverage-html-macos-ui}"
        ;;
    ios-unit)
        scheme="QuiperiOS"
        app_name="QuiperiOS"
        derived_data_path="${IOS_UNIT_DERIVED_DATA_PATH:-${IOS_DERIVED_DATA_PATH:-build/DerivedData-ios-unit}}"
        coverage_path="${IOS_UNIT_COVERAGE_PATH:-${IOS_COVERAGE_PATH:-coverage-ios-unit.lcov}}"
        coverage_html_path="${IOS_UNIT_COVERAGE_HTML_PATH:-${IOS_COVERAGE_HTML_PATH:-coverage-html-ios-unit}}"

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
        ;;
    macos-all)
        scheme="Quiper"
        app_name="Quiper"
        destination="${MACOS_TEST_DESTINATION:-platform=macOS}"
        derived_data_path="${MACOS_DERIVED_DATA_PATH:-build/DerivedData}"
        coverage_path="${MACOS_COVERAGE_PATH:-coverage.lcov}"
        coverage_html_path="${MACOS_COVERAGE_HTML_PATH:-coverage-html}"
        ;;
esac

result_bundle="$derived_data_path/TestResult.xcresult"
rm -rf "$result_bundle"

echo "Running $category tests on: $destination"

xcode_arguments=(
    test
    -project "$project"
    -scheme "$scheme"
    -destination "$destination"
    -derivedDataPath "$derived_data_path"
    -resultBundlePath "$result_bundle"
    -enableCodeCoverage YES
    CLANG_COVERAGE_MAPPING=YES
    COPY_PHASE_STRIP=NO
    -parallel-testing-enabled NO
)

if [[ -n "$test_target" ]]; then
    xcode_arguments+=("-only-testing:$test_target")
fi

if [[ "$category" == macos-* ]]; then
    macos_test_identity="${MACOS_TEST_CODE_SIGN_IDENTITY:--}"
    macos_test_team="${MACOS_TEST_DEVELOPMENT_TEAM:-}"
    xcode_arguments+=(
        CODE_SIGN_IDENTITY="$macos_test_identity"
        DEVELOPMENT_TEAM="$macos_test_team"
    )
fi

xcodebuild "${xcode_arguments[@]}" "$@"

if [[ ! -d "$result_bundle" ]]; then
    echo "Result bundle not found at $result_bundle" >&2
    exit 1
fi

profdata=$(find "$derived_data_path" -name Coverage.profdata -print -quit)
if [[ -z "$profdata" ]]; then
    echo "Coverage.profdata not found in $derived_data_path" >&2
    exit 1
fi

products_path="$derived_data_path/Build/Products"
app_bundle=$(find "$products_path" -path "*/$app_name.app" -type d -print -quit)
if [[ -z "$app_bundle" ]]; then
    echo "$app_name app bundle not found in $products_path" >&2
    exit 1
fi

coverage_object=""
coverage_candidates=(
    "$app_bundle/Contents/MacOS/$app_name.debug.dylib"
    "$app_bundle/Contents/MacOS/$app_name"
    "$app_bundle/$app_name.debug.dylib"
    "$app_bundle/$app_name"
)

for candidate in "${coverage_candidates[@]}"; do
    if [[ -f "$candidate" ]] && otool -l "$candidate" 2>/dev/null | grep "__llvm_covmap" >/dev/null; then
        coverage_object="$candidate"
        break
    fi
done

if [[ -z "$coverage_object" ]]; then
    echo "Instrumented $app_name binary not found in $app_bundle" >&2
    exit 1
fi

echo "Exporting coverage from: $coverage_object"

xcrun llvm-cov report \
    -instr-profile "$profdata" \
    -object "$coverage_object" \
    -ignore-filename-regex='.build|Tests'

xcrun llvm-cov export \
    -format=lcov \
    -instr-profile "$profdata" \
    -object "$coverage_object" \
    -path-equivalence "$(pwd)/,." \
    -ignore-filename-regex='.build|Tests' > "$coverage_path"

rm -rf "$coverage_html_path"
xcrun llvm-cov show \
    -format=html \
    -output-dir "$coverage_html_path" \
    -instr-profile "$profdata" \
    -object "$coverage_object" \
    -ignore-filename-regex='.build|Tests'

echo "Coverage written to $coverage_path"
echo "HTML coverage report written to $coverage_html_path/index.html"
