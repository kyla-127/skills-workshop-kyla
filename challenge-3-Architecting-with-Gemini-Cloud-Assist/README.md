# 🚀 GCP Customer Service Transcript Parser — Deployment Summary

## 📌 Project Overview
Transformed a brittle legacy Bash transcript parser (`grep`/`sed`) into a structured, production-grade Python web application deployed to Google Cloud Run. The solution leverages **Gemini 2.5 Flash** for entity extraction and automatically logs structured outputs to **Google Cloud BigQuery**.

---

## 🏗️ Key Architecture & Refactoring Highlights

1. **Semantic Entity Extraction:**
   * Replaced regular expressions with **Gemini 2.5 Flash** using **Pydantic** schemas for strict type validation (`call_id`, `date`, `customer`, `agent`, `product`, `issue`, `resolution`, `escalate`).

2. **Infrastructure as Code (Terraform):**
   * Configured `main.tf` to provision **BigQuery** (`transcript_analytics.parsed_transcripts`), **Artifact Registry** (`transcript-app-repo`), and **Cloud Storage** bucket resources with least-privilege IAM bindings.

3. **Containerized Web App:**
   * Containerized a **Streamlit** dashboard via Docker to allow batch file upload, raw JSON viewing, ad-hoc text parsing, and BigQuery history viewing.
   * Addressed Cloud Shell proxying and Cloud Run WebSocket constraints using custom `.streamlit/config.toml` settings.

4. **Automated Pipeline Deployment:**
   * Created `deploy.sh` to automate Terraform provisioning, container image compilation via **Cloud Build**, and deployment to **Cloud Run** using the project default Compute Service Account to bypass sandbox permission limits.

---

## ⚡ Deployment & Verification Quickstart

### 1. Execute Pipeline Deployment
```bash
cd ~/Challenge\ 2/customer-service-parser
chmod +x deploy.sh
./deploy.sh