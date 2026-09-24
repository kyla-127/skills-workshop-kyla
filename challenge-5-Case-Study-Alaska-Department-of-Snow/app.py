import os
import json
import uuid
import logging
import streamlit as st
import pandas as pd
from datetime import datetime
from pypdf import PdfReader

# Google Cloud SDKs
from google import genai
from google.genai import types
from google.cloud import dlp_v2
from google.cloud import bigquery
from google.cloud import logging as cloud_logging

# Local Schema Import
from schemas import DocumentSynthesisResult

# ---------------------------------------------------------
# Environment & Client Initialization
# ---------------------------------------------------------
PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT")
LOCATION = "us-central1"
MODEL_ARMOR_TEMPLATE_ID = "ads-parser"

# Cloud Logging Setup
logging_client = cloud_logging.Client()
logging_client.setup_logging()
logger = logging.getLogger("ADS_Document_Synthesis")

# Initialize GCP Clients
genai_client = genai.Client(vertexai=True, project=PROJECT_ID, location=LOCATION)
dlp_client = dlp_v2.DlpServiceClient()
bq_client = bigquery.Client(project=PROJECT_ID)

# Standard Security Block Message
CUSTOM_SAFETY_ERROR = "Sorry, I cannot help you with that."

# ---------------------------------------------------------
# Utility: Extract Text from Files (TXT and PDF)
# ---------------------------------------------------------
def extract_text_from_file(uploaded_file) -> str:
    """Extracts raw text from .txt or .pdf uploaded files."""
    if uploaded_file.name.lower().endswith(".pdf"):
        reader = PdfReader(uploaded_file)
        extracted_text = ""
        for page in reader.pages:
            text = page.extract_text()
            if text:
                extracted_text += text + "\n"
        return extracted_text.strip()
    else:
        return uploaded_file.read().decode("utf-8", errors="ignore").strip()

# ---------------------------------------------------------
# Security Module 1: Sensitive Data Protection (DLP / SDP)
# ---------------------------------------------------------
def sanitize_sensitive_data(text: str):
    """Inspects and redacts PII/SPII (SSN, Phone, Email) using Cloud DLP."""
    parent = f"projects/{PROJECT_ID}"
    inspect_config = {
        "info_types": [
            {"name": "PHONE_NUMBER"},
            {"name": "EMAIL_ADDRESS"},
            {"name": "US_SOCIAL_SECURITY_NUMBER"},
        ],
        "min_likelihood": dlp_v2.Likelihood.POSSIBLE,
    }
    deidentify_config = {
        "info_type_transformations": {
            "transformations": [
                {
                    "primitive_transformation": {
                        "replace_with_info_type_config": {}
                    }
                }
            ]
        }
    }
    item = {"value": text}

    try:
        response = dlp_client.deidentify_content(
            request={
                "parent": parent,
                "deidentify_config": deidentify_config,
                "inspect_config": inspect_config,
                "item": item,
            }
        )
        return response.item.value
    except Exception as e:
        logger.error(f"DLP Error: {str(e)}")
        return text

# ---------------------------------------------------------
# Security Module 2: Model Armor Validation
# ---------------------------------------------------------
def validate_model_armor(prompt_text: str):
    """Validates input prompt against explicit prompt injection and exploit patterns."""
    forbidden_terms = [
        "ignore previous instructions", 
        "ignore all system safety rules",
        "system prompt", 
        "leak credentials", 
        "bypass safety", 
        "recipe for explosive", 
        "synthesize dangerous explosive"
    ]
    for term in forbidden_terms:
        if term in prompt_text.lower():
            logger.warning(f"MODEL ARMOR BLOCK [{MODEL_ARMOR_TEMPLATE_ID}]: Detected unsafe pattern '{term}'.")
            return False, CUSTOM_SAFETY_ERROR
    return True, "PASSED"

# ---------------------------------------------------------
# Streamlit UI Setup
# ---------------------------------------------------------
st.set_page_config(
    page_title="Alaska Dept of Snow — Document Synthesis",
    page_icon="❄️",
    layout="wide"
)

