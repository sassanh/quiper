#!/bin/bash
#
# Fails a test run that executed too few tests or skipped any test outside the
# checked-in allowlist, so neither a vacuous run nor a skip-green run can pass
# CI. Usage: verify-test-results.sh <result-bundle> <min-tests> [allowlist]
set -euo pipefail

result_bundle="${1:?Result bundle path is required}"
min_tests="${2:?Minimum test count is required}"
allowlist="${3:-scripts/test-skip-allowlist.txt}"

# Suite and test identifiers arrive as "Suite/test()" or "Module.Suite/test()";
# the allowlist stores both forms without the module prefix or parentheses.
normalize() {
	printf '%s\n' "$1" | sed -E 's/\(\)$//; s/^[^.]*\.//'
}

summary=$(xcrun xcresulttool get test-results summary --path "$result_bundle")
total_tests=$(jq -r '.totalTestCount // 0' <<<"$summary")
skipped_total=$(jq -r '.skippedTests // 0' <<<"$summary")

if [[ ! "$total_tests" =~ ^[0-9]+$ ]] || ((total_tests < min_tests)); then
	echo "Test run is too small: $total_tests tests ran, at least $min_tests expected." >&2
	exit 1
fi

if ((skipped_total == 0)); then
	echo "Ran $total_tests tests, none skipped."
	exit 0
fi

allowlisted=""
if [[ -f "$allowlist" ]]; then
	allowlisted=$(grep -v -e '^[[:space:]]*$' -e '^#' "$allowlist" | sed -E 's/\(\)$//; s/^[^.]*\.//' || true)
fi

tests_json=$(xcrun xcresulttool get test-results tests --path "$result_bundle")

unexpected=()
skipped_seen=()
while IFS= read -r identifier; do
	[[ -z "$identifier" ]] && continue
	normalized=$(normalize "$identifier")
	skipped_seen+=("$normalized")
	if ! grep -Fxq "$normalized" <<<"$allowlisted"; then
		unexpected+=("$normalized")
	fi
done < <(jq -r '.. | objects | select(.result? == "Skipped" and .nodeType? == "Test Case") | .nodeIdentifier // empty' <<<"$tests_json")

if ((${#unexpected[@]} > 0)); then
	echo "Skipped tests that are not in $allowlist:" >&2
	for identifier in "${unexpected[@]}"; do
		echo "  - $identifier" >&2
	done
	echo "A skipped test ships an unverified scenario: fix the scenario so it runs, or add the identifier to $allowlist with the reason it may be skipped." >&2
	exit 1
fi

stale=0
while IFS= read -r entry; do
	[[ -z "$entry" ]] && continue
	if ! printf '%s\n' "${skipped_seen[@]}" | grep -Fxq "$entry"; then
		echo "Allowlist entry skipped nothing in this run: $entry"
		stale=$((stale + 1))
	fi
done <<<"$allowlisted"

echo "Ran $total_tests tests, skipped ${#skipped_seen[@]} (all allowlisted${stale:+, $stale stale})."
