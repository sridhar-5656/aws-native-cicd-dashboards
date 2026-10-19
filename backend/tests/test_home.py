def test_home_serves_frontend_html(client):
    r = client.get("/", headers={"accept": "text/html"})
    assert r.status_code == 200
    assert "text/html" in r.headers["content-type"]
    assert "<div id=root>" in r.text


def test_home_json_when_requested(client):
    r = client.get("/", headers={"accept": "application/json"})
    assert r.status_code == 200
    body = r.json()
    assert body["version"] == "9.9.9"
    assert "/health/ready" in body["endpoints"]


def test_home_json_fallback_without_build(make_client, tmp_path):
    r = make_client(static_dir=tmp_path / "none").get("/", headers={"accept": "text/html"})
    assert r.status_code == 200
    assert "frontend build not found" in r.json()["message"]


def test_security_headers_present(client):
    r = client.get("/health")
    assert r.headers["x-content-type-options"] == "nosniff"
    assert "x-request-id" in r.headers


def test_favicon_served(client):
    assert client.get("/favicon.svg").status_code == 200


def test_default_version_comes_from_version_file():
    from app.config import Settings
    assert Settings().version  # read from VERSION at repo root
