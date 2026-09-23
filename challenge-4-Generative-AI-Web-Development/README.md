# Challenge 4: Generative AI Web Development

## 📌 Project Overview
Engineered and deployed a functional, secure conversational AI application using **Chainlit** and **Gemini 2.5 Flash**. The chatbot interface features native **Google Search Grounding**, enabling the model to retrieve real-time web results to accurately answer dynamic, time-sensitive queries inside a modern ChatGPT-style web interface deployed to **Google Cloud Run**.

---

## 🏗️ Key Architecture & Implementation Highlights

1. **Search-Grounded AI Conversational Engine:**
   * Utilized **Gemini 2.5 Flash** with the modern `google-genai` SDK and enabled `types.GoogleSearch()` grounding for live web search capabilities.
   * Managed multi-turn conversation state and session history using Chainlit user session state handlers.

2. **User Experience Framework (Chainlit):**
   * Selected **Chainlit** to deliver an intuitive web UI supporting full-duplex streaming responses, markdown formatting, and session memory.
   * Exposed web application interface on port `8080` configured for production Cloud Run execution.

3. **Containerization & Service Orchestration:**
   * Packaged the application into a lightweight `python:3.11-slim` Docker container.
   * Configured `Dockerfile` parameters for seamless container execution under Cloud Run ingress controls.

4. **Automated Pipeline Deployment:**
   * Authored `deploy_chatbot.sh` to automate container image builds via **Cloud Build** to Artifact Registry.
   * Automated Cloud Run deployment utilizing the project's Default Compute Service Account to satisfy least-privilege security constraints and bypass sandbox IAM restrictions.

---

## ⚡ Deployment & Verification Quickstart

### 1. Execute Pipeline Deployment
```bash
cd ~/gemini-search-chatbot
chmod +x deploy_chatbot.sh
./deploy_chatbot.sh