# EAGLE EYE — single image: Flutter web build served by the FastAPI backend.
# NOTE: this Dockerfile was written but could not be built in the authoring environment
# (no Docker daemon). Build with:  docker compose up --build

# ---- stage 1: Flutter web build ----------------------------------------------------
FROM ghcr.io/cirruslabs/flutter:stable AS web
WORKDIR /src/frontend
COPY frontend/pubspec.yaml frontend/pubspec.lock ./
RUN flutter pub get
COPY frontend/ ./
RUN flutter build web --release --no-web-resources-cdn

# ---- stage 2: Python runtime ---------------------------------------------------------
FROM python:3.11-slim AS app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 curl unzip && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY backend/requirements.txt backend/requirements.txt
# CPU-only PyTorch wheels keep the image small; remove the index URL to use CUDA builds.
RUN pip install --extra-index-url https://download.pytorch.org/whl/cpu -r backend/requirements.txt
COPY backend/ backend/
COPY models/eagleeye-synth-v1.pt models/eagleeye-synth-v1.metrics.json models/
COPY scripts/ scripts/
COPY data/demo/ data/demo/
RUN ./scripts/setup_models.sh
COPY --from=web /src/frontend/build/web frontend/build/web
RUN useradd -r -u 10001 eagle && mkdir -p /data && chown -R eagle /data /app
USER eagle
ENV EAGLEEYE_DATA_DIR=/data HOME=/tmp
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s CMD curl -fs http://localhost:8000/api/v1/health || exit 1
WORKDIR /app/backend
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
