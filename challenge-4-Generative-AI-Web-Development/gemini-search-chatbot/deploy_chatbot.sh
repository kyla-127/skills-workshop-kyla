#!/usr/bin/env bash

set -euo pipefail

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION="us-central1"
SERVICE_NAME="gemini-search-chatbot"
IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/transcript-app-repo/${SERVICE_NAME}:latest"

echo "=================================================="
echo "Deploying Gemini Search Chatbot: $PROJECT_ID"
echo "=================================================="

# 1. Build Image via Cloud Build
echo "--> Building container image with Cloud Build..."
gcloud builds submit --tag "$IMAGE_TAG" .

# 2. Get Default Compute Service Account
COMPUTE_SA=$(gcloud iam service-accounts list --filter="name:compute" --format="value(email)")

# 3. Deploy Service to Cloud Run
echo "--> Deploying service to Cloud Run..."
gcloud run deploy "$SERVICE_NAME" \
  --image "$IMAGE_TAG" \
  --region "$REGION" \
  --platform managed \
  --service-account "$COMPUTE_SA" \
  --set-env-vars "GOOGLE_CLOUD_PROJECT=${PROJECT_ID}" \
  --allow-unauthenticated \
  --port 8080

echo "=================================================="
echo "Deployment Complete!"
echo "Live URL:"
gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format 'value(status.url)'
echo "=================================================="
