# ezbeq-jr

Creates and publishes an image for [ezBEQ](https://github.com/3ll3d00d/ezbeq) to github packages, for use with [JRiver Media Center](https://www.jriver.com), or any ezBEQ client that uses the [MiniDSP-RS](https://github.com/mrene/minidsp-rs) project.

> [!NOTE]
> ⚠ This image has not been tested with USB connected devices.
> There are instructions on how to mount USB devices, from another legacy docker image project:
> - [General docker discussion](https://github.com/jmery/ezbeq-docker/tree/ef3f954f37b1b420e31635a699bfbb864e861ad9?tab=readme-ov-file#general-linux-docker-instructions)
> - [Synology NAS discussion](https://github.com/jmery/ezbeq-docker/tree/ef3f954f37b1b420e31635a699bfbb864e861ad9?tab=readme-ov-file#general-linux-docker-instructions)
>  - [Higher privileges discussion](https://github.com/jmery/ezbeq-docker/tree/ef3f954f37b1b420e31635a699bfbb864e861ad9?tab=readme-ov-file#note-on-execute-container-using-high-privilege)

## Setup

- Expects a volume mapped to `/config `to allow user supplied `ezbeq.yml`

Example docker compose file for your reference: [docker-compose.yaml](./docker-compose.yaml)

## FAQ

> Why is it called `-jr`?
 
JR stands for [JRiver Media Center](https://www.jriver.com)

> Does this docker image work for [MiniDSP](https://www.minidsp.com) devices?

Yes.

> Does this build and publish an image for every ezBEQ release?

Yes, see https://github.com/3ll3d00d/ezbeq/blob/main/.github/workflows/create-app.yaml#L108

> Why is this not mentioned in the ezBEQ readme?

It is, in the [Docker section](https://github.com/3ll3d00d/ezbeq?tab=readme-ov-file#docker).


> What architectures are supported?

The docker image get's built to target:

- `linux/amd64`
- `linux/arm64`

---

## Running a local branch

To test a local ezbeq source tree (e.g. an unreleased branch) without
publishing an image:

**1. Copy `.env.example` to `.env` and fill in `EZBEQ_SRC`:**

```bash
cp .env.example .env
# edit .env — at minimum set EZBEQ_SRC to your local ezbeq checkout
```

**2. Run it:**

```bash
bin/run-local            # build image and start (detached)
bin/run-local --logs     # start and follow logs
bin/run-local --rebuild  # force a full image rebuild
bin/run-local --stop     # stop and remove the container
```

The script mounts your real `ezbeq.yml` config (defaults to `~/.ezbeq/ezbeq.yml`;
override with `EZBEQ_CONFIG` in `.env`). Device connection details (TCP address
etc.) come from the config file as usual — no extra network configuration needed.

The image is built from `Dockerfile.dev` in the ezbeq source tree, which
compiles the React UI and downloads the minidsp binary, so it behaves
identically to the published image.

---

## Developer Documentation

### Multi Platform Docker Image

Build for two architectures in parallel, push:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t <HUB USERNAME>/ezbeq-jr:latest \
  --push .
```

#### Setup

Requires Docker's `buildx` setup:

- `docker buildx create --use`
- `docker buildx inspect --bootstrap`