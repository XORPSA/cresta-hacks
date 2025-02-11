import os
from pydantic import BaseModel, Field

class OpenAICredentials(BaseModel):
    apiKey: str = Field(default_factor=lambda: os.getenv("OPENAI_API_KEY"))

class Settings(BaseModel):
    openai_credentials: OpenAICredentials = Field(default_factory=OpenAICredentials)
