"""Gunicorn settings for the container (Gunicorn process manager + Uvicorn workers)."""
import os

bind = f"0.0.0.0:{os.getenv('PORT', '8080')}"
worker_class = "uvicorn_worker.UvicornWorker"
workers = int(os.getenv("WEB_CONCURRENCY", "2"))
# ALB idle timeout is 60s by default; keep-alive must be longer to avoid 502s.
keepalive = 75
timeout = 30
graceful_timeout = 30
worker_tmp_dir = "/dev/shm"
# The application emits its own structured request logs.
accesslog = None
errorlog = "-"
loglevel = os.getenv("GUNICORN_LOG_LEVEL", "info")
