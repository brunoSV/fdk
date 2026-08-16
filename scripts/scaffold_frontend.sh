#!/usr/bin/env bash
# FDK frontend scaffold: creates a React (Vite) SPA under ~/Documents/projects,
# as a sibling to the Rails API app, wired to talk to it. Used by Checkpoint C
# of create-app when Step 2's stack is API-only Rails + a scaffolded frontend.
set -euo pipefail

eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(mise activate bash)"

PROJECTS_DIR="$HOME/Documents/projects"
API_STYLE=""  # graphql | rest
API_URL=""
NAME=""

usage() {
  cat <<EOF
Usage: scaffold_frontend.sh --name <slug>-frontend --api-style <graphql|rest> --api-url <url>
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --api-style) API_STYLE="$2"; shift 2 ;;
    --api-url) API_URL="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

[ -n "$NAME" ] || usage
[ "$API_STYLE" = "graphql" ] || [ "$API_STYLE" = "rest" ] || usage
[ -n "$API_URL" ] || usage

PROJECT_PATH="$PROJECTS_DIR/$NAME"
[ ! -e "$PROJECT_PATH" ] || { echo "Error: $PROJECT_PATH already exists"; exit 1; }

if ! command -v node >/dev/null 2>&1; then
  echo "==> No Node found, installing via mise"
  mise use -g node@lts
fi

mkdir -p "$PROJECTS_DIR"
cd "$PROJECTS_DIR"

echo "==> npm create vite@latest $NAME -- --template react-ts"
npm create vite@latest "$NAME" -- --template react-ts -y

cd "$PROJECT_PATH"

echo "==> npm install"
npm install

if [ "$API_STYLE" = "graphql" ]; then
  echo "==> Adding Apollo Client"
  npm install @apollo/client graphql
fi

cat > .env <<EOF
VITE_API_URL=$API_URL
EOF

echo "==> git init"
git init -q
git add -A
git commit -q -m "Initial scaffold via FDK (React + Vite)"

echo "==> Done: $PROJECT_PATH"
