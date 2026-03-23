# syntax=docker/dockerfile:1
#
# Multi-stage build with three targets:
#
#   base        – shared OS packages + minidsp binary (not used directly)
#   production  – default; pip-installs from requirements.txt into a venv,
#                 runs as a non-root user.  Built by CI / docker buildx bake.
#   dev         – local development; builds from a Poetry source tree with the
#                 React UI compiled via Node/Yarn.  Used by bin/run-local via
#                 docker-compose.local.yaml.

# ── Base: runtime OS + minidsp binary ────────────────────────────────────────
# Shared by both the production and dev build targets.
# python:3.13-slim-trixie — Debian 13 (stable), native Python 3.13, glibc 2.40
FROM python:3.13-slim-trixie AS base

# Set the environment variable for ezbeq configuration
ENV EZBEQ_CONFIG_HOME=/config

# Install runtime-only dependencies required by the application
RUN apt-get update && apt-get install --no-install-recommends -y \
    # Utility for downloading files
    curl \
    # SQLite database command-line tool
    sqlite3 \
    # minidsp is dynamically linked against libusb-1.0.so.0 and expects it to be
    # available in the environment, even if USB communication isn't being used
    libusb-1.0-0 && \
    rm -rf /var/lib/apt/lists/*

# Dynamically download and install the correct minidsp binary based on architecture
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
      amd64) ARCH="x86_64-unknown-linux-gnu" ;; \
      arm64) ARCH="aarch64-unknown-linux-gnu" ;; \
      armhf) ARCH="arm-linux-gnueabihf-rpi" ;; \
      *) echo "Unsupported architecture: $ARCH"; exit 1 ;; \
    esac && \
    URL="https://github.com/mrene/minidsp-rs/releases/latest/download/minidsp.${ARCH}.tar.gz" && \
    curl -L -o minidsp.tar.gz "$URL" && \
    tar -xzf minidsp.tar.gz && \
    mv minidsp /usr/local/bin/minidsp && \
    chmod +x /usr/local/bin/minidsp && \
    rm minidsp.tar.gz

# Set the working directory inside the container
WORKDIR /app

# Define a volume for configuration data
VOLUME ["/config"]

EXPOSE 9968

# Default health check uses port 9968 (the ezbeq default).
# Override this in your docker-compose file if you use a different port:
#   healthcheck:
#     test: ["CMD-SHELL", "curl -f -s http://localhost:YOUR_PORT/api/1/version || exit 1"]
HEALTHCHECK --interval=10s --timeout=2s \
  CMD curl -f -s http://localhost:9968/api/1/version || exit 1

# ── Production builder: install Python deps into a venv ──────────────────────
# Separate stage so build tools don't end up in the final runtime image.
FROM base AS builder

# Install dependencies required for building the application
RUN apt-get update && apt-get install --no-install-recommends -y \
    # Tools for compiling and building packages
    build-essential \
    # Python virtual environment creation tool
    python3-venv && \
    python -m pip install --upgrade pip && \
    rm -rf /var/lib/apt/lists/*

# Create a Python virtual environment at /opt/venv
RUN python -m venv /opt/venv

# Add the virtual environment to the PATH
ENV PATH="/opt/venv/bin:${PATH}"

# Copy the Python requirements file into the container
COPY requirements.txt ./

# Install the Python dependencies listed in requirements.txt
RUN pip install --pre --no-cache-dir -r requirements.txt

# ── Production: clean runtime image ──────────────────────────────────────────
# A clean, lightweight image for running the application.
FROM base AS production

# Copy the Python virtual environment prepared in the build stage.
# This brings only the necessary runtime dependencies, without build tools.
COPY --from=builder /opt/venv /opt/venv

# Add the virtual environment to the PATH
ENV PATH="/opt/venv/bin:${PATH}"

# Create a non-root user and group for running the application
RUN groupadd -r ezbeq && useradd -r -g ezbeq ezbeq && \
    chown -R ezbeq:ezbeq /app

# Switch to the non-root user
USER ezbeq

# Define the default command to run the ezbeq application
CMD ["ezbeq"]

# ── Dev: local source build with Poetry + Node/Yarn ──────────────────────────
# Build context is the local ezbeq source tree (set by docker-compose.local.yaml).
# BuildKit cache mounts keep Yarn and Poetry package caches on the host so
# only changed layers are rebuilt when source files change.
FROM base AS dev

# Add Node.js, Yarn (via corepack) and build tools needed for UI compilation and Poetry
RUN apt-get update && apt-get install --no-install-recommends -y \
    # Tools for compiling and building packages
    build-essential \
    # Python virtual environment creation tool
    python3-venv && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install --no-install-recommends -y nodejs && \
    corepack enable yarn && \
    rm -rf /var/lib/apt/lists/*

# Install Poetry
# Cache pip across builds so Poetry itself isn't re-downloaded every time
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install poetry

# Keep the virtualenv inside the project directory (/app/.venv) so it ends up
# in the image layer.  Without this, Poetry stores the venv under its cache dir
# (~/.cache/pypoetry/virtualenvs/) which is a cache mount — not persisted in
# the image — so the container starts with no installed packages.
RUN poetry config virtualenvs.in-project true

# Install Python deps (without the app itself yet — better layer caching,
# this step only reruns when pyproject.toml or poetry.lock changes).
# Only the download cache is mounted (not the virtualenvs dir).
COPY pyproject.toml poetry.lock ./
RUN --mount=type=cache,target=/root/.cache/pypoetry/cache \
    poetry install --no-root

# Build the React UI into ezbeq/ui/
# Cache the Yarn package cache across builds — node_modules is still rebuilt
# inside the image layer, but packages are fetched from the host cache.
# This step only reruns when ui/ files change.
COPY ui/ ./ui/
RUN --mount=type=cache,target=/root/.yarn/berry/cache \
    cd ui && yarn install --silent && yarn build

# Copy the full source and install the app entry point
COPY . .
RUN --mount=type=cache,target=/root/.cache/pypoetry/cache \
    poetry install

# Define the default command to run the ezbeq application via Poetry
CMD ["poetry", "run", "ezbeq"]
