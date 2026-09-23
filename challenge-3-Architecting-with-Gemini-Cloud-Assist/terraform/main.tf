terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "project_id" {
  type        = string
  description = "Target GCP Project ID"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "GCP deployment region"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# 1. Enable Required GCP APIs
resource "google_project_service" "services" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "aiplatform.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  service            = each.key
  disable_on_destroy = false
}

# 2. Service Account for Cloud Run Application
resource "google_service_account" "app_sa" {
  account_id   = "transcript-app-sa"
  display_name = "Service Account for Transcript Parsing App"
  depends_on   = [google_project_service.services]
}

# 3. Artifact Registry Repository for Container Image
resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = "transcript-app-repo"
  description   = "Docker repository for transcript parsing app"
  format        = "DOCKER"
  depends_on    = [google_project_service.services]
}

# 4. Storage Bucket for Raw File Upload Isolation
resource "google_storage_bucket" "uploads" {
  name                        = "${var.project_id}-raw-transcripts"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
  depends_on                  = [google_project_service.services]
}

# 5. BigQuery Dataset
resource "google_bigquery_dataset" "dataset" {
  dataset_id  = "transcript_analytics"
  location    = "US"
  description = "Isolated analytics dataset for parsed customer service transcripts"
  depends_on  = [google_project_service.services]
}

# 6. BigQuery Table
resource "google_bigquery_table" "parsed_table" {
  dataset_id          = google_bigquery_dataset.dataset.dataset_id
  table_id            = "parsed_transcripts"
  deletion_protection = false

  schema = <<EOF
[
  {"name": "call_id", "type": "STRING", "mode": "NULLABLE"},
  {"name": "date", "type": "STRING", "mode": "NULLABLE"},
  {"name": "customer", "type": "STRING", "mode": "NULLABLE"},
  {"name": "agent", "type": "STRING", "mode": "NULLABLE"},
  {"name": "product", "type": "STRING", "mode": "NULLABLE"},
  {"name": "issue", "type": "STRING", "mode": "NULLABLE"},
  {"name": "resolution", "type": "STRING", "mode": "NULLABLE"},
  {"name": "escalate", "type": "BOOLEAN", "mode": "NULLABLE"},
  {"name": "original_transcript", "type": "STRING", "mode": "NULLABLE"},
  {"name": "processed_at", "type": "TIMESTAMP", "mode": "NULLABLE"},
  {"name": "status", "type": "STRING", "mode": "NULLABLE"},
  {"name": "log_message", "type": "STRING", "mode": "NULLABLE"}
]
EOF
}

# 7. Least Privilege IAM Role Bindings
resource "google_project_iam_member" "vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.app_sa.email}"
}

resource "google_bigquery_data_editor" "bq_editor" {
  dataset_id = google_bigquery_dataset.dataset.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.app_sa.email}"
}

resource "google_storage_bucket_iam_member" "gcs_writer" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.app_sa.email}"
}