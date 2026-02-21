# RAGflow Development Container — macOS (i9)

A containerised RAGflow development environment designed to run on macOS with an Intel i9 processor. The setup wraps RAGflow and all of its backing services in Docker, managed through a small set of shell scripts accessible system-wide via `/usr/local/bin`.

---

## Overview

[RAGflow](https://github.com/infiniflow/ragflow) is an open-source RAG (Retrieval-Augmented Generation) engine. Running it in a container isolates its many dependencies (Elasticsearch, MySQL, Redis, MinIO) from the host machine and lets you bring the full stack up or down with a single command from any directory.

The app container is built on **Debian Bookworm Slim**, keeping the base image lean while remaining compatible with RAGflow's Python and native library requirements.

---

## Architecture

```
macOS Host (i9)
└── Docker Desktop
    ├── ragflow_app          ← Debian bookworm-slim + RAGflow (your workspace)
    ├── ragflow-elasticsearch-1   ← Search & vector index backend
    ├── ragflow-mysql-1           ← Relational metadata store
    ├── ragflow-redis-1           ← Cache & task queue
    └── ragflow-minio-1           ← Object storage (documents, models)
```

All services communicate over an isolated Docker network (`ragflow_default`). Only the RAGflow app ports are exposed to the host — backing services are intentionally kept internal.

### Exposed Ports

| Port | Service |
|------|---------|
| `80` | RAGflow HTTP |
| `443` | RAGflow HTTPS |
| `9380` | RAGflow API |

---

## Prerequisites

- macOS with Docker Desktop installed
- Intel i9 processor (the scripts detect physical CPU count via `sysctl`)
- SSH key at `~/.ssh/id_rsa` (mounted read-only into the container)
- `~/.gitconfig` present on the host

---

## Project Structure

```
ragflow-docker/
├── Dockerfile              # Debian-based RAGflow image
├── docker-compose.yaml     # Backing services (ES, MySQL, Redis, MinIO)
├── run.sh                  # Build, start, and attach to the dev container
├── docker-down.sh          # Gracefully stop all services
└── config/                 # Project config mounted into /workspace/config
```

---


## Building the Image

The Dockerfile uses a **multi-stage build** — a dedicated Node stage compiles the React frontend in isolation before the main Debian image is assembled. This separation is necessary because RAGflow's frontend (11k+ modules) requires more memory than Docker Desktop allocates by default.

### 1. Configure Docker Desktop memory

Before building, open **Docker Desktop → Settings → Resources → Advanced** and set:

| Setting | Required value |
|---------|---------------|
| Memory  | **12 GB** minimum |
| Swap    | **4 GB** minimum |

Click **Apply & Restart**. The build will be killed by the OS OOM killer with exit code 134 if memory is insufficient — the symptom is a `FATAL ERROR: Ineffective mark-compacts near heap limit` message followed by `Killed`.

> **Why so much?** The Vite bundler peaks at ~2.5 GB of heap during the frontend build. The Python dependency install in the main stage requires additional memory concurrently. With 12 GB allocated, both stages have comfortable headroom and 4 GB of swap provides a safety net against transient spikes.

### 2. Build the image

```bash
./build.sh
```

The build clones RAGflow from GitHub, installs all Python dependencies via `uv`, and compiles the React frontend. Expect **10–20 minutes** on first build; subsequent builds are fast due to Docker layer caching.

### Known build quirks on macOS

The following issues were encountered building on macOS with an Intel i9 and have been handled in the Dockerfile — they are documented here for reference.

**Node.js heap exhaustion** — `npm run build` OOMs inside a single-stage Dockerfile because the Node build and Python deps compete for the same memory budget. Resolved by isolating the frontend into a separate builder stage (`FROM node:20-slim AS frontend-builder`) so it has the full memory allocation to itself, with `NODE_OPTIONS=--max-old-space-size=4096`.

**TLS failure in the Node builder stage** — `node:20-slim` ships without `ca-certificates`, causing `git clone` to fail with `server certificate verification failed`. Resolved by installing `ca-certificates` before the clone step.

**Missing `docs/` directory** — Vite imports `docs/references/http_api_reference.md` as a raw asset at build time. The sparse checkout must include both `web` and `docs` or the build exits with `ENOENT`.

**macOS UID below Debian's `UID_MIN`** — macOS assigns user UIDs starting at 501, but Debian's `/etc/login.defs` rejects UIDs below 1000 by default, causing `useradd` to fail. Resolved by lowering `UID_MIN` and `GID_MIN` to 100 in `login.defs` before creating the user.

**GID collision with system groups** — macOS GID 20 (`staff`) conflicts with Debian's GID 20 (`dialout`). `groupadd` refuses to reuse an existing GID without `--non-unique`, and silently fails (swallowed by `|| true`), leaving no named group for `chown`. Resolved by passing `--non-unique` to `groupadd` and using numeric `UID:GID` in `chown` rather than the group name.

---
## Installation

Clone the repository and create the system-wide command links:

```bash
git clone <your-repo-url> ragflow-docker
cd ragflow-docker

chmod +x run.sh docker-down.sh

sudo ln -s "$(pwd)/run.sh"          /usr/local/bin/ragflow-run
sudo ln -s "$(pwd)/docker-down.sh"  /usr/local/bin/ragflow-down
```

---

## Usage

### Start the environment

```bash
ragflow-run
```

Run this from **any directory**. The directory you invoke it from is mounted as `/workspace` inside the container, so your current project is immediately available. Backing services that are already running are left untouched.

### Stop the environment

```bash
ragflow-down
```

Removes all containers and the Docker network. Named volumes (your ES indices, MySQL data, MinIO objects) are **preserved** so data survives across restarts.

### Wipe all data (clean slate)

```bash
cd ~/path/to/ragflow-docker
docker compose down -v
```

The `-v` flag removes volumes in addition to containers. Use this only when you want to reset RAGflow's state entirely.

---

## How It Works

### `run.sh`

1. Captures the **caller's working directory** (`CALLER_DIR`) before changing into the script's own directory — this is what gets mounted as `/workspace`.
2. Changes into the `ragflow-docker/` directory so Docker Compose can find `docker-compose.yaml`.
3. Sets `COMPOSE_PROJECT_NAME=ragflow` so all resources are consistently namespaced regardless of the folder name on disk.
4. Runs `docker compose down` to cleanly remove any previously stopped containers (preventing port allocation conflicts on restart).
5. Starts backing services (`elasticsearch`, `mysql`, `redis`, `minio`) via Compose.
6. Checks whether the app container already exists — creates it if not, starts it if so.
7. Attaches an interactive shell (`docker exec -it ... /bin/bash`).

### `docker-down.sh`

Navigates to its own directory, sets the project name, and runs `docker compose down`. Scoped strictly to the `ragflow` project — no other Docker Compose projects on your machine are affected.

### Volume strategy

| Volume | Contents | Survives `down` | Survives `down -v` |
|--------|----------|-----------------|-------------------|
| `ragflow_es_data` | Elasticsearch indices | ✅ | ❌ |
| `ragflow_mysql_data` | RAGflow metadata | ✅ | ❌ |
| `ragflow_redis_data` | Cache / queues | ✅ | ❌ |
| `ragflow_minio_data` | Uploaded documents | ✅ | ❌ |

---

## Features

- **Invoke from anywhere** — `ragflow-run` mounts whichever directory you're in as `/workspace`, so you never need to `cd` into the project first.
- **Idempotent startup** — re-running `ragflow-run` is safe; it tears down stale containers cleanly before recreating them without touching persistent data.
- **Scoped teardown** — `ragflow-down` only affects the ragflow project; unrelated Compose stacks on the same machine are untouched.
- **Host identity passthrough** — your `~/.gitconfig` and `~/.ssh/id_rsa` are mounted read-only so Git and SSH work inside the container as they do on your Mac.
- **Shared config** — `ragflow-docker/config/` is always available at `/workspace/config` regardless of which directory you launched from.
- **CPU-aware** — container is allocated all physical cores minus one (`sysctl hw.physicalcpu - 1`), leaving one core free for macOS.
- **Privileged capabilities** — `--cap-add=ALL`, `--cap-add=sys_nice`, and `--ulimit rtprio=99` are set for workloads that require elevated scheduling priority.
- **Debian base** — `debian:bookworm-slim` keeps the image minimal while providing full `apt` access for adding tools as needed.

---

## macOS Notes

- `--cpuset-cpus` is passed but **has no effect on macOS** — Docker Desktop does not expose host CPU topology to containers. It is kept for forward compatibility if the stack is ever moved to a Linux host.
- GPU / Metal acceleration is not available inside Docker containers on macOS. For LLM inference acceleration, run [Ollama](https://ollama.com) on the host and point RAGflow at `host.docker.internal`.
- MinIO and Elasticsearch ports are **not** bound to the host to avoid conflicts with other local services. If you need direct host access (e.g. for the MinIO console), temporarily re-enable the relevant `ports:` entries in `docker-compose.yaml`.
