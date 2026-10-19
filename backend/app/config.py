"""Application configuration.

Everything is read from environment variables (prefix ``APP_``). The application
version has a single source of truth: the ``VERSION`` file at the repository root
(copied to ``/srv/VERSION`` in the container). ``APP_VERSION`` may override it.
"""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Optional

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

# repo layout : <root>/backend/app/config.py  -> parents[2] == <root>
# image layout: /srv/backend/app/config.py    -> parents[2] == /srv
ROOT_DIR = Path(__file__).resolve().parents[2]


def _read_version_file() -> str:
    try:
        return (ROOT_DIR / "VERSION").read_text(encoding="utf-8").strip() or "0.0.0"
    except OSError:
        return "0.0.0"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="APP_", extra="ignore")

    name: str = "DevOps Deployment Dashboard"
    version: str = Field(default_factory=_read_version_file)
    environment: str = "local"
    log_level: str = "INFO"

    # Build / deployment metadata. All optional: when absent the API reports null
    # and the UI shows "Unavailable" instead of inventing a value.
    git_commit: Optional[str] = None
    image_tag: Optional[str] = None
    build_time: Optional[str] = None
    release_id: Optional[str] = None

    static_dir: Path = ROOT_DIR / "frontend" / "dist"
    require_frontend: bool = False
    enable_docs: bool = False

    @property
    def effective_release_id(self) -> str:
        if self.release_id:
            return self.release_id
        if self.git_commit:
            return f"{self.version}+{self.git_commit[:7]}"
        return self.version


@lru_cache
def get_settings() -> Settings:
    return Settings()
