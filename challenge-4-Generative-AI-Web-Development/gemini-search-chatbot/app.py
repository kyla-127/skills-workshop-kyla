import os
import chainlit as cl
from google import genai
from google.genai import types

# Initialize the Gemini client
PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT")
client = genai.Client(vertexai=True, project=PROJECT_ID, location="us-central1")

@cl.on_chat_start
async def on_chat_start():
    # Store session-level chat history
    cl.user_session.set("messages", [])
    await cl.Message(
        content="👋 Hello! I am your AI assistant powered by Gemini 2.5 with **Google Search Grounding**. Ask me anything!"
    ).send()

@cl.on_message
async def on_message(message: cl.Message):
    # Retrieve user session history
    messages = cl.user_session.get("messages")
    messages.append({"role": "user", "parts": [{"text": message.content}]})

    msg = cl.Message(content="")
    await msg.send()

    try:
        # Call Gemini 2.5 with Google Search tool enabled
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=messages,
            config=types.GenerateContentConfig(
                tools=[types.Tool(google_search=types.GoogleSearch())]
            ),
        )

        reply_text = response.text or "I couldn't generate a response."
        
        # Stream response back to Chainlit UI
        msg.content = reply_text
        await msg.update()

        # Update chat session history
        messages.append({"role": "model", "parts": [{"text": reply_text}]})
        cl.user_session.set("messages", messages)

    except Exception as e:
        msg.content = f"❌ **Error:** {str(e)}"
        await msg.update()
