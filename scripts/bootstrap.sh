#!/usr/bin/env bash
# One-time setup for things Terraform needs before it can run: the APIs it
# calls to manage the project, and a bucket to keep its state in.
#
# Usage: scripts/bootstrap.sh <gcp-project-id>
set -euo pipefail

PROJECT_ID="${1:?usage: $0 <gcp-project-id>}"
REGION="${REGION:-us-central1}"
BUCKET="gs://${PROJECT_ID}-tfstate"

gcloud services enable \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  storage.googleapis.com \
  --project "$PROJECT_ID"

if gcloud storage buckets describe "$BUCKET" --project "$PROJECT_ID" > /dev/null 2>&1; then
  echo "State bucket $BUCKET already exists."
else
  gcloud storage buckets create "$BUCKET" \
    --project "$PROJECT_ID" \
    --location "$REGION" \
    --uniform-bucket-level-access \
    --public-access-prevention
  # Versioning keeps every past state file, so a bad apply can be recovered.
  gcloud storage buckets update "$BUCKET" --versioning
fi

echo
echo "Next:"
echo "  cd terraform"
echo "  terraform init -backend-config=\"bucket=${PROJECT_ID}-tfstate\""
