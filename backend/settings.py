import os
import json
from pydantic import BaseModel, Field

class OpenAICredentials(BaseModel):
    apiKey: str = Field(default_factory=lambda: os.getenv("OPENAI_API_KEY"))

class AuthConfig(BaseModel):
    jwt_secret: str = Field(default_factory=lambda: os.getenv("JWT_SECRET_API"))
    config_service_addr: str = Field(default_factory=lambda: os.getenv("CONFIG_SERVICE_ADDR"))
    config_use_secure_channel: bool = Field(
        default_factory=lambda: os.getenv("CONFIG_USE_SECURE_CHANNEL", "false").lower() == "true"
    )

class Settings(BaseModel):
    openai_credentials: OpenAICredentials = Field(default_factory=OpenAICredentials)
    auth_config: AuthConfig = Field(default_factory=AuthConfig)

