"""Model-agnostic LLM layer. Business logic depends only on LLMClient."""

from .base import LLMClient
from .factory import get_client

__all__ = ["LLMClient", "get_client"]
