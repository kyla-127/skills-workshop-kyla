# Challenge 2: Code Refactoring with Gemini Code Assist 

A modern, AI-powered solution built in Google Cloud Shell to refactor brittle, regex-based legacy shell scripts into a robust Python web application. This portal leverages the **Gemini 2.5 API (via `google-genai` / Vertex AI)** for semantic entity extraction from unstructured customer support transcripts and automatically writes structured JSON results and execution logs into **Google Cloud BigQuery**.

---

## 🛠️ How It Was Created

The original legacy solution (`parse_transcript.sh`) relied on fragile `grep`, `sed`, and `bash` pattern matching. It broke easily when transcript lines changed order, had extra spaces, or contained multiline customer issues.

To build this modern pipeline:
1. **Pydantic Schema Definition (`TranscriptAnalysis`):** Enforces strict types and structured JSON output for fields such as `call_id`, `date`, `customer`, `agent`, `product`, `issue`, `resolution`, and `escalate`.
2. **Gemini 2.5 Semantic Extraction:** Utilizes `gemini-2.5-flash` with structured outputs (`response_mime_type="application/json"`) to intelligently infer entities and escalation status regardless of text formatting.
3. **BigQuery Streaming Ingestion:** Integrated `google-cloud-bigquery` to automatically log raw text, extracted structured data, execution timestamps, and audit metrics directly into `transcript_analytics.parsed_transcripts`.
4. **Streamlit Web Interface (`app.py`):** Constructed a web dashboard supporting drag-and-drop file uploads, interactive ad-hoc text parsing, live visual entity cards, raw JSON viewers, and audit logging tables.

---

## 🖥️ UI Overview & Screenshots

### 1. File Upload & Processing View
The main interface allows users to drag and drop `.txt` or `.log` transcript files. Clicking **Process File(s) with Gemini** analyzes the transcript and instantly logs the result to BigQuery.

![Upload Interface](Screenshot%202026-09-23%20at%209.31.51%20AM.png)

### 2. Extracted Entities & Structured Output
Upon completion, the application displays structured entity cards (highlighting whether manager escalation is required) alongside the raw JSON output stored in BigQuery.

![Extracted Results View](Screenshot%202026-09-23%20at%209.31.59%20AM.png)

---

## 🚀 Setup & Execution Guide

### Prerequisites
Run the following commands in Google Cloud Shell to set up your environment variables and install required dependencies:

```bash
# 1. Set Google Cloud Project Environment Variable
export GOOGLE_CLOUD_PROJECT=$(gcloud config get-value project)

# 2. Install required Python packages
pip install google-genai google-cloud-bigquery pydantic streamlit pandas
```

### Initialize BigQuery Destination
Create the target dataset and schema table in BigQuery:

```bash
# Create BigQuery Dataset
bq mk --dataset ${GOOGLE_CLOUD_PROJECT}:transcript_analytics

# Create Schema Table
bq mk --table ${GOOGLE_CLOUD_PROJECT}:transcript_analytics.parsed_transcripts \
  call_id:STRING,date:STRING,customer:STRING,agent:STRING,product:STRING,issue:STRING,resolution:STRING,escalate:BOOLEAN,original_transcript:STRING,processed_at:TIMESTAMP,status:STRING,log_message:STRING
```

### Launching the Web Application

To launch the portal in Cloud Shell without WebSocket or CORS errors, run:

```bash
streamlit run app.py \
  --server.port 8080 \
  --server.enableCORS false \
  --server.enableXsrfProtection false
```

*Click on **Web Preview** in the top right corner of Cloud Shell and select **Preview on port 8080** to open the web portal.*

---

## 📖 How to Use the Web Application

1. **Upload Files:**
   - Navigate to the **📁 Drag & Drop File Upload** tab.
   - Drop one or more transcript files (e.g., `transcript-clean.txt`) into the upload zone.
   - Click **Process File(s) with Gemini**.
2. **View Results:**
   - Review the **Structured Entities** card to check parsed fields and verify if `ESCALATION REQUIRED` was triggered.
   - Inspect the **Raw Extracted JSON** view to verify the underlying schema payload.
3. **Ad-Hoc Text Parsing:**
   - Switch to the **📝 Paste Text Parsing** tab to test raw transcript text or load pre-built samples.
4. **Audit History:**
   - Open the **📊 BigQuery History & Audit Logs** tab to view real-time system execution logs, status codes, and downloadable records.