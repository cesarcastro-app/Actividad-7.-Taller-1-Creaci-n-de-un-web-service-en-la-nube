# Imagen pequeña, con versión explícita para que la construcción sea reproducible.
FROM python:3.13.9-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Se instala primero la lista de dependencias para aprovechar la caché de capas.
COPY requirements.txt .
RUN pip install --no-cache-dir --requirement requirements.txt \
    && addgroup --system app \
    && adduser --system --ingroup app --no-create-home app

COPY --chown=app:app app.py stock_service.py ./
COPY --chown=app:app templates ./templates

USER app
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)" || exit 1

# La aplicación no usa el canal administrativo local de Gunicorn 26; se desactiva
# para conservar el sistema de archivos sin permisos de escritura innecesarios.
CMD ["gunicorn", "--bind=0.0.0.0:8000", "--workers=2", "--threads=2", "--timeout=30", "--no-control-socket", "app:app"]
