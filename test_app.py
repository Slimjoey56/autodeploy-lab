"""Tests for the AutoDeploy Lab HTTP endpoints."""

import pytest

from app import create_app


@pytest.fixture()
def client():
    app = create_app({"TESTING": True})
    with app.test_client() as test_client:
        yield test_client


def test_index_returns_service_status(client):
    response = client.get("/")

    assert response.status_code == 200
    assert response.is_json
    assert response.get_json() == {
        "service": "AutoDeploy Lab",
        "status": "running",
    }


def test_health_check_returns_healthy_status(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.is_json
    assert response.get_json() == {"status": "healthy"}


def test_unknown_route_returns_not_found(client):
    response = client.get("/not-a-real-route")

    assert response.status_code == 404
