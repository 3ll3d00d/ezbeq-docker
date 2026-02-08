# Build stage: Used to prepare the application with all necessary tools and dependencies
# Using python:3.13-slim-trixie for linux/amd64 to support minidsp requiring glibc >= 2.32
FROM python:3.13-slim-trixie AS builder

# Set the working directory inside the container
WORKDIR /app

# Install dependencies required for building the application
RUN apt-get update && apt-get install --no-install-recommends -y \
    # Tools for compiling and building packages
    build-essential \
    # Utility for downloading files
    curl \
    # Python virtual environment creation tool
    python3-venv && \
    python -m pip install --upgrade pip  # Upgrade pip to the latest version

# Create a Python virtual environment at /opt/venv
RUN python -m venv /opt/venv

# Add the virtual environment to the PATH
ENV PATH="/opt/venv/bin:${PATH}"

# Copy the Python requirements file into the container
COPY requirements.txt ./

# Install the Python dependencies listed in requirements.txt
RUN pip install --pre --no-cache-dir -r requirements.txt

# Runtime stage: A clean, lightweight image for running the application
FROM python:3.13-slim-trixie

# Set the environment variable for ezbeq configuration
ENV EZBEQ_CONFIG_HOME=/config

# Copy the Python virtual environment prepared in the build stage
# This brings only the necessary runtime dependencies from the build stage.
COPY --from=builder /opt/venv /opt/venv

# Set the working directory inside the container
WORKDIR /app

# Define a volume for configuration data
VOLUME ["/config"]

# Add the virtual environment to the PATH
ENV PATH="/opt/venv/bin:${PATH}"

# Install runtime-only dependencies required by the application
RUN apt-get update && apt-get install --no-install-recommends -y \
    # Utility for downloading files
    curl \
    # SQLite database command-line tool
    sqlite3 \
    # minidsp binary is dynamically linked against libusb-1.0.so.0 and expects it to be available in the environment, even if the functionality it provides (USB communication) isn’t being used
    libusb-1.0-0

# Dynamically download and install the correct minidsp binary based on architecture
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
      amd64) ARCH="x86_64-unknown-linux-gnu" ;; \
      arm64) ARCH="aarch64-unknown-linux-gnu" ;; \
      armhf) ARCH="arm-linux-gnueabihf-rpi" ;; \
      *) echo "Unsupported architecture: $ARCH"; exit 1 ;; \
    esac && \
    URL="https://github.com/mrene/minidsp-rs/releases/latest/download/minidsp.${ARCH}.tar.gz" && \
    curl -L -o minidsp.${ARCH}.tar.gz "$URL" && \
    tar -xzf minidsp.${ARCH}.tar.gz && \
    mv minidsp /usr/local/bin/minidsp && \
    chmod +x /usr/local/bin/minidsp

# Create a non-root user and group for running the application
RUN groupadd -r ezbeq && useradd -r -g ezbeq ezbeq

# Set ownership for /app
RUN chown -R ezbeq:ezbeq /app

# Switch to the non-root user
USER ezbeq

# Define a health check for the application to verify it's running correctly
HEALTHCHECK --interval=10s --timeout=2s \
  CMD curl -f -s --show-error http://localhost:8080/api/1/version || exit 1

# Define the default command to run the ezbeq application
CMD [ "ezbeq" ]