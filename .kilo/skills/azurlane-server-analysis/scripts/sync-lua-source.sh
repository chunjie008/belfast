#!/usr/bin/env bash

set -euo pipefail

readonly REMOTE_URL="https://github.com/AzurLaneTools/AzurLaneLuaScripts.git"
# Reproducible snapshot observed on 2026-09-09. Override with --ref or
# AZURLANE_LUA_REF after identifying the commit that matches the client APK.
readonly DEFAULT_REF="765729abe63066cbf4e2139386c6977c91c7d699"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$repo_root" ]]; then
  printf 'error: could not locate the Belfast Git worktree\n' >&2
  exit 1
fi

ref="${AZURLANE_LUA_REF:-$DEFAULT_REF}"
profile="${AZURLANE_LUA_PROFILE:-cn}"
source_dir="${AZURLANE_LUA_DIR:-$repo_root/AzurLaneLuaScripts}"

usage() {
  cat <<'EOF'
Usage: sync-lua-source.sh [options]

Synchronize a shallow, optionally sparse checkout of AzurLaneLuaScripts.

Options:
  --ref REF       Git branch, tag, or commit (default: pinned snapshot)
  --profile NAME  cn or cn-protocol (default: cn)
  --dir PATH      Checkout directory (default: <repo>/AzurLaneLuaScripts)
  --help          Show this help

Environment:
  AZURLANE_LUA_REF      Same as --ref
  AZURLANE_LUA_PROFILE  Same as --profile
  AZURLANE_LUA_DIR      Same as --dir
EOF
}

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    --ref)
      (($# >= 2)) || fail "--ref requires a value"
      ref="$2"
      shift 2
      ;;
    --profile)
      (($# >= 2)) || fail "--profile requires a value"
      profile="$2"
      shift 2
      ;;
    --dir)
      (($# >= 2)) || fail "--dir requires a value"
      source_dir="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

case "$profile" in
  cn|cn-protocol)
    ;;
  *)
    fail "unsupported profile '$profile' (use cn or cn-protocol)"
    ;;
esac

case "$source_dir" in
  /*)
    ;;
  *)
    source_dir="$repo_root/$source_dir"
    ;;
esac

if [[ -e "$source_dir" && ! -d "$source_dir/.git" ]]; then
  fail "$source_dir exists but is not an AzurLaneLuaScripts Git checkout"
fi

if [[ ! -e "$source_dir" ]]; then
  mkdir -p "$(dirname -- "$source_dir")"
  printf 'cloning %s into %s\n' "$REMOTE_URL" "$source_dir"
  git clone \
    --filter=blob:none \
    --no-checkout \
    --depth=1 \
    "$REMOTE_URL" \
    "$source_dir"
fi

origin_url="$(git -C "$source_dir" remote get-url origin 2>/dev/null || true)"
[[ "$origin_url" == "$REMOTE_URL" ]] || \
  fail "origin for $source_dir is '$origin_url', expected $REMOTE_URL"

# A --no-checkout clone has a HEAD but no index yet. In that state Git reports
# every tree entry as deleted, so defer the cleanliness check until checkout.
index_path="$(git -C "$source_dir" rev-parse --git-path index)"
if [[ "$index_path" != /* ]]; then
  index_path="$source_dir/$index_path"
fi
if [[ -f "$index_path" && -n "$(git -C "$source_dir" status --porcelain)" ]]; then
  fail "$source_dir has local changes; preserve or remove them before syncing"
fi

git -C "$source_dir" fetch --depth=1 origin "$ref"

# Configure sparse checkout before checking out the fetched revision. This is
# important for the first clone: checking out first would materialize the full
# multi-gigabyte tree.
case "$profile" in
  cn-protocol)
    git -C "$source_dir" sparse-checkout init --cone
    git -C "$source_dir" sparse-checkout set CN/net/protocol versions
    ;;
  cn)
    git -C "$source_dir" sparse-checkout init --cone
    git -C "$source_dir" sparse-checkout set CN versions
    ;;
esac

git -C "$source_dir" checkout --detach FETCH_HEAD

required_paths=("$source_dir/CN")
if [[ "$profile" == cn-protocol ]]; then
  required_paths=("$source_dir/CN/net/protocol")
fi

for required_path in "${required_paths[@]}"; do
  [[ -d "$required_path" ]] || fail "expected checkout path is missing: $required_path"
done

commit="$(git -C "$source_dir" rev-parse HEAD)"
commit_date="$(git -C "$source_dir" show -s --format='%cI' HEAD)"
commit_subject="$(git -C "$source_dir" show -s --format='%s' HEAD)"

printf '\nLua source ready\n'
printf '  directory: %s\n' "$source_dir"
printf '  profile:   %s\n' "$profile"
printf '  revision:  %s\n' "$commit"
printf '  date:      %s\n' "$commit_date"
printf '  subject:   %s\n' "$commit_subject"
