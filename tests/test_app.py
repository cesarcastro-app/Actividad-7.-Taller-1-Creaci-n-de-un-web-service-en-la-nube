from unittest.mock import patch

import pytest

from app import create_app
from stock_service import StockDataError


@pytest.fixture()
def client():
    application = create_app()
    application.config.update(TESTING=True)
    return application.test_client()


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


@patch("app.download_stock_data")
def test_api_returns_stock_data(download, client):
    download.return_value = {"ticker": "GOOGL", "records": [], "summary": {}}
    response = client.get("/api/stocks/googl?start=2025-01-01&end=2025-01-10")
    assert response.status_code == 200
    assert response.get_json()["ticker"] == "GOOGL"


@patch("app.download_stock_data", side_effect=StockDataError("dato inválido"))
def test_api_reports_validation_errors(_download, client):
    response = client.get("/api/stocks/invalid")
    assert response.status_code == 400
    assert response.get_json() == {"error": "dato inválido"}
