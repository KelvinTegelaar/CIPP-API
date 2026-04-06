#!/usr/bin/env bash
set -euo pipefail

resource_group="${1:?usage: resolve-function-app.sh <resource-group>}"

mapfile -t apps < <(
  az functionapp list \
    --resource-group "$resource_group" \
    --query "[?tags.workload=='cipp' && tags.environment=='prod'].name" \
    --output tsv
)

if [[ "${#apps[@]}" -eq 0 ]]; then
  echo "No CIPP function app found in resource group '$resource_group'." >&2
  exit 1
fi

if [[ "${#apps[@]}" -gt 1 ]]; then
  echo "Multiple CIPP function apps found in '$resource_group':" >&2
  printf '  - %s\n' "${apps[@]}" >&2
  exit 1
fi

app_name="${apps[0]}"
echo "function_app_name=$app_name" >> "$GITHUB_OUTPUT"

echo "Resolved function app: $app_name"
