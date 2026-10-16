# syntax=docker/dockerfile:1
# Base images come from the ECR Public mirror of Docker Official Images to avoid
# Docker Hub anonymous pull rate limits inside AWS CodeBuild.
ARG NODE_IMAGE=public.ecr.aws/docker/library/node:20-alpine
ARG PYTHON_IMAGE=public.ecr.aws/docker/library/python:3.12-slim

# ---- Stage 1: build the React frontend ---------------------------------------
FROM ${NODE_IMAGE} AS frontend-build
WORKDIR /build/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ ./
RUN npm run build

# ---- Stage 2: install Python dependencies into an isolated prefix ------------
FROM ${PYTHON_IMAGE} AS python-deps
WORKDIR /build
COPY backend/requirements.txt ./
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- Stage 3: minimal runtime image ------------------------------------------
FROM ${PYTHON_IMAGE} AS runtime

# Build metadata baked into the image (passed by CodeBuild with --build-arg).
ARG APP_GIT_COMMIT=""
ARG APP_IMAGE_TAG=""
ARG APP_BUILD_TIME=""

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080 \
    APP_REQUIRE_FRONTEND=true \
    APP_GIT_COMMIT=${APP_GIT_COMMIT} \
    APP_IMAGE_TAG=${APP_IMAGE_TAG} \
    APP_BUILD_TIME=${APP_BUILD_TIME}

RUN groupadd --system --gid 10001 app \
 && useradd  --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

# Same relative layout as the repository so config.py finds VERSION and frontend/dist.
WORKDIR /srv
COPY --from=python-deps /install /usr/local
COPY VERSION /srv/VERSION
COPY backend/app /srv/backend/app
COPY backend/gunicorn.conf.py /srv/backend/gunicorn.conf.py
COPY --from=frontend-build /build/frontend/dist /srv/frontend/dist

USER 10001:10001
EXPOSE 8080

# Docker-level check; ECS uses the equivalent healthCheck in the task definition.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["python", "-c", "import urllib.request as u; u.urlopen('http://127.0.0.1:8080/health/live', timeout=3)"]

CMD ["gunicorn", "--config", "/srv/backend/gunicorn.conf.py", "--chdir", "/srv/backend", "app.main:app"]
