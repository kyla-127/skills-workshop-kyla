#!/usr/bin/env bash

set -euo pipefail

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION="us-central1"
SERVICE_NAME="ads-doc-parser"
REPO_NAME="ads-doc-parser-repo"
IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${SERVICE_NAME}:latest"

if [ -z "$PROJECT_ID" ]; then
  echo "Error: GOOGLE_CLOUD_PROJECT is not set."
  exit 1
fi

echo "=================================================="
echo "Starting ADS Document Synthesis Deployment: $PROJECT_ID"
echo "=================================================="

# 1. Enable Required GCP APIs
echo "--> Enabling GCP Service APIs..."
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  bigquery.googleapis.com \
  dlp.googleapis.com \
  logging.googleapis.com \
  aiplatform.googleapis.com

# 2. Provision Terraform Infrastructure FIRST (Creates BigQuery & Artifact Registry)
echo "--> Provisioning GCP Infrastructure with Terraform..."
cd terraform
terraform init
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}" -auto-approve
cd ..

# 3. Ensure Artifact Registry Repo Exists (Fallback check)
if ! gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" &>/dev/null; then
  echo "--> Creating Artifact Registry repository..."
  gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository for ADS Doc Parser"
fi

# 4. Build Container Image via Cloud Build
echo "--> Building container image with Cloud Build..."
gcloud builds submit --tag "$IMAGE_TAG" .

# 5. Fetch Default Compute Service Account & Apply IAM
COMPUTE_SA=$(gcloud iam service-accounts list --filter="name:compute" --format="value(email)")

echo "--> Assigning IAM permissions to Service Account..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/dlp.admin" >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/bigquery.dataEditor" >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/aiplatform.user" >/dev/null

# 6. Deploy Service to Cloud Run
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
echo "Service URL:"
gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format 'value(status.url)'
echo "=================================================="
