#!/usr/bin/env bash
set -euo pipefail

output_zip="${1:?usage: create-deploy-archive.sh <output-zip-path>}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_root="$(cd "$script_dir/.." && pwd)"
stage_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT

# Copy all API source files excluding git metadata, CI config, and deploy tooling.
# The Function App runtime picks up host.json, function directories, modules, and
# requirements.psd1 from the package root.
rsync -a \
  --exclude=".git" \
  --exclude=".github" \
  --exclude="deploy-scripts" \
  --exclude="*.zip" \
  "$app_root/" "$stage_dir/"

mkdir -p "$(dirname "$output_zip")"
rm -f "$output_zip"

(
  cd "$stage_dir"
  zip -qr "$output_zip" .
)

echo "Created deployment archive at $output_zip"
