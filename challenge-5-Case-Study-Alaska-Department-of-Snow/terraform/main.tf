terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "us-central1"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# BigQuery Dataset
resource "google_bigquery_dataset" "ads_analytics" {
  dataset_id  = "ads_document_analytics"
  description = "Storage for Alaska Department of Snow document synthesis records"
  location    = var.region
}

# BigQuery Table for Document History
resource "google_bigquery_table" "synthesized_docs" {
  dataset_id          = google_bigquery_dataset.ads_analytics.dataset_id
  table_id            = "synthesized_documents"
  deletion_protection = false

  schema = <<EOF
[
  {"name": "doc_id", "type": "STRING", "mode": "REQUIRED"},
  {"name": "filename", "type": "STRING", "mode": "NULLABLE"},
  {"name": "summary", "type": "STRING", "mode": "NULLABLE"},
  {"name": "risk_assessment", "type": "STRING", "mode": "NULLABLE"},
  {"name": "structured_data", "type": "JSON", "mode": "NULLABLE"},
  {"name": "pii_redacted_count", "type": "INTEGER", "mode": "NULLABLE"},
  {"name": "safety_status", "type": "STRING", "mode": "NULLABLE"},
  {"name": "processed_at", "type": "TIMESTAMP", "mode": "REQUIRED"}
]
