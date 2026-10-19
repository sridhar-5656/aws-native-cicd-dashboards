from datetime import datetime


def test_health_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
    datetime.fromisoformat(r.json()["timestamp"])


def test_liveness(client):
    r = client.get("/health/live")
    assert r.status_code == 200
    assert r.json()["status"] == "alive"


def test_readiness_ready(client):
    r = client.get("/health/ready")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ready"
    assert body["checks"]["startup_complete"] is True


def test_readiness_fails_when_frontend_required_but_missing(make_client, tmp_path):
    c = make_client(static_dir=tmp_path / "missing", require_frontend=True)
    assert c.get("/health/live").status_code == 200  # liveness unaffected
    r = c.get("/health/ready")
    assert r.status_code == 503
    assert r.json()["status"] == "not_ready"
    assert r.json()["checks"]["frontend_assets"] is False


def test_readiness_not_ready_when_startup_incomplete(client):
    client.app.state.runtime.startup_complete = False
    assert client.get("/health/ready").status_code == 503
    assert client.get("/health/live").status_code == 200


def test_readiness_not_ready_when_shutting_down(client):
    client.app.state.runtime.shutting_down = True
    assert client.get("/health/ready").status_code == 503
