#!/usr/bin/env bash
# FDK scaffold: creates a new Rails app under ~/Documents/projects with a
# consistent baseline (test framework, auth, git). Product-specific models,
# controllers, and the Devise User model are generated afterward, by hand.
set -euo pipefail

eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(mise activate bash)"

PROJECTS_DIR="$HOME/Documents/projects"
STACK=""       # hotwire | api
AUTH="devise"  # devise | none
TEST="rspec"   # rspec | minitest
DB="postgresql" # postgresql | sqlite3
NAME=""

usage() {
  cat <<EOF
Usage: scaffold.sh --name <slug> --stack <hotwire|api> [--auth <devise|none>] [--test <rspec|minitest>] [--db <postgresql|sqlite3>]
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --stack) STACK="$2"; shift 2 ;;
    --auth) AUTH="$2"; shift 2 ;;
    --test) TEST="$2"; shift 2 ;;
    --db) DB="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

[ -n "$NAME" ] || usage
[ "$STACK" = "hotwire" ] || [ "$STACK" = "api" ] || usage
[ "$AUTH" = "devise" ] || [ "$AUTH" = "none" ] || usage
[ "$TEST" = "rspec" ] || [ "$TEST" = "minitest" ] || usage

PROJECT_PATH="$PROJECTS_DIR/$NAME"
[ ! -e "$PROJECT_PATH" ] || { echo "Error: $PROJECT_PATH already exists"; exit 1; }

mkdir -p "$PROJECTS_DIR"
cd "$PROJECTS_DIR"

RAILS_NEW_FLAGS=(--database="$DB")
[ "$STACK" = "api" ] && RAILS_NEW_FLAGS+=(--api)
[ "$TEST" = "rspec" ] && RAILS_NEW_FLAGS+=(--skip-test)

echo "==> rails new $NAME ${RAILS_NEW_FLAGS[*]}"
rails new "$NAME" "${RAILS_NEW_FLAGS[@]}"

cd "$PROJECT_PATH"

if [ "$TEST" = "rspec" ]; then
  echo "==> Adding rspec-rails"
  bundle add rspec-rails --group "development,test"
  bundle exec rails generate rspec:install
fi

if [ "$AUTH" = "devise" ]; then
  echo "==> Adding devise"
  bundle add devise
  bundle exec rails generate devise:install
fi

if [ "$DB" = "postgresql" ]; then
  echo "==> Creating database"
  bin/rails db:create
fi

echo "==> git init"
git init -q
git add -A
git commit -q -m "Initial scaffold via FDK"

echo "==> Done: $PROJECT_PATH"