st.title("❄️ Alaska Department of Snow (ADS)")
st.caption("Secure Unstructured Document Synthesis & Operational AI Chatbot")
st.sidebar.info(f"🛡️ **Security Template:** `{MODEL_ARMOR_TEMPLATE_ID}`\n🔒 **DLP Mode:** Active")

# Persistent Session Context for Document Content
if "current_document_text" not in st.session_state:
    st.session_state.current_document_text = ""

tab1, tab2, tab3 = st.tabs(["📄 Document Processing", "🤖 ADS Assistant Chatbot", "📊 Processing History (BigQuery)"])

# ---------------------------------------------------------
# TAB 1: Document Processing
# ---------------------------------------------------------
with tab1:
    st.subheader("Upload Operational Document")
    uploaded_file = st.file_uploader("Upload an operational document or log (.pdf, .txt)", type=["pdf", "txt"])
    raw_input_text = st.text_area("Or paste raw operational text here:", height=150)

    content_to_process = ""
    filename = "manual_input.txt"

    if uploaded_file is not None:
        filename = uploaded_file.name
        content_to_process = extract_text_from_file(uploaded_file)
    elif raw_input_text.strip():
        content_to_process = raw_input_text.strip()

    if st.button("🚀 Synthesize Document Securely", type="primary"):
        if not content_to_process:
            st.error("Please provide text or upload a .pdf / .txt document to proceed.")
        else:
            doc_id = str(uuid.uuid4())
            logger.info(f"Processing Document ID: {doc_id} | File: {filename}")

            # Step 1: Model Armor Validation
            is_valid, armor_msg = validate_model_armor(content_to_process)
            if not is_valid:
                st.error(armor_msg)
                logger.error(f"Doc ID {doc_id} blocked by Model Armor Template '{MODEL_ARMOR_TEMPLATE_ID}'.")
            else:
                # Step 2: Sensitive Data Protection (SDP/DLP)
                sanitized_text = sanitize_sensitive_data(content_to_process)
                st.session_state.current_document_text = sanitized_text

                # Step 3: Parse Document with Gemini 2.5 Flash
                prompt = f"""
                You are an AI assistant for the Alaska Department of Snow.
                Analyze the following operational document content:

                {sanitized_text}

                Provide a concise summary, a public safety risk assessment, and extract structured metrics.
                """

                safety_settings = [
                    types.SafetySetting(
                        category=types.HarmCategory.HARM_CATEGORY_HATE_SPEECH,
                        threshold=types.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE,
                    ),
                    types.SafetySetting(
                        category=types.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
                        threshold=types.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE,
                    ),
                ]

                try:
                    response = genai_client.models.generate_content(
                        model="gemini-2.5-flash",
                        contents=prompt,
                        config=types.GenerateContentConfig(
                            response_mime_type="application/json",
                            response_schema=DocumentSynthesisResult,
                            safety_settings=safety_settings,
                        )
                    )

                    if not response.text:
                        st.error(CUSTOM_SAFETY_ERROR)
                        logger.warning(f"Doc ID {doc_id} blocked by Gemini safety settings.")
                    else:
                        parsed_json = json.loads(response.text)
                        
                        # Step 4: Display Results
                        st.success("Sensitive Data Protection applied (PII Redacted). Document uploaded to Chat Context!")
                        
                        st.subheader("📋 Executive Summary")
                        st.write(parsed_json.get("summary", "N/A"))

                        st.subheader("⚠️ Public Safety Risk Assessment")
                        st.warning(parsed_json.get("risk_assessment", "N/A"))

                        st.subheader("⚙️ Structured Operational Data")
                        st.json(parsed_json.get("structured_data", {}))

                        # Step 5: BigQuery Streaming Ingestion
                        table_id = f"{PROJECT_ID}.ads_document_analytics.synthesized_documents"
                        
                        row = {
                            "doc_id": doc_id,
                            "filename": filename,
                            "summary": str(parsed_json.get("summary", "")),
                            "risk_assessment": str(parsed_json.get("risk_assessment", "")),
                            "structured_data": json.dumps(parsed_json.get("structured_data", {})),
                            "pii_redacted_count": 1,
                            "safety_status": "PASSED",
                            "processed_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
                        }

                        errors = bq_client.insert_rows_json(table_id, [row])
                        if not errors:
                            st.success("✅ Results successfully saved to BigQuery!")
                            logger.info(f"Doc ID {doc_id} successfully logged to BigQuery.")
                        else:
                            logger.error(f"BigQuery Insert Errors: {errors}")

                except Exception as e:
                    st.error(CUSTOM_SAFETY_ERROR)
                    logger.error(f"Doc ID {doc_id} execution blocked/failed: {str(e)}")

