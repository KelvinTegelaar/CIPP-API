#!/usr/bin/env bash
set -euo pipefail

resource_group="${1:?usage: deploy-function-app.sh <resource-group> <function-app-name> <zip-path>}"
app_name="${2:?usage: deploy-function-app.sh <resource-group> <function-app-name> <zip-path>}"
zip_path="${3:?usage: deploy-function-app.sh <resource-group> <function-app-name> <zip-path>}"

if [[ ! -f "$zip_path" ]]; then
  echo "Deployment archive not found: $zip_path" >&2
  exit 1
fi

az functionapp deployment source config-zip \
  --resource-group "$resource_group" \
  --name "$app_name" \
  --src "$zip_path"

echo "Deployment completed for function app '$app_name'."
