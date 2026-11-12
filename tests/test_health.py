from fastapi.testclient import TestClient
from unittest.mock import MagicMock

from app.main import app

client = TestClient(app)

def test_health_check():
    response = client.get("/health")

    assert response.status_code == 200

    data = response.json()

    assert data["status"] == "healthy"
    assert data["application"] == "NEXO"

def test_root():
    response = client.get("/")

    assert response.status_code == 200
    assert response.json()["message"] == "Conecta tu negocio."

def test_readiness_check(monkeypatch):
    mock_engine = MagicMock()

    monkeypatch.setattr(
        "app.main.engine",
        mock_engine,
    )

    response = client.get("/health/ready")

    assert response.status_code == 200

    data = response.json()

    assert data["status"] == "ready"
    assert data["application"] == "NEXO"
    assert data["database"] == "connected"

    mock_engine.connect.assert_called_once()

def test_readiness_check_database_unavailable(monkeypatch):
    mock_engine = MagicMock()

    mock_engine.connect.side_effect = Exception(
        "Database connection failed"
    )

    monkeypatch.setattr(
        "app.main.engine",
        mock_engine,
    )

    response = client.get("/health/ready")

    assert response.status_code == 503

    data = response.json()

    assert data["detail"]["status"] == "not_ready"
    assert data["detail"]["database"] == "disconnected"