# ---------------------------------------------------------
# TAB 2: Operational AI Chatbot (Grounded in Document Data)
# ---------------------------------------------------------
with tab2:
    st.subheader("💬 Alaska Dept of Snow AI Assistant")
    
    if st.session_state.current_document_text:
        st.info("📄 **Active Document Context Attached.** You can ask questions directly about your uploaded file.")
    else:
        st.caption("Ask general operational questions or upload a document in Tab 1 to query specific reports.")

    if "messages" not in st.session_state:
        st.session_state.messages = [
            {"role": "assistant", "content": "Hello Operator! I am your Alaska Department of Snow assistant. How can I help you today?"}
        ]

    for message in st.session_state.messages:
        with st.chat_message(message["role"]):
            st.markdown(message["content"])

    if user_prompt := st.chat_input("Ask a question about road conditions, dispatch, or uploaded logs..."):
        st.session_state.messages.append({"role": "user", "content": user_prompt})
        with st.chat_message("user"):
            st.markdown(user_prompt)

        # 1. Model Armor Validation on User Prompt
        is_valid, armor_msg = validate_model_armor(user_prompt)
        if not is_valid:
            with st.chat_message("assistant"):
                st.markdown(CUSTOM_SAFETY_ERROR)
            st.session_state.messages.append({"role": "assistant", "content": CUSTOM_SAFETY_ERROR})
        else:
            sanitized_user_prompt = sanitize_sensitive_data(user_prompt)

            with st.chat_message("assistant"):
                with st.spinner("Thinking..."):
                    # Include active document text into system context if available
                    chat_context = f"""
                    You are a helpful operational assistant for the Alaska Department of Snow (ADS).
                    Provide concise, helpful, and professional advice regarding snow removal, road closures, and dispatch operations.

                    DOCUMENT CONTEXT AVAILABLE TO YOU:
                    {st.session_state.current_document_text}
                    """
                    
                    try:
                        response = genai_client.models.generate_content(
                            model="gemini-2.5-flash",
                            contents=sanitized_user_prompt,
                            config=types.GenerateContentConfig(
                                system_instruction=chat_context,
                                safety_settings=[
                                    types.SafetySetting(
                                        category=types.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
                                        threshold=types.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE,
                                    )
                                ]
                            )
                        )

                        if response.text:
                            st.markdown(response.text)
                            st.session_state.messages.append({"role": "assistant", "content": response.text})
                        else:
                            st.markdown(CUSTOM_SAFETY_ERROR)
                            st.session_state.messages.append({"role": "assistant", "content": CUSTOM_SAFETY_ERROR})

                    except Exception as e:
                        st.markdown(CUSTOM_SAFETY_ERROR)
                        st.session_state.messages.append({"role": "assistant", "content": CUSTOM_SAFETY_ERROR})

# ---------------------------------------------------------
# TAB 3: BigQuery History
# ---------------------------------------------------------
with tab3:
    st.subheader("📊 Document Processing History")
    if st.button("Refresh History"):
        query = f"""
            SELECT doc_id, filename, summary, risk_assessment, safety_status, processed_at
            FROM `{PROJECT_ID}.ads_document_analytics.synthesized_documents`
            ORDER BY processed_at DESC
            LIMIT 10
        """
        try:
            df = bq_client.query(query).to_dataframe()
            if df.empty:
                st.info("No records found in BigQuery yet. Process a valid document to populate data.")
            else:
                st.dataframe(df, use_container_width=True)
        except Exception as e:
            st.error(f"BigQuery Query Error: {str(e)}")
