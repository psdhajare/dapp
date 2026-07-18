"""Selects an LLM provider from config/env. Add a provider = add a branch here."""

from __future__ import annotations

import os

from .base import LLMClient


def get_client(provider: str | None = None) -> LLMClient:
    provider = (provider or os.environ.get("LLM_PROVIDER") or "deepseek").lower()

    if provider == "deepseek":
        from .deepseek import DeepSeekClient

        return DeepSeekClient()

    raise ValueError(f"unknown LLM provider: {provider}")
