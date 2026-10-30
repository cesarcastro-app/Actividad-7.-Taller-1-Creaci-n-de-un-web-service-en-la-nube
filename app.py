"""API HTTP para consultar históricos de acciones desde Yahoo Finance."""

from __future__ import annotations

import os
from datetime import date, timedelta

from flask import Flask, jsonify, render_template, request

from stock_service import StockDataError, download_stock_data


def create_app() -> Flask:
    """Construye la aplicación; usar una fábrica facilita pruebas y despliegue."""
    app = Flask(__name__)
    app.config["DEFAULT_TICKER"] = os.getenv("DEFAULT_TICKER", "GOOGL")

    @app.get("/health")
    def health():
        return jsonify(status="ok"), 200

    @app.get("/api/stocks/<ticker>")
    def stock_api(ticker: str):
        end = request.args.get("end", date.today().isoformat())
        start = request.args.get(
            "start", (date.today() - timedelta(days=30)).isoformat()
        )
        try:
            result = download_stock_data(ticker, start, end)
            return jsonify(result)
        except StockDataError as exc:
            return jsonify(error=str(exc)), 400

    @app.get("/")
    def index():
        ticker = request.args.get("ticker", app.config["DEFAULT_TICKER"])
        end = request.args.get("end", date.today().isoformat())
        start = request.args.get(
            "start", (date.today() - timedelta(days=30)).isoformat()
        )
        result = None
        error = None
        if request.args:
            try:
                result = download_stock_data(ticker, start, end)
            except StockDataError as exc:
                error = str(exc)
        return render_template(
            "index.html",
            ticker=ticker.upper(),
            start=start,
            end=end,
            result=result,
            error=error,
        )

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=False)
