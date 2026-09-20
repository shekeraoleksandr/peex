# Custom container image for the PeEx demo app.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    APP_MESSAGE="Hello from PeEx" \
    APP_ENV="dev" \
    APP_VERSION="1.0.0"

WORKDIR /app
COPY app/app.py /app/app.py

# Run as a non-root user (least privilege)
RUN useradd --system --no-create-home --shell /usr/sbin/nologin appuser
USER appuser

EXPOSE 8080

# Container-native health check (observability)
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz').status==200 else 1)" || exit 1

CMD ["python", "/app/app.py"]
