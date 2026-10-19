def test_info_metadata(client):
    body = client.get("/api/info").json()
    assert body["name"] == "DevOps Deployment Dashboard"
    assert body["version"] == "9.9.9"
    assert body["environment"] == "test"
    assert body["git_commit"] == "abcdef1234567"
    assert body["image_tag"] == "abcdef1"
    assert body["release_id"] == "9.9.9+abcdef1"
    assert "pipeline_execution_status" in body["unavailable"]


def test_info_missing_metadata_is_null_not_invented(make_client, tmp_path):
    body = make_client(static_dir=tmp_path).get("/api/info").json()
    assert body["git_commit"] is None
    assert body["image_tag"] is None
    assert body["build_time"] is None


def test_info_does_not_leak_environment(client, monkeypatch):
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "super-secret-value")
    assert "super-secret-value" not in client.get("/api/info").text


def test_status_ok(client):
    r = client.get("/api/status")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["uptime_seconds"] >= 0
    assert body["checks"]["frontend_assets"] is True


def test_status_without_checks(client):
    assert client.get("/api/status?include_checks=false").json()["checks"] is None


def test_status_invalid_query_returns_422_json(client):
    r = client.get("/api/status?include_checks=maybe")
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "validation_error"


def test_unknown_route_returns_json_404(client):
    r = client.get("/api/nope")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "not_found"


def test_wrong_method_returns_405_json(client):
    r = client.post("/health")
    assert r.status_code == 405
    assert r.json()["error"]["code"] == "method_not_allowed"


def test_unhandled_exception_is_sanitized(client):
    @client.app.get("/boom")
    def boom():
        raise RuntimeError("database password is hunter2")

    r = client.get("/boom")
    assert r.status_code == 500
    assert "hunter2" not in r.text
    assert r.json()["error"]["code"] == "internal_error"
