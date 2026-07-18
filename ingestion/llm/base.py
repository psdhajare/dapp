"""Provider-agnostic LLM interface. No provider SDK may leak past this boundary."""

from __future__ import annotations

from abc import ABC, abstractmethod


class LLMClient(ABC):
    """Minimal contract every provider impl must satisfy.

    complete() takes a system + user prompt and returns the raw text response.
    Callers (e.g. extraction) are responsible for parsing/validating that text;
    they must not know which provider produced it.
    """

    @abstractmethod
    def complete(self, system: str, user: str) -> str:
        ...
