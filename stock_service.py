"""Lógica de dominio independiente de Flask para consultar cotizaciones."""

from __future__ import annotations

from datetime import date
import re

import pandas as pd
import yfinance as yf

TICKER_PATTERN = re.compile(r"^[A-Z0-9.^=-]{1,15}$")


class StockDataError(ValueError):
    """Error esperado de validación o consulta de datos bursátiles."""


def _parse_date(value: str, field: str) -> date:
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError) as exc:
        raise StockDataError(f"{field} debe usar el formato YYYY-MM-DD") from exc


def download_stock_data(ticker: str, start: str, end: str) -> dict:
    """Descarga precios y devuelve datos JSON serializables con un resumen."""
    symbol = ticker.strip().upper()
    if not TICKER_PATTERN.fullmatch(symbol):
        raise StockDataError("El símbolo bursátil no tiene un formato válido")

    start_date = _parse_date(start, "start")
    end_date = _parse_date(end, "end")
    if start_date >= end_date:
        raise StockDataError("start debe ser anterior a end")
    if end_date > date.today():
        raise StockDataError("end no puede ser posterior a hoy")
    if (end_date - start_date).days > 3650:
        raise StockDataError("El intervalo máximo permitido es de 10 años")

    try:
        frame = yf.download(
            symbol,
            start=start_date.isoformat(),
            end=end_date.isoformat(),
            auto_adjust=False,
            progress=False,
            timeout=15,
        )
    except Exception as exc:  # yfinance puede propagar distintos errores de red
        raise StockDataError("No fue posible consultar Yahoo Finance") from exc

    if frame.empty:
        raise StockDataError(f"No se encontraron datos para {symbol}")

    if isinstance(frame.columns, pd.MultiIndex):
        frame.columns = frame.columns.get_level_values(0)
    frame = frame.reset_index()
    rows = []
    for _, item in frame.tail(100).iterrows():
        rows.append(
            {
                "date": item["Date"].date().isoformat(),
                "open": _number(item.get("Open")),
                "high": _number(item.get("High")),
                "low": _number(item.get("Low")),
                "close": _number(item.get("Close")),
                "volume": int(item.get("Volume", 0)),
            }
        )

    closes = [row["close"] for row in rows if row["close"] is not None]
    return {
        "ticker": symbol,
        "start": start_date.isoformat(),
        "end": end_date.isoformat(),
        "records": rows,
        "summary": {
            "record_count": len(rows),
            "average_close": round(sum(closes) / len(closes), 4),
            "last_close": closes[-1],
        },
    }


def _number(value):
    return None if pd.isna(value) else round(float(value), 4)
