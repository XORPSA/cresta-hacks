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

class WeaviateConfig(BaseModel):
    url: str = Field(default_factory=lambda: os.getenv("WEAVIATE_URL"))
    api_key: str = Field(default_factory=lambda: os.getenv("WEAVIATE_API_KEY"))
    rest_endpoint: str = Field(default_factory=lambda: os.getenv("WEAVIATE_REST_ENDPOINT"))
    grpc_endpoint: str = Field(default_factory=lambda: os.getenv("WEAVIATE_GRPC_ENDPOINT"))

class Settings(BaseModel):
    openai_credentials: OpenAICredentials = Field(default_factory=OpenAICredentials)
    auth_config: AuthConfig = Field(default_factory=AuthConfig)
    weaviate_config: WeaviateConfig = Field(default_factory=WeaviateConfig)
