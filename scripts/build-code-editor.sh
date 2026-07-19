#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
EDITOR_DIRECTORY="$REPOSITORY_ROOT/CodeEditorWeb"
DEPENDENCY_STAMP="$EDITOR_DIRECTORY/node_modules/.quiper-dependencies"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "Code editor build requires Node.js 20 or newer and npm." >&2
    exit 1
fi

NODE_MAJOR_VERSION=$(node --version | sed -E 's/^v([0-9]+).*/\1/')
if [ "$NODE_MAJOR_VERSION" -lt 20 ]; then
    echo "Code editor build requires Node.js 20 or newer; found $(node --version)." >&2
    exit 1
fi

DEPENDENCY_KEY="$(shasum -a 256 "$EDITOR_DIRECTORY/package.json" "$EDITOR_DIRECTORY/package-lock.json")|$(node --version)|$(npm --version)"

if [ ! -x "$EDITOR_DIRECTORY/node_modules/.bin/esbuild" ] \
    || [ ! -f "$DEPENDENCY_STAMP" ] \
    || [ "$(<"$DEPENDENCY_STAMP")" != "$DEPENDENCY_KEY" ]; then
    npm ci --prefix "$EDITOR_DIRECTORY" --include=dev --no-audit --no-fund
    printf '%s\n' "$DEPENDENCY_KEY" > "$DEPENDENCY_STAMP"
fi

npm run --prefix "$EDITOR_DIRECTORY" build

if [ "${1:-}" = "--check" ]; then
    git -C "$REPOSITORY_ROOT" diff --exit-code -- Quiper/quiper-code-editor.js
fi
