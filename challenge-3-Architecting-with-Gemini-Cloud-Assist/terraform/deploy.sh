#!/usr/bin/env bash

set -euo pipefail

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION="us-central1"
SERVICE_NAME="transcript-app"
IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/transcript-app-repo/app:latest"

if [ -z "$PROJECT_ID" ]; then
  echo "Error: GOOGLE_CLOUD_PROJECT is not set."
  exit 1
fi

echo "=================================================="
echo "Starting Automated Terraform Deployment: $PROJECT_ID"
echo "=================================================="

# 1. Apply Infrastructure via Terraform
echo "--> Provisioning GCP Infrastructure with Terraform..."
cd terraform
terraform init
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}" -auto-approve
cd ..

# 2. Build Container Image via Cloud Build
echo "--> Building container image with Cloud Build..."
gcloud builds submit --tag "$IMAGE_TAG" .

# 3. Deploy to Cloud Run
echo "--> Deploying service to Cloud Run..."
gcloud run deploy "$SERVICE_NAME" \
  --image "$IMAGE_TAG" \
  --region "$REGION" \
  --platform managed \
  --service-account "transcript-app-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --set-env-vars "GOOGLE_CLOUD_PROJECT=${PROJECT_ID}" \
  --allow-unauthenticated \
  --port 8080

echo "=================================================="
echo "Deployment Complete!"
echo "Service URL:"
gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format 'value(status.url)'
echo "=================================================="
