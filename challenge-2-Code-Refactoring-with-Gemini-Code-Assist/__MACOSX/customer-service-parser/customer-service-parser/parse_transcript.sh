#!/usr/bin/env bash

# Refactored transcript parser using Vertex AI (Gemini) & BigQuery
# Usage: ./parse_transcript.sh <input_transcript.txt>

set -euo pipefail

# Configuration
DATASET_ID="transcript_analytics"
TABLE_ID="parsed_transcripts"
OUTPUT_DIR="output"
LOCATION="us-central1"

# Step 1: Validate environment and inputs
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <input_transcript.txt>"
  exit 1
fi

INPUT_FILE="$1"

if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: file not found: $INPUT_FILE"
  exit 1
fi

# Ensure GOOGLE_CLOUD_PROJECT is set
if [ -z "${GOOGLE_CLOUD_PROJECT:-}" ]; then
  GOOGLE_CLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null)
  if [ -z "$GOOGLE_CLOUD_PROJECT" ]; then
    echo "Error: GOOGLE_CLOUD_PROJECT environment variable is not set."
    exit 1
  fi
fi

mkdir -p "$OUTPUT_DIR"

BASE_NAME=$(basename "$INPUT_FILE")
BASE_NAME="${BASE_NAME%.*}"
OUTPUT_FILE="${OUTPUT_DIR}/${BASE_NAME}.json"

echo "Processing $INPUT_FILE..."

# Step 2: Build the prompt and transcript payload
TRANSCRIPT_TEXT=$(cat "$INPUT_FILE")

PROMPT=$(cat <<'EOF'
Extract key information from the customer transcript below.
Return ONLY a raw, valid JSON object matching this structure:
{
  "call_id": "string or null",
  "date": "string or null",
  "customer": "string or null",
  "agent": "string or null",
  "product": "string or null",
  "issue": "string or null",
  "resolution": "string or null",
  "escalate": boolean
}
EOF
)

FULL_PROMPT="${PROMPT}"$'\n\nTRANSCRIPT:\n'"${TRANSCRIPT_TEXT}"

# Step 3: Extract structured JSON using Vertex AI via Cloud Shell Auth Token
ACCESS_TOKEN=$(gcloud auth print-access-token)

PAYLOAD=$(jq -n --arg prompt "$FULL_PROMPT" '{
  contents: [{
    role: "USER",
    parts: [{ text: $prompt }]
  }],
  generationConfig: {
    responseMimeType: "application/json"
  }
}')

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "$PAYLOAD" \
  "https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${GOOGLE_CLOUD_PROJECT}/locations/${LOCATION}/publishers/google/models/gemini-2.5-flash:generateContent")

PARSED_JSON=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text // empty')

if [ -z "$PARSED_JSON" ]; then
    echo "Error: Vertex AI call failed or returned empty response."
    echo "Response details: $RESPONSE"
    exit 1
fi

# Validate output format using jq
if ! echo "$PARSED_JSON" | jq . >/dev/null 2>&1; then
    echo "Error: Returned output is not valid JSON."
    echo "$PARSED_JSON"
    exit 1
fi

# Step 4: Save to output JSON file
echo "$PARSED_JSON" > "$OUTPUT_FILE"
echo "Successfully wrote parsed JSON to $OUTPUT_FILE"

# Step 5: Write record and logs to BigQuery
echo "Logging record to BigQuery..."
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_MESSAGE="Successfully parsed $BASE_NAME via parse_transcript.sh"
STATUS="SUCCESS"

CALL_ID=$(echo "$PARSED_JSON" | jq -r '.call_id // ""')
DATE_VAL=$(echo "$PARSED_JSON" | jq -r '.date // ""')
CUSTOMER=$(echo "$PARSED_JSON" | jq -r '.customer // ""')
AGENT=$(echo "$PARSED_JSON" | jq -r '.agent // ""')
PRODUCT=$(echo "$PARSED_JSON" | jq -r '.product // ""')
ISSUE=$(echo "$PARSED_JSON" | jq -r '.issue // ""')
RESOLUTION=$(echo "$PARSED_JSON" | jq -r '.resolution // ""')
ESCALATE=$(echo "$PARSED_JSON" | jq -r '.escalate // false')

# Use parameterized SQL query to safely handle multiline strings and special characters
bq query --use_legacy_sql=false \
  --parameter="call_id:STRING:${CALL_ID}" \
  --parameter="date_val:STRING:${DATE_VAL}" \
  --parameter="customer:STRING:${CUSTOMER}" \
  --parameter="agent:STRING:${AGENT}" \
  --parameter="product:STRING:${PRODUCT}" \
  --parameter="issue:STRING:${ISSUE}" \
  --parameter="resolution:STRING:${RESOLUTION}" \
  --parameter="escalate:BOOL:${ESCALATE}" \
  --parameter="original_transcript:STRING:${TRANSCRIPT_TEXT}" \
  --parameter="status:STRING:${STATUS}" \
  --parameter="log_message:STRING:${LOG_MESSAGE}" \
  "INSERT INTO \`${GOOGLE_CLOUD_PROJECT}.${DATASET_ID}.${TABLE_ID}\` 
   (call_id, date, customer, agent, product, issue, resolution, escalate, original_transcript, processed_at, status, log_message) 
   VALUES (
     @call_id,
     @date_val,
     @customer,
     @agent,
     @product,
     @issue,
     @resolution,
     @escalate,
     @original_transcript,
     CURRENT_TIMESTAMP(),
     @status,
     @log_message
   );"

echo "Done."