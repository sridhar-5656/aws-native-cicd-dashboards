import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


@pytest.fixture
def static_dir(tmp_path):
    (tmp_path / "assets").mkdir()
    (tmp_path / "index.html").write_text("<!doctype html><title>dash</title><div id=root></div>")
    (tmp_path / "favicon.svg").write_text("<svg xmlns='http://www.w3.org/2000/svg'/>")
    return tmp_path


@pytest.fixture
def make_client():
    clients = []

    def _make(**overrides):
        settings = Settings(**overrides)
        client = TestClient(create_app(settings), raise_server_exceptions=False)
        client.__enter__()  # runs lifespan startup
        clients.append(client)
        return client

    yield _make
    for c in clients:
        c.__exit__(None, None, None)


@pytest.fixture
def client(make_client, static_dir):
    return make_client(
        static_dir=static_dir, environment="test", git_commit="abcdef1234567",
        image_tag="abcdef1", build_time="2026-01-01T00:00:00Z", version="9.9.9",
    )
