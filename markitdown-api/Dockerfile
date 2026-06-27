FROM python:3.13-slim-bullseye

ENV DEBIAN_FRONTEND=noninteractive
ENV EXIFTOOL_PATH=/usr/bin/exiftool
ENV FFMPEG_PATH=/usr/bin/ffmpeg

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    exiftool \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip --no-cache-dir install -r requirements.txt

COPY app/ ./app/
COPY tests/ ./tests/

RUN useradd -r -u 1001 -g root appuser && \
    chown -R appuser:root /app

USER 1001

EXPOSE 9100

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "9100"]
