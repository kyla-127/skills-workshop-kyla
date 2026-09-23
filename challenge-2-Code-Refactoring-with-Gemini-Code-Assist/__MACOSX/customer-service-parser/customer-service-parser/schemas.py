from pydantic import BaseModel, Field
from typing import Optional

class TranscriptAnalysis(BaseModel):
    call_id: Optional[str] = Field(description="Unique call or interaction identifier")
    date: Optional[str] = Field(description="Date of the interaction (YYYY-MM-DD format if possible)")
    customer: Optional[str] = Field(description="Name or ID of the customer")
    agent: Optional[str] = Field(description="Name or ID of the customer service agent")
    product: Optional[str] = Field(description="Product or service being discussed")
    issue: Optional[str] = Field(description="Detailed summary of the customer's issue")
    resolution: Optional[str] = Field(description="Resolution or next steps agreed upon")
    escalate: bool = Field(description="True if the issue requires escalation or further manager review, False otherwise")