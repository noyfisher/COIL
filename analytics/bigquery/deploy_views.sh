#!/usr/bin/env bash
#
# Deploy all BigQuery views in this directory to pt-helper-dev.
#
# These views are console/ad-hoc reporting tooling — the dashboard's scheduled
# analytics pull uses its own inline SQL and never depends on them being deployed.
#
# Prerequisites:
#   1. gcloud auth login   (account must have BigQuery access on pt-helper-dev)
#   2. bq CLI installed and on PATH (ships with the Google Cloud SDK)
#   3. gcloud config set project pt-helper-dev   (optional — --project_id is passed explicitly below)
#
# Usage:
#   ./deploy_views.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for view_file in "$SCRIPT_DIR"/v_*.sql; do
  echo "Deploying $(basename "$view_file")..."
  bq query --project_id=pt-helper-dev --use_legacy_sql=false < "$view_file"
done

echo "All views deployed."
